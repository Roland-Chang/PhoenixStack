# LXC Service Backup & Recovery Guide

**Date Created**: 2026-07-29  
**Last Updated**: 2026-07-29  
**Status**: Operational Template  
**Scope**: All PhoenixStack LXC containers (bastion, dns, docker, postgres, proxy, vault, etc.)  

---

## Executive Summary

This document provides **service-agnostic recovery procedures** for any LXC container in PhoenixStack infrastructure. All examples use **PROXY01** as the reference service, but procedures apply to **any deployed container**.

**Key Recovery Strategies**:
- **Backup Strategy**: Daily Proxmox snapshots + weekly full backups (automated)
- **Recovery Options**: Service restart (~2 min), snapshot rollback (~5 min), or IaC re-deploy (~20 min)
- **RTO**: 30 minutes acceptable for homelab services
- **RPO**: 24 hours (daily snapshot/backup cycle)

**Applies To**: bastion01/02, dns01/02, docker01/02, pgsql01/02, proxy01, authentik01, vault01/02, amp01, plex01, and future services

---

## How to Use This Guide

### Adapting for Your Service

**Throughout this document, replace these values**:

| Placeholder | Example (PROXY01) | Your Service |
|-------------|-------------------|--------------|
| **VMID** | 105 | Find in Proxmox UI or `terraform/terraform.tf` |
| **Service Name** | proxy01 | bastion01, dns01, docker01, etc. |
| **IP Address** | 10.101.0.31 | Check `ansible/inventory/hosts.yml` |
| **Primary Service** | traefik | pihole, docker, postgresql, etc. |
| **Service Command** | `systemctl restart traefik` | `systemctl restart <your-service>` |
| **Config Path** | `ansible/roles/proxy/` | `ansible/roles/<your-role>/` |

**Quick Lookup Table** (Current Infrastructure):

| Service | VMID | IP Address | Primary Service | Ansible Role |
|---------|------|------------|-----------------|--------------|
| bastion01 | 10101 | 10.101.0.20 | github-runner | bastion |
| bastion02 | 10102 | 10.101.0.21 | github-runner | bastion |
| dns01 | 10201 | 10.101.0.201 | pihole-FTL | pihole |
| dns02 | 10202 | 10.101.0.202 | pihole-FTL | pihole |
| docker01 | 11001 | 10.101.0.51 | docker | docker |
| docker02 | 11002 | 10.101.0.52 | docker | docker |
| pgsql01 | 10701 | 10.101.0.71 | postgresql | postgres |
| pgsql02 | 10702 | 10.101.0.72 | postgresql | postgres |
| proxy01 | 10301 | 10.101.0.31 | traefik | proxy |

*For future services, check terraform/terraform.tf for VMID and ansible/inventory/hosts.yml for IP*

---

## Backup Architecture

All PhoenixStack LXC containers follow the same backup pattern:

```
Daily Backup Cycle (Automated):
├─ Managed by: /usr/local/bin/backup-scheduler.sh
├─ Configuration: /etc/proxmox-backups.conf
├─ Frequency: Daily snapshots at 02:00 UTC
└─ Retention: Keep 7 daily snapshots + 4 weekly backups
```

**See [PROXMOX_BACKUP_INFRASTRUCTURE.md](PROXMOX_BACKUP_INFRASTRUCTURE.md)** for complete backup system documentation.

### Storage Locations

| Type | Location | Retention | Purpose |
|------|----------|-----------|---------|
| **Snapshots** | Proxmox local storage | 7 days | Fast restore via rollback |
| **Full Backups** | External storage (UNAS01 NFS/CIFS) | 4 weeks | Archive for older recovery points |
| **Configuration Backups** | Git repository (Roland-Chang/PhoenixStack) | Unlimited | Version control of all configs |

---

## Part 1: Proxmox Snapshot Operations

### 1.1 Manual Snapshot (Ad-hoc)

Create a snapshot before making changes to **any service**:

```bash
# SSH to Proxmox node
ssh root@pve01.phoenix.stack

# Create snapshot (replace VMID and service name)
pct snapshot <VMID> <service-name>-backup-$(date +%Y%m%d-%H%M%S)

# Example for PROXY01 (VMID 105):
pct snapshot 105 proxy01-backup-$(date +%Y%m%d-%H%M%S)

# Example for DNS01 (VMID 201):
pct snapshot 201 dns01-backup-$(date +%Y%m%d-%H%M%S)

# List snapshots for a container
pct listsnapshot <VMID>

# Delete old snapshot (if needed)
pct delsnapshot <VMID> <snapshot-name>
```

### 1.2 Automated Daily Snapshots

**All deployed services are already covered by automated backups** via:
- **Backup Scheduler**: `/usr/local/bin/backup-scheduler.sh`
- **Configuration**: `/etc/proxmox-backups.conf`
- **Service Script**: `/usr/local/bin/backup-lxc.sh`

To add a new service to automated backups:

```bash
# SSH to Proxmox node
ssh root@pve01.phoenix.stack

# Edit backup configuration
vim /etc/proxmox-backups.conf

# Add your service to the appropriate section:
# [service_name]
# vmid = <VMID>
# snapshot_prefix = <service-name>-daily
# retention_days = 7

# Test the backup for your new service
/usr/local/bin/backup-lxc.sh <VMID> <service-name>-daily 7

# Verify snapshot was created
pct listsnapshot <VMID>
```

**See [PROXMOX_BACKUP_INFRASTRUCTURE.md](PROXMOX_BACKUP_INFRASTRUCTURE.md)** for details on adding/removing services.

---

## Part 2: Configuration Backups (Git-based)

### 2.1 Service Configuration Versioning

**All service configurations are version-controlled in git**:

```bash
# Ansible configuration locations
ansible/roles/<role-name>/files/          # Static config files
ansible/roles/<role-name>/templates/      # Jinja2 templates
ansible/roles/<role-name>/tasks/          # Playbook tasks
ansible/roles/<role-name>/defaults/       # Default variables

# Examples:
ansible/roles/proxy/files/traefik.yml           # Traefik config
ansible/roles/pihole/defaults/dns-records.yml   # DNS records
ansible/roles/github_runner/defaults/           # Runner settings
ansible/roles/postgres/files/postgresql.conf    # PostgreSQL config
```

### 2.2 Document Configuration Changes

**Standard workflow for any service configuration change**:

```bash
# 1. Make the change in ansible/roles/<role>/
# 2. Test in dry-run mode
ansible-playbook -i ansible/inventory/hosts.yml \
  -l <service-name> \
  --check \
  ansible/playbooks/site.yml

# 3. Apply the change
ansible-playbook -i ansible/inventory/hosts.yml \
  -l <service-name> \
  ansible/playbooks/site.yml

# 4. Commit to git
git add ansible/roles/<role>/
git commit -m "Update <service>: <description of change>"
git push origin main
```

---

## Part 3: Recovery Procedures

### 3.1 Scenario: Service Process Crashed (Container Running)

**Symptoms**:
- Service process not responding
- SSH to container **works**
- Container shows as running in Proxmox

**Recovery (Fast Service Restart)**:

```bash
# SSH to the service container (use your service's IP)
ssh root@<service-ip>

# Restart the primary service
systemctl restart <service-name>

# Verify it's running
systemctl status <service-name>

# Wait for startup
sleep 10

# Test service health
# (use appropriate health check for your service)
```

**Examples**:

```bash
# PROXY01 (Traefik)
ssh root@10.101.0.31
systemctl restart traefik
curl http://localhost:8080/ping

# DNS01 (PiHole)
ssh root@10.101.0.201
systemctl restart pihole-FTL
pihole status

# DOCKER01 (Docker daemon)
ssh root@10.101.0.51
systemctl restart docker
docker ps

# PGSQL01 (PostgreSQL)
ssh root@10.101.0.71
systemctl restart postgresql
sudo -u postgres psql -c "SELECT version();"
```

**Estimated recovery time**: 1-2 minutes

---

### 3.2 Scenario: LXC Container Crashed (Corrupted State)

**Symptoms**:
- Cannot SSH to container
- Proxmox shows container as stopped or in error state
- Services unreachable from network

**Recovery (Snapshot Rollback)**:

```bash
# On Proxmox node
ssh root@pve01.phoenix.stack

# 1. Verify container status
pct status <VMID>
# Expected: stopped or error

# 2. List available snapshots
pct listsnapshot <VMID>
# Output examples:
# <service>-daily-20260729-020000
# <service>-daily-20260728-020000
# <service>-daily-20260727-020000

# 3. Rollback to most recent snapshot
pct rollback <VMID> <snapshot-name>

# Example for PROXY01:
pct rollback 105 proxy01-daily-20260729-020000

# 4. Start the container
pct start <VMID>

# 5. Wait for services to start
sleep 30

# 6. Verify container is running
pct status <VMID>

# 7. Test connectivity
ssh root@<service-ip>
# Run service-specific health check
```

**Estimated recovery time**: 5-10 minutes

---

### 3.3 Scenario: Snapshot Corrupted / Rollback Failed

**Symptoms**:
- Rollback fails with error message
- All snapshots are corrupted or too old
- Need to recover to known-good state

**Recovery (Re-deploy via IaC)**:

```bash
# On Proxmox node
ssh root@pve01.phoenix.stack

# 1. Destroy the broken container
pct destroy <VMID> --purge
# WARNING: This deletes the container. Snapshots are gone.

# 2. On your workstation with Terraform:
cd terraform

# 3. Re-create container via Terraform
# Find the module name in terraform.tf
terraform plan | grep <service-name>
terraform apply -target=module.<service-name>

# Wait 60 seconds for container to boot

# 4. Re-configure via Ansible
cd ansible
ssh-keyscan -H <service-ip> >> ~/.ssh/known_hosts

ansible-playbook -i inventory/hosts.yml \
  -l <service-name> \
  -e @vault/onepassword.yml \
  --vault-id @prompt \
  playbooks/site.yml

# 5. Verify service is operational
# (use service-specific verification commands)
```

**Examples**:

```bash
# Re-deploy PROXY01
terraform apply -target=module.proxy01
ansible-playbook -i inventory/hosts.yml -l proxy01 playbooks/site.yml
curl http://10.101.0.31:8080/ping

# Re-deploy DNS01
terraform apply -target=module.dns01
ansible-playbook -i inventory/hosts.yml -l dns01 playbooks/dns_pihole.yml
pihole status

# Re-deploy PGSQL01
terraform apply -target=module.pgsql01
ansible-playbook -i inventory/hosts.yml -l pgsql01 playbooks/site.yml
sudo -u postgres psql -c "SELECT version();"
```

**Estimated recovery time**: 20-30 minutes

---

### 3.4 Decision Tree: Which Recovery Method?

```
Service is down
    ↓
Can SSH to container?
    ├─ YES → Service process crashed
    │   └─ Run: systemctl restart <service>
    │       Recovery time: 1-2 min
    │
    └─ NO → LXC container crashed
        ↓
        Proxmox has recent snapshot?
        ├─ YES → Use snapshot rollback
        │   └─ Run: pct rollback + pct start
        │       Recovery time: 5-10 min
        │
        └─ NO → Re-deploy via Terraform + Ansible
            └─ Run: terraform apply + ansible-playbook
                Recovery time: 20-30 min
```

---

## Part 4: Recovery Testing

### 4.1 Test Schedule

- **Monthly**: Verify snapshots exist and are recent for all services
- **Quarterly**: Practice snapshot restore on a non-critical service
- **Before Major Changes**: Create pre-change snapshot and document rollback procedure

### 4.2 Snapshot Restore Test Procedure

**Objective**: Verify snapshots can be restored without data loss

**Procedure** (use a test service, not production):

```bash
# 1. Create a test snapshot
pct snapshot <VMID> <service>-test-restore-$(date +%Y%m%d-%H%M%S)

# 2. Intentionally break the service (test only!)
ssh root@<service-ip>
systemctl stop <service>
# Optionally: rm <critical-config-file>

# 3. Verify service is broken
# (attempt to use service, should fail)

# 4. Restore from snapshot (on Proxmox node)
pct rollback <VMID> <test-snapshot-name>
pct start <VMID>

# 5. Wait for services to start
sleep 30

# 6. Verify restoration
ssh root@<service-ip>
# Run service health check

# 7. Clean up test snapshot
pct delsnapshot <VMID> <test-snapshot-name>

# 8. Document result
echo "✅ Snapshot restore test PASSED for <service> on $(date)" >> /var/log/recovery-tests.log
```

---

## Part 5: Service-Specific Health Checks

### Quick Reference: Health Check Commands

```bash
# PROXY01 (Traefik)
curl http://10.101.0.31:8080/ping
# Expected: OK

# DNS01/02 (PiHole)
ssh root@10.101.0.201 "pihole status"
# Expected: DNS service is running

# DOCKER01/02 (Docker)
ssh root@10.101.0.51 "docker ps"
# Expected: List of running containers (or empty if none deployed)

# PGSQL01/02 (PostgreSQL)
ssh root@10.101.0.71 "sudo -u postgres psql -c 'SELECT version();'"
# Expected: PostgreSQL version output

# BASTION01/02 (GitHub Runner)
ssh root@10.101.0.20 "systemctl status actions.runner.*"
# Expected: active (running)
```

---

## Part 6: Disaster Recovery Runbook

### Quick Reference Card

**Any Service Down?**

1. **Identify the service and its VMID**:
   ```bash
   # Check service status from Proxmox
   ssh pve01 "pct list | grep <service-name>"
   ```

2. **If container is running, restart service**:
   ```bash
   ssh root@<service-ip> "systemctl restart <service-name>"
   ```

3. **If container is not running, restore from snapshot**:
   ```bash
   ssh pve01 "pct rollback <VMID> <latest-snapshot>; pct start <VMID>"
   ```

4. **Wait 30 seconds, verify**:
   ```bash
   ssh root@<service-ip>
   # Run service-specific health check
   ```

**Estimated recovery time**: 5-10 minutes

---

## Part 7: Backup Verification

### Automated Backup Health Check (All Services)

```bash
# SSH to Proxmox
ssh root@pve01.phoenix.stack

# Check all container snapshots
for vmid in $(pct list | awk 'NR>1 {print $1}'); do
    echo "=== VMID $vmid ==="
    pct listsnapshot $vmid | grep -E "daily|weekly" | head -3
    echo ""
done

# Verify backup scheduler is running
systemctl status backup-scheduler.timer

# Check recent backup logs
tail -50 /var/log/proxmox-backup-scheduler.log
```

---

## Part 8: Monitoring & Alerting

### Service Status Dashboard

```bash
# Quick status check for all PhoenixStack services
cat > /usr/local/bin/service-status.sh << 'EOF'
#!/bin/bash

echo "=== PhoenixStack Service Status ==="
echo ""

# Define services (add as you deploy)
declare -A SERVICES=(
    ["bastion01"]="10.101.0.20:github-runner"
    ["bastion02"]="10.101.0.21:github-runner"
    ["dns01"]="10.101.0.201:pihole-FTL"
    ["dns02"]="10.101.0.202:pihole-FTL"
    ["docker01"]="10.101.0.51:docker"
    ["docker02"]="10.101.0.52:docker"
    ["pgsql01"]="10.101.0.71:postgresql"
    ["pgsql02"]="10.101.0.72:postgresql"
    # Add future services here
)

for service in "${!SERVICES[@]}"; do
    IFS=':' read -r ip service_name <<< "${SERVICES[$service]}"
    
    # Ping check
    if ping -c 1 -W 1 $ip > /dev/null 2>&1; then
        # SSH check
        if ssh -o ConnectTimeout=2 root@$ip "systemctl is-active $service_name" > /dev/null 2>&1; then
            echo "✅ $service ($ip) - OK"
        else
            echo "⚠️  $service ($ip) - Service $service_name not running"
        fi
    else
        echo "🚨 $service ($ip) - Container unreachable"
    fi
done
EOF

chmod +x /usr/local/bin/service-status.sh
/usr/local/bin/service-status.sh
```

---

## Part 9: Maintenance Tasks

### Monthly Maintenance Checklist

```bash
# Run on Proxmox node
ssh root@pve01.phoenix.stack

# 1. Verify recent snapshots exist for all containers
pct list | awk 'NR>1 {print $1}' | while read vmid; do
    echo "=== VMID $vmid ==="
    pct listsnapshot $vmid | head -3
done

# 2. Check storage usage
df -h /var/lib/vz

# 3. Review backup logs
tail -50 /var/log/proxmox-backup-scheduler.log

# 4. Verify all configurations are committed to git
cd /path/to/PhoenixStack
git status ansible/roles/
# Should show: "nothing to commit, working tree clean"

# Completed by: _________
# Date: _________
```

### Quarterly Recovery Test Checklist

- [ ] Choose a non-critical service (e.g., test container or secondary service)
- [ ] Simulate service failure (stop service or container)
- [ ] Practice snapshot restore procedure
- [ ] Verify service recovers with full config
- [ ] Document any issues or improvements
- [ ] Update this runbook if procedures changed

### Annual Infrastructure Review

- [ ] Review retention policy (still 7 days/4 weeks appropriate?)
- [ ] Audit backup storage capacity and usage trends
- [ ] Test full re-deployment via Terraform for at least one service
- [ ] Update disaster recovery procedures for new services
- [ ] Verify all service health checks are current

---

## Appendix A: Proxmox LXC CLI Reference

```bash
# List all containers
pct list

# Container status
pct status <VMID>

# Start/stop container
pct start <VMID>
pct stop <VMID>
pct stop <VMID> --force    # Force stop if hung

# Restart container
pct reboot <VMID>

# Enter container console
pct enter <VMID>

# View container config
pct config <VMID>

# List snapshots
pct listsnapshot <VMID>

# Create snapshot
pct snapshot <VMID> <snapshot-name>

# Restore from snapshot
pct rollback <VMID> <snapshot-name>

# Delete snapshot
pct delsnapshot <VMID> <snapshot-name>

# Destroy container (WARNING: irreversible)
pct destroy <VMID> --purge
```

---

## Appendix B: Service Recovery Contact Sheet

### PhoenixStack Service Inventory

| Service | VMID | IP | Primary Process | Terraform Module | Ansible Role | Phase |
|---------|------|----|--------------------|------------------|--------------|-------|
| bastion01 | 10101 | 10.101.0.20 | github-runner | bastion01 | bastion | 1 ✅ |
| bastion02 | 10102 | 10.101.0.21 | github-runner | bastion02 | bastion | 1 ✅ |
| dns01 | 10201 | 10.101.0.201 | pihole-FTL | dns01 | pihole | 1 ✅ |
| dns02 | 10202 | 10.101.0.202 | pihole-FTL | dns02 | pihole | 1 ✅ |
| docker01 | 11001 | 10.101.0.51 | docker | docker01 | docker | 1 ✅ |
| docker02 | 11002 | 10.101.0.52 | docker | docker02 | docker | 1 ✅ |
| pgsql01 | 10701 | 10.101.0.71 | postgresql | pgsql01 | postgres | 1 ✅ |
| pgsql02 | 10702 | 10.101.0.72 | postgresql | pgsql02 | postgres | 1 ✅ |
| proxy01 | 10301 | 10.101.0.31 | traefik | proxy01 | proxy | 3 📅 |
| authentik01 | 10401 | 10.101.0.41 | authentik | authentik01 | authentik | 4 📅 |
| authentik02 | 10402 | 10.101.0.42 | authentik | authentik02 | authentik | 4 📅 |
| vault01 | 10901 | 10.101.0.81 | vault | vault01 | vault | 4 📅 |
| vault02 | 10902 | 10.101.0.82 | vault | vault02 | vault | 4 📅 |
| plex01 | 10601 | 10.101.0.61 | plexmediaserver | plex01 | plex | 4 📅 |
| amp01 | 10501 | 10.101.0.81 | ampinstmgr | amp01 | amp | 4 📅 |
| monitor01 | 10801 | 10.101.0.91 | prometheus | monitor01 | monitor | 4 📅 |
| backup01 | 11101 | 10.101.0.98 | backup-scheduler | backup01 | backup | 4 📅 |

*Update this table as new services are deployed*

---

## Related Documentation

- **[PROXMOX_BACKUP_INFRASTRUCTURE.md](PROXMOX_BACKUP_INFRASTRUCTURE.md)** - Automated backup system architecture
- **[INFRASTRUCTURE_DESIGN.md](roadmap/INFRASTRUCTURE_DESIGN.md)** - Complete infrastructure standards
- **[HA_REDUNDANCY_STRATEGY.md](roadmap/HA_REDUNDANCY_STRATEGY.md)** - High availability planning
- **[ANSIBLE_PLAYBOOK_GUIDE.md](ANSIBLE_PLAYBOOK_GUIDE.md)** - Playbook execution reference

---

## Document History

| Date | Change | Author |
|------|--------|--------|
| 2026-07-29 | Initial documentation (generalized from PROXY01 guide) | Infrastructure Team |
| | | |
| | | |
