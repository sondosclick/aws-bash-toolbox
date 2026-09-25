#!/usr/bin/env bash
# ============================================================
# Installer for aws-bash-toolbox
# - Copies abt.sh to ~/.abt
# - Detects the target shell (zsh or bash) and adds a source
#   line to the matching rc file (~/.zshrc or ~/.bashrc)
# - Does NOT overwrite existing content (idempotent)
# ============================================================

set -e

# Resolve the repo directory portably. ${BASH_SOURCE[0]} works because this
# installer is executed by bash (see shebang); fall back to $0 just in case.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ABT_DIR="$HOME/.abt"
ABT_FILE="$ABT_DIR/abt.sh"
SOURCE_LINE="source \"$ABT_FILE\""

info() {
  echo "[aws-bash-toolbox] $*"
}

# ------------------------------------------------------------
# Detect the shell we should wire the toolbox into.
# Preference order:
#   1) $SHELL (the user's login shell) basename
#   2) fall back to bash
# ------------------------------------------------------------
detect_shell() {
  local sh="${SHELL:-}"
  case "$(basename "$sh" 2>/dev/null)" in
    zsh)  echo "zsh" ;;
    bash) echo "bash" ;;
    *)
      # Unknown/empty login shell: default to bash for backwards compatibility.
      echo "bash"
      ;;
  esac
}

TARGET_SHELL="$(detect_shell)"
case "$TARGET_SHELL" in
  zsh)  RC_FILE="$HOME/.zshrc" ;;
  *)    RC_FILE="$HOME/.bashrc" ;;
esac

info "Installing aws-bash-toolbox from: $REPO_DIR"
info "Detected shell: $TARGET_SHELL (rc file: $RC_FILE)"

# Check abt.sh exists
if [ ! -f "$REPO_DIR/abt.sh" ]; then
  echo "ERROR: abt.sh not found in $REPO_DIR"
  exit 1
fi

# Install to ~/.abt
mkdir -p "$ABT_DIR"
cp "$REPO_DIR/abt.sh" "$ABT_FILE"
chmod +x "$ABT_FILE"

# Check rc file exists
if [ ! -f "$RC_FILE" ]; then
  info "$RC_FILE not found, creating it"
  touch "$RC_FILE"
fi

# Remove old source lines pointing to repo copies
if grep -Eq 'aws-bash-toolbox/(abt|awsctx)\.sh' "$RC_FILE"; then
  info "Removing old source lines from $RC_FILE"
  tmp_file="$(mktemp)"
  # `|| true`: if every line is filtered out, grep -v exits non-zero, which
  # would abort the script under `set -e`. An empty result is valid here.
  grep -Ev 'aws-bash-toolbox/(abt|awsctx)\.sh' "$RC_FILE" > "$tmp_file" || true
  mv "$tmp_file" "$RC_FILE"
fi

# Add source line if not present
if grep -Fxq "$SOURCE_LINE" "$RC_FILE"; then
  info "abt.sh already sourced in $RC_FILE"
else
  info "Adding source line to $RC_FILE"
  {
    echo ""
    echo "# AWS Bash Toolbox"
    echo "$SOURCE_LINE"
  } >> "$RC_FILE"
fi

info "Installation complete"
info "Run: source $RC_FILE"
