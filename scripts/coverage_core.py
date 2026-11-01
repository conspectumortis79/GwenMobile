#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path

from coverage_report import report_json

FOLDERS = ("Routing", "Storage", "Code", "Shared", "Calls", "Contacts", "Places", "Translation", "Scans")

EXCLUDED = (
    "Code/CodeBlockView.swift",
    "Code/CodeFileExporting.swift",
    "Code/CodeFilePresenting.swift",
    "Shared/CardChrome.swift",
    "Shared/DayTabPicker.swift",
    "Shared/HTTP.swift",
    "Shared/Presenter.swift",
    "Shared/ScaledTypography.swift",
    "Shared/ShareSession.swift",
    "Shared/SheetToolbar.swift",
    "Storage/DeleteAllConfirmation.swift",
    "Storage/UndoBar.swift",
    "Calls/CellularDialer.swift",
    "Calls/SystemURLOpener.swift",
    "Contacts/LiveContactDirectory.swift",
    "Places/PlaceSearch.swift",
    "Routing/ToolRouterSteps.swift",
    "Scans/DocumentScanner.swift",
    "Translation/OnDeviceSession.swift",
    "Translation/TranslationRunner.swift",
)


def core_files(report: dict) -> list:
    found = []
    marker = "/GwenMobile/GwenMobile/"
    for target in report.get("targets", []):
        if not target.get("name", "").startswith("GwenMobileKit"):
            continue
        for entry in target.get("files", []):
            path = entry.get("path", "")
            if marker not in path:
                continue
            relative = path.split(marker)[-1]
            if relative.split("/")[0] not in FOLDERS:
                continue
            if relative in EXCLUDED:
                continue
            found.append((relative, entry))
    return sorted(found)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result", required=True, help="path to the .xcresult bundle")
    parser.add_argument("--min", type=float, default=100.0, help="required line coverage in percent")
    parser.add_argument("--list", action="store_true", help="list every core file with its coverage")
    args = parser.parse_args()

    bundle = Path(args.result)
    if not bundle.exists():
        sys.exit(f"ERROR: result bundle {bundle} is missing")

    files = core_files(report_json(bundle))
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
    if value < args.min:
        sys.exit(f"ERROR: logic core coverage {value:.2f} % is below the required {args.min:.2f} %")
    print(f"coverage core passed: {value:.2f} % >= {args.min:.2f} %")


if __name__ == "__main__":
    main()
