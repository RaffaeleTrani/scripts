#!/bin/bash
function cleanup {
  set +e
  set +x
  sudo ip netns del ns_client
  sudo ip netns del ns_server
}

trap cleanup EXIT
set -x
set -e


#creation of namespaces
sudo ip netns add ns_client
sudo ip netns add ns_server

#client-server veth pair configuration
sudo ip link add name veth1 type veth peer name veth0
sudo ip link set veth0 netns ns_client
sudo ip link set veth1 netns ns_server
sudo ip netns exec ns_client ip addr add 10.100.1.1/24 dev veth0
sudo ip netns exec ns_server ip addr add 10.100.1.2/24 dev veth1
sudo ip netns exec ns_client ip link set veth0 up
sudo ip netns exec ns_server ip link set veth1 up

# Ping client-server
sudo ip netns exec ns_client ping 10.100.1.2 -c 2

# Ping server-client
sudo ip netns exec ns_server ping 10.100.1.1 -c 2

echo "SETUP COMPLETED, RUNNING IPERF TESTS:"

sudo ip netns exec ns_server iperf3 -s -D
sudo ip netns exec ns_client iperf3 -c 10.100.1.2 -t 60 -V

echo "IPERF TESTS COMPLETED, CHECK INTERFACES OF NAMESPACES"

sudo ip netns exec ns_client ip -s link | awk '/veth0/,0'
sudo ip netns exec ns_server ip -s link | awk '/veth1/,0'
