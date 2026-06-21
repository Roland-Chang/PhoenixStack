# SECURITY FIX #2 REMEDIATION PLAN
# Hardcoded SSH Public Key in terraform.tfvars

**Date**: 2026-06-17  
**Issue**: SSH Public Key hardcoded in version-controlled files  
**Status**: READY FOR EXECUTION

---

## 🎯 Problem Statement

**Current State:**
- SSH public key is hardcoded in `terraform/terraform.tfvars`
- Key is hardcoded in `terraform/terraform.tfvars.example` 
- Visible to anyone with repository access
- Part of git commit history (28 commits)

**Risk:**
- SSH key compromise exposes container root access
- Key valid until manually rotated
- Multiple containers potentially compromised if key is leaked
- No audit trail of key access

---

## ✅ Remediation Steps (4-Step Process)

### Step 1: Remove SSH Key from Files
- Remove hardcoded SSH key from `terraform.tfvars`
- Remove hardcoded SSH key from `terraform.tfvars.example`
- Replace with placeholder: `"SSH_KEY_FROM_ENV_VAR"`
- File will rely on `TF_VAR_ssh_public_keys` environment variable

### Step 2: Remove from Git History
- Use `git filter-branch` to remove SSH key from all commits
- Clean git references (reflog, gc)
- Verify with `git log --all --full-history -- terraform/terraform.tfvars*`

### Step 3: Update Documentation
- Update `terraform/README.md` with SSH key environment variable section
- Document how to set SSH key locally and in CI/CD
- Add examples for Bash, PowerShell, and GitHub Actions

### Step 4: Verify and Test
- Verify SSH key not in git history
- Verify terraform validates without SSH key hardcoded
- Verify terraform can use environment variable
- Confirm files staged in git are clean

---

## 📋 Execution Checklist

- [ ] Step 1: Remove SSH key from terraform.tfvars
- [ ] Step 2: Remove SSH key from terraform.tfvars.example
- [ ] Step 3: Remove from git history using git-filter-branch
- [ ] Step 4: Update terraform/README.md documentation
- [ ] Verification: git log returns empty for SSH key
- [ ] Verification: terraform validate succeeds
- [ ] Backup git history in /tmp/

---

## 🔐 Security Impact

**Before Fix:**
- SSH key visible in git history
- Hardcoded in version control
- Accessible to anyone with repo access
- No separation between code and credentials

**After Fix:**
- SSH key stored in environment variable only
- Credentials never committed to git
- Local development uses local env vars
- CI/CD uses GitHub Secrets
- Clear separation of code and credentials

---

## 📁 Files to Modify

| File | Action | Impact |
|------|--------|--------|
| `terraform/terraform.tfvars` | Remove hardcoded key | ✓ Fix applied |
| `terraform/terraform.tfvars.example` | Remove example SSH key | ✓ Documentation updated |
| `terraform/README.md` | Add env var documentation | ✓ Best practices documented |
| `.git/` history | Remove from 28 commits | ✓ History cleaned |

---

## 🔄 Environment Variable Usage

**Local Development (Bash/Linux):**
```bash
export TF_VAR_ssh_public_keys="ssh-ed25519 AAAA..."
terraform plan
```

**Local Development (PowerShell):**
```powershell
$env:TF_VAR_ssh_public_keys = "ssh-ed25519 AAAA..."
terraform plan
```

**GitHub Actions:**
```yaml
- name: Terraform Plan
  env:
    TF_VAR_ssh_public_keys: ${{ secrets.SSH_PUBLIC_KEY }}
  run: terraform plan
```

---

## ⚠️ Important Notes

1. After removing from git history, team members must re-clone
2. Force-push will be required to update GitHub
3. SSH key should be stored in 1Password for safe access
4. Multiple developers may have different SSH keys (create per-user .tfvars)

---

**READY TO EXECUTE**
