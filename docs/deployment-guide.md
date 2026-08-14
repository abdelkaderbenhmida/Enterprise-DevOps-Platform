# Deployment Guide

## Prerequisites

### Local Workstation
- Terraform >= 1.0
- Ansible >= 2.15
- Python 3.9+
- Azure CLI v2 (`az login`)
- SSH key pair (public key contents go in `terraform.tfvars`)
- Git

### Azure Subscription
- Permission to create resource groups / 25 VMs (regional vCPU quota)
- Standard-tier public IPs and a NAT gateway (Standard SKU)
- Storage account for Terraform state (created automatically by bootstrap)

### Terraform State Backend Setup
The Azure backend (storage account + container) is created automatically by
`./scripts/bootstrap.sh` in resource group `enterprise-devops-tfstate`
(storage account `enterprisedevopstfstate`, container `terraform-state`).
To create it manually:

```bash
az group create --name enterprise-devops-tfstate --location westeurope
az storage account create --name enterprisedevopstfstate \
  --resource-group enterprise-devops-tfstate \
  --location westeurope --sku Standard_LRS --min-tls-version TLS1_2
az storage container create --name terraform-state \
  --account-name enterprisedevopstfstate \
  --account-key $(az storage account keys list --account-name enterprisedevopstfstate \
    --resource-group enterprise-devops-tfstate --query "[0].value" -o tsv)
```

Terraform authenticates to the backend via `ARM_ACCESS_KEY` (bootstrap exports it).

## Quick Start

### 1. Clone and Configure
```bash
git clone <repo-url>
cd enterprise-devops-platform

# Configure Terraform variables
cp terraform/environments/dev/terraform.tfvars.example terraform/environments/dev/terraform.tfvars
# Edit terraform.tfvars: paste your public SSH key contents into ssh_public_key

# Configure Ansible vault for secrets
ansible-vault create ansible/inventory/group_vars/vault.yml
# Add secrets (see vault.yml.example)
```

### 2. Deploy Infrastructure
```bash
# Option A: Full bootstrap (automated)
./scripts/bootstrap.sh

# Option B: Step by step
cd terraform/environments/dev
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -auto-approve -var-file=terraform.tfvars

# Generate inventory
cd ../../../scripts
python3 generate-inventory.py > ../ansible/inventory/hosts.ini

# Run Ansible
cd ../ansible
ansible-playbook -i inventory/hosts.ini site.yml
```

### 3. Verify Deployment
```bash
# Check K8s cluster
ssh -J ubuntu@10.0.1.10 ubuntu@10.0.3.10 "kubectl get nodes -o wide"

# Check K8s API via HAProxy VIP
curl -k https://10.0.1.100:6443/healthz

# Check PostgreSQL replication
ssh -J ubuntu@10.0.1.10 ubuntu@10.0.4.11 "sudo -u postgres psql -c 'SELECT * FROM pg_stat_wal_receiver;'"

# Check monitoring
curl http://10.0.5.10:9090/-/healthy
curl http://10.0.5.11:3000/api/health
```

### 4. Deploy Applications (First Time)
```bash
# From bastion or any control plane
kubectl apply -f kubernetes/namespaces.yml
kubectl apply -f kubernetes/app1-taskmanager/
kubectl apply -f kubernetes/app2-nodemongo/
kubectl apply -f kubernetes/app3-static-site/

# Verify
kubectl get pods -A
kubectl get ingress -A
```

### 5. Access Applications
```bash
# Via NGINX LB (VM21)
curl http://10.0.1.20/app1/
curl http://10.0.1.20/app2/
curl http://10.0.1.20/app3/

# Grafana
open http://10.0.5.11:3000  # admin / <vault password>

# Prometheus
open http://10.0.5.10:9090

# Jenkins
open http://10.0.2.20:8080  # admin / <vault password>
```

## Adding a 4th Application

### 1. Create Kubernetes Manifests
```bash
mkdir -p kubernetes/app4-newapp/
# Create deployment.yml, service.yml, ingress.yml, configmap.yml, secret.yml
```

### 2. Add to Deploy Role
```bash
# Edit ansible/roles/deploy-apps/tasks/main.yml
# Add new k8s task for app4
```

### 3. Create Jenkins Pipeline
```bash
# Copy and modify Jenkinsfile
cp jenkins/Jenkinsfile.app1 jenkins/Jenkinsfile.app4
# Update app name, image, namespace
```

### 4. Add to Shared Library (if needed)
```bash
# Add any app-specific build/deploy steps to jenkins/shared-library/vars/
```

### 5. Deploy
```bash
ansible-playbook -i inventory/hosts.ini site.yml --tags deploy-apps
# Or trigger via Jenkins
```

## Scaling Operations

### Add Kubernetes Worker Nodes
```bash
# 1. Update vm_map in terraform/variables/vm-map.tf
# Add vm17-k8s-wk7, vm18-k8s-wk8, etc.

# 2. Apply Terraform
cd terraform/environments/dev
terraform apply -var-file=terraform.tfvars

# 3. Regenerate inventory
cd ../../../scripts
python3 generate-inventory.py > ../ansible/inventory/hosts.ini

# 4. Run only worker role
cd ../ansible
ansible-playbook -i inventory/hosts.ini site.yml --limit k8s_workers
```

### Add Kubernetes Control Plane
```bash
# 1. Update vm_map with new control plane VM
# 2. Apply Terraform
# 3. Regenerate inventory
# 4. Run only control-plane-join role
ansible-playbook -i inventory/hosts.ini site.yml --limit k8s_control_plane[3:]
```

### Scale Application Replicas
```bash
# Via kubectl
kubectl scale deployment app1-backend -n app1 --replicas=4

# Or update manifest and re-apply
# Edit kubernetes/app1-taskmanager/backend-deployment.yml
kubectl apply -f kubernetes/app1-taskmanager/
```

## Maintenance Windows

### OS Updates (Monthly)
```bash
# Via Ansible
ansible all -i inventory/hosts.ini -b -m apt -a "upgrade=yes update_cache=yes"
ansible all -i inventory/hosts.ini -b -a "needs-restarting -r || reboot"
```

### Kubernetes Version Upgrade
```bash
# 1. Update k8s_version in ansible/roles/k8s-common/defaults/main.yml
# 2. Drain and upgrade control planes one at a time
kubectl drain k8s-cp1 --ignore-daemonsets --delete-emptydir-data
# On k8s-cp1:
sudo apt update && sudo apt install -y kubeadm=1.30.0-* kubelet=1.30.0-* kubectl=1.30.0-*
sudo kubeadm upgrade apply v1.30.0
sudo systemctl restart kubelet
kubectl uncordon k8s-cp1
# Repeat for CP2, CP3
# 3. Upgrade workers
kubectl drain k8s-wk1 --ignore-daemonsets --delete-emptydir-data
# On worker:
sudo apt update && sudo apt install -y kubeadm=1.30.0-* kubelet=1.30.0-* kubectl=1.30.0-*
sudo kubeadm upgrade node
sudo systemctl restart kubelet
kubectl uncordon k8s-wk1
# Repeat for all workers
```

### PostgreSQL Maintenance
```bash
# Vacuum/Analyze (weekly)
ssh -J bastion ubuntu@10.0.4.10 "sudo -u postgres psql -c 'VACUUM ANALYZE;'"

# Check replication lag
ssh -J bastion ubuntu@10.0.4.11 "sudo -u postgres psql -c 'SELECT * FROM pg_stat_wal_receiver;'"

# Base backup (monthly)
ssh -J bastion ubuntu@10.0.4.10 "pg_basebackup -D /backup/pg_$(date +%F) -Ft -z -P"
```

## Troubleshooting Common Issues

### Terraform Apply Fails
```bash
# Check state
terraform state list
# Refresh
terraform refresh
# Target specific resource
terraform apply -target=aws_instance.vm["vm08-k8s-cp1"]
```

### Ansible Playbook Fails
```bash
# Run with verbose
ansible-playbook -i inventory/hosts.ini site.yml -vvv
# Run single role
ansible-playbook -i inventory/hosts.ini site.yml --tags common
# Check connectivity
ansible all -i inventory/hosts.ini -m ping
```

### K8s Control Plane Won't Initialize
```bash
# Check containerd
systemctl status containerd
# Check kubeadm logs
journalctl -u kubelet -f
# Reset and retry
kubeadm reset -f
rm -rf /etc/kubernetes /var/lib/etcd
```

### PostgreSQL Replication Broken
```bash
# Check replica status
sudo -u postgres psql -c "SELECT * FROM pg_stat_wal_receiver;"
# Check primary
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"
# Rebuild replica if needed
systemctl stop postgresql
rm -rf /var/lib/postgresql/15/main/*
pg_basebackup -h <primary> -D /var/lib/postgresql/15/main -U replicator -v -P -W
touch /var/lib/postgresql/15/main/standby.signal
systemctl start postgresql
```

### HAProxy VIP Not Failing Over
```bash
# Check keepalived status
systemctl status keepalived
# Check VRRP advertisements
tcpdump -i eth0 vrrp
# Check VIP
ip addr show dev eth0 | grep 10.0.1.100
# Check haproxy
systemctl status haproxy
```

## Rollback Procedures

### Terraform Rollback
```bash
# Destroy and re-apply (careful!)
terraform destroy -target=aws_instance.vm["vm08-k8s-cp1"]
terraform apply -target=aws_instance.vm["vm08-k8s-cp1"]
```

### Ansible Rollback
```bash
# Re-run playbook (idempotent)
ansible-playbook -i inventory/hosts.ini site.yml

# Or restore from backup
# (No automatic rollback - fix forward)
```

### Kubernetes Rollback
```bash
# Rollback deployment
kubectl rollout undo deployment/app1-backend -n app1
# Check history
kubectl rollout history deployment/app1-backend -n app1
```

### PostgreSQL Failback
```bash
# After promoting replica, to make old primary a replica again:
# On old primary (VM17):
systemctl stop postgresql
rm -rf /var/lib/postgresql/15/main/*
pg_basebackup -h <new-primary> -D /var/lib/postgresql/15/main -U replicator -v -P -W
touch /var/lib/postgresql/15/main/standby.signal
# Configure primary_conninfo
systemctl start postgresql
```

## Environment Promotion (Dev → Prod)

### 1. Create Prod Environment
```bash
mkdir -p terraform/environments/prod
# Copy dev files, adjust:
# - Larger instance sizes
# - More worker nodes
# - Different CIDRs (e.g., 10.1.0.0/16)
# - Different backend key
```

### 2. Update Variables
```bash
# terraform/environments/prod/terraform.tfvars
# - instance sizes: t3.xlarge → t3.2xlarge for CPs
# - worker count: 6 → 12
# - enable deletion protection
```

### 3. Deploy Prod
```bash
cd terraform/environments/prod
terraform init
terraform apply -var-file=terraform.tfvars

# Separate Ansible inventory for prod
python3 scripts/generate-inventory.py --env prod > ansible/inventory/hosts-prod.ini
ansible-playbook -i inventory/hosts-prod.ini site.yml
```

## Cost Optimization

### Development (Current)
- CP: t3.xlarge × 3 = ~$0.50/hr
- Workers: t3.large × 6 = ~$0.50/hr
- Others: ~$0.30/hr
- **Total: ~$1.30/hr (~$950/mo)**

### Production Recommendations
- Use Savings Plans / Reserved Instances
- Spot instances for workers (with interruption handling)
- Right-size based on actual utilization
- Consider EKS managed node groups

### Cleanup
```bash
# Destroy everything
cd terraform/environments/dev
terraform destroy -auto-approve -var-file=terraform.tfvars
```