#!/usr/bin/env python3
from __future__ import annotations

import contextlib
import io
import os
import signal
import subprocess
import sys
import time
from dataclasses import dataclass, replace
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common
import mac_app
import mac_storage
import signing_reader
import signing_state
from report import fail

SECONDS_PER_DAY = 86400.0
TRUST_NEEDLE = "not been explicitly trusted"
IPHONE_DERIVED = Path(common.REPO) / "build" / "Deploy"
MAC_DERIVED = Path(common.REPO) / "build" / "renew" / "mac-derived"
BACKUP_ROOT = Path(common.REPO) / "build" / "renew"
REACH_TIMEOUT = 60


@dataclass(frozen=True)
class Options:
    configuration: str = ""
    clean: bool = False
    launch: bool = True
    wait_minutes: float = 0.0
    device: str = ""
    mac_target: Path = Path("/Applications/GwenMobile.app")
    restart_mac: bool = False
    generate: bool = False
    no_generate: bool = False
    backup_root: Path = BACKUP_ROOT


@dataclass
class Outcome:
    plan: object
    ok: bool
    detail: str = ""
    manual: str = ""
    note: str = ""
    installed_at: Path | None = None
    expires: datetime | None = None

    @property
    def title(self) -> str:
        return self.plan.title

    @property
    def days_left(self) -> float | None:
        if not self.expires:
            return None
        return (self.expires - signing_state.now()).total_seconds() / SECONDS_PER_DAY

    def expires_text(self) -> str:
        return f"{self.expires:%Y-%m-%d %H:%M}" if self.expires else "unknown"

    def status_text(self) -> str:
        if self.ok and self.expires:
            return (f"{self.detail or 'renewed'} — valid again for {self.days_left:.1f} days "
                    f"(until {self.expires_text()})")
        if self.ok:
            return self.detail or "renewed"
        return f"failed: {_one_line(self.detail)}"


def _one_line(text: str, limit: int = 300) -> str:
    return " | ".join((text or "").splitlines())[:limit]


def attempt(action, *args, **kwargs) -> tuple:
    buffer = io.StringIO()
    try:
        with contextlib.redirect_stderr(buffer):
            result = action(*args, **kwargs)
        return True, result, buffer.getvalue().strip()
    except SystemExit as exc:
        text = buffer.getvalue().strip() or (str(exc.code) if exc.code not in (None, 0, "") else "")
        return False, None, text or "unknown failure"
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        return False, None, str(exc)


class XcodeProfileCache:
    def state(self) -> signing_state.SigningState:
        return signing_state.SigningState.load(signing_reader.read_all)

    def all(self, spec) -> tuple:
        return self.state().for_target(spec)

    def newest(self, spec):
        return self.state().newest(spec)


def choose(devices: tuple, wanted: str):
    if not devices:
        return None
    if wanted:
        for device in devices:
            if wanted in (device.udid, device.name) or wanted.lower() == device.udid.lower():
                return device
        return None
    return devices[0] if len(devices) == 1 else None


def reachable(actions, device) -> tuple:
    if device is None:
        return False, "no device picked"
    return actions.reachable(device)


def wait_for_device(actions, wanted: str, minutes: float, sleep=time.sleep, clock=time.monotonic):
    deadline = clock() + max(0.0, minutes) * 60
    picked, reason = None, ""
    while True:
        picked = choose(actions.devices(), wanted)
        ok, reason = reachable(actions, picked)
        if ok:
            return picked
        current = clock()
        if minutes <= 0 or current >= deadline:
            return None
        remaining = max(0, int(deadline - current))
        print(f"  {picked.name if picked else 'iPhone'} is not reachable yet ({reason}) — "
              f"waiting up to {remaining}s …")
        sleep(min(30, max(1, remaining)))


class IPhoneActions:
    def devices(self) -> tuple:
        try:
            return tuple(common.list_devices())
        except SystemExit:
            return ()

    def reachable(self, device) -> tuple:
        done = common.run([common.xcrun(), "devicectl", "device", "info", "lockState",
                           "--device", device.udid], timeout=REACH_TIMEOUT)
        text = (done.stderr or done.stdout or "").strip()
        return done.returncode == 0, text.splitlines()[-1] if text else "lockState failed"

    def prepare(self, options: Options) -> None:
        common.generate_project(options.generate, options.no_generate)

    def build(self, options: Options, udid: str) -> Path:
        return common.build_app(options.configuration, f"platform=iOS,id={udid}", IPHONE_DERIVED,
                                clean=options.clean)

    def install(self, app: Path, device) -> subprocess.CompletedProcess:
        return common.install_app(app, device)

    def launch(self, device) -> subprocess.CompletedProcess:
        return common.launch_app(device)

    def explain(self, text: str) -> str:
        return common.explain(text)


class MacActions:
    def __init__(self, stores: mac_storage.SettingsStores | None = None):
        self.stores = stores or mac_app.store_map()

    def store(self, bundle: Path):
        return self.stores.of(bundle)

    def prepare(self, options: Options) -> None:
        common.generate_project(options.generate, options.no_generate)

    def build(self, options: Options) -> Path:
        return mac_app.build(options.configuration, MAC_DERIVED)

    def verify(self, app: Path, configuration: str) -> None:
        mac_app.verify_entitlements(app)
        mac_app.verify_signature(app, require=configuration == "Release")

    def install(self, app: Path, target: Path) -> Path:
        return mac_app.install(app, target)

    def register(self, target: Path) -> None:
        mac_app.register(target)

    def profile(self, target: Path):
        return mac_app.profile_of(target)

    def running(self, target: Path) -> tuple:
        return mac_app.running(mac_app.app_name_of(target))

    def relaunch(self, target: Path) -> None:
        subprocess.Popen(["/usr/bin/open", "-n", str(target)], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)


def trust_hint(name: str) -> str:
    return (f"{name}: the app refused to start because the developer profile is not trusted. On the "
            "iPhone: Einstellungen → Allgemein → VPN & Geräteverwaltung → Apple ID → "
            "„Diesem Anbieter vertrauen“, then open the app.")


def device_hint(actions, wanted: str) -> str:
    devices = actions.devices()
    if not devices:
        return ("no paired iPhone in devicectl — plug in the cable, unlock the iPhone, confirm "
                "“Trust This Computer”, turn developer mode on")
    device = choose(devices, wanted)
    if device is None:
        listed = ", ".join(f"{item.name} ({item.udid})" for item in devices)
        return (f"no single iPhone to pick and “{wanted}” is not among them — paired: {listed}. "
                "Choose with --device <Name|UDID>")
    ok, reason = reachable(actions, device)
    return (f"{device.name} is paired but devicectl cannot reach it ({_one_line(reason)}). "
            f"Listed as “{device.link}” — that field is only a hint, unlock the iPhone "
            "(or plug in the cable) and run this again")


def restore_note(moved: tuple, error: str) -> str:
    if error or not moved:
        return "the retired profiles stayed in the backup folder under build/renew/."
    return (f"put {len(moved)} retired profile(s) back into the Xcode cache — "
            "nothing was lost.")


class Renewal:
    target_id = ""

    def __init__(self, options: Options, actions, cache: XcodeProfileCache | None = None):
        self.options = options
        self.actions = actions
        self.cache = cache or XcodeProfileCache()
        self.plan = None
        self.origin: Path | None = None
        self.retired: tuple = ()
        self.backup: Path | None = None

    def renew(self, plan) -> Outcome:
        self.plan = plan
        outcome = self.perform(plan)
        if not outcome.ok and self.retired:
            restored, moved, error = attempt(self.restore)
            outcome.note = (outcome.note + "  " if outcome.note else "") + restore_note(
                moved if restored else (), error)
        return outcome

    def perform(self, plan) -> Outcome:
        raise NotImplementedError

    def backup_dir(self) -> Path:
        if self.backup is None:
            stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            self.backup = (Path(self.options.backup_root)
                           / f"profile-backup-{self.plan.target_id}-{stamp}")
        return self.backup

    def retire_profiles(self) -> tuple:
        backup = self.backup_dir()
        moved = []
        for item in self.cache.all(self.plan.spec):
            if self.origin is None:
                self.origin = item.path.parent
            moved.append(signing_reader.retire(item.path, backup))
            print(f"  retired {item.short_uuid()} {item.path.suffix} → {backup.name}/")
        self.retired = tuple(moved)
        if not moved:
            print("  no cached profile to retire (Xcode will create one)")
        return self.retired

    def restore(self) -> tuple:
        if not self.backup or not self.origin:
            return ()
        moved = signing_reader.restore(self.backup, self.origin)
        print(f"  put {len(moved)} retired profile(s) back into {self.origin}")
        return moved

    def options_for(self, plan) -> Options:
        return replace(self.options, configuration=self.options.configuration
                       or plan.spec.configuration)

    def outcome(self, plan, ok: bool, detail: str = "", manual: str = "", note: str = "",
                installed_at: Path | None = None) -> Outcome:
        fresh = self.cache.newest(plan.spec)
        return Outcome(plan=plan, ok=ok, detail=detail, manual=manual, note=note,
                       installed_at=installed_at, expires=fresh.expires if fresh else None)


class IPhoneRenewal(Renewal):
    target_id = "iphone"

    def perform(self, plan) -> Outcome:
        device = wait_for_device(self.actions, self.options.device, self.options.wait_minutes)
        if device is None:
            return self.outcome(plan, False, device_hint(self.actions, self.options.device))
        print(f"Device: {device.label()}")
        options = self.options_for(plan)
        self.actions.prepare(options)
        ok, _moved, error = attempt(self.retire_profiles)
        if not ok:
            return self.outcome(plan, False, error, manual="check the Apple ID login in Xcode → Accounts")
        ok, app, error = attempt(self.actions.build, options, device.udid)
        if not ok:
            return self.outcome(plan, False, error, manual="fix the build error shown above")
        ok, done, error = attempt(self.actions.install, app, device)
        text = error or (done.stdout + done.stderr if done else "")
        if not ok or done is None or done.returncode != 0:
            return self.outcome(plan, False, text or "install failed",
                                manual=self.actions.explain(text))
        print(f"  installed on {device.name}")
        return self.finish(plan, device, app)

    def finish(self, plan, device, app: Path) -> Outcome:
        if not self.options.launch:
            return self.outcome(plan, True, f"installed on {device.name}", installed_at=app)
        ok, done, error = attempt(self.actions.launch, device)
        text = error or (done.stdout + done.stderr if done else "")
        if TRUST_NEEDLE in text:
            return self.outcome(plan, True, f"installed on {device.name} — the start was blocked",
                                manual=trust_hint(device.name), installed_at=app)
        if not ok or done is None or done.returncode != 0:
            return self.outcome(plan, True, f"installed, but starting it failed: "
                                            f"{_one_line(text)}",
                                manual=self.actions.explain(text), installed_at=app)
        print("  app is running")
        return self.outcome(plan, True, f"installed and started on {device.name}",
                            installed_at=app)


class MacRenewal(Renewal):
    target_id = "mac"

    def perform(self, plan) -> Outcome:
        options = self.options_for(plan)
        self.actions.prepare(options)
        installed = self.settings_of(self.options.mac_target)
        ok, _moved, error = attempt(self.retire_profiles)
        if not ok:
            return self.outcome(plan, False, error, manual="check the profile cache under build/renew/")
        ok, app, error = attempt(self.actions.build, options)
        if not ok:
            return self.outcome(plan, False, error, manual="fix the build error shown above")
        attempt(self.actions.verify, app, options.configuration)
        shift = mac_storage.shift_warning(installed, self.settings_of(app))
        ok, target, error = attempt(self.actions.install, app, self.options.mac_target)
        if not ok:
            return self.outcome(plan, False, error, manual="check the write permission in /Applications")
        attempt(self.actions.register, target)
        return self.finish(plan, target, shift)

    def settings_of(self, bundle: Path):
        ok, store, _error = attempt(self.actions.store, bundle)
        return store if ok else None

    def finish(self, plan, target: Path, shift: str = "") -> Outcome:
        fresh = self.actions.profile(target)
        note = ""
        if self.options.restart_mac:
            self.restart(target)
            note = "GwenMobile was restarted"
        elif self.actions.running(target):
            note = ("the running instance still holds the old profile — it picks the new one up on "
                    "the next launch, or restart it now with --restart-mac")
        return Outcome(plan=plan, ok=True, detail=f"installed into {target}", note=note, manual=shift,
                       installed_at=target, expires=fresh.expires if fresh else None)

    def restart(self, target: Path) -> None:
        for pid in self.actions.running(target):
            try:
                os.kill(int(pid), signal.SIGTERM)
            except (ProcessLookupError, PermissionError, ValueError):
                continue
        time.sleep(2)
        self.actions.relaunch(target)


ADAPTERS = {IPhoneRenewal.target_id: IPhoneRenewal, MacRenewal.target_id: MacRenewal}
ACTION_CLASSES = {IPhoneRenewal.target_id: IPhoneActions, MacRenewal.target_id: MacActions}


def adapter_for(plan, options: Options, cache: XcodeProfileCache | None = None) -> Renewal:
    adapter = ADAPTERS.get(plan.target_id)
    if adapter is None:
        fail(f"no renewal adapter for '{plan.target_id}' — known: " + ", ".join(sorted(ADAPTERS)))
    return adapter(options, ACTION_CLASSES[plan.target_id](), cache)
