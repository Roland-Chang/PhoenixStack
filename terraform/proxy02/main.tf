# PROXY02 Container - Terraform Configuration
# Deploys the secondary reverse proxy (Traefik) on PVE01 for redundancy

terraform {
  required_version = ">= 1.5"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }
}

module "proxy02" {
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

output "proxy02_vmid" {
  description = "PROXY02 container ID"
  value       = module.proxy02.vmid
}

output "proxy02_ip" {
  description = "PROXY02 IP address"
  value       = module.proxy02.ip_address
}

output "proxy02_hostname" {
  description = "PROXY02 hostname"
  value       = module.proxy02.hostname
}
