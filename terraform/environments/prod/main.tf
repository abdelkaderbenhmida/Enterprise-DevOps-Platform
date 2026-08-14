terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "enterprise-devops-tfstate"
    storage_account_name = "enterprisedevopstfstate"
    container_name       = "terraform-state"
    key                  = "prod/terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "main" {
  name     = "enterprise-devops-prod"
  location = var.location
  tags = {
    Project     = "enterprise-devops-platform"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}

module "network" {
  source                 = "../../modules/network"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  vnet_cidr              = "10.0.0.0/16"
  public_subnet_cidr     = "10.0.1.0/24"
  mgmt_subnet_cidr       = "10.0.2.0/24"
  k8s_subnet_cidr        = "10.0.3.0/24"
  data_subnet_cidr       = "10.0.4.0/24"
  monitoring_subnet_cidr = "10.0.5.0/24"
  apps_subnet_cidr       = "10.0.6.0/24"
  tags = {
    Environment = "prod"
  }
}

module "security_groups" {
  source              = "../../modules/security-groups"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  admin_cidr          = "0.0.0.0/0"
  tags = {
    Environment = "prod"
  }
}

module "compute" {
  source              = "../../modules/compute"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  vm_map              = var.vm_map
  ssh_public_key      = var.ssh_public_key
  subnet_ids = {
    public     = module.network.public_subnet_id
    mgmt       = module.network.mgmt_subnet_id
    k8s        = module.network.k8s_subnet_id
    data       = module.network.data_subnet_id
    monitoring = module.network.monitoring_subnet_id
    apps       = module.network.apps_subnet_id
  }
  sg_ids = {
    bastion    = module.security_groups.sg_bastion_id
    lb         = module.security_groups.sg_lb_id
    mgmt       = module.security_groups.sg_mgmt_id
    k8s_cp     = module.security_groups.sg_k8s_cp_id
    k8s_worker = module.security_groups.sg_k8s_worker_id
    data       = module.security_groups.sg_data_id
    monitoring = module.security_groups.sg_monitoring_id
    apps       = module.security_groups.sg_apps_id
  }
  tags = {
    Environment = "prod"
  }
}

# Optional cloud-managed load balancers. The self-managed NGINX/HAProxy VMs
# (vm21/vm22) are the default path; uncomment to add Azure LBs in front.
# module "load_balancer" {
#   source              = "../../modules/load-balancer"
#   resource_group_name = azurerm_resource_group.main.name
#   location            = azurerm_resource_group.main.location
#   vnet_id             = module.network.vnet_id
#   control_plane_ips   = ["10.0.3.10", "10.0.3.11", "10.0.3.12"]
#   worker_node_ips     = ["10.0.3.20", "10.0.3.21", "10.0.3.22"]
#   api_server_port     = 6443
#   http_port           = 80
#   tags = {
#     Environment = "prod"
#   }
# }

output "vm_ips" {
  value = module.compute.instance_ips
}

output "vnet_id" {
  value = module.network.vnet_id
}

output "subnet_ids" {
  value = {
    public     = module.network.public_subnet_id
    mgmt       = module.network.mgmt_subnet_id
    k8s        = module.network.k8s_subnet_id
    data       = module.network.data_subnet_id
    monitoring = module.network.monitoring_subnet_id
    apps       = module.network.apps_subnet_id
  }
}

output "sg_ids" {
  value = {
    bastion    = module.security_groups.sg_bastion_id
    lb         = module.security_groups.sg_lb_id
    mgmt       = module.security_groups.sg_mgmt_id
    k8s_cp     = module.security_groups.sg_k8s_cp_id
    k8s_worker = module.security_groups.sg_k8s_worker_id
    data       = module.security_groups.sg_data_id
    monitoring = module.security_groups.sg_monitoring_id
    apps       = module.security_groups.sg_apps_id
  }
}
