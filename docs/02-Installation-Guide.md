# Installation Guide

This guide starts from a clean workstation with Vagrant and VirtualBox installed.

## 1. Start the VMs

```bash
vagrant up
vagrant status
```

Expected:

```text
controlplane   running
node01         running
node02         running
```

## 2. Install containerd on All Nodes

Run on `controlplane`, `node01`, and `node02`:

```bash
sudo bash /vagrant/scripts/install-containerd.sh
```

Verify:

```bash
systemctl status containerd
```

## 3. Install Kubernetes Packages on All Nodes

Run on all three nodes:

```bash
sudo bash /vagrant/scripts/install-kubernetes.sh
```

Verify:

```bash
kubeadm version
kubectl version --client
kubelet --version
```

## 4. Initialize the Control Plane

Run only on `controlplane`:

```bash
sudo kubeadm init \
  --apiserver-advertise-address=192.168.56.10 \
  --pod-network-cidr=10.244.0.0/16
```

Configure kubectl:

```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Verify:

```bash
kubectl get nodes
```

## 5. Install Flannel

```bash
bash /vagrant/scripts/install-flannel.sh
```

Verify Flannel uses the private Vagrant network:

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

## 6. Join Worker Nodes

On the control plane:

```bash
kubeadm token create --print-join-command
```

Run the generated command on `node01` and `node02`, for example:

```bash
sudo kubeadm join 192.168.56.10:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

Verify:

```bash
kubectl get nodes -o wide
```

Expected:

```text
controlplane   Ready   192.168.56.10
node01         Ready   192.168.56.11
node02         Ready   192.168.56.12
```

## 7. Install ingress-nginx

```bash
bash /vagrant/scripts/install-ingress.sh
```

Verify:

```bash
kubectl get pods -n ingress-nginx -o wide
kubectl get svc -n ingress-nginx
```

## 8. Install Cert-Manager

```bash
bash /vagrant/scripts/install-cert-manager.sh
```

Verify:

```bash
kubectl get pods -n cert-manager
```

## 9. Configure RBAC User

```bash
bash /vagrant/scripts/configure-rbac.sh
```

Verify:

```bash
kubectl auth can-i create deployments \
  --namespace web \
  --kubeconfig=$HOME/nginx-user.conf
```

Expected:

```text
yes
```

Verify denied access outside the namespace:

```bash
kubectl auth can-i create deployments \
  --namespace default \
  --kubeconfig=$HOME/nginx-user.conf
```

Expected:

```text
no
```

## 10. Deploy NGINX as the RBAC User

```bash
export KUBECONFIG=$HOME/nginx-user.conf
kubectl apply -f /vagrant/kubernetes/nginx-deployment.yaml
kubectl apply -f /vagrant/kubernetes/nginx-service.yaml
kubectl apply -f /vagrant/kubernetes/certificate-nginx.yaml
kubectl apply -f /vagrant/kubernetes/nginx-ingress.yaml
```

Verify:

```bash
kubectl get all -n web
kubectl get certificate -n web
kubectl get ingress -n web
```

## 11. Test Application Access

Find the HTTP NodePort:

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

Example:

```text
80:31680/TCP,443:30443/TCP
```

Test:

```bash
curl -H "Host: nginx.local" http://192.168.56.10:31680
```

Expected: NGINX welcome page HTML.
