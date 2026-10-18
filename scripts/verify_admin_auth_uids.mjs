#!/usr/bin/env node
// READ-ONLY. Independently verifies the admin allowlist for the temporary R1
// rules (DESIGN-database-rules.md, "Admin allowlist").
//
// The database's own `authuid` field cannot be trusted for this: it is the very
// thing the allowlist protects. So each admin record's `authuid` is checked
// against Firebase Auth (the authority) and printed for a human to confirm.
//
// Two ways to run it (nothing is ever written anywhere):
//
//  A. OFFLINE, using the Firebase CLI you are already logged into (no extra credentials):
//       firebase database:get /AllTippers --project dau-footy-tipping-f8a42 -o test/data/tippers.json
//       firebase auth:export test/data/auth-export.json --project dau-footy-tipping-f8a42
//       node scripts/verify_admin_auth_uids.mjs --db-file test/data/tippers.json --auth-export test/data/auth-export.json
//     The Auth export contains PASSWORD HASHES: keep it under test/data/ (git-ignored) and
//     delete it afterwards. The script refuses an export that sits in the repo unignored.
//
//  B. LIVE, using Application Default Credentials:
//       gcloud auth application-default login
//       node scripts/verify_admin_auth_uids.mjs
//
//   --json   machine-readable output
//
// Output per admin record: whether the uid exists in Firebase Auth, its provider(s), whether
// the Auth email matches the record's logon/email and is verified, and whether the uid is
// shared. Review the table, then record the confirmed uids in config/admin-auth-uids.json.
import { realpathSync } from "node:fs";
import { pathToFileURL } from "node:url";
import {
  assertSafeSensitiveInput,
  authLookupFromExport,
  liveAuthLookup,
  liveReadDatabase,
  normaliseEmail,
  readJsonFile,
  tippersFromExport,
} from "./lib/admin_access.mjs";

// 28 alphanumeric characters is only the format Firebase GENERATES; any UID of 1 to 128
// characters is valid, so Auth is always asked and the shape is informational.
const UID_SHAPE = /^[A-Za-z0-9]{28}$/;
const isPlausibleUid = (value) => typeof value === "string" && value.length >= 1 && value.length <= 128;

/**
 * @param {object} tippers   the AllTippers map
 * @param {{getUser(uid):Promise<object|null>}} auth
 */
export async function verifyAdmins(tippers, auth) {
  const adminRecords = Object.entries(tippers).filter(([, t]) => t?.tipperRole === "admin");
  const rows = [];
  for (const [tipperId, record] of adminRecords) {
    const row = {
      tipperId,
      name: record.name ?? "",
      authuid: record.authuid ?? "",
      defaultUidShape: UID_SHAPE.test(record.authuid ?? ""),
      existsInAuth: false,
      authEmail: "",
      emailVerified: false,
      providers: [],
      emailMatchesRecord: false,
      sharedWithOtherRecord: Object.values(tippers).filter((t) => t?.authuid === record.authuid).length > 1,
      verdict: "NOT VERIFIED",
    };
    if (isPlausibleUid(record.authuid)) {
      try {
        const user = await auth.getUser(record.authuid);
        if (user) {
          row.existsInAuth = true;
          row.authEmail = user.email ?? "";
          row.emailVerified = Boolean(user.emailVerified);
          row.providers = (user.providerData ?? []).map((p) => p.providerId);
          const authEmail = normaliseEmail(user.email);
          row.emailMatchesRecord =
            authEmail !== "" && (authEmail === normaliseEmail(record.logon) || authEmail === normaliseEmail(record.email));
        } else {
          row.authError = "auth/user-not-found";
        }
      } catch (error) {
        row.authError = error.code ?? String(error);
      }
    }
    if (row.existsInAuth && row.emailMatchesRecord && row.emailVerified && !row.sharedWithOtherRecord) {
      row.verdict = "OK (confirm this is the right person)";
    } else if (row.existsInAuth) {
      row.verdict = "REVIEW: exists in Auth but email/verification/uniqueness check failed";
    }
    rows.push(row);
  }
  return rows;
}

function parseArgs(argv) {
  const args = { flags: new Set(), values: {} };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (["--db-file", "--auth-export"].includes(a)) args.values[a] = argv[(i += 1)];
    else args.flags.add(a);
  }
  return args;
}

export function formatRows(rows) {
  const lines = [`Admin records found in /AllTippers: ${rows.length}\n`];
  for (const row of rows) {
    lines.push(
      `- ${row.name || row.tipperId}`,
      `    uid           : ${row.authuid}  (generated 28-char format: ${row.defaultUidShape})`,
      `    in Auth       : ${row.existsInAuth}${row.authError ? ` (${row.authError})` : ""}`,
      `    Auth email    : ${row.authEmail || "-"}  verified: ${row.emailVerified}`,
      `    providers     : ${row.providers.join(", ") || "-"}`,
      `    email matches : ${row.emailMatchesRecord}`,
      `    shared uid    : ${row.sharedWithOtherRecord}`,
      `    verdict       : ${row.verdict}\n`,
    );
  }
  return lines.join("\n");
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  let tippers;
  if (args.values["--db-file"]) {
    tippers = tippersFromExport(readJsonFile(args.values["--db-file"]));
  } else {
    tippers = (await liveReadDatabase(["AllTippers"])).AllTippers ?? {};
  }

  let auth;
  if (args.values["--auth-export"]) {
    assertSafeSensitiveInput(args.values["--auth-export"]);
    auth = authLookupFromExport(readJsonFile(args.values["--auth-export"]));
    if (auth.size === 0) throw new Error("The Auth export contains no users; is it a `firebase auth:export` JSON file?");
  } else {
    auth = await liveAuthLookup();
  }

  const rows = await verifyAdmins(tippers, auth);
  console.log(args.flags.has("--json") ? JSON.stringify(rows, null, 2) : formatRows(rows));
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
