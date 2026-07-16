#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Relay"
PROCESS_NAME="RelayApp"
BUNDLE_ID="com.ayushrungta.relay"

ROOT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$PROCESS_NAME"
source "$ROOT_DIR/script/relay_process_helpers.sh"

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

relay_terminate_processes_for_executable "$APP_BINARY"

CONFIGURATION=release "$ROOT_DIR/scripts/build-local-app.sh"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
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
    relay_verify_exactly_one_process "$APP_BINARY"
    ;;
esac
