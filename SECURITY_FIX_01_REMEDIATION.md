# Critical Security Fix #1: Remove Exposed Proxmox Credentials

## 🚨 Issue Summary

The file `terraform/terraform.tfvars` contains:
- ✗ Proxmox API token secret (full infrastructure access)
- ✗ SSH public key for root access

This file has been committed to git history, making credentials visible to anyone with repo access.

## 🔧 4-Step Remediation Process

### STEP 1: Rotate the Compromised Token (MANUAL - Proxmox Console)

**In Proxmox Web UI (https://10.101.0.11:8006):**

1. Navigate to: **Datacenter → API Tokens**
2. Find: `root@pam!terraform-token`
3. Click **Delete** (or just disable it)
4. Create **new token**:
   - Click **Create Token**
   - User: `root@pam`
   - Token ID: `terraform-token-v2` (new naming)
   - Enable: "Privilege Separation" (if available)
   - Click **Generate**
5. **COPY the token secret** (appears once, then hidden!)

**Status**: ⏳ Waiting for you to complete this in Proxmox UI

---

### STEP 2: Remove Credentials from Git History

Once you've rotated the token in Proxmox, we'll clean the git history.

**Command:**
```bash
bash REMOVE_CREDENTIALS_FROM_GIT.sh
```

**What it does:**
- Creates backup of `.git` directory (safe fallback)
- Removes `terraform/terraform.tfvars` from ALL commits
- Cleans git history and garbage collects
- Removes old git references

**After this step:**
- Credentials are gone from git history
- Everyone needs to re-clone the repo
- Will need to force-push to GitHub

---

### STEP 3: Switch to Environment Variables

#### For Local Development:

**Create `terraform/terraform.tfvars` locally (NOT committed):**
```bash
# DO NOT COMMIT THIS FILE - it's in .gitignore

cat > terraform/terraform.tfvars << 'EOF'
proxmox_api_url         = "https://10.101.0.11:8006/api2/json/"
proxmox_api_token_id    = "root@pam!terraform-token-v2"
proxmox_api_token_secret = "YOUR_NEW_TOKEN_SECRET_FROM_PROXMOX"
ssh_public_keys          = "ssh-ed25519 AAAA... your-comment"
EOF
```

**Or use environment variables:**
```bash
export TF_VAR_proxmox_api_token_secret="your_new_token_secret"
export TF_VAR_ssh_public_keys="ssh-ed25519 AAAA... your-comment"

# Now terraform will use env vars
terraform plan
```

#### For GitHub Actions CI/CD:

1. Go to **GitHub Repository Settings → Secrets and variables → Actions**
2. Add new secrets:
   - **PROXMOX_API_URL**: `https://10.101.0.11:8006/api2/json/`
   - **PROXMOX_API_TOKEN_ID**: `root@pam!terraform-token-v2`
   - **PROXMOX_API_TOKEN_SECRET**: `<new token from Proxmox>`
   - **SSH_PUBLIC_KEY**: `ssh-ed25519 AAAA... your-comment`

3. Update `.github/workflows/*.yml` to use secrets:
```yaml
jobs:
  terraform:
    runs-on: self-hosted
    env:
      TF_VAR_proxmox_api_url: ${{ secrets.PROXMOX_API_URL }}
      TF_VAR_proxmox_api_token_id: ${{ secrets.PROXMOX_API_TOKEN_ID }}
      TF_VAR_proxmox_api_token_secret: ${{ secrets.PROXMOX_API_TOKEN_SECRET }}
      TF_VAR_ssh_public_keys: ${{ secrets.SSH_PUBLIC_KEY }}
    steps:
      - uses: actions/checkout@v3
      - run: terraform plan
```

---

### STEP 4: Document & Verify

#### Update terraform/README.md:

Add this section to `terraform/README.md`:

```markdown
## Credentials Management

### Local Development

Create `terraform/terraform.tfvars` (NOT committed):

```hcl
proxmox_api_url          = "https://10.101.0.11:8006/api2/json/"
proxmox_api_token_id     = "root@pam!terraform-token-v2"
proxmox_api_token_secret = "TOKEN_SECRET_FROM_1PASSWORD"
ssh_public_keys          = "YOUR_SSH_PUBLIC_KEY"
```

**IMPORTANT**: This file is in `.gitignore` and should NEVER be committed.

### GitHub Actions / CI/CD

Credentials are injected as GitHub Secrets. See `.github/workflows/` for usage.

To update credentials:
1. Generate new API token in Proxmox
2. Update GitHub Secrets
3. Verify in GitHub Actions run logs (don't print credentials!)

### Rotating Credentials

1. **In Proxmox**: Datacenter → API Tokens → Create new token
2. **Update local tfvars**: Edit `terraform/terraform.tfvars`
3. **Update GitHub**: GitHub Settings → Secrets → Update values
4. **Commit tfvars template**: (The .example file, not the actual file)
```

#### Verification Checklist:

```bash
# Verify file is NOT in git history
git log --all --full-history -- terraform/terraform.tfvars
# (Should return: empty)

# Verify current terraform.tfvars exists locally
ls -la terraform/terraform.tfvars
# (Should show local file)

# Verify file is in .gitignore
grep "terraform.tfvars" .gitignore
# (Should show match)

# Verify terraform can load vars
cd terraform
terraform validate
# (Should complete without errors)

# Verify no credentials in git staged changes
git diff --staged terraform/
# (Should NOT show any secrets)
```

---

## 📋 Execution Checklist

- [ ] Step 1: Rotated token in Proxmox → New token secret: _______________
- [ ] Step 2: Ran `bash REMOVE_CREDENTIALS_FROM_GIT.sh`
- [ ] Step 3: Created local `terraform/terraform.tfvars` (NOT committed)
- [ ] Step 3: Added GitHub Secrets (if using CI/CD)
- [ ] Step 4: Updated `terraform/README.md` with credentials section
- [ ] Verification: Ran all verification commands above
- [ ] Verification: `git push origin --force --all` (if rewriting history)
- [ ] Communication: Notified team to re-clone repository

---

## 🚨 Summary of Changes

| Component | Before | After |
|-----------|--------|-------|
| Proxmox Token | `d3607927-1f5d-474a-8f33-80b65c05f8fa` (exposed) | New token in Proxmox only |
| terraform.tfvars | Committed to git (visible to all) | Local only, not committed |
| Credentials in Git | ✗ Exposed in history | ✓ Completely removed |
| CI/CD Credentials | (None) | ✓ GitHub Secrets |
| SSH Key | Hardcoded in git | Environment variable |

---

## ⚠️ Important Notes

1. **After removing from git history:**
   - `git push --force --all` will rewrite GitHub history
   - All team members must re-clone the repository
   - Existing branches/PRs may need rebasing

2. **The new token is temporary:**
   - Save it to 1Password immediately
   - Don't leave it in terminal history
   - Rotate periodically (quarterly recommended)

3. **Verify nothing is committed:**
   - Always check `git diff --staged` before committing
   - No more sensitive data in repo

---

## 🎯 Next Steps

1. **Complete Step 1**: Rotate token in Proxmox and provide new secret
2. **Run this in order**:
   ```bash
   bash REMOVE_CREDENTIALS_FROM_GIT.sh
   ```
3. **Update terraform/terraform.tfvars** locally
4. **Test terraform**:
   ```bash
   cd terraform
   terraform plan
   ```
5. **Verify git is clean**:
   ```bash
   git log --all --full-history -- terraform/terraform.tfvars
   ```
6. **Force push if rewriting history**:
   ```bash
   git push origin --force --all
   ```

---

This remediation completely removes the exposed credentials from your codebase and implements secure credential management going forward.
