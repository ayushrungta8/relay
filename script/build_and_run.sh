#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Relay"
PROCESS_NAME="RelayApp"
BUNDLE_ID="com.ayushrungta.relay"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$PROCESS_NAME"

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true

CONFIGURATION=release "$ROOT_DIR/scripts/build-local-app.sh"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_process() {
  local attempts=0
  while (( attempts < 20 )); do
    if pgrep -x "$PROCESS_NAME" >/dev/null; then
      pgrep -x "$PROCESS_NAME"
      return 0
    fi
    sleep 0.25
    attempts=$((attempts + 1))
  done
  echo "error: $PROCESS_NAME did not start from $APP_BUNDLE" >&2
  return 1
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact \
      --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact \
      --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    verify_process
    ;;
esac
