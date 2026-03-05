# claude-accounts

> Run multiple Claude Code sessions with different Claude.ai accounts,
> auto-selected by project directory.

---

## Features

- **Per-project accounts** – link any directory to a named account; the
  `claude` wrapper picks it up automatically before each run.
- **Instant switching** – `claude-account use <name>` swaps credentials
  globally in one command.
- **Zero dependencies** – pure Bash, works wherever `claude` runs.
- **Safe storage** – credentials live in `~/.claude-accounts/`, never
  committed to your repository.

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
# requires git
git clone https://github.com/monteiroflavio/claude-accounts.git
cd claude-accounts
chmod +x install.sh bin/claude bin/claude-account
./install.sh
```

> **Note:** `install.sh` copies `bin/claude` and `bin/claude-account` into
> `~/.local/bin/`, renames any pre-existing `claude` binary to `claude.real`,
> and prints reload instructions.

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

---

## How it works

```
~/.claude-accounts/
  accounts/
    personal/
      credentials      ← copy of ~/.claude.json for this account
    work/
      credentials
  current              ← name of the currently active account
  links                ← directory → account mappings
```

When you run `claude` inside a linked directory (or any subdirectory),
the wrapper automatically swaps `~/.claude.json` with the linked
account's credentials before passing all arguments to the real `claude`
binary (`claude.real`).

---

## Uninstall

```bash
rm ~/.local/bin/claude ~/.local/bin/claude-account
# Restore original claude binary if backed up:
mv ~/.local/bin/claude.real ~/.local/bin/claude
```
