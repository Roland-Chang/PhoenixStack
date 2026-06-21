#!/bin/bash
# Phoenix Stack Terraform Script
# Provisions infrastructure (creates/destroys VMs in Proxmox)

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT/terraform"

echo "╔════════════════════════════════════════╗"
echo "║  Phoenix Stack - Terraform             ║"
echo "║  Infrastructure Provisioning           ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Show what will be created
echo "Terraform plan (what will be created):"
echo "────────────────────────────────────────"
terraform plan | grep -E "Plan:|will be created|will be destroyed" || true
echo ""

# Safety confirmation
read -p "Proceed with Terraform apply? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "❌ Cancelled."
  exit 1
fi

echo ""
echo "🔨 Applying Terraform configuration..."
terraform apply -auto-approve

echo ""
echo "✅ Infrastructure provisioned!"
echo ""
echo "Next steps:"
echo "  1. Verify containers were created:"
echo "     terraform state list | grep proxmox_lxc"
echo ""
echo "  2. Configure the infrastructure:"
echo "     phoenix-ansible"
echo ""
echo "  3. Or do both at once:"
echo "     phoenix-deploy"
echo ""
