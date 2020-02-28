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

#specific commands for my cluster, comment up to mkdir nsm command
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

git clone https://github.com/RaffaeleTrani/2S.git deployments/helm/example

NSM_NAMESPACE=default FORWARDING_PLANE=kernel make helm-install-nsm
NSM_NAMESPACE=default FORWARDING_PLANE=kernel make helm-install-example

kubectl="kubectl -n default"
NSC=$(${kubectl} get pods -o=name | grep iperf-client | sed 's@.*/@@')
NSE=$(${kubectl} get pods -o=name | grep iperf-server | sed 's@.*/@@')
FW=$(${kubectl} get pods -o=name | grep firewall | sed 's@.*/@@')

ipClient=$(${kubectl} exec $NSC -c iperf3-client -- ip a | grep nsm0 | grep inet | awk '{print $2}' | sed 's/.\{3\}$//')
ipServer=$(${kubectl} exec $NSE -c iperf3-server -- ip a | grep nsm | grep inet | awk '{print $2}' | sed 's/.\{3\}$//')

lastSegment=$(echo "${ipClient}" | cut -d . -f 4 | cut -d / -f 1)
nextOp=$((lastSegment + 1))
targetIp="172.16.1.${nextOp}"
${kubectl} exec $NSC -c iperf3-client -- ip route add $ipServer via $targetIp dev nsm0

ifName=$(${kubectl} exec $NSE -c iperf3-server -- ip a | grep nsm | awk '{print $2}' | grep nsm | sed 's/@.*//')
lastSegment=$(echo "${ipServer}" | cut -d . -f 4 | cut -d / -f 1)
nextOp=$((lastSegment - 1))
targetIp="172.16.2.${nextOp}"
${kubectl} exec $NSE -c iperf3-server -- ip route add $ipClient via $targetIp dev $ifName
${kubectl} exec $FW -c firewall-container -- apt-get install iproute2 -y
${kubectl} exec $FW -c firewall-container -- apt-get install iptables -y
for ip in $(kubectl exec $FW -c firewall-container -- ip a | grep inet | awk '{print $2}'); do
        if [[ $ip == 172.16.1.* ]]; then
        inIf=$(kubectl exec $FW -c firewall-container -- ip a | grep "inet 172.16.1" | awk '{print $7}')
        elif [[ $ip == 172.16.2.* ]]; then
        outIf=$(kubectl exec $FW -c firewall-container -- ip a | grep "inet 172.16.2" | awk '{print $7}')
        fi
done
echo $inIf
echo $outIf

#firewall application iptables
${kubectl} exec $FW -c firewall-container -- iptables -A FORWARD -i $inIf -o $outIf -j ACCEPT
${kubectl} exec $FW -c firewall-container -- iptables -A FORWARD -i $outIf -o $inIf -j ACCEPT

${kubectl} exec $NSC -c iperf3-client -- iperf3 -c $ipServer -t 60 -V

echo "IPERF TESTS COMPLETED, CHECK INTERFACES OF PODS"

${kubectl} exec $NSC -c iperf3-client -- ip -s link | awk '/nsm/,0'
${kubectl} exec $NSE -c iperf3-server -- ip -s link | awk '/nsm/,0'
${kubectl} exec $FW -c firewall-container -- ip -s link | awk '/nsm/,0'
