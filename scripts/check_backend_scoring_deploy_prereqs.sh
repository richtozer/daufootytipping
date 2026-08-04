#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

node_env="$repo_root/functions/.env"
dart_env="$repo_root/functions_dart/.env"

missing=0

check_env_file() {
  local file="$1"
  local label="$2"
  shift 2

  if [ ! -f "$file" ]; then
    echo "Missing $label env file: $file"
    missing=1
    return
  fi

  for key in "$@"; do
    if ! grep -Eq "^[[:space:]]*${key}=" "$file"; then
      echo "Missing $key in $label env file: $file"
      missing=1
    fi
  done
}

check_env_file \
  "$dart_env" \
  "Dart functions" \
  BACKEND_SCORING_COMMAND_SECRET \
  APP_BADGE_COMMAND_SECRET

check_env_file \
  "$node_env" \
  "TypeScript functions" \
  BACKEND_SCORING_COMMAND_URL \
  BACKEND_SCORING_COMMAND_SECRET \
  DART_FIXTURE_DOWNLOAD_COMMAND_URL \
  APP_BADGE_COUNT_URL \
  APP_BADGE_COMMAND_SECRET

if [ "$missing" -ne 0 ]; then
  cat <<'EOF'

Backend scoring deploy prerequisites are incomplete.

Expected ignored local files:
- functions_dart/.env with BACKEND_SCORING_COMMAND_SECRET
- functions/.env with BACKEND_SCORING_COMMAND_URL,
  BACKEND_SCORING_COMMAND_SECRET, and DART_FIXTURE_DOWNLOAD_COMMAND_URL

Outstanding tips app badges also require:
- functions_dart/.env with APP_BADGE_COMMAND_SECRET
- functions/.env with APP_BADGE_COUNT_URL and APP_BADGE_COMMAND_SECRET

Do not commit actual secret values.
See docs/backend-scoring-deploy.md for the first-deploy sequence.
See docs/app-badge-deploy.md for the badge rollout sequence.
EOF
  exit 1
fi

echo "Backend scoring deploy prerequisite files are present."
