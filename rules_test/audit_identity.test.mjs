// Tests for scripts/audit_identity.mjs with a synthetic database (no real data).
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { after, describe, it } from 'node:test';
import { sandboxEnv } from './support/safety.mjs';
import { auditIdentity, auditKickoffReadiness, normaliseAlias, normaliseEmail } from '../scripts/audit_identity.mjs';

const uid = (c) => c.repeat(28);

const fixture = () => ({
  AppConfig: { currentDAUComp: 'c1' },
  AllTippers: {
    // healthy
    ok1: { authuid: uid('a'), tipperRole: 'tipper', name: 'Alpha', logon: 'alpha@x.test', email: 'alpha@x.test', acctLoggedOnUTC: 'x' },
    // placeholder authuid that is an email address; active this comp
    ph1: { authuid: 'old.sheet@x.test', tipperRole: 'tipper', name: 'Beta', logon: 'beta@x.test', email: 'beta@x.test' },
    // placeholder, dormant, shares its placeholder with ph3
    ph2: { authuid: 'shared@x.test', tipperRole: 'tipper', name: 'Gamma', email: 'gamma@x.test' },
    ph3: { authuid: 'shared@x.test', tipperRole: 'tipper', name: 'Delta', email: 'delta@x.test' },
    // two records with the same REAL uid
    dupA: { authuid: uid('d'), tipperRole: 'tipper', name: 'Dup One', logon: 'dup@x.test', email: 'dup@x.test' },
    dupB: { authuid: uid('d'), tipperRole: 'tipper', name: 'Dup Two', logon: 'dup@x.test', email: 'dup@x.test' },
    // missing authuid
    noUid: { tipperRole: 'tipper', name: 'Nouid', logon: 'nouid@x.test' },
    // admin with a placeholder (dangerous)
    admPh: { authuid: 'admin@x.test', tipperRole: 'admin', name: 'AdminPh', logon: 'admin@x.test', email: 'admin@x.test' },
    // healthy admin
    admOk: { authuid: uid('e'), tipperRole: 'admin', name: 'AdminOk', logon: 'adminok@x.test', email: 'adminok@x.test' },
    // alias collision under normalisation + emoji-only name + not normalised contact + no contact
    ali1: { authuid: uid('f'), tipperRole: 'tipper', name: 'Big Fan!', logon: 'Fan@X.test ', email: 'fan@x.test' },
    ali2: { authuid: uid('g'), tipperRole: 'tipper', name: 'bigfan', logon: 'fan2@x.test', email: 'fan2@x.test' },
    emoji: { authuid: uid('h'), tipperRole: 'tipper', name: '🏉🏉', logon: 'emoji@x.test', email: 'emoji@x.test' },
    nocontact: { authuid: uid('i'), tipperRole: 'tipper', name: 'Nocontact' },
    // logon equals another record's email
    cross: { authuid: uid('j'), tipperRole: 'tipper', name: 'Cross', logon: 'alpha@x.test', email: 'cross@x.test' },
    // long alias
    longname: { authuid: uid('k'), tipperRole: 'tipper', name: 'x'.repeat(70), logon: 'long@x.test', email: 'long@x.test' },
  },
  AllTips: { c1: { ph1: { g1: { r: 'a', t: 1 } }, ok1: { g1: { r: 'a', t: 1 } }, ghost: { g1: { r: 'a', t: 1 } } } },
  AllTippersTokens: { ok1: { tok: 'x' }, deletedTipper: { tok: 'y' } },
  DAUCompsGames: { c1: { g1: { DateUtc: '2026-03-05 09:50:00Z' }, g2: { DateUtc: 'garbage' }, g3: {} } },
});

describe('normalisation', () => {
  it('matches the client rule for aliases and the planned rule for emails', () => {
    assert.equal(normaliseAlias('Big Fan!'), 'bigfan');
    assert.equal(normaliseAlias(' B i g F a n '), 'bigfan');
    assert.equal(normaliseAlias('🏉🏉'), '');
    assert.equal(normaliseAlias('Zoë 7'), 'zoë7');
    assert.equal(normaliseEmail('  Fan@X.test '), 'fan@x.test');
  });
});

describe('auditIdentity (offline)', () => {
  it('classifies every problem the rollout must resolve', async () => {
    const { summary, findings } = await auditIdentity(fixture());
    assert.equal(summary.tippers, 15);
    assert.equal(summary.currentComp, 'c1');
    assert.equal(summary.activeInCurrentComp, 2);
    assert.equal(summary.placeholderAuthuid, 4); // ph1, ph2, ph3, admPh
    assert.equal(summary.placeholderAuthuidActiveCurrentComp, 1); // ph1
    assert.equal(summary.missingAuthuid, 1);
    assert.equal(summary.duplicateAuthuidGroupsRealUid, 1);
    assert.equal(summary.duplicateAuthuidGroupsPlaceholder, 1);
    assert.equal(summary.admins, 2);
    assert.equal(summary.adminsWithPlaceholderOrMissingUid, 1);
    assert.equal(summary.aliasCollisionGroups, 1);
    assert.equal(summary.aliasEmptyOrMissing, 1);
    assert.equal(summary.aliasLongerThanCap, 1);
    assert.equal(summary.noContactAtAll, 1);
    assert.equal(summary.notNormalisedContact, 1);
    // cross (logon = ok1's email) and the mutual pair dupA/dupB (each logon = the other's email)
    assert.equal(summary.logonEqualsOtherRecordsEmail, 3);
    assert.deepEqual(findings.logonEqualsOtherEmail.map((f) => f.tipperId).sort(), ['cross', 'dupA', 'dupB']);
    assert.equal(summary.tipNodesForMissingTipper, 1);
    assert.equal(summary.tokenNodesForMissingTipper, 1);
    assert.equal(summary.authChecked, false);

    const placeholderAdmin = findings.admins.find((a) => a.tipperId === 'admPh');
    assert.equal(placeholderAdmin.defaultUidShape, false);
    assert.equal(placeholderAdmin.accountOk, false);
    const realDup = findings.duplicateAuthuid.find((d) => d.kind === 'real-uid');
    assert.deepEqual(realDup.tipperIds.sort(), ['dupA', 'dupB']);
    assert.equal(realDup.sameLogon, true);
    assert.equal(findings.placeholders.find((p) => p.tipperId === 'ph1').category, 'email-address');
  });

  it('keeps personal data out of the findings; placeholders are returned separately', async () => {
    const { findings, placeholders } = await auditIdentity(fixture());
    assert.ok(!JSON.stringify(findings).includes('@'), 'no email address may appear in findings');
    assert.equal(placeholders.ph1, 'old.sheet@x.test');
  });

  it('never modifies its input', async () => {
    const db = fixture();
    const before = JSON.stringify(db);
    await auditIdentity(db);
    assert.equal(JSON.stringify(db), before);
  });

  it('copes with an empty or partial database', async () => {
    const { summary } = await auditIdentity({});
    assert.equal(summary.tippers, 0);
    assert.equal(summary.placeholderAuthuid, 0);
  });
});

describe('auditIdentity with Firebase Auth cross-check', () => {
  // A fake Auth: uid('a') exists with the right email; beta@ exists under a NEW uid; others unknown.
  const users = new Map([
    [uid('a'), { uid: uid('a'), email: 'alpha@x.test', emailVerified: true }],
    [uid('z'), { uid: uid('z'), email: 'beta@x.test', emailVerified: true }],
    [uid('y'), { uid: uid('y'), email: 'gamma@x.test', emailVerified: false }],
    [uid('d'), { uid: uid('d'), email: 'someone.else@x.test', emailVerified: true }],
  ]);
  const auth = {
    getUser: async (id) => users.get(id) ?? null,
    getUserByEmail: async (email) => [...users.values()].find((u) => u.email === email) ?? null,
  };

  it('proposes a backfill uid for placeholders, flags unverified emails and disagreements', async () => {
    const { summary, findings } = await auditIdentity(fixture(), { auth });
    assert.equal(summary.authChecked, true);
    const ph1 = findings.backfillCandidates.find((c) => c.tipperId === 'ph1');
    assert.equal(ph1.proposedUid, uid('z'));
    assert.equal(ph1.emailVerified, true);
    assert.equal(ph1.alreadyUsedByAnotherRecord, false);
    const ph2 = findings.backfillCandidates.find((c) => c.tipperId === 'ph2');
    assert.equal(ph2.proposedUid, uid('y'));
    assert.equal(ph2.emailVerified, false);
    assert.ok(summary.backfillCandidatesUnverifiedEmail >= 1);
    // A real uid whose Auth email is not the record's email is a disagreement.
    assert.ok(findings.authDisagreements.some((d) => d.tipperId === 'dupA' && d.kind === 'auth-email-differs-from-record'));
  });

  it('flags a proposed uid that another record already uses', async () => {
    const db = fixture();
    db.AllTippers.ok1.authuid = uid('z'); // some other record already owns beta@'s uid
    const { findings } = await auditIdentity(db, { auth });
    const ph1 = findings.backfillCandidates.find((c) => c.tipperId === 'ph1');
    assert.equal(ph1.alreadyUsedByAnotherRecord, true);
  });

  it('flags a real uid that does not exist in Auth', async () => {
    const { findings } = await auditIdentity(fixture(), { auth });
    // ali1 has a well-formed uid that is not in the fake Auth and no Auth user for its email
    assert.ok(findings.authDisagreements.some((d) => d.tipperId === 'ali1' && d.kind === 'uid-not-in-auth-and-no-auth-user-for-email'));
  });
});

describe('Firebase Auth, not string shape, decides what is an account', () => {
  const customUid = 'user-with-a-custom-id'; // 21 chars: not the generated format, still a valid Firebase uid
  const dbWith = () => {
    const db = fixture();
    db.AllTippers.custom = { authuid: customUid, tipperRole: 'tipper', name: 'Custom', logon: 'custom@x.test', email: 'custom@x.test' };
    db.AllTippers.stale = { authuid: uid('s'), tipperRole: 'tipper', name: 'Stale', logon: 'stale@x.test', email: 'stale@x.test' };
    return db;
  };
  const auth = {
    getUser: async (id) => (id === customUid ? { uid: customUid, email: 'custom@x.test', emailVerified: true } : id === uid('a') ? { uid: id, email: 'alpha@x.test', emailVerified: true } : null),
    getUserByEmail: async () => null,
  };

  it('without Auth, a non-28-character value is only a PROVISIONAL placeholder', async () => {
    const { findings, placeholdersConfirmedByAuth } = await auditIdentity(dbWith());
    assert.ok(findings.placeholders.some((p) => p.tipperId === 'custom'));
    assert.equal(findings.placeholders.find((p) => p.tipperId === 'custom').confirmedByAuth, false);
    assert.equal(placeholdersConfirmedByAuth, false);
  });

  it('with Auth, a legitimate non-28-character uid is an account and is protected from overwrite', async () => {
    const { findings, summary, placeholders } = await auditIdentity(dbWith(), { auth });
    assert.ok(!findings.placeholders.some((p) => p.tipperId === 'custom'));
    assert.equal(placeholders.custom, undefined);
    assert.ok(findings.nonDefaultShapeButInAuth.some((p) => p.tipperId === 'custom'));
    assert.equal(summary.authuidNonDefaultShapeButInAuth, 1);
  });

  it('with Auth, a generated-looking uid that is not an account is reported as a stale placeholder', async () => {
    const { findings } = await auditIdentity(dbWith(), { auth });
    const stale = findings.placeholders.find((p) => p.tipperId === 'stale');
    assert.equal(stale.category, 'default-shape-not-in-auth');
    assert.equal(stale.confirmedByAuth, true);
  });

  it('with Auth, an over-long value (more than 128 characters) can never be a uid and is not sent to Auth', async () => {
    const db = dbWith();
    db.AllTippers.huge = { authuid: 'x'.repeat(200), tipperRole: 'tipper', name: 'Huge', logon: 'huge@x.test' };
    const asked = [];
    const recording = { ...auth, getUser: async (id) => { asked.push(id); return auth.getUser(id); } };
    const { findings } = await auditIdentity(db, { auth: recording });
    assert.ok(findings.placeholders.some((p) => p.tipperId === 'huge'));
    assert.ok(!asked.includes('x'.repeat(200)), 'an impossible uid must not be sent to Auth');
    assert.ok(asked.includes(customUid), 'a plausible non-default uid must be sent to Auth');
  });
});

describe('auditKickoffReadiness', () => {
  it('counts games whose DateUtc cannot be converted to epoch milliseconds', () => {
    const { games, unparsable } = auditKickoffReadiness(fixture());
    assert.equal(games, 3);
    assert.deepEqual(unparsable.map((u) => u.gameKey).sort(), ['g2', 'g3']);
  });
});

describe('CLI safety', () => {
  const script = resolve(import.meta.dirname, '../scripts/audit_identity.mjs');
  // SAFETY: every spawn gets the isolated environment (no credentials, no network, demo project).
  const sandboxDir = mkdtempSync(join(tmpdir(), 'audit-cli-'));
  const cliEnv = sandboxEnv(sandboxDir);
  after(() => rmSync(sandboxDir, { recursive: true, force: true }));
  const withInput = (fn) => {
    const dir = mkdtempSync(join(tmpdir(), 'audit-'));
    try {
      const input = join(dir, 'export.json');
      writeFileSync(input, JSON.stringify(fixture()));
      const authExportPath = join(dir, 'auth-export.json');
      writeFileSync(authExportPath, JSON.stringify({ users: [{ localId: uid('a'), email: 'alpha@x.test', emailVerified: true }] }));
      return fn(input, authExportPath);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  };

  it('refuses to write exact placeholders (email addresses) to a path that is not git-ignored', () => {
    const target = resolve(import.meta.dirname, 'placeholders.should-not-exist.json');
    withInput((input, authExportPath) => {
      const r = spawnSync(process.execPath, [script, '--file', input, '--auth-export', authExportPath, '--placeholders-out', target], { encoding: 'utf8', env: cliEnv });
      assert.equal(r.status, 1);
      assert.match(r.stderr, /not git-ignored/);
      assert.equal(existsSync(target), false, 'nothing may be written');
    });
  });

  it('refuses --placeholders-out without an Auth check (shape alone cannot prove a value is not an account)', () => {
    const ignored = resolve(import.meta.dirname, 'node_modules', 'audit-test-needs-auth.json');
    withInput((input) => {
      const r = spawnSync(process.execPath, [script, '--file', input, '--placeholders-out', ignored], { encoding: 'utf8', env: cliEnv });
      assert.equal(r.status, 1);
      assert.match(r.stderr, /needs an Auth check/);
      assert.equal(existsSync(ignored), false);
    });
  });

  it('writes the placeholders to a git-ignored path, and the findings file holds no email addresses', () => {
    const ignoredDir = resolve(import.meta.dirname, 'node_modules'); // ignored by .gitignore (node_modules/)
    const placeholdersPath = join(ignoredDir, 'audit-test-placeholders.json');
    const findingsPath = join(ignoredDir, 'audit-test-findings.json');
    withInput((input, authExportPath) => {
      try {
        const r = spawnSync(process.execPath, [script, '--file', input, '--auth-export', authExportPath, '--placeholders-out', placeholdersPath, '--out', findingsPath], {
          encoding: 'utf8',
          env: cliEnv,
        });
        assert.equal(r.status, 0, r.stderr);
        assert.equal(JSON.parse(readFileSync(placeholdersPath, 'utf8')).ph1, 'old.sheet@x.test');
        assert.ok(!readFileSync(findingsPath, 'utf8').includes('@'));
        assert.ok(!r.stdout.includes('@'), 'the printed summary must not contain email addresses');
      } finally {
        rmSync(placeholdersPath, { force: true });
        rmSync(findingsPath, { force: true });
      }
    });
  });

  it('requires an input source', () => {
    const r = spawnSync(process.execPath, [script], { encoding: 'utf8', env: cliEnv });
    assert.equal(r.status, 1);
    assert.match(r.stderr, /--file|--live/);
  });
});
