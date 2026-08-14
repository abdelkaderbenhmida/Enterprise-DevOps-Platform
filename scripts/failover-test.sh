#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"
INVENTORY_FILE="$ANSIBLE_DIR/inventory/hosts.ini"

BASTION_HOST="10.0.1.10"
BASTION_USER="ubuntu"
K8S_CP1="10.0.3.10"
HAPROXY_VIP="10.0.1.100"
PG_PRIMARY="10.0.4.10"
PG_REPLICA="10.0.4.11"

ssh_bastion() {
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -J "${BASTION_USER}@${BASTION_HOST}" "$@"
}

check_k8s_api() {
    echo "Checking Kubernetes API via HAProxy VIP..."
    if curl -k -s -f "https://${HAPROXY_VIP}:6443/healthz" > /dev/null; then
        echo "✓ K8s API healthy via HAProxy VIP"
        return 0
    else
        echo "✗ K8s API UNHEALTHY via HAProxy VIP"
        return 1
    fi
}

check_k8s_nodes() {
    echo "Checking Kubernetes nodes..."
    ssh_bastion "${BASTION_USER}@${K8S_CP1}" "kubectl get nodes -o wide"
}

check_pg_replication() {
    echo "Checking PostgreSQL replication status..."
    ssh_bastion "${BASTION_USER}@${PG_REPLICA}" "sudo -u postgres psql -c \"SELECT * FROM pg_stat_wal_receiver;\""
    ssh_bastion "${BASTION_USER}@${PG_PRIMARY}" "sudo -u postgres psql -c \"SELECT * FROM pg_stat_replication;\""
}

check_haproxy_backends() {
    echo "Checking HAProxy backend status..."
    ssh_bastion "${BASTION_USER}@10.0.1.21" "echo 'show stat' | socat stdio /var/run/haproxy/stats.socket 2>/dev/null | grep k8s_masters || echo 'Stats socket not accessible, checking via HTTP...' && curl -s http://localhost:9000/stats | grep -A5 k8s_masters"
}

test_k8s_cp_failover() {
    echo ""
    echo "=== Test 1: Control Plane Failover ==="
    echo "Stopping k8s-cp1 (${K8S_CP1})..."
    ssh_bastion "${BASTION_USER}@${K8S_CP1}" "sudo systemctl stop kubelet containerd" || true
    
    echo "Waiting 30 seconds for HAProxy to detect failure..."
    sleep 30
    
    echo "Checking K8s API via HAProxy VIP..."
    if check_k8s_api; then
        echo "✓ PASS: K8s API still accessible via HAProxy"
    else
        echo "✗ FAIL: K8s API not accessible"
    fi
    
    check_k8s_nodes
    
    echo "Restarting k8s-cp1..."
    ssh_bastion "${BASTION_USER}@${K8S_CP1}" "sudo systemctl start containerd kubelet"
    
    echo "Waiting 30 seconds for node to rejoin..."
    sleep 30
    
    check_k8s_nodes
    echo ""
}

test_pg_failover() {
    echo ""
    echo "=== Test 2: PostgreSQL Failover ==="
    echo "Current replication status:"
    check_pg_replication
    
    echo "Stopping PostgreSQL primary (${PG_PRIMARY})..."
    ssh_bastion "${BASTION_USER}@${PG_PRIMARY}" "sudo systemctl stop postgresql" || true
    
    echo "Waiting 10 seconds..."
    sleep 10
    
    echo "Promoting replica to primary..."
    ssh_bastion "${BASTION_USER}@${PG_REPLICA}" "sudo -u postgres pg_ctl promote -D /var/lib/postgresql/15/main"
    
    echo "Waiting 5 seconds for promotion..."
    sleep 5
    
    echo "Checking new primary status..."
    ssh_bastion "${BASTION_USER}@${PG_REPLICA}" "sudo -u postgres psql -c \"SELECT pg_is_in_recovery();\""
    
    echo "Restarting old primary as replica..."
    ssh_bastion "${BASTION_USER}@${PG_PRIMARY}" "sudo systemctl start postgresql"
    
    echo "Waiting 10 seconds..."
    sleep 10
    
    echo "Checking replication status after failover..."
    check_pg_replication
    echo ""
}

test_haproxy_failover() {
    echo ""
    echo "=== Test 3: HAProxy/Keepalived VIP Failover ==="
    echo "Current VIP holder:"
    ssh_bastion "${BASTION_USER}@10.0.1.21" "ip addr show dev eth0 | grep ${HAPROXY_VIP}" || true
    ssh_bastion "${BASTION_USER}@10.0.1.20" "ip addr show dev eth0 | grep ${HAPROXY_VIP}" || true
    
    echo "Stopping keepalived on current master (vm22-haproxy-lb)..."
    ssh_bastion "${BASTION_USER}@10.0.1.21" "sudo systemctl stop keepalived"
    
    echo "Waiting 10 seconds for VIP failover..."
    sleep 10
    
    echo "Checking new VIP holder:"
    ssh_bastion "${BASTION_USER}@10.0.1.21" "ip addr show dev eth0 | grep ${HAPROXY_VIP}" || true
    ssh_bastion "${BASTION_USER}@10.0.1.20" "ip addr show dev eth0 | grep ${HAPROXY_VIP}" || true
    
    echo "Checking K8s API via VIP after failover..."
    check_k8s_api
    
    echo "Restarting keepalived on vm22..."
    ssh_bastion "${BASTION_USER}@10.0.1.21" "sudo systemctl start keepalived"
    
    echo "Waiting 10 seconds..."
    sleep 10
    
    echo "Final VIP holder:"
    ssh_bastion "${BASTION_USER}@10.0.1.21" "ip addr show dev eth0 | grep ${HAPROXY_VIP}" || true
    ssh_bastion "${BASTION_USER}@10.0.1.20" "ip addr show dev eth0 | grep ${HAPROXY_VIP}" || true
    echo ""
}

test_nginx_ingress() {
    echo ""
    echo "=== Test 4: NGINX Ingress & Application Access ==="
    echo "Testing NGINX LB health endpoint..."
    ssh_bastion "${BASTION_USER}@10.0.1.20" "curl -s http://localhost/healthz"
    
    echo "Testing application access via NGINX LB..."
    ssh_bastion "${BASTION_USER}@10.0.1.20" "curl -s -o /dev/null -w '%{http_code}' http://localhost/app1/ || echo 'App1 not deployed yet'"
    ssh_bastion "${BASTION_USER}@10.0.1.20" "curl -s -o /dev/null -w '%{http_code}' http://localhost/app2/ || echo 'App2 not deployed yet'"
    ssh_bastion "${BASTION_USER}@10.0.1.20" "curl -s -o /dev/null -w '%{http_code}' http://localhost/app3/ || echo 'App3 not deployed yet'"
    echo ""
}

main() {
    echo "=== Enterprise DevOps Platform Failover Tests ==="
    echo "This script tests HA capabilities of the platform."
    echo ""
    
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        echo "ERROR: Inventory file not found. Run bootstrap first."
        exit 1
    fi
    
    echo "Running pre-flight checks..."
    check_k8s_api
    check_k8s_nodes
    check_pg_replication
    check_haproxy_backends
    
    case "${1:-all}" in
        k8s)
            test_k8s_cp_failover
            ;;
        pg|postgres)
            test_pg_failover
            ;;
        haproxy|lb)
            test_haproxy_failover
            ;;
        nginx|ingress)
            test_nginx_ingress
            ;;
        all)
            test_k8s_cp_failover
            test_pg_failover
            test_haproxy_failover
            test_nginx_ingress
            ;;
        *)
            echo "Usage: $0 {all|k8s|pg|haproxy|nginx}"
            exit 1
            ;;
    esac
    
    echo "=== Failover Tests Complete ==="
}

main "$@"