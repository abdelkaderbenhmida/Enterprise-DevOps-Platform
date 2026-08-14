terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

variable "vm_map" {
  description = "Map of VMs with role, subnet, ip, size, sg, tags"
  type = map(object({
    role   = string
    subnet = string
    ip     = string
    size   = string
    sg     = string
    tags   = map(string)
  }))
}

variable "ssh_public_key" {
  description = "SSH public key (contents) used to log into the VMs"
  type        = string
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Name of the resource group to place resources in"
  type        = string
}

variable "location" {
  description = "Azure region (e.g. westeurope)"
  type        = string
}

variable "subnet_ids" {
  description = "Map of subnet names to IDs"
  type        = map(string)
}

variable "sg_ids" {
  description = "Map of NSG names to IDs"
  type        = map(string)
}

locals {
  admin_user = "ubuntu"
}

data "azurerm_platform_image" "ubuntu" {
  location  = var.location
  publisher = "Canonical"
  offer     = "0001-com-ubuntu-server-jammy"
  sku       = "22_04-lts-gen2"
  version   = "latest"
}

resource "azurerm_network_interface" "nic" {
  for_each            = var.vm_map
  name                = format("%s-nic", each.key)
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_ids[each.value.subnet]
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
    public_ip_address_id          = try(azurerm_public_ip.pip[each.key].id, null)
  }
}

resource "azurerm_public_ip" "pip" {
  for_each            = { for k, v in var.vm_map : k => v if v.subnet == "public" }
  name                = format("%s-pip", each.key)
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = merge(var.tags, each.value.tags)
}

resource "azurerm_network_interface_security_group_association" "nsg" {
  for_each                  = var.vm_map
  network_interface_id      = azurerm_network_interface.nic[each.key].id
  network_security_group_id = var.sg_ids[each.value.sg]
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each                        = var.vm_map
  name                            = each.key
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = each.value.size
  admin_username                  = local.admin_user
  network_interface_ids           = [azurerm_network_interface.nic[each.key].id]
  disable_password_authentication = true
  tags                            = merge(var.tags, each.value.tags, { Name = each.key })

  admin_ssh_key {
    username   = local.admin_user
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = data.azurerm_platform_image.ubuntu.publisher
    offer     = data.azurerm_platform_image.ubuntu.offer
    sku       = data.azurerm_platform_image.ubuntu.sku
    version   = data.azurerm_platform_image.ubuntu.version
  }

  custom_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y python3 python3-pip
              EOF
  )
}

output "instance_ips" {
  value = {
    for k, v in azurerm_linux_virtual_machine.vm : k => {
      private_ip = v.private_ip_address
      public_ip  = v.public_ip_address
      id         = v.id
    }
  }
}

output "instance_ids" {
  value = {
    for k, v in azurerm_linux_virtual_machine.vm : k => v.id
  }
}
