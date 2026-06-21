# Phoenix Stack Master Terraform Configuration
# Parameterized modules for all 25 container instances

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
<<<<<<< HEAD
  source            = "./modules/bastion"
  instance_vmid     = 101
  instance_hostname = "bastion01"
  cpu_cores         = 2
  memory_mb         = 4096
  ip_address        = "10.101.0.21"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["bastion01"]
=======
  source = "./bastion01"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["bastion01"]

  # Each service module uses its own variables.tf with service-specific defaults
  # Proxmox credentials are inherited from root provider configuration
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
}

module "bastion02" {
<<<<<<< HEAD
  source            = "./modules/bastion"
  instance_vmid     = 102
  instance_hostname = "bastion02"
  cpu_cores         = 2
  memory_mb         = 4096
  ip_address        = "10.101.0.22"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["bastion02"]
=======
  source = "./bastion02"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["bastion02"]

  # Each service module uses its own variables.tf with service-specific defaults
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
}

# ============================================================================
# DNS TIER - Domain Name Services (PiHole)
# ============================================================================
module "dns01" {
<<<<<<< HEAD
  source            = "./modules/dns"
  instance_vmid     = 103
  instance_hostname = "dns01"
  cpu_cores         = 2
  memory_mb         = 2048
  ip_address        = "10.101.0.201"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["dns01"]
=======
  source = "./dns01"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["dns01"]

  # Each service module uses its own variables.tf with service-specific defaults
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
}

module "dns02" {
<<<<<<< HEAD
  source            = "./modules/dns"
  instance_vmid     = 104
  instance_hostname = "dns02"
  cpu_cores         = 2
  memory_mb         = 2048
  ip_address        = "10.101.0.202"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["dns02"]
}

# ============================================================================
# PROXY TIER - Reverse Proxy & Load Balancing (Traefik)
# ============================================================================
module "proxy01" {
  source            = "./modules/proxy"
  instance_vmid     = 105
  instance_hostname = "proxy01"
  cpu_cores         = 2
  memory_mb         = 2048
  ip_address        = "10.101.0.31"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["proxy01"]
}

module "proxy02" {
  source            = "./modules/proxy"
  instance_vmid     = 106
  instance_hostname = "proxy02"
  cpu_cores         = 2
  memory_mb         = 2048
  ip_address        = "10.101.0.32"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["proxy02"]
}

# ============================================================================
# AUTHENTIK TIER - Identity & Authentication
# ============================================================================
module "authentik01" {
  source            = "./modules/authentik"
  instance_vmid     = 107
  instance_hostname = "authentik01"
  cpu_cores         = 2
  memory_mb         = 2048
  ip_address        = "10.101.0.41"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["authentik01"]
}

module "authentik02" {
  source            = "./modules/authentik"
  instance_vmid     = 108
  instance_hostname = "authentik02"
  cpu_cores         = 2
  memory_mb         = 2048
  ip_address        = "10.101.0.42"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["authentik02"]
}

# ============================================================================
# POSTGRES TIER - Primary Database for Authentik HA
# ============================================================================
module "pgsql01" {
  source            = "./modules/postgres"
  instance_vmid     = 115
  instance_hostname = "pgsql01"
  cpu_cores         = 2
  memory_mb         = 2048
  storage_size      = 32
  ip_address        = "10.101.0.71"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["pgsql01"]
}

module "pgsql02" {
  source            = "./modules/postgres"
  instance_vmid     = 116
  instance_hostname = "pgsql02"
  cpu_cores         = 2
  memory_mb         = 2048
  storage_size      = 32
  ip_address        = "10.101.0.72"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["pgsql02"]
}

# ============================================================================
# MARIADB TIER - Secondary Database (Optional MySQL/MariaDB)
# ============================================================================
module "db01" {
  source            = "./modules/mariadb"
  instance_vmid     = 117
  instance_hostname = "db01"
  cpu_cores         = 2
  memory_mb         = 2048
  storage_size      = 32
  ip_address        = "10.101.0.75"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["db01"]
}

module "db02" {
  source            = "./modules/mariadb"
  instance_vmid     = 118
  instance_hostname = "db02"
  cpu_cores         = 2
  memory_mb         = 2048
  storage_size      = 32
  ip_address        = "10.101.0.76"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["db02"]
}

# ============================================================================
# MONITOR TIER - Observability (Prometheus/Grafana)
# ============================================================================
module "monitor01" {
  source            = "./modules/monitor"
  instance_vmid     = 119
  instance_hostname = "monitor01"
  cpu_cores         = 2
  memory_mb         = 2048
  ip_address        = "10.101.0.91"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["monitor01"]
}

module "monitor02" {
  source            = "./modules/monitor"
  instance_vmid     = 120
  instance_hostname = "monitor02"
  cpu_cores         = 2
  memory_mb         = 2048
  ip_address        = "10.101.0.92"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["monitor02"]
}

# ============================================================================
# VAULT TIER - Secrets Management (HashiCorp Vault HA Cluster)
# ============================================================================
module "vault01" {
  source            = "./modules/vault"
  instance_vmid     = 121
  instance_hostname = "vault01"
  cpu_cores         = 2
  memory_mb         = 2048
  ip_address        = "10.101.0.81"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["vault01"]
}

module "vault02" {
  source            = "./modules/vault"
  instance_vmid     = 122
  instance_hostname = "vault02"
  cpu_cores         = 2
  memory_mb         = 2048
  ip_address        = "10.101.0.82"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["vault02"]
}

# ============================================================================
# BACKUP TIER - Proxmox Backup Orchestration
# ============================================================================
module "backup01" {
  source            = "./modules/backup"
  instance_vmid     = 123
  instance_hostname = "backup01"
  cpu_cores         = 2
  memory_mb         = 2048
  storage_size      = 64
  ip_address        = "10.101.0.98"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["backup01"]
}

# ============================================================================
# DOCKER TIER - Containerized Services (Docker host)
# ============================================================================
module "docker01" {
  source            = "./modules/docker"
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
  source            = "./modules/docker"
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
  source            = "./modules/plex"
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
  source            = "./modules/plex"
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
  source            = "./modules/amp"
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
  source            = "./modules/amp"
  instance_vmid     = 114
  instance_hostname = "amp02"
  cpu_cores         = 4
  memory_mb         = 4096
  storage_size      = 128
  ip_address        = "10.101.1.82"
  ssh_public_keys   = var.ssh_public_keys
  mac_address       = var.service_mac_addresses["amp02"]
}

# ============================================================================
# OUTPUTS - Deployment Summary
# ============================================================================
output "bastion_instances" {
  value = {
    bastion01_vmid = module.bastion01.vmid
    bastion02_vmid = module.bastion02.vmid
  }
}

output "all_instances_vmids" {
  value = {
    bastion   = { bastion01 = module.bastion01.vmid, bastion02 = module.bastion02.vmid }
    dns       = { dns01 = module.dns01.vmid, dns02 = module.dns02.vmid }
    proxy     = { proxy01 = module.proxy01.vmid, proxy02 = module.proxy02.vmid }
    authentik = { authentik01 = module.authentik01.vmid, authentik02 = module.authentik02.vmid }
    postgres  = { pgsql01 = module.pgsql01.vmid, pgsql02 = module.pgsql02.vmid }
    mariadb   = { db01 = module.db01.vmid, db02 = module.db02.vmid }
    monitor   = { monitor01 = module.monitor01.vmid, monitor02 = module.monitor02.vmid }
    vault     = { vault01 = module.vault01.vmid, vault02 = module.vault02.vmid }
    backup    = { backup01 = module.backup01.vmid }
    docker    = { docker01 = module.docker01.vmid, docker02 = module.docker02.vmid }
    plex      = { plex01 = module.plex01.vmid, plex02 = module.plex02.vmid }
    amp       = { amp01 = module.amp01.vmid, amp02 = module.amp02.vmid }
  }
}
=======
  source = "./dns02"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["dns02"]

  # Each service module uses its own variables.tf with service-specific defaults
}

# PROXY01 - Reverse proxy (Traefik) for ingress routing
module "proxy01" {
  source = "./proxy01"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["proxy01"]
}

# PROXY02 - Secondary reverse proxy (Traefik) for redundancy
module "proxy02" {
  source = "./proxy02"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["proxy02"]
}

# AUTHENTIK01 - Identity provider (OAuth/SAML)
module "authentik01" {
  source = "./authentik01"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["authentik01"]
}

# AUTHENTIK02 - Secondary identity provider for redundancy
module "authentik02" {
  source = "./authentik02"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["authentik02"]
}

# SQL01 - PostgreSQL database primary (HA cluster master)
module "sql01" {
  source = "./sql01"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["sql01"]
}

# SQL02 - PostgreSQL database standby (HA cluster replica with streaming replication)
module "sql02" {
  source = "./sql02"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["sql02"]
}

# DB01 - MySQL/MariaDB primary (HA cluster master)
module "db01" {
  source = "./db01"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["db01"]
}

# DB02 - MySQL/MariaDB standby (HA cluster replica with replication)
module "db02" {
  source = "./db02"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["db02"]
}

# MONITOR01 - Prometheus metrics collection (Active)
module "monitor01" {
  source = "./monitor01"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["monitor01"]
}

# MONITOR02 - Grafana visualization and dashboards (HA partner)
module "monitor02" {
  source = "./monitor02"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["monitor02"]
}

# VAULT01 - HashiCorp Vault secrets management primary (Raft cluster member)
module "vault01" {
  source = "./vault01"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["vault01"]
}

# VAULT02 - HashiCorp Vault secrets management standby (Raft cluster member)
module "vault02" {
  source = "./vault02"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["vault02"]
}

# BACKUP01 - Proxmox backup orchestration and client
module "backup01" {
  source = "./backup01"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["backup01"]
}

# DOCKER01 - Containerized services platform (Docker host)
module "docker01" {
  source = "./docker01"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["docker01"]
}

# DOCKER02 - Secondary Docker host (redundancy, load distribution)
module "docker02" {
  source = "./docker02"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["docker02"]
}

# PLEX01 - Media server (Plex)
module "plex01" {
  source = "./plex01"

  # Global configuration - passed from root
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["plex01"]
}

# GitHub Actions Runner Test - 2026-06-15
# This comment triggers the workflow to verify the bastion01 self-hosted runner is operational
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
