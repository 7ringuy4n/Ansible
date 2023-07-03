#!/bin/bash
hostname=$(hostname -s)
controlip=$(hostname -I)
pod_cidr="192.168.0.0/16"
service_cidr="172.17.1.0/18"
user="tringuyen"
Node01="172.16.3.175"

cat <<EOF | tee /etc/ansible/hosts
[Nodes]
Node01 ansible_host=$Node01 ansible_port=22 ansible_user=$user
EOF

cat <<EOF | tee /etc/modules-load.d/modules.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1
sysctl --system

apt-get update
apt-get install \
ca-certificates \
curl \
gnupg \
lsb-release -y

OS="xUbuntu_22.04"
VERSION=1.26
echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list
curl -L https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/Release.key | apt-key add -
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | apt-key add -

# Install CRI-O
sudo apt update
sudo apt install cri-o cri-o-runc

# Start and enable Service
sudo systemctl daemon-reload
sudo systemctl restart crio
sudo systemctl enable crio
systemctl status crio

sudo kubeadm config images pull --cri-socket /var/run/crio/crio.sock

# CRI-O
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --cri-socket /var/run/crio/crio.sock \
  --upload-certs \
  --control-plane-endpoint=k8s-cluster.computingforgeeks.com















#option1
swapoff -a
systemctl mask swap.target
apt-get update
apt-get install -y apt-transport-https ca-certificates curl
mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list

curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s \
https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"

chmod +x ./kubectl
mv ./kubectl /usr/local/bin/kubectl

apt-get update
apt-get install -y kubelet=1.26.1-00 kubeadm=1.26.1-00 kubectl=1.26.1-00
systemctl enable kubelet

#Setup MasterNode
kubeadm init \
    --apiserver-advertise-address=$controlip \
    --apiserver-cert-extra-sans=$controlip \
    --pod-network-cidr=$pod_cidr \
    --service-cidr=$service_cidr \
    --node-name=$hostname \
    --cri-socket /run/containerd/containerd.sock \
    --ignore-preflight-errors Swap >> /home/adminconfig.txt

tail -2 /home/adminconfig.txt >> ./script/join.sh

export KUBECONFIG=/etc/kubernetes/admin.conf
cp -i /etc/kubernetes/admin.conf ./script/config
chown -R $user:$user ./script/
chmod -R 777 ./script/
chmod 655 /etc/kubernetes/admin.conf
mkdir -p /home/$user/.kube
cp -i /etc/kubernetes/admin.conf /home/$user/.kube/config
chown $user:$user /home/$user/.kube/config

#Run Ansible
ansible-playbook Setup.yml -l Nodes --become --ask-become-pass

#install Calico CNI
curl https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/calico.yaml -O
kubectl apply -f calico.yaml
kubectl apply -f https://raw.githubusercontent.com/techiescamp/kubeadm-scripts/main/manifests/metrics-server.yaml
sleep 120
kubectl label node node01 node-role.kubernetes.io/worker=worker
kubectl apply -f ./script/testwebserver.yml
kubectl get nodes -o wide
