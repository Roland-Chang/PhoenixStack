# Guests (L5): design

Purpose: how PhoenixStack guests are placed on the network, created (Terraform) and configured (Ansible).
This is **L5a**: the groundwork every service builds on. The first service on it is DNS (L5b, Pi-hole).
The host (L0–L4) is in [../proxmox/README.md](../proxmox/README.md) and stays on `pve-bootstrap.sh`.

Status: **L5a done 2026-11-21; L5b (DNS, `dns01`) applied and checked 2026-11-21.** Applied so far: mgmt back to `/24`, UniFi zones, the Terraform token narrowed to
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

| From | To | Allow |
| --- | --- | --- |
| Internet | DMZ | Port forwards only: `443` → `docker02`, `32400` → `plex01`, game ports → `amp01` |
| LAN and VPN clients | Services | `53` → `dns01`, `dns02`; `443` → `docker01` |
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
# Terraform: the wrapper reads the API token from 1Password and saves the state there after changes
tf plan        # guests/tf.sh, from any directory
tf apply

# Ansible: baseline first. The first run on a NEW container connects as root (VMs already have the admin user)
cd guests/ansible
ansible-galaxy collection install -r requirements.yml      # once
ansible-playbook site.yml -l dns01 -e ansible_user=root --check --diff
ansible-playbook site.yml -l dns01 -e ansible_user=root
# Then the service's own playbook, as the admin user (here: DNS, see L5b below)
ansible-playbook dns.yml -l dns01 --check --diff
PIHOLE_PASSWORD="$(op read 'op://infrastructure/6rgmkyk7enemcundji75k7omeu/password')" ansible-playbook dns.yml -l dns01
```

| Piece | Where | Notes |
| --- | --- | --- |
| Guest list | [inventory.yml](inventory.yml) | Read by both tools. `admin_sources` must match pve01's `ADMIN_SOURCES` and the UDM's Management rules. |
| Terraform | [terraform/](terraform/) | Provider `bpg/proxmox` pinned to `0.120.0` (released 2026-11-02); lock file committed. Each guest gets its MAC, VMID, VLAN, static IP and DNS servers, and a Proxmox firewall: inbound DROP, SSH and ping from admin sources, plus the guest's `firewall_in` rules. **Changing a guest's cloud-init settings (DNS servers, address) restarts it during `apply`**, and a VM's cloud-init then makes new SSH host keys: compare them through pve01 (`qm guest exec <vmid> -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`) before `ssh-keygen -R`. |
| Wrapper | [tf.sh](tf.sh) | Token from 1Password item `(Proxmox) - Terraform Token` (by item ID; update `TOKEN_REF` if the item moves). State saved to `infrastructure` / `(Terraform) - Guests State` after apply, destroy, import and state commands. |
| Ansible | [ansible/](ansible/) | `patch.yml` is the weekly patch run (see [Guest patching](#guest-patching)); it also checks the database dumps. `site.yml` runs the `base` role on every guest; each service has its own playbook (`dns.yml`, `database.yml`, `docker.yml`, `authentik.yml`), run after it as the admin user, because `base` turns root's SSH login off. `base` role: a first full upgrade (new guests only), admin user `aaron` (key only, sudo without a password), root SSH login off, time zone, time sync on VMs, journal cap 200 MB, automatic Debian security updates without reboots, QEMU guest agent on VMs. |

### New guest checklist

Every new guest, in this order (each Terraform and Ansible step dry-run first):

1. **Inventory:** one host entry in [inventory.yml](inventory.yml), addressed by the [scheme](#address-scheme)
   (MAC `02:aa:bb:cc:XX:YY`, VMID `1XXYY`, octet = code × 10 + instance).
2. **Terraform:** `tf plan` (only the new guest and its firewall), then `apply`.
3. **Baseline:** `apb site.yml -l <guest> -e ansible_user=root` (containers' first run only; VMs connect as the admin user).
   If the first full upgrade leaves `/var/run/reboot-required`, reboot the guest now (`ansible <guest> -m reboot`).
4. **Service:** the guest's own playbook (`dns.yml`, `database.yml`, `docker.yml`, `authentik.yml`, ...).
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
| The UDM's IPS blocked repeated SSH from the home LAN | IPS Detection Exclusions for the Young admin workstation and laptop (REBUILD_STATE item 11) |
| `/etc/systemd/journald.conf.d` doesn't exist on Debian 13 | The `base` role creates it |
| The Debian container template has systemd hold port 22 (`ssh.socket`), so reloading sshd stops it | The `base` role restarts sshd there and reloads it elsewhere |
| A dry run on a new container can't check the admin user's keys (the user isn't created yet) | Skipped in that one case |

## L5b: DNS (`dns01`, `dns02`)

**Applied 2026-11-21** and checked from the admin laptop (results below). Not in use by any client yet.

| Area | Decision | Why |
| --- | --- | --- |
| Guests | `dns01`: unprivileged LXC `10201`, MAC `02:aa:bb:cc:02:01`, `10.101.1.21`. `dns02` (added 2026-11-21): LXC `10202`, MAC `02:aa:bb:cc:02:02`, `10.101.1.22`. (Both were `.201`/`.202` until the re-address of 2026-11-22.) Both in Services, 1 core, 512 MiB, 8 GB on `ssd`, start order 1, configured identically by the same roles. | Address scheme tier 02. Pi-hole and Unbound install natively. Two resolvers keep DNS up while one is patched (`patch.yml` does one guest at a time). |
| Software | Pi-hole v6 (embedded web server, no lighttpd) and Unbound, both on `dns01`. | Ansible roles `unbound` and `pihole`, playbook `dns.yml`. |
| Upstream | **Option A** (decided 2026-11-21): Unbound on `127.0.0.1:5335` resolves recursively from the root servers and checks DNSSEC. It is Pi-hole's only upstream. | No third-party resolver sees every lookup, and the UDM stays out of the DNS path. Fallback if the ISP interferes with outbound port 53: forward Unbound to Quad9 over DoT (option D), a config change only. |
| Blocking | **Off** (decided 2026-11-21): no blocklists installed, `dns.blocking.active = false`. | Local names first; turn blocking on later as its own step. |
| Local names | `dns.hosts` from the inventory: every guest plus `dns_records` (`pve01`). `int.phoenixstack.net` is answered only here (`local=/int.phoenixstack.net/`), so an unknown name gets NXDOMAIN instead of the public wildcard record. | One source of truth. Adding a guest to the inventory adds its name. |
| Listening | `dns.listeningMode = SINGLE` on `eth0`: answers any source network, on that interface only. | Pi-hole's default (`LOCAL`) ignores clients outside `10.101.1.0/24`. The Proxmox firewall and the UDM decide who gets in. |
| Firewall (PVE) | `53/udp` and `53/tcp` from `lan_sources`; `443/tcp` (web interface) and SSH from admin sources. | The UDM only lets admin sources into Services today. Opening `53` to all LAN and VPN clients is a UDM rule, added at rollout. |
| Web interface | `https://dns01.int.phoenixstack.net/admin` and `https://dns02.int.phoenixstack.net/admin`, port 443 only, each with Pi-hole's self-signed certificate for its name. Password from 1Password item `(Pi-hole) - DNS Admin` (vault `infrastructure`, item ID `6rgmkyk7enemcundji75k7omeu`; one password for both resolvers), set on the first run only. | An unattended install sets no password, and without one the web interface is open. |
| Install | The installer is pinned to a Pi-hole release tag (`v6.6`) and checked by SHA-256 before it runs. It installs the current release, and FTL is checked against Pi-hole's own checksum. Updates are `pihole -up` in the weekly window. | Pi-hole has no Debian package. |
| Rollout | **Admin machines only** (decided 2026-11-21): point the admin workstation and laptop at `10.101.1.21` and `10.101.1.22` by hand. LAN DHCP stays on the UDM until they have run for a while. | |
| Redundancy | **Accepted risk** (2026-11-21, Aaron): both resolvers are on pve01, so a pve01 reboot or failure takes DNS down. Off-host DNS will be a Pi-hole on the Porter network, later. | Covers guest maintenance now; host outages wait for the Porter instance. |
| Own resolver | `dns01` itself resolves through its gateway (`.254`), not through Pi-hole. | It still has working DNS for updates if Pi-hole is down. |

Steps (each one dry-run first):

1. 1Password: create item `(Pi-hole) - DNS Admin` in `infrastructure` (generated password, 16+ characters); note its item ID for `op read`.
2. `tf plan`: expect only `dns01` plus its firewall options and rules to be created, nothing else. Then `apply`.
3. `site.yml -l dns01 -e ansible_user=root` (`--check --diff`, then for real), then `dns.yml -l dns01` the same way.
4. Check (below), then set the admin machines' DNS to `10.101.1.21` and `10.101.1.22` (were `.201`/`.202`), on the home network's profile only
   (away from home the laptop can't reach them). **Done 2026-11-21 on Aaron's laptop** (Linux Mint, NetworkManager profile
   `Auto YOUNG`: `ipv4.dns`, `ipv4.ignore-auto-dns yes`, `ipv6.ignore-auto-dns yes`, search domain `int.phoenixstack.net`).
   Checked: names resolve through Pi-hole, internal and public. The Young admin workstation is still to do.
5. ~~Afterwards: remove the UDM's manual `pve01.int.phoenixstack.net` record~~ **Done 2026-11-22** (Aaron removed the UDM's local records; the export shows none). Found 2026-11-21: it
   was never used on the Young LAN, because the LAN's DHCP hands out `8.8.8.8`/`8.8.4.4`; the laptop's `/etc/hosts` entry did the work.
   Keep that hosts entry while VPN clients are forced onto public DNS (REBUILD_STATE item 1).
6. Later, the LAN-wide rollout (a UniFi change): the Young LAN's DHCP DNS from `8.8.8.8` to `10.101.1.21`/`.22`, and a
   UDM rule letting LAN and VPN clients reach port 53 on both (today only admin sources get into Services).

Done when (run 2026-11-21, against the old addresses `.201`/`.202`):

- [x] `terraform plan` after the apply shows no changes (2026-11-21, with `dns01` and `dns02`).
- [x] `dns.yml` repeat runs: `changed=0` (twice, 2026-11-21).
- [x] From an admin machine: `dig @10.101.1.201 pve01.int.phoenixstack.net` returns `10.101.0.11`; `dig @10.101.1.201 nothing.int.phoenixstack.net` returns NXDOMAIN.
- [x] `dig @10.101.1.201 example.com` resolves. `dig @10.101.1.201 dnssec-failed.org` returns SERVFAIL (DNSSEC works).
      Answers carry no `ad` flag: Pi-hole clears it unless it validates too (`dns.dnssec`). Left off on purpose (2026-11-21);
      Unbound's SERVFAIL on bad signatures is the protection.
- [x] On `dns01`: `dig @127.0.0.1 -p 5335 . NS` answers (Unbound reaches the root servers, so no ISP interference); `ss -lntup` shows Pi-hole on 53 and 443 only, Unbound on `127.0.0.1:5335`, and nothing on 80 or 123. (Also present, both harmless: the template's Postfix on localhost:25, and Pi-hole on `[::]:53`
      with no IPv6 address on the guest.) Port 80 from the laptop times out (dropped).
- [x] `https://10.101.1.201/admin` asks for the password; browser login works on both (2026-11-21). A non-admin LAN address can't reach 53 or 443 (dropped by the UDM).
- [ ] After a pve01 reboot (next patch window): `dns01` starts first (`pct config 10201` shows `startup: order=1`).

`dns02` (added 2026-11-21, **applied 2026-11-21**; `dns01` re-run to learn its name: only `dns.hosts` changed;
each resolves the other's name): `tf plan` (expect only `dns02` and its firewall), `apply`,
then `apb site.yml -l dns02 -e ansible_user=root` and `apb dns.yml -l dns02` (each `--check --diff` first; the
web password from the same 1Password item), then the same checks against `10.101.1.202`.

**Re-address to `.21`/`.22`** (decided 2026-11-22, with the [address scheme](#address-scheme) realignment; done
before the LAN rollout, while only the admin laptop uses them). **Applied 2026-11-22**: Terraform updated both
containers in place (a second `plan`: no changes; state copy in 1Password matches), `dns.yml` changed only
`dns.hosts` (repeat run `changed=0`). Checked at both new addresses: local names (including each other's), NXDOMAIN
for unknown names, `example.com`, SERVFAIL for `dnssec-failed.org`, and the web interface. Old host keys removed.

**What went wrong:** one `apply` moved both resolvers at once while the laptop still pointed at the old
addresses, so the laptop lost DNS (and with it 1Password, which `tf.sh` needs). Aaron switched it back to the UDM's
DNS. Next time a resolver moves: move one at a time (`tf apply -target='module.lxc["dns01"]'`),
point clients at the moved one, then move the other.

Steps as run:

1. `inventory.yml`: the new IPs. `tf plan`: expect an in-place update of each container's network
   settings only (same VMID and MAC; no replace). Then `apply`.
2. `apb dns.yml --check --diff`, then `apb dns.yml`: only `dns.hosts` changes (the two DNS names).
3. The laptop's NetworkManager profile `Auto YOUNG`: DNS `10.101.1.21`, `10.101.1.22` (done 2026-11-22 by Aaron).
4. Check: `dig @10.101.1.21 pve01.int.phoenixstack.net` and `dig @10.101.1.22 dns01.int.phoenixstack.net` answer;
   `ssh` and the web interface work at the new addresses; a second `plan` and `dns.yml` show no changes.
   Remove the old host keys (`ssh-keygen -R 10.101.1.201`, `-R 10.101.1.202`).

Dry-run limits (seen 2026-11-21): on a brand-new guest, `--check` doesn't refresh the package lists, so the first
full upgrade shows nothing to do although the real run upgrades. And Pi-hole settings aren't previewed (they go through
`pihole-FTL --config`); compare `dns.hosts` and the other values in `roles/pihole/defaults/main.yml` by eye before a
real run that changes them.

What the first L5b run found, and fixed:

| Found | Fix |
| --- | --- |
| A dry run on a new guest pretends to install packages and users, so service, handler and file-owner steps failed | Those steps skip, or check as root, only in that case |
| Pi-hole moves `adlists.list` into `/etc/pihole/migration_backup/` when it builds its database, so Ansible re-created it | The two pre-seed files are written only before the install |

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

## L5d: Docker host and internal Traefik (`docker01`)

**Applied 2026-11-22** and checked (results below). No apps yet; Traefik serves only its dashboard.

| Area | Decision | Why |
| --- | --- | --- |
| Guest | `docker01`: VM `11001`, MAC `02:aa:bb:cc:10:01`, `10.101.1.101`, Services, cloned from `10001`. **8 cores, 32 GiB, 64 GB** on `nvme` (decided 2026-11-22). | Tier 10. Room for the apps moving off docker-temp and the AI agents' helper containers (models run on `ai01`). pve01 has 24 cores / 48 threads and 251 GiB. The disk grows online when needed. |
| Docker | **Docker CE from Docker's apt repository** (decided 2026-11-22), with the Compose plugin. The signing key must match Docker's published fingerprint `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`. Updates come with the weekly `patch.yml`. | Debian's `docker.io` lags behind what current images and Compose files expect. |
| Daemon | `live-restore` (containers keep running while the engine updates); `local` log driver, 5 × 20 MB per container; container networks only from `172.20.0.0/14`. | Default logs never shrink. Docker's default pools include `192.168.x.0/24`, which would collide with Teleport (`192.168.2.0/24`). |
| Admins | `sudo docker`; nobody is in the `docker` group. | The group is root without a password. |
| Firewall (PVE) | `443/tcp` from LAN sources; SSH and ping from admin sources. | Docker rewrites the firewall inside the VM; the Proxmox firewall on the NIC is outside its reach. Until the LAN-wide UDM rule, only admin sources get into Services anyway. |
| Traefik | Internal Traefik `v3.7.19` as the stack `/opt/stacks/traefik` (role `traefik`). Port 443 only, no port-80 redirect. Versions pinned in `roles/traefik/defaults/main.yml`. | |
| Routes | **File provider, no Docker socket** (decided 2026-11-22). Each Docker host lists `routes: [{name, url, admin_only}]` in the inventory: Ansible writes `dynamic/route-<name>.yml` and removes routes that are gone; Pi-hole points `<name>.int.phoenixstack.net` at the host (after `dns.yml`). Apps join the Docker network `proxy`. | Socket access is root on the host. Routes live in git, next to the guest. |
| Certificate | One wildcard, `*.int.phoenixstack.net` (plus the bare name), from Let's Encrypt over Cloudflare DNS-01. The challenge check uses `1.1.1.1` and `9.9.9.9`. Stored in `/opt/stacks/traefik/letsencrypt/acme.json` (root only); Traefik renews it 30 days before expiry. | Certificate transparency logs publish every certificate's names; a wildcard publishes only `*.int`. Pi-hole answers NXDOMAIN for anything under `int.`, so the check must ask public resolvers. |
| Cloudflare token | Its own token (decided 2026-11-22): Zone DNS Edit + Zone Read on `phoenixstack.net`, no IP filter. 1Password `(Cloudflare) - Traefik DNS Token` (item ID `6jwbiosa4zf5wg32uh333srn2m`). On the guest as `secrets/cloudflare-token` (root, `0600`), passed to Traefik as a Compose secret. | Revocable without touching PVE's token. No IP filter: the home address may change, and a failed renewal would go unnoticed until monitoring exists. |
| Dashboard | `https://traefik.int.phoenixstack.net`, admin sources only (`admin-only` IP allow-list). | Authentik can protect it later. |
| Smoke test | `whoami` (`traefik/whoami:v1.12.0`) at `https://whoami.int.phoenixstack.net` while its route is in the inventory; removing the route removes the container. | Proves the name, the route and the certificate before a real app relies on them. |
| Not in this step | The NAS mount (with the media apps), `docker02`, and the UDM rule opening `443` to LAN and VPN clients (with the DNS rollout). | One step at a time. |

Steps (the [new guest checklist](#new-guest-checklist), each one dry-run first):

1. `tf plan`: expect only `docker01` and its firewall. Then `apply`.
2. `apb site.yml -l docker01` (a VM already has the admin user from cloud-init).
3. `apb docker.yml -l docker01`, the real run with
   `CLOUDFLARE_DNS_TOKEN="$(op read 'op://infrastructure/6jwbiosa4zf5wg32uh333srn2m/credential')"`.
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
| A new guest's first `docker.yml` dry run needs the token too (it stops at the token check) | As with Pi-hole's password: run the first dry run with `CLOUDFLARE_DNS_TOKEN` set |

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
| MFA | **Required for every account** (decided 2026-11-22): the login flow accepts WebAuthn (YubiKey, passkey) or TOTP, and an account without either must enrol one before it can finish logging in. Set by our blueprint `roles/authentik/files/phoenix-mfa.yaml`, mounted read-only at `/blueprints/custom`; Authentik re-applies it hourly, so a change by hand in the UI is put back. | The default skipped MFA for accounts without a device. Static codes, Duo, SMS and email aren't offered: SMS and email are the weakest second factors. |

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

Found on the way:

| Found | Fix |
| --- | --- |
| Guests used the UDM for DNS, which has had no local records since that morning: `postgres.int.phoenixstack.net` came back as Cloudflare's public IPv6 addresses (the zone's wildcard), and Authentik hung at its first connection | Services guests use `dns01` and `dns02` (`dns_servers`); both resolvers accept 53 from the Services VLAN. See [Guests' DNS servers](#guests-dns-servers) |
| That `apply` restarted `docker01`, `authentik01` and `pgsql01` (the provider reboots on cloud-init changes), and both VMs got new SSH host keys | Keys compared through pve01's guest agent before accepting; now a note in the Terraform row of [Running it](#running-it) |
| `pgsql01`'s cluster was `SQL_ASCII` (Debian created it with the container's `C` locale), and Authentik's first migration failed on it | Cluster dropped and re-created (approved; it held only the half-migrated `authentik`), UTF-8 with the builtin `C.UTF-8` locale. New clusters get it from `createcluster.d`, and the role stops on a non-UTF8 cluster |
| `python3-psycopg2`, needed by the database tasks, in the same install task as PostgreSQL made every later run look like a new guest in a dry run | Its own task; existing roles are read with plain `psql`, so a dry run lists what it would create |

## Open decisions

1. Cloudflare in front of the public web apps (proxy or tunnel), or DNS only?
2. Plex, Jellyfin, or both?
3. Which docker-temp apps are public (to `docker02`) and which internal (to `docker01`)?
4. AI tier code (proposed 12, `.121`).
5. ~~A second Pi-hole off pve01~~ Settled 2026-11-21: `dns02` on pve01 for guest maintenance; off-host DNS will be a Pi-hole on the Porter network, later; until then a pve01 outage takes DNS down (accepted). Also settled: admin machines first, no ad blocking yet, recursive Unbound upstream (see L5b).
6. Monitoring (uptime and service alerts): which zone and when.
7. Hardware, not blocking: the 990 Pro drives and ASUS card (`data` pool) and the RTX 3070 aren't installed.

Settled 2026-11-20: Terraform state (local, with a 1Password copy), guest patching (automatic security updates,
the rest weekly), mgmt back to `/24`, three zones (mgmt VLAN 10, Services VLAN 100, DMZ VLAN 200), the archived
address scheme with the tier codes reconciled, guest types (LXC for native services, a Docker host VM per zone,
GPU VMs), two Traefik instances, Authentik in Services, YubiKey break-glass.
