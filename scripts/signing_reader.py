#!/usr/bin/env python3
import datetime
import plistlib
import shutil
import subprocess
from pathlib import Path

SECURITY = "/usr/bin/security"
PROFILE_DIR = Path.home() / "Library" / "Developer" / "Xcode" / "UserData" / "Provisioning Profiles"
SUFFIXES = (".mobileprovision", ".provisionprofile")
DECODE_TIMEOUT = 60


def decode(path: Path) -> dict:
    try:
        done = subprocess.run([SECURITY, "cms", "-D", "-i", str(path)],
                              capture_output=True, timeout=DECODE_TIMEOUT)
    except (OSError, subprocess.SubprocessError):
        return {}
    if done.returncode != 0 or not done.stdout:
        return {}
    try:
        payload = plistlib.loads(done.stdout)
    except (ValueError, SyntaxError):
        return {}
    return payload if isinstance(payload, dict) else {}


def paths_of(directory: Path = PROFILE_DIR) -> tuple:
    if not directory.is_dir():
        return ()
    return tuple(item for item in sorted(directory.iterdir()) if item.suffix in SUFFIXES)


def read_all(directory: Path = PROFILE_DIR) -> tuple:
    return tuple((path, decode(path)) for path in paths_of(directory))


def retire(path: Path, backup: Path) -> Path:
    backup.mkdir(parents=True, exist_ok=True)
    target = backup / path.name
    if target.exists():
        stamp = datetime.datetime.now().strftime("%H%M%S")
        target = backup / f"{path.stem}-{stamp}{path.suffix}"
    shutil.move(str(path), str(target))
    return target


def restore(backup: Path, directory: Path = PROFILE_DIR) -> tuple:
    directory.mkdir(parents=True, exist_ok=True)
    moved = []
    for item in sorted(backup.glob("*")) if backup.is_dir() else ():
        if item.suffix in SUFFIXES:
            shutil.move(str(item), str(directory / item.name))
            moved.append(directory / item.name)
    return tuple(moved)
