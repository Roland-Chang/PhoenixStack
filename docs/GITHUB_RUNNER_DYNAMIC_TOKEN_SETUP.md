# GitHub Runner Token Management - Dynamic Generation via API

## Overview

Instead of manually generating short-lived registration tokens via the GitHub UI, this setup uses **Ansible to generate fresh tokens dynamically via GitHub API** for each runner deployment. This approach provides:

- **No manual token copying** - Eliminate the 1-hour expiration window
- **Single fine-grained token in vault** - Store one secure GitHub token with least-privilege permissions
- **Scalable deployment** - Deploy multiple runners (BASTION01, BASTION02, etc.) without regenerating tokens
- **Consistent automation** - Same token generation flow for all runners
- **Better security** - Fine-grained tokens offer repository-level and permission-level control

---

## Prerequisites

### 1. Create a GitHub Fine-Grained Personal Access Token

GitHub's newer fine-grained tokens replace the need for manual registration tokens and offer better security than classic PATs. It's stored once in vault and reused for all runner deployments.

**Steps:**
1. Go to https://github.com/settings/personal-access-tokens/new
2. Enter token name: `PhoenixStack-Runner-Automation`
3. Set expiration: 90 days (recommended)
4. Set **Repository access**: `Only select repositories` → Select `PhoenixStack`
5. Set **Permissions**:
   - **Administration** → ✅ Read and write
   - (Optional) **Actions** → Read and write (for additional control)
6. Click "Generate token"
7. **Copy the token immediately** - you won't see it again (format: `github_pat_...`)
8. Store it securely (you'll add to vault next)

**Important:** This token is required to expire (max 1 year) and stored in vault. Keep it secret like a password.

---

## Setup: Configuring Vault with GitHub PAT

### Create Vault File from Template

```bash
# Copy template
cp ansible/vault/github_runner.yml.example ansible/vault/github_runner.yml

# Edit with your values
nano ansible/vault/github_runner.yml
```

**Fill in these values:**
```yaml
github_repo_url: "https://github.com/Roland-Chang/PhoenixStack"
github_api_token: "github_pat_YOUR_TOKEN_HERE"  # Paste your fine-grained token here
github_repo_owner: "Roland-Chang"
github_repo_name: "PhoenixStack"
```

### Encrypt the Vault File

```bash
# Encrypt (Ansible will prompt for vault password)
ansible-vault encrypt ansible/vault/github_runner.yml

# Verify encryption
cat ansible/vault/github_runner.yml
# Should show: $ANSIBLE_VAULT;1.1;AES256;...
```

---

## Usage: Deploy Runners to BASTION01 and BASTION02

### Deploy to BASTION01

```bash
ansible-playbook -i inventory/hosts.yml playbooks/bastion01_github_runner.yml \
  --vault-id @prompt \
  -e @ansible/vault/github_runner.yml
```

When prompted, enter your vault password.

**What happens:**
1. Ansible reads your fine-grained token from vault
2. Calls GitHub API to generate a fresh registration token
3. Token is used immediately to register the runner
4. Registration token expires after 1 hour (not a problem - runner is already registered)
5. Your fine-grained token remains valid for the set expiration period (90 days recommended)

### Deploy to BASTION02

```bash
ansible-playbook -i inventory/hosts.yml playbooks/bastion02_github_runner.yml \
  --vault-id @prompt \
  -e @ansible/vault/github_runner.yml
```

**Note:** Each deployment generates its own fresh token - no conflicts, no token reuse.

---

## How Token Generation Works

### Step 1: GitHub API Call

```bash
POST https://api.github.com/repos/{owner}/{repo}/actions/runners/registration-token
Headers:
  Authorization: token github_pat_YOUR_TOKEN
  Accept: application/vnd.github.v3+json
```

**Response:**
```json
{
  "token": "AABCDEFG1234567890ABCDEFG1234567890ABCD",
  "expires_at": "2026-06-15T14:30:00Z"
}
```

### Step 2: Runner Registration

The token is immediately used to register the runner:
```bash
cd /home/svc_github_runner/actions-runner
./config.sh \
  --url "https://github.com/Roland-Chang/PhoenixStack" \
  --token "AABCDEFG1234567890ABCDEFG1234567890ABCD" \
  --name "bastion01-runner" \
  --labels "self-hosted,bastion01,infrastructure" \
  --unattended \
  --replace
```

### Step 3: Cleanup

The registration token expires after 1 hour, but it's no longer needed - the runner is already registered and authenticated to GitHub via its own credentials.

---

## Troubleshooting

### Error: "Invalid registration token"

**Cause:** Fine-grained token is invalid, expired, or lacks required permissions

**Solution:**
```bash
# 1. Verify token permissions at https://github.com/settings/personal-access-tokens
# Required: Administration (read/write) on PhoenixStack repository

# 2. If expired, generate new token and update vault:
ansible-vault edit ansible/vault/github_runner.yml
# Update github_api_token with new fine-grained token
```

### Error: "Failed to generate token: 404"

**Cause:** Repository owner/name are incorrect

**Solution:**
```bash
# Verify in vault file
ansible-vault view ansible/vault/github_runner.yml

# Correct example:
# github_repo_owner: "Roland-Chang"      ← Your GitHub username
# github_repo_name: "PhoenixStack"       ← Repo name only (not full URL)
```

### Error: "Token is invalid or expired"

**Cause:** Playbook took >1 hour to run, or PAT expired

**Solution:**
- Check playbook logs for delays
- Ensure bastion node is responsive
- Generate new PAT if needed

### Runner registered but not showing online

**Cause:** Runner service failed to start

**Solution:**
```bash
# SSH to bastion01
ssh root@10.101.0.20

# Check runner service status
systemctl status github-runner

# View logs
journalctl -u github-runner -f

# Manually start (if needed)
systemctl start github-runner
```

---

## Scaling to More Runners

To add BASTION03, BASTION04, etc.:

### 1. Deploy infrastructure (Terraform)
```bash
terraform apply -target=module.bastion03
```

### 2. Deploy base config (Ansible)
```bash
ansible-playbook -i inventory/hosts.yml playbooks/bastion_base.yml -l bastion03
```

### 3. Deploy runner with same vault credentials
```bash
ansible-playbook -i inventory/hosts.yml playbooks/bastion03_github_runner.yml \
  --vault-id @prompt \
  -e @ansible/vault/github_runner.yml
```

The same PAT in vault works for all runners - just create new playbooks for each bastion with appropriate labels and runner names.

---

## Security Best Practices

1. **Vault Password Management**
   - Use a strong vault password
   - Store vault password in `~/.ansible/vault_pass` (with restricted permissions)
   - Or use `--vault-id @prompt` (prompts each time)

2. **Fine-Grained Token Rotation**
   - Tokens have mandatory expiration (max 1 year, 90 days recommended)
   - GitHub requires periodic rotation automatically
   - Create new token with same permissions when current one expires
   - Update vault and re-encrypt

3. **Audit Token Usage**
   - GitHub logs all API calls made with your token
   - Review at: https://github.com/settings/personal-access-tokens/active
   - Revoke immediately if compromised
   - Fine-grained tokens show activity on a per-token basis

4. **Vault File Security**
   - `.gitignore` already excludes `vault/*`
   - Never commit unencrypted PAT
   - Backup encrypted vault files securely
