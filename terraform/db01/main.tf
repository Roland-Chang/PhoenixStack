# DB01 Container - Terraform Configuration
# MySQL/MariaDB Primary (HA Cluster Master)

terraform {
  required_version = ">= 1.5"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }
}

module "db01" {
  source = "../modules/lxc"

  proxmox_node = var.proxmox_node
  vmid         = var.container_vmid
  hostname     = var.hostname
  ostemplate   = var.ostemplate

  cpu_cores    = var.cpu_cores
  memory_mb    = var.memory_mb
  swap_mb      = var.swap_mb
  storage_pool = var.storage_pool
  storage_size = var.storage_size

  ip_address     = var.ip_address
  ip_cidr_suffix = var.ip_cidr_suffix
  gateway        = var.gateway
  network_bridge = var.network_bridge
  nameserver     = var.nameserver
  search_domain  = var.search_domain

  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.mac_address

  enable_nesting = true
  unprivileged   = true
  autostart      = true
  onboot         = true
}

output "db01_vmid" {
  description = "DB01 container ID"
  value       = module.db01.vmid
}

output "db01_ip" {
  description = "DB01 IP address (primary)"
  value       = module.db01.ip_address
}

output "db01_hostname" {
  description = "DB01 hostname"
  value       = module.db01.hostname
}
