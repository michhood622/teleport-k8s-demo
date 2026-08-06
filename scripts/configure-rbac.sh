#!/usr/bin/env bash
set -euo pipefail
cd "$HOME"
openssl genrsa -out nginx-user.key 2048
openssl req -new -key nginx-user.key -out nginx-user.csr -subj "/CN=nginx-user/O=developers"
CSR_B64=$(cat nginx-user.csr | base64 | tr -d '\n')
sed "s|<BASE64_CSR>|${CSR_B64}|g" /vagrant/kubernetes/nginx-user-csr.yaml > nginx-user-csr-rendered.yaml
kubectl apply -f /vagrant/kubernetes/namespace.yaml
kubectl apply -f nginx-user-csr-rendered.yaml
kubectl certificate approve nginx-user
kubectl get csr nginx-user -o jsonpath='{.status.certificate}' | base64 -d > nginx-user.crt
kubectl apply -f /vagrant/kubernetes/role.yaml
kubectl apply -f /vagrant/kubernetes/rolebinding.yaml
kubectl apply -f /vagrant/kubernetes/clusterissuer-selfsigned.yaml
kubectl config set-cluster kubernetes \
  --server=https://192.168.56.10:6443 \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --kubeconfig="$HOME/nginx-user.conf"
kubectl config set-credentials nginx-user \
  --client-key="$HOME/nginx-user.key" \
  --client-certificate="$HOME/nginx-user.crt" \
  --embed-certs=true \
  --kubeconfig="$HOME/nginx-user.conf"
kubectl config set-context nginx-user \
  --cluster=kubernetes \
  --namespace=web \
  --user=nginx-user \
  --kubeconfig="$HOME/nginx-user.conf"
kubectl config use-context nginx-user --kubeconfig="$HOME/nginx-user.conf"
kubectl auth can-i create deployments --namespace web --kubeconfig="$HOME/nginx-user.conf"
kubectl auth can-i create deployments --namespace default --kubeconfig="$HOME/nginx-user.conf"
