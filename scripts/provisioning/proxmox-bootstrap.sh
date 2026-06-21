#!/bin/bash
# Proxmox VE 9.1.1+ Bootstrap Script - Phoenix Stack Edition
# Purpose: Standardize post-ISO configuration for new Proxmox nodes
# Version: 2025-11-25-v4
# Safe to re-run (idempotent where practical)
#
# CHANGELOG:
# v4 (2026-06-02): Fixed firewall config syntax errors and network VLAN logic
# v3 (2025-11-25): Initial Phoenix Stack bootstrap implementation
#
# Usage:
#   Interactive mode:  ./proxmox-bootstrap.sh
#   Automated mode:    ./proxmox-bootstrap.sh --auto
#   Config file mode:  ./proxmox-bootstrap.sh --config ./scripts/proxmox-configs/pve01.conf
#
# For automated deployments, create a config file or edit VARIABLES section below

cat <<'BOOTBANNER'
______ _                      _        _____ _             _    
| ___ \ |                    (_)      /  ___| |           | |   
| |_/ / |__   ___   ___ _ __  ___  __ \ `--.| |_ __ _  ___| | __
|  __/| '_ \ / _ \ / _ \ '_ \| \ \/ /  `--. \ __/ _` |/ __| |/ /
| |   | | | | (_) |  __/ | | | |>  <  /\__/ / || (_| | (__|   < 
\_|   |_| |_|\___/ \___|_| |_|_/_/\_\ \____/ \__\__,_|\___|_|\_\
                                                               
                                                               
BOOTBANNER

set -euo pipefail
IFS=$'\n\t'

# ============================================
# Constants & Lockfile
# ============================================
LOCKFILE="/var/lock/proxmox-bootstrap.lock"
DRY_RUN="no"
MAX_RETRIES=3
RETRY_SLEEP_BASE=2
DEFAULT_FILE_PERMS="600"
DEFAULT_DIR_PERMS="755"

############################################
# Early utility - needed before arg parsing
############################################
# Normalize boolean string to 'yes' or 'no'
normalize_bool(){
  local val="${1:-}"
  case "$val" in
    1|true|TRUE|yes|YES|y|Y) echo "yes" ;;
    *) echo "no" ;;
  esac
}

############################################
# ========== RUNTIME MODE =========
############################################
INTERACTIVE_MODE="yes"  # Will be set to "no" if --auto or --config provided
CONFIG_FILE=""
AUTO_REBOOT="no"        # Reboot automatically at end when enabled
AUTO_REBOOT_PROMPT="yes" # In automated mode, prompt for reboot if AUTO_REBOOT=no
SSH_IMPORT_GITHUB=""    # CLI/config: GitHub username for ssh-import-id-gh

# Parse command line arguments (supports --config FILE and --config=FILE)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto)
      INTERACTIVE_MODE="no"
      shift
      ;;
    --config)
      CONFIG_FILE="$2"
      INTERACTIVE_MODE="no"
      shift 2
      ;;
    --config=*)
      CONFIG_FILE="${1#--config=}"
      INTERACTIVE_MODE="no"
      shift
      ;;
    --dry-run)
      DRY_RUN="yes"
      shift
      ;;
    --dry-run=*)
      DRY_RUN="$(normalize_bool "${1#--dry-run=}")"
      shift
      ;;
    --github)
      # GitHub username to import SSH keys from
      SSH_IMPORT_GITHUB="$2"
      INTERACTIVE_MODE="no"
      shift 2
      ;;
    --github=*)
      SSH_IMPORT_GITHUB="${1#--github=}"
      INTERACTIVE_MODE="no"
      shift
      ;;
    --help|-h)
      echo "Proxmox Bootstrap Script - Phoenix Stack Edition"
      echo ""
      echo "Usage:"
      echo "  $0              Interactive mode (prompts for values)"
      echo "  $0 --auto       Automated mode (uses hardcoded defaults below)"
      echo "  $0 --config <file>  Use config file for values"
      echo "  $0 --dry-run[=yes|no]  Dry-run mode (default yes when provided)"
      echo "  $0 --reboot[=yes|no]  Reboot automatically at end (default: no)"
      echo "  $0 --github <user>    Import SSH keys from GitHub user (uses ssh-import-id-gh)"
      echo ""
      echo "For repeatable deployments, use --config mode."
      echo "For one-off installs, use interactive mode."
      exit 0
      ;;
    --reboot|--auto-reboot)
      AUTO_REBOOT="yes"
      shift
      ;;
    --reboot=*)
      AUTO_REBOOT="$(normalize_bool "${1#--reboot=}")"
      shift
      ;;
    *)
      # ignore unknown positional args
      shift
      ;;
  esac
done

############################################
# ========== VARIABLES (EDIT THESE) =========
############################################
# Core identity
NODE_HOSTNAME="pveXX"              # e.g. pve01, pve02
NODE_DOMAIN=""                     # DNS domain
FQDN=""                            # Computed at runtime via compute_fqdn()
TIMEZONE="America/Denver"          # Phoenix Stack timezone

# Site identification (for multi-site deployments)
SITE="primary"                     # primary or secondary

# Networking (adjust for your environment)
PRIMARY_IFACE="nic1"               # Physical NIC (verify with: ip link)
MGMT_BRIDGE="vmbr0"                # Bridge name
MGMT_VLAN=""                       # Leave empty for untagged, or set VLAN ID
MGMT_IP_CIDR="10.101.1.10/24"        # Node management IP (PHOENIX network)
MGMT_GW="10.101.1.254"               # Gateway (UDM SE at primary)
DNS_SERVERS="1.1.1.1 1.0.0.1"      # Space-separated (Pi-Holes when deployed)
ENABLE_IPV6="no"                   # yes/no

# CIFS / NAS mounts (optional)
ENABLE_CIFS="yes"                             # yes/no
SMB_CREDENTIALS_PATH="/root/.smbcredentials"  # Secure location
SMB_SERVER=""                                 # Unifi UNAS hostname
SMB_USERNAME=""                               # SMB username (set in config for automated mode)
SMB_PASSWORD=""                               # SMB password (set in config for automated mode). Alternatively, set SMB_PASSWORD_ENV or SMB_PASSWORD_FILE env vars.
CIFS_UID="100000"                             # Unprivileged LXC base UID (maps to root/UID 0 inside container)
CIFS_GID="101000"                             # Unprivileged LXC base GID (maps to svc_docker/GID 1000 inside container)
# CIFS_ENTRIES is an array; set in config file or leave empty for defaults
# Example entries that will be dynamically generated in configure_cifs if empty:
# "//${SMB_SERVER}/Backups/${NODE_HOSTNAME} /mnt/pve/cifs-backups cifs ..."
CIFS_ENTRIES=()

# Repository channel
USE_NO_SUBSCRIPTION_REPO="yes"     # yes to disable subscription nag + use no-sub repo

# Packages to ensure are present
EXTRA_APT_PACKAGES=(
  "bash-completion"
  "nano"          # Default editor
  "smartmontools"
  "net-tools"
  "curl"
  "wget"
  "jq"
  "fail2ban"
  "psmisc"
  "git"
  "lm-sensors"
  "ethtool"
  "iotop"
  "htop"
  "ncdu"
  "tmux"
  "cifs-utils"
  "ssh-import-id"
)

# Kernel / performance tuning
SYSCTL_TUNE=(
  "vm.swappiness=10"
  "fs.inotify.max_user_watches=524288"
  "fs.inotify.max_user_instances=512"
  "net.core.somaxconn=1024"
  "net.ipv4.ip_forward=1"
  "net.ipv4.conf.all.send_redirects=0"
  "net.ipv4.conf.default.send_redirects=0"
  "net.bridge.bridge-nf-call-iptables=1"
)

# SSH hardening
SSH_PORT="22"                      # Default port (change if necessary)
DISABLE_ROOT_PASSWORD="yes"        # Disable password auth for root
SSH_PUBLIC_KEY=""                  # Add your public key here for key-based auth
SSH_IMPORT_GITHUB=""               # Optional GitHub username to import keys via ssh-import-id-gh

# Proxmox firewall defaults
ENABLE_PVE_FIREWALL="yes"          # yes/no
FIREWALL_LOG_LEVEL="info"          # nolog, emerg, alert, crit, err, warning, notice, info, debug

# Disable subscription popup
DISABLE_SUBSCRIPTION_NAG="yes"     # yes/no

# ...existing code...

# CPU vulnerability mitigations (optional)
# When enabled, appends kernel cmdline parameters to mitigate/suppress L1TF warning
ENABLE_L1TF_FLUSH_NOWARN="yes"     # yes/no (default: yes)
 
# CIFS share auto-provisioning (requires smbclient)
SMB_AUTOCREATE_DIRS="no"           # yes/no: create missing subdirs on shares
SMB_DOMAIN=""                      # optional domain for SMB auth

############################################
# Utility functions - Logging, prompting, file backup, command execution wrappers
############################################
log(){ printf "[%s] %s\n" "$1" "$2"; }
info(){ log INFO "$1"; }
warn(){ log WARN "$1"; }
error(){ log ERROR "$1" >&2; }
success(){ log SUCCESS "$1"; }

# Display colored banner
# Compute FQDN from NODE_HOSTNAME and NODE_DOMAIN
compute_fqdn(){
  if [[ -n "${NODE_DOMAIN:-}" ]]; then
    FQDN="${NODE_HOSTNAME}.${NODE_DOMAIN}"
  else
    FQDN="${NODE_HOSTNAME}"
  fi
}

# Prompt for input with default value
prompt_with_default(){
  local var_name="$1"
  local prompt_text="$2"
  local default_value="$3"
  local current_value="${!var_name}"
  local input
  
  if [[ "$INTERACTIVE_MODE" == "no" ]]; then
    # Use current value (from defaults or config file)
    return
  fi
  
  # Show current/default value
  if [[ -n "$current_value" ]]; then
    read -r -p "$prompt_text [$current_value]: " input
    if [[ -n "$input" ]]; then
      printf -v "$var_name" '%s' "$input"
    fi
  else
    read -r -p "$prompt_text [$default_value]: " input
    printf -v "$var_name" '%s' "${input:-$default_value}"
  fi
}

# Simple retry wrapper: runs a command up to N times with exponential backoff
retry_cmd(){
  local -r max_attempts=${1:-3}
  shift || true
  local -i attempt=1
  local -i sleep_for=${RETRY_SLEEP_BASE:-2}
  until "${@}"; do
    if (( attempt >= max_attempts )); then
      return 1
    fi
    sleep "$sleep_for"
    attempt=$(( attempt + 1 ))
    sleep_for=$(( sleep_for * 2 ))
  done
  return 0
}

# Acquire simple lockfile to avoid concurrent bootstrap runs
acquire_lock(){
  if [[ -f "$LOCKFILE" ]]; then
    local pid; pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
    if [[ -n "$pid" && -d "/proc/$pid" ]]; then
      error "Another bootstrap appears to be running (PID $pid). Exiting."
      exit 1
    else
      warn "Stale lockfile found, removing"
      rm -f "$LOCKFILE"
    fi
  fi
  echo $$ > "$LOCKFILE"
  info "Acquired lockfile $LOCKFILE"
}

release_lock(){
  rm -f "$LOCKFILE" 2>/dev/null || true
}

# Prompt for yes/no with default
prompt_yes_no(){
  local var_name="$1"
  local prompt_text="$2"
  local default_value="$3"
  
  if [[ "$INTERACTIVE_MODE" == "no" ]]; then
    return
  fi
  
  local input
  while true; do
    read -r -p "$prompt_text (yes/no) [$default_value]: " input
    input="${input:-$default_value}"
    case "$input" in
      yes|y|Y|YES) printf -v "$var_name" '%s' 'yes'; break;;
      no|n|N|NO) printf -v "$var_name" '%s' 'no'; break;;
      *) echo "Please answer yes or no";;
    esac
  done
}

# Load configuration from file
load_config(){
  local config="$1"
  if [[ ! -f "$config" ]]; then
    error "Config file not found: $config"
    exit 1
  fi
  
  info "Loading configuration from $config"
  # shellcheck source=/dev/null
  source "$config"
  # Recalculate derived variables after loading config
  compute_fqdn
  success "Configuration loaded"
}

# Interactive configuration wizard - runs only when INTERACTIVE_MODE=yes
# Prompts user for all configuration values and provides confirmation before proceeding
interactive_config(){
  echo ""
  echo "========================================="
  echo "Phoenix Stack - Proxmox Bootstrap Wizard"
  echo "========================================="
  echo ""
  echo "Press Enter to accept defaults shown in [brackets]"
  echo ""
  
  # Node identity
  echo "--- Node Identity ---"
  prompt_with_default "NODE_HOSTNAME" "Node hostname (e.g., pve01, pve02)" "$NODE_HOSTNAME"
  prompt_with_default "NODE_DOMAIN" "DNS domain" "$NODE_DOMAIN"
  compute_fqdn
  info "FQDN will be: $FQDN"
  
  prompt_with_default "TIMEZONE" "Timezone" "$TIMEZONE"
  
  # Site identification
  echo ""
  echo "--- Site Configuration ---"
  while true; do
    read -r -p "Deployment site (primary/secondary) [$SITE]: " input
    input="${input:-$SITE}"
    case "$input" in
      primary|secondary) SITE="$input"; break;;
      *) echo "Please enter 'primary' or 'secondary'";;
    esac
  done
  
  # Networking
  echo ""
  echo "--- Network Configuration ---"
  echo "Available interfaces:"
  ip -br link | grep -v "lo" | awk '{print "  " $1 " - " $3}'
  echo ""
  
  prompt_with_default "PRIMARY_IFACE" "Primary network interface" "$PRIMARY_IFACE"
  prompt_with_default "MGMT_BRIDGE" "Management bridge name" "$MGMT_BRIDGE"
  prompt_with_default "MGMT_IP_CIDR" "Management IP (CIDR notation)" "$MGMT_IP_CIDR"
  prompt_with_default "MGMT_GW" "Default gateway" "$MGMT_GW"
  prompt_with_default "DNS_SERVERS" "DNS servers (space-separated)" "$DNS_SERVERS"
  prompt_yes_no "ENABLE_IPV6" "Enable IPv6" "$ENABLE_IPV6"
  
  # CIFS/NAS
  echo ""
  echo "--- Storage Configuration ---"
  prompt_yes_no "ENABLE_CIFS" "Configure CIFS/SMB mounts" "$ENABLE_CIFS"
  
  if [[ "$ENABLE_CIFS" == "yes" ]]; then
    prompt_with_default "SMB_SERVER" "SMB/CIFS server hostname" "$SMB_SERVER"
    prompt_with_default "SMB_CREDENTIALS_PATH" "Path to SMB credentials file" "$SMB_CREDENTIALS_PATH"
    
    if [[ ! -f "$SMB_CREDENTIALS_PATH" ]]; then
      warn "Credentials file doesn't exist yet"
      read -r -p "Create it now? (yes/no) [no]: " create_creds
      if [[ "$create_creds" == "yes" ]]; then
        read -r -p "SMB username: " smb_user
        read -r -s -p "SMB password: " smb_pass
        echo ""
        mkdir -p "$(dirname "$SMB_CREDENTIALS_PATH")"
        {
          echo "username=$smb_user"
          echo "password=$smb_pass"
        } > "$SMB_CREDENTIALS_PATH"
        chmod 600 "$SMB_CREDENTIALS_PATH"
        success "Credentials file created"
      fi
    fi
  fi
  
  # Repository configuration
  echo ""
  echo "--- Repository Configuration ---"
  prompt_yes_no "USE_NO_SUBSCRIPTION_REPO" "Use no-subscription repository (disables nag)" "$USE_NO_SUBSCRIPTION_REPO"
  prompt_yes_no "DISABLE_SUBSCRIPTION_NAG" "Disable subscription popup in UI" "$DISABLE_SUBSCRIPTION_NAG"
  
  # SSH Configuration
  echo ""
  echo "--- SSH Security ---"
  prompt_with_default "SSH_PORT" "SSH port" "$SSH_PORT"
  prompt_yes_no "DISABLE_ROOT_PASSWORD" "Disable root password login (require SSH keys)" "$DISABLE_ROOT_PASSWORD"
  
  if [[ "$DISABLE_ROOT_PASSWORD" == "yes" && -z "$SSH_PUBLIC_KEY" ]]; then
    warn "You should add an SSH public key to avoid lockout!"
    read -r -p "Paste your SSH public key (or leave blank to skip): " key_input
    SSH_PUBLIC_KEY="$key_input"
  fi
  
  # Firewall
  echo ""
  echo "--- Firewall ---"
  prompt_yes_no "ENABLE_PVE_FIREWALL" "Enable Proxmox firewall" "$ENABLE_PVE_FIREWALL"
  
  
  # Confirmation
  echo ""
  echo "========================================="
  echo "Configuration Summary:"
  echo "========================================="
  echo "  Hostname: $FQDN"
  echo "  Site: $SITE"
  echo "  Management IP: $MGMT_IP_CIDR"
  echo "  Gateway: $MGMT_GW"
  echo "  DNS: $DNS_SERVERS"
  echo "  CIFS Mounts: $ENABLE_CIFS"
  echo "  SSH Port: $SSH_PORT"
  echo "  Root Password Login: $([ "$DISABLE_ROOT_PASSWORD" == "yes" ] && echo "Disabled" || echo "Enabled")"
  echo "  Firewall: $ENABLE_PVE_FIREWALL"
  echo "========================================="
  echo ""
  
  read -r -p "Proceed with this configuration? (yes/no) [no]: " proceed
  if [[ "$proceed" != "yes" ]]; then
    error "Bootstrap cancelled by user"
    exit 0
  fi
  
  echo ""
  info "Starting bootstrap process..."
  sleep 2
}

require_root(){
  if [[ $EUID -ne 0 ]]; then
    error "Must run as root"; exit 1;
  fi
}

check_proxmox(){
  if ! command -v pveversion >/dev/null 2>&1; then
    error "This system does not appear to be Proxmox VE"; exit 1;
  fi
  info "Detected Proxmox version: $(pveversion | head -n1)"
}

file_has_line(){ local f="$1"; local l="$2"; grep -Fqx "$l" "$f" 2>/dev/null || return 1; }
append_if_missing(){ local f="$1"; shift; for line in "$@"; do if ! file_has_line "$f" "$line"; then echo "$line" >> "$f"; fi; done }

backup_file(){ 
  local f="$1"
  if [[ "$DRY_RUN" == "yes" ]]; then
    if [[ -f "$f" && ! -f "${f}.bootstrap.bak" ]]; then
      info "[DRY-RUN] Would back up $f to ${f}.bootstrap.bak"
    fi
    return
  fi
  if [[ -f "$f" && ! -f "${f}.bootstrap.bak" ]]; then 
    cp "$f" "${f}.bootstrap.bak"
    info "Backed up $f to ${f}.bootstrap.bak"
  fi
}

# Execute a command, respecting DRY_RUN
# Handles environment variable assignments (VAR=value cmd) correctly
run_cmd(){
  if [[ "$DRY_RUN" == "yes" ]]; then
    local cmd_str=""
    local a
    for a in "$@"; do
      # Detect environment variable assignments (contains = but not a path)
      if [[ "$a" =~ ^[A-Z_][A-Z0-9_]*= ]]; then
        cmd_str+="$a "
      else
        cmd_str+="$(printf "%q " "$a")"
      fi
    done
    info "[DRY-RUN] ${cmd_str::-1}"
    return 0
  fi
  "$@"
}

# Create directory with secure permissions, respecting DRY_RUN
# Usage: create_secure_dir DIR [PERMS] [OWNER:GROUP]
create_secure_dir(){
  local dir="$1"
  local perms="${2:-$DEFAULT_DIR_PERMS}"
  local owner="${3:-root:root}"
  if [[ -d "$dir" ]]; then
    return 0
  fi
  if [[ "$DRY_RUN" == "yes" ]]; then
    info "[DRY-RUN] Would create directory $dir with perms $perms"
    return 0
  fi
  mkdir -p "$dir"
  chmod "$perms" "$dir" || true
  chown "$owner" "$dir" || true
}

############################################
# Host identity & basic configuration
############################################
# Validate configuration for required fields and safe defaults
validate_config(){
  info "Validating configuration"
  local errors=0

  # Basic identity
  if [[ -z "${NODE_HOSTNAME:-}" || "${NODE_HOSTNAME}" == "pveXX" ]]; then
    error "NODE_HOSTNAME is unset or left as placeholder (NODE_HOSTNAME=\"${NODE_HOSTNAME:-}\")."
    errors=$((errors+1))
  fi

  # Networking
  if [[ -z "${MGMT_IP_CIDR:-}" ]]; then
    error "MGMT_IP_CIDR must be set (e.g., 10.101.1.101/24)."
    errors=$((errors+1))
  fi
  if [[ -z "${MGMT_GW:-}" ]]; then
    error "MGMT_GW (gateway) must be set."
    errors=$((errors+1))
  fi
  if [[ -z "${PRIMARY_IFACE:-}" ]]; then
    error "PRIMARY_IFACE is not set. Provide the primary network interface name."
    errors=$((errors+1))
  fi

  # CIFS requirements
  if [[ "${ENABLE_CIFS:-no}" == "yes" ]]; then
    if [[ -z "${SMB_SERVER:-}" ]]; then
      error "ENABLE_CIFS=yes but SMB_SERVER is not set."
      errors=$((errors+1))
    fi
    if [[ ! -f "${SMB_CREDENTIALS_PATH:-}" && -z "${SMB_USERNAME:-}" ]]; then
      error "CIFS enabled but no credentials file found and SMB_USERNAME not provided."
      errors=$((errors+1))
    fi
  fi

  # SSH safety: avoid locking out root
  if [[ "${DISABLE_ROOT_PASSWORD:-no}" == "yes" ]]; then
    local have_key="no"
    if [[ -n "${SSH_PUBLIC_KEY:-}" ]]; then have_key="yes"; fi
    if [[ -n "${SSH_IMPORT_GITHUB:-}" ]]; then have_key="yes"; fi
    if [[ -f /root/.ssh/authorized_keys && -s /root/.ssh/authorized_keys ]]; then have_key="yes"; fi
    if [[ "$have_key" != "yes" ]]; then
      error "DISABLE_ROOT_PASSWORD=yes but no SSH public key, GitHub import, or existing /root/.ssh/authorized_keys found. This will lock you out."
      errors=$((errors+1))
    fi
  fi

  if [[ $errors -gt 0 ]]; then
    if [[ "$INTERACTIVE_MODE" == "yes" ]]; then
      warn "Configuration validation found $errors issue(s)."
      echo "Please fix the issues in your config or proceed interactively."
      read -r -p "Continue anyway? (yes/no) [no]: " cont
      cont=${cont:-no}
      if [[ "$cont" != "yes" ]]; then
        error "Aborting per user request due to validation failures."
        exit 1
      fi
    else
      error "Configuration validation failed with $errors issue(s). Aborting in automated mode."
      exit 1
    fi
  else
    success "Configuration validation passed"
  fi
}

configure_hostname(){
  info "Configuring hostname to ${FQDN}"
  local current
  current=$(hostname -f 2>/dev/null || hostname)
  if [[ "$current" != "$FQDN" ]]; then
    if [[ "$DRY_RUN" == "yes" ]]; then
      info "[DRY-RUN] Would set hostname to $NODE_HOSTNAME and update /etc/hosts"
    else
      echo "$NODE_HOSTNAME" > /etc/hostname
      backup_file /etc/hosts
      # Remove old entries for this IP
      local ip
      ip=$(echo "$MGMT_IP_CIDR" | cut -d/ -f1)
      sed -i "/^${ip}[[:space:]]/d" /etc/hosts
      # Add new entry
      echo "${ip} ${FQDN} ${NODE_HOSTNAME}" >> /etc/hosts
      hostname "$NODE_HOSTNAME"
    fi
    success "Hostname set to $FQDN"
  else
    info "Hostname already set to $FQDN"
  fi
}

configure_timezone(){
  info "Setting timezone to $TIMEZONE"
  run_cmd timedatectl set-timezone "$TIMEZONE"
  success "Timezone set to $TIMEZONE"
}

############################################
# Networking (basic bridge + static IP)
############################################
configure_network(){
  info "Configuring network interfaces"
  
  # Validate required network parameters
  if [[ -z "$MGMT_IP_CIDR" || -z "$MGMT_GW" ]]; then
    error "Network configuration incomplete: MGMT_IP_CIDR and MGMT_GW are required"
    return 1
  fi
  
  # Idempotency check: skip if bridge already has the target IP configured
  local mgmt_ip
  mgmt_ip=$(echo "$MGMT_IP_CIDR" | cut -d/ -f1)
  if ip -4 addr show dev "$MGMT_BRIDGE" 2>/dev/null | grep -q "$mgmt_ip"; then
    info "Network already configured: $MGMT_BRIDGE has IP $mgmt_ip"
    return 0
  fi
  
  # Ensure PRIMARY_IFACE exists; attempt auto-detect if missing
  if ! ip link show "$PRIMARY_IFACE" >/dev/null 2>&1; then
    warn "Primary interface $PRIMARY_IFACE not found; attempting auto-detect"
    # Prefer interface used for default route
    local detected
    detected=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1);exit}}}') || true
    if [[ -n "$detected" && "$detected" != "lo" ]]; then
      info "Auto-detected primary interface: $detected"
      PRIMARY_IFACE="$detected"
    else
      # Fallback: choose first non-loopback interface that is up
      detected=$(ip -br link | awk '$2=="UP"{print $1; exit}') || true
      if [[ -n "$detected" ]]; then
        info "Falling back to first UP interface: $detected"
        PRIMARY_IFACE="$detected"
      else
        error "Could not auto-detect any usable network interface"
        info "Available interfaces:"
        ip -br link | grep -v "lo" | awk '{print "  - " $1}'
        exit 1
      fi
    fi
  fi
  
  local iface_file="/etc/network/interfaces"
  backup_file "$iface_file"
  
  if [[ "$DRY_RUN" == "yes" ]]; then
    info "[DRY-RUN] Would write $iface_file with management bridge (native/untagged) + optional workload VLAN bridge"
  else
cat > "$iface_file" <<EOF
# Proxmox VE Network Configuration - Phoenix Stack
# Generated by proxmox-bootstrap.sh on $(date)
# NOTE: Management bridge uses native (untagged) VLAN. Workload VLANs use tagged subinterfaces.

auto lo
iface lo inet loopback

# Primary physical interface
auto $PRIMARY_IFACE
iface $PRIMARY_IFACE inet manual

# Management bridge (native/untagged VLAN)
# Assumes MGMT_VLAN is configured as Native VLAN on switch
auto $MGMT_BRIDGE
iface $MGMT_BRIDGE inet static
    address $MGMT_IP_CIDR
    gateway $MGMT_GW
    bridge-ports $PRIMARY_IFACE
    bridge-stp off
    bridge-fd 0
EOF

  if [[ "$ENABLE_IPV6" == "yes" ]]; then
    cat >> "$iface_file" <<EOF
    post-up sysctl -w net.ipv6.conf.all.forwarding=1
EOF
  fi
  
  # Optional: workload bridge on separate tagged VLAN
  # If you need a second bridge (e.g., vmbr1 for workload), configure as:
  # auto nic2.100
  # iface nic2.100 inet manual
  # auto vmbr1
  # iface vmbr1 inet manual
  #     bridge-ports nic2.100
  #     bridge-stp off
  #     bridge-fd 0
  
  cat >> "$iface_file" <<EOF

# Unconfigured secondary interfaces
iface nic0 inet manual
iface nic1 inet manual
iface nic3 inet manual

source /etc/network/interfaces.d/*
EOF
  fi
}

configure_dns(){
  info "Configuring DNS resolvers"
  
  # Check if resolv.conf is a symlink (systemd-resolved)
  if [[ -L /etc/resolv.conf ]]; then
    if [[ "$DRY_RUN" == "yes" ]]; then
      warn "[DRY-RUN] Would remove /etc/resolv.conf symlink"
    else
      warn "/etc/resolv.conf is a symlink (systemd-resolved). Removing link."
      rm -f /etc/resolv.conf
    fi
  fi
  
  backup_file /etc/resolv.conf
  if [[ "$DRY_RUN" == "yes" ]]; then
    info "[DRY-RUN] Would write /etc/resolv.conf with DNS: $DNS_SERVERS"
  else
    {
      echo "# Generated by proxmox-bootstrap.sh"
      echo "search $NODE_DOMAIN"
      for d in $DNS_SERVERS; do echo "nameserver $d"; done
    } > /etc/resolv.conf
  fi
  
  success "DNS resolvers configured: $DNS_SERVERS"
}

############################################
# Repositories & updates
############################################
configure_repos(){
  info "Configuring Proxmox repositories"
  # Detect Debian suite (VERSION_CODENAME) to select correct PVE repo suite
  local SUITE=""
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    SUITE="${VERSION_CODENAME}"
  fi
  # Fallback: try lsb_release, else default to bookworm
  if [[ -z "$SUITE" ]]; then
    SUITE=$(lsb_release -sc 2>/dev/null || echo "bookworm")
  fi
  # Normalize expected values only (bookworm/trixie); default to bookworm
  case "$SUITE" in
    trixie|bookworm) ;; 
    *) SUITE="bookworm" ;; 
  esac
  
  # ============================================
  # Repository Configuration
  # ============================================
  
  # Disable enterprise repositories by renaming .sources files
  # This prevents apt from attempting to read invalid/inaccessible enterprise repos
  local enterprise_files=(
    "/etc/apt/sources.list.d/pve-enterprise.sources"
    "/etc/apt/sources.list.d/ceph.sources"
  )
  
  for ent_file in "${enterprise_files[@]}"; do
    if [[ -f "$ent_file" ]]; then
      if [[ "$DRY_RUN" == "yes" ]]; then
        info "[DRY-RUN] Would disable $ent_file by renaming to $ent_file.disabled"
      else
        backup_file "$ent_file"
        mv "$ent_file" "$ent_file.disabled"
        info "Disabled $ent_file by renaming to $ent_file.disabled"
      fi
    fi
  done
  
  # Ensure no-subscription repo is present and correctly targeted
  
  if [[ "$USE_NO_SUBSCRIPTION_REPO" == "yes" ]]; then
    local no_sub_file="/etc/apt/sources.list.d/pve-no-subscription.list"
    if [[ ! -f "$no_sub_file" ]] || ! grep -q "pve-no-subscription" "$no_sub_file" 2>/dev/null; then
      if [[ "$DRY_RUN" == "yes" ]]; then
        info "[DRY-RUN] Would create $no_sub_file for suite $SUITE"
      else
        echo "deb http://download.proxmox.com/debian/pve $SUITE pve-no-subscription" > "$no_sub_file"
        info "Enabled no-subscription repository"
      fi
    fi
    # Ensure line uses detected suite
    if [[ -f "$no_sub_file" ]] && grep -q "download.proxmox.com" "$no_sub_file" 2>/dev/null; then
      if [[ "$DRY_RUN" == "yes" ]]; then
        info "[DRY-RUN] Would normalize suite in $no_sub_file to $SUITE"
      else
        sed -i "s|deb http://download\\.proxmox\\.com/debian/pve .* pve-no-subscription|deb http://download.proxmox.com/debian/pve $SUITE pve-no-subscription|" "$no_sub_file"
      fi
    fi
  fi

  info "Updating package lists"
  retry_cmd "$MAX_RETRIES" run_cmd apt-get clean >/dev/null 2>&1 || true
  if retry_cmd "$MAX_RETRIES" run_cmd apt-get update -y; then
    success "Repository configuration complete (apt-get update successful)"
  else
    error "apt-get update failed; check network connectivity and repository configuration"
    return 1
  fi
}

install_packages(){
  info "Installing baseline packages"
  if [[ "$DRY_RUN" == "yes" ]]; then
    info "[DRY-RUN] DEBIAN_FRONTEND=noninteractive apt-get install -y ${EXTRA_APT_PACKAGES[*]}"
    success "Packages installed successfully"
    return 0
  fi
  if ! retry_cmd "$MAX_RETRIES" env DEBIAN_FRONTEND=noninteractive apt-get install -y "${EXTRA_APT_PACKAGES[@]}"; then
    error "Package install failed after retries"
    return 1
  fi
  success "Packages installed successfully"
}

upgrade_system(){
  info "Upgrading system packages (this may take several minutes)..."
  if [[ "$DRY_RUN" == "yes" ]]; then
    info "[DRY-RUN] DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y"
    success "System upgrade complete"
    return 0
  fi
  if ! retry_cmd "$MAX_RETRIES" env DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y; then
    warn "System upgrade had issues after retries"
  fi
  success "System upgrade complete"
}

############################################
# System tuning
############################################
apply_sysctl(){
  info "Applying sysctl tunings"
  local f="/etc/sysctl.d/99-proxmox-bootstrap.conf"
  if [[ "$DRY_RUN" == "yes" ]]; then
    info "[DRY-RUN] Would write $f with sysctl tunings and reload"
  else
    {
      echo "# Proxmox Bootstrap - Phoenix Stack"
      echo "# Generated on $(date)"
      for kv in "${SYSCTL_TUNE[@]}"; do 
        echo "$kv"
      done
    } > "$f"
    run_cmd sysctl --system >/dev/null 2>&1 || warn "sysctl reload returned non-zero"
  fi
  success "Sysctl tunings applied"
}

############################################
# SSH hardening
############################################
configure_ssh(){
  info "Configuring SSH security"
  local sshd_config="/etc/ssh/sshd_config"
  backup_file "$sshd_config"

  import_github_keys(){
    local user="$1"
    if command -v ssh-import-id-gh >/dev/null 2>&1; then
      ssh-import-id-gh "$user" >/dev/null 2>&1
      return $?
    fi
    if command -v ssh-import-id >/dev/null 2>&1; then
      ssh-import-id "gh:${user}" >/dev/null 2>&1
      return $?
    fi
    return 127
  }
  
  # If no SSH_PUBLIC_KEY is set, support importing keys from GitHub
  if [[ -z "$SSH_PUBLIC_KEY" ]]; then
    # Ensure ssh-import-id tooling exists (already part of EXTRA_APT_PACKAGES, but double-check)
    if ! command -v ssh-import-id >/dev/null 2>&1 && ! command -v ssh-import-id-gh >/dev/null 2>&1; then
      info "Installing ssh-import-id"
      retry_cmd "$MAX_RETRIES" run_cmd apt-get install -y ssh-import-id || warn "Failed to install ssh-import-id"
    fi
    # Determine GitHub username
    local gh_user="${SSH_IMPORT_GITHUB}"
    if [[ -z "$gh_user" ]]; then
      # Prompt whenever we have a TTY and keys are required, even in --config mode.
      if [[ -t 0 && "$DISABLE_ROOT_PASSWORD" == "yes" ]]; then
        echo ""
        read -r -p "GitHub username to import SSH keys (blank to skip): " gh_user
      elif [[ "$INTERACTIVE_MODE" == "yes" ]]; then
        echo ""
        read -r -p "GitHub username to import SSH keys (blank to skip): " gh_user
      fi
    fi
    if [[ -n "$gh_user" ]]; then
      if [[ "$DRY_RUN" == "yes" ]]; then
        info "[DRY-RUN] Would import SSH keys from GitHub user '$gh_user'"
      else
        mkdir -p /root/.ssh && chmod 700 /root/.ssh
        # Try provider-specific import first, then generic ssh-import-id fallback.
        if import_github_keys "$gh_user"; then
          info "Imported SSH keys from GitHub user '$gh_user'"
        else
          warn "Failed to import SSH keys from GitHub user '$gh_user'"
        fi
      fi
    fi
  fi

  # Ensure SSH authorized keys exists (avoid lockout)
  # Always add the key from config if provided, even if other keys exist
  if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    # Basic validation: check if key looks valid (starts with ssh-)
    if [[ "$SSH_PUBLIC_KEY" =~ ^ssh-(rsa|ed25519|ecdsa|dss) ]]; then
      if [[ "$DRY_RUN" == "yes" ]]; then
        info "[DRY-RUN] Would add provided SSH public key to /root/.ssh/authorized_keys"
      else
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        # Check if this exact key already exists to avoid duplicates
        if ! grep -qF "$SSH_PUBLIC_KEY" /root/.ssh/authorized_keys 2>/dev/null; then
          echo "$SSH_PUBLIC_KEY" >> /root/.ssh/authorized_keys
          chmod 600 /root/.ssh/authorized_keys
          info "SSH public key added to /root/.ssh/authorized_keys"
        else
          info "SSH public key already present in authorized_keys"
        fi
      fi
    else
      warn "Provided SSH_PUBLIC_KEY doesn't appear to be a valid SSH public key (should start with ssh-*)"
      warn "Will NOT disable password auth to prevent lockout"
      DISABLE_ROOT_PASSWORD="no"
    fi
  fi
  
  # Check if we have any keys for password auth decision
  if [[ "$DISABLE_ROOT_PASSWORD" == "yes" ]]; then
    if [[ ! -f /root/.ssh/authorized_keys || ! -s /root/.ssh/authorized_keys ]]; then
      if [[ "$INTERACTIVE_MODE" == "yes" ]]; then
        warn "No root SSH keys found. You can paste one now to avoid lockout."
        read -r -p "Paste SSH public key (or leave blank to skip): " pasted_key
        if [[ -n "$pasted_key" ]]; then
          if [[ "$DRY_RUN" == "yes" ]]; then
            info "[DRY-RUN] Would add pasted SSH key to /root/.ssh/authorized_keys"
          else
            mkdir -p /root/.ssh
            chmod 700 /root/.ssh
            echo "$pasted_key" >> /root/.ssh/authorized_keys
            chmod 600 /root/.ssh/authorized_keys
            info "SSH public key added to /root/.ssh/authorized_keys"
          fi
        else
          warn "No key provided; skipping automatic disabling of root password login"
          DISABLE_ROOT_PASSWORD="no"
        fi
      else
        warn "Automated mode: no root SSH keys present. Will NOT disable password auth to avoid lockout"
        DISABLE_ROOT_PASSWORD="no"
      fi
    else
      info "Found authorized_keys with $(wc -l < /root/.ssh/authorized_keys) key(s), safe to disable password auth"
    fi
  fi

  # Disable root password login if requested (after ensuring keys present)
  if [[ "$DISABLE_ROOT_PASSWORD" == "yes" ]]; then
    if [[ "$DRY_RUN" == "yes" ]]; then
      info "[DRY-RUN] Would set PermitRootLogin prohibit-password in $sshd_config"
    else
      sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' "$sshd_config"
    fi
    info "Root password login disabled (keys only)"
  fi
  
  # Change SSH port if not default
  if [[ "$SSH_PORT" != "22" ]]; then
    if [[ "$DRY_RUN" == "yes" ]]; then
      info "[DRY-RUN] Would set SSH Port $SSH_PORT in $sshd_config"
    else
      sed -i "s/^#*Port.*/Port $SSH_PORT/" "$sshd_config"
    fi
    info "SSH port changed to $SSH_PORT"
  fi
  
  # Consolidate SSH hardening options into single sed pass
  if [[ "$DRY_RUN" == "yes" ]]; then
    info "[DRY-RUN] Would harden SSH options in $sshd_config"
  else
    local password_auth_value="yes"
    if [[ "$DISABLE_ROOT_PASSWORD" == "yes" ]]; then
      password_auth_value="no"
    fi
    sed -i -e "s/^#*PasswordAuthentication.*/PasswordAuthentication ${password_auth_value}/" \
            -e 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' \
            -e 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' \
            -e 's/^#*X11Forwarding.*/X11Forwarding no/' \
            "$sshd_config"
  fi
  
  # Validate SSH configuration before restarting to prevent lockouts
  if [[ "$DRY_RUN" != "yes" ]]; then
    info "Validating SSH configuration before restart..."
    if ! sshd -t 2>/dev/null; then
      error "SSH configuration validation failed! Not restarting sshd to prevent lockout."
      error "Please fix /etc/ssh/sshd_config manually and run: systemctl restart sshd"
      return 1
    fi
    
    # Final safety check: verify authorized_keys exists if password auth disabled
    if grep -q '^PasswordAuthentication no' "$sshd_config" && 
       grep -q '^PermitRootLogin prohibit-password' "$sshd_config"; then
      if [[ ! -f /root/.ssh/authorized_keys || ! -s /root/.ssh/authorized_keys ]]; then
        error "CRITICAL: Password auth disabled but no SSH keys found!"
        error "Reverting PasswordAuthentication to yes to prevent lockout"
        sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' "$sshd_config"
      fi
    fi
    
    info "SSH configuration valid. Restarting sshd..."
  fi
  
  if ! retry_cmd "$MAX_RETRIES" run_cmd systemctl restart sshd; then
    error "SSH restart failed after retries"
    error "SSH may be in a broken state. Access via console and check: systemctl status sshd"
    return 1
  fi
  success "SSH hardening applied and service restarted"
}

############################################
# Subscription popup suppression
############################################
remove_subscription_nag(){
  if [[ "$DISABLE_SUBSCRIPTION_NAG" != "yes" ]]; then return; fi
  
  info "Disabling subscription nag in UI"
  local js="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
  
  if [[ ! -f "$js" ]]; then
    warn "UI toolkit file not found; skipping subscription patch"
    return
  fi
  
  backup_file "$js"
  
  # Check if already patched (look for the fixed condition)
  if grep -qE "(=== 'active'|== 'Active')" "$js" 2>/dev/null; then
    info "Subscription nag already patched"
    success "Subscription nag disabled"
    return
  fi
  
  # Verify the nag dialog exists before patching
  if ! grep -q "No valid subscription" "$js" 2>/dev/null; then
    warn "Subscription nag code not found; UI may have changed"
    return
  fi
  
  if [[ "$DRY_RUN" == "yes" ]]; then
    info "[DRY-RUN] Would disable subscription status checks in $js"
    success "Subscription nag disabled"
    return
  fi
  
  # Primary fix: Change !== to === in the subscription check
  # This converts the condition from "show nag if NOT active" to "show nag if IS active"
  # Since no-subscription systems are never 'active', the nag never shows
  if sed -i "s/res\.data\.status\.toLowerCase() !== 'active'/res.data.status.toLowerCase() === 'active'/g" "$js"; then
    if grep -q "res\.data\.status\.toLowerCase() === 'active'" "$js" 2>/dev/null; then
      success "Subscription nag disabled"
      retry_cmd "$MAX_RETRIES" run_cmd systemctl restart pveproxy || warn "pveproxy restart failed"
      return
    fi
  fi
  
  # Fallback: Try the uppercase variant (older Proxmox versions)
  if sed -i "s/if (data\.status !== 'Active')/if (data.status === 'Active')/g" "$js"; then
    if grep -q "if (data\.status === 'Active')" "$js" 2>/dev/null; then
      success "Subscription nag disabled (uppercase variant)"
      retry_cmd "$MAX_RETRIES" run_cmd systemctl restart pveproxy || warn "pveproxy restart failed"
      return
    fi
  fi
  
  # If no methods worked, show diagnostic info
  warn "Could not apply subscription nag patch; checking file content..."
  info "Searching for lines near 'No valid subscription':"
  grep -B 5 -A 2 "No valid subscription" "$js" | head -20 || warn "Could not find context"
  error "Unable to find/patch the subscription status check. File may have changed."
}

############################################
# Firewall
############################################
configure_firewall(){
  if [[ "$ENABLE_PVE_FIREWALL" != "yes" ]]; then return; fi
  
  info "Configuring Proxmox firewall"
  local ssh_rule_22="IN ACCEPT -p tcp -dport 22"
  local ssh_rule_configured="IN ACCEPT -p tcp -dport $SSH_PORT"
  
  # Enable firewall but set to accept by default for safety
  if [[ "$DRY_RUN" == "yes" ]]; then
    info "[DRY-RUN] Would write /etc/pve/firewall/cluster.fw with baseline rules"
    info "[DRY-RUN] Would enforce TCP/22 safeguard rule before enabling firewall"
  else
cat > /etc/pve/firewall/cluster.fw <<EOF
[OPTIONS]
enable: 1
policy_in: ACCEPT
policy_out: ACCEPT

[RULES]
# SSH safety baseline (always keep TCP/22 reachable)
$ssh_rule_22
# SSH configured port
$ssh_rule_configured
# Proxmox Web UI
IN ACCEPT -p tcp -dport 8006
# Proxmox cluster communication
IN ACCEPT -p tcp -dport 3128
IN ACCEPT -p tcp -dport 5900:5999
IN ACCEPT -p tcp -dport 60000:60050
# Corosync (if clustering)
IN ACCEPT -p udp -dport 5404:5405
EOF

    # Safety guard: never leave firewall enabled without explicit TCP/22 allow.
    if ! grep -qE '^IN ACCEPT -p tcp -dport 22([[:space:]]|$)' /etc/pve/firewall/cluster.fw; then
      error "Firewall safeguard missing TCP/22 allow rule. Disabling firewall to prevent SSH lockout."
      sed -i 's/^enable:[[:space:]]*1/enable: 0/' /etc/pve/firewall/cluster.fw || true
      return 1
    fi
  fi

  success "Firewall configured with safe defaults"
}

############################################
# CIFS mounts
############################################
configure_cifs(){
  if [[ "$ENABLE_CIFS" != "yes" ]]; then return; fi
  
  info "Configuring CIFS mounts"
  
  # Validate SMB_SERVER is set and reachable
  if [[ -z "$SMB_SERVER" ]]; then
    warn "SMB_SERVER not configured; skipping CIFS mount configuration"
    warn "Set SMB_SERVER in your config file to enable CIFS mounts"
    return
  fi
  
  # Validate network connectivity to SMB server
  if [[ "$DRY_RUN" != "yes" ]]; then
    info "Checking connectivity to SMB server $SMB_SERVER..."
    if ! ping -c 2 -W 3 "$SMB_SERVER" >/dev/null 2>&1; then
      warn "SMB server $SMB_SERVER is not reachable via ping"
      warn "CIFS mounts may fail; verify network configuration and SMB_SERVER hostname/IP"
      # Don't return - allow user to proceed, but warn
    else
      info "SMB server $SMB_SERVER is reachable"
    fi
  fi

  # Optionally source SMB password from env or file to avoid prompts/plaintext config
  if [[ -z "${SMB_PASSWORD:-}" ]]; then
    if [[ -n "${SMB_PASSWORD_ENV:-}" ]]; then
      SMB_PASSWORD="$SMB_PASSWORD_ENV"
    elif [[ -n "${SMB_PASSWORD_FILE:-}" && -f "${SMB_PASSWORD_FILE}" ]]; then
      SMB_PASSWORD="$(head -n1 "${SMB_PASSWORD_FILE}" | tr -d '\r\n')"
    fi
  fi
  
  # Create SMB credentials file if missing
  if [[ ! -f "$SMB_CREDENTIALS_PATH" ]]; then
    warn "SMB credentials file $SMB_CREDENTIALS_PATH not found"
    local smb_user=""
    local smb_pass=""
    # Use username from config if provided
    if [[ -n "$SMB_USERNAME" ]]; then
      smb_user="$SMB_USERNAME"
      if [[ -n "$SMB_PASSWORD" ]]; then
        smb_pass="$SMB_PASSWORD"
        info "Using SMB credentials from config"
      else
        echo ""
        info "SMB username from config: $SMB_USERNAME"
        read -r -s -p "Enter SMB/CIFS password for $SMB_USERNAME: " smb_pass
        echo ""
      fi
    else
      echo ""
      read -r -p "Enter SMB/CIFS username: " smb_user
      read -r -s -p "Enter SMB/CIFS password: " smb_pass
      echo ""
    fi
    # Create credentials file if we have both username and password
    if [[ -n "$smb_user" && -n "$smb_pass" ]]; then
      if [[ "$DRY_RUN" == "yes" ]]; then
        info "[DRY-RUN] Would create $SMB_CREDENTIALS_PATH with username: $smb_user"
        # Actually create a temporary credentials file for dry-run read operations
        export SMB_CREDENTIALS_PATH_DRYRUN="/tmp/.smbcredentials.dryrun"
        printf "%s=%s\n" "username" "$smb_user" > "$SMB_CREDENTIALS_PATH_DRYRUN"
        printf "%s=%s\n" "password" "$smb_pass" >> "$SMB_CREDENTIALS_PATH_DRYRUN"
        chmod 600 "$SMB_CREDENTIALS_PATH_DRYRUN"
        # Point all subsequent reads to the dry-run file
        SMB_CREDENTIALS_PATH="$SMB_CREDENTIALS_PATH_DRYRUN"
      else
        mkdir -p "$(dirname "$SMB_CREDENTIALS_PATH")"
        (umask 077 && cat > "$SMB_CREDENTIALS_PATH" <<EOF
username=$smb_user
password=$smb_pass
EOF
)
        chmod 600 "$SMB_CREDENTIALS_PATH"
        smb_pass=""
        SMB_PASSWORD=""
        SMB_PASSWORD_ENV=""
        success "SMB credentials saved to $SMB_CREDENTIALS_PATH"
      fi
    else
      warn "SMB credentials not provided - skipping CIFS mount configuration"
      warn "To skip prompts, create $SMB_CREDENTIALS_PATH manually before running"
      return
    fi
  fi
  
  # Verify credentials file permissions
  if [[ "$DRY_RUN" != "yes" ]]; then
    local perms
    perms=$(stat -c %a "$SMB_CREDENTIALS_PATH" 2>/dev/null || echo "000")
    if [[ "$perms" != "$DEFAULT_FILE_PERMS" ]]; then
      chmod "$DEFAULT_FILE_PERMS" "$SMB_CREDENTIALS_PATH"
      warn "Fixed permissions on $SMB_CREDENTIALS_PATH (was $perms, now $DEFAULT_FILE_PERMS)"
    fi
  fi
  
  # Generate default CIFS entries if array is empty
  if [[ ${#CIFS_ENTRIES[@]} -eq 0 ]]; then
    info "No CIFS_ENTRIES defined, using defaults"
    CIFS_ENTRIES=(
      "//${SMB_SERVER}/Backups/${NODE_HOSTNAME} /mnt/pve/cifs-backups cifs _netdev,x-systemd.automount,noatime,uid=${CIFS_UID},gid=${CIFS_GID},dir_mode=0770,file_mode=0770,credentials=${SMB_CREDENTIALS_PATH} 0 0"
      "//${SMB_SERVER}/Software/ISO /mnt/pve/cifs-iso cifs _netdev,x-systemd.automount,noatime,uid=${CIFS_UID},gid=${CIFS_GID},dir_mode=0770,file_mode=0770,credentials=${SMB_CREDENTIALS_PATH} 0 0"
    )
  fi
  
  # Install smbclient early if auto-create or auto-provision may use it
  if [[ "$SMB_AUTOCREATE_DIRS" == "yes" ]] && ! command -v smbclient >/dev/null 2>&1; then
    info "Installing smbclient for SMB directory provisioning"
    if ! retry_cmd "$MAX_RETRIES" run_cmd apt-get install -y smbclient; then
      warn "Failed to install smbclient; SMB auto-create will not work"
      SMB_AUTOCREATE_DIRS="no"
    fi
  fi
  
  # Optionally auto-create missing subdirectories on SMB shares (e.g., Backups/<NODE>)
  if [[ "$SMB_AUTOCREATE_DIRS" == "yes" ]]; then
    # Derive user for smbclient from credentials file
    local sc_user="" sc_pass=""
    sc_user=$(grep -iE '^username[[:space:]]*=' "$SMB_CREDENTIALS_PATH" | head -n1 | cut -d'=' -f2 | tr -d ' ')
    sc_pass=$(grep -iE '^password[[:space:]]*=' "$SMB_CREDENTIALS_PATH" | head -n1 | cut -d'=' -f2 | tr -d ' ')
    if [[ -n "$sc_user" && -n "$sc_pass" ]]; then
      for entry in "${CIFS_ENTRIES[@]}"; do
        [[ -z "$entry" ]] && continue
        # Source format: //server/share[/subdir] /mountpoint cifs ...
        local source share server subdir
        source=$(echo "$entry" | awk '{print $1}')
        server=$(echo "$source" | awk -F'//' '{print $2}' | awk -F'/' '{print $1}')
        share=$(echo "$source" | awk -F'//' '{print $2}' | awk -F'/' '{print $2}')
        subdir=$(echo "$source" | awk -F'//' '{print $2}' | cut -d'/' -f3-)
        if [[ -n "$subdir" ]]; then
          # Create subdir inside the share (one level only)
          local topdir
          topdir=$(echo "$subdir" | cut -d'/' -f1)
          if [[ -n "$topdir" ]]; then
            if [[ "$DRY_RUN" == "yes" ]]; then
              info "[DRY-RUN] Would create '$topdir' on //$server/$share via smbclient"
            else
              SMBCLIENT_CMD=(smbclient "//$server/$share" "-U" "$sc_user%$sc_pass")
              [[ -n "$SMB_DOMAIN" ]] && SMBCLIENT_CMD+=("-W" "$SMB_DOMAIN")
              "${SMBCLIENT_CMD[@]}" -c "mkdir $topdir" >/dev/null 2>&1 || true
            fi
          fi
        fi
      done
    else
      warn "Cannot auto-create SMB directories: missing username/password in $SMB_CREDENTIALS_PATH"
    fi
  fi

  backup_file /etc/fstab

  # Ensure base mount directory exists (parent for per-node mounts)
  local base_mount_dir="/mnt/pve"
  create_secure_dir "$base_mount_dir" "$DEFAULT_DIR_PERMS" "root:root"
  
  # Create mount directories and add to fstab
  for entry in "${CIFS_ENTRIES[@]}"; do
    [[ -z "$entry" ]] && continue  # Skip empty entries
    local target
    target=$(echo "$entry" | awk '{print $2}')
    if [[ "$DRY_RUN" == "yes" ]]; then
      info "[DRY-RUN] Would create mount target directory $target"
    else
      mkdir -p "$target"
    fi
    
    # Remove old entry if exists
    local mount_source
    mount_source=$(echo "$entry" | awk '{print $1}')
    if [[ "$DRY_RUN" == "yes" ]]; then
      info "[DRY-RUN] Would remove existing fstab entry for $mount_source"
    else
      sed -i "\|${mount_source}|d" /etc/fstab
    fi
    
    # Add new entry
    if [[ "$DRY_RUN" == "yes" ]]; then
      info "[DRY-RUN] Would append to /etc/fstab: $entry"
    else
      echo "$entry" >> /etc/fstab
    fi
  done
  
  run_cmd systemctl daemon-reload
  # Rely on systemd automount for CIFS shares; no explicit mount -a
  success "CIFS mounts configured"
}

############################################
# Services & hardening
############################################

configure_fail2ban(){
  info "Configuring fail2ban"
  create_secure_dir "/etc/fail2ban" "755" "root:root"
  if [[ "$DRY_RUN" == "yes" ]]; then
    info "[DRY-RUN] Would write /etc/fail2ban/jail.local"
  else
  
  # Create local jail configuration
  cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log

[proxmox]
enabled = true
port = 8006
logpath = /var/log/daemon.log
EOF
  fi

  if ! retry_cmd "$MAX_RETRIES" run_cmd systemctl enable --now fail2ban; then
    warn "fail2ban enable failed"
  fi
  success "Fail2ban configured and running"
}

enable_smart(){
  info "Enabling smartmontools for disk health"
  
  # Check if smartd is a linked unit (common in Proxmox)
  if systemctl is-enabled smartd >/dev/null 2>&1; then
    info "smartd already enabled"
  elif [[ -L /etc/systemd/system/multi-user.target.wants/smartd.service ]]; then
    info "smartd already linked/enabled via systemd"
  else
    # Try to enable it normally
    if ! run_cmd systemctl enable smartd 2>/dev/null; then
      warn "Could not enable smartd (may already be linked)"
    fi
  fi
  
  # Start if not running
  if ! systemctl is-active --quiet smartd; then
    run_cmd systemctl start smartd || warn "Could not start smartd"
  fi
  
  # Run initial SMART test
  info "Running initial SMART scan..."
  for disk in /dev/sd? /dev/nvme?n1; do
    if [[ -e "$disk" ]]; then
      smartctl -a "$disk" > "/var/log/smart-${disk##*/}-initial.log" 2>&1 || true
    fi
  done
  success "SMART monitoring enabled"
}

configure_sensors(){
  info "Configuring hardware sensors"
  if ! run_cmd sensors-detect --auto >/dev/null 2>&1; then
    warn "Could not auto-detect sensors"
  fi
  success "Sensor detection complete"
}

# ...existing code...

############################################
# Post-install cleanup
############################################
cleanup(){
  info "Performing post-install cleanup"
  
  # Clean package cache
  retry_cmd "$MAX_RETRIES" run_cmd apt-get autoremove -y
  retry_cmd "$MAX_RETRIES" run_cmd apt-get autoclean
  
  # Clear bash history for security
  if [[ "$DRY_RUN" == "yes" ]]; then
    info "[DRY-RUN] Would clear shell history"
  else
    history -c
  fi
  
  success "Cleanup complete"
}

############################################
# Kernel mitigation: L1TF suppress warning
############################################
configure_kernel_mitigations(){
  # Append l1tf=flush,nowarn if enabled
  if [[ "$ENABLE_L1TF_FLUSH_NOWARN" == "yes" ]]; then
    if [[ -f /etc/default/grub ]]; then
      info "Applying kernel mitigation: l1tf=flush,nowarn"
      backup_file /etc/default/grub
      
      # Validate GRUB file syntax before proceeding (skip in dry-run)
      if [[ "$DRY_RUN" != "yes" ]] && ! bash -n /etc/default/grub 2>/dev/null; then
        warn "GRUB file has syntax errors, attempting to restore from backup"
        if [[ -f /etc/default/grub.bootstrap.bak ]]; then
          cp /etc/default/grub.bootstrap.bak /etc/default/grub
          info "Restored GRUB from backup"
        else
          warn "No backup available, skipping kernel mitigation"
          return
        fi
      fi
      
      # Check if parameter already present
      if grep -q 'l1tf=flush,nowarn' /etc/default/grub; then
        info "Kernel cmdline already contains l1tf=flush,nowarn"
      else
        # Use a safe approach: read, modify, write back
        if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
          # Extract current value, append new parameter, replace line
          local current_line
          current_line=$(grep '^GRUB_CMDLINE_LINUX=' /etc/default/grub)
          # Strip GRUB_CMDLINE_LINUX=" from start and " from end
          local current_value="${current_line#GRUB_CMDLINE_LINUX=\"}"
          current_value="${current_value%\"}"
          # Trim any trailing spaces
          current_value="${current_value## }"
          current_value="${current_value%% }"
          # Append new parameter
          if [[ -n "$current_value" ]]; then
            local new_value="$current_value l1tf=flush,nowarn"
          else
            local new_value="l1tf=flush,nowarn"
          fi
          # Replace the line safely
          if [[ "$DRY_RUN" == "yes" ]]; then
            info "[DRY-RUN] Would set GRUB_CMDLINE_LINUX=\"$new_value\""
          else
            sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$new_value\"|" /etc/default/grub
          fi
          info "Updated GRUB_CMDLINE_LINUX with l1tf=flush,nowarn"
        else
          if [[ "$DRY_RUN" == "yes" ]]; then
            info "[DRY-RUN] Would append GRUB_CMDLINE_LINUX=\"l1tf=flush,nowarn\""
          else
            echo 'GRUB_CMDLINE_LINUX="l1tf=flush,nowarn"' >> /etc/default/grub
          fi
          info "Added GRUB_CMDLINE_LINUX with l1tf=flush,nowarn"
        fi
        
        # Validate syntax after modification (skip in dry-run)
        if [[ "$DRY_RUN" != "yes" ]] && ! bash -n /etc/default/grub 2>/dev/null; then
          warn "GRUB modification created syntax error, restoring backup"
          cp /etc/default/grub.bootstrap.bak /etc/default/grub
          return
        fi
      fi
      
      if ! retry_cmd "$MAX_RETRIES" run_cmd update-grub; then
        warn "update-grub failed after retries"
      fi
    else
      warn "/etc/default/grub not found; skipping kernel mitigation"
    fi
  fi
}

############################################
# Emit machine-readable metadata and inventory fragment
############################################
emit_node_metadata(){
  info "Writing machine-readable node metadata"
  if [[ "$DRY_RUN" == "yes" ]]; then
    info "[DRY-RUN] Would create /etc/phoenix and write metadata files"
    return
  fi
  mkdir -p /etc/phoenix
  local mgmt_ip
  mgmt_ip=$(echo "$MGMT_IP_CIDR" | cut -d/ -f1)
  cat > /etc/phoenix/node-info.json <<EOF
{
  "hostname": "${NODE_HOSTNAME}",
  "fqdn": "${FQDN}",
  "mgmt_ip": "${mgmt_ip}",
  "mgmt_cidr": "${MGMT_IP_CIDR}",
  "gateway": "${MGMT_GW}",
  "dns": "${DNS_SERVERS}",
  "site": "${SITE}",
  "primary_iface": "${PRIMARY_IFACE}",
  "mgmt_bridge": "${MGMT_BRIDGE}",
  "timestamp": "$(date --iso-8601=seconds)"
}
EOF

  info "Metadata written to /etc/phoenix/node-info.json"
  info "If you track inventories elsewhere, copy values from /etc/phoenix/node-info.json"
}

############################################
# Post-bootstrap health checks
############################################
post_boot_health_checks(){
  info "Running post-bootstrap health checks"
  local mgmt_ip
  mgmt_ip=$(echo "$MGMT_IP_CIDR" | cut -d/ -f1)
  local ok=0 warnc=0 fail=0

  # Bridge IP check
  if ip -4 addr show dev "$MGMT_BRIDGE" | grep -q "$mgmt_ip"; then
    info "Bridge $MGMT_BRIDGE has IP $mgmt_ip"
    ok=$((ok+1))
  else
    warn "Bridge $MGMT_BRIDGE does not show IP $mgmt_ip"
    warnc=$((warnc+1))
  fi

  # Gateway ping
  if ping -c 2 -W 2 "$MGMT_GW" >/dev/null 2>&1; then
    info "Gateway $MGMT_GW reachable"
    ok=$((ok+1))
  else
    warn "Gateway $MGMT_GW not reachable"
    warnc=$((warnc+1))
  fi

  # DNS resolution
  if getent ahosts google.com >/dev/null 2>&1; then
    info "DNS resolution works"
    ok=$((ok+1))
  else
    warn "DNS resolution failed (check /etc/resolv.conf)"
    warnc=$((warnc+1))
  fi

  # Services
  for svc in sshd pveproxy fail2ban; do
    # Skip checks in dry-run or when unit is not installed
    if [[ "$DRY_RUN" == "yes" ]]; then
      info "[DRY-RUN] Skipping service check for $svc"
      continue
    fi
    if ! systemctl list-unit-files | awk '{print $1}' | grep -qx "${svc}.service"; then
      info "Service $svc not installed; skipping check"
      continue
    fi
    if systemctl is-active --quiet "$svc"; then
      info "Service $svc: active"
      ok=$((ok+1))
    else
      warn "Service $svc: not active"
      warnc=$((warnc+1))
    fi
  done

  # CIFS mounts quick check (with systemd automount, they mount on-demand, not at boot)
  if grep -qi cifs /etc/fstab 2>/dev/null; then
    # Just verify fstab entries exist; don't warn about unmounted automounts
    if mount | grep -i cifs >/dev/null 2>&1; then
      info "Some CIFS mounts are currently mounted"
    else
      info "CIFS mounts configured (via systemd automount; will mount on first access)"
    fi
    ok=$((ok+1))
  else
    info "No CIFS mounts configured in /etc/fstab"
    ok=$((ok+1))
  fi

  echo ""
  echo "Post-bootstrap health summary: OK=$ok WARN=$warnc FAIL=$fail"

  if [[ "$INTERACTIVE_MODE" == "yes" ]]; then
    read -r -p "Reboot now to apply kernel/network changes? (yes/no) [no]: " do_reboot
    do_reboot=${do_reboot:-no}
    if [[ "$do_reboot" == "yes" ]]; then
      info "Rebooting system as requested"
      sleep 2
      run_cmd reboot
    fi
  else
    if [[ "$AUTO_REBOOT" == "yes" ]]; then
      info "Auto-reboot enabled: rebooting to apply kernel/network changes"
      sleep 2
      run_cmd reboot
    else
      if [[ "$AUTO_REBOOT_PROMPT" == "yes" ]]; then
        # Automated mode but no auto-reboot: ask once at the end
        read -r -p "Reboot now to apply kernel/network changes? (yes/no) [no]: " do_reboot_auto
        do_reboot_auto=${do_reboot_auto:-no}
        if [[ "$do_reboot_auto" == "yes" ]]; then
          info "Rebooting system as requested"
          sleep 2
          run_cmd reboot
        else
          info "Automated mode: reboot not performed. Please reboot when convenient to apply network/kernel changes"
        fi
      else
        info "Automated mode: reboot not performed (AUTO_REBOOT_PROMPT=no). Please reboot when convenient to apply network/kernel changes"
      fi
    fi
  fi
}

############################################
# Summary
############################################
summary(){
  echo ""
  echo "========================================="
  success "Bootstrap completed for $FQDN"
  echo "========================================="
  echo ""
  echo "Configuration Summary:"
  echo "  Hostname: $FQDN"
  echo "  IP Address: $MGMT_IP_CIDR"
  echo "  Gateway: $MGMT_GW"
  echo "  DNS: $DNS_SERVERS"
  echo "  Site: $SITE"
  echo "  SSH Port: $SSH_PORT"
  echo "  Management Bridge: $MGMT_BRIDGE"
  echo ""
  echo "  Tell me, have you seen the Marvelous Breadfish?" "¯\_(ツ)_/¯"
  echo ""
  display_banner() {
  # Red for the bird
  tput setaf 1
  cat <<'BIRD'
       
              .-                           =-.    ...
             ..                              .++  . .=.
         .= ..                                 .+..=..=.
         .= +.                                . -. := .=   .
         .+ +..              ..   +           .=   == .=   .
         .+..++              .++..++           =   == .=  -.
         .++...+.             ..++++++.       .=. === +..==
           +++..+..           .++++++++.     .== +==   .==
         .. .+++.++++..      .+++: .+++.    .++.++= .-===
        . .+. .++++++++=++.  .+++.    -+. .++++++.=+++=. .=.
        .+  .+++...++++++++=++++++.    .:+++++++++++..+++. .-
         .**....+++++++++++++++++++=  .+++++++++++++++...*+..
           .***.... .+++++++++*****+*. *+++++++++++.
                   ...++.+************.*****++++:..+.
             .+++..  ...*+..:*+********.*******.**.
                       *.    .*+*******.**.  ..   .
                       ..    .*+*******.**.
                             **********..***+..
                          .*+..*.******
                               .******.
                          .-.=**.****
                        .=.**..****...
                      .+.**. .**.*...
                     ++.*   .**.** +
                    ++...  **. .*. +
                   .+..  .**.. .*. +
                   =++   :*.+. .*. ++.
                   .*    *.++.  **. .+++.
                   ..    .++++.. ##. .+++++
                          :***.***####.*+++*
                          .***.**.*###+  ..*.
                           **.*-*. =###.   *.
                           *. .**.   ....
                          .. .***
                              =#.
                               .
BIRD
  
  # Red + bold for Phoenix Stack text
  tput setaf 1
  tput bold
  cat <<'MASTHEAD'
______ _                      _        _____ _             _    
| ___ \ |                    (_)      /  ___| |           | |   
| |_/ / |__   ___   ___ _ __  ___  __ \ `--.| |_ __ _  ___| | __
|  __/| '_ \ / _ \ / _ \ '_ \| \ \/ /  `--. \ __/ _` |/ __| |/ /
| |   | | | | (_) |  __/ | | | |>  <  /\__/ / || (_| | (__|   < 
\_|   |_| |_|\___/ \___|_| |_|_/_/\_\ \____/ \__\__,_|\___|_|\_\
                                                               
                                                               
MASTHEAD
  
  # Reset all colors
  tput sgr0
}
  display_banner
  echo ""
  echo "For next steps, refer to the Phoenix Stack documentation:"
  echo "https://github.com/Roland-Chang/PhoenixStack/blob/main/scripts/README.md"
  echo ""
}

############################################
# Main execution
############################################
main(){
  echo "========================================="
  echo "Phoenix Stack - Proxmox Bootstrap"
  echo "Version: 2025-11-25-v3"
  echo "========================================="
  echo ""
  
  require_root
  check_proxmox
  # Acquire lock to prevent concurrent runs
  acquire_lock
  trap release_lock EXIT

  if [[ "$DRY_RUN" == "yes" ]]; then
    warn "Running in dry-run mode: actions will be reported but not all changes are blocked by this mode"
  fi
  
  # Load config file if provided
  if [[ -n "$CONFIG_FILE" ]]; then
    load_config "$CONFIG_FILE"
  fi
  
  # Run interactive wizard if in interactive mode
  if [[ "$INTERACTIVE_MODE" == "yes" ]]; then
    interactive_config
  else
    info "Running in automated mode"
    info "Using configuration from: ${CONFIG_FILE:-hardcoded defaults}"
  fi

  # Validate configuration before making changes
  validate_config
  
  configure_hostname
  configure_timezone
  configure_network
  configure_dns
  configure_repos
  install_packages
  upgrade_system
  apply_sysctl
  configure_ssh
  configure_firewall
  configure_cifs
  # Chrony removed; NTP via DHCP/UDM SE
  configure_fail2ban
  enable_smart
  configure_sensors
  remove_subscription_nag
  configure_kernel_mitigations
  
  # Remove old kernel packages and clean up boot entries
  info "Cleaning up boot entries"
  if [[ "$DRY_RUN" == "yes" ]]; then
    info "[DRY-RUN] Would clean up old boot entries via proxmox-boot-tool"
  else
    # Proxmox manages kernels automatically; we only clean boot entries
    # Skip kernel package removal as it's error-prone with meta-packages
    if command -v proxmox-boot-tool >/dev/null 2>&1; then
      proxmox-boot-tool clean 2>/dev/null || warn "proxmox-boot-tool clean returned error"
      proxmox-boot-tool refresh 2>/dev/null || warn "proxmox-boot-tool refresh returned error"
      success "Old boot entries cleaned up and bootloader refreshed"
    else
      warn "proxmox-boot-tool not found; skipping boot entry cleanup"
    fi
  fi
  cleanup
  # Emit metadata and an inventory fragment for operator use
  emit_node_metadata
  post_boot_health_checks
  summary
}

main "$@"