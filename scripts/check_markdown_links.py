#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

REPO = Path(__file__).resolve().parent.parent
SKIP_PARTS = {".git", "build", "node_modules", "GwenMobile.xcodeproj"}
SKIP_PREFIXES = ("GwenMobile/Resources/Prompts",)
LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
IMAGE_RE = re.compile(r"<img[^>]*\bsrc=\"([^\"]+)\"", re.IGNORECASE)
FENCE_RE = re.compile(r"^\s*(```|~~~)")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
EXTERNAL_RE = re.compile(r"^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|//)")


def slug(heading: str) -> str:
    text = heading.strip().lower()
    text = re.sub(r"[^\w\s-]", "", text, flags=re.UNICODE)
    return re.sub(r"\s+", "-", text)


def anchors(path: Path) -> set:
    found = set()
    counts = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = HEADING_RE.match(line)
        if not match:
            continue
        base = slug(match.group(2))
        number = counts.get(base, 0)
        found.add(base if number == 0 else "{}-{}".format(base, number))
        counts[base] = number + 1
    return found


def visible_lines(path: Path) -> list:
    lines = []
    fenced = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if FENCE_RE.match(line):
            fenced = not fenced
            lines.append("")
            continue
        lines.append("" if fenced else re.sub(r"`[^`]*`", "", line))
    return lines


def documents(root: Path) -> list:
    found = []
    for path in sorted(root.rglob("*.md")):
        relative = path.relative_to(root)
        if any(part in SKIP_PARTS for part in relative.parts):
            continue
        if any(str(relative).startswith(prefix) for prefix in SKIP_PREFIXES):
            continue
        found.append(path)
    return found


def fragment_of(target: str) -> str:
    return unquote(target.partition("#")[2]).lower()


def check_document(path: Path, root: Path) -> list:
    problems = []
    own = anchors(path)
    for number, line in enumerate(visible_lines(path), start=1):
        targets = LINK_RE.findall(line) + IMAGE_RE.findall(line)
        for raw in targets:
            target = raw.strip().strip("<>").strip()
            if not target or EXTERNAL_RE.match(target):
                continue
            split = urlsplit(target)
            location = unquote(split.path)
            fragment = fragment_of(target)
            if not location:
                if fragment and fragment not in own:
                    problems.append((number, target, "anchor missing in this file"))
                continue
            if location.startswith("/"):
                candidate = (root / location.lstrip("/")).resolve()
            else:
                candidate = (path.parent / location).resolve()
            if not candidate.exists():
                problems.append((number, target, "target does not exist"))
                continue
            if fragment and candidate.suffix.lower() in (".md", ".markdown"):
                if fragment not in anchors(candidate):
                    problems.append((number, target, "anchor missing in the target"))
    return problems


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=str(REPO), help="repository root to scan")
    args = parser.parse_args()
    root = Path(args.root).resolve()
    total = 0
    for path in documents(root):
        problems = check_document(path, root)
        for number, target, reason in problems:
            print("{}:{}: {} ({})".format(path.relative_to(root), number, target, reason))
        total += len(problems)
    checked = len(documents(root))
    if total:
        sys.exit("ERROR: {} broken links in {} documents".format(total, checked))
    print("markdown links ok: {} documents".format(checked))


if __name__ == "__main__":
    main()
