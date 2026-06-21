# Known Issues & Troubleshooting

**Last Updated**: June 5, 2026  
**Scope**: PhoenixStack Infrastructure  
**Maintainer**: Infrastructure Team

---

## Overview

This document catalogs known issues, expected warnings, and workarounds discovered during PhoenixStack deployment and operations. Items are categorized by severity and actionability.

---

## Proxmox API & Terraform Issues

### Issue: Terraform Provider Authentication Requires Correct Token Method

**Severity**: 🔴 High (Blocks Terraform operations)  
**Affected Component**: Terraform Proxmox provider (telmate/proxmox v3.0.x) with API tokens  
**First Observed**: June 5, 2026  
**Status**: ✅ RESOLVED

#### Symptom
```
Error: 401 authentication failure
  with provider["registry.terraform.io/telmate/proxmox"],
  on providers.tf line 3, in provider "proxmox":
   3: provider "proxmox" {
```

#### Root Cause
The telmate/proxmox provider requires API token authentication to use **separate `pm_api_token_id` and `pm_api_token_secret` parameters**, not the combined `pm_user` and `pm_password` fields. Using `pm_user="root@pam!terraform-token"` and `pm_password="secret"` fails authentication because the provider expects the token to be split into its components.

#### Impact
- 🔴 **Blocks** `terraform plan` and `terraform apply` commands
- 401 authentication failures even when credentials are correct
- No way to proceed with infrastructure as code until resolved

#### Resolution
**Status**: ✅ FIXED  

Update [providers.tf](providers.tf) to use correct API token authentication:

**Before (WRONG)**:
```hcl
provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_user         = var.proxmox_user              # ❌ Incorrect for API tokens
  pm_password     = var.proxmox_password          # ❌ Incorrect for API tokens
  pm_tls_insecure = var.proxmox_tls_insecure
}
```

**After (CORRECT)**:
```hcl
provider "proxmox" {
  pm_api_url            = var.proxmox_api_url
  pm_api_token_id       = var.proxmox_api_token_id       # ✅ Format: root@pam!terraform-token
  pm_api_token_secret   = var.proxmox_api_token_secret   # ✅ The token secret
  pm_tls_insecure       = var.proxmox_tls_insecure
}
```

Update [variables.tf](variables.tf):
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

Update [terraform.tfvars](terraform.tfvars):
```hcl
proxmox_api_url          = "https://10.101.0.11:8006/api2/json"
proxmox_api_token_id     = "root@pam!terraform-token"
proxmox_api_token_secret = "d5cfc85d-5f72-41c6-ac2c-670bbb6c1839"
```

**Why This Works**:
- The telmate/proxmox provider splits token handling from password auth
- `pm_api_token_id` expects the full token identifier: `USER@REALM!TOKEN_NAME`
- `pm_api_token_secret` expects only the secret portion
- This allows the provider to construct the correct `Authorization: PVEAPIToken=...` header

#### Testing
Verify the fix works:
```bash
terraform plan
# Should succeed with "No changes" or show resource changes
```

---

### Issue: Terraform Provider Requires Sys.Audit Privilege

**Severity**: 🟡 Medium (May block Terraform operations)  
**Affected Component**: Terraform Proxmox provider (telmate/proxmox v3.0.x) with API tokens  
**First Observed**: June 5, 2026  
**Status**: ✅ RESOLVED (with role assignment)

#### Symptom
```
Error: Permission denied
  on terraform/ansible01/main.tf line XX, in module "ansible01":
  module.ansible01: error querying /api2/json/audit
```

Or during `terraform destroy`:
```
Error: Permission denied when deleting container
```

#### Root Cause
The Terraform Proxmox provider (v3.0.2-rc04+) attempts to query audit logs and system information during container lifecycle operations. The default `PVEVMAdmin` role does not include the **Sys.Audit** privilege, causing permission denied errors.

#### Impact
- 🔴 **Blocks** `terraform apply` and `terraform destroy` commands
- Container may be deployed but Terraform cannot verify or destroy it
- Partial state files remain (require manual cleanup)

#### Resolution
**Status**: ✅ FIXED  
**Workaround**: Assign a role with `Sys.Audit` privilege to your API token

1. Log into Proxmox Web UI: `https://10.101.0.11:8006`
2. Go to **Datacenter** → **Permissions**
3. Click the **Add API Token Permission** button (top-right)
4. Fill in the form:
   - **API Token**: `root@pam!terraform-token`
   - **Path**: `/` (root)
   - **Role**: `Administrator` (quickest fix) or custom `TerraformRole` with Sys.Audit
5. Click **Add**

Verify via CLI (SSH to Proxmox):
```bash
pveum acl list
# Should show your token with Administrator (or custom role) role
```

**Why This Works**: 
- Roles contain privilege definitions including Sys.Audit
- Terraform provider uses audit queries to verify container state
- Without Sys.Audit in the role, provider cannot confirm operations completed successfully

**Best Practice**:
- For production, create a custom role with minimal privileges
- For development/testing, you can use `Administrator` role temporarily
- Never commit credentials or role assignments to git

#### References
- [Proxmox-API-Token-Creation.md](proxmox-api-token-creation.md#step-51-add-sysaudit-privilege-if-needed) — Detailed instructions
- [Terraform Proxmox Provider Issues](https://github.com/Telmate/terraform-provider-proxmox/issues)

---

## Proxmox VE 7.x Issues

### Bridge hash_elasticity Deprecation Warning

**Severity**: ⚠️ Low (Informational only)  
**Affected Components**: vmbr0, vmbr1  
**First Observed**: PVE01 bootstrap deployment, June 2, 2026

#### Symptom
```
vmbr0: the hash_elasticity option has been deprecated and is always 16
vmbr1: the hash_elasticity option has been deprecated and is always 16
```

#### Root Cause
Proxmox VE 7.x kernel hardcodes `hash_elasticity=16` for all bridge instances. This parameter was historically configurable but is now deprecated in favor of kernel defaults. Proxmox still logs this as an informational warning for backward compatibility.

#### Impact
- ✅ **None** - Bridges function normally with the hardcoded value
- The warning is purely informational and does not affect network performance or stability
- Cannot be suppressed or configured

#### Resolution
**Action Required**: None  
**Workaround**: This is expected behavior in Proxmox 7.x and later. No configuration change needed.

#### References
- [Proxmox VE 7.0 Release Notes](https://pve.proxmox.com/wiki/Category:PVE_7)
- Linux kernel bridge documentation (deprecated parameter)

---

## Bootstrap Script Issues

### Issue: Firewall Configuration Generation Bug

**Severity**: � Medium (Fixed)  
**Affected Component**: `proxmox-bootstrap.sh` - firewall rule generation  
**First Observed**: PVE01 bootstrap, June 2, 2026  
**Status**: ✅ FIXED in bootstrap script

#### Symptom
```
/etc/pve/firewall/cluster.fw (line X): can't parse option 'log_level_in: info'
/etc/pve/firewall/cluster.fw (line Y): can't parse option 'log_level_out: info'
/etc/pve/firewall/cluster.fw (line Z): unable to parse rule parameters: -m conntrack --ctstate ESTABLISHED,RELATED
```

#### Root Cause
The bootstrap script's firewall generation section included:
1. Invalid directives: `log_level_in` and `log_level_out` are not valid in `/etc/pve/firewall/cluster.fw`
2. Invalid rule syntax: `-log nolog` with incorrect hyphen placement
3. Invalid conntrack rule: Modern Proxmox 7.x firewall syntax doesn't support this pattern

#### Impact
- ⚠️ **Medium** - Firewall functions but logs syntax errors
- No security impact; default policy is ACCEPT

#### Resolution
**Status**: ✅ FIXED  
**Fix Applied in Bootstrap Script**: 
- Removed invalid directives
- Corrected rule syntax to Proxmox 7.x compatible format
- Removed conntrack rule (not necessary with default ACCEPT policy)

**Changes Made**:
- Line ~1115: Removed `-log nolog` from all rule definitions
- Lines ~1128-1129: Removed `log_level_in` and `log_level_out` directives
- Line ~1141: Removed problematic conntrack rule

#### Future Deployments
PVE02, PVE03, and future nodes will no longer see these firewall syntax errors.

---

### Issue: Network Configuration Doesn't Account for Native vs Tagged VLANs

**Severity**: � Medium (Fixed)  
**Affected Component**: `proxmox-bootstrap.sh` - network interfaces generation  
**First Observed**: PVE01 VLAN 10 configuration attempt, June 2, 2026  
**Status**: ✅ FIXED in bootstrap script

#### Symptom
- Network connectivity lost after initial bootstrap with VLAN configuration
- ARP entries show as `<incomplete>` for gateway
- Cannot ping gateway despite VLAN interface being UP
- SSH times out, Web UI unreachable

#### Root Cause
The bootstrap script attempted to create VLAN-aware bridge with `bridge-pvid` (tagged VLAN) when the Unifi switch port had VLAN 10 configured as **Native (untagged)**. Incompatibility between:
- **Bootstrap config**: Used `bridge-vlan-aware yes` and `bridge-pvid 10` (expects tagged traffic)
- **Switch config**: Sends untagged traffic on native VLAN 10

Result: Layer 2 frames don't match VLAN expectations, ARP fails.

#### Impact
- 🔴 **Critical** - Complete network outage
- Management and SSH access lost
- Requires iDRAC/console access to recover

#### Resolution
**Status**: ✅ FIXED  
**Fix Applied in Bootstrap Script**:
- Removed `bridge-vlan-aware yes` configuration
- Removed `bridge-vids 2-4094` configuration
- Removed `bridge-pvid $MGMT_VLAN` configuration
- Simplified vmbr0 to use plain untagged bridge: `bridge-ports $PRIMARY_IFACE`
- Added documentation for optional workload bridge (vmbr1) on separate VLAN

**Key Change**: Management VLAN is now assumed to be **Native (untagged)** on the switch port, which matches real-world deployment scenarios.

**Corrected Configuration Logic**:
```bash
# Management bridge (native/untagged)
bridge-ports $PRIMARY_IFACE
bridge-stp off
bridge-fd 0

# No VLAN-aware settings for management bridge
# Workload VLANs can be added as separate bridges (e.g., vmbr1 on nic2.100)
```

#### Prevention
- Document that management VLAN should be configured as **Native** on switch port
- Provide examples for optional workload bridge configuration in comments
- Future deployments can add workload VLANs without network outage risk

#### References
- [VLAN fundamentals: tagged vs untagged](https://en.wikipedia.org/wiki/IEEE_802.1Q)

---

## Network Infrastructure Issues

### Issue: Unifi Port Mode Confusion

**Severity**: ⚠️ Medium (Configuration confusion)  
**Affected Component**: Unifi Switch Port Configuration  
**First Observed**: PVE01 port setup, June 2, 2026

#### Symptom
- Port configured as "Uplink" mode
- Cannot add both management and workload VLANs to tagged list
- Unclear which mode is correct for Proxmox host connection

#### Root Cause
Unifi UI options:
- **Uplink**: For switch-to-switch connections (not appropriate for end hosts)
- **Edge**: For end devices (workstations, servers, APs) - **CORRECT for Proxmox**

#### Resolution
**Status**: Fixed in deployment  
**Configuration Applied**:
- Port Mode: **Edge** ✅
- Native VLAN: PHOENIX-PRIMARY-MGMT (10)
- Tagged VLANs: PHOENIX-PRIMARY-WORKLOAD (100)

#### Prevention
- Use "Edge" mode for all hypervisor and server port connections
- Reserve "Uplink" for switch-to-switch or uplink connections only

---

## Operational Guidance

### What to Monitor

**✅ Safe to Ignore:**
- `hash_elasticity` deprecation warnings in iDRAC/system logs
- IPv6 link-local addresses (fe80::) on bridges with IPv6 disabled (kernel auto-assigns)

**⚠️ Investigate:**
- Firewall status shows parse errors → Review `/etc/pve/firewall/cluster.fw` syntax
- Bridges UP but cannot reach gateway → Check switch port VLAN configuration
- CIFS mounts not appearing in `df -h` → This is normal with automount; access mount point to trigger

**🔴 Requires Action:**
- SSH/web UI unreachable after network changes → Use iDRAC console to check connectivity
- SSHD not running → `systemctl status sshd` and review logs
- Firewall `policy_in: DROP` with no allow rules → Will block all inbound traffic

---

## Recovery Procedures

### Network Configuration Rollback

If network changes break connectivity:

```bash
# Via iDRAC console
cp /etc/network/interfaces /etc/network/interfaces.broken
cp /etc/network/interfaces.pre-vlan10 /etc/network/interfaces  # if backup exists
ifreload -a
```

### Firewall Reset

If firewall rules cause lockout:

```bash
# Via iDRAC console
pve-firewall stop
# Or set permissive policy
sed -i 's/^policy_in:.*/policy_in: ACCEPT/' /etc/pve/firewall/cluster.fw
pve-firewall restart
```

---

## Version Information

| Component | Version | Date |
|-----------|---------|------|
| Proxmox VE | 7.0.6-2-pve | June 2, 2026 |
| Kernel | Linux 7.0.6-2-pve | June 2, 2026 |
| Bootstrap Script | proxmox-bootstrap.sh v2025-11-25-v3 | June 2, 2026 |
| Unifi Dream Machine SE | Latest | June 2, 2026 |

---

## Contributing

To add issues to this document:
1. **Title**: Clear, specific description
2. **Severity**: 🔴 High / 🟡 Medium / ⚠️ Low
3. **Root Cause**: Technical explanation
4. **Impact**: What breaks?
5. **Resolution**: How to fix/workaround
6. **Prevention**: How to avoid in future

---

## References

- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/)
- [Ubiquiti UniFi Documentation](https://help.ui.com/)
- [Linux Bridge VLAN Support](https://www.kernel.org/doc/html/latest/networking/bridge.html)
