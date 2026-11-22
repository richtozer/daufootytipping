// The conformance matrix: what a 1.4.x client and an R2 client actually do, against R1, R1-compat, freeze and R2.
// DESIGN-database-rules-phase4.md section 10 ("Test matrix: 1.4.x and R2 client against R1, R1-compat, freeze and
// R2 ... a 1.4.x client against R2 must fail closed with the existing messages and no data change").
//
// Every cell is stated BEFORE it is run. A cell that surprises is a finding: either the table is wrong or a rule is.
// `ok` means the operation succeeds, `no` that the rules refuse it (permission denied). Where the 1.4.x client is
// refused by R2, nothing is written: each operation is checked to leave the data as it was.
//
// FIXTURE uids only. The administrator is both on the R1 allowlist AND linked as a validated admin, as the
// owner's real account is, so the same actor is an administrator under every ruleset.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { PATHS, buildRules } from '../scripts/build_admin_allowlist.mjs';

const ADMIN_UID = 'ADMINfixtureUID000000000001';
const template = readFileSync(PATHS.template, 'utf8');
const r2Template = readFileSync(PATHS.r2Template, 'utf8');
const RULESETS = [
  ['R1', buildRules(template, [ADMIN_UID])],
  ['R1-compat', buildRules(template, [ADMIN_UID], { variant: 'r1-compat' })],
  ['freeze', buildRules(template, [ADMIN_UID], { variant: 'freeze' })],
  ['R2', buildRules(r2Template, [ADMIN_UID], { variant: 'r2' })],
];

const google = { firebase: { sign_in_provider: 'google.com' } };
const anonymous = { firebase: { sign_in_provider: 'anonymous' } };
const actors = {
  unauth: null,
  anon: { uid: 'anonUid', token: anonymous },
  alice: { uid: 'aliceUid', token: google }, // linked tipper t1
  erin: { uid: 'erinUid', token: google }, // signed in, never linked
  admin: { uid: ADMIN_UID, token: google }, // allowlisted AND a linked admin
};

const NOW = Date.now();
const secs = Math.floor(NOW / 1000);
const stamp = { '.sv': 'timestamp' };

const seed = () => ({
  AppConfig: { minAppVersion: '1.4.0', currentDAUComp: 'c1' },
  Teams: { a: { name: 'A' } },
  AllDAUComps: { c1: { name: '2027' } },
  DAUCompsGames: {
    c1: {
      started: { DateUtc: 'x', DateUtcEpochMs: NOW - 3_600_000 },
      upcoming: { DateUtc: 'x', DateUtcEpochMs: NOW + 3_600_000 },
    },
  },
  AllTippers: {
    t1: { name: 'Alice', authuid: 'aliceUid', tipperRole: 'tipper', email: 'a@x.test', logon: 'a@x.test', photoURL: 'a.png' },
    t2: { name: 'Bob', authuid: 'bobUid', tipperRole: 'tipper', email: 'b@x.test', logon: 'b@x.test', compsParticipatedIn: ['c1'] },
    tAdmin: { name: 'Root', authuid: ADMIN_UID, tipperRole: 'admin' },
  },
  AuthIndex: { aliceUid: 't1', bobUid: 't2', [ADMIN_UID]: 'tAdmin' },
  TipperPrivate: {
    t1: { authuid: 'aliceUid', tipperRole: 'tipper', logon: 'a@x.test' },
    t2: { authuid: 'bobUid', tipperRole: 'tipper', logon: 'b@x.test' },
    tAdmin: { authuid: ADMIN_UID, tipperRole: 'admin' },
  },
  AllTips: {
    c1: {
      t1: { started: { r: 'a', t: secs }, upcoming: { r: 'b', t: secs } },
      t2: { started: { r: 'c', t: secs }, upcoming: { r: 'd', t: secs } },
    },
  },
  AllTippersTokens: { t1: { tokA: 1 }, t2: { tokB: 1 } },
  Stats: {
    c1: {
      scoring_status: { status: 'completed' },
      live_scores_backend_v1: { started: { current: { homeInterimScore: 1 }, history: { h0: { tipperID: 't2', scoreTeam: 'home', interimScore: 1, t: NOW - 60_000 } } } },
    },
  },
  ServerConfig: { identity: { mode: 'coexist' } },
});

// [name, actor, operation, expected outcome under [R1, R1-compat, freeze, R2]]
const OK = 'ok';
const NO = 'no';
const OPERATIONS = [
  // ----- what a 1.4.x client does, signed in or not -----
  ['1.4.x: reads AppConfig before sign-in', 'unauth', (d) => d.ref('AppConfig').get(), [OK, OK, OK, OK]],
  ['1.4.x: lists the tippers, signed in', 'alice', (d) => d.ref('AllTippers').get(), [OK, OK, OK, OK]],
  ['1.4.x: lists the tippers, before sign-in', 'unauth', (d) => d.ref('AllTippers').get(), [OK, OK, OK, NO]],
  ['1.4.x: reads Teams signed in / before sign-in', 'alice', (d) => d.ref('Teams').get(), [OK, OK, OK, OK]],
  ['1.4.x: reads Teams before sign-in', 'unauth', (d) => d.ref('Teams').get(), [OK, OK, OK, NO]],
  ['1.4.x: browses games as an anonymous session', 'anon', (d) => d.ref('DAUCompsGames/c1').get(), [OK, OK, OK, OK]],
  ['1.4.x: listens to the whole competition\'s tips', 'alice', (d) => d.ref('AllTips/c1').get(), [OK, OK, OK, NO]],
  ['1.4.x: listens to its own tips', 'alice', (d) => d.ref('AllTips/c1/t1').get(), [OK, OK, OK, OK]],
  ['1.4.x: reads another tipper\'s tip for a game that has started', 'alice', (d) => d.ref('AllTips/c1/t2/started').get(), [OK, OK, OK, OK]],
  ['1.4.x: reads another tipper\'s tip for a game not yet started', 'alice', (d) => d.ref('AllTips/c1/t2/upcoming').get(), [OK, OK, OK, NO]],
  ['1.4.x: tips before kickoff', 'alice', (d) => d.ref('AllTips/c1/t1/upcoming').set({ r: 'e', t: secs }), [OK, OK, OK, OK]],
  ['1.4.x: tips after kickoff', 'alice', (d) => d.ref('AllTips/c1/t1/started').set({ r: 'e', t: secs }), [OK, OK, OK, NO]],
  ['1.4.x: writes a tip under someone else\'s name', 'alice', (d) => d.ref('AllTips/c1/t2/upcoming').set({ r: 'e', t: secs }), [OK, OK, OK, NO]],
  ['1.4.x: reads the stats', 'alice', (d) => d.ref('Stats/c1/scoring_status').get(), [OK, OK, OK, OK]],
  [
    '1.4.x: adds a live-score entry (its own shape)',
    'alice',
    (d) => d.ref('Stats/c1/live_scores_backend_v1/started/history/k1').set({ tipperID: 't1', scoreTeam: 'home', interimScore: 6, gameComplete: false, submittedTimeUTC: '2027-03-07T00:00:00.000Z' }),
    [OK, OK, OK, NO],
  ],
  ['1.4.x: writes the live-score snapshot', 'alice', (d) => d.ref('Stats/c1/live_scores_backend_v1/started/current').set({ homeInterimScore: 6 }), [OK, OK, OK, NO]],
  ['1.4.x: changes its own photo', 'alice', (d) => d.ref('AllTippers/t1/photoURL').set('new.png'), [OK, OK, OK, OK]],
  ['1.4.x: registers a device token itself', 'alice', (d) => d.ref('AllTippersTokens/t1/newTok').set(1), [OK, OK, OK, NO]],
  ['1.4.x: reads every tipper\'s tokens (to remove its own from others)', 'alice', (d) => d.ref('AllTippersTokens').get(), [OK, OK, OK, NO]],
  ['1.4.x: renames itself', 'alice', (d) => d.ref('AllTippers/t1/name').set('Alicia'), [OK, OK, NO, NO]],
  ['1.4.x: a first sign-in creates its own tipper record', 'erin', (d) => d.ref('AllTippers/tErin').set({ authuid: 'erinUid', tipperRole: 'tipper', name: 'Erin' }), [OK, OK, NO, NO]],
  ['1.4.x: tries to make itself an administrator', 'alice', (d) => d.ref('AllTippers/t1/tipperRole').set('admin'), [NO, NO, NO, NO]],
  ['1.4.x admin: toggles a paid comp', 'admin', (d) => d.ref('AllTippers/t1/compsParticipatedIn').set(['c1']), [OK, OK, OK, OK]],
  ['1.4.x admin: renames a tipper', 'admin', (d) => d.ref('AllTippers/t1/name').set('Renamed'), [OK, OK, NO, NO]],
  ['1.4.x admin: merges by deleting a tipper record', 'admin', (d) => d.ref('AllTippers/t2').remove(), [OK, OK, NO, NO]],
  ['1.4.x admin: merges by moving the tips (deleting the old tip node)', 'admin', (d) => d.ref('AllTips/c1/t2').remove(), [OK, OK, NO, OK]],
  ['1.4.x admin: edits the app config', 'admin', (d) => d.ref('AppConfig/currentDAUComp').set('c2'), [OK, OK, OK, OK]],
  ['1.4.x: an ordinary tipper edits the app config', 'alice', (d) => d.ref('AppConfig/currentDAUComp').set('c2'), [NO, NO, NO, NO]],
  ['1.4.x: reads the server\'s configuration', 'alice', (d) => d.ref('ServerConfig').get(), [NO, NO, NO, NO]],

  // ----- what the R2 client does -----
  ['R2: reads its own index entry', 'alice', (d) => d.ref('AuthIndex/aliceUid').get(), [NO, OK, OK, OK]],
  ['R2: an unlinked user reads their own index entry and gets nothing', 'erin', (d) => d.ref('AuthIndex/erinUid').get(), [NO, OK, OK, OK]],
  ['R2: reads its own private record', 'alice', (d) => d.ref('TipperPrivate/t1').get(), [NO, OK, OK, OK]],
  ['R2: reads someone else\'s private record', 'alice', (d) => d.ref('TipperPrivate/t2').get(), [NO, NO, NO, NO]],
  ['R2 admin: reads every private record', 'admin', (d) => d.ref('TipperPrivate').get(), [NO, OK, OK, OK]],
  ['R2: listens to one game\'s tip for another tipper, once it has started', 'alice', (d) => d.ref('AllTips/c1/t2/started').get(), [OK, OK, OK, OK]],
  [
    'R2: adds a live-score entry with the server\'s time',
    'alice',
    (d) => d.ref('Stats/c1/live_scores_backend_v1/started/history/k1').set({ tipperID: 't1', scoreTeam: 'home', interimScore: 6, t: stamp }),
    [OK, OK, OK, OK],
  ],
  ['R2: an anonymous session browses the tippers', 'anon', (d) => d.ref('AllTippers').get(), [OK, OK, OK, OK]],
  ['R2: an anonymous session tips', 'anon', (d) => d.ref('AllTips/c1/t1/upcoming').set({ r: 'e', t: secs }), [NO, NO, NO, NO]],
  ['R2: writes its own index entry or private record (tampering)', 'alice', (d) => d.ref().update({ 'AuthIndex/aliceUid': 'tAdmin', 'TipperPrivate/t1/tipperRole': 'admin' }), [NO, NO, NO, NO]],
];

for (const [rulesetIndex, [rulesetName, rules]] of RULESETS.entries()) {
  describe(`conformance matrix: ${rulesetName}`, () => {
    let env;
    const db = (who) => {
      const a = actors[who];
      return (a === null ? env.unauthenticatedContext() : env.authenticatedContext(a.uid, a.token)).database();
    };
    const dataNow = async () => {
      let value;
      await env.withSecurityRulesDisabled(async (ctx) => {
        value = (await ctx.database().ref().get()).val();
      });
      return JSON.stringify(value);
    };

    before(async () => {
      env = await initializeTestEnvironment({ projectId: 'demo-dau-rules', database: { rules: JSON.stringify(rules) } });
    });
    beforeEach(async () => {
      await env.clearDatabase();
      await env.withSecurityRulesDisabled(async (ctx) => {
        await ctx.database().ref().set(seed());
      });
    });
    after(async () => env.cleanup());

    for (const [name, who, operation, expected] of OPERATIONS) {
      const outcome = expected[rulesetIndex];
      it(`${name}: ${outcome}`, async () => {
        const before = await dataNow();
        if (outcome === OK) {
          await assertSucceeds(operation(db(who)));
        } else {
          await assertFails(operation(db(who)));
          assert.equal(await dataNow(), before, 'a refused operation must leave the data exactly as it was');
        }
      });
    }
  });
}
