# AUTHENTIK01 - Terraform Variables

variable "proxmox_node" {
  description = "Proxmox node for AUTHENTIK01 deployment"
  type        = string
  default     = "pve01"
}

variable "container_vmid" {
  description = "Unique VM ID for AUTHENTIK01"
  type        = number
  default     = 107
}

variable "hostname" {
  description = "Container hostname"
  type        = string
  default     = "authentik01"
}

variable "cpu_cores" {
  description = "CPU cores for AUTHENTIK01"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM for AUTHENTIK01 in MB"
  type        = number
  default     = 4096 # 4GB
}

variable "swap_mb" {
  description = "Swap memory for AUTHENTIK01 in MB"
  type        = number
  default     = 1024
}

variable "storage_pool" {
  description = "Proxmox storage pool for container"
  type        = string
  default     = "ssd"
}

variable "storage_size" {
  description = "Root disk size for AUTHENTIK01 in GB"
  type        = number
  default     = 32 # Authentik stores auth data/logs
}

variable "ostemplate" {
  description = "Container OS template ID"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "ip_address" {
  description = "IPv4 address for AUTHENTIK01 (VLAN 10 Management)"
  type        = string
  default     = "10.101.0.41"
}

variable "ip_cidr_suffix" {
  description = "CIDR suffix for AUTHENTIK01"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Default gateway for AUTHENTIK01"
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
  description = "SSH public key(s) for root access to AUTHENTIK01"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mac_address" {
  description = "MAC address for container (PhoenixStack scheme: 02:aa:bb:cc:04:01)"
  type        = string
  default     = ""
}
