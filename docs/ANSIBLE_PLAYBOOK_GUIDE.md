# Ansible Playbook Execution Guide

## Master Orchestration Playbook

**Use this for complete infrastructure deployment:**

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id @prompt
```

## Playbook Hierarchy

### ✅ **CONSOLIDATED PLAYBOOKS** (Use These)

These are the primary entry points for each service:

#### **BASTION Full Setup** (RECOMMENDED)
- **File**: `ansible/playbooks/bastion_full_setup.yml`
- **Includes**: Base config + 1Password CLI + GitHub runner
- **Targets**: bastion01, bastion02 (group: bastion)
- **Use When**: Deploying bastion servers for the first time
- **Command**:
  ```bash
  ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/bastion_full_setup.yml \
    -e @ansible/vault/onepassword.yml \
    -e @ansible/vault/github_runner.yml \
    --vault-id @prompt
  ```

#### **BASTION Base Configuration** (RECOMMENDED)
- **File**: `ansible/playbooks/bastion_base.yml`
- **Includes**: Base system config + UFW firewall (orchestration ports)
- **Targets**: bastion01, bastion02 (group: bastion)
- **Use When**: Initial bastion server setup or system updates
- **Command**:
  ```bash
  ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/bastion_base.yml
  ```

#### **DNS Base Configuration** (RECOMMENDED)
- **File**: `ansible/playbooks/dns_base.yml`
- **Includes**: Base system config + UFW firewall (DNS ports)
- **Targets**: dns01, dns02 (group: dns)
- **Use When**: Initial DNS server setup or system updates
- **Command**:
  ```bash
  ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/dns_base.yml
  ```

#### **PiHole Deployment** (RECOMMENDED)
- **File**: `ansible/playbooks/dns_pihole.yml`
- **Includes**: Docker + PiHole container + local DNS records
- **Targets**: dns01, dns02 (group: dns)
- **Use When**: Installing/updating PiHole after base config
- **Command**:
  ```bash
  ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/dns_pihole.yml \
    -e @ansible/vault/pihole.yml \
    --vault-id @prompt
  ```

---

### ⚠️ **COMPONENT PLAYBOOKS** (Individual - DON'T MIX)

These are provided for flexibility but **should not be run together**. They will conflict or duplicate work.

| Playbook | Purpose | ⚠️ Note |
|----------|---------|---------|
| `bastion01_base.yml` | Just base config (DEPRECATED) | Use `bastion_base.yml` instead |
| `bastion01_full_setup.yml` | Just full setup (DEPRECATED) | Use `bastion_full_setup.yml` instead |
| `bastion01_onepassword.yml` | Just 1Password setup | Included in `bastion_full_setup.yml` |
| `bastion01_github_runner.yml` | Just GitHub runner | Included in `bastion_full_setup.yml` |
| `bastion01_github_runner_1password.yml` | GitHub runner with 1Password token fetch | **Conflicts with** `bastion_full_setup.yml` |

**DO NOT RUN**:
```bash
# ❌ WRONG - Will conflict (use bastion_full_setup.yml instead)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/bastion01_full_setup.yml
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/bastion01_base.yml
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/bastion01_onepassword.yml
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/bastion01_github_runner.yml

# ❌ WRONG - Conflicts with full_setup
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/bastion01_github_runner_1password.yml
```

---

## Usage Patterns

### Pattern 1: Deploy Everything (Recommended)
```bash
# Complete infrastructure deployment
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id @prompt
```

### Pattern 2: Deploy Only Bastion Servers
```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  --vault-id @prompt \
  --tags bastion
```

### Pattern 3: Deploy Only DNS
```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id @prompt \
  --tags dns
```

### Pattern 4: Deploy Only DNS Base (No PiHole Yet)
```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  --tags dns_base
```

### Pattern 5: Deploy Only PiHole (After DNS Base Already Done)
```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id @prompt \
  --tags pihole
```

### Pattern 6: Deploy to Specific Host
```bash
# Just bastion01 (not bastion02)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/bastion_full_setup.yml \
  -l bastion01 \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  --vault-id @prompt

# Just bastion02
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/bastion_full_setup.yml \
  -l bastion02 \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  --vault-id @prompt

# Just dns01 (not dns02)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/dns_pihole.yml \
  -l dns01 \
  -e @ansible/vault/pihole.yml \
  --vault-id @prompt

# Just dns02
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/dns_pihole.yml \
  -l dns02 \
  -e @ansible/vault/pihole.yml \
  --vault-id @prompt
```

---

## Vault Files Required

For full deployment, ensure these vault files exist and are encrypted:

| Vault File | Contains | Required For |
|-----------|----------|--------------|
| `ansible/vault/onepassword.yml` | 1Password service account token | bastion01 deployment |
| `ansible/vault/github_runner.yml` | GitHub runner registration token | bastion01 deployment |
| `ansible/vault/pihole.yml` | PiHole admin password | DNS/PiHole deployment |

Create/encrypt them with:
```bash
ansible-vault encrypt ansible/vault/pihole.yml
```

---

## Troubleshooting

### "Multiple playbooks running on same host"
**Problem**: Running `bastion01_full_setup.yml` AND `bastion01_base.yml` together
**Solution**: Use only `bastion01_full_setup.yml`, never run individual components

### "Tasks running in unexpected order"
**Problem**: Running individual playbooks instead of `site.yml`
**Solution**: Use `site.yml` with `--tags` to control execution order

### "1Password token not found"
**Problem**: Vault file not encrypted or not provided
**Solution**: Ensure `ansible/vault/onepassword.yml` is encrypted and use `--vault-id @prompt`

---

## Adding New Services

To add a new service to the orchestration:

1. **Create service playbooks**:
   - `ansible/playbooks/serviceXX_base.yml` (base config)
   - `ansible/playbooks/serviceXX_setup.yml` (service-specific setup)

2. **Add import to `site.yml`**:
   ```yaml
   - name: "PHASE N: Deploy ServiceXX"
     tags:
       - servicexx
       - always
     import_playbook: servicexx_setup.yml
   ```

3. **Use consolidated approach**:
   - Don't create `servicexx_full_setup.yml` unless multiple roles are needed
   - Prefer single-purpose playbooks unless consolidation improves clarity

---

## Key Principles

✅ **DO**:
- Use `site.yml` for coordinated deployments
- Use individual playbooks for targeted updates
- Use `--tags` to deploy specific phases
- Use `--vault-id @prompt` for secure credential handling

❌ **DON'T**:
- Mix individual component playbooks (causes duplication)
- Run `bastion01_full_setup.yml` AND component playbooks together
- Store unencrypted vault files
- Commit vault files to git
