# Architecture

## Objective

Build a standard Kubernetes cluster using kubeadm with one control plane node and two worker nodes, then deploy a static NGINX site using a restricted Kubernetes user.

## Topology

```text
Workstation
   |
   | Vagrant / VirtualBox
   v
+----------------------+        +----------------------+        +----------------------+
| controlplane         |        | node01               |        | node02               |
| 192.168.56.10        |        | 192.168.56.11        |        | 192.168.56.12        |
| kube-apiserver       |        | kubelet              |        | kubelet              |
| controller-manager   |        | kube-proxy           |        | kube-proxy           |
| scheduler            |        | containerd           |        | containerd           |
| etcd                 |        | workloads            |        | workloads            |
+----------------------+        +----------------------+        +----------------------+
```

## Components

| Component | Purpose |
|---|---|
| Vagrant | Builds reproducible Ubuntu VMs |
| VirtualBox | Local hypervisor |
| Ubuntu 24.04 | Node operating system |
| containerd | Container runtime |
| kubeadm | Kubernetes bootstrap tool |
| kubelet | Node agent |
| kubectl | Kubernetes CLI |
| Flannel | Pod networking |
| ingress-nginx | HTTP ingress controller |
| Cert-Manager | Issues TLS certificates |
| RBAC | Namespace-scoped authorization |
| Kubernetes CSR API | Certificate-based user authentication |

## Networking Design

Each Vagrant VM has two main interfaces:

| Interface | Network | Purpose |
|---|---|---|
| eth0 | 10.0.2.15 | VirtualBox NAT |
| eth1 | 192.168.56.x | Vagrant private network |

Kubernetes node IPs and Flannel must use `eth1`. If Flannel uses `eth0`, all nodes advertise the same `10.0.2.15` address and cross-node pod routing fails.

## Security Design

The default Kubernetes administrator is used only for cluster bootstrapping and RBAC setup. The NGINX application is deployed by `nginx-user`, a certificate-authenticated Kubernetes user with namespace-scoped permissions in the `web` namespace.

This demonstrates least privilege:

- `nginx-user` can manage NGINX resources in `web`
- `nginx-user` cannot access `kube-system`
- `nginx-user` cannot deploy workloads in other namespaces
