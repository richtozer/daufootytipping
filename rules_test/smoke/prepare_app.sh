#!/usr/bin/env bash
# Builds the RELEASED app (default: 1.4.0 build 712) for the smoke test, in a DISPOSABLE git worktree
# under rules_test/smoke/.work (your working tree is never touched), with ONLY the startup wiring
# patched (patch_app.py). Everything runs inside the OS boundary: no network, no credentials.
#
# `flutter pub get --offline` uses the local pub cache; if a package is missing it fails (closed)
# rather than reaching the network. `--no-web-resources-cdn` bundles the engine locally so the build
# needs no CDN.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
iso="$here/../support/isolated.sh"
tag="${SMOKE_TAG:-ios-testflight-build-712}"
work="$here/.work"
app="$work/app"

mkdir -p "$work"
if [ -d "$app" ]; then
  git -C "$repo" worktree remove --force "$app"
fi
git -C "$repo" worktree add --detach "$app" "$tag"
python3 "$here/patch_app.py" "$app"

cd "$app"
"$iso" flutter pub get --offline

# Record the Firebase JS SDK version this build loads at runtime: the one its firebase_core_web plugin
# defaults to. up.sh refuses to start unless the locally served SDK is exactly this version.
python3 - "$app" "$work/sdk-version" <<'PY'
import json, os, re, sys, urllib.parse
app, out = sys.argv[1], sys.argv[2]
cfg = json.load(open(app + '/.dart_tool/package_config.json'))
pkg = next(p for p in cfg['packages'] if p['name'] == 'firebase_core_web')
uri = pkg['rootUri']
root = urllib.parse.unquote(uri.removeprefix('file://')) if uri.startswith('file://') else os.path.normpath(os.path.join(app, '.dart_tool', urllib.parse.unquote(uri)))
src = open(root.rstrip('/') + '/' + pkg.get('packageUri', 'lib/') + 'src/firebase_sdk_version.dart').read()
version = re.search(r"supportedFirebaseJsSdkVersion\s*=\s*'([\d.]+)'", src).group(1)
open(out, 'w').write(version + '\n')
print('firebase_core_web defaults to Firebase JS SDK ' + version)
PY
"$iso" flutter build web --no-pub --release --no-web-resources-cdn \
  --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=FIREBASE_EMULATOR_HOST=localhost

version="$(grep -m1 '^version:' pubspec.yaml)"
echo "built $version from $tag into $app/build/web"
