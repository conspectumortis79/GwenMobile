#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import xcode_teams
from report import fail

REPO = Path(__file__).resolve().parent.parent
CONFIG = REPO / "Config" / "Signing.xcconfig"
EXAMPLE = REPO / "Config" / "Signing.xcconfig.example"
TEAM_LINE = re.compile(r"^DEVELOPMENT_TEAM[ \t]*=[ \t]*(\S*)[ \t]*$", re.MULTILINE)
TEAM_PATTERN = re.compile(r"^[A-Z0-9]{10}$")


def text_of(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.is_file() else ""


def label(path: Path) -> str:
    try:
        return str(path.relative_to(REPO))
    except ValueError:
        return str(path)


def current_team(path: Path = CONFIG) -> str:
    match = TEAM_LINE.search(text_of(path))
    return match.group(1) if match else ""


def team_line(team: str) -> str:
    return f"DEVELOPMENT_TEAM = {team}".rstrip()


def write_team(team: str, path: Path = CONFIG) -> None:
    line = team_line(team)
    body = text_of(path) or text_of(EXAMPLE)
    if TEAM_LINE.search(body):
        body = TEAM_LINE.sub(lambda match: line, body)
    else:
        body = line
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        path.write_text(body if body.endswith("\n") else body + "\n", encoding="utf-8")
    except OSError as exc:
        fail(f"cannot write {label(path)}: {exc}")


def ensure(bundle_id: str = "", detector=xcode_teams.detect, path: Path = CONFIG) -> str:
    team = current_team(path)
    if team:
        return team
    found = [item for item in detector(bundle_id) if TEAM_PATTERN.match(item)]
    write_team(found[0] if found else "", path)
    if found:
        if len(found) > 1:
            print(f"Signing: {len(found)} teams on this Mac ({', '.join(found)}), "
                  f"using {found[0]} — edit {label(path)} to pick another.")
        print(f"Signing: team {found[0]} written to {label(path)}")
    else:
        print(f"Signing: no team id found on this Mac — {label(path)} stays empty, "
              "set DEVELOPMENT_TEAM there or pick the team in Xcode.")
    return found[0] if found else ""


def main() -> int:
    parser = argparse.ArgumentParser(description="keeps the local signing team in Config/Signing.xcconfig")
    parser.add_argument("--show", action="store_true", help="print the team in use")
    parser.add_argument("--set", metavar="TEAM", help="write this 10 character team id")
    parser.add_argument("--detect", action="store_true", help="list the teams this Mac can offer")
    parser.add_argument("--bundle", default="com.mortis.gwenmobile",
                        help="bundle id whose profile decides the team")
    args = parser.parse_args()
    if args.show:
        print(current_team() or "-")
    elif args.detect:
        print("\n".join(xcode_teams.detect(args.bundle)) or "-")
    elif args.set:
        if not TEAM_PATTERN.match(args.set):
            fail(f"'{args.set}' is not a 10 character team id")
        write_team(args.set)
        print(f"{CONFIG.name}: team {args.set}")
    else:
        print(f"{CONFIG.name}: team {ensure(args.bundle) or '-'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
