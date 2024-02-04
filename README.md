# learn-k8s-automation

Notes and automated pipelines for various things related to a Kubernetes cluster.

Currently using Packer to automate a golden image pipeline and Vagrant to automate provisioning and per-instance configuration of all the nodes in the cluster.<br>

`kubernetes-production-setup-guide.md` details all of the steps I took to initialize the cluster with kubeadm (mostly cobbled together several guides). Living document.<br>
`kubernetes-notes.md` is a bunch of notes on things to consider when operating a cluster in production.<br>
`high-availability-topology.png` is ripped from this excellent tutorial: https://mvallim.github.io/kubernetes-under-the-hood/documentation/kube-masters-and-workers.html <br>
`kubernetes-io-stylus.css` is a dark theme for kubernetes.io originally by ivaks but modified by me built for the Stylus browser addon.

## Instructions

This is a doozy, so strap in...

### Required Tools

1. HyperV must be enabled. See this for more details: https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/quick-start/enable-hyper-v
2. Packer must be installed and on your PATH. See here: https://developer.hashicorp.com/packer/install
3. Vagrant must be installed and on your PATH. See here: https://developer.hashicorp.com/vagrant/install

Please note that having HyperV enabled may interfere with other hypervisors like VirtualBox or VMWare.

### HyperV Networking

Run the `setup-hyperv-network.ps1` powershell script in the root directory of this repo. You must run this from an elevated powershell instance (Run as Administrator).<br>
This will create a new internal virtual switch named `VagrantHyperVSwitch`, a new adapter named `vEthernet (VagrantHyperVSwitch)`, and a new NAT named `VagrantHyperVNAT`.<br>
This internal virtual network will, by default, occupy `172.25.192.0/24` with the gateway on `172.25.192.1`. *Warning: Any changes to the defaults in the powershell script should be made to the `base-k8s.pkr.hcl` and `Vagrantfile` as well.*

### Packer

**MAKE SURE NUMLOCK IS OFF**

Packer is used to build the virtual machine image. The image is based off of the Ubuntu live server image. The core components of a Kubernetes cluster are then installed, and the various tweaks needed to run them are made as well. Finally, the virtual machine image is made into a Vagrant box file.<br>
The end result is an entirely automated image that's ready to either initialize a cluster as a control-plane node or join an existing cluster as either a control-plane node or a worker node.<br>

All commands should be ran from an elevated powershell instance:
```
cd packer
packer init .
packer build ./base-k8s.pkr.hcl
```

The output should be named like `packer_ubuntujammy_hyperv_amd64.box`.

### Vagrant

**IF YOU RUN INTO ERRORS, ALWAYS START BY LOOKING INTO HV-KVP-DAEMON ON THE GUEST**

Vagrant is used to spin up 7 virtual machines through HyperV:
1. The private DNS and relational database server. This isn't entirely necessary but I like having local domain names and a database for apps to use. Not intended to be part of the cluster.
2. 3 control-plane nodes.
3. 3 worker nodes.

All 7 virtual machines are based on the box we just built with Packer.<br>
In addition to spinning these machines up, Vagrant also manages per-machine provisioning: configuring static IP addresses, opening ports, and, in the case of the DNS and DB machine, installing and configuring the bind9 and mariadb servers.<br>

All commands should be ran from an elevated powershell instance:
```
cd vagrant
vagrant box add --name my-base-k8s-box ../packer/packer_ubuntujammy_hyperv_amd64.box
vagrant init my-base-k8s-box
vagrant up --provider=hyperv --no-parallel
```

For debugging:
```
vagrant up --provider=hyperv --no-parallel --debug 2>&1 | Tee-Object -FilePath ".\vagrant.log"
```

## Cleanup

First of all, the vagrant machines should be destroyed:<br>
*All commands should be ran from an elevated powershell instance.*
```
cd vagrant
vagrant destroy --force
vagrant box remove my-base-k8s-box
```

Additionally, the following artifacts may be present:
```
packer/packer_cache/*
vagrant/.vagrant/*
packer_ubuntujammy_hyperv_amd64.box
```