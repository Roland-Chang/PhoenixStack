# MAC Address Scheme

**Purpose**: Define a consistent, predictable MAC addressing scheme for all PhoenixStack infrastructure to ensure stable DHCP assignments, DNS records, and network device tracking.

## MAC Address Fundamentals

### Structure
A MAC address is 48 bits (6 octets), written as: `XX:XX:XX:XX:XX:XX`

### Rules
Every MAC address has two special bits in the first octet:

| Bit | Position | Name | Values |
|---|---|---|---|
| Bit 0 (LSB) | Rightmost | Unicast/Multicast | 0 = Unicast (individual device), 1 = Multicast (group) |
| Bit 1 | Second from right | Administration | 0 = Universally Administered (OUI assigned), 1 = Locally Administered (custom) |

**For PhoenixStack, we use locally administered unicast addresses:**
- First octet must have bit 1 set to 1 and bit 0 set to 0
- Valid first octets: `02, 06, 0A, 0E, 12, 16, 1A, 1E, 22, 26, 2A, 2E, 32, 36, 3A, 3E, ...`
- We use `02` (binary: `0000 0010`)

## PhoenixStack MAC Scheme

```
Format: 02:AA:BB:CC:XX:YY

  02       = Locally administered unicast prefix (required by standard)
  AA:BB:CC = PhoenixStack identifier block (fixed to "aa:bb:cc")
  XX       = Service type (01-99 for different services)
  YY       = Instance number (01-FF for up to 255 instances)
```

### Rationale
- **02 prefix**: Standard for locally administered addresses, clearly indicates custom-assigned MAC
- **aa:bb:cc middle block**: Memorable, distinguishes PhoenixStack devices from other VMs
- **Service type (XX)**: Groups related services (01=Ansible tier, 02=DNS tier, etc.)
- **Instance number (YY)**: Allows multiple instances of each service

## Service Type Reference

| Service | XX | Purpose |
|---|---|---|
| Bastion/Ansible | 01 | Configuration management, orchestration |
| DNS | 02 | Domain name resolution, PiHole/Unbound |
| Proxy | 03 | Reverse proxy, load balancing |
| Authentik | 04 | Authentication, authorization, OIDC |
<<<<<<< HEAD
| Game Server (AMP) | 05 | Game server hosting, AMP by CubeCoders |
| Media | 06 | Media servers (Plex, etc.) |
| Docker | 10 | Workloads, container services |
| Reserved | 07-09, 11-FF | Future services |
=======
| Database | 07 | PostgreSQL database cluster |
| Monitor | 06 | Monitoring, logging, observability |
| Workload | 10 | Workloads, container services (Docker) |
| Reserved | 08-0F, 11-FF | Future services |
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072

## Assigned MAC Addresses

### Management & Orchestration Tier
| Container | Hostname | VMID | MAC Address | IP Address | Status |
|---|---|---|---|---|---|
| Bastion Primary | bastion01 | 101 | `02:aa:bb:cc:01:01` | 10.101.0.21 | ✅ Active |
| Bastion Secondary | bastion02 | 102 | `02:aa:bb:cc:01:02` | 10.101.0.22 | ✅ Active |

### DNS Tier
| Container | Hostname | VMID | MAC Address | IP Address | Status |
|---|---|---|---|---|---|
| DNS Primary | dns01 | 103 | `02:aa:bb:cc:02:01` | 10.101.0.201 | ✅ Deployed |
| DNS Secondary | dns02 | 104 | `02:aa:bb:cc:02:02` | 10.101.0.202 | ✅ Deployed |

### Proxy/Ingress Tier
| Container | Hostname | VMID | MAC Address | IP Address | Status |
|---|---|---|---|---|---|
| Proxy Primary | proxy01 | 105 | `02:aa:bb:cc:03:01` | 10.101.0.31 | 🔄 Planned |
| Proxy Secondary | proxy02 | 106 | `02:aa:bb:cc:03:02` | 10.101.0.32 | 🔄 Planned |

### Identity & Authentication Tier
| Container | Hostname | VMID | MAC Address | IP Address | Status |
|---|---|---|---|---|---|
| Authentik Primary | authentik01 | 107 | `02:aa:bb:cc:04:01` | 10.101.0.41 | 🔄 Planned |
| Authentik Secondary | authentik02 | 108 | `02:aa:bb:cc:04:02` | 10.101.0.42 | 🔄 Planned |

### Workload Tier
| Container | Hostname | VMID | MAC Address | IP Address | Status |
|---|---|---|---|---|---|
<<<<<<< HEAD
| Docker Primary | docker01 | 109 | `02:aa:bb:cc:10:01` | 10.101.0.51 | ✅ Active |
| Docker Secondary | docker02 | 110 | `02:aa:bb:cc:10:02` | 10.101.0.52 | ✅ Active |

### Media Tier
| Container | Hostname | VMID | MAC Address | IP Address | Status |
|---|---|---|---|---|---|
| Media Server Primary | plex01 | 111 | `02:aa:bb:cc:06:01` | 10.101.0.61 | 🔄 Planned |
| Media Server Secondary | plex02 | 112 | `02:aa:bb:cc:06:02` | 10.101.0.62 | 🔄 Planned |

### Game Server Tier (AMP by CubeCoders)
| Container | Hostname | VMID | MAC Address | IP Address | Status |
|---|---|---|---|---|---|
| Game Server Primary | amp01 | 113 | `02:aa:bb:cc:05:01` | 10.101.0.81 | 🔄 Planned |
| Game Server Secondary | amp02 | 114 | `02:aa:bb:cc:05:02` | 10.101.0.82 | 🔄 Planned |

### Database Tier (PostgreSQL - Authentik Backend)
| Container | Hostname | VMID | MAC Address | IP Address | Status |
|---|---|---|---|---|---|
| Database Primary | pgsql01 | 115 | `02:aa:bb:cc:07:01` | 10.101.0.71 | 🔄 Planned |
| Database Secondary | pgsql02 | 116 | `02:aa:bb:cc:07:02` | 10.101.0.72 | 🔄 Planned |
=======
| Docker Primary | docker01 | 109 | `02:aa:bb:cc:10:01` | 10.101.0.51 | 🔄 Planned |
| Docker Secondary | docker02 | 110 | `02:aa:bb:cc:10:02` | 10.101.0.52 | 🔄 Planned |
| Media Server | plex01 | 111 | `02:aa:bb:cc:06:01` | 10.101.0.61 | 🔄 Planned |

### Database Tier (NEW)
| Container | Hostname | VMID | MAC Address | IP Address | Status |
|---|---|---|---|---|---|
| Database Primary | sql01 | 112 | `02:aa:bb:cc:07:01` | 10.101.0.71 | 📋 Planned |
| Database Standby | sql02 | 113 | `02:aa:bb:cc:07:02` | 10.101.0.72 | 📋 Planned |
| Database VIP (Keepalived) | - | - | - | 10.101.0.70 | 📋 Planned |
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072

## Usage in Terraform

To assign a MAC address to a container deployment in `terraform/[container]/terraform.tfvars`:

```hcl
mac_address = "02:aa:bb:cc:01:01"
```

The LXC module uses this value directly. If `mac_address` is empty, Proxmox auto-generates a new MAC on each deployment (not recommended for consistency).

## DNS and DHCP Integration

**Fixed MAC + Fixed IP = Stable Records**

Once assigned:
1. UniFi Dream Machine recognizes the same device despite redeployments
2. DHCP reservations remain consistent
3. DNS records don't require updates
4. Network monitoring/logging shows continuous history

**Without fixed MAC:**
- Each redeployment creates a new DHCP entry
- UniFi shows multiple records for same IP (confusing)
- Historical logs are fragmented across different MAC entries

## Adding New Services

When deploying a new service tier:

1. **Assign a service type** from the Service Type Reference (next available XX)
2. **Document in the table above**
3. **Add MAC to terraform.tfvars**: `mac_address = "02:aa:bb:cc:XX:01"`
4. **Add to inventory** in `ansible/inventory/hosts.yml` with the same IP/MAC

Example for DNS01 deployment:
```hcl
# terraform/dns01/terraform.tfvars
mac_address = "02:aa:bb:cc:02:01"  # DNS service, instance 1
```

## Common Issues & Solutions

| Issue | Cause | Solution |
|---|---|---|
| MAC changes on each deployment | No MAC specified (defaults to empty) | Add `mac_address = "02:aa:bb:cc:XX:YY"` to tfvars |
| Duplicate IP entries in UniFi | Multiple MACs with same IP | Set `mac_address` to fixed value before redeploy |
| MAC conflicts | Two services assigned same MAC | Check table above, pick unique XX:YY |
| UniFi still shows old entry | Cache issue | Reboot UniFi controller or manually remove old entries |

## Future Expansion

If you expand beyond 255 instances of a service:
- Expand the scheme to `02:AA:BB:DD:XX:YY` (using the fourth octet for additional service grouping)
- Or switch to `02:AA:BB:CC:DD:YY` (allowing 256 service types)

For now, the single-octet scheme (`02:aa:bb:cc:XX:YY`) supports up to 255 instances per service type, which exceeds typical homelab/small production needs.

## References

- [IEEE 802 MAC Address Format](https://en.wikipedia.org/wiki/MAC_address)
- [Locally Administered Addresses](https://en.wikipedia.org/wiki/MAC_address#Ranges_of_group_and_locally_administered_addresses)
- [Proxmox LXC Container MAC Configuration](https://pve.proxmox.com/wiki/LXC)
