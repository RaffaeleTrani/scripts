#!/bin/bash
function cleanup {
  set +e
  set +x
  NSM_NAMESPACE=default make helm-delete-nsm
  NSM_NAMESPACE=default make helm-delete-hybrid-example
  rm -r /home/kubernetes/.helm
  rm /home/kubernetes/bin/helm
  cd ../..
  yes | rm -r nsm
}
trap cleanup EXIT

set -x
set -e

#specific commannds for my cluster, comment up to mkdir nsm command
sudo swapoff -a
sudo systemctl restart docker
sudo systemctl restart kubelet
sleep 1m
kubectl get nodes
cd Raffaele

mkdir nsm
cd nsm
git clone https://github.com/networkservicemesh/networkservicemesh.git
cd networkservicemesh
git checkout dcd4809f9128a3d4074d9caae8f0c5dca28a000c
./scripts/install-helm.sh
helm init

git clone https://github.com/RaffaeleTrani/3S1C.git deployments/helm/hybrid-example

NSM_NAMESPACE=default make helm-install-nsm
NSM_NAMESPACE=default make helm-install-hybrid-example

kubectl="kubectl -n default"
NSC=$(${kubectl} get pods -o=name | grep iperf-client | sed 's@.*/@@')
NSE=$(${kubectl} get pods -o=name | grep iperf-server | sed 's@.*/@@')
FW=$(${kubectl} get pods -o=name | grep vpp-firewall | sed 's@.*/@@')

ipServer=$(${kubectl} exec $NSE -c iperf3-server -- ip a | grep nsm | grep inet | awk '{print $2}' | sed 's/.\{3\}$//')

${kubectl} exec $NSC -c iperf3-client -- iperf3 -c $ipServer --port 5201 -t 60 -V

echo "IPERF TESTS COMPLETED, CHECK INTERFACES OF PODS"

${kubectl} exec $NSC -c iperf3-client -- ip -s link | awk '/nsm/,0'
${kubectl} exec $NSE -c iperf3-server -- ip -s link | awk '/nsm/,0'
${kubectl} exec $FW -c firewall-container -- vppctl show int
