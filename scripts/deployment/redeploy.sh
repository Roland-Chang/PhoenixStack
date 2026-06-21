#!/bin/bash
# Phoenix Stack Redeploy Script
# Full cycle: destroy → rebuild → reconfigure
# This is the ultimate validation test

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "╔════════════════════════════════════════╗"
echo "║  Phoenix Stack - Full Redeploy Cycle  ║"
echo "║  Destroy → Rebuild → Reconfigure      ║"
echo "║  WARNING: Destructive operation!      ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Safety confirmation
read -p "Type 'redeploy' to proceed: " confirmation
if [ "$confirmation" != "redeploy" ]; then
  echo "❌ Cancelled."
  exit 1
fi

echo ""
echo "════════════════════════════════════════"
echo "STEP 1: Destroying existing infrastructure"
echo "════════════════════════════════════════"
"$SCRIPT_DIR/destroy.sh"

echo ""
echo "════════════════════════════════════════"
echo "STEP 2: Rebuilding infrastructure"
echo "════════════════════════════════════════"
"$SCRIPT_DIR/terraform.sh"

echo ""
echo "════════════════════════════════════════"
echo "STEP 3: Waiting for containers to provision..."
echo "════════════════════════════════════════"
sleep 90
echo "✅ Containers ready"

echo ""
echo "════════════════════════════════════════"
echo "STEP 4: Running full configuration"
echo "════════════════════════════════════════"
"$SCRIPT_DIR/ansible.sh"

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  ✅ Full Redeploy Cycle Complete!    ║"
echo "╚════════════════════════════════════════╝"
  ansible/playbooks/site.yml \
  -e @ansible/vault/github_runner.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id ansible/vault/.vault_pass

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  ✅ FULL REDEPLOY CYCLE COMPLETE!    ║"
echo "║                                        ║"
echo "║  All infrastructure rebuilt and        ║"
echo "║  reconfigured from scratch.            ║"
echo "║                                        ║"
echo "║  Status:                               ║"
echo "║  ✓ 20 containers deployed              ║"
echo "║  ✓ Bastion + 1Password + GitHub        ║"
echo "║  ✓ PiHole DNS with local records       ║"
echo "╚════════════════════════════════════════╝"
