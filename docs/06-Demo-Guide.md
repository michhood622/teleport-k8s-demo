# Demo Guide

This guide provides a concise 15-minute demo flow.

## 1. Opening

Explain the assignment goal:

- Standard kubeadm Kubernetes cluster
- One control plane and two workers
- NGINX deployed through a restricted user
- RBAC with certificate-based authentication
- TLS issued by Cert-Manager
- Local reproducible environment

## 2. Show Architecture

```bash
kubectl get nodes -o wide
```

Explain:

- Vagrant built the VMs only
- Kubernetes was installed manually
- containerd is the runtime
- Flannel provides pod networking
- ingress-nginx exposes the application

## 3. Show Networking Fix

```bash
kubectl get nodes \
  -o custom-columns='NODE:.metadata.name,FLANNEL-PUBLIC-IP:.metadata.annotations.flannel\.alpha\.coreos\.com/public-ip'
```

Explain why Flannel must use `eth1` in this lab.

## 4. Show RBAC User

```bash
kubectl auth can-i create deployments \
  --namespace web \
  --kubeconfig=$HOME/nginx-user.conf

kubectl auth can-i create deployments \
  --namespace default \
  --kubeconfig=$HOME/nginx-user.conf
```

Explain:

- The user is authenticated by a signed client certificate.
- The RoleBinding grants access only in the `web` namespace.

## 5. Show NGINX Deployment

```bash
export KUBECONFIG=$HOME/nginx-user.conf
kubectl get all -n web
kubectl get ingress -n web
kubectl get certificate -n web
```

## 6. Test the Application

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
curl -H "Host: nginx.local" http://192.168.56.10:<HTTP_NODEPORT>
```

## 7. Discuss Tradeoffs

Pros:

- Native Kubernetes RBAC
- Least privilege
- Clear namespace isolation
- Reproducible lab
- Easy to troubleshoot and explain

Cons:

- Manual certificate lifecycle
- Per-user kubeconfig management
- No centralized identity provider
- Self-signed TLS is appropriate for demo only
- NodePort access is acceptable for a local lab but not the best production ingress pattern

## 8. Troubleshooting Story

Highlight the real issue found:

- Admission webhook timed out
- Ingress was not created
- Endpoint existed but was not reachable
- Flannel advertised `10.0.2.15` on every node
- Patch to `--iface=eth1` restored pod networking

This demonstrates systematic troubleshooting: observe, isolate, test, fix, verify.
