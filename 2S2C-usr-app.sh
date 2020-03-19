#!/bin/bash
function cleanup {
  set +e
  set +x
  NSM_NAMESPACE=default make helm-delete-nsm
  NSM_NAMESPACE=default make helm-delete-example
  rm -r /home/kubernetes/.helm
  rm /home/kubernetes/bin/helm
  cd ../..
  yes | rm -r nsm
}
trap cleanup EXIT

set -x
set -e

#specific commands for my cluster, comment until mkdir nsm command
sudo swapoff -a
sudo systemctl restart docker
sudo systemctl restart kubelet
sleep 1m
kubectl get nodes
cd Raffaele

#create nsm dir, clone nsm project and move to version of January 28th, 2020
mkdir nsm
cd nsm
git clone https://github.com/networkservicemesh/networkservicemesh.git
cd networkservicemesh
git checkout dcd4809f9128a3d4074d9caae8f0c5dca28a000c

#install helm
./scripts/install-helm.sh
helm init

#clone example helm deployment
git clone https://github.com/RaffaeleTrani/2S.git deployments/helm/example

#install nsm and example deployment
NSM_NAMESPACE=default make helm-install-nsm
NSM_NAMESPACE=default make helm-install-example

#get names of pods
kubectl="kubectl -n default"
NSC=$(${kubectl} get pods -o=name | grep iperf-client | sed 's@.*/@@')
NSE=$(${kubectl} get pods -o=name | grep iperf-server | sed 's@.*/@@')
FW=$(${kubectl} get pods -o=name | grep firewall | sed 's@.*/@@')

# NOTE: NSM configuration comes with two different IP addressing for client-firewall and firewall-server communication.
# As the firewall application is implemented as a transparent firewall, the firewall pod needs to be transparent, so with
# following commands I deleted IP addresses in firewall's interfaces and configured server's interface to be the text hop
# of client, as if the communication between them was direct.

#get client interface ip and server interface ip and mac
ipClient=$(${kubectl} exec $NSC -c iperf3-client -- ip a | grep nsm0 | grep inet | awk '{print $2}' | sed 's/.\{3\}$//')
ipServer=$(${kubectl} exec $NSE -c iperf3-server -- ip a | grep nsm | grep inet | awk '{print $2}')
mac=$(${kubectl} exec $NSE -c iperf3-server -- ip a | grep -A 1 -m 1 nsm | grep link/ether | awk '{print $2}')

#get ip of firewall's interfaces and delete them to make firewall transparent
${kubectl} exec $FW -c firewall-container -- apt-get install iproute2 -y
ifFtoC=$(${kubectl} exec $FW -c firewall-container -- ip a | grep nsm | awk '{print $2}' | grep nsm | sed 's/.$//')
ipFtoC=$(${kubectl} exec $FW -c firewall-container -- ip a | grep nsm | grep inet | awk '{print $2}')
ifFtoS=$(${kubectl} exec $FW -c firewall-container -- ip a | grep -B 2 172.16.2.1 | awk 'NR==1{print $2}' | sed 's/.$//')
${kubectl} exec $FW -c firewall-container -- ip a del 172.16.2.1/30 dev $ifFtoS
${kubectl} exec $FW -c firewall-container -- ip a del $ipFtoC dev $ifFtoC


ifName=$(${kubectl} exec $NSE -c iperf3-server -- ip a | grep nsm | awk '{print $2}' | grep nsm | sed 's/.$//')
${kubectl} exec $NSE -c iperf3-server -- ip a del $ipServer dev $ifName
${kubectl} exec $NSE -c iperf3-server -- ip a add $ipFtoC dev $ifName
${kubectl} exec $NSE -c iperf3-server -- ip r add $ipClient dev $ifName
ipServ=$(echo $ipFtoC | sed 's/.\{3\}$//')

#create routing entry in client pod to send traffic to server
${kubectl} exec $NSC -c iperf3-client -- ip r add $ipServ dev nsm0

#update arp entry in client with mac of server
${kubectl} exec $NSC -c iperf3-client -- bash -c "apt-get update && apt-get install net-tools"
${kubectl} exec $NSC -c iperf3-client -- arp -d $ipServ
${kubectl} exec $NSC -c iperf3-client -- arp -s $ipServ $mac

#delete default route in firewall to disable kernel ip packets forwarding and start firewall application
defRoute=$(${kubectl} exec $FW -c firewall-container -- ip r | grep default)
${kubectl} exec $FW -c firewall-container -- ip r del $defRoute
${kubectl} exec $FW -c firewall-container -- ip r
${kubectl} exec $FW -c firewall-container -- cmake-build-debug/untitled nsm & > /dev/null 2>&1

${kubectl} exec $NSC -c iperf3-client -- ping $ipServ -c 5

echo "CONFIGURATION COMPLETED, START IPERF TESTS:"

#start iperf test
#NOTE: iperf server is already started and it does not require the specific command in this case
${kubectl} exec $NSC -c iperf3-client -- iperf3 -c $ipServ -t 60 -V

echo "IPERF TESTS COMPLETED, CHECK INTERFACES OF PODS"

${kubectl} exec $NSC -c iperf3-client -- ip -s link | awk '/nsm/,0'
${kubectl} exec $NSE -c iperf3-server -- ip -s link | awk '/nsm/,0'
${kubectl} exec $FW -c firewall-container -- bash -c "ip -s link"
