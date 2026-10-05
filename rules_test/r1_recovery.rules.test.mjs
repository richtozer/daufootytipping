// The R1 RECOVERY ruleset: what to deploy when R1 breaks a compatibility path, instead of
// reopening the database. It must (a) keep every protection that matters, and (b) relax only
// validation strictness and re-admit the legacy 1.3.x Stats writers. Also proves that awkward
// admin UIDs, once escaped, are accepted by the real RTDB rules parser and match exactly.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { PATHS, buildRules } from '../scripts/build_admin_allowlist.mjs';

const ADMIN_UID = 'ADMINfixtureUID000000000001';
const google = { firebase: { sign_in_provider: 'google.com' } };
const anonymous = { firebase: { sign_in_provider: 'anonymous' } };
const template = readFileSync(PATHS.template, 'utf8');

const actors = {
  unauth: null,
  anon: { uid: 'anonUid', token: anonymous },
  alice: { uid: 'aliceUid', token: google },
  admin: { uid: ADMIN_UID, token: google },
  fakeAdmin: { uid: 'fakeAdminUid', token: google },
};

const seed = () => ({
  AppConfig: { minAppVersion: '1.4.0' },
  AllDAUComps: { c1: { name: '2026' } },
  Teams: { t: { name: 'x' } },
  DAUCompsGames: { c1: { g1: { DateUtc: '2026-03-05 09:50:00Z' } } },
  AllTippers: {
    t1: { authuid: 'aliceUid', tipperRole: 'tipper', name: 'Alice', logon: 'a@x.test', email: 'a@x.test' },
    tFake: { authuid: 'fakeAdminUid', tipperRole: 'admin', name: 'Fake' },
  },
  AllTippersTokens: { t1: { tok: '2026-03-01T00:00:00.000' } },
  AllTips: { c1: { t1: { g1: { r: 'a', t: 1772000000 } } } },
  Stats: { c1: { round_stats_backend_v1: [], game_stats_backend_v1: { paid: {} }, scoring_status: { state: 'ok' } } },
});

describe('recovery rules keep the protections and relax only compatibility', () => {
  let env;
  const db = (who) => {
    const a = actors[who];
    return (a === null ? env.unauthenticatedContext() : env.authenticatedContext(a.uid, a.token)).database();
  };
  const ok = (who, op) => assertSucceeds(op(db(who)));
  const no = (who, op) => assertFails(op(db(who)));

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: 'demo-dau-rules',
      database: { rules: JSON.stringify(buildRules(template, [ADMIN_UID], { variant: 'r1-recovery' })) },
    });
  });
  beforeEach(async () => {
    await env.clearDatabase();
    await env.withSecurityRulesDisabled(async (ctx) => ctx.database().ref().set(seed()));
  });
  after(async () => env.cleanup());

  describe('protections that must survive a recovery deploy', () => {
    const adminOnly = {
      'AppConfig minAppVersion': (d) => d.ref('AppConfig/minAppVersion').set('9.9.9'),
      'AllDAUComps field': (d) => d.ref().update({ 'AllDAUComps/c1/name': 'renamed' }),
      'Teams': (d) => d.ref().update({ 'Teams/t/name': 'renamed' }),
      'DAUCompsGames score': (d) => d.ref().update({ 'DAUCompsGames/c1/g1/HomeTeamScore': 9 }),
    };
    for (const [label, op] of Object.entries(adminOnly)) {
      it(`${label}: allowlisted admin only`, async () => {
        await ok('admin', op);
        for (const who of ['alice', 'anon', 'unauth', 'fakeAdmin']) await no(who, op);
      });
    }

    it('identity fields cannot be written, deleted or replaced by users (including by a record marked admin)', async () => {
      for (const who of ['alice', 'anon', 'unauth', 'fakeAdmin']) {
        await no(who, (d) => d.ref('AllTippers/t1/authuid').set('mine'));
        await no(who, (d) => d.ref('AllTippers/t1/authuid').remove());
        await no(who, (d) => d.ref('AllTippers/t1/tipperRole').set('admin'));
        await no(who, (d) => d.ref('AllTippers/t1/compsParticipatedIn').set(['c1']));
        await no(who, (d) => d.ref('AllTippers/t1').remove());
        await no(who, (d) => d.ref('AllTippers').set(null));
      }
    });
    it('record creation is still restricted to role tipper, own uid and no paid comps', async () => {
      const rec = (o = {}) => ({ authuid: 'aliceUid', tipperRole: 'tipper', name: 'N', ...o });
      await ok('alice', (d) => d.ref('AllTippers/new1').set(rec()));
      await no('alice', (d) => d.ref('AllTippers/new2').set(rec({ tipperRole: 'admin' })));
      await no('alice', (d) => d.ref('AllTippers/new3').set(rec({ authuid: 'other' })));
      await no('alice', (d) => d.ref('AllTippers/new4').set(rec({ compsParticipatedIn: ['c1'] })));
      await no('anon', (d) => d.ref('AllTippers/new5').set(rec({ authuid: 'anonUid' })));
    });
    it('partial records are still rejected (identity children are required)', async () => {
      await no('alice', (d) => d.ref('AllTippers/ghost/name').set('x'));
    });
    it('an invalid role value is still rejected, even for admins', async () => {
      await no('admin', (d) => d.ref('AllTippers/t1/tipperRole').set('superuser'));
    });
    it('token parent wipes, tipper-level tip deletes and anonymous writes stay denied', async () => {
      await no('alice', (d) => d.ref('AllTippersTokens').remove());
      await no('alice', (d) => d.ref('AllTippersTokens/t1').remove());
      await no('alice', (d) => d.ref('AllTips/c1/t1').remove());
      await ok('admin', (d) => d.ref('AllTips/c1/t1').remove());
      await no('anon', (d) => d.ref('AllTips/c1/t1/g9').set({ r: 'a', t: 1 }));
      await no('anon', (d) => d.ref('AllTippersTokens/t1/x').set('y'));
    });
    it('backend-owned Stats branches, diagnostics, identity indexes and unknown paths stay closed to everyone, admins included', async () => {
      for (const who of ['alice', 'admin']) {
        await no(who, (d) => d.ref('Stats/c1/round_stats_backend_v1').set([]));
        await no(who, (d) => d.ref('Stats/c1/game_stats_backend_v1/paid/g1').set({ avgScore: 99 }));
        await no(who, (d) => d.ref('Stats/c1/scoring_status').set({ state: 'forged' }));
        await no(who, (d) => d.ref('Stats/c1/scoring_idempotency_backend_v1/x').set(true));
        await no(who, (d) => d.ref('Diagnostics/androidResumeProbe').set('p'));
        await no(who, (d) => d.ref('AuthIndex/aliceUid').set('t1'));
        await no(who, (d) => d.ref('Secret/x').set(1));
        await no(who, (d) => d.ref().set({}));
      }
    });
    it('reads keep the same shape as R1 (tokens need a sign-in, the root is closed)', async () => {
      await ok('unauth', (d) => d.ref('AppConfig').get());
      await no('unauth', (d) => d.ref('AllTippersTokens').get());
      await no('alice', (d) => d.ref().get());
    });
  });

  describe('what recovery deliberately relaxes', () => {
    it('re-admits the legacy 1.3.x Stats writers for signed-in users only', async () => {
      const ops = [
        (d) => d.ref('Stats/c1/game_stats_v3').update({ 'paid/g1/avgScore': 1 }),
        (d) => d.ref('Stats/c1/live_scores_v3').update({ 'g1/current': { homeInterimScore: 1 } }),
        (d) => d.ref('Stats/c1/round_stats_v3').update({ '0/t1': { aS: 1 } }),
        (d) => d.ref('Stats/c1/scoring_audit_v3/1779988960076504').set({ event: 'scoring_completed' }),
        (d) => d.ref('Stats/c1/admin_scoring_freshness_probe').set({ serverTimestamp: { '.sv': 'timestamp' } }),
      ];
      for (const op of ops) {
        await ok('alice', op);
        await no('anon', op);
        await no('unauth', op);
      }
    });
    it('accepts tip shapes R1 would reject (extra keys, odd values) from signed-in users', async () => {
      await ok('alice', (d) => d.ref('AllTips/c1/t1/g2').set({ r: 'q', t: 'text', extra: 1 }));
      await no('anon', (d) => d.ref('AllTips/c1/t1/g3').set({ r: 'q' }));
    });
    it('accepts profile leaf values and creation keys R1 would reject', async () => {
      await ok('alice', (d) => d.ref('AllTippers/t1/email').set(12345));
      await ok('alice', (d) => d.ref('AllTippers/newKey').set({ authuid: 'aliceUid', tipperRole: 'tipper', name: 'N', isStaff: true }));
    });
  });
});

describe('awkward admin UIDs are escaped and match exactly in the real RTDB rules parser', () => {
  const awkward = ["ad'min\\x", 'x\' || true || \'y', 'plain-uid'];
  let env;
  const as = (uid) => env.authenticatedContext(uid, google).database();

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: 'demo-dau-rules',
      database: { rules: JSON.stringify(buildRules(template, awkward)) },
    });
    await env.withSecurityRulesDisabled(async (ctx) => ctx.database().ref().set({ AppConfig: { minAppVersion: '1.4.0' } }));
  });
  after(async () => env.cleanup());

  for (const uid of awkward) {
    it(`admin ${JSON.stringify(uid)} is recognised`, async () => {
      await assertSucceeds(as(uid).ref('AppConfig/minAppVersion').set('1.4.1'));
    });
  }
  it('near-misses and fragments of those UIDs are not admins', async () => {
    for (const notAdmin of ["ad'min", 'ad\'min\\', "ad'min\\xx", 'x', 'true', "x' || true || 'y ", ' plain-uid', 'plain-uid ', 'PLAIN-UID', 'someone']) {
      await assertFails(as(notAdmin).ref('AppConfig/minAppVersion').set('9.9.9'));
    }
  });
});
