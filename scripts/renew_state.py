#!/usr/bin/env python3
from __future__ import annotations

import json
from dataclasses import dataclass, replace
from datetime import datetime, timedelta, timezone
from pathlib import Path

PROFILE_DAYS = 7.0
SECONDS_PER_DAY = 86400.0
INSTALLS_KEY = "installs"
PENDING_KEY = "pending"


def to_utc(value) -> datetime | None:
    if not isinstance(value, datetime):
        return None
    return (value if value.tzinfo else value.astimezone()).astimezone(timezone.utc)


def from_iso(text: str) -> datetime | None:
    try:
        return to_utc(datetime.fromisoformat(text))
    except (TypeError, ValueError):
        return None


@dataclass(frozen=True)
class Installs:
    stamps: dict
    pending: tuple
    moment: datetime

    @classmethod
    def empty(cls, moment: datetime | None = None) -> "Installs":
        return cls({}, (), to_utc(moment) or datetime.now(timezone.utc))

    @classmethod
    def load(cls, path: Path, moment: datetime | None = None) -> "Installs":
        base = to_utc(moment) or datetime.now(timezone.utc)
        try:
            raw = json.loads(path.read_text()) if path.is_file() else {}
        except (OSError, ValueError):
            raw = {}
        stamps = raw.get(INSTALLS_KEY) if isinstance(raw, dict) else None
        pending = raw.get(PENDING_KEY) if isinstance(raw, dict) else None
        return cls({str(k): str(v) for k, v in (stamps or {}).items()},
                   tuple(str(item) for item in (pending or [])), base)

    def since(self, target_id: str) -> timedelta | None:
        stamp = from_iso(self.stamps.get(target_id, ""))
        return (self.moment - stamp) if stamp else None

    def days_left(self, target_id: str) -> float | None:
        passed = self.since(target_id)
        return None if passed is None else PROFILE_DAYS - passed.total_seconds() / SECONDS_PER_DAY

    def age_text(self, target_id: str) -> str:
        passed = self.since(target_id)
        return "never" if passed is None else f"{passed.days} days ago"

    def is_pending(self, target_id: str) -> bool:
        return target_id in self.pending

    def recorded(self, target_id: str, when: datetime) -> "Installs":
        stamps = dict(self.stamps)
        stamps[target_id] = to_utc(when).isoformat()
        return replace(self, stamps=stamps,
                       pending=tuple(item for item in self.pending if item != target_id))

    def marked(self, target_id: str) -> "Installs":
        return self if self.is_pending(target_id) else replace(self, pending=self.pending + (target_id,))

    def payload(self) -> dict:
        return {INSTALLS_KEY: dict(self.stamps), PENDING_KEY: list(self.pending)}


def store(path: Path, installs: Installs) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(installs.payload(), indent=1, sort_keys=True) + "\n", encoding="utf-8")
    return path
