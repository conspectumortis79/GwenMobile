#!/usr/bin/env python3
import sys
from pathlib import Path
from typing import Optional

from coverage_report import (coverage_parser, enforce_minimum, load_report,
                             source_line_coverage as file_source_line_coverage,
                             targets_matching)

EXCLUDED_SOURCE_FRAGMENTS = ("/GwenMobile/Local/",)


def coverage(target: dict) -> Optional[float]:
    value = target.get("lineCoverage")
    return float(value) * 100 if value is not None else None


def source_line_coverage(bundle: Path, target: dict,
                         include: list[str], exclude: list[str]) -> tuple[int, int]:
    covered = 0
    executable = 0
    for entry in target.get("files", []):
        path = entry.get("path", "")
        if not path or any(fragment in path for fragment in EXCLUDED_SOURCE_FRAGMENTS):
            continue
        if any(fragment in path for fragment in exclude):
            continue
        if include and not any(fragment in path for fragment in include):
            continue
        file_covered, file_executable, _ = file_source_line_coverage(bundle, path)
        covered += file_covered
        executable += file_executable
    return covered, executable


def main() -> None:
    parser = coverage_parser()
    parser.add_argument("--target", default="GwenMobileKit", help="target name prefix to measure")
    parser.add_argument("--source-lines", action="store_true",
                        help="count executable source lines instead of xccov's implicit closures")
    parser.add_argument("--include-source-fragment", action="append", default=[],
                        help="only measure source paths containing this fragment; repeatable")
    parser.add_argument("--exclude-source-fragment", action="append", default=[],
                        help="skip source paths containing this fragment; repeatable")
    args = parser.parse_args()

    bundle, report = load_report(args.result)
    targets = targets_matching(report, args.target)
    if not targets:
        names = ", ".join(t.get("name", "?") for t in report.get("targets", []))
        sys.exit(f"ERROR: no target starting with {args.target!r} in the report (have: {names})")

    worst = None
    for target in targets:
        if args.source_lines:
            covered, executable = source_line_coverage(bundle, target,
                                                       args.include_source_fragment,
                                                       args.exclude_source_fragment)
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
    enforce_minimum("gate", worst, args.min, precision=1)


if __name__ == "__main__":
    main()
