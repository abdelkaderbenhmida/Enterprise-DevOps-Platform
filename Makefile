TERRAFORM_DIR=terraform/environments/dev
PROD_TERRAFORM_DIR=terraform/environments/prod
ANSIBLE_DIR=ansible
TERRAFORM_VERSION=1.9.0

TFSTATE_RG=enterprise-devops-tfstate
TFSTATE_SA=enterprisedevopstfstate

.PHONY: all init validate fmt plan apply destroy ansible-run bootstrap clean docs validate-prod plan-prod apply-prod tfstate-key help

all: init validate fmt plan

tfstate-key:
	@az storage account keys list --account-name $(TFSTATE_SA) --resource-group $(TFSTATE_RG) --query "[0].value" -o tsv

init:
	cd $(TERRAFORM_DIR) && ARM_ACCESS_KEY=$(shell $(MAKE) -s tfstate-key) terraform init

validate:
	cd $(TERRAFORM_DIR) && terraform validate

fmt:
	cd $(TERRAFORM_DIR) && terraform fmt -check -recursive ../../..

plan:
	cd $(TERRAFORM_DIR) && terraform plan -var-file=terraform.tfvars

apply:
	cd $(TERRAFORM_DIR) && terraform apply -auto-approve -var-file=terraform.tfvars

destroy:
	cd $(TERRAFORM_DIR) && terraform destroy -auto-approve -var-file=terraform.tfvars

validate-prod:
	cd $(PROD_TERRAFORM_DIR) && terraform validate

plan-prod:
	cd $(PROD_TERRAFORM_DIR) && terraform plan -var-file=terraform.tfvars

apply-prod:
	cd $(PROD_TERRAFORM_DIR) && terraform apply -auto-approve -var-file=terraform.tfvars

ansible-run:
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory/hosts.ini site.yml

ansible-check:
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory/hosts.ini site.yml --check

bootstrap:
	./scripts/bootstrap.sh

clean:
	rm -rf .terraform
	rm -f .terraform.lock.hcl
	rm -rf terraform/environments/dev/.terraform
	rm -f terraform/environments/dev/.terraform.lock.hcl

docs:
	@echo "Documentation in docs/*.md"

help:
	@echo "Available targets:"
	@echo "  init          - Initialize Terraform"
	@echo "  validate      - Validate Terraform configuration"
	@echo "  fmt           - Check Terraform formatting"
	@echo "  plan          - Show Terraform plan"
	@echo "  apply         - Apply Terraform configuration"
	@echo "  destroy       - Destroy Terraform resources"
	@echo "  validate-prod - Validate prod Terraform configuration"
	@echo "  plan-prod     - Show prod Terraform plan"
	@echo "  apply-prod    - Apply prod Terraform configuration"
	@echo "  ansible-run   - Run Ansible playbook"
	@echo "  ansible-check - Dry-run Ansible playbook"
	@echo "  bootstrap     - Run full bootstrap script"
	@echo "  clean         - Clean Terraform state files"
	@echo "  docs          - Show docs location"