# DNS Quick Reference

## 📋 Current DNS Records (27 total)

### Manual Infrastructure (3)
```
pve01.phoenix.stack → 10.101.0.11
ipmi-pve01.phoenix.stack → 10.101.0.11  
unas01.phoenix.stack → 10.101.0.101
```

### Auto-Generated from Terraform (24)
```
pgsql01-02, db01-02, monitor01-02, authentik01-02, docker01-02, 
proxy01-02, vault01-02, dns01-02, bastion01-02, backup01, plex01
```

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
  DNS_RECORDS_MANAGEMENT.md             # Complete usage guide
  DNS_INTEGRATION_SUMMARY.md            # System architecture
```

## ✅ Validation Checklist

- [ ] Both manual and auto records merge correctly in docker-compose template
- [ ] PiHole containers running and healthy: `docker ps | grep pihole`
- [ ] Records injected in container: `docker exec pihole-pihole-1 grep phoenix.stack /etc/hosts`
- [ ] DNS resolves from workstation: `dig @10.101.0.201 pgsql01.phoenix.stack`
- [ ] DNS resolves from container: `docker exec pihole-pihole-1 dig @127.0.0.1 pgsql01.phoenix.stack`
- [ ] Playbook runs without errors: Ansible playbook DNS deployment succeeds
