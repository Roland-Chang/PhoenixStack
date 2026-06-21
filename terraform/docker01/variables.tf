# DOCKER01 - Terraform Variables

variable "proxmox_node" {
  description = "Proxmox node for DOCKER01 deployment"
  type        = string
  default     = "pve01"
}

variable "container_vmid" {
  description = "Unique VM ID for DOCKER01"
  type        = number
  default     = 109
}

variable "hostname" {
  description = "Container hostname"
  type        = string
  default     = "docker01"
}

variable "cpu_cores" {
  description = "CPU cores for DOCKER01"
  type        = number
  default     = 4
}

variable "memory_mb" {
  description = "RAM for DOCKER01 in MB"
  type        = number
  default     = 8192 # 8GB
}

variable "swap_mb" {
  description = "Swap memory for DOCKER01 in MB"
  type        = number
  default     = 2048
}

variable "storage_pool" {
  description = "Proxmox storage pool for container"
  type        = string
  default     = "ssd"
}

variable "storage_size" {
  description = "Root disk size for DOCKER01 in GB"
  type        = number
  default     = 64 # Docker container images/data
}

variable "ostemplate" {
  description = "Container OS template ID"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "ip_address" {
  description = "IPv4 address for DOCKER01 (VLAN 10 Management)"
  type        = string
  default     = "10.101.0.51"
}

variable "ip_cidr_suffix" {
  description = "CIDR suffix for DOCKER01"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Default gateway for DOCKER01"
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
  description = "SSH public key(s) for root access to DOCKER01"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mac_address" {
  description = "MAC address for container (PhoenixStack scheme: 02:aa:bb:cc:05:01)"
  type        = string
  default     = ""
}
