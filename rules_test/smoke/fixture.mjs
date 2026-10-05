// Synthetic fixture for the real-client smoke test. No real data, no real UIDs.
// The admin UID below is a FIXTURE; it is the only admin the R1 rules loaded for the smoke know about.
export const PROJECT_ID = 'demo-dau-rules';
export const DATABASE_NAMESPACE = `${PROJECT_ID}-default-rtdb`; // derived from the demo databaseURL in the patched app
export const DATABASE_URL = `https://${DATABASE_NAMESPACE}.firebaseio.com`;
export const COMP = 'compSMOKE26';
export const PASSWORD = 'Smoke-test-pw-1';

const uid = (name) => `SMOKE${name}`.padEnd(28, '0').slice(0, 28);
export const UIDS = {
  admin: uid('admin'),
  alice: uid('alice'),
  bob: uid('bob'),
  legacy: uid('legacy'), // the Auth account of the placeholder-backed tipper
  dupe: uid('dupe'), // a second Auth account for the merge scenario
};

export const USERS = {
  admin: { email: 'admin@smoke.example.test', name: 'Admin Smoke' },
  alice: { email: 'alice@smoke.example.test', name: 'Alice Smoke' },
  bob: { email: 'bob@smoke.example.test', name: 'Bob Smoke' },
  legacy: { email: 'legacy@smoke.example.test', name: 'Legacy Smoke' },
  dupe: { email: 'dupe@smoke.example.test', name: 'Dupe Smoke' },
};

const iso = (d) => d.toISOString().replace('T', ' ').replace(/\.\d+Z$/, 'Z');
const hours = (n) => new Date(Date.now() + n * 3600_000);

export function buildDatabase() {
  const now = Date.now();
  const round = (startH, endH) => ({
    roundStartDate: iso(hours(startH)).replace('Z', ''),
    roundEndDate: iso(hours(endH)).replace('Z', ''),
  });
  const game = (league, n, home, away, kickoffHours, scores) => ({
    [`${league}-01-00${n}`]: {
      HomeTeam: home,
      AwayTeam: away,
      DateUtc: iso(hours(kickoffHours)),
      Location: 'Smoke Park',
      MatchNumber: n,
      RoundNumber: 1,
      ...(scores ? { HomeTeamScore: scores[0], AwayTeamScore: scores[1] } : {}),
    },
  });
  const team = (league, name, logo) => ({ [`${league}-${name}`]: { league, name, logoURI: logo } });

  return {
    AppConfig: { currentDAUComp: COMP, createLinkedTipper: true, minAppVersion: '1.4.0', googleClientId: 'demo-client-id' },
    AllDAUComps: {
      [COMP]: {
        name: 'DAU Smoke Comp 2026',
        aflFixtureJsonURL: 'https://fixtures.example.test/afl.json',
        nrlFixtureJsonURL: 'https://fixtures.example.test/nrl.json',
        aflRegularCompEndDateUTC: new Date(now + 90 * 86400_000).toISOString().replace(/\.\d+Z$/, ''),
        nrlRegularCompEndDateUTC: new Date(now + 90 * 86400_000).toISOString().replace(/\.\d+Z$/, ''),
        lastFixtureUTC: new Date(now).toISOString().replace(/\.\d+Z$/, ''),
        // One round: opened yesterday, closes in a week.
        combinedRounds2: [round(-24, 24 * 7)],
      },
    },
    Teams: {
      ...team('nrl', 'Brisbane Broncos', 'assets/teams/nrl/Brisbane_colours.svg'),
      ...team('nrl', 'Canberra Raiders', 'assets/teams/nrl/Canberra_colours.svg'),
      ...team('nrl', 'Canterbury Bulldogs', 'assets/teams/nrl/Canterbury_colours.svg'),
      ...team('nrl', 'Cronulla Sharks', 'assets/teams/nrl/Cronulla_colours.svg'),
      ...team('afl', 'Carlton', 'assets/teams/afl/blues.svg'),
      ...team('afl', 'Adelaide Crows', 'assets/teams/afl/crows.svg'),
      ...team('afl', 'Essendon', 'assets/teams/afl/bombers.svg'),
      ...team('afl', 'Geelong Cats', 'assets/teams/afl/cats.svg'),
    },
    DAUCompsGames: {
      [COMP]: {
        ...game('nrl', 1, 'Brisbane Broncos', 'Canberra Raiders', 30),
        ...game('nrl', 2, 'Canterbury Bulldogs', 'Cronulla Sharks', 54),
        ...game('afl', 1, 'Carlton', 'Adelaide Crows', 28),
        ...game('afl', 2, 'Essendon', 'Geelong Cats', -3, [88, 70]), // already started
      },
    },
    AllTippers: {
      tAdmin: { name: USERS.admin.name, tipperRole: 'admin', authuid: UIDS.admin, logon: USERS.admin.email, email: USERS.admin.email, isAnonymous: false, compsParticipatedIn: [COMP] },
      tAlice: { name: USERS.alice.name, tipperRole: 'tipper', authuid: UIDS.alice, logon: USERS.alice.email, email: USERS.alice.email, isAnonymous: false, compsParticipatedIn: [COMP] },
      tBob: { name: USERS.bob.name, tipperRole: 'tipper', authuid: UIDS.bob, logon: USERS.bob.email, email: USERS.bob.email, isAnonymous: false, compsParticipatedIn: [COMP] },
      // The placeholder-backed legacy tipper: authuid is an EMAIL ADDRESS, as in the real data.
      tLegacy: { name: USERS.legacy.name, tipperRole: 'tipper', authuid: USERS.legacy.email, logon: USERS.legacy.email, email: USERS.legacy.email, active: true, tipperID: 'legacy-sheet-1' },
    },
    AllTips: {
      [COMP]: {
        tBob: { 'afl-02-002': { r: 'a', t: Math.floor(now / 1000) - 7200 } }, // a tip on the already-started game
      },
    },
    AllTippersTokens: {},
  };
}
