// Seeds the emulators for the real-client smoke test (synthetic data, fixture admin UID).
// Run inside the OS boundary with loopback emulator hosts (see README.md).
//   * loads the R1 rules, with ONLY the fixture admin UID, into the app's database namespace
//   * creates verified fixture users in the Auth emulator
//   * writes the synthetic database
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { buildRules, PATHS } from '../../scripts/build_admin_allowlist.mjs';
import { COMP, DATABASE_NAMESPACE, DATABASE_URL, PASSWORD, PROJECT_ID, UIDS, USERS, buildDatabase } from './fixture.mjs';

const require = createRequire(new URL('../../functions/', import.meta.url));
const { deleteApp, initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getDatabase } = require('firebase-admin/database');

const dbHost = process.env.FIREBASE_DATABASE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!dbHost || !authHost) throw new Error('Emulator hosts are not set: run this inside the emulators');
for (const host of [dbHost, authHost]) {
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) throw new Error(`Refusing non-loopback emulator host ${host}`);
}

const variant = process.argv.includes('--recovery') ? 'r1-recovery' : 'r1';
const rules = buildRules(readFileSync(PATHS.template, 'utf8'), [UIDS.admin], { variant });

// 1. Rules for the app's namespace (the emulator keeps rules per namespace).
const put = await fetch(`http://${dbHost}/.settings/rules.json?ns=${DATABASE_NAMESPACE}`, {
  method: 'PUT',
  headers: { Authorization: 'Bearer owner' },
  body: JSON.stringify(rules),
});
if (!put.ok) throw new Error(`Loading rules failed: ${put.status} ${await put.text()}`);

const app = initializeApp({ projectId: PROJECT_ID, databaseURL: DATABASE_URL }, 'smoke-seed');
const auth = getAuth(app);
const db = getDatabase(app);

// 2. Auth users (verified, so the app lets them in; the registration scenario creates its own).
// Start from a clean Auth emulator so a previous run's registrations and anonymous users are gone.
const wipe = await fetch(`http://${authHost}/emulator/v1/projects/${PROJECT_ID}/accounts`, { method: 'DELETE' });
if (!wipe.ok) throw new Error(`Clearing the Auth emulator failed: ${wipe.status}`);
for (const key of Object.keys(USERS)) {
  await auth.createUser({ uid: UIDS[key], email: USERS[key].email, password: PASSWORD, emailVerified: true, displayName: USERS[key].name });
}

// 3. Data.
await db.ref().set(buildDatabase());

console.log(`seeded: rules=${variant} (admin allowlist = fixture UID only), ${Object.keys(USERS).length} users, comp ${COMP}, namespace ${DATABASE_NAMESPACE}`);
getDatabase(app).goOffline();
await deleteApp(app);
