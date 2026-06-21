# Setup Utilities

Configuration and initialization scripts for the Phoenix Stack.

## 📜 Scripts

### `setup-environment.sh`
Comprehensive environment setup for Phoenix Stack development/deployment

**Usage**:
```bash
./scripts/setup/setup-environment.sh
```

**One-liner** (from anywhere in project):
```bash
cd /mount/Projects/repos/phoenixstack && ./scripts/setup/setup-environment.sh
```

**From GitHub** (once pushed):
```bash
bash <(curl -s https://raw.githubusercontent.com/yourusername/phoenixstack/main/scripts/setup/setup-environment.sh)
```

---

## 🎯 What setup-environment.sh Does

### System Validation
1. **Validates required tools** - Checks for git, terraform, ansible, ssh, ssh-keygen
2. **Validates project structure** - Confirms scripts/, terraform/, ansible/, docs/ directories exist
3. **Configures Git** - Sets up git user.name and user.email if needed

### Environment Configuration
4. **SSH key setup** - Configures SSH keys for infrastructure deployment
5. **Shell configuration** - Sets up bash/zsh aliases for quick navigation
6. **Terraform variables** - Exports TF_VAR_ssh_public_keys for IaC

### Verification
7. **Tests aliases** - Verifies aliases are active and working
8. **Reports status** - Displays complete setup summary

### Special Features
- Works on Linux, macOS, and WSL
- Handles both bash and zsh
- Handles git configuration
- SSH key discovery and setup
- Safe to run multiple times
- Can update existing configuration

---

## 🔑 Installed Aliases

After running setup-environment.sh, these commands work from any directory:

### Main Deployment Aliases
```bash
phoenix-deploy           # Deploy infrastructure (scripts/deployment/deploy.sh)
phoenix-destroy          # Destroy infrastructure (scripts/deployment/destroy.sh)
phoenix-redeploy         # Full validation cycle (scripts/deployment/redeploy.sh)
phoenix-reset            # Reset deployment (scripts/deployment/reset.sh)
phoenix-status           # Check infrastructure (scripts/deployment/status.sh)
phoenix-terraform        # Run Terraform deployment
phoenix-ansible          # Run Ansible deployment
phoenix-make             # Run make targets
phoenix-cd               # Change to project directory
```

### Quick Navigation Aliases
```bash
ptf                    # Jump to terraform/ directory
pans                   # Jump to ansible/ directory
pdocs                  # Jump to docs/ directory
pscripts               # Jump to scripts/ directory
proot                  # Jump to project root
```

---

## 📋 Setup Requirements

The script requires:
- Bash or Zsh shell
- Write access to shell config file (~/.bashrc or ~/.zshrc)
- Phoenix Stack project directory

---

## 🔄 Setup Workflow

### First Time (New Machine)
```bash
# 1. Clone repository
git clone https://github.com/yourusername/phoenixstack.git
cd phoenixstack

# 2. Run setup
./scripts/setup/setup-environment.sh

# 3. Open new terminal or reload
source ~/.bashrc

# 4. Verify
alias phoenix-deploy  # Should show the alias definition
alias terraform       # Should show the terraform alias
```

### Adding to Existing Installation
```bash
# If you already have the project, just run:
./scripts/setup/setup-environment.sh
```

### Updating Configuration
```bash
# Simply run setup again - it will prompt to update
./scripts/setup/setup-environment.sh
# Answer 'y' when asked to update
```

---

## 🖥️ Cross-Platform Support

### Linux (Bash)
- Config file: `~/.bashrc`
- Fully supported
- Aliases active in new terminals

### macOS (Bash)
- Config file: `~/.bash_profile`
- Fully supported
- Aliases active in new terminals

### macOS (Zsh)
- Config file: `~/.zshrc`
- Fully supported
- Script prompts to add to zsh config

### Windows (WSL)
- Config file: `~/.bashrc`
- Fully supported (uses WSL bash environment)
- Aliases activeProject Root
PHOENIX_ROOT="/mount/Projects/repos/phoenixstack"

# Phoenix Stack Main Deployment Aliases
alias phoenix-cd="cd $PHOENIX_ROOT"
alias phoenix-make="cd $PHOENIX_ROOT && make"
alias phoenix-deploy="cd $PHOENIX_ROOT && ./scripts/deployment/deploy.sh"
alias phoenix-destroy="cd $PHOENIX_ROOT && ./scripts/deployment/destroy.sh"
alias phoenix-redeploy="cd $PHOENIX_ROOT && ./scripts/deployment/redeploy.sh"
alias phoenix-reset="cd $PHOENIX_ROOT && ./scripts/deployment/reset.sh"
alias phoenix-status="cd $PHOENIX_ROOT && ./scripts/deployment/status.sh"
alias phoenix-terraform="cd $PHOENIX_ROOT && ./scripts/deployment/terraform.sh"
alias phoenix-ansible="cd $PHOENIX_ROOT && ./scripts/deployment/ansible.sh"

# Quick Navigation Aliases
alias ptf="cd $PHOENIX_ROOT/terraform"
alias pans="cd $PHOENIX_ROOT/ansible"
alias pdocs="cd $PHOENIX_ROOT/docs"
alias pscripts="cd $PHOENIX_ROOT/scripts"
alias proot="cd $PHOENIX_ROOT"
```

Each alias automatically changes to the appropriate directory before running commands
The setup script adds this block to your shell config:

```bash
# Phoenix Stack aliases
alias phoenix-deploy="cd /home/username/projects/phoenixstack && ./scripts/deployment/deploy.sh"
alias phoenix-destroy="cd /home/username/projects/phoenixstack && ./scripts/deployment/destroy.sh"
alias phoenix-redeploy="cd /home/username/projects/phoenixstack && ./scripts/deployment/redeploy.sh"
alias phoenix-status="cd /home/username/projects/phoenixstack && ./scripts/deployment/status.sh"
alias phoenix-make="cd /home/username/projects/phoenixstack && make"
alias phoenix-cd="cd /home/username/projects/phoenixstack"
```

Each alias automatically changes to the project directory before running.

---

## 🛠️ Troubleshooting

### Aliases not working in new terminal
```bash
# Reload your shell config
source ~/.bashrc
# or for zsh:
source ~/.zshrc
```

### "Command not found: setup-aliases.sh"
```bash
# Make sure it's executable
chmod +x ./scripts/setup/setup-aliases.sh

# Run from project root
cd ~/projects/phoenixstack
./scripts/setup/setup-aliases.sh
```

### "Permission denied" when editing shell config
```bash
# Check file permissions
ls -la ~/.bashrc

# Ensure you have write access
chmod u+w ~/.bashrc
```

### Duplicate aliases
```bash
# The script should detect and prevent duplicates
# If you see duplicates, edit ~/.bashrc manually and remove the old block
nano ~/.bashrc

# Find and delete the Phoenix Stack aliases section
# Save and reload
source ~/.bashrc
```

### Wrong project path in aliases
```bash
# Edit your shell config to update the path
nano ~/.bashrc

# Find the phoenix-deploy line and update the path
# Or simply re-run setup-aliases.sh from the correct project directory
cd /correct/path/to/phoenixstack
./scripts/setup/setup-aliases.sh
```

---

## 🔐 Environment Variables

The setup script uses these shell environment variables:
- `$HOME` - User home directory
- `$OSTYPE` - Detect macOS vs Linux
- `$SHELL` - Current shell

---

## 📖 Related Documentation

- [Main scripts README](../README.md)
- [Deployment Scripts](../deployment/README.md)
- [Provisioning Scripts](../provisioning/README.md)
- [Git Integration Guide](../../SCRIPTS_GIT_GUIDE.md)
