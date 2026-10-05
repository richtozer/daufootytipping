async page => {
  // The same Firebase JS SDK version the app uses (the one served locally), never a hard-coded one.
  const sdkVersion = (await (await page.request.get('http://127.0.0.1:18091/package.json')).json()).version;
  return JSON.stringify(await page.evaluate(async (sdkVersion) => {
    const base = 'https://www.gstatic.com/firebasejs/' + sdkVersion + '/';
    const [appM, authM, dbM] = await Promise.all([import(base + 'firebase-app.js'), import(base + 'firebase-auth.js'), import(base + 'firebase-database.js')]);
    const out = {};
    const run = async (label, who, tries) => {
      const app = appM.initializeApp({ apiKey: 'demo', projectId: 'demo-dau-rules', databaseURL: 'https://demo-dau-rules-default-rtdb.firebaseio.com' }, 'mc-' + label);
      const auth = authM.getAuth(app);
      authM.connectAuthEmulator(auth, 'http://127.0.0.1:8099', { disableWarnings: true });
      if (who === 'alice') await authM.signInWithEmailAndPassword(auth, 'alice@smoke.example.test', 'Smoke-test-pw-1');
      if (who === 'anonymous') await authM.signInAnonymously(auth);
      const db = dbM.getDatabase(app);
      dbM.connectDatabaseEmulator(db, '127.0.0.1', 8000);
      out[label] = {};
      for (const [name, path, value] of tries) {
        try { await Promise.race([dbM.set(dbM.ref(db, path), value), new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), 5000))]); out[label][name] = 'ALLOWED'; }
        catch (e) { out[label][name] = /permission_denied|PERMISSION_DENIED/i.test(e.message) ? 'DENIED' : 'ERROR ' + e.message.slice(0, 60); }
      }
    };
    const now = Math.floor(Date.now() / 1000);
    await run('normal user (alice)', 'alice', [
      ['A1 rewrite AppConfig/minAppVersion', 'AppConfig/minAppVersion', '9.9.9'],
      ['A2 self-promote tipperRole to admin', 'AllTippers/tAlice/tipperRole', 'admin'],
      ['A3 overwrite another uid into authuid', 'AllTippers/tAlice/authuid', 'SMOKEadmin000000000000000000'],
      ['A4 mark self paid (compsParticipatedIn)', 'AllTippers/tAlice/compsParticipatedIn', ['compSMOKE26']],
      ['A5 create a record with role admin', 'AllTippers/evil1', { authuid: 'x', tipperRole: 'admin', name: 'evil' }],
      ['A6 edit fixtures (game score)', 'DAUCompsGames/compSMOKE26/nrl-01-001/HomeTeamScore', 99],
      ['A7 edit a team', 'Teams/afl-Carlton/name', 'x'],
      ['A8 legacy 1.3.x stats writer (game_stats_v3)', 'Stats/compSMOKE26/game_stats_v3/x', 1],
      ['A9 forge backend scoring status', 'Stats/compSMOKE26/scoring_status', { state: 'forged' }],
      ['A10 wipe every device token', 'AllTippersTokens', null],
      ['A11 write a malformed tip', 'AllTips/compSMOKE26/tAlice/nrl-01-002', { r: 'q' }],
      ['C1 control: valid own tip', 'AllTips/compSMOKE26/tAlice/nrl-01-002', { r: 'b', t: now }],
      ['C2 control: own profile name', 'AllTippers/tAlice/name', 'Alice Smoke'],
      ['K1 KNOWN R1 CONCESSION: edit ANOTHER tipper logon', 'AllTippers/tBob/logon', 'bob@smoke.example.test'],
    ]);
    await run('anonymous user', 'anonymous', [
      ['N1 create a tipper record', 'AllTippers/anon1', { authuid: 'a', tipperRole: 'tipper', name: 'anon' }],
      ['N2 write a tip', 'AllTips/compSMOKE26/tAlice/nrl-01-001', { r: 'a', t: now }],
      ['N3 edit own-looking profile leaf', 'AllTippers/tAlice/name', 'hijack'],
    ]);
    await run('unauthenticated visitor', 'none', [
      ['U1 rewrite AppConfig', 'AppConfig/minAppVersion', '9.9.9'],
      ['U2 write a tip', 'AllTips/compSMOKE26/tAlice/nrl-01-001', { r: 'a', t: now }],
    ]);
    return out;
  }, sdkVersion));
}
