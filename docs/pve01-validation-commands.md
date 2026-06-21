# PVE01 Validation Commands (Bash)

Purpose: command-ready, non-destructive validation of current PVE01 state against expected bootstrap baseline.

**PowerShell users**: See [pve01-validation-commands.ps1](pve01-validation-commands.ps1) for native Windows workflow.  
**Report template**: See [pve01-validation-report-template.md](pve01-validation-report-template.md) for manual validation structure.

## Scope

This runbook validates alignment only. It does not apply configuration changes.

## Preconditions

1. You have SSH access to PVE01.
2. You have local access to repository files:
   - Scripts/proxmox/proxmox-bootstrap.sh
   - Scripts/proxmox/configs/pve01.conf
3. You are prepared to capture output into a timestamped report file.

## Local Preparation (Workstation)

Run from repository root.

```bash
mkdir -p docs
NOW="$(date +%Y%m%d-%H%M%S)"
REPORT="docs/pve01-validation-report-${NOW}.md"
echo "# PVE01 Validation Report (${NOW})" > "$REPORT"
echo "" >> "$REPORT"
echo "## Source Baseline" >> "$REPORT"
echo "- Config: Scripts/proxmox/configs/pve01.conf" >> "$REPORT"
echo "- Script: Scripts/proxmox/proxmox-bootstrap.sh" >> "$REPORT"
```

## Baseline Extraction (Workstation)

```bash
{
  echo ""
  echo "## Expected Values (from pve01.conf)"
  grep -E '^(NODE_HOSTNAME|NODE_DOMAIN|PRIMARY_IFACE|MGMT_BRIDGE|MGMT_VLAN|MGMT_IP_CIDR|MGMT_GW|DNS_SERVERS|ENABLE_IPV6|SSH_PORT|DISABLE_ROOT_PASSWORD|ENABLE_PVE_FIREWALL|FIREWALL_LOG_LEVEL|USE_NO_SUBSCRIPTION_REPO|DISABLE_SUBSCRIPTION_NAG)=' Scripts/proxmox/configs/pve01.conf || true
} >> "$REPORT"
```

## Remote State Collection (PVE01)

Replace admin user and host if needed.

```bash
PVE_HOST="root@PVE01.phoenix.stack"

ssh "$PVE_HOST" 'hostnamectl; echo; ip -br a; echo; ip route; echo; cat /etc/network/interfaces; echo; pveversion -v' > /tmp/pve01-live-state.txt
```

Append remote output to report.

```bash
{
  echo ""
  echo "## Live State Snapshot (PVE01)"
  echo "\`\`\`text"
  cat /tmp/pve01-live-state.txt
  echo "\`\`\`"
} >> "$REPORT"
```

## Security and Access Checks (PVE01)

```bash
ssh "$PVE_HOST" '
  echo "== SSH daemon config (effective subset) ==";
  sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication|pubkeyauthentication)";
  echo;
  echo "== Firewall status ==";
  pve-firewall status || true;
  echo;
  echo "== Datacenter firewall options ==";
  [ -f /etc/pve/firewall/cluster.fw ] && sed -n "1,160p" /etc/pve/firewall/cluster.fw || echo "cluster.fw not found";
' > /tmp/pve01-security-state.txt
```

```bash
{
  echo ""
  echo "## Security Checks"
  echo "\`\`\`text"
  cat /tmp/pve01-security-state.txt
  echo "\`\`\`"
} >> "$REPORT"
```

## Storage and Mount Checks (PVE01)

```bash
ssh "$PVE_HOST" '
  echo "== /etc/fstab ==";
  cat /etc/fstab;
  echo;
  echo "== Active mounts (CIFS/NFS) ==";
  findmnt -t cifs,nfs,nfs4 || true;
  echo;
  echo "== Proxmox storage config ==";
  cat /etc/pve/storage.cfg;
' > /tmp/pve01-storage-state.txt
```

```bash
{
  echo ""
  echo "## Storage Checks"
  echo "\`\`\`text"
  cat /tmp/pve01-storage-state.txt
  echo "\`\`\`"
} >> "$REPORT"
```

## Drift Summary Template

Add this section manually after review.

```markdown
## Drift Summary

### Aligned
- 

### Drifted
- 

### Unknown / Needs Follow-up
- 

## Recommended Next Small Changes
1. 
2. 
3. 
```

## Optional: Quick One-Liner Validation Snapshot

```bash
ssh "$PVE_HOST" 'hostname; ip -4 -br a; ip -4 route; pve-firewall status || true; pveversion'
```

## Safety Notes

1. This runbook is read-only by design.
2. Do not paste secrets, tokens, or private keys into report files.
3. If any high-risk drift is found (SSH lockout risk, firewall deny on management access), stop and document before remediation.
