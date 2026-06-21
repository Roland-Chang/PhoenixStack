# HA & Redundancy Implementation - TODO

**Last Updated**: 2026-06-16
**Current Status**: Planning Phase
**Priority**: Medium (after core infrastructure stable)

## Overview
This document outlines the plan to implement high availability and redundancy across PhoenixStack services. Different services require different approaches based on their state management needs.

---

## Service Assessment

| Service | Pair | Approach | Priority | Status |
|---------|------|----------|----------|--------|
| BASTION | 01/02 | Multi-user SSH + Dual Runners | N/A ✅ | Done by design |
| DNS | 01/02 | Active-Active + PiHole Gravity Replication | HIGH | ⏳ Planned |
| PROXY | 01/02 | Active-Active + Config Sync | HIGH | ⏳ FIRST TEST CASE |
| AUTHENTIK | 01/02 | Active-Active + Shared SQL DB | MEDIUM | 🚫 Blocked on SQL cluster |
| DOCKER | 01/02 | Application-Dependent | LOW | ⏳ Deferred (Docker Swarm?) |
| SQL (NEW) | 01/02 | PostgreSQL Cluster + Keepalived VIP | HIGH | ⏳ NEXT PHASE |

---

## BASTION01/02 - COMPLETE ✅ (No Action Needed)

**Status**: Already configured for multi-user access
- Both instances available for SSH
- Each runs independent GitHub runner
- No shared state = no sync needed
- One instance can be offline without impact to the other

---

## DOCKER01/02 - DEFERRED ⏳ (Handle Later)

**Status**: Skipped for now
- Redundancy approach depends on what's running
- Consider Docker Swarm mode for future
- Application-specific replication may be needed
- Revisit after core infrastructure is stable

---

## PHASE 1: PROXY01/02 - Config Synchronization (START HERE)

**Timeline**: Week 1-2  
**Complexity**: Easy-Medium  
**Risk**: Low (test case for HA patterns)

### What to Build
- [ ] Ansible playbook: `proxy_ha_sync.yml`
  - Syncs `traefik.yml` config across both instances
  - Validates configuration before reload
  - Restarts Traefik service
  - Health checks

- [ ] Ansible role: `roles/traefik_ha/`
  - Task to sync configuration
  - Task to validate config
  - Task to reload service
  - Reusable template for other services

- [ ] UniFi Dream Machine setup
  - Create virtual server with both proxy01:80 and proxy02:80
  - Health check endpoint: `/health`
  - Load balancing: round-robin

### How It Works
```
User Request → Load Balancer
                    ↓
             ┌──────┴──────┐
             ↓              ↓
         PROXY01        PROXY02
      (Traefik)       (Traefik)
      
Both serve requests simultaneously.
Config changes trigger reload on all instances.
```

### Testing Checklist
- [ ] Deploy config to both instances
- [ ] Generate test traffic: `for i in {1..100}; do curl http://10.101.0.254/; done`
- [ ] Verify round-robin distribution in logs
- [ ] Shutdown PROXY01: `systemctl stop traefik`
- [ ] Verify PROXY02 still serves all requests
- [ ] Re-enable PROXY01: `systemctl start traefik`
- [ ] Verify load balancer health checks detect both are up

### Documentation
- [ ] Create `docs/HA_TRAEFIK_SETUP.md`
  - Configuration synchronization procedure
  - Load balancer setup instructions
  - Failover behavior
  - Recovery procedures

---

## PHASE 2: DNS01/02 - PiHole Gravity Replication

**Timeline**: Week 3-4 (after PROXY01/02 works)  
**Complexity**: Medium  
**Risk**: Low (PiHole has built-in replication)

### What to Build
- [ ] Ansible playbook: `dns_ha_sync.yml`
  - Configures gravity database replication
  - Enables periodic sync via cron
  - Health checks for replication status

- [ ] Ansible role: `roles/pihole_replication/`
  - Setup replication user/credentials
  - Configure gravity sync
  - Monitor replication lag

### How It Works
```
DNS01 (Primary)
   ↓ Gravity Replication
DNS02 (Replica)

Admin changes on either sync to the other.
Both serve DNS simultaneously.
```

### Testing Checklist
- [ ] Deploy role to both instances
- [ ] Create test blocklist on DNS01
- [ ] Query DNS02 database: `SELECT * FROM gravity_list`
- [ ] Verify test blocklist appears on DNS02
- [ ] Shutdown DNS01
- [ ] Query DNS02: `nslookup example.com 10.101.0.202`
- [ ] Verify blocklist is being enforced

### Documentation
- [ ] Create `docs/HA_PIHOLE_SETUP.md`

---

## PHASE 3: DATABASE CLUSTER - NEW INFRASTRUCTURE (CRITICAL)

**Timeline**: Week 5-6 (prerequisite for AUTHENTIK01/02 HA)  
**Complexity**: High  
**Risk**: Medium (new infrastructure)

### What to Build

#### 1. Terraform Configuration
<<<<<<< HEAD
- [ ] Create `terraform/pgsql01/` directory
- [ ] Create `terraform/pgsql02/` directory
- [ ] Add modules to `terraform/terraform.tf`
- [ ] Update `terraform/variables.tf` with PostgreSQL MAC addresses

#### 2. Inventory Updates
- [ ] Add PostgreSQL instances to `ansible/inventory/hosts.yml`
  - pgsql01: 10.101.0.71, VMID 112, MAC 02:aa:bb:cc:07:01
  - pgsql02: 10.101.0.72, VMID 113, MAC 02:aa:bb:cc:07:02
=======
- [ ] Create `terraform/sql01/` directory
- [ ] Create `terraform/sql02/` directory
- [ ] Add modules to `terraform/terraform.tf`
- [ ] Update `terraform/variables.tf` with SQL MAC addresses

#### 2. Inventory Updates
- [ ] Add SQL instances to `ansible/inventory/hosts.yml`
  - sql01: 10.101.0.71, VMID 112, MAC 02:aa:bb:cc:07:01
  - sql02: 10.101.0.72, VMID 113, MAC 02:aa:bb:cc:07:02
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
- [ ] Create `sql` group in inventory

#### 3. Ansible Roles
- [ ] `roles/postgresql_primary/` - Configure PostgreSQL for replication
- [ ] `roles/postgresql_replica/` - Setup streaming replication
- [ ] `roles/keepalived_sql/` - Virtual IP failover (10.101.0.70)
- [ ] `roles/postgresql_backup/` - Backup configuration

#### 4. Playbooks
- [ ] `sql_cluster_setup.yml` - Initialize cluster
- [ ] `sql_backup_setup.yml` - Configure backups to backup01
- [ ] `sql_failover_test.yml` - Test failover procedure

### Infrastructure Design
```
┌─────────────────────────────┐
│  SQL01 (Primary)            │
│  PostgreSQL 15              │
│  IP: 10.101.0.71            │
│  VMID: 112                  │
│  Storage: ssd (32GB)        │
└────────────┬────────────────┘
             │ Streaming Replication
             │
┌────────────┴────────────────┐
│  SQL02 (Standby/Replica)    │
│  PostgreSQL 15              │
│  IP: 10.101.0.72            │
│  VMID: 113                  │
│  Storage: ssd (32GB)        │
└─────────────────────────────┘

Virtual IP (Keepalived): 10.101.0.70
Automatic failover on SQL01 outage
```

### Database Schema
```sql
-- AUTHENTIK database
CREATE DATABASE authentik OWNER authentik;
CREATE ROLE authentik LOGIN PASSWORD '***';

-- Replication user
CREATE ROLE replicator SUPERUSER LOGIN REPLICATION PASSWORD '***';
```

### Configuration Details
- **PostgreSQL Version**: 15.x
- **Replication Type**: Streaming (hot standby)
- **VIP**: 10.101.0.70 (Keepalived)
- **Backup**: Daily to backup01 at 02:00 UTC
- **Archive**: WAL archiving for point-in-time recovery

### Testing Checklist
- [ ] Deploy SQL01 and SQL02 via Terraform
- [ ] Verify PostgreSQL is running on both
- [ ] Check replication status: `SELECT * FROM pg_stat_replication`
- [ ] Test read queries on replica
- [ ] Create test database on primary, verify on replica
- [ ] Simulate SQL01 failure (shutdown or network break)
- [ ] Verify Keepalived moved VIP to SQL02
- [ ] Connect to SQL via VIP and verify query works
- [ ] Restore SQL01 and verify re-joins cluster
- [ ] Test backup restore from backup01

### Documentation
- [ ] Create `docs/SQL_CLUSTER_SETUP.md`
- [ ] Create `docs/SQL_FAILOVER_PROCEDURES.md`
- [ ] Create `docs/SQL_BACKUP_RESTORE.md`

---

## PHASE 4: AUTHENTIK01/02 - Shared Database HA

**Timeline**: Week 7-8 (after SQL cluster is stable)  
**Complexity**: Medium  
**Risk**: Low (AUTHENTIK handles multi-instance)

### What to Build
- [ ] Update Ansible playbook: `authentik_full_setup.yml`
  - Connect to SQL cluster VIP (10.101.0.70)
  - Disable local Sqlite database
  - Configure connection pooling

- [ ] Ansible role: `roles/authentik_ha/`
  - Database connection configuration
  - Health checks for both instances
  - Log aggregation (optional)

### How It Works
```
┌──────────────┐  ┌──────────────┐
│ AUTHENTIK01  │  │ AUTHENTIK02  │
└──────┬───────┘  └───────┬──────┘
       │                   │
       └───────────┬───────┘
                   ↓
          SQL Cluster VIP
          (10.101.0.70)
```

### Testing Checklist
- [ ] Deploy AUTHENTIK01 connected to SQL VIP
- [ ] Deploy AUTHENTIK02 connected to SQL VIP
- [ ] Add test user in AUTHENTIK01
- [ ] Verify user appears in AUTHENTIK02 (same database)
- [ ] Shutdown SQL01 (primary)
- [ ] Verify both AUTHENTIK instances still connect via VIP->SQL02
- [ ] Create another test user, verify it's in SQL02
- [ ] Restore SQL01, verify it re-joins cluster
- [ ] Add final test user, verify on all instances

### Documentation
- [ ] Update `docs/AUTHENTIK_SETUP.md` with HA notes
- [ ] Add to `docs/HA_FAILOVER_PROCEDURES.md`

---

## PHASE 5: Monitoring & Alerting (Optional)

**Timeline**: Week 9-10  
**Complexity**: Medium

### What to Build
- [ ] Monitoring dashboard (Grafana)
  - Traefik request distribution
  - DNS query volume per instance
  - SQL replication lag
  - Keepalived VIP status

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
