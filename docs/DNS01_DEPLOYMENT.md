# DNS01 - PiHole DNS Server Deployment Guide

## Overview

DNS01 is the primary internal DNS server for the PhoenixStack infrastructure. It runs PiHole for DNS resolution, ad blocking, and local domain management.

## Infrastructure Details

| Aspect | Value |
|--------|-------|
| **Container Name** | dns01 |
| **Container ID (VMID)** | 102 |
| **Proxmox Node** | pve01 |
| **IP Address** | 10.101.0.201 |
| **VLAN** | 10 (Management) |
| **MAC Address** | 02:aa:bb:cc:02:01 |
| **CPU Cores** | 2 |
| **RAM** | 2GB |
| **Storage** | 16GB SSD |
| **OS Template** | Ubuntu 24.04 LTS |

## Deployment Steps

### Phase 1: Deploy DNS01 Container via Terraform

```bash
# From /home/ayoung/projects/phoenixstack directory

# Plan the DNS01 deployment
terraform plan -target=module.dns01

# Apply the DNS01 deployment
terraform apply -target=module.dns01
```

Expected output:
- Container 102 created on pve01
- IP address: 10.101.0.21
- Hostname: dns01
- Ready for Ansible configuration

### Phase 2: Apply Base Configuration via Ansible

```bash
# Apply base system configuration
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/dns01_base.yml

# Expected: 25+ tasks completed successfully
# - System packages updated
# - SSH hardened
# - Timezone configured
# - Networking configured
# - Backup mount point verified
```

### Phase 3: Deploy PiHole (Future)

PiHole installation playbook: `ansible/playbooks/dns01_pihole.yml` (to be created)

Steps:
1. Install PiHole Docker container
2. Configure DNS records for phoenix.stack domain
3. Set up ad blocking lists
4. Configure DHCP server (if needed)

## Inventory Configuration

Add to `ansible/inventory/hosts.yml`:

```yaml
dns01:
  hosts:
    dns01:
      ansible_host: 10.101.0.21
      ansible_user: root
      ansible_port: 22
```

## Network Configuration

### DNS Resolution

Initially, DNS01 uses the gateway (10.101.0.254) as its nameserver. After PiHole is deployed:

- Update `terraform/dns01/auto.tfvars`:
  ```
  nameserver = "10.101.0.201"  # DNS01 itself
  ```
- Reapply Terraform to update DNS configuration
- Update other containers to use DNS01 as primary nameserver

### Local DNS Records

PiHole will be configured to resolve:
- `dns01.phoenix.stack` → 10.101.0.201
- `pve01.phoenix.stack` → 10.101.0.11
- `bastion01.phoenix.stack` → 10.101.0.20
- Other infrastructure hosts as needed

## Backup Configuration

After backup shares are mounted on pve01, add this to pve01's LXC config:

```
mp0: /mnt/pve/cifs-backups-dns01,mp=/mnt/backups
mp1: /mnt/pve/cifs-media,mp=/mnt/media
```

## Monitoring & Logging

Check DNS01 status:

```bash
# SSH to DNS01
ssh root@dns01

# Check system status
systemctl status

# View system logs
journalctl -xeu systemd | head -50
```

## Troubleshooting

### Container won't start

```bash
# On pve01, check container status
lxc-ls -f
lxc-start 102
lxc-console -n 102
```

### SSH not responding

```bash
# On pve01
pct start 102
pct exec 102 systemctl restart ssh
```

### DNS not resolving

```bash
# Inside DNS01
cat /etc/resolv.conf
systemctl status systemd-resolved
```

## Related Documentation

- [MAC Address Scheme](../mac-address-scheme.md) - MAC addressing strategy
- [Backup Share Setup](../BACKUP_SHARE_SETUP.md) - Configuring backup mounts
- [Bastion01 Deployment](../BASTION01_FRESH_DEPLOYMENT.md) - Similar deployment pattern
