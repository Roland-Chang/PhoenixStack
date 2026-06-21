# Infrastructure Status & Next Steps

**Last Updated**: 2026-06-16  
**Status**: Core infrastructure deployed and operational ✅

---

## Current Infrastructure Summary

### Deployed Containers (11 total)

**Management & Orchestration Tier**
- ✅ BASTION01 (10.101.0.21, VMID 101)
- ✅ BASTION02 (10.101.0.22, VMID 102)

**DNS Tier**
- ✅ DNS01 (10.101.0.201, VMID 103) - PiHole
- ✅ DNS02 (10.101.0.202, VMID 104) - PiHole

**Ingress/Proxy Tier**
- ✅ PROXY01 (10.101.0.31, VMID 105) - Traefik
- ✅ PROXY02 (10.101.0.32, VMID 106) - Traefik

**Identity Tier**
<<<<<<< HEAD
- ✅ AUTHENTIK01 (10.101.0.41, VMID 107) - Authentik
- ✅ AUTHENTIK02 (10.101.0.42, VMID 108) - Authentik
=======
- ✅ AUTHENTIK01 (10.101.0.41, VMID 107)
- ✅ AUTHENTIK02 (10.101.0.42, VMID 108)
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072

**Workload Tier**
- ✅ DOCKER01 (10.101.0.51, VMID 109)
- ✅ DOCKER02 (10.101.0.52, VMID 110)
- ✅ PLEX01 (10.101.0.61, VMID 111)

**Database Tier (FRAMEWORK READY)**
<<<<<<< HEAD
- 📋 PGSQL01 (10.101.0.71, VMID 112) - PostgreSQL Primary
- 📋 PGSQL02 (10.101.0.72, VMID 113) - PostgreSQL Standby
- 📋 DB01 (10.101.0.75, VMID 114) - MariaDB Primary
- 📋 DB02 (10.101.0.76, VMID 115) - MariaDB Standby

**Observability Tier (FRAMEWORK READY)**
- 📋 MONITOR01 (10.101.0.73, VMID 116) - Prometheus
- 📋 MONITOR02 (10.101.0.74, VMID 117) - Grafana
=======
- 📋 SQL01 (10.101.0.71, VMID 112) - PostgreSQL Primary
- 📋 SQL02 (10.101.0.72, VMID 113) - PostgreSQL Standby
- 📋 DB01 (10.101.0.73, VMID 116) - MariaDB Primary
- 📋 DB02 (10.101.0.74, VMID 117) - MariaDB Standby

**Observability Tier (FRAMEWORK READY)**
- 📋 MONITOR01 (10.101.0.101, VMID 114) - Prometheus
- 📋 MONITOR02 (10.101.0.102, VMID 115) - Grafana
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072

**Security Tier (FRAMEWORK READY)**
- 📋 VAULT01 (10.101.0.81, VMID 118) - HashiCorp Vault Primary
- 📋 VAULT02 (10.101.0.82, VMID 119) - HashiCorp Vault Standby

**Backup Tier (FRAMEWORK READY)**
- 📋 BACKUP01 (10.101.0.91, VMID 120) - Proxmox Backup Orchestration

---

## Recent Updates (2026-06-16)

### Infrastructure Alignment
- [x] Updated IP addresses to match organizational schema
- [x] Corrected storage pool configuration (all containers use `ssd`)
- [x] Updated MAC address scheme with database tier
- [x] Updated VMID allocation (112-113 reserved for SQL cluster)
- [x] Updated Terraform variables and documentation

### Documentation Created
- [x] `docs/HA_REDUNDANCY_TODO.md` - Complete HA implementation roadmap
- [x] Updated `docs/mac-address-scheme.md` with SQL tier
- [x] Updated `terraform/terraform.tfvars.example` with correct VMID schema
- [x] Updated `terraform/README_STORAGE_POOLS.md` with storage requirements
- [x] Updated Ansible inventory with proxy and sql groups

### Repository Memory
- [x] `/memories/repo/ha-redundancy-strategy.md` - Detailed HA architecture and patterns

---

## HA/Redundancy Implementation Plan

### Overview
Each service pair has been analyzed for redundancy requirements. Implementation is phased to build HA patterns progressively.

| Phase | Service | Approach | Priority | Status |
|-------|---------|----------|----------|--------|
| 1 | PROXY01/02 | Config sync + Load balancer | HIGH | ⏳ NEXT |
| 2 | DNS01/02 | Gravity DB replication | HIGH | ⏳ Week 3-4 |
<<<<<<< HEAD
| **3** | **PGSQL01/02** | **PostgreSQL cluster + Keepalived** | **CRITICAL** | **✅ TERRAFORM READY** |
=======
| **3** | **SQL01/02** | **PostgreSQL cluster + Keepalived** | **CRITICAL** | **✅ TERRAFORM READY** |
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
| 4 | AUTHENTIK01/02 | Shared database | MEDIUM | ⏳ Week 7-8 (depends on Phase 3) |
| - | BASTION01/02 | N/A (by design) | N/A | ✅ Done |
| - | DOCKER01/02 | N/A (deferred) | LOW | ⏳ After PLEX01 |
| - | PLEX01 | N/A (stateless) | LOW | ✅ Done |

**See `docs/HA_REDUNDANCY_TODO.md` for full details.**

---

## Immediate Next Steps

### 1. **Configure PROXY01/02 Load Balancing** (This Week)
Build config synchronization and test with UniFi load balancer:
```bash
# After implementing proxy_ha_sync.yml playbook:
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/proxy_ha_sync.yml
```

<<<<<<< HEAD
### 2. **Deploy PostgreSQL Cluster** (Priority - Blocks AUTHENTIK HA)
Create Terraform configuration for PGSQL01/02:
```bash
# PostgreSQL Terraform modules now exist in:
# - terraform/pgsql01/
# - terraform/pgsql02/

# Deploy PostgreSQL cluster:
terraform apply -target=module.pgsql01 -target=module.pgsql02

# Verify deployment:
pct list | grep -E "112|113"
ssh root@10.101.0.71  # PGSQL01
ssh root@10.101.0.72  # PGSQL02
=======
### 2. **Deploy SQL Cluster** (Priority - Blocks AUTHENTIK HA)
Create Terraform configuration for SQL01/02:
```bash
# SQL Terraform modules now exist in:
# - terraform/sql01/
# - terraform/sql02/

# Deploy SQL cluster:
terraform apply -target=module.sql01 -target=module.sql02

# Verify deployment:
pct list | grep -E "112|113"
ssh root@10.101.0.71  # SQL01
ssh root@10.101.0.72  # SQL02
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
```

**Why This Priority**: AUTHENTIK01/02 cannot have proper HA without a shared database backend.

### 3. **Test PiHole Replication** (After Phase 1)
Verify DNS01/02 gravity synchronization

### 4. **Migrate AUTHENTIK to Shared DB** (After SQL cluster)
Update AUTHENTIK to use SQL cluster VIP (10.101.0.70)

---

## Key Documentation Files

### For HA Implementation
- **[HA_REDUNDANCY_TODO.md](HA_REDUNDANCY_TODO.md)** - Complete implementation roadmap with timelines
- **[ha-redundancy-strategy.md](/memories/repo/ha-redundancy-strategy.md)** - Detailed architecture patterns and templates (in memory)

### For Infrastructure Reference
- **[mac-address-scheme.md](mac-address-scheme.md)** - Updated with SQL tier and correct VMID schema
- **[README_STORAGE_POOLS.md](../terraform/README_STORAGE_POOLS.md)** - Storage pool requirements (SSD-based)
- **[TERRAFORM_FIX_SUMMARY.md](../TERRAFORM_FIX_SUMMARY.md)** - Previous fixes and considerations

### For Deployment
- **[BASTION01_FRESH_DEPLOYMENT.md](BASTION01_FRESH_DEPLOYMENT.md)** - How to deploy BASTION01 from scratch
- **[ANSIBLE_PLAYBOOK_GUIDE.md](ANSIBLE_PLAYBOOK_GUIDE.md)** - Playbook execution guide

---

## Architecture Decisions

### ✅ Finalized
1. **BASTION01/02 Strategy**: Multi-user SSH + dual GitHub runners (no sync needed)
   - Both instances independently available
   - Runners register separately to GitHub
   - If one goes down, other continues serving

2. **DOCKER01/02 Strategy**: Deferred to later
   - Redundancy depends on running applications
   - Consider Docker Swarm or Kubernetes
   - App-by-app implementation later

3. **SQL Cluster**: NEW infrastructure tier
   - Required for AUTHENTIK01/02 HA
   - Enables future stateful services
   - PostgreSQL with streaming replication + Keepalived VIP

4. **Configuration Sync**: Ansible playbooks
   - Stateless services (Traefik) deploy identical config
   - Config changes trigger reload on all instances
   - Reusable template for future services

5. **Load Balancing**: External (UniFi/HAProxy)
   - Traefik instances are stateless
   - External LB distributes traffic to both
   - Health checks monitor instance availability

---

## Resource Consumption

### Current (11 Containers)
- **vCPU**: ~48 cores allocated
- **RAM**: ~44GB allocated
- **Storage**: ~400GB (SSD)

<<<<<<< HEAD
### With PGSQL01/02 (+2 Containers)
=======
### With SQL01/02 (+2 Containers)
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
- **vCPU**: ~52 cores allocated (+4)
- **RAM**: ~48GB allocated (+4GB)
- **Storage**: ~432GB (including SQL backups)

### Headroom Check
- **Verify**: Proxmox node has sufficient resources before deploying SQL tier

---

## Testing Checklist

### For Each HA Implementation Phase

**PROXY01/02 (Phase 1)**
- [ ] Config sync playbook deployed
- [ ] Both instances serving traffic via load balancer
- [ ] Round-robin distribution verified in logs
- [ ] Failover test: disable PROXY01, PROXY02 handles all traffic
- [ ] Failover test: disable PROXY02, PROXY01 handles all traffic
- [ ] Both restored, verify load balancer recognizes both

**DNS01/02 (Phase 2)**
- [ ] Gravity replication configured
- [ ] Blocklist added on DNS01 appears on DNS02
- [ ] Failover test: disable DNS01, DNS02 serves all queries
- [ ] Verify blocklist enforcement on DNS02

**SQL Cluster (Phase 3)**
- [ ] Primary and standby replicate successfully
- [ ] VIP failover works (simulate primary failure)
- [ ] AUTHENTIK connects via VIP successfully

---

## Troubleshooting Guide

### Issue: Replication Lag
- **Check**: `SELECT * FROM pg_stat_replication` on primary
- **Fix**: Increase WAL_KEEP_SIZE or disable unnecessary logging

### Issue: VIP Not Failing Over
- **Check**: Keepalived status on both SQL nodes
- **Fix**: Verify health checks are detecting failures

### Issue: Service Down After Failover
- **Check**: Connection pooling settings
- **Fix**: Add retry logic to application connections

See `docs/HA_REDUNDANCY_TODO.md` for more details.

---

## Git & Deployment Notes

### State Management
- Terraform state: Local on bastion01 (`terraform.tfstate`)
- Proxmox backups: Protect state file
- GitHub Actions: Uses self-hosted runner on bastion01

### GitOps Considerations
- All infrastructure declared in Terraform
- Ansible playbooks version-controlled
- Config files can be GitOps'd (future enhancement)

### Disaster Recovery
- Terraform state backed up by Proxmox VM snapshots
- SQL backups to backup01 (to be configured)
- WAL archiving for point-in-time recovery (to be configured)

---

## Next Phase Checklist

Before starting Phase 1 (PROXY01/02 HA):

- [ ] Verify PROXY01 and PROXY02 are running and healthy
- [ ] Test Traefik on both instances independently
- [ ] Prepare UniFi Dream Machine for virtual server config
- [ ] Create Ansible role template: `roles/traefik_ha/`
- [ ] Create playbook: `proxy_ha_sync.yml`
- [ ] Update documentation: `docs/HA_TRAEFIK_SETUP.md`

---

## Questions & Contact

For questions or clarifications, see:
- **HA Architecture**: `docs/HA_REDUNDANCY_TODO.md`
- **Patterns**: `/memories/repo/ha-redundancy-strategy.md`
- **Storage**: `terraform/README_STORAGE_POOLS.md`
- **MAC Scheme**: `docs/mac-address-scheme.md`

---

**Status**: ✅ Infrastructure ready for HA implementation  
**Next Action**: Implement Phase 1 (PROXY HA) when resources permit
