#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LANGUAGES = ("de", "en", "es", "fr")
SOURCE_FOLDERS = ("GwenMobile", "GwenMobileProbes", "GwenMobileSystem", "GwenMobileAdapters", "GwenMobileDevice", "GwenMobileShell")
SKIP_NAMES = ("L10nTable.swift",)
ENTRY_RE = re.compile(r'^"(?P<key>(?:[^"\\]|\\.)*)"\s*=\s*"(?P<value>(?:[^"\\]|\\.)*)"\s*;$')
CALL_RE = re.compile(r'L\.(?P<call>fmt|fmt2|n)\(\s*"(?P<literal>(?:[^"\\]|\\.)*)"')
COUNTED_RE = re.compile(r'L\.counted\((?:[^"()]|\([^()]*\))*?one:\s*"(?P<one>(?:[^"\\]|\\.)*)"\s*,'
                        r'\s*many:\s*"(?P<many>(?:[^"\\]|\\.)*)"')
SLOTS = {"fmt": 1, "fmt2": 2}
SWIFT_ESCAPES = {"\\": "\\", '"': '"', "n": "\n", "t": "\t", "r": "\r", "0": "\0"}


def unescape(literal: str) -> str:
    out = []
    index = 0
    while index < len(literal):
        if literal[index] == "\\" and index + 1 < len(literal):
            out.append(SWIFT_ESCAPES.get(literal[index + 1], literal[index + 1]))
            index += 2
        else:
            out.append(literal[index])
            index += 1
    return "".join(out)


def read_table(root: Path, language: str) -> dict:
    path = root / "Localization" / f"{language}.strings"
    table = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = ENTRY_RE.match(line.strip())
        if match:
            table[unescape(match.group("key"))] = match.group("value")
    return table


def source_calls(root: Path) -> list:
    calls = []
    for folder in SOURCE_FOLDERS:
        for path in sorted((root / folder).rglob("*.swift")):
            if path.name in SKIP_NAMES:
                continue
            text = path.read_text(encoding="utf-8")
            for match in CALL_RE.finditer(text):
                literal = match.group("literal")
                if "\\(" in literal:
                    continue
                line = text.count("\n", 0, match.start()) + 1
                calls.append((path.relative_to(root), line, match.group("call"), unescape(literal)))
            for match in COUNTED_RE.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                calls.append((path.relative_to(root), line, "counted_one", unescape(match.group("one"))))
                calls.append((path.relative_to(root), line, "counted_many", unescape(match.group("many"))))
    return calls


def check(root: Path) -> list:
    tables = {language: read_table(root, language) for language in LANGUAGES}
    problems = []
    for path, line, call, key in source_calls(root):
        label = {"counted_one": f'L.counted(one: "{key}")',
                 "counted_many": f'L.counted(many: "{key}")'}.get(call, f'L.{call}("{key}")')
        where = f"{path}:{line}: {label}"
        if key not in tables["de"]:
            problems.append(f"{where} is not defined in Localization/de.strings")
            continue
        for language, table in tables.items():
            text = table.get(key)
            if text is None:
                problems.append(f"{where} is missing in Localization/{language}.strings")
                continue
            slots = text.count("%@")
            if call in SLOTS and slots != SLOTS[call]:
                problems.append(f"{where} in {language}: expected {SLOTS[call]} %@, found {slots}")
            if call in ("n", "counted_many") and "%d" not in text:
                problems.append(f"{where} in {language}: no %d placeholder for the count")
            if call == "counted_one" and ("%d" in text or slots):
                problems.append(f"{where} in {language}: the text for a count of one keeps a placeholder")
    return problems


def main() -> None:
    parser = argparse.ArgumentParser(description="Fail when a localization call does not match its placeholders")
    args = parser.parse_args()
    problems = check(REPO)
    if problems:
        print(f"ERROR: {len(problems)} localization placeholder problem(s):")
        for problem in problems:
            print("  " + problem)
        sys.exit(1)
    print(f"localization placeholders ok: {len(source_calls(REPO))} calls match their keys")


if __name__ == "__main__":
    main()
