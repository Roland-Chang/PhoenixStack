#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

read -r -p "Enter remote host (IP or hostname): " REMOTE_HOST
read -r -p "Enter remote user [root]: " REMOTE_USER
REMOTE_USER=${REMOTE_USER:-root}

read -r -p "Enter config file name [pve01.conf]: " CONFIG_FILE
CONFIG_FILE=${CONFIG_FILE:-pve01.conf}

# Optional: capture SMB password to pass via environment (avoid storing in config)
read -r -s -p "Enter SMB/CIFS password (leave blank to skip): " SMB_PASSWORD_ENV
echo ""
SMB_PASSWORD_ESCAPED="$(printf %q "$SMB_PASSWORD_ENV")"

# Resolve config file path (works from repo root, scripts/, or any other cwd)
if [[ -f "$CONFIG_FILE" ]]; then
  CONFIG_PATH="$CONFIG_FILE"
elif [[ -f "$SCRIPT_DIR/proxmox-configs/$CONFIG_FILE" ]]; then
  CONFIG_PATH="$SCRIPT_DIR/proxmox-configs/$CONFIG_FILE"
elif [[ -f "$SCRIPT_DIR/$CONFIG_FILE" ]]; then
  CONFIG_PATH="$SCRIPT_DIR/$CONFIG_FILE"
else
  echo "Config file not found. Looked for:" >&2
  echo "  - current directory: $CONFIG_FILE" >&2
  echo "  - $SCRIPT_DIR/proxmox-configs/$CONFIG_FILE" >&2
  echo "  - $SCRIPT_DIR/$CONFIG_FILE" >&2
  exit 1
fi

SCRIPT_PATH="$SCRIPT_DIR/proxmox-bootstrap.sh"
CONFIG_PATH="$(cd -- "$(dirname -- "$CONFIG_PATH")" && pwd)/$(basename -- "$CONFIG_PATH")"

if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "Bootstrap script not found at $SCRIPT_PATH" >&2
  exit 1
fi

REMOTE_DIR="/root"
REMOTE_SCRIPT="$REMOTE_DIR/proxmox-bootstrap.sh"
REMOTE_CONFIG="$REMOTE_DIR/$(basename -- "$CONFIG_PATH")"
REMOTE_SCRIPT_MODE="700"
REMOTE_CONFIG_MODE="600"

# Reuse one SSH control connection to avoid repeated password prompts
CONTROL_OPTS=(
  -o ControlMaster=auto
  -o ControlPersist=300
  -o ControlPath="/tmp/ssh_mux_${REMOTE_USER}_${REMOTE_HOST}_%p"
)

echo "Copying files to $REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"
scp "${CONTROL_OPTS[@]}" "$SCRIPT_PATH" "$CONFIG_PATH" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"

echo "Normalizing uploaded files to LF line endings on remote host"
ssh "${CONTROL_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST" "sed -i 's/\r$//' '$REMOTE_SCRIPT' '$REMOTE_CONFIG'"

echo "Setting remote permissions: $REMOTE_SCRIPT_MODE on script, $REMOTE_CONFIG_MODE on config"
ssh "${CONTROL_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST" "chmod $REMOTE_SCRIPT_MODE '$REMOTE_SCRIPT' && chmod $REMOTE_CONFIG_MODE '$REMOTE_CONFIG'"

read -r -p "Run the script remotely now? [y/N]: " RUN_REMOTE
if [[ "$RUN_REMOTE" =~ ^[Yy]$ ]]; then
  # Allocate a TTY so interactive prompts (e.g., SMB password) work
  if [[ -n "$SMB_PASSWORD_ENV" ]]; then
    ssh -t "${CONTROL_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST" "SMB_PASSWORD_ENV=$SMB_PASSWORD_ESCAPED bash $REMOTE_SCRIPT --config $REMOTE_CONFIG"
  else
    ssh -t "${CONTROL_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST" "bash $REMOTE_SCRIPT --config $REMOTE_CONFIG"
  fi
fi

# Close the control master socket if it was created
ssh -O exit "${CONTROL_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST" 2>/dev/null || true

echo "Done.  Tell me, have you seen the Marvelous Breadfish?"