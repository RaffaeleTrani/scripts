#!/bin/bash

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
sudo ip netns exec ns_client ip link set veth0 up
sudo ip netns exec ns_firewall ip link set veth1 up

#client-firewall veth pair configuration
sudo ip link add name veth2 type veth peer name veth3
sudo ip link set veth2 netns ns_firewall
sudo ip link set veth3 netns ns_server
sudo ip netns exec ns_server ip addr add 10.100.1.2/24 dev veth3
sudo ip netns exec ns_firewall ip link set veth2 up
sudo ip netns exec ns_server ip link set veth3 up

set +e
set +x
