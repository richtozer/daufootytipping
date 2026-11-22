// The kickoff backfill and verifier (scripts/backfill_kickoff_epoch.mjs): reads a database export,
// works out DateUtcEpochMs for every game, and refuses to call the data complete until every game has
// exactly that value.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { after, describe, it } from 'node:test';
import { kickoffEpochMs, planKickoffBackfill } from '../scripts/backfill_kickoff_epoch.mjs';
import { sandboxEnv } from './support/safety.mjs';

const vectors = JSON.parse(readFileSync(resolve(import.meta.dirname, '../config/kickoff-vectors.json'), 'utf8'));

const db = (extra = {}) => ({
  DAUCompsGames: {
    compA: {
      'nrl-01-001': { DateUtc: '2026-03-01 02:15:00Z', DateUtcEpochMs: 1772331300000 },
      'nrl-01-002': { DateUtc: '2026-03-01 04:30:00Z' },
      'afl-00-001': { DateUtc: '2026-03-05 08:30:00Z', DateUtcEpochMs: 1 },
    },
    compB: {
      'nrl-01-001': { DateUtc: '2025-03-02 00:00:00Z', DateUtcEpochMs: 1740873600000 },
    },
    ...extra,
  },
});

describe('kickoffEpochMs', () => {
  it('agrees with the Dart parser on every shared valid vector', () => {
    assert.ok(vectors.valid.length > 5);
    for (const { input, epochMs } of vectors.valid) {
      assert.equal(kickoffEpochMs(input), epochMs, `input ${JSON.stringify(input)}`);
    }
  });

  it('refuses every shared invalid vector, as the Dart parser does', () => {
    assert.ok(vectors.invalid.length > 5);
    for (const input of vectors.invalid) {
      assert.equal(kickoffEpochMs(input), null, `input ${JSON.stringify(input)}`);
    }
  });

  it('refuses things that are not text', () => {
    for (const value of [undefined, null, 17, {}, []]) {
      assert.equal(kickoffEpochMs(value), null);
    }
  });
});

describe('planKickoffBackfill', () => {
  it('counts games that are right, missing and wrong, across every comp', () => {
    const plan = planKickoffBackfill(db());

    assert.equal(plan.games, 4);
    assert.equal(plan.correct, 2);
    assert.deepEqual(plan.missing.map((g) => `${g.comp}/${g.gameKey}`), ['compA/nrl-01-002']);
    assert.deepEqual(plan.wrong.map((g) => `${g.comp}/${g.gameKey}`), ['compA/afl-00-001']);
    assert.deepEqual(plan.unreadable, []);
    assert.equal(plan.complete, false);
  });

  it('writes the patch only for what is missing or wrong, as database paths', () => {
    const plan = planKickoffBackfill(db());

    assert.deepEqual(plan.patch, {
      'DAUCompsGames/compA/nrl-01-002/DateUtcEpochMs': 1772339400000,
      'DAUCompsGames/compA/afl-00-001/DateUtcEpochMs': 1772699400000,
    });
  });

  it('is complete, with an empty patch, once every game is right', () => {
    const fixed = db();
    for (const [path, ms] of Object.entries(planKickoffBackfill(fixed).patch)) {
      const [, comp, game] = path.split('/');
      fixed.DAUCompsGames[comp][game].DateUtcEpochMs = ms;
    }

    const plan = planKickoffBackfill(fixed);

    assert.equal(plan.complete, true);
    assert.deepEqual(plan.patch, {});
    assert.equal(plan.correct, plan.games);
  });

  it('treats a value that is not a whole number as wrong, even if it looks right', () => {
    for (const bad of ['1772331300000', 1772331300000.5, null, true, {}]) {
      const plan = planKickoffBackfill({
        DAUCompsGames: { c: { g: { DateUtc: '2026-03-01 02:15:00Z', DateUtcEpochMs: bad } } },
      });
      assert.equal(plan.complete, false, `value ${JSON.stringify(bad)}`);
      assert.ok(plan.wrong.length + plan.missing.length === 1);
    }
  });

  it('cannot patch a game whose DateUtc is unreadable, and is not complete', () => {
    const plan = planKickoffBackfill(
      db({ compC: { x: { DateUtc: 'TBC' }, y: {}, z: 'not an object' } }),
    );

    assert.deepEqual(
      plan.unreadable.map((g) => `${g.comp}/${g.gameKey}`).sort(),
      ['compC/x', 'compC/y', 'compC/z'],
    );
    assert.equal(plan.complete, false);
    assert.equal(Object.keys(plan.patch).some((p) => p.includes('compC')), false);
  });

  it('an empty database is not complete: nothing to verify is not a pass', () => {
    assert.equal(planKickoffBackfill({}).complete, false);
    assert.equal(planKickoffBackfill({ DAUCompsGames: {} }).complete, false);
  });

  it('does not change the input', () => {
    const input = db();
    const before = JSON.stringify(input);
    planKickoffBackfill(input);
    assert.equal(JSON.stringify(input), before);
  });
});

describe('CLI', () => {
  const script = resolve(import.meta.dirname, '../scripts/backfill_kickoff_epoch.mjs');
  // SAFETY: every spawn gets the isolated environment (no credentials, no network, demo project).
  const sandboxDir = mkdtempSync(join(tmpdir(), 'kickoff-cli-'));
  const cliEnv = sandboxEnv(sandboxDir);
  after(() => rmSync(sandboxDir, { recursive: true, force: true }));

  const run = (args, data) => {
    const dir = mkdtempSync(join(tmpdir(), 'kickoff-'));
    try {
      const input = join(dir, 'export.json');
      writeFileSync(input, JSON.stringify(data));
      const patch = join(dir, 'patch.json');
      const r = spawnSync(process.execPath, [script, '--file', input, ...args(patch)], { encoding: 'utf8', env: cliEnv });
      return { ...r, patch, patchText: existsSync(patch) ? readFileSync(patch, 'utf8') : null };
    } finally {
      // read before removal by callers via patchText
    }
  };

  it('--verify exits 1 and says what is missing when the data is not complete', () => {
    const r = run(() => ['--verify'], db());
    assert.equal(r.status, 1);
    assert.match(r.stdout, /missing: 1/);
    assert.match(r.stdout, /wrong: 1/);
  });

  it('--verify exits 0 when every game is right', () => {
    const r = run(() => ['--verify'], {
      DAUCompsGames: { c: { g: { DateUtc: '2026-03-01 02:15:00Z', DateUtcEpochMs: 1772331300000 } } },
    });
    assert.equal(r.status, 0);
    assert.match(r.stdout, /complete/i);
  });

  it('--patch-out writes the patch file and exits 0 (a plan is not a failure)', () => {
    const r = run((patch) => ['--patch-out', patch], db());
    assert.equal(r.status, 0);
    assert.deepEqual(JSON.parse(r.patchText), {
      'DAUCompsGames/compA/nrl-01-002/DateUtcEpochMs': 1772339400000,
      'DAUCompsGames/compA/afl-00-001/DateUtcEpochMs': 1772699400000,
    });
  });

  it('never writes to a database: it has no live write mode', () => {
    // Code only: the usage comment is allowed to tell the operator how to apply a patch.
    const code = readFileSync(script, 'utf8')
      .split('\n')
      .filter((line) => !line.trim().startsWith('//'))
      .join('\n');
    assert.doesNotMatch(code, /\.set\(|\.update\(|\.remove\(|database:update|database:set/);
    assert.doesNotMatch(
      code,
      /child_process|spawn|execFile|execSync/,
      'it must not run another program (such as the Firebase CLI)',
    );
  });

  it('refuses to run with no input', () => {
    const r = spawnSync(process.execPath, [script], { encoding: 'utf8', env: cliEnv });
    assert.equal(r.status, 1);
    assert.match(r.stderr, /--file|--live/);
  });
});
