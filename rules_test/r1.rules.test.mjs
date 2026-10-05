// R1 (interim) rules: conformance and rejection tests.
// DESIGN-database-rules.md section 5, step 1. Baseline clients: 1.4.0 and 1.4.1.
//
// The rules are generated from config/database.rules.r1.template.json with a
// FIXTURE admin allowlist (never real UIDs). Operations replay what the shipped
// client does (shapes taken from Tipper.toJson, Tip.toJson and the view models).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, afterEach, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { PATHS, buildRules } from '../scripts/build_admin_allowlist.mjs';

const ADMIN_UID = 'ADMINfixtureUID000000000001'; // 28 chars, fixture only
const ADMIN2_UID = 'ADMINfixtureUID000000000002';
const rules = buildRules(readFileSync(process.env.R1_TEMPLATE ?? PATHS.template, 'utf8'), [ADMIN_UID, ADMIN2_UID]);

const google = { firebase: { sign_in_provider: 'google.com' } };
const anonymous = { firebase: { sign_in_provider: 'anonymous' } };

const actors = {
  unauth: null,
  anon: { uid: 'anonUid', token: anonymous },
  alice: { uid: 'aliceUid', token: google },
  bob: { uid: 'bobUid', token: google },
  admin: { uid: ADMIN_UID, token: google },
  admin2: { uid: ADMIN2_UID, token: google },
  // A user whose DATABASE record says admin, but who is not on the allowlist.
  fakeAdmin: { uid: 'fakeAdminUid', token: google },
};

let env;
const db = (who) => {
  const a = actors[who];
  return (a === null ? env.unauthenticatedContext() : env.authenticatedContext(a.uid, a.token)).database();
};
const ok = (who, op) => assertSucceeds(op(db(who)));
const no = (who, op) => assertFails(op(db(who)));

async function peek(path) {
  let value;
  await env.withSecurityRulesDisabled(async (ctx) => {
    value = (await ctx.database().ref(path).get()).val();
  });
  return value;
}

const seed = () => ({
  AppConfig: { minAppVersion: '1.4.0', currentDAUComp: 'c1', createLinkedTipper: true },
  AllDAUComps: { c1: { name: '2026', aflFixtureJsonURL: 'https://x.test/afl.json' } },
  Teams: { 'nrl-broncos': { name: 'Broncos', league: 'nrl' } },
  DAUCompsGames: { c1: { g1: { HomeTeam: 'a', AwayTeam: 'b', DateUtc: '2026-03-05 09:50:00Z' } } },
  AllTippers: {
    t1: { authuid: 'aliceUid', tipperRole: 'tipper', name: 'Alice', logon: 'alice@x.test', email: 'alice@x.test' },
    t2: { authuid: 'bobUid', tipperRole: 'tipper', name: 'Bob', logon: 'bob@x.test', email: 'bob@x.test' },
    tFake: { authuid: 'fakeAdminUid', tipperRole: 'admin', name: 'Fake', logon: 'f@x.test', email: 'f@x.test' },
    // legacy record: placeholder authuid (an email address) and extra legacy keys
    tLegacy: { authuid: 'old.sheet@x.test', tipperRole: 'tipper', name: 'Old', logon: 'old@x.test', email: 'old@x.test', active: true, tipperID: 'legacy1' },
  },
  AllTippersTokens: { t1: { tokenAAAA: '2026-03-01T00:00:00.000' } },
  AllTips: {
    c1: {
      t1: { g1: { r: 'a', t: 1772000000 } },
      t2: { g1: { gameResult: 'b', submittedTimeUTC: '2026-03-01T00:00:00Z', legacyTip: true } },
    },
  },
  Stats: {
    c1: {
      live_scores_backend_v1: { g1: { current: { homeInterimScore: 1 }, history: { k1: { tipperID: 't1' } } } },
      game_stats_backend_v1: { paid: { g1: { avgScore: 1 } } },
      scoring_status: { state: 'ok' },
    },
  },
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-dau-rules',
    database: { rules: JSON.stringify(rules) },
  });
});
beforeEach(async () => {
  await env.clearDatabase();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.database().ref().set(seed());
  });
});
afterEach(() => {});
after(async () => env.cleanup());

// Shape of Tipper.toJson for a brand-new user (compsParticipatedIn is an empty list).
const newTipperJson = (overrides = {}) => ({
  authuid: 'aliceUid',
  email: 'new@x.test',
  logon: 'new@x.test',
  name: 'Newbie',
  tipperRole: 'tipper',
  photoURL: 'https://x.test/p.png',
  compsParticipatedIn: [],
  acctCreatedUTC: '2026-10-05 10:00:00.000Z',
  acctLoggedOnUTC: '2026-10-05 10:00:00.000Z',
  isAnonymous: false,
  ...overrides,
});

describe('R1 reads', () => {
  it('stay open for the data the shipped client reads before and after sign-in', async () => {
    for (const path of ['AppConfig', 'Teams', 'AllDAUComps', 'DAUCompsGames/c1', 'AllTippers', 'AllTips/c1/t1', 'Stats/c1/scoring_status', 'Diagnostics']) {
      await ok('unauth', (d) => d.ref(path).get());
    }
  });
  it('tokens need a sign-in; unknown paths and the root are closed', async () => {
    await no('unauth', (d) => d.ref('AllTippersTokens').get());
    await ok('alice', (d) => d.ref('AllTippersTokens').get());
    await no('alice', (d) => d.ref('Secret').get());
    await no('alice', (d) => d.ref().get());
  });
});

describe('R1 admin-only areas (allowlist, not the database role)', () => {
  const ops = {
    'AppConfig minAppVersion': (d) => d.ref('AppConfig/minAppVersion').set('9.9.9'),
    'AppConfig createLinkedTipper': (d) => d.ref('AppConfig/createLinkedTipper').set(false),
    'AllDAUComps field (multi-path update from root)': (d) => d.ref().update({ 'AllDAUComps/c1/name': 'renamed' }),
    'AllDAUComps downloadLock set': (d) => d.ref('AllDAUComps/c1/downloadLock').set('2026-10-05T00:00:00Z'),
    'Teams update': (d) => d.ref().update({ 'Teams/nrl-broncos/name': 'Renamed' }),
    'DAUCompsGames score': (d) => d.ref().update({ 'DAUCompsGames/c1/g1/HomeTeamScore': 12 }),
  };
  for (const [label, op] of Object.entries(ops)) {
    it(`${label}: allowlisted admins allowed, everyone else denied`, async () => {
      await ok('admin', op);
      await ok('admin2', op);
      await no('alice', op);
      await no('anon', op);
      await no('unauth', op);
      await no('fakeAdmin', op); // record says tipperRole admin, but not allowlisted
    });
  }
  it('downloadLock can be cleared by an admin and not by a user', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => ctx.database().ref('AllDAUComps/c1/downloadLock').set('x'));
    await no('alice', (d) => d.ref('AllDAUComps/c1/downloadLock').set(null));
    await ok('admin', (d) => d.ref('AllDAUComps/c1/downloadLock').set(null));
  });
});

describe('R1 tipper records', () => {
  it('a signed-in user can create their own record exactly as the client does', async () => {
    await ok('alice', (d) => d.ref().update({ 'AllTippers/newKey': newTipperJson() }));
    assert.equal(await peek('AllTippers/newKey/tipperRole'), 'tipper');
  });
  it('creation with admin role, another uid, a paid comp or an unknown key is denied', async () => {
    await no('alice', (d) => d.ref('AllTippers/k1').set(newTipperJson({ tipperRole: 'admin' })));
    await no('alice', (d) => d.ref('AllTippers/k2').set(newTipperJson({ authuid: 'someoneElse' })));
    await no('alice', (d) => d.ref('AllTippers/k3').set(newTipperJson({ compsParticipatedIn: ['c1'] })));
    await no('alice', (d) => d.ref('AllTippers/k4').set(newTipperJson({ isStaff: true })));
    await no('alice', (d) => d.ref('AllTippers/k5').set({ tipperRole: 'tipper', name: 'no authuid' }));
  });
  it('anonymous and unauthenticated users cannot create records', async () => {
    await no('anon', (d) => d.ref('AllTippers/k6').set(newTipperJson({ authuid: 'anonUid' })));
    await no('unauth', (d) => d.ref('AllTippers/k7').set(newTipperJson()));
  });
  it('partial records cannot be created through a leaf write', async () => {
    await no('alice', (d) => d.ref('AllTippers/ghost/name').set('x'));
    await no('alice', (d) => d.ref('AllTippers/ghost2/authuid').set('aliceUid'));
  });
  it('login-time leaf updates work for a normal record and for a legacy placeholder record', async () => {
    for (const key of ['t1', 'tLegacy']) {
      await ok('alice', (d) =>
        d.ref().update({
          [`AllTippers/${key}/logon`]: 'a@x.test',
          [`AllTippers/${key}/email`]: 'a@x.test',
          [`AllTippers/${key}/isAnonymous`]: false,
          [`AllTippers/${key}/photoURL`]: 'https://x.test/a.png',
          [`AllTippers/${key}/acctLoggedOnUTC`]: '2026-10-05 10:00:00.000Z',
          [`AllTippers/${key}/acctCreatedUTC`]: '2026-01-01 00:00:00.000Z',
          [`AllTippers/${key}/name`]: 'Renamed',
        }),
      );
    }
  });
  it('identity fields are not writable by non-admins, directly or by replacement or deletion', async () => {
    for (const who of ['alice', 'bob', 'anon', 'unauth', 'fakeAdmin']) {
      await no(who, (d) => d.ref('AllTippers/t1/authuid').set('mine'));
      await no(who, (d) => d.ref('AllTippers/t1/authuid').remove());
      await no(who, (d) => d.ref('AllTippers/t2/tipperRole').set('admin'));
      await no(who, (d) => d.ref('AllTippers/t2/tipperRole').remove());
      await no(who, (d) => d.ref('AllTippers/t1/compsParticipatedIn').set(['c1']));
      await no(who, (d) => d.ref('AllTippers/t1').set(newTipperJson()));
      await no(who, (d) => d.ref('AllTippers/t1').remove());
      await no(who, (d) => d.ref('AllTippers').set(null));
    }
    assert.equal(await peek('AllTippers/t1/authuid'), 'aliceUid');
  });
  it('escalating a database record to admin does not grant admin powers', async () => {
    await no('alice', (d) => d.ref('AllTippers/t1/tipperRole').set('admin'));
    // even if it somehow became admin in the database, the allowlist still decides
    await env.withSecurityRulesDisabled(async (ctx) => ctx.database().ref('AllTippers/t1/tipperRole').set('admin'));
    await no('alice', (d) => d.ref('AppConfig/minAppVersion').set('9.9.9'));
  });
  it('a multi-location update with one denied leaf is all-or-nothing', async () => {
    await no('alice', (d) =>
      d.ref().update({ 'AllTippers/t1/name': 'Changed', 'AllTippers/t1/tipperRole': 'admin' }),
    );
    assert.equal(await peek('AllTippers/t1/name'), 'Alice');
  });
  it('admins can do role, paid, authuid (merge), create and delete', async () => {
    await ok('admin', (d) => d.ref('AllTippers/t1/tipperRole').set('admin'));
    await ok('admin', (d) => d.ref('AllTippers/t2/compsParticipatedIn').set(['c1', 'c0']));
    await ok('admin', (d) => d.ref('AllTippers/tLegacy/authuid').set('newRealUid'));
    await ok('admin', (d) => d.ref().update({ 'AllTippers/adminMade': newTipperJson({ authuid: 'someUid' }) }));
    await ok('admin', (d) => d.ref('AllTippers/t2').remove());
    assert.equal(await peek('AllTippers/t2'), null);
  });
  it('validation still binds admins: invalid role value and a record without identity are rejected', async () => {
    await no('admin', (d) => d.ref('AllTippers/t1/tipperRole').set('superuser'));
    await no('admin', (d) => d.ref('AllTippers/t1/email').set(12345));
    await no('admin', (d) => d.ref('AllTippers/t1/authuid').remove()); // required child
  });
  it('a non-allowlisted record marked admin cannot do admin things', async () => {
    await no('fakeAdmin', (d) => d.ref('AllTippers/t1/tipperRole').set('admin'));
    await no('fakeAdmin', (d) => d.ref('AllTippers/t2/compsParticipatedIn').set(['c1']));
  });
});

describe('R1 device tokens', () => {
  it('leaf register, update and remove work (including the cross-tipper cleanup the client does)', async () => {
    await ok('alice', (d) => d.ref('AllTippersTokens/t1').update({ tokenBBBB: '2026-10-05T00:00:00.000' }));
    await ok('alice', (d) => d.ref('AllTippersTokens/t2/tokenCCCC').set('2026-10-05T00:00:00.000'));
    await ok('alice', (d) => d.ref('AllTippersTokens/t1/tokenAAAA').remove());
  });
  it('wiping a tipper or the whole collection, and anonymous writes, are denied', async () => {
    await no('alice', (d) => d.ref('AllTippersTokens/t1').remove());
    await no('alice', (d) => d.ref('AllTippersTokens').remove());
    await no('anon', (d) => d.ref('AllTippersTokens/t1/tokenDDDD').set('x'));
    await no('unauth', (d) => d.ref('AllTippersTokens/t1/tokenDDDD').set('x'));
  });
});

describe('R1 tips', () => {
  const compact = { r: 'b', t: 1772100000 };
  it('add (root multi-path update), update and delete a tip as the client does', async () => {
    await ok('alice', (d) => d.ref().update({ 'AllTips/c1/t1/g2': compact }));
    await ok('alice', (d) => d.ref('AllTips/c1/t1/g2').update({ r: 'c', t: 1772100001 }));
    await ok('alice', (d) => d.ref('AllTips/c1/t1/g2').remove());
  });
  it('the default tip result z is accepted; unknown results and malformed tips are not', async () => {
    await ok('alice', (d) => d.ref('AllTips/c1/t1/g3').set({ r: 'z', t: 1 }));
    await no('alice', (d) => d.ref('AllTips/c1/t1/g4').set({ r: 'q', t: 1772100000 }));
    await no('alice', (d) => d.ref('AllTips/c1/t1/g4').set({ r: 'a' }));
    await no('alice', (d) => d.ref('AllTips/c1/t1/g4').set({ r: 'a', t: 'not-a-number' }));
    await no('alice', (d) => d.ref('AllTips/c1/t1/g4').set({ r: 'a', t: 1772100000, extra: 1 }));
  });
  it('merging compact fields into a legacy-shaped tip (admin merge, updateTip) is accepted', async () => {
    await ok('alice', (d) => d.ref('AllTips/c1/t2/g1').update(compact));
    await ok('alice', (d) =>
      d.ref('AllTips/c1/t2/g5').set({ gameResult: 'a', submittedTimeUTC: '2026-03-02T00:00:00Z' }),
    );
  });
  it('removing all of a tipper\'s tips is admin-only; anonymous cannot write tips', async () => {
    await no('alice', (d) => d.ref('AllTips/c1/t1').remove());
    await no('alice', (d) => d.ref('AllTips/c1').remove());
    await ok('admin', (d) => d.ref('AllTips/c1/t1').remove());
    await no('anon', (d) => d.ref('AllTips/c1/t2/g9').set(compact));
    await no('unauth', (d) => d.ref('AllTips/c1/t2/g9').set(compact));
  });
});

describe('R1 stats and legacy writers', () => {
  const liveUpdate = (d) =>
    d.ref('Stats/c1/live_scores_backend_v1').update({
      'g1/current': { homeInterimScore: 6, awayInterimScore: 4, submittedTimeUTC: '2026-03-05T10:00:00Z', tipperID: 't1' },
      'g1/history/1772700000000000-home': { submittedTimeUTC: '2026-03-05T10:00:00Z', tipperID: 't1', scoreTeam: 'home', interimScore: 6, gameComplete: false },
    });
  it('the HEAD client live-score write works for signed-in users only', async () => {
    await ok('alice', liveUpdate);
    await no('anon', liveUpdate);
    await no('unauth', liveUpdate);
  });
  it('the whole live-score node cannot be replaced or deleted by a user', async () => {
    await no('alice', (d) => d.ref('Stats/c1/live_scores_backend_v1').remove());
    await no('alice', (d) => d.ref('Stats/c1/live_scores_backend_v1/g1').remove());
  });
  // Operations a still-running or modified 1.3.x client would attempt (commit 238ec95).
  const legacy = {
    'game_stats_v3 update': (d) => d.ref('Stats/c1/game_stats_v3').update({ 'paid/g1/avgScore': 1 }),
    'live_scores_v3 update': (d) => d.ref('Stats/c1/live_scores_v3').update({ 'g1/current': { homeInterimScore: 1 } }),
    'live_scores_v3 remove': (d) => d.ref('Stats/c1/live_scores_v3/g1').remove(),
    'round_stats_v3 write': (d) => d.ref('Stats/c1/round_stats_v3').update({ '0/tipper1': { aS: 1 } }),
    'scoring_audit_v3 set': (d) => d.ref('Stats/c1/scoring_audit_v3/1779988960076504').set({ event: 'scoring_completed' }),
    'freshness probe set': (d) => d.ref('Stats/c1/admin_scoring_freshness_probe').set({ serverTimestamp: { '.sv': 'timestamp' } }),
    'backend round stats': (d) => d.ref('Stats/c1/round_stats_backend_v1').set([]),
    'backend game stats': (d) => d.ref('Stats/c1/game_stats_backend_v1/paid/g1').set({ avgScore: 99 }),
    'scoring status': (d) => d.ref('Stats/c1/scoring_status').set({ state: 'forged' }),
    'idempotency': (d) => d.ref('Stats/c1/scoring_idempotency_backend_v1/x').set(true),
  };
  for (const [label, op] of Object.entries(legacy)) {
    it(`rejected for every client, admins included: ${label}`, async () => {
      for (const who of ['alice', 'anon', 'unauth', 'admin', 'fakeAdmin']) {
        await no(who, op);
      }
    });
  }
});

describe('R1 default deny', () => {
  it('unknown paths, diagnostics and identity index nodes are not client-writable, admins included', async () => {
    for (const who of ['alice', 'admin']) {
      await no(who, (d) => d.ref('Secret/x').set(1));
      await no(who, (d) => d.ref('Diagnostics/androidResumeProbe').set('p'));
      await no(who, (d) => d.ref('AuthIndex/aliceUid').set('t1'));
      await no(who, (d) => d.ref('AliasIndex/alice').set('t1'));
      await no(who, (d) => d.ref('LogonIndex/hash').set('t1'));
      await no(who, (d) => d.ref().set({}));
    }
  });
});
