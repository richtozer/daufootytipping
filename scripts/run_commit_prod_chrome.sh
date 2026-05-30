#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run_commit_prod_chrome.sh <commit-ish> [app-check-debug-token]

Creates a detached Git worktree in /tmp for the supplied commit and runs the
Flutter web app in Chrome against the production Firebase database.

The App Check debug token is read from, in order:
  1. second argument
  2. WEB_APP_CHECK_DEBUG_TOKEN environment variable
  3. .tmp/firebase_app_check_debug_token
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
commitish="$1"
app_check_token="${2:-${WEB_APP_CHECK_DEBUG_TOKEN:-}}"
local_token_file="$repo_root/.tmp/firebase_app_check_debug_token"

if [[ -z "$app_check_token" && -f "$local_token_file" ]]; then
  app_check_token="$(tr -d '[:space:]' < "$local_token_file")"
fi

if [[ -z "$app_check_token" ]]; then
  echo "Error: no App Check debug token supplied." >&2
  usage >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is not installed or not on PATH." >&2
  exit 1
fi

flutter_bin="${FLUTTER_BIN:-}"
if [[ -z "$flutter_bin" ]]; then
  if command -v flutter >/dev/null 2>&1; then
    flutter_bin="$(command -v flutter)"
  elif [[ -x "$HOME/dev/tooling/flutter/bin/flutter" ]]; then
    flutter_bin="$HOME/dev/tooling/flutter/bin/flutter"
  else
    echo "Error: flutter is not installed or not on PATH." >&2
    echo "Set FLUTTER_BIN=/path/to/flutter and retry." >&2
    exit 1
  fi
fi

cd "$repo_root"
commit="$(git rev-parse --verify "${commitish}^{commit}")"
safe_name="$(printf '%s' "$commitish" | tr -c '[:alnum:]_.-' '-')"
worktree_path="${WORKTREE_PATH:-/tmp/dau-${safe_name}-prod-chrome}"

if [[ -e "$worktree_path" ]]; then
  echo "Error: worktree path already exists: $worktree_path" >&2
  echo "Remove it with: git worktree remove $worktree_path" >&2
  exit 1
fi

git worktree add --detach "$worktree_path" "$commit"

cat >"$worktree_path/web/firebase_app_check_debug_token.local.js" <<EOF
self.FIREBASE_APPCHECK_DEBUG_TOKEN = '$app_check_token';
EOF

cd "$worktree_path"
"$flutter_bin" pub get
"$flutter_bin" run -d chrome --dart-define=USE_FIREBASE_EMULATORS=false
