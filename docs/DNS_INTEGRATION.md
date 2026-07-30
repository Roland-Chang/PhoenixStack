# DNS Integration & Records

**Purpose**: DNS record management system for PhoenixStack - unified quick reference and architecture documentation

**Status**: ✅ Infrastructure Ready (Phase 2 - Awaiting Deployment)  
**Last Updated**: 2026-07-29  
**Previous Update**: 2026-06-18 (Consolidated IP scheme)  
**Current Phase**: 🔄 Phase 2 (DNS Stability) - Infrastructure code ready, awaiting deployment

---

## 📋 Quick Reference - Current DNS Records (27 total)

### Manual Infrastructure (3)
```
pve01.phoenix.stack → 10.101.0.11
ipmi-pve01.phoenix.stack → 10.101.0.1  
unas01.phoenix.stack → 10.101.0.101
```

### Auto-Generated from Terraform (24)
```
pgsql01-02, db01-02, monitor01-02, authentik01-02, docker01-02, 
proxy01-02, vault01-02, dns01-02, bastion01-02, backup01, plex01
```

---

## 🔧 Common Tasks

### Add New Manual DNS Record
```bash
# 1. Edit the manual records file
nano ansible/roles/pihole/defaults/manual-dns-records.yml

# 2. Add new entry (YAML format):
#   - hostname: newservice.phoenix.stack
#     ip: 10.101.0.XXX

# 3. Deploy
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/dns_pihole.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id ansible/vault/.vault_pass
```

### Test DNS Resolution
```bash
# Test from workstation
dig @10.101.0.201 pgsql01.phoenix.stack +short

# Test from container
ansible dns01 -i ansible/inventory/hosts.yml \
  -m shell -a "docker exec pihole-pihole-1 dig @127.0.0.1 pgsql01.phoenix.stack +short"

# List all records in container
ansible dns01 -i ansible/inventory/hosts.yml \
  -m shell -a "docker exec pihole-pihole-1 grep phoenix.stack /etc/hosts"
```

### View PiHole Web UI
- DNS01: http://10.101.0.201/admin
- DNS02: http://10.101.0.202/admin
- Username: admin
- Password: From ansible/vault/pihole.yml

---

## 📝 File Structure

```
ansible/
  roles/pihole/
    defaults/
      main.yml                          # 24 Terraform-generated records
      manual-dns-records.yml            # Manual/external infrastructure
    templates/
      docker-compose.yml.j2             # Merges both record sources
      custom.list.j2                    # Reference format (unused)
      05-local-records.conf.j2          # dnsmasq format (unused)
    tasks/
      main.yml                          # Deployment tasks
  playbooks/
    dns_pihole.yml                      # Deploy playbook
  vault/
    pihole.yml                          # Vault with PiHole password

docs/
  DNS_INTEGRATION.md                    # This file - complete reference
```

---

## System Architecture

The Phoenix infrastructure has a unified, IaC-based DNS record management system. DNS records are auto-generated from Terraform module definitions and manually maintained for non-Terraform infrastructure.

### Record Sources

**1. Auto-Generated from Terraform**  
**File:** `ansible/roles/pihole/defaults/main.yml`  
**Source:** Automatically generated from all Terraform modules

Current DNS records are maintained in the Ansible role `pihole/defaults/main.yml` and include all services across:
- **Infrastructure tier** (10.101.0.x): Bastion, DNS, Proxy, Auth, Databases, Vault, Monitor, Backup
- **Application tier** (10.101.1.x): Docker, Plex, AMP game servers
- **Non-Terraform** (Fixed IPs): PVE01, iDRAC, UNAS01 storage

**2. Manual/External (IaC-maintained)**  
**File:** `ansible/roles/pihole/defaults/main.yml` (manual_records section)  
**Source:** Manually maintained for non-Terraform infrastructure

```
- pve01.phoenix.stack → 10.101.0.11 (Proxmox hypervisor)
- unas01.phoenix.stack → 10.101.0.101 (Network storage NAS)
```

### Deployment Mechanism

1. **Variable Loading:** Ansible loads DNS records from `ansible/roles/pihole/defaults/main.yml`
2. **DNS Server Deployment:** DNS01/DNS02 containers run PiHole with auto-generated records
3. **Update Pattern:** Terraform changes → Ansible updates DNS records → PiHole deployed
   ```jinja2
   extra_hosts:
   {% for record in (pihole_manual_records | default([])) + (pihole_local_records | default([])) %}
     {{ record.hostname }}: "{{ record.ip }}"
   {% endfor %}
   ```
4. **Container Injection:** Docker Compose's `extra_hosts` parameter injects all merged records into container `/etc/hosts`
5. **DNS Resolution:** PiHole DNS server reads `/etc/hosts` natively, making all records resolvable

---

## Current Implementation Status

### ✅ Completed
- Docker-compose template supports mapping format for `extra_hosts`
- Manual records file created with example entries
- Both record sources automatically merged
- PiHole containers deployed with all 27 records injected
- DNS resolution verified (internal and external)

### Files Modified
- `ansible/roles/pihole/templates/docker-compose.yml.j2` - Updated to merge both sources
- `ansible/roles/pihole/templates/custom.list.j2` - Updated with both sources (reference)
- `ansible/roles/pihole/defaults/manual-dns-records.yml` - Created for manual entries
- `ansible/roles/pihole/tasks/main.yml` - Removed unnecessary include_vars (auto-loading works)

---

## Usage Guide

### Adding New Infrastructure Records

Edit `ansible/roles/pihole/defaults/manual-dns-records.yml`:

```yaml
pihole_manual_records:
  - hostname: newhost.phoenix.stack
    ip: 10.101.0.XXX
  - hostname: another-service.phoenix.stack
    ip: 10.101.0.YYY
```

### Deploying Updated Records

```bash
cd /home/ayoung/projects/phoenixstack

# Deploy with vault password from .vault_pass file
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/dns_pihole.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id ansible/vault/.vault_pass
```

### Testing DNS Resolution

**From workstation (external):**
```bash
dig @10.101.0.201 pgsql01.phoenix.stack +short
# Returns: 10.101.0.71
```

**From container (internal):**
```bash
ansible dns01 -i ansible/inventory/hosts.yml \
  -m shell -a "docker exec pihole-pihole-1 dig @127.0.0.1 pgsql01.phoenix.stack +short"
# Returns: 10.101.0.71
```

**Verify all records in container:**
```bash
ansible dns01 -i ansible/inventory/hosts.yml \
  -m shell -a "docker exec pihole-pihole-1 cat /etc/hosts | grep phoenix.stack"
```

---

## Design Advantages

1. **Terraform-agnostic:** Manual records can be added for any resource (physical, external, legacy)
2. **Maintainable:** Clear separation between IaC-generated and manually-managed entries
3. **Scalable:** Easy to expand manual-dns-records.yml for future infrastructure
4. **Reliable:** Docker `extra_hosts` approach is more stable than database-based DNS injection
5. **Auditable:** All DNS records are version-controlled in Git
6. **Automated:** Playbook handles both sources transparently

---

## Naming Convention

All infrastructure DNS records follow the pattern:
```
hostname.phoenix.stack → IP_ADDRESS
```

- **Out-of-band management:** `ipmi-hostname.phoenix.stack`
- **Failover/HA pairs:** `hostname01.phoenix.stack`, `hostname02.phoenix.stack`
- **FQDNs:** Always use full `phoenix.stack` domain

---

## ✅ Validation Checklist

- [ ] Both manual and auto records merge correctly in docker-compose template
- [ ] PiHole containers running and healthy: `docker ps | grep pihole`
- [ ] Records injected in container: `docker exec pihole-pihole-1 grep phoenix.stack /etc/hosts`
- [ ] DNS resolves from workstation: `dig @10.101.0.201 pgsql01.phoenix.stack`
- [ ] DNS resolves from container: `docker exec pihole-pihole-1 dig @127.0.0.1 pgsql01.phoenix.stack`
- [ ] Playbook runs without errors: Ansible playbook DNS deployment succeeds

---

## Next Steps (Optional Enhancements)

1. **Add more manual entries:** Storage interfaces, backup targets, monitoring endpoints
2. **DNS failover:** Configure secondary DNS (dns02) as redundant PiHole
3. **Dynamic DNS:** Integrate external DNS provider for public-facing services
4. **DNSSEC validation:** Already enabled (see pihole_dnssec in main.yml)
5. **Split-horizon DNS:** Configure different records for different network segments

---

## Troubleshooting

### DNS records don't appear
1. Check manual-dns-records.yml YAML syntax: `ansible-playbook --syntax-check`
2. Verify docker-compose.yml was generated correctly: `cat /opt/pihole/docker-compose.yml`
3. Check container /etc/hosts: `docker exec pihole-pihole-1 cat /etc/hosts`
4. Restart PiHole: `docker-compose -f /opt/pihole/docker-compose.yml restart`

### Records in web UI don't match /etc/hosts
- PiHole's web UI only shows database-stored records
- `/etc/hosts` records resolve but don't appear in UI (expected behavior)
- Both sources work correctly for DNS resolution
