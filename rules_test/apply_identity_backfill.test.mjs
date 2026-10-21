// scripts/apply-identity-backfill.sh run end to end.
//
// `firebase` is the sanctioned stub from support/safety.mjs (it records every call and never talks to anything).
// `dart` (the planner) and `node` (the Auth slimmer) are fakes that record their calls, hand back canned files and
// let each test decide what they "produce". What is proved here is the script's check-then-act logic: it refreshes
// the Auth accounts itself and never hands the planner the full export; it writes only when a fresh plan of the
// live data is byte-identical to the reviewed patch; it stops if the identity nodes change between its two reads;
// it never writes in check-only mode; and it fails loudly if the verification fails.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { afterEach, beforeEach, describe, it } from 'node:test';
import { PRODUCTION_PROJECT_ID, sandboxEnv } from './support/safety.mjs';

const script = resolve(import.meta.dirname, '..', 'scripts', 'apply-identity-backfill.sh');

const FAKE_DART = `#!/bin/bash
# Fake planner. --patch-out gets the canned fresh patch; --check answers from FAKE_CHECK_EXIT.
echo "dart $*" >> "$FAKE_DIR/firebase-calls.log"
file=""; patch_out=""; check=false
for ((i = 1; i <= $#; i++)); do
  [ "\${!i}" = "--file" ] && file="\${@:$((i + 1)):1}"
  [ "\${!i}" = "--patch-out" ] && patch_out="\${@:$((i + 1)):1}"
  [ "\${!i}" = "--check" ] && check=true
done
if [ "$check" = true ]; then echo "check output"; exit "\${FAKE_CHECK_EXIT:-0}"; fi
echo "plan output"
# While "planning", something changes the tipper list: plant a different first snapshot.
if [ -n "\${FAKE_CHANGE_DURING_PLAN:-}" ]; then
  echo changed > "$(dirname "$file")/snapshot-a/AllTippers.json"
fi
if [ "\${FAKE_PLAN_EXIT:-0}" != 0 ]; then exit "$FAKE_PLAN_EXIT"; fi
[ -n "$patch_out" ] && cp "$FAKE_FRESH_PATCH" "$patch_out"
exit 0
`;

// Fake slimmer: records its arguments and writes the slim accounts file (the second argument after the script).
const FAKE_NODE = `#!/bin/bash
echo "node $*" >> "$FAKE_DIR/firebase-calls.log"
echo '{"users":[{"uid":"u1"}]}' > "$3"
exit 0
`;

describe('apply-identity-backfill.sh', () => {
  let dir;
  const reviewed = '{\n  "TipperPrivate/a": {}\n}\n';

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'apply-identity-'));
    writeFileSync(join(dir, 'fake-dart'), FAKE_DART);
    writeFileSync(join(dir, 'fake-node'), FAKE_NODE);
    chmodSync(join(dir, 'fake-dart'), 0o755);
    chmodSync(join(dir, 'fake-node'), 0o755);
    writeFileSync(join(dir, 'reviewed.json'), reviewed);
    writeFileSync(join(dir, 'fresh.json'), reviewed);
  });
  afterEach(() => rmSync(dir, { recursive: true, force: true }));

  const run = (args, extraEnv = {}) =>
    spawnSync('/bin/bash', [script, ...args], {
      encoding: 'utf8',
      env: sandboxEnv(dir, {
        extra: {
          FAKE_DIR: dir,
          FAKE_FRESH_PATCH: join(dir, 'fresh.json'),
          DART_BIN: join(dir, 'fake-dart'),
          NODE_BIN: join(dir, 'fake-node'),
          ...extraEnv,
        },
      }),
    });
  const base = () => ['--patch', join(dir, 'reviewed.json')];
  const calls = () => (existsSync(join(dir, 'firebase-calls.log')) ? readFileSync(join(dir, 'firebase-calls.log'), 'utf8') : '');
  const lines = () => calls().split('\n').filter(Boolean);
  const applied = () => calls().includes('database:update');

  it('needs a patch, and the patch must exist, before touching anything', () => {
    assert.equal(run([]).status, 64);
    const missing = run(['--patch', join(dir, 'nope.json')]);
    assert.equal(missing.status, 1);
    assert.match(missing.stderr, /does not exist/);
    assert.equal(calls(), '');
  });

  it('refreshes the Auth accounts itself and gives the planner only the slim file', () => {
    const result = run(base());
    assert.equal(result.status, 0, result.stderr);
    const log = lines();
    assert.ok(log.some((line) => line.startsWith('auth:export ') && line.includes('auth-full.json')));
    const slim = log.find((line) => line.startsWith('node '));
    assert.match(slim, /slim_auth_export\.mjs .*auth-full\.json .*auth\.json --delete-input/);
    const planner = log.find((line) => line.startsWith('dart '));
    assert.match(planner, /--auth-accounts \S*\/auth\.json/);
    assert.doesNotMatch(planner, /auth-full/);
  });

  it('check only: confirms the live data still gives the reviewed patch and writes nothing', () => {
    const result = run(base());
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /exactly the reviewed patch/);
    assert.match(result.stdout, /Check only/);
    assert.equal(applied(), false);
  });

  it('writes nothing when the fresh plan is not the reviewed one', () => {
    writeFileSync(join(dir, 'fresh.json'), '{\n  "TipperPrivate/b": {}\n}\n');
    const result = run([...base(), '--apply']);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /no longer produces the patch you reviewed/);
    assert.equal(applied(), false);
  });

  it('writes nothing when the planner reports a problem', () => {
    const result = run([...base(), '--apply'], { FAKE_PLAN_EXIT: '2' });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Nothing was written/);
    assert.equal(applied(), false);
  });

  it('writes nothing when the identity nodes change while the patch is being checked', () => {
    const result = run([...base(), '--apply'], { FAKE_CHANGE_DURING_PLAN: '1' });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /\/AllTippers changed while the patch was being checked/);
    assert.equal(applied(), false);
  });

  it('reads every identity node twice, around the planning, and the second read is just before the write', () => {
    run([...base(), '--apply']);
    const log = lines();
    for (const root of ['AllTippers', 'TipperPrivate', 'AuthIndex', 'AliasIndex', 'LogonIndex', 'Placeholders']) {
      const reads = log.filter((line) => line.startsWith(`database:get /${root} `));
      assert.equal(reads.length, 2, root);
    }
    const update = log.findIndex((line) => line.includes('database:update'));
    const lastRootRead = Math.max(...log.map((line, index) => (line.startsWith('database:get /Placeholders ') ? index : -1)));
    assert.ok(lastRootRead < update, 'the second read comes before the write');
    assert.ok(update - lastRootRead <= 2, 'and nothing slow sits between them');
  });

  it('applies the reviewed patch to the named project with triggers off, then verifies', () => {
    const result = run([...base(), '--apply']);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(applied(), true);
    const log = calls();
    const update = lines().find((line) => line.includes('database:update'));
    assert.ok(update.includes(`--project ${PRODUCTION_PROJECT_ID}`), update);
    assert.match(update, /--disable-triggers/);
    assert.match(update, /reviewed\.json/);
    assert.ok(log.indexOf('auth:export') < log.indexOf('database:update'), 'refreshes Auth before it writes');
    assert.match(log.slice(log.indexOf('database:update')), /--check/, 'verifies after it writes');
    assert.match(result.stdout, /Done: the backfill is in place/);
    assert.match(result.stdout, /check output/, 'shows the verifier output, including any cutover findings');
  });

  it('fails loudly when the verification after the write finds a problem', () => {
    const result = run([...base(), '--apply'], { FAKE_CHECK_EXIT: '1' });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /does not match the plan after the write/);
  });

  it('passes the decisions and allowlist through to every planner run', () => {
    writeFileSync(join(dir, 'decisions.json'), '{}');
    writeFileSync(join(dir, 'allow.json'), '{}');
    run([...base(), '--decisions', join(dir, 'decisions.json'), '--allowlist', join(dir, 'allow.json'), '--apply']);
    const planners = lines().filter((line) => line.startsWith('dart '));
    assert.equal(planners.length, 2);
    for (const line of planners) {
      assert.match(line, /--decisions .*decisions\.json/);
      assert.match(line, /--allowlist .*allow\.json/);
    }
  });
});
