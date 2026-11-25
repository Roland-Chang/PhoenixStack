#!/bin/bash
# backup-scheduler.sh - Master backup orchestrator for all LXC containers
#
# Reads proxmox-backups.conf and executes backup-lxc.sh for each service
# 
# Execution: Runs once daily via cron (typically 02:00 UTC)
# 
# Log location: /var/log/proxmox-backup-scheduler.log

set -euo pipefail

# Configuration
CONFIG_FILE="/etc/proxmox-backups.conf"
BACKUP_SCRIPT="/usr/local/bin/backup-lxc.sh"
LOG_FILE="/var/log/proxmox-backup-scheduler.log"

# ============================================================================
# Validation
# ============================================================================
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] Config file not found: $CONFIG_FILE" | tee -a "$LOG_FILE"
    exit 1
fi

if [ ! -x "$BACKUP_SCRIPT" ]; then
    echo "[ERROR] Backup script not executable: $BACKUP_SCRIPT" | tee -a "$LOG_FILE"
    exit 1
fi

# ============================================================================
# Log function
# ============================================================================
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

# ============================================================================
# Main backup loop
# ============================================================================
main() {
    log "INFO" "=========================================="
    log "INFO" "Master backup scheduler started"
    log "INFO" "Config: $CONFIG_FILE"
    log "INFO" "=========================================="
    
    local total_count=0
    local success_count=0
    local error_count=0
    
    # Read config file line by line
    while IFS=':' read -r vmid hostname retention; do
        # Skip comments and empty lines
        [[ "$vmid" =~ ^# ]] && continue
        [[ -z "$vmid" ]] && continue
        
        # Trim whitespace
        vmid=$(echo "$vmid" | xargs)
        hostname=$(echo "$hostname" | xargs)
        retention=$(echo "$retention" | xargs)
        
        log "INFO" "--------"
        log "INFO" "Processing: VMID=$vmid, Hostname=$hostname, Retention=$retention days"
        
        # Execute backup script
        if "$BACKUP_SCRIPT" "$vmid" "$hostname" "$retention"; then
            log "INFO" "✅ Backup succeeded for $hostname (VMID $vmid)"
            ((success_count++))
        else
            log "ERROR" "❌ Backup failed for $hostname (VMID $vmid)"
            ((error_count++))
        fi
        
        ((total_count++))
        
    done < <(grep -v '^#' "$CONFIG_FILE" | grep -v '^$')
    
    log "INFO" "=========================================="
    log "INFO" "Master backup scheduler completed"
    log "INFO" "Total: $total_count, Success: $success_count, Errors: $error_count"
    log "INFO" "=========================================="
    
    # Exit with error if any backups failed
    if [ "$error_count" -gt 0 ]; then
        exit 1
    fi
}

# Run main function
main
