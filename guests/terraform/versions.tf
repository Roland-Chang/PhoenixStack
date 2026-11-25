terraform {
  required_version = "~> 1.16"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # Exact pin; released 2026-11-02. Raise it deliberately, after reading the changelog.
      version = "= 0.120.0"
    }
  }
}

# The API token comes from the environment (PROXMOX_VE_API_TOKEN), set by ../tf.sh from
# 1Password. No SSH: the provider can do only what the token allows.
provider "proxmox" {
  endpoint = "https://pve01.int.phoenixstack.net:8006/"
  insecure = false
}
