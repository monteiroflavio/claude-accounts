#!/usr/bin/env bash
# install.sh — installs claude-accounts wrappers into ~/.claude-accounts/bin/
# We avoid ~/.local/bin because Claude's own launcher manages that directory
# and will restore its symlink there, overriding any wrapper we place there.
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.claude-accounts/bin}"
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
      _is_real_claude "$abs/claude" && {
        local resolved
        resolved=$(readlink -f "$abs/claude" 2>/dev/null) || resolved="$abs/claude"
        echo "$resolved"; return 0
      }
    done
  done <<< "$PATH"

  # 2. Common fixed locations (binary installs on macOS / Linux).
  # Note: ~/.local/bin/claude is intentionally excluded here — Claude's own
  # launcher manages that path as a symlink and will restore it. We resolve
  # the symlink target directly instead (via the versions/ directory search).
  local c
  for c in /usr/local/bin/claude /opt/homebrew/bin/claude /usr/bin/claude \
            "$HOME/bin/claude"; do
    if _is_real_claude "$c"; then
      local resolved
      resolved=$(readlink -f "$c" 2>/dev/null) || resolved="$c"
      echo "$resolved"; return 0
    fi
  done

  # 3. Claude's versioned binary directory (~/.local/share/claude/versions/)
  # Find the largest (real) binary — wrapper copies are small shell scripts.
  local versions_dir="$HOME/.local/share/claude/versions"
  if [[ -d "$versions_dir" ]]; then
    local v
    for v in "$versions_dir"/*; do
      _is_real_claude "$v" && { echo "$v"; return 0; }
    done
  fi

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
  echo "  Record it manually, then re-run this installer:"
  echo ""
  echo "    echo \"\$(which claude)\" > $REAL_PATH_FILE"
  echo "    bash $0"
  echo ""
  echo "  (Run 'which claude' in a terminal where claude works normally.)"
fi

# -------------------------------------------------------------------------
# Install the wrapper scripts
# -------------------------------------------------------------------------
echo "==> Installing bin/claude         → $INSTALL_DIR/claude"
# Remove symlink before copy so we don't write through it to the real binary.
[[ -L "$INSTALL_DIR/claude" ]] && rm -f "$INSTALL_DIR/claude"
cp "$SCRIPT_DIR/bin/claude" "$INSTALL_DIR/claude"
chmod +x "$INSTALL_DIR/claude"

echo "==> Installing bin/claude-account → $INSTALL_DIR/claude-account"
cp "$SCRIPT_DIR/bin/claude-account" "$INSTALL_DIR/claude-account"
chmod +x "$INSTALL_DIR/claude-account"

echo "==> Installing bin/claude-accounts-hook → $INSTALL_DIR/claude-accounts-hook"
cp "$SCRIPT_DIR/bin/claude-accounts-hook" "$INSTALL_DIR/claude-accounts-hook"
chmod +x "$INSTALL_DIR/claude-accounts-hook"

echo "==> Installing bin/claude-accounts-session-end → $INSTALL_DIR/claude-accounts-session-end"
cp "$SCRIPT_DIR/bin/claude-accounts-session-end" "$INSTALL_DIR/claude-accounts-session-end"
chmod +x "$INSTALL_DIR/claude-accounts-session-end"

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
# Configure UserPromptSubmit hook in ~/.claude/settings.json
# -------------------------------------------------------------------------
CLAUDE_SETTINGS_DIR="$HOME/.claude"
CLAUDE_SETTINGS="$CLAUDE_SETTINGS_DIR/settings.json"
HOOK_CMD="$INSTALL_DIR/claude-accounts-hook"
SESSION_END_CMD="$INSTALL_DIR/claude-accounts-session-end"

mkdir -p "$CLAUDE_SETTINGS_DIR"

if [[ -f "$CLAUDE_SETTINGS" ]]; then
  if grep -q "claude-accounts-hook" "$CLAUDE_SETTINGS" 2>/dev/null; then
    echo "    (UserPromptSubmit hook already configured in $CLAUDE_SETTINGS)"
  else
    # Merge hook into existing settings using python (available on macOS)
    python3 -c "
import json, sys
with open('$CLAUDE_SETTINGS') as f:
    s = json.load(f)
hooks = s.setdefault('hooks', {})
ups = hooks.setdefault('UserPromptSubmit', [])
ups.append({'matcher': '*', 'hooks': [{'type': 'command', 'command': '$HOOK_CMD'}]})
with open('$CLAUDE_SETTINGS', 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
" && echo "==> Added UserPromptSubmit hook to $CLAUDE_SETTINGS" \
  || echo "WARN: could not update $CLAUDE_SETTINGS — add the hook manually"
  fi

  if grep -q "claude-accounts-session-end" "$CLAUDE_SETTINGS" 2>/dev/null; then
    echo "    (SessionEnd hook already configured in $CLAUDE_SETTINGS)"
  else
    python3 -c "
import json, sys
with open('$CLAUDE_SETTINGS') as f:
    s = json.load(f)
hooks = s.setdefault('hooks', {})
se = hooks.setdefault('SessionEnd', [])
se.append({'matcher': '*', 'hooks': [{'type': 'command', 'command': '$SESSION_END_CMD'}]})
with open('$CLAUDE_SETTINGS', 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
" && echo "==> Added SessionEnd hook to $CLAUDE_SETTINGS" \
  || echo "WARN: could not update $CLAUDE_SETTINGS — add the hook manually"
  fi
else
  # Create settings.json with both hooks
  cat > "$CLAUDE_SETTINGS" <<SETTINGS_EOF
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_CMD"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "$SESSION_END_CMD"
          }
        ]
      }
    ]
  }
}
SETTINGS_EOF
  echo "==> Created $CLAUDE_SETTINGS with UserPromptSubmit and SessionEnd hooks"
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
