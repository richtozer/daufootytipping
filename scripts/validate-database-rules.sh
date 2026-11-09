#!/usr/bin/env bash
set -euo pipefail

# Asks the Realtime Database service to VALIDATE the generated rules, without deploying them.
#
# `firebase deploy --only database --dry-run` submits the rules to the service for validation
# (dryRun: true) and stops before any release. That catches what the local emulator may not:
# production's limits on rule length and depth. It does contact the project, so it is run by the
# owner, or by an agent only on the owner's explicit go.
#
# What makes it safe:
#   * `--dry-run` is hard-coded, not an option. There is no way to make this script release rules.
#   * It never touches database.rules.json. Each variant is validated from a throwaway
#     firebase.json in a temporary folder that points straight at the generated file, so there is
#     nothing to install first and nothing to put back afterwards.
#   * The project is explicit: --project is required.
#   * It refuses to run unless the generated rules are current for the admin allowlist.
#
# Usage: validate-database-rules.sh --project <id> [--variant r1|r1-recovery|r1-compat|freeze|r2|all]
#   --variant defaults to "freeze" and "r2", the two not yet deployed. "all" checks all five.
# Exit codes: 0 every variant valid, 1 a variant failed validation or a check failed, 2 usage.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

firebase_bin="${FIREBASE_BIN:-firebase}"
if ! command -v "$firebase_bin" >/dev/null 2>&1 && [ -d "$HOME/.npm-global/bin" ]; then
  export PATH="$HOME/.npm-global/bin:$PATH"
fi

usage() { sed -n '/^# Usage:/,/^# Exit codes/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; }

project=""
variants=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || { echo "Error: --project requires a value." >&2; usage; exit 2; }
      project="$2"; shift 2 ;;
    --variant)
      [ $# -ge 2 ] || { echo "Error: --variant requires a value." >&2; usage; exit 2; }
      variants+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown argument '$1'." >&2; usage; exit 2 ;;
  esac
done

[ -n "$project" ] || { echo "Error: --project <id> is required (the project to validate against, stated explicitly)." >&2; usage; exit 2; }
[ "${#variants[@]}" -gt 0 ] || variants=(freeze r2)
if [ "${variants[0]}" = "all" ]; then variants=(r1 r1-recovery r1-compat freeze r2); fi

generated_for() {
  case "$1" in
    r1) echo "$repo_root/config/generated/database.rules.r1.json" ;;
    r1-recovery) echo "$repo_root/config/generated/database.rules.r1-recovery.json" ;;
    r1-compat) echo "$repo_root/config/generated/database.rules.r1-compat.json" ;;
    freeze) echo "$repo_root/config/generated/database.rules.freeze.json" ;;
    r2) echo "$repo_root/config/generated/database.rules.r2.json" ;;
    *) return 1 ;;
  esac
}
for variant in "${variants[@]}"; do
  generated_for "$variant" >/dev/null || { echo "Error: --variant must be r1, r1-recovery, r1-compat, freeze, r2 or all (got '$variant')." >&2; usage; exit 2; }
done

if ! command -v "$firebase_bin" >/dev/null 2>&1; then
  echo "Error: firebase CLI is not installed or not on PATH (FIREBASE_BIN=${FIREBASE_BIN:-unset})." >&2
  exit 1
fi

echo "Checking the generated rules are current for the admin allowlist..."
node "$repo_root/scripts/build_admin_allowlist.mjs" --check

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failed=0
for variant in "${variants[@]}"; do
  rules="$(generated_for "$variant")"
  dir="$work/$variant"
  mkdir -p "$dir"
  printf '{ "database": { "rules": "%s" } }\n' "$rules" > "$dir/firebase.json"
  echo
  echo "Validating '$variant' against $project (dry run: nothing is released)"
  echo "  rules file: $rules"
  if (cd "$dir" && "$firebase_bin" deploy --only database --project "$project" --dry-run); then
    echo "  RESULT $variant: valid"
  else
    echo "  RESULT $variant: FAILED validation" >&2
    failed=1
  fi
done

echo
if [ "$failed" -eq 0 ]; then
  echo "Every rule set listed was accepted by the service. Nothing was deployed."
else
  echo "At least one rule set was rejected. Nothing was deployed." >&2
fi
exit "$failed"
