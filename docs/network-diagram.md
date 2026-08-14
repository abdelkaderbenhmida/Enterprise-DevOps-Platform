# Network Diagram

## VPC Overview

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
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Traffic Flows

### 1. External User → Applications
```
Internet
    │
    ▼
┌─────────────────┐
│  AWS ALB (opt)  │  (if using cloud LB in front)
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│ VM21 NGINX LB   │◄───►│ VM22 HAProxy LB │  (keepalived VRRP VIP: 10.0.1.100)
│ Port 80/443     │     │ Port 6443       │
└────────┬────────┘     └─────────────────┘
         │
         ▼
┌──────────────────────────────────────┐
│ NGINX upstream: k8s_ingress          │
│ least_conn to 6 workers:30080        │
└────────┬─────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────┐
│ K8s Worker Nodes (NodePort 30080)    │
│ nginx-ingress-controller Pods        │
└────────┬─────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────┐
│ Ingress Resources → Services → Pods  │
│ app1/app2/app3 namespaces            │
└──────────────────────────────────────┘
```

### 2. kubectl / CI/CD → Kubernetes API
```
Client (kubectl/Jenkins)
    │
    ▼
┌─────────────────┐     ┌─────────────────┐
│ VM22 HAProxy LB │◄───►│ VM21 NGINX LB   │  (VIP: 10.0.1.100)
│ Port 6443       │     │ Port 6443       │
└────────┬────────┘     └─────────────────┘
         │
         ▼
┌──────────────────────────────────────┐
│ HAProxy backend: k8s_masters         │
│ roundrobin to 3 CPs:6443             │
│ health check: /healthz               │
└────────┬─────────────────────────────┘
         │
    ┌────┴────┬────┐
    ▼         ▼    ▼
┌──────┐  ┌──────┐  ┌──────┐
│ CP1  │  │ CP2  │  │ CP3  │
│:6443 │  │:6443 │  │:6443 │
└──────┘  └──────┘  └──────┘
```

### 3. Applications → PostgreSQL
```
K8s Pods (app1 namespace)
    │
    ▼
┌──────────────────────────────────────┐
│ K8s Service: postgres-primary        │
│ Type: ExternalName                   │
│ ExternalName: vm17-pg-primary        │
└────────┬─────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────┐
│ VM17 PG Primary (10.0.4.10:5432)     │
│ sg-data allows from 10.0.3.0/24      │
└────────┬─────────────────────────────┘
         │
         ▼ (async replication)
┌──────────────────────────────────────┐
│ VM18 PG Replica (10.0.4.11:5432)     │
│ Hot standby, read-only               │
└──────────────────────────────────────┘
```

### 4. Monitoring Scraping
```
Prometheus (VM19:9090)
    │
    ├──────────────────┬──────────────────┬──────────────────┐
    ▼                  ▼                  ▼                  ▼
┌─────────┐        ┌─────────┐        ┌─────────┐        ┌─────────┐
│All 25   │        │K8s API  │        │Postgres │        │Jenkins  │
│Nodes    │        │Server   │        │Exporter │        │(8080)   │
│:9100    │        │:6443    │        │:9187    │        │/promet- │
│         │        │(kube-   │        │(VM17,18)│        │heus)    │
│node_ex- │        │state-   │        │         │        │         │
│porter   │        │metrics) │        │         │        │         │
└─────────┘        └─────────┘        └─────────┘        └─────────┘
    │                  │                  │                  │
    └──────────────────┴──────────────────┴──────────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │ Alertmanager│ (if deployed)
                    └─────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │  Grafana    │
                    │  (VM20:3000)│
                    └─────────────┘
```

### 5. SSH Access (Bastion Pattern)
```
Admin Workstation
    │
    ▼ (SSH key)
┌─────────────────┐
│ VM01 Bastion    │
│ 10.0.1.10:22    │
│ sg-bastion      │
└────────┬────────┘
         │
    ┌────┼────┬────┬────┬────┬────┐
    ▼    ▼    ▼    ▼    ▼    ▼    ▼
┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐
│VM02│ │VM03│ │VM04│ │VM05│ │VM06│ │VM07│
│... │ │... │ │... │ │... │ │... │ │... │
└────┘ └────┘ └────┘ └────┘ └────┘ └────┘
```

## DNS / Service Discovery

### Internal DNS (Ansible-managed /etc/hosts)
```
10.0.1.10    bastion
10.0.1.20    nginx-lb
10.0.1.21    haproxy-lb
10.0.1.100   k8s-api.internal.lb  # VIP
10.0.2.10    terraform-srv
10.0.2.11    ansible-srv
10.0.2.12    git-srv
10.0.2.20    jenkins-master
10.0.2.21    jenkins-agent1
10.0.2.22    jenkins-agent2
10.0.3.10    k8s-cp1
10.0.3.11    k8s-cp2
10.0.3.12    k8s-cp3
10.0.3.20    k8s-wk1
10.0.3.21    k8s-wk2
10.0.3.22    k8s-wk3
10.0.3.23    k8s-wk4
10.0.3.24    k8s-wk5
10.0.3.25    k8s-wk6
10.0.4.10    pg-primary
10.0.4.11    pg-replica
10.0.5.10    prometheus
10.0.5.11    grafana
10.0.6.10    backend-standalone
10.0.6.11    frontend-standalone
10.0.6.12    test-staging
```

### Kubernetes Internal DNS
```
kubernetes.default.svc.cluster.local          # K8s API (via HAProxy VIP)
postgres-primary.app1.svc.cluster.local       # ExternalName → pg-primary
mongodb.app2.svc.cluster.local                # ClusterIP → MongoDB StatefulSet
app1-backend.app1.svc.cluster.local           # ClusterIP → App1 backend
app1-frontend.app1.svc.cluster.local          # ClusterIP → App1 frontend
app2-node.app2.svc.cluster.local              # ClusterIP → App2 node
app3-static.app3.svc.cluster.local            # ClusterIP → App3 static
```

## Port Reference

| Service | Port | Protocol | Source | Destination |
|---------|------|----------|--------|-------------|
| SSH | 22 | TCP | Admin CIDR → Bastion; Bastion → All | All VMs |
| HTTP | 80 | TCP | Internet → NLB | VM21 |
| HTTPS | 443 | TCP | Internet → NLB | VM21 |
| K8s API | 6443 | TCP | Internet → HAProxy; HAProxy → CPs | VM22 → VM08-10 |
| etcd | 2379-2380 | TCP | CPs → CPs | VM08-10 |
| Kubelet | 10250 | TCP | CPs → Workers | VM08-10 → VM11-16 |
| NodePort | 30000-32767 | TCP | NLB → Workers | VM21 → VM11-16 |
| PostgreSQL | 5432 | TCP | K8s subnet, Mgmt subnet → PG | VM11-16, VM02-07 → VM17-18 |
| Prometheus | 9090 | TCP | Monitoring subnet | VM19 |
| Grafana | 3000 | TCP | Monitoring subnet | VM20 |
| node_exporter | 9100 | TCP | Prometheus → All | VM19 → All |
| postgres_exporter | 9187 | TCP | Prometheus → PG | VM19 → VM17-18 |
| Jenkins | 8080 | TCP | Mgmt subnet | VM05 |
| JNLP Agent | 50000 | TCP | Mgmt subnet | VM05 |
| HAProxy Stats | 9000 | TCP | Prometheus → HAProxy | VM19 → VM22 |
| keepalived VRRP | 112 | VRRP | VM21 ↔ VM22 | VM21 ↔ VM22 |