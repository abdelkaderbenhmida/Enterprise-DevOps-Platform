#!/usr/bin/env bash
# scripts/local-validate.sh — per-"VM" validation of the local lab.
# Mirrors the cloud post-deploy checks (per-VM from the 25-VM spec).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0; FAIL=0; SKIP=0

ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
skip() { echo "  [SKIP] $1"; SKIP=$((SKIP+1)); }

check_http() { # name url expect_status
  local name="$1" url="$2" expect="$3"
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" 2>/dev/null)
  if [[ "$code" == "$expect" ]]; then ok "$name ($code)"; else bad "$name (got $code, want $expect)"; fi
}

echo "=== VM17 pg-primary (localhost:55432) ==="
if docker exec vm17-pg-primary pg_isready -U app1 -d app1 -h localhost >/dev/null 2>&1; then
  ok "pg_isready"
  wal=$(docker exec vm17-pg-primary psql -U app1 -d app1 -tAc "SHOW wal_level")
  [[ "$wal" == "replica" ]] && ok "wal_level=replica" || bad "wal_level=$wal"
  slot=$(docker exec vm17-pg-primary psql -U app1 -d app1 -tAc "SELECT slot_name FROM pg_replication_slots WHERE slot_name='replica_slot_local'")
  [[ -n "$slot" ]] && ok "replication slot replica_slot_local" || bad "slot missing"
else
  bad "pg_isready (primary down)"
fi

echo "=== VM18 pg-replica (localhost:55433) ==="
if docker exec vm18-pg-replica pg_isready -U app1 -d app1 -h localhost >/dev/null 2>&1; then
  ok "pg_isready"
  rec=$(docker exec vm18-pg-replica psql -U app1 -d app1 -tAc "SELECT pg_is_in_recovery()")
  [[ "$rec" == "t" ]] && ok "in recovery (standby)" || bad "pg_is_in_recovery=$rec"
  hb=$(docker exec vm18-pg-replica psql -U app1 -d app1 -tAc "SHOW hot_standby")
  [[ "$hb" == "on" ]] && ok "hot_standby=on" || bad "hot_standby=$hb"
else
  bad "pg_isready (replica down)"
fi

echo "=== VM17/VM18 postgres-exporters ==="
pg_up_primary=$(curl -s --max-time 10 http://localhost:19187/metrics | grep -c '^pg_up 1' || true)
[[ "$pg_up_primary" -ge 1 ]] && ok "exporter primary pg_up=1 (19187)" || bad "exporter primary pg_up (19187)"
pg_up_replica=$(curl -s --max-time 10 http://localhost:19188/metrics | grep -c '^pg_up 1' || true)
[[ "$pg_up_replica" -ge 1 ]] && ok "exporter replica pg_up=1 (19188)" || bad "exporter replica pg_up (19188)"
lag=$(curl -s --max-time 10 http://localhost:19188/metrics | grep '^pg_replication_lag_seconds' | head -1 || true)
[[ -n "$lag" ]] && ok "replica lag metric: $lag" || bad "replica lag metric missing (19188)"

echo "=== VM19 prometheus (localhost:9090) ==="
check_http "prometheus ready (/-/ready)" "http://localhost:9090/-/ready" 200
targets=$(curl -s --max-time 10 "http://localhost:9090/api/v1/targets" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
up=[t for t in d['data']['activeTargets'] if t['health']=='up']
print(len(up), ' '.join(t['labels'].get('job','?') for t in up))
" 2>/dev/null)
echo "  targets up: $targets"

echo "=== VM20 grafana (localhost:3000) ==="
check_http "grafana health (/api/health)" "http://admin:admin@localhost:3000/api/health" 200
dash=$(curl -s --max-time 10 "http://admin:admin@localhost:3000/api/search?type=dash-db" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(len(d), ','.join(sorted(x['title'] for x in d)))
except Exception: print('?')
" 2>/dev/null)
echo "  dashboards: $dash"

echo "=== VM22 haproxy-lb (container lab IP; docker-proxy flaky on this host) ==="
HAP_IP=$(docker inspect vm22-haproxy-lb --format '{{range $k,$v := .NetworkSettings.Networks}}{{if ne $k "kind"}}{{.IPAddress}}{{end}}{{end}}' 2>/dev/null)
HAP_IP=${HAP_IP:-172.19.0.2}
check_http "haproxy stats (:9000/stats)" "http://admin:admin@$HAP_IP:9000/stats" 200
hap_up=$(curl -s --max-time 10 http://$HAP_IP:9000/metrics | grep -E '^haproxy_backend_agg_server_status\{proxy="k8s_control_plane",state="UP"\} [1-9]' | wc -l || true)
[[ "$hap_up" -ge 1 ]] && ok "haproxy exporter metrics + healthy backend (:9000/metrics)" || bad "haproxy exporter metrics"
api=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 https://$HAP_IP:6443/readyz)
[[ "$api" == "200" ]] && ok "k8s API via VIP 6443 (/readyz=$api)" || bad "k8s API via VIP 6443 (got $api)"

echo "=== VM21 nginx-lb (container lab IP; docker-proxy flaky on this host) ==="
NGINX_IP=$(docker inspect vm21-nginx-lb --format '{{range $k,$v := .NetworkSettings.Networks}}{{if ne $k "kind"}}{{.IPAddress}}{{end}}{{end}}' 2>/dev/null)
NGINX_IP=${NGINX_IP:-172.19.0.3}
check_http "nginx /healthz" "http://$NGINX_IP/healthz" 200

echo "=== VM05 jenkins (localhost:8081/50000) ==="
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://localhost:8081 2>/dev/null)
case "$code" in
  200|302|403) ok "jenkins web (:8081, code $code — setup wizard pending OK)";;
  *) bad "jenkins web (:8081 got $code)";;
esac
pw=$(docker exec vm05-jenkins-master sh -c "cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null" 2>/dev/null)
[[ -n "$pw" ]] && ok "jenkins unlock password available" || bad "jenkins unlock password missing"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://localhost:8081/prometheus 2>/dev/null)
case "$code" in
  200|403) ok "jenkins /prometheus ($code)";;
  *) bad "jenkins /prometheus (got $code)";;
esac

echo "=== Apps via ingress (nginx-lb -> kind ingress) ==="
for app in app1 app2 app3; do
  check_http "app /$app/" "http://$NGINX_IP/$app/" 200
done
check_http "app1 API auth enforced (/api/tasks, want 401)" "http://$NGINX_IP/api/tasks" 401

echo
echo "=== Result: $PASS passed, $FAIL failed, $SKIP skipped ==="
[[ "$FAIL" -eq 0 ]]