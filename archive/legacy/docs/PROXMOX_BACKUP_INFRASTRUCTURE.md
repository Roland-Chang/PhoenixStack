# Proxmox Infrastructure-Wide Backup Strategy

**Purpose**: Automate daily backups and snapshots for all LXC containers

**Date Created**: 2026-07-29  
**Last Updated**: 2026-07-29  
**Status**: Active  
**Scope**: All LXC containers in PhoenixStack  

---

## Executive Summary

PhoenixStack implements a **centralized, scalable backup strategy** that:
- ✅ Automatically backs up all LXC containers daily
- ✅ Maintains per-service retention policies (7-14 days)
- ✅ Automatically cleans up old snapshots
- ✅ Scales dynamically as services are added/removed
- ✅ Provides single source of truth for backup configuration
- ✅ Generates detailed logs for monitoring/audit

**RTO/RPO**:
- **RTO**: 5-10 minutes (snapshot restore)
- **RPO**: 24 hours (daily snapshots)

---

## Architecture

### Component 1: Configuration File
**Location**: `/etc/proxmox-backups.conf`

Centralized list of all services and retention policies:
```
VMID:HOSTNAME:RETENTION_DAYS
105:proxy01:7
103:dns01:14
112:pgsql01:14
```

**When to update**:
- Adding new LXC container
- Removing decommissioned container
- Changing retention policy for a service

### Component 2: Backup Script
**Location**: `/usr/local/bin/backup-lxc.sh`

Generalized script that:
- Takes VMID, hostname, and retention days as parameters
- Creates dated snapshots: `hostname-daily-YYYYMMDD-HHMMSS`
- Automatically deletes snapshots older than retention period
- Generates per-service logs: `/var/log/proxmox-backup-{hostname}.log`

**Usage**:
```bash
/usr/local/bin/backup-lxc.sh 105 proxy01 7
```

### Component 3: Master Scheduler
**Location**: `/usr/local/bin/backup-scheduler.sh`

Orchestrates backups for all services:
- Reads `/etc/proxmox-backups.conf`
- Loops through each service
- Calls `backup-lxc.sh` for each VMID/hostname/retention combo
- Generates master log: `/var/log/proxmox-backup-scheduler.log`
- Exits with error if any backup fails (useful for monitoring)

**Execution**: Once daily via cron (typically 02:00 UTC)

---

## Storage Configuration

This section covers how to configure external NFS/CIFS storage on pve01 and expose it to LXC containers for backup storage.

### Overview

The recommended approach is to:
1. Mount NFS/CIFS shares on **pve01** (the Proxmox host) via `/etc/fstab`
2. Pass the mounted directory into the LXC container as a mountpoint
3. Inside the container, the mount point appears as a regular directory

This avoids permission/capability issues with unprivileged LXC containers trying to mount network shares directly.

### Prerequisites

- Access to pve01 (Proxmox host) as root or with sudo
- Backup server reachable from pve01 (e.g., 10.101.0.101 - UniFi UNAS Pro)
- NFS or CIFS configured on the backup server

### Setup Steps

#### Step 1: Install NFS utilities on pve01

```bash
# SSH to pve01
ssh root@pve01.phoenix.stack

# Install NFS client utilities
apt-get update
apt-get install -y nfs-common
```

#### Step 2: Create mount point directory on pve01

```bash
mkdir -p /mnt/backups-bastion01
```

#### Step 3: Add entry to /etc/fstab on pve01

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

#### Step 4: Mount the share on pve01

```bash
# Test the mount
mount /mnt/backups-bastion01

# Verify it mounted successfully
mount | grep backups-bastion01
df -h /mnt/backups-bastion01
```

#### Step 5: Add mountpoint to bastion01 LXC config on pve01

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

#### Step 6: Restart bastion01 container

```bash
pct restart 101
```

#### Step 7: Verify in bastion01

```bash
# SSH to bastion01
ssh root@bastion01.phoenix.stack

# Check the mount
mount | grep backups
ls -la /mnt/backups/
```

### Testing

Run the Ansible playbook to verify everything works:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/bastion01_full_setup.yml --vault-password-file ~/.vault_pass
```

The playbook will verify `/mnt/backups` is accessible and display a confirmation message.

### Storage Troubleshooting

#### Mount not appearing in LXC

- Verify the `mp0:` line is in the LXC config
- Check the host path exists and has correct permissions
- Restart the container: `pct restart 101`

#### NFS mount fails on pve01

```bash
# Check connectivity to backup server
ping 10.101.0.101

# Check if NFS service is available
showmount -e 10.101.0.101

# Manual mount with verbose output
mount -v -t nfs 10.101.0.101:/Backups/BASTION01 /mnt/backups-bastion01
```

#### CIFS mount fails on pve01

```bash
# Test credentials
smbclient -L //10.101.0.101 -U svc_automation

# Check credentials file
cat /root/.smb_credentials
ls -la /root/.smb_credentials  # Should be 0600
```

### Disabling Backup Mounts

If you don't need backup mounts, set in Ansible:

```yaml
backup_share_enabled: false
```

This will skip the mount verification in the playbook.

### Storage References

- [Proxmox LXC Mountpoints Documentation](https://pve.proxmox.com/wiki/Linux_Container#_mountpoints)
- [NFS Mount Options](https://linux.die.net/man/5/nfs)
- [CIFS Mount Options](https://linux.die.net/man/8/mount.cifs)

---

## Retention Policy

| Service Type | Retention | Rationale | Examples |
|---|---|---|---|
| **Critical** | 14 days | Essential infrastructure | dns01, dns02, pgsql01, pgsql02 |
| **Standard** | 7 days | Important services | proxy01, authentik01, bastion01 |

**Why these values?**
- 14 days: Covers most "oops" moments + weekly pattern (catches recurring issues)
- 7 days: Sufficient for homelab, balances storage vs. recovery window
- Daily rotation: Old snapshots auto-delete, freeing storage for new ones

---

## Installation & Setup

### Step 1: Copy Scripts to Proxmox Node

```bash
# On your Proxmox node
scp scripts/backup/backup-lxc.sh root@pve01:/usr/local/bin/
scp scripts/backup/backup-scheduler.sh root@pve01:/usr/local/bin/
scp scripts/backup/proxmox-backups.conf root@pve01:/etc/

# Make them executable
ssh root@pve01 "chmod +x /usr/local/bin/backup-lxc.sh /usr/local/bin/backup-scheduler.sh"
```

### Step 2: Verify Configuration

```bash
ssh root@pve01

# Check config file syntax
cat /etc/proxmox-backups.conf | grep -v '^#' | grep -v '^$'

# Expected output:
# 101:bastion01:7
# 102:bastion02:7
# 103:dns01:14
# ...
```

### Step 3: Test Backup Script Manually

```bash
# Test single backup
/usr/local/bin/backup-lxc.sh 105 proxy01 7

# View log
tail -20 /var/log/proxmox-backup-proxy01.log

# Expected: "✅ Snapshot created successfully"
```

### Step 4: Test Master Scheduler

```bash
# Run scheduler (dry run, will execute all backups)
/usr/local/bin/backup-scheduler.sh

# View master log
tail -50 /var/log/proxmox-backup-scheduler.log

# Expected: "✅ Backup succeeded for {each service}"
```

### Step 5: Schedule via Cron

```bash
# Edit root crontab
crontab -e

# Add this line (runs daily at 02:00 UTC):
0 2 * * * /usr/local/bin/backup-scheduler.sh >> /var/log/proxmox-backup-scheduler.log 2>&1

# Verify cron entry
crontab -l | grep backup-scheduler
```

### Step 6: Create Log Rotation (Optional but Recommended)

```bash
# Create logrotate config
cat > /etc/logrotate.d/proxmox-backups << 'EOF'
/var/log/proxmox-backup*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    missingok
    copytruncate
}
EOF
```

---

## Adding/Removing Services

### Add New Service

1. **Deploy container via Terraform** (creates new VMID)

2. **Update config file**:
   ```bash
   ssh root@pve01
   echo "120:amp01:7" >> /etc/proxmox-backups.conf
   ```

3. **Verify**:
   ```bash
   grep amp01 /etc/proxmox-backups.conf
   ```

4. **Next scheduled backup** will automatically include the new service

### Remove Service

1. **Decommission container** via Terraform

2. **Update config file**:
   ```bash
   ssh root@pve01
   sed -i '/amp01/d' /etc/proxmox-backups.conf
   ```

3. **Optional**: Manually delete remaining snapshots if needed
   ```bash
   qm listsnapshot VMID  # List snapshots
   qm delsnapshot VMID snapshot-name  # Delete if needed
   ```

---

## Monitoring & Health Checks

### Daily Status

```bash
# Check if scheduler ran successfully
ssh root@pve01 "tail -20 /var/log/proxmox-backup-scheduler.log"

# Expected output (end of log):
# [2026-07-29 02:15:32] [INFO] Master backup scheduler completed
# [2026-07-29 02:15:32] [INFO] Total: 13, Success: 13, Errors: 0
```

### Service-Specific Status

```bash
# Check backup for specific service
ssh root@pve01 "tail -20 /var/log/proxmox-backup-proxy01.log"
```

### Snapshot Inventory

```bash
# List all snapshots for a service
ssh root@pve01 "qm listsnapshot 105"

# Expected (7 daily snapshots rotating):
# Name                              | Created       | VMState | Size
# proxy01-daily-20260729-020000     | 2026-07-29... | no      | 256.0 MiB
# proxy01-daily-20260728-020000     | 2026-07-28... | no      | 256.0 MiB
# proxy01-daily-20260727-020000     | 2026-07-27... | no      | 256.0 MiB
# (etc., up to 7 total)
```

### Alert Conditions

Monitor for these issues:

- ⚠️ **WARNING**: Scheduler exits with error code (check `/var/log/proxmox-backup-scheduler.log`)
- ⚠️ **WARNING**: No new snapshots created in last 48 hours
- 🚨 **CRITICAL**: Storage pool > 90% full (snapshots use local storage)
- 🚨 **CRITICAL**: Log file grows beyond 10MB (indicates excessive errors)

---

## Recovery Procedures

### Restore from Snapshot (Fast)

If a service is corrupted or misconfigured:

```bash
ssh root@pve01

# List available snapshots for PROXY01 (VMID 105)
qm listsnapshot 105

# Choose recent snapshot
qm rollback 105 proxy01-daily-20260729-020000

# Boot the container
qm start 105

# Wait 30 seconds for services to start
sleep 30

# Verify
ssh root@10.101.0.31 "systemctl status traefik"
```

**Time to recover**: 5-10 minutes

### Restore from Config/Redeploy (If Snapshots Unavailable)

If all snapshots are corrupted:

```bash
# Destroy broken container
ssh root@pve01 "qm destroy 105 --force"

# Re-deploy via Terraform
cd terraform
terraform apply -target=module.proxy01

# Re-configure via Ansible
ansible-playbook -i ansible/inventory/hosts.yml \
  -l proxy01 \
  ansible/playbooks/site.yml
```

**Time to recover**: 20-30 minutes

---

## Testing & Validation

### Monthly Validation Checklist

```bash
# 1. Verify scheduler ran last night
tail -5 /var/log/proxmox-backup-scheduler.log

# 2. Check snapshot count for each service (should match retention days)
for vmid in 101 102 103 104 105 107 108 109 110 111 112 113; do
    echo "VMID $vmid:"
    qm listsnapshot $vmid | grep daily | wc -l
done

# 3. Spot-check a log file for errors
tail -50 /var/log/proxmox-backup-proxy01.log

# Document results:
# [ ] Scheduler ran successfully
# [ ] All services have expected snapshot count
# [ ] No error messages in logs
# Date: ___________
```

### Quarterly Recovery Test

Test that you can actually restore from a snapshot:

1. **Pick a non-critical service** (docker01, plex01)
2. **Simulate corruption**: Delete a config file or stop a service
3. **Practice restore**: Rollback from snapshot
4. **Verify recovery**: Confirm service recovers with full state
5. **Document**: Note any issues or improvements needed

---

## Logs & Troubleshooting

### Log Files

| Log | Location | Content |
|---|---|---|
| **Master log** | `/var/log/proxmox-backup-scheduler.log` | Overall backup orchestration |
| **Service logs** | `/var/log/proxmox-backup-{hostname}.log` | Per-service backup details |

### Common Issues

**Issue**: Scheduler exits with error
```bash
# Check master log
tail -50 /var/log/proxmox-backup-scheduler.log

# Common causes:
# - Config file syntax error
# - VMID doesn't exist
# - Storage pool full
# - Container offline
```

**Issue**: Only some backups succeeded
```bash
# Check service-specific log
tail -50 /var/log/proxmox-backup-dns01.log

# Likely causes:
# - Container is stopped
# - VMID wrong in config file
# - Storage pool full
```

**Issue**: Storage pool getting full
```bash
# Check storage usage
df -h /var/lib/vz

# If > 90% full:
# 1. Reduce retention period in /etc/proxmox-backups.conf
# 2. Manually delete old snapshots: qm delsnapshot VMID snapshot-name
# 3. Check for other large files consuming space
```

---

## Maintenance Schedule

| Task | Frequency | Owner | Notes |
|---|---|---|---|
| Verify scheduler ran | Daily | Automated alert | Check logs |
| Review retention policy | Quarterly | Infrastructure team | Adjust if needed |
| Recovery test | Quarterly | Infrastructure team | Practice restore procedure |
| Storage review | Monthly | Infrastructure team | Check pool usage |
| Log cleanup | Monthly | Logrotate (automated) | Keep last 30 days |

---

## Backup Configuration Reference

Current services and retention:

```
# Control Plane Tier (7 days)
101:bastion01:7
102:bastion02:7

# DNS/Edge Tier (14 days - critical)
103:dns01:14
104:dns02:14

# Proxy/Ingress Tier (7 days)
105:proxy01:7

# Identity/Auth Tier (7 days)
107:authentik01:7
108:authentik02:7

# Database Tier (14 days - critical)
112:pgsql01:14
113:pgsql02:14

# Compute/Workload Tier (7 days)
109:docker01:7
110:docker02:7

# Media Tier (7 days)
111:plex01:7
```

---

## Related Documentation

- [LXC_SERVICE_RECOVERY.md](LXC_SERVICE_RECOVERY.md) - Service recovery procedures for all LXC containers
- [HA_REDUNDANCY_STRATEGY.md](roadmap/HA_REDUNDANCY_STRATEGY.md) - HA strategy overview
- Proxmox CLI: `man pct` (LXC) or `man qm` (VMs)

---

## Document History

| Date | Change | Author |
|------|--------|--------|
| 2026-07-29 | Initial infrastructure-wide backup strategy | Infrastructure Team |
| | | |
| | | |
