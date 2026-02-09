#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
file="$repo_root/pubspec.yaml"

if [ ! -f "$file" ]; then
  echo "Missing $file"
  exit 1
fi

current_version="$(awk '/^version:/{print $2; exit}' "$file")"
if [ -z "$current_version" ]; then
  echo "Failed to read version from $file"
  exit 1
fi

build_name="${current_version%%+*}"
build_number="${current_version##*+}"

if [ "$build_name" = "$build_number" ]; then
  echo "Version in $file must include a build number like 1.2.3+456"
  exit 1
fi

arg_version="${1:-}"
arg_build="${2:-}"

if [ -n "$arg_version" ]; then
  if [[ "$arg_version" == *"+"* ]]; then
    build_name="${arg_version%%+*}"
    if [ -z "$arg_build" ]; then
      arg_build="${arg_version##*+}"
    fi
  else
    build_name="$arg_version"
  fi
fi

if [ -n "$arg_build" ]; then
  if ! [[ "$arg_build" =~ ^[0-9]+$ ]]; then
    echo "Build number must be numeric: $arg_build"
    exit 1
  fi
  build_number="$arg_build"
else
  if ! [[ "$build_number" =~ ^[0-9]+$ ]]; then
    echo "Current build number is not numeric: $build_number"
    exit 1
  fi
  build_number="$((build_number + 1))"
fi

new_version="version: ${build_name}+${build_number}"

tmp_file="$(mktemp)"
awk -v new_version="$new_version" '
  BEGIN { updated = 0 }
  /^version:/ { print new_version; updated = 1; next }
  { print }
  END { if (updated == 0) exit 2 }
' "$file" > "$tmp_file"
mv "$tmp_file" "$file"

echo "Updated $file -> $new_version"
