# Enterprise DevOps Platform

A complete Infrastructure-as-Code implementation for a 25-VM Enterprise DevOps Platform with Kubernetes HA, PostgreSQL replication, CI/CD pipelines, and full observability.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            VPC: 10.0.0.0/16                                 │
│                                                                             │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐      │
│  │   Public Subnet  │    │  Mgmt Subnet     │    │  K8s Subnet      │      │
│  │   10.0.1.0/24    │    │  10.0.2.0/24     │    │  10.0.3.0/24     │      │
│  │                  │    │                  │    │                  │      │
│  │  IGW ◄──────────►│    │                  │    │                  │      │
│  │      │           │    │                  │    │                  │      │
│  │  ┌───┴───┐        │    │  ┌────────────┐  │    │  ┌────────────┐  │      │
│  │  │ NAT   │◄───────┼────┼──│  Private   │  │    │  │  Private   │  │      │
│  │  │ GW    │        │    │  │  Route Tbl │  │    │  │  Route Tbl │  │      │
│  │  └───────┘        │    │  └────────────┘  │    │  └────────────┘  │      │
│  └──────────────────┘    └──────────────────┘    └──────────────────┘      │
│                                                                             │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐      │
│  │  Data Subnet     │    │ Monitoring Subnet│    │  Apps Subnet     │      │
│  │  10.0.4.0/24     │    │  10.0.5.0/24     │    │  10.0.6.0/24     │      │
│  │                  │    │                  │    │                  │      │
│  │  ┌────────────┐  │    │  ┌────────────┐  │    │  ┌────────────┐  │      │
│  │  │  Private   │  │    │  │  Private   │  │    │  │  Private   │  │      │
│  │  │  Route Tbl │◄─┼────┼──│  Route Tbl │  │    │  │  Route Tbl │  │      │
│  │  └────────────┘  │    │  └────────────┘  │    │  └────────────┘  │      │
│  └──────────────────┘    └──────────────────┘    └──────────────────┘      │
└─────────────────────────────────────────────────────────────────────────────┘
```

## VM Inventory (25 VMs)

| VM | Hostname | Role | Subnet | IP | Size |
|----|----------|------|--------|-----|------|
| VM01 | bastion | SSH Gateway | Public | 10.0.1.10 | Standard_D2s_v3 |
| VM02 | terraform-srv | Terraform | Mgmt | 10.0.2.10 | Standard_D4s_v3 |
| VM03 | ansible-srv | Ansible | Mgmt | 10.0.2.11 | Standard_D4s_v3 |
| VM04 | git-srv | Git Server | Mgmt | 10.0.2.12 | Standard_D4s_v3 |
| VM05 | jenkins-master | Jenkins Controller | Mgmt | 10.0.2.20 | Standard_D8s_v3 |
| VM06 | jenkins-agent1 | Jenkins Agent | Mgmt | 10.0.2.21 | Standard_D4s_v3 |
| VM07 | jenkins-agent2 | Jenkins Agent | Mgmt | 10.0.2.22 | Standard_D4s_v3 |
| VM08 | k8s-cp1 | K8s Control Plane | K8s | 10.0.3.10 | Standard_D8s_v3 |
| VM09 | k8s-cp2 | K8s Control Plane | K8s | 10.0.3.11 | Standard_D8s_v3 |
| VM10 | k8s-cp3 | K8s Control Plane | K8s | 10.0.3.12 | Standard_D8s_v3 |
| VM11-16 | k8s-wk1-6 | K8s Workers | K8s | 10.0.3.20-25 | Standard_D4s_v3 |
| VM17 | pg-primary | PostgreSQL Primary | Data | 10.0.4.10 | Standard_D4s_v3 |
| VM18 | pg-replica | PostgreSQL Replica | Data | 10.0.4.11 | Standard_D4s_v3 |
| VM19 | prometheus | Prometheus | Monitoring | 10.0.5.10 | Standard_D4s_v3 |
| VM20 | grafana | Grafana | Monitoring | 10.0.5.11 | Standard_D2s_v3 |
| VM21 | nginx-lb | NGINX LB | Public | 10.0.1.20 | Standard_D2s_v3 |
| VM22 | haproxy-lb | HAProxy LB | Public | 10.0.1.21 | Standard_D2s_v3 |
| VM23 | backend-standalone | Backend App | Apps | 10.0.6.10 | Standard_D2s_v3 |
| VM24 | frontend-standalone | Frontend App | Apps | 10.0.6.11 | Standard_D2s_v3 |
| VM25 | test-staging | Staging | Apps | 10.0.6.12 | Standard_D2s_v3 |

## Key Features

- **High Availability**: 3-node Kubernetes control plane with stacked etcd, HAProxy + keepalived VRRP for VIP failover
- **PostgreSQL HA**: Streaming replication with manual failover capability
- **Kubernetes**: kubeadm HA cluster with Calico CNI, nginx-ingress, proper resource limits
- **CI/CD**: Jenkins with shared library, Docker builds, Kubernetes deployments
- **Observability**: Prometheus + Grafana with node_exporter, postgres_exporter, alerting rules
- **Security**: Security groups, bastion host, Ansible Vault for secrets

## Quick Start

### Prerequisites
- Terraform >= 1.0
- Ansible >= 2.15
- Python 3.9+
- Azure CLI (`az login`), subscription with permission to create resources
- SSH key pair (public key contents go in `terraform.tfvars`)

### Deploy

```bash
# 1. Configure variables
cp terraform/environments/dev/terraform.tfvars.example terraform/environments/dev/terraform.tfvars
# Edit terraform.tfvars: paste your public SSH key contents into ssh_public_key

# 2. Configure secrets (Ansible Vault)
ansible-vault create ansible/inventory/group_vars/vault.yml

# 3. Run bootstrap (creates Terraform state storage, then provisions Azure + configures Ansible)
./scripts/bootstrap.sh
```

### Manual Steps

```bash
# Infrastructure
cd terraform/environments/dev
terraform init
terraform apply -var-file=terraform.tfvars

# Inventory
cd ../../../scripts
python3 generate-inventory.py > ../ansible/inventory/hosts.ini

# Configuration
cd ../ansible
ansible-playbook -i inventory/hosts.ini site.yml
```

## Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://10.0.5.11:3000 | admin / (vault) |
| Prometheus | http://10.0.5.10:9090 | None |
| Jenkins | http://10.0.2.20:8080 | admin / (vault) |
| HAProxy Stats | http://10.0.1.21:9000/stats | admin / (vault) |
| App1 - Task Manager | http://10.0.1.20/app1/ | - |
| App2 - Node + MongoDB | http://10.0.1.20/app2/ | - |
| App3 - Static Site | http://10.0.1.20/app3/ | - |

## Local Lab (PC testing before cloud)

Mirrors the 25-VM platform 1:1 as Docker containers + the local kind/lab
cluster, so every "VM" can be validated on a PC before provisioning Azure.

VM mapping: VM17/18 = postgres primary/replica, VM19 = prometheus,
VM20 = grafana, VM22 = HAProxy (K8s API VIP), VM21 = NGINX LB (app ingress),
VM05 = Jenkins, VM01-25 node exporters = 1 node-exporter stand-in.

```bash
./local/setup.sh                 # extracts kubeconfig certs, renders local configs
docker compose -f local/docker-compose.yml up -d
./local/k8s/deploy-to-kind.sh    # installs ingress-nginx, builds+loads app images, applies manifests
./scripts/local-validate.sh      # per-VM checks (22 tests)
```

Notes:

- App images load into the local kind cluster directly (`imagePullPolicy: Never`);
  the cloud manifests keep the `ghcr.io/your-org/<app>` refs.
- app1 uses an in-cluster PostgreSQL (`local/k8s/app1-postgres.yml`) instead of
  the external VM17/18 Endpoints (`postgres-external-service.yml` is cloud-only).
- Jenkins boots into the setup wizard on first run (unlock password in
  `/var/jenkins_home/secrets/initialAdminPassword`).
- If host-published ports (e.g. :8080, :9000) are unreachable, access the
  containers directly — docker-proxy on this host is unreliable for
  dual-network containers; the validate script already does this.

## Project Structure

```
enterprise-devops-platform/
├── ansible/
│   ├── roles/                 # 16 Ansible roles
│   ├── playbooks/             # 01-common ... 09-deploy-apps (run individually)
│   ├── inventory/             # Dynamic inventory + group_vars
│   └── site.yml              # Orchestrator (imports all playbooks)
├── terraform/
│   ├── modules/              # network, security-groups, compute, load-balancer
│   ├── environments/dev/     # Dev environment
│   ├── environments/prod/    # Prod mirror (different sizing via tfvars)
│   └── variables/vm-map.tf   # 25-VM map (single source of truth)
├── kubernetes/
│   ├── namespaces.yml
│   ├── ingress/              # nginx-ingress Helm values
│   ├── kube-state-metrics/   # Cluster state exporter (monitoring)
│   ├── app1-taskmanager/     # FastAPI + React
│   ├── app2-nodemongo/       # Node.js + MongoDB StatefulSet
│   └── app3-static-site/     # Static NGINX
├── docker/                   # Dockerfiles for all apps
├── applications/             # Application source code
├── jenkins/
│   ├── Jenkinsfile.app1/2/3  # Pipeline definitions
│   └── shared-library/       # Reusable pipeline steps
├── monitoring/
│   ├── prometheus/           # prometheus.yml, alert.rules.yml
│   └── grafana/dashboards/   # 5 pre-built dashboards
├── local/                    # PC lab: compose, setup.sh, k8s deploy helpers
├── scripts/
│   ├── bootstrap.sh          # Full deployment
│   ├── generate-inventory.py # Terraform → Ansible
│   ├── failover-test.sh      # HA validation (cloud)
│   ├── local-validate.sh     # Per-VM validation (local lab)
│   └── k8s-join-token-refresh.sh
└── docs/                     # Architecture, deployment, recovery guides
```

## Applications

### App1 - Task Manager
- **Backend**: FastAPI + PostgreSQL (VM17/18)
- **Frontend**: React + NGINX
- **K8s**: Deployments with HPA-ready resource limits

### App2 - Node + MongoDB
- **App**: Express.js REST API
- **Database**: MongoDB StatefulSet with PVC
- **K8s**: Deployment + StatefulSet

### App3 - Static Site
- **App**: NGINX serving static HTML/CSS/JS
- **K8s**: Simple Deployment

## High Availability

| Component | Strategy | Failover Time |
|-----------|----------|---------------|
| K8s API | HAProxy + keepalived VRRP | < 10s |
| K8s Control Plane | 3-node stacked etcd quorum | Automatic |
| K8s Workers | K8s pod rescheduling | ~30s |
| PostgreSQL | Streaming replication + manual promote | ~30s |
| NGINX LB | keepalived VRRP | < 10s |

## Monitoring

- **Prometheus** scrapes all 25 nodes (node_exporter), K8s metrics, PostgreSQL, Jenkins, HAProxy
- **Alert Rules**: NodeDown, DiskSpace, CPU/Memory, PodCrashLoop, ReplicationLag, HAProxyBackendDown
- **Grafana Dashboards**: Node Exporter Full, K8s Cluster, PostgreSQL, Jenkins, Applications

## CI/CD Pipeline

```groovy
// Shared library usage
@Library('devops-shared-lib') _

pipeline {
  agent { label 'docker' }
  stages {
    stage('Test') { runTests(command: 'pytest', workingDir: 'app1/backend') }
    stage('Build') { dockerBuildPush(image: 'myapp:latest') }
    stage('Deploy') { deployToK8s(deployment: 'myapp', namespace: 'app1') }
    stage('Smoke') { smokeTest(labelSelector: 'app=myapp') }
  }
}
```

## Documentation

- [Architecture](docs/architecture.md) - Component diagram, decisions
- [Infrastructure](docs/infrastructure-diagram.md) - VM inventory, HA pairings
- [Network](docs/network-diagram.md) - Subnets, traffic flows, ports
- [VM Documentation](docs/vm-documentation.md) - Per-VM details
- [Deployment Guide](docs/deployment-guide.md) - Step-by-step, scaling, maintenance
- [Recovery Guide](docs/recovery-guide.md) - Disaster recovery procedures
- [User Guide](docs/user-guide.md) - Access, kubectl, app management
- [Troubleshooting](docs/troubleshooting.md) - Common issues & solutions

## Testing HA

```bash
# Run all failover tests
./scripts/failover-test.sh all

# Test specific component
./scripts/failover-test.sh k8s      # Control plane failover
./scripts/failover-test.sh pg       # PostgreSQL failover
./scripts/failover-test.sh haproxy  # VIP failover
./scripts/failover-test.sh nginx    # Ingress test
```

## Cleanup

```bash
cd terraform/environments/dev
terraform destroy -auto-approve -var-file=terraform.tfvars
```

## Cost Estimate (Azure westeurope, Pay-As-You-Go)

| Tier | Instances | Monthly (est.) |
|------|-----------|---------|
| Control Planes | 3 × Standard_D8s_v3 | ~$639 |
| Workers | 6 × Standard_D4s_v3 | ~$556 |
| Management | 4 × Standard_D4s_v3 + 1 × Standard_D8s_v3 | ~$477 |
| Data | 2 × Standard_D4s_v3 | ~$185 |
| Monitoring | 1 × Standard_D4s_v3 + 1 × Standard_D2s_v3 | ~$139 |
| Load Balancers | 2 × Standard_D2s_v3 | ~$92 |
| Apps | 3 × Standard_D2s_v3 | ~$139 |
| **Total** | **25 VMs** | **~$2,227/mo** |

*Use Azure Reserved Instances / savings plans for 30-60% savings in production. Azure Spot/eviction-eligible sizes for non-critical nodes.*

## License

MIT License - See LICENSE file for details.