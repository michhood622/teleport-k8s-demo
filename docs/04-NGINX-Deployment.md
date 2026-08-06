# NGINX Deployment Guide

## Objective

Deploy a static NGINX site in the `web` namespace using the restricted `nginx-user` kubeconfig.

## Resources

| Resource | File |
|---|---|
| Namespace | `namespace.yaml` |
| Deployment | `nginx-deployment.yaml` |
| Service | `nginx-service.yaml` |
| Certificate | `certificate-nginx.yaml` |
| Ingress | `nginx-ingress.yaml` |

## Deploy as nginx-user

```bash
export KUBECONFIG=$HOME/nginx-user.conf
kubectl apply -f /vagrant/kubernetes/nginx-deployment.yaml
kubectl apply -f /vagrant/kubernetes/nginx-service.yaml
kubectl apply -f /vagrant/kubernetes/certificate-nginx.yaml
kubectl apply -f /vagrant/kubernetes/nginx-ingress.yaml
```

## Verify Workloads

```bash
kubectl get pods -n web -o wide
kubectl get svc -n web
kubectl get ingress -n web
kubectl get certificate -n web
kubectl get secret nginx-tls -n web
```

## Test HTTP Access

Find the HTTP NodePort:

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

Example:

```text
80:31680/TCP
```

Test:

```bash
curl -H "Host: nginx.local" http://192.168.56.10:31680
```

Expected output includes:

```html
Welcome to nginx!
```

## Test HTTPS Access

Find the HTTPS NodePort:

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

Example:

```text
443:30443/TCP
```

Test with self-signed certificate:

```bash
curl -k -H "Host: nginx.local" https://192.168.56.10:30443
```

Expected output includes:

```html
Welcome to nginx!
```
