# Proxmox API Token Creation Guide

**Purpose**: Create API credentials for Terraform to authenticate with Proxmox VE  
**Security Level**: High (tokens > passwords)  
**Scope**: Proxmox authentication only  

---

## Overview

Proxmox VE supports two authentication methods:
- **API Tokens** (recommended) — Time-limited, revocable, scope-limited
- **Passwords** (not recommended for automation)

This guide creates an **API Token**, which is more secure for Terraform deployments.

---

## Prerequisites

- Admin access to Proxmox VE Web UI
- Proxmox VE 6.2+ (your PVE01 is running 9.2.0 ✓)
- Access to PVE01 at: `https://10.101.0.11:8006`

---

## Step 1: Log into Proxmox Web UI

1. Open browser: `https://10.101.0.11:8006`
2. Log in with **root** user and password
3. Click on your username in the top-right corner

---

## Step 2: Navigate to API Tokens

1. In the left sidebar, expand **Datacenter**
2. Click **Permissions** → **API Tokens**
3. You should see an empty list (no tokens yet)

---

## Step 3: Create New API Token

1. Click **Add** button (top-right of API Tokens panel)
2. Fill in the form:

   | Field | Value | Notes |
   |-------|-------|-------|
   | **User** | `root@pam` | Use root user (can be restricted later) |
   | **Token ID** | `terraform-token` | Friendly identifier (required) |
   | **Expiration** | *(blank)* or pick date | Leave blank for indefinite; set date for auto-revocation |
   | **Privileges Separation** | ☑️ Checked | Restricts token to only its assigned role |

3. Click **Add**

---

## Step 4: Copy Token Secret (CRITICAL)

⚠️ **Important**: The token secret displays **only once**. Copy it immediately!

After clicking **Add**, you'll see:
```
Token ID:  root@pam!terraform-token
Secret:    a1b2c3d4-e5f6-g7h8-i9j0-k1l2m3n4 (example)
```

**Save both values securely** (password manager or temp file).

---

## Step 5: Assign Minimal Permissions (Security Best Practice)

### Option A: Restrict to VM/Container Management (Recommended)

1. Go to **Permissions** → **API Tokens**
2. Select your new token: `root@pam!terraform-token`
3. Click **Edit** (or right-click → edit)
4. Assign role **`PVEVMAdmin`** (allows full container/VM management)
   - Or **`PVEDatastoreAdmin`** if you need storage control
   - Or **`Administrator`** (full access, only if needed)

### Option B: Create Custom Role (Advanced)

For maximum security, create a role limited to:
- Create/delete/modify LXC containers
- Access specific storage pools
- View host information

---

## Step 5.1: Add Sys.Audit Privilege (If Needed)

If you encounter "Permission denied" errors related to audit logs or system information, you need to assign a role with Sys.Audit privilege to your token:

### Method 1: Assign Role via Web UI (Recommended)

1. Go to **Datacenter** → **Permissions**
2. Click the **Add API Token Permission** button (top-right)
3. Fill in the form:
   - **API Token**: Select `root@pam!terraform-token`
   - **Path**: `/` (root - gives access to entire system)
   - **Role**: Select `Administrator` (has Sys.Audit) or your custom role
4. Click **Add**

### Method 2: Create Custom Role with Sys.Audit (Minimal Privileges)

If you want to restrict to only what Terraform needs:

1. Go to **Datacenter** → **Permissions** → **Roles** (in left sidebar)
2. Click **Create** button
3. Name: `TerraformRole` (or similar)
4. Add these privileges (check each one):
   - ☑️ `Sys.Audit` — Required for Terraform provider
   - ☑️ `VM.Allocate` — Create containers
   - ☑️ `VM.Audit` — View containers
   - ☑️ `VM.Clone` — Clone containers
   - ☑️ `VM.Configure` — Modify containers
   - ☑️ `VM.Console` — Access console
   - ☑️ `VM.PowerMgmt` — Power on/off
   - ☑️ `VM.Monitor` — Monitor resources
   - ☑️ `Datastore.Allocate` — Create storage
   - ☑️ `Datastore.AllocateSpace` — Use storage space
5. Click **Create**
6. Then follow Method 1 above, but select `TerraformRole` instead of `Administrator`

### Method 3: Verify via CLI (Optional)

SSH into Proxmox and verify the role/privileges:

```bash
# List all permissions
pveum acl list

# Show specific role privileges
pveum role show Administrator
```

### When You Need Sys.Audit

- Terraform needs to query system/audit information
- Proxmox provider (v3.0.x) queries audit logs during deployment
- Error message: `"Permission denied"` when accessing `/api2/json/audit`

---

## Step 6: Obtain Authentication Credentials

You now have two pieces of information:

```
Proxmox API URL:    https://10.101.0.11:8006/api2/json
API Token ID:       root@pam!terraform-token
API Token Secret:   a1b2c3d4-e5f6-g7h8-i9j0-k1l2m3n4
```

---

## Step 7: Configure Terraform (Recommended Approach)

Use `terraform.tfvars` to store credentials (easier than environment variables):

**Create `terraform/ansible01/terraform.tfvars`:**

```hcl
# Do NOT commit this file - it's in .gitignore for security
proxmox_api_url          = "https://10.101.0.11:8006/api2/json"
proxmox_api_token_id     = "root@pam!terraform-token"
proxmox_api_token_secret = "a1b2c3d4-e5f6-g7h8-i9j0-k1l2m3n4"
```

**Update `terraform/ansible01/providers.tf`:**

```hcl
provider "proxmox" {
  pm_api_url            = var.proxmox_api_url
  pm_api_token_id       = var.proxmox_api_token_id
  pm_api_token_secret   = var.proxmox_api_token_secret
  pm_tls_insecure       = var.proxmox_tls_insecure
}
```

**Update `terraform/ansible01/variables.tf`:**

```hcl
variable "proxmox_api_token_id" {
  description = "Proxmox API token ID (format: user@realm!token-name)"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}
```

⚠️ **IMPORTANT**: Do NOT use `pm_user` and `pm_password` with API tokens. The telmate/proxmox provider requires the split token format:
- `pm_api_token_id` = `root@pam!terraform-token` (the full token identifier)
- `pm_api_token_secret` = the token secret only

### Alternative: Environment Variables (Linux/Bash)

If you prefer environment variables, set them before running Terraform:

```bash
export TF_VAR_proxmox_api_url="https://10.101.0.11:8006/api2/json"
export TF_VAR_proxmox_api_token_id="root@pam!terraform-token"
export TF_VAR_proxmox_api_token_secret="a1b2c3d4-e5f6-g7h8-i9j0-k1l2m3n4"

terraform plan
```

Or in PowerShell (Windows):

```powershell
$env:TF_VAR_proxmox_api_url = "https://10.101.0.11:8006/api2/json"
$env:TF_VAR_proxmox_api_token_id = "root@pam!terraform-token"
$env:TF_VAR_proxmox_api_token_secret = "a1b2c3d4-e5f6-g7h8-i9j0-k1l2m3n4"

terraform plan
```

---

Test the token with a simple API call:

**Bash (Linux/Mac):**
```bash
curl -k -X GET "https://10.101.0.11:8006/api2/json/version" \
  -H 'Authorization: PVEAPIToken=root@pam!terraform-token=a1b2c3d4-e5f6-g7h8-i9j0-k1l2m3n4'
```

**Expected output:**
```json
{"data":{"version":"9.2.3","release":"9.2","repoid":"d0fde103346cf89a"}}
```

**PowerShell (Windows):**
```powershell
$headers = @{
    "Authorization" = "PVEAPIToken=root@pam!terraform-token=a1b2c3d4-e5f6-g7h8-i9j0-k1l2m3n4"
}

$response = Invoke-RestMethod `
    -Uri "https://10.101.0.11:8006/api2/json/version" `
    -Headers $headers `
    -SkipCertificateCheck

$response
```

**Note**: The Authorization header format is: `PVEAPIToken=USER@REALM!TOKEN_NAME=SECRET`

---

## Step 9: Revoke Token (If Needed)

If token is compromised or no longer needed:

1. Go to **Permissions** → **API Tokens**
2. Select token and click **Remove**
3. Token is immediately invalidated

---

## Security Checklist

- ✅ Token uses least-privilege role (not Administrator)
- ✅ Token has expiration date (optional but recommended)
- ✅ Token secret is NOT stored in git or code
- ✅ Token is revoked if compromised
- ✅ Audit log shows token creation/usage

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Invalid authentication" in Terraform | Verify token ID and secret exact match |
| "Permission denied" | Check token role has VM/Container permissions |
| TLS certificate error | Set `pm_tls_insecure = true` in provider (dev only) |
| Token expires | Create new token or extend expiration date |

---

## References

- [Proxmox VE API Documentation](https://pve.proxmox.com/wiki/Proxmox_VE_API)
- [Proxmox API Token Guide](https://pve.proxmox.com/wiki/User_Management#_api_tokens)
- [Terraform Proxmox Provider](https://github.com/Telmate/terraform-provider-proxmox)
