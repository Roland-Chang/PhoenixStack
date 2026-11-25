# APT Mirrors Configuration

**Purpose**: Document the APT mirror configuration strategy for PhoenixStack infrastructure to optimize package download speeds and ensure consistency across all deployed systems.

## Mirror Provider

**Primary Mirror**: [XMission](https://mirrors.xmission.com/)

Mirror URLs by distribution:
- **Ubuntu**: https://mirrors.xmission.com/ubuntu/
- **Debian**: https://mirrors.xmission.com/debian/
- **Linux Mint**: https://mirrors.xmission.com/linuxmint/

## Scope

### Included in Mirror Configuration
- **Ubuntu LXC Containers**: ANSIBLE01, DNS01, PROXY01, AUTHENTIK01, etc.
- **Debian-based Workloads**: Future Linux workloads using Debian as base OS

### Excluded from Mirror Configuration
- **Proxmox VE (PVE01)**: Uses default Proxmox repositories and official Debian repos. Mirror configuration is NOT applied to Proxmox hosts.

**Reason for Exclusion**: Proxmox has specific repository requirements and compatibility needs that differ from standard Debian/Ubuntu. Using third-party mirrors on Proxmox hosts can cause package conflicts or infrastructure instability.

## Implementation

### Ansible Role: base_config

The `ansible/roles/base_config/tasks/main.yml` contains a task that automatically configures APT mirrors for all deployed Ubuntu/Debian containers.

**Task Details**:
- Detects OS distribution (Ubuntu vs Debian)
- Updates `/etc/apt/sources.list` with XMission mirror URLs
- Includes all repository components:
  - `main` (core packages)
  - `restricted` / `contrib` (restricted binaries)
  - `universe` / `non-free` (community/non-free packages)
  - `multiverse` / `non-free-firmware` (third-party/firmware)
- Includes security and backports repositories

**Execution**: Runs automatically when the `ansible01_base.yml` playbook is applied to any new container.

### Example Sources Configuration

#### Ubuntu (24.04 LTS example)
```
deb https://mirrors.xmission.com/ubuntu/ noble main restricted universe multiverse
deb https://mirrors.xmission.com/ubuntu/ noble-updates main restricted universe multiverse
deb https://mirrors.xmission.com/ubuntu/ noble-security main restricted universe multiverse
deb https://mirrors.xmission.com/ubuntu/ noble-backports main restricted universe multiverse
```

#### Debian (Bookworm example)
```
deb https://mirrors.xmission.com/debian/ bookworm main contrib non-free non-free-firmware
deb https://mirrors.xmission.com/debian/ bookworm-updates main contrib non-free non-free-firmware
deb https://mirrors.xmission.com/debian/ bookworm-security main contrib non-free non-free-firmware
deb https://mirrors.xmission.com/debian/ bookworm-backports main contrib non-free non-free-firmware
```

## Manual Configuration (If Needed)

If you need to manually configure mirrors on a container or system:

```bash
# For Ubuntu
sudo tee /etc/apt/sources.list > /dev/null <<EOF
deb https://mirrors.xmission.com/ubuntu/ $(lsb_release -cs) main restricted universe multiverse
deb https://mirrors.xmission.com/ubuntu/ $(lsb_release -cs)-updates main restricted universe multiverse
deb https://mirrors.xmission.com/ubuntu/ $(lsb_release -cs)-security main restricted universe multiverse
deb https://mirrors.xmission.com/ubuntu/ $(lsb_release -cs)-backports main restricted universe multiverse
EOF

sudo apt update
```

```bash
# For Debian
sudo tee /etc/apt/sources.list > /dev/null <<EOF
deb https://mirrors.xmission.com/debian/ $(lsb_release -cs) main contrib non-free non-free-firmware
deb https://mirrors.xmission.com/debian/ $(lsb_release -cs)-updates main contrib non-free non-free-firmware
deb https://mirrors.xmission.com/debian/ $(lsb_release -cs)-security main contrib non-free non-free-firmware
deb https://mirrors.xmission.com/debian/ $(lsb_release -cs)-backports main contrib non-free non-free-firmware
EOF

sudo apt update
```

## Future Mirror Expansion

For future Linux distributions not yet deployed:

| Distribution | Mirror URL | Support Status |
|---|---|---|
| Ubuntu | https://mirrors.xmission.com/ubuntu/ | ✅ Active |
| Debian | https://mirrors.xmission.com/debian/ | ✅ Active |
| Linux Mint | https://mirrors.xmission.com/linuxmint/ | ✅ Active |
| AlmaLinux | https://mirrors.xmission.com/almalinux/ | 🔄 Future |
| CentOS | https://mirrors.xmission.com/centos/ | 🔄 Future |
| Fedora | https://mirrors.xmission.com/fedora/ | 🔄 Future |
| Rocky Linux | https://mirrors.xmission.com/rockylinux/ | 🔄 Future |
| Alpine | https://mirrors.xmission.com/alpine/ | 🔄 Future |

When adding support for new distributions, update the Ansible role task to detect and configure the appropriate mirror URL.

## Performance Benefits

- **Faster package downloads**: XMission mirrors are geographically optimized (west coast USA focus)
- **Reduced latency**: Local mirror caching improves deployment speed
- **Consistency**: All containers use identical mirror sources, reducing deployment drift
- **Resilience**: Multiple repository components ensure package availability

## Troubleshooting

If `apt update` fails with mirror configuration:

1. **Verify mirror availability**: `curl -I https://mirrors.xmission.com/ubuntu/` (for Ubuntu)
2. **Check network connectivity**: Ensure container has internet access to mirrors.xmission.com
3. **Fallback to defaults**: Edit `/etc/apt/sources.list` to revert to default Ubuntu/Debian repositories
4. **Revert in Ansible**: Comment out the mirror configuration task temporarily, then re-run the playbook

## References

- [XMission Mirror Project](https://mirrors.xmission.com/)
- [Ansible Role: base_config](../ansible/roles/base_config/)
- [Ubuntu Mirror Archive](https://wiki.ubuntu.com/Mirrors)
- [Debian Mirror List](https://www.debian.org/mirror/list)
