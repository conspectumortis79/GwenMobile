#!/bin/bash
set -euo pipefail
UDID="${1:-9DE41529-F896-43B4-810A-41523208ED58}"
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
