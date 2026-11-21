#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


def coverage_parser(with_list: bool = False) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result", required=True, help="path to the .xcresult bundle")
    parser.add_argument("--min", type=float, default=100.0, help="required line coverage in percent")
    if with_list:
        parser.add_argument("--list", action="store_true", help="list every measured file with its coverage")
    return parser


def targets_matching(report: dict, prefix: str) -> list[dict]:
    return [target for target in report.get("targets", []) if target.get("name", "").startswith(prefix)]


def enforce_minimum(label: str, value: float, minimum: float, precision: int = 2) -> None:
    if value < minimum:
        sys.exit(f"ERROR: {label} coverage {value:.{precision}f} % is below the required {minimum:.{precision}f} %")
    print(f"coverage {label} passed: {value:.{precision}f} % >= {minimum:.{precision}f} %")


def load_report(result_path: str) -> tuple[Path, dict]:
    bundle = Path(result_path)
    if not bundle.exists():
        sys.exit(f"ERROR: result bundle {bundle} is missing")
    return bundle, report_json(bundle)


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
