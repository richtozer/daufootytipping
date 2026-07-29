#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  start_local_backend.sh
  start_local_backend.sh --seed <path-to-rtdb-json>

Starts the complete local backend stack:
- TypeScript Functions build watcher
- Native Dart Functions executable
- Firebase emulators for functions, database, and firestore
- Optional Realtime Database seed from a JSON snapshot

Keep this terminal open while using the local app.
EOF
}

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
}

firebase_cli="/opt/homebrew/bin/firebase"
if [[ ! -x "${firebase_cli}" ]]; then
  firebase_cli="$(command -v firebase || true)"
fi

seed_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --seed)
      if [[ $# -lt 2 ]]; then
        usage >&2
        exit 1
      fi
      seed_file="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "${seed_file}" && ! -f "${seed_file}" ]]; then
  echo "RTDB seed file not found: ${seed_file}" >&2
  exit 1
fi

cleanup_seed_file=false
cleanup_seed_dir=false
case "${seed_file}" in
  "${TMPDIR:-/tmp}"/firebase-rtdb-export-*.json | /private/tmp/firebase-rtdb-export-*.json)
    cleanup_seed_file=true
    cleanup_seed_dir=true
    ;;
esac

require_command npm
require_command curl
require_command dart

if [[ -z "${firebase_cli}" || ! -x "${firebase_cli}" ]]; then
  echo "Required command not found: firebase" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
seed_script="${script_dir}/seed_rtdb_emulator.sh"
stop_script="${script_dir}/stop_firebase_emulators_vscode.sh"
build_dart_script="${script_dir}/build_dart_functions.sh"

emulator_host="${RTDB_EMULATOR_HOST:-127.0.0.1}"
emulator_port="${RTDB_EMULATOR_PORT:-8000}"
readiness_namespace="${RTDB_EMULATOR_NAMESPACE:-dau-footy-tipping-f8a42-default-rtdb}"
startup_timeout_seconds="${EMULATOR_START_TIMEOUT_SECONDS:-90}"
base_url="http://${emulator_host}:${emulator_port}"
functions_origin="${LOCAL_FUNCTIONS_EMULATOR_ORIGIN:-http://127.0.0.1:9229}"
project_id="${GCLOUD_PROJECT:-dau-footy-tipping-f8a42}"
function_region="${FUNCTION_REGION:-asia-southeast1}"

export BACKEND_SCORING_COMMAND_URL="${functions_origin%/}/${project_id}/${function_region}/backend-scoring-command"

if [[ -n "${seed_file}" ]]; then
  seed_file_abs="$(cd "$(dirname "${seed_file}")" && pwd)/$(basename "${seed_file}")"
fi

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
  echo "Local Firebase backend ports are already in use: ${busy_ports[*]}" >&2
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

  if [[ "${cleanup_seed_file}" == true && -f "${seed_file}" ]]; then
    rm -f "${seed_file}" 2>/dev/null || true
  fi

  if [[ "${cleanup_seed_dir}" == true && -n "${seed_file}" ]]; then
    rmdir "$(dirname "${seed_file}")" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

cd "${repo_root}"

echo "Building native Dart Functions executable..."
bash "${build_dart_script}" native

echo "Starting TypeScript Functions build watcher..."
npm --prefix ./functions run build -- -w &
build_watch_pid=$!

echo "Starting Firebase local backend..."
"${firebase_cli}" emulators:start --only functions,database,firestore &
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

if [[ -n "${seed_file}" ]]; then
  echo "Seeding Realtime Database emulator from ${seed_file_abs}..."
  bash "${seed_script}" "${seed_file_abs}"
else
  echo "Realtime Database emulator is running without a seed snapshot."
fi

cat <<EOF

Local backend is running.
- Emulator UI: http://127.0.0.1:4000
- Realtime Database: http://127.0.0.1:8000
- Functions: http://127.0.0.1:9229

Use the VS Code launch "App: Local emulators (selected device)" for the app.
Keep this terminal open. Press Ctrl+C here to stop the backend.
EOF

wait "${emulator_pid}"
