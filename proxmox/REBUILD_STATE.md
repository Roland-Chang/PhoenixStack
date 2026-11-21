# pve01: current state

Snapshot as of **2026-11-20**. This file says where the host stands and what's still open, so the work
can be picked up on another computer. The design and the rebuild runbook are in [README.md](README.md).
How things got here is in the git history (`git log -- proxmox/`).

## Where things stand

| Area | State |
| --- | --- |
| Host (L0–L3) | **Done 2026-11-14.** Installed from the unattended ISO; PVE 9.2.27, kernel 7.0.14-29. `rpool` is a mirror of the 2 Intel SSDs. `bond0` + VLAN-aware `vmbr0` at 10 Gb/s, host `10.101.0.11/24` (was `/23` until 2026-11-20). IOMMU on; the P2000 is on `vfio-pci` with mapping `GPU01`. Firewall: default DROP. |
| Pools | `nvme` (mirror, 860G), `ssd` (mirror, 231G), `backup` (RAIDZ1 + special mirror, 3.07T, dataset `backup/pbs`). The `data` pool isn't built: the ASUS Hyper M.2 card and the 990 Pro drives aren't installed. |
| Access | `aaron@pve` (group `admins`) and `root@pam` have TOTP, in PVE and in PBS. Tokens: `terraform@pve!automation` (unused so far) and `claude-audit@pve!discovery` (secret in 1Password, `(Proxmox) Claude API`). |
| Admin allowlist | **2026-11-20:** `10.1.1.69/32` (Young admin workstation) and `192.168.2.0/24` (Teleport VPN clients) **applied**, tested over Teleport (SSH, GUI, PBS, SPICE). `10.2.1.69/32` (Porter admin workstation) applied the same day; `verify` passed with 0 warnings. Matches the UDM's Management zone. Was `10.1.1.0/24`, `10.2.1.0/24` and `192.168.2.0/24`. Checked 2026-11-15: a VPN client reaches the host; guests on the mgmt network can't reach ports 22, 8006 or 3128. |
| Guests | **Restored 2026-11-14**, all running with `onboot: 1`. AMP-TEMP (lxc 100, `ssd`, 10.101.1.190). docker-temp (lxc 999, `nvme`, 10.101.0.166; NAS shares Media and Porter bind-mounted read-write). PLEX-TEMP (VM 9999, `nvme`, 10.101.0.111; GPU01 attached). FTP01 (9000) and INTEL01 (9001) are retired. |
| Backups (L4) | **Done.** PBS 4.2 on the host, datastore `pve01-local`. Jobs `nightly-pbs` 01:00 and `nightly-nas` 03:30 have run successfully every night since 2026-11-14 (reported by Aaron 2026-11-16). First PBS run: 256 GiB in 29 minutes. Test restore from the NAS passed, at about 24 MiB/s, so restoring every guest from the NAS takes hours. |
| Alerts (L4) | **Done 2026-11-16.** Everything goes to `alerts@phoenixstack.net` through Brevo, from PVE and from PBS; test emails from both arrived. Root's mail (ZFS events, smartd, cron) goes the same way, and a `sendmail root` test arrived. The built-in `mail-to-root` targets are disabled, and the postfix queue is empty (the undeliverable mail from before the fix was deleted 2026-11-16). |
| Patching and logging | **Applied 2026-11-16.** New package updates are emailed (matcher `phoenix-updates`, `notify package-updates=always`). Dropped inbound packets are logged to `/var/log/pve-firewall.log`. Updates are installed weekly, by hand. |
| Last full plan | 2026-11-16, script version 2026.11.1: **0 changes pending**, all 30 `verify` checks passed. |
| TLS | **Applied 2026-11-16.** Let's Encrypt certificate for `pve01.int.phoenixstack.net` on the PVE GUI (port 8006), issued through Cloudflare DNS-01; valid until 2027-02-15 and renewed by PVE's daily job. Checked from a VPN client: the chain and host name verify. |
| PBS certificate | **Applied 2026-11-18** (reported by Aaron). Let's Encrypt certificate on the PBS GUI (port 8007), with its own ACME account and renewal. Storage `pbs-local` re-created to reach PBS at `pve01.int.phoenixstack.net` with normal certificate checking, so renewals can't break backups. The name resolves only to `10.101.0.11` on the host (`/etc/hosts`, as seen by `getent ahosts`). Script version 2026.11.4. |
| Last patch run | **2026-11-16**: 10 updates installed with `apt dist-upgrade`. Afterwards `verify` showed no updates pending, 0 warnings, and the running kernel is the newest installed, so no reboot was needed. Next run due around 2026-11-23. |

## Open items

1. Name resolution over VPN: the UDM now has the local record `pve01.int.phoenixstack.net → 10.101.0.11` (added 2026-11-16; checked: the GUI answers by name with a valid certificate when the UDM is asked). VPN clients still use public DNS, where the zone's wildcard record answers instead: the WiFiman app builds the tunnel with `8.8.8.8` for all lookups and recreates it on every connect, so editing the tunnel's settings doesn't last. Until VPN DNS is solved properly (worth doing at L5, when there are more names), a client needs a hosts entry: `10.101.0.11 pve01.int.phoenixstack.net` (done on Aaron's laptop 2026-11-16; the GUI opens by name over VPN with a valid certificate).
2. Check that the 01:00 `nightly-pbs` run on 2026-11-19 succeeded: it's the first backup through the re-created `pbs-local` storage.
3. NAS space: it was 77% full before the nightly archives started. Check around 2026-11-21.
4. The pre-rebuild archives on `nas-dump` are still **Protected**: `lxc-100-2026_11_12-19_32_20`,
   `lxc-999-2026_11_12-02_26_20`, `qemu-9999-2026_11_12-02_39_30`. Remove the flag once the new backups
   have a few weeks of history.
5. Set `NOTIFY_ALL_BACKUP_JOBS="no"` once the nightly jobs have proven themselves, so only failures are emailed.
6. **Temporary migration host** (found 2026-11-20): a separate Proxmox machine on the Young LAN (LVM root, kernel
   7.0.2-6) ran copies of the guests during the rebuild, including a docker-temp copy at `10.1.1.116`
   (MAC `bc:24:11:a0:1b:38`). Its guests were shut down 2026-11-20 by Aaron. Anything they saved after the backups
   of 2026-11-12 exists only on that machine's disk (its NAS mount folders were empty local directories). Keep its
   disks until the pve01 guests are verified and anything newer has been copied over, then wipe it.
7. **Port forwards** (fixed 2026-11-20 by Aaron): the UDM's port forwards still pointed at the migration host's
   docker-temp, which caused the 502 Bad Gateway errors. They now point at pve01's docker-temp (`10.101.0.166`).
   That puts an internet-facing guest on the mgmt subnet, next to the host, iDRAC and NAS. Moving it to the services
   VLAN is part of L5 ([../guests/README.md](../guests/README.md)). AMP-TEMP (lxc 100) was found stopped the same day.
8. **Mgmt network back to `/24`** (decided 2026-11-20). **Done 2026-11-20** (reported by Aaron): UniFi changed, then
   pve01's network stage re-applied. Checked: `vmbr0` is `10.101.0.11/24`, NAS mounts up, `verify` passes (bootstrap
   2026.11.5). Still to do: step 1 below (clients left on `10.101.1.x`) and the reservations. Before, PHOENIX-PRIMARY was `10.101.0.0/23`
   with DHCP `10.101.0.11`–`10.101.1.254`, covering pve01's `.11` and the NAS's `.101`. The steps, for the record
   (UniFi and pve01 change together, since a mask mismatch routes host-to-guest traffic through the gateway):
   1. In UniFi, list the clients with `10.101.1.x` addresses (AMP-TEMP had `.1.190`); they'll get new addresses.
      Add fixed-IP reservations for the NAS (`.101`), docker-temp (`.166`, the port forwards' target) and
      PLEX-TEMP (`.111`).
   2. PHOENIX-PRIMARY: `10.101.0.254/24`, DHCP range `10.101.0.100`–`10.101.0.249` (fixed addresses stay below `.100`).
   3. pve01: `pve-sync`; `--stage network` (plan: only the address mask should change); `--apply --stage network`; type `keep`.
   4. Check: `ip -br addr show vmbr0` shows `/24`; `verify` passes; NAS mounts; apps through the port forwards;
      guests pick up the `/24` at their next DHCP renewal (or restart them).
9. **UniFi zones** (2026-11-20, by Aaron, checked with `tools/unifi-export.sh`): mgmt and IOT each moved from shared
   zones to their own (**Management**, **IOT**). Into Management: the admin workstation `10.1.1.69` and Teleport
   (`192.168.2.0/24`) get everything; the Young LAN and the site-to-site VPNs only the NAS (SMB) and PLEX-TEMP (Plex);
   the Young LAN also docker-temp's app ports. Port forwards followed the network. Every zone's access to the UDM is
   limited to DNS, DHCP and ICMP. Stale forwards removed; Services DHCP `.150`–`.199`. SSH is **off** on the UDM and
   the iDRAC on purpose (a closed port 22 there isn't a fault). The Temp site-to-site VPN and unused port lists were deleted;
   two site-to-site VPNs remain (BPorter, RYoung). pve01's `ADMIN_SOURCES` narrowed to match the same day
   (Young and Porter workstations, Teleport). The zone grid is on the topology page (`guests/topology.html`).
10. **1Password clean-up, after the rebuild** (reviewed 2026-11-20, deferred by Aaron): retire the old design's items
    (its automation service account and tokens, the old Proxmox API fields, logins for guests that never ran),
    retire the -TEMP guests' items as their apps move, move items that aren't lab secrets out of the lab vaults,
    keep lab secrets in `infrastructure`, and use one naming pattern, `(Category) - Name`. The item-by-item list
    is kept outside this public repo.

## For the L5 design

The draft is in [../guests/README.md](../guests/README.md) (2026-11-18); it answers the points below.

- Tooling is decided: Terraform creates guests, Ansible configures them.
- Guests share the mgmt network (`10.101.0.0/24`, untagged) with the host. Moving them to their own VLAN,
  and whether they can reach the iDRAC and NAS admin pages today, is not yet looked at.
- No per-guest firewall rules exist.
- **Applied 2026-11-20** (bootstrap 2026.11.6, `templates,access`, reported by Aaron): pool `terraform` created, the
  `terraform@pve` token narrowed to it (no grant on `/` any more), Debian 13 template `debian-13-standard_13.6-1_amd64`
  on `local`.
- **Applied 2026-11-20** (bootstrap 2026.11.7, `access,templates`): pool `templates` with VM template `10001`
  `debian13-cloud` (Debian 13 genericcloud, SHA512-checked; NIC VLAN 100; guest-agent vendor snippet); Terraform may
  only clone there, and its network grant is VLANs 100 and 200 only. Checked through the read-only API.
- Both backup copies are in the same building. An offsite copy is an open decision.
