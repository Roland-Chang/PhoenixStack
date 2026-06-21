# PhoenixStack: Existing Infrastructure Configuration Guide

**Current Focus**: Configure DNS, Proxy, and Authentication for 11 existing containers  
**Timeline**: 3-4 days for full configuration  
**Prerequisite**: All 11 containers deployed and running via Terraform

---

## Overview: What Needs Configuration

| Tier | Service | Containers | Current Status | Next Step |
|------|---------|-----------|-----------------|-----------|
| **DNS** | PiHole | DNS01/02 | Running | Configure DNS resolution & ad-blocking |
| **Proxy** | Traefik | PROXY01/02 | Running | Configure reverse proxy & load balancing |
| **Auth** | Authentik | AUTHENTIK01/02 | Running | Configure SSO (blocked on SQL tier) |
| **Bastion** | SSH + Runners | BASTION01/02 | ✅ Configured | No action needed |
| **Docker** | Application Host | DOCKER01/02 | Running | Deferred (Swarm?) |
| **Media** | Plex | PLEX01 | Running | Configuration TBD |

---

## Phase 1A: DNS01/02 - PiHole Setup (RECOMMENDED STARTING POINT)

**Estimated Duration**: 30-45 minutes  
**Risk Level**: Low (isolated DNS tier)  
**Complexity**: Easy (existing Ansible playbook)

### Step 1: Verify DNS01/02 Containers Running

```bash
# List containers
pct list | grep -E "dns01|dns02"

# Expected output:
#  101  dns01    running   -   2    2048
#  102  dns02    running   -   2    2048

# SSH into DNS01
ssh root@10.101.0.201

# Verify networking
hostname
ip addr show eth0 | grep "inet "
ping 10.101.0.254  # Gateway
```

### Step 2: Update Ansible Inventory

Check current inventory:

```bash
cat /home/ayoung/projects/phoenixstack/ansible/inventory/hosts.yml | grep -A 5 "dns01"
```

If DNS01/02 are not listed, add them:

```bash
# Edit inventory
nano /home/ayoung/projects/phoenixstack/ansible/inventory/hosts.yml

# Add this section:
dns:
  children:
    dns_primary:
      hosts:
        dns01:
          ansible_host: 10.101.0.201
          ansible_user: root
          ansible_port: 22
    dns_secondary:
      hosts:
        dns02:
          ansible_host: 10.101.0.202
          ansible_user: root
          ansible_port: 22
```

### Step 3: Apply Base Configuration

```bash
cd /home/ayoung/projects/phoenixstack

# Apply DNS base configuration
ansible-playbook -i ansible/inventory/hosts.yml \
  -e "@ansible/vault/pihole.yml" \
  ansible/playbooks/dns_base.yml

# Expected: 20+ tasks completed successfully
```

### Step 4: Deploy PiHole

```bash
# Deploy PiHole on both DNS01 and DNS02
ansible-playbook -i ansible/inventory/hosts.yml \
  -e "@ansible/vault/pihole.yml" \
  ansible/playbooks/dns_pihole.yml

# Expected output:
# ✓ dns01 PiHole deployment complete
# ✓ dns02 PiHole deployment complete
```

### Step 5: Verify PiHole Web Interface

```bash
# Access PiHole admin panels
# DNS01: http://10.101.0.201/admin
# DNS02: http://10.101.0.202/admin

# Username: admin
# Password: [from ansible/vault/pihole.yml - pihole_admin_password]

# Check inside containers
ssh root@10.101.0.201 "docker ps | grep pihole"
ssh root@10.101.0.202 "docker ps | grep pihole"

# Test DNS resolution
nslookup example.com 10.101.0.201
nslookup example.com 10.101.0.202

# Query blocklist status
ssh root@10.101.0.201 "curl -s http://127.0.0.1:80/admin/api.php/stats"
```

### Step 6: Update Infrastructure DNS

Once DNS01/02 are working, update all containers to use them:

```bash
# On BASTION01 (or run via Ansible)
for vm in 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120; do
  echo "Updating DNS for container $vm..."
  pct exec $vm -- bash -c 'echo "nameserver 10.101.0.201" > /etc/resolv.conf'
  pct exec $vm -- bash -c 'echo "nameserver 10.101.0.202" >> /etc/resolv.conf'
done

# Verify
pct exec 100 -- cat /etc/resolv.conf | grep nameserver
```

### Phase 1A Validation Checklist

- [ ] Both DNS01 and DNS02 containers running
- [ ] PiHole web interface accessible on both
- [ ] DNS queries resolve correctly (nslookup tests)
- [ ] Ad-blocking lists active and blocking ads
- [ ] All infrastructure containers using DNS01/02 as nameservers
- [ ] Cross-DNS failover works (query DNS02 when DNS01 down)

---

## Phase 1B: PROXY01/02 - Traefik Reverse Proxy Setup

**Estimated Duration**: 60-90 minutes  
**Risk Level**: Medium (ingress point for all services)  
**Complexity**: Medium (Traefik configuration)

### What Traefik Does

```
User Request (http://app.phoenix.stack)
    ↓
Traefik (PROXY01/02)
    ↓
Routes to backend service (e.g., Grafana, Authentik, etc.)
    ↓
Service responds
    ↓
Response through Traefik back to user
```

### Step 1: Verify PROXY01/02 Containers Running

```bash
# List containers
pct list | grep -E "proxy01|proxy02"

# Expected output:
#  103  proxy01  running   -   2    2048
#  104  proxy02  running   -   2    2048

# SSH into PROXY01
ssh root@10.101.0.31

# Verify networking
hostname
ip addr show eth0 | grep "inet "
ping 10.101.0.254  # Gateway
```

### Step 2: Install Traefik on Both Instances

```bash
# SSH to PROXY01
ssh root@10.101.0.31

# Install Docker
apt update
apt install -y docker.io docker-compose

# Enable Docker
systemctl enable docker
systemctl start docker

# Create Traefik configuration directory
mkdir -p /etc/traefik
cd /etc/traefik

# Create traefik.yml (main config)
cat > /etc/traefik/traefik.yml << 'EOF'
# Traefik Configuration
global:
  checkNewVersion: false
  sendAnonymousUsage: false

# API Dashboard
api:
  insecure: true
  dashboard: true
  address: ":8080"

# Entry Points
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

# Providers
providers:
  file:
    filename: /etc/traefik/dynamic.yml
    watch: true

# Enable metrics (for monitoring)
metrics:
  prometheus:
    addEntryPointsLabels: true
    addServicesLabels: true
EOF

# Create dynamic configuration (routing rules)
cat > /etc/traefik/dynamic.yml << 'EOF'
# Dynamic Traefik Configuration
# Routes for different services

http:
  routers:
    # Example: Grafana
    grafana:
      rule: "Host(`grafana.phoenix.stack`)"
      service: grafana
      entryPoint: web

    # Example: Authentik
    authentik:
      rule: "Host(`auth.phoenix.stack`) || Host(`authentik.phoenix.stack`)"
      service: authentik
      entryPoint: web

  services:
    grafana:
      loadBalancer:
        servers:
          - url: "http://10.101.0.102:3000"

    authentik:
      loadBalancer:
        servers:
          - url: "http://10.101.0.11:9000"
EOF

# Create docker-compose.yml for Traefik
cat > /etc/traefik/docker-compose.yml << 'EOF'
version: '3.8'

services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    restart: always
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /etc/traefik/traefik.yml:/traefik.yml:ro
      - /etc/traefik/dynamic.yml:/dynamic.yml:ro
    networks:
      - traefik

networks:
  traefik:
    driver: bridge
EOF

# Start Traefik
cd /etc/traefik
docker-compose up -d

# Verify running
docker ps | grep traefik

# Check dashboard
curl -s http://127.0.0.1:8080/dashboard/ | head -20
```

### Step 3: Replicate Configuration to PROXY02

```bash
# Copy entire Traefik config from PROXY01 to PROXY02
scp -r root@10.101.0.31:/etc/traefik/ /tmp/traefik_config

# SSH to PROXY02
ssh root@10.101.0.102

# Inside PROXY02:
apt update
apt install -y docker.io docker-compose

systemctl enable docker
systemctl start docker

# Copy config
scp -r /tmp/traefik_config /etc/traefik

# Start Traefik
cd /etc/traefik
docker-compose up -d

# Verify
docker ps | grep traefik
```

### Step 4: Configure UniFi Dream Machine Load Balancer

On your UniFi console (assuming you have access):

```
Routing & Firewall → Load Balancer → Create Pool:
  Name: "Traefik HA"
  Port: 80
  Addresses:
    - 10.101.0.31 (PROXY01)
    - 10.101.0.32 (PROXY02)
  Health check: /dashboard/ (HTTP 200-300)
  Failover: Automatic

Create Virtual Server:
  Service Port: 80
  Pool: "Traefik HA"
  VIP: 10.101.0.254:80 (or separate VIP)
```

### Step 5: Add Service Routes

Update `/etc/traefik/dynamic.yml` on both PROXY01 and PROXY02 with routes to your services. Example:

```bash
# SSH to PROXY01
ssh root@10.101.0.31

# Edit dynamic config
nano /etc/traefik/dynamic.yml

# Add routes (example):
http:
  routers:
    grafana:
      rule: "Host(`grafana.phoenix.stack`)"
      service: grafana
    
    prometheus:
      rule: "Host(`prometheus.phoenix.stack`)"
      service: prometheus
    
    authentik:
      rule: "Host(`auth.phoenix.stack`)"
      service: authentik

  services:
    grafana:
      loadBalancer:
        servers:
          - url: "http://10.101.0.102:3000"
    
    prometheus:
      loadBalancer:
        servers:
          - url: "http://10.101.0.101:9090"
    
    authentik:
      loadBalancer:
        servers:
          - url: "http://10.101.0.11:9000"

# Traefik auto-reloads when file changes
```

### Phase 1B Validation Checklist

- [ ] PROXY01 and PROXY02 containers running
- [ ] Docker and Traefik installed on both
- [ ] Traefik dashboard accessible on http://10.101.0.31:8080
- [ ] Traefik dashboard accessible on http://10.101.0.32:8080
- [ ] Dynamic routing configuration loaded
- [ ] Test route working: `curl -H "Host: grafana.phoenix.stack" http://10.101.0.31`
- [ ] Load balancer distributes traffic between PROXY01 and PROXY02
- [ ] Failover works: Stop Traefik on PROXY01, traffic still flows through PROXY02

---

## Phase 2: DNS01/02 - PiHole Gravity Replication

**Estimated Duration**: 30-45 minutes  
**Risk Level**: Low (DNS tier)  
**Complexity**: Medium (database replication)

**Status**: Planning (execute after Phase 1B verified)

This phase sets up active-active DNS replication so changes on either DNS01 or DNS02 sync automatically.

### High-Level Steps

1. Create replication user on DNS01
2. Enable PiHole Gravity Replication
3. Configure periodic sync via cron
4. Test: Make changes on DNS02, verify they appear on DNS01
5. Monitor replication lag

### Documentation Needed

- [ ] Create `docs/HA_PIHOLE_SETUP.md` with detailed steps
- [ ] Ansible role: `roles/pihole_replication/`

---

## Phase 3: AUTHENTIK01/02 - SSO Configuration

**Estimated Duration**: 90-120 minutes  
**Risk Level**: Medium (authentication layer)  
**Complexity**: High (integrated with SQL backends + Traefik)  
<<<<<<< HEAD
**Blocker**: Requires PGSQL01/02 cluster configured first

### High-Level Steps

1. Configure PGSQL01/02 PostgreSQL (Phase 1 of database tier)
=======
**Blocker**: Requires SQL01/02 cluster configured first

### High-Level Steps

1. Configure SQL01/02 PostgreSQL (Phase 1 of database tier)
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
2. Deploy AUTHENTIK01/02 containers
3. Configure Authentik database backend (PostgreSQL)
4. Setup Authentik HA replication
5. Integrate with Traefik (forward auth middleware)
6. Test: Login through Traefik-protected service

### Why This Is Blocked

<<<<<<< HEAD
Authentik uses PostgreSQL for persistent state (users, groups, sessions, tokens). Requires working PGSQL01/02 cluster first.

**Current Status**: 
- PGSQL01/02 containers deployed ✅
- PGSQL01/02 replication NOT YET CONFIGURED ⏳

### Unblock Path

1. Configure PGSQL01/02 PostgreSQL replication (follow [PHASED_DEPLOYMENT_EXECUTION.md](PHASED_DEPLOYMENT_EXECUTION.md#phase-1-postgresql-cluster-pgsql0102---current) Phase 1)
=======
Authentik uses PostgreSQL for persistent state (users, groups, sessions, tokens). Requires working SQL01/02 cluster first.

**Current Status**: 
- SQL01/02 containers deployed ✅
- SQL01/02 replication NOT YET CONFIGURED ⏳

### Unblock Path

1. Configure SQL01/02 PostgreSQL replication (follow [PHASED_DEPLOYMENT_EXECUTION.md](PHASED_DEPLOYMENT_EXECUTION.md#phase-1-postgresql-cluster-sql0102---current) Phase 1)
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
2. Return to this guide and follow AUTHENTIK section

---

## Recommended Execution Order

### Day 1 (Today or Tomorrow):
1. ✅ **Phase 1A**: Configure DNS01/02 with PiHole
2. ✅ **Phase 1B**: Configure PROXY01/02 with Traefik

### Day 2:
1. ✅ **Phase 1B Verification**: Test Traefik HA failover
2. ⏳ **Phase 2**: Configure PiHole Gravity replication (optional, nice-to-have)
3. 🚫 **Phase 3**: Wait (blocked on SQL configuration)

### Days 3-4 (Parallel):
<<<<<<< HEAD
1. 🔄 **Go back to database tier**: Configure PGSQL01/02 PostgreSQL (Phase 1)
=======
1. 🔄 **Go back to database tier**: Configure SQL01/02 PostgreSQL (Phase 1)
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
2. 🔄 **Go back to database tier**: Configure DB01/02 MariaDB (Phase 2)
3. 🔄 **Go back to database tier**: Configure MONITOR01/02 Prometheus/Grafana (Phase 3)

### Day 5:
1. ✅ **Phase 3**: Configure AUTHENTIK01/02 (once SQL01/02 verified working)

---

## Configuration Files Needed

### Vault Credentials

Update/verify these exist:

```bash
# PiHole credentials
cat /home/ayoung/projects/phoenixstack/ansible/vault/pihole.yml

# Expected structure:
pihole_admin_password: "SecurePassword123"
pihole_api_token: "API_TOKEN_HERE"
```

### Ansible Playbooks Existing

✅ `ansible/playbooks/dns_base.yml` - Basic system config  
✅ `ansible/playbooks/dns_pihole.yml` - PiHole installation  
❌ `ansible/playbooks/proxy_ha_sync.yml` - Traefik HA (to be created)  
❌ `ansible/playbooks/dns_ha_sync.yml` - PiHole replication (to be created)  
❌ `ansible/playbooks/authentik_base.yml` - Authentik setup (to be created)

---

## Quick Reference Commands

### DNS Verification
```bash
# DNS01 status
ssh root@10.101.0.201 "docker ps | grep pihole"
ssh root@10.101.0.201 "curl -s http://127.0.0.1/admin/api.php/stats | jq ."

# DNS queries
nslookup google.com 10.101.0.201
nslookup google.com 10.101.0.202
```

### Traefik Verification
```bash
# PROXY01 status
ssh root@10.101.0.31 "docker ps | grep traefik"
ssh root@10.101.0.31 "curl -s http://127.0.0.1:8080/ping"

# Route testing
curl -H "Host: grafana.phoenix.stack" http://10.101.0.31
curl -H "Host: grafana.phoenix.stack" http://10.101.0.32
```

### Container SSH Access
```bash
ssh root@10.101.0.201  # DNS01
ssh root@10.101.0.202  # DNS02
ssh root@10.101.0.31   # PROXY01
ssh root@10.101.0.32   # PROXY02
ssh root@10.101.0.11   # AUTHENTIK01
ssh root@10.101.0.12   # AUTHENTIK02
```

---

## Success Criteria

**Phase 1A Complete**:
- ✅ DNS01/02 resolving queries
- ✅ Ad-blocking lists active
- ✅ All containers using DNS01/02 as nameservers

**Phase 1B Complete**:
- ✅ Traefik dashboards accessible
- ✅ Routes working to backend services
- ✅ Load balancer distributing traffic
- ✅ Failover functional (one PROXY down, other still works)

**Phase 2 Complete**:
- ✅ PiHole configurations syncing between DNS01/02
- ✅ Replication lag minimal

**Phase 3 Ready**:
<<<<<<< HEAD
- ✅ PGSQL01/02 PostgreSQL replication verified
=======
- ✅ SQL01/02 PostgreSQL replication verified
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
- ✅ AUTHENTIK01/02 can connect to SQL backend
- ✅ Authentik forward-auth middleware in Traefik
- ✅ SSO login working through Traefik

---

## Next Steps

1. **Start Phase 1A**: Run DNS PiHole playbooks (30 min)
2. **Start Phase 1B**: Setup Traefik on PROXY01/02 (90 min)
3. **Verify HA**: Test failover scenarios
4. **Report Status**: Share completion updates before next phase

**Ready to start Phase 1A DNS configuration?**
