# Using 1Password with Ansible - PhoenixStack

**Purpose:** Guide for integrating 1Password into Ansible playbooks to fetch secrets dynamically.

---

## Architecture

```
1Password Vault
    ↓
Ansible (local workstation or bastion01)
    ↓
op CLI (reads from 1Password)
    ↓
Playbook variables/tasks
```

---

## Prerequisites

1. **1Password CLI installed** on the machine running Ansible
   ```bash
   # Local workstation
   brew install 1password-cli  # macOS
   sudo apt install 1password-cli  # Linux
   
   # Or deployed via: ansible/playbooks/bastion01_onepassword.yml
   ```

2. **Service Account Token** in environment or file
   ```bash
   export OP_SERVICE_ACCOUNT_TOKEN="your_token_here"
   # Or stored in file (as deployed by Ansible role)
   cat /etc/phoenixstack/1password_token
   ```

3. **Vault Items** created in 1Password with required fields

---

## Method 1: Direct Shell Command in Playbook

Simplest approach - use `shell` module to call `op` directly:

```yaml
- name: Fetch Proxmox credentials from 1Password
  block:
    - name: Get Proxmox API URL
      shell: op read op://infrastructure/Proxmox/api-url
      environment:
        OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
      register: proxmox_api_url
      changed_when: false
      no_log: yes

    - name: Get Proxmox API Token ID
      shell: op read op://infrastructure/Proxmox/api-token-id
      environment:
        OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
      register: proxmox_api_token_id
      changed_when: false
      no_log: yes

    - name: Use the credentials
      debug:
        msg: "Connecting to {{ proxmox_api_url.stdout }}"
```

---

## Method 2: Load from File (Bastion01)

When running on bastion01 where the token is stored:

```yaml
---
- name: Example with file-based token
  hosts: bastion01
  gather_facts: no

  tasks:
    - name: Read service account token from file
      set_fact:
        op_token: "{{ lookup('file', '/etc/phoenixstack/1password_token') }}"
      no_log: yes

    - name: Fetch secret from 1Password
      shell: op read op://infrastructure/Proxmox/api-url
      environment:
        OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
      register: secret
      changed_when: false
      no_log: yes

    - name: Use secret
      debug:
        msg: "Secret value: {{ secret.stdout }}"
```

---

## Method 3: Batch Fetch Multiple Secrets

Efficient way to fetch multiple related fields:

```yaml
- name: Fetch all Proxmox credentials at once
  shell: op item get Proxmox --vault infrastructure --format json
  environment:
    OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
  register: proxmox_item
  changed_when: false
  no_log: yes

- name: Parse credentials
  set_fact:
    proxmox_api_url: "{{ (proxmox_item.stdout | from_json).fields | selectattr('id', 'equalto', 'api-url') | map(attribute='value') | first }}"
    proxmox_token_id: "{{ (proxmox_item.stdout | from_json).fields | selectattr('id', 'equalto', 'api-token-id') | map(attribute='value') | first }}"
    proxmox_token_secret: "{{ (proxmox_item.stdout | from_json).fields | selectattr('id', 'equalto', 'api-token-secret') | map(attribute='value') | first }}"
  no_log: yes
```

---

## Method 4: Reusable Role for 1Password Lookups

Create a role that encapsulates 1Password fetching:

```yaml
# roles/fetch_1password_secrets/tasks/main.yml
---
- name: Fetch secret from 1Password
  shell: op read "{{ op_secret_path }}"
  environment:
    OP_SERVICE_ACCOUNT_TOKEN: "{{ op_service_account_token }}"
  register: op_result
  changed_when: false
  no_log: yes

- name: Set fact with fetched secret
  set_fact:
    "{{ op_variable_name }}": "{{ op_result.stdout }}"
  no_log: yes
```

Usage:
```yaml
- name: Fetch Proxmox API URL
  include_role:
    name: fetch_1password_secrets
  vars:
    op_service_account_token: "{{ lookup('file', '/etc/phoenixstack/1password_token') }}"
    op_secret_path: "op://infrastructure/Proxmox/api-url"
    op_variable_name: "proxmox_api_url"
```

---

## Method 5: Using Ansible Vault + 1Password Together

Store service account token in vault, use it to fetch other secrets:

```yaml
---
- name: Playbook with vault + 1Password
  hosts: bastion01
  vars_files:
    - vault/onepassword.yml  # Contains: onepassword_service_account_token

  tasks:
    - name: Fetch credentials from 1Password
      shell: op read op://infrastructure/GitHub/runner-registration-token
      environment:
        OP_SERVICE_ACCOUNT_TOKEN: "{{ onepassword_service_account_token }}"
      register: github_token
      changed_when: false
      no_log: yes
```

Run with:
```bash
ansible-playbook playbook.yml \
  --vault-id @prompt \
  -e @ansible/vault/onepassword.yml
```

---

## Example: Complete Playbook

```yaml
#!/usr/bin/env ansible-playbook
---
- name: Deploy with 1Password Secrets
  hosts: bastion01
  become: true
  gather_facts: true

  vars:
    # Token sourced from vault file
    onepassword_service_account_token: ""

  pre_tasks:
    - name: Load 1Password token from vault
      set_fact:
        op_token: "{{ lookup('file', '/etc/phoenixstack/1password_token') }}"
      no_log: yes

  tasks:
    - name: Fetch infrastructure secrets from 1Password
      block:
        - name: Get Proxmox credentials
          shell: op item get Proxmox --vault infrastructure --format json
          environment:
            OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
          register: proxmox_secrets
          changed_when: false
          no_log: yes

        - name: Parse Proxmox credentials
          set_fact:
            proxmox_url: "{{ (proxmox_secrets.stdout | from_json).fields | selectattr('label', 'equalto', 'api-url') | map(attribute='value') | first }}"
            proxmox_token_id: "{{ (proxmox_secrets.stdout | from_json).fields | selectattr('label', 'equalto', 'api-token-id') | map(attribute='value') | first }}"
            proxmox_token_secret: "{{ (proxmox_secrets.stdout | from_json).fields | selectattr('label', 'equalto', 'api-token-secret') | map(attribute='value') | first }}"
          no_log: yes

    - name: Use credentials
      debug:
        msg: "Proxmox URL: {{ proxmox_url }}"
```

Run:
```bash
ansible-playbook playbook.yml \
  -i ansible/inventory/hosts.yml \
  --vault-id @prompt \
  -e @ansible/vault/onepassword.yml
```

---

## Best Practices

### 1. Always Use `no_log: yes`

Prevents secret values from appearing in Ansible output:

```yaml
- name: Fetch secret
  shell: op read op://vault/item/field
  register: secret
  no_log: yes
```

### 2. Store Service Account Token Securely

```yaml
# ✅ GOOD: Load from file or vault
op_token: "{{ lookup('file', '/etc/phoenixstack/1password_token') }}"

# ❌ BAD: Hardcode token in playbook
op_token: "sv_live_..."
```

### 3. Use `changed_when: false` for Read-Only Operations

```yaml
- shell: op read op://vault/item/field
  changed_when: false  # Reading doesn't change state
  no_log: yes
```

### 4. Test Connectivity First

```yaml
- name: Test 1Password connectivity
  shell: op whoami
  environment:
    OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
  register: op_whoami
  changed_when: false
```

### 5. Cache Secrets During Playbook Execution

Avoid repeated API calls for same secret:

```yaml
- name: Fetch and cache secrets
  block:
    - name: Get all credentials (cached)
      shell: op item get Proxmox --vault infrastructure --format json
      environment:
        OP_SERVICE_ACCOUNT_TOKEN: "{{ op_token }}"
      register: proxmox_data
      changed_when: false
      no_log: yes

    # Use proxmox_data.stdout throughout playbook
  run_once: true  # Only fetch once for entire play
```

---

## Troubleshooting

### "command not found: op"

1Password CLI not installed:

```bash
# Check installation
which op

# Install if missing
sudo apt-get install 1password-cli
```

### "Authentication failed"

Token invalid or expired:

```bash
# Verify token
echo $OP_SERVICE_ACCOUNT_TOKEN | head -c 20

# Test connectivity
op whoami

# Regenerate token if needed (1Password Settings → Service Accounts)
```

### "Item not found"

Incorrect vault or item name:

```bash
# List vaults
op vault list

# List items in vault
op item list --vault infrastructure

# Check exact item name
op item get "Proxmox" --vault infrastructure
```

### Secret appears in output

Didn't use `no_log: yes`:

```yaml
- shell: op read op://vault/item/field
  register: secret
  no_log: yes  # ← Add this
```

---

## Local Development (Workstation)

If running Ansible from your workstation:

```bash
# Install 1Password CLI
brew install 1password-cli  # macOS
sudo apt install 1password-cli  # Ubuntu

# Authenticate
eval $(op signin my.1password.com)

# Set service account token
export OP_SERVICE_ACCOUNT_TOKEN="your_service_account_token"

# Verify
op whoami

# Run playbook
ansible-playbook playbook.yml -i inventory/hosts.yml
```

---

## References

- [1Password CLI Reference](https://developer.1password.com/docs/cli/reference/)
- [1Password Item Format](https://developer.1password.com/docs/cli/item-management/)
- [Ansible Lookup Plugins](https://docs.ansible.com/ansible/latest/plugins/lookup.html)
- [Ansible Shell Module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/shell_module.html)
