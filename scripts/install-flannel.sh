#!/usr/bin/env bash
set -euo pipefail
FLANNEL_IFACE="${FLANNEL_IFACE:-eth1}"
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
sleep 5
# Force Flannel to use Vagrant's private network interface rather than VirtualBox NAT.
if ! kubectl -n kube-flannel get daemonset kube-flannel-ds -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q -- "--iface=${FLANNEL_IFACE}"; then
  kubectl -n kube-flannel patch daemonset kube-flannel-ds \
    --type='json' \
    -p="[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--iface=${FLANNEL_IFACE}\"}]"
fi
kubectl rollout restart daemonset/kube-flannel-ds -n kube-flannel
kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=180s
kubectl get nodes -o custom-columns='NODE:.metadata.name,FLANNEL-PUBLIC-IP:.metadata.annotations.flannel\.alpha\.coreos\.com/public-ip'
