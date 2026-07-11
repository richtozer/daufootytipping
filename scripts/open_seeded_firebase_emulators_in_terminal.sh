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
staged_dir="$(mktemp -d "${TMPDIR:-/tmp}/firebase-rtdb-export-XXXXXX")"
staged_json_file="${staged_dir}/$(basename "${json_file_abs}")"

osascript - "${json_file_abs}" "${staged_dir}" <<'EOF'
on run argv
  set sourcePath to item 1 of argv
  set destinationDir to item 2 of argv

  tell application "Finder"
    set sourceFile to POSIX file sourcePath as alias
    set destinationFolder to POSIX file destinationDir as alias
    duplicate sourceFile to destinationFolder
  end tell
end run
EOF

osascript - "${repo_root}" "${launcher_script}" "${staged_json_file}" <<'EOF'
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
