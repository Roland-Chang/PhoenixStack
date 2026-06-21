# Backup Share Setup for LXC Containers (via pve01)

This guide explains how to mount backup shares on pve01 (Proxmox host) and pass them through to LXC containers like bastion01.

## Overview

The recommended approach is to:
1. Mount NFS/CIFS shares on **pve01** (the Proxmox host) via `/etc/fstab`
2. Pass the mounted directory into the LXC container as a mountpoint
3. Inside the container, the mount point appears as a regular directory

This avoids permission/capability issues with unprivileged LXC containers trying to mount network shares directly.

## Prerequisites

- Access to pve01 (Proxmox host) as root or with sudo
- Backup server reachable from pve01 (e.g., 10.101.0.101 - UniFi UNAS Pro)
- NFS or CIFS configured on the backup server

## Setup Steps

### Step 1: Install NFS utilities on pve01

```bash
# SSH to pve01
ssh root@pve01.phoenix.stack

# Install NFS client utilities
apt-get update
apt-get install -y nfs-common
```

### Step 2: Create mount point directory on pve01

```bash
mkdir -p /mnt/backups-bastion01
```

### Step 3: Add entry to /etc/fstab on pve01

Edit `/etc/fstab` and add:

```bash
# For NFSv3 (recommended for UniFi UNAS Pro)
10.101.0.101:/Backups/BASTION01 /mnt/backups-bastion01 nfs soft,timeo=30,retrans=3 0 0

# Alternative: For SMB/CIFS (if NFS is not available)
# //10.101.0.101/Backups/BASTION01 /mnt/backups-bastion01 cifs credentials=/root/.smb_credentials,uid=0,gid=0,file_mode=0755,dir_mode=0755 0 0
```

**For CIFS**, also create the credentials file:
```bash
cat > /root/.smb_credentials << EOF
username=svc_automation
password=YOUR_PASSWORD_HERE
EOF
chmod 600 /root/.smb_credentials
```

### Step 4: Mount the share on pve01

```bash
# Test the mount
mount /mnt/backups-bastion01

# Verify it mounted successfully
mount | grep backups-bastion01
df -h /mnt/backups-bastion01
```

### Step 5: Add mountpoint to bastion01 LXC config on pve01

Edit the bastion01 LXC config file: `/etc/pve/lxc/101.conf`

Add this line (use the next available `mp` number):

```
mp0: /mnt/backups-bastion01,mp=/mnt/backups
```

Example of updated config:
```
arch: amd64
cmode: tty
console: 1
cores: 2
cpulimit: 0
cpuunits: 1024
features: nesting=1,keyctl=1,mknod=1
hostname: bastion01
memory: 4096
mp0: /mnt/backups-bastion01,mp=/mnt/backups
nameserver: 10.101.0.254
net0: name=eth0,bridge=vmbr0,gw=10.101.0.254,hwaddr=02:aa:bb:cc:01:01,ip=10.101.0.20/24,type=veth
onboot: 1
ostype: ubuntu
protection: 0
rootfs: ssd:subvol-101-disk-0,size=16G
searchdomain: phoenix.stack
swap: 1024
tty: 2
unprivileged: 1
```

### Step 6: Restart bastion01 container

```bash
pct restart 101
```

### Step 7: Verify in bastion01

```bash
# SSH to bastion01
ssh root@bastion01.phoenix.stack

# Check the mount
mount | grep backups
ls -la /mnt/backups/
```

## Testing

Run the Ansible playbook to verify everything works:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/bastion01_full_setup.yml --vault-password-file ~/.vault_pass
```

The playbook will verify `/mnt/backups` is accessible and display a confirmation message.

## Troubleshooting

### Mount not appearing in LXC

- Verify the `mp0:` line is in the LXC config
- Check the host path exists and has correct permissions
- Restart the container: `pct restart 101`

### NFS mount fails on pve01

```bash
# Check connectivity to backup server
ping 10.101.0.101

# Check if NFS service is available
showmount -e 10.101.0.101

# Manual mount with verbose output
mount -v -t nfs 10.101.0.101:/Backups/BASTION01 /mnt/backups-bastion01
```

### CIFS mount fails on pve01

```bash
# Test credentials
smbclient -L //10.101.0.101 -U svc_automation

# Check credentials file
cat /root/.smb_credentials
ls -la /root/.smb_credentials  # Should be 0600
```

## Disabling Backup Mounts

If you don't need backup mounts, set in Ansible:

```yaml
backup_share_enabled: false
```

This will skip the mount verification in the playbook.

## References

- [Proxmox LXC Mountpoints Documentation](https://pve.proxmox.com/wiki/Linux_Container#_mountpoints)
- [NFS Mount Options](https://linux.die.net/man/5/nfs)
- [CIFS Mount Options](https://linux.die.net/man/8/mount.cifs)
