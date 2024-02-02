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
netplan apply

# ========================
# open the necessary ports
# ========================
ufw allow 10250/tcp comment 'kubelet api'
ufw allow 30000:32767 comment 'kubernetes nodeport services'

# =================
# copy the ssh keys
# =================
# TODO copy ssh keys