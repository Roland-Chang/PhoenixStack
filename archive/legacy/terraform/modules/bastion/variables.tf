# Parameterized Bastion Module Variables
# Supports any bastion instance (bastion01, bastion02, etc.)

variable "proxmox_node" {
  description = "Proxmox node for deployment"
  type        = string
  default     = "pve01"
}

variable "instance_vmid" {
  description = "Unique VM ID for this bastion instance"
  type        = number
}

variable "instance_hostname" {
  description = "Container hostname"
  type        = string
}

variable "cpu_cores" {
  description = "CPU cores for bastion"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM for bastion in MB"
  type        = number
  default     = 4096 # 4GB for control plane
}

variable "swap_mb" {
  description = "Swap memory in MB"
  type        = number
  default     = 1024 # 1GB
}

variable "storage_pool" {
  description = "Proxmox storage pool"
  type        = string
  default     = "ssd"
}

variable "storage_size" {
  description = "Root disk size in GB"
  type        = number
  default     = 16
}

variable "ostemplate" {
  description = "Container OS template ID"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "ip_address" {
  description = "IPv4 address (VLAN 10 Management)"
  type        = string
}

variable "ip_cidr_suffix" {
  description = "CIDR suffix"
  type        = number
  default     = 24 # /24 = 255.255.255.0
}

variable "gateway" {
  description = "Default gateway"
  type        = string
  default     = "10.101.0.254"
}

variable "network_bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

variable "search_domain" {
  description = "DNS search domain"
  type        = string
  default     = "phoenix.stack"
}

variable "ssh_public_keys" {
  description = "SSH public key(s) for root access"
  type        = string
  sensitive   = true
}

variable "mac_address" {
  description = "MAC address (PhoenixStack scheme)"
  type        = string
}

variable "enable_nesting" {
  description = "Enable nesting (for containers running containers)"
  type        = bool
  default     = true
}
