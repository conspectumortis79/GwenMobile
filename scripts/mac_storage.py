#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

SANDBOX = "com.apple.security.app-sandbox"
PREFERENCES = Path("Library") / "Preferences"
CONTAINERS = Path("Library") / "Containers"
APP_SUPPORT = Path("Library") / "Application Support"
ENTITLEMENTS_FILE = "MacOS/GwenMobile.entitlements"


class EntitlementReading(Protocol):
    def entitlements(self, bundle: Path) -> dict:
        ...


class BundleIdReading(Protocol):
    def bundle_id(self, bundle: Path) -> str:
        ...


@dataclass(frozen=True)
class SettingsStore:
    bundle_id: str
    sandboxed: bool
    home: Path

    @property
    def preferences(self) -> Path:
        if self.sandboxed:
            return self.root / PREFERENCES / f"{self.bundle_id}.plist"
        return self.home / PREFERENCES / f"{self.bundle_id}.plist"

    @property
    def root(self) -> Path:
        return self.home / CONTAINERS / self.bundle_id / "Data"

    @property
    def support(self) -> Path:
        if self.sandboxed:
            return self.root / APP_SUPPORT
        return self.home / APP_SUPPORT

    def kind(self) -> str:
        return "the app sandbox" if self.sandboxed else "the plain user library"

    def describe(self) -> str:
        return f"{self.preferences} — {self.kind()}"

    def differs(self, other: "SettingsStore") -> bool:
        return (self.bundle_id, self.sandboxed) != (other.bundle_id, other.sandboxed)


class SettingsStores:
    def __init__(self, entitlements: EntitlementReading, identities: BundleIdReading,
                 home: Path | None = None):
        self.entitlements = entitlements
        self.identities = identities
        self.home = Path(home or Path.home())

    def of(self, bundle: Path) -> SettingsStore | None:
        bundle = Path(bundle)
        if not bundle.is_dir():
            return None
        bundle_id = self.identities.bundle_id(bundle)
        if not bundle_id:
            return None
        sandboxed = bool(self.entitlements.entitlements(bundle).get(SANDBOX))
        return SettingsStore(bundle_id=bundle_id, sandboxed=sandboxed, home=self.home)


def shift_warning(before: SettingsStore | None, after: SettingsStore | None) -> str:
    if before is None or after is None or not before.differs(after):
        return ""
    return (f"the settings store changes with this install: the app that was installed before keeps its "
            f"settings in {before.kind()} at {before.preferences}, the build that replaces it keeps them "
            f"in {after.kind()} at {after.preferences}. Both carry the bundle id {after.bundle_id}, so "
            "macOS hands them two separate stores and the configuration reads as reset afterwards. "
            f"Sign every build of this app the same way (the project sets CODE_SIGN_ENTITLEMENTS for the "
            f"Catalyst SDK to {ENTITLEMENTS_FILE}) so Xcode runs and this script share one store")
