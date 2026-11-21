#!/bin/bash
set -euo pipefail
UDID="${1:-}"
if [ -z "$UDID" ]; then
    UDID="$(python3 -c '
import json, subprocess, sys
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True))
devices = [d for items in data.get("devices", {}).values() for d in items if d.get("isAvailable") and "iPhone" in d.get("name", "")]
booted = [d["udid"] for d in devices if d.get("state") == "Booted"]
print(booted[0] if booted else (devices[0]["udid"] if devices else ""))
')"
fi
if [ -z "$UDID" ]; then
    echo "ERROR: no available iPhone simulator found — pass a simulator UDID as argument" >&2
    exit 1
fi
BUNDLE="com.mortis.gwenmobile"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
for service in calendar contacts photos-add photos media-library microphone reminders location; do
    xcrun simctl privacy "$UDID" grant "$service" "$BUNDLE"
done
xcrun simctl shutdown "$UDID"
DB="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/TCC/TCC.db"
sqlite3 "$DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, flags) VALUES ('kTCCServiceSpeechRecognition', '$BUNDLE', 0, 2, 4, 1, 0);"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl spawn "$UDID" launchctl setenv GWEN_LIVE_PERMISSIONS 1
echo "Berechtigungen fuer $BUNDLE gesetzt"
