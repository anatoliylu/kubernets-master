#!/bin/bash

# Зупинка служб Kubernetes
sudo systemctl stop kubelet
sudo systemctl stop kube-apiserver
sudo systemctl stop kube-controller-manager
sudo systemctl stop kube-scheduler
sudo systemctl stop etcd

# Видалення конфігураційних файлів та даних etcd
sudo rm /etc/kubernetes/manifests/kube-apiserver.yaml
sudo rm /etc/kubernetes/manifests/kube-controller-manager.yaml
sudo rm /etc/kubernetes/manifests/kube-scheduler.yaml
sudo rm /etc/kubernetes/manifests/etcd.yaml
sudo rm -rf /var/lib/etcd

# Скидання кластера Kubernetes
sudo kubeadm reset

# Налаштування хоста
sudo hostnamectl set-hostname "k8s-master-noble"
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo modprobe overlay
sudo modprobe br_netfilter

sudo tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

sudo tee /etc/sysctl.d/kubernetes.conf <<EOT
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOT

sudo sysctl --system

# Встановлення Docker та Containerd
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo apt update && sudo apt install containerd.io -y
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

# Встановлення Kubernetes
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/k8s.gpg
echo 'deb [signed-by=/etc/apt/keyrings/k8s.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/k8s.list
sudo apt update
sudo apt install kubelet kubeadm kubectl -y

# Ініціалізація кластера Kubernetes з ігноруванням попередніх перевірок
sudo kubeadm init --control-plane-endpoint=k8s-master-noble --ignore-preflight-errors=FileAvailable--etc-kubernetes-pki-ca.crt

# Налаштування kubeconfig
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Встановлення Calico
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Перевірка станів вузлів та підпор
kubectl get nodes
kubectl get pods -n kube-system

# Список вузлів та їх CIDR підпор
declare -A NODES=(
  ["k8s-master-noble"]="10.244.0.0/24"
  ["k8s-work-noble"]="10.244.1.0/24"
)

# Призначення CIDR підпори кожному вузлу
for NODE_NAME in "${!NODES[@]}"; do
  POD_CIDR="${NODES[$NODE_NAME]}"
  echo "Призначення CIDR підпори $POD_CIDR вузлу $NODE_NAME"
  kubectl patch node $NODE_NAME -p "{\"spec\":{\"podCIDR\":\"$POD_CIDR\"}}"
done

# Перевірка призначених CIDR підпорів
for NODE_NAME in "${!NODES[@]}"; do
  echo "Перевірка CIDR підпори для вузла $NODE_NAME:"
  kubectl get nodes $NODE_NAME -o jsonpath='{.spec.podCIDR}'
done
