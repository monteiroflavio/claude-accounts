"""
Multi-account credential management system.

Provides secure storage, retrieval, and management of credentials
for multiple accounts using AES-256 encryption.
"""

import os
import json
import base64
import hashlib
import secrets
import getpass
from pathlib import Path
from typing import Optional
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes


STORE_DIR = Path.home() / ".credential_manager"
STORE_FILE = STORE_DIR / "accounts.enc"
SALT_FILE = STORE_DIR / "salt"


def _derive_key(password: str, salt: bytes) -> bytes:
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=480_000,
    )
    return kdf.derive(password.encode())


def _load_salt() -> bytes:
    if SALT_FILE.exists():
        return SALT_FILE.read_bytes()
    salt = secrets.token_bytes(32)
    STORE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    SALT_FILE.write_bytes(salt)
    SALT_FILE.chmod(0o600)
    return salt


def _encrypt(data: bytes, key: bytes) -> bytes:
    aesgcm = AESGCM(key)
    nonce = secrets.token_bytes(12)
    ciphertext = aesgcm.encrypt(nonce, data, None)
    return nonce + ciphertext


def _decrypt(data: bytes, key: bytes) -> bytes:
    aesgcm = AESGCM(key)
    nonce, ciphertext = data[:12], data[12:]
    return aesgcm.decrypt(nonce, ciphertext, None)


class CredentialStore:
    """Encrypted credential store for multiple accounts."""

    def __init__(self, password: Optional[str] = None):
        STORE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
        salt = _load_salt()
        if password is None:
            password = getpass.getpass("Master password: ")
        self._key = _derive_key(password, salt)
        self._accounts: dict = self._load()

    def _load(self) -> dict:
        if not STORE_FILE.exists():
            return {}
        try:
            raw = STORE_FILE.read_bytes()
            plaintext = _decrypt(raw, self._key)
            return json.loads(plaintext.decode())
        except Exception:
            raise ValueError("Failed to decrypt store — wrong password?")

    def _save(self) -> None:
        plaintext = json.dumps(self._accounts, indent=2).encode()
        ciphertext = _encrypt(plaintext, self._key)
        STORE_FILE.write_bytes(ciphertext)
        STORE_FILE.chmod(0o600)

    # ------------------------------------------------------------------
    # CRUD
    # ------------------------------------------------------------------

    def add(self, name: str, credentials: dict, overwrite: bool = False) -> None:
        """Add a new account. Raises ValueError if it already exists."""
        if name in self._accounts and not overwrite:
            raise ValueError(f"Account '{name}' already exists. Use update() or pass overwrite=True.")
        self._accounts[name] = credentials
        self._save()

    def get(self, name: str) -> dict:
        """Return credentials for an account."""
        if name not in self._accounts:
            raise KeyError(f"Account '{name}' not found.")
        return dict(self._accounts[name])

    def update(self, name: str, credentials: dict) -> None:
        """Update credentials for an existing account."""
        if name not in self._accounts:
            raise KeyError(f"Account '{name}' not found.")
        self._accounts[name].update(credentials)
        self._save()

    def delete(self, name: str) -> None:
        """Remove an account from the store."""
        if name not in self._accounts:
            raise KeyError(f"Account '{name}' not found.")
        del self._accounts[name]
        self._save()

    def list_accounts(self) -> list[str]:
        """Return all account names."""
        return list(self._accounts.keys())

    def rename(self, old_name: str, new_name: str) -> None:
        """Rename an account."""
        if old_name not in self._accounts:
            raise KeyError(f"Account '{old_name}' not found.")
        if new_name in self._accounts:
            raise ValueError(f"Account '{new_name}' already exists.")
        self._accounts[new_name] = self._accounts.pop(old_name)
        self._save()

    def export(self, path: str, include_secrets: bool = False) -> None:
        """Export account list to a JSON file (secrets redacted by default)."""
        data = {}
        for name, creds in self._accounts.items():
            if include_secrets:
                data[name] = creds
            else:
                data[name] = {k: "***" for k in creds}
        Path(path).write_text(json.dumps(data, indent=2))
