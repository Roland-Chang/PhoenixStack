# SECURITY FIX #3 & #4 REMEDIATION PLAN

**Date**: 2026-06-17  
**Status**: READY FOR EXECUTION

---

## 🎯 Security Fix #3: 1Password Token Handling

**Problem**: Token visible in process list
- Current: `export OP_SERVICE_ACCOUNT_TOKEN="..."` in shell command
- Risk: Token visible via `ps aux` or `ps -ef` during playbook execution
- Impact: Anyone on system can intercept token

**Solution**: 
- Remove shell export command
- Use token from file (already being written with proper permissions)
- Source token from file only when needed by 1Password CLI

**Files to Modify**:
- `ansible/roles/onepassword_client/tasks/main.yml` (remove shell export block)
- `ansible/roles/github_runner/tasks/main.yml` (if it also uses token)

---

## 🎯 Security Fix #4: Docker-Compose Checksum Verification

**Problem**: Downloaded without SHA256 verification
- Current: `curl ... -o docker-compose && chmod +x`
- Risk: Supply chain attack (malicious binary replacement on GitHub/CDN)
- Impact: Compromised Docker Compose could be installed

**Solution**:
- Download docker-compose binary AND checksums file
- Verify SHA256 before execution
- Fail playbook if checksum doesn't match

**Files to Modify**:
- `ansible/roles/pihole/tasks/main.yml` (download section)

---

## 📋 Execution Order

1. Fix #3: Remove 1Password token from shell export
2. Fix #4: Add Docker-compose SHA256 verification
3. Infrastructure changes: Add PLEX02, AMP01, AMP02 and reorder VMIDs/MACs

---

## ⚠️ Note on Token ID

✅ Confirmed: Token ID corrected to `root@pam!terraform-token`
