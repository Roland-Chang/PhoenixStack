# Migration: ANSIBLE01 → BASTION01

**Date**: June 8, 2026  
**Status**: In Progress

## Overview

ANSIBLE01 has been renamed to **BASTION01** to better reflect its expanded role as a multi-purpose bastion/control plane container.

### Rationale

ANSIBLE01 was primarily named for its Ansible orchestration function, but the container now serves multiple purposes:

1. **Ansible Orchestration** - Configuration management and automation
2. **GitHub Actions Runner** - Self-hosted runner for CI/CD workflows
3. **Bastion/Jump Host** - Secure entry point and jump box to other infrastructure

The name **BASTION01** better communicates these functions and aligns with infrastructure security patterns.

---

## What Changed

### Terraform

| Old | New | Status |
|-----|-----|--------|
| `terraform/ansible01/` | `terraform/bastion01/` | ✅ Created |
| Variable `hostname: ansible01` | Variable `hostname: bastion01` | ✅ Updated |
| Output `ansible01_vmid` | Output `bastion01_vmid` | ✅ Updated |
| Output `ansible01_ip` | Output `bastion01_ip` | ✅ Updated |

### Ansible

| Old | New | Status |
|-----|-----|--------|
| `inventory/hosts.yml` - `ansible01` | `bastion01` | ✅ Updated |
| `playbooks/ansible01_base.yml` | `playbooks/bastion01_base.yml` | ✅ Created (old marked deprecated) |
| Playbook host target | `hosts: bastion01` | ✅ Updated |

### Network

| Property | Value |
|----------|-------|
| Hostname | bastion01 |
| IP Address | 10.101.0.20 (unchanged) |
| MAC Address | 02:aa:bb:cc:01:01 (unchanged) |
| VMID | 101 (unchanged) |

---

## Deployment Steps

### Step 1: Destroy Old ANSIBLE01 Container

```bash
cd terraform/ansible01
terraform destroy -auto-approve
```

**Note:** This destroys the old container but keeps the Terraform state.

### Step 2: Deploy New BASTION01 Container

```bash
cd terraform/bastion01
terraform init  # First time only
terraform plan
terraform apply -auto-approve
```

**Wait ~2 minutes for container to boot and obtain IP address.**

### Step 3: Configure BASTION01 with Ansible

```bash
# Test connectivity
ansible -i ansible/inventory/hosts.yml bastion01 -m ping

# Run base configuration playbook
ansible-playbook -i ansible/inventory/hosts.yml playbooks/bastion01_base.yml
```

**Prompts for `svc_ansible_password` - set a secure password.**

### Step 4: Verify Configuration

```bash
# SSH to root
ssh root@bastion01.phoenix.stack

# Verify services
ansible --version
git --version
terraform --version
```

---

## Rollback Plan (If Needed)

If issues arise, you can restore ANSIBLE01:

```bash
# Destroy BASTION01
cd terraform/bastion01
terraform destroy -auto-approve

# Restore ANSIBLE01 from backup state (if available)
cd terraform/ansible01
terraform apply -auto-approve
```

---

## Known Issues

- ⚠️ DNS records pointing to `ansible01.phoenix.stack` should be updated to `bastion01.phoenix.stack`
- ⚠️ Any firewall rules referencing ANSIBLE01 should be updated
- ⚠️ Monitoring/observability configs referencing ANSIBLE01 need updating

---

## Next Steps

1. ✅ Rename Terraform directory structure
2. ✅ Update Ansible inventory and playbooks
3. ⏳ Execute deployment steps (Step 1-4 above)
4. ⏳ Set up GitHub Actions runner on BASTION01
5. ⏳ Update DNS records (if applicable)
6. ⏳ Update firewall rules (if applicable)

---

## References

- [Terraform bastion01 module](../terraform/bastion01/)
- [Ansible bastion01 playbook](../ansible/playbooks/bastion01_base.yml)
- [Network configuration](mac-address-scheme.md)
