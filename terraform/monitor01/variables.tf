# MONITOR01 - Terraform Variables
# Prometheus metrics collection (Active)

variable "proxmox_node" {
  description = "Proxmox node for MONITOR01 deployment"
  type        = string
  default     = "pve01"
}

variable "container_vmid" {
  description = "Unique VM ID for MONITOR01 (must be unique on Proxmox)"
  type        = number
  default     = 114 # Fixed VMID for MONITOR01
}

variable "hostname" {
  description = "Container hostname"
  type        = string
  default     = "monitor01"
}

variable "cpu_cores" {
  description = "CPU cores for MONITOR01"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM for MONITOR01 in MB"
  type        = number
  default     = 1536 # 1.5GB for Prometheus with 13+ services
}

variable "swap_mb" {
  description = "Swap memory for MONITOR01 in MB"
  type        = number
  default     = 512
}

variable "storage_pool" {
  description = "Proxmox storage pool for container"
  type        = string
  default     = "ssd" # SSD pool for time-series database performance
}

variable "storage_size" {
  description = "Root disk size for MONITOR01 in GB"
  type        = number
  default     = 20 # Prometheus/Grafana storage
}

variable "ostemplate" {
  description = "Container OS template ID"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "ip_address" {
  description = "IPv4 address for MONITOR01 (VLAN 10 Management)"
  type        = string
  default     = "10.101.0.101" # Fixed IP for MONITOR01
}

variable "ip_cidr_suffix" {
  description = "CIDR suffix for MONITOR01"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Default gateway for MONITOR01"
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
  description = "SSH public key(s) for root access to MONITOR01"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mac_address" {
  description = "MAC address for MONITOR01 (PhoenixStack scheme: 02:aa:bb:cc:09:01)"
  type        = string
  default     = ""
}
