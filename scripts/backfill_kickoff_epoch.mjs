#!/usr/bin/env node
// Plans and verifies the DateUtcEpochMs backfill (DESIGN-database-rules.md D5, phase 4 M3).
//
// Every game under /DAUCompsGames/{comp}/{game} must carry DateUtcEpochMs: its kickoff as UTC
// milliseconds since the epoch, equal to its DateUtc. The R2 rules compare the clock with that number
// and fail closed when it is missing, so the data has to be complete, in every comp, before they deploy.
//
// This script only READS (an export, or the live database) and PRINTS or WRITES A FILE. It has no way to
// write to the database. To apply a plan, review the patch file and give it to the Firebase CLI with
// triggers suppressed, so the scoring functions do not run once per game:
//
//   firebase database:update / patch.json --project <id> --disable-triggers
//
// Usage:
//   node scripts/backfill_kickoff_epoch.mjs --file test/data/db.json              # report
//   node scripts/backfill_kickoff_epoch.mjs --file db.json --patch-out patch.json # report + patch file
//   node scripts/backfill_kickoff_epoch.mjs --file db.json --verify               # exit 1 unless complete
//   node scripts/backfill_kickoff_epoch.mjs --live --verify                       # same, live (needs ADC)
import { writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { liveReadDatabase, readJsonFile } from "./lib/admin_access.mjs";

const STORED_FORMAT = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?Z$/;

const asObject = (value) => (value && typeof value === "object" && !Array.isArray(value) ? value : {});

/**
 * DateUtc as UTC milliseconds, or null if it is not exactly a stored kickoff. The same rule as
 * kickoffEpochMsFromDateUtc in packages/dau_shared (checked against config/kickoff-vectors.json by both).
 */
export function kickoffEpochMs(value) {
  if (typeof value !== "string") return null;
  const match = STORED_FORMAT.exec(value);
  if (!match) return null;
  const [year, month, day, hour, minute, second] = match.slice(1, 7).map(Number);
  const millis = match[7] ? Number(match[7].padEnd(3, "0")) : 0;
  const ms = Date.UTC(year, month - 1, day, hour, minute, second, millis);
  const date = new Date(ms);
  const unchanged =
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day &&
    date.getUTCHours() === hour &&
    date.getUTCMinutes() === minute &&
    date.getUTCSeconds() === second;
  return unchanged ? ms : null;
}

/**
 * Works out what each game's DateUtcEpochMs should be and compares it with what is there.
 * `complete` is true only when there is at least one game and every game is already right.
 */
export function planKickoffBackfill(db) {
  let games = 0;
  let correct = 0;
  const missing = [];
  const wrong = [];
  const unreadable = [];
  const patch = {};
  for (const [comp, perComp] of Object.entries(asObject(db?.DAUCompsGames))) {
    for (const [gameKey, game] of Object.entries(asObject(perComp))) {
      games += 1;
      const expected = kickoffEpochMs(asObject(game).DateUtc);
      if (expected === null) {
        unreadable.push({ comp, gameKey });
        continue;
      }
      const present = asObject(game).DateUtcEpochMs;
      if (present === undefined) {
        missing.push({ comp, gameKey });
      } else if (present !== expected) {
        wrong.push({ comp, gameKey, present, expected });
      } else {
        correct += 1;
        continue;
      }
      patch[`DAUCompsGames/${comp}/${gameKey}/DateUtcEpochMs`] = expected;
    }
  }
  return {
    games,
    correct,
    missing,
    wrong,
    unreadable,
    patch,
    complete: games > 0 && correct === games,
  };
}

// ------------------------------------------------------------------- CLI

function parseArgs(argv) {
  const args = { flags: new Set(), values: {} };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (["--file", "--patch-out"].includes(a)) args.values[a] = argv[(i += 1)];
    else args.flags.add(a);
  }
  return args;
}

async function loadDatabase(args) {
  if (args.values["--file"]) return readJsonFile(args.values["--file"]);
  if (args.flags.has("--live")) return liveReadDatabase(["DAUCompsGames"]);
  throw new Error("Provide --file <export.json> or --live");
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const plan = planKickoffBackfill(await loadDatabase(args));

  console.log(`games: ${plan.games}`);
  console.log(`correct: ${plan.correct}`);
  console.log(`missing: ${plan.missing.length}`);
  console.log(`wrong: ${plan.wrong.length}`);
  console.log(`unreadable DateUtc (cannot be patched): ${plan.unreadable.length}`);
  for (const game of plan.unreadable.slice(0, 20)) console.log(`  unreadable: ${game.comp}/${game.gameKey}`);

  if (args.values["--patch-out"]) {
    writeFileSync(args.values["--patch-out"], `${JSON.stringify(plan.patch, null, 2)}\n`);
    console.log(`patch: ${Object.keys(plan.patch).length} paths written to ${args.values["--patch-out"]}`);
  }

  if (args.flags.has("--verify")) {
    console.log(plan.complete ? "complete: every game has the right DateUtcEpochMs" : "NOT complete");
    process.exitCode = plan.complete ? 0 : 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
