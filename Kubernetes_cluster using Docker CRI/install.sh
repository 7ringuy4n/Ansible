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

# Add repo and Install packages
apt update
apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt update
apt install -y containerd.io docker-ce docker-ce-cli

# Create required directories
mkdir -p /etc/systemd/system/docker.service.d

# Create daemon json config file
tee /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

# Start and enable Services
systemctl daemon-reload 
systemctl restart docker
systemctl enable docker

# install CRI Docker
apt update
apt install git wget curl

VER=$(curl -s https://api.github.com/repos/Mirantis/cri-dockerd/releases/latest|grep tag_name | cut -d '"' -f 4|sed 's/v//g')
echo $VER
wget https://github.com/Mirantis/cri-dockerd/releases/download/v${VER}/cri-dockerd-${VER}.amd64.tgz
tar xvf cri-dockerd-${VER}.amd64.tgz
mv cri-dockerd/cri-dockerd /usr/local/bin/

wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service
wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket
mv cri-docker.socket cri-docker.service /etc/systemd/system/
sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service

systemctl daemon-reload
systemctl enable cri-docker.service
systemctl enable --now cri-docker.socket

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
#kubeadm config images pull --cri-socket /run/cri-dockerd.sock
kubeadm init \
    --apiserver-advertise-address=$controlip \
    --apiserver-cert-extra-sans=$controlip \
    --pod-network-cidr=$pod_cidr \
    --service-cidr=$service_cidr \
    --node-name=$hostname \
    --cri-socket /run/cri-dockerd.sock \
    --ignore-preflight-errors Swap >> /home/adminconfig.txt

tail -2 /home/adminconfig.txt >> ./script/join.sh

#Export Kubernetes configuration
export KUBECONFIG=/etc/kubernetes/admin.conf
cp -i /etc/kubernetes/admin.conf ./script/config
chown -R $user:$user ./script/
chmod -R 777 ./script/
chmod 655 /etc/kubernetes/admin.conf
mkdir -p /home/$user/.kube
cp -i /etc/kubernetes/admin.conf /home/$user/.kube/config
chown $user:$user /home/$user/.kube/config

#install Calico CNI
curl https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/calico.yaml -O
kubectl apply -f calico.yaml
kubectl apply -f https://raw.githubusercontent.com/techiescamp/kubeadm-scripts/main/manifests/metrics-server.yaml
sleep 30
kubectl get nodes -o wide