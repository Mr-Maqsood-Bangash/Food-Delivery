#!/bin/bash
set -e
exec > /var/log/user-data.log 2>&1
echo "=== Starting userdata provisioning: $(date) ==="

# ------------------------------------------------------------------
# 1. Base packages
# ------------------------------------------------------------------
apt-get update -y
apt-get install -y curl wget git ca-certificates gnupg lsb-release

# ------------------------------------------------------------------
# 2. Install Docker
# ------------------------------------------------------------------
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# ------------------------------------------------------------------
# 3. Install kubectl
# ------------------------------------------------------------------
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/kubectl

# ------------------------------------------------------------------
# 4. Install kind
# ------------------------------------------------------------------
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
chmod +x ./kind
mv ./kind /usr/local/bin/kind

# ------------------------------------------------------------------
# 5. Install Helm
# ------------------------------------------------------------------
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# ------------------------------------------------------------------
# 6. Install ArgoCD CLI
# ------------------------------------------------------------------
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd-linux-amd64
mv argocd-linux-amd64 /usr/local/bin/argocd

# ------------------------------------------------------------------
# 7. MongoDB hostPath storage directory
# ------------------------------------------------------------------
mkdir -p /mnt/kind-storage/mongo
chmod -R 777 /mnt/kind-storage/mongo

# ------------------------------------------------------------------
# 8. Clone the application repository (as ubuntu user)
# ------------------------------------------------------------------
sudo -u ubuntu git clone ${repo_url} /home/ubuntu/Food-Delivery

# ------------------------------------------------------------------
# 9. Kind cluster config
# ------------------------------------------------------------------
cat > /home/ubuntu/kind-config.yaml << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    image: kindest/node:v1.28.0
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
      - containerPort: 30007
        hostPort: 30007
        protocol: TCP
    extraMounts:
      - hostPath: /mnt/kind-storage/mongo
        containerPath: /data/mongo
  - role: worker
    image: kindest/node:v1.28.0
    extraMounts:
      - hostPath: /mnt/kind-storage/mongo
        containerPath: /data/mongo
  - role: worker
    image: kindest/node:v1.28.0
    extraMounts:
      - hostPath: /mnt/kind-storage/mongo
        containerPath: /data/mongo
EOF
chown ubuntu:ubuntu /home/ubuntu/kind-config.yaml

# ------------------------------------------------------------------
# 10. Create kind cluster (as ubuntu user, needs docker group membership)
# ------------------------------------------------------------------
sudo -u ubuntu newgrp docker << 'EOSU'
kind create cluster --config /home/ubuntu/kind-config.yaml --name food-delivery
EOSU

# Wait for the API server to be reachable
sudo -u ubuntu bash -c 'until kubectl get nodes; do echo "waiting for cluster..."; sleep 5; done'

# ------------------------------------------------------------------
# 11. Install ArgoCD
# ------------------------------------------------------------------
sudo -u ubuntu kubectl create namespace argocd
sudo -u ubuntu kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for ArgoCD pods to be ready..."
sudo -u ubuntu kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s || true

# ------------------------------------------------------------------
# 12. Install ArgoCD Image Updater (via Helm)
# ------------------------------------------------------------------
sudo -u ubuntu helm repo add argo https://argoproj.github.io/argo-helm
sudo -u ubuntu helm repo update
sudo -u ubuntu helm install argocd-image-updater argo/argocd-image-updater -n argocd

# ------------------------------------------------------------------
# 13. Apply Application, ConfigMap, and ImageUpdater manifests from repo
# ------------------------------------------------------------------
APP_DIR="/home/ubuntu/Food-Delivery/three-tier-app-helm-chart/three-tier-app"

if [ -f "$${APP_DIR}/argocd-application.yaml" ]; then
  sudo -u ubuntu kubectl apply -f "$${APP_DIR}/argocd-application.yaml"
fi

if [ -f "$${APP_DIR}/argocd-image-updater-configmap.yaml" ]; then
  sudo -u ubuntu kubectl apply -f "$${APP_DIR}/argocd-image-updater-configmap.yaml"
fi

if [ -f "$${APP_DIR}/imageupdater-cr.yaml" ]; then
  sudo -u ubuntu kubectl apply -f "$${APP_DIR}/imageupdater-cr.yaml"
fi

echo "=== Userdata provisioning complete: $(date) ==="