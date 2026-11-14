#!/usr/bin/env python3
import json
import re
import subprocess
import sys
from pathlib import Path


def report_json(bundle: Path) -> dict:
    proc = subprocess.run(["xcrun", "xccov", "view", "--report", "--json", str(bundle)],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        sys.exit(f"ERROR: xccov failed for {bundle}:\n{proc.stderr.strip()}")
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as error:
        sys.exit(f"ERROR: xccov did not return JSON: {error}")


def source_line_coverage(bundle: Path, path: str) -> tuple[int, int, list[int]]:
    proc = subprocess.run(["xcrun", "xccov", "view", "--archive", "--file", path, str(bundle)],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        return 0, 0, []
    source = []
    try:
        source = Path(path).read_text(errors="replace").splitlines()
    except OSError:
        pass
    covered = 0
    executable = 0
    open_lines = []
    for line in proc.stdout.splitlines():
        match = re.match(r"\s*(\d+):\s*(\d+)", line)
        if not match:
            continue
        number = int(match.group(1))
        text = source[number - 1].strip() if 1 <= number <= len(source) else ""
        if text in ("}", "});", "]", ")", "};"):
            continue
        executable += 1
        if int(match.group(2)) > 0:
            covered += 1
        else:
            open_lines.append(number)
    return covered, executable, open_lines
