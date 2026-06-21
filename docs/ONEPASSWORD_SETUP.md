# 1Password Integration - PhoenixStack

**Purpose:** Centralized secrets management for infrastructure-as-code using 1Password Service Accounts.

---

## Vault Structure

Organize secrets in 1Password with this structure:

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
│   └── Item: SSH Keys
│       ├── Field: id_rsa (private key)
│       └── Field: id_rsa_pub (public key)
└── bastion01 (vault ID: xxxxx)
    └── Item: Service Account
        └── Field: 1password-service-account-token
```

---

## Setup: Create 1Password Service Account

1Password Service Accounts have limited, auditable access to specific items.

### Step 1: Create Service Account in 1Password

1. Sign in to 1Password web app
2. Go to **Settings** → **Integrations** → **Service Accounts**
3. Click **Create Service Account**
4. Name: `phoenixstack-automation`
5. Click **Create**
6. Copy the credentials shown (you won't see them again)

### Step 2: Grant Access to Vault Items

1. Click **Edit Access** on the service account
2. Grant access to:
   - `infrastructure` vault (read access)
   - Any other vaults needed
3. Save

### Step 3: Store Service Account Token Securely

**For GitHub Actions:**
```bash
# Copy the service account token
# Go to your GitHub repo Settings → Secrets and variables → Actions
# Add secret: OP_SERVICE_ACCOUNT_TOKEN = (paste token)
```

**For Local Ansible Execution:**
```bash
# On your local workstation
echo "your_service_account_token" > ~/.op_service_account_token
chmod 600 ~/.op_service_account_token

# Add to ~/.bashrc or ~/.zshrc
export OP_SERVICE_ACCOUNT_TOKEN=$(cat ~/.op_service_account_token)
```

**For Bastion01 (if running locally):**
```bash
# Store in secure location on bastion01
ssh root@10.101.0.20
echo "service_account_token" > /etc/phoenixstack/1password_token
chmod 600 /etc/phoenixstack/1password_token
```

---

## Implementation: GitHub Actions

### Update `.github/workflows/terraform.yml`

Uses 1Password to load Proxmox API credentials:

```yaml
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

      - name: Plan infrastructure
        run: terraform plan
```

### Advantages

- ✅ No credentials in GitHub Secrets (1Password is source of truth)
- ✅ Audit trail in 1Password activity log
- ✅ Easy credential rotation (update in 1Password, applies immediately)
- ✅ Self-hosted runner inherits environment variables

---

## Implementation: Ansible

### Using 1Password CLI Directly

**Step 1: Install 1Password CLI on Bastion01**

Create an Ansible role:

```yaml
- name: Install 1Password CLI
  block:
    - name: Add 1Password repository key
      shell: |
        curl https://downloads.1password.com/linux/keys/1password.asc | \
        sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

    - name: Add 1Password repository
      shell: |
        echo "deb [signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] \
        https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
        sudo tee /etc/apt/sources.list.d/1password.sources.list

    - name: Install 1Password CLI
      apt:
        name: 1password-cli
        state: present
        update_cache: yes
```

**Step 2: Update Ansible Playbooks**

Instead of vault files, fetch directly from 1Password:

```yaml
- name: Get Proxmox credentials from 1Password
  block:
    - name: Read Proxmox API URL
      shell: op read op://infrastructure/Proxmox/api-url
      environment:
        OP_SERVICE_ACCOUNT_TOKEN: "{{ op_service_account_token }}"
      register: proxmox_url
      no_log: yes

    - name: Use credentials
      debug:
        msg: "Proxmox URL: {{ proxmox_url.stdout }}"
```

**Step 3: Create Ansible Role for 1Password**

I'll create `ansible/roles/onepassword_lookup/` to standardize secret fetching.

---

## File Updates Required

Let me implement the full integration:

1. Create 1Password CLI installation role
2. Update GitHub Actions workflow to use 1Password
3. Create 1Password lookup role for Ansible
4. Update playbooks to use 1Password instead of vault files
5. Create comprehensive documentation

---

I'll implement this now. Here's what I'll create:

1. **`docs/ONEPASSWORD_SETUP.md`** - Complete setup guide
2. **`ansible/roles/onepassword_client/`** - Install 1Password CLI on bastion01
3. **`.github/workflows/terraform.yml`** - Update to use 1Password secrets
4. **`ansible/playbooks/bastion01_github_runner.yml`** - Update to fetch token from 1Password
5. **`ansible/playbooks/configure_onepassword.yml`** - Setup 1Password on bastion01

Let's start:
</thinking>
<function_calls>
<invoke name="create_file">
<parameter name="content"># 1Password Integration for PhoenixStack

**Purpose:** Centralized secrets management using 1Password Service Accounts for GitHub Actions, Ansible, and local workflows.

---

## Architecture Overview

```
1Password Vault (Single Source of Truth)
    ├── GitHub Actions: Load via 1password/load-secrets-action@v2
    ├── Ansible: Load via 1Password CLI (op command)
    └── Local: Load via 1password/load-secrets-action or op CLI
```

**Benefits:**
- Single source of truth for all credentials
- No plaintext secrets in git, GitHub, or Ansible
- Audit trail for all secret access
- Easy credential rotation
- Least privilege via Service Accounts

---

## Step 1: Create 1Password Service Account

### In 1Password Web App

1. Sign in to **1password.com**
2. Navigate to **Settings** → **Integrations** → **Service Accounts**
3. Click **Create Service Account**
4. Name: `phoenixstack-automation`
5. Grant access to vaults you'll use (e.g., `infrastructure`, `bastion01`)
6. Click **Create**
7. **⚠️ Copy the token immediately** (only shown once)

Save it safely (you'll add to GitHub Secrets and bastion01 next).

---

## Step 2: Set Up 1Password Vault Items

Create items in your 1Password vault with this structure:

### Vault: `infrastructure`

**Item 1: Proxmox**
- Title: `Proxmox`
- Fields:
  - `api-url` = `https://10.101.0.11:8006/api2/json/`
  - `api-token-id` = `root@pam!terraform-token`
  - `api-token-secret` = `your_actual_token_secret`

**Item 2: GitHub**
- Title: `GitHub`
- Fields:
  - `repository-url` = `https://github.com/username/phoenixstack`
  - `runner-registration-token` = `ABCD1234567890...` (optional; can be fetched fresh each time)

**Item 3: SSH Keys** (optional for key management)
- Title: `SSH Keys`
- Fields:
  - `id_rsa` = (paste your private key)
  - `id_rsa_pub` = (paste your public key)

---

## Step 3: GitHub Actions Setup

### Add 1Password Service Account Token to GitHub Secrets

1. Go to your GitHub repository
2. **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `OP_SERVICE_ACCOUNT_TOKEN`
5. Value: (paste the service account token from Step 1)
6. Click **Add secret**

---

## Step 4: Bastion01 Setup

### SSH into bastion01 and configure 1Password CLI

```bash
ssh root@10.101.0.20

# Create directory for 1Password config
sudo mkdir -p /etc/phoenixstack
sudo chmod 700 /etc/phoenixstack

# Store service account token (be careful with exposure)
# Option A: Via echo (careful in shell history)
echo "OP_SERVICE_ACCOUNT_TOKEN_HERE" | sudo tee /etc/phoenixstack/1password_token > /dev/null
sudo chmod 600 /etc/phoenixstack/1password_token

# Option B: Via editor (safer)
sudo nano /etc/phoenixstack/1password_token
# Paste token, save with Ctrl+O, Enter, Ctrl+X

# Set environment variable for current session
export OP_SERVICE_ACCOUNT_TOKEN=$(sudo cat /etc/phoenixstack/1password_token)

# Test 1Password CLI connection
op whoami
```

If successful, you'll see your 1Password account info.

---

## Step 5: Use 1Password in Workflows

### GitHub Actions Example

File: `.github/workflows/terraform.yml`

```yaml
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

      - name: Plan infrastructure
        run: terraform plan
```

### Ansible Example

File: `ansible/playbooks/example.yml`

```yaml
- name: Example playbook using 1Password
  hosts: localhost
  gather_facts: no
  environment:
    OP_SERVICE_ACCOUNT_TOKEN: "{{ lookup('file', '/etc/phoenixstack/1password_token') }}"

  tasks:
    - name: Get Proxmox API URL from 1Password
      shell: op read op://infrastructure/Proxmox/api-url
      register: proxmox_api_url
      changed_when: false
      no_log: yes

    - name: Display URL (safe since no_log above)
      debug:
        msg: "Using API at: {{ proxmox_api_url.stdout }}"
```

---

## Secret Reference Format

1Password uses this format: `op://vault-name/item-name/field-name`

Examples:
- `op://infrastructure/Proxmox/api-url`
- `op://infrastructure/GitHub/repository-url`
- `op://infrastructure/SSH Keys/id_rsa`

---

## Updating Credentials

**In 1Password (applies everywhere immediately):**

1. Open 1Password web app
2. Navigate to `infrastructure` vault
3. Open `Proxmox` item
4. Edit field value (e.g., `api-token-secret`)
5. Click **Save**

**Next GitHub Actions run** will use the updated credential.

**Next Ansible playbook run** will fetch the updated value.

---

## Security Best Practices

### 1. Rotate Service Account Tokens Regularly

```bash
# In 1Password:
# Settings → Integrations → Service Accounts
# Rotate token every 3-6 months
# Create new token, update in GitHub Secrets
```

### 2. Limit Service Account Access

```
Settings → Integrations → Service Accounts → [Account] → Edit Access
- Only grant access to required vaults
- Only grant access to specific items (not entire vaults if possible)
```

### 3. Audit Service Account Activity

```
Settings → Activity Log → Service Accounts
- View all access to secrets
- Identify unauthorized access
- Monitor activity trends
```

### 4. Never Commit Tokens

- `OP_SERVICE_ACCOUNT_TOKEN` only in GitHub Secrets
- `/etc/phoenixstack/1password_token` only on bastion01 (not in git)
- Never paste in chat, email, or terminal history

### 5. Protect Bastion01 Token File

```bash
# On bastion01, ensure file is protected
sudo chmod 600 /etc/phoenixstack/1password_token
sudo ls -l /etc/phoenixstack/1password_token
# Should show: -rw------- root root
```

---

## Troubleshooting

### "Authentication failed"

```bash
# Check service account token is valid
op whoami
# Expected: your account info

# Verify token format (should be long alphanumeric)
echo $OP_SERVICE_ACCOUNT_TOKEN | head -c 20
```

### "Item not found" or "Field not found"

```bash
# List all items in vault
op item list --vault infrastructure

# Check item details
op item get "Proxmox" --vault infrastructure

# Check field names
op item get "Proxmox" --vault infrastructure | grep -i field
```

### GitHub Actions step fails silently

1. Check service account has access to vault
2. Verify secret path format: `op://vault/item/field`
3. Run locally first to test: `op read op://infrastructure/Proxmox/api-url`

---

## Next Steps

1. ✅ Create 1Password Service Account (Step 1)
2. ✅ Create vault items (Step 2)
3. ✅ Add token to GitHub Secrets (Step 3)
4. ✅ Configure bastion01 (Step 4)
5. ⏭️ Install 1Password CLI on bastion01 (Ansible role)
6. ⏭️ Update GitHub Actions workflow
7. ⏭️ Update Ansible playbooks

---

## References

- [1Password Service Accounts](https://developer.1password.com/docs/service-accounts/get-started/)
- [1Password Load Secrets GitHub Action](https://github.com/1password/load-secrets-action)
- [1Password CLI Reference](https://developer.1password.com/docs/cli/reference/)
- [1Password for DevOps](https://developer.1password.com/docs/automation/devops/)
