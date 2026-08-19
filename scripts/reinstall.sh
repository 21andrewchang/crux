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
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$PROJECT_DIR"

# Signing needs the login keychain, and an SSH login cannot reach it: its security
# session is not the one the keychain was unlocked in, so codesign dies there with
# errSecInternalComponent no matter how the keychain is unlocked. The tmux server is
# in that session — it was started from the console — so when the keychain is out of
# reach here, hand the build to tmux and read its log back. Nothing changes when the
# keychain is already reachable, which is every run started from the Mac itself.
if [[ -z "${CRUX_INNER:-}" ]] \
  && ! security show-keychain-info "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 \
  && tmux ls >/dev/null 2>&1; then
  LOG="$(mktemp -t crux-reinstall)"
  STATUS="$LOG.status"
  echo "==> Keychain is out of reach from this session; building inside tmux"
  tmux new-session -d -c "$PROJECT_DIR" -s "crux-reinstall-$$" \
    "CRUX_INNER=1 ${(q)SELF} >${(q)LOG} 2>&1; echo \$? >${(q)STATUS}"
  # 20 minutes is well past a clean build; past that something is wedged and the
  # log says more than another minute of waiting would.
  for _ in {1..600}; do
    [[ -f "$STATUS" ]] && break
    sleep 2
  done
  cat "$LOG"
  [[ -f "$STATUS" ]] || { echo "==> Timed out waiting on the tmux build"; exit 1; }
  exit "$(cat "$STATUS")"
fi
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
