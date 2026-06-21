# 1Password Integration - Implementation Summary

**Date:** June 8, 2026  
**Status:** ✅ Complete  
**Scope:** Full 1Password integration across PhoenixStack (GitHub Actions, Ansible, local workflows)

---

## What Was Implemented

### 1. Documentation

| File | Purpose |
|------|---------|
| [`docs/ONEPASSWORD_SETUP.md`](docs/ONEPASSWORD_SETUP.md) | Complete 1Password setup guide (vault structure, service accounts, GitHub, Ansible) |
| [`docs/ANSIBLE_ONEPASSWORD.md`](docs/ANSIBLE_ONEPASSWORD.md) | How to use 1Password with Ansible playbooks (5 methods + examples) |

### 2. Ansible Roles

| Component | Purpose |
|-----------|---------|
| `ansible/roles/onepassword_client/` | Install and configure 1Password CLI on bastion01 |
| - `defaults/main.yml` | Configuration defaults (token paths, repo URLs) |
| - `tasks/main.yml` | Installation, configuration, connectivity testing |

### 3. Ansible Playbooks

| Playbook | Purpose |
|----------|---------|
| `ansible/playbooks/bastion01_onepassword.yml` | Deploy 1Password CLI to bastion01 |
| `ansible/playbooks/bastion01_github_runner_1password.yml` | Install GitHub runner, fetching token from 1Password |

### 4. GitHub Actions

| File | Change |
|------|--------|
| `.github/workflows/terraform.yml` | Updated to use `1password/load-secrets-action@v2` instead of GitHub Secrets |
| | Plan jobs: Load Proxmox API credentials from 1Password |
| | Apply jobs: Load Proxmox API credentials from 1Password |

### 5. Configuration Templates

| File | Purpose |
|------|---------|
| `ansible/vault/onepassword.yml.example` | Template for 1Password service account token (vault) |

---

## Architecture Diagram

```
1Password Vault (Single Source of Truth)
├── infrastructure (vault)
│   ├── Proxmox (item)
│   │   ├── api-url
│   │   ├── api-token-id
│   │   └── api-token-secret
│   └── GitHub (item)
│       ├── runner-registration-token
│       └── repository-url
└── Service Account (permissions)
    └── Access to infrastructure vault

                 ↓

    ┌─────────────────────────────────────┐
    │   GitHub Actions (ubuntu-latest)    │
    │  ┌─────────────────────────────────┐│
    │  │ Load Secrets from 1Password Act.││
    │  └─────────────────────────────────┘│
    │           ↓                          │
    │  TF_VAR_* environment variables      │
    │  (Terraform plan)                    │
    └─────────────────────────────────────┘

                 ↓

    ┌─────────────────────────────────────┐
    │  GitHub Actions (self-hosted)       │
    │  (bastion01)                        │
    │  ┌─────────────────────────────────┐│
    │  │ Environment variables from step 1││
    │  │ (Terraform apply)                ││
    │  └─────────────────────────────────┘│
    └─────────────────────────────────────┘

                 ↓

    ┌─────────────────────────────────────┐
    │   Ansible (bastion01)               │
    │  ┌─────────────────────────────────┐│
    │  │ op CLI (1Password Command)      ││
    │  │ Fetch secrets dynamically       ││
    │  │ Environment: OP_SERVICE_..._    ││
    │  │ /etc/phoenixstack/1password_... ││
    │  └─────────────────────────────────┘│
    └─────────────────────────────────────┘
```

---

## Setup Checklist

### ✅ Phase 1: 1Password Account & Service Account (You do this)

- [ ] Log into 1Password web app (1password.com)
- [ ] Go to Settings → Integrations → Service Accounts
- [ ] Create new Service Account named `phoenixstack-automation`
- [ ] Copy the service account token (shown once only)
- [ ] Save token securely (1Password itself, password manager, etc.)

### ✅ Phase 2: Create 1Password Vault Items (You do this)

**Vault:** `infrastructure`

**Item 1: Proxmox**
- [ ] Create new Login item
- [ ] Title: `Proxmox`
- [ ] Add fields:
  - [ ] `api-url` = `https://10.101.0.11:8006/api2/json/`
  - [ ] `api-token-id` = `root@pam!terraform-token`
  - [ ] `api-token-secret` = (your actual token secret)

**Item 2: GitHub**
- [ ] Create new Login item
- [ ] Title: `GitHub`
- [ ] Add fields:
  - [ ] `repository-url` = `https://github.com/Roland-Chang/PhoenixStack`
  - [ ] `runner-registration-token` = (optional, can fetch fresh)

### ⏳ Phase 3: GitHub Configuration (Local)

```bash
# 1. Add 1Password service account token to GitHub Secrets
cd /home/ayoung/projects/phoenixstack

# Go to GitHub repo → Settings → Secrets and variables → Actions
# Click "New repository secret"
# Name: OP_SERVICE_ACCOUNT_TOKEN
# Value: (paste the token from Phase 1)
```

### ⏳ Phase 4: Deploy 1Password on Bastion01 (Ansible)

```bash
cd /home/ayoung/projects/phoenixstack

# 1. Create vault file
cp ansible/vault/onepassword.yml.example ansible/vault/onepassword.yml

# 2. Edit vault file (add service account token)
nano ansible/vault/onepassword.yml
# Change: onepassword_service_account_token: "YOUR_SERVICE_ACCOUNT_TOKEN_HERE"

# 3. Encrypt vault file
ansible-vault encrypt ansible/vault/onepassword.yml
# You will be prompted to create a vault password

# 4. Deploy to bastion01
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/bastion01_onepassword.yml \
  --vault-id @prompt \
  -e @ansible/vault/onepassword.yml
# Enter vault password when prompted
```

### ⏳ Phase 5: Deploy GitHub Runner (Updated to use 1Password)

```bash
cd /home/ayoung/projects/phoenixstack

# Run the updated playbook that fetches token from 1Password
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/bastion01_github_runner_1password.yml \
  --vault-id @prompt \
  -e @ansible/vault/onepassword.yml
# Enter vault password when prompted
```

### ⏳ Phase 6: Verify Everything Works

**GitHub Actions:**
```bash
# Push a change to trigger workflow
git add .
git commit -m "chore: 1Password integration complete"
git push

# Watch Actions tab → Check "Terraform Plan & Apply" job
# Should see: "Load secrets from 1Password" step
```

**Verify 1Password CLI on Bastion01:**
```bash
ssh root@10.101.0.20

# Test 1Password CLI
export OP_SERVICE_ACCOUNT_TOKEN=$(cat /etc/phoenixstack/1password_token)
op whoami

# Should show account info, not errors
```

**Verify GitHub Runner is Using 1Password:**
```bash
ssh root@10.101.0.20

# Check runner logs
journalctl -u github-runner -n 50 -f

# Should show successful registration
```

---

## Key Differences From Previous Setup

### Before (Vault Files)

```yaml
# ❌ Old way - plaintext secrets in vault files
ansible-playbook bastion01_github_runner.yml \
  -e @ansible/vault/github_runner.yml

# Variables stored in: ansible/vault/github_runner.yml
```

### After (1Password)

```yaml
# ✅ New way - fetch secrets on-demand from 1Password
ansible-playbook bastion01_github_runner_1password.yml \
  -e @ansible/vault/onepassword.yml

# Service account token in vault file
# All other credentials fetched from 1Password API
```

**Benefits:**
- Single source of truth (1Password)
- Credentials never stored in git
- Easy rotation (change in 1Password, applies immediately)
- Audit trail in 1Password activity log
- Least privilege via Service Accounts

---

## File Structure

```
PhoenixStack/
├── .github/
│   └── workflows/
│       └── terraform.yml                    ← Updated to use 1Password
├── ansible/
│   ├── playbooks/
│   │   ├── bastion01_onepassword.yml        ← NEW: Deploy 1Password CLI
│   │   ├── bastion01_github_runner.yml      ← (Old way, still available)
│   │   └── bastion01_github_runner_1password.yml  ← NEW: With 1Password lookup
│   ├── roles/
│   │   └── onepassword_client/              ← NEW: 1Password CLI installation
│   │       ├── defaults/main.yml
│   │       └── tasks/main.yml
│   └── vault/
│       ├── github_runner.yml.example        ← (Old way)
│       └── onepassword.yml.example          ← NEW: Service account token
├── docs/
│   ├── ONEPASSWORD_SETUP.md                 ← NEW: Complete setup guide
│   └── ANSIBLE_ONEPASSWORD.md               ← NEW: Ansible integration guide
└── 1PASSWORD_INTEGRATION_SUMMARY.md         ← THIS FILE
```

---

## Troubleshooting

### "Item not found" in Ansible

Make sure 1Password vault structure matches:
```bash
# Check what's in 1Password
op vault list  # Should show: infrastructure
op item list --vault infrastructure  # Should show: Proxmox, GitHub
op item get Proxmox --vault infrastructure  # Should show: api-url, api-token-id, api-token-secret
```

### GitHub Actions workflow fails

Check:
1. `OP_SERVICE_ACCOUNT_TOKEN` secret exists in GitHub
2. 1Password vault items created with correct names
3. Run workflow manually to see full error output

### Ansible can't read /etc/phoenixstack/1password_token

File permissions issue:
```bash
ssh root@10.101.0.20
ls -l /etc/phoenixstack/1password_token
# Should show: -rw------- root root

# If wrong, fix permissions:
sudo chmod 600 /etc/phoenixstack/1password_token
```

---

## Next Steps After Setup Complete

1. ✅ All credentials managed by 1Password
2. ⏭️ Deploy remaining infrastructure (DNS01, PROXY01, etc.)
3. ⏭️ Set up monitoring/alerting
4. ⏭️ Create runbooks for common operations
5. ⏭️ Document disaster recovery procedures

---

## Security Notes

### ✅ What We Got Right

- ✅ No plaintext credentials in git
- ✅ Secrets stored in 1Password (encrypted at rest)
- ✅ Service Account token has limited permissions
- ✅ Audit trail for all secret access
- ✅ Easy credential rotation
- ✅ Bastion01 token file protected (mode 0600)

### ⚠️ What To Remember

- Never commit `.vault_pass` or `/etc/phoenixstack/1password_token` to git
- Rotate service account token every 3-6 months
- Keep 1Password service account credentials safe
- Monitor 1Password activity log for unusual access

---

## References

- [1Password Developer Documentation](https://developer.1password.com/)
- [1Password Service Accounts](https://developer.1password.com/docs/service-accounts/get-started/)
- [1Password CLI Reference](https://developer.1password.com/docs/cli/reference/)
- [1Password Load Secrets Action](https://github.com/1password/load-secrets-action)
- [Ansible Documentation](https://docs.ansible.com/)

---

## Questions?

Refer to the detailed documentation:
- **Setting up 1Password:** [`docs/ONEPASSWORD_SETUP.md`](docs/ONEPASSWORD_SETUP.md)
- **Using with Ansible:** [`docs/ANSIBLE_ONEPASSWORD.md`](docs/ANSIBLE_ONEPASSWORD.md)
- **GitHub Actions:** Look at `.github/workflows/terraform.yml` for `1password/load-secrets-action@v2` example
