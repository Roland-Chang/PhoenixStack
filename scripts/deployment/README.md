# Deployment Scripts

Infrastructure deployment and management scripts for the Phoenix Stack.

## 📜 Scripts

### `deploy.sh`
Deploys full infrastructure (Bastion + DNS + services)

**Usage**:
```bash
./scripts/deployment/deploy.sh
# or via alias:
phoenix-deploy
# or via make:
make deploy
```

**What it does**:
- Changes to project root directory
- Loads all vault files (-e @ansible/vault/*.yml)
- Runs full `site.yml` playbook
- Configures all services

**Typical run time**: 3-5 minutes

---

### `destroy.sh`
Safely destroys all Terraform-managed infrastructure

**Usage**:
```bash
./scripts/deployment/destroy.sh
# or via alias:
phoenix-destroy
# or via make:
make destroy
```

**Safety features**:
- Shows preview of what will be destroyed
- Requires explicit "destroy" confirmation
- Uses `terraform destroy -auto-approve` after confirmation

**Typical run time**: 1-2 minutes

---

### `redeploy.sh`
Complete validation cycle: destroy → rebuild → reconfigure

**Usage**:
```bash
./scripts/deployment/redeploy.sh
# or via alias:
phoenix-redeploy
# or via make:
make redeploy
```

**Workflow**:
1. Destroys existing infrastructure
2. Applies Terraform to rebuild containers (waits 60 seconds for provisioning, adds 30 second buffer)
3. Waits 30 additional seconds for container stabilization
4. Runs full Ansible deployment
5. Reports completion status

**Perfect for**:
- Validating that full destroy→rebuild→reconfigure cycle works
- Testing infrastructure reproducibility
- Disaster recovery drills
- CI/CD pipeline testing

**Typical run time**: 8-12 minutes (including wait times)

---

### `status.sh`
Infrastructure health check and connectivity verification

**Usage**:
```bash
./scripts/deployment/status.sh
# or via alias:
phoenix-status
# or via make:
make status
```

**Checks performed**:
- Lists all Terraform-managed containers (with VMID, name, status)
- Tests SSH connectivity to Bastion
- Tests SSH connectivity to DNS
- Verifies PiHole container is running
- Checks 1Password CLI installation status
- Verifies GitHub runners are active
- Reports overall infrastructure health

**Typical run time**: 10-15 seconds

---

## 🔄 Common Workflows

### Initial Deployment
```bash
./scripts/deployment/deploy.sh
```

### Redeploy Specific Component
```bash
# Full redeployment with validation
./scripts/deployment/redeploy.sh

# Or specific component:
cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/dns_pihole.yml --vault-id vault/.vault_pass
```

### Destroy Everything
```bash
./scripts/deployment/destroy.sh
```

### Check Status
```bash
./scripts/deployment/status.sh
```

### Full Validation Test
```bash
./scripts/deployment/redeploy.sh  # Destroy + rebuild + reconfigure
```

---

## 🛠️ Make Targets

All deployment scripts are also available via make:

```bash
make deploy              # Deploy infrastructure
make destroy             # Destroy infrastructure
make redeploy            # Full cycle: destroy → rebuild → reconfigure
make status              # Check infrastructure health
```

---

## 🔐 Vault Integration

Deployment scripts automatically load vault files:
- `ansible/vault/github_runner.yml`
- `ansible/vault/onepassword.yml`
- `ansible/vault/pihole.yml`

The vault password is read from: `ansible/vault/.vault_pass`

Make sure:
- Vault password file exists and has 600 permissions
- All vault .yml files are in git .gitignore
- Never commit vault password file

---

## 📊 Expected Output Examples

### Successful Deployment
```
[BASTION01] Configuring 1Password client...
[BASTION01] Setting up GitHub runners...
[DNS01] Deploying PiHole container...
[DNS01] Configuring DNS records (27 total)...

✅ Deployment complete
- Bastion: ok=70, changed=31
- DNS: ok=50, changed=28
```

### Status Check Output
```
Terraform Containers:
  bastion01 (ID: 101) - Running
  dns01 (ID: 201) - Running
  ...

SSH Connectivity:
  ✅ Bastion accessible
  ✅ DNS accessible

Services:
  ✅ PiHole running
  ✅ 1Password CLI installed
  ✅ GitHub runners active

📊 Overall Status: HEALTHY
```

---

## ⚠️ Important Notes

- **Destruction operations require confirmation** - Type "destroy" when prompted
- **These scripts assume Proxmox hosts are already bootstrapped** - See `scripts/provisioning/` for host setup
- **Redeploy includes wait times** for container provisioning - Don't interrupt the process
- **SSH must be configured** for Ansible to work
- **Vault password file must exist** before deploying
- **All scripts have error handling** (set -e) - They fail fast on errors

---

## 🐛 Troubleshooting

### "Cannot find vault password file"
```bash
# Make sure it exists and has correct permissions
ls -la ansible/vault/.vault_pass
chmod 600 ansible/vault/.vault_pass
```

### SSH connection failures
```bash
# Check connectivity to Bastion
ssh -v ubuntu@bastion01

# Check inventory file
cat ansible/inventory/hosts.yml
```

### Deployment hangs on specific task
```bash
# Use verbose mode to see what's happening
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml -vv --vault-id ansible/vault/.vault_pass
```

### Container failed to provision
```bash
# Check Terraform state
terraform -chdir=terraform state list

# Check Proxmox directly via API or web UI
```

---

## 📖 Related Documentation

- [Main scripts README](../README.md)
- [Makefile](../../Makefile)
- [Git Integration Guide](../../SCRIPTS_GIT_GUIDE.md)
- [Ansible Playbook Guide](../../docs/ANSIBLE_PLAYBOOK_GUIDE.md)
