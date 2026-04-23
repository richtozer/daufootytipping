#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

# Support user-level npm global installs when the caller's shell startup files
# have not been loaded into the current environment.
if [ -d "$HOME/.npm-global/bin" ]; then
  export PATH="$HOME/.npm-global/bin:$PATH"
fi

if [ "$(git rev-parse --abbrev-ref HEAD)" != "testing" ]; then
  echo "Error: this script must be run from the 'testing' branch."
  exit 1
fi

if ! git show-ref --verify --quiet refs/heads/main; then
  echo "Error: local 'main' branch does not exist."
  exit 1
fi

if ! git remote | grep -qx "origin"; then
  echo "Error: git remote 'origin' does not exist."
  exit 1
fi

if ! command -v firebase >/dev/null 2>&1; then
  echo "Error: firebase CLI is not installed or not on PATH."
  echo "PATH=$PATH"
  echo "If installed with npm, ensure the global npm bin directory is on PATH."
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  echo "Error: working tree is not clean. Commit/stash all changes (including untracked files) first."
  git status --short
  exit 1
fi

echo "Step 1: Fetching latest refs from origin..."
git fetch origin testing main

if ! git show-ref --verify --quiet refs/remotes/origin/testing; then
  echo "Error: remote branch 'origin/testing' does not exist."
  exit 1
fi
if ! git show-ref --verify --quiet refs/remotes/origin/main; then
  echo "Error: remote branch 'origin/main' does not exist."
  exit 1
fi

if git merge-base --is-ancestor testing origin/testing; then
  if [ "$(git rev-parse testing)" != "$(git rev-parse origin/testing)" ]; then
    echo "Step 1a: Fast-forwarding testing from origin/testing..."
    git merge --ff-only origin/testing
  fi
elif git merge-base --is-ancestor origin/testing testing; then
  echo "Step 1a: testing is ahead of origin/testing."
else
  echo "Error: testing has diverged from origin/testing. Reconcile first."
  exit 1
fi

switched_to_main=0
cleanup() {
  if [ "$switched_to_main" -eq 1 ]; then
    git checkout testing >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "Step 2: Switching to main..."
git checkout main
switched_to_main=1

if git merge-base --is-ancestor main origin/main; then
  if [ "$(git rev-parse main)" != "$(git rev-parse origin/main)" ]; then
    echo "Step 2a: Fast-forwarding main from origin/main..."
    git merge --ff-only origin/main
  fi
elif git merge-base --is-ancestor origin/main main; then
  echo "Step 2a: main is ahead of origin/main."
else
  echo "Error: main has diverged from origin/main. Reconcile first."
  exit 1
fi

echo "Step 3: Merging testing into main..."
git merge --no-edit testing

echo "Step 4: Deploying main to Firebase Hosting..."
firebase deploy --only hosting

echo "Step 5: Pushing main to origin..."
git push origin main

echo "Step 6: Switching back to testing..."
git checkout testing
switched_to_main=0

echo "Step 7: Done."
echo "Merged testing -> main, deployed Firebase Hosting from main, pushed main to origin, and returned to testing."
