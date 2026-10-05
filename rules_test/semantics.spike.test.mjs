// Phase 1 spike: prove the Realtime Database rules semantics that
// DESIGN-database-rules.md depends on. These rule sets are minimal prototypes,
// NOT the production rules. Findings are recorded in
// DESIGN-database-rules-phase1.md.
import assert from 'node:assert/strict';
import { after, afterEach, before, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';

const PROJECT_ID = 'demo-dau-rules';

async function envWith(rules, seed) {
  const env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    database: { rules: JSON.stringify({ rules }) },
  });
  if (seed) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.database().ref().set(seed);
    });
  }
  return env;
}

const db = (env, uid, token) =>
  (uid === null ? env.unauthenticatedContext() : env.authenticatedContext(uid, token)).database();

// withSecurityRulesDisabled returns Promise<void>, so capture the value.
async function peek(env, path) {
  let value;
  await env.withSecurityRulesDisabled(async (ctx) => {
    value = (await ctx.database().ref(path).get()).val();
  });
  return value;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// ---------------------------------------------------------------------------
// S1/S2: cascade, .validate and deletes
// ---------------------------------------------------------------------------
describe('S2 cascade and validate semantics', () => {
  let env;
  before(async () => {
    env = await envWith(
      {
        // Blanket parent grant, locked child with validate-based immutability.
        C: {
          $id: {
            '.write': 'auth != null',
            '.validate': "newData.hasChild('locked')",
            locked: {
              '.write': false,
              '.validate': 'newData.val() === data.val()',
            },
            other: {},
          },
        },
        // Same, but without the parent-level hasChild validate.
        C2: {
          $id: {
            '.write': 'auth != null',
            locked: { '.validate': 'newData.val() === data.val()' },
          },
        },
      },
      {
        C: { a: { locked: 'orig', other: 1 } },
        C2: { a: { locked: 'orig', other: 1 } },
      },
    );
  });
  after(async () => env.cleanup());

  it('parent .write cascades: child .write:false cannot revoke it', async () => {
    // locked has .write:false, but the parent grant applies to descendants.
    // The change is only stopped by .validate, not by .write:false.
    await assertSucceeds(db(env, 'u').ref('C2/a/other').set(2));
    // Writing a SAME value to the locked child succeeds (validate passes).
    await assertSucceeds(db(env, 'u').ref('C2/a/locked').set('orig'));
  });

  it('.validate blocks CHANGING a protected child', async () => {
    await assertFails(db(env, 'u').ref('C2/a/locked').set('hijacked'));
  });

  it('.validate does NOT run on delete: direct delete of the child succeeds', async () => {
    await assertSucceeds(db(env, 'u').ref('C2/a/locked').remove());
    assert.equal(await peek(env, 'C2/a/locked'), null, 'locked field was deleted despite validate');
  });

  it('parent .validate(hasChild) DOES block direct deletion of the required child', async () => {
    await assertFails(db(env, 'u').ref('C/a/locked').remove());
  });

  it('parent .validate blocks replacing the record without the child', async () => {
    await assertFails(db(env, 'u').ref('C/a').set({ other: 3 }));
  });

  it('parent replace keeping the child but with a changed value is blocked', async () => {
    await assertFails(db(env, 'u').ref('C/a').set({ locked: 'x', other: 3 }));
  });

  it('parent replace keeping child unchanged succeeds', async () => {
    await assertSucceeds(db(env, 'u').ref('C/a').set({ locked: 'orig', other: 3 }));
  });

  it('whole-record delete is allowed by a blanket parent grant (needs .write guard)', async () => {
    await assertSucceeds(db(env, 'u').ref('C/a').remove());
  });
});

// ---------------------------------------------------------------------------
// S1: leaf-only grants (R1-style tipper protection)
// ---------------------------------------------------------------------------
describe('S1 leaf-only grants protect identity fields', () => {
  let env;
  before(async () => {
    env = await envWith({
      AllTippers: {
        $id: {
          // create-only at the record level
          '.write':
            "auth != null && !data.exists() && newData.child('tipperRole').val() === 'tipper' && newData.child('authuid').val() === auth.uid",
          authuid: {},
          tipperRole: {},
          name: { '.write': 'auth != null' },
          logon: { '.write': 'auth != null' },
        },
      },
    });
  });
  afterEach(async () => env.clearDatabase());
  after(async () => env.cleanup());

  const seedRecord = (extra) =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.database().ref('AllTippers/t1').set({
        authuid: 'uid1',
        tipperRole: 'admin',
        name: 'Admin',
        logon: 'a@x.com',
        ...extra,
      });
    });

  it('allows create with role tipper and own uid', async () => {
    await assertSucceeds(
      db(env, 'uidN').ref('AllTippers/new').set({ authuid: 'uidN', tipperRole: 'tipper', name: 'N' }),
    );
  });

  it('denies create with role admin', async () => {
    await assertFails(
      db(env, 'uidN').ref('AllTippers/new').set({ authuid: 'uidN', tipperRole: 'admin', name: 'N' }),
    );
  });

  it('denies create with someone else uid', async () => {
    await assertFails(
      db(env, 'uidN').ref('AllTippers/new').set({ authuid: 'uidX', tipperRole: 'tipper', name: 'N' }),
    );
  });

  it('denies unauthenticated create', async () => {
    await assertFails(
      db(env, null).ref('AllTippers/new').set({ authuid: 'uidN', tipperRole: 'tipper', name: 'N' }),
    );
  });

  it('allows updating a permitted leaf on an existing record', async () => {
    await seedRecord();
    await assertSucceeds(db(env, 'anyone').ref('AllTippers/t1/name').set('Renamed'));
  });

  it('denies direct write, delete of authuid and tipperRole', async () => {
    await seedRecord();
    await assertFails(db(env, 'anyone').ref('AllTippers/t1/authuid').set('mine'));
    await assertFails(db(env, 'anyone').ref('AllTippers/t1/authuid').remove());
    await assertFails(db(env, 'anyone').ref('AllTippers/t1/tipperRole').set('admin'));
    await assertFails(db(env, 'anyone').ref('AllTippers/t1/tipperRole').remove());
  });

  it('denies replacing or deleting an existing whole record', async () => {
    await seedRecord();
    await assertFails(
      db(env, 'uid1').ref('AllTippers/t1').set({ authuid: 'uid1', tipperRole: 'tipper', name: 'x' }),
    );
    await assertFails(db(env, 'uid1').ref('AllTippers/t1').remove());
    await assertFails(db(env, 'uid1').ref('AllTippers').set(null));
  });

  it('root multi-location update with one denied leaf is all-or-nothing', async () => {
    await seedRecord();
    await assertFails(
      db(env, 'anyone').ref().update({
        'AllTippers/t1/name': 'Changed',
        'AllTippers/t1/tipperRole': 'tipper',
      }),
    );
    assert.equal(await peek(env, 'AllTippers/t1/name'), 'Admin', 'permitted leaf must not be applied when another fails');
  });

  it('root multi-location update of only permitted leaves succeeds', async () => {
    await seedRecord();
    await assertSucceeds(
      db(env, 'anyone').ref().update({
        'AllTippers/t1/name': 'Changed',
        'AllTippers/t1/logon': 'b@x.com',
      }),
    );
  });
});

// ---------------------------------------------------------------------------
// S3: bidirectional identity lookup and rule-error behaviour
// ---------------------------------------------------------------------------
describe('S3 bidirectional lookup', () => {
  const me =
    "root.child('AuthIndex').child(auth.uid).val()";
  const valid =
    `auth != null && root.child('AllTippers').child(${me}).child('authuid').val() === auth.uid`;
  const admin =
    `${valid} && root.child('AllTippers').child(${me}).child('tipperRole').val() === 'admin'`;

  let env;
  before(async () => {
    env = await envWith(
      { Probe: { '.read': valid }, AdminProbe: { '.read': admin } },
      {
        Probe: 'p',
        AdminProbe: 'p',
        AuthIndex: {
          good: 't_good',
          adminuid: 't_admin',
          spoof: 't_admin', // index points at the admin record, but record authuid differs
          dangling: 't_missing',
        },
        AllTippers: {
          t_good: { authuid: 'good', tipperRole: 'tipper' },
          t_admin: { authuid: 'adminuid', tipperRole: 'admin' },
        },
      },
    );
  });
  after(async () => env.cleanup());

  it('valid mapping is recognised', async () => {
    await assertSucceeds(db(env, 'good').ref('Probe').get());
  });
  it('admin mapping is recognised as admin, tipper is not', async () => {
    await assertSucceeds(db(env, 'adminuid').ref('AdminProbe').get());
    await assertFails(db(env, 'good').ref('AdminProbe').get());
  });
  it('missing index entry denies (child(null) rule error evaluates to deny)', async () => {
    await assertFails(db(env, 'nobody').ref('Probe').get());
  });
  it('tampered index pointing at an admin record with a different authuid is denied', async () => {
    await assertFails(db(env, 'spoof').ref('Probe').get());
    await assertFails(db(env, 'spoof').ref('AdminProbe').get());
  });
  it('index pointing at a missing record is denied', async () => {
    await assertFails(db(env, 'dangling').ref('Probe').get());
  });
  it('unauthenticated is denied', async () => {
    await assertFails(db(env, null).ref('Probe').get());
  });
});

// ---------------------------------------------------------------------------
// S4/S5: numeric kickoff, fail-closed, listener scope, parent deletes
// ---------------------------------------------------------------------------
describe('S4/S5 kickoff lock and read scope', () => {
  const me = "root.child('AuthIndex').child(auth.uid).val()";
  const valid = `auth != null && root.child('AllTippers').child(${me}).child('authuid').val() === auth.uid`;
  const isAdmin = `${valid} && root.child('AllTippers').child(${me}).child('tipperRole').val() === 'admin'`;
  const isOwner = `${valid} && ${me} === $tipperId`;
  const kickoff = "root.child('DAUCompsGames').child($comp).child($game).child('DateUtcEpochMs').val()";

  let env;
  const seed = (extra = {}) => ({
    AuthIndex: { alice: 't_alice', bob: 't_bob', root: 't_admin' },
    AllTippers: {
      t_alice: { authuid: 'alice', tipperRole: 'tipper' },
      t_bob: { authuid: 'bob', tipperRole: 'tipper' },
      t_admin: { authuid: 'root', tipperRole: 'admin' },
    },
    ...extra,
  });

  before(async () => {
    env = await envWith({
      DAUCompsGames: { '.read': 'auth != null' },
      AllTips: {
        $comp: {
          '.read': isAdmin,
          $tipperId: {
            '.read': `${isOwner} || ${isAdmin}`,
            '.write': isAdmin,
            $game: {
              '.read': `${isOwner} || ${isAdmin} || now >= ${kickoff}`,
              '.write': `${isAdmin} || (${isOwner} && now < ${kickoff})`,
              '.validate': "newData.hasChildren(['r','t']) && newData.child('r').isString()",
            },
          },
        },
      },
    });
  });
  afterEach(async () => env.clearDatabase());
  after(async () => env.cleanup());

  const seedGames = (ms) =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.database().ref().set(
        seed({
          DAUCompsGames: { c1: { g1: { DateUtcEpochMs: ms }, g2: { DateUtcEpochMs: ms } } },
          AllTips: { c1: { t_alice: { g1: { r: 'a', t: 1 } } } },
        }),
      );
    });
  const tip = { r: 'a', t: 1 };

  it('owner may write before kickoff, not after', async () => {
    await seedGames(Date.now() + 60_000);
    await assertSucceeds(db(env, 'alice').ref('AllTips/c1/t_alice/g2').set(tip));
    await seedGames(Date.now() - 60_000);
    await assertFails(db(env, 'alice').ref('AllTips/c1/t_alice/g2').set(tip));
  });

  it('exact boundary: write allowed just before kickoff, denied just after', async () => {
    await seedGames(Date.now() + 1_500);
    await assertSucceeds(db(env, 'alice').ref('AllTips/c1/t_alice/g2').set(tip));
    await sleep(1_700);
    await assertFails(db(env, 'alice').ref('AllTips/c1/t_alice/g2').set(tip));
  });

  it('owner cannot delete own tip after kickoff, can before', async () => {
    await seedGames(Date.now() + 60_000);
    await assertSucceeds(db(env, 'alice').ref('AllTips/c1/t_alice/g1').remove());
    await seedGames(Date.now() - 60_000);
    await assertFails(db(env, 'alice').ref('AllTips/c1/t_alice/g1').remove());
  });

  it('other tipper cannot read before kickoff, can read after (per-game)', async () => {
    await seedGames(Date.now() + 60_000);
    await assertFails(db(env, 'bob').ref('AllTips/c1/t_alice/g1').get());
    await seedGames(Date.now() - 60_000);
    await assertSucceeds(db(env, 'bob').ref('AllTips/c1/t_alice/g1').get());
  });

  it('other tipper cannot listen at tipper or comp level even after kickoff', async () => {
    await seedGames(Date.now() - 60_000);
    await assertFails(db(env, 'bob').ref('AllTips/c1/t_alice').get());
    await assertFails(db(env, 'bob').ref('AllTips/c1').get());
    await assertFails(db(env, 'bob').ref('AllTips').get());
  });

  it('owner may listen at own tipper level, admin at comp level', async () => {
    await seedGames(Date.now() - 60_000);
    await assertSucceeds(db(env, 'alice').ref('AllTips/c1/t_alice').get());
    await assertFails(db(env, 'alice').ref('AllTips/c1').get());
    await assertSucceeds(db(env, 'root').ref('AllTips/c1').get());
  });

  it('missing kickoff fails closed (owner write, other read)', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.database().ref().set(seed({ AllTips: { c1: { t_alice: { g1: tip } } } }));
    });
    await assertFails(db(env, 'alice').ref('AllTips/c1/t_alice/g2').set(tip));
    await assertFails(db(env, 'bob').ref('AllTips/c1/t_alice/g1').get());
  });

  it('non-numeric kickoff fails closed', async () => {
    await seedGames('2026-03-05 09:50:00Z');
    await assertFails(db(env, 'alice').ref('AllTips/c1/t_alice/g2').set(tip));
    await assertFails(db(env, 'bob').ref('AllTips/c1/t_alice/g1').get());
  });

  it('admin may write after kickoff and perform parent delete; owner may not parent-delete', async () => {
    await seedGames(Date.now() - 60_000);
    await assertSucceeds(db(env, 'root').ref('AllTips/c1/t_alice/g2').set(tip));
    await assertFails(db(env, 'alice').ref('AllTips/c1/t_alice').remove());
    await assertSucceeds(db(env, 'root').ref('AllTips/c1/t_alice').remove());
  });

  it('root multi-location update mixing allowed and denied is all-or-nothing', async () => {
    await seedGames(Date.now() + 60_000);
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.database().ref('DAUCompsGames/c1/g2/DateUtcEpochMs').set(Date.now() - 60_000);
    });
    await assertFails(
      db(env, 'alice').ref().update({
        'AllTips/c1/t_alice/g1': { r: 'b', t: 2 }, // before kickoff: allowed
        'AllTips/c1/t_alice/g2': { r: 'b', t: 2 }, // after kickoff: denied
      }),
    );
    assert.equal(await peek(env, 'AllTips/c1/t_alice/g1/r'), 'a');
  });

  it('validate rejects a malformed tip (missing t)', async () => {
    await seedGames(Date.now() + 60_000);
    await assertFails(db(env, 'alice').ref('AllTips/c1/t_alice/g2').set({ r: 'a' }));
  });
});

// ---------------------------------------------------------------------------
// S7: trusted server timestamp
// ---------------------------------------------------------------------------
describe('S7 server timestamp as trusted submission time', () => {
  let env;
  before(async () => {
    env = await envWith({
      LS: {
        $game: {
          history: {
            $key: {
              '.write': 'auth != null && !data.exists()',
              '.validate':
                "newData.hasChildren(['t','tipperID']) && newData.child('t').val() === now",
            },
          },
        },
      },
    });
  });
  afterEach(async () => env.clearDatabase());
  after(async () => env.cleanup());

  it('accepts the RTDB server timestamp placeholder', async () => {
    await assertSucceeds(
      db(env, 'u').ref('LS/g1/history/k1').set({ tipperID: 'x', t: { '.sv': 'timestamp' } }),
    );
  });
  it('rejects a client-supplied time', async () => {
    await assertFails(db(env, 'u').ref('LS/g1/history/k1').set({ tipperID: 'x', t: Date.now() }));
  });
  it('rejects overwriting or deleting an existing entry (append-only)', async () => {
    await assertSucceeds(
      db(env, 'u').ref('LS/g1/history/k1').set({ tipperID: 'x', t: { '.sv': 'timestamp' } }),
    );
    await assertFails(
      db(env, 'u').ref('LS/g1/history/k1').set({ tipperID: 'y', t: { '.sv': 'timestamp' } }),
    );
    await assertFails(db(env, 'u').ref('LS/g1/history/k1').remove());
  });
});

// ---------------------------------------------------------------------------
// S9: pre-auth AppConfig read semantics
// ---------------------------------------------------------------------------
describe('S9 parent reads are not authorised by child grants', () => {
  let env;
  before(async () => {
    env = await envWith(
      {
        PerKey: { minAppVersion: { '.read': true } },
        Whole: { '.read': true, '.write': false },
      },
      { PerKey: { minAppVersion: '1.0.0', other: 'x' }, Whole: { minAppVersion: '1.0.0' } },
    );
  });
  after(async () => env.cleanup());

  it('per-key public read does NOT permit listening at the parent', async () => {
    await assertSucceeds(db(env, null).ref('PerKey/minAppVersion').get());
    await assertFails(db(env, null).ref('PerKey').get());
  });
  it('a public-read parent permits the unauthenticated parent listener', async () => {
    await assertSucceeds(db(env, null).ref('Whole').get());
    await assertFails(db(env, null).ref('Whole/minAppVersion').set('0.0.1'));
  });
});

// ---------------------------------------------------------------------------
// S10: anonymous detection
// ---------------------------------------------------------------------------
describe('S10 anonymous sign-in detection', () => {
  let env;
  before(async () => {
    env = await envWith(
      {
        NotAnon: { '.read': "auth != null && auth.token.firebase.sign_in_provider !== 'anonymous'" },
        VerifiedEmail: {
          '.read': 'auth != null && auth.token.email_verified === true && auth.token.email != null',
        },
      },
      { NotAnon: 1, VerifiedEmail: 1 },
    );
  });
  after(async () => env.cleanup());

  it('distinguishes anonymous from provider sign-in', async () => {
    await assertFails(
      db(env, 'a', { firebase: { sign_in_provider: 'anonymous' } }).ref('NotAnon').get(),
    );
    await assertSucceeds(
      db(env, 'g', { firebase: { sign_in_provider: 'google.com' } }).ref('NotAnon').get(),
    );
  });
  it('can require a verified email', async () => {
    await assertSucceeds(
      db(env, 'g', { email: 'a@b.com', email_verified: true }).ref('VerifiedEmail').get(),
    );
    await assertFails(
      db(env, 'g', { email: 'a@b.com', email_verified: false }).ref('VerifiedEmail').get(),
    );
  });
});

// ---------------------------------------------------------------------------
// S8: rule lookup count limit
// ---------------------------------------------------------------------------
describe('S8 number of root.child lookups per rule', () => {
  const seed = {};
  for (let i = 1; i <= 60; i += 1) seed[`k${i}`] = 1;
  seed.Probe = 'p';

  for (const n of [4, 8, 10, 11, 20, 40]) {
    it(`rule with ${n} distinct lookups (documented as lookups of data)`, async (t) => {
      const expr = Array.from({ length: n }, (_, i) => `root.child('k${i + 1}').val() === 1`).join(' && ');
      const env = await envWith({ Probe: { '.read': expr }, ...Object.fromEntries([]) }, seed);
      try {
        let outcome;
        try {
          await assertSucceeds(db(env, 'u').ref('Probe').get());
          outcome = 'allowed';
        } catch (err) {
          outcome = `denied: ${String(err.message).slice(0, 120)}`;
        }
        t.diagnostic(`${n} lookups -> ${outcome}`);
        console.log(`S8 ${n} lookups -> ${outcome}`);
      } finally {
        await env.cleanup();
      }
    });
  }
});
