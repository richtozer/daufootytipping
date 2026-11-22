#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"
for port in 19000 19099 19400 19450; do
  if lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Validation port ${port} is busy; leaving that session intact." >&2
    exit 1
  fi
done
mkdir -p emulator/demo/validation
cp config/generated/database.rules.r2.json emulator/demo/validation/database.rules.json
cat > emulator/demo/validation/firebase.json <<'JSON'
{
  "database": { "rules": "database.rules.json" },
  "emulators": {
    "auth": { "host": "127.0.0.1", "port": 19099 },
    "database": { "host": "127.0.0.1", "port": 19000 },
    "hub": { "host": "127.0.0.1", "port": 19400 },
    "logging": { "host": "127.0.0.1", "port": 19450 },
    "ui": { "enabled": false },
    "singleProjectMode": true
  }
}
JSON
# Same project as the demo (so the import's namespace matches), but separate
# ports and only Auth and Database: nothing here touches a running session.
firebase emulators:exec --project dau-footy-tipping-f8a42 \
  --config emulator/demo/validation/firebase.json --only auth,database \
  --import "${repo_root}/emulator/demo/export" \
  "node '${repo_root}/scripts/demo/validate_emulators.mjs'"
