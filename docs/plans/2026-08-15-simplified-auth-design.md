# Simplified auth design

Date: 2026-08-15

## Summary

Replace the current `~/.claude-accounts/accounts/<name>/{credentials,keychain}` +
`links` file architecture with two flat, human-editable files and no CLI:

- `~/.claude-accountsrc` — one saved account per line, `email:credentialBlob`.
  First line is the default account.
- `.claude-accounts` — one line in a project directory, the email of the
  account that project should use. Optional; falls back to the rc file's
  default when absent.

Account identity is the Claude account's own email address (read from
`~/.claude.json`'s `oauthAccount.emailAddress`), never a name the user picks.
There is no `claude-account` CLI. The rc file is written to automatically by
a SessionEnd hook; the project file is edited by hand (`echo email > .claude-accounts`).

## Why

The current design stores each account as a directory
(`credentials` + `keychain` files), tracks project links in a separate
`links` registry, and needs a whole `claude-account` CLI (`add`, `use`,
`link`, `unlink`, `remove`, `status`, `doctor`) to manage it. All of that
collapses into two flat files once identity is derived automatically from
the logged-in account's email instead of a user-chosen name.

## Components (unchanged in role, simplified in implementation)

- **`bin/claude`** (wrapper) — on every invocation: resolve target email,
  look up its blob in the rc file, check expiry, inject into Keychain, exec
  the real `claude` binary. The real-binary discovery logic (`_real_claude`)
  is unchanged.
- **`bin/claude-accounts-hook`** (UserPromptSubmit) — before each message,
  re-injects the correct project's blob into Keychain, so two concurrent
  `claude` sessions using different accounts don't clobber each other's
  Keychain entry between messages. Unchanged in purpose, now reads the flat
  files instead of `links`/`accounts/`.
- **`bin/claude-accounts-session-end`** (SessionEnd) — on exit, reads the
  *currently authenticated* email from `~/.claude.json` and the current
  Keychain blob, and upserts that line in `~/.claude-accountsrc`. This is
  the only place accounts get added or refreshed — logging in as a new
  account (`/login` inside any session) and exiting is enough to register
  it; no command needed.
- **`claude-account` CLI, `accounts/` directory, `links`/`current`/
  `current-dir` files — all removed.**

## File formats

`~/.claude-accountsrc`:
```
fm070795@gmail.com:{"claudeAiOauth":{"accessToken":"...","refreshToken":"...","expiresAt":...,"refreshTokenExpiresAt":...,...}}
work@company.com:{"claudeAiOauth":{...}}
```
One line per account. Split on the *first* `:` only (emails can't contain
`:`; the JSON blob — Keychain's stored value verbatim — can and does).
First line = default account when a project has no `.claude-accounts`.

`.claude-accounts` (in a project directory, gitignored):
```
work@company.com
```
Single line, the email to use. `bin/claude` and the hook walk up from the
working/project directory the same way the old `links` lookup did, stopping
at the first `.claude-accounts` found.

## Data flow

1. `claude` (or the hook) determines the target email: walk up for
   `.claude-accounts`; else first line of `~/.claude-accountsrc`.
2. Look up that email's blob in the rc file.
   - Not found at all (never logged in as that account, or rc file doesn't
     exist yet) → skip injection, exec real `claude` untouched so the user
     can log in normally; SessionEnd will register it afterward.
   - Found → parse `refreshTokenExpiresAt` (fallback: skip the check if
     absent — old-format blobs without it are treated as not expired).
     If it's in the past → print `Account <email> has expired — run
     'claude' and /login again.` to stderr and exit 1 (wrapper only; the
     hook just skips injection silently, since it can't block a running
     session).
     Otherwise → write the blob into Keychain (`security
     add-generic-password -U`), then exec/continue.
3. On SessionEnd, read `oauthAccount.emailAddress` from `~/.claude.json`
   and the live Keychain blob; upsert that line into the rc file (replace
   if the email already has a line, else append).

Note on expiry semantics: only `refreshTokenExpiresAt` is treated as a hard
stop. A merely-stale `accessToken` with a still-valid refresh token is left
alone — the real `claude` binary refreshes it silently using the refresh
token we already injected, and the next SessionEnd run captures the
refreshed blob automatically.

## Error handling

- Missing rc file → treated as "no accounts saved yet"; wrapper is a
  pass-through.
- `.claude-accounts` names an email with no rc entry → warn to stderr,
  pass through untouched (don't block; let the user log in).
- Malformed rc line (no `:`) → skip that line, don't crash.
- Non-macOS (no `security` binary) → injection steps become no-ops with a
  one-time debug note; today's project is macOS-only for this reason and
  that doesn't change.

## install.sh changes

- Installs `bin/claude`, `bin/claude-accounts-hook`,
  `bin/claude-accounts-session-end` only (no `claude-account`).
- Keeps the UserPromptSubmit + SessionEnd hook registration in
  `~/.claude/settings.json`, unchanged in mechanism.
- Actively deletes any leftover old-format state from a prior install:
  `~/.claude-accounts/accounts/`, `~/.claude-accounts/links`,
  `~/.claude-accounts/current`, `~/.claude-accounts/current-dir`, and the
  old `~/.claude-accounts/bin/claude-account` binary if present. Keeps
  `~/.claude-accounts/real-path` and `~/.claude-accounts/bin/` (now holding
  only the three scripts above).

## Testing

No existing automated test suite (pure Bash, no framework). Verify by hand:

1. Fresh machine, no rc file: `claude` passes through untouched, `/login`,
   exit → `~/.claude-accountsrc` created with one line for that email.
2. Second account: `/login` as a different account inside a session, exit
   → second line appended, first line untouched (still default).
3. `.claude-accounts` in a project pointing at the second account →
   `claude` there injects the second account's blob into Keychain; `claude`
   outside any linked project uses the default (first line).
4. Concurrent sessions: two terminals, two projects linked to different
   accounts, interleave messages → each session's Keychain injections don't
   cross-contaminate (hook re-injects before every message).
5. Hand-edit `refreshTokenExpiresAt` in an rc line to a past timestamp →
   `claude` in that project prints the expiry message and exits 1 without
   launching the real binary.
