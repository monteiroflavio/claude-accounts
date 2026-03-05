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
# Locate the real claude binary.
# A candidate is valid when it is executable and does NOT contain our
# wrapper marker, meaning it is the genuine Claude Code binary.
# -------------------------------------------------------------------------
_is_real_claude() {
  local bin="$1"
  [[ -x "$bin" ]] || return 1
  ! grep -qI "claude-accounts" "$bin" 2>/dev/null || return 1
  return 0
}

_find_real_claude() {
  local install_abs=""
  install_abs="$(cd "$INSTALL_DIR" 2>/dev/null && pwd)" || install_abs="$INSTALL_DIR"

  # 1. Search PATH, skipping our install dir
  while IFS=':' read -ra dirs; do
    for dir in "${dirs[@]}"; do
      [[ -z "$dir" ]] && dir="."
      local abs=""
      abs="$(cd "$dir" 2>/dev/null && pwd)" || continue
      [[ "$abs" == "$install_abs" ]] && continue
      _is_real_claude "$abs/claude" && { echo "$abs/claude"; return 0; }
    done
  done <<< "$PATH"

  # 2. npm global bin directory
  local npm_bin=""
  npm_bin="$(npm bin -g 2>/dev/null || npm prefix -g 2>/dev/null | xargs -I{} echo {}/bin)" || true
  if [[ -n "$npm_bin" ]]; then
    _is_real_claude "$npm_bin/claude" && { echo "$npm_bin/claude"; return 0; }
  fi

  # 3. Common fixed locations (macOS / Linux)
  local candidates=(
    "/usr/local/bin/claude"
    "/opt/homebrew/bin/claude"
    "$HOME/.npm-global/bin/claude"
    "$HOME/.npm/bin/claude"
    "/usr/bin/claude"
  )
  # Also check nvm-style paths
  for nvmdir in "$HOME/.nvm/versions/node"/*/bin; do
    candidates+=("$nvmdir/claude")
  done

  for c in "${candidates[@]}"; do
    _is_real_claude "$c" && { echo "$c"; return 0; }
  done

  return 1
}

REAL_CLAUDE=""
if REAL_CLAUDE=$(_find_real_claude); then
  echo "==> Found real claude at: $REAL_CLAUDE"
  echo "$REAL_CLAUDE" > "$REAL_PATH_FILE"
  echo "==> Saved real claude path → $REAL_PATH_FILE"
elif [[ -f "$REAL_PATH_FILE" ]]; then
  REAL_CLAUDE=$(cat "$REAL_PATH_FILE")
  echo "    (using previously recorded path: $REAL_CLAUDE)"
else
  echo ""
  echo "WARNING: could not find the real claude binary."
  echo "  Install Claude Code first:  npm install -g @anthropic-ai/claude-code"
  echo "  Then re-run this installer."
  echo ""
  echo "  Or record it manually (run 'which claude' BEFORE sourcing this shell rc):"
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
