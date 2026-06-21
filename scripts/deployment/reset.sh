#!/bin/bash
# Phoenix Stack Reset Script
# Resets Terraform state to blank after manual infrastructure cleanup
# This is useful when you've manually deleted VMs and need to sync state

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT/terraform"

echo "╔════════════════════════════════════════╗"
echo "║  Phoenix Stack - Reset Terraform State ║"
echo "║  Clears state after manual deletions   ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Safety confirmation
read -p "This will reset Terraform state to blank. Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "❌ Cancelled."
  exit 1
fi

echo ""
echo "📊 Current Terraform state:"
RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l)
echo "   Resources managed: $RESOURCE_COUNT"
echo ""

echo "💾 Backing up current state..."
BACKUP_FILE="terraform.tfstate.backup-$(date +%Y%m%d-%H%M%S)"
cp terraform.tfstate "$BACKUP_FILE"
echo "   ✅ Backup created: $BACKUP_FILE"
echo ""

echo "🔄 Resetting Terraform state..."
rm terraform.tfstate
echo "   ✅ State file removed"
echo ""

echo "🔧 Reinitializing Terraform..."
terraform init -upgrade > /dev/null 2>&1
echo "   ✅ Terraform reinitialized"
echo ""

echo "📊 New Terraform state:"
NEW_RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l)
echo "   Resources managed: $NEW_RESOURCE_COUNT"
echo ""

echo "✅ Terraform state reset complete!"
echo ""
echo "Next steps:"
echo "  1. Review your infrastructure:"
echo "     cd $PROJECT_ROOT && terraform plan"
echo ""
echo "  2. Deploy new infrastructure:"
echo "     terraform apply"
echo ""
