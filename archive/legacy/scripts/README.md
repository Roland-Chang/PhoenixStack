# Phoenix Stack Scripts

Organized collection of scripts for provisioning, deploying, and managing the Phoenix Stack infrastructure.

## 📁 Directory Structure

```
scripts/
├── deployment/          ← Infrastructure deployment & management
├── provisioning/        ← Host provisioning & bootstrap
├── setup/              ← Configuration & setup utilities
├── validation/         ← Infrastructure validation & verification
└── README.md           ← This file
```

## 🚀 Quick Start

### Setup Aliases (One-time)
```bash
./scripts/setup/setup-aliases.sh
```

### Deploy Infrastructure
```bash
phoenix-deploy
# or
make deploy
```

### Check Status
```bash
phoenix-status
# or
make status
```

---

## 📦 Deployment Scripts

For full infrastructure orchestration: Terraform containers + Ansible configuration.

**Location**: `scripts/deployment/`

- **deploy.sh** - Deploy all infrastructure (Bastion + DNS + services)
- **destroy.sh** - Destroy infrastructure with safety confirmation
- **redeploy.sh** - Full cycle validation (destroy → rebuild → reconfigure)
- **status.sh** - Check infrastructure health and connectivity

[→ Deployment Scripts Details](deployment/README.md)

---

## 🔧 Provisioning Scripts

For bootstrapping bare metal Proxmox nodes.

**Location**: `scripts/provisioning/`

- **proxmox-bootstrap.sh** - Main bootstrap script for Proxmox nodes
- **deploy_proxmox_bootstrap.sh** - Deployment wrapper
- **configs/** - Node configuration templates

[→ Provisioning Scripts Details](provisioning/README.md)

---

## ⚙️ Setup Utilities

For initial environment configuration.

**Location**: `scripts/setup/`

- **setup-aliases.sh** - Install shell aliases on any machine

This script auto-detects your shell and adds all Phoenix Stack aliases to:
- `~/.bashrc` (Linux/WSL)
- `~/.bash_profile` (macOS Bash)
- `~/.zshrc` (macOS Zsh)

---

## ✅ Validation Scripts

For verifying infrastructure state and compliance.

**Location**: `scripts/validation/`

- **pve01-validation-commands.ps1** - PowerShell validation script for PVE01 state verification (Windows workflow)
  - Bash/Linux equivalent: [bash-validation-commands.md](validation/bash-validation-commands.md)

See [Validation Scripts README](validation/README.md) for detailed usage.

---

## 🎯 Make Targets

All scripts are also available via `Makefile`:

```bash
make deploy              # Deploy infrastructure
make destroy             # Destroy infrastructure
make redeploy            # Full cycle validation
make status              # Check infrastructure
make validate            # Validate all configs
make syntax-check        # Check playbook syntax
make clean               # Clean temporary files
make help                # Show help
```

---

## 🔑 Shell Aliases

After running `./scripts/setup/setup-aliases.sh`:

```bash
phoenix-deploy           # Deploy infrastructure
phoenix-destroy          # Destroy infrastructure
phoenix-redeploy         # Full validation cycle
phoenix-status           # Check infrastructure
phoenix-make             # Run make targets
phoenix-cd               # Change to project directory
```

---

## 📚 Documentation by Category

### Deployment
- [Deployment Scripts Details](deployment/README.md)
- Common workflows for deploying/managing infrastructure

### Provisioning
- [Provisioning Scripts Details](provisioning/README.md)
- Guide for bootstrapping Proxmox nodes

### Setup
- [Git Integration Guide](../SCRIPTS_GIT_GUIDE.md)
- How to use these scripts in version control

---

## 🔄 Typical Workflows

### New Infrastructure Deployment
```bash
./scripts/setup/setup-aliases.sh    # One-time setup
phoenix-deploy                       # Deploy everything
```

### Bootstrap New Proxmox Node
```bash
cp scripts/provisioning/configs/pve999.conf.example scripts/provisioning/configs/pveXX.conf
# Edit configuration...
./scripts/provisioning/proxmox-bootstrap.sh -c scripts/provisioning/configs/pveXX.conf
```

### Validate Full Stack
```bash
phoenix-redeploy                     # Destroy → rebuild → configure
```

### Check Everything
```bash
phoenix-status                       # Health check
make validate                        # Config validation
```

---

## ℹ️ Notes

- All scripts have proper error handling (set -e)
- Destruction operations require confirmation
- Scripts are idempotent where possible
- Retry logic handles transient failures

**For detailed information, see the README files in each subdirectory.**
