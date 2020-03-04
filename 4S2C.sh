#!/bin/bash
function cleanup {
  set +e
  set +x
  sudo ip netns del ns_client
  sudo ip netns del ns_server
  sudo ip link del veth1 > /dev/null 2>&1
  sudo ip link del veth2 > /dev/null 2>&1
  polycubectl pbforwarder del pbfw1
  polycubectl firewall del fw
  sudo systemctl stop polycubed
}

trap cleanup EXIT
set -x
set -e

#KEEP THIS PART COMMENTED IF YOU ALREADY HAVE POLYCUBE INSTALLED
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

# start polycubed service
sudo systemctl start polycubed
sleep 5

#creation of namespaces
sudo ip netns add ns_client
sudo ip netns add ns_server

#client-server veth pair configuration
sudo ip link add veth1_ type veth peer name veth1
sudo ip link set veth1_ netns ns_client
sudo ip netns exec ns_client ip link set dev veth1_ up
sudo ip link set dev veth1 up
sudo ip netns exec ns_client ifconfig veth1_ 10.100.0.1/24

sudo ip link add veth2_ type veth peer name veth2
sudo ip link set veth2_ netns ns_server
sudo ip netns exec ns_server ip link set dev veth2_ up
sudo ip link set dev veth2 up
sudo ip netns exec ns_server ifconfig veth2_ 10.100.0.2/24

polycubectl pbforwarder add pbfw1
polycubectl pbforwarder pbfw1 ports add veth1
polycubectl pbforwarder pbfw1 ports add veth2
polycubectl pbforwarder pbfw1 ports veth1 set peer="veth1"
polycubectl pbforwarder pbfw1 ports veth2 set peer="veth2"
polycubectl pbforwarder pbfw1 rules add 0 in_port=veth1 action=FORWARD out_port=veth2
polycubectl pbforwarder pbfw1 rules add 1 in_port=veth2 action=FORWARD out_port=veth1

polycubectl firewall add fw
polycubectl attach fw veth1
polycubectl firewall fw chain INGRESS rule add 0 src=10.100.0.1 dst=10.100.0.2 l4proto=ICMP action=FORWARD
polycubectl firewall fw chain EGRESS rule add 0 src=10.100.0.2 dst=10.100.0.1 l4proto=ICMP action=FORWARD
polycubectl firewall fw chain INGRESS rule add 1 src=10.100.0.1 dst=10.100.0.2 l4proto=TCP action=FORWARD
polycubectl firewall fw chain EGRESS rule add 1 src=10.100.0.2 dst=10.100.0.1 l4proto=TCP action=FORWARD

# Ping client-server
sudo ip netns exec ns_client ping 10.100.0.2 -c 2

# Ping server-client
sudo ip netns exec ns_server ping 10.100.0.1 -c 2

echo "SETUP COMPLETED, RUNNING IPERF TESTS:"

sudo ip netns exec ns_server iperf3 -s -D
sudo ip netns exec ns_client iperf3 -c 10.100.0.2 -t 60 -V

echo "IPERF TESTS COMPLETED, CHECK INTERFACES OF NAMESPACES"

sudo ip netns exec ns_client ip -s link | awk '/veth1_/,0'
sudo ip netns exec ns_server ip -s link | awk '/veth2_/,0'
polycubectl pbforwarder pbfw1 show rules -verbose
polycubectl firewall fw show chain ingress
polycubectl firewall fw show chain egress
