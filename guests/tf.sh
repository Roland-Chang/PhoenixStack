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
#
# The state is the only record of what Terraform manages, and it isn't in git: its copy of
# record is a 1Password document. The local file is a working copy, checked against that
# document before every command: when it's missing or older here, it's fetched first, so a
# second workstation never plans from an empty state (which would try to create every guest
# again). After every command that can change it (apply, destroy, import, state ...), it's
# saved back.
#
# Needs: terraform, op (signed in), jq, and OP_ACCOUNT for the PhoenixStack account.
# =============================================================================
set -Eeuo pipefail
umask 077    # state files and the fetched copy: owner only

# 1Password references. Item IDs, not names: names with parentheses can't be used in op:// paths.
TOKEN_REF="${TOKEN_REF:-op://infrastructure/77alo4tqtgsujttuvcwslaukwe/credential}"   # (Proxmox) - Terraform Token
TOKEN_ID="terraform@pve!automation"
STATE_VAULT="${STATE_VAULT:-infrastructure}"
STATE_DOC="(Terraform) - Guests State"

: "${OP_ACCOUNT:?set OP_ACCOUNT to the PhoenixStack 1Password account}"
for cmd in terraform op jq; do command -v "$cmd" >/dev/null || { echo "missing: $cmd" >&2; exit 1; }; done
[[ $# -gt 0 ]] || { sed -n '2,/^# =====/p' "$0" | sed 's/^# \{0,1\}//; /^=====/d'; exit 1; }

cd "$(dirname "$0")/terraform"

secret=$(op read "$TOKEN_REF")
export PROXMOX_VE_API_TOKEN="${TOKEN_ID}=${secret}"
unset secret
chmod 600 terraform.tfstate* 2>/dev/null || true   # files from before the umask above

save_state() {
  [[ -s terraform.tfstate ]] || return 0
  if op document get "$STATE_DOC" --vault "$STATE_VAULT" >/dev/null 2>&1; then
    op document edit "$STATE_DOC" terraform.tfstate --vault "$STATE_VAULT" >/dev/null
  else
    op document create terraform.tfstate --title "$STATE_DOC" --vault "$STATE_VAULT" >/dev/null
  fi
  echo "State saved to 1Password: ${STATE_VAULT} / ${STATE_DOC}"
}

# --- Check the local state against 1Password's copy --------------------------------------
save_after="no"
remote=$(mktemp)
trap 'rm -f "$remote"' EXIT
if op document get "$STATE_DOC" --vault "$STATE_VAULT" --out-file "$remote" --force >/dev/null 2>&1; then
  r_lineage=$(jq -r .lineage "$remote"); r_serial=$(jq -r .serial "$remote")
  if [[ ! -s terraform.tfstate ]]; then
    cp "$remote" terraform.tfstate
    echo "State fetched from 1Password (serial ${r_serial})."
  else
    l_lineage=$(jq -r .lineage terraform.tfstate); l_serial=$(jq -r .serial terraform.tfstate)
    if [[ $l_lineage != "$r_lineage" ]]; then
      echo "The local state and 1Password's are different states (lineage). Stopping: compare them by hand." >&2
      exit 1
    elif ((r_serial > l_serial)); then
      cp terraform.tfstate "terraform.tfstate.local-$(date +%Y%m%d-%H%M%S)"
      cp "$remote" terraform.tfstate
      echo "1Password has a newer state (serial ${r_serial} > ${l_serial}): fetched; the old local copy is kept beside it."
    elif ((l_serial > r_serial)); then
      echo "The local state is newer than 1Password's (serial ${l_serial} > ${r_serial}): the last save didn't happen. Saving it after this command." >&2
      save_after="yes"
    fi
  fi
elif [[ ! -s terraform.tfstate && ${TF_NEW_STATE:-} != yes ]]; then
  echo "No state here and none in 1Password (${STATE_VAULT} / ${STATE_DOC})." >&2
  echo "Only on the very first run: set TF_NEW_STATE=yes." >&2
  exit 1
fi

[[ -d .terraform ]] || terraform init -input=false

status=0
terraform "$@" || status=$?
unset PROXMOX_VE_API_TOKEN

case $1 in
  apply|destroy|import|state|taint|untaint|refresh) save_state ;;
  *) if [[ $save_after == yes ]]; then save_state; fi ;;
esac
exit "$status"
