# PhoenixStack Roadmap & Future Architecture

**Purpose**: Planning documentation for future infrastructure phases, architectural enhancements, and strategic roadmap items.

**Status**: 📅 Planning Phase  
**Last Updated**: 2026-07-29

---

## Overview

This folder contains forward-looking documentation for PhoenixStack infrastructure. These documents describe future capabilities, planned enhancements, and strategic architecture evolution that are **not yet deployed** in production.

**For operational documentation about currently deployed infrastructure, see [../README.md](../README.md)**

---

## 📋 Roadmap Documents

### Phase 3: Control Plane & CI/CD

**GitHub Actions Self-Hosted Runners**
- [GITHUB_RUNNER_SETUP.md](GITHUB_RUNNER_SETUP.md) - Complete GitHub Actions runner guide (basic + advanced dynamic token generation)
- **Status**: 📅 Phase 3 (BASTION01 deployment planning)
- **Dependencies**: BASTION01 container deployment, 1Password integration

**CI/CD Analysis**
- [TIER_4_CI_ANALYSIS.md](TIER_4_CI_ANALYSIS.md) - Advanced automation and CI/CD architecture analysis
- **Status**: 📅 Future phase analysis
- **Scope**: Multi-tier CI/CD patterns, testing strategies, deployment pipelines

---

### Phase 4+: High Availability & Redundancy

**High Availability Strategy**
- [HA_REDUNDANCY_STRATEGY.md](HA_REDUNDANCY_STRATEGY.md) - High availability and redundancy architecture planning
- **Status**: 📅 Phase 4+ (Future enhancement)
- **Scope**: Failover, load balancing, service redundancy, disaster recovery planning
- **Note**: Renamed from HA_REDUNDANCY_TODO.md to reflect strategic planning nature

---

### Infrastructure Standards & Design

**Network & Infrastructure Architecture**
- [INFRASTRUCTURE_DESIGN.md](INFRASTRUCTURE_DESIGN.md) - Comprehensive infrastructure design including hardware specs, network architecture, MAC addressing scheme, and infrastructure standards
- **Status**: 📋 Reference document for infrastructure planning and deployment
- **Scope**: Hardware specifications, network design, MAC allocation, service tiers, design standards

---

## 🎯 Navigation Guide

### I want to...

**...understand the future GitHub Runner architecture**  
→ Start with [GITHUB_RUNNER_SETUP.md](GITHUB_RUNNER_SETUP.md) for the baseline setup, then [GITHUB_RUNNER_DYNAMIC_TOKEN_SETUP.md](GITHUB_RUNNER_DYNAMIC_TOKEN_SETUP.md) for advanced token generation patterns.

**...plan for high availability**  
→ See [HA_REDUNDANCY_STRATEGY.md](HA_REDUNDANCY_STRATEGY.md) for comprehensive HA planning across all tiers.

**...understand the CI/CD vision**  
→ See [TIER_4_CI_ANALYSIS.md](TIER_4_CI_ANALYSIS.md) for multi-tier testing and deployment architecture.

**...plan infrastructure addressing**  
→ See [INFRASTRUCTURE_DESIGN.md](INFRASTRUCTURE_DESIGN.md) for hardware specs, network architecture, and standardized MAC allocation patterns.

---

## 🔄 Roadmap Status Matrix

| Phase | Component | Status | Documentation | Target |
|-------|-----------|--------|---------------|--------|
| Phase 3 | BASTION01 | 📅 Planning | [GITHUB_RUNNER_SETUP.md](GITHUB_RUNNER_SETUP.md) | Q1 2026 |
| Phase 3 | GitHub Runners | 📅 Planning | [GITHUB_RUNNER_DYNAMIC_TOKEN_SETUP.md](GITHUB_RUNNER_DYNAMIC_TOKEN_SETUP.md) | Q1 2026 |
| Phase 4 | High Availability | 📅 Future | [HA_REDUNDANCY_STRATEGY.md](HA_REDUNDANCY_STRATEGY.md) | TBD |
| Phase 4+ | CI/CD Pipeline | 📅 Future | [TIER_4_CI_ANALYSIS.md](TIER_4_CI_ANALYSIS.md) | TBD |

---

## 📖 Document Conventions

### Status Indicators

- **📅 Planning**: Document describes future capabilities not yet implemented
- **🔄 In-Progress**: Actively being worked on or partially deployed
- **✅ Complete**: Fully deployed and operational (moves to ../docs/)

### Lifecycle

1. **Planning docs start here** in `roadmap/` with 📅 status
2. **During implementation**, docs move to 🔄 status (can stay in roadmap/ or move to ../docs/)
3. **After deployment**, docs become ✅ and live in `../docs/` as operational reference

---

## 🔗 Related Documentation

- [../README.md](../README.md) - Main documentation index (deployed infrastructure)
- [../DNS_INTEGRATION.md](../DNS_INTEGRATION.md) - Current DNS architecture (operational)
- [../PVE01_DRIFT_SUMMARY.md](../PVE01_DRIFT_SUMMARY.md) - Hypervisor baseline validation
- [../PROXMOX_BACKUP_INFRASTRUCTURE.md](../PROXMOX_BACKUP_INFRASTRUCTURE.md) - Current backup architecture
- [../../scripts/validation/README.md](../../scripts/validation/README.md) - Validation workflows

---

## Contributing

When creating new roadmap documentation:

1. **Use clear status indicators**: 📅 Planning, 🔄 In-Progress, ✅ Complete
2. **Define dependencies**: What must exist before this can be implemented?
3. **Specify scope**: What is included and excluded from this phase?
4. **Include target dates**: When is this planned for deployment?
5. **Cross-reference**: Link to related operational docs and dependencies

---

*Last Review: 2026-07-29*  
*Next Review: After each major phase completion*
