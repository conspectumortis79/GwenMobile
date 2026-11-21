#!/usr/bin/env python3
import sys

from coverage_report import coverage_parser, enforce_minimum, load_report, targets_matching

FOLDERS = ("Shared", "Storage")


def core_files(report: dict) -> list:
    found = []
    markers = tuple(f"/GwenMobile/{folder}/" for folder in FOLDERS)
    for target in targets_matching(report, "GwenMobileKit"):
        for entry in target.get("files", []):
            path = entry.get("path", "")
            for folder, marker in zip(FOLDERS, markers):
                if marker in path:
                    relative = f"{folder}/{path.split(marker)[-1]}"
                    found.append((relative, entry))
                    break
    return sorted(found)


def main() -> None:
    args = coverage_parser(with_list=True).parse_args()

    _, report = load_report(args.result)
    files = core_files(report)
    if not files:
        sys.exit("ERROR: no core files found in the report")

    covered = sum(entry.get("coveredLines", 0) for _, entry in files)
    executable = sum(entry.get("executableLines", 0) for _, entry in files)
    value = covered / executable * 100 if executable else 0.0

    if args.list:
        for relative, entry in files:
            lines = entry.get("executableLines", 0)
            hits = entry.get("coveredLines", 0)
            print(f"{hits:6d}/{lines:6d} {hits / lines * 100 if lines else 100:6.1f}%  {relative}")
        print()

    print(f"logic core: {value:.2f} % lines ({covered}/{executable}) over {len(files)} files")
    below = [(rel, entry) for rel, entry in files if entry.get("coveredLines", 0) < entry.get("executableLines", 0)]
    for relative, entry in below:
        lines = entry.get("executableLines", 0)
        hits = entry.get("coveredLines", 0)
        print(f"  open {lines - hits:4d}  {relative}")
    enforce_minimum("core", value, args.min)


if __name__ == "__main__":
    main()
