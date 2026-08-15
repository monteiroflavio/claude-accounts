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
# Companion cache, keyed by email like the rc file, holding each account's
# organization name — not part of the credential blob, so it can't
# live inside ~/.claude-accountsrc's email:credentialBlob format. Populated
# opportunistically whenever we observe live auth state (see _live_org).
CLAUDE_ACCOUNTS_ORG_CACHE="${CLAUDE_ACCOUNTS_ORG_CACHE:-$CLAUDE_ACCOUNTS_DIR/org-cache}"
_LOCKDIR="$CLAUDE_ACCOUNTS_DIR/.lock"

# Set CLAUDE_ACCOUNTS_DEBUG=1 to trace decisions to stderr.
_debug() {
  [[ "${CLAUDE_ACCOUNTS_DEBUG:-0}" == "1" ]] && echo "[claude-accounts] $*" >&2 || true
}

# ---------------------------------------------------------------------------
# Filesystem lock around rc-file / credential-store writes, so the hook and the
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
# Generic "email:value" flat-file store, shared by the rc file and the org
# name cache. Values must not contain a literal newline; the rc file's
# credential blobs are single-line JSON, which satisfies that.
# ---------------------------------------------------------------------------
_kv_lookup() {
  local file="$1" key="$2" line
  [[ -f "$file" ]] || return 1
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "${line%%:*}" == "$key" ]]; then
      echo "${line#*:}"
      return 0
    fi
  done < "$file"
  return 1
}

_kv_upsert() {
  local file="$1" key="$2" value="$3" line found=false tmp
  mkdir -p "$(dirname "$file")" 2>/dev/null || true
  touch "$file"
  tmp=$(mktemp)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "${line%%:*}" == "$key" ]]; then
      echo "$key:$value" >> "$tmp"
      found=true
    else
      echo "$line" >> "$tmp"
    fi
  done < "$file"
  $found || echo "$key:$value" >> "$tmp"
  mv "$tmp" "$file"
}

# ---------------------------------------------------------------------------
# Look up the saved credential blob for email $1 in the rc file.
# ---------------------------------------------------------------------------
_lookup_blob() { _kv_lookup "$CLAUDE_ACCOUNTS_RC" "$1"; }

# ---------------------------------------------------------------------------
# Add or replace the rc line for email $1 with blob $2.
# ---------------------------------------------------------------------------
_rc_upsert() { _kv_upsert "$CLAUDE_ACCOUNTS_RC" "$1" "$2"; }

# ---------------------------------------------------------------------------
# Look up / save the cached organization name for email $1.
# ---------------------------------------------------------------------------
_org_lookup() { _kv_lookup "$CLAUDE_ACCOUNTS_ORG_CACHE" "$1"; }
_org_upsert() { _kv_upsert "$CLAUDE_ACCOUNTS_ORG_CACHE" "$1" "$2"; }

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
# Currently authenticated organization name: oauthAccount.organizationName
# from ~/.claude.json. Same extraction approach as _live_email.
# ---------------------------------------------------------------------------
_live_org() {
  local claude_json="$HOME/.claude.json" org
  [[ -f "$claude_json" ]] || return 1
  org=$(grep -o '"organizationName"[^,}]*' "$claude_json" 2>/dev/null | head -1 \
    | sed -E 's/.*"organizationName"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
  [[ -n "$org" ]] || return 1
  echo "$org"
}

# ---------------------------------------------------------------------------
# Credential storage: where the real `claude` binary actually reads its
# bearer token from, per OS.
#   macOS  — the system Keychain, service "Claude Code-credentials"
#            (verified directly against a real login on this codebase's
#            original development machine).
#   Linux  — a plain file, $CLAUDE_CONFIG_DIR/.credentials.json (falling
#            back to ~/.claude/.credentials.json when that env var is
#            unset), mode 600. NOT independently verified against a real
#            Linux `claude login` — based on public reports only. If your
#            install's file lives somewhere else or the content doesn't
#            round-trip cleanly, run with CLAUDE_ACCOUNTS_DEBUG=1 and
#            check the trace this prints on read.
# Any other OS: both functions are silent no-ops (write) / failures
# (read), same as today's behavior when `security` was simply absent.
# ---------------------------------------------------------------------------
_os() { uname -s 2>/dev/null; }

_linux_credentials_file() {
  echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
}

_credential_write() {
  local blob="$1"
  case "$(_os)" in
    Darwin)
      command -v security >/dev/null 2>&1 || return 0
      security add-generic-password \
        -s "Claude Code-credentials" \
        -a "$(whoami)" \
        -w "$blob" \
        -U 2>/dev/null || true
      ;;
    Linux)
      local cred_file
      cred_file=$(_linux_credentials_file)
      mkdir -p "$(dirname "$cred_file")" 2>/dev/null || true
      printf '%s' "$blob" > "$cred_file" 2>/dev/null || return 0
      chmod 600 "$cred_file" 2>/dev/null || true
      ;;
    *)
      _debug "credential storage not implemented for OS '$(_os)'; no-op"
      ;;
  esac
}

_credential_read() {
  case "$(_os)" in
    Darwin)
      command -v security >/dev/null 2>&1 || return 1
      security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null
      ;;
    Linux)
      local cred_file content
      cred_file=$(_linux_credentials_file)
      [[ -f "$cred_file" ]] || return 1
      # Compact to a single line: our rc/org-cache files are one-entry-per-
      # line, but nothing guarantees Claude Code writes this file compact.
      # Safe to strip raw newlines/tabs unconditionally — valid JSON can't
      # contain either as a literal (unescaped) byte inside a string, so
      # this only ever removes formatting whitespace between tokens, never
      # touches actual field content.
      content=$(tr -d '\n\t' < "$cred_file" 2>/dev/null) || return 1
      [[ -n "$content" ]] || return 1
      _debug "read $cred_file (${#content} chars, has refreshTokenExpiresAt: $([[ "$content" == *refreshTokenExpiresAt* ]] && echo yes || echo no))"
      echo "$content"
      ;;
    *)
      return 1
      ;;
  esac
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
