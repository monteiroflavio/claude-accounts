#!/usr/bin/env python3
"""
Command-line interface for the multi-account credential manager.

Usage examples
--------------
  # Add an account interactively
  python cli.py add my-account

  # Add with inline JSON credentials (useful in scripts)
  python cli.py add my-account --creds '{"api_key": "sk-...", "region": "us-east-1"}'

  # List all stored accounts
  python cli.py list

  # Show credentials for an account (secrets are masked by default)
  python cli.py show my-account

  # Switch the active account
  python cli.py use my-account

  # Show which account is currently active
  python cli.py current

  # Update a specific field
  python cli.py update my-account --field api_key --value sk-new-key

  # Delete an account
  python cli.py delete my-account

  # Rename an account
  python cli.py rename my-account new-name

  # Export account names (no secrets)
  python cli.py export accounts.json
"""

import argparse
import getpass
import json
import sys

from credential_manager import CredentialStore
from account_switcher import AccountSwitcher


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="credential-manager",
        description="Multi-account credential management system",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # add
    p_add = sub.add_parser("add", help="Add a new account")
    p_add.add_argument("name", help="Account name")
    p_add.add_argument("--creds", help="JSON string with credentials", default=None)
    p_add.add_argument("--overwrite", action="store_true", help="Overwrite if exists")

    # list
    sub.add_parser("list", help="List all account names")

    # show
    p_show = sub.add_parser("show", help="Show an account's credentials")
    p_show.add_argument("name", help="Account name")
    p_show.add_argument("--reveal", action="store_true", help="Show actual secret values")

    # update
    p_update = sub.add_parser("update", help="Update a credential field")
    p_update.add_argument("name", help="Account name")
    p_update.add_argument("--field", required=True, help="Field name to update")
    p_update.add_argument("--value", default=None, help="New value (prompted if omitted)")

    # delete
    p_delete = sub.add_parser("delete", help="Delete an account")
    p_delete.add_argument("name", help="Account name")

    # rename
    p_rename = sub.add_parser("rename", help="Rename an account")
    p_rename.add_argument("old_name", help="Current account name")
    p_rename.add_argument("new_name", help="New account name")

    # use / switch
    p_use = sub.add_parser("use", help="Switch the active account")
    p_use.add_argument("name", help="Account name to activate")

    # current
    sub.add_parser("current", help="Show the currently active account")

    # export
    p_export = sub.add_parser("export", help="Export account list to JSON")
    p_export.add_argument("path", help="Output file path")
    p_export.add_argument("--include-secrets", action="store_true")

    return parser


def _prompt_credentials() -> dict:
    """Interactively collect key/value credential pairs."""
    print("Enter credentials (blank key to finish):")
    creds: dict = {}
    while True:
        key = input("  Key: ").strip()
        if not key:
            break
        value = getpass.getpass(f"  Value for '{key}': ")
        creds[key] = value
    return creds


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()

    # Commands that don't need the store
    if args.command == "current":
        name = AccountSwitcher.get_active()
        if name:
            print(f"Active account: {name}")
        else:
            print("No active account set.")
        return

    # All other commands need the encrypted store
    try:
        store = CredentialStore()
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)

    switcher = AccountSwitcher(store)

    if args.command == "add":
        if args.creds:
            try:
                creds = json.loads(args.creds)
            except json.JSONDecodeError as exc:
                print(f"Invalid JSON: {exc}", file=sys.stderr)
                sys.exit(1)
        else:
            creds = _prompt_credentials()
        try:
            store.add(args.name, creds, overwrite=args.overwrite)
            print(f"Account '{args.name}' added.")
        except ValueError as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)

    elif args.command == "list":
        accounts = store.list_accounts()
        if not accounts:
            print("No accounts stored.")
        else:
            active = AccountSwitcher.get_active()
            for name in accounts:
                marker = " (active)" if name == active else ""
                print(f"  {name}{marker}")

    elif args.command == "show":
        try:
            creds = store.get(args.name)
        except KeyError as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)
        print(f"Account: {args.name}")
        for k, v in creds.items():
            display = v if args.reveal else "***"
            print(f"  {k}: {display}")

    elif args.command == "update":
        value = args.value if args.value is not None else getpass.getpass(f"New value for '{args.field}': ")
        try:
            store.update(args.name, {args.field: value})
            print(f"Account '{args.name}' updated.")
        except KeyError as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)

    elif args.command == "delete":
        confirm = input(f"Delete account '{args.name}'? [y/N] ").strip().lower()
        if confirm != "y":
            print("Aborted.")
            return
        try:
            store.delete(args.name)
            if AccountSwitcher.get_active() == args.name:
                AccountSwitcher.clear_active()
            print(f"Account '{args.name}' deleted.")
        except KeyError as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)

    elif args.command == "rename":
        try:
            store.rename(args.old_name, args.new_name)
            if AccountSwitcher.get_active() == args.old_name:
                AccountSwitcher.set_active(args.new_name)
            print(f"Renamed '{args.old_name}' → '{args.new_name}'.")
        except (KeyError, ValueError) as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)

    elif args.command == "use":
        try:
            switcher.switch(args.name)
            print(f"Switched to account '{args.name}'.")
        except KeyError as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)

    elif args.command == "export":
        store.export(args.path, include_secrets=args.include_secrets)
        print(f"Exported to '{args.path}'.")


if __name__ == "__main__":
    main()
