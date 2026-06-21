# PLEX01 - Terraform Variables

variable "proxmox_node" {
  description = "Proxmox node for PLEX01 deployment"
  type        = string
  default     = "pve01"
}

variable "container_vmid" {
  description = "Unique VM ID for PLEX01"
  type        = number
  default     = 111
}

variable "hostname" {
  description = "Container hostname"
  type        = string
  default     = "plex01"
}

variable "cpu_cores" {
  description = "CPU cores for PLEX01"
  type        = number
  default     = 4
}

variable "memory_mb" {
  description = "RAM for PLEX01 in MB"
  type        = number
  default     = 4096 # 4GB
}

variable "swap_mb" {
  description = "Swap memory for PLEX01 in MB"
  type        = number
  default     = 1024
}

variable "storage_pool" {
  description = "Proxmox storage pool for container"
  type        = string
  default     = "ssd"
}

variable "storage_size" {
  description = "Root disk size for PLEX01 in GB"
  type        = number
  default     = 32
}

variable "ostemplate" {
  description = "Container OS template ID"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "ip_address" {
  description = "IPv4 address for PLEX01 (VLAN 10 Management)"
  type        = string
  default     = "10.101.0.61"
}

variable "ip_cidr_suffix" {
  description = "CIDR suffix for PLEX01"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Default gateway for PLEX01"
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
  description = "SSH public key(s) for root access to PLEX01"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mac_address" {
  description = "MAC address for container (PhoenixStack scheme: 02:aa:bb:cc:06:01)"
  type        = string
  default     = ""
}
