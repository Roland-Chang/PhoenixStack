# One VM, full-cloned from the Debian cloud template, its NIC on the guest's VLAN, and its
# Proxmox firewall. Cloud-init sets the admin user, SSH keys and static IP at first boot;
# the vendor data installs the QEMU guest agent.

terraform {
  required_providers {
    proxmox = { source = "bpg/proxmox" }
  }
}

variable "guest" { type = any }
variable "common" { type = any }
variable "template_vmid" { type = number }
variable "vendor_data_id" { type = string }

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

resource "proxmox_virtual_environment_vm" "this" {
  node_name   = local.c.node
  vm_id       = local.g.vmid
  name        = local.g.name
  pool_id     = local.c.pool
  description = local.g.description
  # No tags: Proxmox checks tag changes against /vms/<vmid> only, not the pool, so a pool-scoped
  # token can't set them while creating a guest. Pool `terraform` marks Terraform's guests.
  on_boot = true
  started = true

  # Same hardware as template 10001 (pve-bootstrap.sh), so a clone doesn't drift from it.
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  tablet_device = false

  clone {
    vm_id        = var.template_vmid
    full         = true
    datastore_id = local.g.storage
  }

  # The agent arrives with the vendor data on first boot, so give it time.
  agent {
    enabled = true
    timeout = "10m"
  }

  cpu {
    cores = local.g.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = local.g.memory
  }

  disk {
    datastore_id = local.g.storage
    interface    = "scsi0"
    size         = local.g.disk_gb
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge      = "vmbr0"
    vlan_id     = local.g.vlan
    mac_address = local.g.mac
    firewall    = true
  }

  initialization {
    datastore_id        = local.g.storage
    vendor_data_file_id = var.vendor_data_id

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

    user_account {
      username = local.c.admin_user
      keys     = local.c.ssh_public_keys
    }
  }

  operating_system {
    type = "l26"
  }

  serial_device {}
}

resource "proxmox_virtual_environment_firewall_options" "this" {
  node_name = local.c.node
  vm_id     = proxmox_virtual_environment_vm.this.vm_id

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
  node_name = local.c.node
  vm_id     = proxmox_virtual_environment_vm.this.vm_id

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
