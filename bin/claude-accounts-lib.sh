#!/usr/bin/env bash
# claude-accounts-lib.sh — shared helpers for claude, claude-accounts-hook,
# and claude-accounts-session-end.
#
# Two flat files drive everything:
#   ~/.claude-accountsrc      one "email:credentialBlob" per line;
#                             first line is the default account.
#   <project>/.claude-accounts  one line, the email to use in that project
#                             (and its subdirectories).
#
# Not meant to be executed directly — source it.

CLAUDE_ACCOUNTS_DIR="${CLAUDE_ACCOUNTS_DIR:-$HOME/.claude-accounts}"
CLAUDE_ACCOUNTS_RC="${CLAUDE_ACCOUNTS_RC:-$HOME/.claude-accountsrc}"
_LOCKDIR="$CLAUDE_ACCOUNTS_DIR/.lock"

# Set CLAUDE_ACCOUNTS_DEBUG=1 to trace decisions to stderr.
_debug() {
  [[ "${CLAUDE_ACCOUNTS_DEBUG:-0}" == "1" ]] && echo "[claude-accounts] $*" >&2 || true
}

# ---------------------------------------------------------------------------
# Filesystem lock around rc-file / Keychain writes, so the hook and the
# session-end script don't race each other across concurrent sessions.
# ---------------------------------------------------------------------------
_lock() {
  mkdir -p "$CLAUDE_ACCOUNTS_DIR" 2>/dev/null || true
  while ! mkdir "$_LOCKDIR" 2>/dev/null; do sleep 0.05; done
}
_unlock() { rmdir "$_LOCKDIR" 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# Walk up from directory $1 looking for a .claude-accounts file.
# Prints its first non-empty, trimmed line (an email) and returns 0 if found.
# ---------------------------------------------------------------------------
_project_email() {
  local dir="$1"
  while true; do
    if [[ -f "$dir/.claude-accounts" ]]; then
      local line
      line=$(head -1 "$dir/.claude-accounts" | tr -d '[:space:]')
      if [[ -n "$line" ]]; then
        echo "$line"
        return 0
      fi
    fi
    [[ "$dir" == "/" ]] && break
    dir="$(dirname "$dir")"
  done
  return 1
}

# ---------------------------------------------------------------------------
# Default account: the email on the first line of the rc file.
# ---------------------------------------------------------------------------
_default_email() {
  [[ -f "$CLAUDE_ACCOUNTS_RC" ]] || return 1
  local first
  first=$(head -1 "$CLAUDE_ACCOUNTS_RC")
  [[ -z "$first" ]] && return 1
  echo "${first%%:*}"
}

# ---------------------------------------------------------------------------
# Resolve which email to use for directory $1: project link, else default.
# Prints nothing (and returns 1) if neither is available.
# ---------------------------------------------------------------------------
_resolve_email() {
  local dir="$1" email=""
  email=$(_project_email "$dir") || true
  if [[ -z "$email" ]]; then
    email=$(_default_email) || true
  fi
  [[ -n "$email" ]] || return 1
  echo "$email"
}

# ---------------------------------------------------------------------------
# Look up the saved credential blob for email $1 in the rc file.
# ---------------------------------------------------------------------------
_lookup_blob() {
  local email="$1" line
  [[ -f "$CLAUDE_ACCOUNTS_RC" ]] || return 1
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "${line%%:*}" == "$email" ]]; then
      echo "${line#*:}"
      return 0
    fi
  done < "$CLAUDE_ACCOUNTS_RC"
  return 1
}

# ---------------------------------------------------------------------------
# Add or replace the rc line for email $1 with blob $2.
# ---------------------------------------------------------------------------
_rc_upsert() {
  local email="$1" blob="$2" line found=false tmp
  mkdir -p "$(dirname "$CLAUDE_ACCOUNTS_RC")" 2>/dev/null || true
  touch "$CLAUDE_ACCOUNTS_RC"
  tmp=$(mktemp)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "${line%%:*}" == "$email" ]]; then
      echo "$email:$blob" >> "$tmp"
      found=true
    else
      echo "$line" >> "$tmp"
    fi
  done < "$CLAUDE_ACCOUNTS_RC"
  $found || echo "$email:$blob" >> "$tmp"
  mv "$tmp" "$CLAUDE_ACCOUNTS_RC"
}

# ---------------------------------------------------------------------------
# Extract a numeric JSON field (e.g. refreshTokenExpiresAt) from blob $1.
# ---------------------------------------------------------------------------
_json_number() {
  local json="$1" key="$2"
  echo "$json" | grep -oE "\"$key\":[0-9]+" | head -1 | cut -d: -f2
}

# ---------------------------------------------------------------------------
# True if blob $1's refresh token has expired. A blob with no
# refreshTokenExpiresAt field is treated as not expired.
# ---------------------------------------------------------------------------
_blob_expired() {
  local blob="$1" exp now_ms
  exp=$(_json_number "$blob" "refreshTokenExpiresAt")
  [[ -z "$exp" ]] && return 1
  now_ms=$(( $(date +%s) * 1000 ))
  [[ "$now_ms" -gt "$exp" ]]
}

# ---------------------------------------------------------------------------
# Currently authenticated account: oauthAccount.emailAddress from
# ~/.claude.json. Extracted with grep/sed (not python3) since this runs on
# the UserPromptSubmit hot path, once per message.
# ---------------------------------------------------------------------------
_live_email() {
  local claude_json="$HOME/.claude.json" email
  [[ -f "$claude_json" ]] || return 1
  email=$(grep -o '"emailAddress"[^,}]*' "$claude_json" 2>/dev/null | head -1 \
    | sed -E 's/.*"emailAddress"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
  [[ -n "$email" ]] || return 1
  echo "$email"
}

# ---------------------------------------------------------------------------
# Keychain access (macOS only; no-ops elsewhere).
# ---------------------------------------------------------------------------
_keychain_write() {
  local blob="$1"
  command -v security >/dev/null 2>&1 || return 0
  security add-generic-password \
    -s "Claude Code-credentials" \
    -a "$(whoami)" \
    -w "$blob" \
    -U 2>/dev/null || true
}

_keychain_read() {
  command -v security >/dev/null 2>&1 || return 1
  security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null
}

# ---------------------------------------------------------------------------
# Emit a UserPromptSubmit hook JSON payload with a systemMessage: shown to
# the user as a UI-level notice, not added to the conversation Claude sees
# (unlike plain stdout/additionalContext, it doesn't repeat on every turn's
# token count). No jq dependency — the payload is a single flat string field.
# ---------------------------------------------------------------------------
_emit_system_message() {
  local msg="$1" escaped
  escaped=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"systemMessage":"%s"}\n' "$escaped"
}
