# Helpers for the real-client smoke test. Everything runs inside the OS boundary
# (support/isolated.sh): no network except loopback, no credentials.
SMOKE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO="$SMOKE/../support/isolated.sh"
PW="$SMOKE/.work/pw"
mkdir -p "$PW"
# Every playwright-cli call goes through the boundary, from ONE directory (the CLI keys sessions by it),
# so a later call can never relaunch an unprotected browser.
P() { (cd "$PW" && timeout 90 "$ISO" playwright-cli -s=smoke "$@" 2>&1); }
# Both helpers read the file the command ITSELF reports writing (its output names the path), never
# "the newest file in the folder": listing a folder of hundreds of snapshots through `ls | head` made
# `ls` die of SIGPIPE under pipefail, so a check could fail even though the text was on screen, and a
# stale file could be read if two were written in the same instant.
reported_file() { # reported_file <ext> reads a command's output on stdin and prints the last file path it names
  sed -n "s/.*(\(\.playwright-cli\/[^)]*\.$1\)).*/\1/p" | tail -1
}
snap() {
  local out file
  out="$(P snapshot)"
  file="$(printf '%s\n' "$out" | reported_file yml)"
  [ -n "$file" ] && cat "$PW/$file"
  return 0
}
# ref of the first (or last) element whose snapshot line contains $1
R() { snap | grep -m1 -F -- "$1" | grep -o 'ref=e[0-9]*' | head -1 | cut -d= -f2; }
RL() { snap | grep -F -- "$1" | tail -1 | grep -o 'ref=e[0-9]*' | cut -d= -f2; }
click_label() { local r; r=$(R "$1"); if [ -n "$r" ]; then P click "$r" | grep -E "Error"; else echo "NO ELEMENT: $1"; fi; return 0; }
click_last() { local r; r=$(RL "$1"); if [ -n "$r" ]; then P click "$r" | grep -E "Error"; else echo "NO ELEMENT: $1"; fi; return 0; }
fill_label() { local r; r=$(R "$1"); if [ -n "$r" ]; then P fill "$r" "$2" | grep -E "Error"; else echo "NO ELEMENT: $1"; fi; return 0; }
enable_semantics() { P eval "() => { const p = document.querySelector('flt-semantics-placeholder'); if (p) p.click(); return 'ok'; }" >/dev/null; sleep 2; }
# Close the named session. If a browser it started is somehow still running, stop only the processes
# carrying this run's unique marker (written by up.sh), never anything matched by name.
stop_browser() {
  P close >/dev/null 2>&1 || true
  local marker pids
  marker="$(cat "$SMOKE/.work/browser-marker" 2>/dev/null)" || return 0
  [ -n "$marker" ] || return 0
  pids="$(pgrep -f -- "--smoke-browser-marker=$marker" || true)"
  # shellcheck disable=SC2086
  [ -n "$pids" ] && kill $pids 2>/dev/null
  return 0
}
fresh() {
  stop_browser; sleep 1
  (cd "$PW" && timeout 120 "$ISO" playwright-cli -s=smoke open about:blank --config="$PW/cli.config.json" >/dev/null 2>&1)
  local routed; routed="$(P run-code "$(cat "$SMOKE/route.js")" | grep -E '^"|Error')"
  echo "$routed"
  # route.js reports "routed ..." only when every Firebase SDK request matched the locally served version
  case "$routed" in "\"routed"*) ;; *) echo "ABORT: the app was not served the exact Firebase JS SDK it requests: $routed" >&2; exit 1 ;; esac
  enable_semantics
}
ST() { (cd "$SMOKE" && "$ISO" env NODE_OPTIONS=--import=../support/no_production.mjs FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:8099 FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:8000 GCLOUD_PROJECT=demo-dau-rules node state.mjs 2>&1); }
# permission-denied events the app saw (the RTDB SDK logs them as console warnings)
DENIED_COUNT() {
  local out file
  out="$(P console)"
  file="$(printf '%s\n' "$out" | reported_file log)"
  [ -n "$file" ] || { echo UNREADABLE; return 0; }   # not "0": an unreadable log must never count as "no denials"
  grep -ciE "permission_denied|PERMISSION_DENIED" "$PW/$file" || true
}
PASS=0; FAIL=0
# expect "label" '<python expression over d = database/auth state>'
# Checks wait for the condition instead of sleeping a fixed time: the app is driven through a
# software-rendered browser whose speed varies. A check passes as soon as it holds and fails only
# if it never holds within the time allowed. (Waiting cannot make a wrong state pass.)
expect() {
  local label="$1" expr="$2" out i
  for i in 1 2 3 4 5 6; do
    out=$(ST | python3 -c "
import json,sys
d=json.load(sys.stdin)
t=d['tippers']; tips=d['tips']
byname={v['name']:(k,v) for k,v in t.items()}
print('PASS' if ($expr) else 'FAIL')" 2>&1 | tail -1)
    [ "$out" = "PASS" ] && break
    sleep 1
  done
  if [ "$out" = "PASS" ]; then PASS=$((PASS+1)); echo "  PASS  $label"; else FAIL=$((FAIL+1)); echo "  FAIL  $label"; fi
}
expect_no_denials() {
  local n; n=$(DENIED_COUNT)
  if [ "$n" = "0" ]; then PASS=$((PASS+1)); echo "  PASS  $1 (no permission_denied seen by the app)"; else FAIL=$((FAIL+1)); echo "  FAIL  $1 (permission_denied count: $n)"; fi
}
expect_text() { # expect_text "label" "text that must appear on screen" (polls for up to ~30s)
  local i screen
  for i in $(seq 1 12); do
    screen="$(snap)"
    # matched in the shell itself: no pipeline whose early exit could turn a match into a failure
    if [[ "$screen" == *"$2"* ]]; then PASS=$((PASS+1)); echo "  PASS  $1"; return 0; fi
    sleep 1
  done
  FAIL=$((FAIL+1)); echo "  FAIL  $1 (text not on screen: $2)"
}
login_email() { # login_email <email>
  fresh
  click_label "Tap here to sign in with email"; sleep 2
  fill_label 'textbox "Email"' "$1"; fill_label 'textbox "Password"' "Smoke-test-pw-1"
  click_label 'button "Sign In"'; sleep 8
}
