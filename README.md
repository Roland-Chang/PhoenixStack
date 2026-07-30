# PhoenixStack

Security-first, incremental infrastructure-as-code framework for a homelab plus personal-production environment.

## Overview

PhoenixStack is designed to:
- Support learning and experimentation
- Deliver reliable personal services
- Scale responsibly over time
- Keep security and operational discipline at the center

## Core Principles

1. Security before convenience.
2. Methodical, small-step delivery to prevent scope creep.
3. Infrastructure and configuration as code (Terraform + Ansible).
4. Centralized documentation with clear decision records. "If it's not written down, it never happened!"
5. No plaintext secrets in repository content.

## Quick Start - Ansible Deployment

### Prerequisites
- Ansible (installed system-wide on control node)
- Git
- SSH access to infrastructure (key-based authentication)
- 1Password CLI (for secrets management)

### Deploy Infrastructure

```bash
# Run from the ansible/ directory to use ansible.cfg role paths:
cd ansible

# Deploy backup infrastructure
ansible-playbook -i inventory/hosts.yml \
  playbooks/proxmox_backup_setup.yml

# Deploy DNS infrastructure
ansible-playbook -i inventory/hosts.yml \
  playbooks/dns_pihole.yml

# Run full site deployment (all services)
ansible-playbook -i inventory/hosts.yml \
  playbooks/site.yml
```

### Documentation

See [docs/README.md](docs/README.md) for complete documentation index.

**Key References**:
- [INFRASTRUCTURE_DESIGN.md](docs/roadmap/INFRASTRUCTURE_DESIGN.md) - Complete infrastructure design and standards
- [PROXMOX_BACKUP_INFRASTRUCTURE.md](docs/PROXMOX_BACKUP_INFRASTRUCTURE.md) - Backup strategy and automation
- [DNS_INTEGRATION.md](docs/DNS_INTEGRATION.md) - DNS architecture and records
- [1PASSWORD_INTEGRATION.md](docs/1PASSWORD_INTEGRATION.md) - Secrets management setup

## Repository Structure

```
PhoenixStack/
├── ansible/                    # Ansible playbooks and roles
│   ├── inventory/             # Inventory and host definitions
│   ├── playbooks/             # Orchestration playbooks
│   ├── roles/                 # Reusable Ansible roles
│   └── vault/                 # Encrypted secrets (examples)
├── docs/                      # Operational documentation
│   └── roadmap/               # Planning and design docs
├── scripts/                   # Automation scripts
│   ├── backup/                # Backup scripts
│   ├── deployment/            # Deployment automation
│   ├── provisioning/          # Proxmox bootstrap
│   ├── setup/                 # Environment setup
│   └── validation/            # Validation scripts
├── terraform/                 # Terraform modules and configs
│   ├── modules/               # Reusable LXC modules
│   └── providers/             # Provider configurations
├── Instructions.md            # Project standards and workflow
└── README.md                  # This file
```

## Environment Snapshot

- Platform: Proxmox (PHOENIX-PRIMARY)
- Internal domain: phoenix.stack
- External domain: phoenixstack.net
- Management VLAN: 10.101.0.0/24 (VLAN 10)
- Network family: 10.100.0.0/16 to 10.103.0.0/16
- DNS/edge dependencies: Cloudflare, Namecheap, Microsoft 365 MX

## Service Deployment Status

**Phase 1 - Foundation** ✅ Complete
1. ✅ **BASTION01, BASTION02** - Ansible orchestration, GitHub Actions runner
2. ✅ **DNS01, DNS02** - PiHole + Unbound DNS (active-active)
3. ✅ **DOCKER01, DOCKER02** - Container workload hosts
4. ✅ **PGSQL01, PGSQL02** - PostgreSQL databases

**Phase 2 - DNS Stability** 🔄 In Progress
- DNS infrastructure deployed and operational
- Automated record generation from Terraform
- Documentation consolidated

**Phase 3 - Edge Services** 📅 Planned
5. 📅 **PROXY01** - Traefik reverse proxy

**Phase 4 - Identity & Applications** 📅 Planned
6. 📅 **AUTHENTIK01** - Authentication and OAuth
7. 📅 **PLEX01** - Media server
8. 📅 **AMP01** - Game servers

## Work Model

For each change:
1. Define a small objective.
2. Identify security implications and rollback path.
3. Implement minimally.
4. Validate in safe mode first.
5. Document and commit.

## Project Status

**Current Phase**: Phase 2 - DNS Stability (In Progress)  
**Last Updated**: 2026-07-29

### Completed Milestones ✅

**Phase 1: Foundation & Baseline Validation**
- ✅ Management VLAN configured (VLAN 10, 10.101.0.0/24)
- ✅ PVE01 validated against bootstrap configuration
- ✅ PVE01 migrated to management VLAN successfully
- ✅ Drift report produced ([PVE01_DRIFT_SUMMARY.md](docs/PVE01_DRIFT_SUMMARY.md))
- ✅ Documentation infrastructure established
- ✅ BASTION01/02 deployed with GitHub Actions runners
- ✅ DNS01/02 deployed (PiHole + Unbound)
- ✅ DOCKER01/02 deployed
- ✅ PGSQL01/02 deployed
- ✅ Backup automation deployed ([PROXMOX_BACKUP_INFRASTRUCTURE.md](docs/PROXMOX_BACKUP_INFRASTRUCTURE.md))

### Current Focus 🔄

**Phase 2: DNS Stability**
- 🔄 DNS infrastructure operational validation
- 🔄 Automated DNS record generation refinement
- 🔄 Documentation consolidation (completed 2026-07-29)

### Next Steps 📅

**Phase 3: Edge Services**
- Deploy PROXY01 (Traefik reverse proxy)
- Configure CloudFlare integration
- Implement Let's Encrypt certificate automation

## Security Notes

- Secrets belong in Vault or secure runtime injection paths, never in source files.
- **SSH key-only authentication is the default standard** (password auth disabled on all infrastructure hosts).
- **Management VLAN segmentation (10.101.0.0/24)** isolates management plane from workload traffic.
- Apply least-privilege firewall policies between VLANs.
- Disable IPv6 where not required.

## Related Documentation

### Core Documentation
- **Project Standards**: [Instructions.md](Instructions.md) - Project guardrails and workflow
- **Documentation Index**: [docs/README.md](docs/README.md) - Complete documentation catalog
- **Known Issues**: [docs/known-issues.md](docs/known-issues.md) - Troubleshooting reference

### Infrastructure & Architecture
- **Infrastructure Design**: [docs/roadmap/INFRASTRUCTURE_DESIGN.md](docs/roadmap/INFRASTRUCTURE_DESIGN.md) - Comprehensive infrastructure design, hardware specs, network architecture, and standards
- **HA Strategy**: [docs/roadmap/HA_REDUNDANCY_STRATEGY.md](docs/roadmap/HA_REDUNDANCY_STRATEGY.md) - High availability planning

### Operations
- **Backup Infrastructure**: [docs/PROXMOX_BACKUP_INFRASTRUCTURE.md](docs/PROXMOX_BACKUP_INFRASTRUCTURE.md) - Backup strategy and automation
- **DNS Integration**: [docs/DNS_INTEGRATION.md](docs/DNS_INTEGRATION.md) - DNS architecture and records
- **1Password Integration**: [docs/1PASSWORD_INTEGRATION.md](docs/1PASSWORD_INTEGRATION.md) - Secrets management
- **Ansible Playbooks**: [docs/ANSIBLE_PLAYBOOK_GUIDE.md](docs/ANSIBLE_PLAYBOOK_GUIDE.md) - Playbook execution guide

### Reference
- **Proxmox Bootstrap**: [scripts/provisioning/README.md](scripts/provisioning/README.md) - Hypervisor setup
- **Validation Scripts**: [scripts/validation/](scripts/validation/) - Infrastructure validation tools
- **Roadmap**: [docs/roadmap/README.md](docs/roadmap/README.md) - Future planning and architecture

## Infrastructure as Code

**Provisioning**: Terraform (resource lifecycle management)  
**Configuration**: Ansible (service configuration and orchestration)  
**CI/CD**: GitHub Actions (self-hosted runners on bastion01/02)  
**Secrets**: 1Password (secrets management and rotation)  
**Source Control**: GitHub (Roland-Chang/PhoenixStack)

## Network Architecture

**Site**: PHOENIX-PRIMARY  
**Internal Domain**: phoenix.stack  
**External Domain**: phoenixstack.net

**Network Segmentation**:
- Management VLAN: 10.101.0.0/24 (VLAN 10) - Hypervisor, IPMI, infrastructure admin
- Workload Network: 10.101.1.0/24 (VLAN 100) - LXC containers, application services
- Reserved Sites:
  - PHOENIX-SECONDARY: 10.102.0.0/16
  - PHOENIX-TERTIARY: 10.103.0.0/16
  - Cloud Integration: 10.100.0.0/16

**External Services**:
- DNS Provider: CloudFlare (1.1.1.1, 1.0.0.1)
- DNS Registrar: Namecheap
- CDN/Proxy: CloudFlare (Orange Cloud)
- Email: Microsoft 365 (MX records)

For complete network design, see [INFRASTRUCTURE_DESIGN.md](docs/roadmap/INFRASTRUCTURE_DESIGN.md).

