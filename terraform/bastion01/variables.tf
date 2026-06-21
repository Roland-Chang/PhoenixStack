# BASTION01 - Terraform Variables

variable "proxmox_node" {
  description = "Proxmox node for BASTION01 deployment"
  type        = string
  default     = "pve01"
}

variable "container_vmid" {
  description = "Unique VM ID for BASTION01 (must be unique on Proxmox)"
  type        = number
  default     = 101 # Fixed VMID for BASTION01
}

variable "hostname" {
  description = "Container hostname"
  type        = string
  default     = "bastion01" # Fixed hostname for BASTION01
}

variable "cpu_cores" {
  description = "CPU cores for BASTION01"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM for BASTION01 in MB"
  type        = number
  default     = 4096 # 4GB for control plane
}

variable "swap_mb" {
  description = "Swap memory for BASTION01 in MB"
  type        = number
  default     = 1024 # 1GB
}

variable "storage_pool" {
  description = "Proxmox storage pool for container"
  type        = string
  default     = "ssd" # 719GB available; adequate for control plane
}

variable "storage_size" {
  description = "Root disk size for BASTION01 in GB"
  type        = number
  default     = 16
}

variable "ostemplate" {
  description = "Container OS template ID"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "ip_address" {
  description = "IPv4 address for BASTION01 (VLAN 10 Management)"
  type        = string
  default     = "10.101.0.21" # Fixed IP for BASTION01
}

variable "ip_cidr_suffix" {
  description = "CIDR suffix for BASTION01"
  type        = number
  default     = 24 # /24 = 255.255.255.0
}

variable "gateway" {
  description = "Default gateway for BASTION01"
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

variable "ssh_public_keys" {
  description = "SSH public key(s) for root access to BASTION01"
  type        = string
  sensitive   = true
  default     = "" # Will be provided at apply time or via terraform.tfvars
}

variable "mac_address" {
  description = "MAC address for container (PhoenixStack scheme: 02:aa:bb:cc:01:01)"
  type        = string
  default     = "02:aa:bb:cc:01:01" # Fixed MAC for BASTION01
}
