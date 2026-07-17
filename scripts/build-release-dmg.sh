#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Resources/Relay.entitlements"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Relay.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
DMG_NAME="Relay-$VERSION-macos-universal.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
CHECKSUM_PATH="$DMG_PATH.sha256"
WORK_DIR="$(mktemp -d "${TMPDIR%/}/relay-release.XXXXXX")"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
RELAY_BINARY="$BIN_DIR/RelayApp"

ARCHITECTURES="$(lipo -archs "$RELAY_BINARY")"
if [[ "$ARCHITECTURES" != *arm64* || "$ARCHITECTURES" != *x86_64* ]]; then
    printf 'error: expected a universal RelayApp binary, got: %s\n' \
        "$ARCHITECTURES" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
ditto "$RELAY_BINARY" "$APP_DIR/Contents/MacOS/RelayApp"
chmod +x "$APP_DIR/Contents/MacOS/RelayApp"
ditto "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null

# Ad-hoc signing preserves bundle integrity without requiring a paid Apple
# Developer Program membership. Gatekeeper will still require the user to
# approve this unnotarized build once after downloading it.
codesign \
    --force \
    --sign - \
    --entitlements "$ENTITLEMENTS" \
    "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"

PAYLOAD_DIR="$WORK_DIR/payload"
mkdir -p "$PAYLOAD_DIR"
ditto "$APP_DIR" "$PAYLOAD_DIR/Relay.app"
ln -s /Applications "$PAYLOAD_DIR/Applications"

rm -f "$DMG_PATH" "$CHECKSUM_PATH"
hdiutil create \
    -volname "Relay $VERSION" \
    -srcfolder "$PAYLOAD_DIR" \
    -format UDZO \
    -ov \
    "$DMG_PATH"
hdiutil verify "$DMG_PATH"

(
    cd "$DIST_DIR"
    shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)

printf '%s\n%s\n' "$DMG_PATH" "$CHECKSUM_PATH"
