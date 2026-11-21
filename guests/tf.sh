#!/usr/bin/env bash
# =============================================================================
# tf.sh — run Terraform for PhoenixStack guests with secrets from 1Password
#
#   guests/tf.sh plan            review what would change
#   guests/tf.sh apply           apply (Terraform asks for "yes"), then save the state to 1Password
#   guests/tf.sh destroy         remove guests (asks), then save the state
#   guests/tf.sh <any terraform subcommand and flags>
#
# The Proxmox API token is read from 1Password for this run only (never written to disk).
# After every command that can change the state (apply, destroy, import, state ...), the local
# state file is saved to 1Password as a document, because it's the only record of what
# Terraform manages and it isn't in git.
#
# Needs: terraform, op (signed in), and OP_ACCOUNT for the PhoenixStack account.
# =============================================================================
set -Eeuo pipefail

# 1Password references. Item IDs, not names: names with parentheses can't be used in op:// paths.
TOKEN_REF="${TOKEN_REF:-op://infrastructure/77alo4tqtgsujttuvcwslaukwe/credential}"   # (Proxmox) Terraform Token
TOKEN_ID="terraform@pve!automation"
STATE_VAULT="${STATE_VAULT:-infrastructure}"
STATE_DOC="PhoenixStack guests terraform.tfstate"

: "${OP_ACCOUNT:?set OP_ACCOUNT to the PhoenixStack 1Password account}"
for cmd in terraform op; do command -v "$cmd" >/dev/null || { echo "missing: $cmd" >&2; exit 1; }; done
[[ $# -gt 0 ]] || { sed -n '2,/^# =====/p' "$0" | sed 's/^# \{0,1\}//; /^=====/d'; exit 1; }

cd "$(dirname "$0")/terraform"

secret=$(op read "$TOKEN_REF")
export PROXMOX_VE_API_TOKEN="${TOKEN_ID}=${secret}"
unset secret

save_state() {
  [[ -s terraform.tfstate ]] || return 0
  if op document get "$STATE_DOC" --vault "$STATE_VAULT" >/dev/null 2>&1; then
    op document edit "$STATE_DOC" terraform.tfstate --vault "$STATE_VAULT" >/dev/null
  else
    op document create terraform.tfstate --title "$STATE_DOC" --vault "$STATE_VAULT" >/dev/null
  fi
  echo "State saved to 1Password: ${STATE_VAULT} / ${STATE_DOC}"
}

[[ -d .terraform ]] || terraform init -input=false

status=0
terraform "$@" || status=$?
unset PROXMOX_VE_API_TOKEN

case $1 in
  apply|destroy|import|state|taint|untaint|refresh) save_state ;;
esac
exit "$status"
