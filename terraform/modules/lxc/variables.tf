# LXC Module Variables

variable "proxmox_node" {
  description = "Proxmox node name where container will be deployed"
  type        = string
  default     = "pve01"
}

variable "vmid" {
  description = "Unique VM ID for this container (100-999999)"
  type        = number
  validation {
    condition     = var.vmid >= 100 && var.vmid <= 999999
    error_message = "VMID must be between 100 and 999999."
  }
}

variable "hostname" {
  description = "Container hostname (lowercase, no spaces)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.hostname))
    error_message = "Hostname must be lowercase alphanumeric with hyphens, no leading/trailing hyphens."
  }
}

variable "ostemplate" {
  description = "Container OS template ID (e.g., 'local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst')"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "cpu_cores" {
  description = "Number of CPU cores to allocate"
  type        = number
  default     = 2
  validation {
    condition     = var.cpu_cores >= 1 && var.cpu_cores <= 32
    error_message = "CPU cores must be between 1 and 32."
  }
}

variable "memory_mb" {
  description = "RAM in MB"
  type        = number
  default     = 2048
  validation {
    condition     = var.memory_mb >= 256 && var.memory_mb <= 1048576
    error_message = "Memory must be between 256 MB and 1 TB."
  }
}

variable "swap_mb" {
  description = "Swap memory in MB"
  type        = number
  default     = 512
}

variable "storage_pool" {
  description = "Proxmox storage pool (e.g., 'local', 'local-lvm')"
  type        = string
  default     = "local-lvm"
}

variable "storage_size" {
  description = "Root filesystem size in GB"
  type        = number
  default     = 16
  validation {
    condition     = var.storage_size >= 8 && var.storage_size <= 1024
    error_message = "Storage size must be between 8 GB and 1 TB."
  }
}

variable "ip_address" {
  description = "IPv4 address for primary network interface (without CIDR)"
  type        = string
  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.ip_address))
    error_message = "IP address must be a valid IPv4 address."
  }
}

variable "ip_cidr_suffix" {
  description = "CIDR suffix for primary network (e.g., 24 for /24)"
  type        = number
  default     = 24
  validation {
    condition     = var.ip_cidr_suffix >= 8 && var.ip_cidr_suffix <= 30
    error_message = "CIDR suffix must be between 8 and 30."
  }
}

variable "gateway" {
  description = "Default gateway IP address"
  type        = string
}

variable "nameserver" {
  description = "DNS nameserver (space-separated list)"
  type        = string
  default     = "10.101.0.1"
}

variable "search_domain" {
  description = "DNS search domain"
  type        = string
  default     = "phoenix.stack"
}

variable "mac_address" {
  description = "MAC address for primary interface (optional, auto-generated if empty)"
  type        = string
  default     = ""
  validation {
    condition     = var.mac_address == "" || can(regex("^([0-9A-Fa-f]{2}[:]){5}([0-9A-Fa-f]{2})$", var.mac_address))
    error_message = "MAC address must be in format XX:XX:XX:XX:XX:XX or empty."
  }
}

variable "network_bridge" {
  description = "Proxmox bridge for networking (e.g., vmbr0)"
  type        = string
  default     = "vmbr0"
}

variable "timezone" {
  description = "Container timezone (configured post-deployment via Ansible)"
  type        = string
  default     = "UTC"
}

variable "autostart" {
  description = "Start container on Proxmox startup"
  type        = bool
  default     = true
}

variable "onboot" {
  description = "Start container when Proxmox boots"
  type        = bool
  default     = true
}

variable "unprivileged" {
  description = "Run container as unprivileged (more secure)"
  type        = bool
  default     = true
}

variable "ssh_public_keys" {
  description = "SSH public key(s) to add to root user (GitHub import format or raw keys)"
  type        = string
  sensitive   = true
}

variable "enable_nesting" {
  description = "Enable container nesting for systemd compatibility (required for systemd 255+)"
  type        = bool
  default     = true
}
