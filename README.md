# claude-accounts

> Run multiple Claude Code sessions with different Claude.ai accounts,
> auto-selected by project directory.

```bash
curl -fsSL https://raw.githubusercontent.com/monteiroflavio/claude-accounts/main/install.sh | bash
```

---

## Features

- **Per-project accounts** – drop a `.claude-accounts` file (one line, an
  email address) in a project; the `claude` wrapper picks it up
  automatically before each run.
- **Zero commands** – there's no CLI to learn. Accounts register themselves:
  log in with `/login`, and the account you were using is saved to
  `~/.claude-accountsrc` on your very next message — no need to end the
  session.
- **Concurrent session isolation** – every message forces the credential
  store back to the account this project resolves to (its `.claude-accounts`
  file, or the default), so multiple Claude Code sessions with different
  accounts run at the same time without clobbering each other — even if you
  `/login` to a different account mid-session, this project's messages keep
  using its assigned account.
- **Clear expiry** – if an account's refresh token has expired, `claude`
  tells you to log back in instead of failing silently.
- **Safe storage** – credentials live in `~/.claude-accountsrc`, never
  committed to your repository (add `.claude-accounts` to your project's
  `.gitignore` too — it names an account, not a secret, but it's still
  local to your machine).

---

## Requirements

- Bash 4.0+
- macOS or Linux — credential storage is OS-specific: the system Keychain
  on macOS, or `~/.claude/.credentials.json` (`$CLAUDE_CONFIG_DIR` if set)
  on Linux. The Linux path is based on public reports, not independently
  verified against every Claude Code version — if it doesn't work for you,
  run with `CLAUDE_ACCOUNTS_DEBUG=1` and open an issue with the trace.
- `python3` (install.sh and uninstall.sh only — used to edit
  `settings.json`; the wrapper and hooks that run on every message/session
  don't need it)

---

## Installation

### Option A — one-liner (recommended)

```bash
curl -fsSL \
  https://raw.githubusercontent.com/monteiroflavio/claude-accounts/main/install.sh \
  | bash
```

Then reload your shell:

```bash
source ~/.bashrc   # bash
source ~/.zshrc    # zsh
```

### Option B — manual clone

```bash
git clone https://github.com/monteiroflavio/claude-accounts.git
cd claude-accounts
chmod +x install.sh bin/claude bin/claude-accounts-hook bin/claude-accounts-session-end
./install.sh
```

> **Note:** `install.sh` copies the wrapper scripts into
> `~/.claude-accounts/bin/`, records the real claude binary path in
> `~/.claude-accounts/real-path`, and configures UserPromptSubmit and
> SessionEnd hooks in `~/.claude/settings.json`.

---

## Quick start

```bash
# 1. Log in to your first account (opens browser)
claude
# ... /login, then send any message ...
# → saved automatically as the default account in ~/.claude-accountsrc

# 2. Log in to a second account (inside any claude session)
claude
# /login as a different account, then send any message
# → appended as a second line in ~/.claude-accountsrc

# 3. Link a project directory to an account
cd ~/projects/work-project
echo "work@example.com" > .claude-accounts

# 4. From now on, running `claude` here auto-uses that account
claude
```

That's it — there's no `claude-account add/use/link` command. Accounts are
identified by their own email address and register themselves the moment
you log in and send a message (or exit, if you don't send one).

---

## How it works

```
~/.claude-accounts/
  bin/
    claude                      ← wrapper script
    claude-accounts-lib.sh      ← shared helpers
    claude-accounts-hook        ← session isolation hook
    claude-accounts-session-end ← auto-save on exit hook
  real-path                     ← path to the real claude binary

~/.claude-accountsrc            ← one "email:credentialBlob" per line
                                   (first line = default account)
~/.claude-accounts/org-cache    ← one "email:organizationName" per line
                                   (cached opportunistically, not required)

<project>/.claude-accounts      ← one line: the email to use here
```

When you run `claude`, the wrapper walks up from your current directory
looking for a `.claude-accounts` file. If it finds one, it uses that email;
otherwise it falls back to the default (first line of
`~/.claude-accountsrc`). It looks up that email's saved credential blob and
writes it into the OS credential store — the Keychain on macOS,
`~/.claude/.credentials.json` on Linux — before handing off to the real
`claude` binary.

`claude-accounts-hook` runs before every message (via the UserPromptSubmit
hook) and does three things, in order:

1. Saves whichever account you're currently logged in as (from
   `~/.claude.json`) and the current credential-store token into
   `~/.claude-accountsrc` — this is how accounts get added or refreshed,
   immediately, without any separate "save" step. Its organization name
   (also from `~/.claude.json`) is cached alongside it in
   `~/.claude-accounts/org-cache`, keyed by email — a separate file, since
   it isn't part of the credential blob and doesn't belong in the rc
   file's `email:credentialBlob` format.
2. Forces the credential store back to this project's resolved account
   (its `.claude-accounts` file, or the default). This always wins — even over a
   `/login` you just did in this same session. A session's messages only
   ever use its assigned account; point `.claude-accounts` at a different
   account yourself if you want it used here. This is what keeps
   concurrent sessions using different accounts from stomping on each
   other.
3. Reports which account (and organization, if cached) is actually active
   via a `systemMessage` — e.g. `claude-accounts: using bob@example.com
   (Acme Inc)` — a UI-level notice, shown to you but not fed into the
   conversation Claude sees, so it doesn't cost tokens or repeat in the
   transcript every turn. Useful because the CLI's own status display can
   lag: it caches the account identity in `~/.claude.json` at `/login`
   time and doesn't re-derive it from the live credential-store token, so
   it can visibly disagree with which account a message actually used — the
   `systemMessage` is the ground truth. You'll also see a warning here if
   the resolved account has no saved credentials yet, or if its refresh
   token has expired. The organization name is only shown once it's been
   observed live at least once (via this hook or SessionEnd) for that
   account — it's not guessable from the credential blob alone.

   Token-consumption numbers (5-hour and weekly usage) aren't part of this
   `systemMessage` — Claude Code already exposes them natively to a
   status line script via `rate_limits.five_hour.used_percentage` and
   `rate_limits.seven_day.used_percentage` in the JSON it pipes to
   `statusLine.command` (see Claude Code's own status line docs), so
   there's no need to fetch or duplicate them here.

`claude-accounts-session-end` runs when a session exits (SessionEnd hook)
and does the same save as step 1 above — it's just a backstop for
logging in and exiting without ever sending a message, since the hook
above only runs on messages.

If an account's refresh token has expired, `claude` prints a message and
exits instead of launching with a dead credential:

```
claude-accounts: account 'work@example.com' has expired.
  Run 'claude' and /login again to refresh it.
```

A merely stale *access* token (refresh token still valid) isn't treated as
expired — the real `claude` binary refreshes it silently, and your next
message picks up the refreshed token automatically.

---

## Environment variables

| Variable | Description |
|---|---|
| `CLAUDE_ACCOUNTS_DEBUG=1` | Trace wrapper/hook decisions to stderr |
| `CLAUDE_REAL=/path/to/claude` | Override real claude binary path |
| `CLAUDE_ACCOUNTS_DIR=...` | Custom install/lock directory (default: `~/.claude-accounts`) |
| `CLAUDE_ACCOUNTS_RC=...` | Custom rc file path (default: `~/.claude-accountsrc`) |

---

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/monteiroflavio/claude-accounts/main/uninstall.sh | bash
```

Or, from a local clone: `./uninstall.sh`.

It removes `~/.claude-accounts` and `~/.claude-accountsrc`, strips the PATH
entry from your shell rc file, and removes just the `claude-accounts-hook`
and `claude-accounts-session-end` entries from
`~/.claude/settings.json` — any other hooks or settings you have are left
untouched. Safe to run more than once.
