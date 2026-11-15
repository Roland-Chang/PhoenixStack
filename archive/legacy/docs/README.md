# PhoenixStack Documentation

Central documentation repository for PhoenixStack infrastructure and operations.

**Status**: Phase 1 - Foundation & Baseline Validation ✅ Complete  
**Last Updated**: 2026-07-29

---

## 📋 Documentation Index

### ✅ Deployed Infrastructure

**Backup Infrastructure**
- [PROXMOX_BACKUP_INFRASTRUCTURE.md](PROXMOX_BACKUP_INFRASTRUCTURE.md) - Proxmox-wide backup strategy, LXC snapshot automation, and storage configuration (NFS/CIFS mounts)
- [LXC_SERVICE_RECOVERY.md](LXC_SERVICE_RECOVERY.md) - Service recovery procedures for all LXC containers (snapshots, rollback, IaC re-deploy)

**Hypervisor & Baseline**
- [PVE01_DRIFT_SUMMARY.md](PVE01_DRIFT_SUMMARY.md) - Validation report: PVE01 alignment with bootstrap configuration (✅ COMPLIANT)

**Network & Configuration**
- [apt-mirrors-configuration.md](apt-mirrors-configuration.md) - APT repository mirror strategy and configuration

---

### 🔄 In-Progress / Active Phases

**DNS Infrastructure** (Phase 2 - DNS Stability)
- [DNS_INTEGRATION.md](DNS_INTEGRATION.md) - DNS records, architecture, and quick reference (merged guide)

---

### 📅 Planning / Upcoming Phases

**📍 For future-state architecture, infrastructure planning, and roadmap documents, see [roadmap/README.md](roadmap/README.md)**

**Secrets Management** (Operational - Deployed)
- [1PASSWORD_INTEGRATION.md](1PASSWORD_INTEGRATION.md) - Complete 1Password integration guide (setup, GitHub Actions, Ansible)

**Infrastructure as Code** (Operational - Reference)
- [proxmox-api-token-creation.md](proxmox-api-token-creation.md) - Creating Proxmox API credentials for Terraform
- [ANSIBLE_PLAYBOOK_REFERENCE.md](ANSIBLE_PLAYBOOK_REFERENCE.md) - Ansible playbook reference and vault integration
- [ANSIBLE_PLAYBOOK_GUIDE.md](ANSIBLE_PLAYBOOK_GUIDE.md) - Master orchestration playbook execution guide

---

### 🔧 Operational & Reference

**Validation & Runbooks**
- 📍 **[scripts/validation/README.md](../scripts/validation/)** - Complete validation workflows and runbooks
  - Bash/Linux: [bash-validation-commands.md](../scripts/validation/bash-validation-commands.md)
  - PowerShell/Windows: [pve01-validation-commands.ps1](../scripts/validation/pve01-validation-commands.ps1)
  - Centralized entry point for PVE01 validation on all platforms

**Known Issues & Troubleshooting**
- [known-issues.md](known-issues.md) - Known issues catalog, status tracking, and resolutions (most items resolved)

---

## 📖 Documentation Standards

All PhoenixStack documentation follows these standards:

1. **File naming**: `topic-purpose.md` (lowercase, hyphens for spaces, no special characters)
2. **Purpose statement**: Every doc opens with a clear "Purpose:" section
3. **Status badges**: Use emoji indicators (✅ Complete, 🔄 In-Progress, 📅 Planning)
4. **Organization**: Grouped by deployment phase and infrastructure component
5. **Runbooks**: Command-ready and copy-paste executable where possible
6. **Decision records**: Significant architectural choices documented with rationale
7. **Audience**: Written for operators and infrastructure team members

---

## 🔒 Security Standards

These standards are non-negotiable across all infrastructure:

- **Authentication**: SSH key-only (no password auth on infrastructure hosts)
- **Network Segmentation**:
  - Management VLAN: 10.101.0.0/24 (VLAN 10) - Hypervisor, IPMI, admin access
  - Workload VLAN: 10.101.1.0/24 (VLAN 100) - Container and application services
- **Firewall**: Least-privilege, deny-by-default between VLANs
- **Secrets**: HashiCorp Vault (1Password for external integrations) - never plaintext in code/docs
- **IPv6**: Enabled where operational; disable explicitly only if security or functionality requires it

---

## 🚀 Current Deployment Status

| Component | Status | Location | Phase |
|-----------|--------|----------|-------|
| PVE01 (Hypervisor) | ✅ Deployed | 10.101.0.11 | Foundation |
| Backup Infrastructure | ✅ Deployed | pve01 automated | 1 - Validation |
| Management VLAN | ✅ Configured | 10.101.0.0/24 | 1 - Validation |
| BASTION01/02 | 🔄 Planned | 10.101.0.21-22 | 3 - Control Plane |
| DNS01/02 | 🔄 Planned | 10.101.0.201-202 | 2 - DNS |
| PROXY01 | 📅 Planned | 10.101.0.31 | 2 - Proxy |
| AUTHENTIK01 | 📅 Planned | 10.101.0.41 | 4 - Identity |
| DOCKER01 | 📅 Planned | 10.101.1.51 | 5 - Services |
| PLEX01 | 📅 Planned | 10.101.1.61 | 5 - Services |

---

## 📚 Quick Links

### Getting Started
- Start here: [../../README.md](../../README.md) - PhoenixStack project overview
- Guardrails: [../../Instructions.md](../../Instructions.md) - Project rules and standards
- Bootstrap config: [../../scripts/provisioning/configs/pve01.conf](../../scripts/provisioning/configs/pve01.conf) - Node configuration template

### Validation & Verification
- PVE01 Validation: See [scripts/validation/README.md](../scripts/validation/) for Bash/PowerShell runbooks
- Expected baseline: Review [PVE01_DRIFT_SUMMARY.md](PVE01_DRIFT_SUMMARY.md)
- Status check: [../../ansible/inventory/hosts.yml](../../ansible/inventory/hosts.yml) - Current inventory

### Infrastructure Deployment
- Ansible: [ANSIBLE_PLAYBOOK_REFERENCE.md](ANSIBLE_PLAYBOOK_REFERENCE.md)
- Terraform: [proxmox-api-token-creation.md](proxmox-api-token-creation.md)
- Backup: [PROXMOX_BACKUP_INFRASTRUCTURE.md](PROXMOX_BACKUP_INFRASTRUCTURE.md)

---

## 📝 Contributing to Documentation

When adding or updating documentation:

1. Follow the naming convention: `topic-purpose.md`
2. Add a Purpose statement at the top
3. Update this README with appropriate category placement
4. Use the status indicators (✅ 🔄 📅) consistently
5. Link related documents bidirectionally
6. Ensure no plaintext secrets in any documentation
7. Keep scripts in `scripts/` folder, not in `docs/`
