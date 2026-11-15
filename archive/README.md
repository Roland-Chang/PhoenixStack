# Archive

Purpose: keeps the first PhoenixStack design (2025 – July 2026) for reference while the stack is rebuilt.
**Nothing here is maintained, deployed or tested.** Don't run it against the new host.

## Why it was archived (2026-11-14)

The first design grew faster than it was built. Most hosts it describes (bastion, DNS, Ansible
controller, GitHub runner, proxy, Authentik, Vault, …) were never running on pve01. The old pve01 itself
was retired and rebuilt from bare metal ([proxmox/](../proxmox/)). The rebuild starts again from the host
layer up, one layer at a time. Code and docs move back out of here only after they've been reviewed
against the new design.

## What's in `legacy/`

The repository as of `main` at `0c37db4`, with the same folder layout:

| Path | What it was |
| --- | --- |
| `terraform/` | LXC modules per service tier (telmate/proxmox provider) |
| `ansible/` | Roles and playbooks: base config, Pi-hole DNS, GitHub runner, 1Password, Proxmox backups |
| `scripts/` | Deployment wrappers, the old Proxmox bootstrap, backup scripts |
| `docs/` | Design and how-to documents, including the roadmap (VLAN plan, MAC/VMID scheme, HA) |
| `github/workflows/terraform.yml` | The old CI (plan and **auto-apply on push to main**). Moved out of `.github/` so it can't run. |
| `ai/Instructions.md` | The old project instructions. The guardrails that still apply are in the root [CLAUDE.md](../CLAUDE.md). |
| `Makefile`, `README.md` | The old entry points |
| `HANDOFF-2026-11-07.md` | Review notes on this code from a Claude session. Its open items apply to this archive, not to the rebuild. |

## Things to know before reusing anything

- **Known defects, not fixed here:** gateway 10.101.0.254 used for workload hosts on another subnet;
  containers use the gateway as their DNS server; Ansible turns off SSH host key checking; the CI auto-applied on push.
  See `HANDOFF-2026-11-07.md` for the full list.
- `ansible/vault/*.yml` are Ansible Vault-encrypted (AES256). They're in a public repository, so treat
  their contents as exposed if the vault password was ever weak.
- A Proxmox API token secret in `docs/KNOWN_ISSUES.md` is redacted here but still in git history. It
  belonged to the old pve01, which no longer exists.
- The domain, VLAN and naming plan in these docs (`phoenix.stack`, VLAN 100 workloads, VMID/MAC tiers)
  is superseded by [proxmox/README.md](../proxmox/README.md) wherever the two differ.
