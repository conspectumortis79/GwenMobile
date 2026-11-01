#!/usr/bin/env python3
import argparse
import sys
from typing import Optional
from pathlib import Path

from coverage_report import report_json, source_line_coverage as file_source_line_coverage

EXCLUDED_SOURCE_FRAGMENTS = ("/GwenMobile/Local/",)


def coverage(target: dict) -> Optional[float]:
    value = target.get("lineCoverage")
    return float(value) * 100 if value is not None else None


def source_line_coverage(bundle: Path, target: dict) -> tuple[int, int]:
    covered = 0
    executable = 0
    for entry in target.get("files", []):
        path = entry.get("path", "")
        if not path or any(fragment in path for fragment in EXCLUDED_SOURCE_FRAGMENTS):
            continue
        file_covered, file_executable, _ = file_source_line_coverage(bundle, path)
        covered += file_covered
        executable += file_executable
    return covered, executable


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result", required=True, help="path to the .xcresult bundle")
    parser.add_argument("--min", type=float, default=100.0, help="minimum line coverage in percent")
    parser.add_argument("--target", default="GwenMobileKit", help="target name prefix to measure")
    parser.add_argument("--source-lines", action="store_true",
                        help="count executable source lines instead of xccov's implicit closures")
    args = parser.parse_args()

    bundle = Path(args.result)
    if not bundle.exists():
        sys.exit(f"ERROR: result bundle {bundle} is missing")

    report = report_json(bundle)
    targets = [t for t in report.get("targets", []) if t.get("name", "").startswith(args.target)]
    if not targets:
        names = ", ".join(t.get("name", "?") for t in report.get("targets", []))
        sys.exit(f"ERROR: no target starting with {args.target!r} in the report (have: {names})")

    worst = None
    for target in targets:
        if args.source_lines:
            covered, executable = source_line_coverage(bundle, target)
            if executable == 0:
                print(f"{target['name']}: no source lines reported")
                continue
            value = 100 * covered / executable
            print(f"{target['name']}: {value:.1f} % source lines ({covered}/{executable})")
        else:
            value = coverage(target)
            if value is None:
                print(f"{target['name']}: no line coverage reported")
                continue
            print(f"{target['name']}: {value:.1f} % lines "
                  f"({target.get('coveredLines', '?')}/{target.get('executableLines', '?')})")
        worst = value if worst is None else min(worst, value)

    if worst is None:
        sys.exit("ERROR: the report holds no line coverage for the app target")
    if worst < args.min:
        sys.exit(f"ERROR: line coverage {worst:.1f} % is below the required {args.min:.1f} %")
    print(f"coverage gate passed: {worst:.1f} % >= {args.min:.1f} %")


if __name__ == "__main__":
    main()
