# Simplified auth design

Date: 2026-08-15

## Revision (same day): save timing

Original version below had the SessionEnd hook as the only place accounts
get saved — meaning a fresh `/login` wasn't registered until the whole
session exited. In practice this was confirmed by testing (opened a
session, sent one message, checked the rc file — nothing there yet; only
appeared after exiting). That lag is a bad experience, so:

- `claude-accounts-hook` (UserPromptSubmit) now saves the currently
  authenticated account (email + Keychain blob) into the rc file on
  **every message**, before it does its existing job of forcing Keychain
  back to the resolved project/default account. So a mid-session `/login`
  is registered on your very next message.
- The forced resolution in step 2 is absolute by explicit decision: it
  always wins, even over an account you just logged into in the same
  session. There is no "stay on what I just logged into" mode — isolation
  correctness for concurrent sessions was prioritized over that
  convenience. If you want a session to use a different account, update
  its `.claude-accounts` file; that's the user's responsibility, not
  something the hook infers.
- `claude-accounts-session-end` (SessionEnd) is kept only as a backstop
  for logging in and exiting without ever sending a message (the hook
  above needs a message to run).
- The email extraction that both scripts need (`oauthAccount.emailAddress`
  from `~/.claude.json`) moved from a `python3` one-liner to a shared
  `_live_email()` helper in the lib using `grep`/`sed`, since it now runs
  on every message rather than once per session — avoids paying a `python3`
  startup cost on the hot path. `python3` remains a dependency only for
  `install.sh`/`uninstall.sh` (editing `settings.json`).

## Revision 2 (same day): surfacing which account is actually active

The CLI's own status display was confirmed (empirically, by comparing
per-account usage pages after a large test prompt) to authenticate
correctly against the Keychain-forced account, while still visually
*displaying* the account you last `/login`'d as. That's because the CLI
caches identity (email, org UUID, etc.) in `~/.claude.json`'s
`oauthAccount` block at `/login` time and doesn't re-derive it from the
live Keychain token — a field our hook never touches (and deliberately
won't: it's a large, actively-mutated state file the running `claude`
process itself reads/writes, so an external read-modify-write from a
hook risks a race/corruption for a cosmetic fix, with no guarantee the
running process would even notice the change).

Instead, `claude-accounts-hook` now reports the actual resolved account
via the `UserPromptSubmit` hook's `systemMessage` JSON field — a
supported Claude Code mechanism for a UI-level notice shown to the user
without being added to the conversation Claude sees (unlike plain
stdout/`additionalContext` on this hook event, which *is* added to the
model's context and would repeat its token cost on every turn). Built
with a small `_emit_system_message()` lib helper (manual JSON string
escaping, no `jq`/`python3` dependency on the hot path) rather than a
templating library, since the payload is one flat string field.

The hook now emits one of three messages per run: the active account
(`claude-accounts: using <email>`), a warning if the resolved account
has no saved credentials yet, or a warning if its refresh token has
expired — surfacing the same three states the wrapper already handles
at startup, but on every message of an already-running session too.

## Revision 3 (same day): organization name, and where usage numbers belong

Asked to also surface organization name and 5-hour/weekly usage
percentages. Split these, since their feasibility is very different:

- **Organization name**: cached in `~/.claude.json`'s
  `oauthAccount.organizationName`, same place as the email, extracted the
  same way (`_live_org()`, mirroring `_live_email()`). It isn't part of
  the Keychain credential blob, so it can't live inside
  `~/.claude-accountsrc`'s `email:credentialBlob` lines — added a second
  flat file, `~/.claude-accounts/org-cache` (`email:organizationName`),
  built on a new generic `_kv_lookup`/`_kv_upsert` pair that `_lookup_blob`
  /`_rc_upsert` were refactored to call too. Populated opportunistically
  by the same "live save" step that already captures the current email +
  blob (both the hook and SessionEnd), so an account's org name is known
  once it's been observed live at least once; the `systemMessage` falls
  back to plain `using <email>` (no parens) until then, rather than
  showing something wrong.

- **5-hour/weekly usage**: turned out not to need any new code at all.
  Claude Code already sends `rate_limits.five_hour.used_percentage` and
  `rate_limits.seven_day.used_percentage` natively to a status line
  script via the JSON it pipes to `statusLine.command` (confirmed from
  Claude Code's own docs) — computed by the running process from its own
  live API traffic, the same channel already confirmed (via the earlier
  usage-page test) to follow the Keychain-forced account rather than the
  stale `~/.claude.json` login cache. Duplicating that in
  `claude-accounts-hook` via a private/undocumented API call would have
  meant real hot-path latency and a maintenance liability for something
  the platform already provides for free. Decision: leave usage numbers
  to the status line, keep `claude-accounts-hook` focused on account
  resolution + identity reporting.

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
