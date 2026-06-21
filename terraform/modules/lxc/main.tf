# LXC Container Module
# Reusable module for deploying Ubuntu LXC containers on Proxmox

terraform {
  required_version = ">= 1.5"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }
}

resource "proxmox_lxc" "container" {
  # Proxmox Target
  target_node = var.proxmox_node
  vmid        = var.vmid
  hostname    = var.hostname

  # Container OS Type
  ostemplate = var.ostemplate

  # Resource Allocation
  cores  = var.cpu_cores
  memory = var.memory_mb
  swap   = var.swap_mb

  # Storage Configuration
  rootfs {
    storage = var.storage_pool
    size    = "${var.storage_size}G"
  }

  # Networking
  nameserver   = var.gateway
  searchdomain = var.search_domain

  # SSH Public Keys for root access
  ssh_public_keys = var.ssh_public_keys

  # Container Behavior
  start        = var.autostart
  onboot       = var.onboot
  unprivileged = var.unprivileged
  protection   = false

  # Features (for systemd compatibility)
  # We explicitly set nesting for systemd compatibility.
  # keyctl and mknod are left to Proxmox defaults (cannot be managed by terraform-token).
  features {
    nesting = var.enable_nesting
  }

  # Network Interface - Primary (Management VLAN)
  network {
    name   = "eth0"
    hwaddr = var.mac_address != "" ? var.mac_address : null
    ip     = "${var.ip_address}/${var.ip_cidr_suffix}"
    gw     = var.gateway
    bridge = var.network_bridge
  }

  lifecycle {
    ignore_changes = [
      rootfs,    # Avoid drift if storage reference changes
      features   # Token cannot manage keyctl/mknod; ignore all feature drift
    ]
  }
}
