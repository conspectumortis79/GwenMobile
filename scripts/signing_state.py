#!/usr/bin/env python3
from __future__ import annotations

import datetime
from dataclasses import dataclass
from pathlib import Path

IOS = "ios"
MAC = "mac"
CATALYST_PREFIX = "maccatalyst."
WILDCARD = "*"
SECONDS_PER_DAY = 86400.0
KIND_BY_SUFFIX = {".mobileprovision": IOS, ".provisionprofile": MAC}
KIND_BY_NAME = (("iOS Team Provisioning Profile", IOS),
                ("Mac Catalyst Team Provisioning Profile", MAC),
                ("macOS Team Provisioning Profile", MAC))


def now() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


def as_moment(value) -> datetime.datetime:
    if not isinstance(value, datetime.datetime):
        return now()
    return value if value.tzinfo else value.astimezone()


def as_utc(value) -> datetime.datetime | None:
    if not isinstance(value, datetime.datetime):
        return None
    return value if value.tzinfo else value.replace(tzinfo=datetime.timezone.utc)


def parse_date(value) -> datetime.datetime | None:
    if isinstance(value, str):
        try:
            return as_utc(datetime.datetime.strptime(value, "%Y-%m-%d %H:%M:%S"))
        except ValueError:
            return None
    return as_utc(value)


def kind_of(path: Path, name: str) -> str:
    for prefix, kind in KIND_BY_NAME:
        if (name or "").startswith(prefix):
            return kind
    return KIND_BY_SUFFIX.get(path.suffix, "")


def without_team(identifier: str) -> str:
    return (identifier or "").split(".", 1)[1] if "." in (identifier or "") else ""


@dataclass(frozen=True)
class Profile:
    path: Path
    name: str
    team: str
    identifier: str
    kind: str
    created: datetime.datetime | None
    expires: datetime.datetime | None
    devices: tuple

    @property
    def wildcard(self) -> bool:
        return without_team(self.identifier) == WILDCARD

    def matches(self, bundle_id: str) -> bool:
        part = without_team(self.identifier)
        return part in (bundle_id, CATALYST_PREFIX + bundle_id, WILDCARD)

    def days_left(self, moment: datetime.datetime) -> float | None:
        if not self.expires:
            return None
        return (self.expires - as_moment(moment)).total_seconds() / SECONDS_PER_DAY

    def state(self, moment: datetime.datetime) -> str:
        if not self.expires:
            return "no expiry date"
        return "expired" if self.days_left(moment) <= 0 else "active"

    def short_uuid(self) -> str:
        return self.path.stem[:8]

    def expiry_text(self) -> str:
        return f"{self.expires:%Y-%m-%d %H:%M}" if self.expires else "?"

    def describe(self, moment: datetime.datetime) -> str:
        left = self.days_left(moment)
        tail = f"{left:.1f} days" if left is not None else "unknown"
        return (f"{self.name or self.path.name}  [{self.short_uuid()}]  {self.state(moment)} "
                f"until {self.expiry_text()}  ({tail})")


@dataclass(frozen=True)
class TargetSpec:
    id: str
    title: str
    kind: str
    bundle_id: str
    configuration: str = "Debug"


def parse(raw: dict, path: Path) -> Profile:
    name = str(raw.get("Name") or "")
    teams = [str(item) for item in (raw.get("TeamIdentifier") or []) if item]
    entitlements = raw.get("Entitlements") or {}
    devices = tuple(str(item) for item in (raw.get("ProvisionedDevices") or []))
    return Profile(path=path, name=name, team=teams[0] if teams else "",
                   identifier=str(entitlements.get("application-identifier") or ""),
                   kind=kind_of(path, name), created=parse_date(raw.get("CreationDate")),
                   expires=parse_date(raw.get("ExpirationDate")), devices=devices)


class SigningState:
    def __init__(self, profiles: tuple, moment: datetime.datetime | None = None):
        self.moment = as_moment(moment)
        self.profiles = tuple(item for item in profiles if item.kind)

    @classmethod
    def load(cls, reader, moment: datetime.datetime | None = None) -> "SigningState":
        return cls(tuple(parse(raw, path) for path, raw in reader()), moment)

    def for_target(self, spec: TargetSpec) -> tuple:
        found = [item for item in self.profiles
                 if item.kind == spec.kind and item.matches(spec.bundle_id)]
        if any(not item.wildcard for item in found):
            found = [item for item in found if not item.wildcard]
        return tuple(sorted(found, key=lambda item: item.expires or self.moment, reverse=True))

    def newest(self, spec: TargetSpec) -> Profile | None:
        found = self.for_target(spec)
        return found[0] if found else None

    def days_left(self, spec: TargetSpec) -> float | None:
        newest = self.newest(spec)
        return newest.days_left(self.moment) if newest else None
