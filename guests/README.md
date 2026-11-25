# Guests (L5): design

Purpose: how PhoenixStack guests are placed on the network, created (Terraform) and configured (Ansible), and
the services built on them, one layer at a time (L5a groundwork, then L5b onwards). The host (L0–L4) is in
[../proxmox/README.md](../proxmox/README.md) and stays on `pve-bootstrap.sh`.

Status (2026-11-22): **L5a–L5e applied and checked**: DNS (`dns01`, `dns02`), PostgreSQL (`pgsql01`), the Docker host
and Services Traefik (`docker01`), Authentik (`authentik01`). [Household DNS](#household-dns) through Pi-hole is
rolling out. The topology diagram is [topology.html](topology.html) (published:
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
- **Authentik lives in Services.** The public Traefik asks it to log people in (forward-auth) through one allowed
  port; its server and database stay off the DMZ.
- **LAN and VPN clients** use the Services Traefik (`443` on `docker01`), and get names from the UDM, which forwards
  `int.phoenixstack.net` to Pi-hole ([Household DNS](#household-dns)). Admin machines ask Pi-hole directly.
- **Media files** stay on the NAS (mgmt): read-write for media management (`docker01`), read-only for the media
  server (`plex01`) and the public apps (`docker02`). Mounted inside those VMs, not bind-mounted from the host.

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
| When | Nightly at **00:30**, systemd timer `db-dump.timer` (`Persistent=true`: a run missed while the guest was off happens at boot). | Before `nightly-pbs` (01:00) and `nightly-nas` (03:30), so both carry that night's dumps. |
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

| From | To | Allow (design) | Today (UniFi export, 2026-11-22) |
| --- | --- | --- | --- |
| Internet | DMZ | Port forwards only: `443` → `docker02`, `32400` → `plex01`, game ports → `amp01` | `443` → `docker02` since 2026-11-24 (Cloudflare only, port `443` only; the `8443` test forward deleted). `32400` and game ports still go to mgmt (REBUILD_STATE item 7) |
| LAN and VPN clients | Services | `443` → `docker01`. DNS goes through the UDM ([Household DNS](#household-dns)), so no `53` | Not yet: with the first app for household users |
| LAN and VPN clients | DMZ | Nothing (decided 2026-11-23): public names resolve to Cloudflare, so home users come in through the proxy like everyone else, and `docker02` accepts only Cloudflare | As designed (`Internal -> DMZ (Block)`, `VPN -> DMZ (Block)`) |
| Admin sources | Services, DMZ | SSH (`22`) and each guest's admin page | **All ports** (`Young/Porter/VPN Admin -> Services/DMZ`); narrow to the design once the services settle |
| Admin sources | Management | As today (pve01's own firewall also limits to admin sources) | All ports |
| Services, Management, IOT | The UDM itself (Gateway) | DNS (`53`), DHCP (`67`), ping | As designed. The block rules after them match `New` and `Invalid` connections only (since 2026-11-22), so replies to queries the UDM sends itself (its forwarding to Pi-hole) get back |
| Services, DMZ | Internet | Allowed (updates, Plex, game server lists) | Allowed |
| DMZ `docker02` | Services | Authentik's port on `authentik01` (its login pages, forward-auth) | `9443` to `authentik01` (`docker02 -> authentik01`, 2026-11-23) |
| DMZ `docker02` | Management | NAS file sharing (`445`) to `10.101.0.101`, as its own NAS user, read-only on `Media` ([Moving the public apps](#moving-the-public-apps)) | `docker02 -> NAS (SMB)` (2026-11-23); only `445` answers (checked) |
| DMZ `docker02` | docker-temp (Management), **temporary** | The ports of docker-temp's public apps while they move one by one; goes with the last (Step B) | `docker02 -> Docker-Temp (temporary)` (2026-11-24): TCP `2283`, `8081`, `9925` (`83` and `5054` removed 2026-11-24: Audiobookshelf moved, MyBibliotheca deleted; checked closed from `docker02`) |
| DMZ `plex01` | Management | NAS file sharing (`445` or NFS) to `10.101.0.101`, read-only share access | Not yet (no `plex01`) |
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
| First login | Terraform puts Aaron's SSH public key in the guest (container root, or the cloud-init user on VMs). The first `base` run creates user `aaron` (sudo, key only) and sets `PermitRootLogin no`. Later runs connect as `aaron`. | Named admin account; root only during the first run. |
| Host keys | Checking stays on, with `StrictHostKeyChecking=accept-new`. A rebuilt guest's old key is removed by hand. | The archive turned host key checking off. |
| Secrets | 1Password, read on the admin machine with `op read` (Ansible's `pipe` lookup), only when a guest needs a secret it doesn't have yet: a new resolver's web password, a new database role, Traefik's Cloudflare token, Authentik's `.env`. Dry runs never read secrets. **No Ansible Vault files.** | The archive committed Vault files to a public repo. |
| `base` role | A first full upgrade (new guests only), admin user `aaron` (key only, sudo without a password), root SSH login off, time zone, journal cap 200 MB, automatic Debian security updates without reboots (see [Guest patching](#guest-patching)); on VMs also the QEMU guest agent, time sync (`systemd-timesyncd`), no LLMNR or mDNS (systemd-resolved; names come from Pi-hole only), and SSH host keys kept through cloud-init changes (`ssh_deletekeys: false`, set after the first boot made the VM's own keys). | The same baseline on every guest. |
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
| The UDM's IPS blocked repeated SSH from the home LAN | IPS Detection Exclusions for the Young admin workstation and laptop; the Porter ones added 2026-11-23 (REBUILD_STATE item 11) |
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
| Redundancy | **Accepted risk** (2026-11-21, Aaron): both resolvers are on pve01, so a pve01 reboot or failure takes DNS down. Off-host DNS will be a Pi-hole on the Porter network, later. | Covers guest maintenance now; host outages wait for the Porter instance. |
| Own resolver | `dns01` itself resolves through its gateway (`.254`), not through Pi-hole. | It still has working DNS for updates if Pi-hole is down. |

Steps (the [new guest checklist](#new-guest-checklist), each one dry-run first); specific to DNS:

1. 1Password: item `(Pi-hole) - DNS Admin` in `infrastructure` (generated, 16+ characters). The playbook reads it on a
   resolver's first run.
2. One resolver at a time: `tf plan` and `apply`, `apb site.yml -l dns01 -e ansible_user=root`, `apb dns.yml -l dns01`;
   then the same for `dns02`, and `dns.yml` once more on `dns01` so each knows the other's name.
3. Admin machines: DNS `10.101.1.21` and `10.101.1.22` on the home network's profile only (away from home they're out
   of reach). Done 2026-11-21 on Aaron's laptop (NetworkManager profile `Auto YOUNG`: `ipv4.dns`,
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
- [ ] After a pve01 reboot (next patch window): `dns01` starts first (`pct config 10201` shows `startup: order=1`).

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
- [ ] The next morning: a dump folder from 00:30 (`sudo -u postgres ls /var/backups/db-dump`).
- [ ] After a pve01 reboot: `pgsql01` starts after the DNS guests (`startup: order=2`).

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
| Database | `authentik` on `pgsql01` through `postgres.int.phoenixstack.net` (`pg_databases`, L5c), `sslmode=require`. | `require`, not `verify-full`: the server has Debian's self-signed snakeoil certificate. |
| Name | **`https://auth.int.phoenixstack.net`** (decided 2026-11-22): route `auth` on `docker01`'s Traefik (wildcard certificate) to `https://10.101.1.41:9443`; also `AUTHENTIK_WEB__BASE_URL`. | Authentik builds its links from the base URL; a future release requires it. |
| Traefik → Authentik | **HTTPS to Authentik's own self-signed certificate, not verified** (decided 2026-11-22): the route's `self_signed: true` adds a `serversTransport` with `insecureSkipVerify`. Firewall: `9443/tcp` from `10.101.1.101/32` only. Only `docker01` may set `X-Forwarded-For` (`AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS`), so Authentik logs real client addresses. | Encrypted on the wire; the firewall, not the certificate, decides who can talk to it. |
| Settings | Avatars as initials; error reporting and startup analytics off. | Nothing leaves the network that doesn't have to. |
| Secrets | `.env` on the guest (root, `0600`), written once from 1Password: `(Authentik) - Secret Key` (`433bhnakbk4j55mkyrtnv3uhce`), `(PostgreSQL) - authentik` (`b7ycchopd2lagrf3jg4samuk5q`), `(Authentik) - akadmin` (`gc5okp343bflwbgpv53o4ypm6i`, the bootstrap password). Later runs keep the file; a dry run doesn't read 1Password. | To rotate: change the item (and, for the database, `ALTER ROLE authentik PASSWORD`), delete `.env`, run again. A new secret key logs everyone out. |
| Admin | **`akadmin`** is break-glass only: both YubiKeys plus TOTP in Microsoft Authenticator on a phone, outside 1Password (decided 2026-11-22). **`aaron`** is the daily admin (group `authentik Admins`): both YubiKeys plus TOTP in 1Password. Devices are named after where they live ("TOTP Authenticator (MS Auth)", "TOTP Authenticator (1Password)"), so a lost phone or a 1Password compromise says which one to remove. | `akadmin` relies on 1Password only for its password; no single lost device locks either account. The YubiKeys are the phishing-resistant factor, which matters once the public Traefik sends internet users to Authentik. |
| Last resort | Both of `akadmin`'s factors lost: on `authentik01`, `sudo docker exec authentik-server-1 ak create_recovery_key 10 akadmin` prints a one-time login link, valid for 10 minutes (the number is minutes). Then enrol new factors. | SSH to the VM doesn't depend on Authentik. |
| MFA | **Required for every account** (decided 2026-11-22): the login flow accepts WebAuthn (YubiKey, passkey) or TOTP, and an account without either must enrol one before it can finish logging in. Set by our blueprint `roles/authentik/templates/blueprints/phoenix-mfa.yaml.j2`, mounted read-only at `/blueprints/custom`; Authentik re-applies it hourly, so a change by hand in the UI is put back. Exception (decided 2026-11-23, open decision 12): users who log in with Google rely on Google's own sign-in security; admins can't log in that way. | The default skipped MFA for accounts without a device. Static codes, Duo, SMS and email aren't offered: SMS and email are the weakest second factors. |

Steps (the [new guest checklist](#new-guest-checklist), each one dry-run first):

1. 1Password: the three items above (created 2026-11-22).
2. `pg_databases` and `5432` from `.41` on `pgsql01`, `postgres` in `dns_records`: `tf apply`, `apb database.yml -l pgsql01`.
3. `tf plan`: expect only `authentik01` and its firewall. Then `apply`.
4. `apb site.yml -l authentik01`; reboot if the first upgrade asks.
5. `apb authentik.yml -l authentik01` (one 1Password approval; the first start migrates the database, a few minutes).
6. Route `auth` on `docker01`: `apb docker.yml -l docker01`.
7. `apb dns.yml -l dns02`, then `-l dns01` (names `authentik01`, `auth`, `postgres`).
8. UniFi alias; docs.
9. First login as `akadmin` (password from 1Password): two YubiKeys and TOTP in Microsoft Authenticator; then `aaron` with the YubiKeys and 1Password TOTP.

Done when:

- [x] `terraform plan`: no changes. Repeat runs `changed=0`: `site.yml`, `authentik.yml` (`authentik01`), `docker.yml` (`docker01`), `database.yml` (`pgsql01`). Root SSH refused.
- [x] `pgsql01`: database `authentik` UTF8, owner `authentik`, no `CONNECT` for `PUBLIC`; role password stored as SCRAM. Authentik connects over TLS 1.3 with SCRAM through the `hostssl` line.
- [x] Server and worker `healthy`, as UID 1000 with all capabilities dropped and no Docker socket; no errors after the start; the base-URL warning gone.
- [x] From the laptop: `https://auth.int.phoenixstack.net/` redirects to the login flow (`200`), Let's Encrypt wildcard verifies; `9443` on `authentik01` doesn't answer. Authentik logs the laptop's own address (`10.1.1.169`).
- [x] `auth`, `authentik01` and `postgres` resolve on both resolvers.
- [ ] UniFi alias for `authentik01`.
- [x] MFA required: blueprint `PhoenixStack - MFA required` applied (`successful`); the MFA stage is `configure` with WebAuthn and TOTP only.
- [x] A test account without a device (`mfatest`) was made to enrol one at its first login, offered WebAuthn and TOTP; deleted afterwards (2026-11-22).
- [x] `akadmin`: two YubiKeys and "TOTP Authenticator (MS Auth)"; `aaron` (authentik Admins): two YubiKeys and "TOTP Authenticator (1Password)" (checked in the database 2026-11-22).
- [ ] After the next 00:30 dump: `authentik.dump` in the day's folder on `pgsql01`.
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
it in the UI. Apps with their own login (OIDC, e.g. Immich, Grafana) are a different provider type, added with the
app.

Checked 2026-11-22 for the Traefik dashboard: without a login, the page and its API redirect to Authentik; a
forged `X-Forwarded-Host` is ignored; a non-admin source still gets `403` from the allow-list; `aaron` logs in with
a YubiKey and reaches the dashboard; a test user outside `authentik Admins` (`nogroup`, enrolled TOTP as required)
got Authentik's access-denied page, then was deleted.

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

After any restore: log in as `aaron` with a YubiKey; check **Customization → Blueprints** shows `PhoenixStack - MFA required`
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
   accept the self-signed certificate): `aaron` with password and **TOTP** (YubiKeys can't work on `localhost`, see
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

**Step A done 2026-11-23** (all checks below). Step A of moving the public apps off docker-temp: the host, the public
Traefik and Authentik's public name, proven with a test route on a second port. Step B (later) moves the `443`
forward from docker-temp to `docker02`; see [Moving the public apps](#moving-the-public-apps).

| Area | Decision | Why |
| --- | --- | --- |
| Guest | `docker02`: VM `11002`, MAC `02:aa:bb:cc:10:02`, `10.101.2.102`, DMZ (VLAN 200), cloned from `10001`. **8 cores, 16 GiB, 128 GB** on `nvme` (decided 2026-11-23; 64 GB until the podcasts, Step B). | Tier 10, instance 2. Less memory than `docker01` to start; Immich's machine learning is the big one, and memory and disk grow online. |
| Docker | Role `docker_host`, the same as `docker01` (Docker CE, `live-restore`, `no-new-privileges`, `local` logs, `172.20.0.0/14`). | One way to run Docker. |
| Traefik | Role `traefik`, the same version. Port 443 only. Routes from the inventory, file provider, no Docker socket. | As on `docker01`; the socket would be root on an internet-facing host. |
| Certificate | **Cloudflare Origin CA** (decided 2026-11-23): `phoenixstack.net` and `*.phoenixstack.net`, made once in the Cloudflare dashboard (SSL/TLS → Origin Server), 15 years. Certificate and key in 1Password; the first real run writes them to `secrets/` on the guest (root, `0600`). The zone's SSL mode must be **Full (strict)**. | No Cloudflare API token on the internet-facing host. Only Cloudflare needs to trust this certificate, since every request comes through its proxy. |
| Who may connect | `443` from **Cloudflare's addresses only**, on the UDM forward and again on the Proxmox firewall (new firewall source `cloudflare`, the list from cloudflare.com/ips in the inventory); SSH and ping from admin sources. | Two locks, as for pve01. Nobody can skip the proxy, not even from the LAN. |
| Client addresses | Traefik trusts `X-Forwarded-For` from Cloudflare's addresses only (`forwardedHeaders.trustedIPs`). | Apps and logs see the real client, not Cloudflare. |
| Route names | Each Docker host gets a `routes_domain`: `int.phoenixstack.net` on `docker01`, `phoenixstack.net` on `docker02`. Pi-hole adds names only for the `int.` routes. | Public names come from Cloudflare's wildcard record; Pi-hole must not answer them. |
| Authentik | Route `auth` on `docker02` → `https://10.101.1.41:9443`, so **`https://auth.phoenixstack.net`** works from anywhere. The admin interface (`/if/admin/`) is blocked on the public route, so it stays LAN and VPN only (decided 2026-11-23). | Users outside need the login page for OIDC. Admins don't need the admin pages from the internet. |
| Authentik's base URL | **`https://auth.phoenixstack.net`** (decided 2026-11-23; was `auth.int`), so OIDC issuers and links work from anywhere. `auth.int` stays as a LAN and VPN entry. | The public apps' OIDC clients must reach the same issuer from home and away. |
| UDM rules | Forward `8443` → `10.101.2.102:443`, Cloudflare's addresses only, for the test (Cloudflare proxies `8443`). `docker02` → `authentik01` `9443`. `authentik01`'s firewall also accepts `9443` from `docker02`. | Tests the whole path without touching the live `443` forward. |
| DNS | Nothing new: the zone's proxied wildcard record already sends every name to the home address. DMZ guests ask the UDM. | |
| Smoke test | `whoami` at `https://whoami.phoenixstack.net:8443` while its route is in the inventory. | Shows the client address Traefik sees (should be the tester's, not Cloudflare's). |
| Not in this step | Moving the `443` forward; any app; the NAS mount; where each public app runs. | Step B. |

Steps (the [new guest checklist](#new-guest-checklist), each one dry-run first):

1. ~~Roles: `traefik` gets the Origin CA option, trusted Cloudflare addresses and `routes_domain`; Terraform the
   `cloudflare` firewall source; the Pi-hole template skips non-`int.` routes.~~ Written 2026-11-23, with `docker02`
   in the inventory. Checked: `docker.yml -l docker01 --check --diff` changes only a comment and adds the unused
   `deny-all` middleware (`traefik.yml` and the routes render as before); `docker02`'s files render with the Origin
   CA and Cloudflare as trusted proxies; Pi-hole's list gains only `docker02` (not its public routes). The
   Authentik base URL change waits for step 6.
2. ~~Cloudflare: check the SSL mode is Full (strict); create the Origin CA certificate; store it in 1Password.~~
   Done 2026-11-23: SSL mode changed from Full to **Full (strict)**; 1Password `(Cloudflare) - Origin CA Certificate`
   (`lztixhdcrujfgcjpqkqnzq2kym`) holds two files, `origin-cert.pem` and `origin-key.pem` (ECC, valid until
   2041-11-19). Files, not fields: 1Password's concealed fields turn PEM line breaks into spaces.
3. ~~`tf plan`: expect `docker02` and its firewall, and `authentik01`'s firewall. Then `apply`.~~ Applied 2026-11-23
   (4 added; changed: `authentik01`'s firewall and `docker01`'s description).
4. ~~`apb site.yml -l docker02`; reboot if the first upgrade brought a new kernel; `apb docker.yml -l docker02`.~~
   Done 2026-11-23 (rebooted to 6.12.118); repeat runs `changed=0`; `dns.yml` on both resolvers adds the name
   `docker02` only. On the guest: Origin CA certificate served, `whoami` answers, `/if/admin` → `403`, unknown
   name → `404`, `auth` → `504` until the UDM rule (step 5).
5. ~~UniFi: the `8443` forward and the `docker02` → `authentik01` rule.~~ Done 2026-11-23: forward
   "Cloudflare - 8443 (docker02 test)" from the "Cloudflare IPv4 Ranges" group (the same 15 ranges); rule
   `docker02 -> authentik01` (DMZ → Services, TCP `9443`; first set with source port `9443` too, which matched
   nothing).
6. ~~Authentik: trusts `docker02`'s Traefik for `X-Forwarded-For`.~~ Applied 2026-11-23. **The base URL moves to
   `auth.phoenixstack.net` with the `443` forward (Step B):** until then that name on `443` still goes to
   docker-temp (Cloudflare `520`), and Authentik's links would point there.

Done when:

- [x] `tf plan` and repeat Ansible runs: no changes (2026-11-23).
- [x] From outside (phone on mobile data, 2026-11-23): `https://whoami.phoenixstack.net:8443` answers with
      Cloudflare's edge certificate and shows the phone's address; `https://auth.phoenixstack.net:8443` shows the
      login page; `/if/admin/` there is refused.
- [x] Direct to the home address on `8443` without Cloudflare: no answer (2026-11-23).
- [x] `docker02` can't reach Services except `authentik01:9443`, nor mgmt or the client LANs (checked 2026-11-23:
      13 targets; only `authentik01:9443` open, the UDM's admin page closed too).
- [x] Through Cloudflare on `8443` (2026-11-23, from the LAN): `whoami` answers, `auth` shows the login flow,
      `/if/admin/` → `403`; the home address on `8443` without Cloudflare: no answer. Still to do from a phone on
      mobile data (done, above). `X-Forwarded-For` starts with the visitor's address; `X-Real-Ip` shows Cloudflare's.
- [x] From the LAN: `https://auth.int.phoenixstack.net` still works; the Traefik dashboard on `docker01` too (sends
      to the Authentik login).
- [x] `whoami` route removed (2026-11-23: container and route file gone, repeat run `changed=0`). The `8443`
      forward stays for now, to try each moved app on `docker02` before the `443` forward moves (Step B).

### Moving the public apps

Step B (designed 2026-11-23): the `443` forward moves to `docker02` first, then the public apps follow one at a
time, Audiobookshelf first. Until every public app has moved, the public Traefik forwards to docker-temp through a
temporary rule, so the internet stops reaching mgmt the day the forward moves.

| Area | Decision | Why |
| --- | --- | --- |
| Where | Every public app runs on **`docker02`** (decided 2026-11-23). | A broken app reaches only the DMZ. |
| Databases | Each app keeps its own, inside its stack on `docker02`: SQLite (Audiobookshelf, Mealie), Immich its own PostgreSQL. **No PostgreSQL guest in the DMZ and no way to `pgsql01`** (proposed 2026-11-23). | No public app would use a shared one, and it would put every public app's data where any of them could reach it. |
| NAS | **Read-only** (decided 2026-11-23), mounted inside `docker02` at `/mnt/nas/media` by the role `nas_mount` (below) as its own NAS user **`svc_docker02`**, read-only on `Media` (1Password `(UNAS) - svc_docker02`, `cxeg5kim7a3wfgxhhs4najt4ye`). UDM rule `docker02 -> NAS (SMB)`: TCP `445`, to the NAS only. The same paths inside the containers as on docker-temp. | The UNAS sets permissions per share, not per folder. The DMZ's only way into mgmt: SMB, to the NAS. |
| Podcasts | **A NAS share of their own, `Podcasts`** (decided 2026-11-24; was `docker02`'s own disk, decided 2026-11-23): 32 GB of mostly complete archives, growing. `svc_docker02` may read and write it (only it), mounted at `/mnt/nas/podcasts` for Audiobookshelf's uid `2001` only (`nas_mount`: `rw: true, owner: 2001`). The share reports 94 GB. Disk stays 128 GB. | They need writing, and `Media` stays read-only. On the disk they'd go into every nightly guest backup. The DMZ's only write to the NAS: one share, of data that can be downloaded again. |
| App backups | Each app's own backups stay on `docker02` (Audiobookshelf: `/metadata/backups`); the nightly guest backups carry them off (proposed 2026-11-23). | On the NAS they'd need the `Backups` share, which also holds pve01's guest backups. |
| Immich | Needs a writable share of its own (uploads, thumbnails, encoded video, below). Designed with its move. Until then its files sit in `Media`, which `docker02` can read (accepted, below). | `Media` stays read-only. |
| `8443` forward | Deleted when `443` moved (2026-11-24). From then on, a moved app is tried under a temporary name on `443`. | |
| Admin tools | Not reachable from outside once `443` moves (LAN and VPN only, decision 3). Until they're on `docker01`, admins use docker-temp's address and port. | |

Steps (each dry-run first):

1. ~~**Prepare** (nobody notices)~~ Done 2026-11-23: `docker02`'s disk 128 GB (root filesystem 126 GB, grown with
   `sudo growpart /dev/sda 1 && sudo resize2fs /dev/sda1` after `tf apply`); the NAS user and its 1Password item;
   the UDM rule `docker02 -> NAS (SMB)` (by Aaron); the mount role, applied and checked (below); Audiobookshelf's
   backups working again on docker-temp, and one made by hand (a copy also on Aaron's laptop).
2. ~~**Move the `443` forward:** a route on `docker02` for each public app, pointing at docker-temp for now; the
   temporary rule `docker02` → docker-temp, those ports only; Authentik's base URL → `auth.phoenixstack.net`; the
   forward → `docker02`, Cloudflare only; the `8443` forward deleted. Test every public name from a phone on mobile
   data.~~ Done 2026-11-24 (below).
   - 2026-11-24: rule in place; routes `abs` (83), `immich-p` (2283), `meal` (9925), `tools` (8081), `bibliotheca`
     (5054) on `docker02`, applied. Through Cloudflare on `8443`: all five answer, Audiobookshelf's `/ping` and
     socket, Immich's ping; other docker-temp ports stay closed to `docker02`. Not published after the switch
     (agreed): Calibre (its basic auth lived in docker-temp's Traefik) and `absdev`; admins reach them, and the
     admin tools, at `10.101.0.166:<port>`. Names kept as today (`immich-p`, `meal`, `tools`); each is renamed
     when its app moves.
   - 2026-11-24, the switch: Cloudflare's **Always Use HTTPS** turned on (it was off: plain `http://` reached the
     origin and failed with `522`) and SSL mode **Full (strict)**. UniFi forward "Cloudflare - 443" →
     `10.101.2.102:443`, port `443` only (`80`, `81`, `444` gone), Cloudflare's addresses only; the `8443` forward
     deleted. Authentik's base URL → `https://auth.phoenixstack.net` (applied, healthy).
   - [x] Through Cloudflare on `443` (from the LAN, IPv4): `abs` `/ping` and socket, `immich-p` ping, `meal`,
         `tools` → `200`; `bibliotheca` → its login page; `auth` → the login flow, `/if/admin/` → `403` (so it's
         `docker02` answering); `http://` → `301` to `https://`; `:8443` → `522`.
   - [x] Admin forward-auth on `docker01` (Traefik dashboard) still sends to `auth.int.phoenixstack.net`, where the
         YubiKeys are registered.
   - [x] From a phone on mobile data (Aaron, 2026-11-24): the names in a browser, and the Audiobookshelf app.
   - 2026-11-24, later: **MyBibliotheca deleted** (Aaron undecided whether to keep it; if so, rebuilt from scratch).
     On docker-temp: container, image, `appdata/bibliotheca` (1.2 GB), its compose file and `include` line, its
     Traefik rule, its three `.env` lines, the empty backups folder; the rest of docker-temp checked (compose file
     parses, 19 containers up). Route `bibliotheca` removed from `docker02` (now `404`). `5054` out of the
     temporary rule (Aaron). DNS: `bibliotheca` resolves only through the `*.phoenixstack.net` wildcard (a
     made-up name gets the same answer); Cloudflare lists no record of its own (Aaron: wildcard only).
3. ~~**Move Audiobookshelf** (the pilot, below).~~ Done 2026-11-24 (evening, Denver; 01:47–01:50 UTC on the 25th):
   - Role **`apps`** (new, in `docker.yml` after `traefik`): one compose stack per app in `/opt/stacks/<app>`, listed per
     host in the inventory (`apps: [audiobookshelf]`), settings in `roles/apps/defaults/main.yml`; Traefik reaches it
     over the `proxy` network (route `abs` → `http://audiobookshelf:80`). Runs as uid `2001` (no account on the
     host; uid 1000 is `aaron` there), no capabilities, healthcheck on `/healthcheck`.
   - Image `2.37.2` pinned: the same digest docker-temp ran as `latest` (`b897c33f…`).
   - Podcasts: on docker-temp they were on the NAS (`Media/Podcasts`), not local. Copied from the NAS by `docker02`
     itself (32 GB, 513 files, 193 s), then the files changed since, at the switch. The same evening (decision
     above), moved again to the new share `Podcasts` (copy 390 s while it ran; the switch 02:16–02:17 UTC, 44 s):
     healthy, 513 files, `/podcasts` writable. The local copy deleted after Aaron's test, and the frozen
     `Media/Podcasts` on the NAS (Aaron).
   - The switch: Audiobookshelf stopped on docker-temp (`docker stop`, so it stays stopped after a reboot);
     `config` (32 MB) and `metadata` (776 MB) streamed docker-temp → laptop → `docker02` (`tar` over SSH; no rsync
     on `docker02`); `apb docker.yml -l docker02` started it and moved the route. Offline about 2 minutes.
   - [x] Through Cloudflare: `/ping`, `/healthcheck`, `/status` (`2.37.2`), the socket. Container healthy, no
         restarts; database "already up to date" (no migration); 372 entries in `/audiobooks` (read-only: writing
         fails), 5 podcasts; its backups came along in `/metadata/backups`.
   - [x] Aaron (2026-11-24): logged in on the web and in the phone app, played, progress kept.
   - Library scans: Audiobooks nightly at midnight (`0 0 * * *`, set by Aaron 2026-11-24; the watcher can't see
     what Libation writes over SMB). Containers run on local time since the same evening: `TZ` from the inventory's
     `timezone` (`America/Denver`) in the apps' and Traefik's compose files, so that midnight, and the 01:30
     backup, are Denver time (they were UTC). Not Authentik: its documentation says to keep its containers on UTC.
   - **Rollback:** `docker start audiobookshelf` on docker-temp and the route `abs` back to `http://10.101.0.166:83`;
     anything since the switch is lost. docker-temp's copy stays until Audiobookshelf is checked on `docker02`.
   - `83` out of the temporary UDM rule (with `5054`; Aaron, 2026-11-24, checked closed). `absdev` stays on
     docker-temp, offline from the internet (agreed).
4. ~~**Its logins to Authentik**, separately, once it runs well on `docker02` (open decision 12). Rehearsed first on
   its staging copy (below).~~ Done 2026-11-24 (Denver evening; 03:48 UTC on the 25th, 14 s offline):
   - Authentik: OIDC client `abs` from the route's `oidc` entry on `docker02` (`authentik Admins`, `Family`).
   - Audiobookshelf (stopped, database copied first to `/opt/stacks/audiobookshelf/rollback/`, root only):
     Microsoft 365's 4 links and its settings removed; `Aaron Young`'s email → his Authentik address
     (his work address); OpenID → Authentik as on staging (client `abs`, match by email, no auto-register, button
     "Sign in with PhoenixStack"); local login kept. Healthy; the button leads to Authentik's login page.
   - Still to do (Aaron): each person's Authentik user (clean username, email = their Google address, group
     `Young` or `Porter`), checking their Audiobookshelf email matches (the list of accounts is on Aaron's laptop,
     not in this repo); Microsoft 365's app registration for Audiobookshelf deleted in Entra.
   - Staging deleted the same night (it had done its job): inventory entries, its route and DNS name, the
     `abs-staging` client and app in Authentik (a blueprint doesn't delete what it created), the stack, its data
     and image on `docker01`.
   - **Rollback:** stop Audiobookshelf, put the copy back as `config/absdatabase.sqlite` (owner `2001`), start.
5. The other public apps, one at a time. The temporary rule loses each app's port; it goes with the last.

### Staging

Decision 11's app staging, built with Audiobookshelf on 2026-11-24 (Denver evening): **`abs-staging.int.phoenixstack.net`**
on `docker01`, admin sources only, version `2.37.2` (production's, for now: the first use is rehearsing step 4).
Deleted the same night after the rehearsal; the design and steps below are for the next one.

| Area | Design (2026-11-24) | Why |
| --- | --- | --- |
| Where | `docker01` (Services), LAN and VPN only, `admin_only` route. In the inventory: `apps_staging: [{app, version}]` on `docker01`; role `apps` deploys stack `<app>-staging` from the same template (`stack.staging`). | Never public; the same template as production, so staging tries what production will run. |
| Data | Restored from production's **latest backup**, by hand, before the first start (so no empty instance is ever reachable). | Decision 11. Production's data is never touched. |
| Getting the backup there | Through the laptop: `docker02` → laptop → `docker01` over SSH. | Services can't reach the DMZ; no new firewall rule. |
| Media | **None yet** (Aaron, 2026-11-24): `docker01` has no NAS access. `/audiobooks` and `/podcasts` are empty, read-only folders: books show, nothing plays. Media comes when `docker01` gets the NAS (the *arr apps need it), before the first version upgrade is tested there. | Enough for logins; no new NAS user or rule now. |
| Side effects | Switched off in the copy's database before it starts: podcast auto-download, the nightly backup, the folder watcher. Email settings kept (sending only on a user's action). | A copy must not download, write backups or act on its own. |
| Scrubbing | None: the copy holds the 34 accounts and their history, admins only. | It's deleted after use. |
| Lifetime | **Temporary.** Built for a test, deleted (`apps_staging` entry, route, `dns.yml`, then `/opt/stacks/<app>-staging`) once the change is in production. | Nothing to patch or keep in step in between. |
| Logins | Its own OIDC client in Authentik when step 4 is rehearsed (redirect `abs-staging.int…`). Sessions copied from production stay valid here (same signing key). | Production's client never points at staging. |

Restore (Audiobookshelf; dry runs first):

1. `apb docker.yml -l docker01 --check --diff` with the `apps_staging` entry and the `abs-staging` route.
2. Before applying, the latest backup (`/opt/stacks/audiobookshelf/metadata/backups/*.audiobookshelf` on `docker02`)
   through the laptop to `docker01`, unpacked into `/opt/stacks/audiobookshelf-staging` as Audiobookshelf restores
   it: `absdatabase.sqlite` → `config/`, `metadata-items/` → `metadata/items/`, `metadata-authors/` →
   `metadata/authors/`; owner `2001`, folders `0750`.
3. In the copy's database: `podcasts.autoDownloadEpisodes` 0; `server-settings`: `backupSchedule` false,
   `scannerDisableWatcher` true.
4. `apb docker.yml -l docker01`, then `apb dns.yml -l dns01` and `-l dns02` (one at a time; `dns.yml`'s dry run
   can't show the names: the Pi-hole role applies its settings only for real).

- [x] 2026-11-24: backup `2026-11-25T0130` (made on docker-temp, `2.37.2`) restored: database 32 MB, metadata
      189 MB. Started healthy, quiet log (no downloads, backups or scans); both resolvers answer; `/ping`, `/status`
      over HTTPS from the laptop.

Step 4 rehearsal on staging (2026-11-24, Denver evening):

- Authentik, as code (role `authentik`): blueprint `PhoenixStack - People and Google sign-in` (groups `Family`,
  `Young`, `Porter`; Google source, `email_link`, no enrollment flow; its own login flow
  `phoenix-source-authentication` in "all" mode: from Google **and** not in `authentik Admins`; the Google button
  on the login page) and `PhoenixStack - OIDC apps` (an OIDC client per route with `oidc` in the inventory;
  Authentik generates the secret; a scope mapping that sends `email_verified: true`, which Authentik's own doesn't).
  Google's client in `.env.google` (root only), from 1Password `(Google Cloud) - Authentik sign-in`.
- Lessons: Authentik's default source flow runs in "any" mode, so a policy added there doesn't block anyone (hence
  the own flow); a blueprint's OAuth2 provider needs `grant_types` listed (empty otherwise: "Invalid grant_type",
  shown by Audiobookshelf as "Error in callback"); Audiobookshelf accepts return URLs only under
  `/audiobookshelf/`.
- Staging Audiobookshelf: Microsoft 365's settings and its 4 links removed; OpenID → Authentik (issuer
  `https://auth.phoenixstack.net/application/o/abs-staging/`, client `abs-staging`, secret piped from Authentik,
  never shown), button "Sign in with PhoenixStack", match existing users by **email**, no auto-register; local
  login kept.
- [x] Admin path: `aaron` (password + TOTP; YubiKeys are registered on `auth.int`) → his Audiobookshelf account,
      once its email matched (it was a different address: "User not found", then "Unauthorized").
- [x] Google path (a non-admin user), the admin block on Google, the phone app over VPN (Aaron, 2026-11-24: successful).

The NAS mount (role `nas_mount` in `docker.yml`, for hosts with `nas_mounts`; **applied 2026-11-23**):

- `cifs-utils`; `/etc/nas/credentials` (root, `0600`): the NAS user, and its password read once from 1Password.
  Per share a systemd `.mount` and `.automount` unit (`mnt-nas-media`). Options: `ro`, SMB `3.1.1`, `soft`, files
  `0444` and folders `0555` for everyone, `noexec,nosuid,nodev`; a mount attempt gives up within 30 s.
- Mounted on first use, then kept. The guest boots without the NAS, and a container that starts while the NAS is
  away fails to start rather than finding an empty folder.
- **What `docker02` can read:** all of `Media`, since the NAS sets permissions per share. That includes
  `Media/Immich` (the Porter household's photos, thumbnails, encoded video and Immich's database backups) and the
  download folders. A container sees only the folders mounted into it; whoever controls the host sees all of `Media`.
  **Accepted until Immich moves** (decided 2026-11-23): Immich's data then goes to a share of its own and leaves
  `Media`, and Immich on `docker02` holds that data anyway. Narrower later: a `Books` share instead of `Media` for
  `docker02`, with Calibre's redesign.
- To rotate the password: change it on the NAS and in 1Password, delete `/etc/nas/credentials`, run
  `apb docker.yml -l docker02`; stop the apps using the share, `sudo systemctl stop mnt-nas-media.mount`, start
  them again (the share mounts again on first use).

Done when (all checked 2026-11-23):

- [x] Applied to both Docker hosts (`docker02`: the role's six changes; `docker01`: nothing from it); a repeat run
      `changed=0` on both.
- [x] NAS away (the UDM rule already existed, so a temporary block on `docker02` itself): `ls /mnt/nas/media` fails
      after 10 s with "No such device"; a container with a folder from the share refuses to start; nothing is
      created under the mount point. Unblocked, the share mounts on first use.
- [x] `ls /mnt/nas/media/Books/Audiobooks` lists the books (372 entries); `touch` there: "Read-only file system".
- [x] The NAS refuses `svc_docker02` too: on a test mount of `Media` with `rw`, a write gets "Permission denied";
      `Backups` and `Porter` can't be mounted ("Permission denied").
- [x] From `docker02`, the NAS answers on `445` only (`22`, `80`, `139`, `443`, `8443`, `9443`: no answer).
- [x] After a reboot of `docker02`: the automount is active, the share mounts on first use, Traefik is up.

Moving Audiobookshelf without listeners noticing:

- **Same version** (`2.37.2`, pinned) and **the same paths inside the container** (`/config`, `/metadata`,
  `/audiobooks`, `/podcasts`): its database stores file paths. Upgrades come afterwards, through staging (decision 11).
- **Before:** on docker-temp, the libraries' "store covers with item" off (new covers go to `/metadata`; existing
  ones stay readable; **done 2026-11-24** by Aaron). Copy `/metadata` (409 MB then; 776 MB at the move) and the podcasts to `docker02` while
  it runs.
- **The switch**, about five minutes in the quietest hours (08:00–12:00 UTC, 01:00–05:00 in Denver, over the last 60
  days): stop it on docker-temp; copy what changed in `/config`, `/metadata` and the podcasts; start it on `docker02`
  and check; point the route `abs` at it.
- **Users:** the database carries the accounts, progress, bookmarks, the key that signs logins and every phone's
  login, so nobody logs in again. Phones keep playing from their buffer and sync progress when the server answers.
- **Library scans on a schedule:** the folder watcher can't see files that other machines write over SMB (Libation).
- **Rollback:** point the route back at docker-temp and start it there; anything since the switch is lost.

docker-temp today (read 2026-11-23): Deployrr layout in `~/docker` (one compose file including one file per app,
`appdata/`, Traefik 3.6 with file rules in `appdata/traefik3/rules/docker-temp/`, basic auth on the admin tools).
Its Traefik has internal (`80`/`443`) and external (`81`/`444`) entry points, but the UDM forwards the internet's
`443` to the internal one, so LAN-only routes (e.g. glances) answer from outside, behind basic auth. Fixed the
same day: `8080` (Traefik's dashboard and API without a login, `--api.insecure`) taken out of the forward by
Aaron; checked closed through Cloudflare. Stale: the `amp` route (AMP-TEMP deleted).

Also found 2026-11-23:

- Audiobookshelf's nightly backups **fail** (`EACCES` on `/backups`, every night in its logs since at least
  2026-11-21): docker-temp's `/mnt/pve/cifs-backups` hasn't been a NAS mount since pve01's rebuild, just a folder.
  Its newest backup of its own is an older one in `/metadata/backups`. (MyBibliotheca's pointed at the same
  folder.) Fix before the move: backup location `/metadata/backups`, then a backup by hand. (docker-temp itself is in
  the nightly guest backups.) **Fixed 2026-11-23** for Audiobookshelf (by Aaron): location `/metadata/backups`, a
  backup made by hand, and a copy kept on his laptop.
- Audiobookshelf: 34 accounts; 14 listened in the last 90 days, 19 in the last year, 15 never.
- Immich (7 users, password logins) writes to the NAS: uploads (about 32,000 photos), thumbnails (30 GB), encoded
  video (44 GB) and its own database backups (6.6 GB), in `Media/Immich/Porter`. It also reads about 56,000 photos
  from the `Porter` share (`PhotoArchive`) as an external library. Server `v3.1.0` but machine learning `v2.5.3`:
  pin both to one version when it moves.

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
- [ ] A day later: Pi-hole's logs show the UDM's queries, and nothing broke for the household.

### Porter LAN

Started 2026-11-23: steps 1, 2 and 4 done, the tests (step 3) pending. The Porter gateway (a UDM, Ben's) gets the same forward as the Young UDM. Its queries
reach Pi-hole over the BPorter site-to-site tunnel, so this UDM needs one new rule. Only names under
`int.phoenixstack.net` change; every other lookup at Porter goes where it goes today. If pve01 or the tunnel is
down, only the `int.` names fail.

| Area | Decision | Why |
| --- | --- | --- |
| Porter UDM | Two DNS policies, **Forward Domain** `int.phoenixstack.net` → `10.101.1.21` and → `10.101.1.22`, as on the Young UDM. | The same setup at both sites; one place to turn it off. |
| Porter LAN DHCP | DNS server **automatic** (the gateway), domain name `int.phoenixstack.net`. Change only what differs: if DHCP already hands out the gateway, leave it. | Devices use the forward only if they ask the Porter UDM. Short names (`pve01`) need the domain. |
| Young UDM rule | **`Porter Gateway -> Pi-hole (DNS)`**: zone VPN → Services, source the Porter gateway's address, destination `10.101.1.21` and `10.101.1.22`, port `53`, UDP and TCP, before the zone's block rule. | VPN → Services is admin-only, and the gateway isn't an admin source. Port 53 only, to the two resolvers only. |
| Pi-hole firewall | Nothing new if the queries come from a `10.2.1.x` address: `dns01`/`dns02` already accept `53` from `lan` (includes `10.2.1.0/24`). If they come from the gateway's WAN or tunnel address, add that `/32` to their `firewall_in` (inventory) and run `tf plan`/`apply`. | Find out from Pi-hole's query log (step 3), not by guessing. |
| Admin machines | Ben's workstation (Windows) and laptop (macOS) keep hosts entries for `pve01` and its iDRAC (`10.101.0.11 pve01.int.phoenixstack.net pve01`, `10.101.0.1 idrac-pve01.int.phoenixstack.net`), so both still open by name when pve01, and with it Pi-hole, is down. The iDRAC matters most then. | The same fallback as Aaron's machines. |

Steps:

1. ~~**Young UDM:** add the rule `Porter Gateway -> Pi-hole (DNS)` (table above). Use the gateway's LAN address
   (`10.2.1.x`, from its Networks page) as the source first.~~ Done 2026-11-23.
2. ~~**Porter UDM:** add the two Forward Domain policies.~~ Done 2026-11-23.
3. **Test from the gateway's side before any device depends on it**, from Ben's workstation:
   `nslookup pve01.int.phoenixstack.net <Porter gateway address>`. Expect `10.101.0.11`.
   - Cloudflare addresses or a timeout: open Pi-hole's query log on `dns01`. No query from Porter means the rule or
     the source address is wrong: note the address the query came from on the Young UDM's traffic log, fix the
     rule's source (and the Pi-hole `firewall_in`, table above), and test again.
4. ~~**Porter LAN DHCP:** DNS automatic, domain `int.phoenixstack.net`, only if they differ today.~~ Done 2026-11-23.
   Devices switch as their leases renew (expect a mix until then).
5. Check with Ben the next day, then tick the list below.

Done when:

- [ ] Through the Porter gateway: internal names answer (`auth`, `pve01`, `idrac-pve01`) over UDP and TCP; an unknown internal name
      gets NXDOMAIN; public names resolve.
- [ ] Pi-hole's query log shows the Porter gateway's queries (and the source address is recorded above).
- [ ] Failover: with `dns01` stopped, names still answer through `dns02`.
- [ ] Ben's workstation and laptop: `pve01.int.phoenixstack.net` and `auth.int.phoenixstack.net` resolve;
      `https://pve01.int.phoenixstack.net:8006` opens without a certificate warning.
- [ ] A day later: nothing broke for the Porter household.

## Open decisions

1. ~~Cloudflare in front of the public web apps (proxy or tunnel), or DNS only?~~ Settled 2026-11-23: **proxy**, as
   today; the `443` forward accepts Cloudflare's addresses only. The public Traefik uses a **Cloudflare Origin CA**
   certificate, so no Cloudflare API token sits on the internet-facing host (a stolen zone token could redirect any
   name, mail included).
2. Plex, Jellyfin, or both?
3. Which docker-temp apps are public (to `docker02`) and which LAN and VPN only (to `docker01`)? Started 2026-11-23
   (not exhaustive). Public, for every user: Audiobookshelf, Plex, Immich, Mealie, IT-Tools, Calibre. MyBibliotheca: deleted 2026-11-24 (container, data, settings, route); if it comes back, a fresh install. Admins only
   (Aaron and Ben, for now): the *arr apps, libraforge, libation, metube, glances. These are **LAN and VPN only**
   (`<app>.int.phoenixstack.net` on `docker01`), reached from outside over Teleport, not published (decided
   2026-11-23). Plex keeps its own `32400` forward and plex.tv logins (no Traefik, no Authentik). Calibre: later,
   maybe a fresh design rather than a move. Not moved: the Audiobookshelf dev copy (`absdev`). Logins: each app's **built-in OIDC** with
   Authentik wherever it has one (as on docker-temp today), forward-auth only for browser-only apps without it.
   Authentik's public name: **`auth.phoenixstack.net`** (through the public Traefik). When Audiobookshelf moves,
   its existing users must carry over as seamlessly as possible (e.g. matching them to Authentik by username or
   email through OIDC claim mapping): design that with the move. Found 2026-11-23: Audiobookshelf has OIDC set
   up against **Microsoft 365** (Entra ID), switched off, with 4 users linked; Immich uses password logins (none
   linked); docker-temp has no Authentik. **Microsoft 365 isn't used for user logins** (decided 2026-11-23): its
   setup in Audiobookshelf and its app registration in Entra go when Audiobookshelf switches to Authentik
   (decision 12).
4. AI tier code (proposed 12, `.121`).
5. ~~A second Pi-hole off pve01~~ Settled 2026-11-21: `dns02` on pve01 for guest maintenance; off-host DNS will be a Pi-hole on the Porter network, later; until then a pve01 outage takes DNS down (accepted). Also settled: admin machines first, no ad blocking yet, recursive Unbound upstream (see L5b).
6. Monitoring (uptime and service alerts): which zone and when.
7. Hardware, not blocking: the 990 Pro drives and ASUS card (`data` pool) and the RTX 3070 aren't installed.
8. Authentik audiences (groups) for non-admin users. **Settled 2026-11-23: `Family`, with `Young` and `Porter` below
   it**, to start. The proposal (2026-11-22): groups
   describe people, not apps; nested households, `Family` with `Young` and `Porter` below it (a binding to a group
   also admits its child groups), plus outside audiences if needed (`Guests`?). Group definitions in a blueprint,
   memberships in the UI; routes get a list, `authentik_groups`. New users by invitation link or created by hand.
9. **Ad blocking**, together with the off-host Pi-hole at Porter (decided 2026-11-22: roadmap, not now). Household
   networks use the UDM, which forwards only `int.phoenixstack.net` to Pi-hole (LAN-wide DNS rollout, 2026-11-22),
   so a pve01 outage doesn't take the household's DNS down. Ad blocking needs Pi-hole to see every query: once the
   Porter Pi-hole exists, switch household networks to Pi-hole directly (DHCP DNS + a LAN → Services port 53
   rule), for per-device logs and blocklists. Networks that shouldn't depend on Pi-hole (IOT, guests) keep the UDM.
10. **SIEM / central logs** (roadmap 2026-11-22, after the core services; decide together with 6). Sources: the UDM's
   firewall log, pve01, guests' journals, Authentik events, Traefik access logs, Pi-hole queries. First decide the
   scope: log aggregation with alerts (e.g. Grafana + Loki, shared with monitoring) or a full SIEM (e.g. Wazuh:
   agents, detection rules, a search index, much heavier). Tier 08 (`.81`) is the monitoring tier. Until then logs
   stay local (guest journals capped at 200 MB).
11. **Testing before production** (decided 2026-11-23; pilot: Audiobookshelf). Image versions are pinned in git,
    so going to a new version is a change to its pin, tried somewhere else first. Two levels:
    - **App staging:** a copy of the app on `docker01` as `<app>-staging.int.phoenixstack.net` (LAN and VPN only,
      never public), on the candidate version, with a **copy** of production's data restored from its latest
      backup; it never touches production's data or database. Once it works, change the production pin in git
      and apply. In the inventory: a staging flag on the route, which the roles understand.
    - **Test guests:** for changes to roles, Terraform or a whole host, a throwaway guest in tier 99
      (`test01`/`test02`, as for L5a), built from a git branch with the same roles; merge, then destroy it.
    - Not a permanent second environment (a second `docker02`, a second Authentik): twice the patching, and it
      drifts from production.
    - Designed with the pilot (2026-11-24): see [Staging](#staging). Still to design there: the staging app's own
      OIDC client in Authentik (with step 4's rehearsal).
12. **Users log in with their Google account, through Authentik** (decided 2026-11-23). Authentik is the one place
    that says who a person is (username, email, groups); the Google account is only the key they prove it with,
    and the apps only ever see Authentik. Each person is created by hand (a clean username such as `aaron.young`,
    email = the address they sign in to Google with, group); their first Google login links to that user by email.
    No open sign-up: an unknown account gets nothing. Each app keeps one local admin (break-glass), and local logins
    for clients that can't do OIDC (e-readers, scripts) and for people without a Google Account (they keep their
    app username and password). **Audiobookshelf matches by email** (changed 2026-11-24 from "by username": its
    usernames are display names with spaces, which Authentik doesn't allow in usernames): each person's
    Audiobookshelf email must equal their Authentik email, and for Google users that's their Google Account's
    address (any address; a Google Account doesn't need Gmail). Admins' Authentik emails stay as they are (Aaron's:
    his work address; his Audiobookshelf email changes to it at the switch). Its 4 Microsoft 365 links
    are removed first, since it refuses a second link. Users can't change their own email in Authentik (off by
    default), so nobody can take over an unlinked account. The list of people stays out of this repo.
    - **Providers: Google only** (decided 2026-11-23): free, and the simplest to set up. Not now: Apple (needs a
      paid Apple Developer account, and can hide the email), Facebook (a Meta app in Live mode), Plex (can admit
      only accounts our Plex server is shared with).
    - **MFA** (decided 2026-11-23): Google logins rely on Google's own sign-in security, with no Authentik MFA on
      top. **Admins never log in with Google**, only with their password and a YubiKey (the exception to L5e's
      MFA for every account).

Settled 2026-11-20: Terraform state (local, with a 1Password copy), guest patching (automatic security updates,
the rest weekly), mgmt back to `/24`, three zones (mgmt VLAN 10, Services VLAN 100, DMZ VLAN 200), the archived
address scheme with the tier codes reconciled, guest types (LXC for native services, a Docker host VM per zone,
GPU VMs), two Traefik instances, Authentik in Services, YubiKey break-glass.
