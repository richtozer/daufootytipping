#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: start_seeded_firebase_emulators.sh <path-to-rtdb-json>" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec bash "${script_dir}/start_local_backend.sh" --seed "$1"
