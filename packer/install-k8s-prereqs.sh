#!/bin/bash

#===============
# general config
#===============
# load kernel modules required for kubernetes CNI plugins
cat <<EOF | sudo tee -a /etc/modules-load.d/modules.conf
overlay
br_netfilter
EOF

# set kernel variables to allow bridged traffic and ip forwarding
cat <<EOF | sudo tee /etc/sysctl.d/99-my-k8s-vars.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.default.forwarding = 1
net.ipv4.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.all.forwarding = 1
EOF

# set kernel variables again, but this time at ufw (who knows which one gets set - sysctl.d or ufw...)
cat <<EOF | sudo tee -a /etc/ufw/sysctl.conf
net/bridge/bridge-nf-call-iptables=1
net/bridge/bridge-nf-call-ip6tables=1
net/ipv4/ip_forward=1
net/ipv4/conf/default/forwarding = 1
net/ipv4/conf/all/forwarding = 1
net/ipv6/conf/default/forwarding=1
net/ipv6/conf/all/forwarding=1
EOF

# tell ufw to accept forwarded traffic
sed -i -r 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

#========================
# containerd installation
#========================
# containerd package should've been installed during cloud-init (from ubuntu package repository)
# install cni-plugins
mkdir -p /opt/cni/bin
curl -O -L https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz
tar -C /opt/cni/bin -xzf cni-plugins-linux-amd64-v1.4.0.tgz

#=========================
# containerd configuration
#=========================
# generate a default config file
mkdir /etc/containerd
containerd config default > /etc/containerd/config.toml
# add the necessary sections to tell containerd to use the systemd cgroup driver
sed -i -r 's/(SystemdCgroup.*?=.*?)false/\1true/' /etc/containerd/config.toml
sed -i -r 's/pause:3.8/pause:3.9/' /etc/containerd/config.toml

#=================
# kubernetes installation
#=================
mkdir -m 755 /etc/apt/keyrings
# all the necessary packages should've been installed during cloud-init
# download the public signing key for the kubernetes package repos.
# the same signing key is used for all repos so you can disregard the version in the URL
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
# add the package repo.
# the URL does matter here, so change it to match your target version.
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
# update the package index since we've just added a new package repo
apt-get update
# install all the kubernetes components and pin their version
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl