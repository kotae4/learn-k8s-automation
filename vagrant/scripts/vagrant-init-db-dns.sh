#!/bin/bash

# =========================
# name the args for clarity
# =========================
hostCidr=$1
hostIp=$2
routerIp=$3
trustedNetCidr=$4
cp1Ip=$5
cp2Ip=$6
cp3Ip=$7
wk1Ip=$8
wk2Ip=$9
wk3Ip=${10}
lbIp=${11}
domainName=${12}

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
          - $hostIp
          - 1.1.1.2
          - 1.0.0.2
EOF
netplan apply

# =================
# copy the ssh keys
# =================
# TODO copy ssh keys

# =========================
# install and setup mariadb
# =========================
apt install -y mariadb-server
# mysql_secure_installation
# don't set a password on the root account because it's supposedly used in package updates? i dunno
mysql -sfu root <<EOS
-- 1. remove_anonymous_users
DELETE FROM mysql.global_priv WHERE User='';
-- 2. remove_remote_root
DELETE FROM mysql.global_priv WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
-- 3. remove_test_database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
-- 4. reload_privilege_tables
FLUSH PRIVILEGES;
EOS
ufw allow mysql

# =====================================
# install and setup bind9 for local DNS
# =====================================
apt install -y bind9 bind9utils bind9-doc
# we only care about ipv4
sed -i -r 's/OPTIONS="-u bind"/OPTIONS="-u bind -4"/' /etc/default/named
# overwrite the existing options
cat << EOF > /etc/bind/named.conf.options
# new ACL block
acl "trusted" {
$hostIp; # ns1 IP address
$trustedNetCidr; # trusted networks
};

options {
directory "/var/cache/bind";

# disable bind on IPv6
//listen-on-v6 { any; };

# enables resursive queries
recursion yes;
# allows recursive queries from "trusted" - referred to ACL
allow-recursion { trusted; };
# ns1 IP address
listen-on port 53 { localhost; $hostIp; };
# disable zone transfers by default
allow-transfer { none; };

# use cloudflare's public DNS
forwarders { 1.1.1.2; 1.0.0.2; };
};
EOF
# specify forward zone
cat << EOF > /etc/bind/named.conf.local
zone "$domainName" {
    type master;
    file "/etc/bind/zones/db.$domainName";
};
include "/etc/bind/zones.rfc1918";
EOF
# make the zones directory
mkdir /etc/bind/zones
# write our forward zone file
cat << EOF > /etc/bind/zones/db.$domainName
\$TTL	30m
@ IN SOA ns1.$domainName. admin.$domainName. (3 10m 15m 1d 30m)
@ IN NS ns1.$domainName.
ns1.$domainName. IN A $hostIp
db.$domainName. IN A $hostIp
lb.$domainName. IN A $lbIp
cp1.$domainName. IN A $cp1Ip
cp2.$domainName. IN A $cp2Ip
cp3.$domainName. IN A $cp3Ip
worker1.$domainName. IN A $wk1Ip
worker2.$domainName. IN A $wk2Ip
worker3.$domainName. IN A $wk3Ip
EOF
systemctl restart bind9
ufw allow Bind9