.PHONY: help deploy destroy redeploy status clean validate

# Phoenix Stack Makefile
# Convenient commands for managing infrastructure

help:
	@echo "╔════════════════════════════════════════════════════════╗"
	@echo "║           Phoenix Stack - Make Targets               ║"
	@echo "╚════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "📦 DEPLOYMENT:"
	@echo "  make deploy          Deploy infrastructure (Bastion + DNS + services)"
	@echo "  make destroy         Destroy all infrastructure (with confirmation)"
	@echo "  make redeploy        Full cycle: destroy → rebuild → reconfigure"
	@echo ""
	@echo "📊 STATUS & VALIDATION:"
	@echo "  make status          Check infrastructure health"
	@echo "  make validate        Validate Terraform and Ansible configs"
	@echo ""
	@echo "🧹 MAINTENANCE:"
	@echo "  make clean           Remove build artifacts and temporary files"
	@echo "  make syntax-check    Validate playbook syntax"
	@echo ""
	@echo "Examples:"
	@echo "  make help            Show this help message"
	@echo "  make deploy          Run full deployment"

deploy:
	@echo "Deploying Phoenix Stack infrastructure..."
	@./scripts/deployment/deploy.sh

destroy:
	@./scripts/deployment/destroy.sh

redeploy:
	@./scripts/deployment/redeploy.sh

status:
	@./scripts/deployment/status.sh

validate:
	@echo "Validating Terraform configuration..."
	@cd terraform && terraform validate && echo "✅ Terraform valid"
	@echo ""
	@echo "Validating Ansible playbook syntax..."
	@ansible-playbook ansible/playbooks/site.yml --vault-id ansible/vault/.vault_pass --syntax-check
	@echo "✅ Playbooks valid"
	@echo ""
	@echo "✅ All configurations validated!"

syntax-check:
	@echo "Checking Ansible playbook syntax..."
	@ansible-playbook ansible/playbooks/site.yml --vault-id ansible/vault/.vault_pass --syntax-check
	@echo "✅ Syntax check passed!"

clean:
	@echo "Cleaning up temporary files..."
	@find . -type f -name "*.retry" -delete
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@rm -f /tmp/site-playbook*.log
	@echo "✅ Cleanup complete!"

.DEFAULT_GOAL := help
