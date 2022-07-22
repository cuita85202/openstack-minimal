# nova
PART1=true

# neutron
PART2=true
PROVIDER_INTERFACE_NAME=????

IP=${1}

if [ "$IP" == "" ]; then
	echo "must enter private IP of Host (eg. 192.168.10.247)"
	exit 1
fi

cat >> /etc/default/grub << EOT
GRUB_CMDLINE_LINUX_DEFAULT="ipv6.disable=1"
GRUB_CMDLINE_LINUX="ipv6.disable=1"
EOT
update-grub


apt install -y chrony
sed -i 's/^pool/#pool/g' /etc/chrony/chrony.conf
echo "server controller iburst" >> /etc/chrony/chrony.conf
service chrony restart

if [ "$PART1" == "true" ]; then
apt install -y software-properties-common
add-apt-repository cloud-archive:yoga
apt update && apt -y dist-upgrade
apt install -y python3-openstackclient nova-compute

cat > /etc/nova/nova.conf << EOT
[DEFAULT]
transport_url = rabbit://openstack:RABBIT_PASS@controller
my_ip = $IP
instances_path=/var/lib/nova/instances
[api]
auth_strategy = keystone

[keystone_authtoken]
www_authenticate_uri = http://controller:5000/
auth_url = http://controller:5000/
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = NOVA_PASS

[vnc]
enabled = true
server_listen = 0.0.0.0
server_proxyclient_address = $IP
novncproxy_base_url = http://controller:6080/vnc_auto.html

[glance]
api_servers = http://controller:9292

[oslo_concurrency]
lock_path =/var/lib/nova/tmp

[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://controller:5000/v3
username = placement
password = PLACEMENT_PASS

[neutron]
auth_url = http://controller:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = neutron
password = NEUTRON_PASS
EOT

service nova-compute restart
fi

if [ "$PART2" == "true" ]; then
echo "adding sudo right to neutron "
   cat> /etc/sudoers.d/neutron_sudoers <<EOT
Defaults:neutron !requiretty

neutron ALL = (root) NOPASSWD: /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf *
neutron ALL = (root) NOPASSWD: /usr/bin/neutron-rootwrap-daemon /etc/neutron/rootwrap.conf
neutron ALL = (root) NOPASSWD: ALL
EOT

service nova-compute restart

apt install -y neutron-linuxbridge-agent
cat> /etc/neutron/neutron.conf <<EOT
[DEFAULT]
transport_url = rabbit://openstack:RABBIT_PASS@controller
auth_strategy = keystone

[keystone_authtoken]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = NEUTRON_PASS

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
EOT

chmod 640 /etc/neutron/neutron.conf
## restart neutron servers
service nova-compute restart
service neutron-linuxbridge-agent restart

cat> /etc/neutron/plugins/ml2/linuxbridge_agent.ini<<EOT
[linux_bridge]
physical_interface_mappings = provider:$PROVIDER_INTERFACE_NAME

[vxlan]
enable_vxlan = false

[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
EOT
fi

echo "The Compute Node installation is completed!"
echo "ready... press enter to reboot!!!"
read
reboot
