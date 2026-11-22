#!/usr/bin/env node
// Reduces a `firebase auth:export` file to the three fields the identity backfill needs: uid, email and
// emailVerified (DESIGN-database-rules-phase4.md, M4a). The planner refuses a file that still carries
// password hashes, so they never reach it.
//
//   node scripts/slim_auth_export.mjs <full-export.json> <accounts.json> [--delete-input]
//
// `firebase auth:export` always includes password hashes, so the full export is sensitive: this script reads
// it once, writes only the three fields, and with --delete-input removes the full export straight away.
// The full export must be outside the repository or git-ignored; so must the output (it holds email addresses).
import { execFileSync } from "node:child_process";
import { readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { assertSafeSensitiveInput } from "./lib/admin_access.mjs";

const repoRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));

/** { users: [{ uid, email?, emailVerified }] }, sorted by uid, with nothing else from the export. */
export function slimAuthExport(exported) {
  const users = Array.isArray(exported?.users) ? exported.users : [];
  const slim = [];
  for (const raw of users) {
    const uid = raw?.localId ?? raw?.uid;
    if (typeof uid !== "string" || uid === "") continue;
    const entry = { uid };
    if (typeof raw.email === "string" && raw.email !== "") entry.email = raw.email;
    entry.emailVerified = raw.emailVerified === true;
    slim.push(entry);
  }
  slim.sort((a, b) => (a.uid < b.uid ? -1 : a.uid > b.uid ? 1 : 0));
  return { users: slim };
}

function assertOutputSafe(path) {
  const absolute = resolve(path);
  if (relative(repoRoot, absolute).startsWith("..")) return;
  try {
    execFileSync("git", ["check-ignore", "-q", absolute], { cwd: repoRoot, stdio: "ignore" });
  } catch {
    throw new Error(`${path} is inside the repository and not git-ignored, and it holds email addresses. Use a path under /test/data/ or outside the repository.`);
  }
}

function main(argv) {
  const deleteInput = argv.includes("--delete-input");
  const [input, output] = argv.filter((arg) => !arg.startsWith("--"));
  if (!input || !output) {
    throw new Error("Usage: node scripts/slim_auth_export.mjs <full-export.json> <accounts.json> [--delete-input]");
  }
  assertSafeSensitiveInput(input);
  assertOutputSafe(output);
  const slim = slimAuthExport(JSON.parse(readFileSync(input, "utf8")));
  if (slim.users.length === 0) throw new Error("The export contains no users; is it a `firebase auth:export` JSON file?");
  writeFileSync(output, `${JSON.stringify(slim, null, 2)}\n`, { mode: 0o600 });
  if (deleteInput) rmSync(input, { force: true });
  console.log(`Wrote ${slim.users.length} accounts to ${output}${deleteInput ? ` and deleted ${input}` : ""}.`);
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
  try {
    main(process.argv.slice(2));
  } catch (error) {
    console.error(`ERROR: ${error.message}`);
    process.exit(1);
  }
}
