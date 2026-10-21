// scripts/apply-identity-backfill.sh run end to end against FAKE `firebase` and `dart` executables.
//
// `firebase` is the sanctioned stub from support/safety.mjs (it records every call and never talks to anything);
// `dart` is a fake that hands back a canned patch and lets each test decide what the planner "produces" and
// whether the final check passes. What is proved here is the
// script's check-then-act logic: it writes only when a fresh plan of the live data is byte-identical to the
// reviewed patch, it never writes in check-only mode, and it fails loudly if the verification fails.
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
patch_out=""; check=false
for ((i = 1; i <= $#; i++)); do
  [ "\${!i}" = "--patch-out" ] && patch_out="\${@:$((i + 1)):1}"
  [ "\${!i}" = "--check" ] && check=true
done
if [ "$check" = true ]; then echo "check output"; exit "\${FAKE_CHECK_EXIT:-0}"; fi
echo "plan output"
if [ "\${FAKE_PLAN_EXIT:-0}" != 0 ]; then exit "$FAKE_PLAN_EXIT"; fi
[ -n "$patch_out" ] && cp "$FAKE_FRESH_PATCH" "$patch_out"
exit 0
`;

describe('apply-identity-backfill.sh', () => {
  let dir;
  const reviewed = '{\n  "TipperPrivate/a": {}\n}\n';

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'apply-identity-'));
    writeFileSync(join(dir, 'fake-dart'), FAKE_DART);
    chmodSync(join(dir, 'fake-dart'), 0o755);
    writeFileSync(join(dir, 'reviewed.json'), reviewed);
    writeFileSync(join(dir, 'fresh.json'), reviewed);
    writeFileSync(join(dir, 'auth.json'), '{"users":[]}');
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
          ...extraEnv,
        },
      }),
    });
  const base = () => ['--patch', join(dir, 'reviewed.json'), '--auth-export', join(dir, 'auth.json')];
  const calls = () => (existsSync(join(dir, 'firebase-calls.log')) ? readFileSync(join(dir, 'firebase-calls.log'), 'utf8') : '');
  const applied = () => calls().includes('database:update');

  it('needs a patch and an Auth export', () => {
    assert.equal(run([]).status, 64);
    assert.equal(run(['--patch', join(dir, 'reviewed.json')]).status, 64);
    assert.equal(calls(), '');
  });

  it('refuses a patch or Auth export that does not exist, before touching anything', () => {
    const result = run(['--patch', join(dir, 'nope.json'), '--auth-export', join(dir, 'auth.json')]);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /does not exist/);
    assert.equal(calls(), '');
  });

  it('check only: confirms the live data still gives the reviewed patch and writes nothing', () => {
    const result = run(base());
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /exactly the reviewed patch/);
    assert.match(result.stdout, /Check only/);
    assert.equal(applied(), false);
    assert.doesNotMatch(calls(), /database:update/);
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

  it('applies the reviewed patch to the named project with triggers off, then verifies', () => {
    const result = run([...base(), '--apply']);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(applied(), true);
    const log = calls();
    const update = log.split('\n').find((line) => line.includes('database:update'));
    assert.ok(update.includes(`--project ${PRODUCTION_PROJECT_ID}`), update);
    assert.match(update, /--disable-triggers/);
    assert.match(update, /reviewed\.json/);
    assert.ok(log.indexOf('database:get') < log.indexOf('database:update'), 'reads before it writes');
    assert.match(log.slice(log.indexOf('database:update')), /--check/, 'verifies after it writes');
    assert.match(result.stdout, /Done/);
  });

  it('fails loudly when the verification after the write finds a problem', () => {
    const result = run([...base(), '--apply'], { FAKE_CHECK_EXIT: '1' });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /does not match the plan after the write/);
  });

  it('passes the approved links and allowlist through to every planner run', () => {
    writeFileSync(join(dir, 'links.json'), '{}');
    writeFileSync(join(dir, 'allow.json'), '{}');
    run([...base(), '--approved-links', join(dir, 'links.json'), '--allowlist', join(dir, 'allow.json'), '--apply']);
    const planners = calls().split('\n').filter((line) => line.startsWith('dart '));
    assert.equal(planners.length, 2);
    for (const line of planners) {
      assert.match(line, /--approved-links .*links\.json/);
      assert.match(line, /--allowlist .*allow\.json/);
    }
  });
});
