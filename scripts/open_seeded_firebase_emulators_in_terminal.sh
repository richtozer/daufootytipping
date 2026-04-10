#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: open_seeded_firebase_emulators_in_terminal.sh <path-to-rtdb-json>" >&2
  exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This wrapper is intended for macOS Terminal." >&2
  exit 1
fi

json_file="$1"

if [[ ! -f "${json_file}" ]]; then
  echo "RTDB extract not found: ${json_file}" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
launcher_script="${script_dir}/start_seeded_firebase_emulators.sh"
json_file_abs="$(cd "$(dirname "${json_file}")" && pwd)/$(basename "${json_file}")"

osascript - "${repo_root}" "${launcher_script}" "${json_file_abs}" <<'EOF'
on run argv
  set repoRoot to item 1 of argv
  set launcherScript to item 2 of argv
  set jsonFile to item 3 of argv

  tell application "Terminal"
    activate
    do script "cd " & quoted form of repoRoot & " && bash " & quoted form of launcherScript & " " & quoted form of jsonFile
  end tell
end run
EOF
