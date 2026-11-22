// Offline mode, shared access helpers and fail-fast behaviour of the read-only
// admin/identity scripts. Uses synthetic data only. The "no credentials" tests
// sandbox HOME and GOOGLE_APPLICATION_CREDENTIALS so they can never reach production.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { after, describe, it } from 'node:test';
import { sandboxEnv } from './support/safety.mjs';
import { assertSafeSensitiveInput, authLookupFromExport, tippersFromExport } from '../scripts/lib/admin_access.mjs';
import { verifyAdmins } from '../scripts/verify_admin_auth_uids.mjs';

const uid = (c) => c.repeat(28);
const scripts = resolve(import.meta.dirname, '../scripts');

// Shape of `firebase auth:export <file>.json` (hashes included, which the code must ignore).
const authExport = () => ({
  users: [
    { localId: uid('a'), email: 'Good.Admin@X.test', emailVerified: true, passwordHash: 'SECRET-HASH', salt: 'SECRET-SALT', providerUserInfo: [{ providerId: 'google.com', rawId: '1', email: 'good.admin@x.test' }] },
    { localId: uid('b'), email: 'other@x.test', emailVerified: true, providerUserInfo: [{ providerId: 'password' }] },
    { localId: uid('c'), email: 'unverified@x.test', emailVerified: false, providerUserInfo: [{ providerId: 'password' }] },
    { localId: uid('z'), providerUserInfo: [] }, // anonymous: no email
  ],
});

const tippers = () => ({
  t1: { name: 'Good Admin', tipperRole: 'admin', authuid: uid('a'), logon: 'good.admin@x.test' },
  t2: { name: 'Mismatch', tipperRole: 'admin', authuid: uid('b'), logon: 'admin2@x.test' },
  t3: { name: 'Unverified', tipperRole: 'admin', authuid: uid('c'), logon: 'unverified@x.test' },
  t4: { name: 'Ghost', tipperRole: 'admin', authuid: uid('d'), logon: 'ghost@x.test' },
  t5: { name: 'Placeholder', tipperRole: 'admin', authuid: 'sheet@x.test', logon: 'sheet@x.test' },
  t6: { name: 'Ordinary', tipperRole: 'tipper', authuid: uid('e'), logon: 'tipper@x.test' },
});

describe('authLookupFromExport', () => {
  const lookup = authLookupFromExport(authExport());
  it('indexes users by uid and (normalised) email', async () => {
    assert.equal(lookup.size, 4);
    assert.equal((await lookup.getUser(uid('a'))).email, 'Good.Admin@X.test');
    assert.equal((await lookup.getUserByEmail(' good.admin@x.test ')).uid, uid('a'));
    assert.equal(await lookup.getUser(uid('q')), null);
    assert.equal(await lookup.getUserByEmail('nobody@x.test'), null);
  });
  it('exposes providers and never carries password hashes', async () => {
    const user = await lookup.getUser(uid('a'));
    assert.deepEqual(user.providerData, [{ providerId: 'google.com' }]);
    assert.ok(!JSON.stringify(user).includes('SECRET'));
  });
  it('tolerates an empty or malformed export', () => {
    assert.equal(authLookupFromExport({}).size, 0);
    assert.equal(authLookupFromExport(null).size, 0);
  });
});

describe('tippersFromExport', () => {
  it('accepts a whole-database export or just the AllTippers map', () => {
    assert.deepEqual(Object.keys(tippersFromExport({ AllTippers: tippers() })), ['t1', 't2', 't3', 't4', 't5', 't6']);
    assert.deepEqual(Object.keys(tippersFromExport(tippers())), ['t1', 't2', 't3', 't4', 't5', 't6']);
  });
});

describe('verifyAdmins', () => {
  it('verifies the good admin and flags every problem', async () => {
    const rows = await verifyAdmins(tippers(), authLookupFromExport(authExport()));
    const by = Object.fromEntries(rows.map((r) => [r.name, r]));
    assert.equal(rows.length, 5); // the ordinary tipper is not listed
    assert.match(by['Good Admin'].verdict, /^OK/);
    assert.match(by.Mismatch.verdict, /^REVIEW/);
    assert.equal(by.Mismatch.emailMatchesRecord, false);
    assert.match(by.Unverified.verdict, /^REVIEW/);
    assert.equal(by.Unverified.emailVerified, false);
    assert.equal(by.Ghost.verdict, 'NOT VERIFIED');
    assert.equal(by.Ghost.authError, 'auth/user-not-found');
    assert.equal(by.Placeholder.verdict, 'NOT VERIFIED');
    assert.equal(by.Placeholder.defaultUidShape, false);
  });
  it('asks Auth about any plausible uid, so a legitimate custom (non-28-character) admin uid verifies', async () => {
    const exported = authExport();
    exported.users.push({ localId: 'custom-admin-uid', email: 'custom.admin@x.test', emailVerified: true, providerUserInfo: [{ providerId: 'custom' }] });
    const t = { ...tippers(), tc: { name: 'Custom Admin', tipperRole: 'admin', authuid: 'custom-admin-uid', logon: 'custom.admin@x.test' } };
    const rows = await verifyAdmins(t, authLookupFromExport(exported));
    const custom = rows.find((r) => r.name === 'Custom Admin');
    assert.equal(custom.defaultUidShape, false);
    assert.equal(custom.existsInAuth, true);
    assert.match(custom.verdict, /^OK/);
  });
  it('flags a uid shared with another record', async () => {
    const t = tippers();
    t.t6.authuid = uid('a');
    const rows = await verifyAdmins(t, authLookupFromExport(authExport()));
    assert.match(rows.find((r) => r.name === 'Good Admin').verdict, /^REVIEW/);
  });
});

describe('assertSafeSensitiveInput', () => {
  it('allows files outside the repository', () => {
    const dir = mkdtempSync(join(tmpdir(), 'sensitive-'));
    try {
      const file = join(dir, 'auth.json');
      writeFileSync(file, '{}');
      assert.doesNotThrow(() => assertSafeSensitiveInput(file));
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
  it('refuses a file inside the repository that git does not ignore (it contains password hashes)', () => {
    const file = resolve(import.meta.dirname, 'auth-export.should-not-exist.json');
    writeFileSync(file, '{}');
    try {
      assert.throws(() => assertSafeSensitiveInput(file), /password hashes/);
    } finally {
      rmSync(file, { force: true });
    }
  });
  it('allows a file inside the repository that git ignores', () => {
    const file = resolve(import.meta.dirname, 'node_modules', 'auth-export-test.json');
    writeFileSync(file, '{}');
    try {
      assert.doesNotThrow(() => assertSafeSensitiveInput(file));
    } finally {
      rmSync(file, { force: true });
    }
  });
});

describe('CLIs run offline from Firebase CLI exports', () => {
  const withFiles = (fn) => {
    const dir = mkdtempSync(join(tmpdir(), 'offline-'));
    try {
      const db = join(dir, 'db.json');
      const tippersOnly = join(dir, 'tippers.json');
      const auth = join(dir, 'auth-export.json');
      writeFileSync(db, JSON.stringify({ AllTippers: tippers(), AppConfig: { currentDAUComp: 'c1' } }));
      writeFileSync(tippersOnly, JSON.stringify(tippers()));
      writeFileSync(auth, JSON.stringify(authExport()));
      return fn({ db, tippersOnly, auth });
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  };
  // SAFETY: isolated environment (no credentials, no network, demo project); never process.env.
  const sandboxDir = mkdtempSync(join(tmpdir(), 'offline-env-'));
  const cliEnv = sandboxEnv(sandboxDir);
  after(() => rmSync(sandboxDir, { recursive: true, force: true }));
  const run = (script, args) =>
    spawnSync(process.execPath, [join(scripts, script), ...args], { encoding: 'utf8', env: cliEnv, timeout: 60_000 });

  it('verify_admin_auth_uids: --db-file (tippers only) with --auth-export prints verdicts and exits 0', () => {
    withFiles(({ tippersOnly, auth }) => {
      const r = run('verify_admin_auth_uids.mjs', ['--db-file', tippersOnly, '--auth-export', auth]);
      assert.equal(r.status, 0, r.stderr);
      assert.match(r.stdout, /Admin records found in \/AllTippers: 5/);
      assert.match(r.stdout, /OK \(confirm this is the right person\)/);
      assert.match(r.stdout, /REVIEW: exists in Auth/);
      assert.ok(!r.stdout.includes('SECRET'), 'password hashes must never be printed');
    });
  });
  it('verify_admin_auth_uids: --json output is valid JSON', () => {
    withFiles(({ db, auth }) => {
      const r = run('verify_admin_auth_uids.mjs', ['--db-file', db, '--auth-export', auth, '--json']);
      assert.equal(r.status, 0, r.stderr);
      assert.equal(JSON.parse(r.stdout).length, 5);
    });
  });
  it('verify_admin_auth_uids: rejects an auth export that is not an auth export', () => {
    withFiles(({ tippersOnly }) => {
      const r = run('verify_admin_auth_uids.mjs', ['--db-file', tippersOnly, '--auth-export', tippersOnly]);
      assert.equal(r.status, 1);
      assert.match(r.stderr, /no users/);
    });
  });
  it('audit_identity: --file with --auth-export reports an Auth-checked summary', () => {
    withFiles(({ db, auth }) => {
      const r = run('audit_identity.mjs', ['--file', db, '--auth-export', auth, '--json']);
      assert.equal(r.status, 0, r.stderr);
      const out = JSON.parse(r.stdout);
      assert.equal(out.summary.authChecked, true);
      assert.equal(out.summary.tippers, 6);
      assert.ok(!r.stdout.includes('SECRET') && !r.stdout.includes('@'));
    });
  });
});

describe('live mode fails fast and helpfully without credentials', () => {
  // The project id is a non-existent `fixture-` project (never the real one), there are no
  // credentials (minimal env, empty HOME), and the no-network preload is active, so this run
  // cannot reach anything. It proves the script's behaviour when credentials are missing.
  const sandboxDir = mkdtempSync(join(tmpdir(), 'nocreds-'));
  const env = sandboxEnv(sandboxDir, { extra: { ADMIN_SCRIPTS_PROJECT_ID: 'fixture-live-no-credentials' } });
  after(() => rmSync(sandboxDir, { recursive: true, force: true }));

  for (const [script, args] of [
    ['verify_admin_auth_uids.mjs', []],
    ['audit_identity.mjs', ['--live']],
  ]) {
    it(`${script} exits 1 quickly with the fix, instead of hanging`, () => {
      const started = Date.now();
      const r = spawnSync(process.execPath, [join(scripts, script), ...args], { encoding: 'utf8', env, timeout: 45_000 });
      assert.equal(r.status, 1, r.stdout + r.stderr);
      assert.match(r.stderr, /gcloud auth application-default login/);
      assert.match(r.stderr, /firebase auth:export/);
      assert.ok(Date.now() - started < 30_000, 'must not hang');
    });
  }

  it('a live run against a demo- project is refused (no emulator is configured)', () => {
    const demoEnv = sandboxEnv(sandboxDir);
    const r = spawnSync(process.execPath, [join(scripts, 'verify_admin_auth_uids.mjs')], { encoding: 'utf8', env: demoEnv, timeout: 45_000 });
    assert.equal(r.status, 1);
    assert.match(r.stderr, /Refusing to run live against the demo project/);
  });

  it('emulator mode with a non-demo project is refused', () => {
    const emulatorEnv = sandboxEnv(sandboxDir, {
      extra: { ADMIN_SCRIPTS_PROJECT_ID: 'fixture-live-no-credentials', FIREBASE_DATABASE_EMULATOR_HOST: '127.0.0.1:9' },
    });
    const r = spawnSync(process.execPath, [join(scripts, 'verify_admin_auth_uids.mjs')], { encoding: 'utf8', env: emulatorEnv, timeout: 45_000 });
    assert.equal(r.status, 1);
    assert.match(r.stderr, /emulators are configured but the project is/);
  });
});
