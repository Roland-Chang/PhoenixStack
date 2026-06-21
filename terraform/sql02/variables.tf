# SQL02 - Terraform Variables
# PostgreSQL Standby (HA Cluster Replica with Streaming Replication)

variable "proxmox_node" {
  description = "Proxmox node for SQL02 deployment"
  type        = string
  default     = "pve01"
}

variable "container_vmid" {
  description = "Unique VM ID for SQL02 (must be unique on Proxmox)"
  type        = number
  default     = 113 # Fixed VMID for SQL02
}

variable "hostname" {
  description = "Container hostname"
  type        = string
  default     = "sql02"
}

variable "cpu_cores" {
  description = "CPU cores for SQL02"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM for SQL02 in MB"
  type        = number
  default     = 2048 # 2GB for PostgreSQL
}

variable "swap_mb" {
  description = "Swap memory for SQL02 in MB"
  type        = number
  default     = 512
}

variable "storage_pool" {
  description = "Proxmox storage pool for container"
  type        = string
  default     = "ssd" # SSD pool for database performance
}

variable "storage_size" {
  description = "Root disk size for SQL02 in GB"
  type        = number
  default     = 32 # PostgreSQL data storage
}

variable "ostemplate" {
  description = "Container OS template ID"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "ip_address" {
  description = "IPv4 address for SQL02 (VLAN 10 Management)"
  type        = string
  default     = "10.101.0.72" # Fixed IP for SQL02 (standby/replica)
}

variable "ip_cidr_suffix" {
  description = "CIDR suffix for SQL02"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Default gateway for SQL02"
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
  description = "SSH public key(s) for root access to SQL02"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mac_address" {
  description = "MAC address for SQL02 (PhoenixStack scheme: 02:aa:bb:cc:07:02)"
  type        = string
  default     = ""
}
