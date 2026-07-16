#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_DIR="$ROOT_DIR/dist/Relay.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SIGNING_IDENTITY_NAME="OpenClicky Local Development"
EXPECTED_SIGNING_HASH="3DB137FA7E71AF2AD5FBE04774D711AD5295496D"
SIGNING_KEYCHAIN="$HOME/Library/Keychains/OpenClickyDev.keychain-db"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_DIR/RelayApp" "$MACOS_DIR/RelayApp"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

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
    --entitlements "$ROOT_DIR/Resources/Relay.entitlements" \
    "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"

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

echo "$APP_DIR"
