#!/bin/bash

function cleanup {
  set +e
  set +x
  sudo ip netns del ns_client
  sudo ip netns del ns_firewall
  sudo ip netns del ns_server
}
trap cleanup EXIT

set -x
set -e

#creation of namespaces
sudo ip netns add ns_client
sudo ip netns add ns_firewall
sudo ip netns add ns_server

#client-firewall veth pair configuration
sudo ip link add name veth1 type veth peer name veth0
sudo ip link set veth0 netns ns_client
sudo ip link set veth1 netns ns_firewall
sudo ip netns exec ns_client ip addr add 10.100.1.1/24 dev veth0
sudo ip netns exec ns_firewall ip addr add 10.100.1.2/24 dev veth1
sudo ip netns exec ns_client ip link set veth0 up
sudo ip netns exec ns_firewall ip link set veth1 up

#client-firewall veth pair configuration
sudo ip link add name veth2 type veth peer name veth3
sudo ip link set veth2 netns ns_firewall
sudo ip link set veth3 netns ns_server
sudo ip netns exec ns_firewall ip addr add 10.100.2.1/24 dev veth2
sudo ip netns exec ns_server ip addr add 10.100.2.2/24 dev veth3
sudo ip netns exec ns_firewall ip link set veth2 up
sudo ip netns exec ns_server ip link set veth3 up

#route for communication between client and server
sudo ip netns exec ns_client ip route add default via 10.100.1.2 dev veth0
sudo ip netns exec ns_server ip route add default via 10.100.2.1 dev veth3
#Note: no addictional route in firewall as it already knows how to reach veth pairs

#set up iptables rules in ns_firewall as firewall application
sudo ip netns exec ns_firewall sudo iptables -A FORWARD -i veth1 -o veth2 -j ACCEPT
sudo ip netns exec ns_firewall sudo iptables -A FORWARD -i veth2 -o veth1 -j ACCEPT

# Ping client-firewall
sudo ip netns exec ns_client ping 10.100.1.2 -c 2

# Ping client-server (through firewall)
sudo ip netns exec ns_client ping 10.100.2.2 -c 2

# Ping server-firewall
sudo ip netns exec ns_server ping 10.100.2.1 -c 2

# Ping server-client (through firewall)
sudo ip netns exec ns_server ping 10.100.1.1 -c 2

echo "SETUP COMPLETED, RUNNING IPERF TESTS:"

sudo ip netns exec ns_server iperf3 -s -D
sudo ip netns exec ns_client iperf3 -c 10.100.2.2 -t 60 -V

echo "IPERF TESTS COMPLETED, CHECK INTERFACES OF NAMESPACES"

sudo ip netns exec ns_client ip -s link | awk '/veth0/,0'
sudo ip netns exec ns_firewall ip -s link | awk '/veth1,0'
sudo ip netns exec ns_firewall ip -s link | awk '/veth2,0'
sudo ip netns exec ns_server ip -s link | awk '/veth3/,0'
