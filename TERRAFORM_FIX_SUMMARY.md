# Terraform Configuration Fixes - Summary

## Problems Identified and Resolved

### 1. ✅ VMID Conflicts (FIXED)

**Issue:** Multiple containers were assigned the same VM ID numbers, causing deployment failures.

**Conflicts Found:**
| Conflict | Modules | Issue |
|----------|---------|-------|
| VMID 102 | BASTION02, DNS01 | Duplicate VMID |
| VMID 103 | DNS02, PROXY01 (original) | Conflicts with renumbering |
| VMID 104 | AUTHENTIK01 | Conflicts with DNS02 |
| VMID 105 | PROXY01, DOCKER01 (original) | Duplicate VMID |
| VMID 106 | PROXY02, PLEX01 (original) | Duplicate VMID |

**Resolution:** Updated all module `variables.tf` files to implement the correct VMID schema:

```
101 → BASTION01 ✓ (was already correct)
102 → BASTION02 ✓ (changed from 100)
103 → DNS01 ✓ (changed from 102)
104 → DNS02 ✓ (changed from 103)
105 → PROXY01 ✓ (changed from 103)
106 → PROXY02 ✓ (was already correct)
107 → AUTHENTIK01 ✓ (changed from 104)
108 → AUTHENTIK02 ✓ (was already correct)
110 → PLEX01 ✓ (changed from 106)
111 → DOCKER01 ✓ (changed from 105)
```

**Files Updated:**
- `terraform/bastion02/variables.tf` - VMID 100 → 102
- `terraform/dns01/variables.tf` - VMID 102 → 103
- `terraform/dns02/variables.tf` - VMID 103 → 104
- `terraform/proxy01/variables.tf` - VMID 103 → 105
- `terraform/authentik01/variables.tf` - VMID 104 → 107
- `terraform/plex01/variables.tf` - VMID 106 → 110
- `terraform/docker01/variables.tf` - VMID 105 → 111

---

### 2. ✅ Storage Pool Configuration (FIXED)

**Issue:** Several modules referenced a non-existent storage pool `local-lvm`, causing deployment failures with error: "storage 'local-lvm' does not exist"

**Affected Modules:**
- `authentik01/variables.tf` - storage_pool: local-lvm
- `authentik02/variables.tf` - storage_pool: local-lvm
- `docker01/variables.tf` - storage_pool: local-lvm
- `plex01/variables.tf` - storage_pool: local-lvm
- `proxy01/variables.tf` - storage_pool: local-lvm
- `proxy02/variables.tf` - storage_pool: local-lvm

**Resolution:** Changed all `local-lvm` references to `local` (the standard Proxmox local storage pool).

**Current Storage Pool Configuration:**
```
BASTION01: ssd
BASTION02: ssd
DNS01: ssd
DNS02: ssd
PROXY01: local
PROXY02: local
AUTHENTIK01: local
AUTHENTIK02: local
PLEX01: ssd
DOCKER01: local
```

---

### 3. ✅ Documentation and Prerequisites (ADDED)

Created comprehensive documentation to prevent these issues in the future:

**New Files:**
- `terraform/README_STORAGE_POOLS.md` - Complete storage pool configuration guide
  - How to check available storage pools
  - How to create new storage pools (Directory, LVM, ZFS)
  - Storage pool requirements by container
  - Troubleshooting guide

**Updated Files:**
- `terraform/terraform.tfvars.example` - Added comprehensive sections for:
  - Storage pool prerequisites and requirements
  - VM ID allocation schema with full documentation
  - Deployment verification steps
  - Common issues and troubleshooting
  
- `terraform/README.md` - Added new "Prerequisites" section:
  - Storage pools verification steps
  - API token requirements
  - Network bridge requirements
  - LXC template requirements
  - SSH public key requirements

---

## Current Terraform State

### Terraform Plan Results
```
Plan: 7 to add, 0 to change, 3 to destroy
```

**What will happen:**
- 3 containers will be destroyed (bastion02, dns01, dns02) - This is necessary because their VMID changed
- 7 containers will be created with correct VMID values
- Other containers (authentik01, authentik02, proxy01, proxy02) will be created fresh on first apply

### Verification

All VMID allocations verified:
```bash
✓ No duplicate VM IDs
✓ All 10 containers assigned unique IDs (101-108, 110-111)
✓ Storage pool references updated to valid pools
✓ Terraform plan completes without errors
```

---

## Next Steps

### Option A: Deploy All Containers Fresh
```bash
cd terraform
terraform apply tfplan  # Uses the saved plan with all fixes
```

This will:
1. Destroy the 3 containers with old VMID values (bastion02, dns01, dns02)
2. Create all 10 containers with correct VMIDs and storage pools
3. Install SSH keys on all containers
4. Take approximately 5-10 minutes

### Option B: Manual Cleanup (Recommended if wanting fresh start)
```bash
# Destroy all and start fresh
terraform destroy -auto-approve

# Then apply with all fixes
terraform apply -auto-approve
```

---

## Verification After Deployment

Run these checks after `terraform apply` completes:

### 1. Verify all containers are running in Proxmox Web UI
Navigate to: Node (pve01) → LXC Containers
- Check all 10 containers have Status: **running**
- Verify VMID assignment matches schema above

### 2. Verify IP addresses
```bash
for ip in 10.101.0.{20,21,22,23,25,30,201,202}; do
  echo -n "$ip: "
  ping -c 1 -W 1 $ip >/dev/null 2>&1 && echo "OK" || echo "UNREACHABLE"
done
```

Expected:
```
10.101.0.20: OK    (BASTION01)
10.101.0.21: OK    (BASTION02)
10.101.0.22: OK    (PROXY01)
10.101.0.23: OK    (AUTHENTIK01)
10.101.0.25: OK    (AUTHENTIK02)
10.101.0.30: OK    (PROXY02)
10.101.0.201: OK   (DNS01)
10.101.0.202: OK   (DNS02)
```

### 3. Test SSH Access
```bash
ssh -i ~/.ssh/id_ed25519 root@10.101.0.20  # BASTION01
ssh -i ~/.ssh/id_ed25519 root@10.101.0.201 # DNS01
```

Should connect without password using 1Password SSH agent.

### 4. Verify Storage Allocation
In Proxmox Web UI, check Node → Disks:
- Verify `local` and `ssd` storage pools exist
- Confirm containers are using designated pools

---

## Root Cause Analysis

### Why These Issues Occurred

1. **VMID Conflicts:**
   - Module defaults were not coordinated during initial creation
   - VM IDs were not validated for uniqueness
   - Renumbering schema (101-108, 110-111) was planned but not fully implemented

2. **Storage Pool Issues:**
   - `local-lvm` was used as a generic pool name but doesn't exist in Proxmox by default
   - Proxmox storage pool names must exactly match configured pools
   - No validation or documentation required storage pool pre-existence

### Prevention for Future Changes

1. **Terraform Validation:**
   - New modules must follow established VMID allocation schema
   - Storage pool names must be validated against available Proxmox pools
   - Use terraform plan as gate-keeper before creating configurations

2. **Documentation:**
   - Proxmox prerequisites now documented in terraform/README.md
   - Storage pool requirements in terraform/README_STORAGE_POOLS.md
   - terraform.tfvars.example now includes complete troubleshooting guide

3. **Configuration Review:**
   - All modules reviewed for VMID and storage pool consistency
   - No hardcoded references to non-existent resources

---

## Files Changed

**Modified:**
- terraform/bastion02/variables.tf
- terraform/dns01/variables.tf
- terraform/dns02/variables.tf
- terraform/proxy01/variables.tf
- terraform/authentik01/variables.tf
- terraform/plex01/variables.tf
- terraform/docker01/variables.tf
- terraform/authentik01/variables.tf
- terraform/authentik02/variables.tf
- terraform/proxy01/variables.tf
- terraform/proxy02/variables.tf
- terraform/docker01/variables.tf
- terraform/README.md
- terraform/terraform.tfvars.example

**Created:**
- terraform/README_STORAGE_POOLS.md
- terraform/TERRAFORM_FIX_SUMMARY.md (this file)

---

## Rollback Plan

If deployment fails or needs to be reverted:

```bash
# Destroy infrastructure
terraform destroy -auto-approve

# Check state
terraform show

# Review any failures
terraform plan
```

The git history preserves all changes, so previous configurations can be reviewed if needed.
