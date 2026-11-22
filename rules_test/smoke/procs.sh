# Process bookkeeping for the smoke test. Sourced by up.sh and down.sh.
#
# The harness never kills processes by name or pattern: a pattern can match another tool's process
# (another Playwright browser, the user's own emulators). Instead every background process this
# harness starts is launched as the leader of its OWN process group, its PID and start time are
# recorded, and down.sh signals exactly those groups, after checking the PID still belongs to the
# process that was recorded (so a reused PID is never signalled).
PROC_DIR="${PROC_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.work/pids}"
mkdir -p "$PROC_DIR"

# spawn <name> <logfile> <command> [args...]
spawn() {
  local name="$1" log="$2" pid
  shift 2
  python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@" > "$log" 2>&1 < /dev/null &
  pid=$!
  printf '%s\n%s\n' "$pid" "$(ps -o lstart= -p "$pid" | sed 's/^ *//')" > "$PROC_DIR/$name"
}

# stop_recorded: terminate every recorded group that is still the recorded process; forget the records.
stop_recorded() {
  local f pid started now
  for f in "$PROC_DIR"/*; do
    [ -f "$f" ] || continue
    pid="$(sed -n 1p "$f")"
    started="$(sed -n 2p "$f")"
    now="$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^ *//')"
    if [ -n "$now" ] && [ "$now" = "$started" ]; then
      kill -TERM -- "-$pid" 2>/dev/null || true
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
      done
      kill -0 "$pid" 2>/dev/null && kill -KILL -- "-$pid" 2>/dev/null
    fi
    rm -f "$f"
  done
  return 0
}
