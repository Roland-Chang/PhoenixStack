# BASTION01 Fresh Deployment Sequence

Complete step-by-step guide to deploy BASTION01 from scratch with consolidated Ansible setup.

## Prerequisites

- Terraform initialized and ready
- 1Password service account token created and stored securely
- GitHub runner registration token ready (from GitHub Settings > Actions > Runners)
- Proxmox environment running at configured IP

## Step 1: Destroy Existing Infrastructure

```bash
cd terraform

# Confirm you're in the correct directory
pwd  # Should be: /home/ayoung/projects/phoenixstack/terraform

# Review what will be destroyed (optional)
terraform plan -destroy

# Destroy all resources
terraform destroy -auto-approve
```

**Expected output:** All Proxmox LXC containers removed

## Step 2: Deploy Fresh Infrastructure

```bash
# Still in terraform directory

# Create all infrastructure from scratch
terraform apply -auto-approve
```

**Expected output:**
- `bastion01` LXC container created at `10.101.0.20`
- Access via SSH as `root` user

## Step 3: Wait for SSH Readiness

```bash
# Test SSH connectivity (should succeed after ~10-15 seconds)
ssh -i ~/.ssh/id_rsa root@10.101.0.20 "echo 'SSH ready'"

# Alternative: Use ansible to wait
cd ..  # Go back to phoenixstack root
ansible bastion01 -i ansible/inventory/hosts.yml -m wait_for_connection
```

## Step 4: Run Consolidated BASTION01 Setup

This single playbook handles all setup:
1. Base system configuration
2. 1Password CLI installation
3. GitHub Actions runner installation and registration

### Option A: Interactive (Recommended for first run)

```bash
cd /home/ayoung/projects/phoenixstack

ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/bastion01_full_setup.yml \
  -e "github_runner_registration_token=<YOUR_GITHUB_TOKEN>"
```

When prompted, enter the service account password for `svc_ansible` user.

### Option B: With Vault File

If you have an encrypted vault file with the 1Password token:

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/bastion01_full_setup.yml \
  --vault-password-file ~/.vault_pass \
  -e "github_runner_registration_token=<YOUR_GITHUB_TOKEN>"
```

### Option C: With All Variables on Command Line

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/bastion01_full_setup.yml \
  -e "svc_ansible_password=MyPassword123" \
  -e "github_runner_registration_token=<YOUR_GITHUB_TOKEN>" \
  -e "onepassword_service_account_token=<YOUR_1PASSWORD_TOKEN>"
```

### Option D: Run Specific Roles Only

If you only need to reinstall the runner (skip base + 1Password):

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/bastion01_full_setup.yml \
  --tags runner \
  -e "github_runner_registration_token=<YOUR_GITHUB_TOKEN>"
```

Available tags: `base`, `onepassword`, `runner`, `always`

## Step 5: Verify Deployment

### Check Playbook Output

The playbook's post_tasks will display:
- ✓ 1Password CLI account verification
- ✓ GitHub runner service status
- ✓ GitHub runner enabled for auto-start

### Verify in GitHub UI

1. Go to: **GitHub Repository → Settings → Actions → Runners**
2. Look for **"bastion01-runner"**
3. Status should show: **ONLINE** and **IDLE**

### Manual Verification on bastion01

```bash
# Test 1Password CLI
ssh root@10.101.0.20

# Check 1Password
op whoami

# Check GitHub runner service
systemctl status github-runner

# Check runner logs
journalctl -u github-runner -n 50 -f
```

## Step 6: Test CI/CD Pipeline

Push a small Terraform change to trigger the workflow:

```bash
cd terraform

# Make a trivial change (e.g., add comment)
echo "# Test deployment" >> README.md

# Commit and push
git add -A
git commit -m "test: trigger GitHub Actions workflow"
git push origin main
```

**Expected workflow progression:**
1. ✓ **Validate** job (ubuntu-latest) - Terraform syntax check
2. ✓ **Plan** job (ubuntu-latest) - Shows infrastructure changes
3. ✓ **Apply** job (bastion01-runner) - Executes Terraform apply on self-hosted runner

## Troubleshooting

### SSH Connection Fails
```bash
# Wait longer for container startup
sleep 30
ansible bastion01 -i ansible/inventory/hosts.yml -m ping
```

### Playbook Fails on 1Password
- Verify `onepassword_service_account_token` is correct
- Check file permissions: `ls -la /etc/phoenixstack/1password_token` (should be 0600)

### Playbook Fails on GitHub Runner
- Verify runner registration token is valid (not expired)
- Check GitHub token hasn't been used already (can only register once per token)

### Runner Not Appearing in GitHub UI
- Check playbook `post_tasks` output for errors
- View runner logs: `ssh root@10.101.0.20 "journalctl -u github-runner -n 20"`

### Runner Shows OFFLINE
- Check service status: `ssh root@10.101.0.20 "systemctl status github-runner"`
- Verify network connectivity: `ssh root@10.101.0.20 "ping 8.8.8.8"`

## Quick Reference: All-in-One Command

```bash
# Complete fresh deployment in one command
cd /home/ayoung/projects/phoenixstack && \
  terraform destroy -auto-approve && \
  terraform apply -auto-approve && \
  sleep 15 && \
  ansible-playbook -i ansible/inventory/hosts.yml \
    ansible/playbooks/bastion01_full_setup.yml \
    -e "github_runner_registration_token=<YOUR_TOKEN>"
```

## Cleanup (Individual Playbooks)

The following original playbooks are now superseded by `bastion01_full_setup.yml`:
- `ansible/playbooks/bastion01_base.yml`
- `ansible/playbooks/bastion01_onepassword.yml`
- `ansible/playbooks/bastion01_github_runner_1password.yml`

They are still available for reference but should not be used in production. To clean up:

```bash
# Optional: Archive old playbooks for reference
mkdir -p ansible/playbooks/archived
mv ansible/playbooks/bastion01_base.yml ansible/playbooks/archived/
mv ansible/playbooks/bastion01_onepassword.yml ansible/playbooks/archived/
mv ansible/playbooks/bastion01_github_runner_1password.yml ansible/playbooks/archived/
```

## Expected Timeline

- **terraform destroy**: ~20 seconds
- **terraform apply**: ~30-45 seconds
- **SSH ready**: ~5-15 seconds
- **Ansible playbook**: ~2-3 minutes total
  - Base config: ~1 minute
  - 1Password CLI: ~30 seconds
  - GitHub runner: ~1-2 minutes
- **Total deployment time**: ~5-7 minutes

