#!/usr/bin/env bash

set -euo pipefail

readonly project_id='dau-footy-tipping-f8a42'
readonly database_instance='dau-footy-tipping-f8a42-default-rtdb'
readonly probe_path='/Diagnostics/androidResumeProbe'

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "Usage: $0 <nonce>" >&2
  exit 64
fi

readonly probe_value="$1"
if [[ ! "$probe_value" =~ ^[[:alnum:]_.:+-]+$ ]]; then
  echo 'Nonce may contain only letters, numbers, dot, underscore, colon, plus, and hyphen.' >&2
  exit 64
fi

readonly probe_json="\"$probe_value\""

firebase database:set "$probe_path" \
  --project "$project_id" \
  --instance "$database_instance" \
  --data "$probe_json" \
  --disable-triggers \
  --force

firebase database:get "$probe_path" \
  --project "$project_id" \
  --instance "$database_instance"
