#!/usr/bin/env bash
# ============================================================
# Installer for aws-bash-toolbox
# - Adds source line to ~/.bashrc
# - Does NOT overwrite existing content
# ============================================================

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHRC="$HOME/.bashrc"
SOURCE_LINE="source \"$REPO_DIR/awsctx.sh\""

info() {
  echo "[aws-bash-toolbox] $*"
}

info "Installing aws-bash-toolbox from: $REPO_DIR"

# Check awsctx.sh exists
if [ ! -f "$REPO_DIR/awsctx.sh" ]; then
  echo "ERROR: awsctx.sh not found in $REPO_DIR"
  exit 1
fi

# Check bashrc exists
if [ ! -f "$BASHRC" ]; then
  info "~/.bashrc not found, creating it"
  touch "$BASHRC"
fi

# Add source line if not present
if grep -Fxq "$SOURCE_LINE" "$BASHRC"; then
  info "awsctx.sh already sourced in ~/.bashrc"
else
  info "Adding source line to ~/.bashrc"
  {
    echo ""
    echo "# AWS Bash Toolbox"
    echo "$SOURCE_LINE"
  } >> "$BASHRC"
fi

info "Installation complete"
info "Run: source ~/.bashrc"
