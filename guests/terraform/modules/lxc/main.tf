# One unprivileged Debian container, its NIC on the guest's VLAN, and its Proxmox firewall
# (modules/firewall).

terraform {
  required_providers {
    proxmox = { source = "bpg/proxmox" }
  }
}

variable "guest" { type = any }
variable "common" { type = any }
variable "template" { type = string }

locals {
  g = var.guest
  c = var.common
}

resource "proxmox_virtual_environment_container" "this" {
  node_name   = local.c.node
  vm_id       = local.g.vmid
  pool_id     = local.c.pool
  description = local.g.description
  # No tags: Proxmox checks tag changes against /vms/<vmid> only, not the pool, so a pool-scoped
  # token can't set them while creating a guest. Pool `terraform` marks Terraform's guests.
  unprivileged  = true
  start_on_boot = true
  started       = true

  # Boot order after a host reboot: DNS first, then databases, then the rest.
  dynamic "startup" {
    for_each = local.g.startup_order == null ? [] : [local.g.startup_order]
    content {
      order = startup.value
    }
  }

  # nesting is the one feature flag a token may set; systemd in Debian 13 needs it.
  features {
    nesting = true
  }

  cpu {
    cores = local.g.cores
  }

  memory {
    dedicated = local.g.memory
    swap      = 0
  }

  disk {
    datastore_id = local.g.storage
    size         = local.g.disk_gb
  }

  operating_system {
    template_file_id = var.template
    type             = "debian"
  }

  initialization {
    hostname = local.g.name

    dns {
      domain  = local.c.domain
      servers = local.g.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${local.g.ip}/24"
        gateway = local.g.gateway
      }
    }

    # Root's keys on a new container; Ansible's base role then creates the admin user
    # and turns root login off.
    user_account {
      keys = local.c.ssh_public_keys
    }
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    vlan_id     = local.g.vlan
    mac_address = local.g.mac
    firewall    = true
  }
}

# Inbound DROP, the guest's allow rules, and the IP filter (modules/firewall).
module "firewall" {
  source        = "../firewall"
  node          = local.c.node
  kind          = "lxc"
  vmid          = proxmox_virtual_environment_container.this.vm_id
  ip            = local.g.ip
  admin_sources = join(",", local.c.admin_sources)
  rules         = local.g.firewall_in
}
