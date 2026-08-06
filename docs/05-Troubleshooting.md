# Troubleshooting Guide

This guide documents the issues encountered during the build and the commands used to diagnose and resolve them.

## Issue 1: Vagrant Box Not Found

### Symptom

```text
Box 'ubuntu/noble64' could not be found
```

### Fix

Use the Bento Ubuntu 24.04 box:

```ruby
config.vm.box = "bento/ubuntu-24.04"
```

Clean up failed state:

```bash
vagrant destroy -f
rm -rf .vagrant
vagrant up
```

## Issue 2: Malformed Kubernetes APT Repository

### Symptom

```text
E: Malformed entry 1 in list file /etc/apt/sources.list.d/kubernetes.list (Suite)
```

### Cause

The repository entry was split across multiple lines.

### Fix

```bash
sudo rm -f /etc/apt/sources.list.d/kubernetes.list
sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo mkdir -p -m 755 /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
  | sudo gpg --dearmor \
  -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
```

## Issue 3: Flannel Advertised 10.0.2.15 for Every Node

### Symptom

```bash
kubectl get nodes \
  -o custom-columns='NODE:.metadata.name,FLANNEL-PUBLIC-IP:.metadata.annotations.flannel\.alpha\.coreos\.com/public-ip'
```

Output:

```text
controlplane   10.0.2.15
node01         10.0.2.15
node02         10.0.2.15
```

### Cause

Vagrant/VirtualBox creates a NAT interface as `eth0`. Each VM receives `10.0.2.15` on this interface. The private Vagrant network is `eth1` with `192.168.56.x`. Flannel selected the wrong interface.

### Fix

```bash
kubectl -n kube-flannel patch daemonset kube-flannel-ds \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--iface=eth1"}]'

kubectl rollout restart daemonset/kube-flannel-ds -n kube-flannel
kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=180s
```

Verify:

```bash
kubectl get nodes \
  -o custom-columns='NODE:.metadata.name,FLANNEL-PUBLIC-IP:.metadata.annotations.flannel\.alpha\.coreos\.com/public-ip'
```

Expected:

```text
controlplane   192.168.56.10
node01         192.168.56.11
node02         192.168.56.12
```

## Issue 4: ingress-nginx Admission Webhook Timeout

### Symptom

```text
failed calling webhook "validate.nginx.ingress.kubernetes.io": context deadline exceeded
```

### Cause

The Kubernetes API server could not reach the ingress-nginx admission webhook pod because pod networking was broken by Flannel using the wrong interface.

### Diagnostic Commands

```bash
kubectl get pods -n ingress-nginx -o wide
kubectl get endpoints ingress-nginx-controller-admission -n ingress-nginx -o wide
kubectl get pods -n kube-flannel -o wide
kubectl get nodes -o wide
```

Direct webhook test:

```bash
WEBHOOK_IP=$(kubectl get endpoints ingress-nginx-controller-admission \
  -n ingress-nginx \
  -o jsonpath='{.subsets[0].addresses[0].ip}')

curl -k --connect-timeout 5 "https://${WEBHOOK_IP}:8443/healthz"
```

### Fix

Patch Flannel to use `eth1`, restart Flannel, restart ingress-nginx, and retry the Ingress.

```bash
kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s
kubectl apply --kubeconfig=$HOME/nginx-user.conf -f /vagrant/kubernetes/nginx-ingress.yaml
```

## Issue 5: No Ingress Created

### Symptom

```bash
kubectl get ingress --kubeconfig=nginx-user.conf -n web
```

Output:

```text
No resources found in web namespace.
```

### Explanation

The Ingress was not created because the API server rejected it before admission completed. Once the webhook became reachable, the same manifest succeeded.
