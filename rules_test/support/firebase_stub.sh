#!/bin/bash
# The ONLY firebase executable tests may run. Copied byte-for-byte into each test sandbox by
# support/safety.mjs; support/no_production.mjs refuses to run any other file named `firebase`,
# and checks this one by content hash, not by where it lives.
#
# It records every call and REFUSES a deploy unless it is aimed at an explicit `demo-` project.
# It never talks to anything.
sandbox="$(cd "$(dirname "$0")/.." && pwd)"
echo "$*" >> "$sandbox/firebase-calls.log"
project=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  if [ "${args[$i]}" = "--project" ]; then project="${args[$((i + 1))]}"; fi
done
rc_project="$(grep -o '"default"[[:space:]]*:[[:space:]]*"[^"]*"' .firebaserc 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')"
case "$1" in
  use)
    # STUB_USE_STYLE lets tests exercise the different shapes the real CLI prints.
    case "${STUB_USE_STYLE:-plain}" in
      verbose) echo "Active Project: ${rc_project:-none} (default)" ;;
      *) echo "${rc_project:-none}" ;;
    esac
    exit 0
    ;;
  deploy)
    case "$project" in
      demo-*) echo "$*" >> "$sandbox/firebase-deploy.log"; exit 0 ;;
      *) echo "STUB REFUSED: deploy requires an explicit --project demo-*, got '$project'" >&2; exit 99 ;;
    esac
    ;;
esac
exit 0
