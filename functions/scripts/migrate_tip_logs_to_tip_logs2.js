#!/usr/bin/env node

/* eslint-disable require-jsdoc, max-len, operator-linebreak, @typescript-eslint/no-var-requires */

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const DEFAULT_SOURCE_COLLECTION = "tipLogs";
const DEFAULT_TARGET_COLLECTION = "tipLogs2";
const DEFAULT_BATCH_SIZE = 400;
const DEFAULT_PROGRESS_INTERVAL = 100;
const MAX_RETRIES = 5;

function parseArgs(argv) {
  const options = {
    write: false,
    source: DEFAULT_SOURCE_COLLECTION,
    target: DEFAULT_TARGET_COLLECTION,
    batchSize: DEFAULT_BATCH_SIZE,
    limit: null,
    projectId: null,
    emulatorHost: null,
    progressInterval: DEFAULT_PROGRESS_INTERVAL,
    skipExisting: false,
    legacyTimestampAfter: null,
  };

  for (const arg of argv) {
    if (arg === "--write") {
      options.write = true;
    } else if (arg === "--dry-run") {
      options.write = false;
    } else if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else if (arg.startsWith("--source=")) {
      options.source = arg.slice("--source=".length);
    } else if (arg.startsWith("--target=")) {
      options.target = arg.slice("--target=".length);
    } else if (arg.startsWith("--batch-size=")) {
      options.batchSize = Number.parseInt(arg.slice("--batch-size=".length), 10);
    } else if (arg.startsWith("--limit=")) {
      options.limit = Number.parseInt(arg.slice("--limit=".length), 10);
    } else if (arg.startsWith("--project-id=")) {
      options.projectId = arg.slice("--project-id=".length);
    } else if (arg.startsWith("--emulator-host=")) {
      options.emulatorHost = arg.slice("--emulator-host=".length);
    } else if (arg.startsWith("--progress-interval=")) {
      options.progressInterval = Number.parseInt(arg.slice("--progress-interval=".length), 10);
    } else if (arg === "--skip-existing") {
      options.skipExisting = true;
    } else if (arg.startsWith("--legacy-timestamp-after=")) {
      options.legacyTimestampAfter = timestampFrom(arg.slice("--legacy-timestamp-after=".length));
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!options.source || !options.target) {
    throw new Error("--source and --target must be non-empty collection names.");
  }
  if (!Number.isInteger(options.batchSize) || options.batchSize < 1 || options.batchSize > 500) {
    throw new Error("--batch-size must be an integer from 1 to 500.");
  }
  if (options.limit !== null && (!Number.isInteger(options.limit) || options.limit < 1)) {
    throw new Error("--limit must be a positive integer.");
  }
  if (!Number.isInteger(options.progressInterval) || options.progressInterval < 1) {
    throw new Error("--progress-interval must be a positive integer.");
  }
  if (argv.some((arg) => arg.startsWith("--legacy-timestamp-after=")) &&
      options.legacyTimestampAfter === null) {
    throw new Error("--legacy-timestamp-after must be an ISO-8601 timestamp or epoch value.");
  }

  return options;
}

function printUsage() {
  console.log(`
Migrates legacy nested Firestore tip logs into flat tipLogs2 documents.

Default mode is a dry run. Pass --write to write migrated documents.

Usage:
  cd functions
  node scripts/migrate_tip_logs_to_tip_logs2.js [options]

Options:
  --write                    Write migrated docs. Without this, no writes occur.
  --dry-run                  Explicitly run without writes.
  --source=tipLogs           Legacy root collection.
  --target=tipLogs2          Flat target collection.
  --limit=25                 Stop after reading this many legacy log docs.
  --batch-size=400           Firestore batch size, max 500.
  --progress-interval=100    Print progress after this many legacy log docs.
  --skip-existing            Do not rewrite target docs that already exist.
  --legacy-timestamp-after=2026-05-10T00:00:00Z
                             Only migrate legacy logs after this timestamp.
  --project-id=<project>     Firebase project ID for application default credentials.
  --emulator-host=127.0.0.1:8080
                             Use the Firestore emulator.

Authentication:
  For production, use Application Default Credentials, for example:
  GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node scripts/migrate_tip_logs_to_tip_logs2.js --write
`);
}

function findRepoConfigPath(filename) {
  let dir = __dirname;
  while (dir !== path.dirname(dir)) {
    const candidate = path.join(dir, filename);
    if (fs.existsSync(candidate)) {
      return candidate;
    }
    dir = path.dirname(dir);
  }
  return null;
}

function readDefaultFirebaseProjectId() {
  const firebaseRcPath = findRepoConfigPath(".firebaserc");
  if (!firebaseRcPath) {
    return null;
  }

  const firebaseRc = JSON.parse(fs.readFileSync(firebaseRcPath, "utf8"));
  return firebaseRc.projects?.default || null;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function shouldRetry(error) {
  return [4, 8, 10, 13, 14].includes(error?.code);
}

async function withRetry(label, action) {
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt += 1) {
    try {
      return await action();
    } catch (error) {
      if (attempt >= MAX_RETRIES || !shouldRetry(error)) {
        throw error;
      }

      const delayMs = Math.min(30000, 1000 * 2 ** attempt);
      console.warn(
        `${label} failed with retryable Firestore error code ${error.code}; retry ${attempt + 1}/${MAX_RETRIES} in ${delayMs}ms`,
      );
      await sleep(delayMs);
    }
  }

  throw new Error(`${label} failed after ${MAX_RETRIES} retries.`);
}

function stableTargetId(legacyPath) {
  return crypto.createHash("sha1").update(legacyPath).digest("hex");
}

function parseIntOrNull(value) {
  const parsed = Number.parseInt(String(value), 10);
  return Number.isNaN(parsed) ? null : parsed;
}

function timestampFrom(value) {
  if (!value) {
    return null;
  }
  if (value instanceof admin.firestore.Timestamp) {
    return value;
  }
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return admin.firestore.Timestamp.fromDate(value);
  }
  if (typeof value === "string") {
    const millis = Date.parse(value);
    return Number.isNaN(millis)
      ? null
      : admin.firestore.Timestamp.fromDate(new Date(millis));
  }
  if (typeof value === "number") {
    const millis = value > 100000000000 ? value : value * 1000;
    return admin.firestore.Timestamp.fromDate(new Date(millis));
  }
  return null;
}

function isoFrom(value) {
  const timestamp = timestampFrom(value);
  return timestamp ? timestamp.toDate().toISOString() : null;
}

function removeUndefined(value) {
  return Object.fromEntries(
    Object.entries(value).filter(([, fieldValue]) => fieldValue !== undefined),
  );
}

function buildFlatTipLog({legacyPath, yearId, roundId, tipperId, gameId, timestampId, data}) {
  const gameDetails = data.gameDetails || {};
  const appDetails = data.appDetails || {};
  const platform = typeof data.platform === "string" ? data.platform : data.platform?.os;
  const submittedAtInput = data.tipSubmittedUTC || timestampId;
  const gameStartTimeInput = gameDetails.startTimeUTC;
  const installTime = timestampFrom(appDetails.installTime);
  const lastUpdateTime = timestampFrom(appDetails.lastUpdateTime);

  return removeUndefined({
    legacyPath,
    legacyYearId: yearId,
    legacyRoundId: roundId,
    legacyTimestampId: timestampId,
    migratedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: timestampFrom(submittedAtInput),
    submittedAtUTC: timestampFrom(submittedAtInput),
    submittedAtIsoUTC: isoFrom(submittedAtInput) || submittedAtInput,
    seasonYear: parseIntOrNull(yearId),
    round: parseIntOrNull(roundId),
    compId: null,
    compName: null,
    tipperId: data.tipperId || tipperId,
    tipperName: data.tipperName || null,
    gameId: data.gameId || gameId,
    league: gameDetails.league || null,
    homeTeam: gameDetails.homeTeam || null,
    awayTeam: gameDetails.awayTeam || null,
    gameStartTimeUTC: timestampFrom(gameStartTimeInput),
    gameStartTimeIsoUTC: isoFrom(gameStartTimeInput) || gameStartTimeInput || null,
    tipResult: null,
    tip: data.tip ?? null,
    submittedByTipperId: null,
    submittedBy: data.submittedBy || null,
    appVersion: appDetails.version || null,
    buildNumber: appDetails.buildNumber || null,
    installTimeUTC: installTime,
    lastUpdateTimeUTC: lastUpdateTime,
    platform: platform || null,
  });
}

function isAfterTimestamp(timestamp, cutoff) {
  if (!cutoff) {
    return true;
  }
  if (!timestamp) {
    return false;
  }
  return timestamp.toMillis() > cutoff.toMillis();
}

class BatchWriter {
  constructor(db, batchSize) {
    this.db = db;
    this.batchSize = batchSize;
    this.batch = db.batch();
    this.pending = 0;
    this.commits = 0;
  }

  async set(ref, data) {
    this.batch.set(ref, data);
    this.pending += 1;
    if (this.pending >= this.batchSize) {
      await this.flush();
    }
  }

  async flush() {
    if (this.pending === 0) {
      return;
    }
    await withRetry("batch commit", () => this.batch.commit());
    this.commits += 1;
    this.batch = this.db.batch();
    this.pending = 0;
  }
}

function logProgress(stats, context) {
  console.log(
    JSON.stringify({
      progress: true,
      read: stats.read,
      written: stats.written,
      missing: stats.missing,
      skippedBeforeCutoff: stats.skippedBeforeCutoff,
      skippedExisting: stats.skippedExisting,
      years: stats.years,
      rounds: stats.rounds,
      tippers: stats.tippers,
      games: stats.games,
      context,
    }),
  );
}

async function migrate(options) {
  if (options.emulatorHost) {
    process.env.FIRESTORE_EMULATOR_HOST = options.emulatorHost;
  }

  const projectId = options.projectId || readDefaultFirebaseProjectId();
  admin.initializeApp(projectId ? {projectId} : undefined);

  const db = admin.firestore();
  const writer = new BatchWriter(db, options.batchSize);
  const sourceRoot = db.collection(options.source);
  const targetRoot = db.collection(options.target);
  const stats = {
    years: 0,
    rounds: 0,
    tippers: 0,
    games: 0,
    read: 0,
    missing: 0,
    skippedBeforeCutoff: 0,
    skippedExisting: 0,
    written: 0,
  };

  console.log(
    `${options.write ? "WRITE" : "DRY RUN"} migration ${options.source} -> ${options.target}`,
  );
  console.log(`Using Firebase project: ${projectId || "(application default)"}`);

  const yearRefs = await withRetry(
    `${sourceRoot.path}.listDocuments`,
    () => sourceRoot.listDocuments(),
  );
  for (const yearRef of yearRefs) {
    stats.years += 1;
    const roundCollections = await withRetry(
      `${yearRef.path}.listCollections`,
      () => yearRef.listCollections(),
    );
    for (const roundCollection of roundCollections) {
      stats.rounds += 1;
      const tipperRefs = await withRetry(
        `${roundCollection.path}.listDocuments`,
        () => roundCollection.listDocuments(),
      );
      for (const tipperRef of tipperRefs) {
        stats.tippers += 1;
        const gameCollections = await withRetry(
          `${tipperRef.path}.listCollections`,
          () => tipperRef.listCollections(),
        );
        for (const gameCollection of gameCollections) {
          stats.games += 1;
          const logStream = gameCollection.stream();
          for await (const snapshot of logStream) {
            if (options.limit !== null && stats.read >= options.limit) {
              await writer.flush();
              return stats;
            }

            if (!snapshot.exists) {
              stats.missing += 1;
              continue;
            }

            const logRef = snapshot.ref;
            const legacyPath = logRef.path;
            const submittedAt = timestampFrom(snapshot.data()?.tipSubmittedUTC || logRef.id);
            if (!isAfterTimestamp(submittedAt, options.legacyTimestampAfter)) {
              stats.skippedBeforeCutoff += 1;
              continue;
            }

            const flatDoc = buildFlatTipLog({
              legacyPath,
              yearId: yearRef.id,
              roundId: roundCollection.id,
              tipperId: tipperRef.id,
              gameId: gameCollection.id,
              timestampId: logRef.id,
              data: snapshot.data() || {},
            });
            const targetRef = targetRoot.doc(stableTargetId(legacyPath));

            stats.read += 1;
            if (options.skipExisting) {
              const targetSnapshot = await withRetry(
                `${targetRef.path}.get`,
                () => targetRef.get(),
              );
              if (targetSnapshot.exists) {
                stats.skippedExisting += 1;
                continue;
              }
            }

            if (options.write) {
              await writer.set(targetRef, flatDoc);
              stats.written += 1;
            } else if (stats.read <= 5) {
              console.log(JSON.stringify({targetPath: targetRef.path, flatDoc}, null, 2));
            }

            if (stats.read % options.progressInterval === 0) {
              logProgress(stats, legacyPath);
            }
          }
        }
      }
    }
  }

  await writer.flush();
  return stats;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    printUsage();
    return;
  }

  const stats = await migrate(options);
  console.log(JSON.stringify(stats, null, 2));
  if (!options.write) {
    console.log("Dry run only. Re-run with --write to create migrated documents.");
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
