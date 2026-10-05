// Prints the database state the smoke scenarios care about (synthetic data only), for assertions.
import { createRequire } from 'node:module';
import { COMP, DATABASE_URL, PROJECT_ID, UIDS } from './fixture.mjs';

const require = createRequire(new URL('../../functions/', import.meta.url));
const { deleteApp, initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getDatabase } = require('firebase-admin/database');

const app = initializeApp({ projectId: PROJECT_ID, databaseURL: DATABASE_URL }, 'smoke-state');
const db = getDatabase(app);
const val = async (path) => (await db.ref(path).get()).val();
const tippers = (await val('AllTippers')) ?? {};
const tips = (await val(`AllTips/${COMP}`)) ?? {};
const tokens = (await val('AllTippersTokens')) ?? {};

const authUsers = (await getAuth(app).listUsers(100)).users.map((u) => ({ uid: u.uid, email: u.email ?? null, anonymous: u.providerData.length === 0 && !u.email, verified: u.emailVerified }));

const uidName = Object.fromEntries(Object.entries(UIDS).map(([k, v]) => [v, k]));
const out = {
  tippers: Object.fromEntries(
    Object.entries(tippers).map(([id, t]) => [
      id,
      {
        name: t.name,
        role: t.tipperRole,
        authuid: uidName[t.authuid] ? `<${uidName[t.authuid]}>` : t.authuid,
        logon: t.logon ?? null,
        paid: t.compsParticipatedIn ?? null,
        isAnonymous: t.isAnonymous ?? null,
        acctLoggedOnUTC: t.acctLoggedOnUTC ? 'set' : null,
        acctCreatedUTC: t.acctCreatedUTC ? 'set' : null,
        photoURL: t.photoURL ?? null,
        extra: Object.keys(t).filter((k) => !['name', 'tipperRole', 'authuid', 'logon', 'email', 'compsParticipatedIn', 'isAnonymous', 'acctLoggedOnUTC', 'acctCreatedUTC', 'photoURL', 'active', 'tipperID'].includes(k)),
      },
    ]),
  ),
  tips: Object.fromEntries(Object.entries(tips).map(([tid, games]) => [tid, Object.fromEntries(Object.entries(games).map(([g, v]) => [g, v.r ?? v.gameResult]))])),
  tokenTippers: Object.keys(tokens),
  authUsers: authUsers.map((u) => ({ ...u, uid: uidName[u.uid] ? `<${uidName[u.uid]}>` : u.uid })),
};
console.log(JSON.stringify(out, null, 2));
getDatabase(app).goOffline();
await deleteApp(app);
