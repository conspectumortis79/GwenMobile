#!/usr/bin/env python3
import argparse
import plistlib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LOCALIZATIONS = ("en", "de", "es", "fr")
CANONICAL = "en"
ENTRY_RE = re.compile(r'^\s*(?:"(?P<quoted>[^"]+)"|(?P<bare>[A-Za-z0-9_.]+))\s*=\s*"(?P<value>(?:[^"\\]|\\.)*)"\s*;')


def info_plist(root: Path) -> Path:
    return root / "GwenMobile" / "Info.plist"


def strings_file(root: Path, language: str) -> Path:
    return root / "GwenMobile" / f"{language}.lproj" / "InfoPlist.strings"


def read_plist(root: Path) -> dict:
    with info_plist(root).open("rb") as handle:
        return plistlib.load(handle)


def localizable_keys(values: dict) -> list:
    return [key for key, value in values.items()
            if isinstance(value, str) and (key.endswith("UsageDescription") or key == "CFBundleDisplayName")]


def read_entries(path: Path) -> list:
    entries = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = ENTRY_RE.match(line)
        if not match:
            continue
        key = match.group("quoted") or match.group("bare")
        entries.append((key, unescape(match.group("value"))))
    return entries


def unescape(text: str) -> str:
    return re.sub(r"\\(.)", lambda pair: {"n": "\n", "t": "\t"}.get(pair.group(1), pair.group(1)), text)


def escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def file_keys(root: Path, language: str) -> list:
    path = strings_file(root, language)
    if not path.is_file():
        return []
    return [key for key, _ in read_entries(path)]


def expected_keys(root: Path) -> list:
    return localizable_keys(read_plist(root))


def audit(root: Path) -> list:
    expected = set(expected_keys(root))
    problems = []
    for language in LOCALIZATIONS:
        path = strings_file(root, language)
        if not path.is_file():
            problems.append(f"{path.relative_to(root)} is missing")
            continue
        present = set(file_keys(root, language))
        for key in sorted(expected - present):
            problems.append(f"{path.relative_to(root)} is missing: {key}")
        for key in sorted(present - expected):
            problems.append(f"{path.relative_to(root)} has a key that is not in {info_plist(root).name}: {key}")
    return problems


def sync_english(root: Path) -> list:
    values = read_plist(root)
    expected = localizable_keys(values)
    path = strings_file(root, CANONICAL)
    if not path.is_file():
        sys.exit(f"ERROR: {path} is missing")
    entries = read_entries(path)
    present = [key for key, _ in entries]
    unknown = [key for key in present if key not in expected]
    if unknown:
        sys.exit(f"ERROR: {info_plist(root).name} does not define: {', '.join(unknown)}")
    ordered = present + [key for key in expected if key not in present]
    lines = [f'{key} = "{escape(values[key])}";' for key in ordered]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return [(key, before, values[key]) for key, before in entries if before != values[key]]


def main() -> None:
    parser = argparse.ArgumentParser(description="Sync InfoPlist.strings with Info.plist and check every language")
    parser.add_argument("--check", action="store_true",
                        help="report missing or unknown keys without writing anything")
    args = parser.parse_args()

    if args.check:
        problems = audit(REPO)
        if problems:
            print(f"ERROR: {len(problems)} InfoPlist.strings problem(s):")
            for problem in problems:
                print("  " + problem)
            sys.exit(1)
        print(f"InfoPlist.strings complete: {len(expected_keys(REPO))} keys x {len(LOCALIZATIONS)} languages")
        return

    changed = sync_english(REPO)
    for key, before, after in changed:
        print(f"{key}: {before!r} → {after!r}")
    problems = audit(REPO)
    if problems:
        print(f"ERROR: {len(problems)} InfoPlist.strings problem(s):")
        for problem in problems:
            print("  " + problem)
        sys.exit(1)
    print("InfoPlist.strings synchronized" if changed else "InfoPlist.strings was already up to date")


if __name__ == "__main__":
    main()
