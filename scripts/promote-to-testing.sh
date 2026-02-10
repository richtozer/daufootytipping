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

if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  echo "Error: working tree is not clean. Commit/stash all changes (including untracked files) first."
  git status --short
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
