# SQL01 Container - Terraform Configuration
# PostgreSQL Primary (HA Cluster Master)

terraform {
  required_version = ">= 1.5"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }
}

module "sql01" {
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

output "sql01_vmid" {
  description = "SQL01 container ID"
  value       = module.sql01.vmid
}

output "sql01_ip" {
  description = "SQL01 IP address (primary)"
  value       = module.sql01.ip_address
}

output "sql01_hostname" {
  description = "SQL01 hostname"
  value       = module.sql01.hostname
}
