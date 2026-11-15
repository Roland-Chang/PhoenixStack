# pve01 rebuild: current state

Snapshot as of **2026-11-14**. This file is for picking the rebuild up on another computer. The full
design and runbook are in [README.md](README.md). This file records where things stand and how the plan
changed from that runbook.

## Where things stand

| Item | State |
| --- | --- |
| Old pve01 | **Gone.** Phases 1–3 of the README (capture, rehearsal, cutover backup on the old host) no longer apply. |
| Guest backups | **Exist on the NAS** in `Backups/pve01` (mounted as `/mnt/nas/nas-dump` once the bootstrap has run). Phase 7 restores from them. |
| Node config | [config/pve01.conf](config/pve01.conf) is complete: no `REPLACE_ME` outside comments. |
| ASUS Hyper M.2 + Samsung 990 Pro | **Not installed now.** The `data` pool, `data/models` dataset and `data` storage stay commented out in the config. Nothing in the ISO or bootstrap depends on them. |
| Install (Phases 4–5) | **Done.** Checked 2026-11-14: FQDN, timezone, keyboard, root mail, IP/gateway, NIC pinning (`nic0` = 4C:D9:8F:0C:15:3E), rpool mirror of the 2 Intel SSDs (ashift 12, lz4), ARC 24 GiB and root SSH key all match the config. PVE 9.2.2, kernel 7.0.2-6-pve. |
| Unattended installer ISO | Contains the root password hash. **Delete every copy** (`/home/ayoung/iso/pve01-auto.iso` on the Mint workstation, and any copy on the NAS). |
| Old `nvme` / `ssd` pools | Still on their disks (importable, not imported). Wiped by `storage --destroy-data`. |
| Bootstrap plan | Runs clean with no `--apply`. The disk paths in all three pool layouts match the real disks. |
| Bootstrap applied | `repos` (PVE 9.2.27, kernel 7.0.14-29), `system`, `network` (bond0 + VLAN-aware vmbr0, 10 Gb/s), `kernel` (IOMMU on, P2000 on vfio-pci). All verified 2026-11-14. `kernel` will be re-run once for `l1tf=flush,nowarn`. |
| Bootstrap applied (cont.) | `kernel` re-run with `l1tf=flush,nowarn` (warning gone, mitigation unchanged). `nas`: both shares mounted, `nas-iso` and `nas-dump` storages added. |
| Guest archives | Checked 2026-11-14. Newest of lxc-100, lxc-999 and qemu-9999 to be marked Protected. |
| Next step | Protect the 3 archives, then `storage --destroy-data` |

> **The ISO contains the root password hash.** Don't commit it or leave copies around. Delete every copy
> after the install. The password itself is in 1Password (`infrastructure` vault).

## Changes from the README runbook

- **Phases 1–3 skipped**: the old host no longer exists.
- **Phase 2 (build ISO) ran on the workstation, not the old host**: inside a `debian:trixie` Podman
  container, with `--skip-device-check`, because there was no target hardware to check against. The
  hardware check moves to the debug shell before install (see step 2 below).
- **Disk IDs were never checked against a capture.** Check them on the new host before the
  `storage` stage (see step 5 below).

## Remaining steps

### 1. BIOS and controller settings (iDRAC console), README Phase 4

- SATA controllers **RAID → AHCI**.
- PERC H740P **Enhanced HBA**, delete all virtual disks, every backplane disk **Non-RAID**.
- Virtualization, VT-d/IOMMU, SR-IOV **on**. Boot mode **UEFI**.

### 2. Optional: confirm the installer filters on the real hardware

Boot the **regular** Proxmox VE 9 ISO → *Advanced Options → Install Proxmox VE (Terminal UI, Debug
Mode)*. At the shell:

```bash
for d in /sys/block/sd*; do udevadm info -q property -n ${d##*/} | grep -E '^(DEVNAME|ID_MODEL)='; done
ip -br link | grep -i 4c:d9:8f:0c:15:3e
```

Expect **exactly 2** disks with `ID_MODEL=INTEL_SSDSC2BF240A4L` and **1** interface with that MAC.
Then power off. If the output differs, fix `INSTALL_DISK_FILTER` / `UPLINK_MACS` and rebuild the ISO.

### 3. Install

1. Mount `pve01-auto.iso` through iDRAC Virtual Media (from the virtual console, or copy it to the NAS ISO share).
2. Boot it (UEFI). It picks *Automated Installation* by itself, installs in about 10 minutes, and reboots.
3. Unmount it, then **delete every copy** of `pve01-auto.iso`.

What the ISO installs: `pve01.int.phoenixstack.net`, `10.101.0.11/24`, gateway and DNS `10.101.0.254`,
ZFS RAID1 on the 2 Intel SSDs (ashift 12, lz4, ARC max 24 GiB), the uplink NIC selected by MAC with
pinned interface names, and the root SSH key from the config.

### 4. First login

```bash
ssh-keygen -R 10.101.0.11
ssh root@10.101.0.11          # key login, no password
```

### 5. Bootstrap, README Phase 6

```bash
scp -r proxmox root@10.101.0.11:/root/phoenix
ssh root@10.101.0.11
cd /root/phoenix/bootstrap
B="./pve-bootstrap.sh --config ../config/pve01.conf"
$B                                   # full plan: read it end to end
```

**Before the `storage` stage:** run `ls -l /dev/disk/by-id/` and check that every disk path in
`ZFS_POOL_nvme_LAYOUT`, `ZFS_POOL_ssd_LAYOUT` and `ZFS_POOL_backup_LAYOUT` exists. The PERC Non-RAID
conversion changes how the backplane disk names look. Fix the config first if any path is missing.

Then run the stages in order: `repos`, `system`, `network`, `kernel` (reboot), `nas`, then **check the
guest archives on `/mnt/nas/nas-dump` and mark them Protected**, then `storage --destroy-data`,
`access`, `firewall`, `verify`. The README has the exact commands and prompts.

### 6. Restore guests, README Phase 7

- **First**, mark the pre-rebuild archives **Protected** in the GUI (nas-dump → Backups), or `keep-daily=7` deletes them after a week.
- Restore only the three production guests: AMP-TEMP (lxc 100, from the **2026-11-12 19:32** archive; it's smaller because files were removed on purpose), docker-temp (lxc 999), PLEX-TEMP (qemu 9999). FTP01 and INTEL01 are retired and not restored.
- **Watch the VMIDs:** `nas-dump` also has archives from older guests that reused these IDs (`qemu-100`, `lxc-9999`, …). Pick archives by type and ID: `vzdump-lxc-100-…`, `vzdump-lxc-999-…`, `vzdump-qemu-9999-…`.
- `ssd` holds only about 238G. Check AMP-TEMP's disk size before restoring it there. Use `nvme` if it doesn't fit with room to spare.
- docker-temp (999): `pct set 999 --delete mp0,mp1`, then point `mp2`/`mp3` at the `/mnt/nas/...` mounts before starting it.

### 7. Close-out, README Phase 8

`verify` passes, one test restore, old tokens and SMB credentials rotated, config changes committed.

## Rebuilding the ISO on another computer

Only needed if the ISO is lost or the config changes. Requires Podman (`sudo apt install podman` on Mint or Ubuntu).

```bash
mkdir -p ~/iso                       # put proxmox-ve_9.x-y.iso here
cd <repo root>
sudo podman run --rm -it -v "$PWD/proxmox:/work" -v "$HOME/iso:/iso" debian:trixie bash
```

Inside the container:

```bash
apt-get update && apt-get install -y wget openssl
wget -O /usr/share/keyrings/proxmox-archive-keyring.gpg \
  https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg
cat > /etc/apt/sources.list.d/pve.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
apt-get update
cd /work/install
./prepare-iso.sh --config ../config/pve01.conf --iso /iso/proxmox-ve_9.x-y.iso \
  --out /iso/pve01-auto.iso --skip-device-check
exit
```

Back on the host, make yourself the owner of the ISO (it's created as root, mode 600):

```bash
sudo chown "$USER": ~/iso/pve01-auto.iso
```
