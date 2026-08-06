# RBAC Guide

## Objective

Create a Kubernetes user named `nginx-user` that can deploy and manage the NGINX application only in the `web` namespace.

## Authentication Flow

```text
Private key
   ↓
Certificate signing request
   ↓
Kubernetes CSR object
   ↓
Admin approval
   ↓
Signed client certificate
   ↓
User kubeconfig
   ↓
Role + RoleBinding
   ↓
Namespace-scoped API access
```

## Files

| File | Purpose |
|---|---|
| `namespace.yaml` | Creates the `web` namespace |
| `nginx-user-csr.yaml` | Kubernetes CSR object |
| `role.yaml` | Namespace-scoped permissions |
| `rolebinding.yaml` | Binds `nginx-user` to the Role |
| `nginx-user.conf` | Generated user kubeconfig; not committed |

## Manual RBAC Commands

Create private key:

```bash
openssl genrsa -out nginx-user.key 2048
```

Create CSR:

```bash
openssl req -new \
  -key nginx-user.key \
  -out nginx-user.csr \
  -subj "/CN=nginx-user/O=developers"
```

Base64-encode the CSR:

```bash
CSR_B64=$(cat nginx-user.csr | base64 | tr -d '\n')
```

Create the CSR manifest:

```bash
sed "s|<BASE64_CSR>|${CSR_B64}|g" \
  /vagrant/kubernetes/nginx-user-csr.yaml \
  > nginx-user-csr-rendered.yaml
```

Apply and approve:

```bash
kubectl apply -f nginx-user-csr-rendered.yaml
kubectl certificate approve nginx-user
```

Retrieve signed certificate:

```bash
kubectl get csr nginx-user \
  -o jsonpath='{.status.certificate}' \
  | base64 -d > nginx-user.crt
```

Create namespace and RBAC resources:

```bash
kubectl apply -f /vagrant/kubernetes/namespace.yaml
kubectl apply -f /vagrant/kubernetes/role.yaml
kubectl apply -f /vagrant/kubernetes/rolebinding.yaml
kubectl apply -f /vagrant/kubernetes/clusterissuer-selfsigned.yaml
```

Create user kubeconfig:

```bash
kubectl config set-cluster kubernetes \
  --server=https://192.168.56.10:6443 \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --kubeconfig=$HOME/nginx-user.conf

kubectl config set-credentials nginx-user \
  --client-key=nginx-user.key \
  --client-certificate=nginx-user.crt \
  --embed-certs=true \
  --kubeconfig=$HOME/nginx-user.conf

kubectl config set-context nginx-user \
  --cluster=kubernetes \
  --namespace=web \
  --user=nginx-user \
  --kubeconfig=$HOME/nginx-user.conf

kubectl config use-context nginx-user \
  --kubeconfig=$HOME/nginx-user.conf
```

## Permission Validation

Allowed:

```bash
kubectl auth can-i create deployments \
  --namespace web \
  --kubeconfig=$HOME/nginx-user.conf
```

Expected:

```text
yes
```

Denied:

```bash
kubectl auth can-i create deployments \
  --namespace default \
  --kubeconfig=$HOME/nginx-user.conf
```

Expected:

```text
no
```

Denied system namespace:

```bash
kubectl get pods -n kube-system \
  --kubeconfig=$HOME/nginx-user.conf
```

Expected:

```text
Error from server (Forbidden)
```

## Security Tradeoffs

This approach demonstrates Kubernetes-native certificate authentication and RBAC. It is useful for labs and for understanding Kubernetes authorization, but it has operational drawbacks:

- Certificate lifecycle management is manual unless automated.
- Revocation is awkward compared with identity-provider-backed access.
- Per-user kubeconfigs can become difficult to manage at scale.
- Least privilege requires careful Role design and ongoing review.

For production, a centralized identity provider, short-lived certificates, and audited access workflows would be preferred.
