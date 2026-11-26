# pve01: current state

Snapshot as of **2026-11-24**. This file says where the host stands and what's still open, so the work
can be picked up on another computer. The design and the rebuild runbook are in [README.md](README.md).
How things got here is in the git history (`git log -- proxmox/`).

## Where things stand

| Area | State |
| --- | --- |
| Host (L0–L3) | **Done 2026-11-14.** Installed from the unattended ISO; PVE 9.2.28 (2026-11-24), running its newest installed kernel. `rpool` is a mirror of the 2 Intel SSDs. `bond0` + VLAN-aware `vmbr0` at 10 Gb/s, host `10.101.0.11/24` (was `/23` until 2026-11-20). IOMMU on; the P2000 is on `vfio-pci` with mapping `GPU01`. Firewall: default DROP. |
| Pools | `nvme` (mirror, 860G), `ssd` (mirror, 231G), `backup` (RAIDZ1 + special mirror, 3.07T, dataset `backup/pbs`). The `data` pool isn't built: the ASUS Hyper M.2 card and the 990 Pro drives aren't installed. |
| Access | `aaron@pve` (group `admins`) and `root@pam` have TOTP, in PVE and in PBS. Tokens: `terraform@pve!automation` (Terraform's, in use since L5a) and `claude-audit@pve!discovery` (secret in 1Password, `(Proxmox) Claude API`). |
| Admin allowlist | `ADMIN_SOURCES`: `10.1.1.69` and `10.1.1.169` (Young admin workstation and laptop), `10.2.1.69` and `10.2.1.169` (Porter admin workstation and laptop, over the BPorter site-to-site VPN), `192.168.2.0/24` (Teleport VPN clients). The same list as the inventory's `admin_sources` and the UDM's admin rules (item 9 has the one exception). Last applied 2026-11-21: firewall plan 0 changes, `verify` 0 warnings. Checked 2026-11-15: a VPN client reaches the host; guests on the mgmt network can't reach ports 22, 8006 or 3128. |
| Guests | **Restored 2026-11-14** with `onboot: 1`. Running: docker-temp (lxc 999, `nvme`, 10.101.0.166; NAS shares Media and Porter bind-mounted read-write) and PLEX-TEMP (VM 9999, `nvme`, 10.101.0.111; GPU01 attached). AMP-TEMP (lxc 100, `ssd`) was **deleted 2026-11-23** by the Young admin (stopped since 2026-11-20); its backups stay: on `pbs-local` (retention never removes a deleted guest's last backups) and the protected `lxc-100-2026_11_12-19_32_20` on `nas-dump`. The game servers return with `amp01` (DMZ). FTP01 (9000) and INTEL01 (9001) are retired. |
| Backups (L4) | **Done.** PBS 4.2 on the host, datastore `pve01-local`. Jobs `nightly-pbs` 01:00 and `nightly-nas` 03:30 (Denver; since 2026-11-24 written as 08:00 and 10:30 UTC, the host's clock now being UTC) have run successfully every night since 2026-11-14 (reported by the Young admin 2026-11-16). First PBS run: 256 GiB in 29 minutes. Test restore from the NAS passed, at about 24 MiB/s, so restoring every guest from the NAS takes hours. |
| Alerts (L4) | **Done 2026-11-16.** Everything goes to `alerts@phoenixstack.net` through Brevo, from PVE and from PBS; test emails from both arrived. Root's mail (ZFS events, smartd, cron) goes the same way, and a `sendmail root` test arrived. The built-in `mail-to-root` targets are disabled, and the postfix queue is empty (the undeliverable mail from before the fix was deleted 2026-11-16). |
| Patching and logging | **Applied 2026-11-16.** New package updates are emailed (matcher `phoenix-updates`, `notify package-updates=always`). Dropped inbound packets are logged to `/var/log/pve-firewall.log`. Updates are installed weekly, by hand. |
| Last full plan | **2026-11-24**, version 2026.11.7, all stages: 155 checks pass and 1 change pending, the admin user `ben@pve` (waiting on the Porter admin). `verify`: every check passes; 75 package updates pending. |
| TLS | **Applied 2026-11-16.** Let's Encrypt certificate for `pve01.int.phoenixstack.net` on the PVE GUI (port 8006), issued through Cloudflare DNS-01; valid until 2027-02-15 and renewed by PVE's daily job. Checked from a VPN client: the chain and host name verify. |
| PBS certificate | **Applied 2026-11-18** (reported by the Young admin). Let's Encrypt certificate on the PBS GUI (port 8007), with its own ACME account and renewal. Storage `pbs-local` re-created to reach PBS at `pve01.int.phoenixstack.net` with normal certificate checking, so renewals can't break backups. The name resolves only to `10.101.0.11` on the host (`/etc/hosts`, as seen by `getent ahosts`). Script version 2026.11.4. |
| Guests (L5) | Created by Terraform (pool `terraform`) and configured by Ansible: `dns01`/`dns02` (Pi-hole and Unbound, `.21`/`.22`), `pgsql01` (PostgreSQL 17, `.71`), `docker01` (Docker and the Services Traefik, `.101`), `authentik01` (Authentik 2026.8.6, `.41`), all applied and checked by 2026-11-22. Services guests resolve through `dns01`/`dns02`; the Young LAN asks the UDM, which forwards `int.phoenixstack.net` to them (2026-11-22). Design, state and checks: [../guests/README.md](../guests/README.md). |
| Last patch run | **2026-11-16**: 10 updates installed with `apt dist-upgrade`, no reboot needed. **Overdue:** the next was due around 2026-11-23, and 75 updates were pending on 2026-11-24. |

## Open items

1. Name resolution over VPN: the UDM had the local record `pve01.int.phoenixstack.net → 10.101.0.11` from 2026-11-16 until 2026-11-22, when the Young admin removed the UDM's local records: Pi-hole (`dns01`, `dns02`) now holds `pve01` and every guest's name. VPN clients still use public DNS, where the zone's wildcard record answers instead: the WiFiman app builds the tunnel with `8.8.8.8` for all lookups and recreates it on every connect, so editing the tunnel's settings doesn't last. Until VPN DNS is solved properly (worth doing at L5, when there are more names), a client needs a hosts entry: `10.101.0.11 pve01.int.phoenixstack.net` (done on the Young admin's laptop 2026-11-16; the GUI opens by name over VPN with a valid certificate).
2. ~~Check that the 01:00 `nightly-pbs` run on 2026-11-19 succeeded~~ **Done 2026-11-21:** `pbs-local` has backups of 100, 999 and 9999 from 11-19, 11-20 and 11-21 (01:00 local).
3. ~~NAS space~~ **Checked 2026-11-21:** `nas-dump` 79.6% used, about 13 TiB free (was 77%). Pruning works: 7 nightly archives per guest (11-15 to 11-21), about 1.65 TiB in all, so usage should now stay flat.
   Retention never removes the last backups of a guest that no longer exists: the 11-21 backups of the test guests `19901`/`19902` were deleted by hand the same day (on PBS as `root@pam`: PVE's token can't delete, by design). Also on `nas-dump`, not protected and never pruned: `vzdump-qemu-101-2026_05_08` (45 GB, an older guest that reused ID 101) and `vzdump-qemu-9000-2026_11_10` (10.5 GB, FTP01, retired); decide with item 4. The VM template `10001` is backed up nightly too (296 MB on the NAS); left as is.
4. The pre-rebuild archives on `nas-dump` are still **Protected**: `lxc-100-2026_11_12-19_32_20`,
   `lxc-999-2026_11_12-02_26_20`, `qemu-9999-2026_11_12-02_39_30`. Remove the flag once the new backups
   have a few weeks of history.
5. ~~Set `NOTIFY_ALL_BACKUP_JOBS="no"`~~ **Applied 2026-11-21** (`notify` stage; the plan removed only the `phoenix-backups` matcher). Only failed backups are emailed now.
6. ~~Temporary migration host~~ **Wiped** (review item O8, closed 2026-11-26): the separate Proxmox machine on the
   Young LAN that ran copies of the guests during the rebuild (2026-11-12 to 2026-11-20).
7. **Port forwards** (2026-11-24): `443` → `docker02` (`10.101.2.102`), Cloudflare's addresses only, port `443`
   only; every public app runs there since 2026-11-26 (the temporary rule to docker-temp is deleted). `32400` (Plex) → PLEX-TEMP (`10.101.0.111`): an internet-facing guest on
   the mgmt subnet, next to the host, iDRAC and NAS, until Plex moves to `plex01` in the DMZ. No game-port forward
   is left (confirmed in UniFi 2026-11-26, review item O11).
8. **Mgmt network** `10.101.0.0/24` (since 2026-11-20; DHCP `10.101.0.100`–`.249`, fixed addresses below `.100`).
   Still to do: reservations for docker-temp (`.166`) and PLEX-TEMP (`.111`), both plain leases inside the range
   (UniFi export 2026-11-22); the NAS (`.101`) is reserved.
9. **UniFi zones** (checked with `tools/unifi-export.sh`, 2026-11-23): Management, IOT, Services and DMZ each have a
   zone of their own. Into Management: the admin sources get everything; the Young LAN and the site-to-site VPNs
   only the NAS (SMB) and PLEX-TEMP (Plex); the Young LAN also docker-temp's app ports. Every zone's access to the
   UDM is limited to DNS, DHCP and ICMP. SSH is **off** on the UDM and the iDRAC on purpose (a closed port 22 there
   isn't a fault). Two site-to-site VPNs (BPorter, RYoung). The zone grid is on the topology page
   (`guests/topology.html`).
   **Temporary exception (2026-11-21, by the Young admin):** `10.2.1.175`, a temporary production system at the Porter site that
   needs the file server, was added to the UDM's **Porter Admin** rules (into Management, Services and DMZ). It is
   *not* an admin source and isn't in pve01's `ADMIN_SOURCES`, so pve01 itself still drops it. Replace it with a
   rule for the NAS only (its protocol and ports) and take it out of Porter Admin when that system retires.
10. **1Password clean-up, after the rebuild** (reviewed 2026-11-20, deferred by the Young admin): retire the old design's items
    (its automation service account and tokens, the old Proxmox API fields, logins for guests that never ran),
    retire the -TEMP guests' items as their apps move, move items that aren't lab secrets out of the lab vaults,
    keep lab secrets in `infrastructure`, and use one naming pattern, `(Category) - Name`. Two items in use don't
    follow it yet: `(Proxmox) Claude API` and `UniFi read-only export` (rename them, then their references in
    `pve01.conf`, `tools/unifi-export.sh` and the docs). The item-by-item list is kept outside this public repo.
11. **UDM IPS and SSH**: the IPS takes repeated SSH for an outbound scan and blocks it for a few minutes, per
    destination. The admin workstations and laptops (`10.1.1.69`, `10.1.1.169`, `10.2.1.69`, `10.2.1.169`) are on
    its "Detection Exclusions" list. So is the **whole Teleport range** `192.168.2.0/24`
    (2026-11-26, after `192.168.2.8` was cut off on 2026-11-24). An excluded address isn't inspected at all, so keep
    that list to admin machines: before anyone but the admins uses Teleport, narrow it to the admins' fixed Teleport
    addresses, together with the admin sources (review item S2). Not the IPS: Ansible reporting guests unreachable with "Timeout waiting for
    privilege escalation prompt" is the 1Password SSH agent waiting for approval
    ([../guests/README.md](../guests/README.md#ansible), SSH agent).
12. **Offsite backup copy**: both backup copies (PBS and the NAS) are in the same building. An open decision
    (see "Backup design" in [README.md](README.md)).
