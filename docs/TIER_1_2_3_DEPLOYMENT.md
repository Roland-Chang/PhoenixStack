# PhoenixStack: Extended Infrastructure - Tier 1-3 Deployment Guide

<<<<<<< HEAD
**Last Updated**: 2026-06-18
**Status**: Terraform Framework Ready - Pre-Deployment
**⚠️ NOTE**: Architecture consolidated to single 10.101.0.0/23 subnet (VLAN 10) on 2026-06-18. Previous VLAN separation strategy (decision-management-vlan.md) has been superseded. All services now share PHOENIX-PRIMARY subnet with strategic IP segmentation.
=======
**Last Updated**: 2026-06-16
**Status**: Terraform Framework Ready - Pre-Deployment
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072

---

## Overview

PhoenixStack has been extended with observability, security, and resilience tiers. All Terraform configurations are ready for deployment. This document provides deployment procedures and post-deployment configuration requirements.

<<<<<<< HEAD
**Network Architecture Update**: 
- **Single /23 subnet**: 10.101.0.0/23 (10.101.0.0 - 10.101.1.255)
- **Infrastructure tier**: 10.101.0.x (Management, DNS, Databases, Security, Backup)
- **Application tier**: 10.101.1.x (Docker, Plex, Game Servers)
- **Gateway**: 10.101.0.254

=======
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
---

## Current Infrastructure Summary

### Core Tier (Already Deployed)
- **11 Containers**: BASTION01/02, DNS01/02, PROXY01/02, AUTHENTIK01/02, DOCKER01/02, PLEX01

### Database Tier: PostgreSQL Cluster (Terraform Ready - Deploy First)
<<<<<<< HEAD
- **PGSQL01/02**: PostgreSQL HA with streaming replication
- **VMID**: 115-116 | **IPs**: 10.101.0.71-72 | **Memory**: 2GB each

### Database Tier: MariaDB Cluster (Terraform Ready - Deploy First)
- **DB01/02**: MariaDB HA with master-slave replication
- **VMID**: 117-118 | **IPs**: 10.101.0.75-76 | **Memory**: 2GB each

### Tier 1: Observability (Terraform Ready - Deploy Second)
- **MONITOR01/02**: Prometheus + Grafana cluster
- **VMID**: 119-120 | **IPs**: 10.101.0.91-92 | **Memory**: 2GB each

### Tier 2: Security (Terraform Framework - Deploy Third)
- **VAULT01/02**: HashiCorp Vault HA cluster
- **VMID**: 121-122 | **IPs**: 10.101.0.81-82 | **Memory**: 2GB each
- **Status**: Framework ready, requires post-deployment configuration

### Tier 3: Backup (Terraform Framework - Deploy Fourth)
- **BACKUP01**: Proxmox Backup orchestration
- **VMID**: 123 | **IP**: 10.101.0.98 | **Memory**: 2GB
- **Status**: Framework ready, requires Proxmox integration configuration

### Application Services (Deployed separately - moved to 10.101.1.x)
- **DOCKER01/02**: Container hosts (10.101.1.51-52)
- **PLEX01/02**: Media servers (10.101.1.61-62)
- **AMP01/02**: Game servers (10.101.1.81-82)

=======
- **SQL01/02**: PostgreSQL HA with streaming replication
- **VMID**: 112-113 | **IPs**: 10.101.0.71-72 | **Memory**: 2GB each

### Database Tier: MariaDB Cluster (Terraform Ready - Deploy First)
- **DB01/02**: MariaDB HA with master-slave replication
- **VMID**: 116-117 | **IPs**: 10.101.0.73-74 | **Memory**: 2GB each

### Tier 1: Observability (Terraform Ready - Deploy Second)
- **MONITOR01/02**: Prometheus + Grafana cluster
- **VMID**: 114-115 | **IPs**: 10.101.0.101-102 | **Memory**: 1.5GB each

### Tier 2: Security (Terraform Framework - Deploy Second)
- **VAULT01/02**: HashiCorp Vault HA cluster
- **VMID**: 118-119 | **IPs**: 10.101.0.81-82 | **Memory**: 1GB each
- **Status**: Framework ready, requires post-deployment configuration

### Tier 3: Backup (Terraform Framework - Deploy Third)
- **BACKUP01**: Proxmox Backup orchestration
- **VMID**: 120 | **IP**: 10.101.0.91 | **Memory**: 1GB
- **Status**: Framework ready, requires Proxmox integration configuration

>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
---

## Deployment Order & Timeline

```
Phase 1 (This Week - Database Foundation):
<<<<<<< HEAD
├── Deploy PGSQL01/02 PostgreSQL cluster (5 min Terraform + 30 min config)
=======
├── Deploy SQL01/02 PostgreSQL cluster (5 min Terraform + 30 min config)
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
│   ├── Install PostgreSQL
│   ├── Configure streaming replication
│   └── Set up Keepalived VIP (10.101.0.70)
│
├── Deploy DB01/02 MariaDB cluster (5 min Terraform + 30 min config)
│   ├── Install MariaDB
│   ├── Configure master-slave replication
│   └── Set up Keepalived VIP (10.101.0.75)
│
Phase 2 (Next Week - Observability):
├── Deploy MONITOR01/02 (2-3 hours)
│   ├── Configure Prometheus scrape configs
│   ├── Deploy Grafana dashboards
<<<<<<< HEAD
│   └── Integrate with PGSQL01/02 (state backend)
=======
│   └── Integrate with SQL01/02 (state backend)
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
│
Phase 3 (Week After - Security):
├── Deploy VAULT01/02 (3-4 hours)
│   ├── Initialize Raft backend
│   ├── Configure auto-unseal
│   └── Set up auth methods
│
Phase 4 (Final Week - Backup):
└── Deploy BACKUP01 + Proxmox integration (2-3 hours)
    ├── Configure backup policies
    ├── Set up storage targets
    └── Schedule automated backups
```

---

## Deployment Procedures

### Prerequisites
```bash
cd /home/ayoung/projects/phoenixstack/terraform

# Ensure Terraform state is current
terraform init
terraform plan
```

<<<<<<< HEAD
### Deploy PGSQL01/02 (PostgreSQL Cluster)
=======
### Deploy SQL01/02 (PostgreSQL Cluster)
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
```bash
# Plan deployment
terraform plan -target=module.sql01 -target=module.sql02

# Apply deployment
terraform apply -target=module.sql01 -target=module.sql02

# Verify containers are running
pct list | grep -E "112|113"

# SSH to containers
<<<<<<< HEAD
ssh root@10.101.0.71  # PGSQL01
ssh root@10.101.0.72  # PGSQL02
=======
ssh root@10.101.0.71  # SQL01
ssh root@10.101.0.72  # SQL02
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
```

**Post-Deployment Configuration**:
1. Install PostgreSQL on both containers:
   ```bash
   apt update && apt install -y postgresql postgresql-contrib
   ```
<<<<<<< HEAD
2. Configure PGSQL01 as primary:
   - Set `wal_level = replica` in postgresql.conf
   - Create replication user: `createuser -U postgres --replication replicator`
3. Configure SQL02 as standby:
   - `pg_basebackup -h pgsql01 -D /var/lib/postgresql/14/main -U replicator`
   - Enable recovery: `touch /var/lib/postgresql/14/main/recovery.signal`
4. Set up Keepalived VIP (10.101.0.70) for automatic failover
5. Test replication: Monitor `SELECT * FROM pg_stat_replication` on PGSQL01
=======
2. Configure SQL01 as primary:
   - Set `wal_level = replica` in postgresql.conf
   - Create replication user: `createuser -U postgres --replication replicator`
3. Configure SQL02 as standby:
   - `pg_basebackup -h sql01 -D /var/lib/postgresql/14/main -U replicator`
   - Enable recovery: `touch /var/lib/postgresql/14/main/recovery.signal`
4. Set up Keepalived VIP (10.101.0.70) for automatic failover
5. Test replication: Monitor `SELECT * FROM pg_stat_replication` on SQL01
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072

### Deploy DB01/02 (MariaDB Cluster)
```bash
# Plan deployment
terraform plan -target=module.db01 -target=module.db02

# Apply deployment
terraform apply -target=module.db01 -target=module.db02

# Verify containers are running
<<<<<<< HEAD
pct list | grep -E "117|118"

# SSH to containers
ssh root@10.101.0.75  # DB01
ssh root@10.101.0.76  # DB02
=======
pct list | grep -E "116|117"

# SSH to containers
ssh root@10.101.0.73  # DB01
ssh root@10.101.0.74  # DB02
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
```

**Post-Deployment Configuration**:
1. Install MariaDB on both containers:
   ```bash
   apt update && apt install -y mariadb-server mariadb-client
   ```
2. Configure DB01 as primary:
   - Set `server-id = 1` in `/etc/mysql/mariadb.conf.d/50-server.cnf`
   - Enable binary logging: `log_bin = /var/log/mysql/mysql-bin.log`
   - Create replication user: `GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'db02' IDENTIFIED BY 'password'`
3. Configure DB02 as replica:
   - Set `server-id = 2` in config
   - `CHANGE MASTER TO MASTER_HOST='db01', MASTER_USER='replicator', MASTER_PASSWORD='password', MASTER_LOG_FILE='mysql-bin.000001', MASTER_LOG_POS=0;`
   - `START SLAVE;`
4. Set up Keepalived VIP (10.101.0.75) for automatic failover
5. Test replication: Monitor `SHOW SLAVE STATUS\G` on DB02

### Deploy MONITOR01/02
```bash
# Plan deployment
terraform plan -target=module.monitor01 -target=module.monitor02

# Apply deployment
terraform apply -target=module.monitor01 -target=module.monitor02

# Verify containers are running
<<<<<<< HEAD
pct list | grep -E "119|120"

# SSH to containers
ssh root@10.101.0.91  # MONITOR01
ssh root@10.101.0.92  # MONITOR02
=======
pct list | grep -E "114|115"

# SSH to containers
ssh root@10.101.0.101  # MONITOR01
ssh root@10.101.0.102  # MONITOR02
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
```

**Post-Deployment Tasks**:
1. Install Prometheus on MONITOR01:
   ```bash
   apt update && apt install -y prometheus
   ```
2. Install Grafana on MONITOR02:
   ```bash
   apt update && apt install -y grafana-server
   ```
3. Configure Prometheus to scrape all services (bastion, dns, proxy, docker, sql, db, etc.)
4. Create Grafana data source pointing to Prometheus on MONITOR01
5. Import dashboards for each service tier

### Deploy VAULT01/02 (Framework Ready)
```bash
# Plan deployment
terraform plan -target=module.vault01 -target=module.vault02

# Apply deployment
terraform apply -target=module.vault01 -target=module.vault02

# Verify containers are running
pct list | grep -E "118|119"

# SSH to containers
ssh root@10.101.0.81  # VAULT01
ssh root@10.101.0.82  # VAULT02
```

**Post-Deployment Configuration Required**:
1. Install HashiCorp Vault on both containers:
   ```bash
   # On VAULT01 and VAULT02
   apt update && apt install -y vault
   ```
2. Initialize Vault with Raft backend:
   ```bash
   # On VAULT01 (leader node)
   vault operator init -key-shares=3 -key-threshold=2
   vault operator unseal
   ```
3. Join VAULT02 to cluster:
   ```bash
   # On VAULT02
   vault operator raft join http://vault01:8200
   vault operator unseal
   ```
4. Configure auth methods (Kubernetes, JWT, OIDC via Authentik)
5. Migrate 1Password secrets to Vault

### Deploy BACKUP01 (Framework Ready)
```bash
# Plan deployment
terraform plan -target=module.backup01

# Apply deployment
terraform apply -target=module.backup01

# Verify container is running
<<<<<<< HEAD
pct list | grep 123

# SSH to container
ssh root@10.101.0.98  # BACKUP01
=======
pct list | grep 120

# SSH to container
ssh root@10.101.0.91  # BACKUP01
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
```

**Post-Deployment Configuration Required**:
1. Install Proxmox Backup client:
   ```bash
   apt update && apt install -y proxmox-backup-client
   ```
2. Configure authentication with Proxmox Backup Server (if external) or local storage
3. Set up Proxmox API token for backup automation
4. Create backup policies:
<<<<<<< HEAD
   - PGSQL01/02: Daily full + hourly incremental (retain 30 days)
=======
   - SQL01/02: Daily full + hourly incremental (retain 30 days)
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
   - MONITOR01/02: Daily full (retain 14 days)
   - AUTHENTIK01/02: Daily full (retain 30 days)
   - Other services: Weekly full (retain 8 weeks)
5. Schedule automated backup jobs via cron or Proxmox API

---

## Service Architecture & Integration

<<<<<<< HEAD
### PGSQL01/02: PostgreSQL HA Cluster
**Architecture**: Active-Passive with streaming replication
- **PGSQL01** (Primary): Accepts reads and writes
- **PGSQL02** (Standby): Replicates from PGSQL01, handles read-only queries
=======
### SQL01/02: PostgreSQL HA Cluster
**Architecture**: Active-Passive with streaming replication
- **SQL01** (Primary): Accepts reads and writes
- **SQL02** (Standby): Replicates from SQL01, handles read-only queries
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
- **Storage**: SSD pool for high I/O
- **Failover**: Keepalived VIP at 10.101.0.70 for automatic failover
- **Integration Points**:
  - Shared backend for AUTHENTIK01/02
  - Shared backend for GRAFANA (MONITOR02)
  - Shared backend for VAULT01/02 (Raft logs)

**Key Considerations**:
- PostgreSQL WAL (Write-Ahead Logging) ensures durability
<<<<<<< HEAD
- Streaming replication keeps PGSQL02 in sync with <1ms lag
- Manual promotion of PGSQL02 to primary if PGSQL01 fails
=======
- Streaming replication keeps SQL02 in sync with <1ms lag
- Manual promotion of SQL02 to primary if SQL01 fails
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
- Backup via pg_basebackup (full block-level copies)

### DB01/02: MariaDB HA Cluster
**Architecture**: Active-Passive with master-slave replication
- **DB01** (Master): Accepts writes, binary logs all changes
- **DB02** (Slave): Applies binary logs from DB01
- **Storage**: SSD pool for high I/O
- **Failover**: Keepalived VIP at 10.101.0.75 for automatic failover
- **Integration Points**:
  - Applications preferring MySQL syntax
  - Legacy application databases
  - Optional lightweight workload tier

**Key Differences from PostgreSQL**:
- MySQL uses binary logging vs PostgreSQL's WAL
- Replication based on binlog events vs streaming bytes
- Semi-synchronous replication available for stronger guarantees
- Faster write performance in many scenarios

### MONITOR01/02: Observability Cluster
**Architecture**: Active-Active with shared storage (optional remote write)
- **MONITOR01** (Prometheus): Metrics collection, alerting engine
- **MONITOR02** (Grafana): Dashboards, multi-user access, alerting UI
- **Integration Points**:
  - Scrapes all 11 core services + SQL/Vault/Backup
  - Stores metrics in MONITOR01 local storage (or external time-series DB)
<<<<<<< HEAD
  - Grafana uses PGSQL01 as backend for HA dashboard state
=======
  - Grafana uses SQL01 as backend for HA dashboard state
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072

**Key Metrics to Track**:
- CPU/Memory/Disk for all containers
- Network I/O for each service
<<<<<<< HEAD
- PostgreSQL replication lag (PGSQL01 ↔ PGSQL02)
=======
- PostgreSQL replication lag (SQL01 ↔ SQL02)
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
- Vault token/lease counts
- Backup job status and duration
- Traefik request latency/error rates

### VAULT01/02: Secrets Management Cluster
**Architecture**: Raft-based HA cluster
- **VAULT01** (Primary): Leader, processes all requests
- **VAULT02** (Standby): Raft follower, handles read requests
<<<<<<< HEAD
- **Storage**: PostgreSQL in PGSQL01/02 (via Raft backend)
=======
- **Storage**: PostgreSQL in SQL01/02 (via Raft backend)
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
- **Encryption**: Raft logs encrypted with Vault transit engine
- **Integration Points**:
  - BASTION01/02: GitHub runner secrets
  - AUTHENTIK01/02: OIDC provider secrets
  - DOCKER01/02: Container registry credentials
  - PROXY01/02: Certificate secrets

**Key Secrets to Manage**:
- GitHub runner registration tokens
- Container registry authentication
- TLS certificates for Traefik
- OIDC provider credentials
- Database connection strings
- API keys for external integrations

### BACKUP01: Resilience & Recovery
**Architecture**: Centralized backup orchestration
- **BACKUP01**: Backup policy engine, Proxmox API integration
- **Storage Targets**:
  - Option 1: NFS mount to external storage
  - Option 2: S3-compatible object storage (Minio, AWS S3)
  - Option 3: Proxmox Backup Server (external appliance)
- **Backup Scope**:
  - Container filesystem (rootfs)
<<<<<<< HEAD
  - Database snapshots (PGSQL01/02)
=======
  - Database snapshots (SQL01/02)
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
  - Configuration backups (Authentik, Vault, Monitor)
  - Application data (Docker volumes)

**Backup Windows**:
- Daily at 02:00 UTC (low activity period)
- Retention: 30 days for critical (SQL/Vault), 14 days for others
- Recovery testing: Monthly full container restore simulation

---

## Performance & Resource Considerations

### CPU & Memory Allocation
| Service | VMID | Cores | RAM | Notes |
|---------|------|-------|-----|-------|
<<<<<<< HEAD
| PGSQL01 | 115 | 2 | 2GB | PostgreSQL primary, WAL buffer |
| PGSQL02 | 116 | 2 | 2GB | PostgreSQL standby, streaming replication |
| DB01 | 117 | 2 | 2GB | MariaDB master, binary logging |
| DB02 | 118 | 2 | 2GB | MariaDB slave, replication lag tracking |
| MONITOR01 | 119 | 2 | 2GB | Prometheus time-series retention |
| MONITOR02 | 120 | 2 | 2GB | Grafana dashboards + database |
| VAULT01 | 121 | 2 | 2GB | Raft consensus, key rotation |
| VAULT02 | 122 | 2 | 2GB | Raft follower, read requests |
| BACKUP01 | 123 | 2 | 2GB | Backup orchestration (minimal overhead) |

**Total New Resource Addition**: 18 cores, 18GB RAM
**Current Utilization**: Estimated 40-50% of typical homelab capacity

### Storage Sizing
- **PGSQL01/02**: 32GB each (PostgreSQL WAL, data, snapshots)
=======
| SQL01 | 112 | 2 | 2GB | PostgreSQL primary, WAL buffer |
| SQL02 | 113 | 2 | 2GB | PostgreSQL standby, streaming replication |
| DB01 | 116 | 2 | 2GB | MariaDB master, binary logging |
| DB02 | 117 | 2 | 2GB | MariaDB slave, replication lag tracking |
| MONITOR01 | 114 | 2 | 1.5GB | Prometheus time-series retention |
| MONITOR02 | 115 | 2 | 1.5GB | Grafana dashboards + database |
| VAULT01 | 118 | 2 | 1GB | Raft consensus, key rotation |
| VAULT02 | 119 | 2 | 1GB | Raft follower, read requests |
| BACKUP01 | 120 | 2 | 1GB | Backup orchestration (minimal overhead) |

**Total New Resource Addition**: 18 cores, 14.5GB RAM
**Current Utilization**: Estimated 40-50% of typical homelab capacity

### Storage Sizing
- **SQL01/02**: 32GB each (PostgreSQL WAL, data, snapshots)
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
- **DB01/02**: 32GB each (MariaDB binlog, data, snapshots)
- **MONITOR01/02**: 20GB each (Prometheus and Grafana data)
- **VAULT01/02**: 16GB each (Raft logs, minimal local state)
- **BACKUP01**: 16GB (policy configs, temporary staging)
- **Total**: 236GB SSD storage
- **Growth Rate**: Databases grow with application data; Prometheus grows ~1-2GB/day

**Monitoring Tip**: Set up Grafana alert on MONITOR01 for disk usage > 80%
<<<<<<< HEAD
**Backup Tip**: Backup both PGSQL01/02 and DB01/02 regularly; keep 30-day retention
=======
**Backup Tip**: Backup both SQL01/02 and DB01/02 regularly; keep 30-day retention
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072

---

## HA Patterns & Failover Behavior

### MONITOR Failover
- **Prometheus01 down**: Queries fail over to Prometheus02 if configured with remote-write
- **Grafana02 down**: Users access backup Grafana instance (manual intervention)
- **Both down**: Historical data preserved in storage; re-deploy from Terraform

### VAULT Failover
- **VAULT01 down**: VAULT02 automatically assumes leadership (Raft election)
- **VAULT02 down**: No impact; VAULT01 continues serving requests
<<<<<<< HEAD
- **Both down**: Unseal data remains in PGSQL01/02; recover by reinitializing from backup
=======
- **Both down**: Unseal data remains in SQL01/02; recover by reinitializing from backup
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072

### BACKUP Failover
- **BACKUP01 down**: Scheduled backups pause; can be rescheduled manually
- **Storage down**: Backup jobs fail gracefully; retry on next window
- **Recovery**: BACKUP01 data restored from last working backup

---

## Security Considerations

### Network Isolation
- All services on VLAN 10 (Management network)
- Firewall rules should restrict inter-service communication to necessary ports only
- MONITOR: Prometheus (9090), Grafana (3000)
- VAULT: HTTP API (8200)
- BACKUP: SSH (22), Proxmox API client

### Encryption & Authentication
- **Vault**: All data at-rest encrypted, auto-unseal via transit engine
- **Backups**: Encrypted in transit (SSH) and at-rest (if using S3 with SSE)
- **Monitoring**: Prometheus metrics are not sensitive; Grafana should require authentication
- **Certificate Management**: Use Vault's PKI engine for all certificate rotation

### Access Control
```
MONITOR01/02 (Monitoring):
  - SSH: SSH keys only (from BASTION01/02)
  - Grafana UI: Disable anonymous access, integrate with Authentik OIDC
  - Prometheus: No auth (internal metrics), restrict firewall access
  
VAULT01/02 (Secrets):
  - SSH: SSH keys only (from BASTION01/02)
  - HTTP API: Require TLS + authentication (tokens, JWT, OIDC)
  - No direct external access (proxy via BASTION or PROXY if needed)
  
BACKUP01 (Backups):
  - SSH: SSH keys only (from BASTION01/02)
  - Proxmox API: API token with minimal privileges (backup only)
  - Storage: Credentials managed by Vault
```

---

## Monitoring & Troubleshooting

### Key Health Indicators
```bash
# Check Prometheus scrape targets
curl http://10.101.0.101:9090/api/v1/targets

# Check Vault seal status
vault status -address=http://10.101.0.81:8200

# Check backup job status
pct exec 120 -- proxmox-backup-client list backups

# Monitor resource usage
pct resources 114 115 118 119 120
```

### Common Issues & Resolution

| Issue | Symptom | Root Cause | Fix |
|-------|---------|-----------|-----|
| Prometheus OOM | Container exits | Too many metrics/targets | Reduce scrape frequency, add retention limit |
| Vault sealed | Can't authenticate | Server crash, power loss | Unseal with key shares on VAULT01/02 |
| Backup space full | Backup jobs fail | Storage exhausted | Archive old backups, expand storage |
| Grafana UI slow | Dashboard timeouts | Too many panels/queries | Optimize dashboard queries, increase RAM |

---

## Next Steps & Future Enhancements

### After Tier 1-3 Deployment
1. ✅ Test Prometheus scraping all services
2. ✅ Create Grafana dashboards for each service tier
3. ✅ Set up Vault authentication for all services
4. ✅ Execute first backup restore test
5. ⏳ Implement alerting rules in Prometheus
6. ⏳ Configure automatic failover for Vault (if needed)

### Tier 4: Advanced Automation (Future)
Consider after stabilizing Tier 1-3:
- **CI/CD Runners**: Local CI infrastructure (Jenkins, GitLab Runner, Drone)
- **Observability**: Loki log aggregation, Promtail log shipping
- **Advanced Backup**: Velero for Kubernetes-style application backups
- **Advanced Networking**: Load balancer tier (HAProxy, Keepalived)

---

## Related Documentation

- [INFRASTRUCTURE_STATUS.md](INFRASTRUCTURE_STATUS.md) - Overall deployment status
- [HA_REDUNDANCY_TODO.md](HA_REDUNDANCY_TODO.md) - HA implementation roadmap
- [mac-address-scheme.md](mac-address-scheme.md) - MAC address allocations
- [terraform/README.md](terraform/README.md) - Terraform deployment guide
