import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { aliasKey, logonKey, buildDemo, extractFixtures, HISTORY_SEASONS, repoRoot, writeEmulatorImport } from './generate.mjs';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { COMP, NAMESPACE, roster } from './roster.mjs';

const source = JSON.parse(readFileSync(resolve(repoRoot, 'demo/fixtures-2026.json')));
const anchor = '2026-11-10T09:00:00Z';
const now = Date.parse(anchor);
const { database: db, users, manifest } = buildDemo(source, { anchor });
const games = db.DAUCompsGames[COMP];

test('all 20 fictional identities are bidirectionally linked with unique claims', () => {
  assert.equal(users.length, 20);
  assert.equal(Object.keys(db.AuthIndex).length, 20);
  assert.equal(Object.keys(db.AliasIndex).length, 20);
  assert.equal(Object.keys(db.LogonIndex).length, 20);
  for (const user of users) {
    const key = db.AuthIndex[user.uid];
    const record = db.TipperPrivate[key];
    assert.equal(record.authuid, user.uid);
    assert.equal(record.email, user.email);
    assert.match(user.email, /@demo\.example\.test$/);
    assert.equal(db.LogonIndex[logonKey(user.email)], key);
    assert.equal(db.AliasIndex[aliasKey(user.displayName)], key);
    assert.deepEqual(Object.keys(db.AllTippers[key]).sort(), user.photoURL ? ['compsParticipatedIn', 'name', 'photoURL'] : ['compsParticipatedIn', 'name']);
    assert.equal(record.tipperRole, 'tipper');
    assert.equal(user.emailVerified, true);
    assert.equal(user.password, undefined);
  }
});

test('each game resolves to exactly one round and two existing teams', () => {
  const rounds = db.AllDAUComps[COMP].combinedRounds2;
  assert.equal(rounds.length, 12);
  for (const [key, game] of Object.entries(games)) {
    assert.equal(Date.parse(game.DateUtc), game.DateUtcEpochMs);
    assert.equal(rounds.filter(r => game.DateUtcEpochMs >= Date.parse(r.roundStartDate) && game.DateUtcEpochMs <= Date.parse(r.roundEndDate)).length, 1, key);
    assert.ok(db.Teams[`${game.League}-${game.HomeTeam}`]);
    assert.ok(db.Teams[`${game.League}-${game.AwayTeam}`]);
    assert.equal(key, `${game.League}-${String(game.RoundNumber).padStart(2, '0')}-${String(game.MatchNumber).padStart(3, '0')}`);
    for (const team of [game.HomeTeam, game.AwayTeam]) assert.ok(existsSync(resolve(repoRoot, db.Teams[`${game.League}-${team}`].logoURI)));
  }
  for (const round of rounds.slice(0, 7)) assert.ok(Date.parse(round.roundEndDate) + 6 * 3600000 < now);
  assert.ok(Date.parse(rounds[7].roundStartDate) < now && Date.parse(rounds[7].roundEndDate) > now);
  for (const round of rounds.slice(8)) assert.ok(Date.parse(round.roundStartDate) > now);
});

test('completed scores are historical; in-progress/future games have no scores, live or final', () => {
  assert.equal(db.Stats[COMP].live_scores_backend_v1, undefined);
  assert.equal(manifest.counts.live, 2);
  for (const [key, game] of Object.entries(games)) {
    if (game.HomeTeamScore !== undefined) {
      assert.equal(game.HomeTeamScore, source.games[key].HomeTeamScore);
      assert.equal(game.AwayTeamScore, source.games[key].AwayTeamScore);
      assert.ok(game.DateUtcEpochMs < now - 2 * 3600000);
    } else {
      assert.equal(game.AwayTeamScore, undefined);
      assert.ok(game.DateUtcEpochMs > now - 3600000, key);
    }
  }
  assert.ok(manifest.counts.completed > 100);
  assert.ok(manifest.counts.future > 50);
});

test('tips precede kickoff and generation time, with future gaps for the screenshot account', () => {
  for (const tips of Object.values(db.AllTips[COMP])) {
    assert.ok(Object.keys(tips).length > 80);
    for (const [key, tip] of Object.entries(tips)) {
      assert.ok(games[key]);
      assert.match(tip.r, /^[abcde]$/);
      assert.ok(tip.t * 1000 < games[key].DateUtcEpochMs);
      assert.ok(tip.t * 1000 <= now);
    }
  }
  const future = Object.entries(games).filter(([, g]) => g.DateUtcEpochMs > now);
  assert.ok(future.some(([key]) => db.AllTips[COMP]['demo-daisy'][key]));
  assert.ok(future.some(([key]) => !db.AllTips[COMP]['demo-daisy'][key]));
});

test('re-anchoring moves every kickoff equally without changing identities, results or picks', () => {
  assert.deepEqual(buildDemo(source, { anchor }).database, db);
  const later = buildDemo(source, { anchor: '2026-11-17T09:00:00Z' }).database;
  for (const key of Object.keys(games)) assert.equal(later.DAUCompsGames[COMP][key].DateUtcEpochMs - games[key].DateUtcEpochMs, 7 * 86400000);
  assert.deepEqual(later.AuthIndex, db.AuthIndex);
  for (const [id, tips] of Object.entries(db.AllTips[COMP])) {
    for (const [key, tip] of Object.entries(tips)) assert.equal(later.AllTips[COMP][id][key].r, tip.r);
  }
});

test('the three avatar types have local assets or the genuine initials fallback', () => {
  for (const person of roster) {
    const photo = db.AllTippers[person.tipperId].photoURL;
    if (person.avatar === 'initials') assert.equal(photo, undefined);
    else {
      assert.ok(existsSync(resolve(repoRoot, 'demo', new URL(photo).pathname.slice(1))));
      assert.equal(users.find(u => u.uid === person.uid).photoURL, photo);
    }
  }
  const android = buildDemo(source, { anchor, avatarHost: '10.0.2.2' });
  assert.match(android.database.AllTippers['demo-daisy'].photoURL, /^http:\/\/10\.0\.2\.2:8765\//);
});

test('public-fixture extraction strips unknown fields and all user branches', () => {
  const snapshot = {
    AllDAUComps: { privateKey: { aflFixtureJsonURL: 'https://fixturedownload.com/feed/json/afl-2026', nrlFixtureJsonURL: 'https://fixturedownload.com/feed/json/nrl-2026', combinedRounds2: source.rounds } },
    DAUCompsGames: { privateKey: Object.fromEntries(Object.entries(source.games).map(([k, v]) => [k, { ...v, secret: 'DO-NOT-COPY' }])) },
    Teams: source.teams, AllTippers: { private: { name: 'DO-NOT-COPY' } },
  };
  const extracted = extractFixtures(snapshot);
  assert.equal(JSON.stringify(extracted).includes('DO-NOT-COPY'), false);
  assert.equal(JSON.stringify(extracted).includes('privateKey'), false);
  assert.deepEqual(extracted.games, source.games);
});

test('malformed anchors and remote avatar hosts are refused', () => {
  assert.throws(() => buildDemo(source, { anchor: '2026-11-10' }));
  assert.throws(() => buildDemo(source, { anchor, avatarHost: 'example.com' }));
});

test('past seasons become separate competitions with real results and only Daisy tips', () => {
  const history = JSON.parse(readFileSync(resolve(repoRoot, 'demo/history.json')));
  const { database } = buildDemo(source, { anchor, history });
  const daisy = roster.find(person => person.id === 'daisy');
  for (const season of HISTORY_SEASONS) {
    const compKey = `demo-celebrity-${season}`;
    assert.ok(database.AllDAUComps[compKey].combinedRounds2.length > 0);
    const pastGames = database.DAUCompsGames[compKey];
    assert.ok(Object.keys(pastGames).length > 400, compKey);
    for (const [key, game] of Object.entries(pastGames)) {
      assert.equal(game.HomeTeamScore, history.seasons[season].games[key].HomeTeamScore);
      assert.equal(new Date(game.DateUtcEpochMs).getUTCFullYear(), season);
      assert.ok(database.Teams[`${game.League}-${game.HomeTeam}`], key);
      assert.ok(database.Teams[`${game.League}-${game.AwayTeam}`], key);
    }
    assert.deepEqual(Object.keys(database.AllTips[compKey]), [daisy.tipperId]);
  }
  assert.deepEqual(database.AllTippers[daisy.tipperId].compsParticipatedIn, [COMP]);
  assert.equal(JSON.stringify(history).match(/tipper|email|authuid/i), null);
});

test('the emulator import folder holds the database and matching Auth accounts', () => {
  const directory = mkdtempSync(resolve(tmpdir(), 'demo-import-'));
  writeEmulatorImport(directory, db, users, 'Test-password-123');
  const read = name => JSON.parse(readFileSync(resolve(directory, name), 'utf8'));
  const metadata = read('firebase-export-metadata.json');
  assert.equal(metadata.database.path, 'database_export');
  assert.equal(metadata.auth.path, 'auth_export');
  assert.deepEqual(read(`database_export/${NAMESPACE}.json`), db);
  const accounts = read('auth_export/accounts.json').users;
  assert.equal(accounts.length, roster.length);
  for (const account of accounts) {
    assert.equal(db.AuthIndex[account.localId], roster.find(p => p.uid === account.localId).tipperId);
    assert.equal(account.passwordHash, `fakeHash:salt=${account.salt}:password=Test-password-123`);
    assert.equal(account.providerUserInfo[0].providerId, 'password');
  }
});
