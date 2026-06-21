# VAULT02 - Terraform Variables
# HashiCorp Vault - Secrets Management Standby (Raft cluster member)

variable "proxmox_node" {
  description = "Proxmox node for VAULT02 deployment"
  type        = string
  default     = "pve01"
}

variable "container_vmid" {
  description = "Unique VM ID for VAULT02 (must be unique on Proxmox)"
  type        = number
  default     = 119 # Fixed VMID for VAULT02
}

variable "hostname" {
  description = "Container hostname"
  type        = string
  default     = "vault02"
}

variable "cpu_cores" {
  description = "CPU cores for VAULT02"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM for VAULT02 in MB"
  type        = number
  default     = 1024 # 1GB sufficient for Vault
}

variable "swap_mb" {
  description = "Swap memory for VAULT02 in MB"
  type        = number
  default     = 512
}

variable "storage_pool" {
  description = "Proxmox storage pool for container"
  type        = string
  default     = "ssd" # SSD pool for consistency
}

variable "storage_size" {
  description = "Root disk size for VAULT02 in GB"
  type        = number
  default     = 16 # Vault state stored in SQL, minimal local storage needed
}

variable "ostemplate" {
  description = "Container OS template ID"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "ip_address" {
  description = "IPv4 address for VAULT02 (VLAN 10 Management)"
  type        = string
  default     = "10.101.0.82" # Fixed IP for VAULT02
}

variable "ip_cidr_suffix" {
  description = "CIDR suffix for VAULT02"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Default gateway for VAULT02"
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
  description = "SSH public key(s) for root access to VAULT02"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mac_address" {
  description = "MAC address for VAULT02 (PhoenixStack scheme: 02:aa:bb:cc:05:02)"
  type        = string
  default     = ""
}
