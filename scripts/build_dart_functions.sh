#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build_dart_functions.sh <native|linux>

Builds the Dart Cloud Functions manifest and the ignored bin/server executable.
Use native for local emulator testing and linux before deploying to Cloud Run.
EOF
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

target="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

cd "${repo_root}/functions_dart"

dart run build_runner build

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
