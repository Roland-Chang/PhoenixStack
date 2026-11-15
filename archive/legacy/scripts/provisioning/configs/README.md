# Proxmox Bootstrap Configurations

This directory contains node-specific configuration files for the Proxmox bootstrap script (`../proxmox-bootstrap.sh`). Each `.conf` file defines settings for a single Proxmox VE node, enabling reproducible, version-controlled deployments.

## 📁 Purpose

Store node-specific configurations to enable:

- **Repeatable deployments**: Same configuration every time
- **Version control**: Track changes to node configurations
- **Documentation**: Configuration files serve as infrastructure documentation

## 🚀 Usage

### 1. Create Node Configuration

Copy the example template:

```bash
cp pve999.conf.example pveXX.conf
```

Replace `XX` with your node identifier (e.g., `01`, `02`, `backup`, `compute01`).

### 2. Edit Configuration

```bash
nano pveXX.conf
```

**Minimum required settings:**

- `NODE_HOSTNAME`: Node name (e.g., `pve01`)
- `NODE_DOMAIN`: DNS domain (e.g., `phoenix.stack`)
- `PRIMARY_IFACE`: Physical interface name (verify with: `ip link`)
- `MGMT_IP_CIDR`: Node management IP with CIDR notation (e.g., `10.101.0.1/16`)
- `MGMT_GW`: Default gateway IP
- `SSH_PUBLIC_KEY` OR `SSH_IMPORT_GITHUB`: Add SSH key(s) to avoid lockout

### 3. Run Bootstrap

From the scripts directory:

```bash
./proxmox-bootstrap.sh --config ./proxmox-configs/pveXX.conf
```

Or with additional options:

```bash
# Dry-run mode (preview changes without applying)
./proxmox-bootstrap.sh --config ./proxmox-configs/pveXX.conf --dry-run

# Auto-reboot after completion
./proxmox-bootstrap.sh --config ./proxmox-configs/pveXX.conf --reboot
```

---

## 🔧 Configuration Sections

### Node Identity

```ini
NODE_HOSTNAME="pveXX"           # Short hostname (no domain)
NODE_DOMAIN="phoenix.stack"     # DNS domain
TIMEZONE="America/Denver"       # System timezone
SITE="primary"                  # primary or secondary site
```

### Networking (Required)

```ini
PRIMARY_IFACE="nic1"            # Physical NIC (verify: ip link)
MGMT_BRIDGE="vmbr0"             # Bridge interface to configure
MGMT_VLAN=""                    # VLAN ID or blank for untagged
MGMT_IP_CIDR="10.101.1.10/24"   # Node IP with CIDR prefix
MGMT_GW="10.101.1.254"          # Default gateway
DNS_SERVERS="1.1.1.1 1.0.0.1"   # Space-separated DNS servers
ENABLE_IPV6="no"                # IPv6 support (yes/no)
```

### Current Network Schema

- PHOENIX-Primary: `10.101.0.0/16` (workloads/default PHOENIX host network)
- Typical host bootstrap on current configs uses PHOENIX-Primary (`10.1.101.0/24`)

### SSH Security (Important: Prevent Lockout!)

```ini
# Option A: Inline public key (takes precedence)
SSH_PUBLIC_KEY="ssh-ed25519 AAAA... user@host"

# Option B: Auto-import from GitHub
SSH_IMPORT_GITHUB="github_username"

SSH_PORT="22"                    # SSH listening port
DISABLE_ROOT_PASSWORD="yes"      # Disable password auth (requires SSH key!)
```

⚠️ **WARNING**: Always provide an SSH public key or GitHub username before enabling `DISABLE_ROOT_PASSWORD=yes`, or you will lose access to the node.

Behavior implemented in `proxmox-bootstrap.sh`:

- If `DISABLE_ROOT_PASSWORD=yes` and no key is present, the script keeps password auth enabled to prevent lockout.
- If `SSH_IMPORT_GITHUB` is empty but a TTY is present, the script prompts for a GitHub username even in config mode.
- GitHub import tries `ssh-import-id-gh` and falls back to `ssh-import-id gh:<user>`.

### CIFS/SMB Mounts (Optional)

```ini
ENABLE_CIFS="yes"                            # Enable/disable CIFS mounts
SMB_SERVER="unas.phoenix.stack"              # SMB server hostname/IP
SMB_USERNAME="proxmox_backup"                # SMB username
SMB_PASSWORD=""                              # optional; if blank the script prompts securely
SMB_DOMAIN=""                                # Optional domain/workgroup
SMB_AUTOCREATE_DIRS="yes"                    # Auto-create Backups/<NODE> subdirs
SMB_CREDENTIALS_PATH="/root/.smbcredentials" # Path to credentials file
CIFS_UID="100000"                            # UID for unprivileged LXC (maps to root/UID 0 inside container)
CIFS_GID="101000"                            # GID for unprivileged LXC (maps to svc_docker/GID 1000 inside container)
```

Example CIFS mounts (edit as needed):

```ini
CIFS_ENTRIES=(
  "//${SMB_SERVER}/Backups/${NODE_HOSTNAME} /mnt/pve/cifs-backups cifs _netdev,x-systemd.automount,uid=100000,gid=101000,credentials=/root/.smbcredentials 0 0"
  "//${SMB_SERVER}/ISO /mnt/pve/cifs-iso cifs _netdev,x-systemd.automount,uid=100000,gid=101000,credentials=/root/.smbcredentials 0 0"
)
```

### Repository Configuration

```ini
USE_NO_SUBSCRIPTION_REPO="yes"   # Use free no-subscription repo (required if no license)
DISABLE_SUBSCRIPTION_NAG="yes"   # Remove subscription popup from UI
```

### Firewall & Services

```ini
ENABLE_PVE_FIREWALL="yes"        # Enable Proxmox built-in firewall
FIREWALL_LOG_LEVEL="info"        # Log level: info, debug, notice, etc.
```

Firewall safeguard implemented in `proxmox-bootstrap.sh`:

- Baseline cluster firewall rules always include `TCP/22` allow (in addition to `SSH_PORT`) to reduce lockout risk.
- If the script cannot confirm a TCP/22 allow rule in generated firewall config, it disables firewall enablement in that generated file and aborts firewall setup.

### Kernel Tuning (Optional)

```ini
ENABLE_L1TF_FLUSH_NOWARN="yes"   # Add l1tf=flush,nowarn kernel parameter
```

### IPMI Configuration (Optional)

```ini
CONFIGURE_IPMI_NETWORK="no"      # Configure out-of-band management
IPMI_IP=""                       # IPMI static IP
IPMI_NETMASK=""                  # IPMI netmask
IPMI_GATEWAY=""                  # IPMI gateway
```

For complete reference with inline documentation, see: `pve999.conf.example`

---

## 🔐 Security Best Practices

### SSH Key Management

1. **Prevent lockout**: Always add SSH key(s) before setting `DISABLE_ROOT_PASSWORD=yes`

   ```ini
   SSH_PUBLIC_KEY="ssh-ed25519 AAAA... user@workstation"
   # OR
   SSH_IMPORT_GITHUB="your_github_username"
   ```

2. **Generate a strong key** (on your management machine):

   ```bash
   ssh-keygen -t ed25519 -C "proxmox-admin@$(hostname)" -f ~/.ssh/pve_admin_ed25519
   cat ~/.ssh/pve_admin_ed25519.pub  # Add this to SSH_PUBLIC_KEY
   ```

3. **Test before deploying**:

   ```bash
   # Test in dry-run mode first
   ./proxmox-bootstrap.sh --config ./pveXX.conf --dry-run
   ```

### Credential File Security

1. **SMB credentials file permissions must be 600**:

   ```bash
   chmod 600 /root/.smbcredentials
   ```

3. **Version Control**: Be cautious committing files with credentials (use `.gitignore` if needed)

## 🎯 IP Allocation Strategy

Align node IPs with Phoenix Stack network architecture:

**Primary Site PHOENIX-Primary (10.1.101.0/24):**

- 10.101.1.1 - PVE01 (current config example)
- 10.101.1.10-19 - Proxmox hypervisor nodes
- 10.101.1.20-99 - Infrastructure nodes/services
- 10.101.1.100+ - Application VMs/containers

**Primary Site PHOENIX-Primary-Management (10.1.100.0/24):**

- 10.101.0.1 - Dell iDRAC management
- Reserve additional addresses for future OOB and infrastructure management services

**Secondary Site:**

- Keep secondary allocations documented separately per-site as they evolve.

## 🔧 MGMT_VLAN Guidance

| Scenario | Switch Port | Desired VLAN | `MGMT_VLAN` Value | Explanation |
|----------|-------------|--------------|------------------|-------------|
| Host NIC on trunk (multiple VLANs) | 802.1Q trunk | PHOENIX-Primary (10.1.101.0/24) | `10` | Assigns bridge PVID 10 so host IP is on PHOENIX-Primary |
| Host NIC on access port (already PHOENIX-Primary) | Access/untagged | PHOENIX-Primary | `""` (blank) | Upstream port handles VLAN; omit PVID to prevent redundancy |
| Move host to PHOENIX-Primary-Management | 802.1Q trunk | PHOENIX-Primary-Management (10.1.100.0/24) | `11` (example) | Change `MGMT_IP_CIDR`/gateway and ensure firewall allows SSH/WebUI |
| Temporary test VLAN (e.g. 200) | 802.1Q trunk | Test (200) | `200` | Ensure trunk allows VLAN 200 before use |

Best Practices:

- Use a trunk + PVID when the host will also bridge other tagged VLANs for VMs/LXCs.
- Leave blank if the switch port is configured as an access port—simpler and fewer moving parts.
- When migrating to a dedicated management VLAN, plan updates: inventory, DNS records, firewall rules, monitoring targets.
- Keep VLAN definitions and subnet intent consistent across sites.

## 🧱 Line Ending Safety

Shell scripts and Proxmox config files must use LF line endings.

- Windows CRLF line endings can cause bootstrap failures like `$'\r': command not found`.
- Repository `.gitattributes` now enforces LF for `*.sh` and `scripts/proxmox-configs/*.conf`.
- If needed on host, normalize copied files:

```bash
sed -i 's/\r$//' /root/proxmox-bootstrap.sh /root/pve01.conf
```

## 🔄 Workflow

1. **Create config**: `cp pve999.conf.example pveXX.conf`
2. **Customize**: Edit node-specific values
3. **Review**: `cat pveXX.conf`
4. **Deploy**: `sudo ../proxmox-bootstrap.sh --config ./pveXX.conf`
5. **Verify**: Check `/var/log/syslog` for bootstrap activity
6. **Document**: Update this README with node details
7. **Commit**: `git add pveXX.conf && git commit -m "Add pveXX configuration"`

## 📚 Related Documentation

- Bootstrap script: `scripts/proxmox-bootstrap.sh`
