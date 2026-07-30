# 1Password Integration for PhoenixStack

**Purpose:** Complete guide for centralized secrets management using 1Password Service Accounts across GitHub Actions, Ansible, and local workflows.

**Status:** ✅ Complete (Deployed June 8, 2026)  
**Scope:** Full 1Password integration across PhoenixStack infrastructure

---

## 📋 Table of Contents

1. [Quick Start](#quick-start)
2. [Architecture Overview](#architecture-overview)
3. [Part 1: Setup from Scratch](#part-1-setup-from-scratch)
4. [Part 2: GitHub Actions Integration](#part-2-github-actions-integration)
5. [Part 3: Ansible Integration](#part-3-ansible-integration)
6. [Implementation Status](#implementation-status)
7. [Security Best Practices](#security-best-practices)
8. [Troubleshooting](#troubleshooting)
9. [References](#references)

---

## Quick Start

**For first-time setup:** Follow the complete setup checklist below.  
**For Ansible integration:** Jump to [Part 3](#part-3-ansible-integration) and choose a method.  
**For GitHub Actions:** See [Part 2](#part-2-github-actions-integration).  
**To check what's deployed:** See [Implementation Status](#implementation-status).

### Setup Checklist

- [ ] **Phase 1:** Create 1Password Service Account  
- [ ] **Phase 2:** Create vault items (Proxmox, GitHub, etc.)  
- [ ] **Phase 3:** Add token to GitHub Secrets  
- [ ] **Phase 4:** Configure bastion01 with 1Password CLI  
- [ ] **Phase 5:** Deploy GitHub Runner (optional)  
- [ ] **Phase 6:** Verify everything works

**Estimated time:** 30-45 minutes for complete setup

---

## Architecture Overview

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

**Benefits:**
- ✅ Single source of truth for all credentials
- ✅ No plaintext secrets in git, GitHub, or Ansible vault files
- ✅ Audit trail for all secret access (1Password activity log)
- ✅ Easy credential rotation (update in 1Password, applies immediately)
- ✅ Least privilege via Service Accounts (granular vault access)
- ✅ Self-hosted runner inherits environment variables from plan step

---

## Part 1: Setup from Scratch

### Step 1: Create 1Password Service Account

1Password Service Accounts have limited, auditable access to specific items.

#### In 1Password Web App

1. Sign in to **1password.com**
2. Navigate to **Settings** → **Integrations** → **Service Accounts**
3. Click **Create Service Account**
4. Name: `phoenixstack-automation`
5. Click **Create**
6. **⚠️ Copy the token immediately** (only shown once!)

**Save it safely** – you'll add it to GitHub Secrets and bastion01 next.

#### Grant Access to Vault Items

1. Click **Edit Access** on the service account
2. Grant access to vaults:
   - `infrastructure` vault (read access)
   - Any other vaults needed
3. Click **Save**

---

### Step 2: Create 1Password Vault Items

#### Vault Structure

```
Vaults
├── infrastructure (vault ID: xxxxx)
│   ├── Item: Proxmox (API credentials)
│   │   ├── Field: api-url
│   │   ├── Field: api-token-id
│   │   └── Field: api-token-secret
│   ├── Item: GitHub (repository & runner)
│   │   ├── Field: runner-registration-token
│   │   └── Field: repository-url
│   └── Item: SSH Keys (optional)
│       ├── Field: id_rsa (private key)
│       └── Field: id_rsa_pub (public key)
└── bastion01 (vault ID: xxxxx) [optional]
    └── Item: Service Account
        └── Field: 1password-service-account-token
```

#### Create Items

**Item 1: Proxmox**
1. Open `infrastructure` vault in 1Password
2. Click **New Item** → **Login**
3. Title: `Proxmox`
4. Add custom fields:
   - Label: `api-url`, Type: Text, Value: `https://10.101.0.11:8006/api2/json/`
   - Label: `api-token-id`, Type: Text, Value: `root@pam!terraform-token`
   - Label: `api-token-secret`, Type: Password, Value: `your_actual_token_secret`
5. Click **Save**

**Item 2: GitHub**
1. Open `infrastructure` vault
2. Click **New Item** → **Login**
3. Title: `GitHub`
4. Add custom fields:
   - Label: `repository-url`, Type: Text, Value: `https://github.com/username/phoenixstack`
   - Label: `runner-registration-token`, Type: Password, Value: `ABCD1234567890...` (optional)
5. Click **Save**

**Item 3: SSH Keys** (optional)
1. Open `infrastructure` vault
2. Click **New Item** → **Secure Note**
3. Title: `SSH Keys`
4. Add custom fields:
   - Label: `id_rsa`, Type: Password, Value: (paste private key)
   - Label: `id_rsa_pub`, Type: Text, Value: (paste public key)
5. Click **Save**

---

### Step 3: Store Service Account Token

#### For GitHub Actions

```bash
# 1. Go to your GitHub repository
# 2. Settings → Secrets and variables → Actions
# 3. Click "New repository secret"
# 4. Name: OP_SERVICE_ACCOUNT_TOKEN
# 5. Value: (paste the service account token from Step 1)
# 6. Click "Add secret"
```

#### For Local Ansible Execution (Workstation)

```bash
# On your local workstation
echo "your_service_account_token" > ~/.op_service_account_token
chmod 600 ~/.op_service_account_token

# Add to ~/.bashrc or ~/.zshrc
export OP_SERVICE_ACCOUNT_TOKEN=$(cat ~/.op_service_account_token)

# Reload shell
source ~/.bashrc  # or source ~/.zshrc
```

#### For Bastion01 (Self-Hosted Runner)

```bash
# SSH into bastion01
ssh root@10.101.0.20

# Create directory for 1Password config
sudo mkdir -p /etc/phoenixstack
sudo chmod 700 /etc/phoenixstack

# Store service account token
# Option A: Via echo (careful with shell history)
echo "OP_SERVICE_ACCOUNT_TOKEN_HERE" | sudo tee /etc/phoenixstack/1password_token > /dev/null
sudo chmod 600 /etc/phoenixstack/1password_token

# Option B: Via editor (safer)
sudo nano /etc/phoenixstack/1password_token
# Paste token, save with Ctrl+O, Enter, Ctrl+X
sudo chmod 600 /etc/phoenixstack/1password_token

# Test connection
export OP_SERVICE_ACCOUNT_TOKEN=$(sudo cat /etc/phoenixstack/1password_token)
op whoami
# Should show your 1Password account info
```

---

## Part 2: GitHub Actions Integration

### Update `.github/workflows/terraform.yml`

Uses 1Password to load Proxmox API credentials dynamically.

**Complete Example:**

```yaml
name: Terraform Plan & Apply

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  plan:
    name: Terraform Plan
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    
    steps:
      - uses: actions/checkout@v4

      - name: Load secrets from 1Password
        uses: 1password/load-secrets-action@v2
        with:
          export-env: true
        env:
          OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
          TF_VAR_proxmox_api_url: op://infrastructure/Proxmox/api-url
          TF_VAR_proxmox_api_token_id: op://infrastructure/Proxmox/api-token-id
          TF_VAR_proxmox_api_token_secret: op://infrastructure/Proxmox/api-token-secret

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Initialize Terraform
        run: terraform init

      - name: Validate Terraform
        run: terraform validate

      - name: Plan infrastructure
        run: terraform plan

  apply:
    name: Terraform Apply
    runs-on: self-hosted  # bastion01
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    needs: [plan]
    
    steps:
      - uses: actions/checkout@v4

      - name: Load secrets from 1Password
        uses: 1password/load-secrets-action@v2
        with:
          export-env: true
        env:
          OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
          TF_VAR_proxmox_api_url: op://infrastructure/Proxmox/api-url
          TF_VAR_proxmox_api_token_id: op://infrastructure/Proxmox/api-token-id
          TF_VAR_proxmox_api_token_secret: op://infrastructure/Proxmox/api-token-secret

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Initialize Terraform
        run: terraform init

      - name: Apply infrastructure
        run: terraform apply -auto-approve
```

### Advantages

- ✅ No credentials in GitHub Secrets (1Password is source of truth)
- ✅ Audit trail in 1Password activity log
- ✅ Easy credential rotation (update in 1Password, applies immediately)
- ✅ Self-hosted runner inherits environment variables from plan step
- ✅ Credentials never stored in runner logs or artifacts

### Secret Reference Format

1Password uses this format:  
**`op://vault-name/item-name/field-name`**

Examples:
- `op://infrastructure/Proxmox/api-url`
- `op://infrastructure/Proxmox/api-token-secret`
- `op://infrastructure/GitHub/runner-registration-token`

---

## Part 3: Ansible Integration

### Architecture

```
1Password Vault
    ↓
Ansible (local workstation or bastion01)
    ↓
op CLI (reads from 1Password)
    ↓
Playbook variables/tasks
```

### Prerequisites

1. **1Password CLI installed** on the machine running Ansible
   ```bash
   # Local workstation (macOS)
   brew install 1password-cli
   
   # Local workstation (Linux)
   sudo apt install 1password-cli
   
   # Bastion01 (deployed via Ansible role)
   # See: ansible/roles/onepassword_client/
   ansible-playbook -i ansible/inventory/hosts.yml \
     ansible/playbooks/bastion01_onepassword.yml
   ```

2. **Service Account Token** in environment or file
   ```bash
   # Environment variable
   export OP_SERVICE_ACCOUNT_TOKEN="your_token_here"
   
   # Or from file (bastion01)
   export OP_SERVICE_ACCOUNT_TOKEN=$(cat /etc/phoenixstack/1password_token)
   ```

3. **Vault Items** created in 1Password with required fields

---

### Method 1: Direct Shell Command in Playbook

**Simplest approach** - use `shell` module to call `op` directly.

```yaml
---
- name: Fetch Proxmox credentials from 1Password
  hosts: localhost
  gather_facts: no
  vars:
    op_token: "{{ lookup('file', '/etc/phoenixstack/1password_token') }}"

  tasks:
    - name: Get Proxmox API URL
      shell: op read op://infrastructure/Proxmox/api-url
      environment:
        OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
      register: proxmox_api_url
      changed_when: false
      no_log: yes

    - name: Get Proxmox API Token ID
      shell: op read op://infrastructure/Proxmox/api-token-id
      environment:
        OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
      register: proxmox_api_token_id
      changed_when: false
      no_log: yes

    - name: Get Proxmox API Token Secret
      shell: op read op://infrastructure/Proxmox/api-token-secret
      environment:
        OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
      register: proxmox_api_token_secret
      changed_when: false
      no_log: yes

    - name: Use the credentials
      debug:
        msg: "Connecting to {{ proxmox_api_url.stdout }}"
```

**Pros:**
- Simple and straightforward
- Easy to understand
- No custom roles needed

**Cons:**
- Verbose for multiple secrets
- Repeated environment setup

---

### Method 2: Load from File (Bastion01)

When running on bastion01 where the token is stored in a file.

```yaml
---
- name: Example with file-based token
  hosts: bastion01
  gather_facts: no

  tasks:
    - name: Read service account token from file
      set_fact:
        op_token: "{{ lookup('file', '/etc/phoenixstack/1password_token') }}"
      no_log: yes

    - name: Fetch secret from 1Password
      shell: op read op://infrastructure/Proxmox/api-url
      environment:
        OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
      register: secret
      changed_when: false
      no_log: yes

    - name: Use secret
      debug:
        msg: "Secret value: {{ secret.stdout }}"
```

**Pros:**
- Token stored securely on bastion01
- No need to pass token as variable
- Reusable across playbooks

**Cons:**
- Requires token file to exist on bastion01
- Won't work from local workstation without modification

---

### Method 3: Batch Fetch Multiple Secrets

**Efficient way** to fetch multiple related fields in one API call.

```yaml
---
- name: Batch fetch all Proxmox credentials
  hosts: localhost
  gather_facts: no
  vars:
    op_token: "{{ lookup('file', '/etc/phoenixstack/1password_token') }}"

  tasks:
    - name: Fetch all Proxmox credentials at once
      shell: op item get Proxmox --vault infrastructure --format json
      environment:
        OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
      register: proxmox_item
      changed_when: false
      no_log: yes

    - name: Parse credentials from JSON
      set_fact:
        proxmox_api_url: "{{ (proxmox_item.stdout | from_json).fields | selectattr('label', 'equalto', 'api-url') | map(attribute='value') | first }}"
        proxmox_token_id: "{{ (proxmox_item.stdout | from_json).fields | selectattr('label', 'equalto', 'api-token-id') | map(attribute='value') | first }}"
        proxmox_token_secret: "{{ (proxmox_item.stdout | from_json).fields | selectattr('label', 'equalto', 'api-token-secret') | map(attribute='value') | first }}"
      no_log: yes

    - name: Display parsed values (for debugging)
      debug:
        msg: "Proxmox URL: {{ proxmox_api_url }}"
```

**Pros:**
- Single API call for all fields
- More efficient for multiple secrets
- Reduces 1Password API load

**Cons:**
- More complex JSON parsing
- All-or-nothing (fails if item doesn't exist)

---

### Method 4: Reusable Role for 1Password Lookups

Create a role that encapsulates 1Password fetching logic.

**Role Definition:**

File: `roles/fetch_1password_secrets/tasks/main.yml`

```yaml
---
- name: Fetch secret from 1Password
  shell: op read "{{ op_secret_path }}"
  environment:
    OP_SERVICE_ACCOUNT_TOKEN: "{{ op_service_account_token }}"
  register: op_result
  changed_when: false
  no_log: yes

- name: Set fact with fetched secret
  set_fact:
    "{{ op_variable_name }}": "{{ op_result.stdout }}"
  no_log: yes
```

**Usage Example:**

```yaml
---
- name: Use reusable 1Password role
  hosts: localhost
  gather_facts: no
  vars:
    op_token: "{{ lookup('file', '/etc/phoenixstack/1password_token') }}"

  tasks:
    - name: Fetch Proxmox API URL
      include_role:
        name: fetch_1password_secrets
      vars:
        op_service_account_token: "{{ op_token }}"
        op_secret_path: "op://infrastructure/Proxmox/api-url"
        op_variable_name: "proxmox_api_url"

    - name: Fetch Proxmox Token ID
      include_role:
        name: fetch_1password_secrets
      vars:
        op_service_account_token: "{{ op_token }}"
        op_secret_path: "op://infrastructure/Proxmox/api-token-id"
        op_variable_name: "proxmox_token_id"

    - name: Use fetched secrets
      debug:
        msg: "URL: {{ proxmox_api_url }}, Token ID: {{ proxmox_token_id }}"
```

**Pros:**
- Reusable across many playbooks
- Consistent error handling
- Easy to extend with validation logic

**Cons:**
- Requires creating/maintaining a role
- Slightly more verbose invocation

---

### Method 5: Using Ansible Vault + 1Password Together

Store only the service account token in Ansible Vault, use it to fetch other secrets.

**Vault File:**

File: `ansible/vault/onepassword.yml` (encrypted with `ansible-vault encrypt`)

```yaml
---
onepassword_service_account_token: "sv_live_..."
```

**Playbook:**

```yaml
---
- name: Playbook with vault + 1Password
  hosts: bastion01
  vars_files:
    - vault/onepassword.yml  # Contains: onepassword_service_account_token

  tasks:
    - name: Fetch credentials from 1Password
      shell: op read op://infrastructure/GitHub/runner-registration-token
      environment:
        OP_SERVICE_ACCOUNT_TOKEN: "{{ onepassword_service_account_token }}"
      register: github_token
      changed_when: false
      no_log: yes

    - name: Use GitHub token
      debug:
        msg: "Token fetched successfully"
```

**Run with:**

```bash
ansible-playbook playbook.yml \
  --vault-id @prompt \
  -e @ansible/vault/onepassword.yml
```

**Pros:**
- Service account token encrypted in Ansible Vault
- All other credentials fetched dynamically from 1Password
- Single vault password protects access

**Cons:**
- Still need to manage vault password
- Two credential systems (Vault + 1Password)

---

### Complete Playbook Example

Full example combining all best practices:

```yaml
#!/usr/bin/env ansible-playbook
---
- name: Deploy with 1Password Secrets
  hosts: bastion01
  become: true
  gather_facts: true

  pre_tasks:
    - name: Load 1Password token from file
      set_fact:
        op_token: "{{ lookup('file', '/etc/phoenixstack/1password_token') }}"
      no_log: yes

    - name: Test 1Password connectivity
      shell: op whoami
      environment:
        OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
      register: op_whoami
      changed_when: false
      failed_when: op_whoami.rc != 0

    - name: Display 1Password account
      debug:
        msg: "Connected to 1Password as: {{ op_whoami.stdout }}"

  tasks:
    - name: Fetch infrastructure secrets from 1Password
      block:
        - name: Get Proxmox credentials (batch fetch)
          shell: op item get Proxmox --vault infrastructure --format json
          environment:
            OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
          register: proxmox_secrets
          changed_when: false
          no_log: yes

        - name: Parse Proxmox credentials
          set_fact:
            proxmox_url: "{{ (proxmox_secrets.stdout | from_json).fields | selectattr('label', 'equalto', 'api-url') | map(attribute='value') | first }}"
            proxmox_token_id: "{{ (proxmox_secrets.stdout | from_json).fields | selectattr('label', 'equalto', 'api-token-id') | map(attribute='value') | first }}"
            proxmox_token_secret: "{{ (proxmox_secrets.stdout | from_json).fields | selectattr('label', 'equalto', 'api-token-secret') | map(attribute='value') | first }}"
          no_log: yes

    - name: Use credentials (example)
      debug:
        msg: "Connected to Proxmox at {{ proxmox_url }}"

  post_tasks:
    - name: Deployment complete
      debug:
        msg: "Successfully deployed using 1Password secrets"
```

**Run:**

```bash
ansible-playbook playbook.yml -i ansible/inventory/hosts.yml
```

---

### Best Practices

#### 1. Always Use `no_log: yes`

Prevents secret values from appearing in Ansible output or logs.

```yaml
- name: Fetch secret
  shell: op read op://vault/item/field
  register: secret
  no_log: yes  # ← CRITICAL: Don't log secret values
```

#### 2. Store Service Account Token Securely

```yaml
# ✅ GOOD: Load from protected file
op_token: "{{ lookup('file', '/etc/phoenixstack/1password_token') }}"

# ✅ GOOD: Load from Ansible Vault
op_token: "{{ onepassword_service_account_token }}"  # from vault file

# ❌ BAD: Hardcode token in playbook
op_token: "sv_live_ABC123..."
```

#### 3. Use `changed_when: false` for Read-Only Operations

Reading secrets doesn't change system state:

```yaml
- shell: op read op://vault/item/field
  changed_when: false  # ← Prevents showing as "changed"
  no_log: yes
```

#### 4. Test Connectivity First

Verify 1Password CLI works before fetching secrets:

```yaml
- name: Test 1Password connectivity
  shell: op whoami
  environment:
    OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
  register: op_whoami
  changed_when: false
  failed_when: op_whoami.rc != 0
```

#### 5. Cache Secrets During Playbook Execution

Avoid repeated API calls for the same secret:

```yaml
- name: Fetch and cache secrets
  block:
    - name: Get all credentials (cached)
      shell: op item get Proxmox --vault infrastructure --format json
      environment:
        OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
      register: proxmox_data
      changed_when: false
      no_log: yes
      run_once: true  # ← Only fetch once for entire play

    # Use proxmox_data.stdout throughout playbook
```

---

## Implementation Status

### What Was Implemented

#### 1. Documentation

| File | Purpose |
|------|---------|
| [`docs/1PASSWORD_INTEGRATION.md`](1PASSWORD_INTEGRATION.md) | This file - complete integration guide (setup, GitHub, Ansible) |

#### 2. Ansible Roles

| Component | Purpose |
|-----------|---------|
| `ansible/roles/onepassword_client/` | Install and configure 1Password CLI on bastion01 |
| - `defaults/main.yml` | Configuration defaults (token paths, repo URLs) |
| - `tasks/main.yml` | Installation, configuration, connectivity testing |

#### 3. Ansible Playbooks

| Playbook | Purpose |
|----------|---------|
| `ansible/playbooks/bastion01_onepassword.yml` | Deploy 1Password CLI to bastion01 |
| `ansible/playbooks/bastion01_github_runner_1password.yml` | Install GitHub runner, fetching token from 1Password |

#### 4. GitHub Actions

| File | Change |
|------|--------|
| `.github/workflows/terraform.yml` | Updated to use `1password/load-secrets-action@v2` instead of GitHub Secrets |
| | Plan jobs: Load Proxmox API credentials from 1Password |
| | Apply jobs: Load Proxmox API credentials from 1Password |

#### 5. Configuration Templates

| File | Purpose |
|------|---------|
| `ansible/vault/onepassword.yml.example` | Template for 1Password service account token (vault) |

---

### File Structure

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
└── docs/
    └── 1PASSWORD_INTEGRATION.md             ← THIS FILE
```

---

### Key Differences From Previous Setup

#### Before (Vault Files)

```yaml
# ❌ Old way - plaintext secrets in vault files
ansible-playbook bastion01_github_runner.yml \
  -e @ansible/vault/github_runner.yml

# Variables stored in: ansible/vault/github_runner.yml
```

#### After (1Password)

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

## Security Best Practices

### 1. Rotate Service Account Tokens Regularly

```bash
# In 1Password web app:
# Settings → Integrations → Service Accounts
# Rotate token every 3-6 months

# After rotation:
# 1. Update GitHub Secret: OP_SERVICE_ACCOUNT_TOKEN
# 2. Update bastion01: /etc/phoenixstack/1password_token
# 3. Update local workstation: ~/.op_service_account_token
```

### 2. Limit Service Account Access

```
Settings → Integrations → Service Accounts → [Account] → Edit Access
- Only grant access to required vaults
- Use "Read" access (not "Manage")
- Prefer item-specific access over vault-wide access
```

### 3. Audit Service Account Activity

```
Settings → Activity Log → Filter by Service Account
- View all access to secrets
- Identify unauthorized access
- Monitor activity trends
- Export logs for compliance
```

### 4. Never Commit Tokens

Files to protect:
- `OP_SERVICE_ACCOUNT_TOKEN` (only in GitHub Secrets)
- `/etc/phoenixstack/1password_token` (only on bastion01, not in git)
- `~/.op_service_account_token` (local workstation, not in git)
- Never paste in chat, email, Slack, or terminal history

**Add to `.gitignore`:**
```
# 1Password tokens
.op_service_account_token
**/1password_token
ansible/vault/onepassword.yml
```

### 5. Protect Bastion01 Token File

```bash
# On bastion01, ensure file is protected
sudo chmod 600 /etc/phoenixstack/1password_token
sudo ls -l /etc/phoenixstack/1password_token
# Should show: -rw------- root root

# Verify ownership
sudo chown root:root /etc/phoenixstack/1password_token
```

### 6. Use `no_log` in Ansible

Always mark tasks that handle secrets with `no_log: yes`:

```yaml
- name: Fetch secret
  shell: op read op://vault/item/field
  register: secret
  no_log: yes  # ← Prevents secret from appearing in logs
```

### 7. Separate Service Accounts by Environment

If you have multiple environments (dev/staging/prod):

```
Service Accounts:
├── phoenixstack-automation-dev
├── phoenixstack-automation-staging
└── phoenixstack-automation-prod
```

Each with access only to their respective vault.

---

## Troubleshooting

### "command not found: op"

**Problem:** 1Password CLI not installed.

**Solution:**

```bash
# Check installation
which op

# Install if missing (Linux)
sudo apt-get update
sudo apt-get install 1password-cli

# Install if missing (macOS)
brew install 1password-cli

# Verify installation
op --version
```

---

### "Authentication failed"

**Problem:** Service account token invalid, expired, or not set.

**Solution:**

```bash
# Verify token is set
echo $OP_SERVICE_ACCOUNT_TOKEN | head -c 20
# Should show first 20 chars of token (e.g., "sv_live_ABC123...")

# Test connectivity
op whoami
# Expected: your 1Password account info

# If failed: Regenerate token
# 1Password Settings → Service Accounts → Rotate token
# Update in GitHub Secrets and bastion01
```

---

### "Item not found" or "Field not found"

**Problem:** Incorrect vault name, item name, or field name in secret path.

**Solution:**

```bash
# List all vaults
op vault list
# Example output: infrastructure, bastion01

# List items in vault
op item list --vault infrastructure
# Example output: Proxmox, GitHub, SSH Keys

# Check exact item structure
op item get "Proxmox" --vault infrastructure
# Shows all fields in the item

# Verify field names match exactly
op item get "Proxmox" --vault infrastructure --format json | jq '.fields[] | {label: .label, id: .id}'
```

**Common mistakes:**
- Case sensitivity: `proxmox` ≠ `Proxmox`
- Spaces in names: `SSH Keys` not `SSH Keys` (check for extra spaces)
- Field ID vs Label: Use `label` from JSON, not `id`

---

### Secret appears in Ansible output

**Problem:** Forgot to use `no_log: yes` on task that handles secrets.

**Solution:**

```yaml
# ❌ BAD: Secret will be logged
- shell: op read op://vault/item/field
  register: secret

# ✅ GOOD: Secret won't appear in logs
- shell: op read op://vault/item/field
  register: secret
  no_log: yes
```

---

### GitHub Actions step fails silently

**Problem:** 1Password action fails but doesn't show clear error.

**Solution:**

1. **Check service account token is valid:**
   - GitHub repo → Settings → Secrets → `OP_SERVICE_ACCOUNT_TOKEN` exists
   
2. **Verify secret path format:**
   ```yaml
   # Correct format
   TF_VAR_proxmox_api_url: op://infrastructure/Proxmox/api-url
   
   # Common mistakes
   TF_VAR_proxmox_api_url: op://infrastructure/proxmox/api-url  # Wrong case
   TF_VAR_proxmox_api_url: op://infrastructure/Proxmox/api_url  # Wrong field name
   ```

3. **Run workflow manually to see full output:**
   - Actions tab → Select workflow → Run workflow
   - Enable debug logging: Settings → Secrets → Add `ACTIONS_STEP_DEBUG` = `true`

4. **Test locally first:**
   ```bash
   export OP_SERVICE_ACCOUNT_TOKEN="your_token"
   op read op://infrastructure/Proxmox/api-url
   # Should return the URL, not an error
   ```

---

### Ansible can't read `/etc/phoenixstack/1password_token`

**Problem:** File permissions or ownership issue.

**Solution:**

```bash
ssh root@10.101.0.20

# Check file exists
ls -l /etc/phoenixstack/1password_token
# Should show: -rw------- root root

# Fix permissions if wrong
sudo chmod 600 /etc/phoenixstack/1password_token
sudo chown root:root /etc/phoenixstack/1password_token

# Test reading
sudo cat /etc/phoenixstack/1password_token | head -c 20
# Should show first 20 chars of token
```

---

### "Service account does not have access to this vault"

**Problem:** Service account doesn't have permission to access vault or item.

**Solution:**

1. Go to **1Password web app**
2. **Settings** → **Integrations** → **Service Accounts**
3. Click on `phoenixstack-automation`
4. Click **Edit Access**
5. Verify access to required vaults:
   - `infrastructure` → Read access ✅
6. Click **Save**
7. Wait 1-2 minutes for permissions to propagate
8. Test again:
   ```bash
   op item list --vault infrastructure
   ```

---

## Local Development (Workstation)

If running Ansible from your workstation instead of bastion01:

### Setup

```bash
# Install 1Password CLI
brew install 1password-cli  # macOS
sudo apt install 1password-cli  # Ubuntu/Debian

# Create token file
mkdir -p ~/.config/phoenixstack
echo "your_service_account_token" > ~/.config/phoenixstack/1password_token
chmod 600 ~/.config/phoenixstack/1password_token

# Set environment variable
export OP_SERVICE_ACCOUNT_TOKEN=$(cat ~/.config/phoenixstack/1password_token)

# Add to shell profile (~/.bashrc or ~/.zshrc)
echo 'export OP_SERVICE_ACCOUNT_TOKEN=$(cat ~/.config/phoenixstack/1password_token 2>/dev/null)' >> ~/.bashrc
source ~/.bashrc
```

### Test

```bash
# Verify connection
op whoami
# Should show your 1Password account info

# Test secret fetch
op read op://infrastructure/Proxmox/api-url
# Should return: https://10.101.0.11:8006/api2/json/
```

### Run Playbooks

```bash
cd /home/ayoung/projects/phoenixstack

# Run playbook (token loaded from ~/.config/phoenixstack/1password_token)
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/example.yml
```

---

## Next Steps After Setup Complete

1. ✅ All credentials managed by 1Password
2. ⏭️ Deploy remaining infrastructure (DNS01, PROXY01, etc.)
3. ⏭️ Set up monitoring/alerting with 1Password secrets
4. ⏭️ Create runbooks for common operations
5. ⏭️ Document disaster recovery procedures
6. ⏭️ Schedule service account token rotation (3-6 months)

---

## References

### Official Documentation

- [1Password Developer Documentation](https://developer.1password.com/)
- [1Password Service Accounts](https://developer.1password.com/docs/service-accounts/get-started/)
- [1Password CLI Reference](https://developer.1password.com/docs/cli/reference/)
- [1Password Load Secrets Action](https://github.com/1password/load-secrets-action)
- [1Password for DevOps](https://developer.1password.com/docs/automation/devops/)

### Ansible Documentation

- [Ansible Documentation](https://docs.ansible.com/)
- [Ansible Shell Module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/shell_module.html)
- [Ansible Lookup Plugins](https://docs.ansible.com/ansible/latest/plugins/lookup.html)
- [Ansible Vault](https://docs.ansible.com/ansible/latest/cli/ansible-vault.html)

### GitHub Actions

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [GitHub Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)

---

## Questions?

For specific issues not covered in this guide:

1. **Ansible integration questions:** Review [Part 3: Ansible Integration](#part-3-ansible-integration) and choose appropriate method
2. **GitHub Actions issues:** Check [Part 2: GitHub Actions Integration](#part-2-github-actions-integration)
3. **Setup problems:** Walk through [Part 1: Setup from Scratch](#part-1-setup-from-scratch) again
4. **Security concerns:** Review [Security Best Practices](#security-best-practices)
5. **Troubleshooting:** See [Troubleshooting](#troubleshooting) section above

**Last Updated:** 2026-07-29 (Documentation consolidated)  
**Integration Date:** June 8, 2026  
**Status:** ✅ Complete and deployed
