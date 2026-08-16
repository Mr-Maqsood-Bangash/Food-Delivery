# three-tier-app Helm chart

Helm packaging of the MERN three-tier app (React frontend, Node/Express
backend, MongoDB StatefulSet) described in your Kind/EC2 deployment doc.

## Prerequisites

- A running Kind cluster (see `kind-config.yaml` from your original doc).
- On the EC2/Kind host: `sudo mkdir -p /mnt/kind-storage/mongo && sudo chmod 777 /mnt/kind-storage/mongo`
  (matches the `extraMounts` in your kind-config, which maps that path to
  `/data/mongo` inside the nodes — this is what `storage.pv.hostPath` points to).
- Helm 3 installed locally.

## Install

```bash
helm install three-tier ./three-tier-app
```

Override credentials/images/replicas instead of editing values.yaml directly:

```bash
helm install three-tier ./three-tier-app \
  --set mongo.username=admin \
  --set mongo.password=CHANGE_ME \
  --set backend.image.tag=v4 \
  --set frontend.image.tag=v4
```

Or keep a separate, git-ignored file for secrets:

```bash
helm install three-tier ./three-tier-app -f values.yaml -f secrets.values.yaml
```

## What happens on install

1. Creates the `frontend`, `backend`, `database` namespaces.
2. Creates the `standard-storage` StorageClass, a `mongo-pv` PersistentVolume,
   and a `mongo-pvc` PVC in `database` (toggle off with `--set storage.create=false`
   if your cluster dynamically provisions volumes instead).
3. Creates the `mongo-secret` Secret in both `database` and `backend` namespaces.
4. Deploys the `mongo` StatefulSet + headless `mongo-service`.
5. Runs the `mongo-init` Job as a **post-install/post-upgrade Helm hook** —
   it waits for MongoDB, creates the root user, and runs `rs.initiate()`
   for the `rs0` replica set. This replaces the manual `kubectl apply`
   ordering from the original doc; Helm hooks guarantee it runs after the
   StatefulSet is up.
6. Deploys `backend-deployment` / `backend-service`.
7. Deploys `frontend-deployment` / `frontend-service` (NodePort 30007 by
   default — make sure that's mapped in your kind-config.yaml
   `extraPortMappings`).

## Verify

```bash
kubectl -n database get pods,pvc
kubectl -n database logs job/mongo-init
kubectl -n backend get pods
kubectl -n frontend get pods
kubectl exec -it mongo-0 -n database -- mongosh -u admin -p CHANGE_ME --authenticationDatabase admin --eval "rs.status().myState"
```

## Upgrade

```bash
helm upgrade three-tier ./three-tier-app --set backend.image.tag=v4
```

The `mongo-init` Job re-runs on upgrade too (it's idempotent — it checks
for an existing user and wraps `rs.initiate()` in try/catch).

## Uninstall

```bash
helm uninstall three-tier
```

This does **not** delete the PersistentVolume's underlying host data.
To wipe Mongo data completely:

```bash
kubectl delete pvc mongo-pvc -n database
ssh <ec2-host> "sudo rm -rf /mnt/kind-storage/mongo/*"
```

## Notes / fixes vs. the original raw manifests

- The original doc had the frontend reading a `backend-config` ConfigMap key
  while the backend read a `frontend-config` ConfigMap — the names were
  swapped. This chart fixes that: `frontend-config` (in the `frontend`
  namespace) holds `REACT_APP_API_BASE_URL` pointing at
  `backend-service.backend.svc.cluster.local`, and `backend-config` (in the
  `backend` namespace) holds backend-only settings.
- `mongo-secret` is templated into both namespaces that need it, so you only
  maintain credentials in one place (`values.yaml` / `--set`).
- Mongo initialization is a proper Helm hook instead of a manifest you have
  to remember to `kubectl apply` in the right order.
- Set `mongo.database.resources` / `backend.resources` / `frontend.resources`
  to tune requests & limits per environment without touching templates.

## Structure

```
three-tier-app/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── namespaces.yaml
│   ├── NOTES.txt
│   ├── storage/
│   │   ├── storageclass.yaml
│   │   └── pvc.yaml
│   ├── database/
│   │   ├── secret.yaml
│   │   ├── service.yaml
│   │   ├── statefulset.yaml
│   │   └── init-job.yaml
│   ├── backend/
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   └── frontend/
│       ├── configmap.yaml
│       ├── deployment.yaml
│       └── service.yaml
```
