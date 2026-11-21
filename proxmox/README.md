# Proxmox host: design and rebuild runbook

Purpose: how the PhoenixStack Proxmox host (pve01) is designed, and the exact steps to
rebuild it from bare metal to a verified baseline. This covers **L0–L4**:
host → network → storage → access → backups and alerts. Guests and services (L5+) come after.

| Path | What it is |
| --- | --- |
| [config/pve01.conf](config/pve01.conf) | Node config. The single source of truth for all scripts. No secrets. |
| [pre-rebuild/pre-rebuild.sh](pre-rebuild/pre-rebuild.sh) | Runs on a host **about to be reinstalled**. Captures its config and takes verified guest backups. |
| [install/prepare-iso.sh](install/prepare-iso.sh) | Builds an unattended PVE 9 installer ISO from the config. |
| [bootstrap/pve-bootstrap.sh](bootstrap/pve-bootstrap.sh) | Post-install baseline, in stages. Plan by default, `--apply` to change. |
| [REBUILD_STATE.md](REBUILD_STATE.md) | Where the host stands today and what's still open. |

---

## Design decisions

First written 2026-11-08; later decisions carry their own date.

| Area | Decision | Why |
| --- | --- | --- |
| Boot | ZFS **mirror** on 2× Intel 240G SSD | The old boot pool was a stripe, so losing one disk lost the host. |
| VM tier | `nvme`: mirror of 2× Micron 7300 960G, each on its own single M.2 adapter (slots 5 and 7) | Enterprise drives with power-loss protection suit VM disks. One drive per adapter, so the mirror survives an adapter failure. |
| General tier | `ssd`: mirror of 2× Micron 256G SATA (~238G) | Templates and light containers until the `data` pool arrives. |
| Backup tier | `backup`: RAIDZ1 of 4× 1.2TB SAS **+ special vdev** (mirror of 2× Micron 256G SATA) → `backup/pbs` | Slow disks suit backups. Metadata on SSD keeps PBS garbage collection and verify fast. |
| Backups | **Two nightly copies:** to a local PBS (long history) and, separately, a vzdump to the NAS (7 days) | Fast local restores and cheap retention from PBS; a NAS copy that restores on a bare Proxmox install with no PBS. See "Backup design". |
| Data tier (future) | `data`: 2× mirrors of 4× Samsung 990 Pro 1TB on the ASUS Hyper M.2 card (slot 3, CPU 1) → `data/models` | LLM models and general storage, kept apart from VM disk I/O. Same CPU as the 3070. Added after the rebuild (see Operating notes). |
| Boot pool use | OS only. `local-zfs` removed, `/var/lib/vz` capped at 32G | 257G of unknown data had filled the old boot pool. |
| Network | Onboard 10GBASE-T port 1, found by MAC → `bond0` → **VLAN-aware** `vmbr0` | Guests pick a VLAN by tag. Adding onboard port 2 / LACP later is a config change. The GPU kit's external fans block every PCIe slot's rear opening except slot 4, so only a slot-4 card can be cabled. |
| Mgmt VLAN | Host IP `10.101.0.11/24`, untagged on `vmbr0` (VLAN 10 native on the switch). The UniFi network (PHOENIX-PRIMARY) is `10.101.0.0/24`, gateway `.254`, and its DHCP also serves the restored guests. Back to `/24` on 2026-11-20 (it was `/23`); fixed addresses are below `.100`. | No switch change needed for the rebuild. `MGMT_VLAN=10` switches it to tagged. The mask must match UniFi, or host-to-guest traffic routes asymmetrically through the gateway. |
| Domain | `int.phoenixstack.net` (was `phoenix.stack`) | Real domain, so real TLS via Cloudflare DNS-01. The real addresses are only in the UDM's local DNS. Public DNS answers too, but with the zone's wildcard record (Cloudflare proxy), never an internal address. Host names in certificates are public (Certificate Transparency logs). |
| Firewall | Datacenter `policy_in: DROP`; GUI/SSH/SPICE/ping only from the `management` ipset. Dropped inbound packets are logged (`FIREWALL_LOG_LEVEL_IN="info"`, rate-limited) to `/var/log/pve-firewall.log`. | The old firewall was enabled but accepted everything. The log shows who is knocking on the host: a guest probing the admin ports is the thing to look for. |
| Admin sources | `10.1.1.69/32` (Young admin workstation), `10.1.1.169/32` (Aaron's laptop on the home LAN, added 2026-11-21), `10.2.1.69/32` (Porter admin workstation, over the BPorter site-to-site VPN) and `192.168.2.0/24` (Teleport VPN clients). Not the mgmt subnet. Narrowed 2026-11-20 from the whole Young and Porter LANs, to match the UDM's Management zone. | Guests get DHCP addresses on the mgmt subnet and must not reach the host's SSH or GUI. The UDM enforces the same list; this is the second lock, so a loosened UniFi rule doesn't expose the host. Anyone holding a Teleport invite can reach the login pages (logins still need the SSH key, or a password plus TOTP), so keep invites few. The iDRAC console is the fallback. |
| Access | Personal admin users in an `admins` group, with TOTP. Root for break-glass only. Service accounts get privilege-separated tokens with exactly the grants in `SERVICE_ACCOUNTS` (others are removed). Terraform's token works only on guests in pool `terraform` (2026-11-20; see [../guests/README.md](../guests/README.md)). | Named accounts, least privilege. |
| GPU | Quadro P2000 bound to `vfio-pci` at boot; IOMMU passthrough | Reserved for the Plex VM. The host never loads NVIDIA drivers. |
| IPv6 | No RA or autoconfiguration on the host (the stack stays loaded) | Follows the "IPv6 off unless needed" guardrail without breaking PVE daemons. |
| Secrets | Prompted at run time, or read from env vars, then stored root-only on the host. Never in git or logs. | Repo guardrail. |
| PBS | Proxmox Backup Server **on the host itself** (decided 2026-11-14), datastore `pve01-local` on `backup/pbs`. Server-side prune (daily 04:00: 14 daily, 8 weekly, 6 monthly), GC 04:30, weekly verify (Sat 05:00, re-verify after 30 days). PVE reaches it as storage `pbs-local` with token `pve01@pbs!backup`, role **DatastoreBackup** (it can back up and restore, but can't delete). GUI on 8007 from `+management` only. No client-side encryption. With the Let's Encrypt certificate (`acme` stage) the storage connects to `pve01.int.phoenixstack.net` and checks the certificate normally; before that, to 127.0.0.1 with a pinned fingerprint. | Simplest of the options. A separate container or VM wouldn't make PBS independent of this host; the NAS job is the off-host copy. Pruning on the server means a compromised PVE token can't delete history. Encryption adds a key to lose and protects nothing extra while the datastore is on the same host. |
| Alerts | Everything goes to `alerts@phoenixstack.net` (`ROOT_EMAIL`) through the SMTP target `brevo` (smtp-relay.brevo.com:587, STARTTLS), set up in both PVE and PBS. PVE matchers: `phoenix-alerts` (warnings and errors), `phoenix-backups` (every backup result, for the first weeks), `phoenix-system-mail` (mail the host's daemons send to root: ZFS events, smartd, cron) and `phoenix-updates` (new package updates). PBS matcher: `phoenix-alerts` (failed prune, GC and verify jobs). The built-in `mail-to-root` targets are disabled. | A silent failure (disk, ZFS, backup) is the main risk to a single host. The host's local mail can't deliver off-host (outbound port 25 is blocked), so nothing may depend on it. The SMTP login, From address and key aren't in this public repo: they're entered when the `notify` stage runs. To change the sender later, run `notify` and `pbs` with `NOTIFY_SMTP_FROM` set. |
| Patching | **Weekly, by hand** (decided 2026-11-16). Nothing installs itself. The host checks for updates daily and emails `alerts@` when new packages appear (matcher `phoenix-updates`). Once a week: `apt update && apt dist-upgrade`, then reboot if a new kernel was installed. `verify` shows pending updates and fails if the running kernel isn't the newest installed. | A kernel or QEMU update applying itself on a single host would take the guests down, or change things under them, with nobody watching. Weekly keeps the delay for a security fix to days. The cost: it depends on someone acting on the emails. See "Weekly patch window" in the Operating notes. |
| CPU side channels | Microcode kept current (`intel-microcode` + Dell BIOS). Downfall left unmitigated; SMT (Hyper-Threading) left on. | All guests are trusted. The fixes would cost AVX or half the threads. See "Accepted risks". |
| Automation | This script for the host (L0–L4). **Terraform creates guests and Ansible configures them from L5 on** (decided 2026-11-16). | Terraform can't install packages, build pools or harden the host, and needs the API token this script creates. An Ansible port would be days of work re-proven on the only production host, with most Proxmox objects ending up as shell commands in YAML. The script also runs from the iDRAC console when the network is down. Look again if a second host is added. |

### Backup design

Two independent copies, made by two different tools, on two devices:

| Job | Target | Schedule | Retention | Restores from |
| --- | --- | --- | --- | --- |
| **Local** (`nightly-pbs`) | PBS on pve01 → datastore on `backup/pbs` | Nightly **01:00** | `PBS_KEEP`: 14 daily, 8 weekly, 6 monthly (cheap: incremental and deduplicated) | PBS, on pve01. The normal "I broke a VM" restore. |
| **Off-host** (`nightly-nas`) | vzdump (zstd) → `nas-dump` (NAS `Backups/pve01`) | Nightly **03:30** | `NAS_DUMP_PRUNE`: 7 daily | Plain archives. After losing pve01: reinstall Proxmox, mount the NAS, `qmrestore`/`pct restore`. No PBS needed. |

- **Both jobs back up all guests** in snapshot mode, so a new guest is included automatically. They're created by the `pbs` and `backups` stages.
- **Stagger the jobs** so they never overlap (each one snapshots every guest and reads its disks).
- **Expect PBS to read whole VM disks each night.** PBS normally reads only the blocks a VM changed since its last backup, but backing the same VM up to a *different* target (the NAS job) resets that tracking. The upload to PBS is still deduplicated, so only the reading costs more. Fine at this size; if it ever gets slow, move the NAS job to weekly.
- **Exclude what can be re-downloaded or lives elsewhere:** `data/models`, and any NAS bind mounts (containers' `mpX` with `backup=0`).
- **NAS space:** about 7× the compressed size of all guests.
- **Both copies are in the same building.** An offsite copy is an open decision.

### Accepted risks

Recorded 2026-11-14. Accepted by Aaron Young. Each risk depends on one assumption: **every guest
and every workload on pve01 is ours and trusted.** If that stops being true, look at these again first.

The CPUs are 2× Xeon Gold 5118 (Skylake-SP, 2017). Intel no longer supports them: microcode `0x2007006`
is the last release, and it's already loaded (`intel-microcode` 3.20251111 and BIOS 2.29.2 are both current).
So no microcode or BIOS update can close these. The only fixes left take performance away.

| # | Risk | Kernel reports | What an attacker could do | Fix we're not taking, and its cost |
| --- | --- | --- | --- | --- |
| R1 | **Downfall** (GDS, CVE-2022-40982) | `gather_data_sampling: Vulnerable` | Code running in one guest or process reads data from another one running on the **same physical core**. That data can include keys and passwords, because it leaks through AVX registers, which crypto code uses heavily. | Kernel option `gather_data_sampling=force` turns **AVX off**. ZFS checksums and RAIDZ parity, compression, TLS, media transcoding and AI workloads would all slow down noticeably. |
| R2 | **Leaks between Hyper-Threads** (L1TF, MDS, MMIO Stale Data, TAA) | `Mitigation: …; SMT vulnerable` | The same kind of leak between the two Hyper-Threads of one core. A guest on one thread can read another guest's data on its sibling thread. The other paths are already mitigated. | Kernel option `nosmt` (or Hyper-Threading off in the BIOS) halves the threads, **48 → 24**. |

**What accepting them means**

- An attacker first has to **run code on this host**: a compromised guest, a malicious container image or
  package, or a hostile tenant. These flaws don't make the host reachable from the network. They make an
  intrusion that has already happened worse, because one compromised guest becomes a way to read the others' data.
- The guests most worth protecting from that are the ones holding credentials: identity, secrets
  management, the password-manager integration, and the backup server. Planned services like these are exactly what
  a compromised neighbour would read. Keep containers' and guests' software up to date and from trusted
  sources, because that's the control actually doing the work here.
- Leaving this unmitigated doesn't affect stability or correctness. It's a confidentiality risk only.

**Boot warning for R2 turned off.** On every boot, KVM logged `L1TF CPU bug present and SMT on, data
leak possible`. Because R2 is an accepted, documented decision, the kernel option `l1tf=flush,nowarn` (in
`KERNEL_CMDLINE_ADD`) turns that warning off. Protection stays exactly the same: `flush` is the kernel's
default L1TF mitigation, and `nowarn` only silences the message. The risk stays visible in
`/sys/devices/system/cpu/vulnerabilities/l1tf` ("SMT vulnerable") and in the recheck below. **If R2 is
reopened, remove `l1tf=flush,nowarn` from the config and from `/etc/kernel/cmdline` on the host, then run
`proxmox-boot-tool refresh` and reboot.** The bootstrap only adds kernel options, never removes them.

**Look at this again if:**

- any guest runs code we don't control: a VM for a friend, a public CI runner, untrusted
  containers or images, a sandbox for testing malware;
- a guest holds data where a breach would be serious enough to justify the performance cost;
- the CPUs are replaced. A newer generation may fix these in hardware, so remove the entries that no longer apply.

**Recheck after any kernel or BIOS change:**

```bash
grep -H . /sys/devices/system/cpu/vulnerabilities/* | sed 's|.*/||'
journalctl -k -b | grep -i microcode
```

R1 and R2 should be the **only** lines that aren't `Not affected` or fully mitigated. Anything new is a
new decision to make, not something already covered by this one.

---

## Runbook

### Phase 0: Prerequisites (no downtime)

- [ ] iDRAC works from your workstation: virtual console **and** virtual media.
- [ ] Create these in 1Password (`infrastructure` vault):
  - new root password
  - `svc_proxmox` SMB credentials
  - the Brevo SMTP login and SMTP key (`xsmtpsib-…`, not the API key), and the From address, which must be a verified sender in Brevo
  - a Cloudflare API token limited to the `phoenixstack.net` zone, with `DNS:Edit` and `Zone:Read` (item `Cloudflare PVE Token`)
  - empty items to receive the new API tokens later
- [ ] The alert mailbox `alerts@phoenixstack.net` exists and receives mail.
- [ ] Download the latest **Proxmox VE 9.x ISO** to the NAS: share `Media`, folder `Software/ISO/template/iso` (PVE looks for ISOs in `template/iso` under the storage path).
- [ ] Add a local DNS record on the UDM: `pve01.int.phoenixstack.net → 10.101.0.11`. Without it the name resolves to Cloudflare's addresses (the zone has a wildcard record), and the GUI can't be reached by name.
- [ ] Workstation set up as in "Admin workstation" under Operating notes.

Phases 1–3 run on the host being replaced. If it's already gone, start at Phase 2 (workstation build) and Phase 4.

### Phase 1: Capture and rehearse (on the host being replaced, no downtime)

```bash
scp -r proxmox root@10.101.0.11:/root/phoenix
ssh root@10.101.0.11
cd /root/phoenix/pre-rebuild
./pre-rebuild.sh --capture          # writes to the NAS (storage nas-dump): Backups/pve01/rebuild-<timestamp>/
./pre-rebuild.sh --backup-guests    # rehearsal backup; guests keep running
```

Then fill every `REPLACE_ME` in `config/pve01.conf` using `host-inventory.txt` from the capture:

- `UPLINK_MACS`: already set to onboard 10GBASE-T port 1 (taken from the iDRAC inventory).
- `ROOT_SSH_KEYS`, `ROOT_EMAIL`, admin user email.
- Check that every `/dev/disk/by-id/...` path in the pool layouts appears in the capture.
- Check `/var/lib/vz` in the capture. **It is wiped.** Copy off anything you want to keep.
- docker-temp's media and porter bind mounts come from the NAS shares `Media` and `Porter` (`NAS_MOUNTS`, mounted by the `nas` stage).

### Phase 2: Build the installer ISO

**On the host being replaced** (preferred):

```bash
cd /root/phoenix/install
./prepare-iso.sh --config ../config/pve01.conf \
  --iso /mnt/nas/nas-iso/template/iso/proxmox-ve_9.x-y.iso \
  --out /root/pve01-auto.iso
```

The script proves that the disk filter matches **exactly** the 2 Intel SSDs, and the NIC filter matches onboard 10GBASE-T port 1, before it builds anything.

**On a workstation**, when that host is gone (this is how the 2026-11 rebuild was done). Requires Podman:

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

Then `sudo chown "$USER": ~/iso/pve01-auto.iso` (it's created as root, mode 600). `--skip-device-check` means the filters were **not** proven, so check them on the real hardware: boot the regular Proxmox VE 9 ISO → *Advanced Options → Install Proxmox VE (Terminal UI, Debug Mode)*, and at the shell run:

```bash
for d in /sys/block/sd*; do udevadm info -q property -n ${d##*/} | grep -E '^(DEVNAME|ID_MODEL)='; done
ip -br link | grep -i 4c:d9:8f:0c:15:3e
```

Expect exactly 2 disks with `ID_MODEL=INTEL_SSDSC2BF240A4L` and 1 interface with that MAC. If not, fix `INSTALL_DISK_FILTER` / `UPLINK_MACS` and rebuild the ISO.

### Phase 3: Cutover backup (downtime starts)

```bash
cd /root/phoenix/pre-rebuild
./pre-rebuild.sh --backup-guests --final   # shuts down all guests, backs up, verifies
```

> Every archive must show ✓. **Don't continue if any shows ✗.**

### Phase 4: BIOS and controller settings (iDRAC console)

- [ ] SATA controllers: **RAID → AHCI**.
- [ ] PERC H740P: **Enhanced HBA** personality, so the backplane disks reach ZFS raw.
- [ ] **No virtual disks on the PERC.** Delete every one (iDRAC → Storage → Virtual Disks), then convert all backplane disks to **Non-RAID** (Physical Disks → Convert to Non-RAID). Single-disk RAID0 "NonRAID Disk N" volumes are *not* Non-RAID: they hide the real disks, change their `/dev/disk/by-id` names, and block SMART. Check: every backplane disk shows **Non-RAID**.
- [ ] Virtualization Technology **on**; VT-d / IOMMU **on**; SR-IOV Global **on**.
- [ ] Boot mode **UEFI**. Secure Boot is your choice: the bootstrap handles systemd-boot and GRUB.
- [ ] Optional: update the BIOS, iDRAC, PERC and NIC firmware while you're here.

### Phase 5: Install

1. Mount `pve01-auto.iso` through iDRAC Virtual Media and boot from it.
2. It selects **Automated Installation** on its own. The install takes about 10 minutes, then the host reboots.
3. Unmount the ISO, then **delete every copy of `pve01-auto.iso`**. It contains the root password hash.
4. From your workstation, run `ssh-keygen -R 10.101.0.11` (the host key changed), then `ssh root@10.101.0.11`. This should work with your key and no password.

> **Point of no return.** Until Phase 6 `storage --destroy-data`, the old `nvme` and `ssd` pools are untouched. They can still be brought back with `zpool import -f nvme`.

### Phase 6: Bootstrap (stage by stage)

Prefer the iDRAC console or `tmux` for the `network` and `firewall` stages.

```bash
ssh root@10.101.0.11 mkdir -p /root/phoenix   # once, on a fresh host
pve-sync                             # on the workstation: copies proxmox/ to /root/phoenix
ssh root@10.101.0.11
cd /root/phoenix/bootstrap
B="./pve-bootstrap.sh --config ../config/pve01.conf"

$B                                   # full plan: read it end to end
$B --apply --stage repos             # then reboot if told to
$B --apply --stage system
$B --apply --stage network           # type "keep" when asked
$B --apply --stage kernel && reboot
$B --apply --stage nas               # SMB password prompted; mounts the NAS
ls -lt /mnt/nas/nas-dump/dump/ | head -20   # STOP unless every guest's archive is here
$B --apply --stage storage --destroy-data   # type "destroy-<pool>" for each pool
$B --apply --stage access            # store each token in 1Password when shown
$B --apply --stage templates         # Debian container template and Debian cloud VM template for guests
$B --apply --stage firewall          # test GUI + a NEW ssh session, then type "keep"
$B --apply --stage notify            # SMTP login, From address and key prompted; sends a test
$B --apply --stage pbs               # installs PBS; datastore, jobs, token, its own alerts
$B --apply --stage acme              # certificates for both GUIs; Cloudflare token prompted
$B --apply --stage backups           # nightly jobs (they need the guests restored to do anything)
$B --apply --stage verify
$B                                   # re-plan: should report 0 changes pending
```

Before `storage --destroy-data`:

- The old `nvme`/`ssd` pools are the last copy of the guests besides the NAS. After the `nas` stage, check that an archive for every guest is listed, and mark them **Protected** (GUI: nas-dump → Backups) so the `keep-daily=7` prune can't remove them.
- Run `ls -l /dev/disk/by-id/` and check that every disk path in the pool layouts exists. Converting PERC disks to Non-RAID changes their names.

After the `notify` and `pbs` stages: check that both test emails (one from PVE, one from PBS) arrived at `alerts@`, junk folder included. Then send one through the host's own mail, the route ZFS, smartd and cron use, and check it arrives too:

```bash
printf 'Subject: pve01 root mail test\n\nTest.\n' | sendmail root
mailq                                # should say "Mail queue is empty"
```

The `acme` stage asks you to accept Let's Encrypt's terms twice, once for PVE and once for PBS, and whether to use external account binding: answer **no** (Let's Encrypt doesn't use it). It then asks for the Cloudflare token once. Afterwards both `https://pve01.int.phoenixstack.net:8006` and `:8007` open without a certificate warning, and `pvesm list pbs-local` lists the backups.

After the `access` stage:

- Log in as your admin user and enroll **TOTP** for it and for `root@pam`. Do this in the GUI: Datacenter → Permissions → Two Factor. Do the same in the PBS GUI (port 8007) after the `pbs` stage.
- Update 1Password `infrastructure/(Proxmox) Claude API` (field `credential`) with the new `claude-audit@pve!discovery` token.

### Phase 7: Restore guests

Backups are on `nas-dump` (the same NAS folder as before, mounted at `/mnt/nas/nas-dump`).

> **Check sizes first.** `ssd` is now a single mirror (~238G usable, was ~500G). Before restoring AMP-TEMP to `ssd`, check its disk size in the backup (`ls -lh` on the archives is a lower bound; the GUI's restore dialog shows the configured disk sizes). If it won't fit with room to spare, it goes to `nvme` instead.
>
> FTP01 (9000) and INTEL01 (9001) are **retired** (decision 2026-11-14). They aren't restored. INTEL01 had no VM backup.
>
> **Pick archives by type and ID**, never by ID alone: `nas-dump` also holds archives of older guests that reused these VMIDs (`qemu-100`, `lxc-9999`, …).

```bash
ls -lt /mnt/nas/nas-dump/dump/*.zst | head
qmrestore /mnt/nas/nas-dump/dump/vzdump-qemu-9999-<ts>.vma.zst 9999 --storage nvme   # PLEX-TEMP
pct restore 100 /mnt/nas/nas-dump/dump/vzdump-lxc-100-<ts>.tar.zst --storage ssd     # AMP-TEMP
pct restore 999 /mnt/nas/nas-dump/dump/vzdump-lxc-999-<ts>.tar.zst --storage nvme    # docker-temp
```

**docker-temp (999)** had host bind mounts that no longer exist. Before starting it:

```bash
pct set 999 --delete mp0,mp1                                  # drop backups + ISO shares (security)
pct set 999 --mp2 /mnt/nas/media,mp=/mnt/pve/cifs-media       # same in-container path
pct set 999 --mp3 /mnt/nas/porter,mp=/mnt/pve/cifs-porter     # same in-container path
```

Start each guest and check it works. MAC addresses are kept, so DHCP leases don't change. Guests stay untagged on `vmbr0` (the mgmt network) for now; where they move is part of the L5 design.

### Phase 8: Close-out

- [ ] `$B --stage verify` passes with no `FAIL`, and a full plan shows 0 changes pending.
- [ ] TOTP enrolled for every admin login, in PVE and in PBS.
- [ ] Alerts reach `alerts@` from PVE, from PBS and from the host's own mail (tests above).
- [ ] The first scheduled `nightly-pbs` and `nightly-nas` runs succeeded and their result emails arrived.
- [ ] One test restore of a small guest from `nas-dump` to a scratch VMID, then deleted.
- [ ] First weekly patch run done ("Weekly patch window" below).
- [ ] Old `terraform-token` and the old SMB credentials rotated or retired.
- [ ] Re-run Claude's read-only discovery and compare against this design.
- [ ] Commit any config changes made along the way, and update [REBUILD_STATE.md](REBUILD_STATE.md).
- [ ] Weeks later, once the new backups have history: remove the **Protected** flag from the pre-rebuild archives, and set `NOTIFY_ALL_BACKUP_JOBS="no"` so only failed backups are emailed.

---

## Operating notes

- **Admin workstation.** Three things on the machine you administer from:
  1. An alias that copies this folder to the host. In `~/.bash_aliases`:
     `alias pve-sync='scp -r ~/Desktop/phoenix-stack-claude/PhoenixStack/proxmox/. root@10.101.0.11:/root/phoenix/'`.
     The `/.` matters: without it, a second run puts a nested copy in `/root/phoenix/proxmox` and the old scripts keep running. The first line of every bootstrap run shows the script's version, which should match `VERSION` in the repo. Raise `VERSION` whenever the script changes.
  2. SSH uses the 1Password agent for the host under every name you type. SSH matches `Host` rules against the name typed, not the address, so list them all in `~/.ssh/config`:
     `Host 10.101.0.* pve01 pve01.int.phoenixstack.net` with `IdentityAgent ~/.1password/agent.sock` and `User root`.
  3. Over the VPN, a hosts entry `10.101.0.11 pve01.int.phoenixstack.net` (and `pve01`, if you use the short name). The UniFi WiFiman client sends all lookups to public DNS, where the zone's wildcard record answers instead of the UDM. On the home LAN the UDM's record is enough.
- **Weekly patch window.** In `tmux` on the host:
  1. `apt update && apt dist-upgrade`. Always `dist-upgrade` (or `full-upgrade`), never plain `apt upgrade`: Proxmox updates often add or replace packages, and `upgrade` would hold them back. This updates PVE and PBS together.
  2. If a new kernel was installed, reboot at a quiet time. Guests shut down and come back by themselves (`onboot: 1`); expect a few minutes of downtime.
  3. `$B --stage verify`: "no package updates pending" and "running newest installed kernel" should both pass.
  4. After a kernel or BIOS change, run the recheck under "Accepted risks".
- **Re-runnable.** Every stage checks the current state first. Running it again on a correct host changes nothing.
- **Backups of replaced files** are kept in `/var/backups/phoenix-bootstrap/<run-id>/`, along with `run.log`.
- **Adding onboard port 2 / LACP:**
  1. Cable port 2 (second SFP+ → 10GBASE-T module on the switch) and set up the LAG on the USW Aggregation switch.
  2. Add port 2's MAC (in the comment in `pve01.conf`) to `UPLINK_MACS` and set `BOND_MODE="802.3ad"`.
  3. Run `--apply --stage network`.
- **The `data` pool (Samsung 990 Pro 1TB, grown 1 → 2 → 4 drives).** Every step is online and keeps existing data. **Update each drive's firmware before it goes in** (Samsung's bootable ISO, or Magician on another PC); early 990 Pro firmware had a health-degradation bug.
  - **Card setup (once):** the ASUS Hyper M.2 goes in **slot 3**, which must be split into 4× x4 links (it defaults to x16). If a drive doesn't appear, set Slot 3 bifurcation manually (BIOS → Integrated Devices → Slot Bifurcation). Leave **slot 1 at x16** for the 3070. Fill card positions 1, 2, 3, 4 in that order.
  - **Get a drive's path:** `ls -l /dev/disk/by-id/ | grep -i samsung | grep -v part`. Use the `nvme-Samsung_SSD_990_PRO…_<serial>` line **without** a trailing `_1`.
  - **Drive 1: create the pool.** Fill the path in `ZFS_POOL_data_LAYOUT` and uncomment it, uncomment the `data/models` dataset and the `data` storage line, and add `data` to `ZFS_POOLS`. Run `$B` (plan: it should propose only the new pool, dataset and storage), then `$B --apply --stage storage`. **No redundancy yet:** keep only re-downloadable models on `data` until drive 2 is attached.
  - **Drive 2: make it a mirror.** `zpool attach data <990-1-by-id> <990-2-by-id>`, then wait for `zpool status data` to show the resilver finished and `mirror-0` ONLINE. Use **`attach`**, not `add`: `add` would put the new drive alongside the first with no redundancy.
  - **Drives 3 and 4: add a second mirror.** Dry run first, and check the output shows two `mirror` groups: `zpool add -n data mirror <990-3-by-id> <990-4-by-id>`. Then run it without `-n`. Leaving out the word `mirror` would add two unprotected disks. Existing data stays on the first mirror; new writes spread across both.
  - **After each step:** update `ZFS_POOL_data_LAYOUT` to the pool's real layout (`zpool status data`) and commit, so the config matches the host.
- **Changing admin networks:** edit `ADMIN_SOURCES`, then run `--apply --stage firewall`.
- **ACME:** covers the PVE GUI (8006) and the PBS GUI (8007); each product renews its own certificate. The stage also re-creates the `pbs-local` storage so PVE reaches PBS by name: a pinned fingerprint would break backups at every renewal. Set `ACME_ENABLE="yes"`. This needs a Cloudflare token limited to the `phoenixstack.net` zone, with `DNS:Edit` and `Zone:Read` (1Password: `infrastructure` / `Cloudflare PVE Token`). Then run `--apply --stage acme`.
