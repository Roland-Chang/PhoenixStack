# Validation Scripts & Runbooks

Executable validation and testing scripts for PhoenixStack infrastructure. All scripts are **read-only** (non-destructive) validation of infrastructure state.

---

## 🖥️ PVE01 Validation

**Purpose**: Verify Proxmox VE node (pve01) state matches bootstrap configuration and expected baseline.

**Status**: ✅ Stable (Updated 2026-07-29)

### Cross-Platform Validation

Choose the runbook for your platform:

#### **Bash/Linux** (Recommended for Linux/macOS/WSL)
- **File**: [bash-validation-commands.md](bash-validation-commands.md)
- **Platform**: Linux, macOS, WSL, Cygwin
- **Execution**: Copy-paste bash commands into terminal
- **Output**: Markdown report in your local `validation-reports/` folder
- **Time**: 2-3 minutes

#### **PowerShell/Windows** (Native Windows)
- **File**: [pve01-validation-commands.ps1](pve01-validation-commands.ps1)
- **Platform**: Windows PowerShell 5.0+
- **Execution**: Run script directly: `.\pve01-validation-commands.ps1`
- **Output**: Validation report generated on local filesystem
- **Time**: 2-3 minutes

### Baseline Reference

After validation, compare your results against the known-good baseline:

- **File**: [../../docs/PVE01_DRIFT_SUMMARY.md](../../docs/PVE01_DRIFT_SUMMARY.md)
- **Status**: ✅ COMPLIANT (PVE01 fully aligned with bootstrap, generated 2026-07-29)
- **Content**: Expected values for network, SSH, firewall, storage, and system configuration

### Validation Workflow

1. **Prepare** (5 minutes)
   - Choose platform-appropriate runbook above
   - Ensure SSH access to pve01 (root@10.101.0.11)
   - Clone repository locally with `scripts/provisioning/configs/pve01.conf` accessible

2. **Execute** (2-3 minutes)
   - Follow the runbook step-by-step
   - Commands are safe: read-only, no configuration changes
   - Captures output to local `validation-reports/pve01-validation-TIMESTAMP.md` file

3. **Review** (5-10 minutes)
   - Compare collected state against baseline
   - Identify any drift from expected configuration
   - Document findings in the report file

4. **Store** (optional)
   - Keep reports locally for audit trail
   - Never commit reports to git (they contain sensitive infrastructure data)

---

## 🔍 What Gets Validated

| Component | Validation | Expected Value |
|-----------|-----------|-----------------|
| **Hostname & Domain** | `hostnamectl` | `pve01` / `phoenix.stack` |
| **Network Interfaces** | `ip -br a` | vmbr0: 10.101.0.11/24 (VLAN 10) |
| **Default Route** | `ip route` | via 10.101.0.254 |
| **SSH Configuration** | `sshd -T` | Port 22, key-only, no password auth |
| **Firewall Status** | `pve-firewall status` | Enabled and running |
| **Storage Mounts** | `findmnt`, `/etc/fstab` | CIFS backups/ISO/media mounted |
| **Package Repos** | Storage config | No-subscription repo enabled |
| **System Version** | `pveversion -v` | Proxmox VE 9.1.1+ |

---

## ✅ Safety & Best Practices

- **Read-Only**: All validation scripts only read infrastructure state; no changes are made
- **No Secrets**: Script output does not capture passwords or private keys
- **Local Reports**: Validation reports are stored locally only; never committed to git
- **Error Handling**: Scripts handle expected errors gracefully (e.g., optional firewall configs)
- **Idempotent**: Safe to run validation multiple times without side effects

---

## 🚀 Quick Start

### Linux/macOS/WSL
```bash
# From repository root
cd scripts/validation
# Follow the copy-paste commands from bash-validation-commands.md
```

### Windows PowerShell
```powershell
# From scripts\validation folder
.\pve01-validation-commands.ps1
# Script runs interactively and displays results
```

---

## 📋 Related Documentation

- **Bootstrap Config**: [scripts/provisioning/configs/pve01.conf](../provisioning/configs/pve01.conf) - Configuration template
- **Bootstrap Script**: [scripts/provisioning/proxmox-bootstrap.sh](../provisioning/proxmox-bootstrap.sh) - Deployment script
- **Baseline Report**: [docs/PVE01_DRIFT_SUMMARY.md](../../docs/PVE01_DRIFT_SUMMARY.md) - Known-good state
- **Known Issues**: [docs/known-issues.md](../../docs/known-issues.md) - Troubleshooting guide
