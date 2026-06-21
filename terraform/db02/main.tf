# DB02 Container - Terraform Configuration
# MySQL/MariaDB Standby (HA Cluster Replica with Master-Slave Replication)

terraform {
  required_version = ">= 1.5"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }
}

module "db02" {
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

output "db02_vmid" {
  description = "DB02 container ID"
  value       = module.db02.vmid
}

output "db02_ip" {
  description = "DB02 IP address (standby/replica)"
  value       = module.db02.ip_address
}

output "db02_hostname" {
  description = "DB02 hostname"
  value       = module.db02.hostname
}
