# Enterprise DevOps Platform Architecture

## Overview

This document describes the architecture of the 25-VM Enterprise DevOps Platform, a comprehensive infrastructure-as-code project that demonstrates enterprise-grade DevOps practices including high availability, infrastructure automation, container orchestration, CI/CD pipelines, and observability.

## High-Level Architecture

```
                                    Internet
                                       │
                           ┌────────────▼────────────┐
                           │  VM21/VM22 NGINX+HAProxy  │  (public subnet, active-passive
                           │  Load Balancers (VIP)      │   with keepalived VRRP)
                           └────────────┬────────────┘
                                        │
                           ┌────────────▼────────────┐
                           │      VM01 Bastion          │
                           └────────────┬────────────┘
                                        │ SSH only
    ┌───────────────┬───────────────────┼───────────────────┬───────────────┐
    │                │                   │                   │               │
┌──▼───┐   ┌────────▼────────┐  ┌──────▼──────┐   ┌────────▼────────┐  ┌──▼───────┐
│VM02-04│   │ VM05-07 Jenkins  │  │ VM08-10 K8s  │   │ VM11-16 K8s      │  │VM17-18   │
│Mgmt:   │   │ Master+2 Agents  │  │ Control Plane │   │ Workers (6)      │  │Postgres  │
│TF/Ans/ │   │                  │  │ (HA, 3 nodes) │   │                  │  │Pri+Repl  │
│Git     │   │                  │  │ + etcd quorum │   │                  │  │          │
└────────┘   └──────────────────┘  └───────────────┘   └──────────────────┘  └──────────┘

                           ┌────────────────────────┐    ┌──────────────────┐
                           │ VM19 Prometheus          │    │ VM23-25          │
                           │ VM20 Grafana             │    │ Backend/Frontend/│
                           └──────────────────────────┘    │ Staging          │
                                                             └──────────────────┘
```

## Component Architecture

### Network Topology

| Subnet | CIDR | Purpose | VMs |
|--------|------|---------|-----|
| Public | 10.0.1.0/24 | Bastion + Load Balancers | VM01, VM21, VM22 |
| Management | 10.0.2.0/24 | Terraform, Ansible, Git, Jenkins | VM02-VM07 |
| Kubernetes | 10.0.3.0/24 | K8s Control Planes + Workers | VM08-VM16 |
| Data | 10.0.4.0/24 | PostgreSQL Primary + Replica | VM17, VM18 |
| Monitoring | 10.0.5.0/24 | Prometheus + Grafana | VM19, VM20 |
| Applications | 10.0.6.0/24 | Standalone Apps + Staging | VM23-VM25 |

### Security Groups

- **sg-bastion**: SSH (22) from admin CIDR only
- **sg-lb**: HTTP/HTTPS (80/443) from internet; K8s API (6443) from internet; internal to k8s/apps subnets
- **sg-mgmt**: SSH from bastion; Jenkins (8080, 50000) internal
- **sg-k8s-cp**: K8s API (6443) from HAProxy; etcd (2379-2380); kubelet (10250-10259) internal; SSH from bastion
- **sg-k8s-worker**: Kubelet (10250); NodePort (30000-32767) internal; SSH from bastion
- **sg-data**: PostgreSQL (5432) from k8s + mgmt subnets; SSH from bastion
- **sg-monitoring**: Prometheus (9090), Grafana (3000) internal; SSH from bastion
- **sg-apps**: App ports (80, 8000) from LB + internal; SSH from bastion

## Kubernetes Architecture

### Control Plane HA (Stacked etcd)

- **3 control plane nodes** (VM08, VM09, VM10) with stacked etcd
- **HAProxy (VM22)** load balances Kubernetes API (6443) across all 3 control planes
- **keepalived VRRP** provides VIP failover between VM21/VM22
- **kubeadm init** with `--control-plane-endpoint=<haproxy-vip>:6443 --upload-certs`

### Worker Nodes

- **6 worker nodes** (VM11-VM16) joining via kubeadm join
- **Calico CNI** for networking with NetworkPolicy support
- **nginx-ingress-controller** via Helm with NodePort services (30080/30443)

### Namespaces

| Namespace | Purpose |
|-----------|---------|
| app1 | Task Manager application (FastAPI + React) |
| app2 | Node.js + MongoDB application |
| app3 | Static site |
| ingress-nginx | Ingress controller |
| monitoring | In-cluster monitoring (if deployed) |
| kube-system | System components |

### Applications

1. **App1 - Task Manager**: FastAPI backend + React frontend, connects to external PostgreSQL (VM17/18)
2. **App2 - Node + MongoDB**: Node.js application with in-cluster MongoDB StatefulSet
3. **App3 - Static Site**: Nginx serving static content

## Load Balancer Design

### HAProxy (VM22) - Kubernetes API Load Balancer
- Balances TCP port 6443 across 3 control plane nodes
- Health checks via `/healthz` endpoint
- Stats endpoint on port 9000 for Prometheus scraping
- **keepalived VRRP** with VM21 for VIP (10.0.1.100) failover

### NGINX (VM21) - Application Load Balancer
- Reverse proxies to nginx-ingress-controller NodePort (30080) on worker nodes
- Routes traffic to applications via Ingress resources
- Health endpoint at `/healthz`

## PostgreSQL High Availability

- **Primary (VM17)**: Accepts reads/writes, streams WAL to replica
- **Replica (VM18)**: Hot standby, read-only, streams from primary
- **Replication**: Streaming replication with `pg_basebackup` bootstrap
- **Failover**: Manual promotion via `pg_ctl promote`
- **Monitoring**: postgres_exporter on both nodes (port 9187)

## CI/CD Architecture

### Jenkins Master (VM05)
- Jenkins core + plugins (Pipeline, Docker, Kubernetes, JCasC)
- Configuration as Code (JCasC) for declarative setup
- Credentials stored in Jenkins Credentials Store

### Jenkins Agents (VM06, VM07)
- JNLP agents connecting to master
- Docker installed for image builds
- Labels: `docker`, `node` for pipeline targeting

### Shared Library
- `buildImage()`: Build and push Docker images
- `deployToK8s()`: Deploy to Kubernetes via kubectl/helm
- Per-app Jenkinsfiles call shared library steps

## Monitoring & Observability

### Prometheus (VM19)
- Scrapes all 25 nodes via node_exporter (9100)
- Kubernetes service discovery for cluster metrics
- PostgreSQL metrics via postgres_exporter (9187)
- Jenkins metrics via Prometheus plugin
- HAProxy metrics via stats endpoint (9000)

### Alert Rules
- NodeDown, DiskSpaceLow, HighCPU/Memory
- KubePodCrashLooping, KubeNodeNotReady
- PostgresReplicationLagHigh, PostgresDown
- HAProxyBackendDown

### Grafana (VM20)
- Pre-provisioned Prometheus datasource
- Dashboards: Node Exporter Full, Kubernetes Cluster, PostgreSQL, Jenkins, Applications

## Infrastructure as Code

### Terraform
- **Modules**: network, security-groups, compute, load-balancer
- **VM Map**: Single source of truth (25 entries in `variables/vm-map.tf`)
- **Environments**: dev (prod mirror with different sizing)
- **Remote State**: Azure Storage (blob) with lease locking
- **Provider**: Azure (westeurope)

### Ansible
- **Roles**: 16 roles covering all components
- **Inventory**: Dynamic from Terraform output
- **Execution Order**: common → docker → haproxy → k8s-cp → k8s-workers → nginx → jenkins → postgres → monitoring → deploy-apps
- **Secrets**: Ansible Vault for sensitive data

## Deployment Workflow

```bash
# 1. Provision infrastructure
cd terraform/environments/dev
terraform init && terraform apply -auto-approve

# 2. Generate inventory
cd ../../../scripts
python3 generate-inventory.py > ../ansible/inventory/hosts.ini

# 3. Configure everything
cd ../ansible
ansible-playbook -i inventory/hosts.ini site.yml

# 4. Verify
ssh -J bastion ubuntu@10.0.3.10 "kubectl get nodes -o wide"
curl -k https://10.0.1.100:6443/healthz
```

## High Availability Guarantees

| Component | HA Strategy | Failover Time |
|-----------|-------------|---------------|
| K8s API | HAProxy + keepalived VRRP | < 10s |
| K8s Control Plane | 3-node stacked etcd quorum | Automatic |
| K8s Workers | K8s reschedules pods | ~30s |
| PostgreSQL | Streaming replication + manual promote | ~30s |
| NGINX LB | keepalived VRRP with HAProxy | < 10s |
| Jenkins | Single master (agents stateless) | Manual |

## Security Considerations

- SSH access only via bastion host with key-based authentication
- Security groups restrict traffic to minimum required ports
- Kubernetes API server cert SANs include HAProxy VIP
- PostgreSQL authentication via md5, replication user restricted to data subnet
- Jenkins credentials stored in Jenkins Credentials Store (not in code)
- TLS for Kubernetes API, Ingress (Let's Encrypt or internal CA)

## Scaling Considerations

- Add worker nodes: Update `vm_map` in Terraform, run apply, run Ansible k8s-worker role
- Add control planes: Update `vm_map`, run apply, run Ansible k8s-control-plane-join role
- Scale applications: Update replica counts in Kubernetes Deployments
- Scale PostgreSQL: Add read replicas, consider connection pooling (PgBouncer)