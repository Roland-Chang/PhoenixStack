# Proxmox Provider Configuration
# This provider connects to your Proxmox VE cluster for infrastructure provisioning

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_user         = var.proxmox_user
  pm_password     = var.proxmox_password
  pm_tls_insecure = var.proxmox_tls_insecure
}

variable "proxmox_api_url" {
  description = "Proxmox API URL (e.g., https://10.101.0.11:8006/api2/json)"
  type        = string
}

variable "proxmox_user" {
  description = "Proxmox API user (format: user@realm, e.g., root@pam)"
  type        = string
  sensitive   = true
}

variable "proxmox_password" {
  description = "Proxmox API password or API token"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS certificate verification (set to false in production)"
  type        = bool
  default     = true # Set to false when using trusted certificates
}

variable "proxmox_node" {
  description = "Target Proxmox node for container deployment"
  type        = string
  default     = "pve01"
}
