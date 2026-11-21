# PhoenixStack: notes for Claude

Read [README.md](README.md) first, then [proxmox/REBUILD_STATE.md](proxmox/REBUILD_STATE.md) for where the rebuild stands.

## Guardrails

- **No secrets** in code, docs, commits, PRs or chat output. Secrets live in 1Password and are entered at run time.
- **Dry run first.** Run `pve-bootstrap.sh` without `--apply` (plan mode), and Ansible with `--check --diff`,
  before any change. Show the plan, then get approval for destructive or outward-facing steps:
  `--destroy-data`, network/firewall stages, pushes.
- **Protect the guest backups** on the NAS (`Backups/pve01`) until the restored guests are verified.
- **Small steps:** one layer at a time (see the status table in README.md). Don't start new layers or services
  unless asked.
- `archive/` is **reference only**: don't edit it, deploy from it, or treat its docs as current fact.
  Bring things back out only after reviewing them against `proxmox/README.md`.

## Working notes

- Shell scripts and configs under `proxmox/` must keep LF line endings (`proxmox/.gitattributes`).
- pve01 is `10.101.0.11` (mgmt VLAN, reached through the UDM from the admin sources in `ADMIN_SOURCES`:
  the admin workstations `10.1.1.69` (Young) and `10.2.1.69` (Porter), Aaron's laptop `10.1.1.169` on the home LAN,
  and Teleport VPN clients `192.168.2.0/24`).
  Repeated SSH connections from the LAN have been cut off for a few minutes at a time.
  Keep SSH sessions few and long-lived, and use the iDRAC console or tmux for the network/firewall stages.
