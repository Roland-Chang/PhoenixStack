# Root Terraform Variables
# Global container defaults and module-specific settings

# ============================================================================
# GLOBAL CONTAINER DEFAULTS (can be overridden per service in auto.tfvars)
# ============================================================================

variable "proxmox_node" {
  description = "Default Proxmox node for container deployment"
  type        = string
  default     = "pve01"
}

variable "container_vmid" {
  description = "VM ID for container (must be unique on Proxmox)"
  type        = number
  default     = 100
}

variable "hostname" {
  description = "Container hostname"
  type        = string
  default     = "container"
}

variable "cpu_cores" {
  description = "CPU cores for container"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM for container in MB"
  type        = number
  default     = 2048
}

variable "swap_mb" {
  description = "Swap memory for container in MB"
  type        = number
  default     = 1024
}

variable "storage_pool" {
  description = "Proxmox storage pool for container"
  type        = string
  default     = "local-lvm"
}

variable "storage_size" {
  description = "Root disk size for container in GB"
  type        = number
  default     = 20
}

variable "ostemplate" {
  description = "Container OS template ID"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "ip_address" {
  description = "IPv4 address for container"
  type        = string
  default     = "10.101.0.100"
}

variable "ip_cidr_suffix" {
  description = "CIDR suffix for container (/24 = 255.255.255.0)"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Default gateway for container"
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
  description = "SSH public key(s) for root access to container"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mac_address" {
  description = "MAC address for container (PhoenixStack scheme: 02:aa:bb:cc:XX:YY)"
  type        = string
  default     = ""
}

# ============================================================================
# SERVICE MAC ADDRESSES - PhoenixStack Scheme
# ============================================================================

variable "service_mac_addresses" {
  description = "Fixed MAC addresses for each service (PhoenixStack scheme: 02:aa:bb:cc:XX:YY)"
  type        = map(string)
  default = {
    # Bastion tier (SSH/GitHub runners) - 01
    bastion01 = "02:aa:bb:cc:01:01"
    bastion02 = "02:aa:bb:cc:01:02"
    # DNS tier (PiHole) - 02
    dns01 = "02:aa:bb:cc:02:01"
    dns02 = "02:aa:bb:cc:02:02"
    # Proxy tier (Traefik) - 03
    proxy01 = "02:aa:bb:cc:03:01"
    proxy02 = "02:aa:bb:cc:03:02"
    # Identity tier (Authentik) - 04
    authentik01 = "02:aa:bb:cc:04:01"
    authentik02 = "02:aa:bb:cc:04:02"
    # Security tier (Vault) - 05
    vault01 = "02:aa:bb:cc:05:01"
    vault02 = "02:aa:bb:cc:05:02"
    # Observability tier (Plex/Media) - 06
    plex01 = "02:aa:bb:cc:06:01"
    plex02 = "02:aa:bb:cc:06:02"
    # Database tier (PostgreSQL/SQL cluster) - 07:01-02
    sql01 = "02:aa:bb:cc:07:01"
    sql02 = "02:aa:bb:cc:07:02"
    # Database tier (MySQL/MariaDB cluster) - 07:03-04
    db01 = "02:aa:bb:cc:07:03"
    db02 = "02:aa:bb:cc:07:04"
    # Backup tier - 08
    backup01 = "02:aa:bb:cc:08:01"
    # Observability tier (Prometheus/Grafana) - 09
    monitor01 = "02:aa:bb:cc:09:01"
    monitor02 = "02:aa:bb:cc:09:02"
    # Container tier (Docker) - 10
    docker01 = "02:aa:bb:cc:10:01"
    docker02 = "02:aa:bb:cc:10:02"
  }
}
