#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$ROOT_DIR/dist/sparkle-test"
BASELINE_DIR="$TEST_DIR/baseline"
SERVER_DIR="$TEST_DIR/server"
BASE_VERSION="${SPARKLE_TEST_BASE_VERSION:-1.0.2}"
BASE_BUILD="${SPARKLE_TEST_BASE_BUILD:-3}"
UPDATE_VERSION="${SPARKLE_TEST_UPDATE_VERSION:-1.0.3}"
UPDATE_BUILD="${SPARKLE_TEST_UPDATE_BUILD:-4}"
PORT="${SPARKLE_TEST_PORT:-8765}"
FEED_URL="http://127.0.0.1:$PORT/appcast.xml"
UPDATE_ARCHIVE="$SERVER_DIR/Relay-$UPDATE_VERSION.zip"

rm -rf "$TEST_DIR"
mkdir -p "$BASELINE_DIR" "$SERVER_DIR"

RELAY_VERSION="$BASE_VERSION" \
RELAY_BUILD_NUMBER="$BASE_BUILD" \
RELAY_SPARKLE_FEED_URL="$FEED_URL" \
    "$ROOT_DIR/scripts/build-local-app.sh" >/dev/null
ditto "$ROOT_DIR/dist/Relay.app" "$BASELINE_DIR/Relay.app"

RELAY_VERSION="$UPDATE_VERSION" \
RELAY_BUILD_NUMBER="$UPDATE_BUILD" \
RELAY_SPARKLE_FEED_URL="$FEED_URL" \
    "$ROOT_DIR/scripts/build-local-app.sh" >/dev/null
ditto \
    -c \
    -k \
    --sequesterRsrc \
    --keepParent \
    "$ROOT_DIR/dist/Relay.app" \
    "$UPDATE_ARCHIVE"

SPARKLE_ARCHIVE_PATH="$UPDATE_ARCHIVE" \
SPARKLE_APPCAST_PATH="$SERVER_DIR/appcast.xml" \
SPARKLE_DOWNLOAD_URL_PREFIX="http://127.0.0.1:$PORT/" \
RELAY_VERSION="$UPDATE_VERSION" \
    "$ROOT_DIR/scripts/generate-appcast.sh" >/dev/null

printf 'Baseline app: %s\n' "$BASELINE_DIR/Relay.app"
printf 'Update feed: %s\n' "$SERVER_DIR/appcast.xml"
printf '\nStart the local feed server:\n'
printf '  cd %q && python3 -m http.server %q\n' "$SERVER_DIR" "$PORT"
printf '\nThen launch the baseline app in another terminal:\n'
printf '  open %q\n' "$BASELINE_DIR/Relay.app"
