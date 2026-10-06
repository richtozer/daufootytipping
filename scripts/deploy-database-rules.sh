#!/usr/bin/env bash
set -euo pipefail

# Deploys the Realtime Database rules to PRODUCTION, guarded.
#
# What Firebase ships is the file named in firebase.json (database.rules.json). This script
# refuses to deploy unless that exact file is the generated rules for the CURRENT admin
# allowlist (config/admin-auth-uids.json), the allowlist is non-empty, the tree is clean and
# every generated output is up to date. After a successful deploy it records which allowlist
# revision was deployed (config/deployments/allowlist-deployments.jsonl) so each deployment is
# traceable. See DESIGN-database-rules.md (D12) and DESIGN-database-rules-phase3.md.
#
# Safety:
#   * The firebase executable is explicit: FIREBASE_BIN if set, otherwise `firebase` from the
#     PATH. The script never prepends directories to the PATH when a firebase is already
#     resolvable.
#   * The target project is explicit: --project <id> is passed to firebase and must match the
#     project firebase reports as active. --yes REQUIRES --project, so a non-interactive run can
#     never deploy to an implicit default project.
#
# Rollback ladder (use the SMALLEST step that fixes the problem):
#   1. Compatibility problem with R1:  --variant r1-recovery   (keeps every protection; relaxes
#      only validation strictness and re-admits the legacy 1.3.x Stats writers)
#   2. Anything else: fix forward and redeploy r1.
#   3. EMERGENCY ONLY, a last resort that restores unrestricted database writes:
#      BACKUP-database.rules.json. Re-run the identity audit afterwards.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

firebase_bin="${FIREBASE_BIN:-firebase}"

# Support user-level npm global installs, but only when no firebase is resolvable already, so a
# firebase that was put earlier on the PATH (or named in FIREBASE_BIN) is never shadowed.
if ! command -v "$firebase_bin" >/dev/null 2>&1 && [ -d "$HOME/.npm-global/bin" ]; then
  export PATH="$HOME/.npm-global/bin:$PATH"
fi

usage() {
  cat <<'USAGE'
Usage: deploy-database-rules.sh --project <id> [--variant r1|r1-recovery] [--yes] [--allow-dirty] [--dry-run]

  --project       The Firebase project to deploy to (required with --yes; must be the active one)
  --variant       Which generated ruleset database.rules.json must contain (default: r1)
  --yes           Skip the confirmation prompt (requires --project)
  --allow-dirty   Permit deploying with uncommitted changes
  --dry-run       Run every check, print the plan, and stop before deploying

Install the ruleset first, then commit it:
  node scripts/build_admin_allowlist.mjs --install-rules --variant r1

Set FIREBASE_BIN to name the firebase executable explicitly.
USAGE
}

variant="r1"
project_arg=""
assume_yes=0
allow_dirty=0
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    --variant)
      [ $# -ge 2 ] || { echo "Error: --variant requires a value." >&2; usage >&2; exit 1; }
      variant="$2"
      shift 2
      ;;
    --project)
      [ $# -ge 2 ] || { echo "Error: --project requires a value." >&2; usage >&2; exit 1; }
      project_arg="$2"
      shift 2
      ;;
    --yes) assume_yes=1; shift ;;
    --allow-dirty) allow_dirty=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown argument '$1'." >&2; usage >&2; exit 1 ;;
  esac
done

case "$variant" in
  r1|r1-recovery) ;;
  *) echo "Error: --variant must be r1 or r1-recovery." >&2; exit 1 ;;
esac

if [ "$assume_yes" -eq 1 ] && [ -z "$project_arg" ]; then
  echo "Error: --yes requires --project <id>, so a non-interactive run can never deploy to an" >&2
  echo "implicit default project." >&2
  exit 1
fi

if ! command -v "$firebase_bin" >/dev/null 2>&1; then
  echo "Error: firebase CLI is not installed or not on PATH (FIREBASE_BIN=${FIREBASE_BIN:-unset})."
  exit 1
fi

if [ "$allow_dirty" -eq 0 ]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: working tree is not clean. Commit database.rules.json and the generated"
    echo "files first so the deployed commit is recorded and recoverable, or pass --allow-dirty."
    git status --short
    exit 1
  fi
fi

echo "Step 1: Checking the allowlist outputs are current and the list is non-empty..."
node "$repo_root/scripts/build_admin_allowlist.mjs" --check

echo "Step 2: Checking database.rules.json is exactly the generated '${variant}' rules..."
node "$repo_root/scripts/build_admin_allowlist.mjs" --check-deploy --variant "$variant"

# Parse the project ID from the first line of `firebase use`, which prints either "<id>" or
# "Active Project: <id> (<alias>)", and compare it EXACTLY (a substring match would accept
# "my-project" for "my-project-staging").
parse_active_project() {
  printf '%s' "$1" | head -1 | tr -d '\r' \
    | sed -E 's/^[[:space:]]*(Active Project:[[:space:]]*)?//; s/[[:space:]]*\([^)]*\)[[:space:]]*$//; s/[[:space:]]+$//'
}
active_project="$(parse_active_project "$("$firebase_bin" use 2>/dev/null || true)")"
if [ -n "$project_arg" ]; then
  if [ "$active_project" != "$project_arg" ]; then
    echo "Error: --project '${project_arg}' is not the active firebase project ('${active_project}')." >&2
    echo "Run 'firebase use ${project_arg}' deliberately first, or correct --project." >&2
    exit 1
  fi
  project="$project_arg"
else
  project="$active_project"
fi

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
short_commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
revision="$(node "$repo_root/scripts/build_admin_allowlist.mjs" --revision)"

echo
echo "About to deploy Realtime Database rules to PRODUCTION."
echo "  Project:            ${project}"
echo "  Ruleset:            ${variant}"
echo "  Allowlist revision: ${revision}"
echo "  Branch / commit:    ${branch} / ${short_commit}"
if [ "$variant" = "r1-recovery" ]; then
  echo
  echo "  RECOVERY ruleset: relaxes validation strictness and re-admits legacy 1.3.x Stats"
  echo "  writers. Allowlisted admins, identity protection and default deny are unchanged."
fi
echo

if [ "$dry_run" -eq 1 ]; then
  echo "Dry run: all checks passed. Nothing was deployed."
  exit 0
fi

if [ -z "$project_arg" ]; then
  echo "Error: deploying requires --project <id> (the project to deploy to, stated explicitly)." >&2
  exit 1
fi

if [ "$assume_yes" -eq 0 ]; then
  printf "Type 'deploy' to continue: "
  read -r reply
  if [ "$reply" != "deploy" ]; then
    echo "Aborted."
    exit 1
  fi
fi

echo "Step 3: Deploying database rules..."
"$firebase_bin" deploy --only database --project "$project"

echo "Step 4: Recording the deployment..."
node "$repo_root/scripts/build_admin_allowlist.mjs" --record rules --variant "$variant"

echo
echo "Done. Deployed ${variant} rules (allowlist revision ${revision}) from ${short_commit} to ${project}."
echo "Commit config/deployments/allowlist-deployments.jsonl to keep the record."
echo "Now run the post-deploy verification in DESIGN-database-rules-phase3.md section 6."
