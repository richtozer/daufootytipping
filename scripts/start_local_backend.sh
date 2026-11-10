#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  start_local_backend.sh
  start_local_backend.sh --seed <path-to-rtdb-json>
  start_local_backend.sh --demo [--android]

Starts the complete local backend stack:
- TypeScript Functions build watcher
- Native Dart Functions executable
- Firebase emulators for functions, database, and firestore
  (plus auth with --demo; other sessions use real Firebase Auth)
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
demo=false
demo_avatar_host="localhost"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --demo)
      demo=true
      shift
      ;;
    --android)
      demo_avatar_host="10.0.2.2"
      shift
      ;;
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

if [[ "${demo}" == true && -n "${seed_file}" ]]; then
  echo "Use either --demo or --seed, not both." >&2
  exit 1
fi
if [[ "${demo}" == false && "${demo_avatar_host}" != localhost ]]; then
  echo "--android is only used with --demo." >&2
  exit 1
fi

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

ports=(4000 4400 4500 6001 8000 8081 8099 9150 9229)
if [[ "${demo}" == true ]]; then
  ports+=(8765)
fi
for port in "${ports[@]}"; do
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
demo_assets_pid=""

cleanup() {
  trap - EXIT INT TERM

  if [[ -n "${demo_assets_pid}" ]] && kill -0 "${demo_assets_pid}" 2>/dev/null; then
    kill "${demo_assets_pid}" 2>/dev/null || true
    wait "${demo_assets_pid}" 2>/dev/null || true
  fi

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

if [[ "${demo}" == true ]]; then
  echo "Generating the fictional competition relative to now..."
  node scripts/demo/generate.mjs --avatar-host "${demo_avatar_host}"
  node scripts/demo/serve.mjs &
  demo_assets_pid=$!
fi

echo "Building native Dart Functions executable..."
bash "${build_dart_script}" native

echo "Starting TypeScript Functions build watcher..."
npm --prefix ./functions run build -- -w &
build_watch_pid=$!

emulators="functions,database,firestore"
declare -a config_args=()
declare -a env_args=()
if [[ "${demo}" == true ]]; then
  emulators="auth,${emulators}"
  # The demo runs on the R2 rules. The CLI applies the configured rules once
  # every emulator is up, so the demo gets its own copy of firebase.json that
  # names them. The copy sits beside firebase.json so its paths still resolve.
  demo_config="${repo_root}/firebase.demo.json"
  node -e '
    const fs = require("fs");
    const config = JSON.parse(fs.readFileSync("firebase.json", "utf8"));
    config.database.rules = "config/generated/database.rules.r2.json";
    fs.writeFileSync(process.argv[1], JSON.stringify(config, null, 2) + "\n");
  ' "${demo_config}"
  # The generated competition and its Auth accounts are imported at startup,
  # before the Functions emulator registers triggers, so loading fires none.
  config_args=(--config "${demo_config}" --import "${repo_root}/emulator/demo/export")
  # Auth emulator tokens are unsigned, so the Dart callables must skip token
  # verification to accept them. Set for this process only, never exported:
  # auth_bypass_guard.dart refuses it outside the Functions emulator, and
  # deploy-functions.sh refuses to deploy while it is set.
  env_args=(env 'FIREBASE_DEBUG_FEATURES={"skipTokenVerification":true}')
fi

echo "Starting Firebase local backend..."
${env_args[@]+"${env_args[@]}"} "${firebase_cli}" emulators:start ${config_args[@]+"${config_args[@]}"} --only "${emulators}" &
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

if [[ "${demo}" == true ]]; then
  echo "Demo competition and Auth accounts imported from emulator/demo/export."
  echo "Sign in as daisy@demo.example.test; the password is in emulator/demo/credentials.json."
elif [[ -n "${seed_file}" ]]; then
  echo "Seeding Realtime Database emulator from ${seed_file_abs}..."
  bash "${seed_script}" "${seed_file_abs}"
else
  echo "Realtime Database emulator is running without a seed snapshot."
fi

launch_name="App: Local emulators (selected device)"
auth_line=""
if [[ "${demo}" == true ]]; then
  launch_name="App: Demo emulators (selected device)"
  auth_line="- Authentication: http://127.0.0.1:8099"
fi

cat <<EOF

Local backend is running.
- Emulator UI: http://127.0.0.1:4000
- Realtime Database: http://127.0.0.1:8000
- Functions: http://127.0.0.1:9229
${auth_line}

Use the VS Code launch "${launch_name}" for the app.
Keep this terminal open. Press Ctrl+C here to stop the backend.
EOF

wait "${emulator_pid}"
