// Cloud Firestore rules (firestore.rules): the tip log.
//
// Background: the client logs every tip to Firestore for backup and forensics. It moved from a nested
// tipLogs/... path to a flat tipLogs2 collection in May 2026, but the rules still only covered the old
// path, so every write was denied (the client only logs the error) and nothing was recorded after that.
// These tests replay what the client writes and pin what must be denied.
//
// The collection is only ever read in the Firebase console, which is not subject to these rules, so no
// app may read, update or delete an entry.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { Timestamp, addDoc, collection, deleteDoc, doc, getDoc, getDocs, serverTimestamp, setDoc, updateDoc } from 'firebase/firestore';

const repoRoot = resolve(import.meta.dirname, '..');
const rules = readFileSync(process.env.FIRESTORE_RULES_FILE ?? resolve(repoRoot, 'firestore.rules'), 'utf8');

const password = { firebase: { sign_in_provider: 'password' } };
const google = { firebase: { sign_in_provider: 'google.com' } };
const anonymous = { firebase: { sign_in_provider: 'anonymous' } };

let env;
const fs = (who) => {
  switch (who) {
    case 'unauth':
      return env.unauthenticatedContext().firestore();
    case 'anon':
      return env.authenticatedContext('anonUid', anonymous).firestore();
    case 'alice':
      return env.authenticatedContext('aliceUid', google).firestore();
    case 'bob':
      return env.authenticatedContext('bobUid', password).firestore();
    default:
      throw new Error(`unknown actor ${who}`);
  }
};
const ok = (promise) => assertSucceeds(promise);
const no = (promise) => assertFails(promise);

// What GameTipsViewModel._addLogOfTipToFirestore writes, with realistic values.
const clientLog = (overrides = {}) => ({
  createdAt: serverTimestamp(),
  submittedAtUTC: Timestamp.fromDate(new Date('2026-03-05T08:00:00Z')),
  submittedAtIsoUTC: '2026-03-05T08:00:00.000Z',
  seasonYear: 2026,
  round: 1,
  compId: '-OlgMBuUZb3lUFu-MqNC',
  compName: 'DAU Footy Tipping 2026',
  tipperId: '-OK4hy0GM78N5hHC7zGH',
  tipperName: 'Alice',
  gameId: 'nrl-01-001',
  league: 'nrl',
  homeTeam: 'Broncos',
  awayTeam: 'Raiders',
  gameStartTimeUTC: Timestamp.fromDate(new Date('2026-03-05T09:50:00Z')),
  gameStartTimeIsoUTC: '2026-03-05T09:50:00.000Z',
  tipResult: 'a',
  tip: 'Home 13+',
  submittedByTipperId: '-OK4hy0GM78N5hHC7zGH',
  submittedBy: 'Alice',
  appVersion: '1.4.1',
  buildNumber: '713',
  installTimeUTC: Timestamp.fromDate(new Date('2026-02-01T00:00:00Z')),
  lastUpdateTimeUTC: Timestamp.fromDate(new Date('2026-03-01T00:00:00Z')),
  platform: 'ios',
  ...overrides,
});

const without = (log, key) => {
  const copy = { ...log };
  delete copy[key];
  return copy;
};

const seedLog = async () => {
  let ref;
  await env.withSecurityRulesDisabled(async (ctx) => {
    ref = await addDoc(collection(ctx.firestore(), 'tipLogs2'), clientLog());
  });
  return ref.path;
};

describe('firestore.rules: tipLogs2', () => {
  before(async () => {
    env = await initializeTestEnvironment({ projectId: 'demo-dau-rules', firestore: { rules } });
  });
  after(async () => {
    await env?.cleanup();
  });
  beforeEach(async () => {
    await env.clearFirestore();
  });

  describe('creating a log', () => {
    it('a signed-in tipper can log a tip exactly as the client writes it', async () => {
      await ok(addDoc(collection(fs('alice'), 'tipLogs2'), clientLog()));
      await ok(addDoc(collection(fs('bob'), 'tipLogs2'), clientLog()));
    });

    it('accepts the optional fields being null, as the client may write them', async () => {
      await ok(
        addDoc(
          collection(fs('alice'), 'tipLogs2'),
          clientLog({ round: null, submittedByTipperId: null, submittedBy: null, installTimeUTC: null, lastUpdateTimeUTC: null }),
        ),
      );
    });

    it('accepts a field the client adds later (it must not make logging fail silently again)', async () => {
      await ok(addDoc(collection(fs('alice'), 'tipLogs2'), clientLog({ someNewClientField: 'x', anotherOne: 7 })));
    });

    it('accepts every tip value the client can log', async () => {
      for (const result of ['a', 'b', 'c', 'd', 'e', 'z']) {
        await ok(addDoc(collection(fs('alice'), 'tipLogs2'), clientLog({ tipResult: result })));
      }
    });

    it('a signed-out visitor cannot log', async () => {
      await no(addDoc(collection(fs('unauth'), 'tipLogs2'), clientLog()));
    });

    it('the anonymous browsing account cannot log', async () => {
      await no(addDoc(collection(fs('anon'), 'tipLogs2'), clientLog()));
    });

    it('createdAt must be the server time, not a time the client supplies', async () => {
      await no(addDoc(collection(fs('alice'), 'tipLogs2'), clientLog({ createdAt: Timestamp.fromDate(new Date('2025-01-01T00:00:00Z')) })));
    });

    it('a log missing a field it is useless without is refused', async () => {
      for (const key of ['createdAt', 'submittedAtUTC', 'tipperId', 'gameId', 'compId', 'tipResult', 'tip']) {
        await no(addDoc(collection(fs('alice'), 'tipLogs2'), without(clientLog(), key)));
      }
    });

    it('refuses wrong types and out-of-range values', async () => {
      const bad = [
        { tipperId: 42 },
        { gameId: null },
        { compId: ['x'] },
        { tipResult: 'x' },
        { tipResult: 'ab' },
        { tip: 7 },
        { submittedAtUTC: '2026-03-05' },
        { tip: 'x'.repeat(65) },
        { tipperId: 'x'.repeat(129) },
      ];
      for (const override of bad) {
        await no(addDoc(collection(fs('alice'), 'tipLogs2'), clientLog(override)));
      }
    });

    it('caps how many fields a log can carry, so it cannot be used to dump arbitrary data', async () => {
      const many = Object.fromEntries(Array.from({ length: 41 }, (_, i) => [`k${i}`, 1]));
      await no(addDoc(collection(fs('alice'), 'tipLogs2'), { ...clientLog(), ...many }));
    });
  });

  describe('nothing else is allowed on a log', () => {
    it('no app can read a log, whoever wrote it', async () => {
      const path = await seedLog();
      await no(getDoc(doc(fs('alice'), path)));
      await no(getDoc(doc(fs('bob'), path)));
      await no(getDoc(doc(fs('unauth'), path)));
      await no(getDocs(collection(fs('alice'), 'tipLogs2')));
    });

    it('no app can change or delete a log, including its writer', async () => {
      const path = await seedLog();
      await no(updateDoc(doc(fs('alice'), path), { tip: 'Away' }));
      await no(setDoc(doc(fs('alice'), path), clientLog()));
      await no(deleteDoc(doc(fs('alice'), path)));
      await no(deleteDoc(doc(fs('bob'), path)));
    });
  });

  describe('everything else in Firestore is denied', () => {
    it('the old nested tipLogs path, which used to be open to anyone, is now closed', async () => {
      await no(setDoc(doc(fs('alice'), 'tipLogs/2026/1/tipperId/nrl-01-001/1772700000'), clientLog()));
      await no(setDoc(doc(fs('unauth'), 'tipLogs/2026/1/tipperId/nrl-01-001/1772700000'), { anything: true }));
    });

    it('other collections cannot be written or read', async () => {
      await no(setDoc(doc(fs('alice'), 'elsewhere/doc'), { x: 1 }));
      await no(addDoc(collection(fs('alice'), 'tipLogs'), clientLog()));
      await no(getDocs(collection(fs('alice'), 'elsewhere')));
    });
  });

  describe('the rules and the client agree', () => {
    // Reads the field list straight from the client source, so a change there is checked against the
    // rules before it ships.
    const source = readFileSync(resolve(repoRoot, 'lib/view_models/gametip_viewmodel.dart'), 'utf8');
    const block = source.slice(source.indexOf(".collection('tipLogs2').add({"));
    const fields = [...block.slice(0, block.indexOf('});')).matchAll(/^\s+'(\w+)':/gm)].map((m) => m[1]);

    it('finds the client log fields', () => {
      assert.ok(fields.length >= 20, `found only ${fields.length} fields in the client`);
    });

    it('the client writes every field the rules require, and leaves room under the cap', () => {
      for (const key of ['createdAt', 'submittedAtUTC', 'tipperId', 'gameId', 'compId', 'tipResult', 'tip']) {
        assert.ok(fields.includes(key), `the rules require ${key} but the client no longer writes it`);
      }
      assert.ok(fields.length <= 35, `the client writes ${fields.length} fields; the rules cap a log at 40, so raise the cap before adding many more`);
    });

    it('a log with exactly the client field names is accepted', async () => {
      const typed = clientLog();
      const unknown = fields.filter((f) => !(f in typed));
      assert.deepEqual(unknown, [], `the test's sample log is missing client fields: ${unknown.join(', ')}`);
      const exactlyClientFields = Object.fromEntries(fields.map((f) => [f, typed[f]]));
      await ok(addDoc(collection(fs('alice'), 'tipLogs2'), exactlyClientFields));
    });
  });
});
