#!/bin/bash
function cleanup {
  set +e
  set +x
  NSM_NAMESPACE=default make helm-delete-nsm
  NSM_NAMESPACE=default make helm-delete-vpp-example
  rm -r /home/kubernetes/.helm
  rm /home/kubernetes/bin/helm
  cd ../..
  yes | rm -r nsm
}
trap cleanup EXIT

set -x
set -e

#specific commannds for my cluster, comment up to mkdir nsm command
#sudo swapoff -a
#sudo systemctl restart docker
#sudo systemctl restart kubelet
#sleep 1m
#kubectl get nodes
#cd Raffaele

mkdir nsm
cd nsm
git clone https://github.com/networkservicemesh/networkservicemesh.git
cd networkservicemesh
git checkout dcd4809f9128a3d4074d9caae8f0c5dca28a000c
./scripts/install-helm.sh
helm init

git clone https://github.com/RaffaeleTrani/3S2C.git deployments/helm/vpp-example

NSM_NAMESPACE=default make helm-install-nsm
NSM_NAMESPACE=default make helm-install-vpp-example

kubectl="kubectl -n default"
NSC=$(${kubectl} get pods -o=name | grep vpp-iperf-client | sed 's@.*/@@')
NSE=$(${kubectl} get pods -o=name | grep vpp-iperf-server | sed 's@.*/@@')
FW=$(${kubectl} get pods -o=name | grep vpp-firewall | sed 's@.*/@@')

${kubectl} exec $NSC -- bash -c "apt-get update && apt-get install iperf3 -y"
${kubectl} exec $NSC -- touch vcl.conf
${kubectl} exec $NSC -- bash -c "cat > vcl.conf <<EOF
vcl {
  rx-fifo-size 4000000
  tx-fifo-size 4000000
  app-scope-local
  app-scope-global
  api-socket-name /run/vpp-api.sock
}
EOF"

${kubectl} exec $NSC -- cat vcl.conf

${kubectl} exec $NSE -- bash -c "apt-get update && apt-get install iperf3 -y"
${kubectl} exec $NSE -- touch vcl.conf
${kubectl} exec $NSE -- bash -c "cat > vcl.conf <<EOF
vcl {
  rx-fifo-size 4000000
  tx-fifo-size 4000000
  app-scope-local
  app-scope-global
  api-socket-name /run/vpp-api.sock
}
EOF"

${kubectl} exec $NSE -- bash -c "LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libvcl_ldpreload.so VCL_CONFIG=vcl.conf taskset --cpu-list 6-7 iperf3 -4 -s -D"

${kubectl} exec $NSC -- bash -c "LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libvcl_ldpreload.so VCL_CONFIG=vcl.conf taskset --cpu-list 4-5 iperf3 -c 172.16.2.2 --port 5201 -t 60 -V"

echo "IPERF TESTS COMPLETED, CHECK INTERFACES OF PODS"

#${kubectl} exec $NSC -- vppctl show int
#${kubectl} exec $NSE -- vppctl show int
${kubectl} exec $FW -- bash -c "vppctl show int"
