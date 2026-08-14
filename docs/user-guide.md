# User Guide

## Overview

This guide explains how to access and use the Enterprise DevOps Platform after deployment.

## Access Points

### Web Interfaces

| Service | URL | Credentials |
|---------|-----|-------------|
| **Grafana** | http://10.0.5.11:3000 | admin / (from Ansible Vault) |
| **Prometheus** | http://10.0.5.10:9090 | None (read-only) |
| **Jenkins** | http://10.0.2.20:8080 | admin / (from Ansible Vault) |
| **HAProxy Stats** | http://10.0.1.21:9000/stats | admin / (from Ansible Vault) |
| **Kubernetes API** | https://10.0.1.100:6443 | kubeconfig (see below) |

### Applications (via NGINX LB)
| Application | URL |
|-------------|-----|
| App1 - Task Manager | http://10.0.1.20/app1/ |
| App2 - Node + MongoDB | http://10.0.1.20/app2/ |
| App3 - Static Site | http://10.0.1.20/app3/ |

---

## SSH Access

### Bastion Host (Jump Host)
```bash
# Direct SSH to bastion
ssh -i ~/.ssh/id_rsa ubuntu@10.0.1.10

# SSH to any internal VM via bastion
ssh -J ubuntu@10.0.1.10 ubuntu@10.0.3.10  # k8s-cp1
ssh -J ubuntu@10.0.1.10 ubuntu@10.0.4.10  # pg-primary
ssh -J ubuntu@10.0.1.10 ubuntu@10.0.2.20  # jenkins-master
```

### SSH Config (Recommended)
Add to `~/.ssh/config`:
```
Host bastion
    HostName 10.0.1.10
    User ubuntu
    IdentityFile ~/.ssh/id_rsa

Host *.internal
    ProxyJump bastion
    User ubuntu
    IdentityFile ~/.ssh/id_rsa
```

Then use:
```bash
ssh k8s-cp1.internal
ssh pg-primary.internal
```

---

## Kubernetes Access

### Get kubeconfig
```bash
# From bastion or any control plane
ssh -J bastion ubuntu@10.0.3.10 "cat ~/.kube/config" > ~/kubeconfig-enterprise
export KUBECONFIG=~/kubeconfig-enterprise

# Verify
kubectl get nodes
kubectl get pods -A
```

### Useful kubectl Commands
```bash
# Cluster overview
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get services -A
kubectl get ingress -A

# Application status
kubectl get pods -n app1
kubectl get pods -n app2
kubectl get pods -n app3

# Logs
kubectl logs -n app1 -l app=app1-backend --tail=100 -f
kubectl logs -n app2 -l app=app2-node --tail=100 -f
kubectl logs -n app3 -l app=app3-static --tail=100 -f

# Describe resources
kubectl describe pod -n app1 -l app=app1-backend
kubectl describe deployment -n app1 app1-backend

# Exec into pod
kubectl exec -it -n app1 deployment/app1-backend -- /bin/bash

# Port forward (local access)
kubectl port-forward -n app1 svc/app1-frontend 8080:80
# Then open http://localhost:8080
```

---

## Application Management

### App1 - Task Manager (FastAPI + React)
```bash
# Check status
kubectl get pods -n app1
kubectl get svc -n app1
kubectl get ingress -n app1

# Scale
kubectl scale deployment app1-backend -n app1 --replicas=4
kubectl scale deployment app1-frontend -n app1 --replicas=4

# View logs
kubectl logs -n app1 -l app=app1-backend -f
kubectl logs -n app1 -l app=app1-frontend -f

# Update image (via Jenkins or manually)
kubectl set image deployment/app1-backend -n app1 backend=myregistry/app1-backend:v1.2.3
kubectl set image deployment/app1-frontend -n app1 frontend=myregistry/app1-frontend:v1.2.3

# Rollback
kubectl rollout undo deployment/app1-backend -n app1
```

### App2 - Node + MongoDB
```bash
# Check status
kubectl get pods -n app2
kubectl get sts -n app2  # MongoDB StatefulSet
kubectl get pvc -n app2

# Scale Node.js app
kubectl scale deployment app2-node -n app2 --replicas=4

# MongoDB operations
kubectl exec -it -n app2 mongodb-0 -- mongosh

# View logs
kubectl logs -n app2 -l app=app2-node -f
kubectl logs -n app2 -l app=mongodb -f
```

### App3 - Static Site
```bash
# Check status
kubectl get pods -n app3
kubectl get svc -n app3
kubectl get ingress -n app3

# Scale
kubectl scale deployment app3-static -n app3 --replicas=4

# View logs
kubectl logs -n app3 -l app=app3-static -f
```

---

## Database Access

### PostgreSQL (App1 Database)
```bash
# From bastion to primary
ssh -J bastion ubuntu@10.0.4.10 "sudo -u postgres psql -d app1"

# From bastion to replica (read-only)
ssh -J bastion ubuntu@10.0.4.11 "sudo -u postgres psql -d app1"

# Common queries
# List tables
\dt

# Check replication status
SELECT * FROM pg_stat_replication;  -- on primary
SELECT * FROM pg_stat_wal_receiver; -- on replica

# Check connections
SELECT * FROM pg_stat_activity;

# Backup
pg_dump -h 10.0.4.10 -U app1 -d app1 > app1_backup.sql
```

### MongoDB (App2 Database)
```bash
# From bastion (via Kubernetes)
kubectl exec -it -n app2 mongodb-0 -- mongosh

# Or port forward
kubectl port-forward -n app2 svc/mongodb 27017:27017
# Then: mongosh mongodb://localhost:27017/app2
```

---

## Monitoring & Alerting

### Grafana Dashboards
1. Open http://10.0.5.11:3000
2. Login: admin / (vault password)
3. Key dashboards:
   - **Node Exporter Full** - System metrics for all 25 VMs
   - **Kubernetes Cluster** - Cluster health, pods, nodes
   - **PostgreSQL** - Database metrics, replication lag
   - **Jenkins** - Build queue, executor usage
   - **Applications** - Custom app metrics (request rate, latency, errors)

### Prometheus Queries
Open http://10.0.5.10:9090/graph

Useful queries:
```promql
# Node CPU usage
100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Node memory usage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk usage
(node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_avail_bytes{mountpoint="/"}) / node_filesystem_size_bytes{mountpoint="/"} * 100

# Kubernetes pod restarts
rate(kube_pod_container_status_restarts_total[5m])

# PostgreSQL replication lag
pg_replication_lag_seconds

# HAProxy backend status
haproxy_backend_up
```

### Alertmanager (if deployed)
Check alerts at http://10.0.5.10:9093

---

## CI/CD with Jenkins

### Access Jenkins
1. Open http://10.0.2.20:8080
2. Login: admin / (vault password)

### Pipeline Structure
- **App1 Pipeline**: `Jenkinsfile.app1` → builds backend & frontend, deploys to app1 namespace
- **App2 Pipeline**: `Jenkinsfile.app2` → builds Node.js app, deploys to app2 namespace
- **App3 Pipeline**: `Jenkinsfile.app3` → builds static site, deploys to app3 namespace

### Triggering Builds
```bash
# Via Git push (webhook configured)
git push origin main

# Manual trigger
# In Jenkins UI: click "Build Now" on pipeline

# Via CLI
curl -X POST -u admin:TOKEN http://10.0.2.20:8080/job/app1-pipeline/build
```

### Viewing Build Logs
1. Go to pipeline in Jenkins UI
2. Click build number → "Console Output"
3. Or use Blue Ocean: http://10.0.2.20:8080/blue

---

## Common Operations

### Deploy New Application Version
```bash
# Option 1: Via Jenkins (recommended)
# Push to Git → Jenkins builds → deploys automatically

# Option 2: Manual kubectl
kubectl set image deployment/app1-backend -n app1 backend=ghcr.io/user/app1-backend:v1.2.3
kubectl rollout status deployment/app1-backend -n app1

# Option 3: Helm (if using Helm charts)
helm upgrade app1 ./helm/app1 -n app1 --set image.tag=v1.2.3
```

### Check Application Health
```bash
# Kubernetes health checks
kubectl get pods -n app1 -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,STATUS:.status.phase

# Application endpoints
curl http://10.0.1.20/app1/health
curl http://10.0.1.20/app2/health
curl http://10.0.1.20/app3/

# Via Prometheus
# Query: up{job="kubernetes-pods",namespace="app1"}
```

### View Logs Aggregated
```bash
# Using kubectl
kubectl logs -n app1 -l app=app1-backend --since=1h -f

# Using Loki (if deployed)
# Grafana → Explore → Loki → query: {namespace="app1"}
```

### Restart Application
```bash
# Rolling restart
kubectl rollout restart deployment/app1-backend -n app1
kubectl rollout restart deployment/app1-frontend -n app1
kubectl rollout restart deployment/app2-node -n app2
kubectl rollout restart deployment/app3-static -n app3
```

---

## Troubleshooting Quick Reference

| Issue | Check | Fix |
|-------|-------|-----|
| App not accessible | `kubectl get ingress -n <ns>` | Check ingress class, service, pods |
| Pods CrashLoopBackOff | `kubectl logs -n <ns> <pod>` | Fix app config, check resources |
| Pods Pending | `kubectl describe pod` | Check node resources, PVC binding |
| Database connection failed | `kubectl exec -it <pod> -- nc -zv pg-primary 5432` | Check SG, service, DNS |
| High memory/CPU | Grafana Node Exporter dashboard | Scale deployment, add limits |
| Jenkins build fails | Jenkins console output | Check Docker, credentials, kubeconfig |
| K8s API timeout | `curl -k https://10.0.1.100:6443/healthz` | Check HAProxy, control planes |

---

## Useful Aliases (Add to ~/.bashrc)
```bash
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kexec='kubectl exec -it'
alias kpf='kubectl port-forward'
alias kns='kubectl config set-context --current --namespace'

# SSH shortcuts
alias sb='ssh -J ubuntu@10.0.1.10'
alias scp1='ssh -J ubuntu@10.0.1.10 ubuntu@10.0.3.10'
alias scp2='ssh -J ubuntu@10.0.1.10 ubuntu@10.0.3.11'
alias scp3='ssh -J ubuntu@10.0.1.10 ubuntu@10.0.3.12'
alias spg='ssh -J ubuntu@10.0.1.10 ubuntu@10.0.4.10'
alias spr='ssh -J ubuntu@10.0.1.10 ubuntu@10.0.4.11'
alias sprom='ssh -J ubuntu@10.0.1.10 ubuntu@10.0.5.10'
alias sgraf='ssh -J ubuntu@10.0.1.10 ubuntu@10.0.5.11'
alias sjenk='ssh -J ubuntu@10.0.1.10 ubuntu@10.0.2.20'
```

---

## Support

- **Documentation**: This repo's `docs/` directory
- **Runbooks**: `docs/recovery-guide.md`, `docs/troubleshooting.md`
- **Issues**: Git repository issues
- **On-call**: Platform team PagerDuty