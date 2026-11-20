# Guests (L5): design

Purpose: how PhoenixStack guests are placed on the network, created (Terraform) and configured (Ansible).
This is **L5a**: the groundwork every service builds on. The first service on it is DNS (L5b, Pi-hole).
The host (L0–L4) is in [../proxmox/README.md](../proxmox/README.md) and stays on `pve-bootstrap.sh`.

Status: **draft, 2026-11-18. Nothing here is applied yet.** Items marked **Decide** need Aaron's call.

## Scope

- In: the network for new guests, the guest template, IDs and names, Terraform and Ansible layout,
  secrets, the API token's privileges, the per-guest firewall, guest patching, and a test guest that proves it all.
- Out: the three -TEMP guests (AMP-TEMP 100, docker-temp 999, PLEX-TEMP 9999). They stay as they are, on
  the mgmt network, untouched by Terraform. Their future is a separate decision.
- Out: any service. L5a ends with a throwaway test guest, created and destroyed.

## Decisions

| Area | Decision | Why |
| --- | --- | --- |
| Network | New guests go on the **workload VLAN: VLAN 100, `10.101.1.0/24`**, gateway `10.101.1.254` (UDM) (decided 2026-11-20). Mgmt is `10.101.0.0/24` again. | VLAN 100 on `10.101.1.0/24` is the workload network of the original design, free again now that mgmt is a `/24`. The host has no address on the workload VLAN, so a guest can only reach the host's admin ports through the UDM, where it's blocked. |
| Addressing | The original scheme (see [Address scheme](#address-scheme)): MAC `02:aa:bb:cc:XX:YY`, VMID `1XXYY`, a fixed last octet per tier. Terraform sets the MAC and a static IP. UDM DHCP on VLAN 100 limited to `.150–.199`; `.254` gateway. | Kept from the archived design (`archive/legacy/docs/roadmap/MAC_ADDRESS_SCHEME.md`), reconciled 2026-11-20. A DNS server's address is handed out to every client, so it can't move. |
| UDM firewall | Workload VLAN in its own zone. Allow: admin sources (`10.1.1.0/24`, `10.2.1.0/24`, `192.168.2.0/24`) → services, SSH and each service's ports; client LANs and VPN → services, only the ports a service publishes (e.g. 53); services → internet. Block: services → mgmt (host, iDRAC, NAS), services → client LANs. Exceptions (a guest that needs a NAS share) are added per guest, by port. | UniFi allows traffic between internal networks by default. These rules are the real boundary; the PVE guest firewall is a second layer. Set by hand in the UniFi UI and recorded here. |
| Guest firewall (PVE) | Every Terraform guest has its firewall on (`firewall=1` on the NIC), `policy_in: DROP`, and only the rules its service needs, defined in Terraform next to the guest. | Defense in depth: a mistake in the UDM rules doesn't expose a guest. Rules live with the guest that needs them. |
| Guest type | **Unprivileged LXC** by default, from the Debian 13 standard template. A VM only when a guest needs its own kernel, a PCI device, or runs Docker. VM templates (cloud-init) are designed when the first VM is needed. | Containers are light and back up fast. Unprivileged maps container root to an unprivileged host user. |
| Template | Downloaded by the bootstrap's `templates` stage (`LXC_TEMPLATES`, `pveam`) to storage `local`, not by Terraform. It keeps one template; a newer one is fetched by deleting the old one and re-running the stage. | Downloading needs `Sys.Modify`, which the Terraform token loses (see Token). |
| Storage | Root disks on `ssd` for light guests, on `nvme` for I/O-heavy ones. Set per guest. | Matches the tiers in the host design. |
| Names | `<role><nn>`, e.g. `dns01`; FQDN `<name>.int.phoenixstack.net`. | Short and predictable. The domain is the one the host uses. |
| VMIDs | `1XXYY` from the address scheme: dns01 is **10201**. | Read the tier from the ID. Avoids every ID in use (100, 999, 9999). Check `nas-dump` for old `1XXYY` archives before first use (see Implementation steps). |
| Start order | `onboot: 1`; DNS starts first (`startup order=1`), then everything else. | After a patch reboot, other guests find DNS already up. |
| Backups | Nothing to add: both nightly jobs back up all guests. Bind mounts get `backup=0`. | Already covered by L4. |

### Address scheme

From the archived design, kept as it was where its sources agree. Where they disagreed, the scheme document
(`MAC_ADDRESS_SCHEME.md` and `INFRASTRUCTURE_DESIGN.md`) wins over the archived Terraform files.

- **MAC:** `02:aa:bb:cc:XX:YY`. `02` = locally administered unicast; `XX` = tier code; `YY` = instance.
- **VMID:** `1XXYY`, same code and instance.
- **IP:** `10.101.1.<octet>` on VLAN 100, one fixed octet per instance.
- **Name:** `<role><YY>`, e.g. `dns01`.

| Code | Tier | VMIDs | IPs (`10.101.1.x`) | Notes |
| --- | --- | --- | --- | --- |
| 01 | Bastion / Ansible | 101YY | `.21`, `.22` | Archive also had `.20`/`.21` (Terraform); the scheme document's `.21`/`.22` kept. |
| 02 | DNS (Pi-hole) | 102YY | `.201`, `.202` | |
| 03 | Proxy | 103YY | `.31`, `.32` | |
| 04 | Authentik | 104YY | `.41`, `.42` | |
| 05 | Game server (AMP) | 105YY | `.81`, `.82` | Archived Terraform used code 11. |
| 06 | Media (Plex) | 106YY | `.61`, `.62` | |
| 07 | Database | 107YY | `.71`–`.79` | pgsql01/02 `.71`/`.72`, mariadb01 `.73`. |
| 08 | Monitor | 108YY | `.91`, `.92` | Archived Terraform used code 09. |
| 09 | Vault | 109YY | `.111`, `.112` | **Moved:** the archive gave Vault `.81` (AMP's) or `.101` (the NAS's on mgmt). Archived Terraform used code 05. |
| 10 | Docker | 110YY | `.51`, `.52` | |
| 11 | Backup | 111YY | `.121` | Archived Terraform used code 08; no IP in the archive. |
| 99 | Test (throwaway) | 199YY | `.249` | New. `test01` = VMID 19901, MAC `02:aa:bb:cc:99:01`. |

Free for new tiers: `.100`–`.149` (except `.111`, `.112`, `.121`) and `.203`–`.248`. DHCP: `.150`–`.199`.
Infrastructure on mgmt (`10.101.0.0/24`) keeps its original addresses: iDRAC `.1`, pve01 `.11`, NAS `.101`,
gateway `.254`. The -TEMP guests keep their IDs and DHCP addresses until they are rebuilt.

### Terraform

| Area | Decision | Why |
| --- | --- | --- |
| Provider | `bpg/proxmox`, exact version pinned in `required_providers`; Terraform version pinned in `required_version`. | Maintained, covers LXC, VMs and firewall rules. The archive used `telmate/proxmox`. |
| Connection | `https://pve01.int.phoenixstack.net:8006/` with normal certificate checking. No SSH from Terraform. | The GUI has a Let's Encrypt certificate. Without SSH, the provider is limited to the API token's privileges. |
| Credentials | Token `terraform@pve!automation`, read from 1Password at run time: `op run --env-file=… -- terraform plan`. | No secrets on disk or in git. |
| Inventory | One file, `guests/inventory.yml`, lists each guest (VMID, IP, cores, memory, disk, storage, ports). Terraform reads it with `yamldecode()`; Ansible uses it as its inventory. | One source of truth. Adding a guest is one entry. |
| Layout | `guests/terraform/`: one root module, one small `lxc` module, `for_each` over the inventory. | Small enough to read in one sitting. No modules per tier. |
| State | Local state, git-ignored, saved to 1Password (document item) by the wrapper after each `apply` (decided 2026-11-20). | State can hold sensitive values and is the only record of what Terraform owns. A lost state is recoverable here (`terraform import` of a few guests), so a simple backup is enough. |
| Workflow | `plan`, review, `apply`, by hand from an admin workstation. No CI. | The archive's CI applied on every push to main. |
| Hand-made exceptions | Bind mounts and LXC feature flags other than `nesting` need `root@pam`, which no token has. Guests that need them get those lines by hand, recorded in this file, and Terraform ignores them (`lifecycle.ignore_changes`). | Keeps root out of automation. |

### Token (`terraform@pve`)

Today: role `PhoenixTerraform` on `/`, including `Sys.Modify`, `Sys.Console`, `VM.Console` and `Pool.Allocate`.
That's enough to change the host and open a console to any guest, the -TEMP guests included.

New (bootstrap 2026.11.5, written 2026-11-20, **not applied yet**):

- A resource pool **`terraform`**. Terraform creates every guest in it.
- Role `PhoenixTerraform` narrowed to guest privileges: `Pool.Allocate, Pool.Audit, VM.Allocate, VM.Audit,
  VM.Clone, VM.Config.CDROM, VM.Config.CPU, VM.Config.Cloudinit, VM.Config.Disk, VM.Config.HWType,
  VM.Config.Memory, VM.Config.Network, VM.Config.Options, VM.GuestAgent.Audit, VM.PowerMgmt`, granted only on
  the pool. `Pool.Allocate` stays because putting a new guest in a pool requires it on that pool.
- Dropped: `Sys.Modify`, `Sys.Console`, `Sys.Audit` on `/`, `VM.Console`, `VM.Migrate` (one host),
  `Datastore.*` on `/`, `Mapping.*` (until a GPU guest is managed by Terraform).
- Grants (instead of one on `/`), the same for the user and its token:

  | Path | Role | Why |
  | --- | --- | --- |
  | `/pool/terraform` | `PhoenixTerraform` | Create and manage guests, only inside the pool. The -TEMP guests aren't in it. |
  | `/storage/ssd`, `/storage/nvme` | `PVEDatastoreUser` (built-in) | Allocate root disks. |
  | `/storage/local` | `PVEAuditor` (built-in, read-only) | Read the template. |
  | `/sdn/zones/localnetwork/vmbr0` | `PVESDNUser` (built-in) | Attach NICs to `vmbr0` (PVE 8+ checks this). **Narrow to `vmbr0/<vlan>`** once the workload VLAN exists, so Terraform can't put a guest on mgmt. |
  | `/nodes/pve01` | `PVEAuditor` (built-in, read-only) | Read node status. |

- The `access` stage now sets each service account's grants **exactly**: it adds the configured ones and
  removes any others, which is what removes the grant on `/`. The token and its secret are unchanged.
  `verify` checks that each token's grants match the config.
- The privilege list is a starting point. The test guest proves it: create, change, firewall rules, destroy.
  Anything missing is added with the reason written here.

### Ansible

| Area | Decision | Why |
| --- | --- | --- |
| Layout | `guests/ansible/`: `ansible.cfg`, playbooks per service, roles `base` and one per service. Inventory: `../inventory.yml`. | Same inventory as Terraform. |
| Control node | An admin workstation (Young LAN, Porter LAN or VPN). | Those are the networks the UDM lets reach guests' SSH. |
| First login | Terraform puts Aaron's SSH public key in the container's root account. The first `base` run connects as root, creates user `aaron` (sudo, key only), then sets `PermitRootLogin no`. Later runs connect as `aaron`. | Named admin account; root only during the first run. |
| Host keys | Checking stays on, with `StrictHostKeyChecking=accept-new`. A rebuilt guest's old key is removed by hand. | The archive turned host key checking off. |
| Secrets | The 1Password lookup plugin (`community.general.onepassword`), or `op run` for environment variables. **No Ansible Vault files.** | The archive committed Vault files to a public repo. |
| `base` role | Timezone, locale, NTP (`systemd-timesyncd`), journald size cap, sshd hardening, admin user, unattended security updates (see Patching). | The same baseline on every guest. |
| Runs | Always `--check --diff` first, then the real run. | Repo guardrail. |

### Guest patching

Decided 2026-11-20: Debian **security** updates install themselves daily (`unattended-upgrades`, security
origin only, no automatic reboot), and everything else goes through a `patch.yml` playbook in the host's weekly
window.

Why: the reason the host patches by hand (one kernel or QEMU update takes every guest down) doesn't apply to a
container. Containers share the host's kernel, so an update can't reboot them. A bad update breaks one guest,
and the nightly backups restore it.

### Name resolution until L5b

Until Pi-hole exists, each guest's name is added by hand to the UDM's local DNS, as `pve01` was. Guests use
the UDM (`10.101.1.254`) as their resolver. L5b moves the records into git (Pi-hole, managed by Ansible),
and the UDM's manual records are then removed so there is only one copy.

## Implementation steps

Each step is dry-run first. Steps 1–3 change shared infrastructure and wait for approval.

1. **Mgmt back to `/24`** (UniFi and pve01 together; runbook in [../proxmox/REBUILD_STATE.md](../proxmox/REBUILD_STATE.md), open item 8).
2. **UDM (by hand, Aaron):** create the workload network (VLAN 100, `10.101.1.0/24`, DHCP `.150–.199`) and the
   zone rules above. Check that pve01's switch port carries VLAN 100 (`BRIDGE_VIDS="2-4094"` already allows it on `vmbr0`).
3. **Bootstrap 2026.11.5:** pool `terraform`, narrowed token, Debian 13 template. Plan, review,
   `--apply --stage templates,access`. Then narrow the token's network grant to `vmbr0/100`.
4. **Check for old `1XXYY` archives** on `nas-dump` (`ls /mnt/nas/nas-dump/dump/ | grep -E 'vzdump-(lxc|qemu)-1[0-9]{4}-'`),
   so a new guest's backups can't be confused with an old guest's.
5. **Repo:** `guests/inventory.yml`, `guests/terraform/`, `guests/ansible/` with the `base` role. `terraform plan` and
   `ansible-playbook --check --diff` against nothing yet.
6. **Test guest** `test01` (VMID 19901, `10.101.1.249`): apply, run `base`, check, then destroy.

## Done when (test guest)

- [ ] `terraform apply` creates it in pool `terraform`; a second `plan` shows no changes.
- [ ] The token can't change the -TEMP guests or the host (an API call to each fails with 403).
- [ ] `base` runs clean; a second run reports no changes. Root SSH login is refused.
- [ ] From the guest: `10.101.0.11` ports 22, 8006, 8007, the iDRAC and the NAS admin page don't answer;
      `apt update` works.
- [ ] From an admin LAN and the VPN: SSH to the guest works. From the guest: SSH to an admin workstation fails.
- [ ] Its firewall drops a port that isn't allowed (seen in `/var/log/pve-firewall.log`).
- [ ] `terraform destroy` removes it cleanly; the UDM DNS record is removed.

## Open decisions

1. For L5b, not needed yet: who uses Pi-hole first (VPN only, or the LANs too) and whether it blocks ads.

Settled 2026-11-20: Terraform state (local, with a 1Password copy), guest patching (automatic security updates,
the rest weekly), workload network (VLAN 100, `10.101.1.0/24`), mgmt back to `/24`, and the archived address
scheme with the tier codes reconciled above.
