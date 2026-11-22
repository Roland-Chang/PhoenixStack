# One unprivileged Debian container, its NIC on the guest's VLAN, and its Proxmox firewall.

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
  sources = {
    admin = join(",", local.c.admin_sources)
    lan   = join(",", local.c.lan_sources)
    any   = null
  }
  # Rule comments name the source the same way as the built-in SSH and ping rules.
  source_labels = {
    admin = "admin sources"
    lan   = "LAN sources"
    any   = "anywhere"
  }
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
      servers = [local.g.gateway]
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

resource "proxmox_virtual_environment_firewall_options" "this" {
  node_name    = local.c.node
  container_id = proxmox_virtual_environment_container.this.vm_id

  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
  log_level_in  = "info"
  dhcp          = false
  ndp           = false
  radv          = false
  macfilter     = true
  ipfilter      = false
}

resource "proxmox_virtual_environment_firewall_rules" "this" {
  node_name    = local.c.node
  container_id = proxmox_virtual_environment_container.this.vm_id

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "SSH from admin sources"
    proto   = "tcp"
    dport   = "22"
    source  = local.sources.admin
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "Ping from admin sources"
    proto   = "icmp"
    source  = local.sources.admin
  }

  dynamic "rule" {
    for_each = local.g.firewall_in
    content {
      type    = "in"
      action  = "ACCEPT"
      comment = "${rule.value.proto}/${rule.value.port} from ${lookup(local.source_labels, rule.value.source, rule.value.source)}"
      proto   = rule.value.proto
      dport   = rule.value.port
      source  = lookup(local.sources, rule.value.source, rule.value.source)
    }
  }

  depends_on = [proxmox_virtual_environment_firewall_options.this]
}
