#!/usr/bin/env bash
# =============================================================================
# pve-bootstrap.sh — PhoenixStack Proxmox VE 9 host bootstrap
#
# Brings a freshly installed PVE 9 node to the PhoenixStack host baseline.
# PLAN mode (default) changes nothing and shows exactly what would change.
#
# Usage:
#   ./pve-bootstrap.sh --config ../config/pve01.conf                  # plan, all stages
#   ./pve-bootstrap.sh --config ../config/pve01.conf --apply          # apply, all stages
#   ./pve-bootstrap.sh --config ../config/pve01.conf --apply --stage network
#   ./pve-bootstrap.sh --config ../config/pve01.conf --apply --stage storage --destroy-data
#
# Stages, in order:
#   preflight  sanity checks (always runs)
#   repos      no-subscription repo, disable enterprise, full upgrade, packages
#   system     timezone, NTP, DNS, sysctl, journald, SSH hardening
#   network    bond0 + VLAN-aware vmbr0 (auto-rollback unless confirmed)
#   kernel     IOMMU cmdline, vfio GPU binding, GPU resource mapping, ZFS ARC cap
#   nas        NAS SMB mounts + PVE dir storages (before storage, so backups
#              can be checked before any disk is wiped)
#   storage    guest/backup ZFS pools, datasets, PVE storage
#   access     admins group/users, roles, service accounts + API tokens
#   firewall   datacenter default-DROP + admin ipset (auto-rollback unless confirmed)
#   acme       Let's Encrypt cert via Cloudflare DNS-01 (only if ACME_ENABLE=yes)
#   verify     read-only health report
#
# Safety:
#   * Every file it replaces is backed up under /var/backups/phoenix-bootstrap/<run>/
#   * network/firewall changes arm a systemd timer that reverts them unless you
#     type "keep" — losing your session means it rolls back on its own.
#   * Disks with existing data are only wiped with --destroy-data AND a typed
#     confirmation naming the pool. Boot-pool disks are always refused.
#   * Secrets are prompted (or read from env) and never echoed or logged.
# =============================================================================
set -Eeuo pipefail
umask 022
# Byte-order sorting everywhere, so `sort` matches Perl's `sort keys` (json_keys). Under a
# UTF-8 locale `sort` ignores case and reports a false "update role" on every run.
export LC_COLLATE=C

readonly VERSION="2026.11.0"
readonly ALL_STAGES=(preflight repos system network kernel nas storage access firewall acme verify)
readonly STATE_DIR="/etc/phoenixstack"
RUN_ID="$(date +%Y%m%d-%H%M%S)"; readonly RUN_ID
readonly BACKUP_DIR="/var/backups/phoenix-bootstrap/${RUN_ID}"
readonly LOCK_FILE="/run/phoenix-bootstrap.lock"
readonly ROLLBACK_SECS=120

MODE="plan"
CONFIG=""
DESTROY_DATA="no"
declare -a SELECTED_STAGES=()
CHANGES=0
WARNINGS=0
REBOOT_REQUIRED="no"
FILE_CHANGED="no"

# ----------------------------------------------------------------------------
# Output helpers
# ----------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_R=$'\e[31m' C_G=$'\e[32m' C_Y=$'\e[33m' C_B=$'\e[1;34m' C_D=$'\e[2m' C_0=$'\e[0m'
else
  C_R="" C_G="" C_Y="" C_B="" C_D="" C_0=""
fi
section() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; }
info()    { printf '    %s\n' "$*"; }
ok()      { printf '  %s✓%s %s\n' "$C_G" "$C_0" "$*"; }
change()  { printf '  %s~%s %s\n' "$C_Y" "$C_0" "$*"; CHANGES=$((CHANGES + 1)); }
warn()    { printf '  %s!%s %s\n' "$C_Y" "$C_0" "$*" >&2; WARNINGS=$((WARNINGS + 1)); }
die()     { printf '\n%sERROR:%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }
trap 'die "command failed (line $LINENO): $BASH_COMMAND"' ERR

is_apply() { [[ $MODE == apply ]]; }

# run <cmd...> — execute in apply mode, print in plan mode. Never pass secrets here.
run() {
  if is_apply; then
    printf '    %s$ %s%s\n' "$C_D" "$*" "$C_0"
    "$@"
  else
    printf '    %s[plan] %s%s\n' "$C_D" "$*" "$C_0"
  fi
}

# confirm <message> <word> — operator must type <word>. Reads from the terminal.
confirm() {
  local msg=$1 word=$2 reply=""
  printf '\n  %s%s%s\n  Type "%s" to continue: ' "$C_Y" "$msg" "$C_0" "$word"
  read -r reply </dev/tty || true
  [[ $reply == "$word" ]]
}

# read_secret <var> <prompt> — from env var of the same name, else silent prompt.
read_secret() {
  local __var=$1 prompt=$2 v1="" v2=""
  if [[ -n ${!__var:-} ]]; then return 0; fi
  read -r -s -p "    ${prompt}: " v1 </dev/tty; echo
  read -r -s -p "    ${prompt} (again): " v2 </dev/tty; echo
  [[ -n $v1 && $v1 == "$v2" ]] || die "secret entries empty or did not match"
  printf -v "$__var" '%s' "$v1"
}

backup_file() {
  local f=$1
  [[ -e $f ]] || return 0
  mkdir -p "${BACKUP_DIR}$(dirname "$f")"
  cp -a "$f" "${BACKUP_DIR}${f}"
}

# ensure_file <path> <mode> [--secret]   (desired content on stdin)
# Sets FILE_CHANGED=yes|no. Plan mode shows a diff (never for --secret).
ensure_file() {
  local path=$1 mode=$2 secret=${3:-} tmp src
  tmp=$(mktemp)
  cat >"$tmp"
  if [[ -f $path ]] && cmp -s "$tmp" "$path"; then
    rm -f "$tmp"; FILE_CHANGED="no"; ok "$path"; return 0
  fi
  FILE_CHANGED="yes"
  change "$path"
  if [[ $secret != --secret ]]; then
    src=/dev/null; [[ -f $path ]] && src=$path
    diff -u --label "current" --label "desired" "$src" "$tmp" | tail -n +3 | sed 's/^/      /' || true
  fi
  if is_apply; then
    backup_file "$path"
    mkdir -p "$(dirname "$path")"
    if [[ $path == /etc/pve/* ]]; then
      cat "$tmp" >"$path"          # pmxcfs: no chmod/chown
    else
      install -m "$mode" "$tmp" "$path"
    fi
  fi
  rm -f "$tmp"
}

# words <string> — split on any whitespace, one token per line
words() { tr -s ' \t\n' '\n' <<<"$1" | sed '/^$/d'; }
# sort_csv "b,a,c" -> "a,b,c"
sort_csv() { tr ',' '\n' <<<"$1" | sed '/^$/d' | sort | paste -sd, -; }

# JSON helpers (perl JSON::PP is always present on PVE; jq may not be yet)
json_keys() { perl -MJSON::PP -0777 -ne 'my $d=decode_json($_); print "$_\n" for sort keys %$d'; }

# ----------------------------------------------------------------------------
# Discovery helpers
# ----------------------------------------------------------------------------
physical_ifaces() {
  local n
  for n in /sys/class/net/*; do
    if [[ -e $n/device ]]; then basename "$n"; fi
  done | sort -V
}

# iface_for_mac <mac> — physical NIC name owning <mac> (permanent MAC if enslaved)
iface_for_mac() {
  local want=${1,,} n addr
  for n in $(physical_ifaces); do
    addr=$(cat "/sys/class/net/$n/address")
    if [[ -r /sys/class/net/$n/bonding_slave/perm_hwaddr ]]; then
      addr=$(cat "/sys/class/net/$n/bonding_slave/perm_hwaddr")
    fi
    if [[ ${addr,,} == "$want" ]]; then echo "$n"; return 0; fi
  done
  return 1
}

pool_layout() { local v="ZFS_POOL_${1}_LAYOUT"; printf '%s' "${!v:-}"; }
pool_props()  { local v="ZFS_POOL_${1}_PROPS";  printf '%s' "${!v:-}"; }
pool_disks()  { words "$(pool_layout "$1")" | grep '^/dev/' || true; }

# Whole-disk device paths backing every imported pool
imported_pool_disks() {
  local dev parent
  zpool status -LP 2>/dev/null | awk '$1 ~ /^\/dev\// {print $1}' | while read -r dev; do
    parent=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1)
    if [[ -n $parent ]]; then echo "/dev/$parent"; else echo "$dev"; fi
  done | sort -u
}

storage_exists() { grep -qE "^[a-z]+: ${1}\$" /etc/pve/storage.cfg; }
storage_prop() {
  awk -v id="$1" -v key="$2" '
    /^[a-z]+: / { cur=$2; next }
    cur==id && $1==key { $1=""; sub(/^ /,""); print; exit }' /etc/pve/storage.cfg
}

# ----------------------------------------------------------------------------
# Stage: preflight
# ----------------------------------------------------------------------------
stage_preflight() {
  section "preflight"
  [[ $EUID -eq 0 ]] || die "must run as root"
  command -v pveversion >/dev/null || die "pveversion not found — is this a Proxmox VE host?"

  local pvever
  pvever=$(pveversion | sed -n 's|^pve-manager/\([0-9.]*\).*|\1|p')
  if [[ ${pvever%%.*} == 9 ]]; then ok "Proxmox VE ${pvever}"; else die "expected Proxmox VE 9.x, found '${pvever}'"; fi

  if [[ $(hostname) == "$NODE_NAME" ]]; then ok "hostname ${NODE_NAME}"
  else die "hostname is '$(hostname)' but config is for '${NODE_NAME}' (wrong config file?)"; fi
  if [[ $(hostname -f 2>/dev/null || true) == "$NODE_FQDN" ]]; then ok "fqdn ${NODE_FQDN}"
  else warn "hostname -f is '$(hostname -f 2>/dev/null || true)', expected '${NODE_FQDN}' — check /etc/hosts"; fi

  if zpool status rpool 2>/dev/null | grep -qE '^\s+mirror-'; then ok "boot pool rpool is mirrored"
  else warn "boot pool rpool is NOT mirrored"; fi

  local mac ifc
  for mac in $UPLINK_MACS; do
    if ifc=$(iface_for_mac "$mac"); then ok "uplink ${mac} -> ${ifc}"
    else die "no physical NIC has MAC ${mac} (UPLINK_MACS)"; fi
  done

  local p d
  for p in ${ZFS_POOLS:-}; do
    [[ -n $(pool_layout "$p") ]] || die "ZFS_POOL_${p}_LAYOUT is not set"
    for d in $(pool_disks "$p"); do
      if [[ -e $d ]]; then ok "pool ${p}: $(basename "$d")"; else die "pool ${p}: disk not found: ${d}"; fi
    done
  done

  if [[ -n ${GPU_PCI_ADDR:-} ]]; then
    if [[ -n $(lspci -s "$GPU_PCI_ADDR" 2>/dev/null) ]]; then
      ok "GPU ${GPU_PCI_ADDR}: $(lspci -s "${GPU_PCI_ADDR}.0" | cut -d' ' -f2-)"
    else
      die "GPU_PCI_ADDR ${GPU_PCI_ADDR} not found (lspci)"
    fi
  fi

  if ! grep -qw vmx /proc/cpuinfo; then warn "CPU virtualization (VT-x) not visible — check BIOS"; fi
  info "mode: ${MODE^^}   run id: ${RUN_ID}"
}

# ----------------------------------------------------------------------------
# Stage: repos
# ----------------------------------------------------------------------------
stage_repos() {
  section "repos"
  local codename f
  # Parse, don't source: os-release sets VERSION, which is readonly in this script.
  codename=$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release | tr -d '"')
  [[ -n $codename ]] || die "could not read VERSION_CODENAME from /etc/os-release"

  for f in /etc/apt/sources.list.d/*.sources; do
    [[ -f $f ]] || continue
    grep -q 'enterprise.proxmox.com' "$f" || continue
    if grep -qiE '^Enabled:[[:space:]]*(no|false)' "$f"; then
      ok "enterprise repo disabled: $f"
    else
      change "disable enterprise repo: $f"
      if is_apply; then
        backup_file "$f"
        if grep -qi '^Enabled:' "$f"; then sed -i 's/^Enabled:.*/Enabled: no/I' "$f"
        else sed -i '0,/^Types:/s//Enabled: no\nTypes:/' "$f"; fi
      fi
    fi
  done

  ensure_file /etc/apt/sources.list.d/proxmox.sources 0644 <<EOF
# Managed by PhoenixStack pve-bootstrap.sh
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: ${codename}
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

  run apt-get update -q
  local -a missing=()
  local pkg
  for pkg in $EXTRA_PACKAGES; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
      missing+=("$pkg")
    fi
  done

  if is_apply; then
    DEBIAN_FRONTEND=noninteractive apt-get -y -q \
      -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold dist-upgrade
    if ((${#missing[@]})); then
      change "install: ${missing[*]}"
      DEBIAN_FRONTEND=noninteractive apt-get -y -q install "${missing[@]}"
    fi
  else
    info "upgradable now (from current lists): $(apt-get -s dist-upgrade 2>/dev/null | grep -c '^Inst' || true) package(s)"
    if ((${#missing[@]})); then change "install: ${missing[*]}"; else ok "extra packages present"; fi
  fi

  local newest
  newest=$(find /lib/modules -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -V | tail -1)
  if [[ $newest != "$(uname -r)" ]]; then
    REBOOT_REQUIRED="yes"; info "kernel ${newest} installed, running $(uname -r) — reboot required"
  fi
}

# ----------------------------------------------------------------------------
# Stage: system
# ----------------------------------------------------------------------------
stage_system() {
  section "system"

  # Timezone
  if [[ $(timedatectl show -p Timezone --value) == "$TIMEZONE" ]]; then ok "timezone ${TIMEZONE}"
  else change "timezone -> ${TIMEZONE}"; run timedatectl set-timezone "$TIMEZONE"; fi

  # NTP (chrony is the PVE default)
  if [[ -n ${NTP_SERVERS:-} ]]; then
    ensure_file /etc/chrony/sources.d/phoenixstack.sources 0644 < <(
      echo "# Managed by PhoenixStack pve-bootstrap.sh"
      for s in $NTP_SERVERS; do echo "server ${s} iburst"; done)
    if [[ $FILE_CHANGED == yes ]] && is_apply; then chronyc reload sources >/dev/null || true; fi
  fi

  # DNS (PVE manages /etc/resolv.conf via the node DNS API)
  local -a want=() have=()
  read -ra want <<<"$DNS_SERVERS"
  mapfile -t have < <(awk '/^nameserver/{print $2}' /etc/resolv.conf)
  local have_search
  have_search=$(awk '/^search/{print $2; exit}' /etc/resolv.conf)
  if [[ "${want[*]}" == "${have[*]}" && $have_search == "$NODE_DOMAIN" ]]; then
    ok "DNS ${want[*]} (search ${NODE_DOMAIN})"
  else
    change "DNS -> ${want[*]} (search ${NODE_DOMAIN}); was: ${have[*]:-none} (search ${have_search:-none})"
    local -a args=(--search "$NODE_DOMAIN")
    local i
    for i in 0 1 2; do [[ -n ${want[$i]:-} ]] && args+=("--dns$((i + 1))" "${want[$i]}"); done
    run pvesh set "/nodes/${NODE_NAME}/dns" "${args[@]}"
  fi

  # Kernel/network sysctls. IPv6: no autoconfiguration on the host (not disabled
  # outright — some PVE daemons expect the stack to exist).
  ensure_file /etc/sysctl.d/90-phoenixstack.conf 0644 <<'EOF'
# Managed by PhoenixStack pve-bootstrap.sh
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
kernel.dmesg_restrict = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
net.ipv6.conf.all.autoconf = 0
net.ipv6.conf.default.autoconf = 0
EOF
  if [[ $FILE_CHANGED == yes ]] && is_apply; then sysctl --system >/dev/null; fi

  # Persistent, bounded journal
  ensure_file /etc/systemd/journald.conf.d/90-phoenixstack.conf 0644 <<'EOF'
# Managed by PhoenixStack pve-bootstrap.sh
[Journal]
Storage=persistent
SystemMaxUse=1G
EOF
  if [[ $FILE_CHANGED == yes ]] && is_apply; then systemctl restart systemd-journald; fi

  # SSH: make sure our keys are present BEFORE turning off password auth.
  local ak=/root/.ssh/authorized_keys key present=0
  for key in "${ROOT_SSH_KEYS[@]}"; do
    [[ -n $key ]] || continue
    if grep -qF "$key" "$ak" 2>/dev/null; then
      ok "root SSH key present: ${key##* }"; present=$((present + 1))
    else
      change "add root SSH key: ${key##* }"
      if is_apply; then printf '%s\n' "$key" >>"$ak"; present=$((present + 1)); fi
    fi
  done
  if ((present == 0)) && is_apply; then
    warn "no configured SSH key in ${ak} — NOT disabling password auth"
    return 0
  fi
  ensure_file /etc/ssh/sshd_config.d/10-phoenixstack.conf 0644 <<'EOF'
# Managed by PhoenixStack pve-bootstrap.sh (first match wins: this file is included first)
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30
EOF
  if [[ $FILE_CHANGED == yes ]] && is_apply; then
    sshd -t || die "sshd config test failed — not reloading"
    systemctl reload ssh
  fi
}

# ----------------------------------------------------------------------------
# Rollback timers (network / firewall)
# ----------------------------------------------------------------------------
# arm_rollback <name> <script-file> — run <script-file> in ROLLBACK_SECS unless disarmed
arm_rollback() {
  local unit="phoenix-rollback-${1}-${RUN_ID}"
  systemd-run --quiet --unit="$unit" --on-active="${ROLLBACK_SECS}s" /bin/sh "$2"
  info "rollback armed (${unit}): reverts in ${ROLLBACK_SECS}s unless confirmed"
}
disarm_rollback() {
  systemctl stop "phoenix-rollback-${1}-${RUN_ID}.timer" 2>/dev/null || true
  ok "rollback disarmed — change kept"
}
# keep_or_rollback <name> <script-file>
keep_or_rollback() {
  local reply="" wait=$((ROLLBACK_SECS - 15))
  printf '\n  %sStill connected? Type "keep" within %ss or the change auto-reverts:%s ' "$C_Y" "$wait" "$C_0"
  if read -r -t "$wait" reply </dev/tty && [[ $reply == keep ]]; then
    disarm_rollback "$1"
  else
    echo; warn "not confirmed — rolling back now"
    disarm_rollback "$1" >/dev/null
    /bin/sh "$2"
    die "$1 change rolled back"
  fi
}

# ----------------------------------------------------------------------------
# Stage: network
# ----------------------------------------------------------------------------
render_interfaces() {
  local -a uplinks=("$@")
  local n
  echo "# Managed by PhoenixStack pve-bootstrap.sh — edits here will be overwritten."
  echo "# Design: physical uplink(s) -> bond0 -> VLAN-aware vmbr0. Guests choose VLAN by tag."
  echo
  echo "auto lo"
  echo "iface lo inet loopback"
  for n in $(physical_ifaces); do
    echo
    if [[ " ${uplinks[*]} " == *" ${n} "* ]]; then echo "auto ${n}"; fi
    echo "iface ${n} inet manual"
  done
  echo
  echo "auto bond0"
  echo "iface bond0 inet manual"
  echo "    bond-slaves ${uplinks[*]}"
  echo "    bond-miimon 100"
  echo "    bond-mode ${BOND_MODE}"
  if [[ $BOND_MODE == 802.3ad ]]; then
    echo "    bond-xmit-hash-policy layer3+4"
    echo "    bond-lacp-rate fast"
  elif [[ $BOND_MODE == active-backup ]]; then
    echo "    bond-primary ${uplinks[0]}"
  fi
  echo
  echo "auto vmbr0"
  if [[ -z ${MGMT_VLAN:-} ]]; then
    echo "iface vmbr0 inet static"
    echo "    address ${MGMT_CIDR}"
    echo "    gateway ${MGMT_GATEWAY}"
  else
    echo "iface vmbr0 inet manual"
  fi
  echo "    bridge-ports bond0"
  echo "    bridge-stp off"
  echo "    bridge-fd 0"
  echo "    bridge-vlan-aware yes"
  echo "    bridge-vids ${BRIDGE_VIDS}"
  if [[ -n ${MGMT_VLAN:-} ]]; then
    echo
    echo "auto vmbr0.${MGMT_VLAN}"
    echo "iface vmbr0.${MGMT_VLAN} inet static"
    echo "    address ${MGMT_CIDR}"
    echo "    gateway ${MGMT_GATEWAY}"
  fi
  echo
  echo "source /etc/network/interfaces.d/*"
}

stage_network() {
  section "network"
  local -a uplinks=()
  local mac
  for mac in $UPLINK_MACS; do uplinks+=("$(iface_for_mac "$mac")"); done

  local tmp
  tmp=$(mktemp)
  render_interfaces "${uplinks[@]}" >"$tmp"
  ifquery -a -i "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; die "generated interfaces file failed to parse"; }

  ensure_file /etc/network/interfaces 0644 <"$tmp"
  rm -f "$tmp"
  [[ $FILE_CHANGED == yes ]] || return 0
  is_apply || { info "apply will reload networking with a ${ROLLBACK_SECS}s auto-rollback"; return 0; }

  warn "reloading network — run this from the iDRAC console or tmux if you can"
  local rb="${BACKUP_DIR}/rollback-network.sh"
  cat >"$rb" <<EOF
#!/bin/sh
cp -a '${BACKUP_DIR}/etc/network/interfaces' /etc/network/interfaces && ifreload -a
EOF
  arm_rollback network "$rb"
  ifreload -a || { /bin/sh "$rb"; disarm_rollback network; die "ifreload failed — restored previous config"; }
  if ping -c 3 -W 2 "$MGMT_GATEWAY" >/dev/null 2>&1; then
    ok "gateway ${MGMT_GATEWAY} reachable"
  else
    disarm_rollback network >/dev/null; /bin/sh "$rb"; die "gateway unreachable after reload — restored previous config"
  fi
  keep_or_rollback network "$rb"
}

# ----------------------------------------------------------------------------
# Stage: kernel
# ----------------------------------------------------------------------------
stage_kernel() {
  section "kernel"
  local refresh_boot="no" rebuild_initramfs="no" p cur new

  # Kernel command line: systemd-boot (/etc/kernel/cmdline) or GRUB
  if [[ -f /etc/kernel/cmdline ]]; then
    cur=$(</etc/kernel/cmdline); new=$cur
    read -r new <<<"$new"              # trim: the installer leaves a trailing space
    for p in $KERNEL_CMDLINE_ADD; do [[ " $new " == *" $p "* ]] || new+=" $p"; done
    ensure_file /etc/kernel/cmdline 0644 <<<"$new"
    if [[ $FILE_CHANGED == yes ]]; then refresh_boot="yes"; fi
  else
    cur=$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/\1/p' /etc/default/grub); new=$cur
    for p in $KERNEL_CMDLINE_ADD; do [[ " $new " == *" $p "* ]] || new="${new:+$new }$p"; done
    ensure_file /etc/default/grub 0644 < <(sed "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${new}\"|" /etc/default/grub)
    if [[ $FILE_CHANGED == yes ]]; then refresh_boot="yes"; run update-grub; fi
  fi

  # VFIO modules (vfio_virqfd is built into vfio on 6.x kernels)
  ensure_file /etc/modules-load.d/vfio.conf 0644 <<'EOF'
# Managed by PhoenixStack pve-bootstrap.sh
vfio
vfio_iommu_type1
vfio_pci
EOF
  if [[ $FILE_CHANGED == yes ]]; then rebuild_initramfs="yes"; fi

  # GPU → vfio-pci (all functions: video + HDMI audio)
  if [[ -n ${GPU_PCI_ADDR:-} ]]; then
    local ids
    ids=$(lspci -n -s "$GPU_PCI_ADDR" | awk '{print $3}' | sort -u | paste -sd, -)
    [[ -n $ids ]] || die "could not read PCI IDs for ${GPU_PCI_ADDR}"
    ensure_file /etc/modprobe.d/vfio.conf 0644 <<EOF
# Managed by PhoenixStack pve-bootstrap.sh — GPU ${GPU_PCI_ADDR} reserved for passthrough
options vfio-pci ids=${ids} disable_vga=1
softdep nouveau pre: vfio-pci
softdep nvidia pre: vfio-pci
softdep nvidiafb pre: vfio-pci
softdep snd_hda_intel pre: vfio-pci
EOF
    if [[ $FILE_CHANGED == yes ]]; then rebuild_initramfs="yes"; fi
    ensure_file /etc/modprobe.d/blacklist-gpu.conf 0644 <<'EOF'
# Managed by PhoenixStack pve-bootstrap.sh — host must never load GPU drivers
blacklist nouveau
blacklist nvidia
blacklist nvidiafb
EOF
    if [[ $FILE_CHANGED == yes ]]; then rebuild_initramfs="yes"; fi

    # Cluster PCI resource mapping, so guests reference the GPU by name
    # (hostpci0: mapping=<id>) instead of a host-specific PCI address.
    if [[ -n ${GPU_MAPPING_ID:-} ]]; then
      if pvesh get "/cluster/mapping/pci/${GPU_MAPPING_ID}" >/dev/null 2>&1; then
        ok "PCI mapping ${GPU_MAPPING_ID}"
      else
        local dev="/sys/bus/pci/devices/${GPU_PCI_ADDR}.0" vid did svid sdid grp
        vid=$(<"$dev/vendor"); did=$(<"$dev/device")
        svid=$(<"$dev/subsystem_vendor"); sdid=$(<"$dev/subsystem_device")
        grp=$(basename "$(readlink -f "$dev/iommu_group" 2>/dev/null)" 2>/dev/null || true)
        if [[ -z $grp || $grp == . ]]; then
          warn "PCI mapping ${GPU_MAPPING_ID}: no IOMMU group yet — reboot after this stage, then re-run it"
        else
          local map="node=${NODE_NAME},path=${GPU_PCI_ADDR},id=${vid#0x}:${did#0x},subsystem-id=${svid#0x}:${sdid#0x},iommugroup=${grp}"
          change "create PCI mapping ${GPU_MAPPING_ID}: ${map}"
          run pvesh create /cluster/mapping/pci --id "$GPU_MAPPING_ID" \
            --description "GPU ${GPU_PCI_ADDR} (all functions), managed by pve-bootstrap" --map "$map"
        fi
      fi
    fi
  fi

  # ZFS ARC cap
  local arc_bytes=$((ZFS_ARC_MAX_GIB * 1024 * 1024 * 1024))
  ensure_file /etc/modprobe.d/zfs.conf 0644 <<EOF
# Managed by PhoenixStack pve-bootstrap.sh — ARC max ${ZFS_ARC_MAX_GIB} GiB
options zfs zfs_arc_max=${arc_bytes}
EOF
  if [[ $FILE_CHANGED == yes ]]; then
    rebuild_initramfs="yes"
    if is_apply; then echo "$arc_bytes" >/sys/module/zfs/parameters/zfs_arc_max; fi
  fi

  if [[ $rebuild_initramfs == yes ]]; then run update-initramfs -u -k all; refresh_boot="yes"; fi
  if [[ $refresh_boot == yes ]]; then
    if proxmox-boot-tool status >/dev/null 2>&1; then run proxmox-boot-tool refresh; fi
    REBOOT_REQUIRED="yes"
  fi
}

# ----------------------------------------------------------------------------
# Stage: storage
# ----------------------------------------------------------------------------
wipe_disk() {
  local d=$1 x
  for x in "$d"-part*; do
    if [[ -e $x ]]; then
      zpool labelclear -f "$x" 2>/dev/null || true
      wipefs -a -q "$x"
    fi
  done
  zpool labelclear -f "$d" 2>/dev/null || true
  wipefs -a -q "$d"
  sgdisk --zap-all "$d" >/dev/null
}

ensure_pool() {
  local p=$1 d real b
  local -a tokens disks dirty=()
  mapfile -t tokens < <(words "$(pool_layout "$p")")
  mapfile -t disks < <(pool_disks "$p")

  if zpool list -H -o name "$p" >/dev/null 2>&1; then
    ok "pool ${p} exists ($(zpool list -H -o size,health "$p" | tr '\t' ' '))"
    return 0
  fi

  local -a in_use
  mapfile -t in_use < <(imported_pool_disks)
  for d in "${disks[@]}"; do
    real=$(readlink -f "$d")
    [[ $(lsblk -dno TYPE "$real") == disk ]] || die "pool ${p}: ${d} is not a whole disk"
    for b in "${in_use[@]}"; do
      [[ $real == "$b" ]] && die "pool ${p}: ${d} belongs to an imported pool (boot pool?) — refusing"
    done
    if lsblk -no MOUNTPOINTS "$real" | grep -q .; then die "pool ${p}: ${d} has mounted filesystems"; fi
    if [[ -n $(wipefs -n "$real" 2>/dev/null) ]] || (($(lsblk -no NAME "$real" | wc -l) > 1)); then
      dirty+=("$d")
    fi
  done

  change "create ZFS pool '${p}': $(words "$(pool_layout "$p")" | sed 's|/dev/disk/by-id/||' | paste -sd' ' -)"
  for d in "${disks[@]}"; do
    info "$(lsblk -dno SIZE,MODEL,SERIAL "$(readlink -f "$d")" | tr -s ' ')  ${d##*/}$([[ " ${dirty[*]} " == *" $d "* ]] && echo '  [HAS DATA]')"
  done

  if ((${#dirty[@]})) && [[ $DESTROY_DATA != yes ]]; then
    if is_apply; then die "pool ${p}: ${#dirty[@]} disk(s) contain data — re-run with --destroy-data to wipe them"; fi
    info "(apply needs --destroy-data: ${#dirty[@]} disk(s) contain existing data)"
    return 0
  fi
  is_apply || return 0

  if ((${#dirty[@]})); then
    confirm "ALL DATA on the ${#dirty[@]} disk(s) marked [HAS DATA] above will be DESTROYED." "destroy-${p}" \
      || die "not confirmed — pool ${p} not created"
    for d in "${dirty[@]}"; do info "wiping ${d##*/}"; wipe_disk "$d"; done
    udevadm settle
  fi

  zpool create -f -o ashift=12 -o autotrim=on \
    -O compression=lz4 -O atime=off -O xattr=sa -O acltype=posixacl -O dnodesize=auto \
    "$p" "${tokens[@]}"
  local prop
  for prop in $(pool_props "$p"); do zfs set "$prop" "$p"; done
  ok "pool ${p} created"
}

stage_storage() {
  section "storage"
  local p

  for p in ${ZFS_POOLS:-}; do ensure_pool "$p"; done

  # Datasets
  local entry name prop
  for entry in "${ZFS_DATASETS[@]}"; do
    name=${entry%% *}
    if zfs list -H "$name" >/dev/null 2>&1; then ok "dataset ${name}"
    elif zpool list -H "${name%%/*}" >/dev/null 2>&1 || ! is_apply; then
      change "create dataset ${name}"
      local -a opts=()
      for prop in ${entry#"$name"}; do opts+=(-o "$prop"); done
      run zfs create -p "${opts[@]}" "$name"
    else
      warn "dataset ${name}: pool ${name%%/*} missing — skipped"
    fi
  done

  # Boot pool: cap /var/lib/vz, keep guests off it
  if zfs list -H rpool/var-lib-vz >/dev/null 2>&1 && [[ -n ${LOCAL_VZ_QUOTA:-} ]]; then
    if [[ $(zfs get -H -o value quota rpool/var-lib-vz) == "$LOCAL_VZ_QUOTA" ]]; then ok "rpool/var-lib-vz quota ${LOCAL_VZ_QUOTA}"
    else change "rpool/var-lib-vz quota -> ${LOCAL_VZ_QUOTA}"; run zfs set "quota=${LOCAL_VZ_QUOTA}" rpool/var-lib-vz; fi
  fi
  if [[ $(sort_csv "$(storage_prop local content)") == "$(sort_csv "$LOCAL_CONTENT")" ]]; then ok "storage local content ${LOCAL_CONTENT}"
  else change "storage local content -> ${LOCAL_CONTENT}"; run pvesm set local --content "$LOCAL_CONTENT"; fi
  if [[ ${REMOVE_LOCAL_ZFS:-no} == yes ]] && storage_exists local-zfs; then
    if [[ $(zfs list -H -r -o name rpool/data 2>/dev/null | wc -l) -gt 1 ]]; then
      warn "local-zfs (rpool/data) holds volumes — not removing"
    else
      change "remove storage local-zfs (no guest disks on the boot pool)"; run pvesm remove local-zfs
    fi
  fi

  # Guest pool storages
  local id pool content
  for entry in "${PVE_ZFS_STORAGES[@]}"; do
    IFS='|' read -r id pool content <<<"$entry"
    if storage_exists "$id"; then ok "storage ${id}"
    else change "add storage ${id} (zfspool ${pool}: ${content})"
      run pvesm add zfspool "$id" --pool "$pool" --content "$content" --sparse 1; fi
  done
}

# ----------------------------------------------------------------------------
# Stage: nas
# ----------------------------------------------------------------------------
stage_nas() {
  section "nas"
  if [[ -z ${NAS_SERVER:-} || ${#NAS_MOUNTS[@]} -eq 0 ]]; then info "no NAS configured — skipped"; return 0; fi
  local cred="${STATE_DIR}/nas-smb.cred"

  # Credentials file (root-only). Only prompts when missing or user changed.
  if [[ -f $cred ]] && grep -qxF "username=${NAS_SMB_USER}" "$cred"; then
    ok "$cred"
  elif is_apply; then
    read_secret NAS_SMB_PASSWORD "SMB password for ${NAS_SMB_USER}@${NAS_SERVER}"
    ensure_file "$cred" 0600 --secret < <(printf 'username=%s\npassword=%s\n' "$NAS_SMB_USER" "$NAS_SMB_PASSWORD")
    unset NAS_SMB_PASSWORD
  else
    change "$cred (password prompted at apply)"
  fi

  # Managed fstab block
  local entry id share content opts block="" base
  base="credentials=${cred},vers=${NAS_SMB_VERSION},noatime,_netdev,nofail,x-systemd.automount,x-systemd.mount-timeout=30"
  for entry in "${NAS_MOUNTS[@]}"; do
    IFS='|' read -r id share content opts <<<"$entry"
    block+="//${NAS_SERVER}/${share} /mnt/nas/${id} cifs ${base},${opts:-uid=0,gid=0,file_mode=0640,dir_mode=0750} 0 0"$'\n'
  done
  ensure_file /etc/fstab 0644 < <(
    sed '/^# BEGIN phoenixstack-nas$/,/^# END phoenixstack-nas$/d' /etc/fstab
    echo "# BEGIN phoenixstack-nas"
    printf '%s' "$block"
    echo "# END phoenixstack-nas")
  if [[ $FILE_CHANGED == yes ]] && is_apply; then
    for entry in "${NAS_MOUNTS[@]}"; do IFS='|' read -r id _ <<<"$entry"; mkdir -p "/mnt/nas/${id}"; done
    systemctl daemon-reload
    systemctl restart remote-fs.target
  fi

  # Mount check + PVE dir storages
  for entry in "${NAS_MOUNTS[@]}"; do
    IFS='|' read -r id share content opts <<<"$entry"
    if is_apply; then
      ls "/mnt/nas/${id}" >/dev/null 2>&1 || true   # trigger automount
      if findmnt -t cifs "/mnt/nas/${id}" >/dev/null; then ok "mounted //${NAS_SERVER}/${share}"
      else warn "//${NAS_SERVER}/${share} did not mount at /mnt/nas/${id} (journalctl -u 'mnt-nas-*')"; fi
    fi
    [[ $content == none ]] && continue
    if storage_exists "$id"; then ok "storage ${id}"; continue; fi
    change "add storage ${id} (dir /mnt/nas/${id}: ${content})"
    local -a extra=()
    [[ $content == *backup* ]] && extra=(--prune-backups "$NAS_DUMP_PRUNE")
    run pvesm add dir "$id" --path "/mnt/nas/${id}" --content "$content" --is_mountpoint yes "${extra[@]}"
  done
}

# ----------------------------------------------------------------------------
# Stage: access
# ----------------------------------------------------------------------------
pve_exists() { pvesh get "$1" --output-format json >/dev/null 2>&1; }
acl_has() {  # acl_has <path> <type:user|group|token> <ugid> <role>
  pvesh get /access/acl --output-format json \
    | A_PATH=$1 A_TYPE=$2 A_UGID=$3 A_ROLE=$4 perl -MJSON::PP -0777 -ne '
        exit((grep { $_->{path} eq $ENV{A_PATH} && $_->{type} eq $ENV{A_TYPE}
                  && $_->{ugid} eq $ENV{A_UGID} && $_->{roleid} eq $ENV{A_ROLE} } @{decode_json($_)}) ? 0 : 1)'
}
ensure_acl() {  # ensure_acl <path> <user|group|token> <ugid> <role>
  local path=$1 type=$2 ugid=$3 role=$4
  if acl_has "$path" "$type" "$ugid" "$role"; then ok "acl ${path} ${ugid} ${role}"; return 0; fi
  change "acl ${path} ${type} ${ugid} -> ${role}"
  run pveum acl modify "$path" "--${type}s" "$ugid" --roles "$role"
}

stage_access() {
  section "access"
  local entry

  # Admins group
  if pve_exists /access/groups/admins; then ok "group admins"
  else change "create group admins"; run pveum group add admins --comment "PhoenixStack administrators"; fi
  ensure_acl / group admins Administrator

  local userid email fullname
  for entry in "${ADMIN_USERS[@]}"; do
    IFS='|' read -r userid email fullname <<<"$entry"
    if pve_exists "/access/users/${userid}"; then ok "admin user ${userid}"; continue; fi
    change "create admin user ${userid}"
    run pveum user add "$userid" --groups admins --email "$email" --comment "$fullname"
    if is_apply; then
      info "set a password for ${userid}:"
      pveum passwd "$userid" </dev/tty
    fi
  done

  # Custom roles (drop privileges this PVE version doesn't know)
  local -a valid
  mapfile -t valid < <(pvesh get /access/roles/Administrator --output-format json | json_keys)
  local name privs priv kept cur
  for entry in "${PVE_ROLES[@]}"; do
    IFS='|' read -r name privs <<<"$entry"
    kept=""
    for priv in ${privs//,/ }; do
      if [[ " ${valid[*]} " == *" ${priv} "* ]]; then kept+="${kept:+,}${priv}"
      else warn "role ${name}: privilege '${priv}' unknown on this PVE — dropped"; fi
    done
    if pve_exists "/access/roles/${name}"; then
      cur=$(pvesh get "/access/roles/${name}" --output-format json | json_keys | paste -sd, -)
      if [[ $cur == "$(tr ',' '\n' <<<"$kept" | sort | paste -sd, -)" ]]; then ok "role ${name}"
      else change "update role ${name}"; run pveum role modify "$name" --privs "$kept"; fi
    else
      change "create role ${name}"; run pveum role add "$name" --privs "$kept"
    fi
  done

  # Service accounts + tokens (privsep: effective perms = user ∩ token ACLs)
  local role path token comment out secret
  for entry in "${SERVICE_ACCOUNTS[@]}"; do
    IFS='|' read -r userid role path token comment <<<"$entry"
    if pve_exists "/access/users/${userid}"; then ok "service user ${userid}"
    else change "create service user ${userid}"; run pveum user add "$userid" --comment "$comment"; fi
    ensure_acl "$path" user "$userid" "$role"

    if pve_exists "/access/users/${userid}/token/${token}"; then
      ok "token ${userid}!${token}"
    else
      change "create token ${userid}!${token} (secret shown once)"
      if is_apply; then
        out=$(pveum user token add "$userid" "$token" --privsep 1 --comment "$comment" --output-format json)
        secret=$(perl -MJSON::PP -0777 -ne 'print decode_json($_)->{value}' <<<"$out")
        printf '\n    %s┌─ STORE IN 1PASSWORD NOW — shown only once ─────────────%s\n' "$C_Y" "$C_0" >/dev/tty
        printf '    %s│%s token id: %s!%s\n' "$C_Y" "$C_0" "$userid" "$token" >/dev/tty
        printf '    %s│%s secret:   %s\n' "$C_Y" "$C_0" "$secret" >/dev/tty
        printf '    %s└────────────────────────────────────────────────────────%s\n' "$C_Y" "$C_0" >/dev/tty
        unset out secret
        read -r -p "    Press Enter once saved... " _ </dev/tty
      fi
    fi
    ensure_acl "$path" token "${userid}!${token}" "$role"
  done
}

# ----------------------------------------------------------------------------
# Stage: firewall
# ----------------------------------------------------------------------------
stage_firewall() {
  section "firewall"
  local cfw=/etc/pve/firewall/cluster.fw hfw="/etc/pve/nodes/${NODE_NAME}/host.fw"
  local had_c="no" had_h="no"
  [[ -f $cfw ]] && had_c="yes"
  [[ -f $hfw ]] && had_h="yes"

  local entry cidr comment changed="no"
  ensure_file "$cfw" 0640 < <(
    echo "# Managed by PhoenixStack pve-bootstrap.sh"
    echo "[OPTIONS]"
    echo "enable: 1"
    echo "policy_in: DROP"
    echo "policy_out: ACCEPT"
    echo
    echo "[IPSET management] # admin networks: GUI, SSH, SPICE"
    for entry in "${ADMIN_SOURCES[@]}"; do
      IFS='|' read -r cidr comment <<<"$entry"
      echo "${cidr} # ${comment}"
    done
    echo
    echo "[RULES]"
    echo "IN ACCEPT -source +management -p tcp -dport 8006 -log nolog # web GUI/API"
    echo "IN SSH(ACCEPT) -source +management -log nolog"
    echo "IN ACCEPT -source +management -p tcp -dport 3128 -log nolog # SPICE proxy"
    echo "IN Ping(ACCEPT) -source +management -log nolog")
  if [[ $FILE_CHANGED == yes ]]; then changed="yes"; fi

  ensure_file "$hfw" 0640 <<'EOF'
# Managed by PhoenixStack pve-bootstrap.sh
[OPTIONS]
enable: 1
nosmurfs: 1
tcpflags: 1
log_level_in: nolog
EOF
  if [[ $FILE_CHANGED == yes ]]; then changed="yes"; fi

  [[ $changed == yes ]] || return 0
  is_apply || { info "apply will activate with a ${ROLLBACK_SECS}s auto-rollback"; return 0; }

  local rb="${BACKUP_DIR}/rollback-firewall.sh"
  {
    echo "#!/bin/sh"
    if [[ $had_c == yes ]]; then echo "cp '${BACKUP_DIR}${cfw}' '${cfw}'"; else echo "rm -f '${cfw}'"; fi
    if [[ $had_h == yes ]]; then echo "cp '${BACKUP_DIR}${hfw}' '${hfw}'"; else echo "rm -f '${hfw}'"; fi
  } >"$rb"
  arm_rollback firewall "$rb"
  pve-firewall compile >/dev/null 2>"${BACKUP_DIR}/fw-compile.err" || true
  if [[ -s ${BACKUP_DIR}/fw-compile.err ]]; then sed 's/^/      /' "${BACKUP_DIR}/fw-compile.err"; fi
  info "waiting 15s for pve-firewall to load the new rules..."
  sleep 15
  pve-firewall status | sed 's/^/      /'
  info "test now from your workstation: open https://${MGMT_CIDR%/*}:8006 and a NEW ssh session"
  keep_or_rollback firewall "$rb"
}

# ----------------------------------------------------------------------------
# Stage: acme (optional)
# ----------------------------------------------------------------------------
stage_acme() {
  section "acme"
  if [[ ${ACME_ENABLE:-no} != yes ]]; then info "ACME_ENABLE=no — skipped"; return 0; fi

  if pvenode acme account list 2>/dev/null | grep -qw default; then ok "ACME account default"
  else
    change "register ACME account 'default' (${ACME_EMAIL})"
    run pvenode acme account register default "$ACME_EMAIL" --directory "$ACME_DIRECTORY"
  fi

  if pvenode acme plugin config cloudflare >/dev/null 2>&1; then ok "ACME plugin cloudflare"
  else
    change "add ACME DNS plugin cloudflare"
    if is_apply; then
      read_secret CF_API_TOKEN "Cloudflare API token (Zone:DNS:Edit on phoenixstack.net)"
      local data; data=$(mktemp); chmod 600 "$data"
      printf 'CF_Token=%s\n' "$CF_API_TOKEN" >"$data"
      pvenode acme plugin add dns cloudflare --api cf --data "$data"
      shred -u "$data" 2>/dev/null || rm -f "$data"
      unset CF_API_TOKEN
    fi
  fi

  if pvenode config get --property acmedomain0 2>/dev/null | grep -q "$NODE_FQDN"; then ok "acmedomain0 ${NODE_FQDN}"
  else change "acmedomain0 -> ${NODE_FQDN}"; run pvenode config set --acmedomain0 "domain=${NODE_FQDN},plugin=cloudflare"; fi

  if openssl x509 -in "/etc/pve/nodes/${NODE_NAME}/pveproxy-ssl.pem" -noout -issuer 2>/dev/null | grep -qi "let's encrypt"; then
    ok "ACME certificate installed"
  else
    change "order certificate for ${NODE_FQDN}"; run pvenode acme cert order
  fi
}

# ----------------------------------------------------------------------------
# Stage: verify (read-only)
# ----------------------------------------------------------------------------
check() {  # check <description> <command...>
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else warn "FAIL: $desc"; fi
}
stage_verify() {
  section "verify"
  check "rpool mirrored"                  sh -c 'zpool status rpool | grep -qE "^\s+mirror-"'
  check "all pools healthy"               sh -c '[ "$(zpool status -x)" = "all pools are healthy" ]'
  local p; for p in ${ZFS_POOLS:-}; do check "pool ${p} imported" zpool list -H "$p"; done
  check "all PVE storages active"         sh -c '! pvesm status 2>/dev/null | awk "NR>1 && \$3!=\"active\"" | grep -q .'
  check "vmbr0 VLAN-aware"                sh -c '[ "$(cat /sys/class/net/vmbr0/bridge/vlan_filtering)" = 1 ]'
  check "gateway ${MGMT_GATEWAY} reachable" ping -c 1 -W 2 "$MGMT_GATEWAY"
  check "IOMMU groups present"            sh -c 'ls /sys/kernel/iommu_groups | grep -q .'
  if [[ -n ${GPU_PCI_ADDR:-} ]]; then
    check "GPU ${GPU_PCI_ADDR} bound to vfio-pci" sh -c "lspci -nnk -s ${GPU_PCI_ADDR}.0 | grep -q 'in use: vfio-pci'"
    if [[ -n ${GPU_MAPPING_ID:-} ]]; then
      check "PCI mapping ${GPU_MAPPING_ID} exists" pvesh get "/cluster/mapping/pci/${GPU_MAPPING_ID}"
    fi
  fi
  check "ZFS ARC max ${ZFS_ARC_MAX_GIB} GiB" sh -c "[ \"\$(cat /sys/module/zfs/parameters/zfs_arc_max)\" = $((ZFS_ARC_MAX_GIB * 1024 * 1024 * 1024)) ]"
  check "firewall enabled/running"        sh -c 'pve-firewall status | grep -q "enabled/running"'
  check "SSH password auth disabled"      sh -c 'sshd -T 2>/dev/null | grep -qx "passwordauthentication no"'
  check "no enterprise repo enabled"      sh -c '! grep -l enterprise.proxmox.com /etc/apt/sources.list.d/*.sources 2>/dev/null | xargs -r grep -LiE "^Enabled:[[:space:]]*(no|false)" | grep -q .'
  check "running newest installed kernel" sh -c '[ "$(uname -r)" = "$(ls /lib/modules | sort -V | tail -1)" ]'
  check "time synchronized"               sh -c 'timedatectl show -p NTPSynchronized --value | grep -qx yes'
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
usage() { sed -n '2,/^# =====/p' "$0" | sed 's/^# \{0,1\}//; /^=====/d'; exit "${1:-0}"; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --config)       CONFIG=${2:?}; shift 2 ;;
      --config=*)     CONFIG=${1#*=}; shift ;;
      --apply)        MODE="apply"; shift ;;
      --plan)         MODE="plan"; shift ;;
      --stage)        IFS=, read -ra s <<<"${2:?}"; SELECTED_STAGES+=("${s[@]}"); shift 2 ;;
      --stage=*)      IFS=, read -ra s <<<"${1#*=}"; SELECTED_STAGES+=("${s[@]}"); shift ;;
      --destroy-data) DESTROY_DATA="yes"; shift ;;
      --version)      echo "$VERSION"; exit 0 ;;
      -h|--help)      usage 0 ;;
      *)              echo "unknown argument: $1" >&2; usage 1 ;;
    esac
  done
  [[ -n $CONFIG ]] || { echo "--config is required" >&2; usage 1; }
  local st
  for st in "${SELECTED_STAGES[@]}"; do
    [[ " ${ALL_STAGES[*]} " == *" ${st} "* ]] || die "unknown stage '${st}' (valid: ${ALL_STAGES[*]})"
  done
}

load_config() {
  [[ -r $CONFIG ]] || die "cannot read config: $CONFIG"
  if grep -v '^[[:space:]]*#' "$CONFIG" | grep -q 'REPLACE_ME'; then
    die "config still has REPLACE_ME placeholders: $(grep -n 'REPLACE_ME' "$CONFIG" | grep -v ':[[:space:]]*#' | cut -d: -f1 | paste -sd, -)"
  fi
  # shellcheck source=/dev/null
  source "$CONFIG"
  local v
  for v in NODE_NAME NODE_DOMAIN MGMT_CIDR MGMT_GATEWAY DNS_SERVERS UPLINK_MACS BOND_MODE BRIDGE_VIDS ZFS_ARC_MAX_GIB; do
    [[ -n ${!v:-} ]] || die "config: ${v} is required"
  done
  [[ ${#ROOT_SSH_KEYS[@]} -gt 0 ]] || die "config: ROOT_SSH_KEYS is empty"
  [[ ${#ADMIN_SOURCES[@]} -gt 0 ]] || die "config: ADMIN_SOURCES is empty (you would be locked out)"
  NODE_FQDN="${NODE_NAME}.${NODE_DOMAIN}"
}

main() {
  parse_args "$@"
  [[ $EUID -eq 0 ]] || die "must run as root"
  load_config

  exec 9>"$LOCK_FILE"
  flock -n 9 || die "another pve-bootstrap run is in progress"

  printf '%sPhoenixStack pve-bootstrap %s — %s — %s%s\n' "$C_B" "$VERSION" "$NODE_FQDN" "${MODE^^}" "$C_0"
  if is_apply; then
    mkdir -p "$BACKUP_DIR" "$STATE_DIR"; chmod 700 "$STATE_DIR"
    exec > >(tee -a "${BACKUP_DIR}/run.log") 2>&1
  fi

  local -a stages=("${SELECTED_STAGES[@]}")
  ((${#stages[@]})) || stages=("${ALL_STAGES[@]}")
  stage_preflight
  local st
  for st in "${ALL_STAGES[@]}"; do          # always run in canonical order
    [[ $st == preflight ]] && continue
    [[ " ${stages[*]} " == *" ${st} "* ]] || continue
    "stage_${st}"
  done

  section "summary"
  if is_apply; then
    echo "$VERSION $RUN_ID ${stages[*]}" >>"${STATE_DIR}/bootstrap.history"
    info "changes applied: ${CHANGES}   warnings: ${WARNINGS}   backups/log: ${BACKUP_DIR}"
  else
    info "changes pending: ${CHANGES}   warnings: ${WARNINGS}"
    ((CHANGES == 0)) || info "nothing was changed — re-run with --apply to make these changes"
  fi
  if [[ $REBOOT_REQUIRED == yes ]]; then warn "REBOOT REQUIRED before continuing (kernel/initramfs/boot changes)"; fi
}

main "$@"
