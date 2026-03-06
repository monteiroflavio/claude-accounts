# claude-accounts

> Run multiple Claude Code sessions with different Claude.ai accounts,
> auto-selected by project directory.

```bash
curl -fsSL https://raw.githubusercontent.com/monteiroflavio/claude-accounts/main/install.sh | bash
```

---

## Features

- **Per-project accounts** – link any directory to a named account; the
  `claude` wrapper picks it up automatically before each run.
- **Instant switching** – `claude-account use <name>` swaps credentials
  globally in one command.
- **Concurrent session isolation** – per-message keychain swapping via a
  UserPromptSubmit hook ensures multiple Claude Code sessions with different
  accounts work simultaneously.
- **Auto-save on exit** – a SessionEnd hook automatically persists refreshed
  OAuth tokens back to the linked account's storage, so you never have to
  manually re-run `claude-account add` after `/login`.
- **Zero dependencies** – pure Bash, works wherever `claude` runs.
- **Safe storage** – credentials live in `~/.claude-accounts/`, never
  committed to your repository.

---

## Requirements

- Bash 4.0+
- macOS (for keychain-based credential isolation)
- `python3` (install script only — used to update `settings.json`)

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

Clone the repository and run the installer locally:

```bash
git clone https://github.com/monteiroflavio/claude-accounts.git
cd claude-accounts
chmod +x install.sh bin/claude bin/claude-account bin/claude-accounts-hook bin/claude-accounts-session-end
./install.sh
```

> **Note:** `install.sh` copies the wrapper scripts into
> `~/.claude-accounts/bin/`, records the real claude binary path in
> `~/.claude-accounts/real-path`, and configures UserPromptSubmit and
> SessionEnd hooks in `~/.claude/settings.json` for session isolation
> and auto-save.

---

## Quick start

```bash
# 1. Log in to your first account (opens browser)
claude

# 2. Save those credentials under a name
claude-account add personal

# 3. Log in to a second account
claude

# 4. Save it too
claude-account add work

# 5. Link a project directory to an account
cd ~/projects/work-project
claude-account link work

# 6. From now on, running `claude` here auto-uses the work account
claude
```

---

## Commands

| Command | Description |
|---|---|
| `claude-account add <name>` | Save current `~/.claude.json` as `<name>` |
| `claude-account list` | List all saved accounts |
| `claude-account use <name>` | Switch to `<name>` globally |
| `claude-account link [name]` | Link current directory to `<name>` (default: active) |
| `claude-account unlink` | Remove the link for the current directory |
| `claude-account remove <name>` | Delete account `<name>` |
| `claude-account status` | Show active account and directory link |
| `claude-account doctor [--fix]` | Check installation and auto-repair common issues |
| `claude-account help` | Show usage information |

---

## How it works

```
~/.claude-accounts/
  bin/
    claude               ← wrapper script
    claude-account       ← management CLI
    claude-accounts-hook        ← session isolation hook
    claude-accounts-session-end ← auto-save on exit hook
  accounts/
    personal/
      credentials        ← copy of ~/.claude.json
      keychain           ← saved OAuth token (macOS)
    work/
      credentials
      keychain
  current                ← name of the currently active account
  current-dir            ← directory where last account was activated
  links                  ← directory → account mappings
  real-path              ← path to the real claude binary
```

When you run `claude` inside a linked directory (or any subdirectory),
the wrapper automatically swaps `~/.claude.json` and the macOS Keychain
credential with the linked account's saved copies, then passes all
arguments to the real `claude` binary.

For concurrent sessions, the `claude-accounts-hook` runs before every
message (via the UserPromptSubmit hook) and re-injects the correct
account's keychain token. This ensures two sessions using different
accounts don't stomp on each other's credentials.

---

## Environment variables

| Variable | Description |
|---|---|
| `CLAUDE_ACCOUNTS_DEBUG=1` | Trace wrapper decisions to stderr |
| `CLAUDE_REAL=/path/to/claude` | Override real claude binary path |
| `CLAUDE_ACCOUNTS_DIR=...` | Custom storage directory (default: `~/.claude-accounts`) |

---

## Troubleshooting

Run the built-in diagnostic:

```bash
claude-account doctor
```

To auto-repair common issues (missing hook, stale real-path, etc.):

```bash
claude-account doctor --fix
```

---

## Uninstall

```bash
rm -rf ~/.claude-accounts/bin
# Remove PATH entry from ~/.zshrc or ~/.bashrc
# Remove hook from ~/.claude/settings.json
# Optionally remove all data: rm -rf ~/.claude-accounts
```
