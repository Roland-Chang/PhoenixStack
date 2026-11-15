#!/bin/bash
# backup-lxc.sh - Generalized LXC container backup script
# 
# Usage: backup-lxc.sh <VMID> <HOSTNAME> <RETENTION_DAYS>
# 
# Example: backup-lxc.sh 105 proxy01 7
# 
# Creates daily snapshots and automatically removes snapshots older than retention period
# 
# Requirements:
#   - Run as root on Proxmox node
#   - Snapshots are stored locally (not on external backup)
#   - Container must be running

set -euo pipefail

# Parameters
VMID="${1:-}"
HOSTNAME="${2:-}"
RETENTION_DAYS="${3:-7}"

# Validation
if [ -z "$VMID" ] || [ -z "$HOSTNAME" ]; then
    echo "Usage: backup-lxc.sh <VMID> <HOSTNAME> <RETENTION_DAYS>"
    echo "Example: backup-lxc.sh 105 proxy01 7"
    exit 1
fi

# Verify VMID is numeric
if ! [[ "$VMID" =~ ^[0-9]+$ ]]; then
    echo "ERROR: VMID must be numeric: $VMID"
    exit 1
fi

# Verify container exists
if ! qm status "$VMID" > /dev/null 2>&1; then
    echo "ERROR: Container VMID $VMID does not exist or is not accessible"
    exit 1
fi

# Configuration
SNAPSHOT_PREFIX="${HOSTNAME}-daily"
LOG_FILE="/var/log/proxmox-backup-${HOSTNAME}.log"

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
# Create snapshot
# ============================================================================
create_snapshot() {
    local snapshot_name="${SNAPSHOT_PREFIX}-$(date +%Y%m%d-%H%M%S)"
    
    log "INFO" "Creating snapshot for VMID $VMID ($HOSTNAME): $snapshot_name"
    
    if qm snapshot "$VMID" "$snapshot_name"; then
        log "INFO" "✅ Snapshot created successfully: $snapshot_name"
    else
        log "ERROR" "Failed to create snapshot for VMID $VMID"
        return 1
    fi
}

# ============================================================================
# Delete old snapshots
# ============================================================================
delete_old_snapshots() {
    log "INFO" "Checking for snapshots older than $RETENTION_DAYS days"
    
    local cutoff_epoch=$(date -d "-$RETENTION_DAYS days" +%s)
    local deleted_count=0
    
    # Get all snapshots for this container
    while IFS= read -r snapshot_line; do
        # Skip header and empty lines
        [[ -z "$snapshot_line" ]] && continue
        [[ "$snapshot_line" =~ ^Name ]] && continue
        
        # Parse snapshot name
        local snapshot_name=$(echo "$snapshot_line" | awk '{print $1}')
        
        # Skip if not our backup snapshot
        [[ ! "$snapshot_name" =~ ^${SNAPSHOT_PREFIX}- ]] && continue
        
        # Extract date from snapshot name (format: hostname-daily-YYYYMMDD-HHMMSS)
        local snapshot_date=$(echo "$snapshot_name" | grep -oE '[0-9]{8}' | head -1)
        
        if [ -z "$snapshot_date" ]; then
            log "WARN" "Could not extract date from snapshot: $snapshot_name"
            continue
        fi
        
        # Convert date to epoch
        local snapshot_epoch=$(date -d "$snapshot_date" +%s 2>/dev/null || echo 0)
        
        # Delete if older than retention period
        if [ "$snapshot_epoch" -lt "$cutoff_epoch" ]; then
            log "INFO" "Deleting old snapshot: $snapshot_name"
            if qm delsnapshot "$VMID" "$snapshot_name"; then
                log "INFO" "✅ Deleted: $snapshot_name"
                ((deleted_count++))
            else
                log "WARN" "Failed to delete snapshot: $snapshot_name"
            fi
        fi
    done < <(qm listsnapshot "$VMID" 2>/dev/null || echo "")
    
    if [ "$deleted_count" -eq 0 ]; then
        log "INFO" "No snapshots older than $RETENTION_DAYS days found"
    else
        log "INFO" "Deleted $deleted_count old snapshot(s)"
    fi
}

# ============================================================================
# Main execution
# ============================================================================
main() {
    log "INFO" "=========================================="
    log "INFO" "Backup job started for VMID $VMID ($HOSTNAME)"
    log "INFO" "Retention: $RETENTION_DAYS days"
    log "INFO" "=========================================="
    
    # Create new snapshot
    if ! create_snapshot; then
        log "ERROR" "Backup job failed: unable to create snapshot"
        exit 1
    fi
    
    # Delete old snapshots
    delete_old_snapshots
    
    log "INFO" "=========================================="
    log "INFO" "✅ Backup job completed successfully"
    log "INFO" "=========================================="
}

# Run main function
main
