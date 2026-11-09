// FREEZE rules: R1-compat with every identity-bearing write closed to ALL clients, administrators included.
// DESIGN-database-rules-phase4.md section 8, step A1. Generated from the same template and allowlist as R1
// (FIXTURE admin UIDs only, never real ones).
//
// What is proved:
//   1. Structurally, freeze differs from R1-compat in exactly two places (the tipper record and the tipper level
//      of AllTips), and only by REMOVING writes, bar one narrow paid-toggle grant to administrators.
//   2. Nothing that identifies a tipper can change: no record is created, deleted or replaced, and `name`,
//      `email`, `logon` and `isAnonymous` cannot be written, by anyone. A tip node cannot be merged or deleted.
//   3. Everyday use carries on: tipping, reading, the paid toggle, photos, login timestamps, device tokens,
//      live-score entries, and the admin-only reference data.
//   4. The two R1-compat reads still work, and the server-only nodes stay closed.
//   5. What a 1.4.x client does at sign-in: a settled account signs in, and an account whose stored login differs
//      from its email is refused as a WHOLE batch (the known cost of a short freeze window).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { PATHS, buildRules } from '../scripts/build_admin_allowlist.mjs';

const ADMIN_UID = 'ADMINfixtureUID000000000001';
const template = readFileSync(PATHS.template, 'utf8');
const r1 = buildRules(template, [ADMIN_UID]);
const compat = buildRules(template, [ADMIN_UID], { variant: 'r1-compat' });
const freeze = buildRules(template, [ADMIN_UID], { variant: 'freeze' });

const google = { firebase: { sign_in_provider: 'google.com' } };
const anonymous = { firebase: { sign_in_provider: 'anonymous' } };
const actors = {
  unauth: null,
  anon: { uid: 'anonUid', token: anonymous },
  alice: { uid: 'aliceUid', token: google },
  bob: { uid: 'bobUid', token: google },
  admin: { uid: ADMIN_UID, token: google },
  // A user whose DATABASE record says admin, but who is not on the allowlist.
  fakeAdmin: { uid: 'fakeAdminUid', token: google },
};

const seed = () => ({
  AppConfig: { minAppVersion: '1.4.0', currentDAUComp: 'c1' },
  Teams: { a: { name: 'A' } },
  AllDAUComps: { c1: { name: '2027' } },
  DAUCompsGames: { c1: { g1: { DateUtc: 'x' } } },
  AllTippers: {
    t1: { authuid: 'aliceUid', tipperRole: 'tipper', name: 'Alice', email: 'alice@x.test', logon: 'alice@x.test', isAnonymous: false, photoURL: 'a.png', compsParticipatedIn: ['c1'] },
    t2: { authuid: 'bobUid', tipperRole: 'tipper', name: 'Bob', logon: 'Bob@X.test', email: 'bob@x.test', isAnonymous: false },
    tFake: { authuid: 'fakeAdminUid', tipperRole: 'admin', name: 'Fake' },
  },
  AllTips: { c1: { t1: { g1: { r: 'a', t: 1772000000 } }, t2: { g1: { r: 'b', t: 1772000000 } } } },
  AllTippersTokens: { t1: { tokA: 1 } },
  Stats: { c1: { live_scores_backend_v1: { g1: { history: { h0: { tipperID: 't1' } } } } } },
  AuthIndex: { aliceUid: 't1', bobUid: 't2' },
  TipperPrivate: {
    t1: { authuid: 'aliceUid', tipperRole: 'tipper' },
    t2: { authuid: 'bobUid', tipperRole: 'tipper' },
  },
  AliasIndex: { alice: 't1' },
  LogonIndex: { k: 't1' },
  Placeholders: { t1: 'p' },
  ServerConfig: { identity: { mode: 'freeze' } },
  ClaimMoves: { t1: { kind: 'alias' } },
  TokenOwners: { tok: { owner: 't1', seq: 1 } },
  CreateIntents: { aliceUid: { tipperId: 't1' } },
  IdentityLocks: { t1: 'op|1' },
});

describe('freeze is R1-compat with the identity writes taken out', () => {
  const writesOf = (rules) => {
    const found = [];
    const walk = (node, path) => {
      for (const [key, value] of Object.entries(node)) {
        if (key === '.write') found.push(path.join('/'));
        else if (value && typeof value === 'object' && !Array.isArray(value)) walk(value, [...path, key]);
      }
    };
    walk(rules.rules, []);
    return found.sort();
  };

  it('differs from R1-compat in the tipper record and the tipper level of AllTips, and nowhere else', () => {
    const changed = Object.keys(compat.rules).filter((key) => JSON.stringify(compat.rules[key]) !== JSON.stringify(freeze.rules[key]));
    assert.deepEqual(changed.sort(), ['AllTippers', 'AllTips']);
    assert.deepEqual(Object.keys(freeze.rules).sort(), Object.keys(compat.rules).sort());
  });

  it('has these writes, and only these, that R1-compat does not have: the paid toggle for administrators', () => {
    const before = writesOf(compat);
    const after = writesOf(freeze);
    assert.deepEqual(after.filter((w) => !before.includes(w)), ['AllTippers/$tipperId/compsParticipatedIn']);
    assert.match(freeze.rules.AllTippers.$tipperId.compsParticipatedIn['.write'], new RegExp(ADMIN_UID));
  });

  it('removes the whole-node writes, the record create and delete, and the identity-leaf writes', () => {
    const after = writesOf(freeze);
    for (const gone of [
      'AllTippers',
      'AllTippers/$tipperId',
      'AllTippers/$tipperId/name',
      'AllTippers/$tipperId/email',
      'AllTippers/$tipperId/logon',
      'AllTippers/$tipperId/isAnonymous',
      'AllTips/$comp/$tipperId',
    ]) {
      assert.ok(!after.includes(gone), `${gone} must have no .write in freeze`);
    }
    for (const kept of [
      'AllTippers/$tipperId/photoURL',
      'AllTippers/$tipperId/acctLoggedOnUTC',
      'AllTippers/$tipperId/acctCreatedUTC',
      'AllTips/$comp/$tipperId/$game',
      'AllTippersTokens/$tipperId/$token',
      'Stats/$comp/live_scores_backend_v1/$game/history/$key',
      'AppConfig',
      'DAUCompsGames',
    ]) {
      assert.ok(after.includes(kept), `${kept} must keep its .write in freeze`);
    }
  });

  it('adds no write that R1 did not have, except the narrow paid toggle', () => {
    const r1Writes = writesOf(r1);
    for (const write of writesOf(freeze)) {
      if (write === 'AllTippers/$tipperId/compsParticipatedIn') continue;
      assert.ok(r1Writes.includes(write), `${write} is new in freeze`);
    }
  });
});

describe('freeze against the rules engine', () => {
  let env;
  const db = (who) => {
    const a = actors[who];
    return (a === null ? env.unauthenticatedContext() : env.authenticatedContext(a.uid, a.token)).database();
  };
  const ok = (who, op) => assertSucceeds(op(db(who)));
  const no = (who, op) => assertFails(op(db(who)));
  const peek = async (path) => {
    let value;
    await env.withSecurityRulesDisabled(async (ctx) => {
      value = (await ctx.database().ref(path).get()).val();
    });
    return value;
  };

  before(async () => {
    env = await initializeTestEnvironment({ projectId: 'demo-dau-rules', database: { rules: JSON.stringify(freeze) } });
  });
  beforeEach(async () => {
    await env.clearDatabase();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.database().ref().set(seed());
    });
  });
  after(async () => env.cleanup());

  describe('identity cannot move', () => {
    it('no record is created, by a user or an administrator', async () => {
      const fresh = { authuid: 'erinUid', tipperRole: 'tipper', name: 'Erin' };
      await no('alice', (d) => d.ref('AllTippers/tNew').set(fresh));
      await no('admin', (d) => d.ref('AllTippers/tNew').set(fresh));
      await no('admin', (d) => d.ref('AllTippers').update({ tNew: fresh }));
      await no('admin', (d) => d.ref().update({ 'AllTippers/tNew': fresh }));
    });

    it('no record is deleted or replaced, by a user or an administrator', async () => {
      await no('alice', (d) => d.ref('AllTippers/t1').remove());
      await no('admin', (d) => d.ref('AllTippers/t1').remove());
      await no('admin', (d) => d.ref('AllTippers').remove());
      await no('admin', (d) => d.ref('AllTippers/t1').set({ authuid: 'aliceUid', tipperRole: 'tipper', name: 'Other' }));
      assert.equal((await peek('AllTippers/t1')).name, 'Alice');
    });

    it('name, email, logon and isAnonymous cannot be written by anyone', async () => {
      for (const field of ['name', 'email', 'logon', 'isAnonymous']) {
        for (const who of ['alice', 'bob', 'admin', 'fakeAdmin']) {
          await no(who, (d) => d.ref(`AllTippers/t1/${field}`).set(field === 'isAnonymous' ? true : 'changed'));
        }
      }
      assert.equal((await peek('AllTippers/t1')).name, 'Alice');
    });

    it('authuid and tipperRole still cannot be written (as in R1), and an administrator cannot promote anyone', async () => {
      for (const field of ['authuid', 'tipperRole']) {
        for (const who of ['alice', 'admin']) {
          await no(who, (d) => d.ref(`AllTippers/t2/${field}`).set(field === 'tipperRole' ? 'admin' : 'x'));
        }
      }
    });

    it('a tipper\'s whole tip node cannot be merged, replaced or deleted, even by an administrator', async () => {
      await no('admin', (d) => d.ref('AllTips/c1/t1').remove());
      await no('admin', (d) => d.ref('AllTips/c1/t2').set({ g1: { r: 'a', t: 1772000000 } }));
      await no('admin', (d) => d.ref().update({ 'AllTips/c1/t1': null, 'AllTips/c1/t2/g9': { r: 'a', t: 1772000000 } }));
      await no('alice', (d) => d.ref('AllTips/c1/t1').remove());
      assert.equal((await peek('AllTips/c1/t1/g1')).r, 'a');
    });

    it('a root update with one closed field changes nothing', async () => {
      await no('admin', (d) =>
        d.ref().update({ 'AllTippers/t1/compsParticipatedIn': ['c1', 'c2'], 'AllTippers/t1/name': 'Renamed' }),
      );
      assert.deepEqual(await peek('AllTippers/t1/compsParticipatedIn'), ['c1']);
    });
  });

  describe('everyday use carries on', () => {
    it('tipping works as in R1: a game-level tip write by a signed-in user', async () => {
      await ok('alice', (d) => d.ref('AllTips/c1/t1/g2').set({ r: 'c', t: 1772000001 }));
      await ok('alice', (d) => d.ref('AllTips/c1/t1/g1').set({ r: 'd', t: 1772000002 }));
      await ok('admin', (d) => d.ref('AllTips/c1/t2/g1').set({ r: 'e', t: 1772000003 })); // god mode, leaf by leaf
      await no('anon', (d) => d.ref('AllTips/c1/t1/g2').set({ r: 'c', t: 1772000001 }));
      await no('unauth', (d) => d.ref('AllTips/c1/t1/g2').set({ r: 'c', t: 1772000001 }));
    });

    it('everything is still readable, as in R1', async () => {
      for (const path of ['AllTippers', 'AllTips/c1', 'Stats/c1', 'AppConfig', 'Teams', 'AllDAUComps', 'DAUCompsGames/c1']) {
        await ok('unauth', (d) => d.ref(path).get());
      }
    });

    it('an administrator, and only an administrator, toggles a paid comp', async () => {
      await ok('admin', (d) => d.ref('AllTippers/t2/compsParticipatedIn').set(['c1']));
      assert.deepEqual(await peek('AllTippers/t2/compsParticipatedIn'), ['c1']);
      await ok('admin', (d) => d.ref('AllTippers/t1/compsParticipatedIn').set(['c1', 'c2']));
      await ok('admin', (d) => d.ref().update({ 'AllTippers/t1/compsParticipatedIn': ['c2'] }));
      await no('alice', (d) => d.ref('AllTippers/t1/compsParticipatedIn').set(['c1', 'c2', 'c3']));
      await no('fakeAdmin', (d) => d.ref('AllTippers/t2/compsParticipatedIn').set(['c9']));
      await no('anon', (d) => d.ref('AllTippers/t2/compsParticipatedIn').set(['c9']));
    });

    it('photos and login timestamps are still written by a signed-in user', async () => {
      await ok('alice', (d) => d.ref('AllTippers/t1/photoURL').set('new.png'));
      await ok('alice', (d) => d.ref('AllTippers/t1/acctLoggedOnUTC').set('2027-03-07T00:00:00.000Z'));
      await ok('alice', (d) => d.ref('AllTippers/t1/acctCreatedUTC').set('2026-01-01T00:00:00.000Z'));
      await no('anon', (d) => d.ref('AllTippers/t1/photoURL').set('x.png'));
    });

    it('device tokens are still written, live-score entries are still added, and the allowlisted admin still edits config', async () => {
      await ok('alice', (d) => d.ref('AllTippersTokens/t1/tokB').set(1));
      await ok('alice', (d) => d.ref('Stats/c1/live_scores_backend_v1/g1/history/h1').set({ tipperID: 't1', scoreTeam: 'home', interimScore: 6 }));
      await ok('alice', (d) => d.ref('Stats/c1/live_scores_backend_v1/g1/current').set({ homeInterimScore: 6 }));
      await ok('admin', (d) => d.ref('AppConfig/currentDAUComp').set('c2'));
      await ok('admin', (d) => d.ref('Teams/b').set({ name: 'B' }));
      await no('alice', (d) => d.ref('AppConfig/currentDAUComp').set('c2'));
      await no('fakeAdmin', (d) => d.ref('AppConfig/currentDAUComp').set('c2'));
    });
  });

  describe('the R1-compat reads still work, and the server-only nodes stay closed', () => {
    it('a user reads their own AuthIndex entry and their own private record, and nobody else\'s', async () => {
      assert.equal((await ok('alice', (d) => d.ref('AuthIndex/aliceUid').get())).val(), 't1');
      await ok('alice', (d) => d.ref('TipperPrivate/t1').get());
      await no('alice', (d) => d.ref('AuthIndex/bobUid').get());
      await no('alice', (d) => d.ref('TipperPrivate/t2').get());
      await ok('admin', (d) => d.ref('TipperPrivate').get());
    });

    for (const path of ['AuthIndex/aliceUid', 'TipperPrivate/t1', 'AliasIndex', 'LogonIndex', 'Placeholders', 'ServerConfig', 'ClaimMoves', 'TokenOwners', 'CreateIntents', 'IdentityLocks']) {
      it(`${path} cannot be written by anyone`, async () => {
        for (const who of ['alice', 'admin', 'unauth']) {
          await no(who, (d) => d.ref(path).set('x'));
        }
      });
    }

    for (const path of ['AliasIndex', 'LogonIndex', 'Placeholders', 'ServerConfig', 'ClaimMoves', 'TokenOwners', 'CreateIntents', 'IdentityLocks']) {
      it(`${path} cannot be read by anyone`, async () => {
        for (const who of ['alice', 'admin', 'unauth']) {
          await no(who, (d) => d.ref(path).get());
        }
      });
    }
  });

  describe('a 1.4.x client at sign-in', () => {
    // What the client writes: only attributes that differ from the stored record, as one root update.
    it('a settled account signs in: nothing identity-bearing differs, and its photo and timestamps are written', async () => {
      await ok('alice', (d) =>
        d.ref().update({
          'AllTippers/t1/photoURL': 'google.png',
          'AllTippers/t1/acctLoggedOnUTC': '2027-03-07T01:00:00.000Z',
          'AllTippers/t1/acctCreatedUTC': '2026-01-01T00:00:00.000Z',
        }),
      );
    });

    it('an account whose stored login differs from its email has the whole batch refused', async () => {
      // t2.logon is "Bob@X.test"; the account's email is "bob@x.test", so the client tries to rewrite it.
      await no('bob', (d) =>
        d.ref().update({ 'AllTippers/t2/logon': 'bob@x.test', 'AllTippers/t2/photoURL': 'google.png' }),
      );
      assert.equal((await peek('AllTippers/t2')).logon, 'Bob@X.test');
      assert.equal((await peek('AllTippers/t2')).photoURL, undefined, 'all or nothing');
    });
  });
});
