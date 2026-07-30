# Proxmox Storage Pool Configuration

## Required Storage Pools

This Terraform configuration requires the following storage pools to be available in Proxmox:

### Primary Storage Pools

| Pool Name | Used By | Minimum Size | Type | Purpose |
|-----------|---------|--------------|------|---------|
| `ssd` | BASTION01, BASTION02, PROXY01, DNS01, DNS02, AUTHENTIK01, AUTHENTIK02, DOCKER01, DOCKER02, PLEX01 | 500GB+ | SSD/NVMe | General purpose container storage (must be SSD or LVM-thin) |

## Creating Storage Pools in Proxmox

### Option 1: Using Proxmox Web UI

1. Log into Proxmox (https://your-pve-ip:8006)
2. Navigate to **Datacenter** → **Storage**
3. Click **Add** and select your storage type:
   - **Directory** for local filesystem
   - **LVM** for LVM volumes
   - **ZFS** for ZFS pools
4. Configure the pool with appropriate size and mount point

### Option 2: Using Command Line (SSH to Proxmox node)

**Create LVM-based storage pool:**
```bash
# Create a new LVM logical volume
lvcreate -L 500G -n pve-containers pve

# Add it to Proxmox storage
pvesh create /storage -storage local-lvm -type lvmthin -content rootdir,images -volume pve:pve-containers
```

**Create directory-based storage pool:**
```bash
# Create directory
mkdir -p /mnt/storage/local
chmod 755 /mnt/storage/local

# Add to Proxmox
pvesh create /storage -storage local -type dir -content rootdir,images -path /mnt/storage/local
```

## Available Storage Pool Sizes

Check available storage in Proxmox:

```bash
# Via web UI: Datacenter → Storage → View storage usage

# Via SSH command:
pvesh get /nodes/pve01/storage
```

## Modifying Default Storage Pools

To use a different storage pool for specific containers, update the `variables.tf` file:

**Example: Use NVMe storage for AUTHENTIK01**

Edit `authentik01/variables.tf`:
```hcl
variable "storage_pool" {
  description = "Proxmox storage pool for container"
  type        = string
  default     = "nvme"  # Changed from "local"
}
```

## Troubleshooting Storage Errors

### Error: "storage 'local' does not exist"

**Cause:** The storage pool referenced doesn't exist in Proxmox

**Solution:**
1. Log into Proxmox web UI
2. Check **Datacenter** → **Storage** for available pools
3. Update `variables.tf` files to use an available pool
4. Verify pool names are correct (case-sensitive)

### Error: "storage pool full"

**Cause:** Not enough free space on storage pool

**Solution:**
1. Check storage usage: **Datacenter** → **Storage**
2. Increase storage pool size or remove unused containers
3. Verify `storage_size` in variables.tf doesn't exceed available space

## Storage Pool Recommendations

- **local**: Suitable for control plane (BASTION01/02) and identity services (AUTHENTIK01/02)
- **ssd**: Best for DNS services that require fast I/O
- **nvme**: Reserved for future high-performance services

## Current Terraform Configuration

All containers are configured to use the `ssd` storage pool, which must be LVM-thin or SSD-based.
The `local` pool is NOT suitable for containers as it doesn't support container directories.

**Configuration:**
```
BASTION01: ssd
BASTION02: ssd
DNS01: ssd
DNS02: ssd
PROXY01: ssd
AUTHENTIK01: ssd
AUTHENTIK02: ssd
DOCKER01: ssd
DOCKER02: ssd
PLEX01: ssd
```

### Storage Pool Type Requirements

**Important:** The storage pool MUST be one of these types:
- **LVM-thin** (Recommended) - Supports thin provisioning and snapshots
- **SSD/NVMe filesystem** - Direct mount for high performance
- **ZFS** - If configured

**NOT supported for containers:**
- **local** (directory-based storage) - "storage 'local' does not support container directories"

If using a local directory pool, you must convert it to LVM-thin or create an SSD pool.
