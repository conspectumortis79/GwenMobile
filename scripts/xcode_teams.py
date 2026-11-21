#!/usr/bin/env python3
import argparse
import datetime
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import signing_reader
from signing_reader import SECURITY

TEAM_PATTERN = re.compile(r"^[A-Z0-9]{10}$")
TEAM_TIMEOUT = 60


def output(args: list, feed: str = "") -> str:
    try:
        done = subprocess.run([str(item) for item in args], input=feed, capture_output=True,
                              text=True, errors="replace", timeout=TEAM_TIMEOUT)
    except (OSError, subprocess.SubprocessError):
        return ""
    return done.stdout if done.returncode == 0 else ""


def still_valid(expires) -> bool:
    if not isinstance(expires, datetime.datetime):
        return True
    return expires > datetime.datetime.now(expires.tzinfo)


def bundle_matches(identifier: str, bundle_id: str) -> bool:
    without_team = identifier.split(".", 1)[1] if "." in identifier else ""
    return without_team in (bundle_id, f"maccatalyst.{bundle_id}")


def profile_team(plist: dict, bundle_id: str) -> str:
    if not still_valid(plist.get("ExpirationDate")):
        return ""
    entitlements = plist.get("Entitlements") or {}
    identifier = str(entitlements.get("application-identifier") or "")
    if bundle_id and not bundle_matches(identifier, bundle_id):
        return ""
    for team in plist.get("TeamIdentifier") or []:
        if TEAM_PATTERN.match(str(team)):
            return str(team)
    return ""


def from_profiles(bundle_id: str = "") -> list:
    found = []
    for profile in signing_reader.paths_of():
        team = profile_team(signing_reader.decode(profile), bundle_id)
        if team and team not in found:
            found.append(team)
    return found


def from_certificates() -> list:
    pem = output([SECURITY, "find-certificate", "-a", "-c", "Apple Development", "-p"])
    if not pem:
        return []
    subject = output([shutil.which("openssl") or "/usr/bin/openssl", "x509", "-noout",
                      "-subject", "-nameopt", "multiline", "-inform", "PEM"], feed=pem)
    found = []
    for match in re.finditer(r"organizationalUnitName\s*=\s*(\S+)", subject):
        team = match.group(1)
        if TEAM_PATTERN.match(team) and team not in found:
            found.append(team)
    return found


def teams_in_xcode_accounts(preferences: dict) -> list:
    teams = preferences.get("IDEProvisioningTeamByIdentifier") or {}
    found = []
    for entry in teams.values() if isinstance(teams, dict) else ():
        for record in entry if isinstance(entry, list) else (entry,):
            if not isinstance(record, dict):
                continue
            team = str(record.get("teamID") or "")
            if TEAM_PATTERN.match(team) and team not in found:
                found.append(team)
    return found


def from_xcode_accounts() -> list:
    xml = output(["/usr/bin/defaults", "export", "com.apple.dt.Xcode", "-"])
    if not xml:
        return []
    try:
        preferences = plistlib.loads(xml.encode("utf-8"))
    except (ValueError, SyntaxError):
        return []
    return teams_in_xcode_accounts(preferences if isinstance(preferences, dict) else {})


def detect(bundle_id: str = "") -> list:
    teams = from_profiles(bundle_id)
    if teams or not bundle_id:
        return teams
    return from_profiles() or from_certificates() or from_xcode_accounts()


def main() -> int:
    parser = argparse.ArgumentParser(description="lists the signing teams this Mac can offer")
    parser.add_argument("--bundle", default="", help="only teams holding a profile for this bundle id")
    parser.add_argument("--sources", action="store_true", help="show each probe result on its own")
    args = parser.parse_args()
    if args.sources:
        for label, teams in (("profile of this app", from_profiles(args.bundle)),
                             ("any profile", from_profiles()),
                             ("keychain certificate", from_certificates()),
                             ("Xcode account", from_xcode_accounts())):
            print(f"{label}: {', '.join(teams) if teams else '-'}")
    teams = detect(args.bundle)
    if not teams:
        print("no team found on this Mac", file=sys.stderr)
        return 1
    print("\n".join(teams))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
