# VAULT02 Container - Terraform Configuration (Framework)
# HashiCorp Vault - Secrets Management Standby (Raft cluster member)
#
# NOTE: This is a framework deployment only.
# Post-deployment configuration required:
# 1. Join Vault02 to VAULT01's Raft cluster
# 2. Configure auto-unseal with transit engine
# 3. Set up performance/standby replication
# 4. Sync auth methods with VAULT01

terraform {
  required_version = ">= 1.5"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }
}

module "vault02" {
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

output "vault02_vmid" {
  description = "VAULT02 container ID"
  value       = module.vault02.vmid
}

output "vault02_ip" {
  description = "VAULT02 IP address"
  value       = module.vault02.ip_address
}

output "vault02_hostname" {
  description = "VAULT02 hostname"
  value       = module.vault02.hostname
}
