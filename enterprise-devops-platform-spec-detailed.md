# Project: Enterprise DevOps Platform (25 VM) — Detailed Build Specification

> Implementation-ready expansion of the original brief: concrete IP plan, HA topology,
> file-level repo layout, Terraform/Ansible responsibilities, Jenkins pipeline, Kubernetes
> manifest inventory for 3 apps, and load-balancer/HA design. Intended to be fed to an AI
> coding assistant (or followed manually) to generate the actual code.

---

## 1. High-Level Architecture

```
                                    Internet
                                       │
                          ┌────────────▼────────────┐
                          │  VM21/VM22 NGINX+HAProxy  │  (public subnet, active-passive
                          │  Load Balancers (VIP)      │   or keepalived VRRP)
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

**Key architectural decisions to state explicitly in `docs/architecture.md`:**
- Kubernetes runs **stacked etcd** on the 3 control-plane nodes (simpler) vs **external etcd
  cluster** (more resilient, more VMs) — recommend **stacked** for this VM budget.
- VM23 (Backend)/VM24 (Frontend) are **legacy/standalone deployment targets** for apps that
  are NOT containerized in this exercise (e.g. a bare-metal comparison target), while the
  three primary applications (App1/App2/App3) run **inside Kubernetes** on VM11-16. Document
  this split clearly so it isn't ambiguous.
- VM21 (NGINX) fronts HTTP/HTTPS traffic to the Kubernetes Ingress controller; VM22 (HAProxy)
  load-balances TCP traffic to the **Kubernetes API server** (port 6443) across the 3 control
  planes for HA `kubectl`/kubeadm join access. This is the standard "HAProxy in front of the
  K8s API, NGINX in front of app traffic" pattern — document it so the two LBs aren't seen as
  redundant.

---

## 2. Network Plan

| Item | Value |
|---|---|
| VPC/VNet | `10.0.0.0/16` |
| Public subnet | `10.0.1.0/24` (Bastion + LBs only) |
| Private subnet — mgmt/CI | `10.0.2.0/24` |
| Private subnet — k8s | `10.0.3.0/24` |
| Private subnet — data | `10.0.4.0/24` |
| Private subnet — monitoring | `10.0.5.0/24` |
| Private subnet — apps (standalone) | `10.0.6.0/24` |
| Internal DNS | private DNS zone (e.g. `*.internal.lab`) or Ansible-managed `/etc/hosts` |
| SSH | Bastion only, key-based, port 22 |

### IP Allocation

| VM | Hostname | Subnet | IP |
|---|---|---|---|
| VM01 | bastion | public | 10.0.1.10 |
| VM02 | terraform-srv | mgmt | 10.0.2.10 |
| VM03 | ansible-srv | mgmt | 10.0.2.11 |
| VM04 | git-srv | mgmt | 10.0.2.12 |
| VM05 | jenkins-master | mgmt | 10.0.2.20 |
| VM06 | jenkins-agent1 | mgmt | 10.0.2.21 |
| VM07 | jenkins-agent2 | mgmt | 10.0.2.22 |
| VM08 | k8s-cp1 | k8s | 10.0.3.10 |
| VM09 | k8s-cp2 | k8s | 10.0.3.11 |
| VM10 | k8s-cp3 | k8s | 10.0.3.12 |
| VM11-16 | k8s-wk1..6 | k8s | 10.0.3.20–25 |
| VM17 | pg-primary | data | 10.0.4.10 |
| VM18 | pg-replica | data | 10.0.4.11 |
| VM19 | prometheus | monitoring | 10.0.5.10 |
| VM20 | grafana | monitoring | 10.0.5.11 |
| VM21 | nginx-lb | public | 10.0.1.20 |
| VM22 | haproxy-lb | public | 10.0.1.21 |
| VM23 | backend-standalone | apps | 10.0.6.10 |
| VM24 | frontend-standalone | apps | 10.0.6.11 |
| VM25 | test-staging | apps | 10.0.6.12 |

### Security Groups

| SG | Applies to | Rules |
|---|---|---|
| `sg-bastion` | VM01 | 22 from admin IP/0.0.0.0/0 |
| `sg-lb` | VM21-22 | 80/443/6443 from internet or bastion; internal to k8s/apps |
| `sg-mgmt` | VM02-07 | 22 from bastion; 8080/50000 (Jenkins) internal only |
| `sg-k8s-cp` | VM08-10 | 6443, 2379-2380, 10250-10259 internal only; from haproxy-lb on 6443 |
| `sg-k8s-worker` | VM11-16 | 10250, 30000-32767 internal only |
| `sg-data` | VM17-18 | 5432 from k8s subnet + mgmt subnet only |
| `sg-monitoring` | VM19-20 | 9090/3000 internal only; scrape access to all subnets on 9100/metrics ports |
| `sg-apps` | VM23-25 | 8000/80 internal + from LB |

---

## 3. Repository Structure (file-level)

```
enterprise-devops-platform/
├── README.md
├── Makefile
├── .gitignore
│
├── terraform/
│   ├── environments/
│   │   ├── dev/
│   │   │   ├── main.tf
│   │   │   ├── terraform.tfvars
│   │   │   └── backend.tf
│   │   └── prod/                      # mirrors dev, different sizing/counts
│   ├── modules/
│   │   ├── network/                   # VPC, 5 subnets, route tables, NAT/IGW
│   │   ├── security-groups/           # one resource block per SG above
│   │   ├── compute/                   # for_each over a vm map (25 entries)
│   │   └── load-balancer/             # optional cloud LB / VIP resource if not self-managed
│   └── variables/
│       └── vm-map.tf                  # single source of truth: {name, role, subnet, sg, size}
│
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── dynamic_inventory.py       # pulls from terraform output -json
│   │   └── group_vars/
│   │       ├── all.yml
│   │       ├── k8s_control_plane.yml
│   │       ├── k8s_workers.yml
│   │       ├── jenkins.yml
│   │       ├── postgresql.yml
│   │       └── loadbalancers.yml
│   ├── site.yml
│   ├── playbooks/
│   │   ├── 01-common.yml
│   │   ├── 02-docker.yml
│   │   ├── 03-k8s-control-plane-ha.yml
│   │   ├── 04-k8s-workers.yml
│   │   ├── 05-jenkins.yml
│   │   ├── 06-postgresql-ha.yml
│   │   ├── 07-loadbalancers.yml
│   │   ├── 08-monitoring.yml
│   │   └── 09-deploy-apps.yml
│   └── roles/
│       ├── common/
│       ├── docker/
│       ├── k8s-common/
│       ├── k8s-control-plane/         # kubeadm init --control-plane-endpoint=<haproxy VIP>:6443
│       ├── k8s-control-plane-join/    # kubeadm join --control-plane for CP2/CP3
│       ├── k8s-worker/
│       ├── jenkins-master/
│       ├── jenkins-agent/
│       ├── postgresql-primary/        # streaming replication setup
│       ├── postgresql-replica/        # pg_basebackup + recovery.conf/standby.signal
│       ├── nginx-lb/
│       ├── haproxy-lb/                # balances 6443 across k8s-cp1..3
│       ├── prometheus/
│       ├── node_exporter/
│       ├── postgres_exporter/
│       └── grafana/
│
├── kubernetes/
│   ├── namespaces.yml                 # app1, app2, app3, ingress-nginx, monitoring
│   ├── ingress/
│   │   └── ingress-controller-values.yml   # helm values for nginx-ingress
│   ├── app1-taskmanager/
│   │   ├── backend-deployment.yml
│   │   ├── backend-service.yml
│   │   ├── frontend-deployment.yml
│   │   ├── frontend-service.yml
│   │   ├── configmap.yml
│   │   ├── secret.yml
│   │   └── ingress.yml
│   ├── app2-nodemongo/
│   │   ├── deployment.yml
│   │   ├── service.yml
│   │   ├── mongo-statefulset.yml
│   │   ├── mongo-pvc.yml
│   │   ├── mongo-secret.yml
│   │   └── ingress.yml
│   └── app3-static-site/
│       ├── deployment.yml             # nginx serving static content, built via ConfigMap or baked image
│       ├── service.yml
│       └── ingress.yml
│
├── docker/
│   ├── app1-backend/Dockerfile
│   ├── app1-frontend/Dockerfile
│   ├── app2-node/Dockerfile
│   └── app3-static/Dockerfile
│
├── jenkins/
│   ├── Jenkinsfile.app1
│   ├── Jenkinsfile.app2
│   ├── Jenkinsfile.app3
│   └── shared-library/                # reusable pipeline steps (build, test, push, deploy)
│       └── vars/
│           ├── buildImage.groovy
│           └── deployToK8s.groovy
│
├── applications/
│   ├── app1/
│   │   ├── backend/                   # FastAPI, talks to PostgreSQL (VM17/18 or in-cluster)
│   │   └── frontend/                  # React
│   ├── app2/
│   │   └── src/                       # Node.js + Express, talks to MongoDB in-cluster
│   └── app3/
│       └── site/                      # static HTML/CSS/JS
│
├── monitoring/
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   └── alert.rules.yml            # node down, pod crashloop, replica lag, disk >85%
│   └── grafana/
│       └── dashboards/
│           ├── node-exporter.json
│           ├── kubernetes-cluster.json
│           ├── postgresql.json
│           ├── jenkins.json
│           └── applications.json
│
├── scripts/
│   ├── bootstrap.sh                   # terraform apply -> inventory -> ansible site.yml
│   ├── generate-inventory.py
│   ├── k8s-join-token-refresh.sh
│   └── failover-test.sh               # simulates a control-plane/replica failure
│
└── docs/
    ├── architecture.md
    ├── infrastructure-diagram.md
    ├── network-diagram.md
    ├── vm-documentation.md
    ├── deployment-guide.md
    ├── recovery-guide.md
    ├── user-guide.md
    └── troubleshooting.md
```

---

## 4. Terraform — Module Responsibilities

- **`modules/network`**: 1 VPC, 5 subnets (public, mgmt, k8s, data, monitoring, apps —
  actually 6, adjust table), route tables, IGW, NAT gateway for private egress.
- **`modules/security-groups`**: 8 SGs as listed in §2, referenced by name from `compute`.
- **`modules/compute`**: single `for_each` over `var.vm_map` (25 entries) so every VM is
  defined declaratively in `variables/vm-map.tf` — role, subnet, instance size, SG, static IP.
- **`modules/load-balancer`**: only needed if using a cloud-managed LB in addition to
  self-managed NGINX/HAProxy VMs; otherwise omit and treat VM21/22 as regular compute.
- **`environments/dev` vs `prod`**: same modules, different `.tfvars` (e.g. dev uses smaller
  instance sizes and maybe fewer worker nodes to control cost — document as optional).
- Remote state backend (S3+DynamoDB lock, or GCS, or Terraform Cloud) — required at this
  scale since multiple people/pipelines may run Terraform.

---

## 5. Ansible — Role Responsibilities (HA-specific additions vs the 12-VM lab)

| Role | Applies to | Key tasks |
|---|---|---|
| `k8s-control-plane` | VM08 | `kubeadm init --control-plane-endpoint=<haproxy-vip>:6443 --upload-certs`; install CNI (Calico recommended at this scale for NetworkPolicy support) |
| `k8s-control-plane-join` | VM09, VM10 | `kubeadm join <vip>:6443 --control-plane --certificate-key=<key>` |
| `k8s-worker` | VM11-16 | standard `kubeadm join` |
| `haproxy-lb` | VM22 | `haproxy.cfg` with a `frontend` on 6443 and `backend` listing VM08-10 IPs, round-robin, health check via `httpchk` on `/healthz` |
| `nginx-lb` | VM21 | reverse proxy to Ingress controller NodePort(s) on the worker nodes, or to a cloud LB if used |
| `postgresql-primary` | VM17 | install Postgres, `wal_level=replica`, `max_wal_senders`, create replication user |
| `postgresql-replica` | VM18 | `pg_basebackup` from primary, `standby.signal` / `primary_conninfo`, verify streaming replication lag via `pg_stat_replication` |
| `jenkins-master` | VM05 | Jenkins core + plugins (Pipeline, Git, Docker, Kubernetes CLI, Configuration as Code) |
| `jenkins-agent` | VM06-07 | JNLP agent registration to master, Docker installed for image builds |
| `prometheus` | VM19 | scrape configs for all node_exporters, kube-state-metrics, postgres_exporter (both primary+replica), Jenkins `/prometheus` endpoint |
| `postgres_exporter` | VM17-18 | exposes replication lag, connection count, cache hit ratio on port 9187 |
| `grafana` | VM20 | provisioned datasource + all dashboards from `monitoring/grafana/dashboards/` |

`site.yml` order: common → docker → k8s-control-plane → k8s-control-plane-join →
k8s-worker → loadbalancers → jenkins → postgresql (primary then replica) → monitoring →
deploy-apps.

---

## 6. Kubernetes — HA & Multi-App Detail

- **etcd**: stacked topology across VM08-10; back up regularly (`etcdctl snapshot save`) —
  document backup/restore in `docs/recovery-guide.md`.
- **CNI**: Calico (supports NetworkPolicy, useful for isolating app1/app2/app3 namespaces
  from each other).
- **Ingress**: nginx-ingress-controller (via Helm), one Ingress resource per app, all fronted
  by VM21.
- **Namespaces**: `app1`, `app2`, `app3`, `ingress-nginx`, `monitoring` (if running
  kube-state-metrics/exporters in-cluster), `kube-system`.
- **App1 (Task Manager)**: FastAPI backend + React frontend + external PostgreSQL
  (VM17/18) via a K8s `ExternalName` Service or direct `DB_HOST` env pointing at
  the HAProxy'd or primary Postgres IP.
- **App2 (Node + MongoDB)**: MongoDB runs **inside** the cluster as a `StatefulSet` with PVC
  (single instance is fine for lab scope; note that production would need a replica set).
- **App3 (Static site)**: simplest — `Deployment` of `nginx:alpine` with the static files
  baked into the image at build time via the Jenkins pipeline (`COPY site/ /usr/share/nginx/html`).
- **Rolling updates**: set `strategy.rollingUpdate.maxSurge/maxUnavailable` (e.g. 1/0) on
  every Deployment, and configure `readinessProbe`/`livenessProbe` on each container so
  Kubernetes only routes traffic to ready pods during a rollout.
- **Resource requests/limits**: mandatory on every container given the larger blast radius
  of 6 worker nodes (avoid noisy-neighbor scheduling problems).

---

## 7. Jenkins Pipelines

Use a **shared library** (`jenkins/shared-library/`) so `Jenkinsfile.app1/2/3` stay short and
call common steps: `buildImage()`, `runTests()`, `pushImage()`, `deployToK8s()`.

Common stages per app pipeline:
1. Checkout (triggered by GitHub webhook or SCM polling if Jenkins isn't internet-reachable).
2. Install deps + run unit tests (`pytest` / `npm test`, per app).
3. Build Docker image, tag `${GIT_COMMIT_SHORT}`.
4. Push to registry (Docker Hub or GHCR — pick one, store creds in Jenkins Credentials).
5. Deploy: `kubectl set image` or `helm upgrade` against the target namespace, using a
   kubeconfig pointed at the HAProxy VIP (`https://<haproxy-vip>:6443`) so deploys survive
   a single control-plane node failure.
6. Smoke test against VM25 (staging) before promoting, or run the smoke test directly
   post-deploy in the target namespace.
7. Post: archive JUnit XML, notify on failure.

Jenkins agents (VM06-07) should have distinct labels (`docker`, `node`) so pipelines can pin
`agent { label 'docker' }` and parallelize app1/app2/app3 builds across the two agents.

---

## 8. Monitoring — Concrete Scrape Targets & Alerts

**Prometheus jobs:**
- `node_exporter` — all 25 VMs, port 9100.
- `kubernetes-nodes/pods/cadvisor` — via `kubernetes_sd_configs` against the API (through
  the HAProxy VIP or in-cluster if Prometheus runs as a K8s Deployment instead of on VM19 —
  pick one and document; VM19 as a standalone Prometheus VM scraping the cluster externally
  is simpler to reason about for this lab).
- `postgres_exporter` — VM17 and VM18, port 9187, so replica lag is visible.
- `jenkins` — VM05, `/prometheus` endpoint (requires Prometheus plugin).
- `haproxy` — VM22 stats endpoint (`/stats` with Prometheus exporter or built-in exposition).

**Example alert rules (`alert.rules.yml`):**
- `NodeDown` — `up == 0` for 2m.
- `PostgresReplicationLagHigh` — `pg_replication_lag_seconds > 30`.
- `KubePodCrashLooping` — restart count increasing rapidly.
- `DiskSpaceLow` — `node_filesystem_avail_bytes / node_filesystem_size_bytes < 0.15`.
- `HAProxyBackendDown` — any backend server marked down.

**Grafana dashboards:** Node Exporter Full (ID 1860), Kubernetes Cluster (ID 315/7249),
PostgreSQL (ID 9628), Jenkins (community or custom via Prometheus plugin metrics), and a
custom "Applications" dashboard combining request rate/error rate/latency per app namespace.

---

## 9. Deployment Workflow (concrete commands)

```bash
# 1. Provision infrastructure
cd terraform/environments/dev
terraform init
terraform apply -auto-approve

# 2. Generate dynamic inventory
cd ../../../scripts
python3 generate-inventory.py > ../ansible/inventory/hosts.ini

# 3. Configure everything (idempotent, safe to re-run)
cd ../ansible
ansible-playbook -i inventory/hosts.ini site.yml

# 4. Verify HA control plane
ssh -J bastion ubuntu@10.0.3.10 "kubectl get nodes -o wide"
curl -k https://10.0.1.21:6443/healthz     # via HAProxy VIP

# 5. Verify PostgreSQL replication
ssh -J bastion ubuntu@10.0.4.11 "sudo -u postgres psql -c \"select * from pg_stat_wal_receiver;\""

# 6. Deploy applications (first time manually; afterwards via Jenkins)
kubectl apply -f ../kubernetes/namespaces.yml
kubectl apply -f ../kubernetes/app1-taskmanager/
kubectl apply -f ../kubernetes/app2-nodemongo/
kubectl apply -f ../kubernetes/app3-static-site/

# 7. Verify monitoring
curl http://10.0.5.10:9090/-/healthy
curl http://10.0.5.11:3000/api/health

# 8. Access applications through the load balancer
curl http://10.0.1.20/app1/
curl http://10.0.1.20/app2/
curl http://10.0.1.20/app3/
```

`scripts/bootstrap.sh` wraps steps 1–3; `scripts/failover-test.sh` optionally automates
step-4/5-style validation by stopping a control-plane node or the Postgres primary and
confirming the cluster/replica keep serving traffic — useful evidence for the "High
Availability" objective in the brief.

---

## 10. Documentation Deliverables (contents checklist)

- `docs/architecture.md` — component diagram, the CP/etcd topology decision, LB role split
  (NGINX for app traffic vs HAProxy for K8s API).
- `docs/infrastructure-diagram.md` — all 25 VMs grouped by layer (reuse the tables above).
- `docs/network-diagram.md` — 6-subnet layout, SG matrix.
- `docs/vm-documentation.md` — per-VM: role, software, ports, HA pairing (e.g. "VM09/VM10
  are peers of VM08").
- `docs/deployment-guide.md` — full bootstrap sequence, Jenkins pipeline usage, how to add a
  4th application.
- `docs/recovery-guide.md` — etcd backup/restore, Postgres failover (promote replica to
  primary), what to do if a worker node dies (K8s reschedules automatically — explain how to
  verify), HAProxy/NGINX failover if only one is deployed instead of a VRRP pair.
- `docs/user-guide.md` — how to reach each application, how to check its status/logs.
- `docs/troubleshooting.md` — kubeadm join token expiry, etcd quorum loss (need 2/3 nodes),
  replication lag causes, Jenkins agent disconnects, ingress 502s.

---

## 11. Suggested Build Order (incremental generation)

1. Terraform: network + security-groups + compute (all 25 VMs) — validate with `terraform plan`
   before touching Ansible.
2. Ansible `common` + `docker` roles across all VMs.
3. HAProxy (VM22) first — needed as the `--control-plane-endpoint` target before `kubeadm init`.
4. Kubernetes HA control plane (VM08 init, VM09/10 join), then workers (VM11-16), then Calico
   + nginx-ingress via Helm.
5. PostgreSQL primary (VM17) then replica (VM18) — verify replication before moving on.
6. Applications' code + Dockerfiles (`applications/`, `docker/`).
7. Kubernetes manifests for app1/app2/app3 — deploy manually once to validate end-to-end.
8. NGINX LB (VM21) routing to the Ingress controller.
9. Jenkins master/agents + shared library + per-app Jenkinsfiles — automate future deploys.
10. Monitoring stack (VM19/20) + exporters everywhere — last, since it depends on everything
    else already running.
11. Documentation, written last so it reflects what was actually built; run
    `scripts/failover-test.sh` and record the results in `docs/recovery-guide.md`.

---

## 12. Open Decisions to Confirm Before Generating Code

- [ ] Cloud provider for Terraform (`aws`, `gcp`, `azure`, or on-prem `libvirt`/local for a
      no-cost lab — at 25 VMs, cost matters, so this should be decided early)?
- [ ] Registry: Docker Hub vs GHCR?
- [ ] CNI: Calico (recommended for NetworkPolicy) vs Flannel (simpler, no NetworkPolicy)?
- [ ] Is App1's PostgreSQL the external VM17/18 pair, or should each app get its own
      in-cluster database except where a dedicated Postgres tier is specifically being
      demonstrated? (Recommended: keep VM17/18 dedicated to App1 to fulfill the "Primary +
      Replica" objective explicitly.)
- [ ] VRRP/keepalived between VM21 and VM22 for true LB HA, or accept them as single points
      of failure for lab simplicity (document the trade-off either way)?
- [ ] Terraform remote state backend choice (S3+DynamoDB, GCS, Terraform Cloud)?
