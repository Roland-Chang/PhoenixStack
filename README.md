# PhoenixStack

Security-first infrastructure as code for a homelab that also runs personal production services
for family and friends.

## Status (2026-11-21)

The stack is being rebuilt from the ground up, one layer at a time:

| Layer | What | State |
| --- | --- | --- |
| L0–L3 | Proxmox host pve01: install, network, storage, access, firewall | **Done 2026-11-14.** See [proxmox/REBUILD_STATE.md](proxmox/REBUILD_STATE.md) |
| L4 | Backups (PBS + NAS), restore of the existing guests, alerts | **Done 2026-11-16:** guests restored, PBS and nightly jobs running, alerts delivered to a real mailbox. Open follow-ups are in the state file |
| L5+ | Guest provisioning and configuration, services | **L5a done 2026-11-21** ([guests/README.md](guests/README.md), [diagram](guests/topology.html)): zones (Services VLAN 100, DMZ VLAN 200), original address scheme, Terraform and Ansible, proven with test guests. **L5b (DNS, `dns01`: Pi-hole + Unbound)** applied and checked 2026-11-21; no clients use it yet |

The previous design is kept, unmaintained, in [archive/](archive/README.md).

## Layout

| Path | Contents |
| --- | --- |
| [proxmox/](proxmox/README.md) | Host design, rebuild runbook, node config, installer and bootstrap scripts |
| [guests/](guests/README.md) | L5: guest network, Terraform and Ansible design (draft) |
| [archive/](archive/README.md) | The earlier Terraform / Ansible / scripts / docs, for reference only |

## Principles

1. Security before convenience: least privilege, deny by default, IPv6 off unless needed.
2. No secrets in git. They live in 1Password and are entered at run time.
3. Small steps. Finish and verify one layer before starting the next.
4. Every change can be dry-run first (plan mode, `--check`), and every risky change can be rolled back.
5. If it isn't written down, it didn't happen: decisions live next to the code that implements them.
