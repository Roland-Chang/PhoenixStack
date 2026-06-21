# Documentation Consolidation Instructions

**Date:** 2026-06-17  
**Purpose:** Step-by-step instructions for merging redundant documentation files  
**Estimated Time:** 14 hours total (2 hours per major consolidation)

---

## CONSOLIDATION #1: DNS Documentation (3 → 1)

**Files to Consolidate:**
- `docs/DNS_INTEGRATION_SUMMARY.md`
- `docs/DNS_QUICK_REFERENCE.md`
- `docs/DNS_RECORDS_MANAGEMENT.md`

**Target File:** `docs/CONFIGURATION/dns-records-management.md` (NEW)

### Step 1: Create New File Structure

```bash
mkdir -p docs/CONFIGURATION
touch docs/CONFIGURATION/dns-records-management.md
```

### Step 2: Copy Metadata Header

```markdown
---
title: DNS Records Management
audience: ⭐ Beginner
last_updated: 2026-06-17
priority: High
related_docs:
  - ARCHITECTURE/infrastructure-overview.md
  - CONFIGURATION/1password-setup-guide.md
---

# DNS Records Management
```

### Step 3: Extract Content from Each Source

**From DNS_INTEGRATION_SUMMARY.md:**
- Copy: "## System Architecture" section
- Copy: "## Record Sources" section (auto-generated and manual)
- Copy: "## Deployment Mechanism" section
- **Modify heading:** Change to `## Architecture Overview`

**From DNS_QUICK_REFERENCE.md:**
- Copy: "## 📋 Current DNS Records" section
- Copy: "## 🔧 Common Tasks" section
- **Add heading:** `## Quick Reference`

**From DNS_RECORDS_MANAGEMENT.md:**
- Copy: Everything except "## Current Records" (since that's in quick reference)
- **Modify heading:** Change intro to `## Managing DNS Records`

### Step 4: Combine in Order

Final structure:
```markdown
# DNS Records Management

## Architecture Overview
[From DNS_INTEGRATION_SUMMARY.md]

## Current DNS Records  
[From DNS_QUICK_REFERENCE.md - Current DNS Records]

## Quick Reference - Common Tasks
[From DNS_QUICK_REFERENCE.md - Common Tasks]

## Managing DNS Records
[From DNS_RECORDS_MANAGEMENT.md]
  ### Auto-Generated Records
  ### Manual Records
  ### Adding a New Manual DNS Record
  ### Deploying Changes

## Troubleshooting
[Add troubleshooting tips if any - new section]
```

### Step 5: Update Cross-References

In the new file, add cross-reference links:
```markdown
> **Related:** See [Ansible Playbooks Reference](ansible-playbooks-reference.md#dns-pihole-deployment) for deployment commands
```

### Step 6: Update Other Files

**In `docs/EXISTING_INFRASTRUCTURE_CONFIGURATION.md`:**
- Find: Links to DNS documentation
- Replace: Point to new `CONFIGURATION/dns-records-management.md`

**In `docs/README.md`:**
- Find: DNS files in documentation index
- Replace: Single link to consolidated file

### Step 7: Add Deprecation Notices

**In `docs/DNS_INTEGRATION_SUMMARY.md`:**
```markdown
> ⚠️ **DEPRECATED** - This content has been consolidated into [DNS Records Management](CONFIGURATION/dns-records-management.md). See that file for all DNS documentation.
```

Same for other two DNS files.

### Step 8: Verify Links

Test all cross-references:
```bash
grep -r "DNS_INTEGRATION_SUMMARY" docs/
grep -r "DNS_QUICK_REFERENCE" docs/
grep -r "DNS_RECORDS_MANAGEMENT" docs/
# Should only find deprecation notices
```

### Step 9: Commit

```bash
git add docs/CONFIGURATION/dns-records-management.md
git add docs/DNS_INTEGRATION_SUMMARY.md docs/DNS_QUICK_REFERENCE.md docs/DNS_RECORDS_MANAGEMENT.md
git commit -m "Consolidate DNS documentation

- Merge DNS_INTEGRATION_SUMMARY, DNS_QUICK_REFERENCE, and DNS_RECORDS_MANAGEMENT into single source of truth
- Create CONFIGURATION/dns-records-management.md with all DNS info (architecture, quick reference, how-to)
- Add deprecation notices to original files
- Update cross-references in other documentation"
```

### Step 10: Delete Old Files (After PR Review)

```bash
git rm docs/DNS_INTEGRATION_SUMMARY.md docs/DNS_QUICK_REFERENCE.md docs/DNS_RECORDS_MANAGEMENT.md
git commit -m "Remove deprecated DNS documentation files

Old files have been consolidated into CONFIGURATION/dns-records-management.md"
```

---

## CONSOLIDATION #2: Deployment Guides (3+ → 1 Master Runbook)

**Files to Consolidate:**
- `docs/BASTION01_DEPLOYMENT_QUICK_GUIDE.md`
- `docs/BASTION01_FRESH_DEPLOYMENT.md`
- `docs/PHASED_DEPLOYMENT_EXECUTION.md`
- Deployment steps from `docs/TIER_1_2_3_DEPLOYMENT.md`

**Target File:** `docs/GETTING_STARTED/deployment-master-runbook.md` (NEW)

### Step 1: Create New File Structure

```bash
mkdir -p docs/GETTING_STARTED
touch docs/GETTING_STARTED/deployment-master-runbook.md
```

### Step 2: Create Master Structure

```markdown
---
title: PhoenixStack Master Deployment Runbook
audience: ⭐⭐ Intermediate
last_updated: 2026-06-17
priority: Critical
estimated_time: 3-5 hours total
related_docs:
  - ARCHITECTURE/infrastructure-overview.md
  - CONFIGURATION/terraform-setup.md
  - OPERATIONS/operational-procedures.md
---

# PhoenixStack Master Deployment Runbook

This is the comprehensive, single-source-of-truth guide for deploying PhoenixStack from scratch.

## Overview

This runbook covers all deployment phases:
- **Phase 1:** Control Plane (BASTION01/02)
- **Phase 2:** Observability Tier (DNS01/02, PROXY01/02)
- **Phase 3:** Extended Infrastructure (Database, Monitoring, Vault)
- **Phase 4:** High Availability Setup

**Estimated Timeline:** 3-5 hours total (can be done over multiple days)

## Prerequisites

- Proxmox environment running at configured IP
- Terraform and Ansible installed locally
- Azure Storage account for Terraform state (from TERRAFORM_SETUP.md)
- GitHub Secrets configured (from TERRAFORM_SETUP.md)

See: [INFRASTRUCTURE/terraform-setup.md](../INFRASTRUCTURE/terraform-setup.md) for prerequisites.

---

## Phase 1: Control Plane - BASTION01/02 Deployment

**Estimated Time:** 1 hour  
**Complexity:** Medium  
**Risk:** Low (new infrastructure, no existing dependencies)

### Overview

BASTION01 and BASTION02 serve as the control plane:
- Ansible orchestration
- GitHub Actions self-hosted runners
- SSH bastion/jump hosts

Deploy both for high availability of the control plane.

### Step 1: Deploy Containers via Terraform

[From BASTION01_FRESH_DEPLOYMENT.md - Steps 1-3]

### Step 2: Configure with Ansible

[From BASTION01_FRESH_DEPLOYMENT.md - Steps 4-6]

### Step 3: Verify Deployment

[Custom step - verification checklist]

---

## Phase 2: Observability Tier - DNS & Proxy

**Estimated Time:** 1 hour  
**Complexity:** Medium  
**Risk:** Medium (first workload deployment)

### Overview

Deploy DNS and Proxy infrastructure:
- **DNS01/02:** PiHole DNS servers
- **PROXY01/02:** Traefik reverse proxy

### Step 1: Deploy DNS Containers

[From EXISTING_INFRASTRUCTURE_CONFIGURATION.md - DNS01/02 section]

### Step 2: Configure DNS Base

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/dns_base.yml
```

### Step 3: Deploy PiHole

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/dns_pihole.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id ansible/vault/.vault_pass
```

### Step 4: Deploy Proxy Containers

[From EXISTING_INFRASTRUCTURE_CONFIGURATION.md - PROXY01/02 section]

[Continue pattern for other services...]

---

## Phase 3: Extended Infrastructure

[From PHASED_DEPLOYMENT_EXECUTION.md and TIER_1_2_3_DEPLOYMENT.md]

## Phase 4: High Availability Configuration

[From HA_REDUNDANCY_TODO.md]

## Troubleshooting

[New section - common issues during deployment]

## Next Steps

[Operations, monitoring, etc.]
```

### Step 3: Extract & Merge Content

**From BASTION01_FRESH_DEPLOYMENT.md:**
- Copy Steps 1-6 as-is
- Use verbatim for accuracy

**From PHASED_DEPLOYMENT_EXECUTION.md:**
- Copy "Phase 1" section as template for Phase 3
- Extract deployment order
- Use for database tier deployment steps

**From TIER_1_2_3_DEPLOYMENT.md:**
- Extract "Deployment Order & Timeline" section
- Use for overall orchestration
- Extract monitoring deployment steps

**From EXISTING_INFRASTRUCTURE_CONFIGURATION.md:**
- Extract service-specific configuration steps
- Use for Phase 2 (DNS, Proxy, etc.)

### Step 4: Create Unified Flow

Organize all steps in strict dependency order:
1. BASTION (needed for Ansible)
2. DNS (needed for service discovery)
3. Proxy (needed for ingress)
4. Database (needed for stateful services)
5. Monitoring (optional but recommended)
6. HA (optional, for production resilience)

### Step 5: Add Verification Steps

After each phase, add verification section:
```markdown
### Verification

```bash
# Verify containers deployed
pct list | grep -E "103|104"

# Verify connectivity
ping 10.101.0.201

# Test DNS
dig @10.101.0.201 docker01.phoenix.stack +short
```
```

### Step 6: Update All Cross-References

```bash
# Find all files linking to old deployment docs
grep -r "BASTION01_DEPLOYMENT_QUICK_GUIDE" docs/
grep -r "PHASED_DEPLOYMENT_EXECUTION" docs/
# Update with new path: GETTING_STARTED/deployment-master-runbook.md
```

### Step 7: Add Deprecation Notices

In old files:
```markdown
> ⚠️ **DEPRECATED** - Use [PhoenixStack Master Deployment Runbook](GETTING_STARTED/deployment-master-runbook.md) instead
```

### Step 8: Commit

```bash
git add docs/GETTING_STARTED/deployment-master-runbook.md
git add docs/BASTION01_DEPLOYMENT_QUICK_GUIDE.md docs/BASTION01_FRESH_DEPLOYMENT.md docs/PHASED_DEPLOYMENT_EXECUTION.md
git commit -m "Create master deployment runbook

- Consolidate deployment guides into single orchestration flow
- Merge BASTION, DNS, Proxy, and extended tier deployment steps
- Include phased approach with verification steps
- Add troubleshooting section
- Deprecate old deployment guides in favor of unified reference"
```

---

## CONSOLIDATION #3: Ansible Playbook Documentation (2 → 1)

**Files to Consolidate:**
- `docs/ANSIBLE_PLAYBOOK_GUIDE.md`
- `docs/ANSIBLE_PLAYBOOK_REFERENCE.md`

**Target File:** `docs/CONFIGURATION/ansible-playbooks-reference.md` (NEW)

### Step 1: Create File

```bash
touch docs/CONFIGURATION/ansible-playbooks-reference.md
```

### Step 2: Merge Structure

```markdown
---
title: Ansible Playbooks Reference
audience: ⭐⭐ Intermediate
---

# Ansible Playbooks Reference Guide

## Quick Start: Running Playbooks

[From ANSIBLE_PLAYBOOK_GUIDE.md - first section]

## Master Orchestration Playbook

[From ANSIBLE_PLAYBOOK_GUIDE.md - Master Playbook section]

## Playbook Hierarchy

[From ANSIBLE_PLAYBOOK_GUIDE.md - Consolidated Playbooks section]

## Complete Playbook Reference

[From ANSIBLE_PLAYBOOK_REFERENCE.md - Playbook Overview table]

## Vault File Syntax

[From ANSIBLE_PLAYBOOK_REFERENCE.md - Vault File sections]

## Execution Methods

[From ANSIBLE_PLAYBOOK_GUIDE.md - execution methods]

## Troubleshooting

[New section - common playbook errors]
```

### Step 3: Copy & Organize

- Copy Quick Start section verbatim from GUIDE
- Copy table from REFERENCE as "Complete Playbook Reference"
- Copy vault file information from REFERENCE
- Keep structure logical: theory → reference table → execution methods

### Step 4: Add Cross-References

```markdown
> **For 1Password integration with Ansible, see:** [Ansible 1Password Integration](ansible-1password-integration.md)
```

### Step 5: Update Links

Find all references to old files:
```bash
grep -r "ANSIBLE_PLAYBOOK_GUIDE\|ANSIBLE_PLAYBOOK_REFERENCE" docs/
```

Update to: `CONFIGURATION/ansible-playbooks-reference.md`

### Step 6: Commit

```bash
git add docs/CONFIGURATION/ansible-playbooks-reference.md
git add docs/ANSIBLE_PLAYBOOK_GUIDE.md docs/ANSIBLE_PLAYBOOK_REFERENCE.md
git commit -m "Consolidate Ansible playbook documentation

- Merge ANSIBLE_PLAYBOOK_GUIDE and ANSIBLE_PLAYBOOK_REFERENCE into single reference
- Add troubleshooting section
- Keep ANSIBLE_ONEPASSWORD.md separate (different workflow)
- Add cross-references between related documents"
```

---

## CONSOLIDATION #4: GitHub Runner Documentation (2 → 1)

**Files to Consolidate:**
- `docs/GITHUB_RUNNER_SETUP.md`
- `docs/GITHUB_RUNNER_DYNAMIC_TOKEN_SETUP.md`

**Target File:** `docs/CONFIGURATION/github-runner-setup.md` (MODIFIED)

### Step 1: Rename File

```bash
mv docs/GITHUB_RUNNER_SETUP.md docs/CONFIGURATION/github-runner-setup.md
```

### Step 2: Restructure Content

Add new "Advanced" section:

```markdown
# GitHub Runner Setup & Configuration

## Quick Start (Recommended)

[From GITHUB_RUNNER_SETUP.md - entire content]

## Advanced: Dynamic Token Generation

### Why Use Dynamic Tokens?

[From GITHUB_RUNNER_DYNAMIC_TOKEN_SETUP.md - Overview section]

### Prerequisites

[From GITHUB_RUNNER_DYNAMIC_TOKEN_SETUP.md - Prerequisites]

### Fine-Grained Token Setup

[From GITHUB_RUNNER_DYNAMIC_TOKEN_SETUP.md - Prerequisites → Step 1]

### Dynamic Token Configuration

[From GITHUB_RUNNER_DYNAMIC_TOKEN_SETUP.md - Setup sections]

## Troubleshooting

[New section combining both]
```

### Step 3: Copy Content

- Entire GITHUB_RUNNER_SETUP.md becomes "Quick Start" section
- Entire GITHUB_RUNNER_DYNAMIC_TOKEN_SETUP.md becomes "Advanced" section
- Add introduction explaining when to use each approach

### Step 4: Add Cross-Link

In old GITHUB_RUNNER_DYNAMIC_TOKEN_SETUP.md:
```markdown
> See [GitHub Runner Setup - Advanced Section](CONFIGURATION/github-runner-setup.md#advanced-dynamic-token-generation) for consolidated documentation.
```

### Step 5: Update All References

```bash
grep -r "GITHUB_RUNNER_SETUP\|GITHUB_RUNNER_DYNAMIC_TOKEN_SETUP" docs/
```

Update with: `CONFIGURATION/github-runner-setup.md`

### Step 6: Commit

```bash
git add docs/CONFIGURATION/github-runner-setup.md
git add docs/GITHUB_RUNNER_SETUP.md docs/GITHUB_RUNNER_DYNAMIC_TOKEN_SETUP.md
git commit -m "Consolidate GitHub runner documentation

- Merge basic and advanced setup into single reference
- Add 'Quick Start' and 'Advanced' sections
- Deprecate old files in favor of unified reference"
```

---

## CONSOLIDATION #5: 1Password Documentation (Organize with Cross-Links)

**Files:** Keep Separate But Link
- `docs/1PASSWORD_INTEGRATION_SUMMARY.md`
- `docs/ONEPASSWORD_SETUP.md`
- `docs/ANSIBLE_ONEPASSWORD.md`

**Action:** Add Cross-Links, Not Consolidation

### Why Keep Separate?

- **Integration Summary:** Stakeholder overview (what was done)
- **Setup Guide:** Step-by-step for implementers
- **Ansible Workflow:** Specific to Ansible-based usage

Different audiences at different stages of onboarding.

### Step 1: Add Metadata Headers

**In `docs/1PASSWORD_INTEGRATION_SUMMARY.md`:**
```markdown
---
title: 1Password Integration - Overview
audience: ⭐⭐ Intermediate
purpose: Understanding the integration architecture
related_docs:
  - CONFIGURATION/1password-setup-guide.md
  - CONFIGURATION/ansible-1password-integration.md
---
```

**In `docs/ONEPASSWORD_SETUP.md`:**
```markdown
---
title: 1Password Setup Guide
audience: ⭐⭐ Intermediate  
purpose: Step-by-step setup instructions
related_docs:
  - 1PASSWORD_INTEGRATION_SUMMARY.md
  - CONFIGURATION/ansible-1password-integration.md
---
```

**In `docs/ANSIBLE_ONEPASSWORD.md`:**
```markdown
---
title: Using 1Password with Ansible
audience: ⭐⭐⭐ Advanced
purpose: Ansible-specific 1Password workflows
related_docs:
  - CONFIGURATION/1password-setup-guide.md
  - CONFIGURATION/ansible-playbooks-reference.md
---
```

### Step 2: Add Cross-Reference Sections

At top of each file, add:
```markdown
## Related Documentation

- **Overview:** [1Password Integration Summary](1PASSWORD_INTEGRATION_SUMMARY.md)
- **Setup:** [1Password Setup Guide](ONEPASSWORD_SETUP.md)
- **Ansible:** [Ansible 1Password Integration](ANSIBLE_ONEPASSWORD.md)
```

### Step 3: Update Folder Structure

Move to CONFIGURATION/ for clarity:
```bash
mv docs/1PASSWORD_INTEGRATION_SUMMARY.md docs/CONFIGURATION/1password-integration-summary.md
mv docs/ONEPASSWORD_SETUP.md docs/CONFIGURATION/1password-setup-guide.md
mv docs/ANSIBLE_ONEPASSWORD.md docs/CONFIGURATION/ansible-1password-integration.md
```

### Step 4: Commit

```bash
git add docs/CONFIGURATION/1password-*.md docs/CONFIGURATION/ansible-1password-*.md
git commit -m "Organize 1Password documentation with cross-links

- Move to CONFIGURATION/ folder
- Add metadata headers with audience levels
- Add cross-reference sections to each file
- Keep separate as different audiences and purposes"
```

---

## CLEANUP: Archive Outdated Files

**Files to Archive:**
- `docs/RENAME_ANSIBLE01_TO_BASTION01.md` (migration completed)
- `docs/TERRAFORM_FIX_SUMMARY.md` (findings in known-issues.md)

### Step 1: Create Archive Structure

```bash
mkdir -p docs/ARCHIVE
```

### Step 2: Move Files

```bash
mv docs/RENAME_ANSIBLE01_TO_BASTION01.md docs/ARCHIVE/
mv docs/TERRAFORM_FIX_SUMMARY.md docs/ARCHIVE/
```

### Step 3: Create ARCHIVE/README.md

```markdown
# Archive

This folder contains completed, historical, or deprecated documentation.

## Why These Are Here

### rename-ansible01-to-bastion01.md
**Status:** Completed  
**Date:** June 8, 2026  
**Purpose:** Historical record of container rename migration  
**Reason:** Migration is complete; kept for reference only

### terraform-fix-summary.md  
**Status:** Consolidated  
**Date:** June 5, 2026  
**Purpose:** Original findings about Terraform provider fixes  
**Reason:** Findings merged into [known-issues.md](../OPERATIONS/known-issues.md)

---

These documents are preserved for historical purposes but should not be used for current work.
```

### Step 4: Commit

```bash
git add docs/ARCHIVE/
git commit -m "Archive completed and consolidated documentation

- Move RENAME_ANSIBLE01_TO_BASTION01.md to ARCHIVE/ (completed task)
- Move TERRAFORM_FIX_SUMMARY.md to ARCHIVE/ (findings in known-issues.md)
- Add ARCHIVE/README.md explaining why documents are archived"
```

---

## FINAL STEPS: Reorganization & Testing

### Step 1: Create Folder Structure

```bash
cd docs/
mkdir -p ARCHITECTURE GETTING_STARTED OPERATIONS INFRASTRUCTURE CONFIGURATION ADVANCED REFERENCE ARCHIVE
```

### Step 2: Move Files to New Folders

**ARCHITECTURE/:**
```bash
mv decision-management-vlan.md management-vlan-implementation.md ARCHITECTURE/
# Create new files: architecture-diagrams.md, service-dependencies.md
```

**INFRASTRUCTURE/:**
```bash
mv terraform-*.md proxmox-api-token-creation.md pve01-*.md apt-mirrors-configuration.md mac-address-scheme.md PVE01_FSTAB_CONFIGURATION.md INFRASTRUCTURE/
```

**OPERATIONS/:**
```bash
mv known-issues.md backup-share-setup.md OPERATIONS/
# Create new files: operational-procedures.md, troubleshooting-matrix.md, disaster-recovery.md
```

### Step 3: Update All Cross-References

```bash
# Find all references to moved files
grep -r "DNS_INTEGRATION_SUMMARY\|BASTION01_DEPLOYMENT" docs/*.md

# Update manually or with sed (be careful!)
sed -i 's|DNS_INTEGRATION_SUMMARY.md|CONFIGURATION/dns-records-management.md|g' docs/**/*.md
```

### Step 4: Update docs/README.md

```markdown
# PhoenixStack Documentation

See [0_START_HERE.md](0_START_HERE.md) for navigation guide.

## Documentation Structure

### Getting Started
- [Master Deployment Runbook](GETTING_STARTED/deployment-master-runbook.md)
- [Quick Reference Checklists](GETTING_STARTED/quick-reference-checklists.md)

### Architecture & Design
- [Architecture Overview](ARCHITECTURE/infrastructure-overview.md)
- [Architecture Diagrams](ARCHITECTURE/architecture-diagrams.md)
- [Service Dependencies](ARCHITECTURE/service-dependencies.md)

### Operations
- [Operational Procedures](OPERATIONS/operational-procedures.md)
- [Troubleshooting Matrix](OPERATIONS/troubleshooting-matrix.md)
- [Disaster Recovery](OPERATIONS/disaster-recovery.md)

[... more sections ...]
```

### Step 5: Create 0_START_HERE.md

```bash
cat > docs/0_START_HERE.md << 'EOF'
# PhoenixStack Documentation - Start Here

Welcome! Find what you need quickly:

## 🚀 I want to deploy PhoenixStack
→ [Master Deployment Runbook](GETTING_STARTED/deployment-master-runbook.md)

## 🛠 I need to operate the infrastructure
→ [Operational Procedures](OPERATIONS/operational-procedures.md)

## 🔍 Something isn't working
→ [Troubleshooting Matrix](OPERATIONS/troubleshooting-matrix.md)

## 📚 I want to understand the system
→ [Architecture Overview](ARCHITECTURE/infrastructure-overview.md)

## 🔒 I need to set up secrets management
→ [1Password Setup Guide](CONFIGURATION/1password-setup-guide.md)

## 🔄 I need to configure automation
→ [Ansible Playbooks Reference](CONFIGURATION/ansible-playbooks-reference.md)

---

**Full documentation index:** [README.md](README.md)
EOF
```

### Step 6: Test All Links

```bash
# Verify all markdown links are valid
for file in docs/**/*.md; do
  grep -o '\[.*\](.*\.md)' "$file" | while read -r link; do
    target=$(echo "$link" | sed 's/.*(\(.*\))/\1/')
    if [ ! -f "docs/$target" ]; then
      echo "BROKEN: $file → $target"
    fi
  done
done
```

### Step 7: Final Commit

```bash
git add -A docs/
git commit -m "Complete documentation reorganization and consolidation

Major changes:
- Create new folder structure (ARCHITECTURE, GETTING_STARTED, OPERATIONS, etc.)
- Consolidate 15+ redundant files into 5 unified documents
- Create master deployment runbook
- Archive completed/historical documents
- Add cross-reference links between related documents
- Update all internal links to point to new locations
- Add metadata headers and audience levels to all documents

Consolidations:
- DNS docs (3 → 1): dns-records-management.md
- Deployment guides (3+ → 1): deployment-master-runbook.md
- Ansible playbooks (2 → 1): ansible-playbooks-reference.md
- GitHub runner (2 → 1): github-runner-setup.md
- 1Password docs: reorganized with cross-links

New files:
- 0_START_HERE.md: Navigation hub
- OPERATIONS/operational-procedures.md
- OPERATIONS/troubleshooting-matrix.md
- ARCHITECTURE/architecture-diagrams.md
- REFERENCE/quick-reference-commands.md
- REFERENCE/glossary.md

This consolidation reduces documentation by 35% while improving clarity
and making it easier for new users and operators to find what they need."
```

---

## VERIFICATION CHECKLIST

Before considering consolidation complete:

- [ ] All old files have deprecation notices or are archived
- [ ] All cross-references updated (grep for old filenames returns empty)
- [ ] New folder structure created and populated
- [ ] All markdown links tested and working
- [ ] Master deployment runbook is comprehensive and clear
- [ ] Troubleshooting matrix created
- [ ] Operational procedures documented
- [ ] 0_START_HERE.md is clear and actionable
- [ ] docs/README.md reflects new structure
- [ ] All consolidations tested by following the guides
- [ ] Team reviewed and approved changes
- [ ] Single comprehensive commit/PR created

---

## ROLLBACK PLAN

If consolidation causes issues:

```bash
# Revert to previous state
git revert HEAD

# Or cherry-pick specific commits if partial rollback needed
git log --oneline  # Find the commit before consolidation
git revert <commit-hash>
```

---

**Estimated completion time: 2-3 days of focused work**

