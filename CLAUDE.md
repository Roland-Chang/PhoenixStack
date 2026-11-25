# PhoenixStack: notes for Claude

Read [README.md](README.md) first, then [proxmox/REBUILD_STATE.md](proxmox/REBUILD_STATE.md) for where the rebuild stands.

## Guardrails

- **No secrets** in code, docs, commits, PRs or chat output. Secrets live in 1Password and are entered at run time.
- **Dry run first.** Run `pve-bootstrap.sh` without `--apply` (plan mode), `tf plan`, and Ansible with
  `--check --diff`, before any change. Show the plan, then get approval for destructive or outward-facing steps:
  `--destroy-data`, network/firewall stages, pushes.
- **Protect the backups** (PBS and the NAS's `Backups/pve01`): delete, prune or unprotect backups only when
  asked. The pre-rebuild archives stay Protected until REBUILD_STATE item 4 is done.
- **The repo is public** (GitHub): nothing private in it either, such as lists of people, their email addresses,
  or tenant and client IDs. Those stay outside the repo.
- **Small steps:** one layer at a time (see the status table in README.md). Don't start new layers or services
  unless asked.
- `archive/` is **reference only**: don't edit it, deploy from it, or treat its docs as current fact.
  Bring things back out only after reviewing them against `proxmox/README.md`.

## Working notes

- Files keep LF line endings (root `.gitattributes`; `archive/` is left as it is).
- pve01 is `10.101.0.11` (mgmt VLAN, reached through the UDM from the admin sources in `ADMIN_SOURCES`:
  the Young admin workstation and laptop `10.1.1.69` and `10.1.1.169`, the Porter admin workstation and laptop
  `10.2.1.69` and `10.2.1.169`, and Teleport VPN clients `192.168.2.0/24`).
  Repeated SSH can be cut off for a few minutes: the UDM's IPS takes it for an SSH scan. The admin
  workstations and laptops are on the IPS "Detection Exclusions" list; Teleport clients are not, and were cut off
  on 2026-11-24. If SSH times out while ping and the GUI work, check that list first (e.g. for a new admin
  address).
  An Ansible run that reports guests unreachable with "Timeout waiting for privilege escalation prompt" is
  something else: the 1Password SSH agent waiting for approval (`guests/ansible/ansible.cfg`).
  Use the iDRAC console or tmux for the network/firewall stages.
