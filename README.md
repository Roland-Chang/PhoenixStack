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

## Current Repository Layout

- Prompt.txt
- Scripts/proxmox/deploy_proxmox_bootstrap.sh
- Scripts/proxmox/proxmox-bootstrap.sh
- Scripts/proxmox/configs/pve01.conf
- Scripts/proxmox/configs/pve999.conf.example
- Scripts/proxmox/configs/README.md
- Instructions.md
- docs/pve01-validation-commands.md
- docs/pve01-validation-commands.ps1
- docs/pve01-validation-report-template.md
- docs/decision-management-vlan.md
- docs/management-vlan-implementation.md

## Environment Snapshot

- Platform: Proxmox (PHOENIX-PRIMARY)
- Internal domain: phoenix.stack
- External domain: phoenixstack.net
- Management VLAN: 10.101.0.0/24 (VLAN 10)
- Network family: 10.100.0.0/16 to 10.103.0.0/16
- DNS/edge dependencies: Cloudflare, Namecheap, Microsoft 365 MX

## Planned Service Rollout (Initial)

1. BASTION01 (Ansible orchestration, GitHub Actions runner, jump box)
2. DNS01
3. PROXY01
4. AUTHENTIK01
5. DOCKER01
6. PLEX01

This order favors automation and control first, then internal DNS stability, then edge control, followed by identity and service expansion.

## Work Model

For each change:
1. Define a small objective.
2. Identify security implications and rollback path.
3. Implement minimally.
4. Validate in safe mode first.
5. Document and commit.

## Near-Term Roadmap

### Step 1: Network Infrastructure and Baseline Validation
- Configure management VLAN (VLAN 10, 10.101.0.0/24) on network infrastructure.
- Validate active PVE01 state against bootstrap configuration and script assumptions.
- Migrate PVE01 to management VLAN with proper safeguards.
- Produce drift report and validate migration success.

### Step 2: Docs Foundation
- Establish a simple top-level docs folder.
- Add command-ready validation templates (including fstab formatting standard).

### Step 3: Automation Control Plane
- Design and deploy BASTION01 (renamed from ANSIBLE01).
- Define first Ansible inventories and baseline hardening roles.
- Set up GitHub Actions self-hosted runner on BASTION01.
- Configure BASTION01 as bastion/jump host to other infrastructure.

## Security Notes

- Secrets belong in Vault or secure runtime injection paths, never in source files.
- **SSH key-only authentication is the default standard** (password auth disabled on all infrastructure hosts).
- **Management VLAN segmentation (10.101.0.0/24)** isolates management plane from workload traffic.
- Apply least-privilege firewall policies between VLANs.
- Disable IPv6 where not required.

## Related Documentation

- Project instructions and guardrails: [Instructions.md](Instructions.md)
- Proxmox config guidance: [Scripts/proxmox/configs/README.md](Scripts/proxmox/configs/README.md)
- PVE01 validation (Bash): [docs/pve01-validation-commands.md](docs/pve01-validation-commands.md)
- PVE01 validation (PowerShell): [docs/pve01-validation-commands.ps1](docs/pve01-validation-commands.ps1)
- Validation report template: [docs/pve01-validation-report-template.md](docs/pve01-validation-report-template.md)
- Management VLAN design: [docs/decision-management-vlan.md](docs/decision-management-vlan.md)
- Management VLAN implementation: [docs/management-vlan-implementation.md](docs/management-vlan-implementation.md)

## Status

Project is in foundation phase. The next actionable milestone is validation of the existing Proxmox node alignment before deploying new resources.

## IaC Pipeline Decision

- Current default: GitHub Actions
- Future option to re-evaluate: Terraform Cloud

## Network Architecture

- Management VLAN: 10.101.0.0/24 (VLAN 10) - Hypervisor management, IPMI, infrastructure admin
- Workload Network: 10.101.1.0/24 (VLAN 100) - VMs, LXC containers, application services
- Secondary Site: 10.102.0.0/16
- Tertiary Site: 10.103.0.0/16
- Future Cloud: 10.100.0.0/16
# Updated
# Integration test: Mon Jun  8 12:35:07 PM MDT 2026
# Test run 2: Mon Jun  8 12:39:53 PM MDT 2026

## GitHub Actions Runner Status

**Bastion01 Self-Hosted Runner:** Active ✓
- Runner: bastion01-runner
- Labels: self-hosted,bastion01,infrastructure,proxmox
- Status: Ready for CI/CD workflows
- Last verified: 2026-06-15

