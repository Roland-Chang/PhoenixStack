# The Proxmox firewall of one guest (container or VM): inbound DROP plus the guest's allow rules,
# and an IP filter, so the guest can only send from its own address (IP and ARP). The rules
# between guests are by source address, so without the filter one guest could pose as another.

terraform {
  required_providers {
    proxmox = { source = "bpg/proxmox" }
  }
}

variable "node" { type = string }
variable "kind" { type = string } # lxc | vm
variable "vmid" { type = number }
variable "ip" { type = string }
variable "admin_sources" { type = string } # comma-separated CIDRs
variable "rules" { type = any }            # [{port, proto, source, label}], sources resolved by the root module

locals {
  vm_id        = var.kind == "vm" ? var.vmid : null
  container_id = var.kind == "lxc" ? var.vmid : null
}

# The only source address net0 may use. Created before the filter is switched on: a VM's filter
# starts empty (Proxmox adds a container's configured address by itself, but not a VM's), so a VM
# would lose its IPv4 traffic in between.
resource "proxmox_virtual_environment_firewall_ipset" "ipfilter" {
  node_name    = var.node
  vm_id        = local.vm_id
  container_id = local.container_id
  name         = "ipfilter-net0"
  comment      = "Managed by Terraform: the only source address net0 may use (IP and ARP)"

  cidr {
    name = var.ip
  }
}

resource "proxmox_virtual_environment_firewall_options" "this" {
  node_name    = var.node
  vm_id        = local.vm_id
  container_id = local.container_id

  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
  log_level_in  = "info"
  dhcp          = false
  ndp           = false
  radv          = false
  macfilter     = true
  ipfilter      = true

  depends_on = [proxmox_virtual_environment_firewall_ipset.ipfilter]
}

resource "proxmox_virtual_environment_firewall_rules" "this" {
  node_name    = var.node
  vm_id        = local.vm_id
  container_id = local.container_id

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "SSH from admin sources"
    proto   = "tcp"
    dport   = "22"
    source  = var.admin_sources
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "Ping from admin sources"
    proto   = "icmp"
    source  = var.admin_sources
  }

  dynamic "rule" {
    for_each = var.rules
    content {
      type    = "in"
      action  = "ACCEPT"
      comment = "${rule.value.proto}/${rule.value.port} from ${rule.value.label}"
      proto   = rule.value.proto
      dport   = rule.value.port
      source  = rule.value.source
    }
  }

  depends_on = [proxmox_virtual_environment_firewall_options.this]
}
