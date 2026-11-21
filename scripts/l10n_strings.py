#!/usr/bin/env python3
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LANGUAGES = ("de", "en", "es", "fr")
SOURCE_FOLDERS = (
    "GwenMobile",
    "GwenMobileProbes",
    "GwenMobileSystem",
    "GwenMobileAdapters",
    "GwenMobileDevice",
    "GwenMobileShell",
)
SKIP_NAMES = ("L10nTable.swift",)
ENTRY_RE = re.compile(r'^"(?P<key>(?:[^"\\]|\\.)*)"\s*=\s*"(?P<value>(?:[^"\\]|\\.)*)"\s*;$')
ESCAPES = {"\\": "\\", '"': '"', "n": "\n", "t": "\t", "r": "\r", "0": "\0"}


def unescape(text: str) -> str:
    out = []
    index = 0
    while index < len(text):
        if text[index] == "\\" and index + 1 < len(text):
            out.append(ESCAPES.get(text[index + 1], text[index + 1]))
            index += 2
        else:
            out.append(text[index])
            index += 1
    return "".join(out)
