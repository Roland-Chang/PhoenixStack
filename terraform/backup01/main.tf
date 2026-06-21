# BACKUP01 Container - Terraform Configuration (Framework)
# Proxmox Backup Server client & orchestration container
#
# NOTE: This is a framework deployment only.
# Post-deployment configuration required:
# 1. Install Proxmox Backup client tools (proxmox-backup-client)
# 2. Configure SSH keys for Proxmox Backup Server authentication
# 3. Set up scheduled backup jobs via Proxmox API integration
# 4. Configure external storage targets (NFS, S3, or local mount)
# 5. Create backup policies for SQL01/02 and other critical containers
#
# Integration Points:
# - SQL01/02: Full container + database snapshots
# - MONITOR01/02: Grafana dashboards and configs
# - AUTHENTIK01/02: User data and configurations
# - Other services: Incremental snapshots

terraform {
  required_version = ">= 1.5"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }
}

module "backup01" {
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

output "backup01_vmid" {
  description = "BACKUP01 container ID"
  value       = module.backup01.vmid
}

output "backup01_ip" {
  description = "BACKUP01 IP address"
  value       = module.backup01.ip_address
}

output "backup01_hostname" {
  description = "BACKUP01 hostname"
  value       = module.backup01.hostname
}
