#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/relay_process_helpers.sh"

TEST_DIR="$(mktemp -d)"
TARGET_DIR="$TEST_DIR/target bundle"
UNRELATED_DIR="$TEST_DIR/unrelated bundle"
TARGET_BINARY="$TARGET_DIR/RelayApp"
UNRELATED_BINARY="$UNRELATED_DIR/RelayApp"

cleanup() {
  if [[ -n "${TARGET_PID:-}" ]]; then
    kill "$TARGET_PID" >/dev/null 2>&1 || true
    wait "$TARGET_PID" 2>/dev/null || true
  fi
  if [[ -n "${UNRELATED_PID:-}" ]]; then
    kill "$UNRELATED_PID" >/dev/null 2>&1 || true
    wait "$UNRELATED_PID" 2>/dev/null || true
  fi
  if [[ -n "${SECOND_UNRELATED_PID:-}" ]]; then
    kill "$SECOND_UNRELATED_PID" >/dev/null 2>&1 || true
    wait "$SECOND_UNRELATED_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$TARGET_DIR" "$UNRELATED_DIR"
cp /bin/sleep "$TARGET_BINARY"
cp /bin/sleep "$UNRELATED_BINARY"
codesign --force --sign - "$TARGET_BINARY" >/dev/null
codesign --force --sign - "$UNRELATED_BINARY" >/dev/null

"$TARGET_BINARY" 30 &
TARGET_PID=$!
"$UNRELATED_BINARY" 30 &
UNRELATED_PID=$!

MATCHES="$(relay_process_pids_for_executable "$TARGET_BINARY")"
if [[ "$MATCHES" != "$TARGET_PID" ]]; then
  echo "expected only target PID $TARGET_PID, got: $MATCHES" >&2
  exit 1
fi

relay_terminate_processes_for_executable "$TARGET_BINARY" 20 0.05

if [[ -n "$(relay_process_pids_for_executable "$TARGET_BINARY")" ]]; then
  echo "target process survived scoped termination" >&2
  exit 1
fi
wait "$TARGET_PID" 2>/dev/null || true
TARGET_PID=""
if ! kill -0 "$UNRELATED_PID" >/dev/null 2>&1; then
  echo "unrelated same-basename process was terminated" >&2
  exit 1
fi

set +e
relay_verify_exactly_one_process "$TARGET_BINARY" 1 0.01 \
  >/dev/null 2>&1
TARGET_VERIFY_STATUS=$?
set -e
if (( TARGET_VERIFY_STATUS == 0 )); then
  echo "unrelated process incorrectly satisfied target verification" >&2
  exit 1
fi

VERIFIED_PID="$(
  relay_verify_exactly_one_process "$UNRELATED_BINARY" 1 0.01
)"
if [[ "$VERIFIED_PID" != "$UNRELATED_PID" ]]; then
  echo "expected unrelated PID $UNRELATED_PID, got: $VERIFIED_PID" >&2
  exit 1
fi

"$UNRELATED_BINARY" 30 &
SECOND_UNRELATED_PID=$!
set +e
relay_verify_exactly_one_process "$UNRELATED_BINARY" 1 0.01 \
  >/dev/null 2>&1
MULTIPLE_VERIFY_STATUS=$?
set -e
if (( MULTIPLE_VERIFY_STATUS == 0 )); then
  echo "multiple exact-path processes incorrectly passed verification" >&2
  exit 1
fi

FINAL_SCAN_STATE="$TEST_DIR/final-scan-count"
printf '0\n' > "$FINAL_SCAN_STATE"
(
  trap - EXIT
  relay_process_pids_for_executable() {
    local count
    count="$(<"$FINAL_SCAN_STATE")"
    count=$((count + 1))
    printf '%s\n' "$count" > "$FINAL_SCAN_STATE"
    if (( count == 3 )); then
      return 0
    fi
    printf '%s\n' "4242"
  }
  kill() { :; }
  sleep() { :; }
  relay_terminate_processes_for_executable "/final-scan/RelayApp" 1 0
)

VERIFY_FINAL_SCAN_STATE="$TEST_DIR/verify-final-scan-count"
printf '0\n' > "$VERIFY_FINAL_SCAN_STATE"
VERIFIED_FINAL_PID="$(
  relay_process_pids_for_executable() {
    local count
    count="$(<"$VERIFY_FINAL_SCAN_STATE")"
    count=$((count + 1))
    printf '%s\n' "$count" > "$VERIFY_FINAL_SCAN_STATE"
    if (( count == 2 )); then
      printf '%s\n' "4343"
    fi
  }
  sleep() { :; }
  relay_verify_exactly_one_process "/final-scan/RelayApp" 1 0
)"
if [[ "$VERIFIED_FINAL_PID" != "4343" ]]; then
  echo "final verification scan did not observe timeout-edge process" >&2
  exit 1
fi

echo "exact-path process matching passed"
