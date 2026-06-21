# BACKUP01 - Terraform Variables
# Proxmox Backup Server client & orchestration container

variable "proxmox_node" {
  description = "Proxmox node for BACKUP01 deployment"
  type        = string
  default     = "pve01"
}

variable "container_vmid" {
  description = "Unique VM ID for BACKUP01 (must be unique on Proxmox)"
  type        = number
  default     = 120 # Fixed VMID for BACKUP01
}

variable "hostname" {
  description = "Container hostname"
  type        = string
  default     = "backup01"
}

variable "cpu_cores" {
  description = "CPU cores for BACKUP01"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM for BACKUP01 in MB"
  type        = number
  default     = 1024 # 1GB for backup orchestration
}

variable "swap_mb" {
  description = "Swap memory for BACKUP01 in MB"
  type        = number
  default     = 512
}

variable "storage_pool" {
  description = "Proxmox storage pool for container"
  type        = string
  default     = "ssd" # SSD pool for consistency
}

variable "storage_size" {
  description = "Root disk size for BACKUP01 in GB"
  type        = number
  default     = 16 # Minimal - actual backups stored on external/NFS
}

variable "ostemplate" {
  description = "Container OS template ID"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "ip_address" {
  description = "IPv4 address for BACKUP01 (VLAN 10 Management)"
  type        = string
  default     = "10.101.0.91" # Fixed IP for BACKUP01
}

variable "ip_cidr_suffix" {
  description = "CIDR suffix for BACKUP01"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Default gateway for BACKUP01"
  type        = string
  default     = "10.101.0.254"
}

variable "network_bridge" {
  description = "Proxmox network bridge (vmbr0 = VLAN 10 Management)"
  type        = string
  default     = "vmbr0"
}

variable "search_domain" {
  description = "DNS search domain"
  type        = string
  default     = "phoenix.stack"
}

variable "nameserver" {
  description = "DNS nameserver for container"
  type        = string
  default     = "10.101.0.1"
}

variable "ssh_public_keys" {
  description = "SSH public key(s) for root access to BACKUP01"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mac_address" {
  description = "MAC address for BACKUP01 (PhoenixStack scheme: 02:aa:bb:cc:08:01)"
  type        = string
  default     = ""
}
