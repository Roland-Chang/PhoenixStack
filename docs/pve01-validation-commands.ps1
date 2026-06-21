# PVE01 Validation Script (PowerShell)
# Purpose: command-ready, non-destructive validation of current PVE01 state against expected bootstrap baseline.
# Run from repository root on Windows workstation.

param(
    [string]$PveHost = "root@pve01.phoenix.stack",
    [string]$ConfigFile = "Scripts/proxmox/configs/pve01.conf"
)

# Validate preconditions
if (-not (Test-Path $ConfigFile)) {
    Write-Error "Config file not found: $ConfigFile"
    exit 1
}

# Create timestamped report
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = "docs/pve01-validation-report-$timestamp.md"

Write-Host "Creating validation report: $reportPath" -ForegroundColor Cyan

# Initialize report
@"
# PVE01 Validation Report ($timestamp)

## Source Baseline
- Config: $ConfigFile
- Script: Scripts/proxmox/proxmox-bootstrap.sh

"@ | Out-File -FilePath $reportPath -Encoding utf8

# Extract expected values from config
Write-Host "Extracting expected configuration values..." -ForegroundColor Cyan

$expectedSection = @"

## Expected Values (from pve01.conf)
``````text
"@

$configContent = Get-Content $ConfigFile | Where-Object { 
    $_ -match '^(NODE_HOSTNAME|NODE_DOMAIN|PRIMARY_IFACE|MGMT_BRIDGE|MGMT_VLAN|MGMT_IP_CIDR|MGMT_GW|DNS_SERVERS|ENABLE_IPV6|SSH_PORT|DISABLE_ROOT_PASSWORD|ENABLE_PVE_FIREWALL|FIREWALL_LOG_LEVEL|USE_NO_SUBSCRIPTION_REPO|DISABLE_SUBSCRIPTION_NAG)=' 
}

$expectedSection += ($configContent -join "`n")
$expectedSection += "`n``````n"

Add-Content -Path $reportPath -Value $expectedSection

# Collect live state from PVE01
Write-Host "Collecting live state from $PveHost..." -ForegroundColor Cyan

$stateCommands = "hostnamectl; echo; ip -br a; echo; ip route; echo; cat /etc/network/interfaces; echo; pveversion -v"

try {
    $liveState = ssh $PveHost $stateCommands 2>&1
    
    $stateSection = @"

## Live State Snapshot (PVE01)
``````text
$liveState
``````

"@
    Add-Content -Path $reportPath -Value $stateSection
}
catch {
    Write-Warning "Failed to collect live state: $_"
    Add-Content -Path $reportPath -Value "`n## Live State Snapshot (PVE01)`n**ERROR**: Failed to connect or execute commands.`n"
}

# Security and access checks
Write-Host "Running security and access checks..." -ForegroundColor Cyan

$securityCommands = @'
echo "== SSH daemon config (effective subset) ==";
sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication|pubkeyauthentication)";
echo;
echo "== Firewall status ==";
pve-firewall status || true;
echo;
echo "== Datacenter firewall options ==";
[ -f /etc/pve/firewall/cluster.fw ] && sed -n "1,160p" /etc/pve/firewall/cluster.fw || echo "cluster.fw not found";
'@

try {
    $securityState = ssh $PveHost $securityCommands 2>&1
    
    $securitySection = @"

## Security Checks
``````text
$securityState
``````

"@
    Add-Content -Path $reportPath -Value $securitySection
}
catch {
    Write-Warning "Failed to collect security state: $_"
    Add-Content -Path $reportPath -Value "`n## Security Checks`n**ERROR**: Failed to execute security checks.`n"
}

# Storage and mount checks
Write-Host "Running storage and mount checks..." -ForegroundColor Cyan

$storageCommands = @'
echo "== /etc/fstab ==";
cat /etc/fstab;
echo;
echo "== Active mounts (CIFS/NFS) ==";
findmnt -t cifs,nfs,nfs4 || true;
echo;
echo "== Proxmox storage config ==";
cat /etc/pve/storage.cfg;
'@

try {
    $storageState = ssh $PveHost $storageCommands 2>&1
    
    $storageSection = @"

## Storage Checks
``````text
$storageState
``````

"@
    Add-Content -Path $reportPath -Value $storageSection
}
catch {
    Write-Warning "Failed to collect storage state: $_"
    Add-Content -Path $reportPath -Value "`n## Storage Checks`n**ERROR**: Failed to execute storage checks.`n"
}

# Add drift summary template
$driftTemplate = @"

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

---
*Validation completed: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")*
"@

Add-Content -Path $reportPath -Value $driftTemplate

Write-Host "`nValidation report created: $reportPath" -ForegroundColor Green
Write-Host "Review the report and fill in the Drift Summary section manually." -ForegroundColor Yellow

# Optional: Open report in VS Code
$openReport = Read-Host "`nOpen report in VS Code? (y/n)"
if ($openReport -eq 'y') {
    code $reportPath
}
