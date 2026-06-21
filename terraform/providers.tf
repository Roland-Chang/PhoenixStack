# Proxmox Provider Variables
# These are required for authentication to the Proxmox API
# Values are loaded from terraform.tfvars or environment variables

variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID (format: user@realm!tokenname)"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret/password"
  type        = string
  sensitive   = true
}
