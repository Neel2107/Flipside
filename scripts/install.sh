#!/bin/sh
# Installs the latest Flipside release into /Applications, replacing any earlier copy.
#
#   curl -fsSL https://raw.githubusercontent.com/Neel2107/Flipside/main/scripts/install.sh | sh
#
# FLIPSIDE_VERSION picks a release other than the latest, FLIPSIDE_APPS_DIR another folder.
set -eu

APPS_DIR="${FLIPSIDE_APPS_DIR:-/Applications}"
VERSION="${FLIPSIDE_VERSION:-latest}"
REPO="${FLIPSIDE_REPO:-Neel2107/Flipside}"
ASSET_NAME="Flipside-app-aarch64-apple-darwin.tar.gz"

fail() {
  echo "error: $*" >&2
  exit 1
}

check_platform() {
  [ "$(uname -s)" = "Darwin" ] || fail "Flipside requires macOS"
  [ "$(uname -m)" = "arm64" ] || fail "Flipside requires an Apple silicon Mac"
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [ "$major" -ge 14 ] || fail "Flipside requires macOS 14 or later"
}

can_write_apps_dir() {
  probe="$APPS_DIR"
  while [ ! -e "$probe" ]; do
    parent="$(dirname "$probe")"
    [ "$parent" = "$probe" ] && return 1
    probe="$parent"
  done
  [ -w "$probe" ]
}

run_privileged() {
  if [ "$(id -u)" -eq 0 ] || can_write_apps_dir; then
    "$@"
  else
    sudo "$@"
  fi
}

release_url() {
  asset="$1"
  if [ "$VERSION" = "latest" ]; then
    echo "https://github.com/$REPO/releases/latest/download/$asset"
    return
  fi

  case "$VERSION" in
    v*) tag="$VERSION" ;;
    *) tag="v$VERSION" ;;
  esac
  echo "https://github.com/$REPO/releases/download/$tag/$asset"
}

verify_archive() {
  sums_url="$(release_url SHA256SUMS)"
  sums_path="$TEMP_DIR/SHA256SUMS"
  status="$(curl -sSL --connect-timeout 10 --retry 2 -o "$sums_path" -w '%{http_code}' "$sums_url" 2>/dev/null)" || status="000"

  [ "$status" = "200" ] || fail "could not download release checksums (HTTP $status)"

  expected="$(awk -v name="$ASSET_NAME" '$2 == name { print $1 }' "$sums_path")"
  [ -n "$expected" ] || fail "$ASSET_NAME is missing from SHA256SUMS"

  actual="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{ print $1 }')"
  [ "$actual" = "$expected" ] || fail "checksum verification failed"
  echo "Verified SHA-256: $actual"
}

check_platform

TEMP_DIR="$(mktemp -d /tmp/flipside-install.XXXXXX)"
DESTINATION="$APPS_DIR/Flipside.app"
STAGED_APP="$APPS_DIR/.Flipside.app.staged-$$"
BACKUP_APP="$APPS_DIR/.Flipside.app.backup-$$"
COMMITTED=0

cleanup() {
  rm -rf "$TEMP_DIR"
  if [ "$COMMITTED" -ne 1 ] && [ -e "$BACKUP_APP" ] && [ ! -e "$DESTINATION" ]; then
    run_privileged mv "$BACKUP_APP" "$DESTINATION" || true
  fi
  run_privileged rm -rf "$STAGED_APP" || true
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# FLIPSIDE_APP_ARCHIVE installs from a local archive instead of downloading one.
ARCHIVE_PATH="${FLIPSIDE_APP_ARCHIVE:-$TEMP_DIR/$ASSET_NAME}"
if [ -z "${FLIPSIDE_APP_ARCHIVE:-}" ]; then
  DOWNLOAD_URL="$(release_url "$ASSET_NAME")"
  echo "Downloading $DOWNLOAD_URL"
  curl -fL --connect-timeout 10 --retry 2 "$DOWNLOAD_URL" -o "$ARCHIVE_PATH"
  verify_archive
fi

tar -xzf "$ARCHIVE_PATH" -C "$TEMP_DIR"
SOURCE_APP="$TEMP_DIR/Flipside.app"
[ -x "$SOURCE_APP/Contents/MacOS/Flipside" ] || fail "archive does not contain Flipside.app"
/usr/bin/codesign --verify --deep --strict "$SOURCE_APP"

# Quit every running copy, including development builds outside the install folder, so the
# new install is the only Flipside in the menu bar. Skipped when installing somewhere else,
# which leaves the copy in /Applications alone.
WAS_RUNNING=0
if [ "$APPS_DIR" = "/Applications" ] && pgrep -x Flipside >/dev/null; then
  WAS_RUNNING=1
  echo "Closing the running copy of Flipside"
  osascript -e 'tell application id "com.flipside.Flipside" to quit' >/dev/null 2>&1 || true
  sleep 1
  pkill -x Flipside 2>/dev/null || true
fi

if [ ! -d "$APPS_DIR" ]; then
  run_privileged install -d -m 0755 "$APPS_DIR"
fi
run_privileged rm -rf "$STAGED_APP" "$BACKUP_APP"
run_privileged ditto "$SOURCE_APP" "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"
run_privileged xattr -dr com.apple.quarantine "$STAGED_APP" 2>/dev/null || true

if [ -e "$DESTINATION" ]; then
  run_privileged mv "$DESTINATION" "$BACKUP_APP"
fi

if ! run_privileged mv "$STAGED_APP" "$DESTINATION"; then
  if [ -e "$BACKUP_APP" ] && [ ! -e "$DESTINATION" ]; then
    run_privileged mv "$BACKUP_APP" "$DESTINATION"
  fi
  fail "installation failed; the previous version was restored"
fi

COMMITTED=1
run_privileged rm -rf "$BACKUP_APP"

echo "Installed Flipside at $DESTINATION"
if [ "$WAS_RUNNING" -eq 1 ]; then
  # An update: put it back in the menu bar where it was.
  open "$DESTINATION"
else
  echo "Launch it with: open \"$DESTINATION\""
fi
