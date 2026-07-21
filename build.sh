#!/bin/bash
# Build Fauxcus.app from the Swift package and ad-hoc sign it.
# `build.sh install` additionally replaces /Applications/Fauxcus.app and relaunches.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Fauxcus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Fauxcus "$APP/Contents/MacOS/Fauxcus"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Fauxcus.icns Resources/MenuBarIcon.png "Resources/MenuBarIcon@2x.png" \
   Resources/PrismIcon.png "Resources/PrismIcon@2x.png" "$APP/Contents/Resources/"

# Prefer a real Apple Development identity (stable across rebuilds, so TCC
# permissions like Reminders stick); fall back to ad-hoc if none exists.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "Signed with: $IDENTITY"
else
    codesign --force -s - "$APP"
    echo "Signed ad-hoc (no Apple Development identity found)"
fi

echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x Fauxcus || true
    for _ in $(seq 1 20); do
        pgrep -x Fauxcus >/dev/null || break
        sleep 0.25
    done
    rm -rf /Applications/Fauxcus.app
    ditto "$APP" /Applications/Fauxcus.app
    open /Applications/Fauxcus.app
    echo "Installed and launched /Applications/Fauxcus.app"
fi

