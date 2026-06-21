# Terraform State Management with Azure Storage
# 
# Purpose: Configure Terraform state backend in Azure Storage Account
# This document provides step-by-step instructions for setting up remote state
# management for PhoenixStack infrastructure.
#
# Security Considerations:
# - Remote state eliminates need for local .tfstate files
# - State is encrypted at rest and in transit in Azure Storage
# - Access is managed via Azure RBAC and SAS tokens
# - GitHub Actions uses service principal authentication

## Overview

PhoenixStack uses **Azure Storage Account** as the remote backend for Terraform state.

**Benefits:**
- ✅ State file never stored locally (reduces security risk)
- ✅ Supports GitHub Actions automation
- ✅ State encryption at rest (Azure Storage encryption)
- ✅ State encryption in transit (HTTPS)
- ✅ Multiple users can safely read/write state simultaneously
- ✅ Audit trail: who made changes and when (via Azure audit logs)
- ✅ Locks prevent concurrent applies (safety against race conditions)

**Architecture:**
```
Local Development
    ↓
Terraform ← → Azure Storage Account (state backend)
    ↓
Proxmox API (infrastructure changes)

GitHub Actions CI/CD
    ↓
Terraform ← → Azure Storage Account (state backend)
    ↓
Proxmox API (infrastructure changes)
```

---

## Prerequisites

1. **Azure Subscription** (you already have this)
2. **Azure CLI** installed on your workstation
   ```bash
   az --version  # Verify installation
   ```
3. **GitHub account** with admin access to your PhoenixStack repository
4. **Terraform** v1.5+ installed
   ```bash
   terraform --version
   ```

---

## Step 1: Create Azure Storage Account

### 1.1 Login to Azure

```bash
az login
# Browser opens → select your account → Close browser window
```

### 1.2 Create Resource Group

```bash
az group create \
  --name phoenixstack-terraform \
  --location eastus  # Change to your preferred region
```

### 1.3 Create Storage Account

Storage account names must be globally unique (lowercase, no special chars, 3-24 chars).

```bash
az storage account create \
  --name phoenixstacktfstate \
  --resource-group phoenixstack-terraform \
  --location eastus \
  --sku Standard_LRS \
  --kind StorageV2 \
  --https-only true \
  --access-tier Hot \
  --encryption-services blob
```

**Output:** Save the storage account ID (you'll need it for Step 3)

### 1.4 Create Container

```bash
az storage container create \
  --name terraform-state \
  --account-name phoenixstacktfstate \
  --public-access off
```

### 1.5 Enable Versioning (optional but recommended)

```bash
az storage account blob-service-properties update \
  --account-name phoenixstacktfstate \
  --enable-versioning true
```

---

## Step 2: Create Azure Service Principal for GitHub Actions

GitHub Actions will authenticate to Azure using a service principal. This principal will have **only** the permissions needed to read/write Terraform state.

### 2.1 Create Service Principal

```bash
az ad sp create-for-rbac \
  --name terraform-github-phoenixstack \
  --role Contributor \
  --scopes /subscriptions/$(az account show --query id -o tsv)
```

**Output example:**
```json
{
  "appId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "displayName": "terraform-github-phoenixstack",
  "password": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "tenant": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

### 2.2 Scope Down Permissions (More Secure)

By default, the service principal has broad permissions. Let's restrict it to only the storage account:

```bash
# Get the storage account resource ID
STORAGE_ID=$(az storage account show \
  --name phoenixstacktfstate \
  --resource-group phoenixstack-terraform \
  --query id -o tsv)

# Assign Storage Blob Data Contributor role
az role assignment create \
  --assignee terraform-github-phoenixstack \
  --role "Storage Blob Data Contributor" \
  --scope "$STORAGE_ID"
```

---

## Step 3: Add GitHub Secrets

Store the service principal credentials in GitHub Secrets so GitHub Actions can authenticate to Azure and retrieve the state file.

### 3.1 Navigate to GitHub Repository Settings

1. Go to your PhoenixStack repository
2. Settings → Secrets and variables → Actions → New repository secret

### 3.2 Add Azure Secrets

Create the following secrets with values from Step 2.1:

| Secret Name | Value |
|---|---|
| `AZURE_SUBSCRIPTION_ID` | From `az account show --query id -o tsv` |
| `AZURE_TENANT_ID` | From service principal output: `tenant` |
| `AZURE_CLIENT_ID` | From service principal output: `appId` |
| `AZURE_CLIENT_SECRET` | From service principal output: `password` |

### 3.3 Add Proxmox Secrets

Also add your Proxmox credentials (keep them secure!):

| Secret Name | Value |
|---|---|
| `PROXMOX_API_URL` | `https://10.101.0.11:8006/api2/json/` |
| `PROXMOX_API_TOKEN_ID` | `root@pam!terraform-token` |
| `PROXMOX_API_TOKEN_SECRET` | (your actual token secret from 1Password) |

---

## Step 4: Test Local Terraform with Azure Backend

### 4.1 Authenticate to Azure Locally

```bash
az login
```

### 4.2 Initialize Terraform

```bash
cd terraform
terraform init
```

Terraform will:
1. Authenticate to Azure using your credentials
2. Create the backend configuration
3. Download Proxmox provider
4. Ready to plan/apply

### 4.3 Test with Dry-Run

```bash
terraform plan -no-color > /tmp/terraform_plan.txt
```

If this succeeds, the backend is working!

---

## Step 5: Verify GitHub Actions Integration

### 5.1 Push a Test Change

```bash
git add .
git commit -m "Test: Add Terraform state backend configuration"
git push origin feature/terraform-state-backend
```

### 5.2 Create Pull Request

Go to GitHub → Create PR → Review the plan output in GitHub Actions

### 5.3 Verify Plan Output

GitHub Actions workflow should:
1. ✅ Validate syntax
2. ✅ Run terraform plan
3. ✅ Comment on PR with plan summary

---

## Troubleshooting

### Error: "storage account not found"

**Cause:** Storage account name is incorrect or doesn't exist

**Fix:**
```bash
az storage account list --query "[].name" -o table
```

### Error: "authentication failed"

**Cause:** Azure credentials not configured or expired

**Fix:**
```bash
az login --use-device-code  # Re-authenticate
```

### Error: "permission denied" in GitHub Actions

**Cause:** Service principal permissions are insufficient

**Fix:** Re-run Step 2.2 to ensure "Storage Blob Data Contributor" role is assigned

### Error: "backend initialization failed"

**Cause:** Backend configuration in `terraform/terraform.tf` doesn't match storage account name

**Fix:** Verify resource_group_name and storage_account_name in `backend "azurerm"` block match your Azure resources

---

## Cost Considerations

**Estimated Monthly Cost:**
- Storage Account: $0.50 - $2.00 (based on usage)
- Terraform state file: ~100KB = negligible cost
- **Total: < $5/month**

---

## Accessing State Remotely

### View State File (Read-Only)

```bash
terraform state list
terraform state show module.ansible01
```

### Pull State Locally (Emergency Recovery)

```bash
terraform state pull > local_state_backup.json
```

**WARNING:** This downloads the state file locally. Keep it secure and do NOT commit to git.

### Push State Remotely (Emergency Recovery)

```bash
terraform state push local_state_backup.json
```

---

## Next Steps

1. ✅ Complete steps 1-4 above
2. ✅ Test GitHub Actions workflow with a PR
3. ✅ Deploy your first infrastructure module (DNS01)
4. ✅ Verify Terraform state is stored in Azure
5. ✅ Monitor Azure Storage costs

---

## Additional Resources

- [Terraform Azure Backend Documentation](https://www.terraform.io/language/settings/backends/azurerm)
- [Azure Storage Account Security Best Practices](https://learn.microsoft.com/en-us/azure/storage/common/storage-best-practices-for-security)
- [GitHub Actions Azure Login](https://github.com/Azure/login)
