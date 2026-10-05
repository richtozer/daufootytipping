#!/usr/bin/env bash
# Real-client smoke test: the RELEASED 1.4.0 (build 712) web app, driven through its own UI in a
# contained headless browser, against the emulators with the R1 rules (fixture admin UID only).
# Prerequisites: prepare_app.sh, then up.sh. Exit status 1 if any check fails.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

echo "== S1  fresh sign-in, a normal tipper whose authuid is a real Firebase UID"
login_email "alice@smoke.example.test"
expect_text "tipping page rendered with the seeded games" "Brisbane Broncos V Canberra Raiders"
expect "login wrote acctLoggedOnUTC and acctCreatedUTC on Alice's own record" "byname['Alice Smoke'][1]['acctLoggedOnUTC']=='set' and byname['Alice Smoke'][1]['acctCreatedUTC']=='set'"
expect "no new record, authuid and role untouched" "len(t)==4 and byname['Alice Smoke'][1]['authuid']=='<alice>' and byname['Alice Smoke'][1]['role']=='tipper'"
expect_no_denials "S1"

echo "== S2  a placeholder-backed account (authuid is an email address, as in the legacy data)"
login_email "legacy@smoke.example.test"
expect_text "legacy user reached the tipping page" "Brisbane Broncos V Canberra Raiders"
expect "client linked by email and wrote the login-time fields" "byname['Legacy Smoke'][1]['acctLoggedOnUTC']=='set'"
expect "authuid is still the placeholder (the client never writes it); no new record" "byname['Legacy Smoke'][1]['authuid']=='legacy@smoke.example.test' and len(t)==4"
expect_no_denials "S2"

echo "== S3  registration of a brand-new user (the client creates its own record)"
fresh
click_label "Tap here to sign in with email"; sleep 2
click_label "Need an email account? Register"; sleep 2
fill_label 'textbox "Email"' "newbie@smoke.example.test"; fill_label 'textbox "Password"' "Smoke-test-pw-1"
click_label 'button "Register"'; sleep 6
expect_text "unverified email is turned away" "Your email is not verified"
CODE=$(curl -s -m 5 http://127.0.0.1:8099/emulator/v1/projects/demo-dau-rules/oobCodes | python3 -c "
import json,sys
c=[x for x in json.load(sys.stdin)['oobCodes'] if x['email']=='newbie@smoke.example.test' and x['requestType']=='VERIFY_EMAIL']
print(c[-1]['oobCode'] if c else '')")
curl -s -m 5 -X POST "http://127.0.0.1:8099/identitytoolkit.googleapis.com/v1/accounts:update?key=demo" -H 'Content-Type: application/json' -d "{\"oobCode\":\"$CODE\"}" >/dev/null
login_email "newbie@smoke.example.test"
expect_text "alias dialog appears for a verified new user" "New Tipper Alias"
fill_label 'textbox "Tipper Alias' "alice  SMOKE!"; click_label 'button "Save"'; sleep 3
expect_text "an alias that collides with an existing tipper is rejected by the client" "too similar to an existing alias"
expect "no record created for the rejected alias" "len(t)==4"
fill_label 'textbox "Tipper Alias' "Newbie Smoke"; click_label 'button "Save"'; sleep 8
expect "new record created: role tipper, authuid is the new account's real UID, not a placeholder" "'Newbie Smoke' in byname and byname['Newbie Smoke'][1]['role']=='tipper' and len(byname['Newbie Smoke'][1]['authuid'])>20 and not byname['Newbie Smoke'][1]['authuid'].startswith('<')"
expect "exactly one record was added" "len(t)==5"
expect_no_denials "S3"

echo "== S4  the new user submits a tip"
click_label 'checkbox "Home team wins by 13 points or more Home 13+"'; sleep 4
expect "tip written as {r,t} under the new tipper (accepted by R1 validation)" "any('nrl-01-001' in g for k,g in tips.items() if k==byname['Newbie Smoke'][0])"
expect_no_denials "S4"

echo "== S5  admin: paid and unpaid edits (compsParticipatedIn, admin only under R1)"
login_email "admin@smoke.example.test"
click_label 'tab "P R O F I L E"'; sleep 2
expect_text "admin options visible" "Admin Tippers"
click_label 'button "Admin Tippers"'; sleep 3
expect_text "admin list loaded all tippers" "Showing 5 of 5 tippers"
click_label 'button "Newbie Smoke - tipper'; sleep 3
P click "$(snap | grep -m1 -F 'cell [ref=' | grep -o 'ref=e[0-9]*' | cut -d= -f2)" >/dev/null; sleep 4
expect "admin marked Newbie as paid" "byname['Newbie Smoke'][1]['paid']==['compSMOKE26']"
back=$(snap | grep -m1 -E '^\s*- button \[(active )?ref=' | grep -o 'ref=e[0-9]*' | cut -d= -f2); P click "$back" >/dev/null; sleep 2
click_label 'button "Alice Smoke - tipper'; sleep 3
P click "$(snap | grep -m1 -F 'cell [ref=' | grep -o 'ref=e[0-9]*' | cut -d= -f2)" >/dev/null; sleep 4
expect "admin marked Alice as unpaid" "byname['Alice Smoke'][1]['paid'] is None"
expect_no_denials "S5"

echo "== S6  admin: merge the new-account record into the legacy record"
back=$(snap | grep -m1 -E '^\s*- button \[(active )?ref=' | grep -o 'ref=e[0-9]*' | cut -d= -f2); P click "$back" >/dev/null; sleep 2
click_label 'button "Newbie Smoke - tipper'; sleep 3
click_label 'button "Merge..."'; sleep 3
click_label 'button "Tipper to merge to"'; sleep 2
click_label 'menuitem "Legacy Smoke"'; sleep 2
click_last 'button "Merge"'; sleep 3
expect_text "the app asks for confirmation" "Are you sure you want to merge these tippers"
click_last 'button "Merge"'; sleep 8
expect "source record deleted" "'Newbie Smoke' not in byname and len(t)==4"
expect "legacy record took the new account's identity and logon" "byname['Legacy Smoke'][1]['logon']=='newbie@smoke.example.test' and not byname['Legacy Smoke'][1]['authuid'].startswith('legacy@')"
expect "the tip moved to the legacy record" "any('nrl-01-001' in g for k,g in tips.items() if k==byname['Legacy Smoke'][0])"
expect_no_denials "S6"

echo "== S7  god mode: the admin tips on behalf of Bob"
login_email "admin@smoke.example.test"
click_label 'tab "P R O F I L E"'; sleep 2; click_label 'button "Admin Tippers"'; sleep 3
click_label 'button "Bob Smoke - tipper'; sleep 3
P click "$(snap | grep -F -A1 'God mode' | grep -m1 'switch' | grep -o 'ref=e[0-9]*' | cut -d= -f2)" >/dev/null; sleep 3
for _ in 1 2; do back=$(snap | grep -m1 -E 'button \[(active )?ref=' | grep -o 'ref=e[0-9]*' | cut -d= -f2); P click "$back" >/dev/null; sleep 2; done
click_label 'tab "3 T I P S"'; sleep 3
P click "$(snap | grep -m1 -F 'checkbox "Away team wins by 13 points or more Away 13+"' | grep -o 'ref=e[0-9]*' | cut -d= -f2)" >/dev/null
expect_text "the app warns that this is God Mode" "You are tipping in God Mode"
click_label 'button "Submit"'; sleep 5
expect "Bob gained a tip written by the admin" "'nrl-01-001' in tips.get(byname['Bob Smoke'][0],{})"
expect_no_denials "S7"

echo "== S8  admin: change a role (tipperRole, admin only under R1)"
click_label 'tab "P R O F I L E"'; sleep 2; click_label 'button "Admin Tippers"'; sleep 3
click_label 'button "Legacy Smoke - tipper'; sleep 3
sw=$(snap | grep -F 'switch [' | tail -1 | grep -o 'ref=e[0-9]*' | cut -d= -f2); P click "$sw" >/dev/null; sleep 1   # the second switch is "DAU Admin"
click_label 'button "Save"'; sleep 4
expect "Legacy now has role admin IN THE DATABASE (they are not on the rules' allowlist)" "byname['Legacy Smoke'][1]['role']=='admin'"
expect_no_denials "S8"

echo "== S9  escalation: a database-role admin who is NOT on the allowlist cannot write admin-only data"
login_email "newbie@smoke.example.test"
click_label 'tab "P R O F I L E"'; sleep 2
expect_text "post-merge login maps to the legacy record (no alias prompt, no duplicate)" "Legacy Smoke"
expect "no duplicate record was created by that login" "len(t)==4"
expect_text "the client UI offers admin options (it trusts the database role)" "Admin Teams"
click_label 'button "Admin Teams"'; sleep 3; click_label 'button "Carlton"'; sleep 3
tn=$(snap | grep -m1 -F 'textbox [ref=' | grep -o 'ref=e[0-9]*' | cut -d= -f2); P fill "$tn" "HIJACKED TEAM NAME" >/dev/null
P click "$(snap | grep -F -A1 'heading "Edit Team"' | tail -1 | grep -o 'ref=e[0-9]*' | cut -d= -f2)" >/dev/null   # the Save button, which follows the heading (the first button is Back)
expect_text "the app reports the failed save" "Failed to update the team record"
n=$(DENIED_COUNT); if [ "$n" -ge 1 ]; then PASS=$((PASS+1)); echo "  PASS  the rules refused it (permission_denied seen by the app)"; else FAIL=$((FAIL+1)); echo "  FAIL  no permission_denied seen"; fi
team=$((cd "$SMOKE" && "$ISO" env NODE_OPTIONS=--import=../support/no_production.mjs FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:8000 GCLOUD_PROJECT=demo-dau-rules node -e "
const {createRequire}=require('node:module'); const r=createRequire('$SMOKE/../../functions/');
const {initializeApp}=r('firebase-admin/app'); const {getDatabase}=r('firebase-admin/database');
const app=initializeApp({projectId:'demo-dau-rules',databaseURL:'https://demo-dau-rules-default-rtdb.firebaseio.com'});
getDatabase(app).ref('Teams/afl-Carlton/name').get().then(s=>{console.log(s.val());process.exit(0)});" 2>&1) | tail -1)
if [ "$team" = "Carlton" ]; then PASS=$((PASS+1)); echo "  PASS  the team name in the database is unchanged"; else FAIL=$((FAIL+1)); echo "  FAIL  team name is '$team'"; fi

echo "== S10 anonymous browsing"
fresh
click_label 'button "Tap here to view Stats"'; sleep 8
expect_text "anonymous user lands on Stats" "Competition Leaderboard"
expect "no tipper record created" "len(t)==4 and not any(v['isAnonymous'] for v in t.values())"
expect "an anonymous Auth user exists in the emulator" "any(u['anonymous'] for u in d['authUsers'])"
expect_no_denials "S10"

echo "== S11 a modified client (the same Firebase SDK, driven directly) against R1"
res=$(P run-code "$(cat "$SMOKE/attacker.js")" | grep -E '^"' | head -1)
echo "$res" | python3 -c "
import json,sys
data=json.loads(json.loads(sys.stdin.read().strip()))
bad=0
for who,rs in data.items():
    for k,v in rs.items():
        want = 'ALLOWED' if k[0] in 'CK' else 'DENIED'
        ok = (v==want)
        bad += 0 if ok else 1
        print(f\"  {'PASS' if ok else 'FAIL'}  [{who}] {k}: {v}\" + ('  (expected '+want+')' if not ok else ''))
sys.exit(1 if bad else 0)" && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

echo
echo "RESULT: $PASS group(s)/check(s) passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
