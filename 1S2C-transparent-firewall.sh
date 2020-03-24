#!/bin/bash

function cleanup {
  set +e
  set +x
  sudo iptables -D FORWARD -s 10.100.1.2/24 -d 10.100.1.1/24 -j ACCEPT
  sudo iptables -D FORWARD -s 10.100.1.1/24 -d 10.100.1.2/24 -j ACCEPT
  sudo ip netns del ns_client
  sudo ip netns del ns_server
  sudo ip link set br0 down
  sudo brctl delbr br0
}
trap cleanup EXIT

set -x
set -e

#install packet to use brctl for linux bridge
#keep next line commented if already installed
#sudo apt install bridge-utils

#creation of namespaces
sudo ip netns add ns_client
sudo ip netns add ns_server
sudo brctl addbr br0

#client-firewall veth pair configuration
sudo ip link add name veth1 type veth peer name veth0
sudo ip link set veth0 netns ns_client
sudo brctl addif br0 veth1
sudo ip netns exec ns_client ip addr add 10.100.1.1/24 dev veth0
sudo ip netns exec ns_client ip link set veth0 up
sudo ip link set veth1 up

#server-firewall veth pair configuration
sudo ip link add name veth2 type veth peer name veth3
sudo ip link set veth3 netns ns_server
sudo brctl addif br0 veth2
sudo ip netns exec ns_server ip addr add 10.100.1.2/24 dev veth3
sudo ip netns exec ns_server ip link set veth3 up
sudo ip link set veth2 up

#set up bridge to work as transparent firewall
sudo ip link set br0 up
sudo iptables -A FORWARD -s 10.100.1.2/24 -d 10.100.1.1/24 -j ACCEPT
sudo iptables -A FORWARD -s 10.100.1.1/24 -d 10.100.1.2/24 -j ACCEPT

# Ping client-server through firewall
sudo ip netns exec ns_client ping 10.100.1.2 -c 2

echo "SETUP COMPLETED, RUNNING IPERF TESTS:"

sudo ip netns exec ns_server iperf3 -s -D
sudo ip netns exec ns_client iperf3 -c 10.100.1.2 -t 60 -V

echo "IPERF TESTS COMPLETED, CHECK INTERFACES OF NAMESPACES AND LINUX BRIDGE"

sudo ip netns exec ns_client ip -s link | awk '/veth0/,0'
sudo ip netns exec ns_server ip -s link | awk '/veth3/,0'
sudo ip -s link | awk '/br0/,0'
