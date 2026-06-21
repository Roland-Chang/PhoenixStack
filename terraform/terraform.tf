# Phoenix Stack Master Terraform Configuration
# Modular infrastructure-as-code with DRY principles
# Service type modules (bastion, dns, authentik, etc.) called multiple times with different parameters

terraform {
  required_version = ">= 1.5"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# Configure the Proxmox Provider
provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = true
}

# ============================================================================
# BASTION TIER - Control Plane (SSH, Ansible, GitHub Actions runner)
# ============================================================================

module "bastion01" {
  source = "./modules/bastion"

  instance_vmid     = 101
  instance_hostname = "bastion01"
  ip_address        = "10.101.0.21"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["bastion01"]
}

module "bastion02" {
  source = "./modules/bastion"

  instance_vmid     = 102
  instance_hostname = "bastion02"
  ip_address        = "10.101.0.22"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["bastion02"]
}

# ============================================================================
# DNS TIER - Domain Name Services (PiHole)
# ============================================================================

module "dns01" {
  source = "./modules/dns"

  instance_vmid     = 103
  instance_hostname = "dns01"
  ip_address        = "10.101.0.201"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["dns01"]
}

module "dns02" {
  source = "./modules/dns"

  instance_vmid     = 104
  instance_hostname = "dns02"
  ip_address        = "10.101.0.202"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["dns02"]
}

# ============================================================================
# PROXY TIER - Reverse Proxy & Load Balancing (Traefik)
# ============================================================================

module "proxy01" {
  source = "./modules/proxy"

  instance_vmid     = 105
  instance_hostname = "proxy01"
  ip_address        = "10.101.0.31"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["proxy01"]
}

module "proxy02" {
  source = "./modules/proxy"

  instance_vmid     = 106
  instance_hostname = "proxy02"
  ip_address        = "10.101.0.32"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["proxy02"]
}

# ============================================================================
# AUTHENTIK TIER - Identity & Authentication
# ============================================================================

module "authentik01" {
  source = "./modules/authentik"

  instance_vmid     = 107
  instance_hostname = "authentik01"
  ip_address        = "10.101.0.41"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["authentik01"]
}

module "authentik02" {
  source = "./modules/authentik"

  instance_vmid     = 108
  instance_hostname = "authentik02"
  ip_address        = "10.101.0.42"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["authentik02"]
}

# ============================================================================
# POSTGRES TIER - Primary Database for Authentik HA
# ============================================================================

module "pgsql01" {
  source = "./modules/postgres"

  instance_vmid     = 115
  instance_hostname = "pgsql01"
  ip_address        = "10.101.0.71"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["pgsql01"]
}

module "pgsql02" {
  source = "./modules/postgres"

  instance_vmid     = 116
  instance_hostname = "pgsql02"
  ip_address        = "10.101.0.72"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["pgsql02"]
}

# ============================================================================
# MARIADB TIER - Secondary Database (MySQL/MariaDB)
# ============================================================================

module "mariadb01" {
  source = "./modules/mariadb"

  instance_vmid     = 117
  instance_hostname = "db01"
  ip_address        = "10.101.0.75"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["db01"]
}

module "mariadb02" {
  source = "./modules/mariadb"

  instance_vmid     = 118
  instance_hostname = "db02"
  ip_address        = "10.101.0.76"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["db02"]
}

# ============================================================================
# MONITOR TIER - Observability (Prometheus/Grafana)
# ============================================================================

module "monitor01" {
  source = "./modules/monitor"

  instance_vmid     = 119
  instance_hostname = "monitor01"
  ip_address        = "10.101.0.91"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["monitor01"]
}

module "monitor02" {
  source = "./modules/monitor"

  instance_vmid     = 120
  instance_hostname = "monitor02"
  ip_address        = "10.101.0.92"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["monitor02"]
}

# ============================================================================
# VAULT TIER - Secrets Management (HashiCorp Vault HA Cluster)
# ============================================================================

module "vault01" {
  source = "./modules/vault"

  instance_vmid     = 121
  instance_hostname = "vault01"
  ip_address        = "10.101.0.81"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["vault01"]
}

module "vault02" {
  source = "./modules/vault"

  instance_vmid     = 122
  instance_hostname = "vault02"
  ip_address        = "10.101.0.82"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["vault02"]
}

# ============================================================================
# BACKUP TIER - Proxmox Backup Orchestration
# ============================================================================

module "backup01" {
  source = "./modules/backup"

  instance_vmid     = 123
  instance_hostname = "backup01"
  storage_size      = 64
  ip_address        = "10.101.0.98"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["backup01"]
}

# ============================================================================
# DOCKER TIER - Containerized Services
# ============================================================================

module "docker01" {
  source = "./modules/docker"

  instance_vmid     = 109
  instance_hostname = "docker01"
  cpu_cores         = 4
  memory_mb         = 4096
  storage_size      = 64
  ip_address        = "10.101.1.51"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["docker01"]
}

module "docker02" {
  source = "./modules/docker"

  instance_vmid     = 110
  instance_hostname = "docker02"
  cpu_cores         = 4
  memory_mb         = 4096
  storage_size      = 64
  ip_address        = "10.101.1.52"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["docker02"]
}

# ============================================================================
# PLEX TIER - Media Server
# ============================================================================

module "plex01" {
  source = "./modules/plex"

  instance_vmid     = 111
  instance_hostname = "plex01"
  cpu_cores         = 4
  memory_mb         = 4096
  storage_size      = 256
  ip_address        = "10.101.1.61"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["plex01"]
}

module "plex02" {
  source = "./modules/plex"

  instance_vmid     = 112
  instance_hostname = "plex02"
  cpu_cores         = 4
  memory_mb         = 4096
  storage_size      = 256
  ip_address        = "10.101.1.62"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["plex02"]
}

# ============================================================================
# AMP TIER - Game Servers (CubeCoders AMP)
# ============================================================================

module "amp01" {
  source = "./modules/amp"

  instance_vmid     = 113
  instance_hostname = "amp01"
  cpu_cores         = 4
  memory_mb         = 4096
  storage_size      = 128
  ip_address        = "10.101.1.81"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["amp01"]
}

module "amp02" {
  source = "./modules/amp"

  instance_vmid     = 114
  instance_hostname = "amp02"
  cpu_cores         = 4
  memory_mb         = 4096
  storage_size      = 128
  ip_address        = "10.101.1.82"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["amp02"]
}
