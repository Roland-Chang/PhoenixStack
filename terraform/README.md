# Terraform IaC for Phoenix Stack

Infrastructure as Code using Terraform to provision containers and infrastructure on Proxmox VE.

## ⚠️ Prerequisites (READ BEFORE DEPLOYING)

**CRITICAL: Verify these are configured in Proxmox BEFORE running `terraform apply`**

### 1. Storage Pool (REQUIRED)
Your Proxmox node must have an **`ssd`** storage pool:
- **Type**: LVM-thin, SSD filesystem, or ZFS (NOT directory-based "local" storage)
- **Minimum Size**: 500GB+
- **Used by**: ALL containers (BASTION01-02, DNS01-02, PROXY01-02, AUTHENTIK01-02, DOCKER01-02, PLEX01)

**⚠️ Common Error:**
```
Error: storage 'local' does not support container directories
```
**Solution**: Create an LVM-thin or SSD-based pool named `ssd`

To verify:
```bash
# Via Proxmox Web UI: Datacenter > Storage (check Pool Type)
# Via SSH: pvesh get /storage | grep -A5 ssd
```

If missing, see [README_STORAGE_POOLS.md](README_STORAGE_POOLS.md) to create it.

### 2. Proxmox API Token
An API token must be created with appropriate permissions:
- Log into Proxmox Web UI (https://pve-ip:8006)
- Datacenter > API Tokens > Add
- Token ID: `terraform-token`
- Realm: `pam`
- Grant: Datastore.Allocate, Datastore.AllocateSpace, Datastore.Audit, SDN.Use, Sys.Audit, VM.Allocate, VM.Audit, VM.Clone, VM.Config.*, VM.Console, VM.PowerMgmt

### 3. Network Bridge
A network bridge for the management VLAN must exist:
- Expected bridge: `vmbr0` or similar
- Network: `10.101.0.0/24`
- Gateway: `10.101.0.254`

### 4. LXC Template
An LXC container template must be available (usually pre-installed):
- Check Proxmox > Node > local (storage) > CT Templates
- Recommended: Debian 12 template

### 5. SSH Public Key
Your SSH public key (in 1Password) must be added to `terraform.tfvars`
- Format: `ssh_public_keys = ["ssh-ed25519 AAAA... comment"]`

**If any of these are missing, `terraform apply` will fail. See troubleshooting section below.**

## 📁 Structure

```
terraform/
├── terraform.tf             # Backend and terraform config (Azure Storage)
├── providers.tf             # Proxmox provider definition
├── terraform.tfvars         # ⚠️ Secrets (do NOT commit)
├── terraform.tfvars.example # Template for terraform.tfvars
├── modules/                 # Reusable Terraform modules
│   └── lxc/                # LXC container module
│       ├── main.tf         # Container resource definition
│       ├── variables.tf    # Input variables
│       └── outputs.tf      # Outputs
├── bastion01/              # BASTION01 (control plane, Ansible, GitHub runner)
│   ├── main.tf             # Module instantiation
│   ├── variables.tf        # Variable definitions
│   └── auto.tfvars         # Pre-configured values
├── dns01/                  # DNS01 (PiHole)
├── proxy01/                # PROXY01 (Traefik reverse proxy)
├── authentik01/            # AUTHENTIK01 (OAuth provider)
├── docker01/               # DOCKER01 (container services)
└── plex01/                 # PLEX01 (media server)
```

## 🔑 Key Concepts

### Providers
The `providers/` directory contains shared provider configuration for Proxmox API access. This is included by all deployment configurations.

### Modules
The `modules/lxc/` directory contains a reusable module for deploying LXC containers. This module can be used for ANSIBLE01, PROXY01, DNS01, and other containers.

### Deployments
Each container gets its own directory (e.g., `bastion01/`, `dns01/`, etc.) that instantiates the LXC module with container-specific variables. The `auto.tfvars` file is automatically loaded for each deployment.

## 🚀 Quick Start - BASTION01 Example

### 1. Initialize Terraform

```bash
cd bastion01
terraform init
```

### 2. Review Configuration

```bash
cat auto.tfvars  # Review pre-configured values
```

### 3. Plan Deployment

```bash
terraform plan -out=tfplan
```

### 4. Apply Configuration

```bash
terraform apply tfplan
```

**Note:** BASTION01 uses `auto.tfvars` which is automatically loaded. No need to copy from example.

## 🔐 Security

### Protecting Secrets

**Never commit**:
- `terraform.tfvars` files (contains API tokens)
- `.terraform/` directories (contains sensitive state)
- `*.tfstate` or `*.tfstate.backup` (infrastructure state)

**Instead**:
- Use `terraform.tfvars.example` as a template
- Store `terraform.tfvars` locally (it's in `.gitignore`)
- OR set credentials via environment variables: `TF_VAR_proxmox_api_token_id` and `TF_VAR_proxmox_api_token_secret`
- Use remote state backend (Terraform Cloud) for team environments

### Credential Rotation (June 2026)

**Status**: ✅ Credentials rotated on 2026-06-17 following security audit
- ✓ Old token secret removed from git history using `git filter-branch`
- ✓ New API token generated in Proxmox (token ID: `root@pam!terraform-token-v2`)
- ✓ `terraform.tfvars` protected by `.gitignore` and never committed
- ✓ Environment variable injection available for CI/CD

### Example - Setting Credentials via terraform.tfvars

```hcl
# terraform.tfvars (NOT committed - exists locally only)
# This file is in .gitignore for security
proxmox_api_url          = "https://10.101.0.11:8006/api2/json"
proxmox_api_token_id     = "root@pam!terraform-token-v2"
proxmox_api_token_secret = "YOUR_TOKEN_SECRET"  # Get from 1Password
```

### Example - Setting Credentials via Environment Variables

**Bash/Linux:**
```bash
# Local development
export TF_VAR_proxmox_api_url="https://10.101.0.11:8006/api2/json"
export TF_VAR_proxmox_api_token_id="root@pam!terraform-token-v2"
export TF_VAR_proxmox_api_token_secret="YOUR_TOKEN_SECRET"

terraform plan
terraform apply
```

**PowerShell/Windows:**
```powershell
$env:TF_VAR_proxmox_api_url = "https://10.101.0.11:8006/api2/json"
$env:TF_VAR_proxmox_api_token_id = "root@pam!terraform-token-v2"
$env:TF_VAR_proxmox_api_token_secret = "YOUR_TOKEN_SECRET"

terraform plan
terraform apply
```

### GitHub Actions / CI/CD

For automated deployments, store credentials as GitHub Secrets:

1. GitHub Settings → Secrets and variables → Actions
2. Add secrets:
   - `PROXMOX_API_URL`: `https://10.101.0.11:8006/api2/json`
   - `PROXMOX_API_TOKEN_ID`: `root@pam!terraform-token-v2`
   - `PROXMOX_API_TOKEN_SECRET`: (from 1Password)
   - `SSH_PUBLIC_KEY`: (from 1Password)

3. Use in workflow:
```yaml
- name: Terraform Plan
  env:
    TF_VAR_proxmox_api_url: ${{ secrets.PROXMOX_API_URL }}
    TF_VAR_proxmox_api_token_id: ${{ secrets.PROXMOX_API_TOKEN_ID }}
    TF_VAR_proxmox_api_token_secret: ${{ secrets.PROXMOX_API_TOKEN_SECRET }}
    TF_VAR_ssh_public_keys: ${{ secrets.SSH_PUBLIC_KEY }}
  run: terraform plan
```

---

## 🔑 SSH Public Key Configuration

### Local Development

SSH keys are required for root access to all containers. They should **NOT** be hardcoded in `terraform.tfvars`.

**Bash/Linux:**
```bash
# Export your public key as environment variable
export TF_VAR_ssh_public_keys="$(cat ~/.ssh/id_ed25519.pub)"
# Or for RSA:
export TF_VAR_ssh_public_keys="$(cat ~/.ssh/id_rsa.pub)"

# Now terraform will use your key
terraform plan
```

**PowerShell/Windows:**
```powershell
# Get your public key content
$pubkey = Get-Content ~/.ssh/id_ed25519.pub
$env:TF_VAR_ssh_public_keys = $pubkey

terraform plan
```

**For Multiple SSH Keys:**
```bash
# Separate keys with newlines (Terraform will read as single variable)
export TF_VAR_ssh_public_keys="ssh-ed25519 AAAA... user1@host
ssh-rsa BBBB... user2@host"

terraform plan
```

### Multiple Developers (Different SSH Keys)

If team members have different SSH keys, each developer should set their own environment variable:

```bash
# Developer A
export TF_VAR_ssh_public_keys="$(cat ~/.ssh/id_ed25519.pub)"

# Developer B (different key)
export TF_VAR_ssh_public_keys="$(cat ~/.ssh/id_rsa.pub)"
```

Or create per-developer `.tfvars` files:
```bash
# terraform.tfvars.alice (gitignore'd)
ssh_public_keys = "ssh-ed25519 AAAA... alice@laptop"

# terraform.tfvars.bob (gitignore'd)
ssh_public_keys = "ssh-rsa BBBB... bob@workstation"

# Use with: terraform plan -var-file=terraform.tfvars.alice
```

### GitHub Actions / CI/CD

Store SSH public key as GitHub Secret:

1. GitHub Settings → Secrets and variables → Actions
2. Add secret: `SSH_PUBLIC_KEY` = (your public key from 1Password)
3. Reference in workflow (see example above)

**Important**: Store the **public key** (`.pub` file), not the private key!

---

### Proxmox API Token Permissions (Permanent Constraint)

**What**: Proxmox API tokens permanently cannot set or modify `keyctl` and `mknod` feature flags. Only `root@pam` can change these flags.

**Error (when not handled)**: 
```
403 Permission check failed (changing feature flags (except nesting) is only allowed for root@pam)
```

### How This Project Handles It

The LXC module uses **`lifecycle.ignore_changes = [features]`** to prevent Terraform from attempting to modify flags that the token doesn't have permission to change.

**Result**:
- ✅ All containers deploy successfully without permission errors
- ✅ Containers function identically regardless of feature flag values  
- ✅ Terraform operations never fail due to feature flag restrictions
- ✅ New containers created with sensible Proxmox defaults

**Technical**:
- Terraform ignores feature flag drift to prevent impossible modifications
- Only `nesting=true` is explicitly managed (required for systemd compatibility)
- Other flags (`keyctl`, `mknod`, `fuse`) left to Proxmox defaults
- Pre-existing containers keep their original flag values without causing errors

**Container Status**:
| Container | VMID | nesting | keyctl | mknod |
|-----------|------|---------|--------|-------|
| bastion01 | 101 | ✓ | (various) | (various) |
| bastion02 | 100 | ✓ | (default) | (default) |
| dns01 | 102 | ✓ | (default) | (default) |
| dns02 | 103 | ✓ | (default) | (default) |

All containers run successfully. Flag differences have no operational impact.

### If You Need Specific Flag Values Later

**Manual Setup (Recommended)**:
```bash
ssh root@pve01
pct set 102 -features keyctl=1,mknod=1
pct restart 102
```

**For More Information**: See [modules/lxc/README.md](modules/lxc/README.md#-important-proxmox-api-token-permissions--feature-flags) for detailed explanation.

## 📋 Modules Reference

### LXC Module

**Purpose**: Deploy Ubuntu LXC containers on Proxmox

**Required Variables**:
- `vmid`: Unique container ID (100-999999)
- `hostname`: Container name
- `ip_address`: IPv4 address
- `gateway`: Default gateway
- `ssh_public_keys`: SSH key(s) for access

**Optional Variables**:
- `cpu_cores`: CPU allocation (default: 2)
- `memory_mb`: RAM in MB (default: 2048)
- `storage_size`: Root disk size in GB (default: 16)
- `network_bridge`: Proxmox bridge (default: vmbr0)

**Example Usage**:
```hcl
module "my_container" {
  source = "../modules/lxc"
  
  vmid                = 102
  hostname            = "mycontainer"
  ip_address          = "10.101.0.21"
  gateway             = "10.101.0.254"
  ssh_public_keys     = "ssh-import-id-gh:username"
  proxmox_node        = "pve01"
  cpu_cores           = 4
  memory_mb           = 8192
  storage_size        = 32
}
```

**Full Documentation**: See [modules/lxc/README.md](modules/lxc/README.md) for complete reference.

## 🔄 Deployment Workflow

### For New Containers (PROXY01, DNS01, etc.)

1. **Create directory**:
   ```bash
   mkdir terraform/proxy01
   ```

2. **Create main.tf** (copy from ansible01):
   ```bash
   cp ansible01/main.tf proxy01/main.tf
   # Edit module name: proxy01
   ```

3. **Create variables.tf** (customize for container):
   ```bash
   cp ansible01/variables.tf proxy01/variables.tf
   # Edit defaults: container_vmid, hostname, ip_address, etc.
   ```

4. **Create terraform.tfvars**:
   ```bash
   cp ansible01/terraform.tfvars.example proxy01/terraform.tfvars
   # Edit values
   ```

5. **Create DEPLOYMENT.md** (adapt instructions)

6. **Deploy**:
   ```bash
   cd proxy01
   terraform init
   terraform plan
   terraform apply
   ```

## 📊 Managing State

### Local State (Single User)

For personal use, Terraform state is stored locally in `.terraform/` and `terraform.tfstate`. This is fine for single-user environments.

**Backup state**:
```bash
cp ansible01/terraform.tfstate ansible01/terraform.tfstate.backup
```

### Remote State (Team Environments)

For team collaboration, use Terraform Cloud or S3 backend:

```hcl
terraform {
  backend "remote" {
    organization = "phoenix-stack"
    workspaces {
      name = "ansible01"
    }
  }
}
```

See [Terraform Cloud Documentation](https://developer.hashicorp.com/terraform/cloud-docs) for setup.

## 🧪 Testing

### Validate Syntax

```bash
cd ansible01
terraform validate
terraform fmt -check -recursive ..
```

### Plan Without Changes

```bash
terraform plan -out=tfplan
# Review tfplan carefully before applying
```

### Destroy Test Environment

```bash
terraform destroy
# Confirms container removal (VMID 101 will be deleted)
```

## 🔍 Troubleshooting

### Provider Issues

```bash
terraform init -upgrade
terraform providers lock -platform=linux_amd64 -platform=darwin_amd64
```

### State Corruption

```bash
# Back up current state
mv terraform.tfstate terraform.tfstate.corrupted

# Refresh state
terraform refresh

# Or re-import manually
terraform import proxmox_lxc.container 101
```

### Proxmox Connection Issues

```bash
# Test API connectivity
curl -k https://10.101.0.11:8006/api2/json/nodes

# Verify credentials
export TF_VAR_proxmox_api_url="https://10.101.0.11:8006/api2/json"
export TF_VAR_proxmox_user="root@pam"
export TF_VAR_proxmox_password="test"
terraform validate
```

## 📚 Resources

- [Terraform Documentation](https://www.terraform.io/docs)
- [Proxmox Provider Documentation](https://registry.terraform.io/providers/telmate/proxmox/latest)
- [Proxmox API Documentation](https://pve.proxmox.com/pve-docs/api-viewer/)

## 🤝 Next Steps

- [ ] ANSIBLE01 deployment (see [DEPLOYMENT.md](ansible01/DEPLOYMENT.md))
- [ ] PROXY01 container setup
- [ ] DNS01 container setup
- [ ] Ansible integration for post-provisioning
