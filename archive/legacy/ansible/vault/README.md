# Ansible Vault - Encrypted Secrets Storage

This directory contains encrypted Ansible vault files for storing sensitive credentials and configuration data.

## Contents

- `github_runner.yml.example` - Template for GitHub runner configuration (safe to commit)
- `github_runner.yml` - Encrypted GitHub runner credentials (NOT committed; .gitignore prevents it)

## Security

All `.yml` files in this directory (except `.example` files) are:
- **Encrypted with ansible-vault** at rest
- **Ignored by git** - never committed
- **Safe to store** alongside your Ansible playbooks

## Using Vault Files

### Create a New Vault File

```bash
# Copy from example template
cp ansible/vault/github_runner.yml.example ansible/vault/github_runner.yml

# Edit with nano (file is plaintext at this stage)
nano ansible/vault/github_runner.yml

# Encrypt the vault file (you'll be prompted for a password)
ansible-vault encrypt ansible/vault/github_runner.yml

# Verify it's encrypted (should show binary/encrypted content)
cat ansible/vault/github_runner.yml
```

### Run Playbook with Vault

**Option 1: Prompt for vault password**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/bastion01_github_runner.yml \
  --vault-id @prompt \
  -e @ansible/vault/github_runner.yml
```

**Option 2: Use vault password file (local only, not in git)**
```bash
# Store password in plaintext file (keep locally, never commit)
echo "your_vault_password" > ansible/vault/.vault_pass

# Run with password file
ansible-playbook -i inventory/hosts.yml playbooks/bastion01_github_runner.yml \
  --vault-password-file=ansible/vault/.vault_pass \
  -e @ansible/vault/github_runner.yml

# Note: .vault_pass is in .gitignore; it won't be committed
```

### Edit an Encrypted Vault File

```bash
# Decrypt (in editor), make changes, re-encrypt automatically
ansible-vault edit ansible/vault/github_runner.yml

# You'll be prompted for the vault password
```

### View an Encrypted Vault File

```bash
# Decrypt and display (doesn't modify file)
ansible-vault view ansible/vault/github_runner.yml
```

## Vault Password Management

### Best Practices

1. **Don't commit `.vault_pass` files** - They're in .gitignore for this reason
2. **Use `@prompt`** - Most secure, you type password each time
3. **Document the process** - Your team should know how to use vault
4. **Rotate vault passwords periodically** - Annual rotation recommended
5. **Store vault password securely** - Password manager, 1Password, etc.

### For Team Environments

If sharing this repository with team members:

1. **Distribute vault password securely** (not via email/chat)
   - Use 1Password/LastPass shared vault
   - Use secrets management system
   - Distribute in person if possible

2. **Team workflow:**
   ```bash
   # Each team member creates their own .vault_pass file locally
   echo "team_vault_password" > ansible/vault/.vault_pass
   chmod 600 ansible/vault/.vault_pass
   
   # Run playbooks with password file
   ansible-playbook playbooks/bastion01_github_runner.yml \
     --vault-password-file=ansible/vault/.vault_pass \
     -e @ansible/vault/github_runner.yml
   ```

## Vault Files Checklist

When adding a new vault file:

- [ ] Create from `.example` template
- [ ] Fill in sensitive values
- [ ] Encrypt with `ansible-vault encrypt`
- [ ] Test playbook execution with `--vault-id @prompt`
- [ ] Verify file is encrypted (binary content)
- [ ] Confirm `.gitignore` pattern matches filename
- [ ] Document in playbook comments how to use it

## Troubleshooting

### "Decryption failed" error

```
ERROR! Decryption failed (no vault secrets were found that could decrypt ciphertext) on ansible/vault/github_runner.yml
```

**Solution:** You provided wrong vault password, or the file isn't encrypted.
```bash
# Re-encrypt file
ansible-vault encrypt ansible/vault/github_runner.yml

# Or verify it's actually encrypted
file ansible/vault/github_runner.yml
```

### "Invalid YAML" after editing vault file

```bash
# Syntax check before encrypting
ansible-vault view ansible/vault/github_runner.yml | ansible-playbook-validator

# Or view and validate
cat <(ansible-vault view ansible/vault/github_runner.yml)
```

## References

- [Ansible Vault Documentation](https://docs.ansible.com/ansible/latest/user_guide/vault.html)
- [Vault ID Queries](https://docs.ansible.com/ansible/latest/user_guide/vault.html#vault-id-q-option)
- [Best Practices for Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html#best-practices-for-ansible-vault)
