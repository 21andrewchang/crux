#!/bin/zsh
# Pull Crux's data off the phone, or put a backup back.
#
# The store is small and holds everything written — sessions, attempts, notes,
# check-ins, timestamps. The videos are gigabytes and change far less often, so
# they are opt-in rather than paid for on every run.
#
#   scripts/backup.sh              store only, seconds
#   scripts/backup.sh --full       store + attempt videos, minutes
#   scripts/backup.sh --list       what backups exist
#   scripts/backup.sh --restore <dir>   put one back on the phone
#
# Run it before anything that touches an @Model type. Adding a property with a
# default migrates cleanly; renaming or removing one may not, and a store that
# will not open is a crash on launch that usually ends in deleting the app.
set -euo pipefail

DEVICE_ID="B912DCD3-C247-58B4-98AA-A014D4C521B4"
BUNDLE_ID="com.627b8d.Crux"
ROOT="$HOME/CruxBackups"
CONTAINER="Library/Application Support"

pull() { xcrun devicectl device copy from --device "$DEVICE_ID" --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" --source "$1" --destination "$2" >/dev/null 2>&1; }
push() { xcrun devicectl device copy to --device "$DEVICE_ID" --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" --source "$1" --destination "$2" >/dev/null 2>&1; }

# What is actually in a store, so a backup reports what it caught rather than only
# that it ran. A run that comes back with zero sessions is the interesting case.
summarize() {
  local store="$1/default.store"
  [[ -f "$store" ]] || { echo "   (no store found)"; return; }
  local s a
  s=$(sqlite3 "$store" "select count(*) from ZCLIMBSESSION;" 2>/dev/null || echo "?")
  a=$(sqlite3 "$store" "select count(*) from ZATTEMPT;" 2>/dev/null || echo "?")
  echo "   $s sessions, $a attempts"
  [[ -d "$1/Attempts" ]] && echo "   $(ls "$1/Attempts" | wc -l | tr -d ' ') media files, $(du -sh "$1/Attempts" | cut -f1)"
}

case "${1:-}" in
  --list)
    [[ -d "$ROOT" ]] || { echo "No backups yet."; exit 0; }
    for d in "$ROOT"/*(N/); do echo "${d:t}"; summarize "$d"; done
    ;;

  --restore)
    DIR="${2:?usage: scripts/backup.sh --restore <dir-or-name>}"
    [[ -d "$DIR" ]] || DIR="$ROOT/$DIR"
    [[ -d "$DIR" ]] || { echo "No such backup: $DIR"; exit 1; }
    echo "==> Restoring $DIR"
    summarize "$DIR"
    # Force-quit first: a live app holds the store open and can flush its own copy
    # back over the one being written underneath it.
    echo "==> Force-quit Crux on the phone, then press return."
    read -r
    for f in default.store default.store-wal default.store-shm; do
      [[ -f "$DIR/$f" ]] && { echo "    $f"; push "$DIR/$f" "$CONTAINER/$f"; }
    done
    [[ -d "$DIR/Attempts" ]] && { echo "    Attempts (this is the slow one)"; push "$DIR/Attempts" "$CONTAINER/Attempts"; }
    xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID" >/dev/null
    echo "==> Restored and relaunched."
    ;;

  *)
    FULL=0
    [[ "${1:-}" == "--full" ]] && FULL=1
    STAMP=$(date +%Y-%m-%d-%H%M%S)
    DEST="$ROOT/$STAMP"
    mkdir -p "$DEST"
    echo "==> Backing up to $DEST"
    # The store itself is not optional. Without this the whole run is `|| true`:
    # an unplugged or locked phone fails every copy, leaves an empty directory
    # behind, and exits 0 — a backup that looks taken and holds nothing.
    if ! pull "$CONTAINER/default.store" "$DEST/default.store"; then
      rmdir "$DEST" 2>/dev/null || true
      echo "!! Could not read the store off the phone — nothing was backed up." >&2
      echo "   Check it is plugged in, unlocked, and trusts this Mac." >&2
      exit 1
    fi
    # These two may genuinely not exist: SwiftData checkpoints the WAL on a clean
    # close, and there is nothing to copy when it has.
    for f in default.store-wal default.store-shm; do
      pull "$CONTAINER/$f" "$DEST/$f" || true
    done
    if (( FULL )); then
      echo "    pulling videos, this takes a few minutes"
      pull "$CONTAINER/Attempts" "$DEST/Attempts" || true
    fi
    summarize "$DEST"
    (( FULL )) || echo "   (videos not included — run with --full for those)"
    ;;
esac
