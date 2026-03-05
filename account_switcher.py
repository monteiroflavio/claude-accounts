"""
Account switcher — manages the currently active account and
injects its credentials into the environment or returns them
for direct use.
"""

import os
import json
from pathlib import Path
from typing import Optional

from credential_manager import CredentialStore


STATE_FILE = Path.home() / ".credential_manager" / "active_account"


class AccountSwitcher:
    """Select and activate one of the stored accounts."""

    def __init__(self, store: CredentialStore):
        self._store = store

    # ------------------------------------------------------------------
    # Active account persistence
    # ------------------------------------------------------------------

    @staticmethod
    def get_active() -> Optional[str]:
        """Return the name of the currently active account, or None."""
        if STATE_FILE.exists():
            return STATE_FILE.read_text().strip() or None
        return None

    @staticmethod
    def set_active(name: str) -> None:
        STATE_FILE.write_text(name)
        STATE_FILE.chmod(0o600)

    @staticmethod
    def clear_active() -> None:
        if STATE_FILE.exists():
            STATE_FILE.unlink()

    # ------------------------------------------------------------------
    # Switching
    # ------------------------------------------------------------------

    def switch(self, name: str) -> dict:
        """
        Switch to *name* and return its credentials.

        Also updates the persistent active-account state so that
        subsequent calls to :func:`get_active` reflect the change.
        """
        credentials = self._store.get(name)
        self.set_active(name)
        return credentials

    def current_credentials(self) -> Optional[dict]:
        """Return credentials for the currently active account, or None."""
        name = self.get_active()
        if name is None:
            return None
        try:
            return self._store.get(name)
        except KeyError:
            return None

    def inject_env(self, name: Optional[str] = None) -> None:
        """
        Inject credentials for *name* (or the active account) into
        the current process environment.

        Each credential key is upper-cased and prefixed with
        ``ACCOUNT_``.  For example ``api_key`` becomes
        ``ACCOUNT_API_KEY``.
        """
        target = name or self.get_active()
        if target is None:
            raise RuntimeError("No active account selected.")
        credentials = self._store.get(target)
        for key, value in credentials.items():
            env_key = f"ACCOUNT_{key.upper()}"
            os.environ[env_key] = str(value)
        self.set_active(target)
