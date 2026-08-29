#!/bin/bash
set -e
exec > /var/log/user-data.log 2>&1

REPO_URL="${repo_url}"

echo "=== Starting userdata provisioning: $$(date) ==="
echo "Using repo URL: $${REPO_URL}"

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
KUBECTL_VERSION=$$(curl -L -s https://dl.k8s.io/release/stable.txt)
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
# 5. Install Helm (private server)
# ------------------------------------------------------------------
if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh
fi
helm version --short

# ------------------------------------------------------------------
# 6. Install ArgoCD CLI
# ------------------------------------------------------------------
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd-linux-amd64
mv argocd-linux-amd64 /usr/local/bin/argocd

# ------------------------------------------------------------------
# 7. MongoDB hostPath storage directories (default + blue + green)
# ------------------------------------------------------------------
mkdir -p /mnt/kind-storage/mongo
mkdir -p /mnt/kind-storage/blue-mongo
mkdir -p /mnt/kind-storage/green-mongo
chmod -R 777 /mnt/kind-storage/mongo /mnt/kind-storage/blue-mongo /mnt/kind-storage/green-mongo

# ------------------------------------------------------------------
# 8. Clone the application repository (as ubuntu user)
# ------------------------------------------------------------------
if [ ! -d /home/ubuntu/Food-Delivery ]; then
  sudo -u ubuntu bash -lc 'git clone "$1" /home/ubuntu/Food-Delivery' -- "$${REPO_URL}"
fi

# ------------------------------------------------------------------
# 9. Kind cluster config (blue + green NodePorts mapped)
# ------------------------------------------------------------------
cat > /home/ubuntu/kind-config.yaml << EOF
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
      - containerPort: ${frontend_node_port}
        hostPort: ${frontend_node_port}
        protocol: TCP
      - containerPort: ${green_node_port}
        hostPort: ${green_node_port}
        protocol: TCP
    extraMounts:
      - hostPath: /mnt/kind-storage/mongo
        containerPath: /data/mongo
      - hostPath: /mnt/kind-storage/blue-mongo
        containerPath: /data/blue-mongo
      - hostPath: /mnt/kind-storage/green-mongo
        containerPath: /data/green-mongo
  - role: worker
    image: kindest/node:v1.28.0
    extraMounts:
      - hostPath: /mnt/kind-storage/mongo
        containerPath: /data/mongo
      - hostPath: /mnt/kind-storage/blue-mongo
        containerPath: /data/blue-mongo
      - hostPath: /mnt/kind-storage/green-mongo
        containerPath: /data/green-mongo
  - role: worker
    image: kindest/node:v1.28.0
    extraMounts:
      - hostPath: /mnt/kind-storage/mongo
        containerPath: /data/mongo
      - hostPath: /mnt/kind-storage/blue-mongo
        containerPath: /data/blue-mongo
      - hostPath: /mnt/kind-storage/green-mongo
        containerPath: /data/green-mongo
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

# ------------------------------------------------------------------
# 14. Wait for default MongoDB pod, then initiate replica set + create root user
#     (fixes the "chicken-and-egg" bug where creating the user before
#     the replica set exists causes auth to silently fail)
# ------------------------------------------------------------------
echo "Waiting for mongo-0 pod (default) to exist..."
sudo -u ubuntu bash -c '
until kubectl get pod mongo-0 -n database >/dev/null 2>&1; do
  echo "mongo-0 pod not created yet, retrying in 5s..."
  sleep 5
done
'

echo "Waiting for mongo-0 pod to be Ready..."
sudo -u ubuntu kubectl wait --for=condition=Ready pod/mongo-0 -n database --timeout=300s

sleep 10

echo "Initiating MongoDB replica set..."
sudo -u ubuntu kubectl exec mongo-0 -n database -- mongosh --quiet --eval '
try {
  rs.initiate({
    _id: "rs0",
    members: [{ _id: 0, host: "mongo-0.mongo-service.database.svc.cluster.local:27017" }]
  });
  print("Replica set initiated.");
} catch (e) {
  print("rs.initiate skipped (may already be initiated): " + e);
}
'

echo "Waiting for replica set to elect a PRIMARY..."
sudo -u ubuntu bash -c '
for i in $$(seq 1 30); do
  STATE=$$(kubectl exec mongo-0 -n database -- mongosh --quiet --eval "rs.status().myState" 2>/dev/null || echo "0")
  if [ "$$STATE" = "1" ]; then
    echo "Replica set PRIMARY is ready."
    break
  fi
  echo "Still waiting for PRIMARY (attempt $$i)..."
  sleep 5
done
'

echo "Creating MongoDB root user (if not already present)..."
sudo -u ubuntu kubectl exec mongo-0 -n database -- mongosh --quiet --eval '
db = db.getSiblingDB("admin");
if (!db.getUser("admin")) {
  db.createUser({
    user: "admin",
    pwd: "securepass",
    roles: [{ role: "root", db: "admin" }]
  });
  print("Root user created.");
} else {
  print("Root user already exists, skipping.");
}
'

echo "=== Userdata provisioning complete: $$(date) ==="