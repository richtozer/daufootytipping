#!/usr/bin/env bash

set -euo pipefail

uid="$(id -u)"

collect_pids() {
  local pids=""
  local port

  for port in 8000 8081 8099 6001 4000 4400 4500 9150 9229; do
    if command -v lsof >/dev/null 2>&1; then
      pids+=$'\n'"$(lsof -nP -tiTCP:${port} -sTCP:LISTEN -u "${uid}" 2>/dev/null || true)"
    fi
  done

  # Catch watch/build processes that may not own a listening port.
  pids+=$'\n'"$(pgrep -u "${uid}" -f "firebase emulators:start" 2>/dev/null || true)"
  pids+=$'\n'"$(pgrep -u "${uid}" -f "npm --prefix ./functions run build -- -w" 2>/dev/null || true)"
  pids+=$'\n'"$(pgrep -u "${uid}" -f "tsc --watch" 2>/dev/null || true)"
  pids+=$'\n'"$(pgrep -u "${uid}" -f "tsc -w" 2>/dev/null || true)"

  printf '%s\n' "${pids}" | awk 'NF' | sort -u
}

mapfile -t pids < <(collect_pids)

if [[ "${#pids[@]}" -eq 0 ]]; then
  echo "No local Firebase emulator/debug processes found."
  exit 0
fi

echo "Stopping local emulator/debug processes: ${pids[*]}"
kill "${pids[@]}" 2>/dev/null || true
sleep 1

mapfile -t remaining < <(collect_pids)
if [[ "${#remaining[@]}" -gt 0 ]]; then
  echo "Force stopping remaining processes: ${remaining[*]}"
  kill -9 "${remaining[@]}" 2>/dev/null || true
fi

exit 0
