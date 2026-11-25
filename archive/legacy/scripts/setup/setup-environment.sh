#!/bin/bash
#
# Phoenix Stack - Environment Setup Script
# Configures a new system for Phoenix Stack development/deployment
# - Validates required tools (terraform, ansible, git, ssh)
# - Configures shell environment and aliases
# - Sets up SSH authentication
# - Validates project structure
#
# Usage: ./scripts/setup/setup-environment.sh
#        bash <(curl -s https://raw.githubusercontent.com/yourusername/phoenixstack/main/scripts/setup/setup-environment.sh)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get command version
get_version() {
    local cmd="$1"
    local flag="${2:---version}"
    $cmd $flag 2>/dev/null | head -1 || echo "unknown"
}

# ============================================================================
# PHASE 1: Validate Required Tools
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║     Phoenix Stack - Environment Setup                  ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
print_info "PHASE 1: Validating required tools..."
echo ""

REQUIRED_TOOLS=("git" "terraform" "ansible" "ssh" "ssh-keygen")
MISSING_TOOLS=()

for tool in "${REQUIRED_TOOLS[@]}"; do
    if command_exists "$tool"; then
        version=$(get_version "$tool")
        print_status "$tool installed ($version)"
    else
        print_error "$tool NOT found"
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo ""
    print_warning "Missing required tools: ${MISSING_TOOLS[*]}"
    echo ""
    echo "Install missing tools:"
    echo "  Ubuntu/Debian:  sudo apt-get install ${MISSING_TOOLS[*]}"
    echo "  macOS:          brew install ${MISSING_TOOLS[*]}"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Setup cancelled."
        exit 1
    fi
fi

# ============================================================================
# PHASE 2: Validate Project Structure
# ============================================================================
echo ""
print_info "PHASE 2: Validating project structure..."
echo ""

# Determine project root
# If this script is run from anywhere, try to find the phoenixstack directory
if [ -d "scripts" ] && [ -d "terraform" ] && [ -d "ansible" ]; then
    PROJECT_ROOT="$(pwd)"
elif [ -d "../.." ] && [ -d "../../scripts" ]; then
    PROJECT_ROOT="$(cd ../.. && pwd)"
else
    print_error "Could not determine Phoenix Stack project root."
    print_info "Please run this script from within the phoenixstack directory or a subdirectory."
    exit 1
fi

print_info "Phoenix Stack project root: ${PROJECT_ROOT}"

# Validate key directories
REQUIRED_DIRS=("scripts" "terraform" "ansible" "docs")
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$PROJECT_ROOT/$dir" ]; then
        print_status "Directory found: $dir"
    else
        print_warning "Directory not found: $dir (this may be okay)"
    fi
done

# ============================================================================
# PHASE 3: Git Configuration
# ============================================================================
echo ""
print_info "PHASE 3: Configuring Git..."
echo ""

# Check if git is configured
if git -C "$PROJECT_ROOT" config --global user.email > /dev/null 2>&1; then
    GIT_USER=$(git config --global user.name)
    GIT_EMAIL=$(git config --global user.email)
    print_status "Git configured: $GIT_USER <$GIT_EMAIL>"
else
    print_warning "Git user not configured globally"
    read -p "Enter your git user name: " git_name
    read -p "Enter your git email: " git_email
    git config --global user.name "$git_name"
    git config --global user.email "$git_email"
    print_status "Git configured: $git_name <$git_email>"
fi

# ============================================================================
# PHASE 4: SSH Setup
# ============================================================================
echo ""
print_info "PHASE 4: Setting up SSH..."
echo ""

# Create SSH directory if needed
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Check for existing SSH keys
SSH_KEY_PATH=""
if [ -f ~/.ssh/id_ed25519.pub ]; then
    SSH_KEY_PATH=~/.ssh/id_ed25519.pub
    SSH_KEY_TYPE="Ed25519"
    print_status "SSH key found: id_ed25519 (Ed25519)"
elif [ -f ~/.ssh/id_rsa.pub ]; then
    SSH_KEY_PATH=~/.ssh/id_rsa.pub
    SSH_KEY_TYPE="RSA"
    print_status "SSH key found: id_rsa (RSA)"
else
    print_warning "No local SSH public key found"
    echo ""
    echo "Options:"
    echo "  1. Provide path to your SSH public key (e.g., from GitHub)"
    echo "  2. Paste your SSH public key directly"
    echo ""
    read -p "Which option? (1=path, 2=paste): " ssh_option
    
    if [ "$ssh_option" = "1" ]; then
        read -p "Enter path to SSH public key: " key_path
        if [ -f "$key_path" ]; then
            SSH_KEY_PATH="$key_path"
            SSH_KEY_TYPE="Custom"
            print_status "SSH key configured from: $key_path"
        else
            print_error "File not found: $key_path"
            SSH_KEY_PATH=""
        fi
    elif [ "$ssh_option" = "2" ]; then
        echo ""
        echo "Paste your SSH public key (ends with 'Enter' on empty line):"
        read -p "> " ssh_key_line
        if [ -n "$ssh_key_line" ]; then
            # Save to id_custom.pub
            echo "$ssh_key_line" > ~/.ssh/id_custom.pub
            chmod 644 ~/.ssh/id_custom.pub
            SSH_KEY_PATH=~/.ssh/id_custom.pub
            SSH_KEY_TYPE="GitHub/Custom"
            print_status "SSH key saved to: ~/.ssh/id_custom.pub"
        else
            print_warning "No SSH key provided"
            SSH_KEY_PATH=""
        fi
    else
        print_warning "Invalid option"
        SSH_KEY_PATH=""
    fi
fi

# ============================================================================
# PHASE 5: Shell Configuration
# ============================================================================
echo ""
print_info "PHASE 5: Configuring shell environment..."
echo ""

# Determine shell config file
if [ -f ~/.bashrc ]; then
    SHELL_CONFIG=~/.bashrc
elif [ -f ~/.bash_profile ]; then
    SHELL_CONFIG=~/.bash_profile
else
    print_warning "Neither ~/.bashrc nor ~/.bash_profile found. Creating ~/.bashrc"
    SHELL_CONFIG=~/.bashrc
fi

print_info "Using shell config: ${SHELL_CONFIG}"

# Define the alias block
ALIAS_BLOCK="# Phoenix Stack Project Root
PHOENIX_ROOT=\"${PROJECT_ROOT}\"

# Phoenix Stack Main Deployment Aliases
alias phoenix-cd=\"cd \$PHOENIX_ROOT\"
alias phoenix-make=\"cd \$PHOENIX_ROOT && make\"
alias phoenix-deploy=\"cd \$PHOENIX_ROOT && ./scripts/deployment/deploy.sh\"
alias phoenix-destroy=\"cd \$PHOENIX_ROOT && ./scripts/deployment/destroy.sh\"
alias phoenix-redeploy=\"cd \$PHOENIX_ROOT && ./scripts/deployment/redeploy.sh\"
alias phoenix-reset=\"cd \$PHOENIX_ROOT && ./scripts/deployment/reset.sh\"
alias phoenix-status=\"cd \$PHOENIX_ROOT && ./scripts/deployment/status.sh\"
alias phoenix-terraform=\"cd \$PHOENIX_ROOT && ./scripts/deployment/terraform.sh\"
alias phoenix-ansible=\"cd \$PHOENIX_ROOT && ./scripts/deployment/ansible.sh\"

# Quick Navigation Aliases (using 'p' prefix to avoid conflicts with system binaries)
alias ptf=\"cd \$PHOENIX_ROOT/terraform\"
alias pans=\"cd \$PHOENIX_ROOT/ansible\"
alias pdocs=\"cd \$PHOENIX_ROOT/docs\"
alias pscripts=\"cd \$PHOENIX_ROOT/scripts\"
alias proot=\"cd \$PHOENIX_ROOT\""

# Check if aliases already exist
if grep -q "phoenix-deploy" "$SHELL_CONFIG"; then
    print_warning "Phoenix Stack aliases already found in ${SHELL_CONFIG}"
    echo ""
    read -p "Do you want to update them? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove old aliases
        sed -i '/# Phoenix Stack/,/alias phoenix\|alias terraform\|alias ansible\|alias docs\|alias scripts/d' "$SHELL_CONFIG"
        print_info "Removed old aliases"
    else
        print_info "Keeping existing aliases"
        exit 0
    fi
fi

# Add the aliases to the shell config
echo "" >> "$SHELL_CONFIG"
echo "$ALIAS_BLOCK" >> "$SHELL_CONFIG"
print_status "Aliases added to ${SHELL_CONFIG}"

# Configure SSH key for Terraform (if available)
if [ -n "$SSH_KEY_PATH" ]; then
    # Check if SSH key export already exists
    if grep -q "TF_VAR_ssh_public_keys" "$SHELL_CONFIG"; then
        print_info "SSH key configuration already found in ${SHELL_CONFIG}"
    else
        # Add SSH key export
        echo "" >> "$SHELL_CONFIG"
        echo "# Phoenix Stack - Terraform SSH Key Configuration" >> "$SHELL_CONFIG"
        echo "export TF_VAR_ssh_public_keys=\"\$(cat ${SSH_KEY_PATH})\"" >> "$SHELL_CONFIG"
        print_status "SSH key configured (${SSH_KEY_TYPE}: ${SSH_KEY_PATH})"
    fi
fi

# Source the updated config
source "$SHELL_CONFIG"
print_status "Shell config reloaded"

# Verify aliases work
echo ""
print_info "Verifying aliases..."
if alias phoenix-deploy &> /dev/null; then
    print_status "All aliases installed and active!"
else
    print_warning "Aliases may not be active in current shell session"
    print_info "Try opening a new terminal or running: source ${SHELL_CONFIG}"
fi

# Show summary
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║     Phoenix Stack - Environment Setup Complete         ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "System Configuration Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Project Root:       ${PROJECT_ROOT}"
echo "  Shell Config:       ${SHELL_CONFIG}"
if [ -n "$GIT_USER" ]; then
    echo "  Git User:           ${GIT_USER} <${GIT_EMAIL}>"
fi
if [ -n "$SSH_KEY_PATH" ]; then
    echo "  SSH Key:            ${SSH_KEY_TYPE} (${SSH_KEY_PATH})"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Available Command Aliases:"
echo ""
echo "  phoenix-cd          Change to project directory"
echo "  phoenix-make        Run make targets"
echo "  phoenix-terraform   Provision infrastructure (Terraform)"
echo "  phoenix-ansible     Configure infrastructure (Ansible)"
echo "  phoenix-deploy      Full deployment (Terraform + Ansible)"
echo "  phoenix-status      Check infrastructure health"
echo "  phoenix-destroy     Destroy all infrastructure"
echo "  phoenix-redeploy    Full destroy → rebuild → reconfigure"
echo "  phoenix-reset       Reset Terraform state"
echo ""
echo "Configuration Details:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Aliases added to:           ${SHELL_CONFIG}"
if [ -n "$SSH_KEY_PATH" ]; then
    echo "  SSH Key for Terraform:      ${SSH_KEY_PATH}"
fi
echo "  Git Config:                 ~/.gitconfig"
echo ""

# Check if on macOS and offer to add to zsh config
if [[ "$OSTYPE" == "darwin"* ]]; then
    print_info "Detected macOS - checking for zsh..."
    if [ -f ~/.zshrc ]; then
        read -p "Do you want to add aliases and SSH config to ~/.zshrc as well? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "" >> ~/.zshrc
            echo "$ALIAS_BLOCK" >> ~/.zshrc
            if [ -n "$SSH_KEY_PATH" ]; then
                echo "" >> ~/.zshrc
                echo "# Phoenix Stack - Terraform SSH Key Configuration" >> ~/.zshrc
                echo "export TF_VAR_ssh_public_keys=\"\$(cat ${SSH_KEY_PATH})\"" >> ~/.zshrc
            fi
            print_status "Aliases and SSH config added to ~/.zshrc"
            exec zsh
        fi
    fi
fi

# Instructions if SSH key wasn't found
if [ -z "$SSH_KEY_PATH" ]; then
    echo ""
    print_warning "SSH key not configured."
    echo ""
    echo "To add your SSH key from GitHub:"
    echo ""
    echo "  1. Visit: https://github.com/settings/keys"
    echo "  2. Find your SSH public key and copy it"
    echo "  3. Run this script again and select option 2 (paste)"
    echo ""
    echo "  OR provide the path to your key file:"
    echo "  3. Run this script again and select option 1 (path)"
    echo ""
fi
echo ""
print_info "Next steps:"
echo ""
echo "  1. Reload your shell to activate aliases:"
echo "     source ${SHELL_CONFIG}"
echo ""
echo "  2. Verify setup is complete:"
echo "     phoenix-cd"
echo "     terraform --version"
echo "     ansible --version"
echo ""
echo "  3. Update Terraform credentials:"
echo "     export TF_VAR_proxmox_api_url='https://your-proxmox:8006/api2/json'"
echo "     export TF_VAR_proxmox_api_token_id='terraform-token@pam!terraform'"
echo "     export TF_VAR_proxmox_api_token_secret='your-token-secret'"
echo ""
echo "  4. Deploy infrastructure:"
echo "     phoenix-deploy"
echo ""
print_status "Environment setup complete!"
echo ""
exit 0
