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
  # Never reboot a VM by itself during an apply: a change that needs the VM offline fails
  # instead, and one that needs a later reboot only warns. (Default true: on 2026-11-22 a DNS
  # change rebooted both VMs mid-apply.) Reboot by hand: ansible <guest> -m reboot.
  reboot_after_update = false

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

  # The app's data on its own disk (inventory data_disk_gb): it grows online, and to shrink it, its data is
  # copied to a smaller disk. Thin, with discard, like the system disk.
  dynamic "disk" {
    for_each = local.g.data_disk_gb == null ? [] : [local.g.data_disk_gb]
    content {
      datastore_id = local.g.storage
      interface    = "scsi1"
      size         = disk.value
      discard      = "on"
      ssd          = true
      iothread     = true
    }
  }

  # A GPU passed through by its resource mapping on pve01 (inventory gpu_mapping, e.g. GPU01). The token
  # needs Mapping.Use on /mapping/pci/<name>. Adding it to a running VM takes effect at its next start.
  dynamic "hostpci" {
    for_each = local.g.gpu_mapping == null ? [] : [local.g.gpu_mapping]
    content {
      device  = "hostpci0"
      mapping = hostpci.value
      pcie    = true
      rombar  = true
    }
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

# Inbound DROP, the guest's allow rules, and the IP filter (modules/firewall).
module "firewall" {
  source        = "../firewall"
  node          = local.c.node
  kind          = "vm"
  vmid          = proxmox_virtual_environment_vm.this.vm_id
  ip            = local.g.ip
  admin_sources = join(",", local.c.admin_sources)
  rules         = local.g.firewall_in
}
