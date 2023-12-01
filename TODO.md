# Initing cluster with kubeadm

Example: `kubeadm init --control-plane-endpoint lb.local.testapp.private:6443 --pod-network-cidr=10.244.0.0/16 [additional arguments ...]`<br>

1. Run kubeadm init with the --control-plane-endpoint flag using the VIP address provided when generating the static Pod manifest.
2. The kubelet will parse and execute all manifests, including the kube-vip manifest generated in step one and the other control plane components including kube-apiserver.
3. kube-vip starts and advertises the VIP address.
4. The kubelet on this first control plane will connect to the VIP advertised in the previous step.
5. kubeadm init finishes successfully on the first control plane.
6. Install networking addon (flannel) and check the pod status to make sure everything's up and running before continuing.
    * NOTE: If kubeadm is used, then pass --pod-network-cidr=10.244.0.0/16 to kubeadm init to ensure that the podCIDR is set.
7. Using the output from the kubeadm init command on the first control plane, run the kubeadm join command on the remainder of the control planes.
8. Copy the generated kube-vip manifest to the remainder of the control planes and place in their static Pods manifest directory (default of /etc/kubernetes/manifests/).

I assume 7 & 8 should be swapped. Copy the manifest to the other hosts before running the kubeadm join command.

Canal is another networking addon, it uses calico for net policies and intra-node comms and flannel for inter-node comms. Canal is used by default in RKE2 installations.

# Packer

Packer will be used to produce golden images. These golden images contain all the static software installations and configuration we need (ie; things that don't depend on any runtime information).

Need images:
1. Kubernetes node
    * openssh
    * containerd, runc, and cni-plugins
    * kubeadm, kubelet, and kubectl
2. 'Primary' node
    * Uses kubernetes node as base
    * Adds bind9 DNS and mariadb

Fork packer's hyper-v builder and move ip address discovery to arp filtered by mac address instead of going through Get-VMNetworkAdapter and Get-NetIPAddress:<br>
`arp -a | findstr <VM-mac-address>`

# Vagrant

Vagrant will be used for any configuration that depends on dynamic, per-instance information. Namely, network configuration.<br>
It might also be used to initialize the cluster, install the CNI plugin (flannel?), and install kube-vip. If I'm able to pull the output of these steps out into the scope of the vagrantfile and use them as variables when provisioning the other machines then this would be a huge boon.