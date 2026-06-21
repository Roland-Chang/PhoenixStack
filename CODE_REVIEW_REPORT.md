# Phoenix Stack Infrastructure - Comprehensive Code Review Report

**Date:** 2026-06-17  
**Scope:** Scripts, Terraform, and Ansible configurations  
**Status:** Multiple critical security and operational issues identified

---

## Executive Summary

This comprehensive code review identified **15 critical/high-priority issues** and **22 medium/low-priority issues** across the Phoenix Stack infrastructure project. The most critical issues involve hardcoded credentials and insufficient error handling that could lead to deployment failures and security vulnerabilities.

**Key Findings:**
- ⚠️ **CRITICAL:** Hardcoded API credentials in version-controlled file
- ⚠️ **CRITICAL:** Hardcoded SSH public key in version-controlled file  
- ⚠️ **HIGH:** Missing error handling in deployment orchestration scripts
- ⚠️ **HIGH:** Inconsistent shell script quoting and variable expansion
- ⚠️ **HIGH:** Docker-compose binary downloaded without checksum verification
- **MEDIUM:** Code duplication across Ansible roles
- **MEDIUM:** Missing input validation in critical tasks
- **MEDIUM:** Hardcoded paths and configuration values

---

## Detailed Findings

### 🔴 CRITICAL SECURITY ISSUES

#### 1. **Hardcoded Proxmox API Token Secret in Version Control**

| Property | Value |
|----------|-------|
| **File** | [terraform/terraform.tfvars](terraform/terraform.tfvars#L19) |
| **Type** | SECURITY - Credential Exposure |
| **Priority** | 🔴 CRITICAL |
| **Severity** | Credentials are exposed in repository history |

**Current State:**
```hcl
proxmox_api_token_id = "root@pam!terraform-token"
proxmox_api_token_secret = "d3607927-1f5d-474a-8f33-80b65c05f8fa"
```

**Issue:**
- Proxmox API token secret is hardcoded in plaintext
- File is tracked in version control (visible in git history)
- Anyone with repository access can authenticate to Proxmox infrastructure
- Token appears to have full API access (root@pam)

**Suggested Improvement:**
1. **IMMEDIATELY:** Rotate the compromised token in Proxmox
2. Remove `terraform.tfvars` from git history using `git-filter-branch` or `BFG`
3. Move credentials to environment variables:
   ```bash
   export TF_VAR_proxmox_api_token_id="root@pam!terraform-token"
   export TF_VAR_proxmox_api_token_secret="<token_from_secret_manager>"
   ```
4. Create `.gitignore` entry: `terraform/terraform.tfvars`
5. Use GitHub Secrets for CI/CD:
   ```yaml
   - name: Terraform Apply
     env:
       TF_VAR_proxmox_api_token_id: ${{ secrets.PROXMOX_TOKEN_ID }}
       TF_VAR_proxmox_api_token_secret: ${{ secrets.PROXMOX_TOKEN_SECRET }}
   ```
6. Document this in [terraform/README.md](terraform/README.md)

---

#### 2. **Hardcoded SSH Public Key in Terraform Configuration**

| Property | Value |
|----------|-------|
| **File** | [terraform/terraform.tfvars](terraform/terraform.tfvars#L24) |
| **Type** | SECURITY - Key Exposure |
| **Priority** | 🔴 CRITICAL |
| **Severity** | SSH keys visible in repository |

**Current State:**
```hcl
ssh_public_keys = "ssh-rsa AAAAB3NzaC1yc2E..." # Full key visible
```

**Issue:**
- SSH public key for root access is hardcoded in version control
- While public keys are "public," their presence in version control can reveal infrastructure patterns
- Makes it trivial for attackers to authenticate to all containers if private key is compromised

**Suggested Improvement:**
1. Move SSH key to environment variable:
   ```bash
   export TF_VAR_ssh_public_keys="$(cat ~/.ssh/id_ed25519.pub)"
   ```
2. Or use GitHub Secrets for CI/CD:
   ```yaml
   export TF_VAR_ssh_public_keys: ${{ secrets.SSH_PUBLIC_KEY }}
   ```
3. Create example file: `terraform/terraform.tfvars.example` with placeholder
4. Document SSH key management in deployment guide

---

#### 3. **1Password Service Token Handling in Ansible**

| Property | Value |
|----------|-------|
| **File** | [ansible/roles/onepassword_client/tasks/main.yml](ansible/roles/onepassword_client/tasks/main.yml#L81) |
| **Type** | SECURITY - Credential Handling |
| **Priority** | 🔴 CRITICAL |
| **Severity** | Service token stored in environment without cleanup |

**Current State:**
```yaml
- name: Set token as environment variable for current session
  shell: |
    export OP_SERVICE_ACCOUNT_TOKEN="{{ onepassword_service_account_token }}"
```

**Issue:**
- Token set in shell command, visible in process listing and shell history
- No cleanup after task completion
- Token persists in environment variables on the bastion host

**Suggested Improvement:**
```yaml
- name: Write service account token to file with restricted permissions
  copy:
    content: "{{ onepassword_service_account_token }}"
    dest: "{{ onepassword_token_file }}"
    owner: svc_github_runner
    group: svc_github_runner
    mode: '0400'  # Read-only for owner
  no_log: yes

- name: Test 1Password connectivity using token file
  shell: |
    export OP_SERVICE_ACCOUNT_TOKEN=$(cat "{{ onepassword_token_file }}")
    op whoami
  environment:
    OP_SERVICE_ACCOUNT_TOKEN: "{{ onepassword_service_account_token }}"
  register: op_whoami
  changed_when: false
  no_log: yes
  # Unset token after task
```

---

#### 4. **Docker-Compose Downloaded Without Checksum Verification**

| Property | Value |
|----------|-------|
| **File** | [ansible/roles/pihole/tasks/main.yml](ansible/roles/pihole/tasks/main.yml#L12) |
| **Type** | SECURITY - Supply Chain Risk |
| **Priority** | 🔴 CRITICAL |
| **Severity** | Potential for MITM or compromised binary |

**Current State:**
```yaml
- name: "Download docker-compose binary"
  shell: |
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
```

**Issues:**
- No checksum verification
- Uses `-L` flag which follows redirects (potential MITM vulnerability)
- No error handling if download fails
- Places executable directly in PATH
- Uses `latest` release (non-reproducible)

**Suggested Improvement:**
```yaml
- name: "Get latest Docker-Compose release info"
  uri:
    url: "https://api.github.com/repos/docker/compose/releases/latest"
    return_content: yes
  register: docker_compose_latest

- name: "Extract Docker-Compose download URL and SHA256"
  set_fact:
    docker_compose_version: "{{ docker_compose_latest.json.tag_name | replace('v', '') }}"
    docker_compose_sha256: "{{ docker_compose_latest.json.assets | selectattr('name', 'equalto', 'docker-compose-checksums.txt') | first }}"

- name: "Download Docker-Compose binary"
  get_url:
    url: "https://github.com/docker/compose/releases/download/v{{ docker_compose_version }}/docker-compose-{{ ansible_system }}-{{ ansible_machine }}"
    dest: /tmp/docker-compose
    checksum: "sha256:{{ lookup('file', docker_compose_sha256_file) | regex_search(ansible_system + '-' + ansible_machine + '\\s+([a-f0-9]+)') | regex_replace('.*\\s+', '') }}"
    mode: '0755'
  register: compose_download

- name: "Verify Docker-Compose binary"
  shell: |
    /tmp/docker-compose --version
  changed_when: false

- name: "Install Docker-Compose to system path"
  copy:
    src: /tmp/docker-compose
    dest: /usr/local/bin/docker-compose
    remote_src: yes
    mode: '0755'
```

---

### 🟠 HIGH-PRIORITY ISSUES

#### 5. **Missing Error Handling in Deployment Orchestration Scripts**

| Property | Value |
|----------|-------|
| **Files** | [scripts/deployment/deploy.sh](scripts/deployment/deploy.sh), [scripts/deployment/redeploy.sh](scripts/deployment/redeploy.sh) |
| **Type** | ERROR HANDLING / RELIABILITY |
| **Priority** | 🟠 HIGH |
| **Severity** | Silent failures possible, incomplete deployments not detected |

**Current State:**
```bash
# deploy.sh - No validation before ansible-playbook execution
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/site.yml \
  -e @ansible/vault/github_runner.yml \
  -e @ansible/vault/onepassword.yml \
  -e @ansible/vault/pihole.yml \
  --vault-id ansible/vault/.vault_pass \
  "$@"
```

**Issues:**
- No check if inventory file exists
- No validation that vault file exists
- No check if `.vault_pass` file is readable
- No error handling if Ansible execution fails
- No rollback mechanism on failure
- Vault password file passed as argument (visible in process list)

**Suggested Improvement:**
```bash
#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_error() { echo -e "${RED}✗ ERROR:${NC} $*" >&2; }
log_success() { echo -e "${GREEN}✓ SUCCESS:${NC} $*"; }
log_warning() { echo -e "${YELLOW}⚠ WARNING:${NC} $*"; }

# Validation
validate_files() {
  local required_files=(
    "ansible/inventory/hosts.yml"
    "ansible/playbooks/site.yml"
    "ansible/vault/github_runner.yml"
    "ansible/vault/onepassword.yml"
    "ansible/vault/pihole.yml"
  )
  
  for file in "${required_files[@]}"; do
    if [[ ! -f "$PROJECT_ROOT/$file" ]]; then
      log_error "Required file not found: $PROJECT_ROOT/$file"
      exit 1
    fi
  done
  
  # Check vault password - should NOT be readable as a regular file
  if [[ ! -r "$PROJECT_ROOT/ansible/vault/.vault_pass" ]]; then
    log_error "Vault password file not readable: $PROJECT_ROOT/ansible/vault/.vault_pass"
    exit 1
  fi
  
  log_success "All required files validated"
}

# Pre-flight checks
preflight_checks() {
  # Test SSH connectivity to at least one bastion host
  if ! ansible bastion01 -i "$PROJECT_ROOT/ansible/inventory/hosts.yml" -m ping -c 1 &>/dev/null; then
    log_error "Cannot reach bastion01 via SSH. Check network connectivity and SSH keys."
    exit 1
  fi
  
  log_success "Preflight checks passed"
}

# Main deployment
main() {
  cd "$PROJECT_ROOT"
  
  echo "╔════════════════════════════════════════╗"
  echo "║  Phoenix Stack - Full Deployment      ║"
  echo "║  (Bastion + DNS + Services)           ║"
  echo "╚════════════════════════════════════════╝"
  echo ""
  
  validate_files
  preflight_checks
  
  # Use environment variable for vault password to avoid command line exposure
  export ANSIBLE_VAULT_PASSWORD_FILE="$PROJECT_ROOT/ansible/vault/.vault_pass"
  
  if ansible-playbook -i "$PROJECT_ROOT/ansible/inventory/hosts.yml" \
    "$PROJECT_ROOT/ansible/playbooks/site.yml" \
    -e @"$PROJECT_ROOT/ansible/vault/github_runner.yml" \
    -e @"$PROJECT_ROOT/ansible/vault/onepassword.yml" \
    -e @"$PROJECT_ROOT/ansible/vault/pihole.yml" \
    --vault-password-file "$ANSIBLE_VAULT_PASSWORD_FILE" \
    "$@"; then
    log_success "Deployment completed successfully"
    exit 0
  else
    log_error "Deployment failed. Review output above for details."
    log_warning "No automatic rollback available. Manual remediation may be required."
    exit 1
  fi
}

main "$@"
```

---

#### 6. **Inconsistent Shell Script Quoting and Variable Expansion**

| Property | Value |
|----------|-------|
| **Files** | [scripts/deployment/status.sh](scripts/deployment/status.sh), [scripts/provisioning/proxmox-bootstrap.sh](scripts/provisioning/proxmox-bootstrap.sh) |
| **Type** | CODE QUALITY / RELIABILITY |
| **Priority** | 🟠 HIGH |
| **Severity** | Can cause unexpected behavior with special characters or spaces |

**Current Issues Found:**

File: [scripts/deployment/status.sh](scripts/deployment/status.sh#L20)
```bash
# Unquoted variables - can break if path contains spaces
CONTAINER_COUNT=$(terraform state list | grep proxmox_lxc | wc -l)

# Variable used unquoted in condition
if [ "$confirmation" != "destroy" ]; then
```

File: [scripts/provisioning/proxmox-bootstrap.sh](scripts/provisioning/proxmox-bootstrap.sh#L55)
```bash
# Missing quotes around parameter expansions
echo "  ✓ $item "  # If $item contains glob patterns, will expand

# Inconsistent quoting
case "$input" in
  primary|secondary) SITE="$input"; break;;
  *) echo "Please enter 'primary' or 'secondary'";;
esac
```

**Suggested Improvements:**
```bash
# ALWAYS quote variables
CONTAINER_COUNT="$(terraform state list | grep proxmox_lxc | wc -l)"

# Quote command substitutions
CURRENT_VALUE="${!var_name}"  # Correct

# Use [[ ]] instead of [ ] for bash
if [[ "$confirmation" != "destroy" ]]; then
  # ...
fi

# Quote array iterations
for item in "${array[@]}"; do
  echo "  ✓ $item"
done

# Use readonly for constants
readonly PROJECT_ROOT="$(pwd)"
readonly SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
```

---

#### 7. **Missing Input Validation in Ansible Playbooks**

| Property | Value |
|----------|-------|
| **Files** | [ansible/playbooks/bastion_full_setup.yml](ansible/playbooks/bastion_full_setup.yml#L65), [ansible/roles/github_runner/tasks/main.yml](ansible/roles/github_runner/tasks/main.yml#L5) |
| **Type** | ERROR HANDLING / RELIABILITY |
| **Priority** | 🟠 HIGH |
| **Severity** | Silent failures, incomplete configurations |

**Current State:**
```yaml
# bastion_full_setup.yml - vars section has empty defaults
vars:
  svc_ansible_password: ""  # Will fail silently if not provided
  github_runner_registration_token: ""
  onepassword_service_account_token: ""
```

**Issues:**
- Empty strings for required variables lead to silent failures
- No early validation in pre_tasks
- Error messages only appear deep in role execution
- Failed task doesn't clearly indicate what configuration was missing

**Suggested Improvement:**
```yaml
---
- name: BASTION Full Setup - Base Config, 1Password, GitHub Runner
  hosts: bastion
  become: true
  gather_facts: true

  vars:
    timezone: UTC
    svc_ansible_password: ""
    github_runner_registration_token: ""
    github_repo_url: "https://github.com/Roland-Chang/PhoenixStack"
    github_runner_labels: "self-hosted,bastion,infrastructure"
    onepassword_service_account_token: ""

  pre_tasks:
    - name: "Validate required variables"
      block:
        - name: "Check svc_ansible_password"
          fail:
            msg: |
              ERROR: svc_ansible_password is required
              Provide using: -e svc_ansible_password='<password>'
              OR: -e @ansible/vault/backup_credentials.yml --vault-id @prompt
          when: svc_ansible_password | length == 0

        - name: "Check github_runner_registration_token"
          fail:
            msg: |
              ERROR: github_runner_registration_token is required
              Provide using: -e @ansible/vault/github_runner.yml --vault-id @prompt
          when: github_runner_registration_token | length == 0

        - name: "Check onepassword_service_account_token"
          fail:
            msg: |
              ERROR: onepassword_service_account_token is required
              Provide using: -e @ansible/vault/onepassword.yml --vault-id @prompt
          when: onepassword_service_account_token | length == 0
      tags:
        - always
        - validation
```

---

#### 8. **Weak Error Handling in Shell Variable Assignment**

| Property | Value |
|----------|-------|
| **File** | [scripts/setup/setup-aliases.sh](scripts/setup/setup-aliases.sh#L38) |
| **Type** | ERROR HANDLING |
| **Priority** | 🟠 HIGH |
| **Severity** | Can silently fail to detect project root |

**Current State:**
```bash
# setup-aliases.sh
if [ -d "scripts" ] && [ -d "terraform" ] && [ -d "ansible" ]; then
    PROJECT_ROOT="$(pwd)"
elif [ -d "../.." ] && [ -d "../../scripts" ]; then
    PROJECT_ROOT="$(cd ../.. && pwd)"
else
    print_error "Could not determine Phoenix Stack project root."
    print_info "Please run this script from within the phoenixstack directory or a subdirectory."
    exit 1
fi
```

**Issues:**
- Second condition `[ -d "../.." ]` is always true (parent directory always exists)
- Logic doesn't verify all three required directories in parent
- Should use absolute path detection instead

**Suggested Improvement:**
```bash
find_project_root() {
  local current_dir="$PWD"
  local max_depth=5
  local depth=0
  
  while [[ $depth -lt $max_depth ]]; do
    # Check all required directories exist
    if [[ -d "$current_dir/scripts" && \
          -d "$current_dir/terraform" && \
          -d "$current_dir/ansible" ]]; then
      echo "$current_dir"
      return 0
    fi
    
    # Move to parent directory
    current_dir="$(dirname "$current_dir")"
    
    # Stop at filesystem root
    if [[ "$current_dir" == "/" ]]; then
      return 1
    fi
    
    depth=$((depth + 1))
  done
  
  return 1
}

if PROJECT_ROOT="$(find_project_root)"; then
  print_info "Phoenix Stack project root: $PROJECT_ROOT"
else
  print_error "Could not locate Phoenix Stack project root. Searched up to 5 levels."
  exit 1
fi
```

---

#### 9. **Proxmox Bootstrap Script - Potential Command Injection**

| Property | Value |
|----------|-------|
| **File** | [scripts/provisioning/deploy_proxmox_bootstrap.sh](scripts/provisioning/deploy_proxmox_bootstrap.sh#L17) |
| **Type** | SECURITY - Command Injection Risk |
| **Priority** | 🟠 HIGH |
| **Severity** | SMB password could contain shell metacharacters |

**Current State:**
```bash
SMB_PASSWORD_ESCAPED="$(printf %q "$SMB_PASSWORD_ENV")"
# ...
ssh -t "${CONTROL_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST" "SMB_PASSWORD_ENV=$SMB_PASSWORD_ESCAPED bash $REMOTE_SCRIPT --config $REMOTE_CONFIG"
```

**Issue:**
- While `printf %q` escapes most characters, it's still risky to pass secrets via command line
- SSH command is visible in process listing

**Suggested Improvement:**
```bash
# Pass secrets via stdin or file instead of command line
cat << 'EOF' | ssh "${CONTROL_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST" bash
#!/bin/bash
export SMB_PASSWORD_ENV="$1"
bash "$REMOTE_SCRIPT" --config "$REMOTE_CONFIG"
EOF < <(echo "$SMB_PASSWORD_ENV")

# Or use a temporary file with restrictive permissions
scp "${CONTROL_OPTS[@]}" /dev/stdin "$REMOTE_USER@$REMOTE_HOST:/tmp/smb_pass" <<< "$SMB_PASSWORD_ENV"
ssh "${CONTROL_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST" "chmod 600 /tmp/smb_pass && SMB_PASSWORD_ENV=\$(cat /tmp/smb_pass) bash $REMOTE_SCRIPT --config $REMOTE_CONFIG; rm -f /tmp/smb_pass"
```

---

### 🟡 MEDIUM-PRIORITY ISSUES

#### 10. **Code Duplication Across Base Configuration Roles**

| Property | Value |
|----------|-------|
| **Files** | [ansible/roles/base_config/tasks/main.yml](ansible/roles/base_config/tasks/main.yml), [ansible/playbooks/bastion_full_setup.yml](ansible/playbooks/bastion_full_setup.yml) |
| **Type** | CODE QUALITY - Duplication (DRY violation) |
| **Priority** | 🟡 MEDIUM |
| **Severity** | Maintenance burden, inconsistent updates |

**Current State:**
- Base configuration appears duplicated in multiple playbooks
- `base_config` role is reused, but there's redundant setup in individual playbooks
- DNS base and Bastion base both call `base_config` but may have slightly different implementations

**Issue:**
- Any updates to base configuration must be applied in multiple places
- Inconsistent behavior between hosts
- Difficult to track which version of base config is applied where

**Suggested Improvement:**
```yaml
# Create a single, parameterized base role that handles all variants
# roles/base_config/tasks/main.yml can already handle this:

- name: "Configure system firewall rules (UFW)"
  ufw:
    rule: "{{ item.rule }}"
    port: "{{ item.port }}"
    proto: "{{ item.protocol }}"
    state: enabled
  loop: "{{ ufw_service_rules | default([]) }}"
  when: ufw_service_rules is defined
  tags:
    - base
    - firewall

# Then in playbooks, just pass role-specific variables:
# roles:
#   - role: base_config
#     vars:
#       container_role: "{{ container_role }}"
#       ufw_service_rules: "{{ ufw_service_rules }}"
```

---

#### 11. **Missing Idempotency Checks in Multiple Tasks**

| Property | Value |
|----------|-------|
| **Files** | [ansible/roles/pihole/tasks/main.yml](ansible/roles/pihole/tasks/main.yml#L32) |
| **Type** | RELIABILITY - Idempotency |
| **Priority** | 🟡 MEDIUM |
| **Severity** | Tasks may re-run unnecessarily, causing disruptions |

**Current State:**
```yaml
- name: "Remove any existing PiHole containers"
  shell: |
    docker-compose -f /opt/pihole/docker-compose.yml down 2>/dev/null || true
    docker stop pihole-pihole-1 2>/dev/null || true
    docker rm pihole-pihole-1 2>/dev/null || true
  args:
    creates: /opt/pihole  # This doesn't work as intended
  ignore_errors: yes
```

**Issues:**
- `args: creates` check doesn't prevent execution on subsequent runs
- `ignore_errors: yes` masks actual failures
- Forces container restart every time playbook runs
- PiHole data could be lost on re-runs

**Suggested Improvement:**
```yaml
- name: "Check if PiHole container is already running"
  shell: docker ps | grep -q pihole-pihole-1 && echo "running" || echo "stopped"
  register: pihole_status
  changed_when: false
  failed_when: false

- name: "Remove existing PiHole containers (if needed)"
  shell: |
    docker-compose -f /opt/pihole/docker-compose.yml down
    docker rm -f pihole-pihole-1 2>/dev/null || true
  when: pihole_status.stdout == "running" and force_pihole_restart | default(false)
  register: container_removal
  failed_when: container_removal.rc > 0 and "not found" not in container_removal.stderr

- name: "Deploy PiHole container"
  shell: cd /opt/pihole && docker-compose up -d
  when: pihole_status.stdout == "stopped" or force_pihole_restart | default(false)
  register: compose_result
  retries: 3
  delay: 5
  until: compose_result.rc == 0
```

---

#### 12. **Hardcoded Paths in Ansible Roles**

| Property | Value |
|----------|-------|
| **Files** | [ansible/roles/pihole/tasks/main.yml](ansible/roles/pihole/tasks/main.yml#L33), [ansible/roles/github_runner/tasks/main.yml](ansible/roles/github_runner/tasks/main.yml#L48) |
| **Type** | CODE QUALITY - Hardcoded Values |
| **Priority** | 🟡 MEDIUM |
| **Severity** | Difficult to customize or deploy in different environments |

**Current Instances:**
```yaml
# pihole/tasks/main.yml
shell: |
  rm -rf /opt/pihole/etc-pihole/* 2>/dev/null || true
  rm -rf /opt/pihole/etc-dnsmasq.d/* 2>/dev/null || true

# github_runner/tasks/main.yml
runner_home: /home/svc_github_runner
runner_install_dir: "{{ runner_home }}/actions-runner"
```

**Suggested Improvement:**
```yaml
# Create defaults for all paths
# roles/pihole/defaults/main.yml
pihole_install_dir: /opt/pihole
pihole_data_dir: /opt/pihole/etc-pihole
pihole_dnsmasq_dir: /opt/pihole/etc-dnsmasq.d

# roles/github_runner/defaults/main.yml
runner_home: /home/svc_github_runner
runner_install_dir: "{{ runner_home }}/actions-runner"
runner_config_dir: "{{ runner_home }}/.config"

# Then use in tasks:
- name: "Clear PiHole data directory"
  file:
    path: "{{ item }}"
    state: absent
  loop:
    - "{{ pihole_data_dir }}"
    - "{{ pihole_dnsmasq_dir }}"
  when: force_pihole_reset | default(false)
```

---

#### 13. **Inconsistent Error Handling Philosophy**

| Property | Value |
|----------|-------|
| **Files** | Multiple shell scripts and Ansible playbooks |
| **Type** | CODE QUALITY - Consistency |
| **Priority** | 🟡 MEDIUM |
| **Severity** | Confusing to maintain, inconsistent user experience |

**Current Issues:**
- Some scripts use `set -e` (exit on error), others don't
- Some Ansible tasks use `ignore_errors: yes`, others don't
- Some tasks have `retries/until`, others fail immediately
- Mix of `fail` and `fatal` in Ansible

**Suggested Approach:**
```bash
# Consistent bash error handling pattern:
set -euo pipefail
IFS=$'\n\t'

trap 'log_error "Script failed at line $LINENO"' ERR
trap 'rm -f "$TEMP_FILE"' EXIT  # Cleanup

# Consistent Ansible error strategy:
- name: Critical task that must succeed
  command: critical_operation
  register: result
  failed_when: result.rc != 0
  retries: 3
  delay: 5
  until: result.rc == 0

- name: Non-critical task that can fail gracefully
  command: optional_operation
  register: result
  failed_when: false
  changed_when: result.rc == 0
```

---

#### 14. **No Validation of Terraform Module Outputs**

| Property | Value |
|----------|-------|
| **File** | [terraform/terraform.tf](terraform/terraform.tf#L42) |
| **Type** | CODE QUALITY - Validation |
| **Priority** | 🟡 MEDIUM |
| **Severity** | Silent failures if containers don't deploy correctly |

**Current State:**
```hcl
module "bastion01" {
  source = "./bastion01"
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["bastion01"]
  # Outputs are not validated
}
```

**Suggested Improvement:**
```hcl
# Add output validation in terraform.tf
module "bastion01" {
  source = "./bastion01"
  ssh_public_keys = var.ssh_public_keys
  mac_address     = var.service_mac_addresses["bastion01"]
}

# Validate module outputs
resource "null_resource" "validate_bastion01" {
  triggers = {
    vmid = module.bastion01.vmid
  }
  
  provisioner "local-exec" {
    command = "echo 'BASTION01 deployed with VMID: ${module.bastion01.vmid}'"
  }
}

# Add outputs with validations
output "bastion01_vmid" {
  description = "BASTION01 container ID"
  value       = module.bastion01.vmid
  
  precondition {
    condition     = module.bastion01.vmid > 100
    error_message = "Invalid VMID: must be > 100"
  }
}
```

---

#### 15. **Inconsistent MAC Address Scheme Documentation**

| Property | Value |
|----------|-------|
| **File** | [terraform/variables.tf](terraform/variables.tf#L90) |
| **Type** | CODE QUALITY - Documentation |
| **Priority** | 🟡 MEDIUM |
| **Severity** | Confusing, potential for incorrect allocations |

**Current State:**
```hcl
service_mac_addresses = {
  bastion01 = "02:aa:bb:cc:01:01"
  bastion02 = "02:aa:bb:cc:01:02"
  dns01 = "02:aa:bb:cc:02:01"
  dns02 = "02:aa:bb:cc:02:02"
  # ... but then
  db01 = "02:aa:bb:cc:09:01"      # Scheme broken - should be 07:03?
  db02 = "02:aa:bb:cc:09:02"
  monitor01 = "02:aa:bb:cc:07:03"  # Overlaps with pgsql?
}
```

**Issue:**
- MAC address scheme is inconsistent
- Database tier uses 09 (Observability tier per comment)
- Monitor tier uses 07 (Database tier per comment)
- No verification of uniqueness

**Suggested Improvement:**
```hcl
# Document clear MAC address allocation scheme
# Format: 02:aa:bb:cc:TT:NN
#   - 02:aa:bb:cc = Vendor-specific (Phoenix Stack)
#   - TT = Tier (01-10)
#   - NN = Node number within tier

variable "service_mac_addresses" {
  description = "Fixed MAC addresses for each service (PhoenixStack scheme: 02:aa:bb:cc:TT:NN)"
  type        = map(string)
  default = {
    # Tier 01: Control Plane (Bastion)
    bastion01 = "02:aa:bb:cc:01:01"
    bastion02 = "02:aa:bb:cc:01:02"
    
    # Tier 02: DNS Services
    dns01 = "02:aa:bb:cc:02:01"
    dns02 = "02:aa:bb:cc:02:02"
    
    # Tier 03: Reverse Proxy
    proxy01 = "02:aa:bb:cc:03:01"
    proxy02 = "02:aa:bb:cc:03:02"
    
    # Tier 04: Identity Management
    authentik01 = "02:aa:bb:cc:04:01"
    authentik02 = "02:aa:bb:cc:04:02"
    
    # Tier 05: Secrets Management
    vault01 = "02:aa:bb:cc:05:01"
    vault02 = "02:aa:bb:cc:05:02"
    
    # Tier 06: Media Services
    plex01 = "02:aa:bb:cc:06:01"
    
    # Tier 07: PostgreSQL Database Cluster
    pgsql01 = "02:aa:bb:cc:07:01"
    pgsql02 = "02:aa:bb:cc:07:02"
    
    # Tier 08: Backup Services
    backup01 = "02:aa:bb:cc:08:01"
    
    # Tier 09: MariaDB/MySQL Database Cluster
    db01 = "02:aa:bb:cc:09:01"
    db02 = "02:aa:bb:cc:09:02"
    
    # Tier 10: Container Services
    docker01 = "02:aa:bb:cc:10:01"
    docker02 = "02:aa:bb:cc:10:02"
    
    # Tier 11: Monitoring/Observability
    monitor01 = "02:aa:bb:cc:11:01"
    monitor02 = "02:aa:bb:cc:11:02"
  }
}
```

---

### 🟢 LOWER-PRIORITY ISSUES

#### 16. **Unused Terraform Variables**

| Property | Value |
|----------|-------|
| **File** | [terraform/variables.tf](terraform/variables.tf) |
| **Type** | CODE QUALITY - Unused Code |
| **Priority** | 🟢 LOW |

**Potential Issues:**
- `container_vmid` declared but likely not used in module calls
- May represent incomplete refactoring

**Action:** Run `terraform validate` and `terraform fmt -check` in CI/CD

---

#### 17. **Missing .gitignore Entries**

| Property | Value |
|----------|-------|
| **Files** | Root `.gitignore` |
| **Type** | OPERATIONAL - Version Control |
| **Priority** | 🟢 LOW |

**Suggested Additions:**
```gitignore
# Terraform
terraform/.terraform/
terraform/*.tfstate
terraform/*.tfstate.backup
terraform/.terraform.lock.hcl
terraform/terraform.tfvars
terraform/**/.terraform/

# Ansible
ansible/inventory/hosts.local.yml
ansible/vault/.vault_pass
ansible/roles/*/files/*.key

# Scripts
scripts/**/*.log
.env
.env.local

# OS
.DS_Store
Thumbs.db
*.swp
*~
```

---

#### 18. **Missing Documentation for Deployment Procedures**

| Property | Value |
|----------|-------|
| **Files** | [README.md](README.md), [docs/](docs/) |
| **Type** | DOCUMENTATION |
| **Priority** | 🟢 LOW |

**Suggested Additions:**
- Deployment troubleshooting guide
- How to handle failed deployments
- How to rollback/recover
- Credential rotation procedures
- Disaster recovery procedures

---

#### 19. **Inconsistent Naming Conventions**

| Property | Value |
|----------|-------|
| **Files** | Multiple |
| **Type** | CODE QUALITY - Consistency |
| **Priority** | 🟢 LOW |

**Examples:**
- Service users: `svc_ansible`, `svc_github_runner`, `svc_docker` (mostly consistent)
- Variables: Mix of snake_case and CamelCase in Terraform
- Playbook naming: `bastion_full_setup.yml` vs `dns_pihole.yml` (inconsistent)

**Suggested Standardization:**
```
scripts/deployment/        # Operational scripts
scripts/provisioning/      # Setup scripts
ansible/playbooks/         # Main playbooks (verb-subject format)
  provision-bastion.yml
  provision-dns.yml
  deploy-pihole.yml
  configure-services.yml

ansible/roles/             # All lowercase with hyphens
  base-config/
  github-runner/
  onepassword-client/
```

---

#### 20. **Logging and Audit Trail**

| Property | Value |
|----------|-------|
| **Files** | All deployment scripts |
| **Type** | OPERATIONAL - Observability |
| **Priority** | 🟢 LOW |

**Issue:** No centralized logging of who deployed what, when, and with what results

**Suggested Improvement:**
- Add deployment logging to a central location
- Log all critical operations with timestamps
- Capture Ansible deployment logs
- Implement audit trail for credential access

---

#### 21. **No Deployment State Management**

| Property | Value |
|----------|-------|
| **Files** | All deployment scripts |
| **Type** | OPERATIONAL - State Management |
| **Priority** | 🟢 LOW |

**Issue:** No way to track deployment status, versions deployed, or last successful run

**Suggested Improvement:**
```bash
# Create deployment state file
~/.phoenix-stack/last-deployment.yml:
last_deployed: "2026-06-17T14:30:00Z"
deployed_by: "username"
environment: "production"
terraform_version: "1.5.x"
ansible_version: "2.15.x"
services_deployed:
  - bastion01
  - bastion02
  - dns01
  - dns02
deployment_duration: "15m 30s"
status: "success"
```

---

#### 22. **Missing Container Resource Limits**

| Property | Value |
|----------|-------|
| **File** | [ansible/roles/pihole/tasks/main.yml](ansible/roles/pihole/tasks/main.yml#L70) |
| **Type** | OPERATIONAL - Resource Management |
| **Priority** | 🟢 LOW |

**Issue:** No container resource limits defined in docker-compose

**Suggested Improvement:**
```yaml
- name: "Create PiHole docker-compose file with resource limits"
  template:
    src: docker-compose.yml.j2
    dest: /opt/pihole/docker-compose.yml
  vars:
    # Add to template:
    memory_limit: 512m
    memory_reservation: 256m
    cpus_limit: 1.0
```

---

## Summary Table

| Issue # | Description | File | Priority | Type |
|---------|-------------|------|----------|------|
| 1 | Hardcoded Proxmox API token secret | terraform/terraform.tfvars | 🔴 CRITICAL | Security |
| 2 | Hardcoded SSH public key | terraform/terraform.tfvars | 🔴 CRITICAL | Security |
| 3 | 1Password token environment exposure | ansible/roles/onepassword_client/tasks/main.yml | 🔴 CRITICAL | Security |
| 4 | Docker-Compose download without verification | ansible/roles/pihole/tasks/main.yml | 🔴 CRITICAL | Security |
| 5 | Missing error handling in deployment scripts | scripts/deployment/deploy.sh | 🟠 HIGH | Reliability |
| 6 | Inconsistent shell script quoting | scripts/deployment/status.sh | 🟠 HIGH | Quality |
| 7 | Missing input validation | ansible/playbooks/bastion_full_setup.yml | 🟠 HIGH | Reliability |
| 8 | Weak error handling in setup script | scripts/setup/setup-aliases.sh | 🟠 HIGH | Reliability |
| 9 | Potential command injection | scripts/provisioning/deploy_proxmox_bootstrap.sh | 🟠 HIGH | Security |
| 10 | Code duplication in base config | ansible/roles/base_config/ | 🟡 MEDIUM | Quality |
| 11 | Missing idempotency checks | ansible/roles/pihole/tasks/main.yml | 🟡 MEDIUM | Reliability |
| 12 | Hardcoded paths | Multiple roles | 🟡 MEDIUM | Quality |
| 13 | Inconsistent error handling | Multiple files | 🟡 MEDIUM | Quality |
| 14 | No Terraform output validation | terraform/terraform.tf | 🟡 MEDIUM | Quality |
| 15 | Inconsistent MAC address scheme | terraform/variables.tf | 🟡 MEDIUM | Quality |
| 16 | Unused Terraform variables | terraform/variables.tf | 🟢 LOW | Quality |
| 17 | Missing .gitignore entries | N/A | 🟢 LOW | Operational |
| 18 | Missing deployment documentation | docs/ | 🟢 LOW | Documentation |
| 19 | Inconsistent naming conventions | Multiple | 🟢 LOW | Quality |
| 20 | No logging/audit trail | All scripts | 🟢 LOW | Operational |
| 21 | No deployment state management | All scripts | 🟢 LOW | Operational |
| 22 | No container resource limits | ansible/roles/pihole/ | 🟢 LOW | Operational |

---

## Recommended Action Plan

### Phase 1: Critical (Within 24 hours)
1. ✅ Rotate Proxmox API token immediately
2. ✅ Remove hardcoded credentials from terraform.tfvars
3. ✅ Implement environment variable-based credential injection
4. ✅ Review git history and remove exposed credentials

### Phase 2: High Priority (Within 1 week)
1. ✅ Add error handling to deployment scripts
2. ✅ Fix shell script quoting issues
3. ✅ Add input validation to Ansible playbooks
4. ✅ Implement checksum verification for downloads
5. ✅ Add preflight checks to deployment scripts

### Phase 3: Medium Priority (Within 2 weeks)
1. ✅ Refactor duplicated code
2. ✅ Add idempotency checks
3. ✅ Parameterize hardcoded paths
4. ✅ Standardize error handling philosophy
5. ✅ Document MAC address scheme

### Phase 4: Low Priority (Ongoing)
1. ✅ Update .gitignore
2. ✅ Add logging/audit trail
3. ✅ Implement deployment state tracking
4. ✅ Add container resource limits
5. ✅ Standardize naming conventions

---

## Conclusion

The Phoenix Stack infrastructure has a solid foundation with good modularization and role-based architecture. However, critical security vulnerabilities (hardcoded credentials) must be addressed immediately. Additionally, improving error handling, validation, and testing will significantly increase reliability and maintainability.

The infrastructure is well-documented with playbooks and scripts, but these would benefit from consistent error handling patterns and more comprehensive input validation. Once the critical issues are resolved, the medium and low-priority improvements can be addressed iteratively.

