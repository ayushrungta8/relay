#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE_PATH="${SPARKLE_ARCHIVE_PATH:-$DIST_DIR/Relay-macos-universal.dmg}"
APPCAST_PATH="${SPARKLE_APPCAST_PATH:-$ROOT_DIR/appcast.xml}"
VERSION="${RELAY_VERSION:-$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "$INFO_PLIST"
)}"
DOWNLOAD_URL_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/ayushrungta8/relay/releases/download/v$VERSION/}"
GENERATE_APPCAST="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
WORK_DIR="$(mktemp -d "${TMPDIR%/}/relay-appcast.XXXXXX")"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ ! -f "$ARCHIVE_PATH" ]]; then
    printf 'error: update archive not found: %s\n' "$ARCHIVE_PATH" >&2
    exit 1
fi
if [[ ! -x "$GENERATE_APPCAST" ]]; then
    printf 'error: Sparkle tools are unavailable; run swift package resolve first\n' >&2
    exit 1
fi

ditto "$ARCHIVE_PATH" "$WORK_DIR/$(basename "$ARCHIVE_PATH")"
if [[ -f "$APPCAST_PATH" ]]; then
    ditto "$APPCAST_PATH" "$WORK_DIR/appcast.xml"
fi

"$GENERATE_APPCAST" \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    --link "https://github.com/ayushrungta8/relay" \
    --maximum-versions 5 \
    --maximum-deltas 0 \
    "$WORK_DIR"

ditto "$WORK_DIR/appcast.xml" "$APPCAST_PATH"
printf '%s\n' "$APPCAST_PATH"
