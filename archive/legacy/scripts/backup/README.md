# Proxmox Backup Scripts

**Purpose**: Automated, scalable backup infrastructure for all PhoenixStack LXC containers

**Last Updated**: 2026-07-29

---

## Quick Start

### 1. Deploy to Proxmox Node

Copy scripts and configuration to Proxmox node (pve01):

```bash
# From your workstation with repo cloned
scp scripts/backup/backup-lxc.sh root@pve01:/usr/local/bin/
scp scripts/backup/backup-scheduler.sh root@pve01:/usr/local/bin/
scp scripts/backup/proxmox-backups.conf root@pve01:/etc/

# Make executable
ssh root@pve01 "chmod +x /usr/local/bin/backup-lxc.sh /usr/local/bin/backup-scheduler.sh"
```

### 2. Test Backups

```bash
# Manual test (backs up proxy01)
ssh root@pve01 "/usr/local/bin/backup-lxc.sh 105 proxy01 7"

# Test full scheduler
ssh root@pve01 "/usr/local/bin/backup-scheduler.sh"
```

### 3. Schedule via Cron

```bash
ssh root@pve01 "crontab -e"

# Add line (runs daily at 02:00 UTC):
0 2 * * * /usr/local/bin/backup-scheduler.sh >> /var/log/proxmox-backup-scheduler.log 2>&1
```

---

## Files

### `proxmox-backups.conf`
Centralized configuration file listing all services and retention policies.

**Format**: `VMID:HOSTNAME:RETENTION_DAYS`

**Example**:
```
# Control Plane
101:bastion01:7
102:bastion02:7

# Critical Services (14 days)
103:dns01:14
104:dns02:14
112:pgsql01:14
113:pgsql02:14

# Standard Services (7 days)
105:proxy01:7
107:authentik01:7
```

**When to update**:
- Adding new LXC container
- Removing container
- Changing retention policy

---

### `backup-lxc.sh`
Generalized backup script for a single LXC container.

**Usage**: `backup-lxc.sh <VMID> <HOSTNAME> <RETENTION_DAYS>`

**Example**:
```bash
/usr/local/bin/backup-lxc.sh 105 proxy01 7
```

**What it does**:
1. Creates daily snapshot: `proxy01-daily-20260729-020000`
2. Deletes snapshots older than retention period
3. Logs to: `/var/log/proxmox-backup-proxy01.log`

**Parameters**:
- `VMID`: Proxmox container ID (numeric, e.g., 105)
- `HOSTNAME`: Container hostname for naming snapshots (e.g., proxy01)
- `RETENTION_DAYS`: How many days to keep snapshots (7 or 14)

---

### `backup-scheduler.sh`
Master orchestrator that runs all backups daily.

**Usage**: `/usr/local/bin/backup-scheduler.sh`

**What it does**:
1. Reads `/etc/proxmox-backups.conf`
2. Loops through each service
3. Calls `backup-lxc.sh` for each VMID/hostname/retention combo
4. Logs to: `/var/log/proxmox-backup-scheduler.log`
5. Exits with error if any backup fails

**Execution**: Runs once daily via cron (typically 02:00 UTC)

---

## Retention Policy

| Service Type | Retention | Examples |
|---|---|---|
| **Critical** | 14 days | dns01, dns02, pgsql01, pgsql02 |
| **Standard** | 7 days | proxy01, authentik01, bastion01, docker01, plex01 |

---

## Monitoring

### Check Last Backup

```bash
ssh root@pve01 "tail -20 /var/log/proxmox-backup-scheduler.log"

# Expected (successful):
# [2026-07-29 02:15:32] [INFO] Master backup scheduler completed
# [2026-07-29 02:15:32] [INFO] Total: 13, Success: 13, Errors: 0
```

### Check Snapshots

```bash
ssh root@pve01 "qm listsnapshot 105"

# Should show 7 daily snapshots (rotating):
# proxy01-daily-20260729-020000
# proxy01-daily-20260728-020000
# proxy01-daily-20260727-020000
# (etc.)
```

### Storage Usage

```bash
ssh root@pve01 "df -h /var/lib/vz"

# Should show storage pool usage
# Alarm if > 90% full
```

---

## Adding a New Service

When deploying a new LXC container:

1. **Deploy via Terraform** (creates new VMID)

2. **Update config file**:
   ```bash
   ssh root@pve01
   echo "120:amp01:7" >> /etc/proxmox-backups.conf
   ```

3. **Verify**:
   ```bash
   grep amp01 /etc/proxmox-backups.conf
   ```

4. **Next scheduled backup** (at 02:00 UTC) will automatically include it

---

## Removing a Service

When decommissioning a container:

1. **Remove from Terraform** (destroys container)

2. **Update config file**:
   ```bash
   ssh root@pve01
   sed -i '/amp01/d' /etc/proxmox-backups.conf
   ```

3. **Optional - Clean up snapshots**:
   ```bash
   qm listsnapshot VMID  # List snapshots
   qm delsnapshot VMID snapshot-name  # Delete if needed
   ```

---

## Recovery

### Quick Restore (From Snapshot)

```bash
ssh root@pve01

# List snapshots
qm listsnapshot 105

# Restore from snapshot
qm rollback 105 proxy01-daily-20260729-020000

# Boot container
qm start 105

# Wait 30 seconds, then verify
ssh root@10.101.0.31 "systemctl status traefik"
```

**Recovery time**: 5-10 minutes

### Full Redeploy (If Snapshots Lost)

```bash
# Destroy broken container
ssh root@pve01 "qm destroy 105 --force"

# Redeploy via Terraform
cd terraform
terraform apply -target=module.proxy01

# Reconfigure via Ansible
ansible-playbook -i ansible/inventory/hosts.yml -l proxy01 ansible/playbooks/site.yml
```

**Recovery time**: 20-30 minutes

---

## Documentation

For complete details, see [PROXMOX_BACKUP_INFRASTRUCTURE.md](../../docs/PROXMOX_BACKUP_INFRASTRUCTURE.md)

---

## Troubleshooting

### Scheduler didn't run

```bash
# Check cron is configured
ssh root@pve01 "crontab -l | grep backup-scheduler"

# Check if service had errors
ssh root@pve01 "tail -50 /var/log/proxmox-backup-scheduler.log"
```

### Storage pool full

```bash
# Check usage
ssh root@pve01 "df -h /var/lib/vz"

# If > 90% full:
# 1. Reduce retention in proxmox-backups.conf
# 2. Manually delete old snapshots: qm delsnapshot VMID snapshot-name
```

### Service-specific backup failed

```bash
# Check service log
ssh root@pve01 "tail -50 /var/log/proxmox-backup-proxy01.log"

# Common causes:
# - Container offline
# - VMID wrong in config
# - Storage full
```

---

## SLA/Service Levels

| Metric | Value |
|---|---|
| **Backup Frequency** | Daily (02:00 UTC) |
| **Retention** | 7-14 days (per service) |
| **RTO** | 5-10 min (snapshot) or 20-30 min (full redeploy) |
| **RPO** | 24 hours (daily snapshots) |
| **Acceptable for** | Homelab, non-critical services |

---

## Related Documentation

- [PROXMOX_BACKUP_INFRASTRUCTURE.md](../../docs/PROXMOX_BACKUP_INFRASTRUCTURE.md) - Complete backup strategy
- [LXC_SERVICE_RECOVERY.md](../../docs/LXC_SERVICE_RECOVERY.md) - Service recovery procedures for all LXC containers
- [HA_REDUNDANCY_STRATEGY.md](../../docs/roadmap/HA_REDUNDANCY_STRATEGY.md) - HA strategy overview
