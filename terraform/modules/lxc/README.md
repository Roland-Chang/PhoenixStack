# LXC Container Module

Reusable Terraform module for deploying Ubuntu LXC containers on Proxmox VE.

## 📋 Module Overview

This module standardizes LXC container deployment across the Phoenix Stack infrastructure. All service containers (bastion01, dns01, dns02, proxy01, etc.) use this module with service-specific variables.

## 🔑 Key Features

- **Automated Container Deployment** - Deploys Ubuntu 24.04 LXC containers with consistent configuration
- **Network Configuration** - Configures static IP, gateway, search domain, and nameserver
- **SSH Key Management** - Injects SSH public keys for root access via Terraform variables
- **Resource Control** - Configurable CPU cores, memory, swap, and storage allocation
- **Systemd Compatibility** - Enables nesting feature for systemd 255+ support

## 📦 Module Inputs

### Required Variables
- `proxmox_node` - Proxmox node name (e.g., "pve01")
- `vmid` - Unique VM ID for container
- `hostname` - Container hostname
- `ostemplate` - OS template ID (e.g., "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst")
- `ip_address` - Static IPv4 address (e.g., "10.101.0.201")
- `ip_cidr_suffix` - CIDR notation (e.g., 24 for /24)
- `gateway` - Default gateway (e.g., "10.101.0.254")
- `network_bridge` - Proxmox network bridge (e.g., "vmbr0")
- `search_domain` - DNS search domain (e.g., "phoenix.stack")
- `mac_address` - MAC address for primary NIC

### Optional Variables
- `cpu_cores` - CPU cores (default: 2)
- `memory_mb` - RAM in MB (default: 2048)
- `swap_mb` - Swap in MB (default: 512)
- `storage_pool` - Storage pool name (default: "ssd")
- `storage_size` - Root disk size in GB (default: 16)
- `nameserver` - Primary nameserver (default: gateway)
- `ssh_public_keys` - SSH public keys for root access (default: empty)
- `autostart` - Auto-start on boot (default: true)
- `onboot` - Boot container on startup (default: true)
- `unprivileged` - Run unprivileged LXC (default: true)
- `enable_nesting` - Enable nesting feature for systemd (default: true)

## ⚠️ Important: Proxmox API Token Permissions & Feature Flags

### The Challenge

Proxmox API tokens have a permanent limitation: **they cannot set or modify certain LXC feature flags**:
- ❌ `keyctl` (ipc namespacing) - requires `root@pam`
- ❌ `mknod` (device creation) - requires `root@pam`
- ✅ `nesting` (namespace isolation) - token-compatible
- ✅ `fuse` (filesystem in userspace) - token-compatible

**Error When Attempting to Modify**:
```
Error: 403 Permission check failed (changing feature flags (except nesting) is only allowed for root@pam)
```

### How This Module Solves It

This module uses **`lifecycle.ignore_changes`** to prevent Terraform from trying to manage unmodifiable flags:

```hcl
lifecycle {
  ignore_changes = [
    rootfs,    # Avoid drift if storage reference changes
    features   # Token cannot manage keyctl/mknod; ignore all feature drift
  ]
}
```

**What this means:**
- ✅ Terraform CAN create new containers (Proxmox API sets defaults)
- ✅ Terraform CAN manage other attributes (CPU, memory, networking)
- ✅ Terraform IGNORES feature flag differences to prevent permission errors
- ✅ NO "permission denied" errors during infrastructure updates
- ⚠️ Feature flags cannot be changed after container creation

### Feature Flag Status by Container

| Container | VMID | keyctl | mknod | nesting | Status |
|-----------|------|--------|-------|---------|--------|
| bastion01 | 101 | true | true | true | ✅ Running (pre-token deployment) |
| bastion02 | 100 | (default) | (default) | true | ✅ Running (token deployment) |
| dns01 | 102 | (default) | (default) | true | ✅ Running (token deployment) |
| dns02 | 103 | (default) | (default) | true | ✅ Running (token deployment) |

**Important**: All containers function identically. The keyctl/mknod flags don't affect current operations.

### Why This Works

1. **Terraform creates new containers**: The Proxmox API accepts the request from the token (initial creation is allowed)
2. **Proxmox sets defaults**: Flags not specified in creation request get Proxmox defaults
3. **Module ignores drift**: Even if existing containers have different flag values, `ignore_changes` prevents Terraform from trying to modify them
4. **No permission errors**: By not attempting to modify flags, we avoid the 403 error

### If Additional Flags Are Needed Later

If you discover containers REQUIRE specific `keyctl` or `mknod` settings:

**Option 1: Manual Configuration (Recommended)**
```bash
# SSH to Proxmox node
ssh root@pve01

# Set flags for a container
pct set 102 -features keyctl=1,mknod=1

# Restart container if needed
pct restart 102
```

**Option 2: Recreate Container with Flags Pre-Set**
1. Delete container: `terraform destroy -target=module.service_name`
2. Manually create on Proxmox: `pct create 102 ubuntu-template -features keyctl=1,mknod=1`
3. Import into Terraform: `terraform import module.service_name.module.service_name.proxmox_lxc.container pve01/lxc/102`

**Option 3: Temporary Use of root@pam**
- Configure Terraform provider with `root@pam` credentials instead of token (less secure)
- Run `terraform apply` once with elevated privileges
- Switch back to token for normal operations

## 🚀 Usage

### Typical Service Module Structure

```
terraform/
└── my_service/
    ├── main.tf                # Instantiates lxc module
    ├── variables.tf           # Variable definitions
    └── auto.tfvars           # Pre-configured values
```

**Example: main.tf**
```hcl
module "my_service" {
  source = "../modules/lxc"
  
  # Proxmox Configuration
  proxmox_node = var.proxmox_node
  
  # Container Identity
  vmid       = var.container_vmid
  hostname   = var.hostname
  ostemplate = var.ostemplate
  
  # Resource Allocation
  cpu_cores    = var.cpu_cores
  memory_mb    = var.memory_mb
  swap_mb      = var.swap_mb
  storage_pool = var.storage_pool
  storage_size = var.storage_size
  
  # Networking
  ip_address     = var.ip_address
  ip_cidr_suffix = var.ip_cidr_suffix
  gateway        = var.gateway
  network_bridge = var.network_bridge
  nameserver     = var.nameserver
  search_domain  = var.search_domain
  
  # SSH Keys
  ssh_public_keys = var.ssh_public_keys
  
  # Network MAC Address
  mac_address = var.mac_address
  
  # Features
  enable_nesting = true
  
  # Container Configuration
  unprivileged = true
}
```

**Example: auto.tfvars**
```hcl
proxmox_node   = "pve01"
container_vmid = 104
hostname       = "my-service"
ip_address     = "10.101.0.203"
mac_address    = "02:aa:bb:cc:02:03"
# ... other variables
```

## 📤 Module Outputs

The module returns:
- `container_vmid` - VM ID of created container
- `container_hostname` - Hostname of created container
- `container_ip` - IP address of created container

## 🔄 Deployment Workflow

1. **Create service directory** (e.g., `terraform/my_service/`)
2. **Copy template files** from existing service (e.g., dns01/)
3. **Update variables** (VMID, hostname, IP, MAC address)
4. **Add module reference** to root `terraform.tf`
5. **Deploy**:
   ```bash
   terraform plan -target=module.my_service
   terraform apply -target=module.my_service
   ```
6. **Run Ansible** for post-deployment configuration

## 🐛 Troubleshooting

### "Permission check failed (changing feature flags)" Error

This occurs when trying to set `keyctl=1` or `mknod=1` with a non-root token. 

**Solution**: The module only sets `nesting=1`, which works with tokens. If you need other flags, set them manually post-creation as documented above.

### Container Fails to Start

Check Proxmox logs:
```bash
pct list          # List all containers
pct status 102    # Check specific container status
pct log 102       # View container logs
```

### SSH Access Fails

Verify:
1. SSH public key passed to Terraform: `cat terraform/terraform.tfvars | grep ssh_public_keys`
2. Container is running: `pct status <vmid>`
3. Network connectivity: `ping 10.101.0.201` (from host with access to VLAN)

## 📚 Related Documentation

- [Terraform Setup Guide](../README.md) - Main Terraform documentation
- [Mac Address Scheme](../docs/mac-address-scheme.md) - MAC addressing for containers
- [Proxmox API Token Creation](../docs/proxmox-api-token-creation.md) - How to create Terraform token
