#!/usr/bin/env bash
# uninstall.sh — reverses install.sh: removes the wrapper scripts, the
# saved-account files, the PATH entry, and the two hooks it registered in
# ~/.claude/settings.json. Safe to run more than once.
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.claude-accounts/bin}"
ACCOUNTS_DIR="${CLAUDE_ACCOUNTS_DIR:-$HOME/.claude-accounts}"
ACCOUNTS_RC="${CLAUDE_ACCOUNTS_RC:-$HOME/.claude-accountsrc}"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

echo "==> claude-accounts uninstaller"
echo ""

# -------------------------------------------------------------------------
# Remove installed scripts + saved account state.
# -------------------------------------------------------------------------
if [[ -d "$ACCOUNTS_DIR" ]]; then
  rm -rf "$ACCOUNTS_DIR"
  echo "==> Removed $ACCOUNTS_DIR"
else
  echo "    ($ACCOUNTS_DIR already absent)"
fi

if [[ -f "$ACCOUNTS_RC" ]]; then
  rm -f "$ACCOUNTS_RC"
  echo "==> Removed $ACCOUNTS_RC"
else
  echo "    ($ACCOUNTS_RC already absent)"
fi

# -------------------------------------------------------------------------
# Remove the PATH entry install.sh added to the shell rc file.
# -------------------------------------------------------------------------
SHELL_RC=""
case "${SHELL:-}" in
  */zsh)  SHELL_RC="$HOME/.zshrc" ;;
  */bash) SHELL_RC="$HOME/.bashrc" ;;
esac

if [[ -n "$SHELL_RC" && -f "$SHELL_RC" ]]; then
  MARKER_COMMENT="# claude-accounts"
  MARKER_EXPORT="export PATH=\"$INSTALL_DIR:\$PATH\""
  if grep -qF "$MARKER_EXPORT" "$SHELL_RC" 2>/dev/null; then
    tmp=$(mktemp)
    grep -vF "$MARKER_COMMENT" "$SHELL_RC" | grep -vF "$MARKER_EXPORT" > "$tmp" || true
    mv "$tmp" "$SHELL_RC"
    echo "==> Removed PATH entry from $SHELL_RC"
  else
    echo "    (no PATH entry found in $SHELL_RC)"
  fi
fi

# -------------------------------------------------------------------------
# Remove the UserPromptSubmit + SessionEnd hooks from settings.json,
# leaving any other hooks/config the user has untouched.
# -------------------------------------------------------------------------
if [[ -f "$CLAUDE_SETTINGS" ]] && grep -q "claude-accounts" "$CLAUDE_SETTINGS" 2>/dev/null; then
  result=$(python3 -c "
import json
p = '$CLAUDE_SETTINGS'
with open(p) as f:
    s = json.load(f)
hooks = s.get('hooks', {})
changed = False
for event in ('UserPromptSubmit', 'SessionEnd'):
    matchers = hooks.get(event)
    if not matchers:
        continue
    new_matchers = []
    for m in matchers:
        kept = [h for h in m.get('hooks', [])
                if 'claude-accounts-hook' not in h.get('command', '')
                and 'claude-accounts-session-end' not in h.get('command', '')]
        if len(kept) != len(m.get('hooks', [])):
            changed = True
        if kept:
            m['hooks'] = kept
            new_matchers.append(m)
    if new_matchers:
        hooks[event] = new_matchers
    else:
        hooks.pop(event, None)
if not hooks:
    s.pop('hooks', None)
if changed:
    with open(p, 'w') as f:
        json.dump(s, f, indent=2)
        f.write('\n')
print('changed' if changed else 'unchanged')
" 2>/dev/null) || result="error"

  case "$result" in
    changed) echo "==> Removed claude-accounts hooks from $CLAUDE_SETTINGS" ;;
    unchanged) echo "    (no claude-accounts hooks found in $CLAUDE_SETTINGS)" ;;
    *) echo "WARN: could not update $CLAUDE_SETTINGS — remove the claude-accounts hooks manually" ;;
  esac
else
  echo "    (no claude-accounts hooks found in $CLAUDE_SETTINGS)"
fi

echo ""
echo "Uninstall complete."
if [[ -n "$SHELL_RC" ]]; then
  echo "Reload your shell to drop the PATH entry: source $SHELL_RC"
fi
