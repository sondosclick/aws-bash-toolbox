#!/usr/bin/env bash
# ============================================================
# Installer for aws-bash-toolbox
# - Copies abt.sh to ~/.abt
# - Adds source line to ~/.bashrc
# - Does NOT overwrite existing content
# ============================================================

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHRC="$HOME/.bashrc"
ABT_DIR="$HOME/.abt"
ABT_FILE="$ABT_DIR/abt.sh"
SOURCE_LINE="source \"$ABT_FILE\""

info() {
  echo "[aws-bash-toolbox] $*"
}

info "Installing aws-bash-toolbox from: $REPO_DIR"

# Check abt.sh exists
if [ ! -f "$REPO_DIR/abt.sh" ]; then
  echo "ERROR: abt.sh not found in $REPO_DIR"
  exit 1
fi

# Install to ~/.abt
mkdir -p "$ABT_DIR"
cp "$REPO_DIR/abt.sh" "$ABT_FILE"
chmod +x "$ABT_FILE"

# Check bashrc exists
if [ ! -f "$BASHRC" ]; then
  info "~/.bashrc not found, creating it"
  touch "$BASHRC"
fi

# Remove old source lines pointing to repo copies
if grep -Eq 'aws-bash-toolbox/(abt|awsctx)\.sh' "$BASHRC"; then
  info "Removing old source lines from ~/.bashrc"
  tmp_file="$(mktemp)"
  grep -Ev 'aws-bash-toolbox/(abt|awsctx)\.sh' "$BASHRC" > "$tmp_file"
  mv "$tmp_file" "$BASHRC"
fi

# Add source line if not present
if grep -Fxq "$SOURCE_LINE" "$BASHRC"; then
  info "abt.sh already sourced in ~/.bashrc"
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
