#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Resources/Relay.entitlements"
APP_ICON="$ROOT_DIR/Resources/Relay.icns"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Relay.app"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
VERSION="${RELAY_VERSION:-$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "$INFO_PLIST"
)}"
BUILD_NUMBER="${RELAY_BUILD_NUMBER:-$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleVersion' \
        "$INFO_PLIST"
)}"
DMG_NAME="Relay-macos-universal.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
CHECKSUM_PATH="$DMG_PATH.sha256"
WORK_DIR="$(mktemp -d "${TMPDIR%/}/relay-release.XXXXXX")"
RW_DMG_PATH="$WORK_DIR/Relay-rw.dmg"
MOUNT_DIR="$WORK_DIR/mount"
SIGNING_IDENTITY_NAME="OpenClicky Local Development"
EXPECTED_SIGNING_HASH="3DB137FA7E71AF2AD5FBE04774D711AD5295496D"
SIGNING_KEYCHAIN="$HOME/Library/Keychains/OpenClickyDev.keychain-db"

if [[ -n "${RELAY_VERSION:-}" && -z "${RELAY_BUILD_NUMBER:-}" ]] ||
        [[ -z "${RELAY_VERSION:-}" && -n "${RELAY_BUILD_NUMBER:-}" ]]; then
    printf 'error: set RELAY_VERSION and RELAY_BUILD_NUMBER together\n' >&2
    exit 1
fi

cleanup() {
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
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
mkdir -p \
    "$APP_DIR/Contents/MacOS" \
    "$APP_DIR/Contents/Resources" \
    "$FRAMEWORKS_DIR"
ditto "$RELAY_BINARY" "$APP_DIR/Contents/MacOS/RelayApp"
ditto "$BIN_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/Sparkle.framework"
chmod +x "$APP_DIR/Contents/MacOS/RelayApp"
ditto "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
ditto "$APP_ICON" "$APP_DIR/Contents/Resources/Relay.icns"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $VERSION" \
    "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleVersion $BUILD_NUMBER" \
    "$APP_DIR/Contents/Info.plist"
if [[ -n "${RELAY_SPARKLE_FEED_URL:-}" ]]; then
    /usr/libexec/PlistBuddy \
        -c "Set :SUFeedURL $RELAY_SPARKLE_FEED_URL" \
        "$APP_DIR/Contents/Info.plist"
fi
plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
PACKAGED_VERSION="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "$APP_DIR/Contents/Info.plist"
)"
PACKAGED_BUILD="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleVersion' \
        "$APP_DIR/Contents/Info.plist"
)"
if [[ "$PACKAGED_VERSION" != "$VERSION" || "$PACKAGED_BUILD" != "$BUILD_NUMBER" ]]; then
    printf 'error: packaged version mismatch; expected %s (%s), got %s (%s)\n' \
        "$VERSION" "$BUILD_NUMBER" "$PACKAGED_VERSION" "$PACKAGED_BUILD" >&2
    exit 1
fi

IDENTITY_SEARCH_ARGS=()
CODESIGN_KEYCHAIN_ARGS=()
if [[ -f "$SIGNING_KEYCHAIN" ]]; then
    security unlock-keychain -p "" "$SIGNING_KEYCHAIN"
    IDENTITY_SEARCH_ARGS=("$SIGNING_KEYCHAIN")
    CODESIGN_KEYCHAIN_ARGS=(--keychain "$SIGNING_KEYCHAIN")
fi
VALID_IDENTITIES="$(
    security find-identity -v -p codesigning \
        "${IDENTITY_SEARCH_ARGS[@]}"
)"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(
        printf '%s\n' "$VALID_IDENTITIES" |
            awk -v quoted="\"$SIGNING_IDENTITY_NAME\"" \
                'index($0, quoted) { print $2; exit }'
    )"
fi
if [[ -z "$SIGN_IDENTITY" ]] &&
        printf '%s\n' "$VALID_IDENTITIES" |
            awk -v hash="$EXPECTED_SIGNING_HASH" \
                '$2 == hash { found = 1 } END { exit !found }'; then
    SIGN_IDENTITY="$EXPECTED_SIGNING_HASH"
fi
if [[ -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" ]]; then
    printf 'error: valid "%s" code-signing identity not found\n' \
        "$SIGNING_IDENTITY_NAME" >&2
    exit 1
fi

RESOLVED_SIGNING_LINE="$(
    printf '%s\n' "$VALID_IDENTITIES" |
        awk -v identity="$SIGN_IDENTITY" \
            '$2 == identity || index($0, "\"" identity "\"") { print; exit }'
)"
if [[ -z "$RESOLVED_SIGNING_LINE" ]]; then
    printf 'error: requested code-signing identity is not valid: %s\n' \
        "$SIGN_IDENTITY" >&2
    exit 1
fi
RESOLVED_SIGNING_HASH="$(
    printf '%s\n' "$RESOLVED_SIGNING_LINE" | awk '{ print $2 }'
)"
if [[ "$RESOLVED_SIGNING_HASH" != "$EXPECTED_SIGNING_HASH" ]]; then
    printf 'error: Relay signing identity drifted; expected %s, got %s\n' \
        "$EXPECTED_SIGNING_HASH" "$RESOLVED_SIGNING_HASH" >&2
    exit 1
fi

printf 'Using identity: %s (%s)\n' \
    "$SIGNING_IDENTITY_NAME" "$RESOLVED_SIGNING_HASH"
codesign \
    --force \
    --sign "$RESOLVED_SIGNING_HASH" \
    "${CODESIGN_KEYCHAIN_ARGS[@]}" \
    --timestamp=none \
    --entitlements "$ENTITLEMENTS" \
    "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1)"
if printf '%s\n' "$SIGNATURE_DETAILS" | grep -q 'Signature=adhoc'; then
    printf 'error: Relay.app is still ad-hoc signed\n' >&2
    exit 1
fi
if ! printf '%s\n' "$SIGNATURE_DETAILS" |
        grep -F "Authority=$SIGNING_IDENTITY_NAME" >/dev/null; then
    printf 'error: Relay.app was not signed by %s\n' \
        "$SIGNING_IDENTITY_NAME" >&2
    exit 1
fi

PAYLOAD_DIR="$WORK_DIR/payload"
mkdir -p "$PAYLOAD_DIR"
ditto "$APP_DIR" "$PAYLOAD_DIR/Relay.app"
ln -s /Applications "$PAYLOAD_DIR/Applications"
ditto "$APP_ICON" "$PAYLOAD_DIR/.VolumeIcon.icns"

rm -f "$DMG_PATH" "$CHECKSUM_PATH"
hdiutil create \
    -volname "Relay $VERSION" \
    -srcfolder "$PAYLOAD_DIR" \
    -format UDRW \
    -ov \
    "$RW_DMG_PATH"

mkdir -p "$MOUNT_DIR"
hdiutil attach \
    -readwrite \
    -nobrowse \
    -mountpoint "$MOUNT_DIR" \
    "$RW_DMG_PATH" >/dev/null
xcrun SetFile -a C "$MOUNT_DIR"
hdiutil detach "$MOUNT_DIR" >/dev/null

hdiutil convert \
    "$RW_DMG_PATH" \
    -format UDZO \
    -ov \
    -o "$DMG_PATH"
hdiutil verify "$DMG_PATH"

(
    cd "$DIST_DIR"
    shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)

printf '%s\n%s\n' "$DMG_PATH" "$CHECKSUM_PATH"
