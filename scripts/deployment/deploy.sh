#!/bin/bash
# Phoenix Stack Deployment Script
# Full deployment: Terraform (provision) → Ansible (configure)

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "╔════════════════════════════════════════╗"
echo "║  Phoenix Stack - Full Deployment      ║"
echo "║  (Terraform + Ansible)                ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Phase 1: Terraform (provision infrastructure)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHASE 1: Provisioning Infrastructure"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"$SCRIPT_DIR/terraform.sh"

# Phase 2: Ansible (configure infrastructure)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHASE 2: Configuring Infrastructure"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"$SCRIPT_DIR/ansible.sh" "$@"

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  ✅ Full Deployment Complete!         ║"
echo "╚════════════════════════════════════════╝"
