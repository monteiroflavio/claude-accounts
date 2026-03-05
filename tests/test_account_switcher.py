"""Tests for AccountSwitcher."""

import pytest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent))


@pytest.fixture()
def tmp_store_dir(tmp_path, monkeypatch):
    import credential_manager as cm
    import account_switcher as sw
    monkeypatch.setattr(cm, "STORE_DIR", tmp_path)
    monkeypatch.setattr(cm, "STORE_FILE", tmp_path / "accounts.enc")
    monkeypatch.setattr(cm, "SALT_FILE", tmp_path / "salt")
    monkeypatch.setattr(sw, "STATE_FILE", tmp_path / "active_account")
    return tmp_path


@pytest.fixture()
def store(tmp_store_dir):
    from credential_manager import CredentialStore
    s = CredentialStore(password="pw")
    s.add("acct1", {"api_key": "key-1"})
    s.add("acct2", {"api_key": "key-2"})
    return s


@pytest.fixture()
def switcher(store):
    from account_switcher import AccountSwitcher
    return AccountSwitcher(store)


class TestAccountSwitcher:
    def test_switch_returns_credentials(self, switcher):
        creds = switcher.switch("acct1")
        assert creds["api_key"] == "key-1"

    def test_switch_sets_active(self, switcher):
        from account_switcher import AccountSwitcher
        switcher.switch("acct1")
        assert AccountSwitcher.get_active() == "acct1"

    def test_switch_changes_active(self, switcher):
        from account_switcher import AccountSwitcher
        switcher.switch("acct1")
        switcher.switch("acct2")
        assert AccountSwitcher.get_active() == "acct2"

    def test_current_credentials(self, switcher):
        switcher.switch("acct2")
        creds = switcher.current_credentials()
        assert creds["api_key"] == "key-2"

    def test_current_credentials_none_when_no_active(self, switcher):
        from account_switcher import AccountSwitcher
        AccountSwitcher.clear_active()
        assert switcher.current_credentials() is None

    def test_switch_missing_account_raises(self, switcher):
        with pytest.raises(KeyError):
            switcher.switch("nonexistent")

    def test_inject_env(self, switcher, monkeypatch):
        import os
        switcher.switch("acct1")
        switcher.inject_env()
        assert os.environ.get("ACCOUNT_API_KEY") == "key-1"

    def test_inject_env_no_active_raises(self, switcher, monkeypatch):
        from account_switcher import AccountSwitcher
        AccountSwitcher.clear_active()
        with pytest.raises(RuntimeError, match="No active account"):
            switcher.inject_env()

    def test_inject_env_specific_account(self, switcher, monkeypatch):
        import os
        switcher.inject_env("acct2")
        assert os.environ.get("ACCOUNT_API_KEY") == "key-2"

    def test_clear_active(self, switcher):
        from account_switcher import AccountSwitcher
        switcher.switch("acct1")
        AccountSwitcher.clear_active()
        assert AccountSwitcher.get_active() is None
