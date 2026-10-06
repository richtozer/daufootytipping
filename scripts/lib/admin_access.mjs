// Shared access helpers for the read-only audit scripts.
//
// Two ways to get data in, so nobody is blocked on Google Application Default
// Credentials:
//   1. OFFLINE (no credentials in the script): feed it exports made with the
//      Firebase CLI you are already logged into
//        firebase database:get / --project dau-footy-tipping-f8a42 -o <file>
//        firebase auth:export <file>.json --project dau-footy-tipping-f8a42
//   2. LIVE: Application Default Credentials (`gcloud auth application-default login`).
//
// A Firebase Auth export contains PASSWORD HASHES. These helpers therefore refuse
// to read one that sits inside the repository unless git ignores it.
import { execFileSync } from "node:child_process";
import { readFileSync, realpathSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const PRODUCTION_PROJECT_ID = "dau-footy-tipping-f8a42";

// Tests point the scripts at a demo- project through this override. It is deliberately the only
// way to change the project, and assertProjectMatchesMode() keeps it from being mixed up.
export const PROJECT_ID = process.env.ADMIN_SCRIPTS_PROJECT_ID ?? PRODUCTION_PROJECT_ID;
export const DATABASE_URL = `https://${PROJECT_ID}-default-rtdb.asia-southeast1.firebasedatabase.app`;

const usingEmulator = () =>
  Boolean(process.env.FIREBASE_AUTH_EMULATOR_HOST || process.env.FIREBASE_DATABASE_EMULATOR_HOST);

/**
 * Emulator mode requires a demo- project; live mode refuses one. This makes it impossible for an
 * emulator test to name the production project, or for a real run to be silently pointed at a
 * fixture project.
 */
export function assertProjectMatchesMode() {
  const demo = PROJECT_ID.startsWith("demo-");
  if (usingEmulator() && !demo) {
    throw new Error(
      `Refusing to run: the Firebase emulators are configured but the project is "${PROJECT_ID}". Emulator runs must use a demo- project (set ADMIN_SCRIPTS_PROJECT_ID=demo-...).`,
    );
  }
  if (!usingEmulator() && demo) {
    throw new Error(`Refusing to run live against the demo project "${PROJECT_ID}" (no emulator is configured).`);
  }
}

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const functionsRequire = createRequire(new URL("../../functions/", import.meta.url));

export function loadAdminSdk() {
  return {
    ...functionsRequire("firebase-admin/app"),
    getAuth: functionsRequire("firebase-admin/auth").getAuth,
    getDatabase: functionsRequire("firebase-admin/database").getDatabase,
  };
}

export const normaliseEmail = (value) => (typeof value === "string" ? value.trim().toLowerCase() : "");

/** Refuse a sensitive input that is inside the repo and not git-ignored. */
export function assertSafeSensitiveInput(path) {
  const absolute = realpathSync(resolve(path));
  const inside = !relative(repoRoot, absolute).startsWith("..");
  if (!inside) return;
  try {
    execFileSync("git", ["check-ignore", "-q", absolute], { cwd: repoRoot, stdio: "ignore" });
  } catch {
    throw new Error(
      `${path} is inside the repository and not git-ignored. A Firebase Auth export contains password hashes: save it under /test/data/ (ignored) or outside the repo, and delete it afterwards.`,
    );
  }
}

/** Build lookups from a `firebase auth:export` JSON file. Hashes are never read. */
export function authLookupFromExport(exported) {
  const users = Array.isArray(exported?.users) ? exported.users : [];
  const byUid = new Map();
  const byEmail = new Map();
  for (const raw of users) {
    const uid = raw.localId ?? raw.uid;
    if (typeof uid !== "string") continue;
    const user = {
      uid,
      email: raw.email ?? "",
      emailVerified: Boolean(raw.emailVerified),
      providerData: (raw.providerUserInfo ?? raw.providerData ?? []).map((p) => ({ providerId: p.providerId })),
    };
    byUid.set(uid, user);
    const key = normaliseEmail(user.email);
    if (key) byEmail.set(key, user);
  }
  return {
    size: byUid.size,
    getUser: async (uid) => byUid.get(uid) ?? null,
    getUserByEmail: async (email) => byEmail.get(normaliseEmail(email)) ?? null,
  };
}

export function readJsonFile(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

/** Accept either a whole-database export or just the AllTippers map. */
export function tippersFromExport(json) {
  if (json && typeof json === "object" && json.AllTippers && typeof json.AllTippers === "object") return json.AllTippers;
  return json && typeof json === "object" ? json : {};
}

const CREDENTIAL_HELP = `No Google credentials were found.

Quickest fix (gcloud is installed):
    gcloud auth application-default login
    gcloud auth application-default set-quota-project ${PROJECT_ID}
then run this script again.

Or use the Firebase CLI you are already logged into and run this script OFFLINE:
    firebase database:get / --project ${PROJECT_ID} -o test/data/db.json
    firebase auth:export test/data/auth-export.json --project ${PROJECT_ID}
(the Auth export contains password hashes: keep it under test/data/ and delete it afterwards)
then pass --file/--db-file and --auth-export.`;

/** Fail fast (and clearly) when live access is requested but no credentials exist. */
export async function ensureCredentials({ timeoutMs = 15000 } = {}) {
  assertProjectMatchesMode();
  if (usingEmulator()) return;
  process.env.METADATA_SERVER_DETECTION ??= "none"; // do not spend minutes probing for a GCE metadata server
  const { GoogleAuth } = functionsRequire("google-auth-library");
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error("timed out looking for credentials")), timeoutMs);
  });
  try {
    await Promise.race([new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/cloud-platform"] }).getClient(), timeout]);
  } catch (error) {
    throw new Error(`${CREDENTIAL_HELP}\n\n(${error.message})`);
  } finally {
    clearTimeout(timer);
  }
}

/** Live Auth lookups through the Admin SDK (needs credentials or the Auth emulator). */
export async function liveAuthLookup() {
  await ensureCredentials();
  const { initializeApp, getApps, getAuth } = loadAdminSdk();
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID, databaseURL: DATABASE_URL });
  const orNull = async (fn) => {
    try {
      return await fn();
    } catch (error) {
      if (error?.code === "auth/user-not-found") return null;
      throw error;
    }
  };
  return {
    getUser: (uid) => orNull(() => getAuth().getUser(uid)),
    getUserByEmail: (email) => orNull(() => getAuth().getUserByEmail(email)),
  };
}

/** Live database reads through the Admin SDK. */
export async function liveReadDatabase(paths) {
  await ensureCredentials();
  const { initializeApp, getApps, getDatabase } = loadAdminSdk();
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID, databaseURL: DATABASE_URL });
  const root = getDatabase().ref();
  const out = {};
  for (const path of paths) out[path] = (await root.child(path).once("value")).val();
  return out;
}
