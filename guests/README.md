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
| Network | New guests go on a **services VLAN**, not on mgmt. Proposed: **VLAN 20, `10.101.2.0/24`**, gateway `10.101.2.254` (UDM). **Decide:** confirm the ID and subnet don't clash with existing UniFi networks. | The host has no address on the services VLAN, so a guest can only reach the host's admin ports through the UDM, where it's blocked. Today guests share the mgmt subnet, and their access to the iDRAC and NAS admin pages hasn't been checked. `10.101.1.0/24` (the old plan) is inside the mgmt `/23`. |
| Addressing | Static IPs set by Terraform in `.1–.99`; UDM DHCP limited to `.100–.199`; `.254` gateway. | A DNS server's address is handed out to every client, so it can't move. DHCP stays available for anything temporary. |
| UDM firewall | Services VLAN in its own zone. Allow: admin sources (`10.1.1.0/24`, `10.2.1.0/24`, `192.168.2.0/24`) → services, SSH and each service's ports; client LANs and VPN → services, only the ports a service publishes (e.g. 53); services → internet. Block: services → mgmt (host, iDRAC, NAS), services → client LANs. Exceptions (a guest that needs a NAS share) are added per guest, by port. | UniFi allows traffic between internal networks by default. These rules are the real boundary; the PVE guest firewall is a second layer. Set by hand in the UniFi UI and recorded here. |
| Guest firewall (PVE) | Every Terraform guest has its firewall on (`firewall=1` on the NIC), `policy_in: DROP`, and only the rules its service needs, defined in Terraform next to the guest. | Defense in depth: a mistake in the UDM rules doesn't expose a guest. Rules live with the guest that needs them. |
| Guest type | **Unprivileged LXC** by default, from the Debian 13 standard template. A VM only when a guest needs its own kernel, a PCI device, or runs Docker. VM templates (cloud-init) are designed when the first VM is needed. | Containers are light and back up fast. Unprivileged maps container root to an unprivileged host user. |
| Template | Downloaded by the bootstrap (`pveam`) to storage `local`, not by Terraform. | Downloading needs `Sys.Modify`, which the Terraform token loses (see Token). One more line in the bootstrap's config. |
| Storage | Root disks on `ssd` for light guests, on `nvme` for I/O-heavy ones. Set per guest. | Matches the tiers in the host design. |
| Names | `<role><nn>`, e.g. `dns01`; FQDN `<name>.int.phoenixstack.net`. | Short and predictable. The domain is the one the host uses. |
| VMIDs | `VLAN × 1000 + last octet`: `10.101.2.10` on VLAN 20 is **20010**. | Read the address from the ID. Avoids every ID in use or in the archives on `nas-dump` (100, 999, 9000, 9001, 9999, and the older 1xxxx plan). |
| Start order | `onboot: 1`; DNS starts first (`startup order=1`), then everything else. | After a patch reboot, other guests find DNS already up. |
| Backups | Nothing to add: both nightly jobs back up all guests. Bind mounts get `backup=0`. | Already covered by L4. |

### Terraform

| Area | Decision | Why |
| --- | --- | --- |
| Provider | `bpg/proxmox`, exact version pinned in `required_providers`; Terraform version pinned in `required_version`. | Maintained, covers LXC, VMs and firewall rules. The archive used `telmate/proxmox`. |
| Connection | `https://pve01.int.phoenixstack.net:8006/` with normal certificate checking. No SSH from Terraform. | The GUI has a Let's Encrypt certificate. Without SSH, the provider is limited to the API token's privileges. |
| Credentials | Token `terraform@pve!automation`, read from 1Password at run time: `op run --env-file=… -- terraform plan`. | No secrets on disk or in git. |
| Inventory | One file, `guests/inventory.yml`, lists each guest (VMID, IP, cores, memory, disk, storage, ports). Terraform reads it with `yamldecode()`; Ansible uses it as its inventory. | One source of truth. Adding a guest is one entry. |
| Layout | `guests/terraform/`: one root module, one small `lxc` module, `for_each` over the inventory. | Small enough to read in one sitting. No modules per tier. |
| State | **Decide.** Recommended: local state, git-ignored, saved to 1Password (document item) by the wrapper after each `apply`. Alternative: OpenTofu, whose built-in state encryption allows keeping the state file in git. | State can hold sensitive values and is the only record of what Terraform owns. A lost state is recoverable here (`terraform import` of a few guests), so a simple backup is enough. |
| Workflow | `plan`, review, `apply`, by hand from an admin workstation. No CI. | The archive's CI applied on every push to main. |
| Hand-made exceptions | Bind mounts and LXC feature flags other than `nesting` need `root@pam`, which no token has. Guests that need them get those lines by hand, recorded in this file, and Terraform ignores them (`lifecycle.ignore_changes`). | Keeps root out of automation. |

### Token (`terraform@pve`)

Today: role `PhoenixTerraform` on `/`, including `Sys.Modify`, `Sys.Console`, `VM.Console` and `Pool.Allocate`.
That's enough to change the host and open a console to any guest, the -TEMP guests included.

Proposed:

- A resource pool **`terraform`**. Terraform creates every guest in it.
- Role `PhoenixTerraform` narrowed to: `VM.Allocate, VM.Audit, VM.Clone, VM.Config.CDROM, VM.Config.CPU,
  VM.Config.Cloudinit, VM.Config.Disk, VM.Config.HWType, VM.Config.Memory, VM.Config.Network,
  VM.Config.Options, VM.PowerMgmt, VM.GuestAgent.Audit, Datastore.AllocateSpace, Datastore.Audit, SDN.Use,
  SDN.Audit, Sys.Audit, Pool.Audit`.
- Dropped: `Sys.Modify`, `Sys.Console`, `VM.Console`, `VM.Migrate` (one host), `Pool.Allocate`,
  `Datastore.Allocate`, `Datastore.AllocateTemplate`, `Mapping.*` (until a GPU guest is managed by Terraform).
- ACLs (instead of one on `/`):

  | Path | Why |
  | --- | --- |
  | `/pool/terraform` | Create and manage guests, only inside the pool. The -TEMP guests aren't in it. |
  | `/storage/ssd`, `/storage/nvme` | Allocate root disks. |
  | `/storage/local` | Read the template (`Datastore.Audit`). |
  | `/sdn/zones/localnetwork/vmbr0` | Attach NICs to `vmbr0` (PVE 8+ checks this). |
  | `/nodes/pve01` | Read node status (`Sys.Audit`). |

- Bootstrap change: `SERVICE_ACCOUNTS` takes one ACL path today; it needs a list. The `access` stage
  creates the pool too. Run in plan mode first; the token secret is unchanged.
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

**Decide.** Recommended: Debian **security** updates install themselves daily (`unattended-upgrades`, security
origin only, no automatic reboot), and everything else goes through a `patch.yml` playbook in the host's weekly
window. Alternative: everything by hand in the weekly window, like the host.

Why: the reason the host patches by hand (one kernel or QEMU update takes every guest down) doesn't apply to a
container. Containers share the host's kernel, so an update can't reboot them. A bad update breaks one guest,
and the nightly backups restore it.

### Name resolution until L5b

Until Pi-hole exists, each guest's name is added by hand to the UDM's local DNS, as `pve01` was. Guests use
the UDM (`10.101.2.254`) as their resolver. L5b moves the records into git (Pi-hole, managed by Ansible),
and the UDM's manual records are then removed so there is only one copy.

## Implementation steps

Each step is dry-run first. Steps 1 and 2 change shared infrastructure and wait for approval.

1. **UDM (by hand, Aaron):** create the services network (VLAN 20, `10.101.2.0/24`, DHCP `.100–.199`) and the
   zone rules above. Check that pve01's switch port carries VLAN 20 (`BRIDGE_VIDS="2-4094"` already allows it on `vmbr0`).
2. **Bootstrap:** pool `terraform`, narrowed role, list of ACL paths, Debian 13 template download. Plan, review,
   `--apply --stage access`.
3. **Repo:** `guests/inventory.yml`, `guests/terraform/`, `guests/ansible/` with the `base` role. `terraform plan` and
   `ansible-playbook --check --diff` against nothing yet.
4. **Test guest** `test01`, `10.101.2.99`, VMID 20099: apply, run `base`, check, then destroy.

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

1. VLAN ID and subnet for the services network (proposed VLAN 20, `10.101.2.0/24`).
2. Terraform state: local plus a 1Password copy, or OpenTofu with an encrypted state.
3. Guest patching: unattended security updates, or everything by hand.
4. For L5b, not needed yet: who uses Pi-hole first (VPN only, or the LANs too) and whether it blocks ads.
