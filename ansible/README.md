# Ansible Configuration Management for Phoenix Stack

Ansible playbooks and roles for configuring infrastructure containers after Terraform provisioning.

## 📁 Structure

```
ansible/
├── ansible.cfg             # Ansible configuration (behavior, defaults)
├── inventory/              # Inventory files
│   └── hosts.yml          # Host definitions and variables
├── playbooks/             # Playbook entry points
│   ├── bastion01_base.yml # BASTION01 configuration playbook (control plane)
│   └── ansible01_base.yml # DEPRECATED (use bastion01_base.yml)
├── roles/                 # Reusable roles
│   ├── base_config/       # Base system packages and configuration
│   │   ├── tasks/
│   │   ├── handlers/
│   │   └── templates/
│   └── ansible_user/      # Create svc_ansible service user
│       ├── tasks/
│       └── handlers/
└── group_vars/            # Group-level variables (optional)
```

## 🚀 Quick Start

### 1. Configure Inventory

Inventory is auto-configured for BASTION01 at `10.101.0.20`. Edit `inventory/hosts.yml` if needed:

```yaml
bastion01:
  ansible_host: 10.101.0.20  # Update if different
```

### 2. Test Connectivity

```bash
ansible all -i inventory/hosts.yml -m ping
```

### 3. Run Playbook

```bash
# Without password (interactive)
ansible-playbook -i inventory/hosts.yml playbooks/bastion01_base.yml

# With password (non-interactive)
ansible-playbook -i inventory/hosts.yml playbooks/bastion01_base.yml \
  -e svc_ansible_password="mypassword"
```

## 📋 Playbooks

### bastion01_base.yml

**Purpose**: Configure BASTION01 container with base packages and service user

**Runs**:
1. **base_config** role:
   - Update packages
   - Install essential tools (curl, git, nano, etc.)
   - Install Ansible and Python dependencies
   - Configure SSH (key-based auth only)
   - Configure system settings (timezone, hostname)
   - Enable IP forwarding

2. **ansible_user** role:
   - Create `svc_ansible` service user
   - Configure sudo access (NOPASSWD)
   - Set up SSH directories
   - Optional: Set user password

**Usage**:
```bash
# Interactive (prompts for svc_ansible password)
ansible-playbook -i inventory/hosts.yml playbooks/ansible01_base.yml

# Non-interactive
ansible-playbook -i inventory/hosts.yml playbooks/ansible01_base.yml \
  -e svc_ansible_password="password123"

# Dry-run (check mode)
ansible-playbook -i inventory/hosts.yml playbooks/ansible01_base.yml --check

# Specific tags only
ansible-playbook -i inventory/hosts.yml playbooks/ansible01_base.yml \
  --tags "ansible_user"

# Verbose output
ansible-playbook -i inventory/hosts.yml playbooks/ansible01_base.yml -vvv
```

## 🔧 Roles

### base_config

**Purpose**: Configure base Ubuntu system

**Tasks**:
- Update APT cache and upgrade packages
- Install essential packages (curl, git, nano, htop, etc.)
- Install Ansible and dependencies
- Configure timezone and hostname
- Disable SSH password authentication
- Enable IP forwarding

**Variables** (in playbook or group_vars):
```yaml
hostname: ansible01          # Container hostname
timezone: UTC                # System timezone
```

### ansible_user

**Purpose**: Create service user for Ansible operations

**Tasks**:
- Create `svc_ansible` user
- Add user to sudo and other groups
- Set user password (optional)
- Configure sudoers for NOPASSWD
- Create .ansible directories
- Set up SSH keys (optional)

**Variables**:
```yaml
svc_ansible_password: ""     # Password (will be hashed)
svc_ansible_ssh_keys: []     # SSH public keys to add
```

## 📚 Inventory Configuration

### hosts.yml Structure

```yaml
all:
  hosts:
    ansible01:                              # Host name
      ansible_host: 10.101.0.20            # IP address
      ansible_port: 22                     # SSH port
      ansible_user: root                   # SSH user
      ansible_ssh_private_key_file: ~/.ssh/id_rsa  # SSH key

control_plane:                             # Group
  hosts:
    ansible01:                             # Group member

all:
  vars:
    ansible_python_interpreter: /usr/bin/python3
    domain: phoenix.stack
    timezone: UTC
```

### Add New Hosts

```yaml
all:
  hosts:
    ansible01:
      ansible_host: 10.101.0.20
    proxy01:
      ansible_host: 10.101.0.21
    dns01:
      ansible_host: 10.101.0.22

control_plane:
  hosts:
    ansible01:

proxies:
  hosts:
    proxy01:

dns_servers:
  hosts:
    dns01:
```

## 🔐 Security Best Practices

✅ **Implemented**:
- SSH key-based authentication only
- svc_ansible: Non-root user for operations
- Sudoers: NOPASSWD for automation
- Password authentication disabled

⚠️ **For Production**:
- Use Vault for sensitive variables
- Implement role-based access control
- Add network policies
- Monitor playbook execution
- Rotate credentials regularly

## 🧪 Testing

### Check Connectivity

```bash
ansible all -i inventory/hosts.yml --list-hosts
ansible all -i inventory/hosts.yml -m ping
```

### Dry-Run

```bash
ansible-playbook -i inventory/hosts.yml playbooks/ansible01_base.yml --check
```

### Debug Output

```bash
# Increased verbosity
ansible-playbook -i inventory/hosts.yml playbooks/ansible01_base.yml -vvv

# Show registered variables
ansible-playbook -i inventory/hosts.yml playbooks/ansible01_base.yml -v | grep -A2 "register:"
```

### Test Specific Tasks

```bash
# Run only tasks with specific tag
ansible-playbook -i inventory/hosts.yml playbooks/ansible01_base.yml \
  --tags "packages"

# Skip specific tasks
ansible-playbook -i inventory/hosts.yml playbooks/ansible01_base.yml \
  --skip-tags "security"
```

## 🔄 Idempotency

Playbooks are designed to be idempotent (safe to run multiple times):

```bash
# Run once
ansible-playbook -i inventory/hosts.yml playbooks/ansible01_base.yml

# Run again - should report no changes
ansible-playbook -i inventory/hosts.yml playbooks/ansible01_base.yml
```

Second run will show `ok:` for most tasks (already configured).

## 🚀 Advanced Usage

### Custom Variables

Pass variables at runtime:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/ansible01_base.yml \
  -e "timezone=America/New_York" \
  -e "hostname=custom-ansible"
```

### Using Group Variables

Create `group_vars/control_plane.yml`:

```yaml
---
timezone: UTC
ntp_server: 10.101.0.254
apt_cache_valid_time: 3600
```

Then playbook automatically uses these values.

### Using Host Variables

Create `host_vars/ansible01.yml`:

```yaml
---
# Ansible01-specific settings
container_role: orchestration
svc_ansible_password: "{{ lookup('env', 'SVC_ANSIBLE_PASS') }}"
```

## 🔍 Troubleshooting

### SSH Connection Refused

```bash
# Check SSH access
ssh -vvv root@10.101.0.20

# Add to known_hosts
ssh-keyscan -t rsa 10.101.0.20 >> ~/.ssh/known_hosts
```

### Playbook Fails

```bash
# Run with verbose output
ansible-playbook -i inventory/hosts.yml playbooks/ansible01_base.yml -vvv

# Check target host is reachable
ansible all -i inventory/hosts.yml -m setup
```

### svc_ansible Password Not Set

```bash
# Run ansible_user role specifically
ansible-playbook -i inventory/hosts.yml playbooks/ansible01_base.yml \
  --tags "ansible_user" \
  -e svc_ansible_password="newpassword"
```

## 📝 Creating New Playbooks

### Template

```yaml
#!/usr/bin/env ansible-playbook
---
- name: Configure [CONTAINER_NAME]
  hosts: [host_group]
  become: yes
  gather_facts: yes

  vars:
    my_variable: "value"

  pre_tasks:
    - name: Debug info
      debug:
        msg: "Configuring {{ inventory_hostname }}"

  roles:
    - role: my_role
      tags:
        - configuration

  post_tasks:
    - name: Verify configuration
      debug:
        msg: "Configuration complete!"
```

### Creating New Roles

```bash
# Generate role structure
ansible-galaxy init roles/my_role

# Role structure
roles/my_role/
├── tasks/main.yml        # Role tasks
├── handlers/main.yml     # Event handlers
├── templates/            # Jinja2 templates
├── files/                # Static files
├── vars/main.yml         # Role variables
├── defaults/main.yml     # Default variables
├── meta/main.yml         # Role dependencies
└── README.md             # Role documentation
```

## 📚 Resources

- [Ansible Documentation](https://docs.ansible.com/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [Ansible Galaxy Roles](https://galaxy.ansible.com/)

## 🤝 Next Steps

- [ ] ANSIBLE01 deployment and configuration
- [ ] Create playbooks for PROXY01, DNS01, etc.
- [ ] Integrate with Terraform outputs for dynamic inventory
- [ ] Set up Vault for secret management
- [ ] Implement monitoring and logging

## Related Documentation

- [Terraform IaC](../terraform/README.md)
- [ANSIBLE01 Deployment Guide](../terraform/ansible01/DEPLOYMENT.md)
- [Proxmox Bootstrap Script](../Scripts/proxmox/README.md)
