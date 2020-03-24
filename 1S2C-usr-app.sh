#!/bin/bash

function cleanup {
  set +e
  set +x
  sudo ip netns del ns_client
  sudo kill $(ps aux | grep 'sudo ip netns exec ns_firewall' | awk '{print $2}') > /dev/null 2>&1
  sudo kill $(ps aux | grep 'iperf3 -s -D' | awk '{print $2}') > /dev/null 2>&1  
  sudo ip netns del ns_firewall
  sudo ip netns del ns_server
  yes | rm -r firewall
}
trap cleanup EXIT

set -x
set -e


#get firewall application
mkdir firewall
git clone https://github.com/RaffaeleTrani/firewall.git firewall

#creation of namespaces
sudo ip netns add ns_client
sudo ip netns add ns_firewall
sudo ip netns add ns_server

#client-firewall veth pair configuration
sudo ip link add name veth1 type veth peer name veth0
sudo ip link set veth0 netns ns_client
sudo ip link set veth1 netns ns_firewall
sudo ip netns exec ns_client ip addr add 10.100.1.1/24 dev veth0
sudo ip netns exec ns_client ip link set veth0 up
sudo ip netns exec ns_firewall ip link set veth1 up

#server-firewall veth pair configuration
sudo ip link add name veth2 type veth peer name veth3
sudo ip link set veth2 netns ns_firewall
sudo ip link set veth3 netns ns_server
sudo ip netns exec ns_server ip addr add 10.100.1.2/24 dev veth3
sudo ip netns exec ns_firewall ip link set veth2 up
sudo ip netns exec ns_server ip link set veth3 up

#disable Linux TCP offloading in both client and server namespace
sudo ip netns exec ns_client ethtool --offload veth0 rx off tx off
sudo ip netns exec ns_client ethtool -K veth0 gso off
sudo ip netns exec ns_server ethtool --offload veth3 rx off tx off
sudo ip netns exec ns_server ethtool -K veth3 gso off

#start firewall user application
sudo ip netns exec ns_firewall firewall/cmake-build-debug/untitled namespaces &

#command to check if firewall process is running in background as expected
jobs

# Ping client-server through firewall
sudo ip netns exec ns_client ping 10.100.1.2 -c 2

echo "SETUP COMPLETED, RUNNING IPERF TESTS:"

sudo ip netns exec ns_server iperf3 -s -D
sudo ip netns exec ns_client iperf3 -c 10.100.1.2 -t 60 -V

echo "IPERF TESTS COMPLETED, CHECK INTERFACES OF NAMESPACES"

sudo ip netns exec ns_client ip -s link | awk '/veth0/,0'
sudo ip netns exec ns_firewall ip -s link | awk '/veth1/,0'
sudo ip netns exec ns_firewall ip -s link | awk '/veth2/,0'
sudo ip netns exec ns_server ip -s link | awk '/veth3/,0'
