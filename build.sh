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
codesign --force -s - "$APP"

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

