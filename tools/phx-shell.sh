# shellcheck shell=bash
# =============================================================================
# phx-shell.sh — PhoenixStack shell shortcuts (bash and zsh)
#
# Load it from your shell's startup file (~/.bash_aliases, ~/.bashrc or ~/.zshrc):
#   source <path to your clone>/tools/phx-shell.sh
#
#   phx        use the PhoenixStack 1Password account in this terminal, and go to the repo
#   apb ...    ansible-playbook, run from guests/ansible from any directory
#                e.g.  apb dns.yml -l dns01 --check --diff
#   pve-sync   copy the repo's proxmox/ folder to pve01 (/root/phoenix)
#
# Per-person settings live outside the repo, in ~/.config/phoenixstack/env:
#   PHX_OP_ACCOUNT=<your 1Password account ID>   needed by phx (op account list shows it)
#   PHX_PVE_HOST=root@10.101.0.11                optional; pve-sync's target
# =============================================================================

# Where this file is, so the shortcuts work wherever the repo was cloned.
if [ -n "${BASH_VERSION:-}" ]; then
  _phx_self="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _phx_self="${(%):-%x}"
else
  echo "phx-shell.sh: needs bash or zsh" >&2
  return 1 2>/dev/null || exit 1
fi
PHX_ROOT="$(cd "$(dirname "$_phx_self")/.." && pwd)"
unset _phx_self

[ -f "$HOME/.config/phoenixstack/env" ] && . "$HOME/.config/phoenixstack/env"

# Earlier versions were aliases; an alias with the same name would break these definitions.
unalias phx apb pve-sync 2>/dev/null

phx() {
  if [ -z "${PHX_OP_ACCOUNT:-}" ]; then
    echo "phx: set PHX_OP_ACCOUNT in ~/.config/phoenixstack/env (op account list shows the ID)" >&2
    return 1
  fi
  export OP_ACCOUNT="$PHX_OP_ACCOUNT"
  cd "$PHX_ROOT" || return
}

apb() {
  (cd "$PHX_ROOT/guests/ansible" && ansible-playbook "$@")
}

# The "/." matters: without it, a second run nests a copy in /root/phoenix/proxmox.
pve-sync() {
  scp -r "$PHX_ROOT/proxmox/." "${PHX_PVE_HOST:-root@10.101.0.11}:/root/phoenix/"
}
