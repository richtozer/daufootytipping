#!/usr/bin/env bash
# Runs the live-score wiring (M5) end to end on LOCAL emulators, inside the same
# operating-system boundary as the rules tests (no network but loopback, no
# credentials):
#
#   history write -> Database emulator -> Functions emulator -> the real TypeScript
#   trigger -> POST with the command secret -> the real Dart worker -> the
#   aggregator (and, for a change to `current`, the existing scoring).
#
# The test reads the emulators' console output (teed to a file) to see what the Dart
# worker logged; the hub's debug log repeats each line and may hold environment values.
#
# It checks that a submission reaches the worker, that shadow mode changes nothing,
# that writing `current` is scored without aggregating again, and that the fixture
# import's clearing of a game's live node is not undone. See
# functions_dart/test/e2e/live_score_wiring_e2e_test.dart.
#
# Uses its own project (demo-dau-rules), ports and throwaway environment files, so
# it neither touches production nor disturbs a running local backend.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

database_port="${WIRING_DATABASE_PORT:-9351}"
functions_port="${WIRING_FUNCTIONS_PORT:-9352}"
hub_port="${WIRING_HUB_PORT:-4451}"
logging_port="${WIRING_LOGGING_PORT:-4551}"
project="demo-dau-rules"
region="asia-southeast1"

# The physical path: the Firebase CLI resolves its project directory that way, and the
# source paths below are relative to it.
stage="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/live-score-wiring.XXXXXX")" && pwd -P)"
trap 'rm -rf "${stage}"' EXIT
mkdir -p "${stage}/env-functions" "${stage}/env-functions-dart"

# A throwaway secret, used only between the two local functions.
secret="$(openssl rand -hex 16)"
origin="http://127.0.0.1:${functions_port}"
# For a demo project the Functions emulator registers its database triggers against a
# namespace named after the project itself (a real project's is "<id>-default-rtdb"),
# so the Dart worker is pointed at that namespace too.
namespace="${project}"
for dir in env-functions env-functions-dart; do
  {
    echo "BACKEND_SCORING_COMMAND_SECRET=${secret}"
    echo "LOCAL_FUNCTIONS_EMULATOR_ORIGIN=${origin}"
    echo "RTDB_EMULATOR_NAMESPACE=${namespace}"
  } > "${stage}/${dir}/.env"
done

echo "Building the TypeScript functions..."
npm --prefix "${repo_root}/functions" run build >/dev/null

relative() {
  node -e 'console.log(require("path").relative(process.argv[1], process.argv[2]))' "$1" "$2"
}

cat > "${stage}/firebase.json" <<JSON
{
  "functions": [
    {
      "runtime": "nodejs22",
      "source": "$(relative "${stage}" "${repo_root}/functions")",
      "configDir": "env-functions",
      "codebase": "default"
    },
    {
      "runtime": "dart3",
      "source": "$(relative "${stage}" "${repo_root}/functions_dart")",
      "configDir": "env-functions-dart",
      "codebase": "dart_functions"
    }
  ],
  "emulators": {
    "database": { "port": ${database_port} },
    "functions": { "port": ${functions_port} },
    "hub": { "port": ${hub_port} },
    "logging": { "port": ${logging_port} },
    "ui": { "enabled": false },
    "singleProjectMode": false
  }
}
JSON

test_command="cd '${repo_root}/functions_dart' && env \
LIVE_SCORE_WIRING_E2E=1 \
LIVE_SCORE_WIRING_NS='${namespace}' \
LIVE_SCORE_WIRING_PROJECT='${project}' \
LIVE_SCORE_WIRING_FUNCTIONS_ORIGIN='${origin}' \
LIVE_SCORE_WIRING_LOG='${stage}/console.log' \
LIVE_SCORE_WIRING_SECRET='${secret}' \
LIVE_SCORE_WIRING_PATIENCE='${LIVE_SCORE_WIRING_PATIENCE:-90}' \
dart test test/e2e/live_score_wiring_e2e_test.dart -j 1 --reporter expanded"

cd "${stage}"
# The boundary starts the command with an empty environment and no stored Firebase
# login, so the experiment that lets the emulator run Dart functions (normally kept
# in the CLI's own settings) is switched on here.
"${repo_root}/rules_test/support/isolated.sh" env FIREBASE_CLI_EXPERIMENTS=dartfunctions \
  firebase emulators:exec --project "${project}" --only database,functions "${test_command}" \
  2>&1 | tee "${stage}/console.log"
