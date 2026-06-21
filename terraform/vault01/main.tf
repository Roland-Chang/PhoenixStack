# VAULT01 Container - Terraform Configuration (Framework)
# HashiCorp Vault - Secrets Management Primary (Raft cluster member)
#
# NOTE: This is a framework deployment only.
# Post-deployment configuration required:
# 1. Initialize Vault using Raft backend
# 2. Configure auto-unseal with transit engine
# 3. Set up replication to VAULT02
# 4. Configure auth methods (OIDC, Kubernetes, AppRole)

terraform {
  required_version = ">= 1.5"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }
}

module "vault01" {
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

output "vault01_vmid" {
  description = "VAULT01 container ID"
  value       = module.vault01.vmid
}

output "vault01_ip" {
  description = "VAULT01 IP address"
  value       = module.vault01.ip_address
}

output "vault01_hostname" {
  description = "VAULT01 hostname"
  value       = module.vault01.hostname
}
