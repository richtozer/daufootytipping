// The LIVE code paths of the read-only scripts, run against the Auth and Database emulators with
// synthetic data. This is the combination the synthetic unit tests cannot cover: `--live
// --auth-check` initialises the Admin SDK for both the database read and the Auth lookups, and
// the SDK rejects a second initialisation with different options.
//
// ISOLATION (support/safety.mjs, DESIGN-database-rules-phase3.md section 8):
//   * the project is the demo- project the emulators run under; the production project is never
//     named in this file, and the scripts refuse to run against it in emulator mode;
//   * the scripts under test get a minimal environment: no credentials, an empty HOME, loopback
//     emulator hosts only, and the preload that refuses any non-loopback network access;
//   * the test is skipped unless BOTH emulator hosts are present, so it can never run "live".
//
// Run with:  npm run test:live
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { after, before, describe, it } from 'node:test';
import { sandboxEnv } from './support/safety.mjs';

const require = createRequire(new URL('../functions/', import.meta.url));
const { deleteApp, initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getDatabase } = require('firebase-admin/database');

const PROJECT_ID = 'demo-dau-rules'; // the project the emulators run under
const DATABASE_URL = `https://${PROJECT_ID}-default-rtdb.asia-southeast1.firebasedatabase.app`;
const scripts = resolve(import.meta.dirname, '../scripts');
const uid = (c) => c.repeat(28);

const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const databaseHost = process.env.FIREBASE_DATABASE_EMULATOR_HOST;
const emulated = Boolean(authHost && databaseHost);

let seedApp;
let sandboxDir;
let env;

describe('live CLI paths against the emulators', { skip: emulated ? false : 'run with `npm run test:live` (needs the Auth and Database emulators)' }, () => {
  before(async () => {
    sandboxDir = mkdtempSync(join(tmpdir(), 'live-cli-'));
    env = sandboxEnv(sandboxDir, {
      extra: { ADMIN_SCRIPTS_PROJECT_ID: PROJECT_ID, FIREBASE_AUTH_EMULATOR_HOST: authHost, FIREBASE_DATABASE_EMULATOR_HOST: databaseHost },
    });
    seedApp = initializeApp({ projectId: PROJECT_ID, databaseURL: DATABASE_URL }, 'live-test-seed');
    const auth = getAuth(seedApp);
    await auth.createUser({ uid: uid('a'), email: 'good.admin@example.test', emailVerified: true });
    await auth.createUser({ uid: uid('b'), email: 'beta@example.test', emailVerified: true }); // new account for a placeholder record
    await auth.createUser({ uid: 'custom-uid-not-28', email: 'custom@example.test', emailVerified: true }); // a legitimate non-28-char uid
    await getDatabase(seedApp).ref().set({
      AppConfig: { currentDAUComp: 'c1' },
      AllTippers: {
        adm: { name: 'Good Admin', tipperRole: 'admin', authuid: uid('a'), logon: 'good.admin@example.test', email: 'good.admin@example.test' },
        ph1: { name: 'Beta', tipperRole: 'tipper', authuid: 'old.sheet@example.test', logon: 'beta@example.test', email: 'beta@example.test' },
        cust: { name: 'Custom', tipperRole: 'tipper', authuid: 'custom-uid-not-28', logon: 'custom@example.test', email: 'custom@example.test' },
      },
      AllTips: { c1: { ph1: { g1: { r: 'a', t: 1 } } } },
      AllTippersTokens: {},
      DAUCompsGames: { c1: { g1: { DateUtc: '2026-03-05 09:50:00Z' } } },
    });
  });

  // The seeding app holds a database connection; close it or the test process never exits.
  after(async () => {
    if (seedApp) {
      getDatabase(seedApp).goOffline();
      await deleteApp(seedApp);
    }
    if (sandboxDir) rmSync(sandboxDir, { recursive: true, force: true });
  });

  const run = (script, args) => spawnSync(process.execPath, [join(scripts, script), ...args], { encoding: 'utf8', env, timeout: 90_000 });

  it('audit_identity --live --auth-check runs end to end (no Admin SDK double-initialisation)', () => {
    const r = run('audit_identity.mjs', ['--live', '--auth-check', '--json']);
    assert.equal(r.status, 0, `${r.stdout}\n${r.stderr}`);
    assert.doesNotMatch(r.stderr, /already exists|duplicate-app|different options|different configuration/i);
    const { summary } = JSON.parse(r.stdout);
    assert.equal(summary.tippers, 3);
    assert.equal(summary.authChecked, true);
    assert.equal(summary.backfillCandidates, 1); // ph1 -> the new Auth account for beta@
  });

  it('a non-default-shaped uid that IS an Auth account is not treated as a placeholder', () => {
    const r = run('audit_identity.mjs', ['--live', '--auth-check', '--json']);
    assert.equal(r.status, 0, r.stderr);
    const { summary } = JSON.parse(r.stdout);
    assert.equal(summary.placeholderAuthuidConfirmedByAuth, 1, 'only ph1 is confirmed as not an Auth account');
    assert.equal(summary.authuidNonDefaultShapeButInAuth, 1, 'cust must be protected from overwrite');
  });

  it('verify_admin_auth_uids runs live against the emulators', () => {
    const r = run('verify_admin_auth_uids.mjs', []);
    assert.equal(r.status, 0, `${r.stdout}\n${r.stderr}`);
    assert.match(r.stdout, /OK \(confirm this is the right person\)/);
  });
});
