# DB02 - Terraform Variables
# MySQL/MariaDB Standby (HA Cluster Replica with Master-Slave Replication)

variable "proxmox_node" {
  description = "Proxmox node for DB02 deployment"
  type        = string
  default     = "pve01"
}

variable "container_vmid" {
  description = "Unique VM ID for DB02 (must be unique on Proxmox)"
  type        = number
  default     = 117 # Fixed VMID for DB02
}

variable "hostname" {
  description = "Container hostname"
  type        = string
  default     = "db02"
}

variable "cpu_cores" {
  description = "CPU cores for DB02"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM for DB02 in MB"
  type        = number
  default     = 2048 # 2GB for MariaDB
}

variable "swap_mb" {
  description = "Swap memory for DB02 in MB"
  type        = number
  default     = 512
}

variable "storage_pool" {
  description = "Proxmox storage pool for container"
  type        = string
  default     = "ssd" # SSD pool for database performance
}

variable "storage_size" {
  description = "Root disk size for DB02 in GB"
  type        = number
  default     = 32 # MariaDB data storage
}

variable "ostemplate" {
  description = "Container OS template ID"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "ip_address" {
  description = "IPv4 address for DB02 (VLAN 10 Management)"
  type        = string
  default     = "10.101.0.74" # Fixed IP for DB02 (standby/replica)
}

variable "ip_cidr_suffix" {
  description = "CIDR suffix for DB02"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Default gateway for DB02"
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
  description = "SSH public key(s) for root access to DB02"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mac_address" {
  description = "MAC address for DB02 (PhoenixStack scheme: 02:aa:bb:cc:07:04)"
  type        = string
  default     = ""
}
