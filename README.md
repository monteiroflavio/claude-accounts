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
  log in with `/login`, and the account you were using is saved
  automatically when the session ends.
- **Concurrent session isolation** – per-message Keychain swapping via a
  UserPromptSubmit hook lets multiple Claude Code sessions with different
  accounts run at the same time without clobbering each other.
- **Clear expiry** – if an account's refresh token has expired, `claude`
  tells you to log back in instead of failing silently.
- **Safe storage** – credentials live in `~/.claude-accountsrc`, never
  committed to your repository (add `.claude-accounts` to your project's
  `.gitignore` too — it names an account, not a secret, but it's still
  local to your machine).

---

## Requirements

- Bash 4.0+
- macOS (for Keychain-based credential storage)
- `python3` (install script, and the SessionEnd hook — used to read/write
  JSON)

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
# ... /login, then exit the session ...
# → saved automatically as the default account in ~/.claude-accountsrc

# 2. Log in to a second account (inside any claude session)
claude
# /login as a different account, then exit
# → appended as a second line in ~/.claude-accountsrc

# 3. Link a project directory to an account
cd ~/projects/work-project
echo "work@example.com" > .claude-accounts

# 4. From now on, running `claude` here auto-uses that account
claude
```

That's it — there's no `claude-account add/use/link` command. Accounts are
identified by their own email address and register themselves the first
time you log in and exit.

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

<project>/.claude-accounts      ← one line: the email to use here
```

When you run `claude`, the wrapper walks up from your current directory
looking for a `.claude-accounts` file. If it finds one, it uses that email;
otherwise it falls back to the default (first line of
`~/.claude-accountsrc`). It looks up that email's saved credential blob and
writes it into the macOS Keychain before handing off to the real `claude`
binary.

For concurrent sessions, `claude-accounts-hook` runs before every message
(via the UserPromptSubmit hook) and re-injects the correct project's
Keychain entry, so two sessions using different accounts don't stomp on
each other.

`claude-accounts-session-end` runs when a session exits (SessionEnd hook):
it reads whichever account you're currently logged in as (from
`~/.claude.json`) and the current Keychain token, and saves/updates that
account's line in `~/.claude-accountsrc`. This is the only way accounts get
added or refreshed — there's no separate "save" step.

If an account's refresh token has expired, `claude` prints a message and
exits instead of launching with a dead credential:

```
claude-accounts: account 'work@example.com' has expired.
  Run 'claude' and /login again to refresh it.
```

A merely stale *access* token (refresh token still valid) isn't treated as
expired — the real `claude` binary refreshes it silently, and the next
SessionEnd run picks up the refreshed token automatically.

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
rm -rf ~/.claude-accounts ~/.claude-accountsrc
# Remove PATH entry from ~/.zshrc or ~/.bashrc
# Remove the hooks from ~/.claude/settings.json
```
