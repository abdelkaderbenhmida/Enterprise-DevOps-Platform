#!/usr/bin/env bash
# local/k8s/deploy-to-kind.sh — deploys the platform apps to the local
# kind cluster: ingress-nginx, namespaces, app1/app2/app3 + in-cluster
# postgres (app1) + MongoDB (app2 StatefulSet).
#
# Uses the local kind cluster (context kind-devops-platform) and loads the
# app images directly into kind (no registry needed).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
K8S="$REPO_ROOT/kubernetes"
LOCAL_K8S="$SCRIPT_DIR"
CTX="kind-devops-platform"
REGISTRY_HOST="${REGISTRY_HOST:-}"
INGRESS_NGINX_VERSION="controller-v1.15.1"

# Load personal/secret config from repo root .env if present
if [ -f "$REPO_ROOT/.env" ]; then
  set -a; source "$REPO_ROOT/.env"; set +a
fi

KC="kubectl --context $CTX"

echo "=== deploy-to-kind ==="

$KC cluster-info >/dev/null 2>&1 || { echo "ERROR: kind context $CTX not reachable (is the cluster running?)"; exit 1; }

echo "--- Installing ingress-nginx ($INGRESS_NGINX_VERSION) ---"
kubectl --context $CTX apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_NGINX_VERSION}/deploy/static/provider/kind/deploy.yaml" >/dev/null
echo "  waiting for ingress-nginx controller (webhook) ..."
$KC -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=300s >/dev/null

echo "--- Building + loading app images into kind ---"
IMAGES=(
  "app1-backend:docker/app1-backend/Dockerfile"
  "app1-frontend:docker/app1-frontend/Dockerfile"
  "app2-node:docker/app2-node/Dockerfile"
  "app3-static:docker/app3-static/Dockerfile"
)
for entry in "${IMAGES[@]}"; do
  name="${entry%%:*}"
  dockerfile="${entry#*:}"
  tag="local/${name}:latest"
  echo "  building $name ..."
  docker build -q -t "$tag" -f "$REPO_ROOT/$dockerfile" "$REPO_ROOT"
  echo "  loading $name into kind ..."
  kind load docker-image "$tag" --name devops-platform >/dev/null
  eval "export IMG_${name//-/_}='$tag'"
done

echo "--- Applying manifests ---"
$KC apply -f "$K8S/namespaces.yml" || true
$KC apply -f "$LOCAL_K8S/app1-postgres.yml" || true
$KC apply -f "$K8S/app1-taskmanager/backend-deployment.yml" \
  -f "$K8S/app1-taskmanager/backend-service.yml" \
  -f "$K8S/app1-taskmanager/frontend-deployment.yml" \
  -f "$K8S/app1-taskmanager/frontend-service.yml" \
  -f "$K8S/app1-taskmanager/configmap.yml" \
  -f <(sed "s/value: changeme/value: ${PG_APP1_PASSWORD:-changeme}/" "$K8S/app1-taskmanager/secret.yml") || true
for i in $(seq 1 10); do
  $KC apply -f "$K8S/app1-taskmanager/ingress.yml" && break
  echo "  ingress webhook not ready, retry $i ..."
  sleep 6
done
$KC apply -f "$K8S/app2-nodemongo/" || true
$KC apply -f "$K8S/app3-static-site/" || true

echo "--- Setting local image references (in-cluster postgres skips the external Endpoints) ---"
$KC -n app1 set image deployment/app1-backend backend="${IMG_app1_backend}"
$KC -n app1 set image deployment/app1-frontend frontend="${IMG_app1_frontend}"
$KC -n app2 set image deployment/app2-node node="${IMG_app2_node}"
$KC -n app3 set image deployment/app3-static static="${IMG_app3_static}"

echo "--- Waiting for rollouts ---"
for ns in app1 app2 app3; do
  for dep in $($KC -n "$ns" get deploy -o name | sed 's|deployment.apps/||'); do
    echo "  waiting $ns/$dep ..."
    $KC -n "$ns" rollout status deployment/"$dep" --timeout=180s >/dev/null
  done
done

echo "--- Waiting for ingress-nginx + Mongo ---"
$KC -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s >/dev/null
$KC -n app2 rollout status statefulset/mongodb --timeout=180s >/dev/null || true

echo
echo "=== Deployed. Ingress controller NodePort: ==="
$KC -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.ports[*].nodePort}'
echo
echo "Access apps via: http://127.0.0.1:30080/app1/ (kind NodePort)"
echo "or through the local NGINX LB: http://127.0.0.1:8080/app1/"