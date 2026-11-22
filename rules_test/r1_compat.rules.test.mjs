// R1-COMPAT rules: R1 plus exactly the two reads the R2 client needs, and nothing else.
// DESIGN-database-rules-phase4.md, section 3. Generated from the same template and allowlist as R1
// (FIXTURE admin UIDs only, never real ones).
//
// What is proved:
//   1. Structurally, the ruleset is R1 plus the two new nodes, with no `.write` or `.validate` in them, so
//      it cannot add a write permission and 1.4.x clients behave exactly as under R1.
//   2. A signed-in user reads only their OWN AuthIndex entry.
//   3. A signed-in user reads a TipperPrivate record only when the link agrees in BOTH directions;
//      allowlisted admins read every record; nobody else reads the node.
//   4. Neither node, and no other identity node, can be written or listed by any client.
//   5. A few R1 behaviours are untouched.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { PATHS, buildRules } from '../scripts/build_admin_allowlist.mjs';

const ADMIN_UID = 'ADMINfixtureUID000000000001';
const ADMIN2_UID = 'ADMINfixtureUID000000000002';
const template = readFileSync(PATHS.template, 'utf8');
const r1 = buildRules(template, [ADMIN_UID, ADMIN2_UID]);
const compat = buildRules(template, [ADMIN_UID, ADMIN2_UID], { variant: 'r1-compat' });

const google = { firebase: { sign_in_provider: 'google.com' } };
const anonymous = { firebase: { sign_in_provider: 'anonymous' } };

const actors = {
  unauth: null,
  anon: { uid: 'anonUid', token: anonymous },
  alice: { uid: 'aliceUid', token: google },
  bob: { uid: 'bobUid', token: google },
  carol: { uid: 'carolUid', token: google },
  dave: { uid: 'daveUid', token: google },
  erin: { uid: 'erinUid', token: google }, // signed in, but has no AuthIndex entry at all
  admin: { uid: ADMIN_UID, token: google },
  admin2: { uid: ADMIN2_UID, token: google },
  // A user whose DATABASE record says admin, but who is not on the allowlist.
  fakeAdmin: { uid: 'fakeAdminUid', token: google },
};

const seed = () => ({
  AppConfig: { minAppVersion: '1.4.0', currentDAUComp: 'c1' },
  AllDAUComps: { c1: { name: '2026' } },
  AllTippers: {
    t1: { authuid: 'aliceUid', tipperRole: 'tipper', name: 'Alice' },
    t2: { authuid: 'bobUid', tipperRole: 'tipper', name: 'Bob' },
    tFake: { authuid: 'fakeAdminUid', tipperRole: 'admin', name: 'Fake' },
  },
  AllTips: { c1: { t1: { g1: { r: 'a', t: 1772000000 } } } },
  // The server-owned identity data, linked in both directions where it should be.
  AuthIndex: {
    aliceUid: 't1',
    bobUid: 't2',
    fakeAdminUid: 'tFake',
    carolUid: 'tCarol', // the index says carol, but the record names someone else
    daveUid: 'tDave', // the index says dave, but the record names nobody
    anonUid: 'tAnon', // an anonymous session can never read its entry
  },
  TipperPrivate: {
    t1: { authuid: 'aliceUid', tipperRole: 'tipper', logon: 'alice@x.test', email: 'alice@x.test' },
    t2: { authuid: 'bobUid', tipperRole: 'tipper', logon: 'bob@x.test', email: 'bob@x.test' },
    tFake: { authuid: 'fakeAdminUid', tipperRole: 'admin', logon: 'f@x.test' },
    tCarol: { authuid: 'someoneElseUid', tipperRole: 'tipper' },
    tDave: { tipperRole: 'tipper' },
    tAnon: { authuid: 'anonUid', tipperRole: 'tipper' },
    // Alice is named by this record, but the index points her at t1.
    tHalf: { authuid: 'aliceUid', tipperRole: 'tipper' },
  },
  AliasIndex: { alice: 't1' },
  LogonIndex: { someKey: 't1' },
  Placeholders: { t1: 'placeholder' },
  ServerConfig: { identity: { mode: 'off' } },
  ClaimMoves: { t1: { kind: 'alias' } },
  TokenOwners: { tok: { owner: 't1', seq: 1 } },
  CreateIntents: { aliceUid: { tipperId: 't1' } },
  IdentityLocks: { t1: 'op|1' },
});

describe('r1-compat is R1 plus two read rules and nothing else', () => {
  const walk = (node, visit, path = []) => {
    for (const [key, value] of Object.entries(node)) {
      visit(key, [...path, key]);
      if (value && typeof value === 'object') walk(value, visit, [...path, key]);
    }
  };

  it('adds exactly AuthIndex and TipperPrivate, and leaves every R1 node as it was', () => {
    const added = Object.keys(compat.rules).filter((key) => !(key in r1.rules));
    assert.deepEqual(added.sort(), ['AuthIndex', 'TipperPrivate']);
    for (const key of Object.keys(r1.rules)) {
      assert.deepEqual(compat.rules[key], r1.rules[key], `${key} must be exactly as in R1`);
    }
  });

  it('contains no write rule, no validation and no index in what it adds', () => {
    for (const node of ['AuthIndex', 'TipperPrivate']) {
      walk(compat.rules[node], (key, path) => {
        assert.ok(['.read', '$uid', '$tipperId'].includes(key), `unexpected key ${path.join('/')} under ${node}`);
        assert.notEqual(key, '.write', `${node} must have no .write`);
      });
    }
  });

  it('every rule it adds is a read, and requires a signed-in user or an allowlisted admin', () => {
    const reads = [
      compat.rules.AuthIndex.$uid['.read'],
      compat.rules.TipperPrivate['.read'],
      compat.rules.TipperPrivate.$tipperId['.read'],
    ];
    for (const read of reads) {
      assert.match(read, /auth != null/);
      assert.doesNotMatch(read, /^true$/);
    }
    assert.match(compat.rules.AuthIndex.$uid['.read'], /sign_in_provider !== 'anonymous'/);
    assert.match(compat.rules.TipperPrivate.$tipperId['.read'], /sign_in_provider !== 'anonymous'/);
  });
});

describe('r1-compat against the rules engine', () => {
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
      database: { rules: JSON.stringify(compat) },
    });
  });
  beforeEach(async () => {
    await env.clearDatabase();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.database().ref().set(seed());
    });
  });
  after(async () => env.cleanup());

  describe('AuthIndex: a signed-in user reads their own entry and nothing else', () => {
    it('reads their own entry', async () => {
      const entry = await ok('alice', (d) => d.ref('AuthIndex/aliceUid').get());
      assert.equal(entry.val(), 't1');
    });

    it('a user with no link reads their own entry and gets null: a successful "no entry", not a denial', async () => {
      const entry = await ok('erin', (d) => d.ref('AuthIndex/erinUid').get());
      assert.equal(entry.val(), null);
    });

    it('cannot read anyone else\'s entry', async () => {
      await no('alice', (d) => d.ref('AuthIndex/bobUid').get());
      await no('bob', (d) => d.ref('AuthIndex/aliceUid').get());
    });

    it('cannot list the node, and neither can an admin', async () => {
      await no('alice', (d) => d.ref('AuthIndex').get());
      await no('admin', (d) => d.ref('AuthIndex').get());
      await no('admin', (d) => d.ref('AuthIndex/aliceUid').get());
    });

    it('is refused to an anonymous session even for its own uid, and to the unauthenticated', async () => {
      await no('anon', (d) => d.ref('AuthIndex/anonUid').get());
      await no('unauth', (d) => d.ref('AuthIndex/aliceUid').get());
    });
  });

  describe('TipperPrivate: the owner rule needs the link to agree in both directions', () => {
    it('the owner reads their record', async () => {
      const record = await ok('alice', (d) => d.ref('TipperPrivate/t1').get());
      assert.equal(record.val().logon, 'alice@x.test');
      await ok('alice', (d) => d.ref('TipperPrivate/t1/email').get());
    });

    it('nobody reads someone else\'s record', async () => {
      await no('alice', (d) => d.ref('TipperPrivate/t2').get());
      await no('bob', (d) => d.ref('TipperPrivate/t1').get());
    });

    it('a record that names the user, but the index points elsewhere, is refused', async () => {
      // tHalf says authuid = aliceUid, but AuthIndex[aliceUid] = t1.
      await no('alice', (d) => d.ref('TipperPrivate/tHalf').get());
    });

    it('an index entry that points at a record naming someone else is refused', async () => {
      // AuthIndex[carolUid] = tCarol, but tCarol.authuid = someoneElseUid.
      await no('carol', (d) => d.ref('TipperPrivate/tCarol').get());
    });

    it('an index entry that points at a record with no owner is refused', async () => {
      await no('dave', (d) => d.ref('TipperPrivate/tDave').get());
    });

    it('a user with no index entry reads nothing', async () => {
      await no('erin', (d) => d.ref('TipperPrivate/t1').get());
    });

    it('cannot list the node', async () => {
      await no('alice', (d) => d.ref('TipperPrivate').get());
      await no('bob', (d) => d.ref('TipperPrivate').get());
    });

    it('allowlisted admins read every record and the whole node', async () => {
      await ok('admin', (d) => d.ref('TipperPrivate/t1').get());
      await ok('admin', (d) => d.ref('TipperPrivate/tCarol').get());
      const all = await ok('admin2', (d) => d.ref('TipperPrivate').get());
      assert.equal(Object.keys(all.val()).length, 7);
    });

    it('a user whose DATABASE record says admin, but who is not on the allowlist, gets no extra read', async () => {
      await no('fakeAdmin', (d) => d.ref('TipperPrivate').get());
      await no('fakeAdmin', (d) => d.ref('TipperPrivate/t1').get());
      await ok('fakeAdmin', (d) => d.ref('TipperPrivate/tFake').get()); // their own, by the owner rule
    });

    it('is refused to an anonymous session and to the unauthenticated', async () => {
      await no('anon', (d) => d.ref('TipperPrivate/tAnon').get());
      await no('unauth', (d) => d.ref('TipperPrivate/t1').get());
    });
  });

  describe('no client can write either node, or touch any other identity node', () => {
    it('nobody writes AuthIndex or TipperPrivate: not the owner, not an admin', async () => {
      for (const who of ['alice', 'bob', 'admin', 'admin2', 'fakeAdmin', 'anon', 'unauth']) {
        await no(who, (d) => d.ref('AuthIndex/aliceUid').set('t2'));
        await no(who, (d) => d.ref('AuthIndex/brandNewUid').set('t1'));
        await no(who, (d) => d.ref('AuthIndex/aliceUid').remove());
        await no(who, (d) => d.ref('TipperPrivate/t1/logon').set('evil@x.test'));
        await no(who, (d) => d.ref('TipperPrivate/t1').update({ email: 'evil@x.test' }));
        await no(who, (d) => d.ref('TipperPrivate/t9').set({ authuid: 'aliceUid', tipperRole: 'admin' }));
        await no(who, (d) => d.ref('TipperPrivate/t1').remove());
      }
      assert.equal(await peek(env, 'AuthIndex/aliceUid'), 't1');
      assert.equal(await peek(env, 'TipperPrivate/t1/logon'), 'alice@x.test');
    });

    it('the other server-owned identity nodes stay closed for reading and writing', async () => {
      for (const node of ['AliasIndex', 'LogonIndex', 'Placeholders', 'ServerConfig', 'ClaimMoves', 'TokenOwners', 'CreateIntents', 'IdentityLocks']) {
        for (const who of ['alice', 'admin', 'unauth']) {
          await no(who, (d) => d.ref(node).get());
          await no(who, (d) => d.ref(node).set({ x: 1 }));
        }
      }
    });
  });

  describe('R1 behaviour is untouched', () => {
    it('the public reads and the tipper list are as in R1', async () => {
      await ok('unauth', (d) => d.ref('AllTippers').get());
      await ok('unauth', (d) => d.ref('AppConfig').get());
    });

    it('a user still writes their own tip, and not someone else\'s tipper record', async () => {
      await ok('alice', (d) => d.ref('AllTips/c1/t1/g2').set({ r: 'b', t: 1772000100 }));
      await no('bob', (d) => d.ref('AllTippers/t1/authuid').set('bobUid'));
      await no('bob', (d) => d.ref('AllTippers/t1').remove());
    });

    it('a non-admin still cannot write admin-only data', async () => {
      await no('alice', (d) => d.ref('AppConfig/minAppVersion').set('0.0.1'));
      await ok('admin', (d) => d.ref('AppConfig/minAppVersion').set('1.4.1'));
    });
  });
});

async function peek(env, path) {
  let value;
  await env.withSecurityRulesDisabled(async (ctx) => {
    value = (await ctx.database().ref(path).get()).val();
  });
  return value;
}
