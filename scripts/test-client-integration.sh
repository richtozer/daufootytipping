#!/usr/bin/env bash
# Runs the client integration tests (test/integration) on LOCAL emulators, inside
# the same operating-system boundary as the rules tests (no network but loopback,
# no credentials):
#
#   the app's own client classes  ->  the REAL Dart callable server (compiled from
#   functions_dart/bin/server.dart, started in emulator mode)  ->  a Realtime
#   Database emulator running the REAL rulesets (config/generated/*.json).
#
# The same emulator is what the cutover rehearsal (test/integration/cutover_rehearsal_test.dart)
# runs the real mode, purge and restore tools against.
#
# It covers what fakes cannot: that what the client sends is what the server
# accepts, that the server's errors are what the client reads, and that the data the
# callables write is data the rulesets accept, before and after the cutover to R2.
# What it cannot cover is the device: the Firebase Auth, Messaging and Database
# plugins, Apple and Google sign-in. See DESIGN-database-rules-phase4.md, section 8.
#
# Usage: scripts/test-client-integration.sh [flutter test arguments...]
#   (default: every test under test/integration)
#
# Ports can be moved with CLIENT_IT_DATABASE_PORT, CLIENT_IT_SERVER_PORT,
# CLIENT_IT_HUB_PORT and CLIENT_IT_LOGGING_PORT. It uses its own project
# (demo-dau-rules), so it neither touches production nor a local backend.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

database_port="${CLIENT_IT_DATABASE_PORT:-9361}"
server_port="${CLIENT_IT_SERVER_PORT:-9362}"
hub_port="${CLIENT_IT_HUB_PORT:-4461}"
logging_port="${CLIENT_IT_LOGGING_PORT:-4561}"
project="demo-dau-rules"

# The physical path: the Firebase CLI resolves its project directory that way.
stage="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/client-integration.XXXXXX")" && pwd -P)"
trap 'rm -rf "${stage}"' EXIT

echo "Compiling the Dart functions server and the identity tools..."
for program in server identity_mode identity_purge identity_restore; do
  (cd "${repo_root}/functions_dart" && dart compile exe "bin/${program}.dart" -o "${stage}/${program}" >/dev/null)
done

cat > "${stage}/firebase.json" <<JSON
{
  "database": { "rules": "${repo_root}/config/generated/database.rules.r1-compat.json" },
  "emulators": {
    "database": { "port": ${database_port} },
    "hub": { "port": ${hub_port} },
    "logging": { "port": ${logging_port} },
    "ui": { "enabled": false },
    "singleProjectMode": true
  }
}
JSON

if [ "$#" -eq 0 ]; then
  set -- test/integration
fi
test_args=""
for arg in "$@"; do
  test_args="${test_args} $(printf '%q' "${arg}")"
done

# Runs inside the boundary, with the Database emulator up. The server is started in
# emulator mode (FUNCTIONS_EMULATOR=true is what lets it accept unsigned tokens; it
# refuses to start with those switches anywhere else).
cat > "${stage}/run.sh" <<RUN
#!/usr/bin/env bash
set -uo pipefail
export FUNCTIONS_EMULATOR=true
export PORT=${server_port}
export RTDB_EMULATOR_NAMESPACE=${project}
export GCLOUD_PROJECT=${project}
export FIREBASE_DEBUG_FEATURES='{"skipTokenVerification":true}'
"${stage}/server" > "${stage}/server.log" 2>&1 &
server_pid=\$!
trap 'kill "\${server_pid}" 2>/dev/null || true' EXIT
ready=0
for _ in \$(seq 1 60); do
  if [ "\$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${server_port}/nothing")" != "000" ]; then
    ready=1
    break
  fi
  sleep 0.5
done
if [ "\${ready}" != "1" ]; then
  echo "The Dart server did not start:" >&2
  cat "${stage}/server.log" >&2
  exit 1
fi
cd "${repo_root}"
export INTEGRATION_SERVER_URL="http://127.0.0.1:${server_port}"
# The identity tools, as the owner runs them; with the emulator's host variable set (it is) they
# read and write the emulator instead of going through the Firebase CLI to a project.
export IDENTITY_MODE_TOOL="${stage}/identity_mode"
export IDENTITY_PURGE_TOOL="${stage}/identity_purge"
export IDENTITY_RESTORE_TOOL="${stage}/identity_restore"
flutter test --no-pub --suppress-analytics --concurrency=1 ${test_args}
status=\$?
if [ "\${status}" != "0" ]; then
  echo "--- server log (last lines) ---" >&2
  tail -n 40 "${stage}/server.log" | cut -c1-240 >&2
fi
exit \${status}
RUN
chmod +x "${stage}/run.sh"

"${repo_root}/rules_test/support/isolated.sh" \
  firebase emulators:exec --config "${stage}/firebase.json" --only database \
  --project "${project}" "${stage}/run.sh"
