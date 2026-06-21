# Local DNS Records Management

This playbook manages local DNS records for the Phoenix infrastructure across two sources:

## 1. **Auto-Generated Records** (Terraform-managed)
**File:** `ansible/roles/pihole/defaults/main.yml`  
**Source:** Automatically generated from all Terraform infrastructure

These are rebuilt automatically when you deploy new services via Terraform. They include:
- pgsql01/02 (PostgreSQL)
- db01/02 (MariaDB)
- authentik01/02, docker01/02, proxy01/02, vault01/02, plex01, backup01, etc.

## 2. **Manual Records** (IaC-maintained but manual entries)
**File:** `ansible/roles/pihole/defaults/manual-dns-records.yml`  
**Source:** Manually maintained for out-of-band, physical, and external infrastructure

Update this file when you need to add:
- Physical hosts (Proxmox servers, storage devices)
- Out-of-band management interfaces (iDRAC, iLO, IPMI)
- External services not managed by Terraform
- Legacy systems

### Adding a New Manual DNS Record

Edit `ansible/roles/pihole/defaults/manual-dns-records.yml`:

```yaml
pihole_manual_records:
  - hostname: example.phoenix.stack
    ip: 10.101.0.XXX
```

### Deploying Changes

After editing either source, redeploy PiHole:

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/dns_pihole.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id ansible/vault/.vault_pass
```

Both DNS sources are automatically merged and deployed to PiHole's `extra_hosts` configuration and `/etc/pihole/custom.list`.

## Current Records

**Manual/External (manual-dns-records.yml):**
- pve01.phoenix.stack → 10.101.0.11
- ipmi-pve01.phoenix.stack → 10.101.0.11
- unas01.phoenix.stack → 10.101.0.101

**Auto-Generated from Terraform (main.yml):**
- 24 service entries (pgsql, db, monitor, authentik, docker, proxy, vault, etc.)

Total: 27 DNS records automatically managed and deployed
