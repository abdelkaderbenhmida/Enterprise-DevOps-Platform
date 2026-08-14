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

variable "vnet_cidr" {
  description = "CIDR block for the virtual network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for public subnet (bastion + LBs)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "mgmt_subnet_cidr" {
  description = "CIDR for mgmt/CI subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "k8s_subnet_cidr" {
  description = "CIDR for Kubernetes subnet"
  type        = string
  default     = "10.0.3.0/24"
}

variable "data_subnet_cidr" {
  description = "CIDR for data subnet (PostgreSQL)"
  type        = string
  default     = "10.0.4.0/24"
}

variable "monitoring_subnet_cidr" {
  description = "CIDR for monitoring subnet"
  type        = string
  default     = "10.0.5.0/24"
}

variable "apps_subnet_cidr" {
  description = "CIDR for standalone apps subnet"
  type        = string
  default     = "10.0.6.0/24"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

resource "azurerm_virtual_network" "main" {
  name                = "enterprise-devops-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "public" {
  name                 = "enterprise-devops-public"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.public_subnet_cidr]
}

resource "azurerm_subnet" "mgmt" {
  name                 = "enterprise-devops-mgmt"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.mgmt_subnet_cidr]
}

resource "azurerm_subnet" "k8s" {
  name                 = "enterprise-devops-k8s"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.k8s_subnet_cidr]
}

resource "azurerm_subnet" "data" {
  name                 = "enterprise-devops-data"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.data_subnet_cidr]
}

resource "azurerm_subnet" "monitoring" {
  name                 = "enterprise-devops-monitoring"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.monitoring_subnet_cidr]
}

resource "azurerm_subnet" "apps" {
  name                 = "enterprise-devops-apps"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.apps_subnet_cidr]
}

resource "azurerm_public_ip" "nat" {
  name                = "enterprise-devops-nat-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "main" {
  name                = "enterprise-devops-nat"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "mgmt" {
  subnet_id      = azurerm_subnet.mgmt.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_subnet_nat_gateway_association" "k8s" {
  subnet_id      = azurerm_subnet.k8s.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_subnet_nat_gateway_association" "data" {
  subnet_id      = azurerm_subnet.data.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_subnet_nat_gateway_association" "monitoring" {
  subnet_id      = azurerm_subnet.monitoring.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_subnet_nat_gateway_association" "apps" {
  subnet_id      = azurerm_subnet.apps.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "vnet_name" {
  value = azurerm_virtual_network.main.name
}

output "public_subnet_id" {
  value = azurerm_subnet.public.id
}

output "mgmt_subnet_id" {
  value = azurerm_subnet.mgmt.id
}

output "k8s_subnet_id" {
  value = azurerm_subnet.k8s.id
}

output "data_subnet_id" {
  value = azurerm_subnet.data.id
}

output "monitoring_subnet_id" {
  value = azurerm_subnet.monitoring.id
}

output "apps_subnet_id" {
  value = azurerm_subnet.apps.id
}

output "nat_gateway_id" {
  value = azurerm_nat_gateway.main.id
}
