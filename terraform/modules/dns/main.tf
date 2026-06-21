# Parameterized Service Module
# Wraps the lxc module with service-specific defaults

module "service_container" {
  source = "../lxc"

  proxmox_node    = var.proxmox_node
  vmid            = var.instance_vmid
  hostname        = var.instance_hostname
  ostemplate      = var.ostemplate
  cpu_cores       = var.cpu_cores
  memory_mb       = var.memory_mb
  swap_mb         = var.swap_mb
  storage_pool    = var.storage_pool
  storage_size    = var.storage_size
  ip_address      = var.ip_address
  ip_cidr_suffix  = var.ip_cidr_suffix
  gateway         = var.gateway
  network_bridge  = var.network_bridge
  nameserver      = var.gateway
  search_domain   = var.search_domain
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.mac_address
  enable_nesting  = var.enable_nesting
  unprivileged    = true
  autostart       = true
  onboot          = true
}

output "vmid" {
  description = "Container VMID"
  value       = module.service_container.vmid
}

output "hostname" {
  description = "Container hostname"
  value       = module.service_container.hostname
}

output "ip_address" {
  description = "Container IP address"
  value       = module.service_container.ip_address
}
