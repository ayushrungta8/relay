#!/usr/bin/env bash

relay_process_pids_for_executable() {
  local expected_executable="$1"
  local pid
  local executable

  while IFS= read -r process_line; do
    read -r pid executable <<<"$process_line"
    if [[ "$executable" == "$expected_executable" ]]; then
      printf '%s\n' "$pid"
    fi
  done < <(LC_ALL=C /bin/ps -ww -axo pid=,comm=)
}

relay_terminate_processes_for_executable() {
  local expected_executable="$1"
  local max_attempts="${2:-20}"
  local delay="${3:-0.25}"
  local attempt
  local pid
  local -a pids=()
  local -a remaining=()

  while IFS= read -r pid; do
    if [[ -n "$pid" ]]; then
      pids+=("$pid")
    fi
  done < <(relay_process_pids_for_executable "$expected_executable")

  if (( ${#pids[@]} == 0 )); then
    return 0
  fi

  kill -TERM "${pids[@]}" 2>/dev/null || true

  for ((attempt = 0; attempt < max_attempts; attempt++)); do
    remaining=()
    while IFS= read -r pid; do
      if [[ -n "$pid" ]]; then
        remaining+=("$pid")
      fi
    done < <(relay_process_pids_for_executable "$expected_executable")
    if (( ${#remaining[@]} == 0 )); then
      return 0
    fi
    sleep "$delay"
  done

  remaining=()
  while IFS= read -r pid; do
    if [[ -n "$pid" ]]; then
      remaining+=("$pid")
    fi
  done < <(relay_process_pids_for_executable "$expected_executable")
  if (( ${#remaining[@]} == 0 )); then
    return 0
  fi

  printf 'error: processes for %s survived termination: %s\n' \
    "$expected_executable" "${remaining[*]}" >&2
  return 1
}

relay_verify_exactly_one_process() {
  local expected_executable="$1"
  local max_attempts="${2:-20}"
  local delay="${3:-0.25}"
  local attempt
  local pid
  local -a pids=()

  for ((attempt = 0; attempt < max_attempts; attempt++)); do
    pids=()
    while IFS= read -r pid; do
      if [[ -n "$pid" ]]; then
        pids+=("$pid")
      fi
    done < <(relay_process_pids_for_executable "$expected_executable")

    case "${#pids[@]}" in
      0)
        sleep "$delay"
        ;;
      1)
        printf '%s\n' "${pids[0]}"
        return 0
        ;;
      *)
        printf 'error: expected one process for %s, found %s: %s\n' \
          "$expected_executable" "${#pids[@]}" "${pids[*]}" >&2
        return 1
        ;;
    esac
  done

  pids=()
  while IFS= read -r pid; do
    if [[ -n "$pid" ]]; then
      pids+=("$pid")
    fi
  done < <(relay_process_pids_for_executable "$expected_executable")
  case "${#pids[@]}" in
    0)
      printf 'error: expected one process for %s, found none\n' \
        "$expected_executable" >&2
      return 1
      ;;
    1)
      printf '%s\n' "${pids[0]}"
      return 0
      ;;
    *)
      printf 'error: expected one process for %s, found %s: %s\n' \
        "$expected_executable" "${#pids[@]}" "${pids[*]}" >&2
      return 1
      ;;
  esac
}
