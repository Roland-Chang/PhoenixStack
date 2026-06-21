# Ansible Playbook Reference Guide

Complete reference for running PhoenixStack Ansible playbooks with vault file integration.

---

## 📋 Playbook Overview

| Playbook | Target | Purpose | Vault Files |
|----------|--------|---------|-------------|
| `site.yml` | All infrastructure | Master orchestration playbook (runs all phases) | `onepassword.yml`, `github_runner.yml`, `pihole.yml` |
| `bastion_full_setup.yml` | Bastion servers | Control plane setup (users, 1Password, GitHub runner) | `onepassword.yml`, `github_runner.yml`, `backup_credentials.yml` |
| `dns_base.yml` | DNS servers | DNS foundational configuration | None |
| `dns_pihole.yml` | DNS servers | PiHole Docker container deployment | None |

---

## 🔐 Vault File Syntax

### Location
All vault files stored in: `ansible/vault/`

### Available Vault Files
```
ansible/vault/
├── onepassword.yml              # 1Password CLI service account token
├── onepassword.yml.example      # Template (safe to commit)
├── github_runner.yml            # GitHub Actions runner registration token
├── github_runner.yml.example    # Template (safe to commit)
├── backup_credentials.yml       # Backup service credentials
├── backup_credentials.yml.example # Template (safe to commit)
├── pihole.yml                   # PiHole admin password
├── pihole.yml.example           # Template (safe to commit)
└── .vault_pass                  # Local password file (NOT committed, .gitignore)
```

### Vault File Format

Each vault file contains encrypted variable definitions. Example structure:

```yaml
# onepassword.yml (when decrypted)
op_service_account_token: "your_token_here"

# github_runner.yml (when decrypted)
github_runner_registration_token: "ghr_xxxxxxxxxxxx"

# pihole.yml (when decrypted)
pihole_admin_password: "your_password_here"
```

---

## 🔑 Decryption Methods

### Method 1: Interactive Prompt (Recommended - Most Secure)

Prompts for vault password each time you run a playbook:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  --vault-id @prompt
```

**Advantages:**
- ✅ Most secure - password never stored on disk
- ✅ No password file management needed
- ✅ Audit-friendly - each run requires conscious password entry

### Method 2: Local Password File

Store vault password locally (never committed via `.gitignore`):

```bash
# Create local vault password file (one-time setup)
echo "your_vault_password_here" > ansible/vault/.vault_pass
chmod 600 ansible/vault/.vault_pass

# Run playbook with password file
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  --vault-password-file=ansible/vault/.vault_pass
```

**Advantages:**
- ✅ Non-interactive - suitable for CI/CD pipelines
- ✅ Password file is .gitignore'd

**Disadvantages:**
- ⚠️  Password stored in plaintext on disk

### Method 3: Environment Variable

```bash
# Export vault password as environment variable
export ANSIBLE_VAULT_PASSWORD_FILE=ansible/vault/.vault_pass

# Run playbook (automatically uses password file)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml
```

---

## 🎯 Command Patterns & Syntax

### Basic Pattern

```bash
ansible-playbook \
  -i ansible/inventory/hosts.yml \           # Inventory file
  ansible/playbooks/PLAYBOOK.yml \           # Playbook to run
  -e @ansible/vault/FILE1.yml \              # External variables (vault file 1)
  -e @ansible/vault/FILE2.yml \              # External variables (vault file 2)
  --vault-id @prompt                         # Vault decryption method
```

### Common Modifiers

```bash
# Limit to specific hosts/groups
-l bastion01                                 # Single host
-l bastion                                   # Host group
-l '!monitor01'                              # Exclude host

# Run only specific roles/tasks
--tags base,onepassword                      # Include only these tags
--skip-tags runner                           # Skip these tags

# Debug output
-v                                           # Verbose (show more details)
-vv                                          # Very verbose
-vvv                                         # Very very verbose
--check                                      # Dry run (don't make changes)

# Control execution
--start-at-task="Task Name"                  # Start at specific task
--step                                       # Interactive confirmation per task
-f 5                                         # Set fork count (parallelism)
```

---

## 📝 Playbook Examples

### Full Stack Deployment (All Infrastructure)

Deploy everything: Bastion, DNS, PiHole

```bash
# Using vault files with interactive password prompt
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id @prompt

# Using vault password file
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  -e @ansible/vault/pihole.yml \
  --vault-password-file=ansible/vault/.vault_pass

# Dry run (check mode)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id @prompt \
  --check
```

### Deploy Only Bastion Servers

Setup control plane with 1Password and GitHub runner:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/bastion_full_setup.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  --vault-id @prompt
```

Deploy to single bastion server only:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/bastion_full_setup.yml \
  -l bastion01 \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  --vault-id @prompt
```

### Deploy Only DNS Servers

Base DNS configuration only:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/dns_base.yml
```

PiHole deployment (requires Docker already installed):

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/dns_pihole.yml
```

Both DNS phases together:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  --tags dns \
  -e @ansible/vault/pihole.yml \
  --vault-id @prompt
```

### Deploy Specific Phases from site.yml

```bash
# Bastion only (Phase 1)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  --tags bastion \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  --vault-id @prompt

# DNS only (Phase 2 + 3)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  --tags dns \
  -e @ansible/vault/pihole.yml \
  --vault-id @prompt

# PiHole only (Phase 3)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  --tags pihole \
  -e @ansible/vault/pihole.yml \
  --vault-id @prompt
```

### Skip Specific Roles

Deploy bastion but skip GitHub runner:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/bastion_full_setup.yml \
  --tags base,onepassword \
  -e @ansible/vault/onepassword.yml \
  --vault-id @prompt
```

### Run with Increased Verbosity

Show what Ansible is doing:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id @prompt \
  -v                               # Show task names and results
  # or
  -vv                              # Also show variable values
  # or
  -vvv                             # Also show SSH details
```

### Test Without Making Changes (Check Mode)

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id @prompt \
  --check
```

---

## 🛡️ Vault File Management

### Create/Update Vault Files

**From template:**

```bash
# Copy template
cp ansible/vault/onepassword.yml.example ansible/vault/onepassword.yml

# Edit (plaintext)
nano ansible/vault/onepassword.yml

# Encrypt
ansible-vault encrypt ansible/vault/onepassword.yml
```

**Edit existing encrypted file:**

```bash
# Opens in editor, decrypts automatically
ansible-vault edit ansible/vault/onepassword.yml
```

**View without editing:**

```bash
ansible-vault view ansible/vault/onepassword.yml
```

**Re-encrypt with new password:**

```bash
ansible-vault rekey ansible/vault/onepassword.yml
```

---

## 📊 Host Groups & Limits

Reference for targeting specific hosts/groups:

| Target | Command |
|--------|---------|
| All hosts | (none - default) |
| Single host | `-l bastion01` |
| Host group | `-l bastion` or `-l dns` or `-l sql` or `-l mariadb` |
| Multiple groups | `-l 'bastion:dns'` |
| Exclude host | `-l 'all:!monitor01'` |
| Exclude group | `-l 'all:!vault'` |
| Regex pattern | `-l '~^bastion.*'` |

### Available Groups

```yaml
bastion         # bastion01, bastion02
dns             # dns01, dns02
proxy           # proxy01, proxy02
sql             # pgsql01, pgsql02
mariadb         # db01, db02
monitoring      # monitor01, monitor02
vault           # vault01, vault02
backup          # backup01
identity        # authentik01, authentik02
media           # plex01
compute         # docker01, docker02
```

---

## 🏷️ Available Tags

Tags for controlling which roles execute:

### Bastion Playbook Tags
```
base            # Base system configuration
onepassword     # 1Password CLI setup
runner          # GitHub Actions runner
always          # Always executed
```

### Site.yml Playbook Tags
```
bastion         # All bastion servers (phase 1)
dns             # DNS servers setup (phases 2-3)
dns_base        # DNS base config only
pihole          # PiHole deployment only
always          # Always executed
```

---

## 🔍 Debugging & Troubleshooting

### Test Connectivity

```bash
# Verify SSH access to all hosts
ansible all -i ansible/inventory/hosts.yml -m ping

# Verify specific group
ansible dns -i ansible/inventory/hosts.yml -m ping
```

### View Host Variables

```bash
# Show all variables for a host
ansible-inventory -i ansible/inventory/hosts.yml --host bastion01

# Show group variables
ansible-inventory -i ansible/inventory/hosts.yml --graph
```

### Run Single Task

```bash
# Start at specific task
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  --start-at-task="Task Name" \
  -e @ansible/vault/onepassword.yml \
  --vault-id @prompt
```

### Interactive Execution

```bash
# Pause before each task
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  --step \
  -e @ansible/vault/onepassword.yml \
  --vault-id @prompt
```

### View Gathered Facts

```bash
# Debug: show facts for hosts
ansible all -i ansible/inventory/hosts.yml -m setup

# Specific host
ansible bastion01 -i ansible/inventory/hosts.yml -m setup
```

---

## 📋 Checklist Before Running Playbooks

- [ ] All Terraform containers deployed and running (`pct list`)
- [ ] SSH access verified (`ssh root@<container_ip>`)
- [ ] Vault files created from templates (`.example` files)
- [ ] Vault files encrypted (`ansible-vault encrypt <file>`)
- [ ] Vault password available (or setup `.vault_pass`)
- [ ] Inventory file updated with correct IPs (`ansible/inventory/hosts.yml`)
- [ ] Network connectivity tested (`ansible all -m ping`)
- [ ] Playbook syntax valid (`ansible-playbook --syntax-check`)

---

## 🚨 Common Issues & Solutions

### "Permission denied (publickey)"

**Cause:** SSH key not configured or wrong user

**Solution:**
```bash
# Verify SSH access
ssh -v root@10.101.0.21

# Check inventory user setting
grep ansible_user ansible/inventory/hosts.yml

# Configure SSH key if needed
ssh-copy-id -i ~/.ssh/id_rsa.pub root@10.101.0.21
```

### "Vault id 'prompt' not found"

**Cause:** Typo in vault-id parameter

**Solution:**
```bash
# Correct syntax
--vault-id @prompt      # @ is required

# Not
--vault-id prompt       # Missing @
--vault-password-file   # Different parameter
```

### "Decryption failed (no vault secrets available)"

**Cause:** Wrong vault password or missing password file

**Solution:**
```bash
# Try interactive prompt
--vault-id @prompt

# Or verify password file exists
ls -la ansible/vault/.vault_pass

# Test vault file decryption
ansible-vault view ansible/vault/onepassword.yml
```

### "Host unreachable"

**Cause:** Container not running or network unreachable

**Solution:**
```bash
# Verify containers running
pct list | grep -E "bastion|dns"

# Verify network access
ping 10.101.0.21  # bastion01

# Check SSH service
pct enter 100 -- systemctl status ssh
```

---

## 📞 Quick Reference Card

```bash
# Most common: Full deployment with interactive vault password
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id @prompt

# Dry run (check mode)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id @prompt \
  --check

# Test connectivity
ansible all -i ansible/inventory/hosts.yml -m ping

# View decrypted vault file
ansible-vault view ansible/vault/onepassword.yml

# Edit encrypted vault file
ansible-vault edit ansible/vault/onepassword.yml

# Deploy only bastion servers
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/bastion_full_setup.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/github_runner.yml \
  --vault-id @prompt

# Deploy to single host
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml \
  -l bastion01 \
  -e @ansible/vault/onepassword.yml \
  --vault-id @prompt
```

