#!/usr/bin/env python3
import sys

from coverage_report import (coverage_parser, enforce_minimum, load_report,
                             source_line_coverage, targets_matching)

MARKER = "/GwenMobileSystem/"


def files(report: dict) -> list:
    found = []
    for target in targets_matching(report, "GwenMobileFeatureCore"):
        for entry in target.get("files", []):
            path = entry.get("path", "")
            if MARKER not in path:
                continue
            found.append((path.split(MARKER)[-1], path))
    return sorted(found)


def main() -> None:
    args = coverage_parser(with_list=True).parse_args()

    bundle, report = load_report(args.result)
    measured = files(report)
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
    enforce_minimum("system", value, args.min)


if __name__ == "__main__":
    main()
