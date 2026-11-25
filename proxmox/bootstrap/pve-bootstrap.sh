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
#   access     admins group/users, resource pools, roles, service accounts + API tokens
#              (a service account's ACLs are set to exactly its configured grants)
#   templates  LXC templates (LXC_TEMPLATES) from the Proxmox appliance index; VM templates
#              (VM_TEMPLATES) from checksum-verified cloud images, with cloud-init vendor data
#   firewall   datacenter default-DROP + admin ipset (auto-rollback unless confirmed)
#   notify     root@pam email; SMTP notification target + alert/backup matchers
#              (the SMTP part only if NOTIFY_SMTP_ENABLE=yes)
#   pbs        Proxmox Backup Server on this host: datastore, prune/GC/verify jobs,
#              backup user + token, PVE storage (only if PBS_ENABLE=yes)
#   backups    PVE backup jobs (BACKUP_JOBS): nightly to PBS and to the NAS
#   acme       Let's Encrypt certs for the PVE and PBS GUIs via Cloudflare DNS-01; PVE then
#              reaches PBS by name instead of a pinned fingerprint (only if ACME_ENABLE=yes)
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

readonly VERSION="2026.11.7"
readonly ALL_STAGES=(preflight repos system network kernel nas storage access templates firewall notify pbs backups acme verify)
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

# read_value <var> <prompt> — from env var of the same name, else visible prompt.
# For values that are private but not secret (kept out of the public repo).
read_value() {
  local __var=$1 prompt=$2 v=""
  if [[ -n ${!__var:-} ]]; then return 0; fi
  read -r -p "    ${prompt}: " v </dev/tty
  [[ -n $v ]] || die "${prompt}: empty"
  printf -v "$__var" '%s' "$v"
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

# JSON helpers (perl JSON::PP is always present on PVE; jq may not be yet). All read JSON on
# stdin. json_get and json_find print nothing when the input isn't JSON (the object is missing).
json_keys() { perl -MJSON::PP -0777 -ne 'my $d=decode_json($_); print "$_\n" for sort keys %$d'; }
# json_get <key> — a top-level value: a list is sorted and comma-joined, true/false print as 1/0
json_get() {
  perl -MJSON::PP -0777 -ne 'BEGIN { $k = shift @ARGV }
    my $d = eval { decode_json($_) }; exit 0 unless ref $d eq "HASH";
    my $v = $d->{$k}; print ref $v eq "ARRAY" ? join(",", sort @$v) : ($v // "")' "$1"
}
# json_find <print-key> <key=value>... — in a JSON list, print <print-key> of the first element
# matching every key=value pair. Exit status 1 when none matches.
json_find() {
  perl -MJSON::PP -0777 -ne 'BEGIN { $p = shift @ARGV; @c = map { [split /=/, $_, 2] } splice @ARGV }
    my $l = eval { decode_json($_) }; exit 1 unless ref $l eq "ARRAY";
    for my $e (@$l) {
      next if grep { ($e->{$_->[0]} // "") ne $_->[1] } @c;
      print $e->{$p} // ""; exit 0;
    }
    exit 1' "$@"
}

# PVE and PBS API readers. *_json fails when the object doesn't exist; *_get prints one value or nothing.
pve_json()   { pvesh get "$1" --output-format json 2>/dev/null; }
pve_exists() { pve_json "$1" >/dev/null; }
pve_get()    { { pve_json "$1" || true; } | json_get "$2"; }                      # pve_get <path> <key>
pbs_json()   { proxmox-backup-manager "$@" --output-format json 2>/dev/null; }
pbs_get()    { { pbs_json "${@:2}" || true; } | json_get "$1"; }                  # pbs_get <key> <subcommand...>
pbs_has()    { pbs_json "${@:3}" | json_find "$1" "$1=$2" >/dev/null; }           # pbs_has <key> <value> <list-subcommand...>
# key_label <public key>: its fingerprint and comment, for messages. Never the key itself: a key
# without a comment would otherwise be printed whole.
key_label() {
  local fp comment
  fp=$(ssh-keygen -lf /dev/stdin <<<"$1" 2>/dev/null | awk '{print $2}')
  read -r _ _ comment <<<"$1"
  echo "${fp:-unreadable key}${comment:+ ($comment)}"
}

readonly PVE_CERT_DIR="/etc/pve/nodes" PBS_CERT="/etc/proxmox-backup/proxy.pem"
cert_from_le()    { openssl x509 -in "$1" -noout -issuer 2>/dev/null | grep -qi "let's encrypt"; }   # cert_from_le <pem>
os_codename()     { sed -n 's/^VERSION_CODENAME=//p' /etc/os-release | tr -d '"'; }   # parsed, not sourced: os-release sets VERSION
pkg_installed()   { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }
newest_kernel()   { find /lib/modules -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -V | tail -1; }
pending_updates() { apt-get -s dist-upgrade 2>/dev/null | grep -c '^Inst' || true; }

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
# disable_enterprise_repos — the Proxmox enterprise repos need a subscription; installing
# PVE or PBS packages can add them (enabled). Used by the repos and pbs stages.
disable_enterprise_repos() {
  local f
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
}

# ensure_proxmox_repo <file> <pve|pbs> — the no-subscription repo for that product
ensure_proxmox_repo() {
  local codename
  codename=$(os_codename)
  [[ -n $codename ]] || die "could not read VERSION_CODENAME from /etc/os-release"
  ensure_file "/etc/apt/sources.list.d/$1" 0644 <<EOF
# Managed by PhoenixStack pve-bootstrap.sh
Types: deb
URIs: http://download.proxmox.com/debian/$2
Suites: ${codename}
Components: $2-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
}

stage_repos() {
  section "repos"
  disable_enterprise_repos
  ensure_proxmox_repo proxmox.sources pve

  run apt-get update -q
  local -a missing=()
  local pkg
  for pkg in $EXTRA_PACKAGES; do pkg_installed "$pkg" || missing+=("$pkg"); done

  if is_apply; then
    DEBIAN_FRONTEND=noninteractive apt-get -y -q \
      -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold dist-upgrade
    if ((${#missing[@]})); then
      change "install: ${missing[*]}"
      DEBIAN_FRONTEND=noninteractive apt-get -y -q install "${missing[@]}"
    fi
  else
    info "upgradable now (from current lists): $(pending_updates) package(s)"
    if ((${#missing[@]})); then change "install: ${missing[*]}"; else ok "extra packages present"; fi
  fi

  local newest
  newest=$(newest_kernel)
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

  # ZFS trim and scrub. Debian's cron runs them at 00:24 host time on the first and second Sunday,
  # which on a UTC clock is Saturday evening in Denver. Its file is set aside with dpkg-divert (a
  # name with a dot, which cron ignores; package upgrades update that copy, never the original), and
  # ours runs the same scripts on the same Sundays at ZFS_MAINTENANCE_TIME.
  local zfs_cron=/etc/cron.d/zfsutils-linux zfs_aside=/etc/cron.d/zfsutils-linux.phoenix-diverted
  local zfs_h=${ZFS_MAINTENANCE_TIME%%:*} zfs_m=${ZFS_MAINTENANCE_TIME##*:}
  [[ $zfs_h =~ ^[0-9]{1,2}$ && $zfs_m =~ ^[0-9]{2}$ ]] || die "ZFS_MAINTENANCE_TIME must be HH:MM (got ${ZFS_MAINTENANCE_TIME})"
  if [[ $(dpkg-divert --truename "$zfs_cron") == "$zfs_aside" ]]; then ok "Debian's ZFS cron set aside (${zfs_aside})"
  else
    change "set Debian's ZFS cron aside: ${zfs_cron} -> ${zfs_aside}"
    run dpkg-divert --local --rename --divert "$zfs_aside" --add "$zfs_cron"
  fi
  ensure_file /etc/cron.d/phoenix-zfs-maintenance 0644 <<EOF
# Managed by PhoenixStack pve-bootstrap.sh: Debian's ZFS trim and scrub (its cron file is diverted
# to ${zfs_aside}), at ${ZFS_MAINTENANCE_TIME} host time (UTC) instead of 00:24.
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# TRIM the first Sunday of every month.
$((10#$zfs_m)) $((10#$zfs_h)) 1-7 * * root if [ \$(date +\%w) -eq 0 ] && [ -x /usr/lib/zfs-linux/trim ]; then /usr/lib/zfs-linux/trim; fi
# Scrub the second Sunday of every month.
$((10#$zfs_m)) $((10#$zfs_h)) 8-14 * * root if [ \$(date +\%w) -eq 0 ] && [ -x /usr/lib/zfs-linux/scrub ]; then /usr/lib/zfs-linux/scrub; fi
EOF

  # SSH: make sure our keys are present BEFORE turning off password auth.
  local ak=/root/.ssh/authorized_keys key present=0
  for key in "${ROOT_SSH_KEYS[@]}"; do
    [[ -n $key ]] || continue
    if grep -qF "$key" "$ak" 2>/dev/null; then
      ok "root SSH key present: $(key_label "$key")"; present=$((present + 1))
    else
      change "add root SSH key: $(key_label "$key")"
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
      if pve_exists "/cluster/mapping/pci/${GPU_MAPPING_ID}"; then
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
# Stage: templates
# ----------------------------------------------------------------------------
# Templates are named <prefix>_<version>_<arch>.tar.<ext>. The appliance index lists several
# architectures (amd64 and arm64), so every match is limited to this host's.
host_arch() { dpkg --print-architecture; }

# template_matches <prefix> <field> — names in field <field> of stdin that are <prefix> templates for this host
template_matches() {
  awk -v p="$1" -v a="$(host_arch)" -v f="$2" '{ n = $f; sub(/^.*\//, "", n) }
    index(n, p "_") == 1 && n ~ ("_" a "\\.tar\\.") {print $f}' | sort -V | tail -1
}

# template_present <storage> <prefix> — newest matching vztmpl volume on <storage>, or nothing
template_present() {
  { pveam list "$1" 2>/dev/null || true; } | template_matches "$2" 1
}

# ensure_vm_template "vmid|name|storage|pool|vlan|base-url|file" — build the template if the VMID is free
ensure_vm_template() {
  local vmid name storage pool vlan base file cfg tmp sum
  IFS='|' read -r vmid name storage pool vlan base file <<<"$1"
  if cfg=$(qm config "$vmid" 2>/dev/null); then
    if grep -qx 'template: 1' <<<"$cfg" && grep -qx "name: ${name}" <<<"$cfg"; then ok "VM template ${vmid} ${name}"
    else warn "VMID ${vmid} exists but isn't template '${name}' — left alone"; fi
    return 0
  fi
  change "create VM template ${vmid} ${name} from ${file} (disk on ${storage}, pool ${pool}, NIC VLAN ${vlan})"
  if ! is_apply; then
    info "[plan] download ${base}/${file}, check it against SHA512SUMS, qm create, import the disk, add a cloud-init drive, qm template"
    return 0
  fi
  tmp=$(mktemp -d /var/tmp/phoenix-template.XXXXXX)
  info "downloading ${file} ..."
  curl -fsSL --proto =https --tlsv1.2 -o "${tmp}/${file}" "${base}/${file}"
  curl -fsSL --proto =https --tlsv1.2 -o "${tmp}/SHA512SUMS" "${base}/SHA512SUMS"
  if ! (cd "$tmp" && grep -E " [*]?${file}\$" SHA512SUMS | sha512sum -c --status); then
    rm -rf "$tmp"; die "${file}: SHA512 doesn't match ${base}/SHA512SUMS — template not created"
  fi
  sum=$(grep -E " [*]?${file}\$" "${tmp}/SHA512SUMS" | cut -c1-16)
  ok "${file} SHA512 ${sum}… matches"
  run qm create "$vmid" --name "$name" --pool "$pool" --ostype l26 --machine q35 --cpu x86-64-v2-AES \
    --cores 1 --memory 1024 --scsihw virtio-scsi-single --net0 "virtio,bridge=vmbr0,tag=${vlan},firewall=1" \
    --agent enabled=1 --serial0 socket --vga serial0 --tags "template;debian13" \
    --description "Built by pve-bootstrap ${VERSION} on $(date +%F) from ${base}/${file} (SHA512 ${sum}...)"
  run qm set "$vmid" --scsi0 "${storage}:0,import-from=${tmp}/${file},discard=on,ssd=1" \
    --ide2 "${storage}:cloudinit" --boot order=scsi0 --cicustom "vendor=local:snippets/${CI_VENDOR_SNIPPET}"
  run qm template "$vmid"
  rm -rf "$tmp"
}

stage_templates() {
  section "templates"
  local entry storage prefix have want
  for entry in ${LXC_TEMPLATES[@]+"${LXC_TEMPLATES[@]}"}; do
    IFS='|' read -r storage prefix <<<"$entry"
    have=$(template_present "$storage" "$prefix")
    if [[ -n $have ]]; then ok "template ${have}"; continue; fi
    # The index is refreshed daily by pve-daily-update; refresh it now only when applying.
    if is_apply; then pveam update >/dev/null 2>&1 || warn "pveam update failed — using the cached index"; fi
    want=$({ pveam available --section system 2>/dev/null || true; } | template_matches "$prefix" 2)
    if [[ -z $want ]]; then
      warn "no $(host_arch) template matching '${prefix}' in the appliance index (pveam available --section system)"
      continue
    fi
    change "download template ${want} to ${storage}"
    run pveam download "$storage" "$want"
  done

  [[ ${#VM_TEMPLATES[@]} -gt 0 ]] || return 0
  # Vendor data for every guest cloned from a VM template (merged with the user data PVE generates
  # from the guest's cloud-init settings: user, SSH key, IP).
  ensure_file "/var/lib/vz/snippets/${CI_VENDOR_SNIPPET}" 0644 <<'EOF'
#cloud-config
# Managed by PhoenixStack pve-bootstrap.sh: vendor data for guests cloned from VM templates.
package_update: true
packages:
  - qemu-guest-agent
runcmd:
  - [systemctl, enable, --now, qemu-guest-agent]
EOF
  for entry in "${VM_TEMPLATES[@]}"; do ensure_vm_template "$entry"; done
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
ensure_acl() {  # ensure_acl <path> <user|group|token> <ugid> <role>
  local path=$1 type=$2 ugid=$3 role=$4
  if pve_json /access/acl | json_find path "path=$path" "type=$type" "ugid=$ugid" "roleid=$role" >/dev/null; then
    ok "acl ${path} ${ugid} ${role}"; return 0
  fi
  change "acl ${path} ${type} ${ugid} -> ${role}"
  run pveum acl modify "$path" "--${type}s" "$ugid" --roles "$role"
}

# acl_entries <user|token|group> <ugid> — one "path role" line per ACL entry it holds
acl_entries() {
  { pve_json /access/acl || true; } | perl -MJSON::PP -0777 -ne 'BEGIN { ($t, $u) = splice @ARGV, 0, 2 }
    my $l = eval { decode_json($_) }; exit 0 unless ref $l eq "ARRAY";
    print "$_->{path} $_->{roleid}\n" for grep { $_->{type} eq $t && $_->{ugid} eq $u } @$l' "$1" "$2"
}

# grants_lines <grants> — "path=role path=role" as sorted "path role" lines (compare with acl_entries)
grants_lines() { words "$1" | tr '=' ' ' | sort; }

# ensure_grants <user|token> <ugid> <grants> — exactly these ACL entries: add missing, remove others
ensure_grants() {
  local type=$1 ugid=$2 grants=$3 g path role
  for g in $grants; do ensure_acl "${g%%=*}" "$type" "$ugid" "${g#*=}"; done
  while read -r path role; do
    [[ -n $path ]] || continue
    [[ " ${grants} " == *" ${path}=${role} "* ]] && continue
    change "remove acl ${path} ${type} ${ugid} ${role} (not in config)"
    run pveum acl delete "$path" "--${type}s" "$ugid" --roles "$role"
  done < <(acl_entries "$type" "$ugid")
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
    run pveum user add "$userid" --groups admins ${email:+--email "$email"} --comment "$fullname"
    if is_apply; then
      info "set a password for ${userid}:"
      pveum passwd "$userid" </dev/tty
    fi
  done

  # Resource pools
  local poolid pcomment
  for entry in ${PVE_POOLS[@]+"${PVE_POOLS[@]}"}; do
    IFS='|' read -r poolid pcomment <<<"$entry"
    if { pve_json /pools || true; } | json_find poolid "poolid=${poolid}" >/dev/null; then ok "pool ${poolid}"
    else change "create pool ${poolid}"; run pveum pool add "$poolid" --comment "$pcomment"; fi
  done

  # Custom roles (drop privileges this PVE version doesn't know)
  local -a valid
  mapfile -t valid < <(pve_json /access/roles/Administrator | json_keys)
  local name privs priv kept cur
  for entry in "${PVE_ROLES[@]}"; do
    IFS='|' read -r name privs <<<"$entry"
    kept=""
    for priv in ${privs//,/ }; do
      if [[ " ${valid[*]} " == *" ${priv} "* ]]; then kept+="${kept:+,}${priv}"
      else warn "role ${name}: privilege '${priv}' unknown on this PVE — dropped"; fi
    done
    if pve_exists "/access/roles/${name}"; then
      cur=$(pve_json "/access/roles/${name}" | json_keys | paste -sd, -)
      if [[ $cur == "$(sort_csv "$kept")" ]]; then ok "role ${name}"
      else change "update role ${name}"; run pveum role modify "$name" --privs "$kept"; fi
    else
      change "create role ${name}"; run pveum role add "$name" --privs "$kept"
    fi
  done

  # Service accounts + tokens (privsep: effective perms = user ∩ token ACLs, so both get the same grants)
  local grants g token comment out secret
  for entry in "${SERVICE_ACCOUNTS[@]}"; do
    IFS='|' read -r userid grants token comment <<<"$entry"
    for g in $grants; do
      [[ $g == /*=?* ]] || die "SERVICE_ACCOUNTS ${userid}: grant '${g}' is not path=role"
    done
    if pve_exists "/access/users/${userid}"; then ok "service user ${userid}"
    else change "create service user ${userid}"; run pveum user add "$userid" --comment "$comment"; fi
    ensure_grants user "$userid" "$grants"

    if pve_exists "/access/users/${userid}/token/${token}"; then
      ok "token ${userid}!${token}"
    else
      change "create token ${userid}!${token} (secret shown once)"
      if is_apply; then
        out=$(pveum user token add "$userid" "$token" --privsep 1 --comment "$comment" --output-format json)
        secret=$(json_get value <<<"$out")
        printf '\n    %s┌─ STORE IN 1PASSWORD NOW — shown only once ─────────────%s\n' "$C_Y" "$C_0" >/dev/tty
        printf '    %s│%s token id: %s!%s\n' "$C_Y" "$C_0" "$userid" "$token" >/dev/tty
        printf '    %s│%s secret:   %s\n' "$C_Y" "$C_0" "$secret" >/dev/tty
        printf '    %s└────────────────────────────────────────────────────────%s\n' "$C_Y" "$C_0" >/dev/tty
        unset out secret
        read -r -p "    Press Enter once saved... " _ </dev/tty
      fi
    fi
    ensure_grants token "${userid}!${token}" "$grants"
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
    # PVE adds the auto-detected local network (the host's whole subnet) to the
    # management ipset. Guests share that subnet via DHCP, so pin it to the host
    # itself: only ADMIN_SOURCES reach the admin ports. (Single node, no corosync.)
    echo "[ALIASES]"
    echo "local_network ${MGMT_CIDR%/*}/32 # host only, overrides auto-detected subnet"
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
    echo "IN Ping(ACCEPT) -source +management -log nolog"
    if [[ ${PBS_ENABLE:-no} == yes ]]; then
      echo "IN ACCEPT -source +management -p tcp -dport 8007 -log nolog # Proxmox Backup Server GUI/API"
    fi)
  if [[ $FILE_CHANGED == yes ]]; then changed="yes"; fi

  # log_level_in: dropped/rejected inbound packets go to /var/log/pve-firewall.log
  # (rate-limited by PVE: 1 line/second with a burst of 5, and rotated).
  ensure_file "$hfw" 0640 <<EOF
# Managed by PhoenixStack pve-bootstrap.sh
[OPTIONS]
enable: 1
nosmurfs: 1
tcpflags: 1
log_level_in: ${FIREWALL_LOG_LEVEL_IN:-nolog}
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
# Stage: notify (optional) — PVE notification system → SMTP relay
# ----------------------------------------------------------------------------
# ensure_matcher <name> <description> <match args...> — create if missing (target = SMTP target)
ensure_matcher() {
  local name=$1 desc=$2; shift 2
  if pve_exists "/cluster/notifications/matchers/${name}"; then ok "matcher ${name}"; return 0; fi
  change "add matcher ${name}: ${desc} -> ${NOTIFY_SMTP_NAME}"
  run pvesh create /cluster/notifications/matchers --name "$name" --target "$NOTIFY_SMTP_NAME" \
    --comment "Managed by pve-bootstrap: ${desc}" "$@"
}

# pve_notify_value <target> <key> [file] — one value from PVE's notification config section
# (the SMTP key is only in /etc/pve/priv/notifications.cfg, which the API never returns)
pve_notify_value() {
  awk -v sec="smtp: $1" -v key="$2" '
    /^[a-z]+: / { insec = ($0 == sec) }
    insec && $1 == key { sub(/^[ \t]*[^ \t]+[ \t]+/, ""); print; exit }' "${3:-/etc/pve/notifications.cfg}"
}

# notify_test <pve|pbs> — send a test through the SMTP target
notify_test() {
  local n=$NOTIFY_SMTP_NAME sent="no"
  case $1 in
    pve) if pvesh create "/cluster/notifications/targets/${n}/test" >/dev/null; then sent="yes"; fi ;;
    pbs) if proxmox-backup-manager notification target test "$n" >/dev/null; then sent="yes"; fi ;;
  esac
  if [[ $sent == yes ]]; then ok "${1^^} test notification sent — check ${NOTIFY_MAILTO} (and its spam folder)"; return 0; fi
  warn "${1^^} test notification failed. A 535 error means a wrong login or key (Brevo: the SMTP key, xsmtpsib-…, not the API key)."
  info "This stage won't ask for the key again: fix it in the ${1^^} GUI (Notifications → ${n} → Edit), then use Test there."
}

stage_notify() {
  section "notify"

  # root@pam's address: where the built-in mail-to-root target and the host's own root mail
  # (ZFS events, smartd, cron) are forwarded. Set by the installer; kept in step with the config here.
  local cur
  cur=$(pve_get /access/users/root@pam email)
  if [[ $cur == "$ROOT_EMAIL" ]]; then ok "root@pam email ${ROOT_EMAIL}"
  else
    change "root@pam email -> ${ROOT_EMAIL}; was: ${cur:-none}"
    run pveum user modify root@pam --email "$ROOT_EMAIL"
  fi

  if [[ ${NOTIFY_SMTP_ENABLE:-no} != yes ]]; then info "NOTIFY_SMTP_ENABLE=no — skipped"; return 0; fi
  local n=$NOTIFY_SMTP_NAME smtp="/cluster/notifications/endpoints/smtp/${NOTIFY_SMTP_NAME}"

  # SMTP target. Login, From address and key are not in git (public repo): prompted or env.
  if pve_exists "$smtp"; then
    local retest="no"
    cur=$(pve_get "$smtp" mailto)
    if [[ $cur == "$NOTIFY_MAILTO" ]]; then ok "SMTP target ${n} -> ${NOTIFY_MAILTO}"
    else
      change "SMTP target ${n} recipient -> ${NOTIFY_MAILTO}; was: ${cur:-none}"
      run pvesh set "$smtp" --mailto "$NOTIFY_MAILTO"
      retest="yes"
    fi
    # From address: not in git. Only checked when given in env NOTIFY_SMTP_FROM
    # (use it when the verified sender at the relay changes).
    if [[ -n ${NOTIFY_SMTP_FROM:-} ]]; then
      cur=$(pve_notify_value "$n" from-address)
      if [[ $cur == "$NOTIFY_SMTP_FROM" ]]; then ok "SMTP target ${n} From address matches NOTIFY_SMTP_FROM"
      else
        change "SMTP target ${n} From address -> ${NOTIFY_SMTP_FROM}; was: ${cur:-none}"
        run pvesh set "$smtp" --from-address "$NOTIFY_SMTP_FROM"
        retest="yes"
      fi
    fi
    if [[ $retest == yes ]] && is_apply; then notify_test pve; fi
  else
    change "add SMTP target ${n}: ${NOTIFY_SMTP_SERVER}:${NOTIFY_SMTP_PORT} (${NOTIFY_SMTP_MODE}) -> ${NOTIFY_MAILTO} (login, From and key prompted)"
    if is_apply; then
      read_value  NOTIFY_SMTP_USER     "SMTP login"
      read_value  NOTIFY_SMTP_FROM     "From address (a verified sender at the relay)"
      read_secret NOTIFY_SMTP_PASSWORD "SMTP key for ${NOTIFY_SMTP_USER}"
      # Not via run(): never print the key.
      pvesh create /cluster/notifications/endpoints/smtp --name "$n" \
        --server "$NOTIFY_SMTP_SERVER" --port "$NOTIFY_SMTP_PORT" --mode "$NOTIFY_SMTP_MODE" \
        --username "$NOTIFY_SMTP_USER" --password "$NOTIFY_SMTP_PASSWORD" \
        --from-address "$NOTIFY_SMTP_FROM" --mailto "$NOTIFY_MAILTO" \
        --comment "Managed by pve-bootstrap" >/dev/null
      unset NOTIFY_SMTP_PASSWORD
      ok "SMTP target ${n} created"
      notify_test pve
    fi
  fi

  local -a sev=() sv
  for sv in ${NOTIFY_SEVERITIES//,/ }; do sev+=(--match-severity "$sv"); done
  ensure_matcher phoenix-alerts "severity ${NOTIFY_SEVERITIES}" "${sev[@]}"
  if [[ ${NOTIFY_ALL_BACKUP_JOBS:-no} == yes ]]; then
    ensure_matcher phoenix-backups "every backup job result" --match-field "exact:type=vzdump"
  elif pve_exists "/cluster/notifications/matchers/phoenix-backups"; then
    change "remove matcher phoenix-backups (NOTIFY_ALL_BACKUP_JOBS=no; failures still match phoenix-alerts)"
    run pvesh delete /cluster/notifications/matchers/phoenix-backups
  fi

  # Mail the host's daemons send to root (ZFS events, smartd, cron) enters the notification
  # system as type "system-mail" with no severity, so phoenix-alerts doesn't match it.
  ensure_matcher phoenix-system-mail "mail sent to root by host daemons (ZFS events, smartd, cron)" \
    --match-field "exact:type=system-mail"

  # "Updates available" notices. The daily update job (pve-daily-update.timer) only sends
  # them on hosts without a subscription when notify package-updates=always, and they are
  # severity info, so they need their own matcher.
  if [[ ${NOTIFY_PACKAGE_UPDATES:-no} == yes ]]; then
    ensure_matcher phoenix-updates "new package updates available" --match-field "exact:type=package-updates"
    local dc=/etc/pve/datacenter.cfg
    if grep -qE '^notify:.*package-updates=always' "$dc" 2>/dev/null; then ok "daily update job announces new updates (package-updates=always)"
    elif grep -E '^notify:' "$dc" 2>/dev/null | grep -qvE '^notify:[[:space:]]*package-updates=[a-z]+[[:space:]]*$'; then
      warn "datacenter.cfg has other 'notify' settings — set package-updates=always by hand (Datacenter → Options)"
    else
      change "daily update job announces new updates: notify package-updates=always"
      run pvesh set /cluster/options --notify package-updates=always
    fi
  fi

  # The built-in mail-to-root target sends through the host's local mail system, which
  # can't deliver off-host here (tested 2026-11-16). Off, so nothing is queued or bounced.
  if [[ ${NOTIFY_MAIL_TO_ROOT:-on} == off ]]; then
    if [[ $(pve_get /cluster/notifications/endpoints/sendmail/mail-to-root disable) == 1 ]]; then ok "built-in target mail-to-root disabled"
    else
      change "disable built-in target mail-to-root (local mail can't deliver off-host; ${n} carries the alerts)"
      run pvesh set /cluster/notifications/endpoints/sendmail/mail-to-root --disable 1
    fi
  fi
}

# ----------------------------------------------------------------------------
# Stage: pbs (optional) — Proxmox Backup Server on this host
# ----------------------------------------------------------------------------
ensure_pbs_acl() {  # ensure_pbs_acl <path> <auth-id> <role>
  if pbs_json acl list | json_find path "path=$1" "ugid=$2" "roleid=$3" >/dev/null; then ok "acl $1 $2 $3"; return 0; fi
  change "acl $1 $2 -> $3"
  run proxmox-backup-manager acl update "$1" "$3" --auth-id "$2"
}

# ensure_pbs_storage [token-secret] — PVE storage for the PBS datastore. The token secret goes
# straight from PBS into PVE (/etc/pve/priv) and is never shown. A token can only get an ACL after
# it exists, so it's created, granted and handed to PVE together. With a secret given, that token
# is reused (the acme stage re-creates the storage this way).
# With PBS's self-signed certificate PVE connects to 127.0.0.1 and pins the fingerprint. With a
# Let's Encrypt certificate it connects by name and checks the certificate normally, so a renewal
# (a new fingerprint every two months) can't break backups.
ensure_pbs_storage() {
  local ds=$PBS_DATASTORE auth="${PBS_USER}!${PBS_TOKEN}" secret=${1:-} how
  if storage_exists "$PBS_PVE_STORAGE"; then
    ok "storage ${PBS_PVE_STORAGE} (server $(storage_prop "$PBS_PVE_STORAGE" server))"
    ensure_pbs_acl "/datastore/${ds}" "$auth" DatastoreBackup
    return 0
  fi
  if cert_from_le "$PBS_CERT"; then how="server ${NODE_FQDN}, trusted certificate"; else how="server 127.0.0.1, pinned fingerprint"; fi
  change "add PVE storage ${PBS_PVE_STORAGE} (${how}; keep-all: PBS prunes) with token ${auth}"
  is_apply || return 0

  if [[ -z $secret ]]; then
    if pbs_json user list-tokens "$PBS_USER" | grep -q "\"${auth}\""; then
      warn "token ${auth} exists but its secret is unknown — regenerating"
      proxmox-backup-manager user delete-token "$PBS_USER" "$PBS_TOKEN" >/dev/null
    fi
    # generate-token has no --output-format; it prints "Result: {json}".
    secret=$(proxmox-backup-manager user generate-token "$PBS_USER" "$PBS_TOKEN" \
      | perl -MJSON::PP -0777 -ne 's/^\s*Result:\s*//; print decode_json($_)->{value}')
    [[ -n $secret ]] || die "could not create token ${auth}"
    ok "token ${auth} created"
  fi
  proxmox-backup-manager acl update "/datastore/${ds}" DatastoreBackup --auth-id "$auth"

  local -a target
  if cert_from_le "$PBS_CERT"; then
    target=(--server "$NODE_FQDN")
  else
    local fp
    fp=$(proxmox-backup-manager cert info | awk '/Fingerprint/{print $NF}')
    [[ -n $fp ]] || die "could not read the PBS certificate fingerprint"
    target=(--server 127.0.0.1 --fingerprint "$fp")
  fi
  # Not via run(): never print the secret.
  pvesm add pbs "$PBS_PVE_STORAGE" "${target[@]}" --datastore "$ds" --username "$auth" \
    --password "$secret" --content backup --prune-backups keep-all=1
  unset secret
  ok "storage ${PBS_PVE_STORAGE} added (${how})"
}

stage_pbs() {
  section "pbs"
  if [[ ${PBS_ENABLE:-no} != yes ]]; then info "PBS_ENABLE=no — skipped"; return 0; fi
  local ds=$PBS_DATASTORE auth="${PBS_USER}!${PBS_TOKEN}" installed="no"

  ensure_proxmox_repo pbs.sources pbs
  if pkg_installed proxmox-backup-server; then
    ok "proxmox-backup-server installed"; installed="yes"
  else
    change "install proxmox-backup-server"
    if is_apply; then
      apt-get update -q
      DEBIAN_FRONTEND=noninteractive apt-get -y -q install proxmox-backup-server
      installed="yes"
    fi
  fi
  disable_enterprise_repos               # the package adds pbs-enterprise.sources
  if [[ $installed != yes ]]; then
    info "(plan) once installed: datastore ${ds} on ${PBS_DATASTORE_PATH}, prune/GC/verify jobs, ${auth}, PVE storage ${PBS_PVE_STORAGE}"
    return 0
  fi

  # Datastore (its GC schedule is kept in step with the config)
  local cur_sched
  if pbs_has name "$ds" datastore list; then
    cur_sched=$(pbs_get gc-schedule datastore show "$ds")
    if [[ $cur_sched == "$PBS_GC_SCHEDULE" ]]; then ok "datastore ${ds} (GC ${PBS_GC_SCHEDULE})"
    else
      change "datastore ${ds}: GC schedule ${cur_sched:-none} -> ${PBS_GC_SCHEDULE}"
      run proxmox-backup-manager datastore update "$ds" --gc-schedule "$PBS_GC_SCHEDULE"
    fi
  else
    [[ -d $PBS_DATASTORE_PATH ]] || die "datastore path ${PBS_DATASTORE_PATH} missing (run the storage stage)"
    [[ -z $(ls -A "$PBS_DATASTORE_PATH") ]] || die "datastore path ${PBS_DATASTORE_PATH} is not empty — refusing"
    change "create datastore ${ds} on ${PBS_DATASTORE_PATH} (GC ${PBS_GC_SCHEDULE})"
    run proxmox-backup-manager datastore create "$ds" "$PBS_DATASTORE_PATH" \
      --gc-schedule "$PBS_GC_SCHEDULE" --comment "pve01 local backups (managed by pve-bootstrap)"
  fi

  # Prune and verify jobs (server-side; the backup token can't delete). Existing jobs get the
  # config's schedule; their other settings are left as created.
  if pbs_has id "${ds}-prune" prune-job list; then
    cur_sched=$(pbs_json prune-job list | json_find schedule "id=${ds}-prune" || true)
    if [[ $cur_sched == "$PBS_PRUNE_SCHEDULE" ]]; then ok "prune job ${ds}-prune (${PBS_PRUNE_SCHEDULE})"
    else
      change "prune job ${ds}-prune: schedule ${cur_sched} -> ${PBS_PRUNE_SCHEDULE}"
      run proxmox-backup-manager prune-job update "${ds}-prune" --schedule "$PBS_PRUNE_SCHEDULE"
    fi
  else
    local -a keep=() kv
    for kv in ${PBS_KEEP//,/ }; do keep+=("--${kv%%=*}" "${kv#*=}"); done
    change "add prune job ${ds}-prune (${PBS_PRUNE_SCHEDULE}: ${PBS_KEEP})"
    run proxmox-backup-manager prune-job create "${ds}-prune" --store "$ds" --schedule "$PBS_PRUNE_SCHEDULE" "${keep[@]}"
  fi
  if pbs_has id "${ds}-verify" verify-job list; then
    cur_sched=$(pbs_json verify-job list | json_find schedule "id=${ds}-verify" || true)
    if [[ $cur_sched == "$PBS_VERIFY_SCHEDULE" ]]; then ok "verify job ${ds}-verify (${PBS_VERIFY_SCHEDULE})"
    else
      change "verify job ${ds}-verify: schedule ${cur_sched} -> ${PBS_VERIFY_SCHEDULE}"
      run proxmox-backup-manager verify-job update "${ds}-verify" --schedule "$PBS_VERIFY_SCHEDULE"
    fi
  else
    change "add verify job ${ds}-verify (${PBS_VERIFY_SCHEDULE}, re-verify after ${PBS_VERIFY_OUTDATED_DAYS} days)"
    run proxmox-backup-manager verify-job create "${ds}-verify" --store "$ds" --schedule "$PBS_VERIFY_SCHEDULE" \
      --ignore-verified true --outdated-after "$PBS_VERIFY_OUTDATED_DAYS"
  fi

  # Backup user (token permissions = user ACL ∩ token ACL)
  if pbs_has userid "$PBS_USER" user list; then ok "PBS user ${PBS_USER}"
  else change "create PBS user ${PBS_USER}"; run proxmox-backup-manager user create "$PBS_USER" --comment "PVE backups (managed by pve-bootstrap)"; fi
  ensure_pbs_acl "/datastore/${ds}" "$PBS_USER" DatastoreBackup

  ensure_pbs_storage

  pbs_notifications
}

# PBS has its own notification system (prune, GC, verify, sync). Same SMTP relay as PVE.
pbs_notifications() {
  # PBS keeps its own root@pam record (separate from PVE's). Its built-in mail-to-root target,
  # fed by the default matcher, sends to this address; empty means those mails go nowhere.
  local root_cur
  root_cur=$(pbs_json user list | json_find email userid=root@pam || true)
  if [[ $root_cur == "$ROOT_EMAIL" ]]; then ok "PBS root@pam email ${ROOT_EMAIL}"
  else
    change "PBS root@pam email -> ${ROOT_EMAIL}; was: ${root_cur:-none}"
    run proxmox-backup-manager user update root@pam --email "$ROOT_EMAIL"
  fi

  [[ ${NOTIFY_SMTP_ENABLE:-no} == yes ]] || return 0
  local n=$NOTIFY_SMTP_NAME
  if pbs_has name "$n" notification endpoint smtp list; then
    local cur want retest="no"
    cur=$(pbs_get mailto notification endpoint smtp show "$n")
    if [[ $cur == "$NOTIFY_MAILTO" ]]; then ok "PBS SMTP target ${n} -> ${NOTIFY_MAILTO}"
    else
      change "PBS SMTP target ${n} recipient -> ${NOTIFY_MAILTO}; was: ${cur:-none}"
      run proxmox-backup-manager notification endpoint smtp update "$n" --mailto "$NOTIFY_MAILTO"
      retest="yes"
    fi
    # From address follows PVE's target (or env NOTIFY_SMTP_FROM, which the notify stage applies to PVE).
    want=${NOTIFY_SMTP_FROM:-$(pve_notify_value "$n" from-address 2>/dev/null || true)}
    cur=$(pbs_get from-address notification endpoint smtp show "$n")
    if [[ -z $want || $cur == "$want" ]]; then ok "PBS SMTP target ${n} From address matches PVE's"
    else
      change "PBS SMTP target ${n} From address -> ${want}; was: ${cur:-none}"
      run proxmox-backup-manager notification endpoint smtp update "$n" --from-address "$want"
      retest="yes"
    fi
    if [[ $retest == yes ]] && is_apply; then notify_test pbs; fi
  else
    change "add PBS SMTP target ${n}: ${NOTIFY_SMTP_SERVER}:${NOTIFY_SMTP_PORT} -> ${NOTIFY_MAILTO} (login, From and key copied from PVE's target, else prompted)"
    if is_apply; then
      local user from pw
      user=$(pve_notify_value "$n" username); from=$(pve_notify_value "$n" from-address)
      pw=$(pve_notify_value "$n" password /etc/pve/priv/notifications.cfg 2>/dev/null || true)
      if [[ -z $user || -z $from || -z $pw ]]; then
        info "PVE target ${n} not found or incomplete — asking instead"
        read_value  NOTIFY_SMTP_USER     "SMTP login";                                   user=$NOTIFY_SMTP_USER
        read_value  NOTIFY_SMTP_FROM     "From address (a verified sender at the relay)"; from=$NOTIFY_SMTP_FROM
        read_secret NOTIFY_SMTP_PASSWORD "SMTP key for ${user}";                         pw=$NOTIFY_SMTP_PASSWORD
        unset NOTIFY_SMTP_PASSWORD
      fi
      # Not via run(): never print the key.
      proxmox-backup-manager notification endpoint smtp create "$n" \
        --server "$NOTIFY_SMTP_SERVER" --port "$NOTIFY_SMTP_PORT" --mode "$NOTIFY_SMTP_MODE" \
        --username "$user" --password "$pw" --from-address "$from" --mailto "$NOTIFY_MAILTO" \
        --comment "Managed by pve-bootstrap"
      unset pw
      ok "PBS SMTP target ${n} created"
      notify_test pbs
    fi
  fi

  if pbs_has name phoenix-alerts notification matcher list; then ok "PBS matcher phoenix-alerts"
  else
    local -a sev=() sv
    for sv in ${NOTIFY_SEVERITIES//,/ }; do sev+=(--match-severity "$sv"); done
    change "add PBS matcher phoenix-alerts: severity ${NOTIFY_SEVERITIES} -> ${n}"
    run proxmox-backup-manager notification matcher create phoenix-alerts --target "$n" "${sev[@]}" \
      --comment "Managed by pve-bootstrap: severity ${NOTIFY_SEVERITIES}"
  fi

  if [[ ${NOTIFY_MAIL_TO_ROOT:-on} == off ]]; then
    if [[ $(pbs_get disable notification endpoint sendmail show mail-to-root) == 1 ]]; then ok "PBS built-in target mail-to-root disabled"
    else
      change "disable PBS built-in target mail-to-root (local mail can't deliver off-host; ${n} carries the alerts)"
      run proxmox-backup-manager notification endpoint sendmail update mail-to-root --disable true
    fi
  fi

  # Datastore must use the notification system (the default), not legacy sendmail.
  local nmode
  nmode=$(pbs_get notification-mode datastore show "$PBS_DATASTORE")
  if [[ ${nmode:-notification-system} == notification-system ]]; then
    ok "datastore ${PBS_DATASTORE} uses the notification system"
  else
    change "datastore ${PBS_DATASTORE} notification-mode -> notification-system"
    run proxmox-backup-manager datastore update "$PBS_DATASTORE" --notification-mode notification-system
  fi
}

# ----------------------------------------------------------------------------
# Stage: backups — PVE backup jobs (all guests)
# ----------------------------------------------------------------------------
stage_backups() {
  section "backups"
  local entry id sched store extra comment cur
  for entry in "${BACKUP_JOBS[@]}"; do
    IFS='|' read -r id sched store extra comment <<<"$entry"
    if ! storage_exists "$store"; then
      if is_apply; then warn "backup job ${id}: storage ${store} missing — skipped"; continue; fi
      info "(storage ${store} does not exist yet — created by an earlier stage)"
    fi
    if cur=$(pve_json "/cluster/backup/${id}"); then
      if [[ $(json_get schedule <<<"$cur") == "$sched" && $(json_get storage <<<"$cur") == "$store" ]]; then
        ok "backup job ${id} (${sched} -> ${store})"
      else
        change "update backup job ${id} -> ${sched} -> ${store}"
        run pvesh set "/cluster/backup/${id}" --schedule "$sched" --storage "$store"
      fi
    else
      change "add backup job ${id}: all guests, ${sched} -> ${store} ${extra}"
      # shellcheck disable=SC2086  # $extra holds option pairs from config
      run pvesh create /cluster/backup --id "$id" --schedule "$sched" --storage "$store" --all 1 \
        --mode snapshot --enabled 1 --notification-mode notification-system --comment "$comment" $extra
    fi
  done
}

# ----------------------------------------------------------------------------
# Stage: acme (optional)
# ----------------------------------------------------------------------------
# acme_token_file — path of a root-only file holding the Cloudflare token in the format the
# ACME plugins read. Prompts once per run (or reads env CF_API_TOKEN). Remove with acme_token_done.
ACME_TOKEN_FILE=""
acme_token_file() {
  if [[ -z $ACME_TOKEN_FILE ]]; then
    read_secret CF_API_TOKEN "Cloudflare API token (DNS:Edit and Zone:Read on the zone)"
    ACME_TOKEN_FILE=$(mktemp); chmod 600 "$ACME_TOKEN_FILE"
    printf 'CF_Token=%s\n' "$CF_API_TOKEN" >"$ACME_TOKEN_FILE"
    unset CF_API_TOKEN
  fi
}
acme_token_done() {
  [[ -n $ACME_TOKEN_FILE ]] || return 0
  shred -u "$ACME_TOKEN_FILE" 2>/dev/null || rm -f "$ACME_TOKEN_FILE"
  ACME_TOKEN_FILE=""
}

stage_acme() {
  section "acme"
  if [[ ${ACME_ENABLE:-no} != yes ]]; then info "ACME_ENABLE=no — skipped"; return 0; fi

  # --- PVE GUI (8006) ---
  if pvenode acme account list 2>/dev/null | grep -qw default; then ok "ACME account default"
  else
    change "register ACME account 'default' (${ACME_EMAIL})"
    run pvenode acme account register default "$ACME_EMAIL" --directory "$ACME_DIRECTORY"
  fi

  if pvenode acme plugin config cloudflare >/dev/null 2>&1; then ok "ACME plugin cloudflare"
  else
    change "add ACME DNS plugin cloudflare"
    if is_apply; then acme_token_file; pvenode acme plugin add dns cloudflare --api cf --data "$ACME_TOKEN_FILE"; fi
  fi

  if pvenode config get --property acmedomain0 2>/dev/null | grep -q "$NODE_FQDN"; then ok "acmedomain0 ${NODE_FQDN}"
  else change "acmedomain0 -> ${NODE_FQDN}"; run pvenode config set --acmedomain0 "domain=${NODE_FQDN},plugin=cloudflare"; fi

  if cert_from_le "${PVE_CERT_DIR}/${NODE_NAME}/pveproxy-ssl.pem"; then ok "ACME certificate installed"
  else change "order certificate for ${NODE_FQDN}"; run pvenode acme cert order; fi

  # --- PBS GUI (8007): PBS has its own ACME account, plugin and renewal job ---
  if [[ ${PBS_ENABLE:-no} == yes ]] && command -v proxmox-backup-manager >/dev/null; then
    if proxmox-backup-manager acme account list 2>/dev/null | grep -qw default; then ok "PBS ACME account default"
    else
      change "register PBS ACME account 'default' (${ACME_EMAIL})"
      run proxmox-backup-manager acme account register default "$ACME_EMAIL" --directory "$ACME_DIRECTORY"
    fi

    if proxmox-backup-manager acme plugin config cloudflare >/dev/null 2>&1; then ok "PBS ACME plugin cloudflare"
    else
      change "add PBS ACME DNS plugin cloudflare"
      if is_apply; then acme_token_file; proxmox-backup-manager acme plugin add dns cloudflare --api cf --data "$ACME_TOKEN_FILE"; fi
    fi

    if proxmox-backup-manager node show 2>/dev/null | grep -q "$NODE_FQDN"; then ok "PBS acmedomain0 ${NODE_FQDN}"
    else
      change "PBS acmedomain0 -> ${NODE_FQDN}"
      run proxmox-backup-manager node update --acme account=default --acmedomain0 "domain=${NODE_FQDN},plugin=cloudflare"
    fi

    # --force: PBS's self-signed certificate is valid for centuries, and without it the order
    # is skipped as "not expiring". Only reached when the current certificate isn't from LE.
    if cert_from_le "$PBS_CERT"; then ok "PBS ACME certificate installed"
    else change "order PBS certificate for ${NODE_FQDN}"; run proxmox-backup-manager acme cert order --force true; fi

    # PVE's storage must follow: it pins the old certificate's fingerprint. 'server' can't be
    # changed on an existing storage, so it is removed and added again with the same token.
    # Only the storage definition is touched; the backups in the datastore are not.
    if storage_exists "$PBS_PVE_STORAGE" && [[ $(storage_prop "$PBS_PVE_STORAGE" server) != "$NODE_FQDN" ]]; then
      change "re-create storage ${PBS_PVE_STORAGE} with server ${NODE_FQDN} (trusted certificate, no pinned fingerprint)"
      if is_apply; then
        cert_from_le "$PBS_CERT" || die "PBS certificate is not from Let's Encrypt — storage ${PBS_PVE_STORAGE} left as it was"
        # Every address the resolver returns (as getaddrinfo, which the backup client uses) must
        # be this host: the public zone has a wildcard record, so a leak would point backups away.
        local addrs
        addrs=$(getent ahosts "$NODE_FQDN" | awk '{print $1}' | sort -u | paste -sd' ' -)
        [[ $addrs == "${MGMT_CIDR%/*}" ]] \
          || die "${NODE_FQDN} resolves to '${addrs:-nothing}' on this host, not only ${MGMT_CIDR%/*} (check /etc/hosts) — storage left as it was"
        local pw="/etc/pve/priv/storage/${PBS_PVE_STORAGE}.pw" secret=""
        if [[ -s $pw ]]; then secret=$(<"$pw"); fi
        pvesm remove "$PBS_PVE_STORAGE"
        ensure_pbs_storage "$secret"
        unset secret
        if pvesm list "$PBS_PVE_STORAGE" >/dev/null 2>&1; then ok "storage ${PBS_PVE_STORAGE} answers: PVE can list the backups"
        else warn "storage ${PBS_PVE_STORAGE} does not answer — run: pvesm list ${PBS_PVE_STORAGE}"; fi
      fi
    fi
  fi
  acme_token_done
}

# ----------------------------------------------------------------------------
# Stage: verify (read-only)
# ----------------------------------------------------------------------------
check() {  # check <description> <command...>
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else warn "FAIL: $desc"; fi
}
check_eq() {  # check_eq <description> <actual> <expected>
  if [[ $2 == "$3" ]]; then ok "$1"; else warn "FAIL: $1 (found '${2:-nothing}')"; fi
}
stage_verify() {
  section "verify"
  check "rpool mirrored"                  sh -c 'zpool status rpool | grep -qE "^\s+mirror-"'
  check_eq "all pools healthy"            "$(zpool status -x 2>&1)" "all pools are healthy"
  local p; for p in ${ZFS_POOLS:-}; do check "pool ${p} imported" zpool list -H "$p"; done
  local bad
  bad=$(pvesm status 2>/dev/null | awk 'NR>1 && $3!="active"{print $1"("$3")"}' | paste -sd' ' -)
  if [[ -z $bad ]]; then ok "all PVE storages active"; else warn "FAIL: PVE storages not active: ${bad}"; fi
  check_eq "vmbr0 VLAN-aware"             "$(cat /sys/class/net/vmbr0/bridge/vlan_filtering 2>/dev/null)" 1
  check "gateway ${MGMT_GATEWAY} reachable" ping -c 1 -W 2 "$MGMT_GATEWAY"
  check "IOMMU groups present"            sh -c 'ls /sys/kernel/iommu_groups | grep -q .'
  if [[ -n ${GPU_PCI_ADDR:-} ]]; then
    check "GPU ${GPU_PCI_ADDR} bound to vfio-pci" sh -c "lspci -nnk -s ${GPU_PCI_ADDR}.0 | grep -q 'in use: vfio-pci'"
    if [[ -n ${GPU_MAPPING_ID:-} ]]; then
      check "PCI mapping ${GPU_MAPPING_ID} exists" pve_exists "/cluster/mapping/pci/${GPU_MAPPING_ID}"
    fi
  fi
  check_eq "ZFS ARC max ${ZFS_ARC_MAX_GIB} GiB" "$(cat /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null)" "$((ZFS_ARC_MAX_GIB * 1024 * 1024 * 1024))"
  check "firewall enabled/running"        sh -c 'pve-firewall status | grep -q "enabled/running"'
  check "SSH password auth disabled"      sh -c 'sshd -T 2>/dev/null | grep -qx "passwordauthentication no"'
  check "no enterprise repo enabled"      sh -c '! grep -l enterprise.proxmox.com /etc/apt/sources.list.d/*.sources 2>/dev/null | xargs -r grep -LiE "^Enabled:[[:space:]]*(no|false)" | grep -q .'
  check_eq "running newest installed kernel" "$(uname -r)" "$(newest_kernel)"
  check_eq "time synchronized"            "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" yes
  check "daily update check scheduled"    systemctl is-active --quiet pve-daily-update.timer
  check "package lists refreshed in the last 2 days" sh -c 'find /var/cache/apt/pkgcache.bin -mtime -2 | grep -q .'
  local pending
  pending=$(pending_updates)
  if [[ ${pending:-0} == 0 ]]; then ok "no package updates pending"
  else info "${pending} package update(s) pending — apply in the next patch window (apt update && apt dist-upgrade)"; fi
  if [[ ${NOTIFY_SMTP_ENABLE:-no} == yes ]]; then
    check_eq "alerts go to ${NOTIFY_MAILTO} (PVE SMTP target ${NOTIFY_SMTP_NAME})" \
      "$(pve_get "/cluster/notifications/endpoints/smtp/${NOTIFY_SMTP_NAME}" mailto)" "$NOTIFY_MAILTO"
    check_eq "root@pam email ${ROOT_EMAIL}" "$(pve_get /access/users/root@pam email)" "$ROOT_EMAIL"
    check "root mail (ZFS events, smartd, cron) routed to ${NOTIFY_SMTP_NAME}" pve_exists /cluster/notifications/matchers/phoenix-system-mail
    if [[ ${NOTIFY_PACKAGE_UPDATES:-no} == yes ]]; then
      check "update notices routed to ${NOTIFY_SMTP_NAME}" pve_exists /cluster/notifications/matchers/phoenix-updates
      check "daily update job announces new updates" grep -qE '^notify:.*package-updates=always' /etc/pve/datacenter.cfg
    fi
  fi
  if [[ ${PBS_ENABLE:-no} == yes ]]; then
    check "PBS running" systemctl is-active --quiet proxmox-backup-proxy
    check "PBS datastore ${PBS_DATASTORE}" pbs_has name "$PBS_DATASTORE" datastore list
    check_eq "PBS root@pam email ${ROOT_EMAIL}" "$(pbs_json user list | json_find email userid=root@pam)" "$ROOT_EMAIL"
    if [[ ${NOTIFY_SMTP_ENABLE:-no} == yes ]]; then
      check_eq "PBS alerts go to ${NOTIFY_MAILTO} (PBS SMTP target ${NOTIFY_SMTP_NAME})" \
        "$(pbs_get mailto notification endpoint smtp show "$NOTIFY_SMTP_NAME")" "$NOTIFY_MAILTO"
    fi
  fi
  if [[ ${ACME_ENABLE:-no} == yes ]]; then
    local two_weeks=$((14 * 86400))
    check "PVE GUI certificate valid for 14+ days" openssl x509 -in "${PVE_CERT_DIR}/${NODE_NAME}/pveproxy-ssl.pem" -noout -checkend "$two_weeks"
    if [[ ${PBS_ENABLE:-no} == yes ]]; then
      check "PBS GUI certificate from Let's Encrypt, valid for 14+ days" \
        sh -c "openssl x509 -in '$PBS_CERT' -noout -issuer | grep -qi \"let's encrypt\" && openssl x509 -in '$PBS_CERT' -noout -checkend $two_weeks"
      check_eq "storage ${PBS_PVE_STORAGE} reaches PBS by name" "$(storage_prop "$PBS_PVE_STORAGE" server)" "$NODE_FQDN"
    fi
  fi
  local entry id
  for entry in "${BACKUP_JOBS[@]}"; do
    id=${entry%%|*}
    check "backup job ${id}" pve_exists "/cluster/backup/${id}"
  done
  local storage prefix
  for entry in ${LXC_TEMPLATES[@]+"${LXC_TEMPLATES[@]}"}; do
    IFS='|' read -r storage prefix <<<"$entry"
    check "template ${prefix} on ${storage}" test -n "$(template_present "$storage" "$prefix")"
  done
  for entry in ${VM_TEMPLATES[@]+"${VM_TEMPLATES[@]}"}; do
    id=${entry%%|*}
    check "VM template ${id}" sh -c "qm config ${id} | grep -qx 'template: 1'"
  done
  for entry in ${PVE_POOLS[@]+"${PVE_POOLS[@]}"}; do
    id=${entry%%|*}
    check "pool ${id}" sh -c "pvesh get /pools --output-format json | grep -q '\"poolid\":\"${id}\"'"
  done
  local userid grants token
  for entry in "${SERVICE_ACCOUNTS[@]}"; do
    IFS='|' read -r userid grants token _ <<<"$entry"
    check_eq "permissions of ${userid}!${token} match config" \
      "$(acl_entries token "${userid}!${token}" | sort | paste -sd, -)" "$(grants_lines "$grants" | paste -sd, -)"
  done
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

# Run only when executed, so tests can source this file for its functions.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
