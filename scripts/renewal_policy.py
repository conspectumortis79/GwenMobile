#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

import signing_state

DEFAULT_THRESHOLD_DAYS = 2.0
MISSING_PROFILE = "no provisioning profile for this target yet"
UNKNOWN_DATE = "the profile carries no expiry date — renewing to be safe"
EXPIRED = "the profile expired on {expires} — the app has to be reinstalled on this target"
BELOW_THRESHOLD = "the profile runs out in {left:.1f} days (threshold {threshold:.1f})"
DEVICE_BELOW = "the build on this target was installed {age}, its profile runs out in {left:.1f} days"
DEVICE_EXPIRED = ("the build on this target was installed {age} — past the 7 days, so its profile is "
                      "expired")
PENDING_RETRY = "the last attempt for this target failed — retrying until the device answers"
STILL_VALID = "the profile holds for another {left:.1f} days — nothing to do"
FORCED = "renewal forced by --force"
NO_PROFILE = "no profile"
NO_DEADLINE = "device deadline unknown"


@dataclass(frozen=True)
class Plan:
    spec: signing_state.TargetSpec
    profile: signing_state.Profile | None
    renew: bool
    reason: str
    days_left: float | None
    moment: datetime
    cache_days: float | None = None
    device_days: float | None = None

    @property
    def target_id(self) -> str:
        return self.spec.id

    @property
    def title(self) -> str:
        return self.spec.title

    def deadline_text(self) -> str:
        if self.device_days is None:
            return NO_DEADLINE
        return f"installed build runs out in {self.device_days:.1f} days"

    def profile_text(self) -> str:
        return self.profile.describe(self.moment) if self.profile else NO_PROFILE

    def describe(self) -> str:
        action = "renew" if self.renew else "keep"
        return f"{self.title}: {action} — {self.reason}\n    {self.profile_text()}"


def merged_days_left(cache_days: float | None, device_days: float | None) -> float | None:
    values = [item for item in (cache_days, device_days) if item is not None]
    return min(values) if values else None


def reason_for(profile, cache_days: float | None, device_days: float | None, threshold: float,
               force: bool, pending: bool, age: str) -> tuple:
    left = merged_days_left(cache_days, device_days)
    if force:
        return True, FORCED
    if pending:
        return True, PENDING_RETRY
    if profile is None:
        return True, MISSING_PROFILE
    if profile.expires is None:
        return True, UNKNOWN_DATE
    device_driven = device_days is not None and (cache_days is None or device_days < cache_days)
    if left is None or left <= 0:
        return True, (DEVICE_EXPIRED.format(age=age) if device_driven
                      else EXPIRED.format(expires=profile.expiry_text()))
    if left < threshold:
        return True, (DEVICE_BELOW.format(age=age, left=left) if device_driven
                      else BELOW_THRESHOLD.format(left=left, threshold=threshold))
    return False, STILL_VALID.format(left=left)


def selected(specs: tuple, wanted: tuple) -> tuple:
    if not wanted or "*" in wanted or "all" in wanted:
        return tuple(specs)
    known = {spec.id: spec for spec in specs}
    missing = sorted(set(wanted) - set(known))
    if missing:
        raise ValueError("unknown target: " + ", ".join(missing)
                         + " — available: " + ", ".join(known))
    return tuple(spec for spec in specs if spec.id in set(wanted))


def decide(specs: tuple, state: signing_state.SigningState, threshold: float = DEFAULT_THRESHOLD_DAYS,
           force: bool = False, wanted: tuple = (), installs=None) -> tuple:
    moment = state.moment
    plans = []
    for spec in selected(tuple(specs), tuple(wanted)):
        profile = state.newest(spec)
        cache_days = profile.days_left(moment) if profile else None
        device_days = installs.days_left(spec.id) if installs else None
        pending = installs.is_pending(spec.id) if installs else False
        age = installs.age_text(spec.id) if installs else ""
        renew, reason = reason_for(profile, cache_days, device_days, threshold, force, pending, age)
        plans.append(Plan(spec=spec, profile=profile, renew=renew, reason=reason,
                          days_left=merged_days_left(cache_days, device_days), moment=moment,
                          cache_days=cache_days, device_days=device_days))
    return tuple(plans)


def due(plans: tuple) -> tuple:
    return tuple(plan for plan in plans if plan.renew)


def kept(plans: tuple) -> tuple:
    return tuple(plan for plan in plans if not plan.renew)
