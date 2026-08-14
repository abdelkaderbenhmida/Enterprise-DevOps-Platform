# Infrastructure Diagram

## VM Inventory (25 VMs)

### Infrastructure Layer (5 VMs)
| VM | Hostname | Role | Subnet | IP | Size |
|----|----------|------|--------|-----|------|
| VM01 | bastion | Bastion/SSH Gateway | Public | 10.0.1.10 | t3.medium |
| VM21 | nginx-lb | NGINX Load Balancer | Public | 10.0.1.20 | t3.medium |
| VM22 | haproxy-lb | HAProxy Load Balancer | Public | 10.0.1.21 | t3.medium |

### Management/CI Layer (6 VMs)
| VM | Hostname | Role | Subnet | IP | Size |
|----|----------|------|--------|-----|------|
| VM02 | terraform-srv | Terraform/Automation | Management | 10.0.2.10 | t3.large |
| VM03 | ansible-srv | Ansible/Automation | Management | 10.0.2.11 | t3.large |
| VM04 | git-srv | Git Server (Gitea/GitLab) | Management | 10.0.2.12 | t3.large |
| VM05 | jenkins-master | Jenkins Controller | Management | 10.0.2.20 | t3.xlarge |
| VM06 | jenkins-agent1 | Jenkins Build Agent | Management | 10.0.2.21 | t3.large |
| VM07 | jenkins-agent2 | Jenkins Build Agent | Management | 10.0.2.22 | t3.large |

### Kubernetes Layer (9 VMs)
| VM | Hostname | Role | Subnet | IP | Size |
|----|----------|------|--------|-----|------|
| VM08 | k8s-cp1 | K8s Control Plane 1 | Kubernetes | 10.0.3.10 | t3.xlarge |
| VM09 | k8s-cp2 | K8s Control Plane 2 | Kubernetes | 10.0.3.11 | t3.xlarge |
| VM10 | k8s-cp3 | K8s Control Plane 3 | Kubernetes | 10.0.3.12 | t3.xlarge |
| VM11 | k8s-wk1 | K8s Worker 1 | Kubernetes | 10.0.3.20 | t3.large |
| VM12 | k8s-wk2 | K8s Worker 2 | Kubernetes | 10.0.3.21 | t3.large |
| VM13 | k8s-wk3 | K8s Worker 3 | Kubernetes | 10.0.3.22 | t3.large |
| VM14 | k8s-wk4 | K8s Worker 4 | Kubernetes | 10.0.3.23 | t3.large |
| VM15 | k8s-wk5 | K8s Worker 5 | Kubernetes | 10.0.3.24 | t3.large |
| VM16 | k8s-wk6 | K8s Worker 6 | Kubernetes | 10.0.3.25 | t3.large |

### Data Layer (2 VMs)
| VM | Hostname | Role | Subnet | IP | Size |
|----|----------|------|--------|-----|------|
| VM17 | pg-primary | PostgreSQL Primary | Data | 10.0.4.10 | t3.large |
| VM18 | pg-replica | PostgreSQL Replica | Data | 10.0.4.11 | t3.large |

### Monitoring Layer (2 VMs)
| VM | Hostname | Role | Subnet | IP | Size |
|----|----------|------|--------|-----|------|
| VM19 | prometheus | Prometheus Server | Monitoring | 10.0.5.10 | t3.large |
| VM20 | grafana | Grafana Server | Monitoring | 10.0.5.11 | t3.medium |

### Standalone Applications Layer (3 VMs)
| VM | Hostname | Role | Subnet | IP | Size |
|----|----------|------|--------|-----|------|
| VM23 | backend-standalone | Backend App (Non-K8s) | Apps | 10.0.6.10 | t3.medium |
| VM24 | frontend-standalone | Frontend App (Non-K8s) | Apps | 10.0.6.11 | t3.medium |
| VM25 | test-staging | Staging/Testing | Apps | 10.0.6.12 | t3.medium |

## HA Pairings

| Component | Primary | Backup | Failover Mechanism |
|-----------|---------|--------|-------------------|
| K8s API LB | VM22 (HAProxy) | VM21 (NGINX) | keepalived VRRP |
| K8s Control Plane | VM08 | VM09, VM10 | Stacked etcd quorum |
| PostgreSQL | VM17 (Primary) | VM18 (Replica) | Manual promotion |
| Jenkins Master | VM05 | N/A | Single (agents stateless) |
| Prometheus | VM19 | N/A | Single |
| Grafana | VM20 | N/A | Single |

## Network Connectivity Matrix

```
                    ┌─────────────┐
                    │  Internet   │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
       ┌─────────────┐           ┌─────────────┐
       │  VM21 NGINX │           │ VM22 HAProxy│
       │   (VIP)     │◄──VRRP───►│   (VIP)     │
       └──────┬──────┘           └──────┬──────┘
              │                         │
              ▼                         ▼
       ┌─────────────┐           ┌─────────────┐
       │  K8s Ingress│           │ K8s API     │
       │  (NodePort) │           │  (6443)     │
       └──────┬──────┘           └──────┬──────┘
              │                         │
      ┌───────┴───────┐                 │
      ▼               ▼                 ▼
┌─────────┐     ┌─────────┐      ┌─────────┐
│ K8s WK1 │     │ K8s WK2 │      │ K8s CP1 │
│  ...    │     │  ...    │      │  CP2    │
└─────────┘     └─────────┘      │  CP3    │
                                 └─────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
             ┌──────────┐        ┌──────────┐        ┌──────────┐
             │   DB     │        │  Mgmt    │        │ Monitoring│
             │ (5432)   │        │ (8080)   │        │  (9090)  │
             └──────────┘        └──────────┘        └──────────┘
```

## Subnet Layout

```
VPC: 10.0.0.0/16
│
├── Public (10.0.1.0/24) ──► IGW
│   ├── 10.0.1.10  (VM01 Bastion)
│   ├── 10.0.1.20  (VM21 NGINX LB)
│   ├── 10.0.1.21  (VM22 HAProxy LB)
│   └── 10.0.1.100 (VIP - keepalived)
│
├── Management (10.0.2.0/24) ──► NAT Gateway
│   ├── 10.0.2.10  (VM02 Terraform)
│   ├── 10.0.2.11  (VM03 Ansible)
│   ├── 10.0.2.12  (VM04 Git)
│   ├── 10.0.2.20  (VM05 Jenkins Master)
│   ├── 10.0.2.21  (VM06 Jenkins Agent 1)
│   └── 10.0.2.22  (VM07 Jenkins Agent 2)
│
├── Kubernetes (10.0.3.0/24) ──► NAT Gateway
│   ├── 10.0.3.10  (VM08 K8s CP1)
│   ├── 10.0.3.11  (VM09 K8s CP2)
│   ├── 10.0.3.12  (VM10 K8s CP3)
│   ├── 10.0.3.20  (VM11 K8s WK1)
│   ├── 10.0.3.21  (VM12 K8s WK2)
│   ├── 10.0.3.22  (VM13 K8s WK3)
│   ├── 10.0.3.23  (VM14 K8s WK4)
│   ├── 10.0.3.24  (VM15 K8s WK5)
│   └── 10.0.3.25  (VM16 K8s WK6)
│
├── Data (10.0.4.0/24) ──► NAT Gateway
│   ├── 10.0.4.10  (VM17 PG Primary)
│   └── 10.0.4.11  (VM18 PG Replica)
│
├── Monitoring (10.0.5.0/24) ──► NAT Gateway
│   ├── 10.0.5.10  (VM19 Prometheus)
│   └── 10.0.5.11  (VM20 Grafana)
│
└── Apps (10.0.6.0/24) ──► NAT Gateway
    ├── 10.0.6.10  (VM23 Backend Standalone)
    ├── 10.0.6.11  (VM24 Frontend Standalone)
    └── 10.0.6.12  (VM25 Test Staging)
```

## Security Group Rules Summary

| SG | Ingress Rules | Egress |
|----|---------------|--------|
| sg-bastion | 22/tcp from admin CIDR | All |
| sg-lb | 80,443,6443/tcp from 0.0.0.0/0; all from 10.0.3.0/24, 10.0.6.0/24 | All |
| sg-mgmt | 22/tcp from sg-bastion; 8080,50000/tcp from 10.0.2.0/24 | All |
| sg-k8s-cp | 6443/tcp from sg-lb; 2379-2380,10250-10259/tcp from 10.0.3.0/24; 22/tcp from sg-bastion | All |
| sg-k8s-worker | 10250/tcp from 10.0.3.0/24; 30000-32767/tcp from 10.0.3.0/24,10.0.1.0/24; 22/tcp from sg-bastion | All |
| sg-data | 5432/tcp from 10.0.3.0/24,10.0.2.0/24; 22/tcp from sg-bastion | All |
| sg-monitoring | 9090,3000/tcp from 10.0.5.0/24; 22/tcp from sg-bastion | All |
| sg-apps | 80,8000/tcp from sg-lb,10.0.6.0/24; 22/tcp from sg-bastion | All |