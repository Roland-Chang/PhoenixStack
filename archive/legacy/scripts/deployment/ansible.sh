#!/bin/bash
# Phoenix Stack Ansible Script
# Configures infrastructure with Ansible

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT"

echo "╔════════════════════════════════════════╗"
echo "║  Phoenix Stack - Ansible Configuration ║"
echo "║  (Bastion + DNS + Services)            ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Run the full site playbook with all vault files
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/site.yml \
  -e @ansible/vault/github_runner.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id ansible/vault/.vault_pass \
  "$@"

echo ""
echo "✅ Configuration complete!"
