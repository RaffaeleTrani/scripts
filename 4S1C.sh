#!/bin/bash
function cleanup {
  set +e
  set +x
  sudo ip netns exec ns1 polycubectl firewall del fw
  sudo ip netns del ns_client
  sudo ip netns del ns_server
  sudo pkill polycubed
}

trap cleanup EXIT
set -x
set -e

#KEEP THIS PART COMMENTED IF YOU ALREADY HAVE POLYCUBE INSTALLED IN YOUR MACHINE
#
## install git
##sudo apt-get install git
#
## clone the polycube repository
##git clone https://github.com/polycube-network/polycube
##cd polycube
##git submodule update --init --recursive
## launch the automatic install script (use -h to see the different installation modes)
#./scripts/install.sh

#NOTE: as a polycube instance will be started in namespace ns_client, 
#      if you have a running instance of polycube you need to stop it before running next commands

#creation of namespaces
sudo ip netns add ns_client
sudo ip netns add ns_server

sudo ip link add name veth2 type veth peer name veth1
sudo ip link set veth1 netns ns_client
sudo ip link set veth2 netns ns_server
sudo ip netns exec ns_client ip addr add 10.100.0.1/24 dev veth1
sudo ip netns exec ns_server ip addr add 10.100.0.2/24 dev veth2
sudo ip netns exec ns_client ip link set veth1 up
sudo ip netns exec ns_server ip link set veth2 up

sudo ip netns exec ns_client ip link set lo up
sudo ip netns exec ns_client sudo polycubed &
sleep5

#create firewall
sudo ip netns exec ns_client polycubectl firewall add fw
sudo ip netns exec ns_client polycubectl attach fw veth1

#icmp rules
sudo ip netns exec ns_client polycubectl firewall fw chain INGRESS rule add 0 src=10.100.0.2 dst=10.100.0.1 l4proto=ICMP action=FORWARD
sudo ip netns exec ns_client polycubectl firewall fw chain EGRESS rule add 0 src=10.100.0.1 dst=10.100.0.2 l4proto=ICMP action=FORWARD

#TCP rules
sudo ip netns exec ns_client polycubectl firewall fw chain INGRESS rule add 1 src=10.100.0.2 dst=10.100.0.1 l4proto=TCP action=FORWARD
sudo ip netns exec ns_client polycubectl firewall fw chain EGRESS rule add 1 src=10.100.0.1 dst=10.100.0.2 l4proto=TCP action=FORWARD

# Ping client-server
sudo ip netns exec ns_client ping 10.100.0.2 -c 2

# Ping server-client
sudo ip netns exec ns_server ping 10.100.0.1 -c 2

echo "SETUP COMPLETED, RUNNING IPERF TESTS:"

sudo ip netns exec ns_server iperf3 -s -D
sudo ip netns exec ns_client iperf3 -c 10.100.0.2 -t 60 -V

echo "IPERF TESTS COMPLETED, CHECK INTERFACES OF NAMESPACES"

sudo ip netns exec ns_client ip -s link | awk '/veth1/,0'
sudo ip netns exec ns_server ip -s link | awk '/veth2/,0'
polycubectl firewall fw show chain ingress
polycubectl firewall fw show chain egress
