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
ipClient=192.168.254.4/24
netClient=192.168.254.0/24
netServer=172.16.2.0/30

kubectl="kubectl -n default"
NSC=$(${kubectl} get pods -o=name | grep ns-client | sed 's@.*/@@')
NSE=$(${kubectl} get pods -o=name | grep iperf-server | sed 's@.*/@@')
FW=$(${kubectl} get pods -o=name | grep vpp-firewall | sed 's@.*/@@')

ipNSClient=$(${kubectl} exec $NSC -c ns-client -- ip a | grep nsm0 | grep inet | awk '{print $2}' | sed 's/.\{3\}$//')
ipServer=$(${kubectl} exec $NSE -c iperf3-server -- ip a | grep nsm | grep inet | awk '{print $2}' | sed 's/.\{3\}$//')

${kubectl} exec $NSC -c ns-client -- ip route add $netClient via ????? dev nsm0
${kubectl} exec $NSE -c iperf3-server -- ip route add
 $netClient via $ipNSClient

sshpass -p 'netlab' ssh -o "StrictHostKeyChecking=no" cube2@130.192.225.62 /bin/bash <<'SSH_EOF'
sudo ip route add $netServer via 192.168.254.2 dev (metti qui il device di cube2)
iperf3 -c $ipServer -t 60 -V
exit
SSH_EOF

echo "IPERF TESTS COMPLETED, CHECK INTERFACES OF PODS"

${kubectl} exec $NSC -c ns-client -- ip -s link | awk '/nsm/,0'
${kubectl} exec $NSE -c iperf3-server -- ip -s link | awk '/nsm/,0'
${kubectl} exec $FW -- vppctl show int
