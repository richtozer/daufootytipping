#!/usr/bin/env bash
# Starts everything the smoke test needs, ALL inside the OS boundary (no network except loopback, no
# credentials): the Auth + Database + Firestore emulators, the synthetic seed with the R1 rules, a
# static server for the built app, and a static server for the local Firebase JS bundles.
# Stop with down.sh. Build the app first with prepare_app.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
iso="$here/../support/isolated.sh"
work="$here/.work"
app="$work/app/build/web"
firebase_js="$here/sdk/node_modules/firebase"
variant="${1:-r1}"   # r1 | r1-recovery
# shellcheck source=procs.sh
source "$here/procs.sh"

[ -d "$app" ] || { echo "Build the app first: $here/prepare_app.sh" >&2; exit 1; }
mkdir -p "$work/pw"

# The browser loads the Firebase JS SDK from Google's CDN, which the OS boundary refuses, so the same
# files are served locally. They must be EXACTLY the version the released build asks for (the version
# its firebase_core_web plugin defaults to, recorded by prepare_app.sh), or the app would be running
# against an SDK it was never released with. Refuse to start otherwise.
wanted="$(cat "$work/sdk-version" 2>/dev/null || true)"
[ -n "$wanted" ] || { echo "No $work/sdk-version: run prepare_app.sh first." >&2; exit 1; }
have="$(node -p "require('$firebase_js/package.json').version" 2>/dev/null || true)"
if [ "$have" != "$wanted" ]; then
  echo "The release build uses Firebase JS SDK $wanted but smoke/sdk has '${have:-nothing}'." >&2
  echo "Install the matching version (this is the only step that needs the network, run it yourself):" >&2
  echo "  (cd $here/sdk && npm install --save-exact firebase@$wanted)" >&2
  exit 1
fi
echo "Firebase JS SDK: $have (matches the release build)"

# A per-run marker on the browser's command line, so the harness can find exactly the browser it
# launched (and no other Playwright browser) if closing the session ever leaves one behind.
marker="smoke-$(date +%s)-$$"
printf '%s\n' "$marker" > "$work/browser-marker"

# Headless Chromium for the contained browser (no Chrome sandbox: it cannot nest inside the OS boundary).
shell="$(ls -d "$HOME"/Library/Caches/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-mac-arm64/chrome-headless-shell | tail -1)"
cat > "$work/pw/cli.config.json" <<JSON
{
  "browser": {
    "browserName": "chromium",
    "isolated": true,
    "launchOptions": {
      "headless": true,
      "executablePath": "$shell",
      "args": ["--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage", "--smoke-browser-marker=$marker"]
    }
  }
}
JSON

# Every background process is a recorded process-group leader (procs.sh), so down.sh can stop exactly
# these and nothing else; stdio is detached so this script returns even when piped.
cd "$here"
spawn emulators "$work/emulators.log" "$iso" firebase emulators:start --only auth,database,firestore --project demo-dau-rules
for _ in $(seq 1 60); do
  if curl -s -m 2 -o /dev/null http://127.0.0.1:8000/ && curl -s -m 2 -o /dev/null http://127.0.0.1:8099/; then break; fi
  sleep 2
done
curl -s -m 2 -o /dev/null http://127.0.0.1:8000/ || { echo "emulators did not start; see $work/emulators.log" >&2; exit 1; }

(cd "$here" && "$iso" env NODE_OPTIONS=--import=../support/no_production.mjs \
  FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:8099 FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:8000 GCLOUD_PROJECT=demo-dau-rules \
  node seed.mjs $([ "$variant" = r1-recovery ] && echo --recovery))

spawn app_server "$work/app_server.log" "$iso" python3 -m http.server 18090 --bind 127.0.0.1 --directory "$app"
spawn sdk_server "$work/fbjs_server.log" "$iso" python3 -m http.server 18091 --bind 127.0.0.1 --directory "$firebase_js"
sleep 2
curl -s -m 3 -o /dev/null -w "app served: http %{http_code}\n" http://127.0.0.1:18090/
echo "smoke environment is up (rules variant: $variant)"
