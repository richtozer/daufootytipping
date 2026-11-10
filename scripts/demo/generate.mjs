#!/usr/bin/env node
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync, chmodSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';
import { COMP, NAMESPACE, roster } from './roster.mjs';

export const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const hour = 3600000;
const iso = value => new Date(value).toISOString();
const millis = value => Date.parse(value.replace(' ', 'T'));
export const aliasKey = value => value.replace(/[^\p{L}\p{N}]/gu, '').toLowerCase();
export const logonKey = value => createHash('sha256').update(value.trim().toLowerCase()).digest('base64url');
const random = key => createHash('sha256').update(key).digest().readUInt32BE() / 4294967296;

// Deliberate allowlist: never spread an export's records into the public fixture.
export function extractFixtures(snapshot) {
  const matches = Object.entries(snapshot.AllDAUComps ?? {}).filter(([, c]) =>
    c.aflFixtureJsonURL?.endsWith('afl-2026') && c.nrlFixtureJsonURL?.endsWith('nrl-2026'));
  if (matches.length !== 1) throw new Error('Expected exactly one 2026 competition');
  const [sourceCompKey, comp] = matches[0];
  const rounds = comp.combinedRounds2.slice(0, 12).map(r => ({
    roundStartDate: r.roundStartDate, roundEndDate: r.roundEndDate,
  }));
  const teams = {};
  const games = {};
  for (const [key, g] of Object.entries(snapshot.DAUCompsGames[sourceCompKey])) {
    const time = millis(g.DateUtc);
    const round = rounds.findIndex(r => time >= millis(r.roundStartDate) && time <= millis(r.roundEndDate));
    if (round < 0) continue;
    const league = key.slice(0, 3);
    const names = [g.HomeTeam, g.AwayTeam].map(name => {
      const teamKey = Object.keys(snapshot.Teams).find(k => k.toLowerCase() === `${league}-${name}`.toLowerCase());
      if (!teamKey) throw new Error(`Missing team ${league}-${name}`);
      const t = snapshot.Teams[teamKey];
      teams[teamKey] = { name: t.name, league, logoURI: t.logoURI };
      return teamKey.slice(4);
    });
    if (![g.HomeTeamScore, g.AwayTeamScore].every(Number.isInteger)) throw new Error(`Missing 2026 result: ${key}`);
    games[key] = {
      HomeTeam: names[0], AwayTeam: names[1], Location: g.Location,
      DateUtc: g.DateUtc, RoundNumber: g.RoundNumber, MatchNumber: g.MatchNumber,
      HomeTeamScore: g.HomeTeamScore, AwayTeamScore: g.AwayTeamScore,
    };
  }
  return {
    provenance: 'Public 2026 fixtures/results extracted from local end-of-season export; no user data.',
    sourceUrls: ['https://fixturedownload.com/feed/json/afl-2026', 'https://fixturedownload.com/feed/json/nrl-2026'],
    rounds, teams, games,
  };
}

export const HISTORY_SEASONS = [2022, 2023, 2024, 2025];

// Past seasons' public fixtures and results, so the app's head-to-head history
// (which reads every competition's games) has real matchups. Same allowlist
// rule as extractFixtures: only fixture fields, never tipper or comp records.
export function extractHistory(snapshot) {
  const seasons = {};
  const teams = {};
  for (const season of HISTORY_SEASONS) {
    const matches = Object.entries(snapshot.AllDAUComps ?? {}).filter(([, c]) =>
      c.aflFixtureJsonURL?.endsWith(`afl-${season}`) && c.nrlFixtureJsonURL?.endsWith(`nrl-${season}`));
    if (matches.length !== 1) throw new Error(`Expected exactly one ${season} competition`);
    const [compKey, comp] = matches[0];
    const games = {};
    for (const [key, g] of Object.entries(snapshot.DAUCompsGames?.[compKey] ?? {})) {
      if (![g.HomeTeamScore, g.AwayTeamScore].every(Number.isInteger)) continue;
      const league = key.slice(0, 3);
      const names = [g.HomeTeam, g.AwayTeam].map(name => {
        const teamKey = Object.keys(snapshot.Teams).find(k => k.toLowerCase() === `${league}-${name}`.toLowerCase());
        if (!teamKey) throw new Error(`Missing team ${league}-${name}`);
        const t = snapshot.Teams[teamKey];
        teams[teamKey] = { name: t.name, league, logoURI: t.logoURI };
        return teamKey.slice(4);
      });
      games[key] = {
        HomeTeam: names[0], AwayTeam: names[1], Location: g.Location,
        DateUtc: g.DateUtc, RoundNumber: g.RoundNumber, MatchNumber: g.MatchNumber,
        HomeTeamScore: g.HomeTeamScore, AwayTeamScore: g.AwayTeamScore,
      };
    }
    seasons[season] = {
      aflRegularCompEndDateUTC: comp.aflRegularCompEndDateUTC,
      nrlRegularCompEndDateUTC: comp.nrlRegularCompEndDateUTC,
      rounds: comp.combinedRounds2.map(r => ({ roundStartDate: r.roundStartDate, roundEndDate: r.roundEndDate })),
      games,
    };
  }
  return {
    provenance: 'Public 2022-2025 fixtures/results extracted from local export; no user data.',
    teams, seasons,
  };
}

const DAISY_ACCURACY = 0.86;

// The tip that a game's final score makes correct (margins: AFL 31+, NRL 13+).
function resultFor(key, game) {
  const homeMargin = game.HomeTeamScore - game.AwayTeamScore;
  const threshold = key.startsWith('afl') ? 31 : 13;
  return homeMargin >= threshold ? 'a' : homeMargin > 0 ? 'b' : homeMargin === 0 ? 'c' : homeMargin <= -threshold ? 'e' : 'd';
}

// Past seasons as their own competitions, unshifted, so head-to-head history
// shows real results. Only the screenshot account (Daisy) gets past tips, which
// is what lights up the "tipped correctly" shading in her matchup history. The
// tippers' compsParticipatedIn is left alone: these seasons hold no stats.
function addHistory(database, history) {
  Object.assign(database.Teams, structuredClone(history.teams));
  const daisy = roster.find(person => person.id === 'daisy');
  for (const [season, past] of Object.entries(history.seasons)) {
    const compKey = `demo-celebrity-${season}`;
    database.AllDAUComps[compKey] = {
      name: `Celebrity Dream League ${season}`,
      aflFixtureJsonURL: `https://fixturedownload.com/feed/json/afl-${season}`,
      nrlFixtureJsonURL: `https://fixturedownload.com/feed/json/nrl-${season}`,
      aflRegularCompEndDateUTC: past.aflRegularCompEndDateUTC,
      nrlRegularCompEndDateUTC: past.nrlRegularCompEndDateUTC,
      combinedRounds2: past.rounds,
    };
    const games = {};
    const tips = {};
    for (const [key, raw] of Object.entries(past.games)) {
      const kickoff = millis(raw.DateUtc);
      games[key] = { League: key.slice(0, 3), ...raw, DateUtcEpochMs: kickoff };
      const pick = random(`${daisy.id}/${season}/${key}/pick`) < DAISY_ACCURACY
        ? resultFor(key, raw)
        : ['a', 'b', 'd', 'e'][Math.floor(random(`${season}/${key}/${daisy.id}/other`) * 4)];
      tips[key] = { r: pick, t: Math.floor((kickoff - 10 * hour) / 1000) };
    }
    database.DAUCompsGames[compKey] = games;
    database.AllTips[compKey] = { [daisy.tipperId]: tips };
  }
}

export function buildDemo(source, { anchor = new Date().toISOString(), avatarHost = 'localhost', history } = {}) {
  const now = Date.parse(anchor);
  if (!Number.isFinite(now) || !/(Z|[+-]\d{2}:\d{2})$/.test(anchor)) throw new Error('Anchor needs an ISO timestamp with timezone');
  if (!/^(localhost|127\.0\.0\.1|10\.0\.2\.2)$/.test(avatarHost)) throw new Error('Use a local simulator avatar host');
  const shift = now - 48 * hour - millis(source.rounds[7].roundStartDate);
  const games = {};
  const roundKeys = source.rounds.map(r => Object.entries(source.games)
    .filter(([, g]) => millis(g.DateUtc) >= millis(r.roundStartDate) && millis(g.DateUtc) <= millis(r.roundEndDate))
    .sort((a, b) => millis(a[1].DateUtc) - millis(b[1].DateUtc)).map(([key]) => key));
  if (roundKeys.length !== 12 || roundKeys.some(keys => keys.length === 0)) throw new Error('Expected twelve populated combined rounds');
  const states = {};
  for (const [r, keys] of roundKeys.entries()) {
    for (const league of ['afl', 'nrl']) {
      const leagueKeys = keys.filter(key => key.startsWith(league));
      for (const [i, key] of leagueKeys.entries()) {
        const raw = source.games[key];
        let kickoff = millis(raw.DateUtc) + shift;
        if (r === 7) kickoff = now + (i < 2 ? [-28, -6][i] : i === 2 ? -0.5 : 2 + (i - 3) * 5) * hour;
        const state = r < 7 || (r === 7 && i < 2) ? 'completed' : r === 7 && i === 2 ? 'live' : 'future';
        states[key] = state;
        games[key] = {
          League: league, HomeTeam: raw.HomeTeam, AwayTeam: raw.AwayTeam, Location: raw.Location,
          MatchNumber: raw.MatchNumber, RoundNumber: raw.RoundNumber,
          DateUtc: iso(kickoff), DateUtcEpochMs: kickoff,
          ...(state === 'completed' ? { HomeTeamScore: raw.HomeTeamScore, AwayTeamScore: raw.AwayTeamScore } : {}),
        };
      }
    }
  }
  const rounds = roundKeys.map(keys => ({
    roundStartDate: iso(Math.min(...keys.map(k => games[k].DateUtcEpochMs))),
    roundEndDate: iso(Math.max(...keys.map(k => games[k].DateUtcEpochMs))),
  }));
  const end = iso(Math.max(...Object.values(games).map(g => g.DateUtcEpochMs)) + 24 * hour);
  const database = {
    AppConfig: { currentDAUComp: COMP, createLinkedTipper: true, minAppVersion: '1.4.0' },
    ServerConfig: { identity: { mode: 'final' }, liveScores: { mode: 'active' } },
    AllDAUComps: { [COMP]: {
      name: 'Celebrity Dream League',
      aflFixtureJsonURL: 'http://127.0.0.1:8765/fixtures/afl-2026.json',
      nrlFixtureJsonURL: 'http://127.0.0.1:8765/fixtures/nrl-2026.json',
      lastFixtureUTC: iso(now), aflRegularCompEndDateUTC: end, nrlRegularCompEndDateUTC: end,
      combinedRounds2: rounds,
    } },
    Teams: structuredClone(source.teams), DAUCompsGames: { [COMP]: games },
    AllTippers: {}, TipperPrivate: {}, AuthIndex: {}, AliasIndex: {}, LogonIndex: {},
    AllTips: { [COMP]: {} }, Stats: { [COMP]: {} },
  };
  const users = [];
  for (const [index, person] of roster.entries()) {
    const photoURL = person.avatar === 'initials' ? null :
      `http://${avatarHost}:8765/avatars/${person.id}.jpg`;
    database.AllTippers[person.tipperId] = {
      name: person.name, compsParticipatedIn: [COMP], ...(photoURL ? { photoURL } : {}),
    };
    database.TipperPrivate[person.tipperId] = {
      authuid: person.uid, email: person.email, logon: person.email, tipperRole: 'tipper',
      isAnonymous: false, acctCreatedUTC: iso(now - 100 * 24 * hour), acctLoggedOnUTC: iso(now),
    };
    database.AuthIndex[person.uid] = person.tipperId;
    database.AliasIndex[aliasKey(person.name)] = person.tipperId;
    database.LogonIndex[logonKey(person.email)] = person.tipperId;
    users.push({ uid: person.uid, email: person.email, emailVerified: true, displayName: person.name, ...(photoURL ? { photoURL } : {}) });
    const tips = {};
    for (const [r, keys] of roundKeys.entries()) {
      if (r > 8) continue; // Later rounds remain open for development/testing.
      for (const key of keys) {
        const g = games[key];
        const rand = random(`${person.id}/${key}/pick`);
        // The screenshot account (Daisy) has a few upcoming tips still to make.
        const missing = person.id === 'daisy'
          ? states[key] === 'future' && random(key) < 0.35
          : random(`${person.id}/${key}/missing`) < (r >= 7 ? 0.15 : 0.035);
        if (missing) continue;
        // The screenshot account sits near the top of the leaderboard.
        const accuracy = person.id === 'daisy' ? DAISY_ACCURACY : 0.35 + (index % 7) * 0.065;
        const pick = rand < accuracy ? resultFor(key, source.games[key]) : ['a', 'b', 'd', 'e'][Math.floor(random(`${key}/${person.id}/other`) * 4)];
        tips[key] = { r: pick, t: Math.floor(Math.min(now - hour, g.DateUtcEpochMs - (8 + index) * hour) / 1000) };
      }
    }
    database.AllTips[COMP][person.tipperId] = tips;
  }
  if (history) addHistory(database, history);
  return { database, users, manifest: {
    comp: COMP, anchor: iso(now), currentRound: 8, completedRounds: 7, totalRounds: 12,
    sourceSeason: 2026, screenshotAccount: 'daisy@demo.example.test', avatarHost,
    counts: { tippers: roster.length, games: Object.keys(games).length, ...Object.fromEntries(['completed', 'live', 'future'].map(s => [s, Object.values(states).filter(v => v === s).length])) },
    note: 'Fictional accounts and tips. Shifted 2026 fixtures; historical final scores; the two in-progress games have no live scores, so the app shows no live-score warning. Not celebrity endorsements.',
  } };
}

export function generate({ anchor, avatarHost, output = resolve(repoRoot, 'emulator/demo') } = {}) {
  const source = JSON.parse(readFileSync(resolve(repoRoot, 'demo/fixtures-2026.json'), 'utf8'));
  const history = JSON.parse(readFileSync(resolve(repoRoot, 'demo/history.json'), 'utf8'));
  const result = buildDemo(source, { anchor, avatarHost, history });
  mkdirSync(resolve(output, 'fixtures'), { recursive: true });
  const write = (name, value) => writeFileSync(resolve(output, name), `${JSON.stringify(value, null, 2)}\n`);
  write('competition.json', result.database);
  write('auth-users.json', result.users);
  write('manifest.json', result.manifest);
  for (const league of ['afl', 'nrl']) write(`fixtures/${league}-2026.json`, Object.values(result.database.DAUCompsGames[COMP]).filter(g => g.League === league));
  execFileSync('dart', ['run', 'bin/demo_stats.dart', resolve(output, 'competition.json'), result.manifest.anchor], {
    cwd: resolve(repoRoot, 'functions_dart'), stdio: 'inherit',
  });
  const database = JSON.parse(readFileSync(resolve(output, 'competition.json'), 'utf8'));
  writeEmulatorImport(resolve(output, 'export'), database, result.users, demoPassword());
  console.log(`Demo generated: ${output}\n${JSON.stringify(result.manifest.counts)}`);
  return result;
}

// The shared demo password lives only in the gitignored emulator/ directory.
// It is reused across runs so a signed-in simulator stays signed in.
export function demoPassword() {
  const credentialsPath = resolve(repoRoot, 'emulator/demo/credentials.json');
  execFileSync('git', ['check-ignore', '-q', credentialsPath], { cwd: repoRoot });
  const tracked = execFileSync('git', ['ls-files', '--', credentialsPath], { cwd: repoRoot, encoding: 'utf8' });
  if (tracked.trim()) throw new Error('Credentials file must not be tracked');
  const credentials = existsSync(credentialsPath)
    ? JSON.parse(readFileSync(credentialsPath, 'utf8'))
    : { password: `Demo-${randomBytes(12).toString('base64url')}`, screenshotAccount: 'daisy@demo.example.test' };
  if (typeof credentials.password !== 'string' || credentials.password.length < 12) throw new Error('Invalid local demo credentials');
  writeFileSync(credentialsPath, `${JSON.stringify(credentials, null, 2)}\n`, { mode: 0o600 });
  chmodSync(credentialsPath, 0o600);
  return credentials.password;
}

// An emulator export folder for `firebase emulators:start --import`. Imported
// data is in place before the Functions emulator registers its triggers, so
// loading fires none (a bulk write after startup fires one or two per tip).
// Auth accounts use the emulator's plain "fakeHash" password format.
export function writeEmulatorImport(directory, database, users, password) {
  rmSync(directory, { recursive: true, force: true });
  mkdirSync(resolve(directory, 'database_export'), { recursive: true });
  mkdirSync(resolve(directory, 'auth_export'), { recursive: true });
  const write = (name, value) => writeFileSync(resolve(directory, name), `${JSON.stringify(value, null, 2)}\n`);
  write('firebase-export-metadata.json', {
    version: '15.18.0',
    database: { version: '4.11.2', path: 'database_export' },
    auth: { version: '15.18.0', path: 'auth_export' },
  });
  write(`database_export/${NAMESPACE}.json`, database);
  const createdAt = String(Date.parse('2026-01-01T00:00:00Z'));
  write('auth_export/accounts.json', {
    kind: 'identitytoolkit#DownloadAccountResponse',
    users: users.map(user => {
      const salt = `fakeSalt${createHash('sha256').update(user.uid).digest('hex').slice(0, 20)}`;
      return {
        localId: user.uid, email: user.email, emailVerified: true, displayName: user.displayName,
        ...(user.photoURL ? { photoUrl: user.photoURL } : {}),
        passwordHash: `fakeHash:salt=${salt}:password=${password}`, salt,
        passwordUpdatedAt: Number(createdAt), validSince: createdAt.slice(0, -3),
        createdAt, lastLoginAt: createdAt,
        providerUserInfo: [{
          providerId: 'password', email: user.email, federatedId: user.email, rawId: user.email,
          displayName: user.displayName, ...(user.photoURL ? { photoUrl: user.photoURL } : {}),
        }],
      };
    }),
  });
  write('auth_export/config.json', { signIn: { allowDuplicateEmails: false } });
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const args = process.argv.slice(2);
  if (args[0] === '--extract-source') {
    const snapshot = JSON.parse(readFileSync(args[1], 'utf8'));
    writeFileSync(resolve(repoRoot, 'demo/fixtures-2026.json'), `${JSON.stringify(extractFixtures(snapshot), null, 2)}\n`);
    writeFileSync(resolve(repoRoot, 'demo/history.json'), `${JSON.stringify(extractHistory(snapshot), null, 2)}\n`);
  } else {
    const options = {};
    for (let i = 0; i < args.length; i += 2) {
      const key = { '--anchor': 'anchor', '--avatar-host': 'avatarHost', '--output': 'output' }[args[i]];
      if (!key || !args[i + 1]) throw new Error('Usage: generate.mjs [--anchor ISO] [--avatar-host localhost|10.0.2.2] [--output DIR]');
      options[key] = args[i + 1];
    }
    generate(options);
  }
}
