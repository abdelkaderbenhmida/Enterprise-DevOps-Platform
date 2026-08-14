#!/usr/bin/env bash
# local/setup.sh — prepares run-time config for the local 1:1 lab.
# 1. Extracts CA + client certs from ~/.kube/config for Prometheus.
# 2. Builds a local prometheus.yml (same jobs as canonical monitoring
#    config, static targets pointed at the local containers).
set -euo pipefail

LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$LOCAL_DIR/prometheus/run"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
MON_DIR="$(dirname "$LOCAL_DIR")/monitoring/prometheus"
KIND_CTX="${KIND_CTX:-kind-devops-platform}"
KIND_NODE="${KIND_NODE:-devops-platform-control-plane}"

echo "=== enterprise-devops local setup ==="

[[ -f "$KUBECONFIG" ]] || { echo "ERROR: no kubeconfig at $KUBECONFIG"; exit 1; }
mkdir -p "$RUN_DIR"
python3 -c "import yaml" 2>/dev/null || { echo "ERROR: need python3 + PyYAML"; exit 1; }

# In-network address of the kind API server (matches its serving-cert SAN).
if docker inspect "$KIND_NODE" >/dev/null 2>&1; then
  API_SERVER="https://${KIND_NODE}:6443"
else
  API_SERVER="https://kubernetes.default.svc"
fi

echo "Extracting TLS material from $KUBECONFIG (context '$KIND_CTX') ..."
python3 - "$KUBECONFIG" "$RUN_DIR" "$KIND_CTX" "$API_SERVER" <<'EOF'
import base64, os, sys, yaml

kubeconfig, out_dir, ctx_name, api_server = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(kubeconfig) as f:
    cfg = yaml.safe_load(f)

ctx = next((c for c in cfg.get("contexts", []) if c["name"] == ctx_name), None)
if ctx is None:
    print(f"ERROR: context '{ctx_name}' not found in kubeconfig", file=sys.stderr)
    sys.exit(1)

cluster = next((c["cluster"] for c in cfg.get("clusters", []) if c["name"] == ctx["context"]["cluster"]), None)
user = next((u["user"] for u in cfg.get("users", []) if u["name"] == ctx["context"]["user"]), None)

if cluster is None or user is None:
    print(f"ERROR: cluster/user for context '{ctx_name}' not found in kubeconfig", file=sys.stderr)
    sys.exit(1)

def write(path, data):
    if data is None:
        return
    if isinstance(data, str) and os.path.exists(data):
        with open(path) as f:
            data = f.read()
    else:
        try:
            data = base64.b64decode(data, validate=True).decode()
        except Exception:
            pass
    with open(path, "w") as f:
        f.write(data)

write(os.path.join(out_dir, "ca.crt"), cluster.get("certificate-authority-data")
      or cluster.get("certificate-authority"))
write(os.path.join(out_dir, "client.crt"), user.get("client-certificate-data")
      or user.get("client-certificate"))
write(os.path.join(out_dir, "client.key"), user.get("client-key-data")
      or user.get("client-key"))
print("server:", api_server)
EOF

chmod 0644 "$RUN_DIR/client.key" 2>/dev/null || true

echo "Writing prometheus kubeconfig ..."
python3 - "$KUBECONFIG" "$RUN_DIR/kubeconfig" "$KIND_CTX" "$API_SERVER" <<'EOF'
import sys, yaml

src, dst, ctx_name, api_server = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(src) as f:
    cfg = yaml.safe_load(f)
ctx = next(c for c in cfg["contexts"] if c["name"] == ctx_name)
cluster = next(c for c in cfg["clusters"] if c["name"] == ctx["context"]["cluster"])
user = next(u for u in cfg["users"] if u["name"] == ctx["context"]["user"])
cluster = dict(cluster)
cluster["cluster"] = dict(cluster["cluster"])
cluster["cluster"]["server"] = api_server
out = {
    "apiVersion": "v1",
    "kind": "Config",
    "clusters": [cluster],
    "users": [user],
    "contexts": [{"name": "prometheus", "context": {"cluster": cluster["name"], "user": user["name"]}}],
    "current-context": "prometheus",
}
with open(dst, "w") as f:
    yaml.safe_dump(out, f, default_flow_style=False, explicit_start=True)
EOF
chmod 0644 "$RUN_DIR/kubeconfig"

echo "Copying alert rules ..."
cp "$MON_DIR/alert.rules.yml" "$RUN_DIR/alert.rules.yml"

echo "Rendering local prometheus.yml (static targets -> local containers) ..."
python3 - "$MON_DIR/prometheus.yml" "$RUN_DIR/prometheus.yml" <<'EOF'
import sys, yaml

src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    cfg = yaml.safe_load(f)

node_targets = ["node-exporter:9100"]
pg_targets = ["postgres-exporter-primary:9187", "postgres-exporter-replica:9187"]

for job in cfg["scrape_configs"]:
    n = job.get("job_name")
    if n == "node_exporter":
        job["static_configs"] = [{"targets": node_targets}]
    elif n == "postgres_exporter":
        job["static_configs"] = [{"targets": pg_targets, "labels": {"instance": "postgres"}}]
    elif n == "jenkins":
        job["static_configs"] = [{"targets": ["jenkins:8080"]}]
    elif n == "haproxy":
        job["static_configs"] = [{"targets": ["haproxy:9000"]}]
    elif n == "kubernetes-nodes":
        # kind kubelets present self-signed certs; skip verification in the lab.
        job.setdefault("tls_config", {})["insecure_skip_verify"] = True

with open(dst, "w") as f:
    yaml.safe_dump(cfg, f, default_flow_style=False, sort_keys=False, explicit_start=True)
EOF

echo "Rendering nginx.conf (VM21 upstream -> kind node IP) ..."
KIND_NODE_IP="$(docker inspect devops-platform-control-plane --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo '172.18.0.2')"
sed "s/{{KIND_NODE_IP}}/$KIND_NODE_IP/" "$LOCAL_DIR/nginx/nginx.conf.tpl" > "$LOCAL_DIR/nginx/nginx.conf"

echo
echo "Done. Start the lab with:"
echo "  docker compose -f $LOCAL_DIR/docker-compose.yml up -d --build"
echo "Deploy apps with:"
echo "  $LOCAL_DIR/k8s/deploy-to-kind.sh"
echo "Validate with:"
echo "  ./scripts/local-validate.sh"