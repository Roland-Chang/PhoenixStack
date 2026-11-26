# PhoenixStack

Security-first infrastructure as code for a homelab that also runs personal production services
for family and friends.

## Status (2026-11-24)

The stack is being rebuilt from the ground up, one layer at a time:

| Layer | What | State |
| --- | --- | --- |
| L0–L3 | Proxmox host pve01: install, network, storage, access, firewall | **Done 2026-11-14.** See [proxmox/REBUILD_STATE.md](proxmox/REBUILD_STATE.md) |
| L4 | Backups (PBS + NAS), restore of the existing guests, alerts | **Done 2026-11-16:** guests restored, PBS and nightly jobs running, alerts delivered to a real mailbox. Open follow-ups are in the state file |
| L5+ | Guest provisioning and configuration, services | **In progress.** Done and checked by 2026-11-22: L5a (zones, address scheme, Terraform and Ansible), L5b DNS (`dns01`, `dns02`), L5c PostgreSQL (`pgsql01`), L5d Docker host and Services Traefik (`docker01`), L5e Authentik (`authentik01`, MFA required). L5f, the DMZ Docker host and public Traefik (`docker02`): the internet's `443` goes there, and Audiobookshelf is its first app, with logins through Authentik (Google for users), 2026-11-24; Mealie (Authentik logins) and IT-Tools followed 2026-11-25, and Immich, the last, 2026-11-26. Critical systems run on UTC. Details: [guests/README.md](guests/README.md), [diagram](guests/topology.html) |

The previous design is kept, unmaintained, in [archive/](archive/README.md).

## Layout

| Path | Contents |
| --- | --- |
| [proxmox/](proxmox/README.md) | Host design, rebuild runbook, node config, installer and bootstrap scripts |
| [guests/](guests/README.md) | L5: guest network, Terraform and Ansible, and the services on them |
| [tools/](tools/) | Workstation helpers: the shell shortcuts (`phx-shell.sh`) and a read-only UniFi export |
| [archive/](archive/README.md) | The earlier Terraform / Ansible / scripts / docs, for reference only |

## Principles

1. Security before convenience: least privilege, deny by default, IPv6 off unless needed.
2. No secrets in git. They live in 1Password and are entered at run time.
3. Small steps. Finish and verify one layer before starting the next.
4. Every change can be dry-run first (plan mode, `--check`), and every risky change can be rolled back.
5. If it isn't written down, it didn't happen: decisions live next to the code that implements them.
