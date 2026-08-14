terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to place resources in"
  type        = string
}

variable "location" {
  description = "Azure region (e.g. westeurope)"
  type        = string
}

variable "vnet_id" {
  description = "Virtual network ID for backend pool addresses"
  type        = string
}

variable "control_plane_ips" {
  description = "Private IPs of the Kubernetes control plane nodes"
  type        = list(string)
}

variable "worker_node_ips" {
  description = "Private IPs of the Kubernetes worker nodes (Ingress NodePort targets)"
  type        = list(string)
}

variable "api_server_port" {
  description = "Kubernetes API server port"
  type        = number
  default     = 6443
}

variable "http_port" {
  description = "HTTP port for application traffic"
  type        = number
  default     = 80
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

# Optional cloud-managed load balancers.
# This module is NOT wired into the environments by default: the repo's HA
# topology uses self-managed NGINX (VM21) + HAProxy (VM22) VMs with keepalived.
# Use this module only when a cloud-managed LB is preferred.

# Azure Load Balancer: TCP 6443 -> control planes (same role as self-managed HAProxy)
resource "azurerm_public_ip" "api" {
  name                = "k8s-api-lb-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = merge(var.tags, { Name = "k8s-api-lb" })
}

resource "azurerm_lb" "api" {
  name                = "k8s-api-lb"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  tags                = merge(var.tags, { Name = "k8s-api-lb" })

  frontend_ip_configuration {
    name                 = "PublicIP"
    public_ip_address_id = azurerm_public_ip.api.id
  }
}

resource "azurerm_lb_backend_address_pool" "api" {
  name            = "k8s-api-pool"
  loadbalancer_id = azurerm_lb.api.id
}

resource "azurerm_lb_backend_address_pool_address" "api_cp" {
  count                   = length(var.control_plane_ips)
  name                    = "cp-${count.index}"
  backend_address_pool_id = azurerm_lb_backend_address_pool.api.id
  virtual_network_id      = var.vnet_id
  ip_address              = var.control_plane_ips[count.index]
}

resource "azurerm_lb_probe" "api" {
  loadbalancer_id     = azurerm_lb.api.id
  name                = "api-health"
  protocol            = "Tcp"
  port                = var.api_server_port
  interval_in_seconds = 15
  number_of_probes    = 3
}

resource "azurerm_lb_rule" "api" {
  loadbalancer_id                = azurerm_lb.api.id
  name                           = "k8s-api-rule"
  protocol                       = "Tcp"
  frontend_port                  = var.api_server_port
  backend_port                   = var.api_server_port
  frontend_ip_configuration_name = "PublicIP"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.api.id]
  probe_id                       = azurerm_lb_probe.api.id
}

# Azure Load Balancer: HTTP 80 -> worker NodePorts (same role as self-managed NGINX)
resource "azurerm_public_ip" "app" {
  name                = "app-http-lb-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = merge(var.tags, { Name = "app-http-lb" })
}

resource "azurerm_lb" "app" {
  name                = "app-http-lb"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  tags                = merge(var.tags, { Name = "app-http-lb" })

  frontend_ip_configuration {
    name                 = "PublicIP"
    public_ip_address_id = azurerm_public_ip.app.id
  }
}

resource "azurerm_lb_backend_address_pool" "app" {
  name            = "app-http-pool"
  loadbalancer_id = azurerm_lb.app.id
}

resource "azurerm_lb_backend_address_pool_address" "app_worker" {
  count                   = length(var.worker_node_ips)
  name                    = "worker-${count.index}"
  backend_address_pool_id = azurerm_lb_backend_address_pool.app.id
  virtual_network_id      = var.vnet_id
  ip_address              = var.worker_node_ips[count.index]
}

resource "azurerm_lb_probe" "app" {
  loadbalancer_id     = azurerm_lb.app.id
  name                = "app-health"
  protocol            = "Http"
  request_path        = "/healthz"
  port                = var.http_port
  interval_in_seconds = 15
  number_of_probes    = 3
}

resource "azurerm_lb_rule" "app" {
  loadbalancer_id                = azurerm_lb.app.id
  name                           = "app-http-rule"
  protocol                       = "Tcp"
  frontend_port                  = var.http_port
  backend_port                   = var.http_port
  frontend_ip_configuration_name = "PublicIP"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.app.id]
  probe_id                       = azurerm_lb_probe.app.id
}

output "api_lb_ip" {
  value = azurerm_public_ip.api.ip_address
}

output "app_lb_ip" {
  value = azurerm_public_ip.app.ip_address
}
