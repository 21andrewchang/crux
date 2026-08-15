#!/bin/zsh
# Build Crux on this Mac and install it on Andrew's iPhone, wherever it is plugged in.
#
# If the phone is plugged into this machine, installs directly. Otherwise, if
# REMOTE_HOST is reachable over SSH, ships the .app there and installs through
# that machine's devicectl (phone plugged into the MacBook while working over SSH).
set -euo pipefail

DEVICE_ID="B912DCD3-C247-58B4-98AA-A014D4C521B4"
BUNDLE_ID="com.andrewchang.Crux"
REMOTE_HOST="${REMOTE_HOST:-andrewchang@100.92.210.96}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$PROJECT_DIR"
xcodebuild -project Climb.xcodeproj -scheme Climb \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates build

APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/Climb-*/Build/Products/Debug-iphoneos/Crux.app | head -1)

device_state() {
  xcrun devicectl list devices 2>/dev/null | grep "$DEVICE_ID" | awk '{print $4}'
}

if [[ "$(device_state)" == (connected|available) ]]; then
  echo "==> Installing locally"
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
  xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"
else
  echo "==> Phone not here; installing via $REMOTE_HOST"
  rsync -a --delete "$APP" "$REMOTE_HOST":/tmp/crux-install/
  ssh "$REMOTE_HOST" "
    xcrun devicectl device install app --device $DEVICE_ID /tmp/crux-install/Crux.app &&
    xcrun devicectl device process launch --device $DEVICE_ID $BUNDLE_ID
  "
fi
echo "==> Done"
