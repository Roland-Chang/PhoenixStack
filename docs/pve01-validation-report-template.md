# PVE01 Validation Report (YYYY-MM-DD)

**Date**: YYYY-MM-DD HH:MM:SS  
**Validator**: [Your Name]  
**Purpose**: Non-destructive validation of PVE01 state against bootstrap baseline  

---

## Source Baseline
- Config: Scripts/proxmox/configs/pve01.conf
- Script: Scripts/proxmox/proxmox-bootstrap.sh

---

## Expected Values (from pve01.conf)

```text
NODE_HOSTNAME="..."
NODE_DOMAIN="..."
PRIMARY_IFACE="..."
MGMT_BRIDGE="..."
MGMT_VLAN="..."
MGMT_IP_CIDR="..."
MGMT_GW="..."
DNS_SERVERS="..."
ENABLE_IPV6="..."
SSH_PORT="..."
DISABLE_ROOT_PASSWORD="..."
ENABLE_PVE_FIREWALL="..."
FIREWALL_LOG_LEVEL="..."
USE_NO_SUBSCRIPTION_REPO="..."
DISABLE_SUBSCRIPTION_NAG="..."
```

---

## Live State Snapshot (PVE01)

### Hostname and Identity
```text
[Output from: hostnamectl]
```

### Network Interfaces
```text
[Output from: ip -br a]
```

### Routing
```text
[Output from: ip route]
```

### Network Configuration File
```text
[Output from: cat /etc/network/interfaces]
```

### Proxmox Version
```text
[Output from: pveversion -v]
```

---

## Security Checks

### SSH Configuration (Effective)
```text
[Output from: sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication|pubkeyauthentication)"]
```

**Expected Standards**:
- Port: [SSH_PORT from config or 22]
- PermitRootLogin: yes or prohibit-password
- PasswordAuthentication: **no** (SSH key-only required)
- PubkeyAuthentication: **yes**

### Firewall Status
```text
[Output from: pve-firewall status]
```

### Datacenter Firewall Configuration
```text
[Output from: cat /etc/pve/firewall/cluster.fw (first 160 lines)]
```

---

## Storage Checks

### fstab Entries
```text
[Output from: cat /etc/fstab]
```

### Active CIFS/NFS Mounts
```text
[Output from: findmnt -t cifs,nfs,nfs4]
```

### Proxmox Storage Configuration
```text
[Output from: cat /etc/pve/storage.cfg]
```

---

## Drift Summary

### ✅ Aligned
- [List items that match expected baseline exactly]
- 

### ⚠️ Drifted
- [List items that differ from expected baseline]
- 

### ❓ Unknown / Needs Follow-up
- [List items that require additional investigation or clarification]
- 

---

## Security Posture Assessment

### SSH Key-Only Access
- [ ] Password authentication is disabled
- [ ] Public key authentication is enabled
- [ ] Root login method is appropriate (key-only or prohibited)

### Firewall Configuration
- [ ] Proxmox firewall is enabled (if ENABLE_PVE_FIREWALL=yes)
- [ ] SSH access rule exists and is appropriate
- [ ] Default policy is deny/drop
- [ ] No overly permissive allow rules

### Network Configuration
- [ ] IP addressing matches expected baseline
- [ ] Default gateway is correct
- [ ] DNS servers are configured as expected
- [ ] IPv6 is disabled (if ENABLE_IPV6=no)

### Storage Security
- [ ] CIFS/NFS mounts use credentials file (not inline passwords)
- [ ] Credentials file has 600 permissions
- [ ] Mount options include appropriate security flags (_netdev, etc.)

---

## Recommended Next Small Changes

1. [Specific, actionable change item]
2. [Specific, actionable change item]
3. [Specific, actionable change item]

---

## Notes and Observations

[Add any additional context, concerns, or observations here]

---

## Approval and Sign-off

- [ ] No high-risk drift identified (SSH lockout, firewall deny on mgmt)
- [ ] Drift items documented and remediation plan created (if needed)
- [ ] Ready to proceed to next phase (yes/no/conditional)

**Validated by**: [Your Name]  
**Date**: [YYYY-MM-DD]  

---

*This validation was performed using command-ready runbooks from docs/pve01-validation-commands.md and docs/pve01-validation-commands.ps1*
