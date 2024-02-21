#!/bin/bash

# =========================
# name the args for clarity
# =========================
hostCidr=$1
hostIp=$2
routerIp=$3
dbdnsIp=$4

# ==============================================================================
# do the static network configuration
# vagrant's hyperv provider does not currently support networking
# see: https://developer.hashicorp.com/vagrant/docs/providers/hyperv/limitations
# ==============================================================================
# delete the subiquity / cloud-init config first
rm -f /etc/netplan/00-installer-config.yaml
cat << EOF > /etc/netplan/99-my-lan.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      dhcp6: false
      accept-ra: false
      link-local: []
      addresses:
        - $hostIp$hostCidr
      routes:
        - to: default
          via: $routerIp
      nameservers:
        addresses:
          - $dbdnsIp
          - 1.1.1.2
          - 1.0.0.2
EOF

# ========================
# open the necessary ports
# ========================
ufw allow 6443/tcp comment 'Kubernetes API Server'
ufw allow 2379:2380/tcp comment 'etcd server client api'
ufw allow 10250/tcp comment 'kubelet api'
ufw allow 10259/tcp comment 'kube-scheduler'
ufw allow 10257/tcp comment 'kube-controller-manager'

# =======================================================
# Create the kubelet config that's passed to kubeadm init
# =======================================================
cat << EOF > ~/kubelet-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: 1.28.0
controlPlaneEndpoint: "lb.local.testapp.private:6443"
networking:
  podSubnet: 10.244.0.0/16
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
failSwapOn: false
featureGates:
  NodeSwap: true
memorySwap:
  swapBehavior: UnlimitedSwap
EOF