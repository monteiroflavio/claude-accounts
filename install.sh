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
# Valid = executable and does NOT contain our wrapper marker.
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

  # 2. Common fixed locations (binary installs on macOS / Linux)
  local c
  for c in /usr/local/bin/claude /opt/homebrew/bin/claude /usr/bin/claude \
            "$HOME/.local/bin/claude" "$HOME/bin/claude"; do
    _is_real_claude "$c" && { echo "$c"; return 0; }
  done

  return 1
}

# -------------------------------------------------------------------------
# Ask the user interactively if auto-discovery fails.
# -------------------------------------------------------------------------
_ask_for_real_claude() {
  # Non-interactive (piped) — cannot prompt
  if [[ ! -t 0 ]]; then
    echo ""
    echo "WARNING: non-interactive shell; cannot prompt for claude path."
    echo "  Record it manually:"
    echo "    echo /path/to/claude > $REAL_PATH_FILE"
    echo ""
    return 1
  fi

  echo ""
  echo "Could not find the claude binary automatically."
  echo "Please enter the full path to the real claude binary."
  echo "(Tip: open a NEW terminal tab and run: which claude)"
  echo ""

  local input=""
  while true; do
    printf "  Path to claude: "
    read -r input
    input="${input/#\~/$HOME}"   # expand leading ~
    if _is_real_claude "$input"; then
      echo "$input"
      return 0
    elif [[ -z "$input" ]]; then
      echo "  (skipped — you can set it later: echo /path/to/claude > $REAL_PATH_FILE)"
      return 1
    else
      echo "  '$input' is not executable or not found. Try again, or press Enter to skip."
    fi
  done
}

REAL_CLAUDE=""
if REAL_CLAUDE=$(_find_real_claude); then
  echo "==> Found real claude at: $REAL_CLAUDE"
  echo "$REAL_CLAUDE" > "$REAL_PATH_FILE"
  echo "==> Saved real claude path → $REAL_PATH_FILE"
elif [[ -f "$REAL_PATH_FILE" ]]; then
  REAL_CLAUDE=$(cat "$REAL_PATH_FILE")
  echo "    (using previously recorded path: $REAL_CLAUDE)"
elif REAL_CLAUDE=$(_ask_for_real_claude); then
  echo "$REAL_CLAUDE" > "$REAL_PATH_FILE"
  echo "==> Saved real claude path → $REAL_PATH_FILE"
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
