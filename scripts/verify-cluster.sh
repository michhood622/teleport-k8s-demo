#!/usr/bin/env bash
set -euo pipefail
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get nodes -o custom-columns='NODE:.metadata.name,FLANNEL-PUBLIC-IP:.metadata.annotations.flannel\.alpha\.coreos\.com/public-ip'
kubectl get svc ingress-nginx-controller -n ingress-nginx || true
kubectl get all -n web || true
kubectl get ingress -n web || true
kubectl auth can-i create deployments --namespace web --kubeconfig="$HOME/nginx-user.conf" || true
kubectl auth can-i create deployments --namespace default --kubeconfig="$HOME/nginx-user.conf" || true
