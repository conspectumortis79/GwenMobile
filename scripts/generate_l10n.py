#!/usr/bin/env python3
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOURCES = REPO / "Localization"
OUTPUT = REPO / "GwenMobile" / "Shared" / "L10nTable.swift"
LANGUAGES = ("de", "en", "es", "fr")
ENTRY_RE = re.compile(r'^"(?P<key>(?:[^"\\]|\\.)*)"\s*=\s*"(?P<value>(?:[^"\\]|\\.)*)"\s*;$')
LINE_LIMIT = 118


def unescape(text: str) -> str:
    out = []
    index = 0
    while index < len(text):
        character = text[index]
        if character == "\\" and index + 1 < len(text):
            following = text[index + 1]
            out.append({"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}.get(following, following))
            index += 2
        else:
            out.append(character)
            index += 1
    return "".join(out)


def escape_swift(text: str) -> str:
    return (text.replace("\\", "\\\\").replace('"', '\\"')
            .replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r"))


def read_language(language: str) -> dict:
    path = SOURCES / f"{language}.strings"
    if not path.is_file():
        sys.exit(f"ERROR: {path} is missing")
    entries = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = line.strip()
        if not stripped:
            continue
        match = ENTRY_RE.match(stripped)
        if not match:
            sys.exit(f"ERROR: {path}:{number}: not a string entry: {line}")
        key = unescape(match.group("key"))
        if key in entries:
            sys.exit(f"ERROR: {path}:{number}: duplicate key {key}")
        entries[key] = unescape(match.group("value"))
    if not entries:
        sys.exit(f"ERROR: {path} holds no entries")
    return entries


def load() -> dict:
    tables = {language: read_language(language) for language in LANGUAGES}
    reference = set(tables[LANGUAGES[0]])
    for language in LANGUAGES[1:]:
        missing = reference - set(tables[language])
        extra = set(tables[language]) - reference
        if missing:
            sys.exit(f"ERROR: {language}.strings is missing: {', '.join(sorted(missing))}")
        if extra:
            sys.exit(f"ERROR: {language}.strings has unknown keys: {', '.join(sorted(extra))}")
    return {key: {language: tables[language][key] for language in LANGUAGES} for key in sorted(reference)}


def swift_entry(key: str, values: dict) -> str:
    pairs = [(language, escape_swift(values[language])) for language in LANGUAGES]
    inline = '        "%s": [%s],' % (escape_swift(key),
                                      ", ".join(f'.{language}: "{text}"' for language, text in pairs))
    if len(inline) <= LINE_LIMIT:
        return inline
    lines = ['        "%s": [.de: "%s",' % (escape_swift(key), pairs[0][1])]
    lines += [f'                .{language}: "{text}",' for language, text in pairs[1:]]
    lines[-1] = lines[-1].rstrip(",") + "],"
    return "\n".join(lines)


def render(entries: dict) -> str:
    lines = ["import Foundation", "", "enum L10nTable {",
             "    static let values: [String: [AppLanguage: String]] = ["]
    lines += [swift_entry(key, entries[key]) for key in entries]
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def main() -> None:
    entries = load()
    generated = render(entries)
    if "--check" in sys.argv:
        existing = OUTPUT.read_text(encoding="utf-8") if OUTPUT.is_file() else ""
        if existing != generated:
            sys.exit(f"ERROR: {OUTPUT.relative_to(REPO)} is out of date — run scripts/generate_l10n.py")
        print(f"{OUTPUT.relative_to(REPO)} is up to date ({len(entries)} keys x {len(LANGUAGES)} languages)")
        return
    OUTPUT.write_text(generated, encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(REPO)} with {len(entries)} keys x {len(LANGUAGES)} languages")


if __name__ == "__main__":
    main()
