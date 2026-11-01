#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
STRINGS = Path("Localization") / "de.strings"
SOURCE_FOLDERS = ("GwenMobile", "GwenMobileProbes", "GwenMobileSystem", "GwenMobileAdapters", "GwenMobileDevice", "GwenMobileShell")
SKIP_NAMES = ("L10nTable.swift",)
ENTRY_RE = re.compile(r'^"(?P<key>(?:[^"\\]|\\.)*)"\s*=')

# Keys that are assembled from an enum raw value at runtime: "<prefix><rawValue>".
DYNAMIC_PREFIXES = (
    "feature_",
    "memory_cat_",
    "memory_retention_",
    "memory_source_",
    "price_watch_status_",
    "scan_file_",
    "scan_task_",
)

# Keys that are assembled from a variable: "\(keyPrefix)_ambiguous" in ContactAnswer.
INTERPOLATED_KEYS = frozenset({
    "call_ambiguous",
    "call_no_number",
    "message_ambiguous",
    "message_no_number",
})


def keys_in(path: Path) -> list:
    found = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = ENTRY_RE.match(line.strip())
        if match:
            found.append(match.group("key"))
    return found


def source_text(root: Path) -> str:
    parts = []
    for folder in SOURCE_FOLDERS:
        for path in sorted((root / folder).rglob("*.swift")):
            if path.name in SKIP_NAMES:
                continue
            parts.append(path.read_text(encoding="utf-8"))
    return "\n".join(parts)


def unused_keys(keys: list, source: str,
                prefixes: tuple = DYNAMIC_PREFIXES,
                interpolated: frozenset = INTERPOLATED_KEYS) -> list:
    unused = []
    for key in keys:
        if f'"{key}"' in source:
            continue
        if key in interpolated:
            continue
        if any(key.startswith(prefix) for prefix in prefixes):
            continue
        unused.append(key)
    return unused


def check(root: Path) -> list:
    return unused_keys(keys_in(root / STRINGS), source_text(root))


def main() -> None:
    parser = argparse.ArgumentParser(description="Fail when a localization key is never referenced")
    parser.add_argument("--list", action="store_true", help="print every unused key and exit 0")
    args = parser.parse_args()

    keys = keys_in(REPO / STRINGS)
    unused = check(REPO)
    if args.list:
        for key in unused:
            print(key)
        return
    if unused:
        print(f"ERROR: {len(unused)} localization key(s) are never referenced:")
        for key in unused:
            print("  " + key)
        sys.exit(1)
    print(f"localization usage ok: {len(keys)} keys are referenced (directly, dynamically or interpolated)")


if __name__ == "__main__":
    main()
