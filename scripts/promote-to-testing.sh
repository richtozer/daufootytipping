#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

if [ "$(git rev-parse --abbrev-ref HEAD)" != "development" ]; then
  echo "Error: this script must be run from the 'development' branch."
  exit 1
fi

if ! git show-ref --verify --quiet refs/heads/testing; then
  echo "Error: local 'testing' branch does not exist."
  exit 1
fi

if ! git remote | grep -qx "origin"; then
  echo "Error: git remote 'origin' does not exist."
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  echo "Error: working tree is not clean. Commit/stash all changes (including untracked files) first."
  git status --short
  exit 1
fi

echo "Step 2a: Fetching latest refs from origin..."
git fetch origin development testing

if ! git show-ref --verify --quiet refs/remotes/origin/development; then
  echo "Error: remote branch 'origin/development' does not exist."
  exit 1
fi
if ! git show-ref --verify --quiet refs/remotes/origin/testing; then
  echo "Error: remote branch 'origin/testing' does not exist."
  exit 1
fi

if git merge-base --is-ancestor development origin/development; then
  if [ "$(git rev-parse development)" != "$(git rev-parse origin/development)" ]; then
    echo "Step 2b: Fast-forwarding development from origin/development..."
    git merge --ff-only origin/development
  fi
elif git merge-base --is-ancestor origin/development development; then
  echo "Step 2b: development is ahead of origin/development."
else
  echo "Error: development has diverged from origin/development. Reconcile first."
  exit 1
fi

switched_to_testing=0
cleanup() {
  if [ "$switched_to_testing" -eq 1 ]; then
    git checkout development >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "Step 3: Merging development into testing..."
git checkout testing
switched_to_testing=1

if git merge-base --is-ancestor testing origin/testing; then
  if [ "$(git rev-parse testing)" != "$(git rev-parse origin/testing)" ]; then
    echo "Step 3a: Fast-forwarding testing from origin/testing..."
    git merge --ff-only origin/testing
  fi
elif git merge-base --is-ancestor origin/testing testing; then
  echo "Step 3a: testing is ahead of origin/testing."
else
  echo "Error: testing has diverged from origin/testing. Reconcile first."
  exit 1
fi

git merge --no-edit development

echo "Step 4: Switching back to development..."
git checkout development
switched_to_testing=0

echo "Step 5: Bumping build number..."
"$repo_root/scripts/bump_build_number.sh"

new_version="$(awk '/^version:/{print $2; exit}' "$repo_root/pubspec.yaml")"

echo "Step 6: Committing bumped version..."
git add "$repo_root/pubspec.yaml"
git commit -m "chore(version): bump build number to ${new_version}"

echo "Step 7: Done."
echo "Merged development -> testing, returned to development, and committed version ${new_version}."
echo "Remember to push both branches: git push origin testing development"
