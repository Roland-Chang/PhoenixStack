variable "node" {
  description = "Proxmox node the guests run on."
  type        = string
  default     = "pve01"
}

variable "pool" {
  description = "Resource pool for every guest; the API token can only manage guests in it."
  type        = string
  default     = "terraform"
}

variable "lxc_template" {
  description = "Container template (downloaded by the bootstrap's templates stage)."
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
}

variable "vm_template_vmid" {
  description = "VM template to clone (built by the bootstrap's templates stage, pool templates)."
  type        = number
  default     = 10001
}

variable "vm_vendor_data" {
  description = "Cloud-init vendor data for VMs (written by the bootstrap): installs the QEMU guest agent."
  type        = string
  default     = "local:snippets/phoenix-vendor.yaml"
}
