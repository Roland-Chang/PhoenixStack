# Proxmox Bootstrap - Phoenix Stack

Automated post-installation configuration for Proxmox VE nodes in the Phoenix Stack infrastructure.

## 📋 Overview

This bootstrap script standardizes Proxmox node deployment by automating:

- **Hostname & DNS**: Network identity and domain configuration
- **Network Interfaces**: VLAN-aware bridge configuration for management and workload networks
- **SSH Keys**: Automated key installation from GitHub or manual public key
- **Storage**: CIFS/SMB mount configuration for shared backups and ISO libraries
- **Firewall**: Proxmox cluster firewall enablement and rule configuration
- **System Tuning**: Kernel parameters, swap, sysctl optimizations
- **Package Management**: Repository configuration, security updates
- **Idempotency**: Safe to re-run; skips steps already completed

## 🚀 Quick Start

### 1. Prepare Proxmox Host

Install Proxmox VE from ISO with standard post-installation networking (DHCP). Ensure:
- SSH is accessible
- Network connectivity to repository/firewall servers
- Physical network port attached to management VLAN (untagged/native)

### 2. Create Configuration File

Copy the template:

```bash
cp configs/pve999.conf.example configs/pveXX.conf
```

Edit with your node settings:

```bash
nano configs/pveXX.conf
```

**Critical settings**:
- `NODE_HOSTNAME`: Node identifier (e.g., `pve01`)
- `NODE_DOMAIN`: DNS domain (e.g., `phoenix.stack`)
- `PRIMARY_IFACE`: Physical interface (verify with `ip link` on host)
- `MGMT_IP_CIDR`: Management IP with CIDR (e.g., `10.101.0.11/24`)
- `MGMT_GW`: Default gateway (e.g., `10.101.0.254`)
- `SSH_IMPORT_GITHUB`: GitHub username for automatic key import (recommended)

### 3. Validate Configuration (Dry-Run)

```bash
sudo bash proxmox-bootstrap.sh --dry-run --config-file configs/pveXX.conf --ssh-import-github YOUR_GITHUB_USER
```

Review output for:
- Network interface configuration correctness
- Firewall rule syntax
- CIFS mount paths and credentials
- All expected services and packages

### 4. Execute Bootstrap

```bash
sudo bash proxmox-bootstrap.sh --config-file configs/pveXX.conf --ssh-import-github YOUR_GITHUB_USER
```

Or interactively:

```bash
sudo bash proxmox-bootstrap.sh
```

### 5. Validate Deployment

After bootstrap completes:

```bash
# Verify network configuration
ip addr show
ip route show
bridge link

# Test connectivity
ping <MGMT_GW>
ping 8.8.8.8

# Check firewall status
pve-firewall status

# Verify CIFS mounts
cd /mnt/pve/cifs-backups
ls -la
```

For comprehensive validation, run the validation script from the docs directory:

```bash
bash ../docs/pve01-validation-commands.ps1
```

## 📁 Directory Structure

```
scripts/provisioning/
├── proxmox-bootstrap.sh          # Main bootstrap script (executable)
├── README.md                      # This file
├── deploy_proxmox_bootstrap.sh   # Optional deployment wrapper
├── configs/
│   ├── README.md                 # Configuration guide
│   ├── pveXX.conf               # Per-node configuration files
│   └── pve999.conf.example      # Configuration template
```

## 🔧 Configuration Options

See `configs/README.md` for complete configuration reference.

Key variables:

| Variable | Example | Purpose |
|----------|---------|---------|
| `NODE_HOSTNAME` | `pve01` | Node name |
| `NODE_DOMAIN` | `phoenix.stack` | DNS domain |
| `PRIMARY_IFACE` | `nic2` | Physical network interface |
| `MGMT_IP_CIDR` | `10.101.0.11/24` | Management IP + CIDR |
| `MGMT_GW` | `10.101.0.254` | Default gateway |
| `MGMT_VLAN` | `10` | Management VLAN (info only, for documentation) |
| `ENABLE_CIFS` | `yes` | Enable CIFS mount auto-configuration |
| `SMB_SERVER` | `10.101.0.101` | CIFS/SMB server IP |
| `ENABLE_PVE_FIREWALL` | `yes` | Enable Proxmox firewall |
| `DISABLE_ROOT_PASSWORD` | `yes` | Disable root password login (use SSH keys only) |
| `SSH_IMPORT_GITHUB` | `username` | Automatically import SSH keys from GitHub |

## ⚠️ Known Issues & Fixes

### Issue: Firewall Configuration Parse Errors (FIXED in v4)

**Symptom**: Firewall status shows syntax errors on lines 6-7, 22

**Fix**: v4 removes invalid Proxmox 7.x firewall directives (`log_level_in`, `log_level_out`, invalid conntrack rules)

**Details**: See [docs/known-issues.md](../../docs/known-issues.md#issue-firewall-configuration-generation-bug)

### Issue: Network Connectivity After VLAN Configuration (FIXED in v4)

**Symptom**: Network fails after bootstrap; ARP incomplete for gateway

**Fix**: v4 uses native (untagged) VLAN configuration for management bridge; removes deprecated VLAN-aware settings

**Details**: See [docs/known-issues.md](../../docs/known-issues.md#issue-network-configuration-doesnt-account-for-native-vs-tagged-vlans)

**Key Learning**: Management VLAN must be configured as **Native (untagged)** on switch port. Script now assumes this standard topology.

### Issue: CIFS Mounts Don't Appear in `df`

**Symptom**: Mount point exists but doesn't show in `df` output

**Behavior**: This is expected with `x-systemd.automount`; mounts only appear after first access

**Workaround**: Access mount point to trigger automount: `ls /mnt/pve/cifs-backups`

## 📖 Usage Patterns

### Deployment Workflow

1. **PXE/ISO Boot**: Fresh Proxmox VE installation
2. **SSH Access**: Ensure root SSH login works temporarily
3. **Config Prep**: Create node-specific `.conf` file
4. **Dry-Run**: Validate configuration without applying
5. **Execute**: Run bootstrap script
6. **Validate**: Run validation script to confirm all settings
7. **Iterate**: For PVE02, PVE03, etc., repeat steps 3-6

### Recovery from Network Misconfiguration

If network fails during bootstrap:

1. Access via iDRAC/IPMI console (serial or web)
2. Revert network config: `cp /etc/network/interfaces.bak /etc/network/interfaces`
3. Restart networking: `systemctl restart networking`
4. SSH back in and review `/var/log/proxmox-bootstrap.log`
5. Adjust configuration and retry

See [docs/known-issues.md](../../docs/known-issues.md) for recovery procedures.

## 🔐 Security Considerations

- **SSH Keys Only**: Script disables root password by default (`DISABLE_ROOT_PASSWORD=yes`)
- **Key Import**: Uses GitHub API to fetch public keys (requires GitHub username)
- **SMB Credentials**: Stored in `/root/.smbcredentials` with restricted permissions (600)
- **Firewall Enabled**: Proxmox firewall enabled by default with restricted rule set
- **No Secrets in Config**: Configuration files never contain passwords or private keys

**Best Practice**: Store configuration files in git with sensitive values injected at runtime via environment variables or command-line flags.

## 📝 Logging

Bootstrap execution is logged to:

- **Console**: Real-time status and progress
- **Syslog**: `/var/log/syslog` for persistent logging
- **Bootstrap Log**: `/var/log/proxmox-bootstrap.log` (if configured)

Enable verbose output:

```bash
sudo bash -x proxmox-bootstrap.sh --config-file configs/pveXX.conf 2>&1 | tee bootstrap.log
```

## 🧪 Testing

### Dry-Run Validation

Always test configuration before deployment:

```bash
sudo bash proxmox-bootstrap.sh --dry-run --config-file configs/pve01.conf --ssh-import-github myusername
```

This shows:
- Generated network interfaces configuration
- Firewall rules that will be created
- CIFS mount points and paths
- All package installations
- No actual system changes applied

### Idempotency Verification

Script is designed to be safe to re-run:

```bash
# Run once
sudo bash proxmox-bootstrap.sh --config-file configs/pveXX.conf

# Run again - should report already configured
sudo bash proxmox-bootstrap.sh --config-file configs/pveXX.conf
```

Second run should skip most steps and report "Already configured."

## 📞 Troubleshooting

**Problem**: "Primary interface not found"
- **Cause**: Interface name in config doesn't match host
- **Fix**: Verify with `ip link` on target host; update config

**Problem**: "Cannot download SSH key from GitHub"
- **Cause**: Network unreachable or GitHub username invalid
- **Fix**: Provide SSH key directly via `SSH_PUBLIC_KEY` config variable

**Problem**: "CIFS mount failed"
- **Cause**: SMB credentials incorrect or SMB server unreachable
- **Fix**: Verify SMB_SERVER IP and SMB_USER/SMB_PASS; test from host with: `smbclient -L //10.101.0.101`

**Problem**: "Firewall shows syntax errors"
- **Cause**: Old bootstrap version (v3 or earlier)
- **Fix**: Update to v4+

## 📚 Related Documentation

- [Management VLAN Implementation](../../docs/management-vlan-implementation.md)
- [Known Issues & Troubleshooting](../../docs/known-issues.md)
- [PVE01 Validation Commands](../../docs/pve01-validation-commands.md)
- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)

## 📋 Checklist for New Deployments

- [ ] Proxmox VE installed from ISO
- [ ] SSH access verified
- [ ] Config file created (`configs/pveXX.conf`)
- [ ] Dry-run executed and reviewed
- [ ] Bootstrap executed
- [ ] Validation script passed
- [ ] Proxmox Web UI accessible
- [ ] SSH key-based auth working
- [ ] CIFS mounts accessible
- [ ] Firewall running without errors

## 📝 Version History

| Version | Date | Changes |
|---------|------|---------|
| v4 | 2026-06-02 | Fixed firewall config syntax errors; fixed network VLAN logic for native (untagged) management VLAN |
| v3 | 2025-11-25 | Initial Phoenix Stack bootstrap implementation |

## License

Phoenix Stack - Internal Infrastructure

