#!/usr/bin/env node

const DEFAULT_NAMESPACE = "dau-footy-tipping-f8a42-default-rtdb";
const STATS_PATH_ROOT = "/Stats";
const ROUND_STATS_BACKEND_V1_ROOT = "round_stats_backend_v1";
const GAME_STATS_BACKEND_V1_ROOT = "game_stats_backend_v1";
const ROUND_STATS_V3_ROOT = "round_stats_v3";
const GAME_STATS_V3_ROOT = "game_stats_v3";
const DEFAULT_FIELDS = [
  "aS",
  "aMs",
  "aMt",
  "aMu",
  "aTo",
  "nS",
  "nMs",
  "nMt",
  "nMu",
  "nTo",
];
const DEFAULT_GAME_STATS_FIELDS = [
  "pctTipA",
  "pctTipB",
  "pctTipC",
  "pctTipD",
  "pctTipE",
  "avgScore",
  "avgScoreTipCount",
];
const VALID_TYPES = new Set(["round-stats", "game-stats"]);

export function compareRoundStats({
  backendStats,
  legacyStats,
  roundNumber,
  tipperId,
  fields = DEFAULT_FIELDS,
}) {
  const explicitRound = roundNumber != null;
  const backendRounds = explicitRound
    ? [roundNumber]
    : roundKeysForComparison(backendStats, legacyStats);
  const rounds = [];

  for (const backendRoundNumber of backendRounds) {
    const backendRound = objectValue(backendStats, backendRoundNumber);
    const legacyRound = legacyRoundForBackendRound(
      legacyStats,
      backendRoundNumber,
    );
    const legacyRoundIndex = backendRoundNumber - 1;
    const result = {
      backendRoundNumber,
      legacyRoundIndex,
      missingBackendRound: backendRound == null,
      missingLegacyRound: legacyRound == null,
      missingBackendTippers: [],
      missingLegacyTippers: [],
      mismatches: [],
      matches: 0,
      backendTipperCount: backendRound == null ? 0 : Object.keys(backendRound).length,
      legacyTipperCount: legacyRound == null ? 0 : Object.keys(legacyRound).length,
    };

    if (!explicitRound &&
        isIgnorableStructuralRound(backendRound, legacyRound, fields)) {
      continue;
    }

    if (backendRound == null || legacyRound == null) {
      rounds.push(result);
      continue;
    }

    const backendTipperIds = tipperId == null
      ? Object.keys(backendRound)
      : [tipperId];
    const legacyTipperIds = tipperId == null
      ? Object.keys(legacyRound)
      : [tipperId];
    const tipperIds = new Set([...backendTipperIds, ...legacyTipperIds]);

    for (const id of Array.from(tipperIds).sort()) {
      const backendTipperStats = backendRound[id];
      const legacyTipperStats = legacyRound[id];
      if (backendTipperStats == null) {
        result.missingBackendTippers.push(id);
        continue;
      }
      if (legacyTipperStats == null) {
        result.missingLegacyTippers.push(id);
        continue;
      }

      const fieldDiffs = {};
      for (const field of fields) {
        const backendValue = backendTipperStats[field] ?? 0;
        const legacyValue = legacyTipperStats[field] ?? 0;
        if (backendValue !== legacyValue) {
          fieldDiffs[field] = {
            backend: backendValue,
            legacy: legacyValue,
          };
        }
      }

      if (Object.keys(fieldDiffs).length > 0) {
        result.mismatches.push({
          tipperId: id,
          fields: fieldDiffs,
        });
      } else {
        result.matches += 1;
      }
    }

    rounds.push(result);
  }

  return {
    rounds,
    totals: summarizeRounds(rounds),
  };
}

export function compareGameStats({
  backendStats,
  legacyStats,
  cohort,
  gameKey,
  fields = DEFAULT_GAME_STATS_FIELDS,
}) {
  const cohorts = cohort == null ? ["paid", "free"] : [cohort];
  const results = [];

  for (const cohortKey of cohorts) {
    const backendCohort = objectValue(backendStats, cohortKey);
    const legacyCohort = objectValue(legacyStats, cohortKey);
    const result = {
      cohort: cohortKey,
      missingBackendCohort: backendCohort == null,
      missingLegacyCohort: legacyCohort == null,
      missingBackendGames: [],
      missingLegacyGames: [],
      mismatches: [],
      matches: 0,
      backendGameCount: backendCohort == null ? 0 : Object.keys(backendCohort).length,
      legacyGameCount: legacyCohort == null ? 0 : Object.keys(legacyCohort).length,
    };

    if (backendCohort == null || legacyCohort == null) {
      results.push(result);
      continue;
    }

    const backendGameKeys = gameKey == null
      ? Object.keys(backendCohort)
      : [gameKey];
    const legacyGameKeys = gameKey == null
      ? Object.keys(legacyCohort)
      : [gameKey];
    const gameKeys = new Set([...backendGameKeys, ...legacyGameKeys]);

    for (const key of Array.from(gameKeys).sort()) {
      const backendGameStats = backendCohort[key];
      const legacyGameStats = legacyCohort[key];
      if (backendGameStats == null) {
        result.missingBackendGames.push(key);
        continue;
      }
      if (legacyGameStats == null) {
        result.missingLegacyGames.push(key);
        continue;
      }

      const fieldDiffs = {};
      for (const field of fields) {
        const backendValue = normalizeComparableNumber(
          backendGameStats[field] ?? 0,
        );
        const legacyValue = normalizeComparableNumber(
          legacyGameStats[field] ?? 0,
        );
        if (backendValue !== legacyValue) {
          fieldDiffs[field] = {
            backend: backendValue,
            legacy: legacyValue,
          };
        }
      }

      if (Object.keys(fieldDiffs).length > 0) {
        result.mismatches.push({
          gameKey: key,
          fields: fieldDiffs,
        });
      } else {
        result.matches += 1;
      }
    }

    results.push(result);
  }

  return {
    cohorts: results,
    totals: summarizeGameStatsCohorts(results),
  };
}

export function parseArgs(args, env = process.env) {
  const options = {
    baseUrl: defaultBaseUrl(env),
    namespace:
      env.RTDB_EMULATOR_NAMESPACE ||
      env.FIREBASE_DATABASE_EMULATOR_NAMESPACE ||
      DEFAULT_NAMESPACE,
    fields: DEFAULT_FIELDS,
    maxMismatches: 20,
    type: "round-stats",
  };

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    const nextValue = () => {
      i += 1;
      if (i >= args.length) {
        throw new Error(`Missing value for ${arg}`);
      }
      return args[i];
    };

    switch (arg) {
      case "--help":
      case "-h":
        options.help = true;
        break;
      case "--comp-key":
        options.compKey = nextValue();
        break;
      case "--type":
        options.type = nextValue();
        if (!VALID_TYPES.has(options.type)) {
          throw new Error("--type must be round-stats or game-stats");
        }
        if (options.type === "game-stats" &&
            options.fields === DEFAULT_FIELDS) {
          options.fields = DEFAULT_GAME_STATS_FIELDS;
        }
        break;
      case "--round":
        options.roundNumber = positiveInt(nextValue(), "--round");
        break;
      case "--cohort":
        options.cohort = nextValue();
        if (options.cohort !== "paid" && options.cohort !== "free") {
          throw new Error("--cohort must be paid or free");
        }
        break;
      case "--game-key":
        options.gameKey = nextValue();
        break;
      case "--tipper-id":
        options.tipperId = nextValue();
        break;
      case "--base-url":
        options.baseUrl = trimTrailingSlash(nextValue());
        break;
      case "--namespace":
        options.namespace = nextValue();
        break;
      case "--fields":
        options.fields = nextValue()
          .split(",")
          .map((field) => field.trim())
          .filter((field) => field.length > 0);
        break;
      case "--max-mismatches":
        options.maxMismatches = positiveInt(nextValue(), "--max-mismatches");
        break;
      case "--json":
        options.json = true;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!options.help && !options.compKey) {
    throw new Error("Missing required argument: --comp-key");
  }
  if (options.type === "round-stats" &&
      (options.cohort != null || options.gameKey != null)) {
    throw new Error("--cohort and --game-key require --type game-stats");
  }
  if (options.type === "game-stats" &&
      (options.roundNumber != null || options.tipperId != null)) {
    throw new Error("--round and --tipper-id require --type round-stats");
  }

  return options;
}

export function formatComparisonReport(comparison, options) {
  const lines = [];
  lines.push("Backend scoring comparison");
  lines.push(`compKey: ${options.compKey}`);
  lines.push("mapping: backend round N -> v3 round N - 1");
  if (options.roundNumber != null) {
    lines.push(`round: ${options.roundNumber}`);
  }
  if (options.tipperId != null) {
    lines.push(`tipperId: ${options.tipperId}`);
  }
  lines.push("");

  for (const round of comparison.rounds) {
    lines.push(
      `Round ${round.backendRoundNumber} vs v3[${round.legacyRoundIndex}]`,
    );
    if (round.missingBackendRound) {
      lines.push("  missing backend round");
      continue;
    }
    if (round.missingLegacyRound) {
      lines.push("  missing v3 round");
      continue;
    }

    lines.push(`  matches: ${round.matches}`);
    lines.push(`  mismatches: ${round.mismatches.length}`);
    lines.push(`  backend rows: ${round.backendTipperCount}`);
    lines.push(`  v3 rows: ${round.legacyTipperCount}`);
    lines.push(
      `  v3-only tippers missing backend: ${round.missingBackendTippers.length}`,
    );
    lines.push(
      `  backend-only tippers missing v3: ${round.missingLegacyTippers.length}`,
    );

    for (const mismatch of round.mismatches.slice(0, options.maxMismatches)) {
      lines.push(
        `  mismatch ${mismatch.tipperId}: ${formatFieldDiffs(mismatch.fields)}`,
      );
    }
    if (round.mismatches.length > options.maxMismatches) {
      lines.push(
        `  ... ${round.mismatches.length - options.maxMismatches} more mismatches`,
      );
    }
  }

  lines.push("");
  lines.push(`rounds compared: ${comparison.totals.roundsCompared}`);
  lines.push(`rounds missing backend: ${comparison.totals.missingBackendRounds}`);
  lines.push(`rounds missing v3: ${comparison.totals.missingLegacyRounds}`);
  lines.push(`total matches: ${comparison.totals.matches}`);
  lines.push(`total mismatches: ${comparison.totals.mismatches}`);
  lines.push(
    `total v3-only tippers missing backend: ${comparison.totals.missingBackendTippers}`,
  );
  lines.push(
    `total backend-only tippers missing v3: ${comparison.totals.missingLegacyTippers}`,
  );

  return lines.join("\n");
}

export function formatGameStatsComparisonReport(comparison, options) {
  const lines = [];
  lines.push("Backend game stats comparison");
  lines.push(`compKey: ${options.compKey}`);
  lines.push(
    `mapping: ${GAME_STATS_BACKEND_V1_ROOT}/<cohort>/<gameKey> -> ` +
    `${GAME_STATS_V3_ROOT}/<cohort>/<gameKey>`,
  );
  if (options.cohort != null) {
    lines.push(`cohort: ${options.cohort}`);
  }
  if (options.gameKey != null) {
    lines.push(`gameKey: ${options.gameKey}`);
  }
  lines.push("");

  for (const cohort of comparison.cohorts) {
    lines.push(`Cohort ${cohort.cohort}`);
    if (cohort.missingBackendCohort) {
      lines.push("  missing backend cohort");
      continue;
    }
    if (cohort.missingLegacyCohort) {
      lines.push("  missing v3 cohort");
      continue;
    }

    lines.push(`  matches: ${cohort.matches}`);
    lines.push(`  mismatches: ${cohort.mismatches.length}`);
    lines.push(`  backend games: ${cohort.backendGameCount}`);
    lines.push(`  v3 games: ${cohort.legacyGameCount}`);
    lines.push(`  v3-only games missing backend: ${cohort.missingBackendGames.length}`);
    lines.push(`  backend-only games missing v3: ${cohort.missingLegacyGames.length}`);

    for (const gameKey of cohort.missingBackendGames.slice(
      0,
      options.maxMismatches,
    )) {
      lines.push(`  missing backend game ${gameKey}`);
    }
    if (cohort.missingBackendGames.length > options.maxMismatches) {
      lines.push(
        `  ... ${cohort.missingBackendGames.length - options.maxMismatches} more missing backend games`,
      );
    }

    for (const gameKey of cohort.missingLegacyGames.slice(
      0,
      options.maxMismatches,
    )) {
      lines.push(`  missing v3 game ${gameKey}`);
    }
    if (cohort.missingLegacyGames.length > options.maxMismatches) {
      lines.push(
        `  ... ${cohort.missingLegacyGames.length - options.maxMismatches} more missing v3 games`,
      );
    }

    for (const mismatch of cohort.mismatches.slice(0, options.maxMismatches)) {
      lines.push(
        `  mismatch ${mismatch.gameKey}: ${formatFieldDiffs(mismatch.fields)}`,
      );
    }
    if (cohort.mismatches.length > options.maxMismatches) {
      lines.push(
        `  ... ${cohort.mismatches.length - options.maxMismatches} more mismatches`,
      );
    }
  }

  lines.push("");
  lines.push(`cohorts compared: ${comparison.totals.cohortsCompared}`);
  lines.push(`cohorts missing backend: ${comparison.totals.missingBackendCohorts}`);
  lines.push(`cohorts missing v3: ${comparison.totals.missingLegacyCohorts}`);
  lines.push(`total matches: ${comparison.totals.matches}`);
  lines.push(`total mismatches: ${comparison.totals.mismatches}`);
  lines.push(
    `total v3-only games missing backend: ${comparison.totals.missingBackendGames}`,
  );
  lines.push(
    `total backend-only games missing v3: ${comparison.totals.missingLegacyGames}`,
  );

  return lines.join("\n");
}

export function hasGameStatsComparisonFailures(comparison) {
  const totals = comparison.totals;
  return totals.missingBackendCohorts > 0 ||
    totals.missingLegacyCohorts > 0 ||
    totals.mismatches > 0 ||
    totals.missingBackendGames > 0 ||
    totals.missingLegacyGames > 0;
}

export function hasComparisonFailures(comparison) {
  const totals = comparison.totals;
  return totals.missingBackendRounds > 0 ||
    totals.missingLegacyRounds > 0 ||
    totals.mismatches > 0 ||
    totals.missingBackendTippers > 0 ||
    totals.missingLegacyTippers > 0;
}

function summarizeRounds(rounds) {
  return rounds.reduce(
    (totals, round) => {
      totals.roundsCompared += 1;
      if (round.missingBackendRound) {
        totals.missingBackendRounds += 1;
      }
      if (round.missingLegacyRound) {
        totals.missingLegacyRounds += 1;
      }
      totals.matches += round.matches;
      totals.mismatches += round.mismatches.length;
      totals.missingBackendTippers += round.missingBackendTippers.length;
      totals.missingLegacyTippers += round.missingLegacyTippers.length;
      return totals;
    },
    {
      roundsCompared: 0,
      missingBackendRounds: 0,
      missingLegacyRounds: 0,
      matches: 0,
      mismatches: 0,
      missingBackendTippers: 0,
      missingLegacyTippers: 0,
    },
  );
}

function summarizeGameStatsCohorts(cohorts) {
  return cohorts.reduce(
    (totals, cohort) => {
      totals.cohortsCompared += 1;
      if (cohort.missingBackendCohort) {
        totals.missingBackendCohorts += 1;
      }
      if (cohort.missingLegacyCohort) {
        totals.missingLegacyCohorts += 1;
      }
      totals.matches += cohort.matches;
      totals.mismatches += cohort.mismatches.length;
      totals.missingBackendGames += cohort.missingBackendGames.length;
      totals.missingLegacyGames += cohort.missingLegacyGames.length;
      return totals;
    },
    {
      cohortsCompared: 0,
      missingBackendCohorts: 0,
      missingLegacyCohorts: 0,
      matches: 0,
      mismatches: 0,
      missingBackendGames: 0,
      missingLegacyGames: 0,
    },
  );
}

function legacyRoundForBackendRound(legacyStats, backendRoundNumber) {
  const legacyRoundIndex = backendRoundNumber - 1;
  if (Array.isArray(legacyStats)) {
    return legacyStats[legacyRoundIndex] ?? null;
  }
  return objectValue(legacyStats, legacyRoundIndex);
}

function roundKeysForComparison(backendStats, legacyStats) {
  return Array.from(
    new Set([
      ...numericKeys(backendStats),
      ...legacyBackendRoundKeys(legacyStats),
    ]),
  ).sort((a, b) => a - b);
}

function legacyBackendRoundKeys(legacyStats) {
  if (legacyStats == null || typeof legacyStats !== "object") {
    return [];
  }
  if (Array.isArray(legacyStats)) {
    return legacyStats.map((_, index) => index + 1);
  }
  return Object.keys(legacyStats)
    .map((key) => Number(key))
    .filter((key) => Number.isInteger(key) && key >= 0)
    .map((legacyRoundIndex) => legacyRoundIndex + 1)
    .sort((a, b) => a - b);
}

function isEmptyRoundStats(roundStats, fields) {
  if (roundStats == null || typeof roundStats !== "object") {
    return true;
  }

  const tipperStats = Object.values(roundStats);
  if (tipperStats.length === 0) {
    return true;
  }

  return tipperStats.every((stats) => {
    if (stats == null || typeof stats !== "object") {
      return true;
    }
    return fields.every((field) => (stats[field] ?? 0) === 0);
  });
}

function isIgnorableStructuralRound(backendRound, legacyRound, fields) {
  if (backendRound == null && legacyRound == null) {
    return true;
  }
  if (backendRound == null) {
    return isEmptyRoundStats(legacyRound, fields);
  }
  if (legacyRound == null) {
    return isEmptyRoundStats(backendRound, fields);
  }
  return false;
}

function objectValue(value, key) {
  if (value == null || typeof value !== "object") {
    return null;
  }
  return value[String(key)] ?? null;
}

function numericKeys(value) {
  if (value == null || typeof value !== "object") {
    return [];
  }
  return Object.keys(value)
    .map((key) => Number(key))
    .filter((key) => Number.isInteger(key) && key > 0)
    .sort((a, b) => a - b);
}

function formatFieldDiffs(fields) {
  return Object.entries(fields)
    .map(([field, diff]) => `${field} backend=${diff.backend} v3=${diff.legacy}`)
    .join(", ");
}

function normalizeComparableNumber(value) {
  if (typeof value !== "number") {
    return value;
  }
  return Number(value.toFixed(3));
}

function defaultBaseUrl(env) {
  if (env.FIREBASE_DATABASE_EMULATOR_HOST) {
    return `http://${env.FIREBASE_DATABASE_EMULATOR_HOST}`;
  }
  const host = env.RTDB_EMULATOR_HOST || "127.0.0.1";
  const port = env.RTDB_EMULATOR_PORT || "8000";
  return `http://${host}:${port}`;
}

function positiveInt(raw, label) {
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1) {
    throw new Error(`${label} must be a positive integer`);
  }
  return value;
}

function trimTrailingSlash(value) {
  return value.replace(/\/+$/, "");
}

function rtdbPath(path) {
  return path
    .split("/")
    .filter((segment) => segment.length > 0)
    .map((segment) => encodeURIComponent(segment))
    .join("/");
}

async function fetchRtdbJson({baseUrl, namespace, path}) {
  const url = `${baseUrl}/${rtdbPath(path)}.json?ns=${encodeURIComponent(namespace)}`;
  let response;
  try {
    response = await fetch(url);
  } catch (error) {
    throw new Error(`RTDB read failed: ${url}: ${error.message}`);
  }
  if (!response.ok) {
    throw new Error(`RTDB read failed ${response.status}: ${url}`);
  }
  return response.json();
}

async function runCli() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return 0;
  }

  const backendRoot = options.type === "game-stats"
    ? GAME_STATS_BACKEND_V1_ROOT
    : ROUND_STATS_BACKEND_V1_ROOT;
  const legacyRoot = options.type === "game-stats"
    ? GAME_STATS_V3_ROOT
    : ROUND_STATS_V3_ROOT;
  const [backendStats, legacyStats] = await Promise.all([
    fetchRtdbJson({
      baseUrl: options.baseUrl,
      namespace: options.namespace,
      path: `${STATS_PATH_ROOT}/${options.compKey}/${backendRoot}`,
    }),
    fetchRtdbJson({
      baseUrl: options.baseUrl,
      namespace: options.namespace,
      path: `${STATS_PATH_ROOT}/${options.compKey}/${legacyRoot}`,
    }),
  ]);

  const comparison = options.type === "game-stats"
    ? compareGameStats({
      backendStats,
      legacyStats,
      cohort: options.cohort,
      gameKey: options.gameKey,
      fields: options.fields,
    })
    : compareRoundStats({
      backendStats,
      legacyStats,
      roundNumber: options.roundNumber,
      tipperId: options.tipperId,
      fields: options.fields,
    });

  if (options.json) {
    console.log(JSON.stringify(comparison, null, 2));
  } else {
    console.log(options.type === "game-stats"
      ? formatGameStatsComparisonReport(comparison, options)
      : formatComparisonReport(comparison, options));
  }

  return options.type === "game-stats"
    ? (hasGameStatsComparisonFailures(comparison) ? 1 : 0)
    : (hasComparisonFailures(comparison) ? 1 : 0);
}

function usage() {
  return [
    "Usage:",
    "  node scripts/compare_backend_round_stats.mjs --comp-key <compKey> [options]",
    "",
    "Options:",
    "  --type <type>            round-stats or game-stats. Default: round-stats.",
    "  --round <number>          Compare one backend round against v3[round - 1].",
    "  --tipper-id <id>          Compare one tipper only.",
    "  --cohort <paid|free>      Compare one game-stats cohort only.",
    "  --game-key <key>          Compare one game only for game-stats.",
    "  --base-url <url>          RTDB REST base URL. Defaults to emulator env or http://127.0.0.1:8000.",
    "  --namespace <name>        RTDB namespace. Defaults to emulator env or dau-footy-tipping-f8a42-default-rtdb.",
    "  --fields <a,b,c>          Comma-separated fields to compare.",
    "  --max-mismatches <n>      Max mismatches printed per round. Default: 20.",
    "  --json                    Print machine-readable JSON.",
    "  --help                    Show this help.",
  ].join("\n");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  runCli()
    .then((exitCode) => {
      process.exitCode = exitCode;
    })
    .catch((error) => {
      console.error(error.message);
      process.exitCode = 2;
    });
}
