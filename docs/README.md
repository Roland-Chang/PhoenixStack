# PhoenixStack Documentation

Central documentation repository for PhoenixStack infrastructure and operations.

## Validation and Baseline

- [pve01-validation-commands.md](pve01-validation-commands.md) - Command-ready PVE01 validation runbook (Bash/Linux)
- [pve01-validation-commands.ps1](pve01-validation-commands.ps1) - Command-ready PVE01 validation script (PowerShell/Windows)
- [pve01-validation-report-template.md](pve01-validation-report-template.md) - Standardized drift report template

## Infrastructure Configuration

- [apt-mirrors-configuration.md](apt-mirrors-configuration.md) - APT mirror strategy and implementation for package management
- [mac-address-scheme.md](mac-address-scheme.md) - MAC addressing scheme for consistent container identification

## Documentation Standards

1. **File naming**: topic-purpose.md (lowercase, hyphens for spaces)
2. **Purpose statement**: Every doc starts with a clear purpose
3. **Decisions**: Use decision records for architectural choices
4. **Runbooks**: Command-ready, copy-paste executable where possible
5. **Templates**: Provide structure for repeatable processes

## Quick Reference

### Security Standards
- SSH key-only authentication (default for all infrastructure)
- Management VLAN segmentation (10.101.0.0/24, VLAN 10)
- Workload VLAN segmentation (10.101.1.0/24, VLAN 100)
- No plaintext secrets in any repository content
- Least-privilege firewall policies between VLANs
- IPv6 disabled unless explicitly required

### Current Phase
Phase 1: Network Configuration and Baseline Validation - implementing management VLAN and validating PVE01 migration.
