#!/usr/bin/env node

const DEFAULT_NAMESPACE = "dau-footy-tipping-f8a42-default-rtdb";
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

export function compareRoundStats({
  backendStats,
  legacyStats,
  roundNumber,
  tipperId,
  fields = DEFAULT_FIELDS,
}) {
  const backendRounds = roundNumber == null
    ? numericKeys(backendStats)
    : [roundNumber];
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

export function parseArgs(args, env = process.env) {
  const options = {
    baseUrl: defaultBaseUrl(env),
    namespace:
      env.RTDB_EMULATOR_NAMESPACE ||
      env.FIREBASE_DATABASE_EMULATOR_NAMESPACE ||
      DEFAULT_NAMESPACE,
    fields: DEFAULT_FIELDS,
    maxMismatches: 20,
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
      case "--round":
        options.roundNumber = positiveInt(nextValue(), "--round");
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

function legacyRoundForBackendRound(legacyStats, backendRoundNumber) {
  const legacyRoundIndex = backendRoundNumber - 1;
  if (Array.isArray(legacyStats)) {
    return legacyStats[legacyRoundIndex] ?? null;
  }
  return objectValue(legacyStats, legacyRoundIndex);
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

  const [backendStats, legacyStats] = await Promise.all([
    fetchRtdbJson({
      baseUrl: options.baseUrl,
      namespace: options.namespace,
      path: `/Stats/${options.compKey}/round_stats_backend_v1`,
    }),
    fetchRtdbJson({
      baseUrl: options.baseUrl,
      namespace: options.namespace,
      path: `/Stats/${options.compKey}/round_stats_v3`,
    }),
  ]);

  const comparison = compareRoundStats({
    backendStats,
    legacyStats,
    roundNumber: options.roundNumber,
    tipperId: options.tipperId,
    fields: options.fields,
  });

  if (options.json) {
    console.log(JSON.stringify(comparison, null, 2));
  } else {
    console.log(formatComparisonReport(comparison, options));
  }

  return hasComparisonFailures(comparison) ? 1 : 0;
}

function usage() {
  return [
    "Usage:",
    "  node scripts/compare_backend_round_stats.mjs --comp-key <compKey> [options]",
    "",
    "Options:",
    "  --round <number>          Compare one backend round against v3[round - 1].",
    "  --tipper-id <id>          Compare one tipper only.",
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
