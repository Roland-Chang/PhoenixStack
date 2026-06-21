# Terraform & GitHub Actions Setup - Quick Start

## Summary of Changes

I've created a complete Terraform infrastructure-as-code setup with GitHub Actions CI/CD automation and Azure Storage remote state backend. Here's what has been implemented:

### ✅ Created Files & Directories

**Root Terraform Configuration:**
- `terraform/terraform.tf` - Terraform and Azure backend configuration
- `terraform/providers.tf` - Proxmox provider configuration
- `terraform/terraform.tfvars` - Placeholder with your Proxmox API credentials
- `terraform/terraform.tfvars.example` - Documented template

**Service Module Directories:**
- `terraform/dns01/` - DNS server (PiHole)
- `terraform/proxy01/` - Reverse proxy (Traefik)
- `terraform/authentik01/` - Identity/OAuth provider
- `terraform/docker01/` - Container services platform
- `terraform/plex01/` - Plex media server

Each service directory contains:
- `main.tf` - LXC module invocation
- `variables.tf` - Input variables
- `auto.tfvars` - Configured resource specs (CPU, RAM, storage, IPs, MACs)

**CI/CD & Documentation:**
- `.github/workflows/terraform.yml` - GitHub Actions plan/apply pipeline
- `docs/terraform-state-azure-setup.md` - Complete Azure Storage backend setup guide
- Updated `.gitignore` - Enhanced protection for Terraform secrets

---

## Next Steps (DO THIS NEXT)

### Phase 1: Azure Storage Backend Setup (Required)
Complete ALL steps in [docs/terraform-state-azure-setup.md](docs/terraform-state-azure-setup.md):

1. **Create Azure Storage Account** (Steps 1.1-1.5)
   ```bash
   # ~10 minutes
   az group create --name phoenixstack-terraform --location eastus
   az storage account create --name phoenixstacktfstate ...
   az storage container create --name terraform-state ...
   ```

2. **Create Azure Service Principal** (Step 2)
   ```bash
   # Generates credentials for GitHub Actions
   az ad sp create-for-rbac --name terraform-github-phoenixstack ...
   ```

3. **Add GitHub Secrets** (Step 3)
   - 4 Azure secrets (subscription, tenant, client ID, secret)
   - 3 Proxmox secrets (API URL, token ID, token secret)
   - Repository → Settings → Secrets and variables → Actions

4. **Test Locally** (Step 4)
   ```bash
   az login
   cd terraform
   terraform init
   terraform plan -no-color
   ```

### Phase 2: Deploy First Infrastructure
Once Azure backend is configured:

1. Create a feature branch
   ```bash
   git checkout -b feature/dns01-deployment
   ```

2. Update `terraform/terraform.tfvars` with actual Proxmox token secret from 1Password:
   ```hcl
   proxmox_api_token_secret = "your_actual_secret_here"
   ```

3. Commit and push
   ```bash
   git add terraform/
   git commit -m "feat: Configure DNS01 deployment variables"
   git push origin feature/dns01-deployment
   ```

4. Create PR → Review GitHub Actions plan output → Approve → Merge to main → GitHub Actions applies changes

---

## Architecture Decision: Why GitHub Actions + Azure

| Aspect | Local | GitHub Actions + Azure |
|--------|-------|------------------------|
| **Secrets Management** | Local file (risky) | GitHub Secrets (encrypted) |
| **Audit Trail** | None | Full (commit → plan → apply) |
| **Team-Ready** | No | Yes |
| **Learning Value** | Limited | High (enterprise standard) |
| **Maintenance** | Manual | Automated on push/merge |
| **Cost** | Free | < $5/month (Azure storage) |

---

## File Structure Reference

```
terraform/
├── terraform.tf                 # Backend + terraform configuration
├── providers.tf                 # Proxmox provider setup
├── terraform.tfvars             # ⚠️ Secrets (NOT committed)
├── terraform.tfvars.example     # Template for terraform.tfvars
├── modules/
│   └── lxc/                     # Shared LXC container module
├── ansible01/
│   ├── main.tf                  # Module call
│   ├── variables.tf             # Input definitions
│   └── terraform.tfvars.example # Example values
├── dns01/
│   ├── main.tf
│   ├── variables.tf
│   └── auto.tfvars              # Auto-loaded configuration
├── proxy01/
│   ├── main.tf
│   ├── variables.tf
│   └── auto.tfvars
└── [authentik01, docker01, plex01]/
    └── (same structure)

.github/
└── workflows/
    └── terraform.yml            # GitHub Actions CI/CD pipeline

docs/
└── terraform-state-azure-setup.md   # Step-by-step Azure setup
```

---

## Security Highlights

✅ **Secrets Never Committed:**
- `terraform.tfvars` is in `.gitignore`
- Proxmox credentials stored in GitHub Secrets
- Azure credentials managed by GitHub Actions service principal

✅ **State File Security:**
- Remote state in Azure Storage (encrypted at rest)
- No local `.tfstate` files
- State locked during apply (prevents concurrent modifications)

✅ **Access Control:**
- GitHub Actions uses least-privilege service principal
- Azure RBAC restricts access to storage account only
- Audit logs track who accessed state and when

---

## Testing the Setup

### Local Test (Before GitHub)

```bash
cd terraform
terraform init
terraform validate
terraform plan -no-color
```

### GitHub Actions Test (PR)

1. Push to feature branch
2. Create PR
3. GitHub Actions automatically:
   - ✅ Validates syntax
   - ✅ Runs plan for all services
   - ✅ Comments on PR with summary

---

## Important Notes

### Terraform State File

- **DO NOT** delete `terraform/terraform.tfvars` unless you're sure
- **DO NOT** commit `terraform/terraform.tfvars` to git
- **DO** use `terraform.tfvars.example` as a template
- Azure Storage is the source of truth for state

### Resource Specifications

Each service's `auto.tfvars` is pre-configured with:
- ✅ Correct VMID (101-106)
- ✅ MAC addresses from scheme (02:aa:bb:cc:XX:01)
- ✅ Management VLAN IPs (10.101.0.20-25)
- ✅ Reasonable CPU/RAM/Storage defaults

You can adjust these values in the `auto.tfvars` files before deploying.

---

## Troubleshooting

**Error: "backend initialization failed"**
- Verify Azure resource group and storage account name match `terraform/terraform.tf`
- Ensure service principal has correct permissions

**Error: "provider not found"**
- Run `terraform init` to download providers

**Error: "authentication failed to Proxmox"**
- Verify `PROXMOX_API_TOKEN_SECRET` is correct in GitHub Secrets
- Check Proxmox API URL format (should end with `/api2/json/`)

---

## Next: Proceed to Azure Setup

**→ Follow [docs/terraform-state-azure-setup.md](docs/terraform-state-azure-setup.md) for complete step-by-step instructions.**

Once complete, reply and we can test the first infrastructure deployment!
