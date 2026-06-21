# Phoenix Stack Git Integration Guide

This document explains how to commit and manage the Phoenix Stack deployment scripts in Git.

## Files to Commit

### New Files (Not in .gitignore)
- `Makefile` - Make targets for all common operations
- `scripts/deploy.sh` - Deploy infrastructure
- `scripts/destroy.sh` - Destroy infrastructure
- `scripts/redeploy.sh` - Full cycle validation
- `scripts/status.sh` - Infrastructure health check
- `scripts/setup-aliases.sh` - **NEW** - Install aliases on any machine
- `scripts/README.md` - Documentation for all scripts

### Files NOT to Commit (Already in .gitignore)
- `.terraform/` - Terraform state and plugins
- `terraform.tfstate*` - Infrastructure state files
- `.vault_pass` - Vault password file
- `*.yml` in vault/ - Encrypted vault files
- `.retry` - Ansible retry files

## Committing the Scripts

### Step 1: Stage the files
```bash
git add Makefile scripts/
```

### Step 2: View changes
```bash
git diff --cached
```

### Step 3: Create descriptive commit
```bash
git commit -m "Add deployment scripts and Makefile for operational convenience

- Add Makefile with 7 targets (deploy, destroy, redeploy, status, validate, clean, help)
- Create deploy.sh for full site deployment with vault integration
- Create destroy.sh with safety confirmation
- Create redeploy.sh for full validation cycle (destroy→rebuild→reconfigure)
- Create status.sh for infrastructure health checks
- Create setup-aliases.sh to install aliases on any machine
- Add comprehensive documentation in scripts/README.md

These scripts provide convenient command-line interfaces and shell aliases
for managing the Phoenix Stack infrastructure, improving operational ease
and reducing deployment errors."
```

### Step 4: Push to repository
```bash
git push origin main
```

## Using setup-aliases.sh on Other Machines

Once committed, new machines can set up aliases with:

```bash
# After cloning the repository
./scripts/setup-aliases.sh

# Or automatically from GitHub:
bash <(curl -s https://raw.githubusercontent.com/yourusername/phoenixstack/main/scripts/setup-aliases.sh)
```

## CI/CD Integration (Optional)

These scripts can be used in CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
deploy:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v3
    - name: Deploy Phoenix Stack
      run: |
        ./scripts/deploy.sh
```

Or in GitLab CI:

```yaml
deploy_stage:
  script:
    - ./scripts/deploy.sh
```

## Versioning Scripts

As you update scripts, consider:

1. **Semantic Versioning**: Tag releases with versions
   ```bash
   git tag v1.0.0 -m "Initial release of deployment scripts"
   git push origin v1.0.0
   ```

2. **Changelog**: Update CHANGELOG.md with script updates

3. **Documentation**: Keep scripts/README.md in sync with changes

## Example .gitignore Entry

Make sure these are NOT committed:

```gitignore
# Terraform state and config
terraform.tfstate*
.terraform/

# Ansible vault
ansible/vault/.vault_pass
*.vault

# Temporary files
*.retry
*.log
/tmp/

# Secrets
.env
.env.local
```

## Using Scripts from CI/CD

### GitHub Actions

```yaml
name: Deploy Infrastructure

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'
      
      - name: Install dependencies
        run: |
          pip install ansible proxmoxer
      
      - name: Configure SSH key
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_KEY }}" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
      
      - name: Setup vault password
        run: |
          echo "${{ secrets.VAULT_PASS }}" > ansible/vault/.vault_pass
          chmod 600 ansible/vault/.vault_pass
      
      - name: Deploy
        run: ./scripts/deploy.sh
```

## Troubleshooting

### Aliases not working after setup
```bash
# Reload shell configuration
source ~/.bashrc
# or for zsh:
source ~/.zshrc
```

### Script permissions lost after clone
```bash
# Restore execute permissions
chmod +x scripts/*.sh
```

### Different scripts between machines
This shouldn't happen if everything is committed. Verify:
```bash
git status  # Should show no unexpected changes
git log --oneline scripts/  # Should show all script commits
```
