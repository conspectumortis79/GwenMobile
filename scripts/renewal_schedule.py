#!/usr/bin/env python3
from __future__ import annotations

import os
import plistlib
import shutil
import sys
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common

LABEL = "com.mortis.gwenmobile.renew-signing"
AGENT_DIR = Path.home() / "Library" / "LaunchAgents"
AGENT_PATH = AGENT_DIR / f"{LABEL}.plist"
LOG_DIR = Path(common.REPO) / "build" / "renew"
DEFAULT_HOUR = 9
DEFAULT_MINUTE = 20
DEFAULT_WAIT_MINUTES = 20
DEFAULT_THRESHOLD = "2"
DEFAULT_TARGETS = "all"
EXTRA_PATH = ("/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:"
              "/Applications/Xcode.app/Contents/Developer/usr/bin")
DOMAIN_PREFIX = "gui"


def default_path(extra: str = "") -> str:
    parts = EXTRA_PATH.split(":")
    candidates = [str(Path(sys.executable).parent) if sys.executable else "", extra]
    candidates.extend(tool_dirs())
    for directory in candidates:
        if directory and directory not in parts:
            parts.append(directory)
    return ":".join(parts)


def domain() -> str:
    return f"{DOMAIN_PREFIX}/{os.getuid()}"


def shorthand() -> str:
    return f"{domain()}/{LABEL}"


def parse_spec(spec: str) -> tuple:
    hour, minute = (spec.split(":") + ["0"])[:2]
    if not (hour.isdigit() and minute.isdigit()):
        raise ValueError(f"'{spec}' is not HH:MM")
    if not (0 <= int(hour) <= 23 and 0 <= int(minute) <= 59):
        raise ValueError(f"'{spec}' is outside 00:00 … 23:59")
    return int(hour), int(minute)


def next_fire(hour: int, minute: int, moment: datetime | None = None) -> datetime:
    start = moment or datetime.now()
    candidate = start.replace(hour=int(hour), minute=int(minute), second=0, microsecond=0)
    return candidate if candidate > start else candidate + timedelta(days=1)


def tool_dirs() -> tuple:
    found = []
    for tool in (sys.executable, shutil.which("xcodegen"), shutil.which("xcrun")):
        directory = str(Path(tool).parent) if tool else ""
        if directory and directory not in found:
            found.append(directory)
    return tuple(found)


def render(script: Path, hour: int, minute: int, python: str | None = None,
           working: Path | None = None, log_dir: Path | None = None,
           wait_minutes: int = DEFAULT_WAIT_MINUTES, device: str = "") -> dict:
    log_dir = Path(log_dir or LOG_DIR)
    arguments = [python or sys.executable, str(script), "--renew", "--targets", DEFAULT_TARGETS,
                 "--threshold", DEFAULT_THRESHOLD, "--wait-minutes", str(wait_minutes)]
    if device:
        arguments += ["--device", device]
    return {
        "Label": LABEL,
        "ProgramArguments": arguments,
        "WorkingDirectory": str(working or Path(common.REPO)),
        "EnvironmentVariables": {"PATH": default_path(), "HOME": str(Path.home())},
        "StandardOutPath": str(log_dir / "launchd.out.log"),
        "StandardErrorPath": str(log_dir / "launchd.err.log"),
        "StartCalendarInterval": {"Hour": int(hour), "Minute": int(minute)},
    }


def load(path: Path = AGENT_PATH) -> dict:
    if not path.is_file():
        return {}
    try:
        with path.open("rb") as handle:
            payload = plistlib.load(handle)
    except (ValueError, OSError):
        return {}
    return payload if isinstance(payload, dict) else {}


def schedule_of(payload: dict) -> tuple:
    interval = payload.get("StartCalendarInterval") or {}
    if not isinstance(interval, dict) or "Hour" not in interval:
        return (None, None)
    return (int(interval["Hour"]), int(interval["Minute"]))


def install(spec: str, script: Path, python: str | None = None, device: str = "") -> Path:
    hour, minute = parse_spec(spec)
    payload = render(script, hour, minute, python=python, device=device)
    AGENT_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    with AGENT_PATH.open("wb") as handle:
        plistlib.dump(payload, handle)
    print(f"Wrote {AGENT_PATH} — the job runs every day at {hour:02d}:{minute:02d}")
    print(f"The first run is at {next_fire(hour, minute):%Y-%m-%d %H:%M}.")
    return AGENT_PATH


def unload(run=common.run) -> int:
    done = run(["/bin/launchctl", "bootout", shorthand()])
    if done.returncode == 0:
        print("launchd job unloaded")
    if AGENT_PATH.is_file():
        AGENT_PATH.unlink()
        print(f"removed {AGENT_PATH}")
    return 0


def reload(run=common.run) -> int:
    run(["/bin/launchctl", "bootout", shorthand()])
    done = run(["/bin/launchctl", "bootstrap", domain(), AGENT_PATH])
    if done.returncode != 0:
        print("launchctl bootstrap said: " + (done.stderr or done.stdout).strip()[:300])
    else:
        print(f"launchd job loaded: {shorthand()}")
    return done.returncode


def start_now(run=common.run) -> int:
    done = run(["/bin/launchctl", "kickstart", "-k", shorthand()])
    if done.returncode != 0:
        print("kickstart failed — is the job installed? "
              + (done.stderr or done.stdout).strip()[:200])
    return done.returncode


def loaded(run=common.run) -> bool:
    return run(["/bin/launchctl", "print", shorthand()]).returncode == 0


def status(run=common.run) -> dict:
    payload = load()
    hour, minute = schedule_of(payload)
    return {"file": str(AGENT_PATH), "installed": bool(payload),
            "loaded": loaded(run) if payload else False,
            "time": f"{hour:02d}:{minute:02d}" if hour is not None else "-",
            "next": next_fire(hour, minute) if hour is not None else None,
            "arguments": payload.get("ProgramArguments") or [],
            "log": str(LOG_DIR / "launchd.err.log")}
