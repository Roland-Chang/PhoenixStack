# LXC Module Outputs

output "vmid" {
  description = "Proxmox VM/Container ID"
  value       = proxmox_lxc.container.vmid
}

output "hostname" {
  description = "Container hostname"
  value       = proxmox_lxc.container.hostname
}

output "ip_address" {
  description = "Container primary IP address"
  value       = var.ip_address
}

output "gateway" {
  description = "Container default gateway"
  value       = var.gateway
}
