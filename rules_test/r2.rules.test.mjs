// R2 (final) rules. DESIGN-database-rules.md D1 to D8 and DESIGN-database-rules-phase4.md sections 3, 8 and 10.
// Generated from their own template; they take NO allowlist (FIXTURE uids only below, never real ones).
//
// What is proved:
//   1. Structurally: no allowlist literal anywhere, no client write on any identity node, and the output does
//      not depend on the allowlist at all.
//   2. An administrator is the validated private role and nothing else: a retired R1 allowlist uid, a user whose
//      PUBLIC record says admin, a tampered index, an anonymous session, an unlinked user are all not admins.
//   3. Every lookup fails closed, including with a missing, dangling or half-written link (rule errors deny).
//   4. Tip secrecy and the kickoff lock, to the millisecond, with a missing or non-numeric kickoff failing closed.
//   5. Tipper records: no client can create, delete or rename; the only direct writes are the owner's photo and an
//      administrator's paid toggle.
//   6. Live-score history is append-only, own-tipper only, started-and-not-official only, with the server's own
//      timestamp; `current` and every other node belongs to the server.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { PATHS, buildRules } from '../scripts/build_admin_allowlist.mjs';

const ALLOWLISTED_UID = 'ADMINfixtureUID000000000001'; // an R1 allowlist uid: retired in R2
const r1Template = readFileSync(PATHS.template, 'utf8');
const r2Template = readFileSync(PATHS.r2Template, 'utf8');
const r2 = buildRules(r2Template, [ALLOWLISTED_UID], { variant: 'r2' });

const google = { firebase: { sign_in_provider: 'google.com' } };
const anonymous = { firebase: { sign_in_provider: 'anonymous' } };

const actors = {
  unauth: null,
  anon: { uid: 'anonUid', token: anonymous }, // a perfect admin link, but an anonymous session
  alice: { uid: 'aliceUid', token: google },
  bob: { uid: 'bobUid', token: google },
  carol: { uid: 'carolUid', token: google }, // the index names tCarol, whose record names someone else
  dave: { uid: 'daveUid', token: google }, // the index names tDave, whose record names nobody
  erin: { uid: 'erinUid', token: google }, // signed in, no index entry
  frank: { uid: 'frankUid', token: google }, // the index names a record that does not exist
  admin: { uid: 'adminUid', token: google },
  allowlisted: { uid: ALLOWLISTED_UID, token: google }, // on the retired R1 allowlist, not linked
  publicAdmin: { uid: 'pubAdminUid', token: google }, // PUBLIC record says admin; the private role says tipper
  spoof: { uid: 'spoofUid', token: google }, // the index points at the admin's record, which names the admin
};

const NOW = Date.now();
const PAST = NOW - 3_600_000;
const FUTURE = NOW + 3_600_000;
const nowSeconds = () => Math.floor(Date.now() / 1000);

const tipOf = (r = 'a') => ({ r, t: nowSeconds() });

const seed = () => ({
  AppConfig: { minAppVersion: '1.4.0', currentDAUComp: 'c1' },
  Teams: { 'nrl-a': { name: 'A' } },
  AllDAUComps: { c1: { name: '2027' } },
  DAUCompsGames: {
    c1: {
      started: { DateUtc: 'x', DateUtcEpochMs: PAST },
      upcoming: { DateUtc: 'x', DateUtcEpochMs: FUTURE },
      noKickoff: { DateUtc: 'x' },
      badKickoff: { DateUtc: 'x', DateUtcEpochMs: 'soon' },
      official: { DateUtc: 'x', DateUtcEpochMs: PAST, HomeTeamScore: 20, AwayTeamScore: 10 },
      oneScore: { DateUtc: 'x', DateUtcEpochMs: PAST, HomeTeamScore: 20 },
    },
  },
  // Pre-purge shape: the public record still carries its identity fields. R2 must not trust any of them.
  AllTippers: {
    t1: { name: 'Alice', photoURL: 'a.png', authuid: 'aliceUid', tipperRole: 'tipper', email: 'a@x.test', compsParticipatedIn: ['c1'] },
    t2: { name: 'Bob', authuid: 'bobUid', tipperRole: 'tipper', email: 'b@x.test' },
    tAdmin: { name: 'Root', authuid: 'adminUid', tipperRole: 'admin' },
    tPub: { name: 'Pub', authuid: 'pubAdminUid', tipperRole: 'admin' },
  },
  AuthIndex: {
    aliceUid: 't1',
    bobUid: 't2',
    adminUid: 'tAdmin',
    anonUid: 'tAnon',
    carolUid: 'tCarol',
    daveUid: 'tDave',
    frankUid: 'tNowhere',
    pubAdminUid: 'tPub',
    spoofUid: 'tAdmin',
  },
  TipperPrivate: {
    t1: { authuid: 'aliceUid', tipperRole: 'tipper', logon: 'a@x.test' },
    t2: { authuid: 'bobUid', tipperRole: 'tipper', logon: 'b@x.test' },
    tAdmin: { authuid: 'adminUid', tipperRole: 'admin', logon: 'root@x.test' },
    tAnon: { authuid: 'anonUid', tipperRole: 'admin' },
    tCarol: { authuid: 'someoneElseUid', tipperRole: 'admin' },
    tDave: { tipperRole: 'admin' },
    tPub: { authuid: 'pubAdminUid', tipperRole: 'tipper' },
  },
  AllTips: {
    c1: {
      t1: { started: tipOf('a'), upcoming: tipOf('b'), noKickoff: tipOf('c'), badKickoff: tipOf('d') },
      t2: { started: tipOf('e'), upcoming: tipOf('a') },
    },
  },
  Stats: {
    c1: {
      live_scores_backend_v1: {
        started: {
          current: { homeInterimScore: 6 },
          history: { old: { tipperID: 't2', scoreTeam: 'home', interimScore: 6, t: PAST } },
        },
      },
      scoring_status: { status: 'completed' },
      round_stats_backend_v1: { 1: { t1: { total: 1 } } },
    },
  },
  Diagnostics: { androidResumeProbe: 'nonce' },
  AllTippersTokens: { t1: { tokA: 1 } },
  AliasIndex: { alice: 't1' },
  LogonIndex: { someKey: 't1' },
  Placeholders: { t1: 'placeholder' },
  ServerConfig: { identity: { mode: 'coexist' }, liveScores: { mode: 'active' } },
  ClaimMoves: { t1: { kind: 'alias' } },
  TokenOwners: { tok: { owner: 't1', seq: 1 } },
  CreateIntents: { aliceUid: { tipperId: 't1' } },
  IdentityLocks: { t1: 'op|1' },
  IdentityOps: { op1: { step: 1 } },
});

describe('r2 structure', () => {
  const walk = (node, visit, path = []) => {
    for (const [key, value] of Object.entries(node)) {
      visit(key, value, [...path, key]);
      if (value && typeof value === 'object' && !Array.isArray(value)) walk(value, visit, [...path, key]);
    }
  };

  it('has no allowlist in it: no uid literal anywhere, and the output ignores the allowlist entirely', () => {
    const text = JSON.stringify(r2);
    assert.doesNotMatch(text, /auth\.uid === '/, 'a uid literal is an allowlist');
    assert.ok(!text.includes(ALLOWLISTED_UID));
    for (const uids of [[], ['a'], ['a', 'b', 'c']]) {
      assert.deepEqual(buildRules(r2Template, uids, { variant: 'r2' }), r2);
    }
  });

  it('is not the R1 template: it differs from every R1 variant on the node that matters most', () => {
    for (const variant of ['r1', 'r1-compat']) {
      const other = buildRules(r1Template, [ALLOWLISTED_UID], { variant });
      assert.notDeepEqual(r2.rules.AllTips, other.rules.AllTips);
      assert.notDeepEqual(r2.rules.AllTippers, other.rules.AllTippers);
    }
  });

  it('puts a .write only where a client may write, and nowhere on an identity node', () => {
    const writes = [];
    walk(r2.rules, (key, _value, path) => {
      if (key === '.write') writes.push(path.slice(0, -1).join('/'));
    });
    assert.deepEqual(writes.sort(), [
      'AllDAUComps',
      'AllTippers/$tipperId/compsParticipatedIn',
      'AllTippers/$tipperId/photoURL',
      'AllTips/$comp/$tipperId',
      'AllTips/$comp/$tipperId/$game',
      'AppConfig',
      'DAUCompsGames',
      'Stats/$comp/live_scores_backend_v1/$game/history/$entry',
      'Teams',
    ]);
    for (const identity of [
      'AuthIndex',
      'TipperPrivate',
      'AliasIndex',
      'LogonIndex',
      'Placeholders',
      'ServerConfig',
      'ClaimMoves',
      'TokenOwners',
      'CreateIntents',
      'IdentityLocks',
      'IdentityOps',
      'AllTippersTokens',
    ]) {
      const node = r2.rules[identity];
      if (node === undefined) continue;
      walk(node, (key, _v, path) => assert.notEqual(key, '.write', `${identity} must have no .write (${path.join('/')})`));
    }
  });

  it('names no identity node it should not: the server-only nodes are not in the rules at all', () => {
    for (const closed of ['AliasIndex', 'LogonIndex', 'Placeholders', 'ServerConfig', 'ClaimMoves', 'TokenOwners', 'CreateIntents', 'IdentityLocks', 'IdentityOps', 'AllTippersTokens']) {
      assert.equal(r2.rules[closed], undefined, `${closed} must fall to default deny`);
    }
    assert.equal(r2.rules['.read'], undefined);
    assert.equal(r2.rules['.write'], undefined);
  });

  it('has no write on live-score current or on any scoring branch', () => {
    const live = r2.rules.Stats.$comp.live_scores_backend_v1.$game;
    assert.deepEqual(Object.keys(live), ['history']);
    assert.deepEqual(Object.keys(r2.rules.Stats.$comp), ['live_scores_backend_v1']);
  });
});

describe('r2 against the rules engine', () => {
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
  const stamp = { '.sv': 'timestamp' };
  const entry = (over = {}) => ({ tipperID: 't1', scoreTeam: 'home', interimScore: 6, t: stamp, ...over });

  before(async () => {
    env = await initializeTestEnvironment({ projectId: 'demo-dau-rules', database: { rules: JSON.stringify(r2) } });
  });
  beforeEach(async () => {
    await env.clearDatabase();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.database().ref().set(seed());
    });
  });
  after(async () => env.cleanup());

  describe('an administrator is the validated private role, and nothing else', () => {
    const asksAdmin = (who) => db(who).ref('AppConfig/minAppVersion').set('9.9.9');

    it('the linked administrator is one', async () => {
      await assertSucceeds(asksAdmin('admin'));
      assert.equal(await peek('AppConfig/minAppVersion'), '9.9.9');
    });

    it('a retired R1 allowlist uid is not one', async () => {
      await assertFails(asksAdmin('allowlisted'));
    });

    for (const [name, why] of [
      ['alice', 'an ordinary tipper'],
      ['publicAdmin', 'a user whose PUBLIC record says admin while the private role says tipper'],
      ['spoof', 'an index entry pointing at the admin record, which names a different uid'],
      ['anon', 'an anonymous session, even with an admin link'],
      ['carol', 'an index entry pointing at a record that names someone else'],
      ['dave', 'an index entry pointing at a record that names nobody'],
      ['erin', 'a signed-in user with no index entry'],
      ['frank', 'an index entry pointing at a record that does not exist'],
      ['unauth', 'an unauthenticated session'],
    ]) {
      it(`${name} is not one (${why})`, async () => {
        await assertFails(asksAdmin(name));
        assert.equal(await peek('AppConfig/minAppVersion'), '1.4.0');
      });
    }

    it('promoting oneself in the public record does nothing, because no client can write it', async () => {
      await no('alice', (d) => d.ref('AllTippers/t1/tipperRole').set('admin'));
      await no('alice', (d) => d.ref('TipperPrivate/t1/tipperRole').set('admin'));
      await no('alice', (d) => d.ref('AuthIndex/aliceUid').set('tAdmin'));
    });
  });

  describe('AppConfig and reference data', () => {
    it('AppConfig is readable before sign-in; only an administrator writes it', async () => {
      await ok('unauth', (d) => d.ref('AppConfig').get());
      await ok('admin', (d) => d.ref('AppConfig/currentDAUComp').set('c2'));
      await no('alice', (d) => d.ref('AppConfig/currentDAUComp').set('c2'));
    });

    for (const path of ['Teams', 'AllDAUComps', 'DAUCompsGames/c1', 'Diagnostics']) {
      it(`${path} needs a session to read (an anonymous one will do), and no client writes Diagnostics`, async () => {
        await no('unauth', (d) => d.ref(path).get());
        await ok('anon', (d) => d.ref(path).get());
        await ok('alice', (d) => d.ref(path).get());
      });
    }

    it('Teams, AllDAUComps and DAUCompsGames are written by an administrator only', async () => {
      await ok('admin', (d) => d.ref('Teams/nrl-b').set({ name: 'B' }));
      await ok('admin', (d) => d.ref('AllDAUComps/c2').set({ name: '2028' }));
      await ok('admin', (d) => d.ref('DAUCompsGames/c1/started/DateUtcEpochMs').set(PAST - 1));
      for (const who of ['alice', 'anon', 'unauth', 'allowlisted']) {
        await no(who, (d) => d.ref('Teams/nrl-b').set({ name: 'B' }));
        await no(who, (d) => d.ref('AllDAUComps/c2').set({ name: '2028' }));
        await no(who, (d) => d.ref('DAUCompsGames/c1/started/DateUtcEpochMs').set(1));
      }
      await no('admin', (d) => d.ref('Diagnostics/androidResumeProbe').set('p'));
    });
  });

  describe('AllTippers: public data, with no way for a client to change who anyone is', () => {
    it('is readable by any session, an anonymous one included, and not before sign-in', async () => {
      await ok('anon', (d) => d.ref('AllTippers').get());
      await ok('alice', (d) => d.ref('AllTippers/t2/name').get());
      await no('unauth', (d) => d.ref('AllTippers').get());
    });

    it('nobody creates a record, an administrator included', async () => {
      const fresh = { name: 'New', authuid: 'erinUid', tipperRole: 'tipper' };
      await no('erin', (d) => d.ref('AllTippers/tNew').set(fresh));
      await no('admin', (d) => d.ref('AllTippers/tNew').set(fresh));
      await no('admin', (d) => d.ref('AllTippers').update({ tNew: fresh }));
    });

    it('nobody deletes or replaces a record, an administrator included', async () => {
      await no('alice', (d) => d.ref('AllTippers/t1').remove());
      await no('admin', (d) => d.ref('AllTippers/t1').remove());
      await no('admin', (d) => d.ref('AllTippers').remove());
      await no('alice', (d) => d.ref('AllTippers/t1').set({ name: 'Mine', authuid: 'aliceUid', tipperRole: 'tipper' }));
      await no('admin', (d) => d.ref('AllTippers/t1').set({ name: 'Theirs' }));
    });

    it('nobody writes name, email, logon, authuid, tipperRole, isAnonymous or a login timestamp', async () => {
      for (const field of ['name', 'email', 'logon', 'authuid', 'tipperRole', 'isAnonymous', 'acctLoggedOnUTC', 'acctCreatedUTC']) {
        for (const who of ['alice', 'admin']) {
          await no(who, (d) => d.ref(`AllTippers/t1/${field}`).set(field === 'isAnonymous' ? false : 'x'));
        }
      }
      assert.equal((await peek('AllTippers/t1')).name, 'Alice');
    });

    it('the owner writes their own photo and nobody else\'s', async () => {
      await ok('alice', (d) => d.ref('AllTippers/t1/photoURL').set('new.png'));
      assert.equal(await peek('AllTippers/t1/photoURL'), 'new.png');
      await no('alice', (d) => d.ref('AllTippers/t2/photoURL').set('mine.png'));
      await no('admin', (d) => d.ref('AllTippers/t1/photoURL').set('admin.png'));
      await no('erin', (d) => d.ref('AllTippers/t1/photoURL').set('x.png'));
      await no('publicAdmin', (d) => d.ref('AllTippers/t1/photoURL').set('x.png'));
      await no('carol', (d) => d.ref('AllTippers/tCarol/photoURL').set('x.png'));
    });

    it('a photo must be a string of sensible length', async () => {
      await no('alice', (d) => d.ref('AllTippers/t1/photoURL').set(5));
      await no('alice', (d) => d.ref('AllTippers/t1/photoURL').set('x'.repeat(2049)));
      await ok('alice', (d) => d.ref('AllTippers/t1/photoURL').set('x'.repeat(2048)));
    });

    it('an administrator, and only an administrator, toggles a paid comp', async () => {
      await ok('admin', (d) => d.ref('AllTippers/t2/compsParticipatedIn').set(['c1']));
      assert.deepEqual(await peek('AllTippers/t2/compsParticipatedIn'), ['c1']);
      await ok('admin', (d) => d.ref('AllTippers/t1/compsParticipatedIn').remove());
      await no('alice', (d) => d.ref('AllTippers/t1/compsParticipatedIn').set(['c1', 'c2']));
      await no('allowlisted', (d) => d.ref('AllTippers/t2/compsParticipatedIn').set(['c1']));
      await no('publicAdmin', (d) => d.ref('AllTippers/t2/compsParticipatedIn').set(['c1']));
    });

    it('a root update that includes one forbidden leaf changes nothing', async () => {
      await no('alice', (d) =>
        d.ref().update({ 'AllTippers/t1/photoURL': 'ok.png', 'AllTippers/t1/name': 'Renamed' }),
      );
      assert.equal(await peek('AllTippers/t1/photoURL'), 'a.png');
      await ok('alice', (d) => d.ref().update({ 'AllTippers/t1/photoURL': 'ok.png' }));
    });
  });

  describe('AuthIndex and TipperPrivate: the owner reads their own, an administrator reads all, nobody writes', () => {
    it('a user reads their own index entry, and null when they have none', async () => {
      assert.equal((await ok('alice', (d) => d.ref('AuthIndex/aliceUid').get())).val(), 't1');
      assert.equal((await ok('erin', (d) => d.ref('AuthIndex/erinUid').get())).val(), null);
      await no('alice', (d) => d.ref('AuthIndex/bobUid').get());
      await no('alice', (d) => d.ref('AuthIndex').get());
      await no('admin', (d) => d.ref('AuthIndex').get());
      await no('anon', (d) => d.ref('AuthIndex/anonUid').get());
      await no('unauth', (d) => d.ref('AuthIndex/aliceUid').get());
    });

    it('the owner reads their private record, and a link that disagrees either way reads nothing', async () => {
      assert.equal((await ok('alice', (d) => d.ref('TipperPrivate/t1').get())).val().logon, 'a@x.test');
      await no('alice', (d) => d.ref('TipperPrivate/t2').get());
      await no('carol', (d) => d.ref('TipperPrivate/tCarol').get());
      await no('dave', (d) => d.ref('TipperPrivate/tDave').get());
      await no('erin', (d) => d.ref('TipperPrivate/t1').get());
      await no('frank', (d) => d.ref('TipperPrivate/tNowhere').get());
      await no('anon', (d) => d.ref('TipperPrivate/tAnon').get());
    });

    it('only the validated administrator lists the node', async () => {
      await ok('admin', (d) => d.ref('TipperPrivate').get());
      await ok('admin', (d) => d.ref('TipperPrivate/t2').get());
      for (const who of ['alice', 'allowlisted', 'publicAdmin', 'spoof', 'anon', 'unauth']) {
        await no(who, (d) => d.ref('TipperPrivate').get());
      }
    });

    it('no client writes either node, an administrator included', async () => {
      for (const who of ['alice', 'admin', 'erin']) {
        await no(who, (d) => d.ref('AuthIndex/erinUid').set('t1'));
        await no(who, (d) => d.ref('TipperPrivate/t1/tipperRole').set('admin'));
        await no(who, (d) => d.ref('TipperPrivate/tNew').set({ authuid: 'erinUid', tipperRole: 'tipper' }));
      }
      assert.equal(await peek('AuthIndex/erinUid'), null);
    });
  });

  describe('tips: secret until kickoff, locked from kickoff', () => {
    const tip = (path) => `AllTips/c1/${path}`;

    it('the owner reads their own tips, at the tipper level and per game', async () => {
      await ok('alice', (d) => d.ref(tip('t1')).get());
      await ok('alice', (d) => d.ref(tip('t1/upcoming')).get());
    });

    it('nobody else reads a tip before kickoff, and everyone signed in reads it after, game by game', async () => {
      await no('bob', (d) => d.ref(tip('t1/upcoming')).get());
      await no('anon', (d) => d.ref(tip('t1/upcoming')).get());
      await no('unauth', (d) => d.ref(tip('t1/upcoming')).get());
      await ok('bob', (d) => d.ref(tip('t1/started')).get());
      await ok('anon', (d) => d.ref(tip('t1/started')).get());
      await no('unauth', (d) => d.ref(tip('t1/started')).get());
    });

    it('nobody else lists a tipper\'s tips or a competition\'s, even once games have started', async () => {
      await no('bob', (d) => d.ref(tip('t1')).get());
      await no('bob', (d) => d.ref('AllTips/c1').get());
      await no('bob', (d) => d.ref('AllTips').get());
      await no('allowlisted', (d) => d.ref('AllTips/c1').get());
      await ok('admin', (d) => d.ref('AllTips/c1').get());
      await ok('admin', (d) => d.ref(tip('t1/upcoming')).get());
    });

    it('a game with no kickoff, or a kickoff that is not a number, is never readable by others and never writable by its owner', async () => {
      for (const game of ['noKickoff', 'badKickoff']) {
        await no('bob', (d) => d.ref(tip(`t1/${game}`)).get());
        await no('alice', (d) => d.ref(tip(`t1/${game}`)).set(tipOf('b')));
        await ok('alice', (d) => d.ref(tip(`t1/${game}`)).get());
        await ok('admin', (d) => d.ref(tip(`t1/${game}`)).set(tipOf('b')));
      }
    });

    it('the owner tips before kickoff, changes the tip and removes it, and not after', async () => {
      await ok('alice', (d) => d.ref(tip('t1/upcoming')).set(tipOf('c')));
      assert.equal((await peek(tip('t1/upcoming'))).r, 'c');
      await ok('alice', (d) => d.ref(tip('t1/upcoming')).remove());
      await ok('bob', (d) => d.ref(tip('t2/upcoming')).set(tipOf('d')));
      await no('alice', (d) => d.ref(tip('t1/started')).set(tipOf('d')));
      await no('alice', (d) => d.ref(tip('t1/started')).remove());
      assert.equal((await peek(tip('t1/started'))).r, 'a');
    });

    it('zero grace retains the exact kickoff deadline', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await ctx.database().ref('AppConfig/tipGracePeriodSeconds').set(0);
        await ctx.database().ref('DAUCompsGames/c1').update({
          'upcoming/DateUtcEpochMs': Date.now() - 50,
          'started/DateUtcEpochMs': Date.now() + 60_000,
        });
      });
      await no('alice', (d) => d.ref(tip('t1/upcoming')).set(tipOf('c')));
      await ok('alice', (d) => d.ref(tip('t1/started')).set(tipOf('c')));
    });

    for (const [label, setting, seconds] of [
      ['absent default', null, 120], ['configured', 300, 300],
      ['invalid string', '300', 120], ['negative', -1, 120],
      ['fractional', 0.5, 120],
    ]) {
      it(`grace ${label}: owner writes while competitors cannot read, then the reverse`, async () => {
        await env.withSecurityRulesDisabled(async (ctx) => {
          await ctx.database().ref('AppConfig/tipGracePeriodSeconds').set(setting);
          await ctx.database().ref('DAUCompsGames/c1/upcoming/DateUtcEpochMs')
            .set(Date.now() - (seconds - 30) * 1000);
        });
        await ok('alice', (d) => d.ref(tip('t1/upcoming')).set(tipOf('c')));
        await no('bob', (d) => d.ref(tip('t1/upcoming')).get());
        await no('alice', (d) => d.ref('Stats/c1/live_scores_backend_v1/upcoming/history/grace').set(entry()));
        await env.withSecurityRulesDisabled(async (ctx) => {
          await ctx.database().ref('DAUCompsGames/c1/upcoming/DateUtcEpochMs')
            .set(Date.now() - seconds * 1000 - 100);
        });
        await no('alice', (d) => d.ref(tip('t1/upcoming')).set(tipOf('d')));
        await ok('bob', (d) => d.ref(tip('t1/upcoming')).get());
        await ok('alice', (d) => d.ref('Stats/c1/live_scores_backend_v1/upcoming/history/grace').set(entry()));
      });
    }

    it('nobody tips for someone else, and an unlinked, anonymous or mismatched session tips for no one', async () => {
      await no('bob', (d) => d.ref(tip('t1/upcoming')).set(tipOf('c')));
      await no('anon', (d) => d.ref(tip('t1/upcoming')).set(tipOf('c')));
      await no('erin', (d) => d.ref(tip('t1/upcoming')).set(tipOf('c')));
      await no('carol', (d) => d.ref(tip('tCarol/upcoming')).set(tipOf('c')));
      await no('dave', (d) => d.ref(tip('tDave/upcoming')).set(tipOf('c')));
      await no('allowlisted', (d) => d.ref(tip('t1/upcoming')).set(tipOf('c')));
      await no('unauth', (d) => d.ref(tip('t1/upcoming')).set(tipOf('c')));
      assert.equal((await peek(tip('t1/upcoming'))).r, 'b');
    });

    it('an administrator may edit any tip at any time, and merge or delete a tipper\'s whole node; an owner may not', async () => {
      await ok('admin', (d) => d.ref(tip('t1/started')).set(tipOf('b')));
      await ok('admin', (d) => d.ref(tip('t2')).set({ started: tipOf('b') }));
      await no('alice', (d) => d.ref(tip('t1')).remove());
      await no('alice', (d) => d.ref(tip('t1')).set({ upcoming: tipOf('b') }));
      await ok('admin', (d) => d.ref(tip('t1')).remove());
    });

    it('a tip must have the right shape', async () => {
      const bad = [
        { t: nowSeconds() },
        { r: 'a' },
        { r: 'f', t: nowSeconds() },
        { r: 'A', t: nowSeconds() },
        { r: 1, t: nowSeconds() },
        { r: 'a', t: 'now' },
        { r: 'a', t: 0 },
        { r: 'a', t: nowSeconds(), extra: 1 },
        { r: 'a', t: nowSeconds() + 90_000 }, // more than a day ahead of the server
      ];
      for (const shape of bad) await no('alice', (d) => d.ref(tip('t1/upcoming')).set(shape));
      await ok('alice', (d) => d.ref(tip('t1/upcoming')).set({ r: 'z', t: nowSeconds() }));
      await ok('alice', (d) => d.ref(tip('t1/upcoming')).set({ r: 'a', t: nowSeconds() + 3_600 })); // a fast clock
      await ok('alice', (d) =>
        d.ref(tip('t1/upcoming')).set({ gameResult: 'Home', submittedTimeUTC: '2027-03-07T00:00:00Z' }),
      );
      await ok('alice', (d) => d.ref(tip('t1/upcoming')).set({ r: 'a', t: nowSeconds(), legacyTip: 'x' }));
    });

    it('a root update that tips two games, one of them locked, changes neither', async () => {
      await no('alice', (d) =>
        d.ref().update({ 'AllTips/c1/t1/upcoming': tipOf('c'), 'AllTips/c1/t1/started': tipOf('c') }),
      );
      assert.equal((await peek(tip('t1/upcoming'))).r, 'b');
    });
  });

  describe('live scores: history is append-only and the server owns everything else', () => {
    const history = (key) => `Stats/c1/live_scores_backend_v1/started/history/${key}`;

    it('any session reads Stats, and not before sign-in', async () => {
      await ok('anon', (d) => d.ref('Stats/c1/scoring_status').get());
      await ok('alice', (d) => d.ref('Stats/c1/live_scores_backend_v1/started/current').get());
      await no('unauth', (d) => d.ref('Stats/c1').get());
    });

    it('a linked tipper adds an entry for themselves, with the server\'s own time', async () => {
      await ok('alice', (d) => d.ref(history('k1')).set(entry()));
      const stored = await peek(history('k1'));
      assert.equal(stored.tipperID, 't1');
      assert.ok(Math.abs(stored.t - Date.now()) < 60_000, 'the stored time is the server\'s');
    });

    it('not for someone else, and not without a link, or as an anonymous session', async () => {
      await no('alice', (d) => d.ref(history('k1')).set(entry({ tipperID: 't2' })));
      await no('bob', (d) => d.ref(history('k1')).set(entry()));
      for (const who of ['erin', 'carol', 'dave', 'frank', 'anon', 'unauth', 'allowlisted']) {
        await no(who, (d) => d.ref(history('k1')).set(entry()));
      }
    });

    it('only once the game has started, and not once it has an official score', async () => {
      const at = (game) => `Stats/c1/live_scores_backend_v1/${game}/history/k1`;
      await no('alice', (d) => d.ref(at('upcoming')).set(entry()));
      await no('alice', (d) => d.ref(at('noKickoff')).set(entry()));
      await no('alice', (d) => d.ref(at('badKickoff')).set(entry()));
      await no('alice', (d) => d.ref(at('official')).set(entry()));
      await ok('alice', (d) => d.ref(at('oneScore')).set(entry())); // one score is not an official result
    });

    it('the time must be the server\'s: a client time, a past time and a missing time are refused', async () => {
      await no('alice', (d) => d.ref(history('k1')).set(entry({ t: Date.now() })));
      await no('alice', (d) => d.ref(history('k1')).set(entry({ t: Date.now() - 3_600_000 })));
      const { t: _omitted, ...withoutTime } = entry();
      await no('alice', (d) => d.ref(history('k1')).set(withoutTime));
      await no('alice', (d) => d.ref(history('k1')).set(entry({ t: 'now' })));
    });

    it('the score must be a whole number from 0 to 300, for home or away, and nothing else may ride along', async () => {
      for (const score of [-1, 301, 5.5, '6', null]) {
        await no('alice', (d) => d.ref(history('k1')).set(entry({ interimScore: score })));
      }
      await no('alice', (d) => d.ref(history('k1')).set(entry({ scoreTeam: 'draw' })));
      await no('alice', (d) => d.ref(history('k1')).set(entry({ gameComplete: true })));
      await no('alice', (d) => d.ref(history('k1')).set(entry({ submittedTimeUTC: 'x' })));
      await ok('alice', (d) => d.ref(history('k2')).set(entry({ interimScore: 0 })));
      await ok('alice', (d) => d.ref(history('k3')).set(entry({ interimScore: 300, scoreTeam: 'away' })));
    });

    it('an entry is never overwritten or removed by a tipper, even their own', async () => {
      await ok('alice', (d) => d.ref(history('k1')).set(entry()));
      await no('alice', (d) => d.ref(history('k1')).set(entry({ interimScore: 40 })));
      await no('alice', (d) => d.ref(history('k1')).remove());
      await no('bob', (d) => d.ref(history('old')).remove());
      await no('bob', (d) => d.ref(history('old')).set(entry({ tipperID: 't2' })));
      await no('alice', (d) => d.ref('Stats/c1/live_scores_backend_v1/started/history').remove());
      assert.equal((await peek(history('k1'))).interimScore, 6);
    });

    it('an administrator may remove an entry (a correction), and nobody else may', async () => {
      await ok('admin', (d) => d.ref(history('old')).remove());
      assert.equal(await peek(history('old')), null);
      await no('allowlisted', (d) => d.ref(history('old')).remove());
    });

    it('no client writes `current` or any scoring branch, an administrator included', async () => {
      const live = 'Stats/c1/live_scores_backend_v1/started';
      for (const who of ['alice', 'admin']) {
        await no(who, (d) => d.ref(`${live}/current`).set({ homeInterimScore: 99 }));
        await no(who, (d) => d.ref(`${live}/current/homeInterimScore`).set(99));
        await no(who, (d) => d.ref('Stats/c1/scoring_status').set({ status: 'x' }));
        await no(who, (d) => d.ref('Stats/c1/round_stats_backend_v1/1').remove());
        await no(who, (d) => d.ref('Stats/c1/live_scores_v3/started').set({ x: 1 }));
      }
      assert.equal((await peek(`${live}/current`)).homeInterimScore, 6);
    });
  });

  describe('everything the server owns is closed to every client', () => {
    const closed = [
      'AliasIndex',
      'LogonIndex',
      'Placeholders',
      'ServerConfig',
      'ServerConfig/liveScores/mode',
      'ClaimMoves',
      'TokenOwners',
      'CreateIntents',
      'IdentityLocks',
      'IdentityOps',
      'AllTippersTokens',
      'AllTippersTokens/t1',
    ];
    for (const path of closed) {
      it(`${path} cannot be read or written by anyone`, async () => {
        for (const who of ['unauth', 'anon', 'alice', 'admin', 'allowlisted']) {
          await no(who, (d) => d.ref(path).get());
          await no(who, (d) => d.ref(path).set('x'));
        }
      });
    }

    it('a node the rules never mention is closed too', async () => {
      await no('admin', (d) => d.ref('SomethingNew').set(1));
      await no('admin', (d) => d.ref('SomethingNew').get());
      await no('admin', (d) => d.ref().get());
      await no('admin', (d) => d.ref().set({}));
    });
  });
});
