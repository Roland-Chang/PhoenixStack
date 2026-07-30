# GitHub Actions Self-Hosted Runner Setup

**Purpose:** Install and configure GitHub Actions self-hosted runners on bastion infrastructure to execute Terraform and Ansible workflows locally within the Proxmox environment.

**Status:** 📅 Phase 3 (BASTION01 Deployment) - Infrastructure-as-Code implemented, awaiting deployment  
**Readiness:** ✅ Ansible roles and playbooks ready for deployment

---

## 📋 Table of Contents

1. [Quick Start](#quick-start)
2. [Part 1: Basic Setup](#part-1-basic-setup)
3. [Part 2: Advanced - Dynamic Token Generation](#part-2-advanced---dynamic-token-generation)
4. [Maintenance & Operations](#maintenance--operations)
5. [Scaling to Multiple Runners](#scaling-to-multiple-runners)
6. [Troubleshooting](#troubleshooting)
7. [References](#references)

---

## Quick Start

**For first-time setup:** Follow [Part 1: Basic Setup](#part-1-basic-setup) for manual token workflow.  
**For automated deployments:** Use [Part 2: Dynamic Token Generation](#part-2-advanced---dynamic-token-generation) for API-driven token management.  
**For maintenance:** Jump to [Maintenance & Operations](#maintenance--operations).

---

## Part 1: Basic Setup

### Prerequisites

1. **Bastion01 deployed and accessible**
   ```bash
   # Verify connectivity
   ssh root@10.101.0.20
   ```

2. **Bastion01 base configuration complete**
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/bastion01_base.yml
   ```

3. **GitHub repository access**
   - Need ability to register self-hosted runners in your GitHub repository

---

### Step 1: Get a Registration Token from GitHub

Registration tokens allow the runner to authenticate with GitHub. They expire after 1 hour.

**Via GitHub Web UI:**
1. Go to your repository: `https://github.com/username/phoenixstack`
2. Navigate to **Settings** → **Actions** → **Runners**
3. Click **"New self-hosted runner"** (top right)
4. Keep this window open; you'll need the token in the next step

**Token appears after OS selection; it looks like:**
```
ABCDEFG1234567890ABCDEFG1234567890ABCD
```

---

### Step 2: Run the Ansible Playbook

#### Option A: Using Ansible Vault (Recommended - Most Secure)

Vault encrypts sensitive variables at rest in git.

```bash
# 1. Create vault file from template
cp ansible/vault/github_runner.yml.example ansible/vault/github_runner.yml

# 2. Edit the vault file with your token and repo URL
nano ansible/vault/github_runner.yml

# 3. Encrypt the vault file
ansible-vault encrypt ansible/vault/github_runner.yml

# 4. Run playbook with vault
ansible-playbook -i inventory/hosts.yml playbooks/bastion01_github_runner.yml \
  --vault-id @prompt \
  -e @ansible/vault/github_runner.yml
```

When prompted, enter your vault password.

#### Option B: Using Command-Line Variables (Quick, Less Secure)

```bash
ansible-playbook -i inventory/hosts.yml playbooks/bastion01_github_runner.yml \
  -e "github_repo_url=https://github.com/username/phoenixstack" \
  -e "github_runner_registration_token=YOUR_TOKEN_HERE"
```

⚠️ **Warning:** Token appears in shell history with this method. Only use in trusted environments.

#### Option C: Interactive Prompts (Most User-Friendly)

```bash
ansible-playbook -i inventory/hosts.yml playbooks/bastion01_github_runner.yml

# When prompted:
# github_repo_url []: https://github.com/username/phoenixstack
# github_runner_registration_token []: ABCDEFG1234567890...
```

---

### Step 3: Verify Runner Registration

Once the playbook completes successfully:

#### Check Runner Status on GitHub

1. Go to **Settings** → **Actions** → **Runners** in your repository
2. You should see "bastion01-runner" listed as **Idle** and **Online**

#### Check Runner Status Locally on Bastion01

```bash
# SSH into bastion01
ssh root@10.101.0.20

# View runner service status
systemctl status github-runner

# View runner logs (last 50 lines, follow output)
journalctl -u github-runner -n 50 -f

# View runner process
ps aux | grep -i runner
```

---

### Step 4: Update GitHub Actions Workflow

Update `.github/workflows/terraform.yml` to use the self-hosted runner:

```yaml
apply:
  name: Terraform Apply
  needs: validate
  runs-on: self-hosted  # <-- Changed from ubuntu-latest
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  # ... rest of job ...
```

The Terraform workflow in this repository has already been updated to use `runs-on: self-hosted` for the `apply` job.

---

### Step 5: Test the Integration

#### Create a Simple Test Workflow

Create `.github/workflows/test-runner.yml`:

```yaml
name: Test Self-Hosted Runner

on:
  workflow_dispatch:

jobs:
  test:
    name: Test Runner
    runs-on: self-hosted
    steps:
      - name: System Info
        run: |
          echo "Hostname: $(hostname)"
          echo "Kernel: $(uname -a)"
          echo "Runner User: $(whoami)"
      
      - name: Check Terraform
        run: terraform --version
      
      - name: Check Ansible
        run: ansible --version
```

**Trigger:**
1. Go to **Actions** tab in your repository
2. Select "Test Self-Hosted Runner"
3. Click **"Run workflow"** → **"Run workflow"** (dropdown)
4. Observe job execution on your runner

---

## Part 2: Advanced - Dynamic Token Generation

### Overview

Instead of manually generating short-lived registration tokens via the GitHub UI, use **Ansible to generate fresh tokens dynamically via GitHub API** for each runner deployment.

**Benefits:**
- **No manual token copying** - Eliminate the 1-hour expiration window
- **Single fine-grained token in vault** - Store one secure GitHub token with least-privilege permissions
- **Scalable deployment** - Deploy multiple runners (BASTION01, BASTION02, etc.) without regenerating tokens
- **Consistent automation** - Same token generation flow for all runners
- **Better security** - Fine-grained tokens offer repository-level and permission-level control

---

### Step 1: Create a GitHub Fine-Grained Personal Access Token

GitHub's newer fine-grained tokens replace the need for manual registration tokens and offer better security than classic PATs.

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

### Step 2: Configure Vault with GitHub PAT

#### Create Vault File from Template

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

#### Encrypt the Vault File

```bash
# Encrypt (Ansible will prompt for vault password)
ansible-vault encrypt ansible/vault/github_runner.yml

# Verify encryption
cat ansible/vault/github_runner.yml
# Should show: $ANSIBLE_VAULT;1.1;AES256;...
```

---

### Step 3: Deploy Runners with Dynamic Token Generation

#### Deploy to BASTION01

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

#### Deploy to BASTION02

```bash
ansible-playbook -i inventory/hosts.yml playbooks/bastion02_github_runner.yml \
  --vault-id @prompt \
  -e @ansible/vault/github_runner.yml
```

**Note:** Each deployment generates its own fresh token - no conflicts, no token reuse.

---

### How Token Generation Works

#### GitHub API Call

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

#### Runner Registration

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

#### Cleanup

The registration token expires after 1 hour, but it's no longer needed - the runner is already registered and authenticated to GitHub via its own credentials.

---

## Maintenance & Operations

### Restart the Runner Service

If the runner becomes unresponsive:

```bash
ssh root@10.101.0.20
systemctl restart github-runner
systemctl status github-runner
```

### View Detailed Logs

```bash
ssh root@10.101.0.20
journalctl -u github-runner --since "1 hour ago"  # Last hour
journalctl -u github-runner -e                     # Most recent 50 lines
journalctl -u github-runner -f                     # Follow live logs
```

### Runner Configuration Files

Located on bastion01:
- **Installation:** `/home/svc_github_runner/actions-runner/`
- **Configuration:** `/home/svc_github_runner/actions-runner/.runner`
- **Work directory:** `/home/svc_github_runner/actions-runner/_work/`

### Update Runner Version

To update the runner to a newer version:

1. Update `runner_version` in `ansible/roles/github_runner/defaults/main.yml`
2. Re-run the playbook:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/bastion01_github_runner.yml \
     -e @ansible/vault/github_runner.yml \
     --vault-id @prompt
   ```

---

## Scaling to Multiple Runners

### Deploy Additional Runners

To add BASTION03, BASTION04, etc.:

#### 1. Deploy infrastructure (Terraform)
```bash
terraform apply -target=module.bastion03
```

#### 2. Deploy base config (Ansible)
```bash
ansible-playbook -i inventory/hosts.yml playbooks/bastion_base.yml -l bastion03
```

#### 3. Deploy runner with same vault credentials
```bash
ansible-playbook -i inventory/hosts.yml playbooks/bastion03_github_runner.yml \
  --vault-id @prompt \
  -e @ansible/vault/github_runner.yml
```

The same PAT in vault works for all runners - just create new playbooks for each bastion with appropriate labels and runner names.

---

## Troubleshooting

### Issue: Runner appears offline in GitHub UI

```bash
ssh root@10.101.0.20
systemctl status github-runner
journalctl -u github-runner -n 50
```

**Check for:**
- Network connectivity: `curl https://api.github.com/repos/username/phoenixstack -I`
- Token validity (tokens expire after 1 hour)
- DNS resolution: `nslookup api.github.com`

**Solution:**
```bash
systemctl restart github-runner
```

---

### Issue: Runner job hangs or never completes

```bash
# Check runner process
ps aux | grep -i runner

# Check for stuck jobs
ls -la /home/svc_github_runner/actions-runner/_work/

# Restart runner
systemctl restart github-runner
```

---

### Error: "Invalid registration token" (Dynamic Token Generation)

**Cause:** Fine-grained token is invalid, expired, or lacks required permissions

**Solution:**
```bash
# 1. Verify token permissions at https://github.com/settings/personal-access-tokens
# Required: Administration (read/write) on PhoenixStack repository

# 2. If expired, generate new token and update vault:
ansible-vault edit ansible/vault/github_runner.yml
# Update github_api_token with new fine-grained token
```

---

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

---

### Issue: Permission denied errors in job

The runner executes as `svc_github_runner` user. If jobs need elevated privileges:

1. **Don't use sudo** - Configure the workflow to not need it
2. **Add to sudoers** (not recommended):
   ```bash
   usermod -aG sudo svc_github_runner
   ```

---

### Issue: Terraform state lock errors

Multiple runners/jobs trying to apply simultaneously cause state locks:

1. Review GitHub Actions workflow to ensure only one apply job runs at a time
2. Check for stuck locks: `ls -la /home/svc_github_runner/actions-runner/_work/*/.terraform.d/`

---

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

## Security Considerations

### Token Security

1. **Registration Tokens (Basic Setup):**
   - Valid for 1 hour only
   - Always store in ansible-vault or GitHub Secrets
   - Never commit plaintext tokens to git

2. **Fine-Grained PATs (Advanced Setup):**
   - Tokens have mandatory expiration (max 1 year, 90 days recommended)
   - Store only in encrypted vault
   - Rotate before expiration
   - Revoke immediately if compromised

### Runner User Privileges

- Runner executes as unprivileged `svc_github_runner` user
- If jobs need root access, reconsider the workflow design
- Avoid using `sudo` in workflows

### Network Access

- Runner has outbound HTTPS access to github.com
- Internal Proxmox API credentials stored in GitHub Secrets
- Terraform state stored locally on bastion01 (protected by Proxmox backups)

### Audit Trail

- All GitHub Actions jobs logged in GitHub UI
- All Ansible execution logged via journalctl
- All infrastructure changes logged in terraform.tfstate
- Fine-grained PAT usage tracked at: https://github.com/settings/personal-access-tokens/active

### Vault File Security

- `.gitignore` already excludes `vault/*`
- Never commit unencrypted PAT or registration tokens
- Backup encrypted vault files securely
- Use strong vault password

---

## Next Steps

### After Basic Setup (Part 1)

1. ✅ Runner installed and online
2. ⏭️ Configure GitHub repository secrets for Proxmox API tokens
3. ⏭️ Update Terraform GitHub Actions workflow to use runner
4. ⏭️ Create test workflow to validate integration
5. ⏭️ Document runbook for common operations

### After Advanced Setup (Part 2)

1. ✅ Dynamic token generation configured
2. ⏭️ Deploy additional runners (BASTION02, etc.)
3. ⏭️ Set calendar reminder for PAT rotation (before expiration)
4. ⏭️ Configure GitHub webhook notifications for runner status
5. ⏭️ Integrate with monitoring/alerting system

---

## References

### Official Documentation

- [GitHub Actions Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Registering Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners)
- [GitHub Fine-Grained PATs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token#creating-a-fine-grained-personal-access-token)
- [GitHub Runner API](https://docs.github.com/en/rest/actions/self-hosted-runners)

### Ansible Documentation

- [Ansible Vault Documentation](https://docs.ansible.com/ansible/latest/user_guide/vault.html)
- [Ansible URI Module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/uri_module.html)

### System Administration

- [Systemd Service Management](https://www.freedesktop.org/software/systemd/man/systemctl.html)
- [Journalctl Documentation](https://www.freedesktop.org/software/systemd/man/journalctl.html)

---

*Last Updated: 2026-07-29 (Documentation consolidated)*  
*Phase 3 Status: Infrastructure ready, awaiting deployment*
