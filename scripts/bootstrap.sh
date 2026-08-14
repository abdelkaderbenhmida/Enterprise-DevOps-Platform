#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TERRAFORM_DIR="$PROJECT_ROOT/terraform/environments/dev"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"
INVENTORY_FILE="$ANSIBLE_DIR/inventory/hosts.ini"

TFSTATE_RG="enterprise-devops-tfstate"
TFSTATE_SA="enterprisedevopstfstate"
TFSTATE_CONTAINER="terraform-state"
LOCATION="${AZURE_LOCATION:-westeurope}"

echo "=== Enterprise DevOps Platform Bootstrap (Azure) ==="
echo "Project root: $PROJECT_ROOT"
echo ""

echo "Step 0: Ensure Azure Terraform state backend exists"
echo "-----------------------------------------------------"
if ! az account show >/dev/null 2>&1; then
    echo "ERROR: Not logged into Azure. Run 'az login' first."
    exit 1
fi

az group create --name "$TFSTATE_RG" --location "$LOCATION" --output none
if ! az storage account show --name "$TFSTATE_SA" --resource-group "$TFSTATE_RG" --output none >/dev/null 2>&1; then
    az storage account create \
        --name "$TFSTATE_SA" \
        --resource-group "$TFSTATE_RG" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --encryption-services blob \
        --min-tls-version TLS1_2 \
        --output none
fi

SA_KEY=$(az storage account keys list --account-name "$TFSTATE_SA" --resource-group "$TFSTATE_RG" --query "[0].value" -o tsv)
az storage container create \
    --name "$TFSTATE_CONTAINER" \
    --account-name "$TFSTATE_SA" \
    --account-key "$SA_KEY" \
    --output none

echo "Step 1: Provision infrastructure with Terraform"
echo "------------------------------------------------"
cd "$TERRAFORM_DIR"

if [[ ! -f "terraform.tfvars" ]]; then
    echo "ERROR: terraform.tfvars not found. Copy terraform.tfvars.example and fill in values."
    exit 1
fi

echo "Initializing Terraform..."
ARM_ACCESS_KEY="$SA_KEY" terraform init

echo "Applying Terraform configuration..."
ARM_ACCESS_KEY="$SA_KEY" terraform apply -auto-approve -var-file=terraform.tfvars

echo ""
echo "Step 2: Generate dynamic Ansible inventory"
echo "-------------------------------------------"
cd "$PROJECT_ROOT"
python3 scripts/generate-inventory.py > "$INVENTORY_FILE"

if [[ ! -s "$INVENTORY_FILE" ]]; then
    echo "ERROR: Generated inventory is empty"
    exit 1
fi

echo "Inventory generated at $INVENTORY_FILE"
echo ""

echo "Step 3: Configure with Ansible"
echo "-------------------------------"
cd "$ANSIBLE_DIR"

echo "Running site.yml playbook..."
ansible-playbook -i inventory/hosts.ini site.yml

echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "Next steps:"
echo "  - Verify HA control plane: ssh -J bastion ubuntu@10.0.3.10 'kubectl get nodes -o wide'"
echo "  - Verify PostgreSQL replication: ssh -J bastion ubuntu@10.0.4.11 'sudo -u postgres psql -c \"select * from pg_stat_wal_receiver;\"'"
echo "  - Access applications via NGINX LB: curl http://10.0.1.20/app1/"
echo "  - Access Grafana: http://10.0.5.11:3000 (admin/admin)"
echo "  - Access Prometheus: http://10.0.5.10:9090"
echo "  - Access Jenkins: http://10.0.2.20:8080"