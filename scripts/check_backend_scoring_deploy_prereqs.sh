#!/usr/bin/env bash
set -euo pipefail

# Validates the local .env files needed to deploy the backend scoring functions.
#
# Takes an optional target: all (default) | dart | default
#
# The TypeScript wrappers need the DEPLOYED Dart endpoint URLs, which do not
# exist until the Dart worker has been deployed once. Checking those URLs when
# only the Dart codebase is being deployed would make the first deploy
# impossible, so URL requirements are scoped to the target.
# See docs/backend-scoring-deploy.md for the first-deploy sequence.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

target="${1:-all}"
case "$target" in
  all|dart|default) ;;
  *) echo "Error: target must be one of: all, dart, default." >&2; exit 1 ;;
esac

node_env="$repo_root/functions/.env"
dart_env="$repo_root/functions_dart/.env"

missing=0

# Reads a key's value from an env file, trimming whitespace and surrounding
# quotes. Never printed - only tested.
env_value() {
  local file="$1" key="$2" line value
  [ -f "$file" ] || return 1
  line="$(grep -E "^[[:space:]]*${key}=" "$file" | tail -1 || true)"
  [ -n "$line" ] || return 1
  value="${line#*=}"
  value="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")"
  printf '%s' "$value"
}

require_file() {
  local file="$1" label="$2"
  if [ ! -f "$file" ]; then
    echo "Missing $label env file: $file"
    missing=1
    return 1
  fi
  return 0
}

# kind: secret | url
require_key() {
  local file="$1" label="$2" key="$3" kind="$4" value
  if ! value="$(env_value "$file" "$key")"; then
    echo "Missing $key in $label env file: $file"
    missing=1
    return
  fi
  if [ -z "$value" ]; then
    echo "Empty $key in $label env file: $file"
    missing=1
    return
  fi
  if [ "$kind" = "url" ]; then
    case "$value" in
      https://*) ;;
      http://127.0.0.1*|http://localhost*|http://0.0.0.0*|http://[::1]*)
        # Only the deploy path runs this script, and a loopback address is not
        # reachable from Cloud Run - every wrapper call would fail.
        echo "Invalid $key in $label env file: points at a local emulator."
        echo "  Loopback addresses are unreachable from Cloud Run. Use the"
        echo "  deployed https:// URL."
        missing=1 ;;
      *)
        echo "Invalid $key in $label env file: must be an https:// URL."
        missing=1 ;;
    esac
  fi
}

# The Dart secrets are required for every target, not just a Dart deploy: the
# worker needs them to run, and deploying the TypeScript side needs their values
# to verify against what the wrappers will send. Requiring only that the file
# exists is not enough - an empty or partial file would silently skip the
# comparison below.
if require_file "$dart_env" "Dart functions"; then
  require_key "$dart_env" "Dart functions" BACKEND_SCORING_COMMAND_SECRET secret
  require_key "$dart_env" "Dart functions" APP_BADGE_COMMAND_SECRET secret
fi

if [ "$target" = "default" ] || [ "$target" = "all" ]; then
  if require_file "$node_env" "TypeScript functions"; then
    require_key "$node_env" "TypeScript functions" BACKEND_SCORING_COMMAND_URL url
    require_key "$node_env" "TypeScript functions" DART_FIXTURE_DOWNLOAD_COMMAND_URL url
    require_key "$node_env" "TypeScript functions" APP_BADGE_COUNT_URL url
    require_key "$node_env" "TypeScript functions" BACKEND_SCORING_COMMAND_SECRET secret
    require_key "$node_env" "TypeScript functions" APP_BADGE_COMMAND_SECRET secret
  fi
fi

# The wrapper authenticates to the Dart worker with a shared header secret, so
# deploying either side with a secret the other does not share fails every
# wrapper call at runtime. Compare whenever both files are present, for every
# target: deploying one side alone still has to agree with the other side's
# configuration. Values are compared, never shown.
if [ -f "$dart_env" ] && [ -f "$node_env" ]; then
  for secret_key in BACKEND_SCORING_COMMAND_SECRET APP_BADGE_COMMAND_SECRET; do
    dart_secret="$(env_value "$dart_env" "$secret_key" || true)"
    node_secret="$(env_value "$node_env" "$secret_key" || true)"
    if [ -n "$dart_secret" ] && [ -n "$node_secret" ] && [ "$dart_secret" != "$node_secret" ]; then
      echo "Mismatched $secret_key between $dart_env and $node_env."
      echo "  The TypeScript wrapper would be rejected by the Dart worker."
      missing=1
    fi
  done
fi

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

The TypeScript URLs are the DEPLOYED Dart endpoint URLs. On a first deploy,
deploy the Dart codebase first (scripts/deploy-functions.sh --only dart), then
record its URLs here before deploying the TypeScript codebase.

Do not commit actual secret values.
See docs/backend-scoring-deploy.md for the first-deploy sequence.
See docs/app-badge-deploy.md for the badge rollout sequence.
EOF
  exit 1
fi

echo "Backend scoring deploy prerequisite files are present (target: ${target})."
