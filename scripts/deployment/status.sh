#!/bin/bash
# Phoenix Stack Status Script
# Check infrastructure health and connectivity

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT"

echo "=========================================="
echo "  Phoenix Stack - Infrastructure Status"
echo "=========================================="
echo ""

# Check Terraform state
echo "TERRAFORM STATE:"
echo "──────────────────────────────────────────"
cd "$PROJECT_ROOT/terraform"
CONTAINER_COUNT=$(terraform state list 2>/dev/null | grep proxmox_lxc | wc -l)
echo "Managed containers: $CONTAINER_COUNT"
terraform state list 2>/dev/null | grep proxmox_lxc | sed 's/^/  [OK] /'
echo ""

# Check Ansible inventory
echo "ANSIBLE INVENTORY:"
echo "──────────────────────────────────────────"
cd "$PROJECT_ROOT"
TOTAL_HOSTS=$(grep -v "^#" ansible/inventory/hosts.yml | grep -v "^\[" | grep -v "^$" | wc -l)
echo "Total hosts configured: $TOTAL_HOSTS"
echo ""

# Check critical services
echo "CONNECTIVITY CHECK:"
echo "──────────────────────────────────────────"

# Bastion connectivity
echo "Bastion01 (10.101.0.21):"
if ansible bastion01 -i ansible/inventory/hosts.yml -m ping &>/dev/null; then
  echo "  [OK] SSH reachable"
else
  echo "  [FAIL] SSH unreachable"
fi

echo "Bastion02 (10.101.0.22):"
if ansible bastion02 -i ansible/inventory/hosts.yml -m ping &>/dev/null; then
  echo "  [OK] SSH reachable"
else
  echo "  [FAIL] SSH unreachable"
fi

# DNS connectivity
echo "DNS01 (10.101.0.201):"
if ansible dns01 -i ansible/inventory/hosts.yml -m ping &>/dev/null; then
  echo "  [OK] SSH reachable"
  if ansible dns01 -i ansible/inventory/hosts.yml -m shell -a "docker ps 2>/dev/null | grep pihole" &>/dev/null; then
    echo "  [OK] PiHole container running"
  else
    echo "  [WARN] PiHole container not running"
  fi
else
  echo "  [FAIL] SSH unreachable"
fi

echo "DNS02 (10.101.0.202):"
if ansible dns02 -i ansible/inventory/hosts.yml -m ping &>/dev/null; then
  echo "  [OK] SSH reachable"
  if ansible dns02 -i ansible/inventory/hosts.yml -m shell -a "docker ps 2>/dev/null | grep pihole" &>/dev/null; then
    echo "  [OK] PiHole container running"
  else
    echo "  [WARN] PiHole container not running"
  fi
else
  echo "  [FAIL] SSH unreachable"
fi

echo ""
echo "SERVICE STATUS:"
echo "──────────────────────────────────────────"

# Check GitHub runners
echo "GitHub Runners (Bastion):"
if ansible bastion01 -i ansible/inventory/hosts.yml -m shell -a "systemctl is-active svc_github_runner@svc_github_runner 2>/dev/null || true" &>/dev/null 2>&1; then
  echo "  [OK] Runner service status check attempted"
else
  echo "  [WARN] Could not check runner status"
fi

# Check 1Password CLI
echo "1Password CLI (Bastion):"
if ansible bastion01 -i ansible/inventory/hosts.yml -m shell -a "op --version" &>/dev/null 2>&1; then
  echo "  [OK] 1Password CLI installed"
else
  echo "  [WARN] 1Password CLI not responding"
fi

echo ""
echo "Status check complete!"
echo ""
echo "Quick commands:"
echo "  phoenix-deploy    - Deploy infrastructure"
echo "  phoenix-destroy   - Destroy infrastructure"
echo "  phoenix-redeploy  - Full destroy -> rebuild -> reconfigure cycle"
echo "  phoenix-status    - Show this status report"
