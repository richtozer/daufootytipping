#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <path-to-rtdb-json>" >&2
  exit 1
fi

json_file="$1"
emulator_host="${RTDB_EMULATOR_HOST:-127.0.0.1}"
emulator_port="${RTDB_EMULATOR_PORT:-8000}"
base_url="http://${emulator_host}:${emulator_port}"

if [[ ! -f "$json_file" ]]; then
  echo "RTDB seed file not found: $json_file" >&2
  exit 1
fi

seed_namespace() {
  local ns="$1"
  local shallow

  echo "Seeding Realtime Database emulator (ns=${ns}) from ${json_file}"

  curl --fail --silent --show-error \
    -X PUT \
    -H "Content-Type: application/json" \
    --data-binary @"${json_file}" \
    "${base_url}/.json?ns=${ns}" >/dev/null

  shallow="$(
    curl --fail --silent --show-error \
      "${base_url}/.json?ns=${ns}&shallow=true"
  )"

  if [[ "${shallow}" == "null" || -z "${shallow}" ]]; then
    echo "Seed verification failed for namespace ${ns} (database is still empty)." >&2
    return 1
  fi

  echo "Seeded Realtime Database emulator successfully (ns=${ns})."
  return 0
}

declare -a candidates=()

if [[ -n "${RTDB_EMULATOR_NAMESPACE:-}" ]]; then
  candidates+=("${RTDB_EMULATOR_NAMESPACE}")
fi

# Project-specific likely namespaces (regional and non-regional forms).
candidates+=(
  "dau-footy-tipping-f8a42-default-rtdb"
  "dau-footy-tipping-f8a42-default-rtdb.asia-southeast1"
  "dau-footy-tipping-f8a42"
)

for ns in "${candidates[@]}"; do
  if [[ " ${seen_namespaces:-} " == *" ${ns} "* ]]; then
    continue
  fi
  seen_namespaces="${seen_namespaces:-} ${ns}"

  if seed_namespace "$ns"; then
    exit 0
  fi
done

echo "Unable to seed RTDB emulator using any known namespace." >&2
echo "Set RTDB_EMULATOR_NAMESPACE in the task if your namespace differs." >&2
exit 1
