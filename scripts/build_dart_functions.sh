#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build_dart_functions.sh <native|linux> [--skip-manifest]

Builds the Dart Cloud Functions manifest and the ignored bin/server executable.
Use native for local emulator testing and linux before deploying to Cloud Run.

--skip-manifest compiles without running build_runner, for callers that have
already generated and verified functions.yaml (see deploy-functions.sh).
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 1
fi

target="$1"
skip_manifest=false
if [[ $# -eq 2 ]]; then
  if [[ "$2" == "--skip-manifest" ]]; then
    skip_manifest=true
  else
    usage >&2
    exit 1
  fi
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

cd "${repo_root}/functions_dart"

if [[ "${skip_manifest}" == false ]]; then
  dart run build_runner build
fi

case "${target}" in
  native)
    dart compile exe bin/server.dart -o bin/server
    ;;
  linux)
    dart compile exe bin/server.dart -o bin/server --target-os linux --target-arch x64
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
