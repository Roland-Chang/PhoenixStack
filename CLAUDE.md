# PhoenixStack: notes for Claude

Read [README.md](README.md) first, then [proxmox/REBUILD_STATE.md](proxmox/REBUILD_STATE.md) for where the rebuild stands.

## Guardrails

- **No secrets** in code, docs, commits, PRs or chat output. Secrets live in 1Password and are entered at run time.
- **Dry run first.** Run `pve-bootstrap.sh` without `--apply` (plan mode), `tf plan`, and Ansible with
  `--check --diff`, before any change. Show the plan, then get approval for destructive or outward-facing steps:
  `--destroy-data`, network/firewall stages, pushes.
- **Protect the guest backups** on the NAS (`Backups/pve01`) until the restored guests are verified.
- **Small steps:** one layer at a time (see the status table in README.md). Don't start new layers or services
  unless asked.
- `archive/` is **reference only**: don't edit it, deploy from it, or treat its docs as current fact.
  Bring things back out only after reviewing them against `proxmox/README.md`.

## Working notes

- Files keep LF line endings (root `.gitattributes`; `archive/` is left as it is).
- pve01 is `10.101.0.11` (mgmt VLAN, reached through the UDM from the admin sources in `ADMIN_SOURCES`:
  the Young admin workstation and laptop `10.1.1.69` and `10.1.1.169`, the Porter admin workstation and laptop
  `10.2.1.69` and `10.2.1.169`, and Teleport VPN clients `192.168.2.0/24`).
  Repeated SSH from the home LAN used to be cut off for a few minutes: the UDM's IPS took it for an SSH scan.
  Fixed 2026-11-21 by putting the admin workstation and laptop on the IPS "Detection Exclusions" list. If SSH
  times out while ping and the GUI work, check that list first (e.g. for a new admin address).
  Use the iDRAC console or tmux for the network/firewall stages.
