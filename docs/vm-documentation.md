# VM Documentation

## VM Inventory Details

### VM01 - Bastion Host
- **Hostname**: bastion
- **Role**: SSH gateway / jump host
- **Subnet**: Public (10.0.1.0/24)
- **IP**: 10.0.1.10
- **Instance Type**: t3.medium
- **Security Group**: sg-bastion
- **Software**: 
  - OpenSSH server
  - Ansible (for ad-hoc commands)
  - kubectl (for cluster access)
  - AWS CLI
- **Ports**: 22 (SSH from admin CIDR only)
- **Key Access**: SSH key-based only, no passwords
- **HA Pairing**: None (single point of access - document emergency access)

---

### VM02 - Terraform Server
- **Hostname**: terraform-srv
- **Role**: Infrastructure automation
- **Subnet**: Management (10.0.2.0/24)
- **IP**: 10.0.2.10
- **Instance Type**: t3.large
- **Security Group**: sg-mgmt
- **Software**:
  - Terraform >= 1.0
  - AWS CLI v2
  - Git
  - Python 3 + boto3
- **Ports**: 22 (from bastion), 8080/50000 (Jenkins internal - not used here)
- **Key Access**: SSH from bastion
- **Storage**: 50GB GP3 for Terraform state cache
- **HA Pairing**: None (run Terraform from CI/CD or admin workstation)

---

### VM03 - Ansible Server
- **Hostname**: ansible-srv
- **Role**: Configuration management
- **Subnet**: Management (10.0.2.0/24)
- **IP**: 10.0.2.11
- **Instance Type**: t3.large
- **Security Group**: sg-mgmt
- **Software**:
  - Ansible >= 2.15
  - Ansible collections: kubernetes.core, community.general
  - Python 3 + kubernetes, openshift libs
  - SSH client
  - Vault CLI (for secrets)
- **Ports**: 22 (from bastion)
- **Key Access**: SSH from bastion
- **HA Pairing**: None (Ansible is push-based, run from CI/CD or admin)

---

### VM04 - Git Server
- **Hostname**: git-srv
- **Role**: Git repository hosting (Gitea/GitLab)
- **Subnet**: Management (10.0.2.0/24)
- **IP**: 10.0.2.12
- **Instance Type**: t3.large
- **Security Group**: sg-mgmt
- **Software**:
  - Gitea (lightweight) or GitLab CE
  - PostgreSQL (local or external)
  - Nginx reverse proxy
  - Let's Encrypt certs
- **Ports**: 22 (from bastion), 80/443 (from mgmt subnet), 3000 (Gitea)
- **Key Access**: SSH from bastion
- **Storage**: 100GB GP3 for repositories
- **HA Pairing**: None (backup repos to S3)

---

### VM05 - Jenkins Master
- **Hostname**: jenkins-master
- **Role**: CI/CD orchestration
- **Subnet**: Management (10.0.2.0/24)
- **IP**: 10.0.2.20
- **Instance Type**: t3.xlarge
- **Security Group**: sg-mgmt
- **Software**:
  - OpenJDK 17
  - Jenkins LTS
  - Plugins: Pipeline, Git, Docker, Kubernetes, JCasC, Credentials Binding, Blue Ocean, Prometheus
  - Configuration as Code (JCasC)
  - Docker CLI (for agent communication)
- **Ports**: 22 (from bastion), 8080 (web UI), 50000 (JNLP agents)
- **Key Access**: SSH from bastion
- **Storage**: 100GB GP3 for Jenkins home + build artifacts
- **HA Pairing**: None (single master; agents stateless; consider HA Jenkins for production)

---

### VM06 - Jenkins Agent 1
- **Hostname**: jenkins-agent1
- **Role**: CI/CD build executor
- **Subnet**: Management (10.0.2.0/24)
- **IP**: 10.0.2.21
- **Instance Type**: t3.large
- **Security Group**: sg-mgmt
- **Software**:
  - OpenJDK 17
  - Docker CE + Buildx + Compose
  - Node.js 20, Python 3.11, Go 1.22
  - kubectl, helm, terraform
  - Jenkins JNLP agent (systemd service)
- **Labels**: `docker`, `node`, `python`, `go`
- **Ports**: 22 (from bastion)
- **Key Access**: SSH from bastion; JNLP from Jenkins master
- **HA Pairing**: Peer with VM07 (both agents; pipelines can run on either)

---

### VM07 - Jenkins Agent 2
- **Hostname**: jenkins-agent2
- **Role**: CI/CD build executor
- **Subnet**: Management (10.0.2.0/24)
- **IP**: 10.0.2.22
- **Instance Type**: t3.large
- **Security Group**: sg-mgmt
- **Software**: Same as VM06
- **Labels**: `docker`, `node`, `python`, `go`
- **Ports**: 22 (from bastion)
- **Key Access**: SSH from bastion; JNLP from Jenkins master
- **HA Pairing**: Peer with VM06

---

### VM08 - Kubernetes Control Plane 1 (Bootstrap)
- **Hostname**: k8s-cp1
- **Role**: K8s control plane (first/init)
- **Subnet**: Kubernetes (10.0.3.0/24)
- **IP**: 10.0.3.10
- **Instance Type**: t3.xlarge
- **Security Group**: sg-k8s-cp
- **Software**:
  - containerd
  - kubeadm, kubelet, kubectl v1.29
  - Calico CNI (tigera-operator)
  - nginx-ingress-controller (Helm)
- **Ports**: 22 (from bastion), 6443 (from HAProxy), 2379-2380 (etcd), 10250-10259 (kubelet)
- **Key Access**: SSH from bastion
- **Special**: Runs `kubeadm init --control-plane-endpoint=10.0.1.100:6443 --upload-certs`
- **HA Pairing**: Peer with VM09, VM10 (stacked etcd quorum - need 2/3)

---

### VM09 - Kubernetes Control Plane 2
- **Hostname**: k8s-cp2
- **Role**: K8s control plane (join)
- **Subnet**: Kubernetes (10.0.3.0/24)
- **IP**: 10.0.3.11
- **Instance Type**: t3.xlarge
- **Security Group**: sg-k8s-cp
- **Software**: Same as VM08
- **Ports**: Same as VM08
- **Special**: Runs `kubeadm join --control-plane --certificate-key=...`
- **HA Pairing**: Peer with VM08, VM10

---

### VM10 - Kubernetes Control Plane 3
- **Hostname**: k8s-cp3
- **Role**: K8s control plane (join)
- **Subnet**: Kubernetes (10.0.3.0/24)
- **IP**: 10.0.3.12
- **Instance Type**: t3.xlarge
- **Security Group**: sg-k8s-cp
- **Software**: Same as VM08
- **Ports**: Same as VM08
- **Special**: Runs `kubeadm join --control-plane --certificate-key=...`
- **HA Pairing**: Peer with VM08, VM09

---

### VM11-VM16 - Kubernetes Workers (6 nodes)
| VM | Hostname | IP | Role |
|----|----------|-----|------|
| VM11 | k8s-wk1 | 10.0.3.20 | Worker |
| VM12 | k8s-wk2 | 10.0.3.21 | Worker |
| VM13 | k8s-wk3 | 10.0.3.22 | Worker |
| VM14 | k8s-wk4 | 10.0.3.23 | Worker |
| VM15 | k8s-wk5 | 10.0.3.24 | Worker |
| VM16 | k8s-wk6 | 10.0.3.25 | Worker |

- **Instance Type**: t3.large
- **Security Group**: sg-k8s-worker
- **Software**:
  - containerd
  - kubeadm, kubelet, kubectl v1.29
  - Calico CNI (auto via node join)
- **Ports**: 22 (from bastion), 10250 (from CPs), 30000-32767 (NodePort from LBs)
- **Key Access**: SSH from bastion
- **Special**: Run `kubeadm join` with worker token
- **HA Pairing**: All 6 are peers; K8s reschedules pods on failure

---

### VM17 - PostgreSQL Primary
- **Hostname**: pg-primary
- **Role**: PostgreSQL primary (read/write)
- **Subnet**: Data (10.0.4.0/24)
- **IP**: 10.0.4.10
- **Instance Type**: t3.large
- **Security Group**: sg-data
- **Software**:
  - PostgreSQL 15
  - wal_level = replica
  - max_wal_senders = 10
  - postgres_exporter (port 9187)
- **Ports**: 22 (from bastion), 5432 (from K8s + mgmt subnets), 9187 (Prometheus)
- **Key Access**: SSH from bastion
- **Databases**: app1 (for App1), monitoring user for exporter
- **Replication**: Streams WAL to VM18
- **HA Pairing**: Primary for VM18 (replica)

---

### VM18 - PostgreSQL Replica
- **Hostname**: pg-replica
- **Role**: PostgreSQL hot standby (read-only)
- **Subnet**: Data (10.0.4.0/24)
- **IP**: 10.0.4.11
- **Instance Type**: t3.large
- **Security Group**: sg-data
- **Software**:
  - PostgreSQL 15 (standby mode)
  - standby.signal + primary_conninfo
  - postgres_exporter (port 9187)
- **Ports**: 22 (from bastion), 5432 (from K8s + mgmt subnets), 9187 (Prometheus)
- **Key Access**: SSH from bastion
- **Bootstrap**: `pg_basebackup` from VM17
- **Failover**: Manual `pg_ctl promote` to become primary
- **HA Pairing**: Replica for VM17

---

### VM19 - Prometheus
- **Hostname**: prometheus
- **Role**: Metrics collection & alerting
- **Subnet**: Monitoring (10.0.5.0/24)
- **IP**: 10.0.5.10
- **Instance Type**: t3.large
- **Security Group**: sg-monitoring
- **Software**:
  - Prometheus 2.48
  - Alertmanager (optional)
  - node_exporter (port 9100)
- **Ports**: 22 (from bastion), 9090 (web UI), 9100 (self-scrape)
- **Key Access**: SSH from bastion
- **Storage**: 50GB GP3 for TSDB (30d retention)
- **Scrape Targets**: All 25 nodes (9100), K8s API, PG exporters, Jenkins, HAProxy
- **HA Pairing**: None (single; consider HA Prometheus for production)

---

### VM20 - Grafana
- **Hostname**: grafana
- **Role**: Visualization & dashboards
- **Subnet**: Monitoring (10.0.5.0/24)
- **IP**: 10.0.5.11
- **Instance Type**: t3.medium
- **Security Group**: sg-monitoring
- **Software**:
  - Grafana 10.x
  - Provisioned Prometheus datasource
  - Pre-loaded dashboards (Node, K8s, PG, Jenkins, Apps)
- **Ports**: 22 (from bastion), 3000 (web UI)
- **Key Access**: SSH from bastion
- **Default Login**: admin / (set via Ansible Vault)
- **HA Pairing**: None (stateless; dashboards in Git)

---

### VM21 - NGINX Load Balancer
- **Hostname**: nginx-lb
- **Role**: L7 load balancer for applications
- **Subnet**: Public (10.0.1.0/24)
- **IP**: 10.0.1.20
- **Instance Type**: t3.medium
- **Security Group**: sg-lb
- **Software**:
  - NGINX
  - keepalived (BACKUP state for VIP)
- **Ports**: 22 (from bastion), 80/443 (Internet), 9100 (Prometheus)
- **Key Access**: SSH from bastion
- **Upstream**: 6 K8s workers on NodePort 30080 (least_conn)
- **HA Pairing**: VRRP BACKUP with VM22 (VIP 10.0.1.100)

---

### VM22 - HAProxy Load Balancer
- **Hostname**: haproxy-lb
- **Role**: L4 load balancer for K8s API
- **Subnet**: Public (10.0.1.0/24)
- **IP**: 10.0.1.21
- **Instance Type**: t3.medium
- **Security Group**: sg-lb
- **Software**:
  - HAProxy
  - keepalived (MASTER state for VIP)
- **Ports**: 22 (from bastion), 6443 (Internet → K8s API), 9000 (stats), 9100 (Prometheus)
- **Key Access**: SSH from bastion
- **Backend**: 3 K8s CPs on 6443 (roundrobin, health check /healthz)
- **HA Pairing**: VRRP MASTER with VM21 (VIP 10.0.1.100)

---

### VM23 - Backend Standalone
- **Hostname**: backend-standalone
- **Role**: Non-containerized backend application
- **Subnet**: Apps (10.0.6.0/24)
- **IP**: 10.0.6.10
- **Instance Type**: t3.medium
- **Security Group**: sg-apps
- **Software**: Application-specific (Node.js, Python, Java, etc.)
- **Ports**: 22 (from bastion), 8000 (from LB + internal)
- **HA Pairing**: None (single instance for comparison)

---

### VM24 - Frontend Standalone
- **Hostname**: frontend-standalone
- **Role**: Non-containerized frontend application
- **Subnet**: Apps (10.0.6.0/24)
- **IP**: 10.0.6.11
- **Instance Type**: t3.medium
- **Security Group**: sg-apps
- **Software**: Application-specific (Nginx, Apache, Node.js)
- **Ports**: 22 (from bastion), 80 (from LB + internal)
- **HA Pairing**: None

---

### VM25 - Test Staging
- **Hostname**: test-staging
- **Role**: Staging environment for integration testing
- **Subnet**: Apps (10.0.6.0/24)
- **IP**: 10.0.6.12
- **Instance Type**: t3.medium
- **Security Group**: sg-apps
- **Software**: Full stack for end-to-end testing
- **Ports**: 22 (from bastion), 80/8000 (from LB + internal)
- **HA Pairing**: None

---

## Maintenance Procedures

### Routine Updates
```bash
# On each VM (via Ansible)
apt update && apt upgrade -y
# Reboot if kernel updated
needs-restarting -r && reboot
```

### Certificate Rotation
- **K8s**: `kubeadm certs renew all` on control planes (annually)
- **ETCD**: Rotate certs via kubeadm
- **Application TLS**: Let's Encrypt auto-renewal via cert-manager

### Backup Schedule
| Component | Frequency | Retention | Method |
|-----------|-----------|-----------|--------|
| ETCD | Daily | 7 days | `etcdctl snapshot save` |
| PostgreSQL | Daily | 30 days | `pg_basebackup` + WAL archiving |
| Prometheus | N/A | 30 days | TSDB retention |
| Grafana | On change | Git | Dashboard JSON in Git |
| Jenkins | Daily | 7 days | Jenkins home backup |
| Terraform State | On apply | Versioned | S3 versioning |