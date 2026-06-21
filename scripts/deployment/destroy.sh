#!/bin/bash
# Phoenix Stack Destroy Script
# Destroys all Terraform infrastructure with safety checks

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT/terraform"

echo "╔═════════════════════════════════════════╗"
echo "║  Phoenix Stack - Destroy Infrastructure ║"
echo "║  ⚠️  WARNING: This will DELETE all VMs! ║"
echo "╚═════════════════════════════════════════╝"
echo ""

# Show what will be destroyed
echo "Preview of resources to be destroyed:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
DESTROY_PLAN=$(terraform plan -destroy 2>&1)
echo "$DESTROY_PLAN" | grep "module\." | grep "will be destroyed" | sed 's/^[[:space:]]*#[[:space:]]*/  /' | sed 's/ will be destroyed.*//'
echo "$DESTROY_PLAN" | grep "^Plan:" 
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Safety confirmation
read -p "Type 'destroy' to confirm: " confirmation
if [ "$confirmation" != "destroy" ]; then
  echo "❌ Cancelled."
  exit 1
fi

echo ""
echo "🔥 Destroying infrastructure..."
terraform destroy -auto-approve

echo ""
echo "✅ Infrastructure destroyed!"
echo "All 20 containers have been removed from Proxmox."
