#!/usr/bin/env bash
set -euo pipefail

# Deploys the Cloud Functions codebases to the active Firebase project.
#
# This is deliberately NOT part of promote-to-testing.sh. Firebase Functions
# have no preview channel the way Hosting does, so every deploy here is a
# PRODUCTION deploy: TestFlight/Play-internal testers and real users share one
# backend. Function changes must stay backward compatible with the client
# version currently on main.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

# Support user-level npm global installs when the caller's shell startup files
# have not been loaded into the current environment.
if [ -d "$HOME/.npm-global/bin" ]; then
  export PATH="$HOME/.npm-global/bin:$PATH"
fi
if [ -d "$HOME/dev/tooling/flutter/bin" ]; then
  export PATH="$HOME/dev/tooling/flutter/bin:$PATH"
fi

usage() {
  cat <<'EOF'
Usage: deploy-functions.sh [--only default|dart|all] [--yes] [--allow-dirty]

  --only default   Deploy the TypeScript codebase only (functions/)
  --only dart      Deploy the Dart codebase only (functions_dart/)
  --only all       Deploy both (default)
  --yes            Skip the confirmation prompt
  --allow-dirty    Permit deploying with uncommitted changes

Deploys to the active Firebase project. Run 'firebase use' to check or change it.
EOF
}

only="all"
assume_yes=0
allow_dirty=0

while [ $# -gt 0 ]; do
  case "$1" in
    --only)
      [ $# -ge 2 ] || { echo "Error: --only requires a value." >&2; usage >&2; exit 1; }
      only="$2"
      shift 2
      ;;
    --yes) assume_yes=1; shift ;;
    --allow-dirty) allow_dirty=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown argument '$1'." >&2; usage >&2; exit 1 ;;
  esac
done

case "$only" in
  default|dart|all) ;;
  *) echo "Error: --only must be one of: default, dart, all." >&2; exit 1 ;;
esac

if ! command -v firebase >/dev/null 2>&1; then
  echo "Error: firebase CLI is not installed or not on PATH."
  echo "PATH=$PATH"
  echo "If installed with npm, ensure the global npm bin directory is on PATH."
  exit 1
fi

if [ "$allow_dirty" -eq 0 ]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: working tree is not clean. Commit or stash first so the deployed"
    echo "commit is recorded and recoverable, or pass --allow-dirty."
    git status --short
    exit 1
  fi
fi

project="$(firebase use 2>/dev/null | head -1 | tr -d '\r')"
branch="$(git rev-parse --abbrev-ref HEAD)"
commit="$(git rev-parse HEAD)"
short_commit="$(git rev-parse --short HEAD)"

targets=""
case "$only" in
  default) targets="functions:default" ;;
  dart)    targets="functions:dart_functions" ;;
  all)     targets="functions:default,functions:dart_functions" ;;
esac

echo
echo "About to deploy Cloud Functions to PRODUCTION."
echo "  Project:   ${project}"
echo "  Codebases: ${targets}"
echo "  Branch:    ${branch}"
echo "  Commit:    ${short_commit}"
if [ "$allow_dirty" -eq 1 ] && { ! git diff --quiet || ! git diff --cached --quiet; }; then
  echo "  WARNING:   working tree is dirty - the deployed code is not this commit."
fi
echo
echo "Test clients and real users share this backend. Confirm the change is"
echo "backward compatible with the client version currently on main."
echo

if [ "$assume_yes" -eq 0 ]; then
  printf "Type 'deploy' to continue: "
  read -r reply
  if [ "$reply" != "deploy" ]; then
    echo "Aborted."
    exit 1
  fi
fi

echo "Step 1: Checking backend scoring deploy prerequisites..."
bash "$repo_root/scripts/check_backend_scoring_deploy_prereqs.sh"

if [ "$only" = "dart" ] || [ "$only" = "all" ]; then
  # The TypeScript codebase is gated by the firebase.json predeploy hooks
  # (lint, build, test). The Dart codebase has no predeploy entry, so gate it
  # here instead. dau_shared is included because functions_dart depends on it.
  echo "Step 2: Running Dart tests..."
  (cd "$repo_root/packages/dau_shared" && dart test)
  (cd "$repo_root/functions_dart" && dart analyze && dart test)

  echo "Step 3: Building Dart Cloud Functions for Linux deployment..."
  bash "$repo_root/scripts/build_dart_functions.sh" linux
fi

echo "Step 4: Deploying ${targets}..."
firebase deploy --only "$targets"

echo
echo "Done. Deployed ${targets} from ${short_commit} (${branch}) to ${project}."
echo
echo "There is no one-command rollback for Cloud Functions. To revert, redeploy"
echo "the previous known-good commit:"
echo
echo "    git stash                     # if you have local changes"
echo "    git checkout <previous-sha>"
echo "    scripts/deploy-functions.sh --only ${only}"
echo "    git checkout ${branch}"
