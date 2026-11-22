#!/usr/bin/env bash
# Stops exactly what up.sh and the browser session started, by recorded process group and per-run
# browser marker. It never kills by process name or pattern.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"
# shellcheck source=procs.sh
source "$here/procs.sh"
stop_browser
stop_recorded
rm -f "$SMOKE/.work/browser-marker"
sleep 2
echo "smoke environment stopped"
