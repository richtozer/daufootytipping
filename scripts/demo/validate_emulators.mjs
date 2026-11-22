// Integration check of the generated import folder, on alternate ports with
// only the Auth and Database emulators (no Functions, so nothing is triggered).
// Run through validate_emulators.sh; never against a developer's session.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { repoRoot } from './generate.mjs';
import { COMP, NAMESPACE, roster } from './roster.mjs';

if (process.env.FIREBASE_DATABASE_EMULATOR_HOST !== '127.0.0.1:19000' || process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:19099') {
  throw new Error('Run only inside the validation emulators started by validate_emulators.sh');
}
const namespace = NAMESPACE;
const { password } = JSON.parse(readFileSync(resolve(repoRoot, 'emulator/demo/credentials.json'), 'utf8'));
let token;
for (const person of roster) {
  const response = await fetch('http://127.0.0.1:19099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-key', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: person.email, password, returnSecureToken: true }),
  });
  assert.equal(response.status, 200, `Sign in ${person.id}`);
  const account = await response.json();
  assert.equal(account.localId, person.uid);
  if (person.id === 'daisy') token = account.idToken;
}
async function db(path, method = 'GET', value, admin = false) {
  return fetch(`http://127.0.0.1:19000/${path}.json?ns=${namespace}${admin ? '' : `&auth=${encodeURIComponent(token)}`}`, {
    method, headers: { 'Content-Type': 'application/json', ...(admin ? { Authorization: 'Bearer owner' } : {}) },
    ...(value === undefined ? {} : { body: JSON.stringify(value) }),
  });
}
assert.equal(await (await db('AuthIndex/demo-celebrity-daisy')).json(), 'demo-daisy');
assert.equal((await db('TipperPrivate/demo-daisy')).status, 200);
assert.equal((await db('TipperPrivate/demo-albo')).status, 401);
const publicTippers = await (await db('AllTippers')).json();
assert.equal(Object.keys(publicTippers).length, 20);
assert.equal(publicTippers['demo-daisy'].email, undefined);
const games = await (await db(`DAUCompsGames/${COMP}`)).json();
const future = Object.keys(games).find(key => games[key].DateUtcEpochMs > Date.now() + 86400000);
const past = Object.keys(games).find(key => games[key].DateUtcEpochMs < Date.now() - 86400000);
assert.ok(future && past, 'Regenerate demo relative to now if the fixed snapshot is stale');
const tip = { r: 'b', t: Math.floor(Date.now() / 1000) };
assert.equal((await db(`AllTips/${COMP}/demo-daisy/${future}`, 'PUT', tip)).status, 200);
assert.equal((await db(`AllTips/${COMP}/demo-albo/${future}`, 'PUT', tip)).status, 401);
assert.equal((await db(`AllTips/${COMP}/demo-daisy/${past}`, 'PUT', tip)).status, 401);
const stats = await (await db(`Stats/${COMP}`)).json();
const rounds = stats.round_stats_backend_v1;
assert.equal(Object.values(rounds).filter(Boolean).length, 12);
assert.equal(Object.keys(rounds[8]).length, 20);
const totals = Object.keys(publicTippers).map(id => Object.values(rounds).filter(Boolean).reduce((sum, r) => sum + r[id].aS + r[id].nS, 0));
assert.ok(new Set(totals).size > 10, 'Leaderboard should have varied calculated scores');
// No crowd-sourced live scores, so the app shows no live-score warning.
assert.equal(stats.live_scores_backend_v1, undefined);
for (const season of [2022, 2023, 2024, 2025]) {
  const past = await (await db(`DAUCompsGames/demo-celebrity-${season}`, 'GET', undefined, true)).json();
  assert.ok(Object.keys(past ?? {}).length > 400, `past season ${season}`);
}
assert.ok(Object.keys(await (await db('AllTips/demo-celebrity-2025/demo-daisy')).json()).length > 400);
console.log('PASS: imported data and 20 sign-ins, private identity isolation, own future tip, rejected cross-user/past writes, round/game stats, no live scores, past seasons.');
