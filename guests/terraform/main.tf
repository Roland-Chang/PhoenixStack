# Every guest in ../inventory.yml, created on pve01 in pool `terraform`.

locals {
  inventory = yamldecode(file("${path.module}/../inventory.yml"))
  globals   = local.inventory.all.vars

  # One flat map of guests, each with the same attributes (group values and defaults filled in).
  guests = merge([
    for group_name, group in local.inventory.all.children : {
      for name, h in group.hosts : name => {
        name        = name
        kind        = h.kind
        vmid        = h.vmid
        mac         = upper(h.mac)
        ip          = h.ip
        zone        = group.vars.zone
        vlan        = group.vars.vlan
        gateway     = group.vars.gateway
        cores       = try(h.cores, 1)
        memory      = try(h.memory, 512)
        disk_gb     = try(h.disk_gb, 8)
        storage     = try(h.storage, "ssd")
        description = try(h.description, "")
        # Boot order on pve01 (DNS 1, databases 2); null leaves it unset.
        startup_order = try(h.startup_order, null)
        firewall_in = [
          for r in try(h.firewall_in, []) : {
            port   = tostring(r.port)
            proto  = try(r.proto, "tcp")
            source = try(r.source, "admin")
          }
        ]
      }
    }
  ]...)

  common = {
    node            = var.node
    pool            = var.pool
    domain          = local.globals.domain
    ssh_public_keys = local.globals.ssh_public_keys
    admin_user      = local.globals.admin_user
    admin_sources   = local.globals.admin_sources
    lan_sources     = local.globals.lan_sources
  }
}

module "lxc" {
  source   = "./modules/lxc"
  for_each = { for k, g in local.guests : k => g if g.kind == "lxc" }

  guest    = each.value
  common   = local.common
  template = var.lxc_template
}

module "vm" {
  source   = "./modules/vm"
  for_each = { for k, g in local.guests : k => g if g.kind == "vm" }

  guest          = each.value
  common         = local.common
  template_vmid  = var.vm_template_vmid
  vendor_data_id = var.vm_vendor_data
}

output "guests" {
  description = "What Terraform manages: name, kind, VMID, address."
  value       = { for k, g in local.guests : k => "${g.kind} ${g.vmid} ${g.ip} (${g.zone})" }
}
