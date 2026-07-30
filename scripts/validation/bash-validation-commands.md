# PVE01 Validation Commands (Bash)

**Purpose**: Command-ready, non-destructive validation of current PVE01 state against expected bootstrap baseline.

**PowerShell equivalent**: [pve01-validation-commands.ps1](pve01-validation-commands.ps1) for Windows workflow  
**Generated reports**: Store validation outputs in your local docs/ folder for record-keeping  
**Baseline reference**: Compare against [../../docs/PVE01_DRIFT_SUMMARY.md](../../docs/PVE01_DRIFT_SUMMARY.md)

---

## Scope

This runbook validates alignment only. It does not apply configuration changes.

## Preconditions

1. You have SSH access to PVE01 (root@10.101.0.11 or root@pve01.phoenix.stack)
2. You have local access to repository files:
   - `scripts/provisioning/proxmox-bootstrap.sh`
   - `scripts/provisioning/configs/pve01.conf`
3. You are prepared to capture output into a timestamped report file

## Local Preparation (Workstation)

Run from repository root to set up report file:

```bash
mkdir -p validation-reports
NOW="$(date +%Y%m%d-%H%M%S)"
REPORT="validation-reports/pve01-validation-${NOW}.md"
echo "# PVE01 Validation Report (${NOW})" > "$REPORT"
echo "" >> "$REPORT"
echo "## Source Baseline" >> "$REPORT"
echo "- Config: scripts/provisioning/configs/pve01.conf" >> "$REPORT"
echo "- Script: scripts/provisioning/proxmox-bootstrap.sh" >> "$REPORT"
```

## Baseline Extraction (Workstation)

Extract expected configuration from bootstrap config:

```bash
{
  echo ""
  echo "## Expected Values (from pve01.conf)"
  grep -E '^(NODE_HOSTNAME|NODE_DOMAIN|PRIMARY_IFACE|MGMT_BRIDGE|MGMT_VLAN|MGMT_IP_CIDR|MGMT_GW|DNS_SERVERS|ENABLE_IPV6|SSH_PORT|DISABLE_ROOT_PASSWORD|ENABLE_PVE_FIREWALL|FIREWALL_LOG_LEVEL|USE_NO_SUBSCRIPTION_REPO|DISABLE_SUBSCRIPTION_NAG)=' scripts/provisioning/configs/pve01.conf || true
} >> "$REPORT"
```

## Remote State Collection (PVE01)

Replace `PVE_HOST` if using different credentials/hostname:

```bash
PVE_HOST="root@10.101.0.11"

ssh "$PVE_HOST" 'hostnamectl; echo; ip -br a; echo; ip route; echo; cat /etc/network/interfaces; echo; pveversion -v' > /tmp/pve01-live-state.txt
```

Append remote output to report:

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

Verify SSH hardening, firewall, and access control:

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

Append security check results:

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

Verify CIFS/NFS mounts and storage configuration:

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

Append storage results:

```bash
{
  echo ""
  echo "## Storage Checks"
  echo "\`\`\`text"
  cat /tmp/pve01-storage-state.txt
  echo "\`\`\`"
} >> "$REPORT"
```

## Drift Summary (Manual Review)

After collecting all data, add this section to your report:

```markdown
## Drift Summary

### ✅ Aligned
- (List items that match bootstrap config)

### ⚠️ Drifted
- (List items that differ from bootstrap config)

### ❓ Unknown / Needs Follow-up
- (List items requiring investigation)

## Recommended Remediation
1. (If applicable)
2. (If applicable)
```

## Quick Snapshot (One-Liner)

For rapid validation without capturing to file:

```bash
ssh root@10.101.0.11 'hostname; ip -4 -br a; ip -4 route; pve-firewall status || true; pveversion'
```

## Safety Notes

1. ✅ This runbook is **read-only by design** - no configuration changes are made
2. ✅ Do not paste secrets, tokens, or private keys into report files
3. ✅ Reports saved to local filesystem only - never committed to git
4. ⚠️ If high-risk drift is found (e.g., SSH lockout risk, firewall deny on management access), document findings before attempting remediation
