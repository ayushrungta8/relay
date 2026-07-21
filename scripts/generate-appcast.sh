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
MOUNT_DIR="$WORK_DIR/mount"

cleanup() {
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
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
if [[ -f "$ARCHIVE_PATH.sha256" ]]; then
    (
        cd "$(dirname "$ARCHIVE_PATH")"
        shasum -a 256 -c "$(basename "$ARCHIVE_PATH").sha256"
    )
fi

mkdir -p "$MOUNT_DIR"
hdiutil attach \
    -readonly \
    -nobrowse \
    -mountpoint "$MOUNT_DIR" \
    "$ARCHIVE_PATH" >/dev/null
ARCHIVE_INFO_PLIST="$MOUNT_DIR/Relay.app/Contents/Info.plist"
if [[ ! -f "$ARCHIVE_INFO_PLIST" ]]; then
    printf 'error: update archive does not contain Relay.app\n' >&2
    exit 1
fi
ARCHIVE_VERSION="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "$ARCHIVE_INFO_PLIST"
)"
ARCHIVE_BUILD="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleVersion' \
        "$ARCHIVE_INFO_PLIST"
)"
if [[ "$ARCHIVE_VERSION" != "$VERSION" ]]; then
    printf 'error: archive is version %s, but appcast target is %s\n' \
        "$ARCHIVE_VERSION" "$VERSION" >&2
    exit 1
fi
if [[ -n "${RELAY_BUILD_NUMBER:-}" && "$ARCHIVE_BUILD" != "$RELAY_BUILD_NUMBER" ]]; then
    printf 'error: archive build is %s, but appcast target is %s\n' \
        "$ARCHIVE_BUILD" "$RELAY_BUILD_NUMBER" >&2
    exit 1
fi
hdiutil detach "$MOUNT_DIR" >/dev/null

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
