# Kubernetes Production Environment

This details the steps I followed to create a highly-available Kubernetes cluster suitable for production environments.<br>
It is a work in progress. Not suitable for production (yet).

## Hyper-V Setup

Networking in hyper-v is weird. Read this:<br>
https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/user-guide/setup-nat-network

I have a feeling it's suboptimal but since the hyper-v environment is not related to a kubernetes production environment it's good enough for me.

## Private DNS for hosts

We want each host to have its own routable FQDN within the LAN. We also need a FQDN for the loadbalancer virtual IP (see the kube-vip section below).<br>
We'll make a compromise on high-availability for the DNS server. In a real prod env we'd have one or more replica DNS servers on separate hosts. But for now this just installs and configures one primary DNS server on just one host. I chose the first control plane host.<br>

1. Install bind9 and various utils:
    ```bash
    sudo apt install -y bind9 bind9utils bind9-doc
    ```
2. Open `/etc/default/named` file. Look for OPTIONS line and edit it to look like this:
```
OPTIONS="-u bind -4"
```
3. Restart `named`:
```bash
sudo systemctl restart named
```
4. Open `/etc/bind/named.conf.options` and add a new ACL block and add some additional config to the options block:
```
# new ACL block
acl "trusted" {
        172.25.240.20;    # ns1 - or you can use localhost for ns1
        172.29.0.0/20;  # trusted networks
};

# modify existing options block to look like this
options {
        directory "/var/cache/bind";

        //listen-on-v6 { any; };        # disable bind on IPv6

        recursion yes;                 # enables resursive queries
        allow-recursion { trusted; };  # allows recursive queries from "trusted" - referred to ACL
        listen-on { 172.25.240.20; };   # ns1 IP address
        allow-transfer { none; };      # disable zone transfers by default

        # use cloudflare's public DNS
        forwarders {
                1.1.1.2;
                1.0.0.2
        };
};
```
5. Open `/etc/bind/named.conf.local` file and specify our forward zone:
```
zone "local.testapp.private" {
    type master;
    file "/etc/bind/zones/db.local.testapp.private";
    # allow-transfer { x.x.x.x; } # this is where we'd set replica server IPs
};

```
6. Make sure the /etc/bind/zones dir exists:
```bash
sudo mkdir /etc/bind/zones
```
7. Copy and rename the example forward zone file that comes with bind9:
```bash
sudo cp /etc/bind/db.local /etc/bind/zones/db.local.testapp.private
```
8. Edit the forward zone file:
    * Replace `localhost.` with the FQDN of this name server `ns1.local.testapp.private.`
    * Replace `root.localhost.` with `admin.local.testapp.private.`
    * Set `Serial` to `3`. Increment this **each time you change & save the file.**
    * For the NS record, change `localhost.` to the same value as above. There is no `@` before the NS record.
    * Add all the A records you want, don't forget `ns1.local.testapp.private.` which is also used as the NS record and SOA
    * Delete the AAAA record since we only support ipv4
    * All domain names seem to end with a `.`
9. Check these config files:
    ```bash
    # should print nothing and return immediately to prompt
    sudo named-checkconf
    # should print some info and "OK"
    sudo named-checkzone local.testapp.private /etc/bind/zones/db.local.testapp.private
    ```
10. Restart and allow through firewall:
    ```bash
    sudo systemctl restart bind9
    sudo ufw allow Bind9
    ```

We don't need a reverse zone for our use case.<br>
Domain names we probably need:
* ns1.local.testapp.private pointing to cp1 host 172.25.240.20
* db.local.testapp.private pointing to cp1 host 172.25.240.20
* lb.local.testapp.private pointing to cp1 host 172.25.240.20
* cp1.local.testapp.private pointing to cp1 host 172.25.240.20
* cp2.local.testapp.private pointing to cp2 host 172.25.240.21
* cp3.local.testapp.private pointing to cp3 host 172.25.240.22
* worker1.local.testapp.private pointing to worker1 host 172.25.240.120
* worker2.local.testapp.private pointing to worker2 host 172.25.240.121


## Universal Machine Configuration

Below are configuration steps that must be taken on all machines. Regardless of whether they'll be master nodes or worker nodes.

### Forwarding IPv4 and letting iptables see bridged traffic

TODO this is buggy on ubuntu jammy. I think there are additional steps since it's now using NetworkManager and netplan.

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system
```

#### Verification

Verify that the modules are loaded:
```bash
lsmod | grep br_netfilter
lsmod | grep overlay
```

Verify system variables were written properly:
```bash
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
```

### Swap Configuration

In some cases swap memory should be disabled on each node. Unclear if this is still the case or if this applies to our current setup.<br>
Swap should be disabled in config files `/etc/fstab` and `systemd.swap`. Look up further instructions specific to distro.

NOTE this no longer applies, swap memory is fine for this setup.

### MAC Address and product_uuid

Each node in the cluster should have unique values. Some virtual machines may use the same product_uuid. Verify with the following:
```bash
# check MAC address of each network interface
$ ifconfig -a
# check product_uuid
$ sudo cat /sys/class/dmi/id/product_uuid
```

### SSH

1. Verify ssh is not currently running `sudo systemctl status ssh`
2. Install openssh-server `sudo apt install -y openssh-server`
3. Verify ssh is now running (repeat step 1)
4. Open ssh port using ufw `sudo ufw allow ssh`
5. Save ufw config `sudo ufw enable && sudo ufw reload`

### Open Ports

#### Control plane
```bash
sudo ufw allow 6443/tcp comment 'Kubernetes API Server'
sudo ufw allow 2379:2380/tcp comment 'etcd server client api'
sudo ufw allow 10250/tcp comment 'kubelet api'
sudo ufw allow 10259/tcp comment 'kube-scheduler'
sudo ufw allow 10257/tcp comment 'kube-controller-manager'
```
* etcd ports are included here, but etcd can be hosted externally too

#### Worker nodes
```bash
sudo ufw allow 10250/tcp comment 'kubelet api'
sudo ufw allow 30000:32767 comment 'kubernetes nodeport services'
```

Verify with netcat, eg:
```bash
$ nc -zvw 3 127.0.0.1 6443
```

### Network Configuration

Ubuntu uses netplan to configure its networking.<br>
Create a new file in `/etc/netplan` called `my-lan.yaml`:
```bash
sudo nano /etc/netplan/my-lan.yaml
```
Add this content to the file:
```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      dhcp6: false
      accept-ra: false
      link-local: []
      addresses:
        - <IP Address CIDR> # eg; 172.25.240.21/24
      routes:
        - to: default
          via: 172.25.240.1
      nameservers:
        addresses:
          - 172.25.240.20 # the IP hosting the DNS server
          - 1.1.1.2
          - 1.0.0.2
```

Apply configuration:
```bash
sudo netplan apply
```
Verify that the resolver now includes our private DNS along with the fallbacks:
```bash
sudo resolvectl status
```

If an ipv6 address was assigned to the interface before running this netplan, it won't be auto-removed. Use the following in that case:
```bash
sudo ip -6 addr del <ipv6/cidr> dev eth0
```

`sudo netplan get` can be used to get the system-wide config. This is what's active.<br>
`sudo ip link set eth0 up|down` can be used to cycle an interface up & down.<br>
`ip route show dev eth0` can be used to verify the default gateway is set correctly.<br>

default gateway: 172.25.240.1 netmask 255.255.255.0<br>
dns: 172.25.240.20, 1.1.1.2, 1.0.0.2

cp1: 172.25.240.20<br>
cp2: 172.25.240.21<br>
cp3: 172.25.240.22<br>
worker1: 172.25.240.120<br>
worker2: 172.25.240.121<br>
worker3: 172.25.240.122<br>


### cgroup Drivers

Recommend using systemd as the init system with an OS that supports cgroupv2.<br>
To verify that the OS is using cgroupv2 run this and verify the output reads `cgroup2fs`:
```bash
stat -fc %T /sys/fs/cgroup/
```

Starting with v1.22 and later, kubeadm will default to the systemd cgroupDriver if not overridden in the KubeletConfiguration. This is good. The container runtime must also be configured to use this same cgroup driver though.

### Container Runtimes (containerd)

This assumes the distro is a glibc-based distro.<br>
musl-based distros like Alpine Linux would have to build from source or rely on a third-party package.

1. Download `containerd-<VERSION>-<OS>-<ARCH>.tar.gz` from [containerd github releases](https://github.com/containerd/containerd/releases) and extract it under `/usr/local`:
    ```bash
    $ tar Cxzvf /usr/local containerd-1.7.8-linux-amd64.tar.gz
    ```
2. Download `containerd.service` file [from here](https://raw.githubusercontent.com/containerd/containerd/main/containerd.service) into `/etc/systemd/system/containerd.service`
3. Run the following:
    ```
    $ systemctl daemon-reload
    $ systemctl enable --now containerd
    ```
4. Download the `runc.<ARCH>` from [runc github releases](https://github.com/opencontainers/runc/releases) and install it at `/usr/local/sbin/runc`:
    ```bash
    $ install -m 755 runc.amd64 /usr/local/sbin/runc
    ```
    * runc is built statically so should work on any distro.
5. Download the `cni-plugins-<OS>-<ARCH>-<VERSION>.tgz` from [containernetworking/plugins github releases](https://github.com/containernetworking/plugins/releases) and extract it under `/opt/cni/bin`:
    ```bash
    $ mkdir -p /opt/cni/bin
    $ tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.3.0.tgz
    ```
    ```bash
    # automated
    mkdir -p /opt/cni/bin
    curl -O -L https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz
    tar -C /opt/cni/bin -xzf cni-plugins-linux-amd64-v1.3.0.tgz
    ```
    * This is also built statically so should work on any distro.
6. Generate a default configuration file:
    ```bash
    sudo mkdir /etc/containerd
    $ containerd config default > /etc/containerd/config.toml
    ```
7. Add the necessary sections to tell containerd to use the systemd cgroup driver. The config.toml file should look like this:
    ```
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
    ...
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
        SystemdCgroup = true
    ```
    * Ensure `cri` is not included in the `disabled_plugins` list
8. Override the sandbox (pause image) by setting this in the config.toml file:
    ```
    [plugins."io.containerd.grpc.v1.cri"]
        sandbox_image = "registry.k8s.io/pause:3.8"
    ```
9. ***TODO*** Configure kubelet to declare the matching `pod-infra-container-image`, otherwise kubelet will garbage collect the pause image.
10. ***TODO*** Configure kubeadm cgroup driver
11. Restart containerd:
    ```bash
    $ sudo systemctl restart containerd
    ```

#### Transferring all these files to other hosts

1. Move `cni-plugins-linux-amd64-v1.3.0.tgz`, `config.toml`, `containerd.service`, `containerd-1.7.8-linux-amd64.tar.gz`, and `runc.amd64` into a folder `containerd-files`
2. Move and execute this script from the same dir on the remote host:
    ```bash
        #!/bin/bash

        tar Cxzvf /usr/local containerd-1.7.8-linux-amd64.tar.gz
        cp containerd.service /etc/systemd/system/containerd.service
        systemctl daemon-reload
        systemctl enable --now containerd
        install -m 755 runc.amd64 /usr/local/sbin/runc
        mkdir -p /opt/cni/bin
        tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.3.0.tgz
        mkdir /etc/containerd
        cp config.toml /etc/containerd/config.toml
        systemctl restart containerd
    ```

#### Install a friendlier containerd CLI (nerdctl)

nerdctl provides a user-friendly interface to containerd. For example:
```bash
$ nerdctl run --name redis redis:alpine
```



### Installing kubeadm, kubelet and kubectl

These packages should be installed on all machines.

These instructions assume a Debian-based distribution.<br>
For releases older than Debian 12 and Ubuntu 22.04, you first need to run: `sudo mkdir -m 755 /etc/apt/keyrings`.

1. Update the `apt` package index and install packages needed to use the Kubernetes `apt` repository:
    ```bash
    $ sudo apt-get update
    $ sudo apt-get install -y apt-transport-https ca-certificates curl gpg
    ```
2. Download the public signing key for the Kubernetes package repos. The same signing key is used for all repos so you can disregard the version in the URL:
    ```bash
    $ curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    ```
3. Add the appropriate Kubernetes `apt` repo. Change the URL to match the version of Kubernetes you're targeting.
    ```bash
    $ echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    ```
4. Update the `apt` package index, install all the components, and pin their version:
    ```bash
    $ sudo apt-get update
    $ sudo apt-get install -y kubelet kubeadm kubectl
    $ sudo apt-mark hold kubelet kubeadm kubectl
    ```

Kubelet waits in a crashloop until kubeadm gives it something to do.

### Configuring kubelet cgroup driver

v1.22 and later, kubeadm defaults kubelet cgroup driver to systemd. We don't have to do anything here.<br>
Regardless, here are the commands for kubeadm that would be helpful:<br>
It is possible to configure the kubelet that kubeadm will start if a custom KubeletConfiguration API object is passed with a configuration file like so `kubeadm ... --config some-config-file.yaml`.<br>
By calling `kubeadm config print init-defaults --component-configs KubeletConfiguration` you can see all the default values for this structure.<br>

## ControlPlane Primary Machine Configuration

This should be done only on the first controlplane machine (the one that will eventually run `kubeadm init`).

### kube-vip for vIP and LB

For a highly-available control plane, we need a virtual IP and load balancer. One tried and true method is to use `keepalived` in tandem with `haproxy`. Another option is to use kube-vip which combines the functionality into one service.

#### kube-vip

1. Set an alias to spin up the kube-vip container (using `containerd`):
    ```bash
    alias kube-vip="ctr image pull ghcr.io/kube-vip/kube-vip:v0.6.3; ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:v0.6.3 vip /kube-vip"
    ```
    * Hardcode the version or fetch the latest version tag using curl and github's api.
2. Create a manifest:
    ```bash
    kube-vip manifest pod \
        --interface <INTERFACE> \
        --address <VIP> \
        --controlplane \
        --arp \
        --leaderElection | tee /etc/kubernetes/manifests/kube-vip.yaml
    ```
    * <INTERFACE> is the name of the network interface on the control planes which will announce the vIP. This can be found via `ip a` command.
    * <VIP> is the vIP to be served or a FQDN. All hosts must be in the same address space.

The address passed to kube-vip will be passed to `kubeadm init` as well (the `--control-plane-endpoint` of kubeadm).<br>
The output of the kubeadm init should then be used in `kubeadm join` on the other control planes (copy over the same generated kube-vip manifest first).<br>
**NOTE**: IP addresses shouldn't be used in prod environments, so the address should be a FQDN. Set up the DNS server first I guess...

DNS resolution maps the FQDN to an IP. ARP resolution maps the IP to MAC. Maybe a slight inefficiency but using the FQDN adds a layer of flexibility and is easier to make sense of for other devs looking at it (eg; "where'd 172.25.240.200 come from??" vs "ah, lb.local.testapp.private, that's the load balancer served on the vIP").

## Finally creating the cluster

#### kubeadmin init
`kubeadm init --pod-network-cidr=10.244.0.0/16 --control-plane-endpoint=lb.local.testapp.private:6443 --upload-certs`

The `--pod-network-cidr` here just explicitly specifies the pod address. It is the same as the (current) default pod network cidr, but stating it explicitly adds some future-proofing and bug-proofing.<br>
The `--control-plane-endpoint` is set to the domain name that points at the kube-vip Virtual IP. The port is the default, and is the same as kube-apiserver's default port.<br>
The `--upload-certs` flag uploads certs that should be shared across all controlplane nodes. If installing certificates manually on each node, you can remove this flag, but it's nice to have kubeadm do this for us.<br>

#### Cluster networking

The next step is to install a CNI plugin. This enables the coredns service to come up and enables comms between pods (and nodes). Choosing `flannel` to start with. The RKE2 distro uses a combination of `flannel` and `calico` called `Canal`. But just one of these is fine to start.

`kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml`

Once the CNI plugin is installed and running, we look for the coredns service to come up: `kubectl get pods --all-namespaces`

#### Other controlplane nodes

Once we confirm the CNI plugin is working and coredns is up and running, we can now join the other controlplane nodes like so:
```
sudo kubeadm join lb.local.testapp.private:6443 --token tokdde.969kzyboywoh95p6 \
	--discovery-token-ca-cert-hash sha256:d5e0039ef17aaf1b8e1526f470d05606e84ecb2fa76167e7d53d8a4539128783 \
	--control-plane --certificate-key 3927cddcdcb29ee807219c1d19b607596dd02c114ad01d5c077ebe86a19ef3de
```

The `--control-plane` flag here tells kubeadm that we want this node to be a new controlplane node. The rest of the flags come from the output of the `kubeadm init` command (or we can regenerate the hashes and cert keys at a later time - the output from the kubeadm init command is only good for two hours).

#### Worker nodes
Finally, we can join our worker nodes. This is just the output from the `kubeadm init` command, should look like this:
```
sudo kubeadm join lb.local.testapp.private:6443 --token tokdde.969kzyboywoh95p6 \
	--discovery-token-ca-cert-hash sha256:d5e0039ef17aaf1b8e1526f470d05606e84ecb2fa76167e7d53d8a4539128783
```

## Conclusion

We now have a highly available control plane and worker nodes.<br>
We can begin deploying our application(s).