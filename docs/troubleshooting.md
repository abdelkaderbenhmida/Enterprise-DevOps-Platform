# Troubleshooting Guide

## Quick Diagnostic Commands

### Infrastructure Level
```bash
# Check all VMs reachable
ansible all -i inventory/hosts.ini -m ping

# Check Terraform state
cd terraform/environments/dev
terraform state list
terraform show

# Check Azure resources
az vm list -g enterprise-devops-dev -o table
az resource list -g enterprise-devops-dev --resource-type Microsoft.Network/networkSecurityGroups -o table
```

### Kubernetes Level
```bash
# Cluster health
kubectl get nodes -o wide
kubectl get cs
kubectl top nodes

# Control plane pods
kubectl -n kube-system get pods -o wide

# Etcd health
kubectl -n kube-system exec etcd-k8s-cp1 -- etcdctl endpoint health --cluster \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# CNI status
kubectl -n calico-system get pods
kubectl -n kube-system get pods -l k8s-app=calico-node

# Ingress controller
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx get svc
```

### Application Level
```bash
# All pods status
kubectl get pods -A -o wide

# Failed pods
kubectl get pods -A --field-selector=status.phase!=Running

# Events
kubectl get events -A --sort-by='.lastTimestamp' | tail -50

# Resource usage
kubectl top pods -A
kubectl top nodes
```

### Database Level
```bash
# PostgreSQL primary
ssh -J bastion ubuntu@10.0.4.10 "sudo -u postgres psql -c 'SELECT * FROM pg_stat_activity;'"
ssh -J bastion ubuntu@10.0.4.10 "sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'"

# PostgreSQL replica
ssh -J bastion ubuntu@10.0.4.11 "sudo -u postgres psql -c 'SELECT * FROM pg_stat_wal_receiver;'"

# Replication lag
ssh -J bastion ubuntu@10.0.4.11 "sudo -u postgres psql -c 'SELECT now() - pg_last_xact_replay_timestamp() AS lag;'"
```

### Monitoring Level
```bash
# Prometheus targets
curl -s http://10.0.5.10:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'

# Prometheus rules
curl -s http://10.0.5.10:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.alert) | {alert: .alert, state: .state}'

# Grafana health
curl -s http://10.0.5.11:3000/api/health
```

---

## Common Issues & Solutions

### 1. Terraform Issues

#### Terraform Init Fails - Backend Configuration
```
Error: Backend initialization failed
```
**Solution**: Verify S3 bucket and DynamoDB table exist, check AWS credentials.

#### Terraform Apply Fails - Instance Limit Exceeded
```
Error: InsufficientInstanceCapacity
```
**Solution**: Try different AZ, reduce instance count, or request limit increase.

#### Terraform State Lock
```
Error: Error acquiring the state lock
```
**Solution**: 
```bash
# Force unlock (use carefully!)
terraform force-unlock <LOCK_ID>
```

#### Resource Already Exists
```
Error: resource already exists
```
**Solution**: Import existing resource or delete manually and re-apply.
```bash
terraform import azurerm_linux_virtual_machine.vm["vm01-bastion"] i-1234567890abcdef0
```

---

### 2. Ansible Issues

#### SSH Connection Failed
```
UNREACHABLE! => {"msg": "Failed to connect to the host via ssh"}
```
**Solution**:
```bash
# Check SSH key
ssh -i ~/.ssh/id_rsa ubuntu@<IP>

# Check security groups allow SSH from bastion
# Check bastion can reach target
ssh -J bastion ubuntu@<TARGET_IP> "echo test"

# Verify inventory IPs correct
cat ansible/inventory/hosts.ini
```

#### Python Not Found
```
"msg": "/usr/bin/python3: not found"
```
**Solution**: 
```bash
# On target host
apt update && apt install -y python3

# Or set ansible_python_interpreter in inventory
```

#### Package Install Fails
```
"apt" module failed
```
**Solution**:
```bash
# Run apt update first
ansible all -b -m apt -a "update_cache=yes"

# Check /var/lib/dpkg/lock
ansible all -b -a "lsof /var/lib/dpkg/lock"
```

#### Role Dependency Missing
```
ERROR! The role 'xyz' was not found
```
**Solution**: Check `roles_path` in ansible.cfg, ensure role directory exists.

---

### 3. Kubernetes Issues

#### Control Plane Won't Initialize
```
[kubelet-check] The HTTP call equal to 'healthz' failed
```
**Solution**:
```bash
# Check containerd
systemctl status containerd
journalctl -u containerd -f

# Check kubelet
journalctl -u kubelet -f

# Check kubeadm config
cat /etc/kubernetes/kubeadm/init.yaml

# Reset and retry
kubeadm reset -f
rm -rf /etc/kubernetes /var/lib/etcd
# Re-run Ansible k8s-control-plane role
```

#### Control Plane Join Fails
```
[ERROR CRI]: container runtime is not running
```
**Solution**:
```bash
# On joining node
systemctl status containerd
systemctl start containerd

# Check CRI socket
ls -la /run/containerd/containerd.sock

# Retry join
kubeadm join ... --v=5
```

#### Worker Node Not Ready
```
STATUS: NotReady
```
**Solution**:
```bash
# Check kubelet
journalctl -u kubelet -f

# Check CNI
kubectl -n calico-system get pods -o wide
kubectl -n kube-system get pods -l k8s-app=calico-node

# Check node conditions
kubectl describe node <node-name>

# Common: CNI not installed on worker
# Calico DaemonSet should handle this automatically
```

#### Pods Stuck in Pending
```
STATUS: Pending
```
**Solution**:
```bash
kubectl describe pod <pod-name> -n <namespace>

# Common causes:
# 1. Insufficient resources - check node capacity
kubectl describe nodes

# 2. PVC not bound - check storage class
kubectl get pvc -n <namespace>
kubectl get sc

# 3. Node selector/affinity not matching
# 4. Taints/tolerations
kubectl describe node <node-name> | grep -i taint
```

#### Pods CrashLoopBackOff
```
STATUS: CrashLoopBackOff
```
**Solution**:
```bash
# Check logs
kubectl logs <pod-name> -n <namespace> --previous

# Check events
kubectl describe pod <pod-name> -n <namespace>

# Common causes:
# 1. Application config error - check ConfigMap/Secret
# 2. Database connection failed - check service, DNS, SG
# 3. Resource limits too low - OOMKilled
kubectl describe pod <pod-name> | grep -i oom

# 4. Probe failing - check readiness/liveness endpoints
```

#### DNS Resolution Fails
```
dial tcp: lookup <service> on 10.96.0.10:53: no such host
```
**Solution**:
```bash
# Check CoreDNS
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns

# Restart CoreDNS
kubectl -n kube-system rollout restart deployment/coredns

# Check service exists
kubectl get svc -n <namespace>
```

#### Ingress Not Working
```
502 Bad Gateway or 404
```
**Solution**:
```bash
# Check ingress controller
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx logs -l app.kubernetes.io/component=controller

# Check ingress resource
kubectl get ingress -n <namespace>
kubectl describe ingress <name> -n <namespace>

# Check service endpoints
kubectl get endpoints -n <namespace>

# Check service selector matches pod labels
kubectl get pods -n <namespace> --show-labels
kubectl get svc <name> -n <namespace> -o yaml
```

---

### 4. PostgreSQL Issues

#### Primary Down
```
could not connect to server: Connection refused
```
**Solution**:
```bash
# Check service
systemctl status postgresql

# Check logs
journalctl -u postgresql -f
tail -f /var/log/postgresql/postgresql-15-main.log

# Check port
ss -tlnp | grep 5432

# Restart
systemctl restart postgresql
```

#### Replication Lag High
```
pg_replication_lag_seconds > 30
```
**Solution**:
```bash
# Check network latency
ping 10.0.4.10

# Check WAL generation rate
# On primary:
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"

# Check replica applying
# On replica:
sudo -u postgres psql -c "SELECT * FROM pg_stat_wal_receiver;"

# Increase wal_keep_size on primary
# postgresql.conf: wal_keep_size = 2GB
systemctl reload postgresql
```

#### Replication Broken
```
FATAL: could not receive data from WAL stream
```
**Solution**:
```bash
# Rebuild replica (see Recovery Guide)
# On replica:
systemctl stop postgresql
rm -rf /var/lib/postgresql/15/main/*
pg_basebackup -h <primary> -D /var/lib/postgresql/15/main -U replicator -v -P -W
touch /var/lib/postgresql/15/main/standby.signal
systemctl start postgresql
```

#### Too Many Connections
```
FATAL: remaining connection slots are reserved
```
**Solution**:
```bash
# Check current connections
sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_activity;"

# Check max_connections
sudo -u postgres psql -c "SHOW max_connections;"

# Increase if needed (requires restart)
# postgresql.conf: max_connections = 200
systemctl restart postgresql

# Consider PgBouncer for connection pooling
```

---

### 5. Load Balancer Issues

#### HAProxy VIP Not Responding
```
curl: (7) Failed to connect to 10.0.1.100 port 6443
```
**Solution**:
```bash
# Check keepalived
systemctl status keepalived

# Check VIP assigned
ip addr show dev eth0 | grep 10.0.1.100

# Check VRRP packets
tcpdump -i eth0 vrrp

# Check HAProxy
systemctl status haproxy
haproxy -c -f /etc/haproxy/haproxy.cfg

# Check backends
echo "show stat" | socat stdio /var/run/haproxy/stats.socket
```

#### NGINX 502 Bad Gateway
```
502 Bad Gateway
```
**Solution**:
```bash
# Check upstream
nginx -t
systemctl status nginx

# Check upstream servers reachable
for ip in 10.0.3.20 10.0.3.21 10.0.3.22 10.0.3.23 10.0.3.24 10.0.3.25; do
  curl -s -o /dev/null -w "%{http_code}" http://$ip:30080/healthz
done

# Check ingress controller pods
kubectl -n ingress-nginx get pods -o wide

# Check NodePort
kubectl -n ingress-nginx get svc ingress-nginx-controller
```

---

### 6. Jenkins Issues

#### Jenkins Not Starting
```
Jenkins service failed to start
```
**Solution**:
```bash
# Check Java
java -version

# Check Jenkins logs
journalctl -u jenkins -f
tail -f /var/log/jenkins/jenkins.log

# Check port 8080
ss -tlnp | grep 8080

# Check JCasC config
cat /var/lib/jenkins/casc.yaml
```

#### Agents Not Connecting
```
Agent offline
```
**Solution**:
```bash
# On agent
systemctl status jenkins-agent
journalctl -u jenkins-agent -f

# Check JNLP URL
curl http://jenkins-master:8080/computer/<agent-name>/jenkins-agent.jnlp

# Check secret correct
# Re-run Ansible jenkins-agent role
```

#### Build Fails - Docker Permission
```
permission denied while trying to connect to the Docker daemon socket
```
**Solution**:
```bash
# On agent, add jenkins user to docker group
usermod -aG docker jenkins
systemctl restart jenkins-agent
```

---

### 7. Monitoring Issues

#### Prometheus Targets Down
```
Health: down
```
**Solution**:
```bash
# Check target reachable from Prometheus
ssh ubuntu@10.0.5.10 "curl -s http://<target-ip>:<port>/metrics"

# Check firewall/SG allows 9090/9100/9187 from Prometheus subnet

# Check scrape config
cat /etc/prometheus/prometheus.yml

# Reload Prometheus
curl -X POST http://10.0.5.10:9090/-/reload
```

#### Grafana No Data
```
No data points
```
**Solution**:
```bash
# Check datasource
# Grafana UI → Configuration → Data Sources → Test

# Check Prometheus query
# Grafana Explore → run query manually

# Check dashboard JSON valid
cat monitoring/grafana/dashboards/<dashboard>.json | jq .
```

---

### 8. Network Issues

#### Cannot Reach VM from Bastion
```
ssh: connect to host 10.0.3.10 port 22: Connection timed out
```
**Solution**:
```bash
# Check SG allows SSH from bastion SG
aws ec2 describe-security-groups --group-ids sg-xxx

# Check routing
# Private subnets need NAT gateway for outbound, but inbound from bastion via SG

# Check NACLs (if used)
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=vpc-xxx"
```

#### Inter-VM Communication Fails
```
Connection refused / timeout
```
**Solution**:
```bash
# Check both SGs allow traffic
# Source SG in destination SG ingress rules

# Check application listening on correct interface
ss -tlnp | grep <port>

# Check iptables/firewalld/ufw
ufw status
iptables -L -n
```

---

## Log Locations Quick Reference

| Component | Log Location |
|-----------|--------------|
| Terraform | Console output, `terraform show` |
| Ansible | `ansible-playbook -v` output |
| Kubelet | `journalctl -u kubelet` |
| Containerd | `journalctl -u containerd` |
| API Server | `/var/log/kubernetes/kube-apiserver.log` (on CP) |
| Controller Manager | `/var/log/kubernetes/kube-controller-manager.log` |
| Scheduler | `/var/log/kubernetes/kube-scheduler.log` |
| Etcd | `journalctl -u etcd` (static pod) |
| Calico | `kubectl -n calico-system logs -l k8s-app=calico-node` |
| Ingress NGINX | `kubectl -n ingress-nginx logs -l app.kubernetes.io/component=controller` |
| PostgreSQL | `/var/log/postgresql/postgresql-15-main.log` |
| HAProxy | `journalctl -u haproxy`, `/var/log/haproxy.log` |
| Keepalived | `journalctl -u keepalived` |
| NGINX | `/var/log/nginx/access.log`, `/var/log/nginx/error.log` |
| Jenkins | `/var/log/jenkins/jenkins.log` |
| Prometheus | `journalctl -u prometheus` |
| Grafana | `/var/log/grafana/grafana.log` |
| Node Exporter | `journalctl -u node_exporter` |
| Postgres Exporter | `journalctl -u postgres_exporter` |

---

## Emergency Contacts

| Issue Type | Primary | Secondary |
|------------|---------|-----------|
| Infrastructure (Terraform/AWS) | Platform Team | DevOps Lead |
| Kubernetes | Platform Team | SRE Team |
| Database (PostgreSQL) | DBA Team | Platform Team |
| CI/CD (Jenkins) | DevOps Team | Platform Team |
| Monitoring | SRE Team | Platform Team |
| Security | Security Team | Platform Lead |

---

## Escalation Procedure

1. **Level 1** - On-call engineer investigates (15 min)
2. **Level 2** - Team lead engaged (30 min)
3. **Level 3** - Manager + cross-team (1 hour)
4. **Level 4** - Executive notification (2 hours)

Document all actions in incident tracker.