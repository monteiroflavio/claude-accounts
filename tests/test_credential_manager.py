"""Tests for CredentialStore."""

import json
import pytest
from unittest.mock import patch, MagicMock
from pathlib import Path

# Patch file-system paths before importing the module under test
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))


@pytest.fixture()
def tmp_store_dir(tmp_path, monkeypatch):
    """Redirect STORE_DIR / STORE_FILE / SALT_FILE to a temp directory."""
    import credential_manager as cm
    monkeypatch.setattr(cm, "STORE_DIR", tmp_path)
    monkeypatch.setattr(cm, "STORE_FILE", tmp_path / "accounts.enc")
    monkeypatch.setattr(cm, "SALT_FILE", tmp_path / "salt")
    return tmp_path


@pytest.fixture()
def store(tmp_store_dir):
    from credential_manager import CredentialStore
    return CredentialStore(password="test-password")


class TestCredentialStore:
    def test_add_and_get(self, store):
        store.add("acct1", {"api_key": "key-1", "region": "us"})
        creds = store.get("acct1")
        assert creds["api_key"] == "key-1"
        assert creds["region"] == "us"

    def test_add_duplicate_raises(self, store):
        store.add("acct1", {"api_key": "key-1"})
        with pytest.raises(ValueError, match="already exists"):
            store.add("acct1", {"api_key": "key-2"})

    def test_add_overwrite(self, store):
        store.add("acct1", {"api_key": "key-1"})
        store.add("acct1", {"api_key": "key-2"}, overwrite=True)
        assert store.get("acct1")["api_key"] == "key-2"

    def test_update(self, store):
        store.add("acct1", {"api_key": "old"})
        store.update("acct1", {"api_key": "new"})
        assert store.get("acct1")["api_key"] == "new"

    def test_update_missing_raises(self, store):
        with pytest.raises(KeyError):
            store.update("nonexistent", {"api_key": "x"})

    def test_delete(self, store):
        store.add("acct1", {"api_key": "key"})
        store.delete("acct1")
        assert "acct1" not in store.list_accounts()

    def test_delete_missing_raises(self, store):
        with pytest.raises(KeyError):
            store.delete("nonexistent")

    def test_list_accounts(self, store):
        store.add("a", {"x": "1"})
        store.add("b", {"x": "2"})
        assert sorted(store.list_accounts()) == ["a", "b"]

    def test_rename(self, store):
        store.add("old", {"api_key": "k"})
        store.rename("old", "new")
        assert "new" in store.list_accounts()
        assert "old" not in store.list_accounts()
        assert store.get("new")["api_key"] == "k"

    def test_rename_missing_raises(self, store):
        with pytest.raises(KeyError):
            store.rename("nonexistent", "something")

    def test_rename_to_existing_raises(self, store):
        store.add("a", {})
        store.add("b", {})
        with pytest.raises(ValueError):
            store.rename("a", "b")

    def test_persistence(self, tmp_store_dir):
        """Data should survive a new CredentialStore instance."""
        from credential_manager import CredentialStore
        import credential_manager as cm

        s1 = CredentialStore(password="pw")
        s1.add("acct", {"token": "abc"})

        s2 = CredentialStore(password="pw")
        assert s2.get("acct")["token"] == "abc"

    def test_wrong_password_raises(self, tmp_store_dir):
        from credential_manager import CredentialStore

        s1 = CredentialStore(password="correct")
        s1.add("acct", {"token": "abc"})

        with pytest.raises(ValueError, match="wrong password"):
            CredentialStore(password="wrong")

    def test_export_redacted(self, store, tmp_path):
        store.add("acct1", {"api_key": "secret"})
        out = tmp_path / "export.json"
        store.export(str(out))
        data = json.loads(out.read_text())
        assert data["acct1"]["api_key"] == "***"

    def test_export_with_secrets(self, store, tmp_path):
        store.add("acct1", {"api_key": "secret"})
        out = tmp_path / "export.json"
        store.export(str(out), include_secrets=True)
        data = json.loads(out.read_text())
        assert data["acct1"]["api_key"] == "secret"
