# PVE01 Storage Mount Configuration (fstab)

Updated fstab configuration for Phoenix Stack file server integration with per-LXC backup isolation.

## Architecture Overview

**Before (Legacy):**
- PVE01 mounts `/Backups/pve01`
- All containers access through PVE01's mount (backups mixed in single folder)

**After (Current):**
- PVE01 mounts `/Backups/pve01` for hypervisor backups
- PVE01 mounts `/Software/ISO` for deployment ISOs
- **Each container mounts its own** `/Backups/{{ HOSTNAME }}` directly
- Containers handle their own mount points (via Ansible base_config role)

## PVE01 Updated fstab

Replace the entire `/etc/fstab` file with:

```bash
# Proxmox Mount Point Configuration
# File server: 10.101.0.101

# Local storage (system root filesystem)
/dev/pve/root / ext4 errors=remount-ro 0 1
/dev/pve/swap none swap sw 0 0

# EFI partition (if exists)
# /dev/sda2 /boot/efi vfat defaults 0 0

# ============================================================================
# SMB/CIFS Mounts - File Server (10.101.0.101)
# ============================================================================

# Proxmox hypervisor backups
# Credentials: /root/.smbcredentials (ensure this file exists with SMB username/password)
//10.101.0.101/Backups/pve01 /mnt/pve/cifs-backups cifs _netdev,x-systemd.automount,noatime,uid=100000,gid=101000,dir_mode=0770,file_mode=0770,credentials=/root/.smbcredentials 0 0

# ISOs for container/VM deployment
//10.101.0.101/Software/ISO /mnt/pve/cifs-iso cifs _netdev,x-systemd.automount,noatime,uid=100000,gid=101000,dir_mode=0770,file_mode=0770,credentials=/root/.smbcredentials 0 0
```

## Deployment Instructions

### Option 1: Manual SSH Update

```bash
# SSH into PVE01
ssh root@10.101.0.11

# Edit fstab
nano /etc/fstab
# Delete Media, Nextcloud, Projects lines
# Keep only Backups/pve01 and Software/ISO
# Save and exit (Ctrl+X, Y, Enter in nano)

# Unmount old shares
umount /mnt/pve/cifs-media 2>/dev/null || true
umount /mnt/pve/cifs-nextcloud 2>/dev/null || true
umount /mnt/pve/cifs-projects 2>/dev/null || true

# Remount new shares
mount -a

# Verify
mount | grep cifs
```

### Option 2: Automated SSH Command

```bash
# From your local machine
ssh -i ~/.ssh/id_rsa root@10.101.0.11 "cat > /etc/fstab << 'EOF'
# Proxmox Mount Point Configuration - Phoenix Stack
# File server: 10.101.0.101

/dev/pve/root / ext4 errors=remount-ro 0 1
/dev/pve/swap none swap sw 0 0

# SMB/CIFS Mounts
//10.101.0.101/Backups/pve01 /mnt/pve/cifs-backups cifs _netdev,x-systemd.automount,noatime,uid=100000,gid=101000,dir_mode=0770,file_mode=0770,credentials=/root/.smbcredentials 0 0
//10.101.0.101/Software/ISO /mnt/pve/cifs-iso cifs _netdev,x-systemd.automount,noatime,uid=100000,gid=101000,dir_mode=0770,file_mode=0770,credentials=/root/.smbcredentials 0 0
EOF
"

# Unmount old shares and remount
ssh -i ~/.ssh/id_rsa root@10.101.0.11 "umount /mnt/pve/cifs-* 2>/dev/null || true; mount -a"

# Verify
ssh -i ~/.ssh/id_rsa root@10.101.0.11 "mount | grep cifs"
```

### Option 3: Add to Bootstrap Script

If adding this to your Proxmox provisioning workflow, add this section:

```bash
# ============================================================================
# Configure SMB/CIFS mounts for file server access
# ============================================================================
log_info "Configuring file server mounts (SMB/CIFS)..."

# Update fstab with Phoenix Stack mounts
cat > /etc/fstab << 'EOF'
# Proxmox filesystem
/dev/pve/root / ext4 errors=remount-ro 0 1
/dev/pve/swap none swap sw 0 0

# SMB/CIFS Mounts - File Server (10.101.0.101)
# Credentials required: /root/.smbcredentials with format:
#   username=<smbuser>
#   password=<smbpass>

# PVE01 hypervisor backups
//10.101.0.101/Backups/pve01 /mnt/pve/cifs-backups cifs _netdev,x-systemd.automount,noatime,uid=100000,gid=101000,dir_mode=0770,file_mode=0770,credentials=/root/.smbcredentials 0 0

# ISO libraries for deployment
//10.101.0.101/Software/ISO /mnt/pve/cifs-iso cifs _netdev,x-systemd.automount,noatime,uid=100000,gid=101000,dir_mode=0770,file_mode=0770,credentials=/root/.smbcredentials 0 0
EOF

# Ensure SMB credentials file exists
if [ ! -f /root/.smbcredentials ]; then
    log_warn "SMB credentials file missing: /root/.smbcredentials"
    log_warn "Create with: cat > /root/.smbcredentials << 'CREDS'"
    log_warn "username=<username>"
    log_warn "password=<password>"
    log_warn "CREDS"
    log_warn "chmod 600 /root/.smbcredentials"
else
    chmod 600 /root/.smbcredentials
fi

# Install cifs-utils if not present
apt-get install -y cifs-utils

# Create mount directories
mkdir -p /mnt/pve/cifs-backups
mkdir -p /mnt/pve/cifs-iso

# Remount all shares
mount -a

log_success "File server mounts configured"
```

## Important Notes

### SMB Credentials File
The fstab entries reference `/root/.smbcredentials`. Ensure this file exists:

```bash
cat > /root/.smbcredentials << 'EOF'
username=your_smb_username
password=your_smb_password
EOF

chmod 600 /root/.smbcredentials
```

### Mount Options Explained
- `_netdev`: Mount after network is available
- `x-systemd.automount`: Lazy-mount on access (prevents boot delays if file server is unavailable)
- `noatime`: Don't update access time (performance)
- `uid=100000,gid=101000`: Unprivileged container ownership (required for LXC)
- `dir_mode=0770,file_mode=0770`: Directory and file permissions
- `credentials=/root/.smbcredentials`: Path to SMB credentials file

### Verification

After applying changes:

```bash
# Check mounts
mount | grep cifs

# Test access
ls -la /mnt/pve/cifs-backups/
ls -la /mnt/pve/cifs-iso/

# Verify systemd automount (should show "automount")
systemctl status mnt-pve-cifs*.automount
```

## Container Backup Mount Architecture

Each container (bastion01, dns01, proxy01, etc.) will independently mount:
- Source: `//10.101.0.101/Backups/{{ HOSTNAME | upper }}`
- Mount point: `/mnt/backups`
- Configured by: `ansible/roles/base_config/tasks/main.yml`
- Credentials from: `ansible/vault/backup_credentials.yml`

**Result:**
- `bastion01` → `//10.101.0.101/Backups/BASTION01` at `/mnt/backups`
- `dns01` → `//10.101.0.101/Backups/DNS01` at `/mnt/backups`
- `proxy01` → `//10.101.0.101/Backups/PROXY01` at `/mnt/backups`
- etc.

Each container has isolated backup storage with no risk of mixing directories.
