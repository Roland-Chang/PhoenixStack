# Guests (L5): design

Purpose: how PhoenixStack guests are placed on the network, created (Terraform) and configured (Ansible), and
the services built on them, one layer at a time (L5a groundwork, then L5b onwards). The host (L0–L4) is in
[../proxmox/README.md](../proxmox/README.md) and stays on `pve-bootstrap.sh`.

Status (2026-11-24): **L5a–L5e applied and checked**: DNS (`dns01`, `dns02`), PostgreSQL (`pgsql01`), the Docker host
and Services Traefik (`docker01`), Authentik (`authentik01`). **L5f under way**: `docker02` takes the internet's
`443` and runs Audiobookshelf, with logins through Authentik; the other public apps follow one at a time.
[Household DNS](#household-dns) goes through the UDM to Pi-hole. The topology diagram is [topology.html](topology.html) (published:
<https://claude.ai/artifact/Uc6MzcxWspFZyG8dAN5qsA>, private).

## Scope

- In: the zones and their firewall rules, guest templates, IDs and addresses, Terraform and Ansible layout,
  secrets, the API token's privileges, the per-guest firewall, guest patching, the test guests that proved it, and
  each service's section (L5b onwards).
- Out: the -TEMP guests (docker-temp 999, PLEX-TEMP 9999; AMP-TEMP 100 deleted 2026-11-23, backups kept). They stay as they are, on
  the mgmt network, untouched by Terraform, until their services move to new guests.

## Architecture

What the lab will run (2026-11-20, not exhaustive): DNS (Pi-hole), Authentik (SSO, MFA, SAML), Plex and/or
Jellyfin, media management, game servers (AMP), local AI agents, and the databases they need.

### Zones

| Zone | VLAN | Subnet | Holds | Reached from |
| --- | --- | --- | --- | --- |
| **Management** | 10 (native) | `10.101.0.0/24` | pve01 `.11`, NAS `.101`, iDRAC `.1`, UDM `.254`; the -TEMP guests for now | Admin sources only |
| **Services** | 100 | `10.101.1.0/24` | Pi-hole, Authentik, databases, the Services Traefik and Docker host, media management, AI | LAN and VPN clients, on published ports |
| **DMZ** | 200 | `10.101.2.0/24` | The public Traefik and Docker host, Plex/Jellyfin, game servers | The internet, through three port forwards only |

Why a DMZ: game servers and media servers are reachable from the internet, game servers directly and often with
third-party mods. On one shared VLAN, a compromised game server would reach DNS, Authentik and the databases
without passing any firewall the UDM controls. With its own zone, everything it can reach is a rule on the UDM.

### How requests flow

- **From the internet**, three port forwards, all into the DMZ: `443` → the public Traefik, `32400` → Plex,
  game ports → AMP. Nothing else is forwarded.
- **Two Traefik instances.** Public (on `docker02`, DMZ): only routes meant for the internet. Services (on
  `docker01`): everything for LAN and VPN users. A mistake in the public one can expose only what the
  DMZ holds. (Not "internal": in the UniFi rules, Internal is the zone of the client LANs.)
- **Names follow who reaches the app, not where it runs:**
  - **Public: `<app>.phoenixstack.net`** (e.g. `abs.phoenixstack.net`), for general users from anywhere. Served by
    the public Traefik, in public DNS (Cloudflare). The app runs on `docker02` too (decided 2026-11-23,
    [Moving the public apps](#moving-the-public-apps)). Public names also work at home, so a public
    app gets only this name, not a second `int.` one.
  - **LAN and VPN only: `<name>.int.phoenixstack.net`**, for guests and apps that never face the internet. Served
    by the Services Traefik; the real addresses are only in Pi-hole. `int.` doesn't mean admin-only: who may
    reach a guest or an admin page is set by the [UDM rules](#udm-rules), not by the name.
- **Authentik lives in Services.** People log in on its public name, which the public Traefik passes to it through
  one allowed port: apps with their own login send them there (OIDC), the others ask it first (forward-auth). Its
  server and database stay off the DMZ.
- **LAN and VPN clients** use the Services Traefik (`443` on `docker01`), and get names from the UDM, which forwards
  `int.phoenixstack.net` to Pi-hole ([Household DNS](#household-dns)). Admin machines ask Pi-hole directly.
- **Media files** stay on the NAS (mgmt): read-write for media management (`docker01`), read-only for the media
  server (`plex01`) and the public apps (`docker02`), plus a writable share of its own for a public app that
  downloads (`Podcasts`). Mounted inside those VMs, not bind-mounted from the host.

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

#### Database dumps

The standard for every database guest (decided 2026-11-22). PostgreSQL first (role `postgresql`); MariaDB gets the
same when it arrives.

| | Standard | Why |
| --- | --- | --- |
| When | Nightly at **06:30 UTC** (was 00:30 local until the guests moved to UTC, 2026-11-24): 23:30 Denver in winter, 00:30 in summer. systemd timer `db-dump.timer` (`Persistent=true`: a run missed while the guest was off happens at boot). | Before `nightly-pbs` (08:00 UTC) and `nightly-nas` (10:30 UTC), so both carry that night's dumps. |
| What | Each database separately (PostgreSQL: `pg_dump --format=custom`), plus the roles (`pg_dumpall --globals-only`). | One database or one table can be restored alone; without the roles a restore has no owners. |
| Check | Each dump is read back (`pg_restore --list`). The day's folder appears only when every dump succeeded. | A bad night never leaves a half set that looks complete. |
| Where | `/var/backups/db-dump/<YYYY-MM-DD>/` on the guest, owner `postgres`, mode `0700`. Script `/usr/local/sbin/db-dump`. | No NAS mount in the guest (Services can't reach mgmt); the guest backups copy the folder off. |
| Keep | 7 day folders on the guest. | Older dumps live on in the guest backups: PBS keeps 14 daily, 8 weekly and 6 monthly, the NAS 7 nightly. |
| Watch | A good run writes `last-ok`. The weekly `patch.yml` fails if it's older than 26 hours. | Real alerts come with monitoring (open decision 6). |
| Restore test | At setup, and after every major version upgrade. | A dump nobody has restored is a hope. |

Restore one database: `sudo -u postgres pg_restore --create --dbname=postgres /var/backups/db-dump/<day>/<db>.dump`
(drop the old one first, or restore under a new name).

## Decisions

| Area | Decision | Why |
| --- | --- | --- |
| Network | Three zones (see [Zones](#zones)). Every new guest is in Services or the DMZ; none on mgmt. Decided 2026-11-20. | The host has no address in Services or the DMZ, so a guest can only reach its admin ports through the UDM, where they're blocked. |
| Addressing | The original scheme (see [Address scheme](#address-scheme)): MAC `02:aa:bb:cc:XX:YY`, VMID `1XXYY`, a fixed last octet per guest. Terraform sets the MAC and a static IP. UDM DHCP on VLANs 100 and 200 limited to `.150–.199`; `.254` gateway. | Kept from the archived design (`archive/legacy/docs/roadmap/MAC_ADDRESS_SCHEME.md`), reconciled 2026-11-20. Pi-hole's addresses are set on the UDM and on admin machines, so they shouldn't move. |
| UDM firewall | One zone per VLAN, default block between zones, then the allows in [UDM rules](#udm-rules). | UniFi allows traffic between internal networks by default. These rules are the real boundary; the PVE guest firewall is a second layer. Set by hand in the UniFi UI and recorded here. |
| Guest firewall (PVE) | Every Terraform guest has its firewall on (`firewall=1` on the NIC), `policy_in: DROP`, only the rules its service needs (in Terraform next to the guest; a source may name another guest), and an **IP filter**: each guest may only send from its own address, IP and ARP (`ipfilter` with an `ipfilter-net0` list holding that address; since 2026-11-22). One shared module: [terraform/modules/firewall](terraform/modules/firewall/main.tf). | Defense in depth: also covers traffic between guests in the same zone, which the UDM never sees. Rules between guests trust the source address, which the IP filter makes trustworthy: before it, a connection from an address `docker01` doesn't own reached `dns01`; afterwards it's dropped (tested 2026-11-22). |
| Guest type | See [Guest types](#guest-types). | |
| Templates | **Container:** Debian 13 standard, downloaded by the bootstrap's `templates` stage (done). **VM:** `debian13-cloud`, VMID `10001`, built by the same stage (bootstrap 2026.11.7) from Debian's `genericcloud` image, checked against Debian's published SHA512 sums. Disk on `ssd`, in pool **`templates`**, where Terraform may only read and clone (`PVETemplateUser`). NIC tagged VLAN 100. A cloud-init vendor snippet (`local:snippets/phoenix-vendor.yaml`, written by the bootstrap) installs the QEMU guest agent at first boot. Terraform full-clones, so the template can be rebuilt (`qm destroy 10001`, re-run the stage) without touching guests. | Downloading needs `Sys.Modify`, which the Terraform token doesn't have. Cloud-init sets the user, SSH key and static IP at first boot through the API. A separate pool keeps Terraform from changing or deleting the template. The VLAN tag means a fresh clone never sits untagged on mgmt. |
| Storage | Root disks on `ssd` for light guests, on `nvme` for I/O-heavy ones and Docker hosts. AI models wait for the `data` pool. | `ssd` holds 231 GB; Docker images and media metadata grow. |
| Names | `<role><nn>`, e.g. `dns01`; FQDN `<name>.int.phoenixstack.net`. | Short and predictable. The domain is the one the host uses. |
| Start order | `onboot: 1`; DNS first (`startup order=1`), databases second, then everything else. | After a patch reboot, other guests find DNS and their databases already up. |
| Backups | Nothing to add: both nightly jobs back up all guests. NAS shares are mounted inside guests, so they aren't in the backups. Database dumps: see [Databases](#databases). | Already covered by L4. |

### Address scheme

From the archived design (`02:aa:bb:cc:XX:YY` MACs, `1XXYY` VMIDs, the tier codes), with one change: **realigned
2026-11-22** so the last octet spells the same code and instance as the MAC and VMID. The archive's octets followed
no rule (code 01 had `.21`, code 05 `.81`, code 09 `.111`).

- **MAC:** `02:aa:bb:cc:XX:YY`. `02` = locally administered unicast; `XX` = tier code; `YY` = instance.
- **VMID:** `1XXYY`, same code and instance.
- **IP:** `10.101.<zone>.<octet>`, where the third octet is the zone (1 = Services, 2 = DMZ) and the last octet is
  **code × 10 + instance**: `pgsql01` is MAC `…:07:01`, VMID `10701`, `10.101.1.71`. The last octet is unique
  across both zones, so `.102` is always `docker02`.
- **Name:** `<role><YY>`, e.g. `dns01`.
- **Limits:** instances `01`–`09` per tier. Codes `01`–`14` fit below DHCP (`.150`–`.199`); a code from 15 on would
  need the DHCP range moved first. Test (`99`) is the one exception.
- **Lookalikes:** the zone octet tells them apart, but note that `10.101.1.11` (`bastion01`) isn't pve01
  (`10.101.0.11`), and `10.101.1.101` (`docker01`) isn't the NAS (`10.101.0.101`).

| Code | Tier | VMIDs | Zone | Last octet | Notes |
| --- | --- | --- | --- | --- | --- |
| 00 | Templates | 100YY | — | — | New. `10001` = Debian 13 cloud-init VM template. |
| 01 | Bastion / Ansible | 101YY | Services | `.11`, `.12` | |
| 02 | DNS (Pi-hole) | 102YY | Services | `.21`, `.22` | `dns01`, `dns02`, both on pve01 (were `.201`/`.202` until 2026-11-22). Off-host DNS: a Pi-hole on the Porter network, later. |
| 03 | Proxy | 103YY | — | `.31`, `.32` | Reserved. Traefik runs as a container on each zone's Docker host. |
| 04 | Authentik | 104YY | Services | `.41`, `.42` | |
| 05 | Game server (AMP) | 105YY | DMZ | `.51`, `.52` | |
| 06 | Media (Plex / Jellyfin) | 106YY | DMZ | `.61`, `.62` | `plex01` gets the P2000. |
| 07 | Database | 107YY | Services | `.71`–`.79` | `pgsql01`/`pgsql02` `.71`/`.72`, `mariadb01` `.73`. |
| 08 | Monitor | 108YY | Services | `.81`, `.82` | |
| 09 | Vault | 109YY | Services | `.91`, `.92` | |
| 10 | Docker host | 110YY | 01 Services, 02 DMZ | `.101`, `.102` | |
| 11 | Backup | 111YY | Services | `.111` | |
| 12 | AI | 112YY | Services | `.121` | New, proposed. `ai01` gets the RTX 3070 (not fitted yet). |
| 99 | Test (throwaway) | 199YY | both | `.248`, `.249` | The exception to the rule. `test01` = LXC in Services (`10.101.1.249`); `test02` = VM in the DMZ (`10.101.2.248`). |

The archived Terraform files used other codes for some tiers (AMP 11, Monitor 09, Vault 05, Backup 08); the scheme
document's codes were kept.

Free for new tiers: codes `13` and `14` (`.131`–`.149`). Above DHCP, `.200`–`.247` are unused. DHCP: `.150`–`.199`.
Infrastructure on mgmt (`10.101.0.0/24`) keeps its original addresses: iDRAC `.1`, pve01 `.11`, NAS `.101`,
gateway `.254`. The -TEMP guests keep their IDs and DHCP addresses until they are rebuilt.

### UDM rules

Default: block between zones. Then allow only these (each by port, to the named guest where it says so).
"Admin sources" are the Young admin workstation and laptop (`10.1.1.69`, `10.1.1.169`), the Porter admin workstation and laptop (`10.2.1.69`, `10.2.1.169`), and Teleport VPN clients `192.168.2.0/24` (the same list as pve01's `ADMIN_SOURCES`).
**One exception:** `10.2.1.175`, a temporary production system at the Porter site, is in the UDM's Porter Admin
rules (into Management, Services and DMZ) but isn't an admin source, and pve01 still drops it. Replace it with a
NAS-only rule when that system retires (REBUILD_STATE item 9).

| From | To | Allow (design) | Today (UniFi export 2026-11-23, plus the changes since) |
| --- | --- | --- | --- |
| Internet | DMZ | Port forwards only: `443` → `docker02`, `32400` → `plex01`, game ports → `amp01` | `443` → `docker02` since 2026-11-24 (Cloudflare only, port `443` only). `32400` still goes to PLEX-TEMP on mgmt (REBUILD_STATE item 7). No game-port forward in the export (AMP-TEMP deleted 2026-11-23); to confirm in UniFi |
| LAN and VPN clients | Services | `443` → `docker01`. DNS goes through the UDM ([Household DNS](#household-dns)), so no `53` | Not yet: with the first app for household users |
| LAN and VPN clients | DMZ | Nothing (decided 2026-11-23): public names resolve to Cloudflare, so home users come in through the proxy like everyone else, and `docker02` accepts only Cloudflare. **Except Plex:** `32400` to `plex01` (2026-11-26), as PLEX-TEMP has today (Plex clients at home connect directly, not through Cloudflare) | As designed (`Internal -> DMZ (Block)`, `VPN -> DMZ (Block)`). Plex: `Internal -> plex01 (Plex)` and `VPN -> plex01 (Plex)`, TCP `32400` to `10.101.2.61`, each ordered **above** its zone's block rule (checked in the export 2026-11-26); live once Plex runs there |
| Admin sources | Services, DMZ | SSH (`22`) and each guest's admin page | **All ports** (`Young/Porter/VPN Admin -> Services/DMZ`); narrow to the design once the services settle |
| Admin sources | Management | As today (pve01's own firewall also limits to admin sources) | All ports |
| Services, Management, IOT | The UDM itself (Gateway) | DNS (`53`), DHCP (`67`), ping | As designed. The block rules after them match `New` and `Invalid` connections only (since 2026-11-22), so replies to queries the UDM sends itself (its forwarding to Pi-hole) get back |
| Services, DMZ | Internet | Allowed (updates, Plex, game server lists) | Allowed |
| DMZ `docker02` | Services | Authentik's port on `authentik01` (its login pages, forward-auth) | `9443` to `authentik01` (`docker02 -> authentik01`, 2026-11-23) |
| DMZ `docker02` | Management | NAS file sharing (`445`) to `10.101.0.101`, as its own NAS user: read-only on `Media`, read-write on an app's own share (`Podcasts`) ([Moving the public apps](#moving-the-public-apps)) | `docker02 -> NAS (SMB)` (2026-11-23); only `445` answers (checked) |
| DMZ `docker02` | docker-temp (Management) | **None since 2026-11-26.** The temporary rule `docker02 -> Docker-Temp (temporary)` (2026-11-24) carried the public apps' ports while they moved one by one (Step B) | Rule deleted by the Young admin 2026-11-26 after Immich moved; checked from `docker02`: `2283`, `83`, `8081`, `9925` and `22` on docker-temp time out (dropped), the NAS's `445` still answers |
| DMZ `plex01` | Management | NAS file sharing (`445` or NFS) to `10.101.0.101`, read-only share access | `plex01 -> NAS (SMB)` (2026-11-26): TCP `445` to `10.101.0.101`, IPv4; its NAS user reads `Media` only. Checked live from `plex01`: `445` open, pve01's GUI and PostgreSQL closed |
| Services `docker01` | Management | NAS file sharing to `10.101.0.101` | Not yet |
| Services | DMZ | Nothing (add monitoring later, by port) | Nothing |
| Services, DMZ | Management, client LANs | Nothing else | Nothing |

The -TEMP guests' rules (the Young LAN and the site VPNs to the NAS's SMB and to PLEX-TEMP's Plex, the Young LAN to
docker-temp) go when those guests do.

### Terraform

| Area | Decision | Why |
| --- | --- | --- |
| Provider | `bpg/proxmox`, exact version pinned in `required_providers`; Terraform version pinned in `required_version`. | Maintained, covers LXC, VMs and firewall rules. The archive used `telmate/proxmox`. |
| Connection | `https://pve01.int.phoenixstack.net:8006/` with normal certificate checking. No SSH from Terraform. | The GUI has a Let's Encrypt certificate. Without SSH, the provider is limited to the API token's privileges. |
| Credentials | Token `terraform@pve!automation`, read from 1Password by the wrapper [tf.sh](tf.sh) (`op read`) and passed to Terraform in its environment, for that run only. | No secrets on disk or in git. |
| Inventory | One file, `guests/inventory.yml`, lists each guest (kind, VMID, MAC, zone, IP, cores, memory, disk, storage, ports). Terraform reads it with `yamldecode()`; Ansible uses it as its inventory. | One source of truth. Adding a guest is one entry. |
| Layout | `guests/terraform/`: one root module, two small modules (`lxc`, `vm`), `for_each` over the inventory. | Small enough to read in one sitting. No modules per tier. |
| State | The copy of record is a 1Password document; the local file (git-ignored, owner-only) is a working copy. The wrapper checks it against 1Password's before every command, fetches it when it's missing or older (2026-11-22), and saves it back after every command that can change it. | State can hold sensitive values and is the only record of what Terraform owns. Fetching first means a second workstation never plans from an empty state. A lost state is recoverable here (`terraform import` of a few guests). |
| Workflow | `plan`, review, `apply`, by hand from an admin workstation. No CI. | The archive's CI applied on every push to main. |
| Tags | None. Proxmox checks tag changes against `/vms/<vmid>` only, not the pool, so the pool-scoped token can't set them while creating a guest (found by the first test apply, 2026-11-20). Pool `terraform` marks Terraform's guests; the VLAN shows the zone. | Keeps the token pool-scoped instead of granting it rights on every guest. |
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
  | `/storage/local` | `PVEDatastoreUser` (built-in) | Use the container template and the cloud-init vendor snippet. A VM that references a snippet needs `Datastore.AllocateSpace` here (found by the first test apply, 2026-11-20; was `PVEAuditor`). `local` holds no guest disks, and this role can't upload. |
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
| SSH agent | Keys in the 1Password agent (`~/.ssh/config`: `IdentityAgent` for `10.101.*`), which asks before it signs. [ansible.cfg](ansible/ansible.cfg): `timeout = 60`, and each guest's connection reused for 15 minutes (`ControlPersist`), so one approval per guest covers a session. | With several guests at once, the default 10 s ran out before the approval and the run reported them unreachable ("Timeout waiting for privilege escalation prompt"; the guest's log: "Connection closed by authenticating user ... [preauth]"), 2026-11-22. |
| First login | Terraform puts the Young admin's SSH public key in the guest (container root, or the cloud-init user on VMs). The first `base` run creates user `aaron` (sudo, key only) and sets `PermitRootLogin no`. Later runs connect as `aaron`. | Named admin account; root only during the first run. |
| Host keys | Checking stays on, with `StrictHostKeyChecking=accept-new`. A rebuilt guest's old key is removed by hand. | The archive turned host key checking off. |
| Secrets | 1Password, read on the admin machine with `op read` (Ansible's `pipe` lookup), only when a guest needs a secret it doesn't have yet: a new resolver's web password, a new database role, Traefik's Cloudflare token, Authentik's `.env`. Dry runs never read secrets. **No Ansible Vault files.** | The archive committed Vault files to a public repo. |
| `base` role | A first full upgrade (new guests only), admin user `aaron` (key only, sudo without a password), root SSH login off, time zone (**UTC**, the inventory's `timezone`; see below), journal cap 200 MB, automatic Debian security updates without reboots (see [Guest patching](#guest-patching)); on VMs also the QEMU guest agent, time sync (`systemd-timesyncd`), no LLMNR or mDNS (systemd-resolved; names come from Pi-hole only), and SSH host keys kept through cloud-init changes (`ssh_deletekeys: false`, set after the first boot made the VM's own keys). | The same baseline on every guest. |
| Runs | Always `--check --diff` first, then the real run. | Repo guardrail. |

### Guest patching

Decided 2026-11-20: Debian **security** updates install themselves daily (`unattended-upgrades`, security
origin only, no automatic reboot), and everything else goes through a `patch.yml` playbook in the host's weekly
window. Docker images are updated in the same window, by pulling pinned versions changed in git.

Why: the reason the host patches by hand (one kernel or QEMU update takes every guest down) doesn't apply to a
guest. A bad update breaks one guest, and the nightly backups restore it.

How (2026-11-21):

- **New guests:** the `base` role's first run does an `apt full-upgrade` before anything else is installed, then
  leaves a marker (`/etc/phoenix/initial-upgrade`) so it never runs again. The templates' packages can be weeks old.
- **Weekly:** `apb patch.yml --check --diff`, then `apb patch.yml`, after the host's patching. One guest at a time:
  `apt full-upgrade`, a reboot only when Debian asks for one (`/var/run/reboot-required`), then `pihole -up` on the
  DNS guests. `pihole -up` (v6.6) exits 1 even after a successful update, so the playbook checks the result with
  `pihole -up --check-only` instead. The `base` role and the service playbooks never upgrade anything themselves, so a
  repeat run stays `changed=0`.

### Guests' DNS servers

Services guests ask `dns01` and `dns02` (`dns_servers` in the inventory's `services` group, decided 2026-11-22);
the two resolvers themselves ask the UDM, so neither depends on the other at boot. Both accept port 53 from the
Services VLAN. Groups without `dns_servers` (the DMZ, for now) use their gateway (`.254`).

Until 2026-11-22 every guest used its gateway. That worked while the UDM held local records; once they were removed
(Pi-hole has the only copy), internal names went to public DNS, where the zone's wildcard record answers with
Cloudflare's addresses. Found when Authentik couldn't reach `postgres.int.phoenixstack.net` (L5e).

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
7. ~~**Test guests** `test01` (LXC, Services) and `test02` (VM, DMZ)~~ Applied, checked and destroyed 2026-11-21
   (see below). L5a is done.

## Running it

From an admin workstation or laptop (Young or Porter, or over Teleport), with `OP_ACCOUNT` set for the PhoenixStack
1Password account (the `phx` shortcut; `tf` and `apb` below are shortcuts too, see the admin-workstation notes in [../proxmox/README.md](../proxmox/README.md)) and `pve01.int.phoenixstack.net` resolving to `10.101.0.11`:

```bash
# Terraform: the wrapper reads the API token from 1Password and keeps the state in step with 1Password's copy
tf plan        # guests/tf.sh, from any directory
tf apply

# Ansible (apb = ansible-playbook in guests/ansible). Baseline first: a NEW container's first run connects as root
ansible-galaxy collection install -r guests/ansible/requirements.yml   # once
apb site.yml -l dns01 -e ansible_user=root --check --diff
apb site.yml -l dns01 -e ansible_user=root
# Then the service's own playbook, as the admin user (here: DNS, see L5b). A secret it needs on a first run
# is read from 1Password by the playbook itself.
apb dns.yml -l dns01 --check --diff
apb dns.yml -l dns01
```

| Piece | Where | Notes |
| --- | --- | --- |
| Guest list | [inventory.yml](inventory.yml) | Read by both tools. `admin_sources` must match pve01's `ADMIN_SOURCES` and the UDM's Management rules. |
| Terraform | [terraform/](terraform/) | Provider `bpg/proxmox` pinned to `0.120.0` (released 2026-11-02); lock file committed. Each guest gets its MAC, VMID, VLAN, static IP and DNS servers, and a Proxmox firewall (inbound DROP, SSH and ping from admin sources, the guest's `firewall_in` rules, the IP filter). **Cloud-init changes** (DNS servers, address): a container restarts during the `apply` (the provider has no option against it); a VM doesn't (`reboot_after_update = false`, since 2026-11-22): the apply warns or fails instead, and the VM is rebooted by hand (`ansible <guest> -m reboot`). VMs keep their SSH host keys through such a change (`base` role). After a new module: `tf init` once. |
| Wrapper | [tf.sh](tf.sh) | Token from 1Password item `(Proxmox) - Terraform Token` (by item ID; update `TOKEN_REF` if the item moves). State: `infrastructure` / `(Terraform) - Guests State` is the copy of record; fetched when the local copy is missing or older, saved after apply, destroy, import and state commands (see [Terraform](#terraform)). |
| Ansible | [ansible/](ansible/) | `site.yml` runs the `base` role (see [Ansible](#ansible)) on every guest; each service has its own playbook (`dns.yml`, `database.yml`, `docker.yml`, `authentik.yml`), run after it as the admin user, because `base` turns root's SSH login off. `patch.yml` is the weekly patch run (see [Guest patching](#guest-patching)); it also checks the database dumps. |

### New guest checklist

Every new guest, in this order (each Terraform and Ansible step dry-run first):

1. **Inventory:** one host entry in [inventory.yml](inventory.yml), addressed by the [scheme](#address-scheme)
   (MAC `02:aa:bb:cc:XX:YY`, VMID `1XXYY`, octet = code × 10 + instance).
2. **Terraform:** `tf plan` (only the new guest and its firewall), then `apply`.
3. **Baseline:** `apb site.yml -l <guest> -e ansible_user=root` (containers' first run only; VMs connect as the admin user).
   If the first full upgrade leaves `/var/run/reboot-required`, reboot the guest now (`ansible <guest> -m reboot`).
4. **Service:** the guest's own playbook (`dns.yml`, `database.yml`, `docker.yml`, `authentik.yml`, ...).
   An app behind an Authentik login: `authentik: true` on its route, then `authentik.yml` before `docker.yml`
   (see [Apps behind Authentik](#apps-behind-authentik)).
5. **DNS name:** `apb dns.yml -l dns01`, then `-l dns02`. Pi-hole learns names only from the inventory, so a guest
   (or a Docker host's new route) has no name until this runs. One resolver at a time, since clients use them.
6. **UniFi alias** (by hand, decided 2026-11-22): in UniFi Network, open the client with the guest's MAC, set its
   name to the guest's name (`pgsql01`) and its note to the inventory `description`. Guests have static addresses,
   so UniFi never learns their names from DHCP and lists them by MAC only. The alias is a label; DNS doesn't use it.
   Not scripted: that would need a UniFi account with write access (which can also change firewall rules) for a
   label on a handful of clients.
7. **Docs:** the guest's section in this file, the [topology](topology.html) page, and
   [REBUILD_STATE](../proxmox/REBUILD_STATE.md).

When a guest is destroyed: remove its inventory entry (Terraform destroys it on the next `apply`), re-run step 5,
and remove its UniFi client entry ("Forget").

## Done when (test guests)

Run 2026-11-21 on `test01` (LXC, Services, `10.101.1.249`) and `test02` (VM, DMZ, `10.101.2.248`):

- [x] `terraform apply` creates both in pool `terraform`; a second `plan` shows no changes.
- [x] The token can't change the -TEMP guests or the host: it holds no permissions on `/vms/100`, `/vms/999`,
      `/vms/9999` or `/`, and reading their configs, the host's log or its updates returns 403.
- [x] `base` runs clean on both; a second run reports `changed=0`. Root SSH login is refused.
- [x] From each: `10.101.0.11` ports 22, 8006, 8007, the iDRAC, the NAS (443, 22) and the UDM's admin page don't
      answer; `apt update` and DNS work.
- [x] From `test02` (DMZ) and `test01` (Services): the other zone's guest doesn't answer.
- [x] From an admin workstation (the laptop, home LAN): SSH to both works. From either: SSH to the admin
      workstation and laptop fails.
- [x] Each one's firewall drops a port that isn't allowed, logged as `policy DROP` in `/var/log/pve-firewall.log`.
- [x] `terraform destroy` removes both cleanly; nothing else on pve01 changes. 2026-11-21: state is empty; pve01 lists
      only the template `10001` and the three -TEMP guests, as before.

What the first run found, and fixed:

| Found | Fix |
| --- | --- |
| Proxmox checks tags against `/vms/<vmid>` only, so a pool-scoped token can't set them when creating a guest | No tags (see Terraform decisions) |
| A VM referencing the vendor snippet needs `Datastore.AllocateSpace` on `local` | `PVEDatastoreUser` on `/storage/local` |
| The UDM had no admin rules into Services; Internal and VPN reached the whole DMZ | `Young/Porter/VPN Admin -> Services/DMZ` rules, then `Internal -> DMZ (Block)` and `VPN -> DMZ (Block)` |
| The UDM's IPS blocked repeated SSH from the home LAN | IPS Detection Exclusions for the Young admin workstation and laptop; the Porter ones added 2026-11-23, the Teleport range 2026-11-26 (REBUILD_STATE item 11) |
| `/etc/systemd/journald.conf.d` doesn't exist on Debian 13 | The `base` role creates it |
| The Debian container template has systemd hold port 22 (`ssh.socket`), so reloading sshd stops it | The `base` role restarts sshd there and reloads it elsewhere |
| A dry run on a new container can't check the admin user's keys (the user isn't created yet) | Skipped in that one case |

## L5b: DNS (`dns01`, `dns02`)

**Applied 2026-11-21** and checked from the admin laptop (results below). Used by the admin machines, the Services
guests and, through the UDM, household devices ([Household DNS](#household-dns)).

| Area | Decision | Why |
| --- | --- | --- |
| Guests | `dns01`: unprivileged LXC `10201`, MAC `02:aa:bb:cc:02:01`, `10.101.1.21`. `dns02` (added 2026-11-21): LXC `10202`, MAC `02:aa:bb:cc:02:02`, `10.101.1.22`. (Both were `.201`/`.202` until the re-address of 2026-11-22.) Both in Services, 1 core, 512 MiB, 8 GB on `ssd`, start order 1, configured identically by the same roles. | Address scheme tier 02. Pi-hole and Unbound install natively. Two resolvers keep DNS up while one is patched (`patch.yml` does one guest at a time). |
| Software | Pi-hole v6 (embedded web server, no lighttpd) and Unbound, on each resolver. | Ansible roles `unbound` and `pihole`, playbook `dns.yml`. |
| Upstream | **Recursive Unbound** (decided 2026-11-21): Unbound on `127.0.0.1:5335` resolves recursively from the root servers and checks DNSSEC. It is Pi-hole's only upstream. | No third-party resolver sees every lookup, and the UDM stays out of Pi-hole's own lookups. Fallback if the ISP interferes with outbound port 53: forward Unbound to Quad9 over DoT, a config change only. |
| Blocking | **Off** (decided 2026-11-21): no blocklists installed, `dns.blocking.active = false`. | Local names first; turn blocking on later as its own step. |
| Local names | `dns.hosts` from the inventory: every guest plus `dns_records` (`pve01`, `idrac-pve01` for its iDRAC, `postgres`). `int.phoenixstack.net` is answered only here (`local=/int.phoenixstack.net/`), so an unknown name gets NXDOMAIN instead of the public wildcard record. | One source of truth. Adding a guest to the inventory adds its name. |
| Listening | `dns.listeningMode = SINGLE` on `eth0`: answers any source network, on that interface only. | Pi-hole's default (`LOCAL`) ignores clients outside `10.101.1.0/24`. The Proxmox firewall and the UDM decide who gets in. |
| Firewall (PVE) | `53/udp` and `53/tcp` from `lan_sources` and from the Services VLAN (the guests, and the UDM forwarding household lookups from `.254`); `443/tcp` (web interface) and SSH from admin sources. | The UDM decides which clients reach Services; household devices don't need to, since the UDM asks for them. |
| Web interface | `https://dns01.int.phoenixstack.net/admin` and `https://dns02.int.phoenixstack.net/admin`, port 443 only, each with Pi-hole's self-signed certificate for its name. Password from 1Password item `(Pi-hole) - DNS Admin` (vault `infrastructure`, item ID `6rgmkyk7enemcundji75k7omeu`; one password for both resolvers), read by the playbook on a resolver's first run only. | An unattended install sets no password, and without one the web interface is open. |
| Install | The installer is pinned to a Pi-hole release tag (`v6.6`) and checked by SHA-256 before it runs. It installs the current release, and FTL is checked against Pi-hole's own checksum. Updates are `pihole -up` in the weekly window. | Pi-hole has no Debian package. |
| Rollout | Admin machines first (2026-11-21, by hand), then the Services guests (2026-11-22, `dns_servers`), then household devices through the UDM (2026-11-22, [Household DNS](#household-dns)). | |
| Redundancy | **Accepted risk** (2026-11-21, the Young admin): both resolvers are on pve01, so a pve01 reboot or failure takes DNS down. Off-host DNS will be a Pi-hole on the Porter network, later. | Covers guest maintenance now; host outages wait for the Porter instance. |
| Own resolver | `dns01` itself resolves through its gateway (`.254`), not through Pi-hole. | It still has working DNS for updates if Pi-hole is down. |

Steps (the [new guest checklist](#new-guest-checklist), each one dry-run first); specific to DNS:

1. 1Password: item `(Pi-hole) - DNS Admin` in `infrastructure` (generated, 16+ characters). The playbook reads it on a
   resolver's first run.
2. One resolver at a time: `tf plan` and `apply`, `apb site.yml -l dns01 -e ansible_user=root`, `apb dns.yml -l dns01`;
   then the same for `dns02`, and `dns.yml` once more on `dns01` so each knows the other's name.
3. Admin machines: DNS `10.101.1.21` and `10.101.1.22` on the home network's profile only (away from home they're out
   of reach). Done 2026-11-21 on the Young admin's laptop (NetworkManager profile `Auto YOUNG`: `ipv4.dns`,
   `ipv4.ignore-auto-dns yes`, `ipv6.ignore-auto-dns yes`, search domain `int.phoenixstack.net`); the Young admin
   workstation is still to do.
4. The UDM's manual `pve01` record: removed 2026-11-22 (Pi-hole holds it). Admin machines keep their hosts entry for
   VPN use and host rebuilds (REBUILD_STATE item 1).
5. Household devices: [Household DNS](#household-dns).

Done when (first run 2026-11-21 at the old addresses `.201`/`.202`; the name, NXDOMAIN, public-name, DNSSEC and
web-interface checks were repeated at `.21`/`.22` on 2026-11-22):

- [x] `terraform plan` after the apply shows no changes; `dns.yml` repeat runs: `changed=0`.
- [x] From an admin machine: `dig @10.101.1.21 pve01.int.phoenixstack.net` returns `10.101.0.11`; `dig @10.101.1.21 nothing.int.phoenixstack.net` returns NXDOMAIN.
- [x] `dig @10.101.1.21 example.com` resolves. `dig @10.101.1.21 dnssec-failed.org` returns SERVFAIL (DNSSEC works).
      Answers carry no `ad` flag: Pi-hole clears it unless it validates too (`dns.dnssec`). Left off on purpose (2026-11-21);
      Unbound's SERVFAIL on bad signatures is the protection.
- [x] On `dns01`: `dig @127.0.0.1 -p 5335 . NS` answers (Unbound reaches the root servers, so no ISP interference); `ss -lntup` shows Pi-hole on 53 and 443 only, Unbound on `127.0.0.1:5335`, and nothing on 80 or 123. (Also present, both harmless: the template's Postfix on localhost:25, and Pi-hole on `[::]:53`
      with no IPv6 address on the guest.) Port 80 from the laptop times out (dropped).
- [x] `https://10.101.1.21/admin` asks for the password; browser login works on both. A non-admin LAN address can't reach 53 or 443 (dropped by the UDM).
- [x] After a pve01 reboot: `dns01` and `dns02` start first (checked 2026-11-26, patch reboot: order 1 with PLEX-TEMP, then `pgsql01`, then the rest).

What L5b found, and fixed:

| Found | Fix |
| --- | --- |
| A dry run on a new guest pretends to install packages and users, so service, handler and file-owner steps failed | Those steps skip, or check as root, only in that case |
| Pi-hole moves `adlists.list` into `/etc/pihole/migration_backup/` when it builds its database, so Ansible re-created it | The two pre-seed files are written only before the install |
| Dry runs can't preview Pi-hole's settings (they go through `pihole-FTL --config`), and on a new guest `--check` doesn't refresh the package lists | Compare `dns.hosts` and the other values in `roles/pihole/defaults/main.yml` by eye before a real run that changes them |
| Re-addressing both resolvers in one `apply` (2026-11-22, `.201`/`.202` to `.21`/`.22`) cut the laptop's DNS, and with it 1Password | Move one resolver at a time (`tf apply -target='module.lxc["dns01"]'`), point clients at it, then the other |

## L5c: PostgreSQL (`pgsql01`)

**Applied 2026-11-22** and checked (results below). First application database: `authentik` (L5e); the cluster was re-created as UTF-8 then.

| Area | Decision | Why |
| --- | --- | --- |
| Guest | `pgsql01`: unprivileged LXC `10701`, MAC `02:aa:bb:cc:07:01`, `10.101.1.71`, Services. 2 cores, 2 GiB, 32 GB on **`nvme`**, start order 2. | Address scheme tier 07. Databases are I/O-heavy (see Storage). Starts after DNS, before the apps. |
| Version | **PostgreSQL 17 from Debian 13** (decided 2026-11-22), not the PGDG repository. | Debian's stable major; Authentik needs 14 or later. Security fixes come from Debian's security archive with the daily automatic updates; the PostgreSQL project supports 17 until 2029-11. |
| Cluster | **UTF-8 with PostgreSQL's builtin `C.UTF-8` locale** (`createcluster.d/phoenix.conf`, written before the package installs; re-created 2026-11-22, see L5e). The role stops if a cluster isn't UTF8. | Debian creates the cluster at install with the guest's locale, which is `C` in a container: `SQL_ASCII`. The builtin locale sorts the same on every glibc version, so upgrades never invalidate indexes. |
| Settings | `conf.d/phoenix.conf`: listens on `localhost` and `10.101.1.71`; SCRAM passwords; TLS on (Debian's snakeoil certificate), TLS 1.2 or newer; `shared_buffers` ¼ and `effective_cache_size` ¾ of the guest's memory; connections logged. | Debian's `postgresql.conf` stays untouched, so package updates don't conflict. |
| Access | `pg_hba.conf`: the `postgres` superuser only locally as the `postgres` OS user (`sudo -u postgres psql`); local SCRAM on `127.0.0.1`. Network clients get one `hostssl … scram-sha-256` line per application database, from that client's address. | Least privilege; no remote superuser, no network login without TLS. |
| Firewall (PVE) | SSH and ping from admin sources only, for now. `5432/tcp` opens per client, with its database. | Guest-to-guest traffic in VLAN 100 never passes the UDM, so this firewall is the boundary between guests. No UDM change. |
| Databases | From the inventory's `pg_databases` on the host: `[{name, client, password}]`. Each is a UTF8 database owned by a login role of the same name, reachable over TLS from its client's `/32` only (`hostssl` line; `5432` from that address in `firewall_in`), with `CONNECT` revoked from `PUBLIC`. The role's password is read from 1Password (`op read` on the admin machine) only when the role is created; a dry run doesn't read it. First: `authentik` (L5e). | One database per app, so one app's credentials reach nothing else. |
| Dumps | The [database dump standard](#database-dumps). | |
| Ansible | Role `postgresql`, playbook `database.yml` (hosts `pgsql*`; MariaDB later as its own play). `patch.yml` checks the dumps weekly. Minor PostgreSQL updates come with `apt full-upgrade` and restart the server briefly. | Named like `dns.yml`: playbook by function, role by software. |
| `pgsql02` (`.72`) | Not now (decided 2026-11-22). | A replica on the same host only covers a broken guest, which the dumps and guest backups already cover; it adds patching, lag monitoring, and WAL that piles up while the replica is down. Revisit with a second physical host: then streaming replication (`pg_basebackup -R` with a replication slot capped by `max_slot_wal_keep_size`, TLS and SCRAM) and manual failover (`pg_promote()`). |
| Service name | Applications connect to **`postgres.int.phoenixstack.net`**, not to `pgsql01` (decided 2026-11-22). In `dns_records` since L5e. | A move or a failover is then one DNS change, not a change in every app. |

Steps (each one dry-run first):

1. `tf plan`: expect only `pgsql01` and its firewall to be created. Then `apply`.
2. `apb site.yml -l pgsql01 -e ansible_user=root` (`--check --diff`, then for real).
3. `apb database.yml -l pgsql01` (`--check --diff`, then for real). The real run makes the first dump.
4. `apb dns.yml -l dns01`, then `-l dns02`: Pi-hole learns the new guest's name from the inventory. Every new guest
   needs this step (missed at first on 2026-11-22). One resolver at a time, since clients use them.

Done when:

- [x] `terraform plan` after the apply shows no changes (state copy in 1Password matches); `site.yml` and `database.yml` repeat runs: `changed=0`; root SSH refused.
- [x] `select version()`: PostgreSQL 17.12 (Debian 17.12-0+deb13u1). 5432 on `127.0.0.1`, `[::1]` (both `localhost`) and `10.101.1.71` only. `ssl = on`, TLS 1.2 minimum, SCRAM, `shared_buffers` 512 MB, `effective_cache_size` 1.5 GB, no `pg_hba` errors.
- [x] `pgsql01.int.phoenixstack.net` resolves to `10.101.1.71` on both resolvers (after step 4).
- [x] Network login from the guest itself is refused, with and without TLS (`no pg_hba.conf entry`; the TLS attempt shows TLS works). From the laptop, 5432 is dropped.
- [x] `db-dump.timer` next run 2026-11-23 00:30. The first dump (at setup) wrote `2026-11-22/globals.sql` and `postgres.dump` and `last-ok`; a second run the same day replaced the folder, with no partial folder left.
- [x] Restore test: scratch database `dumptest` (1,000 rows) dumped, dropped, restored with `pg_restore --create` (1,000 rows back), dropped again, dumps re-run.
- [x] `apb patch.yml --check -l pgsql01` passes the dump check ("Last good dump: 2026-11-22 11:57").
- [x] A dump folder every night (`sudo -u postgres ls /var/backups/db-dump`): one per night since 2026-11-22 (checked 2026-11-24).
- [x] After a pve01 reboot: `pgsql01` starts after the DNS guests (`startup: order=2`), checked 2026-11-26. **Found:** PostgreSQL
      started before ifupdown had set `10.101.1.71`, couldn't bind it and served localhost only, so Authentik had no database
      for about 15 minutes. Fixed in the role: PostgreSQL starts after `networking.service` (a drop-in), and networkd's
      wait-online stays off (it doesn't manage `eth0` in a container and only times out). Reboot-tested twice: listening
      on `10.101.1.71` 12 seconds after boot, no failed units.

## L5d: Docker host and Services Traefik (`docker01`)

**Applied 2026-11-22** and checked (results below). No apps yet; Traefik serves only its dashboard.

| Area | Decision | Why |
| --- | --- | --- |
| Guest | `docker01`: VM `11001`, MAC `02:aa:bb:cc:10:01`, `10.101.1.101`, Services, cloned from `10001`. **8 cores, 32 GiB, 64 GB** on `nvme` (decided 2026-11-22). | Tier 10. Room for the apps moving off docker-temp and the AI agents' helper containers (models run on `ai01`). pve01 has 24 cores / 48 threads and 251 GiB. The disk grows online when needed. |
| Docker | **Docker CE from Docker's apt repository** (decided 2026-11-22), with the Compose plugin. The signing key must match Docker's published fingerprint `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`, checked on every run; it's downloaded only when missing (since 2026-11-23: fetching it again only made dry runs report a change whenever Docker re-published the same key). Updates come with the weekly `patch.yml`. | Debian's `docker.io` lags behind what current images and Compose files expect. |
| Daemon | `live-restore` (containers keep running while the engine updates); `no-new-privileges` for every container (2026-11-22); `local` log driver, 5 × 20 MB per container; container networks only from `172.20.0.0/14`. | Default logs never shrink. Docker's default pools include `192.168.x.0/24`, which would collide with Teleport (`192.168.2.0/24`). |
| Admins | `sudo docker`; nobody is in the `docker` group. | The group is root without a password. |
| Firewall (PVE) | `443/tcp` from LAN sources; SSH and ping from admin sources. | Docker rewrites the firewall inside the VM; the Proxmox firewall on the NIC is outside its reach. Until the LAN-wide UDM rule, only admin sources get into Services anyway. |
| Traefik | Services Traefik `v3.7.19` as the stack `/opt/stacks/traefik` (role `traefik`). Port 443 only, no port-80 redirect. Versions pinned in `roles/traefik/defaults/main.yml`. | |
| Routes | **File provider, no Docker socket** (decided 2026-11-22). Each Docker host lists `routes: [{name, url, admin_only}]` in the inventory: Ansible writes `dynamic/route-<name>.yml` and removes routes that are gone; Pi-hole points `<name>.int.phoenixstack.net` at the host (after `dns.yml`). Apps join the Docker network `proxy`. | Socket access is root on the host. Routes live in git, next to the guest. |
| Certificate | One wildcard, `*.int.phoenixstack.net` (plus the bare name), from Let's Encrypt over Cloudflare DNS-01. The challenge check uses `1.1.1.1` and `9.9.9.9`. Stored in `/opt/stacks/traefik/letsencrypt/acme.json` (root only); Traefik renews it 30 days before expiry. | Certificate transparency logs publish every certificate's names; a wildcard publishes only `*.int`. Pi-hole answers NXDOMAIN for anything under `int.`, so the check must ask public resolvers. |
| Cloudflare token | Its own token (decided 2026-11-22): Zone DNS Edit + Zone Read on `phoenixstack.net`, no IP filter. 1Password `(Cloudflare) - Traefik DNS Token` (item ID `6jwbiosa4zf5wg32uh333srn2m`). Written on the first real run (the playbook reads it with `op read`; dry runs don't need it) to `secrets/cloudflare-token` on the guest (root, `0600`), passed to Traefik as a Compose secret. To rotate: change the item, delete that file, run again. | Revocable without touching PVE's token. No IP filter: the home address may change, and a failed renewal would go unnoticed until monitoring exists. |
| Dashboard | `https://traefik.int.phoenixstack.net`, admin sources only (`admin-only` IP allow-list), and since L5e an Authentik login (`authentik Admins`). | Two checks: the right address and the right person. |
| Smoke test | `whoami` (`traefik/whoami:v1.12.0`) at `https://whoami.int.phoenixstack.net` while its route is in the inventory; removing the route removes the container. | Proves the name, the route and the certificate before a real app relies on them. |
| Not in this step | The NAS mount (with the media apps), `docker02`, and the UDM rule opening `443` to LAN and VPN clients (with the first app for household users). | One step at a time. |

Steps (the [new guest checklist](#new-guest-checklist), each one dry-run first):

1. `tf plan`: expect only `docker01` and its firewall. Then `apply`.
2. `apb site.yml -l docker01` (a VM already has the admin user from cloud-init).
3. `apb docker.yml -l docker01` (the first real run reads the Cloudflare token from 1Password).
4. `apb dns.yml -l dns01`, then `-l dns02` (names `docker01`, `traefik`, `whoami`).
5. UniFi alias; docs.

Done when:

- [x] `terraform plan` after the apply: no changes (state copy in 1Password matches). `site.yml` and `docker.yml` repeat runs: `changed=0` (`docker.yml` without the token). Root SSH refused.
- [x] Docker 29.10.0 from `download.docker.com` (trixie/stable); live-restore on, `local` log driver; network `proxy` is `172.20.0.0/24`.
- [x] Certificate issued at the first start (DNS-01 validated in about 20 s): `int.phoenixstack.net` + `*.int.phoenixstack.net`, Let's Encrypt, valid until 2027-02-20, verifies from the laptop. `whoami` showed `X-Real-Ip: 10.1.1.169`, the laptop's own address.
- [x] Dashboard: `200` from the laptop; `403` from `10.101.1.101` (not an admin source), while `whoami` answered `200` there.
- [x] An unknown name gets `404`.
- [x] From the laptop: 80, 2375, 2376 and 8080 don't answer. IPv6: link-local addresses only (as on `dns01`).
- [x] `whoami` route removed: `docker.yml` removed the container and `route-whoami.yml`, `dns.yml` the name (NXDOMAIN on both resolvers); repeat run `changed=0`.

Found on the way:

| Found | Fix |
| --- | --- |
| `cloud-init status` says "degraded done": Proxmox's generated user-data uses the deprecated `user:` key | Harmless (no errors); nothing to do until Proxmox changes it |
| The first full upgrade installed a new kernel, so Debian asked for a reboot | Rebooted before installing Docker; now a step in the new guest checklist |
| A new guest's first `docker.yml` dry run needs the token too (it stops at the token check) | Since 2026-11-22 the playbook reads the token from 1Password itself, and dry runs don't need it |

## L5e: Identity (`authentik01`)

**Applied 2026-11-22** and checked (results below). Ready for the first login; no applications use it yet.

| Area | Decision | Why |
| --- | --- | --- |
| Guest | `authentik01`: VM `10401`, MAC `02:aa:bb:cc:04:01`, `10.101.1.41`, Services, cloned from `10001`. **2 cores, 4 GiB**, 32 GB on `nvme` (decided 2026-11-22). | Tier 04. Authentik asks for 2 cores and 2 GB with its database on board; ours is on `pgsql01`, and Redis is gone since 2025.10. Uses about 1.2 GB. Memory is reserved on pve01, cores aren't. |
| Software | **Authentik `2026.8.6`** (`ghcr.io/goauthentik/server`), server and worker, as the stack `/opt/stacks/authentik` (role `authentik`, playbook `authentik.yml`, with `docker_host`). Version pinned in `roles/authentik/defaults/main.yml`. | Updates are a change in git after reading the release notes, deployed in the weekly window. |
| Changes from upstream | Our blueprints in `blueprints/` (mounted read-only). No bundled PostgreSQL. **No Docker socket and no root for the worker** (decided 2026-11-22). Only `9443` published (not `9000`). Both containers: `no-new-privileges`, all capabilities dropped. | The socket is root on the VM; it's only for outposts Authentik manages itself, and ours will be deployed from git. |
| Database | `authentik` on `pgsql01` through `postgres.int.phoenixstack.net` (`pg_databases`, L5c), `sslmode=require`. Connections kept open for 5 minutes, each tested before reuse (`CONN_MAX_AGE` 300, `CONN_HEALTH_CHECKS`; since 2026-11-26, review item O3). Measured: new connections from about 15 to 5 a minute (21,600 to 7,500 a day; each kept connection is replaced every 5 minutes), 39 held open of PostgreSQL's 100. | `require`, not `verify-full`: the server has Debian's self-signed snakeoil certificate. |
| Name | **`https://auth.int.phoenixstack.net`** (decided 2026-11-22): route `auth` on `docker01`'s Traefik (wildcard certificate) to `https://10.101.1.41:9443`; also `AUTHENTIK_WEB__BASE_URL`. | Authentik builds its links from the base URL; a future release requires it. |
| Traefik → Authentik | **HTTPS to Authentik's own self-signed certificate, not verified** (decided 2026-11-22): the route's `self_signed: true` adds a `serversTransport` with `insecureSkipVerify`. Firewall: `9443/tcp` from `10.101.1.101/32` only. Only `docker01` may set `X-Forwarded-For` (`AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS`), so Authentik logs real client addresses. | Encrypted on the wire; the firewall, not the certificate, decides who can talk to it. |
| Settings | Avatars as initials; error reporting and startup analytics off. | Nothing leaves the network that doesn't have to. |
| Secrets | `.env` on the guest (root, `0600`), written once from 1Password: `(Authentik) - Secret Key` (`433bhnakbk4j55mkyrtnv3uhce`), `(PostgreSQL) - authentik` (`b7ycchopd2lagrf3jg4samuk5q`), `(Authentik) - akadmin` (`gc5okp343bflwbgpv53o4ypm6i`, the bootstrap password). Later runs keep the file; a dry run doesn't read 1Password. | To rotate: change the item (and, for the database, `ALTER ROLE authentik PASSWORD`), delete `.env`, run again. A new secret key logs everyone out. |
| Admin | **`akadmin`** is break-glass only: both YubiKeys plus TOTP in Microsoft Authenticator on a phone, outside 1Password (decided 2026-11-22). **`aaron`** is the daily admin (group `authentik Admins`): both YubiKeys plus TOTP in 1Password. Devices are named after where they live ("TOTP Authenticator (MS Auth)", "TOTP Authenticator (1Password)"), so a lost phone or a 1Password compromise says which one to remove. | `akadmin` relies on 1Password only for its password; no single lost device locks either account. The YubiKeys are the phishing-resistant factor, which matters once the public Traefik sends internet users to Authentik. |
| Last resort | Both of `akadmin`'s factors lost: on `authentik01`, `sudo docker exec authentik-server-1 ak create_recovery_key 10 akadmin` prints a one-time login link, valid for 10 minutes (the number is minutes). Then enrol new factors. | SSH to the VM doesn't depend on Authentik. |
| MFA | **Required for every account** (decided 2026-11-22): the login flow accepts WebAuthn (YubiKey, passkey) or TOTP, and an account without either must enrol one before it can finish logging in. Set by our blueprint `roles/authentik/templates/blueprints/phoenix-mfa.yaml.j2`, mounted read-only at `/blueprints/custom`; Authentik re-applies it hourly, so a change by hand in the UI is put back. Exception (decided 2026-11-23, open decision 12): users who log in with Google rely on Google's own sign-in security; admins can't log in that way. | The default skipped MFA for accounts without a device. Static codes, Duo, SMS and email aren't offered: SMS and email are the weakest second factors. |
| Admin logins | **Only from the admin sources** (decided 2026-11-26, review item S3): blueprint `phoenix-admin-sources.yaml` puts a deny stage in the default login flow right after the username, before the password. It runs for superusers and `authentik Admins` whose address isn't in the inventory's `admin_sources` (home admin machines, Teleport). Checked through the flow API: `aaron.young` via `auth.int` over Teleport gets the password step; `aaron.young` and `akadmin` via the public name are refused; a non-admin gets the password step both ways. | The admin API answered on the public name (S3); now an admin login needs the LAN or Teleport. Not covered: sessions already open and API tokens. If the policy ever errors, Authentik treats it as false and the login goes on (no lockout). Admins on a phone away from home: Teleport first. |

Steps (the [new guest checklist](#new-guest-checklist), each one dry-run first):

1. 1Password: the three items above (created 2026-11-22).
2. `pg_databases` and `5432` from `.41` on `pgsql01`, `postgres` in `dns_records`: `tf apply`, `apb database.yml -l pgsql01`.
3. `tf plan`: expect only `authentik01` and its firewall. Then `apply`.
4. `apb site.yml -l authentik01`; reboot if the first upgrade asks.
5. `apb authentik.yml -l authentik01` (one 1Password approval; the first start migrates the database, a few minutes).
6. Route `auth` on `docker01`: `apb docker.yml -l docker01`.
7. `apb dns.yml -l dns02`, then `-l dns01` (names `authentik01`, `auth`, `postgres`).
8. UniFi alias; docs.
9. First login as `akadmin` (password from 1Password): two YubiKeys and TOTP in Microsoft Authenticator; then `aaron` (now `aaron.young`) with the YubiKeys and 1Password TOTP.

Done when:

- [x] `terraform plan`: no changes. Repeat runs `changed=0`: `site.yml`, `authentik.yml` (`authentik01`), `docker.yml` (`docker01`), `database.yml` (`pgsql01`). Root SSH refused.
- [x] `pgsql01`: database `authentik` UTF8, owner `authentik`, no `CONNECT` for `PUBLIC`; role password stored as SCRAM. Authentik connects over TLS 1.3 with SCRAM through the `hostssl` line.
- [x] Server and worker `healthy`, as UID 1000 with all capabilities dropped and no Docker socket; no errors after the start; the base-URL warning gone.
- [x] From the laptop: `https://auth.int.phoenixstack.net/` redirects to the login flow (`200`), Let's Encrypt wildcard verifies; `9443` on `authentik01` doesn't answer. Authentik logs the laptop's own address (`10.1.1.169`).
- [x] `auth`, `authentik01` and `postgres` resolve on both resolvers.
- [ ] UniFi alias for `authentik01`.
- [x] MFA required: blueprint `PhoenixStack - MFA required` applied (`successful`); the MFA stage is `configure` with WebAuthn and TOTP only.
- [x] A test account without a device (`mfatest`) was made to enrol one at its first login, offered WebAuthn and TOTP; deleted afterwards (2026-11-22).
- [x] `akadmin`: two YubiKeys and "TOTP Authenticator (MS Auth)"; `aaron` (now `aaron.young`; authentik Admins): two YubiKeys and "TOTP Authenticator (1Password)" (checked in the database 2026-11-22).
- [x] `authentik.dump` in each night's folder on `pgsql01` (4.1 MB, checked 2026-11-24).
- [x] [Restore rehearsal](#restore-rehearsal) passed 2026-11-22 (before the first app depends on Authentik).

Found on the way:

| Found | Fix |
| --- | --- |
| Guests used the UDM for DNS, which has had no local records since that morning: `postgres.int.phoenixstack.net` came back as Cloudflare's public IPv6 addresses (the zone's wildcard), and Authentik hung at its first connection | Services guests use `dns01` and `dns02` (`dns_servers`); both resolvers accept 53 from the Services VLAN. See [Guests' DNS servers](#guests-dns-servers) |
| That `apply` restarted `docker01`, `authentik01` and `pgsql01` (the provider reboots on cloud-init changes), and both VMs got new SSH host keys | Keys compared through pve01's guest agent before accepting. Since 2026-11-22 Terraform doesn't reboot VMs (`reboot_after_update = false`), and VMs keep their host keys (`base` role) |
| `pgsql01`'s cluster was `SQL_ASCII` (Debian created it with the container's `C` locale), and Authentik's first migration failed on it | Cluster dropped and re-created (approved; it held only the half-migrated `authentik`), UTF-8 with the builtin `C.UTF-8` locale. New clusters get it from `createcluster.d`, and the role stops on a non-UTF8 cluster |
| `python3-psycopg2`, needed by the database tasks, in the same install task as PostgreSQL made every later run look like a new guest in a dry run | Its own task; existing roles are read with plain `psql`, so a dry run lists what it would create |

### Apps behind Authentik

A route on a Docker host with `authentik: true` (and a `title`) is behind an Authentik login (decided 2026-11-22;
first: the Traefik dashboard):

| Piece | Where | What it does |
| --- | --- | --- |
| Inventory | the route: `{name, url, authentik: true, title, authentik_group}` | One line switches it on. `authentik_group` defaults to `authentik Admins`. |
| Traefik (`docker01`) | `dynamic/authentik.yml` (middleware `authentik`, forward auth to `https://10.101.1.41:9443/outpost.goauthentik.io/auth/traefik`); the route gets the middleware after `admin-only`, plus a `<name>-outpost` router for `/outpost.goauthentik.io/` | Not logged in: redirect to `auth.int.phoenixstack.net` (password + YubiKey/TOTP), then back. Passes `X-authentik-username`, `-groups`, `-email`, `-name`, `-uid` to the app. |
| Authentik (`authentik01`) | blueprint `PhoenixStack - Proxy apps` (`templates/blueprints/phoenix-proxy-apps.yaml.j2`), built from the same routes | Per route: a proxy provider (forward auth, single application), an application (slug = route name), a group binding; and the embedded outpost's provider list. |

Order: `apb authentik.yml -l authentik01` first (the app must exist), then `apb docker.yml -l docker01`, then
`dns.yml` if the name is new. Removing `authentik: true` or the route doesn't delete the app in Authentik: delete
it in the UI. Apps with their own login (OIDC) are a different provider type: [below](#apps-with-their-own-login-oidc-and-google-sign-in).

Checked 2026-11-22 for the Traefik dashboard: without a login, the page and its API redirect to Authentik; a
forged `X-Forwarded-Host` is ignored; a non-admin source still gets `403` from the allow-list; `aaron` logs in with
a YubiKey and reaches the dashboard; a test user outside `authentik Admins` (`nogroup`, enrolled TOTP as required)
got Authentik's access-denied page, then was deleted.

### Apps with their own login (OIDC), and Google sign-in

Since 2026-11-24 (decision 12; first app: Audiobookshelf). Users sign in with Google; admins never do.

| Piece | Where | What it does |
| --- | --- | --- |
| Inventory | a route's `oidc: {title, redirects, groups}` on any Docker host | One entry makes the app's OIDC client. The role refuses an entry without groups: an app with no group binding admits every user. |
| OIDC clients | blueprint `PhoenixStack - OIDC apps` (`phoenix-oidc-apps.yaml.j2`) | Per route: a confidential provider (client ID = route name, strict redirect URIs on the route's own name, `authorization_code` and `refresh_token` grants: the default is none), an application and its group bindings. Authentik generates each secret once; it's entered in the app, never in git. Scope `email` comes from our mapping, which sends `email_verified: true` (Authentik's own sends `false`): every email is set by an admin and is the person's Google address. |
| People and Google | blueprint `PhoenixStack - People and Google sign-in` (`phoenix-people.yaml.j2`) | Groups `Family`, with `Young` and `Porter` below it (decision 8). The Google source: links a Google login to the existing Authentik user with the same email (`email_link`), no enrollment flow (an unknown Google account gets nothing), its button on the login page. |
| Admins and Google | flow `phoenix-source-authentication`, in "all" mode | A Google login must come from Google **and** not be in `authentik Admins`. (Authentik's default source flow runs in "any" mode, where an extra policy blocks nobody.) |
| Google's client | `.env.google` on `authentik01` (root, `0600`), written once from 1Password `(Google Cloud) - Authentik sign-in` | Client ID and secret for the Google source. Google Cloud project `PhoenixStack`, redirect URI `https://auth.phoenixstack.net/source/oauth/callback/google/`. |

Each person: an Authentik user created by hand, with the username **`first.last`** (the standard since 2026-11-25,
for admins too: `aaron` became `aaron.young`; Authentik allows no spaces), the email they
sign in to Google with, **no password**, and their group (`Young` or `Porter`); without a group, Google lets them
in but no app does. Users can't change their own email. Removing a route doesn't delete its client: delete it in
the UI. Checked 2026-11-24 on a staging copy, then in production: an admin by password and TOTP, a user by Google,
an admin refused on Google, the phone app.

### Authentik recovery

What a working Authentik needs, and where each piece comes from:

| Piece | Source | Note |
| --- | --- | --- |
| VM, Docker, compose file, blueprints | git: `tf apply`, `apb site.yml`, `apb authentik.yml` | |
| Secret key, database password, bootstrap password | 1Password (the `.env` items above), written by `authentik.yml` | **Same secret key as before.** It signs sessions, links and tokens; a new one logs everyone out and voids them. |
| Users, MFA devices, flows, apps, settings | Database `authentik` on `pgsql01`: nightly dump `/var/backups/db-dump/<day>/authentik.dump` (7 days on the guest), and the PBS/NAS backups of `pgsql01` | The dumps live on `pgsql01` itself: if the guest is gone, get them from its backup (PVE GUI → backup → **File Restore**) or restore the whole container. |
| Uploaded files (wallpaper, favicon) | `authentik01:/opt/stacks/authentik/data`, only in the PBS/NAS backups of `authentik01` | File Restore from the VM's backup. |
| The name `auth.int.phoenixstack.net` | git (`routes` on `docker01`, `authentik_base_url`) | **Must stay the same**: WebAuthn keys (YubiKeys, passkeys) are bound to the name the browser used at enrolment. On any other name only TOTP works. |

Pick the smallest repair that fits (each command dry-run first where it has one):

1. **`authentik01` broken, database fine.** Fastest: restore the VM from last night's PBS backup (it reconnects to the
   database by itself). Or rebuild: `tf apply` (after removing the broken VM), `apb site.yml -l authentik01`,
   `apb authentik.yml -l authentik01`; then File Restore the `data` folder if it held uploads.
2. **Database damaged, `pgsql01` fine** (a bad upgrade, a wrong change). Stop Authentik
   (`sudo docker compose stop` in `/opt/stacks/authentik`), then on `pgsql01`:

   ```bash
   sudo -u postgres dropdb authentik
   sudo -u postgres pg_restore --create --dbname=postgres /var/backups/db-dump/<day>/authentik.dump
   ```

   `--create` brings back the database's owner and access rules too: `apb database.yml -l pgsql01 --check` should show
   `changed=0`. Then `apb authentik.yml -l authentik01` to start it. Changes since that night's dump are lost.
3. **`pgsql01` lost.** Restore the container from PBS (start order and address come with it). Or rebuild:
   `tf apply`, `apb site.yml -l pgsql01 -e ansible_user=root`, `apb database.yml -l pgsql01` (UTF-8 cluster, role
   `authentik` with the password from 1Password, empty database), then take `authentik.dump` from the old guest's
   backup (File Restore) and restore it as in 2, with `--clean` instead of dropping first if the empty database is there.
4. **Can't log in** (both of `akadmin`'s factors gone, flows broken by a change): `ak create_recovery_key` (see Admin,
   above). Infrastructure logins (Proxmox, UniFi, iDRAC, NAS, 1Password) never depend on Authentik.

After any restore: log in as `aaron.young` with a YubiKey; check **Customization → Blueprints** shows `PhoenixStack - MFA required`
as successful; `apb authentik.yml --check` and `apb database.yml --check` show `changed=0`.

### Restore rehearsal

Before the first app depends on Authentik, and after each major Authentik upgrade. It proves that a dump, the
1Password secrets and git rebuild a working Authentik, without touching the live one. Use a fresh dump:
`sudo systemctl start db-dump.service` on `pgsql01` (replaces that day's folder).

1. **Scratch database** on `pgsql01`, from the latest dump, owned by `authentik`:
   `createdb -O authentik authentik_restoretest`, then
   `pg_restore --no-owner --role=authentik --dbname=authentik_restoretest <day>/authentik.dump`.
   A temporary `hostssl authentik_restoretest authentik 10.101.1.41/32 scram-sha-256` line, by hand, then reload.
2. **Scratch stack** on `authentik01`: a copy of the stack in `/opt/stacks/authentik-restoretest` (project name
   `authentik-restoretest`, same image and `.env`, `AUTHENTIK_POSTGRESQL__NAME=authentik_restoretest`, its own empty
   `data`, port `127.0.0.1:9444`, so nothing outside the VM can reach it and no firewall, DNS or route changes).
   Set its `AUTHENTIK_WEB__BASE_URL` to `https://localhost:9444` **and** the restored copy's stored one, which wins
   over the setting (scratch database only):
   `UPDATE authentik_tenants_tenant SET base_url='https://localhost:9444' WHERE schema_name='public';`,
   then restart the scratch server. Otherwise its links point at the live Authentik.
3. **Log in** through an SSH tunnel (`ssh -L 9444:127.0.0.1:9444 aaron@10.101.1.41`, then `https://localhost:9444`,
   accept the self-signed certificate): `aaron.young` with password and **TOTP** (YubiKeys can't work on `localhost`, see
   above). Check: both admin accounts and their devices are listed, **Customization → Blueprints** shows the MFA
   blueprint as successful, the brand settings match the live ones.
4. **Tear down:** `docker compose down` and remove the scratch folder; `dropdb authentik_restoretest`;
   `apb database.yml -l pgsql01` removes the hand-made line (expect only `pg_hba.conf` changed, then `changed=0`).
5. Record the result below.

| Date | Dump | Result | Time |
| --- | --- | --- | --- |
| 2026-11-22 | Manual, 19:16 (3.2 MB, 230 tables) | **Passed.** `aaron` logged in with password and 1Password TOTP; both admins and all 6 MFA devices restored; MFA blueprint `successful`, stage `configure` (WebAuthn, TOTP). Live Authentik healthy throughout. Found: the stored base URL (see step 2). Menu is Customization → Blueprints, not System. | 11 min, dump to teardown |

What it doesn't prove: WebAuthn after a restore (only on the real name, so only in a real recovery) and the
`data` folder (empty today; covered by the VM backups).

## L5f: DMZ Docker host and public Traefik (`docker02`)

**State (2026-11-26):** `docker02` takes the internet's `443`, through Cloudflare's proxy, and runs every public
app: Audiobookshelf, Mealie, IT-Tools and Immich ([Moving the public apps](#moving-the-public-apps)); the temporary
rule to docker-temp is gone. Built 2026-11-23 (Step A); the forward
and Audiobookshelf moved 2026-11-24 (Step B).

| Area | Decision | Why |
| --- | --- | --- |
| Guest | `docker02`: VM `11002`, MAC `02:aa:bb:cc:10:02`, `10.101.2.102`, DMZ (VLAN 200), cloned from `10001`. **8 cores, 16 GiB, 128 GB** on `nvme` (grown from 64 GB for podcasts that then moved to the NAS; disks don't shrink). | Tier 10, instance 2. Less memory than `docker01` to start; Immich's machine learning is the big one, and memory and disk grow online. |
| Docker | Role `docker_host`, the same as `docker01` (Docker CE, `live-restore`, `no-new-privileges`, `local` logs, `172.20.0.0/14`). | One way to run Docker. |
| Traefik | Role `traefik`, the same version. Port 443 only. Routes from the inventory, file provider, no Docker socket. | As on `docker01`; the socket would be root on an internet-facing host. |
| Certificate | **Cloudflare Origin CA** (decided 2026-11-23): `phoenixstack.net` and `*.phoenixstack.net`, 15 years (until 2041-11-19). 1Password `(Cloudflare) - Origin CA Certificate` holds it as two files (concealed fields turn PEM line breaks into spaces); the first run writes them to `secrets/` on the guest (root, `0600`). Cloudflare: SSL mode **Full (strict)**, **Always Use HTTPS** on (without it, plain `http://` reached the origin and failed with `522`). | No Cloudflare API token on the internet-facing host. Only Cloudflare needs to trust this certificate, since every request comes through its proxy. |
| Who may connect | `443` from **Cloudflare's addresses only**, on the UDM forward and again on the Proxmox firewall (firewall source `cloudflare`, the list from cloudflare.com/ips in the inventory); SSH and ping from admin sources. | Two locks, as for pve01. Nobody can skip the proxy, not even from the LAN. |
| Client addresses | Traefik trusts `X-Forwarded-For` from Cloudflare's addresses only (`forwardedHeaders.trustedIPs`). | Apps and logs see the real client, not Cloudflare. |
| Route names | Each Docker host has a `routes_domain`: `int.phoenixstack.net` on `docker01`, `phoenixstack.net` on `docker02`. Pi-hole adds names only for the `int.` routes. | Public names come from Cloudflare's wildcard record; Pi-hole must not answer them. |
| Authentik | Route `auth` on `docker02` → `https://10.101.1.41:9443`, so **`https://auth.phoenixstack.net`** works from anywhere, and it's Authentik's base URL (`auth.int` stays as a LAN and VPN entry). The admin pages (`/if/admin/`) are refused on the public name; the admin API isn't (review item S3). | Users outside need the login pages, and OIDC issuers must be the same at home and away. |
| UDM rules | Forward "Cloudflare - 443" → `10.101.2.102:443`, from the "Cloudflare IPv4 Ranges" group, port `443` only. Rules `docker02 -> authentik01` (TCP `9443`), `docker02 -> NAS (SMB)` (TCP `445`) ([UDM rules](#udm-rules); the temporary rule to docker-temp was deleted 2026-11-26). `authentik01`'s own firewall also accepts `9443` from `docker02`. | `docker02` reaches only what its apps need. |
| DNS | Nothing new: the zone's proxied wildcard record sends every name to the home address. DMZ guests ask the UDM. | |

Checked (2026-11-23 and 24):

- [x] `tf plan` and repeat Ansible runs: no changes.
- [x] Through Cloudflare, from a phone on mobile data and from the LAN: the names answer with Cloudflare's
      certificate; Traefik sees the visitor's address (`X-Forwarded-For`); `/if/admin/` → `403`; `http://` →
      `301` to `https://`. Without Cloudflare, the home address doesn't answer.
- [x] `docker02` reaches only `authentik01:9443` in Services, the NAS on `445` and docker-temp's temporary ports;
      nothing else in mgmt or the client LANs (13 targets, 2026-11-23; the temporary ports again 2026-11-24).
- [x] From the LAN, `auth.int` and the Traefik dashboard on `docker01` still work; the dashboard sends to the
      Authentik login on `auth.int`, where the YubiKeys are registered.

### Moving the public apps

Step B (designed 2026-11-23): the `443` forward moved to `docker02` first; the public apps follow one at a time.
All of them have moved (Immich last, 2026-11-26), and the temporary rule to docker-temp is deleted.

| Area | Decision | Why |
| --- | --- | --- |
| Where | Every public app runs on **`docker02`** (decided 2026-11-23), as a stack of role `apps`. | A broken app reaches only the DMZ. |
| Databases | Each app keeps its own, inside its stack: SQLite (Audiobookshelf, Mealie), Immich its own PostgreSQL. **No PostgreSQL guest in the DMZ and no way to `pgsql01`** (proposed 2026-11-23). | No public app would use a shared one, and it would put every public app's data where any of them could reach it. |
| NAS | **Read-only** `Media` (decided 2026-11-23), mounted inside `docker02` at `/mnt/nas/media` (role `nas_mount`, below) as its own NAS user **`svc_docker02`** (1Password `(UNAS) - svc_docker02`), which may only read it on the NAS too. The same paths inside the containers as on docker-temp. | The UNAS sets permissions per share, not per folder. The DMZ's only way into mgmt: SMB, to the NAS. |
| Writable shares | **One share per app that must write**, read-write for `svc_docker02` only (`nas_mounts`: `rw: true`, `owner` = the app's uid). First: `Podcasts` (decided 2026-11-24), 32 GB of mostly complete archives, growing; the share reports 94 GB. | `Media` stays read-only. On `docker02`'s disk they'd go into every nightly guest backup. Each writable share holds data its one app can download or rebuild. |
| App backups | Each app's own backups stay on `docker02` (Audiobookshelf: `/metadata/backups`); the nightly guest backups carry them off (proposed 2026-11-23). | On the NAS they'd need the `Backups` share, which also holds pve01's guest backups. |
| Immich | Needs a writable share of its own (uploads, thumbnails, encoded video, below). Designed with its move. Until then its files sit in `Media`, which `docker02` can read (accepted, below). | `Media` stays read-only. |
| Not published | Calibre (its basic auth lived in docker-temp's Traefik) and `absdev`, agreed 2026-11-24; neither has a container on docker-temp any more (compose files only, checked 2026-11-27). Admins reach the admin tools at `10.101.0.178:<port>` until they move to `docker01` (LAN and VPN only, decision 3; [Admin apps to `docker01`](#admin-apps-to-docker01)). MyBibliotheca: deleted 2026-11-24; a fresh install if it comes back. | |
| Names | Kept as on docker-temp (`immich-p`, `meal`, `tools`) until each app moves, then renamed after the app. | Phones and bookmarks keep working meanwhile. |

Steps (each dry-run first):

1. ~~Prepare~~ Done 2026-11-23: the disk, the NAS user, `docker02 -> NAS (SMB)`, the role `nas_mount`, and
   Audiobookshelf's own backups working again on docker-temp.
2. ~~Move the `443` forward~~ Done 2026-11-24: routes to docker-temp for each public app, the temporary rule,
   Authentik's public base URL, then the forward; the `8443` test forward deleted.
3. ~~Move Audiobookshelf~~ Done 2026-11-24, about 2 minutes offline ([Audiobookshelf](#audiobookshelf)).
4. ~~Its logins through Authentik~~ Done 2026-11-24, rehearsed first on a staging copy ([Staging](#staging));
   14 seconds offline.
5. ~~Move Mealie~~ Done 2026-11-25, about 90 seconds offline ([Mealie](#mealie)).
6. ~~Move IT-Tools~~ Done 2026-11-25, no downtime ([IT-Tools](#it-tools)).
7. ~~Immich~~ Done 2026-11-26, about 16 minutes offline ([Immich](#immich)). The temporary rule was then
   deleted (checked closed). **Step B is complete.**

#### Moving an app

From the Audiobookshelf move. Each step dry-run first; the switch in the quietest hours (for Audiobookshelf,
01:00–05:00 Denver).

1. **Read it on docker-temp**, read-only: its compose file and mounts, image digest, container user, data sizes,
   its own backups and schedules, its login settings. Note which folders change (database, uploads, downloads),
   and which live on the NAS: Audiobookshelf's podcasts did, not on docker-temp's disk.
2. **Decide where its data goes:** app data on `docker02`'s disk in `/opt/stacks/<app>`; files it only reads, from
   `Media`; files it writes on the NAS, on a share of its own (the Young admin creates it, read-write for `svc_docker02`).
3. **Code it:** an `apps_catalog` entry (its own uid, with no account on the host: uid 1000 is `aaron`; its
   folders; the version whose **digest matches** docker-temp's) and `templates/<app>/compose.yml.j2` with **the
   same paths inside the container**, `TZ: {{ app_timezone }}`, no capabilities and a healthcheck. Dry-run with
   `-e '{"apps": ["<app>"]}'` before it goes into the inventory.
4. **Copy while it runs:** the big data first, NAS to NAS on `docker02` itself, or through the laptop with `tar`
   over SSH (`docker02` has no rsync; 776 MB took about a minute).
5. **Switch:** stop it on docker-temp (`docker stop`, so it stays stopped after a reboot); copy what changed; add it
   to the inventory's `apps` and point its route at `http://<app>:<port>`; `apb docker.yml -l docker02`. Check its
   health, log, mounts (read-only where expected, writable where needed), then the app on a phone.
6. **Close the door:** the Young admin removes its port from the temporary rule; check from `docker02` that it's closed.
7. **Logins:** through Authentik where the app does OIDC (an `oidc` entry on its route,
   [above](#apps-with-their-own-login-oidc-and-google-sign-in)), rehearsed on a staging copy first.
8. **Rollback** until it's settled: start it on docker-temp and point the route back. A week later, delete the
   rollback copies.

#### Removing an app

The roles don't delete what an app leaves behind (review item O5, 2026-11-26): its folder holds its data, and
Authentik's blueprints never delete. What they do: role `apps` **reports** every stack folder in `/opt/stacks` that
is no longer in `apps`/`apps_staging` (running or stopped); role `nas_mount` **removes** the units of a share taken
out of `nas_mounts` (unmounts it; nothing on the NAS changes). The steps, each dry-run first:

1. Take its backup if anything in it matters (its own backup, or `/opt/stacks/<app>` from the guest backups).
2. Remove it from the inventory: its `apps` (or `apps_staging`) entry and its route; for a share only it used, its
   `nas_mounts` entry. Then `apb docker.yml -l <host>`: the route file goes, the report names the stack, and the
   share's units go.
3. Stop it: `cd /opt/stacks/<app> && sudo docker compose down` (containers and networks; the folder stays).
4. Its OIDC client: delete the application and its provider in Authentik's admin interface (blueprints don't).
5. An `int.` route: `apb dns.yml -l dns01`, then `-l dns02`, so Pi-hole drops the name.
6. After the rollback period: `sudo rm -r /opt/stacks/<app>`, its images (`sudo docker image prune -a`), and its
   NAS share if it had one (the NAS user's access first, then the share).
7. Outside the repo: its 1Password items, UDM rules or port forwards that named it, and the Cloudflare record if it
   had its own.

#### Audiobookshelf

On `docker02` since 2026-11-24.

| Area | State |
| --- | --- |
| Stack | `/opt/stacks/audiobookshelf` (role `apps`); image `2.37.2`, the digest docker-temp ran as `latest`; uid `2001`, no capabilities, healthcheck `/healthcheck`; route `abs` → `http://audiobookshelf:80`. |
| Files | `config` and `metadata` on `docker02`'s disk; `/audiobooks` read-only from `Media/Books/Audiobooks`; `/podcasts` read-write on the share `Podcasts`. |
| Schedules | Library scan of Audiobooks nightly at midnight, Denver time (the folder watcher can't see what Libation writes over SMB); its own backup nightly at 01:30 into `/metadata/backups`. |
| Logins | "Sign in with PhoenixStack": Authentik client `abs` (`authentik Admins`, `Family`), matching existing accounts by **email**, no auto-register. Local logins stay, for e-readers, the API accounts and people without a Google Account. Microsoft 365's links and settings were removed. |
| Accounts | 34 (14 listened in the last 90 days). Each person's Authentik email must equal their Audiobookshelf email; the account list is on the Young admin's laptop, not in this repo. |
| Rollback | Until about 2026-12-01: the database from before the login switch in `/opt/stacks/audiobookshelf/rollback/` (root only; back as `config/absdatabase.sqlite`, owner `2001`), the only rollback copy left (docker-temp's stopped container and `absdev` are gone: checked 2026-11-27). |

#### IT-Tools

On `docker02` since 2026-11-25, public with no login (decided by the Young admin the same day: it holds no data; its tools
run in the visitor's browser).

| Area | State |
| --- | --- |
| Stack | `/opt/stacks/it-tools` (role `apps`); image `2024.10.22-7ca5933`, the digest docker-temp ran as `latest` (still the newest release); route `tools` → `http://it-tools:80`. |
| Hardening | nginx's master starts as root, so it keeps `CHOWN`, `SETUID`, `SETGID` and `NET_BIND_SERVICE` (every other capability dropped); workers run as `nginx`; read-only filesystem with temporary `/var/cache/nginx`, `/var/run`, `/tmp`; memory 128 MiB; healthcheck `/`. |
| Switch | No data, so no downtime: the route moved first, then docker-temp's copy was stopped and commented out of its compose file. Checked through Cloudflare: `200`, `http://` → `301`, served by `docker02` (its access log). |
| Closed | `8081` removed from the temporary rule by the Young admin the same day; checked from `docker02`: times out (dropped), while `2283` connects. |

#### Mealie

On `docker02` since 2026-11-25, about 90 seconds offline (18:06:27–18:07:56 UTC). Before the switch, the stack was
test-started with its data copied while docker-temp still served it: healthy as uid `2002` with no capabilities.
At the switch, both copies were stopped, the data copied again (951 files, `mealie.db` checksum equal), then
`apb docker.yml -l docker02`. Checked through Cloudflare: `200`, `http://` → `301`, a wrong login `401` and logged
with the client's real address; 5 users and 414 recipes; the data folder writable.

Port `9925` removed from the temporary rule by the Young admin the same day; checked from `docker02`: `9925` times out
(dropped), `2283` and `8081` connect. Mealie was then removed from docker-temp's stack by the Young admin, so the rollback is
the copy of its data folder, still on docker-temp's disk (`~/docker/appdata/mealie`), until about 2026-12-02.
Logins through Authentik (step 7), designed 2026-11-25: visitors go straight to Authentik (no Mealie login
screen); anyone in `authentik Admins` or `Family` gets in; new people get an account on first login, in group
`Young Family`, household `Family`; existing accounts are matched by email; `authentik Admins` are Mealie admins.
Mealie's own password form stays at `/login?direct=1` until everyone has logged in through Authentik once, then
goes off; `svc_mealie` stays as the break-glass admin (a password account: turn password logins back on to use it
when Authentik is down). The client secret is in 1Password `(Authentik) - Mealie OIDC`, written into
`/opt/stacks/mealie/.env` (root only) by role `apps` (`env_op`).

Rehearsed 2026-11-25 on a staging copy (`meal-staging` on `docker01`, production's data):

- [x] An admin by password and TOTP (security keys are bound to `auth.int`, and OIDC uses the public name), straight
      from Mealie to Authentik and back: a new Mealie admin account. The first try looped: Mealie's default group
      is `Home`, this instance's is `Young Family`, so it couldn't create the account (`DEFAULT_GROUP` and
      `DEFAULT_HOUSEHOLD` now set).
- [x] An existing account matched by email: after its email was given to `svc_mealie` (staging only), the same
      login opened `svc_mealie`, still an admin and still a password account; no new account.
- [x] An admin refused on Google (by design).

In production since 2026-11-25 (`apb docker.yml -l docker02`, a few seconds offline). Authentik accounts for
Two more family members were added the same day (group `Young`, no password, like the first one's); one more has none yet.
The Young admin logged in through Authentik the same day (a new admin account, `aaron.young`). Then `password_login: false`:
no Mealie login screen, Mealie's own passwords refused. The staging copy was deleted (route, Pi-hole name, stack,
image, its Authentik client and its 1Password item, archived).

| Area | State |
| --- | --- |
| Logins | Through Authentik only. Users with Google, admins with password and TOTP (security keys are bound to `auth.int`). |
| Accounts | Three family members match their Authentik accounts by email (group `Young`). One more has no Authentik account, so no way in until they get one. |
| Break-glass | `svc_mealie`, admin, password account: set `password_login: true`, `apb docker.yml -l docker02`, log in at `/login?direct=1`. Its password: 1Password `(Docker) - Mealie` in `infrastructure` (`gqya622kl225ssha4w2quyku7a`). A non-work email is still to do. |

| Area | On docker-temp (read 2026-11-25) | On `docker02` |
| --- | --- | --- |
| Image | `ghcr.io/mealie-recipes/mealie:latest` = `v3.30.0`, digest `sha256:90f83da6…d784` (built 2026-11-01) | `v3.30.0`, the same digest (checked with `docker buildx imagetools inspect` on `docker02`) |
| User | uid 1000 (`svc_docker`), through the image's `PUID`/`PGID`: `run.sh` starts as root, `chown -R /app`, then `gosu` | uid `2002`, started as that uid with `PUID` equal to it, so `run.sh` skips its root steps; no capabilities |
| Data | `~/docker/appdata/mealie` → `/app/data`, 247 MB: SQLite `mealie.db` (1.7 MB), recipe images (85 MB), two manual backup zips (156 MB, 2025-12 and 2026-05), logs. Nothing on the NAS. | `/opt/stacks/mealie/data` → `/app/data`, owner `2002` |
| Content | 5 users (1 admin), 1 household, 414 recipes; last change 2026-11-21 | |
| Logins | Mealie's own passwords (all 5), sign-up off; no OIDC, no SMTP | The same; Authentik later (step 7) |
| Settings | `BASE_URL` was `http://localhost:9925` (links Mealie sends pointed nowhere); the daily-jobs time misspelled (`DAILY_SCHEUDULE_TIME`), so the default 23:45 ran; `TZ` UTC; memory 1000M | `BASE_URL` `https://meal.phoenixstack.net`; `DAILY_SCHEDULE_TIME` 03:00 Denver; `TZ` from `app_timezone`; memory 1 GiB; healthcheck `/api/app/about` |
| Its own backups | None scheduled (Mealie has no backup schedule) | The nightly guest backups carry `/opt/stacks/mealie` off; the old zips come along |
| Route | `meal` → `http://10.101.0.166:9925` (temporary rule) | `meal` → `http://mealie:9000`; renamed after the app later |

Closed 2026-11-26: the temporary migration host is wiped (REBUILD_STATE item 6), so nothing more comes from it.

#### Immich

On `docker02` since 2026-11-26 (moving started 2026-11-25). **One instance for everyone** (decided by the Young admin 2026-11-25): Immich keeps
each user's library private (admins manage accounts but can't browse others' photos); root on the hosts and the NAS
can read everything. NAS share **`Immich`**, read-write for `svc_docker02` only; `svc_docker02` may read `Porter`
(the external library). Created by the Young admin 2026-11-25. The name `immich-p` stays until it's changed with the Porter
users (every phone app's server address changes with it).

Read on docker-temp 2026-11-25:

| Area | On docker-temp |
| --- | --- |
| Images | Server `v3.1.0` (`sha256:b434cb92…`), machine learning **`v2.5.3`** (`sha256:fa843f76…`): pin both to `v3.1.0` at the move. PostgreSQL `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0` (14.19; extensions `vchord 0.4.3`, `vector 0.8.1`). Redis `redis:alpine` (no persistence, 256 MB). |
| Database | 1.5 GB, on docker-temp's disk (`appdata/immich-postgresql`), user `immich_db_user`, checksums on. Immich's own dump nightly at 02:00 into `upload/backups` (on the NAS). |
| Media | `Media/Immich/Porter` → `/usr/src/app/upload` (read-write): about **229 GB**: `upload` 148 GB (originals), `thumbs` 30 GB (about 150,000 files), `encoded-video` 44 GB, `backups` 6.6 GB, `profile` and `library` nearly empty (no storage template). Database paths start with `/usr/src/app/upload/`, so the path inside the container stays. An unnamed volume at `/data` (Immich's newer default) is empty. |
| External library | "New External Library", owner: the Porter admin, `Porter/PhotoArchive` → `/porter`, mounted **read-write** (read-only on `docker02`: Immich doesn't write to external libraries). About 55,700 assets. Folder watching is on (it can't see changes over SMB; a scan schedule instead). |
| Content | 7 users (3 Immich admins), about 32,400 uploads and 55,700 external assets. Uploads: 7,400 in August, 22,600 in September, 2,400 in October, **none since 2026-10-25**. 187 uploaded videos are over 100 MB (largest 1.1 GB): **Cloudflare's free plan refuses uploads over 100 MB**. |
| Machine learning | Model cache in `appdata/immich-machine-learning` (downloaded again if missing). |

On `docker02` (coded 2026-11-25, dry run clean; the stack not started yet):

| Area | Design |
| --- | --- |
| Stack | `/opt/stacks/immich` (role `apps`), four containers, all as uid `2003` with no capabilities: `immich-server` and `immich-machine-learning` `v3.1.0` (server: the digest docker-temp runs), `immich-postgres` (the same image and digest as docker-temp), `immich-redis` (Valkey 8: the job queues, `noeviction`, not saved to disk). PostgreSQL and Redis only on the stack's internal network; machine learning also has the default network, for its models. |
| Media | NAS share `Immich` → `/mnt/nas/immich` (read-write for uid `2003` only) → `/usr/src/app/upload`, as on docker-temp; `IMMICH_MEDIA_LOCATION` set to it, so the image's `/data` isn't used. `Porter` → `/mnt/nas/porter` (read-only), `PhotoArchive` → `/porter:ro`. |
| Database | `/opt/stacks/immich/postgres` on `docker02`'s disk; password in 1Password `(Immich) - PostgreSQL` (`.env`, root only, role `apps` `env_op`). Moved with a dump at the switch. |
| Route | `immich-p` → `http://immich-server:2283` (since the switch, 2026-11-26). |

Progress (where to pick up):

1. ~~NAS mounts on `docker02`~~ Done 2026-11-25 (`apb docker.yml -l docker02`, dry run first): `/mnt/nas/immich`
   (read-write, uid `2003` only: uid `1000` can't list it) and `/mnt/nas/porter` (read-only, even for root), checked.
   The new share came with a quota of about 5 GB; the Young admin raised it to **5 TB** (it shows as 4.6T in `df`).
2. ~~Bulk copy~~ Done 2026-11-26 01:20 UTC (`cp -rT --preserve=timestamps`, 3 h 27 min, `exit=0`). Checked: every
   top folder has the same file count and size as the source (`upload` 32,298 files, 157 GB; `thumbs` 155,134;
   `encoded-video` 10,183), except `backups`, which only lacks the next nightly dump. **Lesson:** on the read-only
   `Media` mount every file shows as `0440`, `cp` creates its copy with that mode, and on SMB without Unix
   extensions a file without write bits gets the NAS's **read-only** flag (not even root can write it). Immich
   refused to start (`EACCES` on `encoded-video/.immich`). Cleared on every file 2026-11-26 with
   `setpriv --reuid=2003 --regid=2003 --clear-groups find /mnt/nas/immich -type f ! -perm -u=w -exec chmod u+w {} +`
   (systemd unit `immich-chmod`); contents unchanged. Later copies onto a writable share: add
   `--no-preserve=mode`.
3. ~~Test start~~ Done 2026-11-26, route still on docker-temp: `apb docker.yml -l docker02 -e '{"apps":
   ["audiobookshelf","mealie","it-tools","immich"], "immich_api_only": true}'` (`immich_api_only`: the API worker
   only, `IMMICH_WORKERS_INCLUDE=api`, so no job touches the files). Database restored from docker-temp's
   `pg_dumpall --clean --if-exists` as Immich documents (into `postgres`, `search_path` fix), **without the
   `immich_db_user` role lines**: the dump would set docker-temp's password, and `docker02` has its own (1Password).
   No errors; 88,026 assets, 7 users, 222 albums, 91,352 faces, as on docker-temp. All four containers run as uid
   `2003` (PostgreSQL and machine learning too); server healthy, no migrations needed; uploads, thumbnails, encoded
   video and `/porter` readable; about 2 GB of 16 GiB used. Browser check through `ssh -L 2283:<immich-server's
   proxy-network address>:2283 aaron@10.101.2.102` (look only: the switch replaces this database).
4. ~~The switch~~ Done 2026-11-26, 17:49–18:05 UTC (daytime, the Young admin's go-ahead; no uploads since 2026-10-25):
   Immich stopped on docker-temp (`docker update --restart=no` on its four containers, so a reboot doesn't start
   them); database dumped and restored as in step 3 (same counts; newest asset 2026-10-25); delta copy with
   `cp -ruvT --preserve=timestamps --no-preserve=mode` (11 min, one file: that night's database dump, writable,
   same checksum); `immich` into the inventory's `apps`, route `immich-p` → `http://immich-server:2283`. Checked
   through Cloudflare: `ping`, version `3.1.0`, the web page; API and job workers running, no errors. Found after
   the switch: Redis was set to evict keys (`allkeys-lru`), but it holds Immich's **job queues**; now
   `noeviction` (Immich's job library warned). The temporary rule: deleted by the Young admin 2026-11-26 after Immich moved; checked from `docker02`: `2283`, `83`, `8081`, `9925` and `22` on docker-temp time out (dropped), the NAS's `445` still answers. Left: a phone check (app upload and browsing). Fixed the same day: the role set
   `postgres/` to `0750` and PostgreSQL set it back to `0700` at each start; now the catalog's `folder_modes`
   gives it `0700` (repeat run `changed=0`).
5. Rollback until about 2026-12-03: docker-temp's stopped stack and `Media/Immich/Porter` are left as they are
   (anything uploaded since the switch exists only on `docker02`). To roll back: `docker update
   --restart=unless-stopped` and `docker start` on docker-temp's four Immich containers, the route back to
   `http://10.101.0.178:2283` (docker-temp's address since 2026-11-26), and a UDM rule `docker02` → docker-temp `2283` again. Then delete the old copy. Later: logins through Authentik, a version policy, the rename of `immich-p` (with the Porter users), and
   Cloudflare's 100 MB upload limit (checked with a phone after the move).

### Staging

Decision 11's app staging: a copy on `docker01`, built for one test and deleted after it. Used for Audiobookshelf's
switch to Authentik (2026-11-24) and Mealie's (2026-11-25). For an app with OIDC, the copy gets a client of its own
(route `<app>-staging` with `oidc`) and that client's secret in `env_op_staging`; delete both afterwards.

| Area | Design (2026-11-24) | Why |
| --- | --- | --- |
| Where | `docker01` (Services), LAN and VPN only, `admin_only` route `<app>-staging`. In the inventory: `apps_staging: [{app, version}]` on `docker01`; role `apps` deploys stack `<app>-staging` from the same template (`stack.staging`). | Never public; the same template as production, so staging tries what production will run. |
| Data | Restored from production's **latest backup**, by hand, before the first start (so no empty instance is ever reachable). | Decision 11. Production's data is never touched. |
| Getting the backup there | Through the laptop: `docker02` → laptop → `docker01` over SSH. | Services can't reach the DMZ; no new firewall rule. |
| Media | **None yet** (the Young admin, 2026-11-24): `docker01` has no NAS access. The NAS folders are empty, read-only stand-ins: items show, nothing plays. Media comes when `docker01` gets the NAS (the *arr apps need it), before the first version upgrade is tested there. | Enough for logins; no new NAS user or rule now. |
| Side effects | Switched off in the copy's database before it starts (for Audiobookshelf: podcast auto-download, the nightly backup, the folder watcher). | A copy must not download, write backups or act on its own. |
| Scrubbing | None: the copy holds the accounts and their history, admins only. | It's deleted after use. |
| Lifetime | **Temporary:** deleted once the change is in production: the `apps_staging` entry and the route, `dns.yml`, its client in Authentik (a blueprint doesn't delete it), then `/opt/stacks/<app>-staging` and its image. | Nothing to patch or keep in step in between. |
| Logins | Its own OIDC client (an `oidc` entry on its route). Sessions copied from production stay valid in the copy (same signing key). | Production's client never points at staging. |

Restore (Audiobookshelf; dry runs first):

1. `apb docker.yml -l docker01 --check --diff` with the `apps_staging` entry and the `<app>-staging` route.
2. Before applying, the latest backup (`/opt/stacks/audiobookshelf/metadata/backups/*.audiobookshelf` on `docker02`)
   through the laptop to `docker01`, unpacked into `/opt/stacks/audiobookshelf-staging` as Audiobookshelf restores
   it: `absdatabase.sqlite` → `config/`, `metadata-items/` → `metadata/items/`, `metadata-authors/` →
   `metadata/authors/`; owner `2001`, folders `0750`.
3. In the copy's database: `podcasts.autoDownloadEpisodes` 0; `server-settings`: `backupSchedule` false,
   `scannerDisableWatcher` true.
4. `apb docker.yml -l docker01`, then `apb dns.yml -l dns01` and `-l dns02`, one at a time. `dns.yml`'s dry run
   can't show the names (the Pi-hole role applies its settings only for real), so check each resolver answers.

### The NAS mount

Role `nas_mount` in `docker.yml`, for hosts with `nas_mounts` (since 2026-11-23):

- `cifs-utils`; `/etc/nas/credentials` (root, `0600`): the NAS user, and its password read once from 1Password.
  Per share a systemd `.mount` and `.automount` unit (`mnt-nas-media`). Options: SMB `3.1.1`, `soft`,
  `noexec,nosuid,nodev`; read-only shares `ro`, files `0444` and folders `0555`; writable shares (`rw: true`,
  `owner`) `rw`, files `0640` and folders `0750`, for that uid only. A mount attempt gives up within 30 s.
- Mounted on first use, then kept. The guest boots without the NAS, and a container that starts while the NAS is
  away fails to start rather than finding an empty folder.
- **What `docker02` can read:** all of `Media`, since the NAS sets permissions per share. That includes
  `Media/Immich` (the Porter household's photos, thumbnails, encoded video and Immich's database backups) and the
  download folders. A container sees only the folders mounted into it; whoever controls the host sees all of `Media`.
  **Accepted until Immich moves** (decided 2026-11-23): Immich's data then goes to a share of its own and leaves
  `Media`, and Immich on `docker02` holds that data anyway. Narrower later: a `Books` share instead of `Media` for
  `docker02`, with Calibre's redesign.
- To rotate the password: change it on the NAS and in 1Password, delete `/etc/nas/credentials`, run
  `apb docker.yml -l docker02`; stop the apps using the shares, stop each `mnt-nas-*.mount`, start the apps again
  (the shares mount again on first use).
- [x] Checked 2026-11-23 for `Media`: with the NAS away, a listing fails after 10 s and a container using the share
      refuses to start; writes are refused by the mount and by the NAS; `Backups` and `Porter` can't be mounted;
      only `445` answers; the mount survives a reboot. 2026-11-24 for `Podcasts`: uid `2001` writes, `aaron`
      can't list it.

### docker-temp: what's left to move

Read 2026-11-23 and 2026-11-27: a Deployrr layout in `~/docker` (one compose file including one file per app,
`appdata/`, Traefik 3.6 with file rules, basic auth on the admin tools). Its user `svc_docker` has no passwordless
`sudo`, but is in the `docker` group. Since 2026-11-24 the internet doesn't reach it, and since 2026-11-26 neither
does `docker02`. **Its address is `10.101.0.178` since the patch reboot of 2026-11-26** (it was `.166`, a plain DHCP
lease); a fixed IP `.178` in UniFi keeps it there until it retires (outside the address scheme: temporary, VMID 999).
The public apps have all moved (Immich last, 2026-11-26); what's left are the admin apps, below.

### Admin apps to `docker01`

**Designed 2026-11-27, decided by the Young admin the same day. First group and MeTube moved the same day** (below);
libraforge next. The admin apps leave docker-temp for `docker01` (Services: LAN and VPN only, decision 3); then
docker-temp retires. **Libation stays out** (the Young admin, 2026-11-27: maybe not in use long-term); it goes with
docker-temp unless decided otherwise.

On docker-temp (read 2026-11-27): all as uid 1000, images on `latest` (Sonarr on its `develop` branch, v5 nightly).

| App | Data | NAS | Name today |
| --- | --- | --- | --- |
| Sonarr | 481 MB | `Media` read-write (imports into `TV Shows`), `###Downloads` | `tv.` |
| Radarr | 3.1 GB | `Media` read-write (imports into `Movies`), `###Downloads` | `movies.` |
| SABnzbd | 4 MB | `###Downloads` | `dl.` |
| autobrr | 9 KB | none | `autobrr.` |
| Libation | 88 MB | `###Downloads/libation`; its "backups" go to an unmounted folder, so onto docker-temp's own disk | (no web UI) |
| libraforge | 11 MB | `###Prep/audiobook-dev` | `libraforge.` |
| MeTube | 1 KB | `###Downloads/ytdl` | `ytdl.` |
| Glances | config | docker-temp's Docker, through a socket proxy | `glances.` |

| Area | Decision | Why |
| --- | --- | --- |
| Where | **`docker01`**, as stacks of role `apps`. | Admin tools, never public (decision 3). |
| NAS | **`Media` read-write** for `docker01`'s own NAS user **`svc_docker01`** (1Password `(UNAS) - svc_docker01`). Checked 2026-11-27 with `smbclient`: reads and writes `Media`; `Porter`, `Backups`, `Immich`, `Podcasts` refused. UDM rule `docker01 -> NAS (SMB)` to create. | A deliberate exception to "one share per app that writes": Sonarr and Radarr import into the library itself, and managing it is their job. `docker01` isn't internet-facing and only admins reach it; the DMZ stays read-only. |
| One uid | All apps that write to `Media` run as **one shared uid**, the owner of the writable mount (role `nas_mount`: one `owner` per share). | They hand files to each other (download → import). |
| Logins | **Authentik only**, admins only (forward-auth on each route, `admin_only`). The apps' own logins switch to "External"; their API keys stay, for each other. | One login, with MFA, for every admin tool. |
| Names | After the app: `sonarr.int`, `radarr.int`, `sabnzbd.int`, `autobrr.int`, `metube.int`, `libraforge.int`. The old public names (`tv.`, `movies.`, `dl.`, `ytdl.`) go. | The naming rule (2026-11-23). |
| Glances | **Dropped.** | It needs the Docker socket; monitoring is decision 6. |
| Versions | Pinned to the digest each runs today (Sonarr's nightly too; to its stable branch later, through staging). | As the public apps. |
| Plex | **No rule `docker01 -> plex01`**: Sonarr and Radarr don't notify Plex (they didn't before either); Plex scans its libraries **every hour** instead (was daily; set 2026-11-27). Its "scan on change" can't see changes made over SMB by another machine. | A notification would need the server owner's full Plex token on `docker01`; an hour's delay is fine. |
| Order | Sonarr, Radarr, SABnzbd and autobrr together (they work as one); then MeTube, libraforge, Libation one at a time. | |

**First group moved 2026-11-27** (Sonarr, Radarr, SABnzbd, autobrr; stopped on docker-temp 03:15 UTC, healthy on
`docker01` 03:23):

- NAS: `Media` read-write at `/mnt/nas/media` for uid `2010` (`apps_media_uid`); checked: uid `2010` writes and
  deletes, the admin user `aaron` can't even list it; UDM rule `docker01 -> NAS (SMB)` checked live (`445` open,
  pve01's GUI closed).
- Images: the tags with the same image IDs as docker-temp's (Sonarr's is `develop-5.0.0.2941-ls208`). LinuxServer's
  images refuse to start as a non-root uid until **`/run` is a RAM folder owned by that uid** (their s6 needs it);
  then they run as uid `2010` with no capabilities. autobrr runs that way as it is.
- Data: each app's `/config` from docker-temp (4.1 GB) to `/opt/stacks/<app>/config`, through the laptop; the same
  paths inside the containers, so their databases needed no change (root folders `/data/media1/…`, SABnzbd at
  `sabnzbd:8080`). Checked: Sonarr and Radarr reach SABnzbd; they see 353 show and 2,010 film folders; all three
  write to `/data/downloads`; Sonarr writes in `TV Shows`.
- Logins: Sonarr and Radarr `AuthenticationMethod` **External**; SABnzbd's web login cleared (its `[misc]` only: the
  Usenet server's login stays) and `sabnzbd.int.phoenixstack.net` added to its `host_whitelist`. Sonarr and Radarr
  also have **`AllowedHosts`**, which still named their old public names (`tv.`, `movies.`) and refused anything else
  with "Invalid Hostname": now `<app>,<app>.int.phoenixstack.net`. autobrr keeps its own login behind Authentik
  (it can't switch it off; OIDC with Authentik is the alternative, later); it has no download clients configured.
  The settings before the move are kept as `config.xml.pre-move` and `sabnzbd.ini.pre-move`.
- Authentik (`authentik.yml`): a proxy provider and application per app, `authentik Admins` only; Pi-hole names on
  `dns01`, then `dns02`. Checked from an admin machine: every name redirects to Authentik's login. Repeat runs of
  `docker.yml`, `authentik.yml` and `dns.yml`: `changed=0`.
- Rollback: docker-temp's four containers are stopped with `restart=no`, data untouched (`docker update
  --restart=unless-stopped` and `docker start` brings them back, at `10.101.0.178:<port>`).

**MeTube moved 2026-11-27** (03:33–03:34 UTC): `2026.11.06` (the same image as docker-temp's); as uid `2010` with no
capabilities as it is; `state` (history, queue) and `cookies` from docker-temp. `cookies/cookies.txt` (a copy also
in `state`) holds browser cookies for YouTube, a logged-in session: a credential, kept only on `docker01`'s disk
(`0600`, uid `2010`). Downloads into `Media/###Downloads/ytdl` (checked: writes). Log level back to the default (it
was `debug`). Route `metube`, admins through Authentik. A new Authentik proxy app answers `404` for up to a minute
until Authentik's outpost picks it up, then redirects to the login. Rollback: docker-temp's container, stopped
with `restart=no`.

## L5g: Media server (`plex01`)

**Live since 2026-11-27** (switched 02:26–02:30 UTC; remote access a few minutes later). Replaces PLEX-TEMP (VM `9999`, `10.101.0.111`, mgmt). Decided by the Young admin
the same day: **Plex only** (Jellyfin, if it comes, is its own instance); **native** install; **read-only** media;
downtime is acceptable. Goals: users never reconfigure a client, and the VM is only as big as it needs to be.

### PLEX-TEMP today (read 2026-11-26)

| Area | State |
| --- | --- |
| VM | Ubuntu 26.04, 4 cores (2 sockets × 2), 16 GiB, one 256 GB disk on `nvme` **without `discard`**: 95 GB used inside, 225 GB taken on the pool. P2000 (`GPU01`), NVIDIA 580 (550 and 570 packages left over). |
| Plex | `plexmediaserver` 1.43.5 (`.deb`), name `PLEX01`, claimed; data in `/var/lib/plexmediaserver/…/Plex Media Server`, **82 GB**: databases folder 54 GB, `Metadata` 20 GB, `Media` (preview thumbnails) 6.6 GB, the rest under 1 GB. |
| Databases | `library.db` 0.55 GB and `library.blobs.db` 1.1 GB, **integrity check `ok`** on copies made with Plex's SQLite. The other **52 GB are 69 `-tmp` files**: the scheduled backup's target, `/content/Plex Database`, doesn't exist, so each backup (every 3 days, July 2025 – April 2026) was left behind. |
| Libraries | 15 (71,505 items), all under **`/content`**: the NAS share `Media` as `svc_plex`, mounted **read-write**. |
| Network | No `customConnections`, no manual port mapping: clients find the server through plex.tv. `LanNetworksBandwidth` still lists the old networks (`192.168.1.0/23`, `10.0.1.0/24`), so home clients count as remote. |
| Subtitles | 1,032 sidecar files next to the media (read only); 46 downloaded on demand, stored **inside `library.blobs.db`**. |
| Address | DHCP. After the patch reboot of 2026-11-26 it came back at `.25` and the forward missed it for about 1¾ hours; fixed IP `.111` in UniFi since. |

### Design

| Area | Decision | Why |
| --- | --- | --- |
| Identity | **Carry over `Preferences.xml` and the databases**; never run both servers at once. | Clients, shares, managed users and watch history follow the server's machine identifier and its library IDs. A fresh install gets a new identifier: that's why users had to reconfigure before. |
| Guest | `plex01`: VM `10601`, MAC `02:aa:bb:cc:06:01`, **static** `10.101.2.61`, DMZ, Debian 13 (clone of `10001`). 4 cores, 12 GiB (Plex uses about 5 GiB today; the rest for the transcode folder). `GPU01` (P2000) passed through. | Tier 06. Static, as every new guest, so the forward can't miss it. |
| Disks | **Two, both `discard=on`, thin:** 32 GB system disk; **64 GB Plex data disk** at `/var/lib/plexmediaserver` (about 28 GB used at the move). | Grow online in a minute when needed. A ZFS volume can't shrink, but with Plex alone on its disk, shrinking is a copy to a smaller disk. `discard` returns freed space to the pool. |
| Transcoding | GPU (NVENC/NVDEC); temporary files in RAM (`tmpfs` at `/transcode`, 4 GiB). | Never fills a disk, never in a backup. |
| Install | Plex's apt repository (key fingerprint pinned), **version pinned to PLEX-TEMP's 1.43.5** for the move; NVIDIA driver from Debian 13's `non-free` (550 series, supports Pascal; checked at build). New role `plex`, playbook `plex.yml`. | Native, as decided: one app on a dedicated VM with a GPU; the data layout stays as it is. |
| Media | NAS `Media` **read-only** at **`/content`** (same path, so all 15 libraries stay valid), own NAS user **`svc_plex01`** (role `nas_mount`). | The DMZ standard. Users can't delete media from Plex apps; Plex can't write next to the media. |
| Subtitles | Sidecar files and on-demand downloads keep working (read-only and inside the database). Automatic downloads later: **Bazarr** with the *arr apps on `docker01`, writing sidecars. | No write access to the NAS from the internet-facing host. |
| Settings changed after the move | `LanNetworksBandwidth` → the current home and VPN networks; database backups to a local folder on the data disk (Plex's own, every 3 days, kept 3); transcoder folder `/transcode`; hardware encoding on. | Today's backup target doesn't exist; home clients should count as local. |
| Firewall | `32400/tcp` from anywhere (UDM forward and Proxmox firewall); SSH and ping from admin sources. UDM rule `plex01 -> NAS (SMB)` (TCP `445`). | As `docker02`: two locks. |
| Backups | Both disks in the nightly guest backups. | |

### Migration (each step dry-run first)

1. ~~Prepare~~ Done 2026-11-26 (the Young admin): NAS user `svc_plex01` (1Password `(UNAS) - svc_plex01`), checked
   with `smbclient`: reads `Media`, can't write to it, and `Porter`, `Backups`, `Immich`, `Podcasts` are refused. UDM
   rule `plex01 -> NAS (SMB)` (`10.101.2.61` → `10.101.0.101:445`, TCP, IPv4; checked in the export). Transfer
   folder `Media/transfer`.
2. ~~Build~~ Done 2026-11-26: Terraform (`data_disk_gb`, and `gpu_mapping` for the switch, in the VM module), then
   `site.yml` and `plex.yml` (roles `nas_mount`, `plex`); repeat runs `changed=0`. Checked: static `10.101.2.61`; the
   NAS reachable on `445` only (not pve01's GUI, not PostgreSQL); `/content` reads the NAS and refuses writes; data
   disk at `/var/lib/plexmediaserver`, `/transcode` 4 GiB in RAM, both after a reboot; Plex 1.43.5 installed, held,
   disabled, not running. Found on the way:
   - Debian's **standard kernel** replaces the cloud image's (the NVIDIA module isn't built against the cloud kernel;
     with both at one version the boot menu picked the cloud one, so `grub-reboot` once, then the cloud kernels
     removed). NVIDIA 550.163.01 is built for it (`dkms`); it needs `contrib` as well as `non-free`.
   - Plex's installer refuses a masked service, and its post-install step starts Plex. Instead, an `override.conf`
     (the only one Plex accepts): **Plex starts only if its `Preferences.xml` exists**. Its post-install start was
     skipped by that condition, so no new identity was created; a Plex rebuilt from nothing needs the condition
     removed for its first start.
   - **GPU test, done 2026-11-26** (Plex offline about 25 minutes): the token got `Mapping.Use` on `GPU01` (`access`
     stage), PLEX-TEMP off, `gpu_mapping: GPU01` on `plex01`. With the card's option ROM, **SeaBIOS hung before
     booting** (0 bytes read from disk); with **`rombar` off** (the VM module now always passes the GPU that way: it
     is never a display) it booted in 30 s. `nvidia-smi`: Quadro P2000, 550.163.01. NVDEC + NVENC (`h264_nvenc`,
     Debian's `ffmpeg`, removed afterwards with its 175 libraries): 20 s of a film at 226 fps, 9.4× real time. So
     **SeaBIOS works; no UEFI needed.** Then the GPU went back to PLEX-TEMP (`gpu_mapping` removed again: two VMs
     with one GPU configured would fail at the next pve01 reboot), Plex on `.111` and remotely again. Notes: Plex's
     own transcoder can't be tested while Plex is off (its codecs come with the running server); the NVIDIA packages
     divert the system's `libGL` (only matters for tools like `ffmpeg`, not for Plex); PLEX-TEMP's start logs
     "failed to reset PCI device", harmless (its driver sees the card).
   - Plex's user is uid `999` here, `998` on PLEX-TEMP: copied files are given to `plex` afterwards.
3. ~~Copy ahead~~ Done 2026-11-27 while PLEX-TEMP served: `tar` of `Metadata` and `Media` to `Media/transfer/plex-ahead.tar`
   (27.4 GB, 4 min, through PLEX-TEMP's guest agent; a marker file `/root/phx-ahead-start` there records the start),
   unpacked on `plex01` (under 3 min) and given to `plex`. Checked: `Metadata` 63,606 files / 20 GB and `Media`
   142,837 / 6.6 GB on both; none changed on PLEX-TEMP since the archive started.
4. ~~Switch~~ Done 2026-11-27, Plex offline 02:26–02:30 UTC: Plex stopped and disabled on PLEX-TEMP (databases closed
   cleanly, no `-wal`); catch-up archive `Media/transfer/plex-switch.tar` (1.76 GB: `Preferences.xml`, the two
   databases, `Plug-in Support/{Data,Metadata Combination,Preferences}`, `Scanners`, `Plug-ins` with the third-party
   agent `Audnexus.bundle`; nothing in `Metadata`/`Media` had changed), checksums equal on `plex01`; PLEX-TEMP shut
   down with `onboot` off (it must not take the GPU at a pve01 reboot); `Preferences.xml` changed before the first
   start (original kept as `Preferences.xml.pre-switch`): `LanNetworksBandwidth` the current networks, database
   backups to `/var/lib/plexmediaserver/db-backups`, transcoder `/transcode`, hardware decode and encode on;
   `gpu_mapping: GPU01` and `plex_enabled: true` in the inventory; forward "Plex - 32400" → `10.101.2.61` (the Young
   admin). Then **manual public port `32400`** (it was automatic, waiting for UPnP, which a fixed forward doesn't
   answer): plex.tv reports it `mapped`. Checked: same name `PLEX01` and machine identifier, claimed; all 15 libraries
   with their IDs; through the public address; a phone on mobile data browses and plays with no change on it; a
   transcode runs on the GPU (`nvdec` → `nvenc`, 15.7× real time).
5. **Rollback** until about 2026-12-04: on `plex01`, `plex_enabled: false` and `gpu_mapping` removed (`apb plex.yml`,
   `tf apply`); PLEX-TEMP `onboot` on, started, `systemctl enable --now plexmediaserver` there; forward back to
   `.111`. (Plex data changed on `plex01` meanwhile stays there.) Afterwards: delete PLEX-TEMP (VM `9999`), the
   transfer folder's two archives (29 GB), `Preferences.xml.pre-switch`, the UDM rules `Internal -> Plex-TEMP` and
   `Site VPNs -> Plex-TEMP` and their returns; `svc_plex` loses its access to `Media`.

## Household DNS

**Started 2026-11-22** on the Young LAN; watching it for a day before the other networks.

| Area | Decision | Why |
| --- | --- | --- |
| How | **The UDM forwards `int.phoenixstack.net` to Pi-hole** (decided 2026-11-22). Household devices keep the UDM as their DNS server; two UniFi DNS policies ("Forward Domain") send the internal domain to `dns01` and `dns02`, and the UDM resolves everything else itself, as before. | A pve01 reboot or failure takes only the internal names down, not the household's internet. Turning the forward off works at once. |
| Not chosen, for now | Pi-hole directly, handed out by DHCP. | Every pve01 reboot would take the household offline. Revisit with ad blocking and the Porter Pi-hole (open decision 9). |
| Young LAN | DHCP DNS: automatic, so the gateway (was `8.8.8.8`/`8.8.4.4`); domain `int.phoenixstack.net` (was `young.stack`), so short names like `pgsql01` work. | Devices switch as their leases renew (24 hours). |
| UDM rules | No new rule for DNS: the UDM asks Pi-hole from `10.101.1.254`, which the resolvers accept. The zone rules `Services/Management/IOT -> Gateway (Block)` now match `New` and `Invalid` connections only. | Set to all states, they also dropped Pi-hole's replies to the UDM's own queries, and forwarded names timed out. |
| Admin machines | Unchanged: they ask Pi-hole directly. | |
| Not yet | Porter (steps below, [Porter LAN](#porter-lan)) and RYoung (the same steps over their own tunnel); IOT already uses the UDM, so it gets the names too (the zone rules still keep it out of Services); VPN clients (WiFiman forces public DNS, REBUILD_STATE item 1); the `443` rule into Services (with the first app for household users). | One network at a time. |

Done when (checked 2026-11-22 through the UDM, `dig @10.1.1.254`):

- [x] Internal names answer (`auth`, `postgres`, `pve01`, `authentik01`) over UDP and TCP; `AAAA` is empty (no public
      wildcard); an unknown internal name gets NXDOMAIN; public names resolve.
- [x] Failover: with either resolver stopped, the other answers at once; with both stopped, internal names fail and
      public names still resolve.
- [x] A phone rejoined the Young Wi-Fi: DNS `10.1.1.254`, websites load.
- [x] Pi-hole's logs show the UDM's queries (914 a day to each resolver, checked 2026-11-24), and nothing broke for the household.

### Porter LAN

Started 2026-11-23: steps 1, 2 and 4 done, the tests (step 3) pending. The Porter gateway (a UDM, the Porter admin's) gets the same forward as the Young UDM. Its queries
reach Pi-hole over the BPorter site-to-site tunnel, so this UDM needs one new rule. Only names under
`int.phoenixstack.net` change; every other lookup at Porter goes where it goes today. If pve01 or the tunnel is
down, only the `int.` names fail.

| Area | Decision | Why |
| --- | --- | --- |
| Porter UDM | Two DNS policies, **Forward Domain** `int.phoenixstack.net` → `10.101.1.21` and → `10.101.1.22`, as on the Young UDM. | The same setup at both sites; one place to turn it off. |
| Porter LAN DHCP | DNS server **automatic** (the gateway), domain name `int.phoenixstack.net`. Change only what differs: if DHCP already hands out the gateway, leave it. | Devices use the forward only if they ask the Porter UDM. Short names (`pve01`) need the domain. |
| Young UDM rule | **`Porter Gateway -> Pi-hole (DNS)`**: zone VPN → Services, source the Porter gateway's address, destination `10.101.1.21` and `10.101.1.22`, port `53`, UDP and TCP, before the zone's block rule. | VPN → Services is admin-only, and the gateway isn't an admin source. Port 53 only, to the two resolvers only. |
| Pi-hole firewall | Nothing new if the queries come from a `10.2.1.x` address: `dns01`/`dns02` already accept `53` from `lan` (includes `10.2.1.0/24`). If they come from the gateway's WAN or tunnel address, add that `/32` to their `firewall_in` (inventory) and run `tf plan`/`apply`. | Find out from Pi-hole's query log (step 3), not by guessing. |
| Admin machines | The Porter admin's workstation (Windows) and laptop (macOS) keep hosts entries for `pve01` and its iDRAC (`10.101.0.11 pve01.int.phoenixstack.net pve01`, `10.101.0.1 idrac-pve01.int.phoenixstack.net`), so both still open by name when pve01, and with it Pi-hole, is down. The iDRAC matters most then. | The same fallback as the Young admin's machines. |

Steps:

1. ~~**Young UDM:** add the rule `Porter Gateway -> Pi-hole (DNS)` (table above). Use the gateway's LAN address
   (`10.2.1.x`, from its Networks page) as the source first.~~ Done 2026-11-23.
2. ~~**Porter UDM:** add the two Forward Domain policies.~~ Done 2026-11-23.
3. **Test from the gateway's side before any device depends on it**, from the Porter admin's workstation:
   `nslookup pve01.int.phoenixstack.net <Porter gateway address>`. Expect `10.101.0.11`.
   - Cloudflare addresses or a timeout: open Pi-hole's query log on `dns01`. No query from Porter means the rule or
     the source address is wrong: note the address the query came from on the Young UDM's traffic log, fix the
     rule's source (and the Pi-hole `firewall_in`, table above), and test again.
4. ~~**Porter LAN DHCP:** DNS automatic, domain `int.phoenixstack.net`, only if they differ today.~~ Done 2026-11-23.
   Devices switch as their leases renew (expect a mix until then).
5. Check with the Porter admin the next day, then tick the list below.

Done when:

- [ ] Through the Porter gateway: internal names answer (`auth`, `pve01`, `idrac-pve01`) over UDP and TCP; an unknown internal name
      gets NXDOMAIN; public names resolve.
- [ ] Pi-hole's query log shows the Porter gateway's queries (and the source address is recorded above).
- [ ] Failover: with `dns01` stopped, names still answer through `dns02`.
- [ ] The Porter admin's workstation and laptop: `pve01.int.phoenixstack.net` and `auth.int.phoenixstack.net` resolve;
      `https://pve01.int.phoenixstack.net:8006` opens without a certificate warning.
- [ ] A day later: nothing broke for the Porter household.

## Decisions by number

Each keeps its number: code comments and the other docs refer to them ("decision 11").

### Open

- **3.** Which docker-temp apps are public (on `docker02`) and which LAN and VPN only (on `docker01`)? Started
  2026-11-23, not exhaustive:
  - Public, for every user: Audiobookshelf (moved 2026-11-24), Plex, Immich, Mealie, IT-Tools, Calibre (later,
    maybe a fresh design rather than a move). MyBibliotheca was deleted 2026-11-24.
  - Admins only (the Young and Porter admins, for now), **LAN and VPN only** (`<app>.int.phoenixstack.net` on `docker01`),
    reached from outside over Teleport, never published (decided 2026-11-23): the *arr apps, libraforge, libation,
    metube, glances.
  - Plex keeps its own `32400` forward and plex.tv logins (no Traefik, no Authentik). `absdev` doesn't move.
  - Logins: each app's **built-in OIDC** with Authentik wherever it has one, forward-auth only for browser-only apps
    without it. Immich has password logins today (7 users, none linked to anything).
- **4.** AI tier code (proposed 12, `.121`).
- **6.** Monitoring (uptime and service alerts): which zone and when.
- **7.** Hardware, not blocking: the 990 Pro drives and ASUS card (`data` pool) and the RTX 3070 aren't installed.
- Small items (2026-11-25): the Porter admin's SSH access to the guests (the Young admin sets it up with the Porter admin and passes on the details);
  a non-work email for Mealie's `svc_mealie`; an Authentik account for the remaining family member, if wanted.

### Roadmap (decided: later)

- **9. Ad blocking**, together with the off-host Pi-hole at Porter (decided 2026-11-22). Household networks use the
  UDM, which forwards only `int.phoenixstack.net` to Pi-hole, so a pve01 outage doesn't take the household's DNS
  down. Ad blocking needs Pi-hole to see every query: once the Porter Pi-hole exists, switch household networks to
  Pi-hole directly (DHCP DNS + a LAN → Services port 53 rule), for per-device logs and blocklists. Networks that
  shouldn't depend on Pi-hole (IOT, guests) keep the UDM.
- **10. SIEM / central logs** (2026-11-22, after the core services; decide together with 6). Sources: the UDM's
  firewall log, pve01, guests' journals, Authentik events, Traefik access logs, Pi-hole queries. First decide the
  scope: log aggregation with alerts (e.g. Grafana + Loki, shared with monitoring) or a full SIEM (e.g. Wazuh:
  agents, detection rules, a search index, much heavier). Tier 08 (`.81`) is the monitoring tier. Until then logs
  stay local (guest journals capped at 200 MB).

### Settled

- **1. Cloudflare's proxy** in front of the public web apps (settled 2026-11-23): the `443` forward accepts
  Cloudflare's addresses only, and the public Traefik uses a **Cloudflare Origin CA** certificate, so no Cloudflare
  API token sits on the internet-facing host (a stolen zone token could redirect any name, mail included).
- **2. Plex only** (settled 2026-11-26): `plex01` runs Plex, natively; Jellyfin, if it ever comes, is its own
  instance (L5g).
- **5. DNS on pve01** (settled 2026-11-21): `dns02` on pve01 covers guest maintenance; off-host DNS will be a
  Pi-hole on the Porter network, later; until then a pve01 outage takes DNS down (accepted). Also settled: admin
  machines first, no ad blocking yet, recursive Unbound upstream (see L5b).
- **8. Authentik audiences** (settled 2026-11-23, built 2026-11-24): `Family`, with `Young` and `Porter` below it.
  Groups describe people, not apps; a binding to a group also admits its child groups; outside audiences
  (`Guests`?) if needed. Group definitions in a blueprint, memberships in the UI; new users created by hand.
- **11. Testing before production** (decided 2026-11-23). Image versions are pinned in git, so a new version is a
  change to its pin, tried somewhere else first:
  - **App staging:** a copy on `docker01` (`<app>-staging.int.phoenixstack.net`, LAN and VPN only, never public) on
    the candidate version, with a **copy** of production's data from its latest backup, never touching production.
    Once it works, change the production pin in git and apply. Designed and used once, 2026-11-24: [Staging](#staging).
  - **Test guests:** for changes to roles, Terraform or a whole host, a throwaway guest in tier 99
    (`test01`/`test02`, as for L5a), built from a git branch with the same roles; merge, then destroy it.
  - Not a permanent second environment (a second `docker02`, a second Authentik): twice the patching, and it
    drifts from production.
- **12. Users log in with their Google account, through Authentik** (decided 2026-11-23, live 2026-11-24 with
  Audiobookshelf; [how](#apps-with-their-own-login-oidc-and-google-sign-in)). Authentik is the one place that says
  who a person is (username, email, groups); the Google account is only the key they prove it with, and the apps
  only ever see Authentik. Each person is created by hand; their first Google login links to that user by email. No
  open sign-up. Each app keeps one local admin (break-glass), and local logins for clients that can't do OIDC
  (e-readers, scripts) and for people without a Google Account.
  - **Apps match by email** (changed 2026-11-24 from "by username": Audiobookshelf's usernames are display names
    with spaces, which Authentik doesn't allow): each person's app email must equal their Authentik email, and for
    Google users that's their Google Account's address (any address; a Google Account doesn't need Gmail). Admins'
    Authentik emails stay as they are. The list of people stays out of this repo.
  - **Providers: Google only** (decided 2026-11-23): free, and the simplest to set up. Not now: Apple (needs a paid
    Apple Developer account, and can hide the email), Facebook (a Meta app in Live mode), Plex (can admit only
    accounts our Plex server is shared with).
  - **MFA** (decided 2026-11-23): Google logins rely on Google's own sign-in security, with no Authentik MFA on
    top. **Admins never log in with Google**, only with their password and a YubiKey (the exception to L5e's MFA
    for every account).
  - **Microsoft 365 isn't used for user logins** (decided 2026-11-23): removed from Audiobookshelf at its switch.

Settled 2026-11-20: Terraform state (local, with a 1Password copy), guest patching (automatic security updates,
the rest weekly), mgmt back to `/24`, three zones (mgmt VLAN 10, Services VLAN 100, DMZ VLAN 200), the archived
address scheme with the tier codes reconciled, guest types (LXC for native services, a Docker host VM per zone,
GPU VMs), two Traefik instances, Authentik in Services, YubiKey break-glass.
