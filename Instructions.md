# PhoenixStack Project Instructions

This file defines how PhoenixStack work is planned, implemented, reviewed, and documented.

## 1. Mission and Operating Model

PhoenixStack is a hybrid homelab plus personal-production environment focused on:
- Learning and experimentation
- Practical, reliable services for family and friends
- Security-first operations

Work should be incremental, testable, documentable, and reversible.

## 2. Non-Negotiable Guardrails

1. Security first in every change.
2. No plaintext secrets in code, docs, commits, issues, pull requests, or AI outputs.
3. Internal documentation is the first source of truth.
4. Small scoped changes only; avoid parallel large initiatives.
5. Every infrastructure change must be traceable through git history.
6. Prefer least privilege and deny-by-default network access.
7. Disable IPv6 where not explicitly required.
8. Keep documentation centralized in a docs folder unless there is a strong reason not to.

## 3. Preferred Tooling and Roles

- Terraform: infrastructure provisioning and lifecycle
- Ansible: host and service configuration
- GitHub: source control and change workflow
- GitHub Actions: default IaC execution pipeline
- Terraform Cloud: deferred for future evaluation
- HashiCorp Vault: secrets lifecycle and rotation
- Docker/Compose and Traefik: application delivery and reverse proxy services
- Proxmox: virtualization platform

## 4. Current Assets in This Repository

- Proxmox bootstrap script and wrapper:
  - Scripts/proxmox/proxmox-bootstrap.sh
  - Scripts/proxmox/deploy_proxmox_bootstrap.sh
- Node config templates and examples:
  - Scripts/proxmox/configs/pve01.conf
  - Scripts/proxmox/configs/pve999.conf.example
  - Scripts/proxmox/configs/README.md

These assets are considered the initial deployment baseline.

## 5. Documentation Standards

1. Use Markdown for all documentation.
2. Place reference docs under docs by default.
3. Add a short purpose statement at the top of each document.
4. Record assumptions, constraints, and decisions explicitly.
5. Use a simple naming pattern: topic-purpose.md (example: proxmox-network-baseline.md).

## 6. Change Workflow Standard

1. Define a small objective.
2. List security impact and rollback approach before implementation.
3. Implement the smallest viable change.
4. Validate in dry-run or non-production scope first.
5. Document what changed and why.
6. Commit with clear message and open pull request.

## 7. Initial Architecture Direction

Primary environment direction:
- Site: PHOENIX-PRIMARY
- Internal domain: phoenix.stack
- External domain: phoenixstack.net
- Management VLAN: 10.101.0.0/24 (VLAN 10)
- Workload network: 10.101.1.0/24 (VLAN 100)
- Core stack: Proxmox + Terraform + Ansible + Vault + Traefik + service LXCs

Initial planned LXC rollout sequence:
1. ANSIBLE01
2. DNS01
3. PROXY01
4. AUTHENTIK01
5. DOCKER01
6. PLEX01

## 8. Terraform/Infrastructure Deployment Constraints

### Proxmox API Token Limitations

When deploying LXC containers via Terraform:

1. **API tokens cannot set advanced feature flags** (`keyctl`, `mknod`) during container creation
2. **Only `nesting=1` is supported** via token - this is sufficient for systemd 255+ and container nesting
3. **Workaround for additional flags**: 
   - Deploy container via Terraform (with token)
   - Manually set additional flags as `root@pam` on the Proxmox node
   - Edit `/etc/pve/lxc/VMID.conf` and restart container

**Documentation**: See [terraform/modules/lxc/README.md](terraform/modules/lxc/README.md#-important-proxmox-api-token-permissions) for detailed instructions.

**Current Status**:
- ✅ All future LXC containers will be created with `nesting=1` only
- ✅ DNS01, DNS02 operational with `nesting=1`
- ℹ️ Bastion01 has additional flags (set manually post-deployment)

## 9. Security Baseline Checklist

Apply this checklist to every host/service rollout:

1. SSH key-only access configured (password authentication disabled).
2. Firewall rules reviewed and least privilege enforced.
3. Management plane traffic isolated on dedicated VLAN (10.101.0.0/24).
4. Secrets sourced from secure store, never committed.
5. Logging and alerting path defined.
6. Backup and restore path validated.
7. Patch/update strategy documented.
8. DNS and certificate dependencies documented.

## 9. Phased Delivery Plan (Methodical and Small)

### Phase 0: Repository Foundation (Current)
- Create repository-level instructions and README.
- Create docs skeleton and architecture index.
- Confirm baseline Proxmox script behavior and config schema.

### Phase 1: Baseline Validation and Network Configuration
- Configure management VLAN (VLAN 10, 10.101.0.0/24) on network infrastructure.
- Validate current PVE01 configuration against bootstrap script expectations.
- Migrate PVE01 to management VLAN with proper safeguards.
- Produce a gap report: aligned, drifted, unknown.
- No further infrastructure changes until migration validated.

### Phase 2: Automation Control Plane
- Define and deploy ANSIBLE01.
- Establish Ansible inventory model and role structure.
- Add first hardening playbooks for baseline hosts.

### Phase 3: Edge and Access
- Deploy DNS01 to stabilize internal name resolution before proxy and identity rollout.
- Deploy PROXY01 with Traefik baseline.
- Document Cloudflare DNS and proxy flow.
- Prepare Authentik integration plan (no rushed implementation).

### Phase 4: Identity and Service Expansion
- Deploy AUTHENTIK01 after design review.
- Deploy DOCKER01.
- Deploy additional service nodes (for example PLEX01) after security review.

## 10. Immediate Next Actions

1. Configure management VLAN (VLAN 10) on Ubiquiti network infrastructure.
2. Create PVE01 migration plan with rollback procedure.
3. Run non-destructive validation of current PVE01 settings against config.
4. Execute PVE01 migration to management VLAN during maintenance window.
5. Validate connectivity and update documentation.

## 11. Open Decision Items

1. Backup target policy for each service tier.
2. Initial monitoring and alerting stack selection.
3. Vault integration approach and secret rotation schedule.

## 12. AI Collaboration Constraints

1. Prefer internal docs in this repository before external references.
2. Never expose secrets in prompts or outputs.
3. Keep outputs actionable, minimal, and stepwise.
4. For risky operations, require a dry-run or explicit approval checkpoint.
