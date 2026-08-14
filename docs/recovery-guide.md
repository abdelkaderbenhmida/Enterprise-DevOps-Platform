# Recovery Guide

## Overview

This guide covers disaster recovery procedures for the Enterprise DevOps Platform. It assumes you have a working backup strategy in place (see Deployment Guide for backup schedules).

## Recovery Scenarios

### 1. Single Kubernetes Control Plane Failure

**Symptoms**: One control plane node down, API still accessible via HAProxy VIP.

**Impact**: Reduced etcd quorum (2/3), but cluster remains functional.

**Recovery**:
```bash
# 1. Verify remaining control planes healthy
kubectl get nodes
kubectl get cs

# 2. Fix the failed node (replace instance or repair)
# If instance replaced:
# - Terraform apply to recreate VM
# - Run k8s-control-plane-join role on new node

# 3. If etcd member lost, remove from cluster
kubectl -n kube-system exec -it etcd-k8s-cp1 -- etcdctl member list
kubectl -n kube-system exec -it etcd-k8s-cp1 -- etcdctl member remove <failed-member-id>

# 4. Verify cluster health
kubectl get nodes -o wide
etcdctl endpoint health --cluster --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key
```

---

### 2. Multiple Control Plane Failure (Quorum Lost)

**Symptoms**: 2+ control planes down, Kubernetes API unavailable.

**Impact**: Complete cluster outage. etcd quorum lost (need 2/3).

**Recovery**:
```bash
# 1. STOP - Do not restart remaining control plane yet

# 2. Recover etcd from snapshot on ONE surviving node
# On surviving control plane (e.g., k8s-cp1):
systemctl stop kubelet
systemctl stop containerd

# Restore etcd snapshot
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot-latest.db \
  --name=k8s-cp1 \
  --initial-cluster=k8s-cp1=https://10.0.3.10:2380,k8s-cp2=https://10.0.3.11:2380,k8s-cp3=https://10.0.3.12:2380 \
  --initial-cluster-token=etcd-cluster \
  --initial-advertise-peer-urls=https://10.0.3.10:2380 \
  --data-dir=/var/lib/etcd

# 3. Update etcd static pod manifest with force-new-cluster
# Edit /etc/kubernetes/manifests/etcd.yaml
# Add: --force-new-cluster to etcd container command

# 4. Start etcd
systemctl start containerd
# Wait for etcd pod to come up

# 5. Remove force-new-cluster from manifest
# Wait for etcd to restart

# 6. Start kubelet
systemctl start kubelet

# 7. Verify single control plane works
kubectl get nodes

# 8. Rejoin other control planes (after Terraform recreates VMs)
# Run k8s-control-plane-join role on each
```

**etcd Snapshot Location**: `/backup/etcd-snapshot-<date>.db` on each control plane (daily cron).

---

### 3. All Control Planes Lost (Complete Cluster Loss)

**Symptoms**: All 3 control planes gone.

**Impact**: Total Kubernetes cluster loss.

**Recovery**:
```bash
# 1. Recreate all 3 control plane VMs via Terraform
cd terraform/environments/dev
terraform apply -target=azurerm_linux_virtual_machine.vm["vm08-k8s-cp1"] -target=azurerm_linux_virtual_machine.vm["vm09-k8s-cp2"] -target=azurerm_linux_virtual_machine.vm["vm10-k8s-cp3"]

# 2. Regenerate inventory
python3 scripts/generate-inventory.py > ansible/inventory/hosts.ini

# 3. Run Ansible from scratch on control planes
ansible-playbook -i inventory/hosts.ini site.yml --limit k8s_control_plane

# 4. Restore etcd from latest snapshot on first control plane
# (Same procedure as "Multiple Control Plane Failure" step 2)

# 5. Rejoin workers
ansible-playbook -i inventory/hosts.ini site.yml --limit k8s_workers

# 6. Re-deploy applications
ansible-playbook -i inventory/hosts.ini site.yml --tags deploy-apps

# 7. Verify
kubectl get nodes -o wide
kubectl get pods -A
```

---

### 4. PostgreSQL Primary Failure

**Symptoms**: VM17 unreachable, application errors connecting to database.

**Impact**: Write unavailable. Reads can be served by replica if promoted.

**Recovery - Option A: Promote Replica (Recommended for HA)**:
```bash
# 1. On replica (VM18), promote to primary
ssh -J bastion ubuntu@10.0.4.11 "sudo -u postgres pg_ctl promote -D /var/lib/postgresql/15/main"

# 2. Verify promotion
ssh -J bastion ubuntu@10.0.4.11 "sudo -u postgres psql -c 'SELECT pg_is_in_recovery();'"
# Should return 'f' (false = primary)

# 3. Update application configuration to point to new primary (10.0.4.11)
# - Update Kubernetes ExternalName service or ConfigMap
# - Update any standalone app configs
kubectl patch service postgres-primary -n app1 -p '{"spec":{"externalName":"pg-replica"}}'

# 4. Rebuild old primary as new replica (when VM17 recovered)
# On VM17 (after fixing/replacing):
systemctl stop postgresql
rm -rf /var/lib/postgresql/15/main/*
pg_basebackup -h 10.0.4.11 -D /var/lib/postgresql/15/main -U replicator -v -P -W
touch /var/lib/postgresql/15/main/standby.signal
# Configure primary_conninfo in postgresql.auto.conf
systemctl start postgresql

# 5. Verify replication
ssh -J bastion ubuntu@10.0.4.11 "sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'"
```

**Recovery - Option B: Restore from Backup**:
```bash
# 1. Stop PostgreSQL on primary
systemctl stop postgresql

# 2. Restore from latest pg_basebackup
rm -rf /var/lib/postgresql/15/main/*
tar -xzf /backup/pg_basebackup_latest.tar.gz -C /var/lib/postgresql/15/main/
chown -R postgres:postgres /var/lib/postgresql/15/main
chmod 700 /var/lib/postgresql/15/main

# 3. Restore WAL files for point-in-time recovery (if needed)
# Copy WAL files to /var/lib/postgresql/15/main/pg_wal/
# Create recovery.signal with recovery_target_time

# 4. Start PostgreSQL
systemctl start postgresql

# 5. Rebuild replica from new primary
# (Same as Option A step 4)
```

---

### 5. PostgreSQL Replica Failure

**Symptoms**: VM18 unreachable, replication lag alerts.

**Impact**: No read replica, no HA failover target.

**Recovery**:
```bash
# 1. Recreate VM18 via Terraform
terraform apply -target=azurerm_linux_virtual_machine.vm["vm18-pg-replica"]

# 2. Regenerate inventory and run replica role
python3 scripts/generate-inventory.py > ansible/inventory/hosts.ini
ansible-playbook -i inventory/hosts.ini site.yml --limit postgresql_replica

# 3. Verify replication caught up
ssh -J bastion ubuntu@10.0.4.11 "sudo -u postgres psql -c 'SELECT * FROM pg_stat_wal_receiver;'"
```

---

### 6. Worker Node Failure

**Symptoms**: Node shows NotReady, pods evicted.

**Impact**: Workloads rescheduled to other workers (if resources available).

**Recovery**:
```bash
# 1. Check node status
kubectl get nodes
kubectl describe node <failed-node>

# 2. If node recoverable (reboot, fix issue):
# SSH to node, fix issue, reboot
# Node will rejoin automatically

# 3. If node lost permanently:
# Drain and delete node
kubectl drain <failed-node> --ignore-daemonsets --delete-emptydir-data --force
kubectl delete node <failed-node>

# 4. Replace via Terraform
terraform apply -target=azurerm_linux_virtual_machine.vm["vm11-k8s-wk1"]

# 5. Run worker role on new node
ansible-playbook -i inventory/hosts.ini site.yml --limit k8s_workers[0]

# 6. Verify
kubectl get nodes
```

---

### 7. HAProxy/NGINX Load Balancer Failure

**Symptoms**: VIP not responding, health checks failing.

**HAProxy (VM22) Failure - VRRP Failover Should Be Automatic**:
```bash
# 1. Verify keepalived moved VIP to VM21
ssh -J bastion ubuntu@10.0.1.20 "ip addr show dev eth0 | grep 10.0.1.100"

# 2. Check HAProxy on VM21 (should be BACKUP, now MASTER)
ssh -J bastion ubuntu@10.0.1.20 "systemctl status keepalived"

# 3. Fix VM22 (replace or repair)
terraform apply -target=azurerm_linux_virtual_machine.vm["vm22-haproxy-lb"]
ansible-playbook -i inventory/hosts.ini site.yml --limit haproxy_lb

# 4. Verify VIP back on VM22 (if higher priority)
ssh -J bastion ubuntu@10.0.1.21 "ip addr show dev eth0 | grep 10.0.1.100"
```

**Both LBs Down (Split Brain or Both Failed)**:
```bash
# 1. Check keepalived on both
ssh -J bastion ubuntu@10.0.1.20 "systemctl status keepalived"
ssh -J bastion ubuntu@10.0.1.21 "systemctl status keepalived"

# 2. Restart keepalived on both
ssh -J bastion ubuntu@10.0.1.20 "sudo systemctl restart keepalived"
ssh -J bastion ubuntu@10.0.1.21 "sudo systemctl restart keepalived"

# 3. Verify VIP on one (should be VM22 as MASTER priority 101)
```

---

### 8. Prometheus/Grafana Failure

**Prometheus (VM19) Failure**:
```bash
# 1. Replace VM
terraform apply -target=azurerm_linux_virtual_machine.vm["vm19-prometheus"]
ansible-playbook -i inventory/hosts.ini site.yml --limit prometheus

# 2. TSDB restored from last 30 days (local storage)
# For longer history, need remote storage (S3/Thanos)
```

**Grafana (VM20) Failure**:
```bash
# 1. Replace VM
terraform apply -target=azurerm_linux_virtual_machine.vm["vm20-grafana"]
ansible-playbook -i inventory/hosts.ini site.yml --limit grafana

# 2. Dashboards auto-provisioned from Git
# 3. Datasource auto-configured to Prometheus
```

---

### 9. Jenkins Master Failure

**Symptoms**: Jenkins UI down, builds not triggering.

**Recovery**:
```bash
# 1. Replace VM
terraform apply -target=azurerm_linux_virtual_machine.vm["vm05-jenkins-master"]
ansible-playbook -i inventory/hosts.ini site.yml --limit jenkins_master

# 2. Restore Jenkins home from backup
# - Jobs, credentials, build history from daily backup
# - Restore to /var/lib/jenkins

# 3. Reconfigure agents (they'll reconnect automatically via JNLP)
```

---

### 10. Complete VPC/Region Failure

**Scenario**: Entire AWS region/availability zone down.

**Recovery**: Requires multi-region setup (not in current scope).
- Terraform state in S3 (cross-region replication)
- AMIs copied to backup region
- Runbook: Deploy to backup region, update DNS

---

## Backup Verification Checklist

Run monthly to ensure recoverability:

```bash
# 1. Verify etcd snapshots exist and are valid
for cp in k8s-cp1 k8s-cp2 k8s-cp3; do
  ssh -J bastion ubuntu@$cp "ls -la /backup/etcd-snapshot-*.db"
  # Test restore to temp location
  ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-snapshot-latest.db
done

# 2. Verify PostgreSQL base backups
ssh -J bastion ubuntu@10.0.4.10 "ls -la /backup/pg_basebackup_*.tar.gz"
# Test restore to temp instance

# 3. Verify Terraform state in S3
aws s3 ls s3://enterprise-devops-terraform-state/dev/

# 4. Verify Grafana dashboards in Git
git -C monitoring/grafana/dashboards log --oneline -5

# 5. Test failover procedures (run failover-test.sh)
./scripts/failover-test.sh all
```

---

## Contact Information

| Role | Contact | Escalation |
|------|---------|------------|
| Platform Owner | platform-team@company.com | PagerDuty: platform-oncall |
| Database Admin | dba-team@company.com | PagerDuty: dba-oncall |
| Network Admin | network-team@company.com | PagerDuty: network-oncall |
| Security | security@company.com | PagerDuty: security-oncall |

---

## Runbook Quick Reference

| Emergency | Command |
|-----------|---------|
| K8s API down | `./scripts/failover-test.sh k8s` |
| PostgreSQL primary down | `ssh bastion "sudo -u postgres pg_ctl promote -D /var/lib/postgresql/15/main"` |
| VIP not failing over | `ssh bastion "systemctl restart keepalived"` (on both LBs) |
| Worker node stuck | `kubectl drain <node> --force && kubectl delete node <node>` |
| Full cluster restore | See "All Control Planes Lost" section |