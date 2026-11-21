# Guests (L5): design

Purpose: how PhoenixStack guests are placed on the network, created (Terraform) and configured (Ansible).
This is **L5a**: the groundwork every service builds on. The first service on it is DNS (L5b, Pi-hole).
The host (L0–L4) is in [../proxmox/README.md](../proxmox/README.md) and stays on `pve-bootstrap.sh`.

Status: **design, 2026-11-20.** Applied so far: mgmt back to `/24`, UniFi zones, the Terraform token narrowed to
its pools and VLANs 100/200, the Debian 13 container template and VM template `10001`. The topology diagram is [topology.html](topology.html)
(published: <https://claude.ai/artifact/Uc6MzcxWspFZyG8dAN5qsA>, private).

## Scope

- In: the zones and their firewall rules, guest templates, IDs and addresses, Terraform and Ansible layout,
  secrets, the API token's privileges, the per-guest firewall, guest patching, and test guests that prove it all.
- Out: the three -TEMP guests (AMP-TEMP 100, docker-temp 999, PLEX-TEMP 9999). They stay as they are, on
  the mgmt network, untouched by Terraform, until their services move to new guests.
- Out: any service. L5a ends with two throwaway test guests, created and destroyed.

## Architecture

What the lab will run (2026-11-20, not exhaustive): DNS (Pi-hole), Authentik (SSO, MFA, SAML), Plex and/or
Jellyfin, media management, game servers (AMP), local AI agents, and the databases they need.

### Zones

| Zone | VLAN | Subnet | Holds | Reached from |
| --- | --- | --- | --- | --- |
| **Management** | 10 (native) | `10.101.0.0/24` | pve01 `.11`, NAS `.101`, iDRAC `.1`, UDM `.254`; the -TEMP guests for now | Admin sources only |
| **Services** | 100 | `10.101.1.0/24` | Pi-hole, Authentik, databases, the internal Traefik and Docker host, media management, AI | LAN and VPN clients, on published ports |
| **DMZ** | 200 | `10.101.2.0/24` | The public Traefik and Docker host, Plex/Jellyfin, game servers | The internet, through three port forwards only |

Why a DMZ: game servers and media servers are reachable from the internet, game servers directly and often with
third-party mods. On one shared VLAN, a compromised game server would reach DNS, Authentik and the databases
without passing any firewall the UDM controls. With its own zone, everything it can reach is a rule on the UDM.

### How requests flow

- **From the internet**, three port forwards, all into the DMZ: `443` → the public Traefik, `32400` → Plex,
  game ports → AMP. Nothing else is forwarded.
- **Two Traefik instances.** Public (on `docker02`, DMZ): only routes meant for the internet. Internal (on
  `docker01`, Services): everything for LAN and VPN users. A mistake in the public one can expose only what the
  DMZ holds.
- **Authentik lives in Services.** The public Traefik asks it to log people in (forward-auth) through one allowed
  port; its server and database stay off the DMZ.
- **LAN and VPN clients** use Pi-hole (`53`) and the internal Traefik (`443`) in Services.
- **Media files** stay on the NAS (mgmt): read-write for media management (`docker01`), read-only for the media
  server (`plex01`). Mounted inside those VMs, not bind-mounted from the host.

### Guest types

| Kind | Used for | Why |
| --- | --- | --- |
| **Unprivileged LXC** | Simple services that install natively: Pi-hole, PostgreSQL, MariaDB | Light, back up in seconds, no dependency on a Docker host. |
| **Docker host VM**, one per zone | Most applications, as compose stacks in git deployed by Ansible: `docker01` (Services), `docker02` (DMZ) | Most of these apps ship as Docker images; this is how docker-temp works today. Proxmox recommends VMs for Docker, and docker-temp's mount and permission trouble came from Docker inside a container. |
| **Dedicated VM** | A GPU, its own kernel, or isolation: `plex01` (P2000), `ai01` (RTX 3070), `amp01`, `authentik01` | A GPU passes through to one VM; the containers inside that VM share it. |

GPU sharing (2026-11-20): each GPU belongs to one VM and is shared by the containers in it (NVIDIA container
toolkit). Sharing one GPU across several guests would need the NVIDIA driver on pve01 (reverses the host design:
every kernel update rebuilds the driver, containers must match its version) or vGPU (needs licences and
supported data-centre cards; neither the P2000 nor the 3070 qualifies).

### Identity and break-glass

- Authentik is the login for applications, not for infrastructure. **Proxmox, UniFi, the iDRAC, the NAS and
  1Password never depend on Authentik**; each keeps its own local admin login.
- Break-glass MFA is a YubiKey. Register two keys everywhere and keep the spare apart from the first.

### Databases

- `pgsql01` (PostgreSQL) for Authentik first, then the apps that use PostgreSQL. `mariadb01` when an app needs
  MySQL/MariaDB. Apps that ship their own special database (Immich) keep it.
- Nightly database dumps on top of the guest backups: a snapshot of a running database is only crash-consistent.

## Decisions

| Area | Decision | Why |
| --- | --- | --- |
| Network | Three zones (see [Zones](#zones)). Every new guest is in Services or the DMZ; none on mgmt. Decided 2026-11-20. | The host has no address in Services or the DMZ, so a guest can only reach its admin ports through the UDM, where they're blocked. |
| Addressing | The original scheme (see [Address scheme](#address-scheme)): MAC `02:aa:bb:cc:XX:YY`, VMID `1XXYY`, a fixed last octet per guest. Terraform sets the MAC and a static IP. UDM DHCP on VLANs 100 and 200 limited to `.150–.199`; `.254` gateway. | Kept from the archived design (`archive/legacy/docs/roadmap/MAC_ADDRESS_SCHEME.md`), reconciled 2026-11-20. A DNS server's address is handed out to every client, so it can't move. |
| UDM firewall | One zone per VLAN, default block between zones, then the allows in [UDM rules](#udm-rules). | UniFi allows traffic between internal networks by default. These rules are the real boundary; the PVE guest firewall is a second layer. Set by hand in the UniFi UI and recorded here. |
| Guest firewall (PVE) | Every Terraform guest has its firewall on (`firewall=1` on the NIC), `policy_in: DROP`, and only the rules its service needs, defined in Terraform next to the guest. | Defense in depth: also covers traffic between guests in the same zone, which the UDM never sees. |
| Guest type | See [Guest types](#guest-types). | |
| Templates | **Container:** Debian 13 standard, downloaded by the bootstrap's `templates` stage (done). **VM:** `debian13-cloud`, VMID `10001`, built by the same stage (bootstrap 2026.11.7) from Debian's `genericcloud` image, checked against Debian's published SHA512 sums. Disk on `ssd`, in pool **`templates`**, where Terraform may only read and clone (`PVETemplateUser`). NIC tagged VLAN 100. A cloud-init vendor snippet (`local:snippets/phoenix-vendor.yaml`, written by the bootstrap) installs the QEMU guest agent at first boot. Terraform full-clones, so the template can be rebuilt (`qm destroy 10001`, re-run the stage) without touching guests. | Downloading needs `Sys.Modify`, which the Terraform token doesn't have. Cloud-init sets the user, SSH key and static IP at first boot through the API. A separate pool keeps Terraform from changing or deleting the template. The VLAN tag means a fresh clone never sits untagged on mgmt. |
| Storage | Root disks on `ssd` for light guests, on `nvme` for I/O-heavy ones and Docker hosts. AI models wait for the `data` pool. | `ssd` holds 231 GB; Docker images and media metadata grow. |
| Names | `<role><nn>`, e.g. `dns01`; FQDN `<name>.int.phoenixstack.net`. | Short and predictable. The domain is the one the host uses. |
| Start order | `onboot: 1`; DNS first (`startup order=1`), databases second, then everything else. | After a patch reboot, other guests find DNS and their databases already up. |
| Backups | Nothing to add: both nightly jobs back up all guests. NAS shares are mounted inside guests, so they aren't in the backups. Database dumps: see [Databases](#databases). | Already covered by L4. |

### Address scheme

From the archived design, kept as it was where its sources agree. Where they disagreed, the scheme document
(`MAC_ADDRESS_SCHEME.md` and `INFRASTRUCTURE_DESIGN.md`) wins over the archived Terraform files.

- **MAC:** `02:aa:bb:cc:XX:YY`. `02` = locally administered unicast; `XX` = tier code; `YY` = instance.
- **VMID:** `1XXYY`, same code and instance.
- **IP:** `10.101.<zone>.<octet>`, where the third octet is the zone (1 = Services, 2 = DMZ). The last octet is
  unique across both zones, so `.52` is always `docker02`.
- **Name:** `<role><YY>`, e.g. `dns01`.

| Code | Tier | VMIDs | Zone | Last octet | Notes |
| --- | --- | --- | --- | --- | --- |
| 00 | Templates | 100YY | — | — | New. `10001` = Debian 13 cloud-init VM template. |
| 01 | Bastion / Ansible | 101YY | Services | `.21`, `.22` | Archive also had `.20`/`.21` (Terraform); the scheme document's `.21`/`.22` kept. |
| 02 | DNS (Pi-hole) | 102YY | Services | `.201`, `.202` | `dns02` later, off pve01. |
| 03 | Proxy | 103YY | — | `.31`, `.32` | Reserved. Traefik runs as a container on each zone's Docker host. |
| 04 | Authentik | 104YY | Services | `.41`, `.42` | |
| 05 | Game server (AMP) | 105YY | DMZ | `.81`, `.82` | Archived Terraform used code 11. |
| 06 | Media (Plex / Jellyfin) | 106YY | DMZ | `.61`, `.62` | `plex01` gets the P2000. |
| 07 | Database | 107YY | Services | `.71`–`.79` | pgsql01/02 `.71`/`.72`, mariadb01 `.73`. |
| 08 | Monitor | 108YY | Services | `.91`, `.92` | Archived Terraform used code 09. |
| 09 | Vault | 109YY | Services | `.111`, `.112` | **Moved:** the archive gave Vault `.81` (AMP's) or `.101` (the NAS's on mgmt). Archived Terraform used code 05. |
| 10 | Docker host | 110YY | 01 Services, 02 DMZ | `.51`, `.52` | |
| 11 | Backup | 111YY | Services | `.121` | Archived Terraform used code 08; no IP in the archive. |
| 12 | AI | 112YY | Services | `.131` | New, proposed. `ai01` gets the RTX 3070 (not fitted yet). |
| 99 | Test (throwaway) | 199YY | both | `.248`, `.249` | New. `test01` = LXC in Services (`10.101.1.249`); `test02` = VM in the DMZ (`10.101.2.248`). |

Free for new tiers: `.100`–`.149` (except those above) and `.203`–`.247`. DHCP: `.150`–`.199`.
Infrastructure on mgmt (`10.101.0.0/24`) keeps its original addresses: iDRAC `.1`, pve01 `.11`, NAS `.101`,
gateway `.254`. The -TEMP guests keep their IDs and DHCP addresses until they are rebuilt.

### UDM rules

Default: block between zones. Then allow only these (each by port, to the named guest where it says so).
"Admin sources" are the admin workstations `10.1.1.69` (Young) and `10.2.1.69` (Porter) and Teleport VPN clients `192.168.2.0/24` (the same list as pve01's `ADMIN_SOURCES`).

| From | To | Allow |
| --- | --- | --- |
| Internet | DMZ | Port forwards only: `443` → `docker02`, `32400` → `plex01`, game ports → `amp01` |
| LAN and VPN clients | Services | `53` → `dns01`; `443` → `docker01` |
| LAN and VPN clients | DMZ | The same ports as the internet (so public names also work at home) |
| Admin sources | Services, DMZ | SSH (`22`) and each guest's admin page |
| Admin sources | Management | As today (pve01's own firewall also limits to admin sources) |
| Services, DMZ | Internet | Allowed (updates, Plex, game server lists) |
| DMZ `docker02` | Services | Authentik's port on `authentik01` (forward-auth); each published app's port on `docker01` |
| DMZ `plex01` | Management | NAS file sharing (`445` or NFS) to `10.101.0.101`, read-only share access |
| Services `docker01` | Management | NAS file sharing to `10.101.0.101` |
| Services | DMZ | Nothing (add monitoring later, by port) |
| Services, DMZ | Management, client LANs | Nothing else |

### Terraform

| Area | Decision | Why |
| --- | --- | --- |
| Provider | `bpg/proxmox`, exact version pinned in `required_providers`; Terraform version pinned in `required_version`. | Maintained, covers LXC, VMs and firewall rules. The archive used `telmate/proxmox`. |
| Connection | `https://pve01.int.phoenixstack.net:8006/` with normal certificate checking. No SSH from Terraform. | The GUI has a Let's Encrypt certificate. Without SSH, the provider is limited to the API token's privileges. |
| Credentials | Token `terraform@pve!automation`, read from 1Password at run time: `op run --env-file=… -- terraform plan`. | No secrets on disk or in git. |
| Inventory | One file, `guests/inventory.yml`, lists each guest (kind, VMID, MAC, zone, IP, cores, memory, disk, storage, ports). Terraform reads it with `yamldecode()`; Ansible uses it as its inventory. | One source of truth. Adding a guest is one entry. |
| Layout | `guests/terraform/`: one root module, two small modules (`lxc`, `vm`), `for_each` over the inventory. | Small enough to read in one sitting. No modules per tier. |
| State | Local state, git-ignored, saved to 1Password (document item) by the wrapper after each `apply` (decided 2026-11-20). | State can hold sensitive values and is the only record of what Terraform owns. A lost state is recoverable here (`terraform import` of a few guests), so a simple backup is enough. |
| Workflow | `plan`, review, `apply`, by hand from an admin workstation. No CI. | The archive's CI applied on every push to main. |
| Hand-made exceptions | Bind mounts and LXC feature flags other than `nesting` need `root@pam`, which no token has. Guests that need them get those lines by hand, recorded in this file, and Terraform ignores them (`lifecycle.ignore_changes`). | Keeps root out of automation. The design avoids bind mounts (NAS shares are mounted inside VMs). |

### Token (`terraform@pve`)

Before 2026-11-20: role `PhoenixTerraform` on `/`, including `Sys.Modify`, `Sys.Console`, `VM.Console` and `Pool.Allocate`.
That's enough to change the host and open a console to any guest, the -TEMP guests included.

Now (bootstrap 2026.11.6, **applied 2026-11-20**):

- A resource pool **`terraform`**. Terraform creates every guest in it.
- Role `PhoenixTerraform` narrowed to guest privileges: `Pool.Allocate, Pool.Audit, VM.Allocate, VM.Audit,
  VM.Clone, VM.Config.CDROM, VM.Config.CPU, VM.Config.Cloudinit, VM.Config.Disk, VM.Config.HWType,
  VM.Config.Memory, VM.Config.Network, VM.Config.Options, VM.GuestAgent.Audit, VM.PowerMgmt`, granted only on
  the pool. `Pool.Allocate` stays because putting a new guest in a pool requires it on that pool.
- Dropped: `Sys.Modify`, `Sys.Console`, `Sys.Audit` on `/`, `VM.Console`, `VM.Migrate` (one host),
  `Datastore.*` on `/`, `Mapping.*`.
- Grants (instead of one on `/`), the same for the user and its token:

  | Path | Role | Why |
  | --- | --- | --- |
  | `/pool/terraform` | `PhoenixTerraform` | Create and manage guests, only inside the pool. The -TEMP guests aren't in it. |
  | `/pool/templates` | `PVETemplateUser` (built-in) | Read and clone the VM templates; can't change or delete them. (bootstrap 2026.11.7) |
  | `/storage/ssd`, `/storage/nvme` | `PVEDatastoreUser` (built-in) | Allocate root disks. |
  | `/storage/local` | `PVEAuditor` (built-in, read-only) | Read the template. |
  | `/sdn/zones/localnetwork/vmbr0/100`, `/vmbr0/200` | `PVESDNUser` (built-in) | Attach NICs to `vmbr0` on VLAN 100 (Services) or 200 (DMZ) only. Without a grant on `vmbr0` itself, Terraform can't create an untagged NIC, so it can't put a guest on mgmt. (bootstrap 2026.11.7; was all of `vmbr0`) |
  | `/nodes/pve01` | `PVEAuditor` (built-in, read-only) | Read node status. |

- Later: `Mapping.Use` on `/mapping/pci/GPU01` only, when `plex01` is built (and the same for the 3070's mapping).
- The `access` stage sets each service account's grants **exactly**: it adds the configured ones and removes
  any others. `verify` checks that each token's grants match the config.
- The privilege list is a starting point. The test guests prove it: create, change, firewall rules, destroy.
  Anything missing is added with the reason written here.

### Ansible

| Area | Decision | Why |
| --- | --- | --- |
| Layout | `guests/ansible/`: `ansible.cfg`, playbooks per service, roles `base`, `docker_host` and one per service. Compose stacks live in git, one folder per stack. Inventory: `../inventory.yml`. | Same inventory as Terraform. Docker hosts are rebuilt from git, not hand-edited like docker-temp. |
| Control node | An admin workstation (Young LAN, Porter LAN or VPN). | Those are the networks the UDM lets reach guests' SSH. |
| First login | Terraform puts Aaron's SSH public key in the guest (container root, or the cloud-init user on VMs). The first `base` run creates user `aaron` (sudo, key only) and sets `PermitRootLogin no`. Later runs connect as `aaron`. | Named admin account; root only during the first run. |
| Host keys | Checking stays on, with `StrictHostKeyChecking=accept-new`. A rebuilt guest's old key is removed by hand. | The archive turned host key checking off. |
| Secrets | 1Password, read at deploy time: the lookup plugin (`community.general.onepassword`) or `op run`, with a 1Password service account limited to one vault. **No Ansible Vault files.** | The archive committed Vault files to a public repo. |
| `base` role | Timezone, locale, NTP (`systemd-timesyncd`), journald size cap, sshd hardening, admin user, unattended security updates (see Patching), QEMU guest agent on VMs. | The same baseline on every guest. |
| Runs | Always `--check --diff` first, then the real run. | Repo guardrail. |

### Guest patching

Decided 2026-11-20: Debian **security** updates install themselves daily (`unattended-upgrades`, security
origin only, no automatic reboot), and everything else goes through a `patch.yml` playbook in the host's weekly
window. Docker images are updated in the same window, by pulling pinned versions changed in git.

Why: the reason the host patches by hand (one kernel or QEMU update takes every guest down) doesn't apply to a
guest. A bad update breaks one guest, and the nightly backups restore it.

### Name resolution until L5b

Until Pi-hole exists, each guest's name is added by hand to the UDM's local DNS, as `pve01` was. Guests use
their zone's gateway (`.254`) as their resolver. L5b moves the records into git (Pi-hole, managed by Ansible),
and the UDM's manual records are then removed so there is only one copy.

## Implementation steps

Each step is dry-run first. Steps that change shared infrastructure wait for approval.

1. ~~**Mgmt back to `/24`**~~ Done 2026-11-20.
2. ~~**Bootstrap 2026.11.6:** pool `terraform`, narrowed token, Debian 13 container template~~ Done 2026-11-20.
3. ~~**UniFi:** Services (VLAN 100) and DMZ (VLAN 200) networks and zones, and the starting rules~~ Done 2026-11-20,
   with a Management and an IOT zone as well (see [topology.html](topology.html) and REBUILD_STATE item 9).
4. ~~**Bootstrap 2026.11.7:** pool `templates`, the token's network grant narrowed to VLANs 100 and 200, the VM
   template (`10001`)~~ Done 2026-11-20; checked through the read-only API (template, pool, token grants).
5. ~~**Check for old `1XXYY` archives** on `nas-dump`~~ Done 2026-11-20: none, the IDs are clear.
6. ~~**Repo:** `guests/inventory.yml`, `guests/terraform/` (`lxc` and `vm` modules), `guests/ansible/` with the `base`
   role~~ Written 2026-11-20 (`terraform validate`, `ansible-playbook --syntax-check`). See [Running it](#running-it).
7. **Test guests** `test01` (LXC, Services) and `test02` (VM, DMZ): plan, apply, run `base`, check, then destroy.

## Running it

From an admin workstation (Young or Porter workstation, or Teleport), with `OP_ACCOUNT` set for the PhoenixStack
1Password account and `pve01.int.phoenixstack.net` resolving to `10.101.0.11`:

```bash
# Terraform: the wrapper reads the API token from 1Password and saves the state there after changes
guests/tf.sh plan
guests/tf.sh apply

# Ansible: first run on a NEW container connects as root (VMs already have the admin user)
cd guests/ansible
ansible-galaxy collection install -r requirements.yml      # once
ansible-playbook site.yml -l test01 -e ansible_user=root --check --diff
ansible-playbook site.yml -l test01 -e ansible_user=root
ansible-playbook site.yml -l test02 --check --diff
ansible-playbook site.yml -l test02
```

| Piece | Where | Notes |
| --- | --- | --- |
| Guest list | [inventory.yml](inventory.yml) | Read by both tools. `admin_sources` must match pve01's `ADMIN_SOURCES` and the UDM's Management rules. |
| Terraform | [terraform/](terraform/) | Provider `bpg/proxmox` pinned to `0.120.0` (released 2026-11-02); lock file committed. Each guest gets its MAC, VMID, VLAN and static IP, and a Proxmox firewall: inbound DROP, SSH and ping from admin sources, plus the guest's `firewall_in` rules. |
| Wrapper | [tf.sh](tf.sh) | Token from 1Password item `(Proxmox) - Terraform Token` (by item ID; update `TOKEN_REF` if the item moves). State saved to `infrastructure` / `PhoenixStack guests terraform.tfstate` after apply, destroy, import and state commands. |
| Ansible | [ansible/](ansible/) | `base` role: admin user `aaron` (key only, sudo without a password), root SSH login off, time zone, time sync on VMs, journal cap 200 MB, automatic Debian security updates without reboots, QEMU guest agent on VMs. |

## Done when (test guests)

- [ ] `terraform apply` creates both in pool `terraform`; a second `plan` shows no changes.
- [ ] The token can't change the -TEMP guests or the host (an API call to each fails with 403).
- [ ] `base` runs clean on both; a second run reports no changes. Root SSH login is refused.
- [ ] From each: `10.101.0.11` ports 22, 8006, 8007, the iDRAC and the NAS admin page don't answer;
      `apt update` works.
- [ ] From `test02` (DMZ): nothing in Services answers except the ports the rules allow.
- [ ] From an admin LAN and the VPN: SSH to both works. From either: SSH to an admin workstation fails.
- [ ] Each one's firewall drops a port that isn't allowed (seen in `/var/log/pve-firewall.log`).
- [ ] `terraform destroy` removes both cleanly; the UDM DNS records are removed.

## Open decisions

1. Cloudflare in front of the public web apps (proxy or tunnel), or DNS only?
2. Plex, Jellyfin, or both?
3. Which docker-temp apps are public (to `docker02`) and which internal (to `docker01`)?
4. AI tier code (proposed 12, `.131`).
5. A second Pi-hole off pve01, so DNS survives a host reboot. Who uses Pi-hole first, and whether it blocks ads.
6. Monitoring (uptime and service alerts): which zone and when.
7. Hardware, not blocking: the 990 Pro drives and ASUS card (`data` pool) and the RTX 3070 aren't installed.

Settled 2026-11-20: Terraform state (local, with a 1Password copy), guest patching (automatic security updates,
the rest weekly), mgmt back to `/24`, three zones (mgmt VLAN 10, Services VLAN 100, DMZ VLAN 200), the archived
address scheme with the tier codes reconciled, guest types (LXC for native services, a Docker host VM per zone,
GPU VMs), two Traefik instances, Authentik in Services, YubiKey break-glass.
