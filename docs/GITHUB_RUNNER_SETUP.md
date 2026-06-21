# GitHub Actions Self-Hosted Runner Setup - BASTION01

**Purpose:** Install and configure a GitHub Actions self-hosted runner on bastion01 to execute Terraform and Ansible workflows locally within the Proxmox environment.

**Status:** Infrastructure-as-Code implemented via Ansible role and playbook.

---

## Quick Start

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

3. **GitHub personal access token or repository access**
   - Need ability to register self-hosted runners in your GitHub repository

---

## Step 1: Get a Registration Token from GitHub

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

## Step 2: Run the Ansible Playbook

### Option A: Using Ansible Vault (Recommended - Most Secure)

Vault encrypts sensitive variables at rest in git.

```bash
# 1. Create vault file from template
cp ansible/vault/github_runner.yml.example ansible/vault/github_runner.yml

# 2. Edit the vault file with your token and repo URL
# (use your editor or ansible-vault edit)
nano ansible/vault/github_runner.yml

# 3. Encrypt the vault file
ansible-vault encrypt ansible/vault/github_runner.yml

# 4. Run playbook with vault
ansible-playbook -i inventory/hosts.yml playbooks/bastion01_github_runner.yml \
  --vault-id @prompt \
  -e @ansible/vault/github_runner.yml
```

When prompted, enter your vault password.

### Option B: Using Command-Line Variables (Quick, Less Secure)

```bash
ansible-playbook -i inventory/hosts.yml playbooks/bastion01_github_runner.yml \
  -e "github_repo_url=https://github.com/username/phoenixstack" \
  -e "github_runner_registration_token=YOUR_TOKEN_HERE"
```

⚠️ **Warning:** Token appears in shell history with this method. Only use in trusted environments.

### Option C: Interactive Prompts (Most User-Friendly)

```bash
ansible-playbook -i inventory/hosts.yml playbooks/bastion01_github_runner.yml

# When prompted:
# github_repo_url []: https://github.com/username/phoenixstack
# github_runner_registration_token []: ABCDEFG1234567890...
```

---

## Step 3: Verify Runner Registration

Once the playbook completes successfully:

### Check Runner Status on GitHub

1. Go to **Settings** → **Actions** → **Runners** in your repository
2. You should see "bastion01-runner" listed as **Idle** and **Online**

### Check Runner Status Locally on Bastion01

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

## Step 4: Update GitHub Actions Workflow

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

## Step 5: Test the Integration

### Create a Simple Test Workflow

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

## Maintenance

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

## Troubleshooting

### Issue: Runner appears offline in GitHub UI

```bash
ssh root@10.101.0.20
systemctl status github-runner
journalctl -u github-runner -n 50
```

Check for:
- Network connectivity: `curl https://api.github.com/repos/username/phoenixstack -I`
- Token validity (tokens expire after 1 hour)
- DNS resolution: `nslookup api.github.com`

### Issue: Runner job hangs or never completes

```bash
# Check runner process
ps aux | grep -i runner

# Check for stuck jobs
ls -la /home/svc_github_runner/actions-runner/_work/

# Restart runner
systemctl restart github-runner
```

### Issue: Permission denied errors in job

The runner executes as `svc_github_runner` user. If jobs need elevated privileges:

1. **Don't use sudo** - Configure the workflow to not need it
2. **Add to sudoers** (not recommended):
   ```bash
   usermod -aG sudo svc_github_runner
   ```

### Issue: Terraform state lock errors

Multiple runners/jobs trying to apply simultaneously cause state locks:

1. Review GitHub Actions workflow to ensure only one apply job runs at a time
2. Check for stuck locks: `ls -la /home/svc_github_runner/actions-runner/_work/*/.terraform.d/`

---

## Security Considerations

1. **Token Security:**
   - Registration tokens are valid for 1 hour
   - Always store in ansible-vault or GitHub Secrets
   - Never commit plaintext tokens to git

2. **Runner User Privileges:**
   - Runner executes as unprivileged `svc_github_runner` user
   - If jobs need root access, reconsider the workflow design
   - Avoid using `sudo` in workflows

3. **Network Access:**
   - Runner has outbound HTTPS access to github.com
   - Internal Proxmox API credentials stored in GitHub Secrets
   - Terraform state stored locally on bastion01 (protected by Proxmox backups)

4. **Audit Trail:**
   - All GitHub Actions jobs logged in GitHub UI
   - All Ansible execution logged via journalctl
   - All infrastructure changes logged in terraform.tfstate

---

## Next Steps

1. ✅ Runner installed and online
2. ⏭️ Configure GitHub repository secrets for Proxmox API tokens
3. ⏭️ Update Terraform GitHub Actions workflow to use runner
4. ⏭️ Create test workflow to validate integration
5. ⏭️ Document runbook for common operations (deployments, updates, rollbacks)

---

## References

- [GitHub Actions Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Registering Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners)
- [Ansible Vault Documentation](https://docs.ansible.com/ansible/latest/user_guide/vault.html)
- [Systemd Service Management](https://www.freedesktop.org/software/systemd/man/systemctl.html)
