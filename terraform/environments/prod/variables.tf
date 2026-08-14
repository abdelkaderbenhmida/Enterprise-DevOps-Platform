variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "westeurope"
}

variable "ssh_public_key" {
  description = "Contents of the public SSH key used to log into the VMs"
  type        = string
}
