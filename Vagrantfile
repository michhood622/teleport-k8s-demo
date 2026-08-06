Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"

  nodes = {
    "controlplane" => { ip: "192.168.56.10", memory: 4096, cpus: 2 },
    "node01"       => { ip: "192.168.56.11", memory: 3072, cpus: 2 },
    "node02"       => { ip: "192.168.56.12", memory: 3072, cpus: 2 }
  }

  nodes.each do |hostname, settings|
    config.vm.define hostname do |node|
      node.vm.hostname = hostname
      node.vm.network "private_network", ip: settings[:ip]

      node.vm.provider "virtualbox" do |vb|
        vb.name = "teleport-#{hostname}"
        vb.memory = settings[:memory]
        vb.cpus = settings[:cpus]
      end

      # Vagrant performs OS preparation only. Kubernetes is installed manually.
      node.vm.provision "shell", inline: <<-SHELL
        set -eux

        hostnamectl set-hostname #{hostname}

        sed -i '/controlplane/d' /etc/hosts
        sed -i '/node01/d' /etc/hosts
        sed -i '/node02/d' /etc/hosts
        cat <<HOSTS >> /etc/hosts
192.168.56.10 controlplane
192.168.56.11 node01
192.168.56.12 node02
HOSTS

        swapoff -a
        sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab

        cat <<MODULES >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
MODULES
        modprobe overlay
        modprobe br_netfilter

        cat <<SYSCTL >/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables=1
net.bridge.bridge-nf-call-iptables=1
net.ipv4.ip_forward=1
SYSCTL
        sysctl --system

        echo "KUBELET_EXTRA_ARGS=--node-ip=#{settings[:ip]}" > /etc/default/kubelet

        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y \
          curl vim git wget bash-completion apt-transport-https \
          ca-certificates gnupg software-properties-common openssl
      SHELL
    end
  end
end
