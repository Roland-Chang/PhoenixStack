# HA & Redundancy Strategy

**Last Updated**: 2026-07-29  
**Current Status**: Architecture Revised  
**Priority**: Phased implementation with pragmatic approach  

## Executive Summary

PhoenixStack adopts a **pragmatic HA strategy** that aligns with homelab constraints:

- **PROXY01**: Single instance with automated backup/recovery (acceptable downtime ~15-30 min)
- **DNS01/DNS02**: Active-Active with PiHole Gravity replication (high availability for critical DNS)
- **SQL Cluster**: Planned for future AUTHENTIK HA (PostgreSQL + Keepalived)
- **BASTION01/02**: Already HA by design (multi-user + dual GitHub runners)

This approach balances reliability, operational complexity, and resource utilization.

---

## Service Assessment & Strategy

| Service | Approach | Status | Rationale |
|---------|----------|--------|-----------|
| BASTION | Multi-user SSH + Dual Runners | ✅ Complete | No shared state, inherent redundancy |
| **PROXY** | **Single instance + Backup/Recovery** | 🟢 Revised | Simplifies architecture, acceptable RTO |
| **DNS** | **Active-Active + Gravity Replication** | ⏳ Next Phase | Critical service, PiHole handles sync |
| AUTHENTIK | Shared SQL DB (pending SQL cluster) | 🔲 Blocked | Requires SQL cluster first |
| SQL | PostgreSQL Cluster + Keepalived VIP | ⏳ Future | Prerequisite for AUTHENTIK HA |
| DOCKER | Application-dependent | ⏳ Deferred | Revisit after core infrastructure stable |

---

## PROXY01 - Single Instance with Backup/Recovery

### Architecture

```
Internet Traffic
    ↓
UniFi Port Forward (80, 443)
    ↓
PROXY01 (Traefik) - Single instance
    ├─ All incoming traffic routes here
    ├─ Daily Proxmox snapshots (automated)
    ├─ Git-based config version control
    └─ Recovery time: 5-10 min (snapshot) or 20-30 min (full redeploy)
```

### Why This Approach?

✅ **Pros:**
- Eliminates double-proxying complexity (HAProxy → Traefik)
- Single layer of reverse proxy logic
- Simpler header management and debugging
- No distributed state to synchronize
- Fast snapshot-based recovery (5-10 min)
- Acceptable for homelab (not enterprise-critical)

⚠️ **Trade-off:**
- Services down if PROXY01 fails until recovery completes
- 5-10 minutes with snapshot, 20-30 with full redeploy
- This is acceptable for a personal/homelab infrastructure

### Implementation: Automated Backup/Recovery

**What to configure:**
1. ✅ Proxmox cron-based snapshots of PROXY01 (daily at 02:00 UTC)
2. ✅ Snapshot retention policy (keep last 7 days)
3. ✅ Recovery runbook (see [LXC_SERVICE_RECOVERY.md](../LXC_SERVICE_RECOVERY.md))
4. ✅ Quarterly restore testing checklist
5. ✅ Configuration version control via git

**Restore procedure** (when PROXY01 fails):

*Quick recovery (snapshot rollback - 5-10 min):*
```bash
# On Proxmox node
qm rollback 105 proxy01-daily-20260729-020000
qm start 105
```

*Full recovery (redeploy via IaC - 20-30 min):*
```bash
# 1. Destroy broken container
qm destroy 105 --force

# 2. Re-deploy via Terraform
terraform apply -target=module.proxy01

# 3. Re-configure via Ansible
ansible-playbook -l proxy01 ansible/playbooks/site.yml
```

### Service Level Expectation
- **RTO (Recovery Time Objective)**: 5-10 min (snapshot) or 20-30 min (redeploy)
- **RPO (Recovery Point Objective)**: 24 hours (daily snapshot)
- **Acceptable for**: Homelab, personal services
- **Not suitable for**: Enterprise production, business-critical services

### Documentation
See [LXC_SERVICE_RECOVERY.md](../LXC_SERVICE_RECOVERY.md) for detailed recovery procedures (applicable to all services)

---

## DNS01/DNS02 - Active-Active with PiHole Gravity Replication

### Architecture

```
┌──────────────────────────────────────┐
│  Internal DNS Queries                │
└────────────────┬─────────────────────┘
                 │ (Round-robin or failover)
        ┌────────┴───────┐
        ↓                 ↓
    DNS01              DNS02
   (PiHole)           (PiHole)
   10.101.0.201       10.101.0.202
        │                 │
        └────────┬────────┘
                 │ Gravity Replication
          (Database sync)
                 ↓
        Synchronized blocklists,
        whitelists, configurations
```

### Why DNS HA?

✅ **Critical infrastructure**: Everything depends on DNS
- VMs resolve service names via DNS01/DNS02
- Proxmox uses DNS for service discovery
- Traefik backend routing depends on DNS
- **HA is essential**

### Implementation Plan (PHASE 1)

#### Step 1: Prepare PiHole Replication Credentials
```bash
# On DNS01
mysql -u root -p

# Create replication user
CREATE USER 'pihole_sync'@'10.101.0.202' IDENTIFIED BY 'STRONG_PASSWORD';
GRANT SELECT ON pihole.* TO 'pihole_sync'@'10.101.0.202';
FLUSH PRIVILEGES;
```

#### Step 2: Ansible Role - `roles/pihole_replication/`
Create tasks for:
- Install replication tools (MySQL replication or PiHole's built-in gravity sync)
- Configure replication user credentials (from Ansible vault)
- Setup gravity database sync
- Verify replication status

#### Step 3: Test Replication
```bash
# On DNS01: Create test blocklist
# Verify it appears on DNS02: SELECT * FROM gravity_list

# On DNS02: Create test whitelist
# Verify it appears on DNS01

# Test DNS queries on both:
nslookup google.com 10.101.0.201
nslookup google.com 10.101.0.202
```

#### Step 4: Configure DNS Failover
Option A: **Client-side DNS failover** (DNS entries in services)
```yaml
# Ansible host vars
dns_servers:
  - 10.101.0.201  # DNS01 (primary)
  - 10.101.0.202  # DNS02 (fallback)
```

Option B: **Proxy-side failover** (Traefik resolves both)
- Traefik queries DNS01 first, falls back to DNS02

### Testing Checklist (DNS HA Validation)

- [ ] Deploy replication role to DNS02
- [ ] Create test blocklist on DNS01, verify on DNS02
- [ ] Create test whitelist on DNS02, verify on DNS01
- [ ] Query both instances: `nslookup -server=10.101.0.201 google.com`
- [ ] Shutdown DNS01 (`systemctl stop pihole`)
- [ ] Verify DNS02 still resolves queries correctly
- [ ] Re-enable DNS01, verify replication catches up
- [ ] Verify blocklists match on both instances

### Service Level Expectation (DNS HA)
- **RTO**: < 1 second (automatic DNS failover)
- **RPO**: < 1 minute (Gravity sync frequency)
- **Suitable for**: Essential infrastructure service

---

## PHASE 2: SQL Cluster (Future - Prerequisite for AUTHENTIK HA)

### Architecture (Planned)

```
┌──────────────────────────────┐
│  SQL01 (Primary)             │
│  PostgreSQL + Keepalived VIP │
│  IP: 10.101.0.71             │
│  VIP: 10.101.0.70            │
└──────────────┬───────────────┘
               │ Streaming Replication
               │
┌──────────────┴───────────────┐
│  SQL02 (Replica/Standby)     │
│  PostgreSQL 15               │
│  IP: 10.101.0.72             │
└──────────────────────────────┘
```

### Timeline
- **Status**: Planned for after DNS01/DNS02 HA is stable
- **Complexity**: High (new infrastructure)
- **Prerequisite for**: AUTHENTIK01/02 HA

### What to Configure
- [ ] PostgreSQL cluster setup (primary/replica)
- [ ] Streaming replication (hot standby)
- [ ] Keepalived VIP for automatic failover
- [ ] Daily backups to backup01
- [ ] Restore/recovery procedures

### Documentation
- [ ] Create `docs/SQL_CLUSTER_SETUP.md`
- [ ] Create `docs/SQL_FAILOVER_PROCEDURES.md`
- [ ] Create `docs/SQL_BACKUP_RESTORE.md`

---

## PHASE 3: AUTHENTIK01/02 - Shared Database HA (Future)

### Architecture (After SQL Cluster)

```
┌──────────────┐  ┌──────────────┐
│ AUTHENTIK01  │  │ AUTHENTIK02  │
│ Port 9443    │  │ Port 9443    │
└──────┬───────┘  └───────┬──────┘
       │                   │
       └───────────┬───────┘
                   ↓
          SQL Cluster VIP
          (10.101.0.70)
```

**Status**: Blocked on SQL cluster completion
**Timeline**: After Phase 2 (SQL cluster) is stable

---

## BASTION01/02 - Complete ✅

**Status**: Already configured for multi-user access
- Both instances available for SSH
- Each runs independent GitHub runner
- No shared state = no sync needed
- One instance can be offline without impact on the other
- **Action required**: None

---

## Recovery Procedures

### PROXY01 Recovery (Backup/Restore)

**Detailed procedures documented in**: [LXC_SERVICE_RECOVERY.md](../LXC_SERVICE_RECOVERY.md)

**Quick Reference**:

**Scenario 1**: Traefik process crashed (LXC still running)
```bash
ssh root@10.101.0.31
systemctl restart traefik
```
**RTO**: 1-2 minutes

**Scenario 2**: LXC container crashed (corrupted state)
```bash
ssh root@pve01
qm rollback 105 proxy01-daily-20260729-020000
qm start 105
```
**RTO**: 5-10 minutes

**Scenario 3**: Snapshots unavailable/corrupted
```bash
# Re-deploy via Terraform + Ansible (see LXC_SERVICE_RECOVERY.md)
```
**RTO**: 20-30 minutes

**Decision Tree**: See [LXC_SERVICE_RECOVERY.md](../LXC_SERVICE_RECOVERY.md#34-decision-tree-which-recovery-method)

### DNS01/DNS02 Recovery

**Scenario**: DNS01 fails

**Expected behavior**:
- Clients automatically fail over to DNS02 (via DNS round-robin or failover config)
- No manual intervention needed
- Estimated downtime: < 1 second

**If both DNS servers fail**:
1. SSH to first healthy DNS container
2. Restore from Proxmox snapshot
3. Verify replication status: `mysql -u root -e "SELECT * FROM information_schema.innodb_trx;"`

---

## Backup Strategy for PROXY01

### Automated Snapshots (Daily)

**Configuration**:
```bash
# On Proxmox - schedule via cron or Proxmox backup scheduler
# Daily at 02:00 UTC, keep last 7 snapshots

# Example Proxmox backup command:
qm snapshot VMID proxy01-snapshot-$(date +%Y%m%d-%H%M%S)
```

### Manual Snapshot Before Changes

```bash
# Before any major Traefik config change:
qm snapshot VMID proxy01-backup-pre-update-$(date +%Y%m%d)

# After confirming the change works:
# Delete old snapshot
```

### Disaster Recovery Runbook

**Document in**: `docs/PROXY_DISASTER_RECOVERY.md`
- Step-by-step restore procedure
- When to use snapshot vs. re-deploy
- Rollback procedures
- Contact information for emergencies

---

## Next Actions

### PHASE 1 (THIS WEEK)
- [ ] Document PROXY01 backup/recovery procedures → `docs/PROXY_DISASTER_RECOVERY.md`
- [ ] Validate Proxmox snapshot configuration
- [ ] Test restore procedure on a non-production LXC first
- [ ] Document backup testing schedule (quarterly)

### PHASE 2 (NEXT 2-3 WEEKS)
- [ ] Create `roles/pihole_replication/` Ansible role
- [ ] Implement DNS01/DNS02 Gravity replication
- [ ] Test DNS failover scenarios
- [ ] Document DNS HA setup → `docs/DNS_GRAVITY_REPLICATION.md`

### PHASE 3 (DEFERRED)
- [ ] Plan SQL cluster deployment
- [ ] Create Terraform modules for SQL01/SQL02
- [ ] Implement Keepalived VIP
- [ ] Build backup/restore procedures for SQL

---

## Risk Mitigation Summary

| Service | Failure Scenario | Recovery Strategy | RTO | RPO |
|---------|------------------|-------------------|-----|-----|
| PROXY01 | Traefik crashes or LXC fails | Proxmox snapshot restore | 10 min | 24 hr |
| DNS01   | DNS01 fails | Automatic failover to DNS02 | < 1 sec | < 1 min |
| DNS02   | DNS02 fails | Automatic failover to DNS01 | < 1 sec | < 1 min |
| AUTHENTIK | Requires SQL cluster HA (not yet deployed) | N/A | - | - |

---

## Definitions

- **RTO (Recovery Time Objective)**: Maximum acceptable downtime
- **RPO (Recovery Point Objective)**: Maximum acceptable data loss
- **HA (High Availability)**: System continues operating when a component fails
- **Single Point of Failure**: A component whose failure stops the whole system (e.g., PROXY01 currently)


- [ ] Alerts for:
  - Replication lag > 1 second
  - VIP failover events
  - Service down on primary
  - Database connection failures

---

## Summary Timeline

```
Week 1-2:  PROXY01/02 config sync ✅ FIRST
Week 3-4:  DNS01/02 replication
Week 5-6:  SQL01/02 cluster (NEW)
Week 7-8:  AUTHENTIK01/02 HA
Week 9-10: Monitoring (optional)
```

---

## Infrastructure Summary After All Phases

| Service | Instances | Approach | Status |
|---------|-----------|----------|--------|
| BASTION | 01/02 | Multi-user SSH + Runners | ✅ Done |
| DNS | 01/02 | Active-Active + Gravity Replication | ⏳ Phase 2 |
| PROXY | 01/02 | Active-Active + Config Sync | ⏳ Phase 1 |
| AUTHENTIK | 01/02 | Active-Active + Shared SQL | ⏳ Phase 4 |
| SQL | 01/02 | PostgreSQL Cluster + VIP | ⏳ Phase 3 |
| DOCKER | 01/02 | App-dependent (deferred) | ⏳ Later |

**Total Containers**: 13 (was 11, +SQL01/02)

---

## Key Decisions Made

1. ✅ **BASTION01/02**: No sync needed - designed for multi-user access
2. ✅ **DOCKER01/02**: Deferred to later - handle app-by-app
3. ✅ **DATABASE TIER NEEDED**: SQL01/02 required for AUTHENTIK01/02 HA
4. ✅ **Start with PROXY01/02**: Best test case for Ansible HA patterns
5. ✅ **PiHole native replication**: Excellent for DNS01/02
6. ✅ **Keepalived VIP**: Standard for SQL cluster failover

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Replication lag | Stale data | Monitor lag, adjust batch sizes |
| VIP flip-flop | Service interruption | Increase failover threshold |
| DB corruption | Data loss | Test backups regularly |
| Config drift | Inconsistent behavior | Ansible idempotency checks |
| Cascading failure | Total outage | Health checks on all tiers |

---

## Questions to Answer Before Implementation

- [ ] Where will SQL backups be stored? (backup01?)
- [ ] Do we need cross-datacenter failover? (Probably not now)
- [ ] Should we implement read replicas for reports?
- [ ] How long can we tolerate replication lag?
- [ ] Do we need monitoring/alerting before Phase 1?

---

## Reusable Ansible Patterns

All HA implementations will follow these patterns:

1. **Configuration Sync Template**: See `/memories/repo/ha-redundancy-strategy.md`
2. **Health Check Template**: See same file
3. **Database Replication Template**: See same file

These templates can be adapted for any future HA pair.

---

**Next Step**: Start with PHASE 1 (PROXY01/02 config sync) after core infrastructure is stable.
