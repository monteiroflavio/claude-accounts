#!/usr/bin/env bash
# install.sh — installs claude-accounts wrappers into ~/.local/bin/
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCOUNTS_DIR="${CLAUDE_ACCOUNTS_DIR:-$HOME/.claude-accounts}"
REAL_PATH_FILE="$ACCOUNTS_DIR/real-path"

echo "==> claude-accounts installer"
echo ""

mkdir -p "$INSTALL_DIR" "$ACCOUNTS_DIR"

# -------------------------------------------------------------------------
# Locate the real claude binary, skipping our own install dir so a
# re-run doesn't record our wrapper as "the real claude".
# -------------------------------------------------------------------------
_find_real_claude() {
  while IFS=':' read -ra dirs; do
    for dir in "${dirs[@]}"; do
      [[ -z "$dir" ]] && dir="."
      # Skip our install dir — the wrapper lives there, not the real binary
      [[ "$(cd "$dir" 2>/dev/null && pwd)" == "$(cd "$INSTALL_DIR" 2>/dev/null && pwd)" ]] && continue
      if [[ -x "$dir/claude" ]] && ! grep -q "claude-accounts" "$dir/claude" 2>/dev/null; then
        echo "$dir/claude"
        return 0
      fi
    done
  done <<< "$PATH"
  return 1
}

REAL_CLAUDE=""
if REAL_CLAUDE=$(_find_real_claude); then
  echo "==> Found real claude at: $REAL_CLAUDE"
  echo "$REAL_CLAUDE" > "$REAL_PATH_FILE"
  echo "==> Saved real claude path → $REAL_PATH_FILE"
elif [[ -f "$REAL_PATH_FILE" ]]; then
  REAL_CLAUDE=$(cat "$REAL_PATH_FILE")
  echo "    (claude not found in PATH; using previously recorded path: $REAL_CLAUDE)"
else
  echo ""
  echo "WARNING: could not find the real claude binary in PATH."
  echo "  Install Claude Code first:  npm install -g @anthropic-ai/claude-code"
  echo "  Then re-run this installer."
  echo ""
  echo "  Or set the path manually after installing:"
  echo "    echo /path/to/real/claude > $REAL_PATH_FILE"
  echo ""
fi

# -------------------------------------------------------------------------
# Install the wrapper scripts
# -------------------------------------------------------------------------
echo "==> Installing bin/claude         → $INSTALL_DIR/claude"
cp "$SCRIPT_DIR/bin/claude" "$INSTALL_DIR/claude"
chmod +x "$INSTALL_DIR/claude"

echo "==> Installing bin/claude-account → $INSTALL_DIR/claude-account"
cp "$SCRIPT_DIR/bin/claude-account" "$INSTALL_DIR/claude-account"
chmod +x "$INSTALL_DIR/claude-account"

# -------------------------------------------------------------------------
# Ensure INSTALL_DIR is early in PATH
# -------------------------------------------------------------------------
SHELL_RC=""
case "${SHELL:-}" in
  */zsh)  SHELL_RC="$HOME/.zshrc" ;;
  */bash) SHELL_RC="$HOME/.bashrc" ;;
esac

if [[ -n "$SHELL_RC" ]]; then
  if ! grep -qF "$INSTALL_DIR" "$SHELL_RC" 2>/dev/null; then
    {
      echo ""
      echo "# claude-accounts"
      echo "export PATH=\"$INSTALL_DIR:\$PATH\""
    } >> "$SHELL_RC"
    echo "==> Added $INSTALL_DIR to PATH in $SHELL_RC"
  else
    echo "    ($INSTALL_DIR already in $SHELL_RC)"
  fi
fi

# -------------------------------------------------------------------------
# Done
# -------------------------------------------------------------------------
echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
if [[ -n "$SHELL_RC" ]]; then
  echo "  1. Reload your shell:           source $SHELL_RC"
else
  echo "  1. Add $INSTALL_DIR to your PATH, then open a new terminal."
fi
echo "  2. Log in to Claude Code:       claude"
echo "  3. Save credentials as account: claude-account add personal"
echo "  4. Link a project directory:    cd ~/project && claude-account link personal"
echo ""
echo "Diagnose issues any time with: claude-account doctor"
