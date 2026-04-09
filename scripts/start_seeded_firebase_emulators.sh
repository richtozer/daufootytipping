#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: start_seeded_firebase_emulators.sh <path-to-rtdb-json>

Starts the local Firebase emulators, waits for the Realtime Database emulator
to become available, and seeds it using the supplied JSON extract.
EOF
}

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

json_file="$1"

if [[ ! -f "${json_file}" ]]; then
  echo "RTDB extract not found: ${json_file}" >&2
  exit 1
fi

require_command npm
require_command firebase
require_command curl

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
seed_script="${script_dir}/seed_rtdb_emulator.sh"
stop_script="${script_dir}/stop_firebase_emulators_vscode.sh"
json_file_abs="$(cd "$(dirname "${json_file}")" && pwd)/$(basename "${json_file}")"

emulator_host="${RTDB_EMULATOR_HOST:-127.0.0.1}"
emulator_port="${RTDB_EMULATOR_PORT:-8000}"
readiness_namespace="${RTDB_EMULATOR_NAMESPACE:-dau-footy-tipping-f8a42}"
startup_timeout_seconds="${EMULATOR_START_TIMEOUT_SECONDS:-60}"
base_url="http://${emulator_host}:${emulator_port}"

check_busy_port() {
  local port="$1"

  command -v lsof >/dev/null 2>&1 || return 1
  lsof -nP -a -u "$(id -un)" -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
}

declare -a busy_ports=()

for port in 4000 4400 4500 6001 8000 8081 8099 9150 9229; do
  if check_busy_port "${port}"; then
    busy_ports+=("${port}")
  fi
done

if [[ "${#busy_ports[@]}" -gt 0 ]]; then
  echo "Firebase emulator ports are already in use: ${busy_ports[*]}" >&2
  echo "Stop the current session first with ${stop_script}" >&2
  exit 1
fi

build_watch_pid=""
emulator_pid=""

cleanup() {
  trap - EXIT INT TERM

  if [[ -n "${emulator_pid}" ]] && kill -0 "${emulator_pid}" 2>/dev/null; then
    kill "${emulator_pid}" 2>/dev/null || true
    wait "${emulator_pid}" 2>/dev/null || true
  fi

  if [[ -n "${build_watch_pid}" ]] && kill -0 "${build_watch_pid}" 2>/dev/null; then
    kill "${build_watch_pid}" 2>/dev/null || true
    wait "${build_watch_pid}" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

cd "${repo_root}"

echo "Starting Firebase Functions TypeScript watch..."
npm --prefix ./functions run build -- -w &
build_watch_pid=$!

echo "Starting Firebase emulators..."
firebase emulators:start --inspect-functions &
emulator_pid=$!

echo "Waiting for Realtime Database emulator on ${emulator_host}:${emulator_port}..."
ready="false"

for ((second = 1; second <= startup_timeout_seconds; second++)); do
  if curl --silent --output /dev/null --max-time 1 \
    "${base_url}/.json?ns=${readiness_namespace}&shallow=true"; then
    ready="true"
    break
  fi

  sleep 1
done

if [[ "${ready}" != "true" ]]; then
  echo "Timed out waiting for the RTDB emulator to start." >&2
  exit 1
fi

echo "Seeding Realtime Database emulator from ${json_file_abs}..."
bash "${seed_script}" "${json_file_abs}"
echo "Firebase emulators are running with the seeded RTDB extract."
echo "Keep this Terminal window open while you use the local environment."

wait "${emulator_pid}"
