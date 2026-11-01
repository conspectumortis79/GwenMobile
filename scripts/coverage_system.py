#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path

from coverage_report import report_json, source_line_coverage

MARKER = "/GwenMobileSystem/"


def files(report: dict) -> list:
    found = []
    for target in report.get("targets", []):
        if not target.get("name", "").startswith("GwenMobileSystem"):
            continue
        for entry in target.get("files", []):
            path = entry.get("path", "")
            if MARKER not in path:
                continue
            found.append((path.split(MARKER)[-1], path))
    return sorted(found)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result", required=True, help="path to the .xcresult bundle")
    parser.add_argument("--min", type=float, default=100.0)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()

    bundle = Path(args.result)
    if not bundle.exists():
        sys.exit(f"ERROR: result bundle {bundle} is missing")

    measured = files(report_json(bundle))
    if not measured:
        sys.exit("ERROR: no measured System files in the report")

    covered = 0
    executable = 0
    for relative, path in measured:
        hits, lines, open_lines = source_line_coverage(bundle, path)
        covered += hits
        executable += lines
        if args.list:
            print(f"{hits:6d}/{lines:6d} {relative}")
        if open_lines:
            print(f"  open {len(open_lines):4d}  {relative}")

    value = covered / executable * 100 if executable else 0.0
    print(f"system logic: {value:.2f} % lines ({covered}/{executable}) over {len(measured)} files")
    if value < args.min:
        sys.exit(f"ERROR: System logic coverage {value:.2f} % is below {args.min:.2f} %")
    print(f"coverage system passed: {value:.2f} % >= {args.min:.2f} %")


if __name__ == "__main__":
    main()
