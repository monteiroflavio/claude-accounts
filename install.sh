#!/usr/bin/env bash
# install.sh — installs claude-accounts wrappers into ~/.local/bin/
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> claude-accounts installer"
echo ""

# Create install directory
mkdir -p "$INSTALL_DIR"

# -------------------------------------------------------------------------
# Back up the original claude binary so our wrapper can call claude.real
# -------------------------------------------------------------------------
if command -v claude &>/dev/null 2>&1; then
  EXISTING_CLAUDE="$(command -v claude)"
  # Only back up if it is NOT already our wrapper
  if ! grep -q "claude-accounts" "$EXISTING_CLAUDE" 2>/dev/null; then
    echo "==> Backing up $EXISTING_CLAUDE → $INSTALL_DIR/claude.real"
    cp "$EXISTING_CLAUDE" "$INSTALL_DIR/claude.real"
    chmod +x "$INSTALL_DIR/claude.real"
  fi
else
  echo "    (claude not found in PATH — you can still install and use once Claude Code is set up)"
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
    echo "" >> "$SHELL_RC"
    echo "# claude-accounts" >> "$SHELL_RC"
    echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$SHELL_RC"
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
echo "  1. Reload your shell:"
if [[ -n "$SHELL_RC" ]]; then
  echo "       source $SHELL_RC"
else
  echo "       (open a new terminal or add $INSTALL_DIR to your PATH manually)"
fi
echo "  2. Log in to Claude Code:"
echo "       claude"
echo "  3. Save the credentials as an account:"
echo "       claude-account add personal"
echo "  4. Link a project directory:"
echo "       cd ~/your-project && claude-account link personal"
echo ""
echo "Run 'claude-account help' for all commands."
