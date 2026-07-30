# PhoenixStack Infrastructure Design

**Purpose**: Comprehensive infrastructure design documentation including hardware specifications, network architecture, MAC addressing scheme, and infrastructure standards for PhoenixStack.

**Status**: 📋 Design Reference  
**Last Updated**: 2026-07-29

---

## Table of Contents

1. [Overview](#overview)
2. [Hardware Specifications](#hardware-specifications)
3. [Network Architecture](#network-architecture)
4. [MAC Address Scheme](#mac-address-scheme)
5. [Service Tier Architecture](#service-tier-architecture)
6. [Infrastructure Standards](#infrastructure-standards)
7. [Future Expansion](#future-expansion)

---

## Overview

PhoenixStack is a homelab and learning environment with production services for personal and family use. The infrastructure is designed with:

- **Security First**: All design decisions prioritize security
- **Scalability**: Framework supports easy addition of new services
- **Best Practices**: Adheres to industry standards for infrastructure management
- **Automation**: Infrastructure as Code (IaC) with Terraform and Ansible
- **Modularity**: Well-architected framework of reusable modules

---

## Hardware Specifications

### Compute Hardware

**Proxmox Host (PVE01)**
- **Model**: Dell PowerEdge T640 Tower Server
- **Service Tag**: 5MWT7X2
- **BIOS**: Version 2.27.0
- **CPU**: Dual Intel Xeon 5118 @ 2.30GHz (24 cores total)
- **RAM**: 256GB DDR4 2400 MT/s
- **GPU**: Nvidia Quadro P2000
- **Networking**: 10Gb capable
- **Hostname**: pve01.phoenix.stack
- **Management IP**: 10.101.0.11/24 (VLAN 10)
- **iDRAC/IPMI**: ipmi-pve01.phoenix.stack @ 10.101.0.1

### Network Hardware

**100% Ubiquiti Environment**
- **Gateway**: UniFi Dream Machine SE
- **Core Switch**: UniFi USW 10Gb Aggregation Switch
- **Distribution**: UniFi USW 24 PoE
- **Workgroup**: UniFi USW Flex XG
- **Wireless**: UniFi U7-Pro-Wall (×3)

**Management**: UniFi Network Application via Dream Machine SE

### Storage Hardware

**UNAS01 - UniFi UNAS Pro**
- **Hostname**: unas01.phoenix.stack
- **IP Address**: 10.101.0.101
- **Networking**: 10Gb
- **Protocols**: CIFS/SMB (primary), NFS (available)
- **Purpose**: Centralized backup storage, ISO storage, media storage

**Storage Shares**:
- `/Backups/` - Container and system backups
- `/ISO/` - Operating system images and templates
- `/Media/` - Media files for Plex and other services

---

## Network Architecture

### Site Overview

**PHOENIX-PRIMARY Site**
- **WAN**: Direct Communications 1Gb/1Gb fiber optic internet
- **Primary Subnet**: 10.101.0.0/16
- **Management VLAN**: VLAN 10 (10.101.0.0/24) - native/untagged
- **Workload VLAN**: VLAN 100 (10.101.1.0/24) - tagged
- **Gateway**: 10.101.0.254
- **Internal Domain**: phoenix.stack
- **External Domain**: phoenixstack.net

**Future Sites** (Reserved):
- PHOENIX-SECONDARY: 10.102.0.0/16
- PHOENIX-TERTIARY: 10.103.0.0/16
- Cloud-Based: 10.100.0.0/16

### VLAN Configuration

| VLAN | Subnet | Purpose | Tagged/Native |
|------|--------|---------|---------------|
| 10 | 10.101.0.0/24 | Management & Infrastructure | Native (untagged) |
| 100 | 10.101.1.0/24 | Workload & Services | Tagged |

### DNS Configuration

**External DNS**:
- **Provider**: CloudFlare (Orange Cloud proxy enabled)
- **Servers**: 1.1.1.1, 1.0.0.1
- **Registrar**: Namecheap
- **Email**: Microsoft M365 MX records

**Internal DNS**:
- **Primary**: dns01.phoenix.stack @ 10.101.0.201
- **Secondary**: dns02.phoenix.stack @ 10.101.0.202
- **Technology**: PiHole + Unbound (deployed via Terraform + Ansible)
- **Domain**: phoenix.stack (internal)

### Key Infrastructure IPs

| Device/Service | Hostname | IP Address | VLAN | Notes |
|----------------|----------|------------|------|-------|
| iDRAC/IPMI | ipmi-pve01.phoenix.stack | 10.101.0.1 | 10 | Out-of-band management |
| Proxmox Host | pve01.phoenix.stack | 10.101.0.11 | 10 | Hypervisor management |
| UNAS Storage | unas01.phoenix.stack | 10.101.0.101 | 10 | Backup and media storage |
| Gateway | gateway.phoenix.stack | 10.101.0.254 | 10 | UniFi Dream Machine SE |
| DNS Primary | dns01.phoenix.stack | 10.101.0.201 | 10 | PiHole DNS server |
| DNS Secondary | dns02.phoenix.stack | 10.101.0.202 | 10 | PiHole DNS server |

---

## MAC Address Scheme

### Overview

PhoenixStack uses a **consistent, predictable MAC addressing scheme** for all LXC containers to ensure:
- Stable DHCP assignments
- Persistent DNS records
- Reliable network device tracking
- Clean UniFi controller history

### Scheme Format

```
Format: 02:AA:BB:CC:XX:YY

  02       = Locally administered unicast prefix (IEEE 802 standard)
  AA:BB:CC = PhoenixStack identifier (fixed to "aa:bb:cc")
  XX       = Service type (01-FF for different service tiers)
  YY       = Instance number (01-FF for up to 255 instances per tier)
```

### Rationale

- **02 prefix**: IEEE standard for locally administered addresses
- **aa:bb:cc block**: Memorable identifier distinguishing PhoenixStack devices
- **Service type (XX)**: Groups related services by tier/function
- **Instance number (YY)**: Supports multiple instances per service type

### Service Type Reference

| Service Type | Code (XX) | Purpose |
|--------------|-----------|---------|
| Bastion/Ansible | 01 | Configuration management, orchestration |
| DNS | 02 | Domain name resolution (PiHole/Unbound) |
| Proxy | 03 | Reverse proxy, load balancing (Traefik) |
| Authentik | 04 | Authentication, authorization, OIDC/OAuth |
| Game Server | 05 | Game server hosting (AMP by CubeCoders) |
| Media | 06 | Media servers (Plex, etc.) |
| Database | 07 | PostgreSQL, MariaDB clusters |
| Monitor | 08 | Monitoring, logging, observability |
| Vault | 09 | Secrets management (HashiCorp Vault) |
| Docker/Workload | 10 | Container workloads, general services |
| Backup | 11 | Backup orchestration and management |
| Reserved | 12-FF | Future service types |

### Assigned MAC Addresses

#### Management & Orchestration Tier (XX=01)

| Container | Hostname | VMID | MAC Address | IP Address | Status |
|-----------|----------|------|-------------|------------|--------|
| Bastion Primary | bastion01 | 10101 | `02:aa:bb:cc:01:01` | 10.101.0.20 | ✅ Active |
| Bastion Secondary | bastion02 | 10102 | `02:aa:bb:cc:01:02` | 10.101.0.21 | ✅ Active |

#### DNS Tier (XX=02)

| Container | Hostname | VMID | MAC Address | IP Address | Status |
|-----------|----------|------|-------------|------------|--------|
| DNS Primary | dns01 | 10201 | `02:aa:bb:cc:02:01` | 10.101.0.201 | ✅ Deployed |
| DNS Secondary | dns02 | 10202 | `02:aa:bb:cc:02:02` | 10.101.0.202 | ✅ Deployed |

#### Proxy/Ingress Tier (XX=03)

| Container | Hostname | VMID | MAC Address | IP Address | Status |
|-----------|----------|------|-------------|------------|--------|
| Proxy Primary | proxy01 | 10301 | `02:aa:bb:cc:03:01` | 10.101.0.31 | 🔄 Planned |
| Proxy Secondary | proxy02 | 10302 | `02:aa:bb:cc:03:02` | 10.101.0.32 | 🔄 Planned |

#### Identity & Authentication Tier (XX=04)

| Container | Hostname | VMID | MAC Address | IP Address | Status |
|-----------|----------|------|-------------|------------|--------|
| Authentik Primary | authentik01 | 10401 | `02:aa:bb:cc:04:01` | 10.101.0.41 | 🔄 Planned |
| Authentik Secondary | authentik02 | 10402 | `02:aa:bb:cc:04:02` | 10.101.0.42 | 🔄 Planned |

#### Workload Tier (XX=10)

| Container | Hostname | VMID | MAC Address | IP Address | Status |
|-----------|----------|------|-------------|------------|--------|
| Docker Primary | docker01 | 11001 | `02:aa:bb:cc:10:01` | 10.101.0.51 | ✅ Active |
| Docker Secondary | docker02 | 11002 | `02:aa:bb:cc:10:02` | 10.101.0.52 | ✅ Active |

#### Media Tier (XX=06)

| Container | Hostname | VMID | MAC Address | IP Address | Status |
|-----------|----------|------|-------------|------------|--------|
| Media Server | plex01 | 10601 | `02:aa:bb:cc:06:01` | 10.101.0.61 | 🔄 Planned |

#### Database Tier (XX=07)

| Container | Hostname | VMID | MAC Address | IP Address | Status |
|-----------|----------|------|-------------|------------|--------|
| PostgreSQL Primary | pgsql01 | 10701 | `02:aa:bb:cc:07:01` | 10.101.0.71 | 🔄 Planned |
| PostgreSQL Secondary | pgsql02 | 10702 | `02:aa:bb:cc:07:02` | 10.101.0.72 | 🔄 Planned |
| MariaDB Primary | mariadb01 | 10703 | `02:aa:bb:cc:07:03` | 10.101.0.73 | 🔄 Planned |

#### Game Server Tier (XX=05)

| Container | Hostname | VMID | MAC Address | IP Address | Status |
|-----------|----------|------|-------------|------------|--------|
| Game Server | amp01 | 10501 | `02:aa:bb:cc:05:01` | 10.101.0.81 | 🔄 Planned |

#### Monitoring Tier (XX=08)

| Container | Hostname | VMID | MAC Address | IP Address | Status |
|-----------|----------|------|-------------|------------|--------|
| Monitor | monitor01 | 10801 | `02:aa:bb:cc:08:01` | 10.101.0.91 | 🔄 Planned |

#### Secrets Management Tier (XX=09)

| Container | Hostname | VMID | MAC Address | IP Address | Status |
|-----------|----------|------|-------------|------------|--------|
| Vault | vault01 | 10901 | `02:aa:bb:cc:09:01` | 10.101.0.101 | 🔄 Planned |

### Usage in Terraform

MAC addresses are assigned in Terraform module configurations:

```hcl
# Example: terraform/modules/dns/terraform.tfvars
mac_address = "02:aa:bb:cc:02:01"  # DNS service, instance 1
```

**Important**: Always specify MAC addresses in Terraform. If omitted, Proxmox auto-generates a new MAC on each deployment, causing:
- Multiple DHCP entries in UniFi
- Fragmented network history
- DNS record inconsistencies

### Benefits of Fixed MAC Addresses

✅ **Stable DHCP**: UniFi Dream Machine recognizes the same device across redeployments  
✅ **Consistent DNS**: Records remain valid despite container recreation  
✅ **Clean History**: Network monitoring shows continuous device history  
✅ **Reliable Tracking**: Security and audit logs maintain device continuity  

---

## Proxmox VMID Scheme

### Overview

PhoenixStack uses a **consistent, predictable VMID scheme** aligned with the MAC address service type codes. This ensures:
- Instant service identification from VMID in Proxmox UI
- Perfect alignment with MAC addressing
- Scalable infrastructure (up to 99 instances per service type)
- Self-documenting resource IDs

### Scheme Format

```
Format: 1XXYY

  1  = PhoenixStack infrastructure prefix
  XX = Service type code (matches MAC address scheme: 01-11)
  YY = Instance number (01-99 for up to 99 instances per tier)
```

### Examples

| Service | Service Type | VMID | Calculation |
|---------|--------------|------|-------------|
| bastion01 | 01 (bastion) | **10101** | 1 + 01 + 01 |
| dns01 | 02 (dns) | **10201** | 1 + 02 + 01 |
| proxy01 | 03 (proxy) | **10301** | 1 + 03 + 01 |
| docker01 | 10 (docker) | **11001** | 1 + 10 + 01 |
| pgsql01 | 07 (database) | **10701** | 1 + 07 + 01 |
| vault01 | 09 (vault) | **10901** | 1 + 09 + 01 |

### Service Type to VMID Mapping

| Service Type | Code (XX) | VMID Range | Example Services |
|--------------|-----------|------------|------------------|
| Bastion | 01 | 10101-10199 | bastion01 (10101), bastion02 (10102) |
| DNS | 02 | 10201-10299 | dns01 (10201), dns02 (10202) |
| Proxy | 03 | 10301-10399 | proxy01 (10301), proxy02 (10302) |
| Authentik | 04 | 10401-10499 | authentik01 (10401), authentik02 (10402) |
| Game Server | 05 | 10501-10599 | amp01 (10501), amp02 (10502) |
| Media | 06 | 10601-10699 | plex01 (10601), plex02 (10602) |
| Database | 07 | 10701-10799 | pgsql01 (10701), pgsql02 (10702), mariadb01 (10703) |
| Monitor | 08 | 10801-10899 | monitor01 (10801), monitor02 (10802) |
| Vault | 09 | 10901-10999 | vault01 (10901), vault02 (10902) |
| Docker | 10 | 11001-11099 | docker01 (11001), docker02 (11002) |
| Backup | 11 | 11101-11199 | backup01 (11101) |

### Benefits of Aligned VMID Scheme

✅ **Instant Recognition**: See VMID 10701 in Proxmox UI → immediately know it's pgsql01 (database tier, instance 01)  
✅ **Consistent with MAC**: VMID 10201 has MAC `02:aa:bb:cc:02:01` (both use service code 02)  
✅ **Scalable**: 99 instances per service type (e.g., docker01-docker99)  
✅ **Self-Documenting**: No external lookup needed to understand resource purpose  
✅ **Debugging**: Correlate Proxmox logs, MAC addresses, and service names instantly  

### Usage in Terraform

VMIDs are explicitly assigned in [terraform/terraform.tf](../../terraform/terraform.tf):

```hcl
module "dns01" {
  source = "./modules/dns"
  
  instance_vmid     = 10201  # Service type 02 (dns), instance 01
  instance_hostname = "dns01"
  mac_address       = "02:aa:bb:cc:02:01"  # Matches service type 02
  # ...
}
```

**Important**: Always specify VMIDs in Terraform. Proxmox auto-assignment can cause:
- VMID collisions with future planned services
- Loss of VMID-to-service correlation
- Confusion when reading Proxmox UI or logs

---

## Service Tier Architecture

PhoenixStack services are organized into logical tiers for clear separation of concerns and dependencies:

### Tier 1: Management & Orchestration
**Purpose**: Infrastructure automation and configuration management  
**Services**: Bastion (Ansible)  
**Dependencies**: None (foundational tier)  
**Status**: ✅ Active

### Tier 2: DNS & Core Services
**Purpose**: Name resolution and foundational network services  
**Services**: DNS (PiHole + Unbound)  
**Dependencies**: Tier 1 (deployed via Ansible)  
**Status**: ✅ Deployed

### Tier 3: Edge & Ingress
**Purpose**: External access and traffic routing  
**Services**: Proxy (Traefik)  
**Dependencies**: Tier 2 (requires DNS)  
**Status**: 🔄 Planned (Phase 3)

### Tier 4: Identity & Authentication
**Purpose**: Authentication, authorization, OAuth/OIDC  
**Services**: Authentik  
**Dependencies**: Tier 3 (requires proxy for HTTPS), Database tier  
**Status**: 🔄 Planned (Phase 4)

### Tier 5: Data & Persistence
**Purpose**: Database services for applications  
**Services**: PostgreSQL, MariaDB  
**Dependencies**: Tier 1 (deployed via Ansible)  
**Status**: 🔄 Planned (Phase 4)

### Tier 6: Workloads & Applications
**Purpose**: Application hosting and container orchestration  
**Services**: Docker, Plex, AMP (game servers)  
**Dependencies**: Tier 2 (DNS), Tier 3 (Proxy), Tier 4 (Auth - optional)  
**Status**: 🔄 Mixed (Docker ✅ Active, others Planned)

### Tier 7: Observability & Operations
**Purpose**: Monitoring, logging, metrics  
**Services**: Monitoring stack  
**Dependencies**: All tiers (monitors everything)  
**Status**: 🔄 Planned (Phase 5+)

### Tier 8: Security & Secrets
**Purpose**: Secrets management and rotation  
**Services**: HashiCorp Vault  
**Dependencies**: Tier 1 (deployed via Ansible), Tier 3 (Proxy for HTTPS)  
**Status**: 🔄 Planned (Phase 5+)

---

## Infrastructure Standards

### Deployment Methodology

**Infrastructure as Code (IaC)**:
- **Provisioning**: Terraform for resource creation
- **Configuration**: Ansible for service configuration
- **Version Control**: GitHub (repository: Roland-Chang/PhoenixStack)
- **CI/CD**: GitHub Actions for automation

### Container Standards

**Platform**: LXC containers (not Docker containers) for services  
**OS**: Ubuntu Server 22.04 LTS or 24.04 LTS  
**Privileges**: Unprivileged containers (security best practice)  
**Features**: Nesting enabled where required (for Docker-in-LXC)

### Security Standards

**Secrets Management**:
- ❌ **NEVER** store secrets in plain text
- ✅ Use 1Password for secret storage
- ✅ Use Ansible Vault for encrypted playbook variables
- ✅ Retrieve secrets via 1Password Service Account tokens

**Access Control**:
- SSH key-based authentication (no passwords)
- Least privilege principle
- sudo access logged and audited

**Network Security**:
- VLAN segmentation (management vs workload)
- Firewall rules at UniFi level
- HTTPS for all external services (via Traefik + Let's Encrypt)

### Backup Standards

**Strategy**: See [PROXMOX_BACKUP_INFRASTRUCTURE.md](../PROXMOX_BACKUP_INFRASTRUCTURE.md)  
**Retention**:
- Critical services: 14 days
- Standard services: 7 days
- Daily snapshots (automated)

**Storage**: UNAS01 shares mounted on pve01, passed through to containers

### Documentation Standards

**Location**: `docs/` folder (operational), `docs/roadmap/` (planning)  
**Format**: Markdown (.md files)  
**Editor**: VS Code with GitHub Copilot  
**Style**: Clear, concise, with examples and troubleshooting sections

---

## Future Expansion

### Multi-Site Architecture

**Planned Sites**:
- **PHOENIX-SECONDARY**: 10.102.0.0/16 (failover/disaster recovery)
- **PHOENIX-TERTIARY**: 10.103.0.0/16 (edge/remote location)
- **Cloud Integration**: 10.100.0.0/16 (Azure/AWS hybrid)

### High Availability

**Target Services for HA** (see [HA_REDUNDANCY_STRATEGY.md](HA_REDUNDANCY_STRATEGY.md)):
- DNS: Active-Active (✅ Deployed)
- Proxy: Active-Passive (🔄 Planned)
- Authentik: Active-Passive (🔄 Planned)
- Database: Primary-Standby replication (🔄 Planned)

### Scalability Considerations

**MAC Address Scheme**: Supports 255 instances per service tier (current design)  
**IP Addressing**: /16 subnets provide 65,534 addresses per site  
**VMID Range**: Proxmox supports 100-999999999 (effectively unlimited)  

**Expansion Path**:
1. Add services within existing tiers (up to 255 instances each)
2. Define new service types (codes 11-FF available)
3. Deploy to additional sites (SECONDARY, TERTIARY, Cloud)
4. Implement cross-site replication and failover

### Cloud Integration

**Future Considerations**:
- **Azure**: Primary cloud target (M365 integration)
- **AWS**: Secondary consideration
- **Hybrid Connectivity**: VPN or private connectivity
- **Workload Migration**: Lift-and-shift or cloud-native refactoring

---

## Software & Tooling Standards

### Development Environment

**IDE**: Visual Studio Code  
**AI Assistant**: GitHub Copilot  
**Source Control**: GitHub Pro  
**Repository**: Roland-Chang/PhoenixStack

### Infrastructure Tools

**IaC Provisioning**: Terraform (primary)  
**Configuration Management**: Ansible (primary)  
**Secrets Management**: 1Password (current), HashiCorp Vault (future)  
**CI/CD**: GitHub Actions  

### Operating Systems

**Workstations**:
- Windows 11 Professional
- Linux Mint Cinnamon (dual-boot/alternate)

**Servers**:
- Proxmox VE 9.1.1+ (hypervisor)
- Ubuntu Server 22.04/24.04 LTS (LXC containers)

**Default Editor**: nano (all Linux environments)

### Application Stack

**Reverse Proxy**: Traefik  
**Authentication**: Authentik (OAuth/OIDC)  
**DNS**: PiHole + Unbound  
**Container Platform**: Docker + Docker Compose  
**Monitoring**: TBD (Prometheus/Grafana planned)  
**Secrets**: 1Password (current), Vault (planned)  

### Productivity & External Services

**Email & Productivity**: Microsoft 365  
**OAuth/Identity**: Microsoft Entra ID (integrated with Authentik)  
**DNS Registrar**: Namecheap  
**CDN/Proxy**: CloudFlare  
**Backup Storage**: UniFi UNAS Pro  

---

## References

### Internal Documentation

- [HA_REDUNDANCY_STRATEGY.md](HA_REDUNDANCY_STRATEGY.md) - High availability strategy and decisions
- [GITHUB_RUNNER_SETUP.md](GITHUB_RUNNER_SETUP.md) - CI/CD runner deployment
- [TIER_4_CI_ANALYSIS.md](TIER_4_CI_ANALYSIS.md) - CI/CD pipeline analysis
- [../PROXMOX_BACKUP_INFRASTRUCTURE.md](../PROXMOX_BACKUP_INFRASTRUCTURE.md) - Backup strategy
- [../DNS_INTEGRATION.md](../DNS_INTEGRATION.md) - DNS architecture and records
- [../1PASSWORD_INTEGRATION.md](../1PASSWORD_INTEGRATION.md) - Secrets management setup

### External References

- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Terraform Documentation](https://www.terraform.io/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [UniFi Documentation](https://help.ui.com/)
- [IEEE 802 MAC Address Standard](https://standards.ieee.org/standard/802-2014.html)

---

## Document History

| Date | Change | Author |
|------|--------|--------|
| 2026-07-29 | Initial infrastructure design document consolidating MAC scheme and hardware specs | Infrastructure Team |
| | | |

---

**Status Legend**:
- ✅ Active/Deployed
- 🔄 In Progress/Planned
- 📋 Design/Planning
- ❌ Deprecated/Removed
