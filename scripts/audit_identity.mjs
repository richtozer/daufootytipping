#!/usr/bin/env node
// READ-ONLY identity audit (DESIGN-database-rules.md, rollout step 0).
//
// Finds everything that must be understood or fixed by hand BEFORE any server
// code trusts identity data: placeholder `authuid` values, duplicate `authuid`s,
// logon/email conflicts that would make linking ambiguous, alias collisions,
// the admin list, and (optionally) disagreements with Firebase Auth, which is
// the authority (the database `authuid` is the very thing being protected).
//
// Nothing is ever written to the database. Personal data (the exact placeholder
// strings, which are email addresses) is only written to a path you name with
// --placeholders-out, and only if that path is git-ignored.
//
// Usage:
//   Offline, with the Firebase CLI you are already logged into:
//     firebase database:get / --project dau-footy-tipping-f8a42 -o test/data/db.json
//     firebase auth:export test/data/auth-export.json --project dau-footy-tipping-f8a42
//     node scripts/audit_identity.mjs --file test/data/db.json --auth-export test/data/auth-export.json
//   Live (Application Default Credentials):
//     node scripts/audit_identity.mjs --live --auth-check
//   Options:
//     --auth-check              cross-check against Firebase Auth live (needs Application Default
//                               Credentials: `gcloud auth application-default login`)
//     --auth-export <path>      cross-check against a `firebase auth:export <file>.json` instead
//                               (no extra credentials; the export holds PASSWORD HASHES, so it must
//                               be git-ignored or outside the repo, and should be deleted afterwards)
//     --out <path>              write the findings (tipper ids and categories only) as JSON
//     --placeholders-out <path> write { tipperId: exactPlaceholder } for /Placeholders. Requires an Auth
//                               check (shape alone cannot prove a value is not an account).
//                               CONTAINS EMAIL ADDRESSES; refused unless git-ignored.
//     --json                    print the summary as JSON
import { execFileSync } from "node:child_process";
import { readFileSync, realpathSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import {
  assertSafeSensitiveInput,
  authLookupFromExport,
  liveAuthLookup,
  liveReadDatabase,
  readJsonFile,
} from "./lib/admin_access.mjs";

// 28 alphanumeric characters is the format Firebase GENERATES; Firebase accepts any UID of 1 to 128
// characters, so this shape is only ever a provisional hint, never proof of validity or of absence.
const UID_SHAPE = /^[A-Za-z0-9]{28}$/;
const isPlausibleUid = (value) => typeof value === "string" && value.length >= 1 && value.length <= 128;
const ALIAS_MAX = 64;

export const normaliseEmail = (value) => (typeof value === "string" ? value.trim().toLowerCase() : "");

/** Same rule as the client's _normaliseAlias: strip non letters/digits/space, drop spaces, lower-case. */
export function normaliseAlias(value) {
  if (typeof value !== "string") return "";
  return value.replace(/[^\p{L}\p{N}\s]/gu, "").replace(/\s+/g, "").toLowerCase();
}

const asObject = (value) => (value && typeof value === "object" && !Array.isArray(value) ? value : {});
const countChildren = (value) => Object.keys(asObject(value)).length;

function groupBy(entries, keyFn) {
  const groups = new Map();
  for (const entry of entries) {
    const key = keyFn(entry);
    if (key === "" || key == null) continue;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(entry);
  }
  return groups;
}

/**
 * @param {object} db       the database as one object (an export, or a live read)
 * @param {object} [options]
 * @param {{getUser(uid):Promise<object|null>, getUserByEmail(email):Promise<object|null>}} [options.auth]
 *        optional Firebase Auth lookups; each returns { uid, email, emailVerified } or null.
 */
export async function auditIdentity(db, { auth = null } = {}) {
  const tippers = asObject(db.AllTippers);
  const currentComp = db.AppConfig?.currentDAUComp ?? null;
  const tipsByComp = asObject(db.AllTips);
  const currentTips = asObject(tipsByComp[currentComp]);
  const records = Object.entries(tippers).map(([tipperId, t]) => ({ tipperId, ...asObject(t) }));

  // ---- Classify every authuid. Firebase Auth is the authority; string shape is only a
  // provisional fallback when no Auth data is supplied (Firebase accepts UIDs of 1 to 128
  // characters, and 28 alphanumeric characters is merely the common generated format).
  //   missing                  no usable value
  //   in-auth / not-in-auth    decided by Firebase Auth
  //   default-shape-unchecked  looks like a generated UID; NOT verified
  //   non-default-shape-unchecked  does not look like one; a PROVISIONAL placeholder only
  const status = new Map();
  const authUsers = new Map();
  for (const r of records) {
    const uid = r.authuid;
    if (typeof uid !== "string" || uid === "") {
      status.set(r.tipperId, "missing");
    } else if (auth) {
      const user = isPlausibleUid(uid) ? await auth.getUser(uid) : null;
      if (user) authUsers.set(r.tipperId, user);
      status.set(r.tipperId, user ? "in-auth" : "not-in-auth");
    } else {
      status.set(r.tipperId, UID_SHAPE.test(uid) ? "default-shape-unchecked" : "non-default-shape-unchecked");
    }
  }
  const isAccount = (r) => (auth ? status.get(r.tipperId) === "in-auth" : status.get(r.tipperId) === "default-shape-unchecked");
  const isPlaceholder = (r) =>
    auth ? status.get(r.tipperId) === "not-in-auth" : status.get(r.tipperId) === "non-default-shape-unchecked";

  const findings = {
    placeholders: [],
    missingAuthuid: [],
    duplicateAuthuid: [],
    admins: [],
    logonDuplicates: [],
    emailDuplicates: [],
    logonEqualsOtherEmail: [],
    notNormalised: [],
    missingContact: [],
    aliasCollisions: [],
    aliasEmptyOrMissing: [],
    aliasTooLong: [],
    tipsForMissingTipper: [],
    tokensForMissingTipper: [],
    authDisagreements: [],
    backfillCandidates: [],
    nonDefaultShapeButInAuth: [],
  };

  const placeholders = {}; // tipperId -> exact placeholder (PII; only meaningful when confirmed by Auth)

  for (const r of records) {
    const uid = r.authuid;
    const tipsInCurrentComp = countChildren(currentTips[r.tipperId]);
    const base = {
      tipperId: r.tipperId,
      activeCurrentComp: tipsInCurrentComp > 0,
      tipsInCurrentComp,
      hasLogin: Boolean(r.acctLoggedOnUTC),
      role: r.tipperRole ?? null,
    };
    if (status.get(r.tipperId) === "missing") {
      findings.missingAuthuid.push(base);
    } else if (isPlaceholder(r)) {
      placeholders[r.tipperId] = uid;
      findings.placeholders.push({
        ...base,
        confirmedByAuth: auth !== null,
        category: uid.includes("@") ? "email-address" : UID_SHAPE.test(uid) ? "default-shape-not-in-auth" : "non-default-shape",
      });
    }
    if (auth && status.get(r.tipperId) === "in-auth" && !UID_SHAPE.test(uid)) {
      findings.nonDefaultShapeButInAuth.push(base); // must NEVER be overwritten as a placeholder
    }
    if (r.tipperRole === "admin") {
      findings.admins.push({
        ...base,
        defaultUidShape: UID_SHAPE.test(uid ?? ""),
        isAuthAccount: auth ? status.get(r.tipperId) === "in-auth" : null,
        accountOk: isAccount(r),
      });
    }
    if (!r.logon && !r.email) findings.missingContact.push(base);
    if ((r.logon && r.logon !== normaliseEmail(r.logon)) || (r.email && r.email !== normaliseEmail(r.email))) {
      findings.notNormalised.push(base);
    }
    const alias = normaliseAlias(r.name);
    if (typeof r.name !== "string" || alias === "") findings.aliasEmptyOrMissing.push(base);
    if (typeof r.name === "string" && r.name.length > ALIAS_MAX) findings.aliasTooLong.push(base);
  }

  // Duplicate authuid values (accounts and placeholders reported separately).
  for (const [uid, group] of groupBy(records, (r) => r.authuid)) {
    if (group.length < 2) continue;
    findings.duplicateAuthuid.push({
      kind: isAccount(group[0]) ? "real-uid" : "placeholder",
      tipperIds: group.map((r) => r.tipperId),
      tipCounts: group.map((r) => countChildren(currentTips[r.tipperId])),
      sameLogon: new Set(group.map((r) => normaliseEmail(r.logon))).size === 1,
      sameEmail: new Set(group.map((r) => normaliseEmail(r.email))).size === 1,
      anyAdmin: group.some((r) => r.tipperRole === "admin"),
    });
  }

  for (const [, group] of groupBy(records, (r) => normaliseEmail(r.logon))) {
    if (group.length > 1) findings.logonDuplicates.push({ tipperIds: group.map((r) => r.tipperId) });
  }
  for (const [, group] of groupBy(records, (r) => normaliseEmail(r.email))) {
    if (group.length > 1) findings.emailDuplicates.push({ tipperIds: group.map((r) => r.tipperId) });
  }
  // One record's logon equals a different record's email: linking by either would be ambiguous.
  const byEmail = groupBy(records, (r) => normaliseEmail(r.email));
  for (const r of records) {
    const others = (byEmail.get(normaliseEmail(r.logon)) ?? []).filter((o) => o.tipperId !== r.tipperId);
    if (normaliseEmail(r.logon) && others.length > 0) {
      findings.logonEqualsOtherEmail.push({ tipperId: r.tipperId, otherTipperIds: others.map((o) => o.tipperId) });
    }
  }
  for (const [, group] of groupBy(records, (r) => normaliseAlias(r.name))) {
    if (group.length > 1) findings.aliasCollisions.push({ tipperIds: group.map((r) => r.tipperId) });
  }

  for (const [comp, perTipper] of Object.entries(tipsByComp)) {
    for (const tipperId of Object.keys(asObject(perTipper))) {
      if (!(tipperId in tippers)) findings.tipsForMissingTipper.push({ comp, tipperId });
    }
  }
  for (const tipperId of Object.keys(asObject(db.AllTippersTokens))) {
    if (!(tipperId in tippers)) findings.tokensForMissingTipper.push({ tipperId });
  }

  // ---- Firebase Auth cross-check (the authority), when available.
  if (auth) {
    const uidOwner = groupBy(records, (r) => r.authuid);
    for (const r of records) {
      const authUser = authUsers.get(r.tipperId) ?? null;
      const emails = [...new Set([normaliseEmail(r.logon), normaliseEmail(r.email)].filter(Boolean))];

      if (authUser) {
        const authEmail = normaliseEmail(authUser.email);
        if (!authEmail || !emails.includes(authEmail)) {
          findings.authDisagreements.push({ tipperId: r.tipperId, kind: "auth-email-differs-from-record", verified: Boolean(authUser.emailVerified) });
        }
        continue;
      }
      // Not an Auth account (a placeholder, a stale uid, or nothing): look for the Auth
      // user by the record's email(s) to PROPOSE a backfill. This is a proposal for review,
      // never applied automatically.
      const candidates = new Map();
      for (const email of emails) {
        const found = await auth.getUserByEmail(email);
        if (found) candidates.set(found.uid, found);
      }
      if (candidates.size === 1) {
        const [candidate] = candidates.values();
        const ownedByOther = (uidOwner.get(candidate.uid) ?? []).some((o) => o.tipperId !== r.tipperId);
        findings.backfillCandidates.push({
          tipperId: r.tipperId,
          status: status.get(r.tipperId),
          proposedUid: candidate.uid,
          emailVerified: Boolean(candidate.emailVerified),
          alreadyUsedByAnotherRecord: ownedByOther,
        });
      } else if (candidates.size > 1) {
        findings.authDisagreements.push({ tipperId: r.tipperId, kind: "emails-map-to-different-auth-users" });
      } else if (status.get(r.tipperId) === "not-in-auth" && UID_SHAPE.test(r.authuid)) {
        findings.authDisagreements.push({ tipperId: r.tipperId, kind: "uid-not-in-auth-and-no-auth-user-for-email" });
      }
    }
  }

  const realDup = findings.duplicateAuthuid.filter((d) => d.kind === "real-uid");
  const summary = {
    tippers: records.length,
    currentComp,
    activeInCurrentComp: records.filter((r) => countChildren(currentTips[r.tipperId]) > 0).length,
    admins: findings.admins.length,
    adminsWithPlaceholderOrMissingUid: findings.admins.filter((a) => !a.accountOk).length,
    // Without --auth-check this counts PROVISIONAL placeholders by string shape only.
    placeholderAuthuid: findings.placeholders.length,
    placeholderAuthuidActiveCurrentComp: findings.placeholders.filter((p) => p.activeCurrentComp).length,
    missingAuthuid: findings.missingAuthuid.length,
    duplicateAuthuidGroupsRealUid: realDup.length,
    duplicateAuthuidGroupsPlaceholder: findings.duplicateAuthuid.length - realDup.length,
    logonDuplicateGroups: findings.logonDuplicates.length,
    emailDuplicateGroups: findings.emailDuplicates.length,
    logonEqualsOtherRecordsEmail: findings.logonEqualsOtherEmail.length,
    notNormalisedContact: findings.notNormalised.length,
    noContactAtAll: findings.missingContact.length,
    aliasCollisionGroups: findings.aliasCollisions.length,
    aliasEmptyOrMissing: findings.aliasEmptyOrMissing.length,
    aliasLongerThanCap: findings.aliasTooLong.length,
    tipNodesForMissingTipper: findings.tipsForMissingTipper.length,
    tokenNodesForMissingTipper: findings.tokensForMissingTipper.length,
    authChecked: auth !== null,
    ...(auth
      ? {
          placeholderAuthuidConfirmedByAuth: findings.placeholders.length,
          authuidNonDefaultShapeButInAuth: findings.nonDefaultShapeButInAuth.length,
          authDisagreements: findings.authDisagreements.length,
          backfillCandidates: findings.backfillCandidates.length,
          backfillCandidatesAlreadyUsedByAnotherRecord: findings.backfillCandidates.filter((c) => c.alreadyUsedByAnotherRecord).length,
          backfillCandidatesUnverifiedEmail: findings.backfillCandidates.filter((c) => !c.emailVerified).length,
        }
      : {}),
  };

  return { summary, findings, placeholders, placeholdersConfirmedByAuth: auth !== null };
}

/** Games whose DateUtc cannot be converted to epoch ms (readiness for the numeric kickoff backfill). */
export function auditKickoffReadiness(db) {
  const pattern = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}Z$/;
  let games = 0;
  const unparsable = [];
  for (const [comp, perComp] of Object.entries(asObject(db.DAUCompsGames))) {
    for (const [gameKey, game] of Object.entries(asObject(perComp))) {
      games += 1;
      const raw = game?.DateUtc;
      const ms = typeof raw === "string" && pattern.test(raw) ? Date.parse(raw.replace(" ", "T")) : NaN;
      if (Number.isNaN(ms)) unparsable.push({ comp, gameKey });
    }
  }
  return { games, unparsable };
}

// ------------------------------------------------------------------- CLI

function isIgnoredByGit(path) {
  try {
    execFileSync("git", ["check-ignore", "-q", path], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

function parseArgs(argv) {
  const args = { flags: new Set(), values: {} };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (["--file", "--out", "--placeholders-out", "--auth-export"].includes(a)) args.values[a] = argv[(i += 1)];
    else args.flags.add(a);
  }
  return args;
}

async function loadDatabase(args) {
  if (args.values["--file"]) return readJsonFile(args.values["--file"]);
  if (args.flags.has("--live")) {
    return liveReadDatabase(["AllTippers", "AllTippersTokens", "AllTips", "AppConfig", "DAUCompsGames"]);
  }
  throw new Error("Provide --file <export.json> or --live");
}

async function loadAuth(args) {
  if (args.values["--auth-export"]) {
    assertSafeSensitiveInput(args.values["--auth-export"]);
    const lookup = authLookupFromExport(readJsonFile(args.values["--auth-export"]));
    if (lookup.size === 0) throw new Error("The Auth export contains no users; is it a `firebase auth:export` JSON file?");
    return lookup;
  }
  if (args.flags.has("--auth-check")) return liveAuthLookup();
  return null;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const db = await loadDatabase(args);
  const auth = await loadAuth(args);
  const result = await auditIdentity(db, { auth });
  const kickoff = auditKickoffReadiness(db);

  const placeholdersOut = args.values["--placeholders-out"];
  if (placeholdersOut) {
    if (!result.placeholdersConfirmedByAuth) {
      throw new Error(
        "--placeholders-out needs an Auth check (--auth-export or --auth-check): without it the placeholders are only guesses from the shape of the value, and a migration must never overwrite a value that could be a real account.",
      );
    }
    if (!isIgnoredByGit(placeholdersOut)) {
      throw new Error(`${placeholdersOut} is not git-ignored; it contains email addresses. Choose a path under /test/data/ or another ignored location.`);
    }
    writeFileSync(placeholdersOut, `${JSON.stringify(result.placeholders, null, 2)}\n`);
  }
  if (args.values["--out"]) {
    writeFileSync(args.values["--out"], `${JSON.stringify({ summary: result.summary, kickoff, findings: result.findings }, null, 2)}\n`);
  }

  if (args.flags.has("--json")) {
    console.log(JSON.stringify({ summary: result.summary, kickoff: { games: kickoff.games, unparsable: kickoff.unparsable.length } }, null, 2));
    return;
  }
  console.log("Identity audit (read-only)\n");
  for (const [key, value] of Object.entries(result.summary)) console.log(`  ${key.padEnd(48)} ${value}`);
  console.log(`  ${"kickoffGames".padEnd(48)} ${kickoff.games}`);
  console.log(`  ${"kickoffUnparsableDateUtc".padEnd(48)} ${kickoff.unparsable.length}`);
  if (placeholdersOut) console.log(`\nWrote exact placeholders (contains emails) to ${placeholdersOut}`);
  if (args.values["--out"]) console.log(`Wrote findings (ids and categories only) to ${args.values["--out"]}`);
}

function isEntryPoint() {
  if (!process.argv[1]) return false;
  try {
    return import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href;
  } catch {
    return false;
  }
}

if (isEntryPoint()) {
  main().then(
    () => process.exit(0),
    (error) => {
      console.error(`ERROR: ${error.message}`);
      process.exit(1);
    },
  );
}
