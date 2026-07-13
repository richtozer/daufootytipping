import assert from "node:assert/strict";
import test from "node:test";

import {
  compareGameStats,
  compareRoundStats,
  formatGameStatsComparisonReport,
  formatComparisonReport,
  hasGameStatsComparisonFailures,
  hasComparisonFailures,
  parseArgs,
} from "./compare_backend_round_stats.mjs";

test("compareRoundStats maps backend round N to v3 round N - 1", () => {
  const comparison = compareRoundStats({
    backendStats: {
      1: {
        "tipper-1": {aS: 4, nS: 12},
      },
      3: {
        "tipper-1": {aS: 6, nS: 8},
      },
    },
    legacyStats: [
      {
        "tipper-1": {aS: 4, nS: 12},
      },
      {
        "tipper-1": {aS: 0, nS: 0},
      },
      {
        "tipper-1": {aS: 6, nS: 8},
      },
    ],
    fields: ["aS", "nS"],
  });

  assert.equal(comparison.totals.roundsCompared, 2);
  assert.equal(comparison.totals.matches, 2);
  assert.equal(comparison.totals.mismatches, 0);
  assert.equal(comparison.rounds[0].legacyRoundIndex, 0);
  assert.equal(comparison.rounds[1].legacyRoundIndex, 2);
  assert.equal(hasComparisonFailures(comparison), false);
});

test("compareRoundStats reports field mismatches", () => {
  const comparison = compareRoundStats({
    backendStats: {
      13: {
        "tipper-1": {aS: 8, nS: 6},
      },
    },
    legacyStats: {
      12: {
        "tipper-1": {aS: 10, nS: 6},
      },
    },
    fields: ["aS", "nS"],
  });

  assert.equal(comparison.totals.matches, 0);
  assert.equal(comparison.totals.mismatches, 1);
  assert.deepEqual(comparison.rounds[0].mismatches[0], {
    tipperId: "tipper-1",
    fields: {
      aS: {
        backend: 8,
        legacy: 10,
      },
    },
  });
  assert.equal(hasComparisonFailures(comparison), true);
});

test("compareRoundStats limits comparison to one tipper", () => {
  const comparison = compareRoundStats({
    backendStats: {
      1: {
        "tipper-1": {aS: 4},
        "tipper-2": {aS: 8},
      },
    },
    legacyStats: [
      {
        "tipper-1": {aS: 4},
        "tipper-2": {aS: 0},
      },
    ],
    tipperId: "tipper-1",
    fields: ["aS"],
  });

  assert.equal(comparison.totals.matches, 1);
  assert.equal(comparison.totals.mismatches, 0);
});

test("compareRoundStats reports missing rounds and tippers", () => {
  const comparison = compareRoundStats({
    backendStats: {
      1: {
        "backend-only": {aS: 4},
      },
      2: {
        "tipper-1": {aS: 2},
      },
    },
    legacyStats: [
      {
        "legacy-only": {aS: 4},
      },
    ],
    fields: ["aS"],
  });

  assert.equal(comparison.totals.missingLegacyRounds, 1);
  assert.deepEqual(comparison.rounds[0].missingLegacyTippers, ["backend-only"]);
  assert.deepEqual(comparison.rounds[0].missingBackendTippers, ["legacy-only"]);
  assert.equal(comparison.rounds[0].backendTipperCount, 1);
  assert.equal(comparison.rounds[0].legacyTipperCount, 1);
  assert.equal(hasComparisonFailures(comparison), true);
});

test("compareRoundStats ignores empty structural tail rounds", () => {
  const comparison = compareRoundStats({
    backendStats: {
      1: {
        "tipper-1": {aS: 4, nS: 2},
      },
      2: null,
      3: {
        "tipper-1": {aS: 0, nS: 0},
      },
    },
    legacyStats: [
      {
        "tipper-1": {aS: 4, nS: 2},
      },
      null,
    ],
    fields: ["aS", "nS"],
  });

  assert.equal(comparison.totals.roundsCompared, 1);
  assert.equal(comparison.totals.matches, 1);
  assert.equal(comparison.totals.missingBackendRounds, 0);
  assert.equal(comparison.totals.missingLegacyRounds, 0);
  assert.equal(hasComparisonFailures(comparison), false);
});

test("compareRoundStats reports explicit missing empty rounds", () => {
  const comparison = compareRoundStats({
    backendStats: {
      3: {
        "tipper-1": {aS: 0, nS: 0},
      },
    },
    legacyStats: [],
    roundNumber: 3,
    fields: ["aS", "nS"],
  });

  assert.equal(comparison.totals.roundsCompared, 1);
  assert.equal(comparison.totals.missingLegacyRounds, 1);
  assert.equal(hasComparisonFailures(comparison), true);
});

test("formatComparisonReport includes zero-index mapping", () => {
  const comparison = compareRoundStats({
    backendStats: {
      1: {
        "tipper-1": {aS: 4},
      },
    },
    legacyStats: [
      {
        "tipper-1": {aS: 6},
      },
    ],
    fields: ["aS"],
  });

  const report = formatComparisonReport(comparison, {
    compKey: "comp2026",
    maxMismatches: 20,
  });

  assert.match(report, /mapping: backend round N -> v3 round N - 1/);
  assert.match(report, /Round 1 vs v3\[0\]/);
  assert.match(report, /backend rows: 1/);
  assert.match(report, /v3 rows: 1/);
  assert.match(report, /aS backend=4 v3=6/);
});

test("parseArgs reads emulator defaults and CLI options", () => {
  const options = parseArgs(
    [
      "--comp-key",
      "comp2026",
      "--round",
      "13",
      "--tipper-id",
      "tipper-1",
      "--fields",
      "aS,nS",
      "--max-mismatches",
      "5",
    ],
    {
      FIREBASE_DATABASE_EMULATOR_HOST: "127.0.0.1:8000",
      FIREBASE_DATABASE_EMULATOR_NAMESPACE: "test-ns",
    },
  );

  assert.equal(options.compKey, "comp2026");
  assert.equal(options.roundNumber, 13);
  assert.equal(options.tipperId, "tipper-1");
  assert.equal(options.baseUrl, "http://127.0.0.1:8000");
  assert.equal(options.namespace, "test-ns");
  assert.deepEqual(options.fields, ["aS", "nS"]);
  assert.equal(options.maxMismatches, 5);
});

test("compareGameStats compares paid and free cohorts by game key", () => {
  const comparison = compareGameStats({
    backendStats: {
      paid: {
        "nrl-01-001": {avgScore: 2.1234, avgScoreTipCount: 10, pctTipD: 0.4},
      },
      free: {
        "nrl-01-001": {avgScore: 1, avgScoreTipCount: 20, pctTipD: 0.1},
      },
    },
    legacyStats: {
      paid: {
        "nrl-01-001": {avgScore: 2.123, avgScoreTipCount: 10, pctTipD: 0.4},
      },
      free: {
        "nrl-01-001": {avgScore: 1, avgScoreTipCount: 20, pctTipD: 0.1},
      },
    },
    fields: ["avgScore", "avgScoreTipCount", "pctTipD"],
  });

  assert.equal(comparison.totals.cohortsCompared, 2);
  assert.equal(comparison.totals.matches, 2);
  assert.equal(comparison.totals.mismatches, 0);
  assert.equal(hasGameStatsComparisonFailures(comparison), false);
});

test("compareGameStats reports field mismatches and missing games", () => {
  const comparison = compareGameStats({
    backendStats: {
      paid: {
        "backend-only": {avgScore: 1},
        "nrl-01-001": {avgScore: 2, avgScoreTipCount: 10},
      },
      free: {},
    },
    legacyStats: {
      paid: {
        "legacy-only": {avgScore: 1},
        "nrl-01-001": {avgScore: 3, avgScoreTipCount: 10},
      },
      free: {},
    },
    cohort: "paid",
    fields: ["avgScore", "avgScoreTipCount"],
  });

  assert.equal(comparison.totals.matches, 0);
  assert.equal(comparison.totals.mismatches, 1);
  assert.deepEqual(comparison.cohorts[0].missingLegacyGames, ["backend-only"]);
  assert.deepEqual(comparison.cohorts[0].missingBackendGames, ["legacy-only"]);
  assert.deepEqual(comparison.cohorts[0].mismatches[0], {
    gameKey: "nrl-01-001",
    fields: {
      avgScore: {
        backend: 2,
        legacy: 3,
      },
    },
  });
  assert.equal(hasGameStatsComparisonFailures(comparison), true);
});

test("compareGameStats limits comparison to one game", () => {
  const comparison = compareGameStats({
    backendStats: {
      paid: {
        "nrl-01-001": {avgScore: 2},
        "nrl-01-002": {avgScore: 4},
      },
    },
    legacyStats: {
      paid: {
        "nrl-01-001": {avgScore: 2},
        "nrl-01-002": {avgScore: 0},
      },
    },
    cohort: "paid",
    gameKey: "nrl-01-001",
    fields: ["avgScore"],
  });

  assert.equal(comparison.totals.matches, 1);
  assert.equal(comparison.totals.mismatches, 0);
});

test("formatGameStatsComparisonReport describes cohort mapping", () => {
  const comparison = compareGameStats({
    backendStats: {
      paid: {
        "nrl-01-001": {avgScore: 2},
      },
    },
    legacyStats: {
      paid: {
        "nrl-01-001": {avgScore: 3},
      },
    },
    cohort: "paid",
    fields: ["avgScore"],
  });

  const report = formatGameStatsComparisonReport(comparison, {
    compKey: "comp2026",
    cohort: "paid",
    maxMismatches: 20,
  });

  assert.match(report, /Backend game stats comparison/);
  assert.match(report, /Cohort paid/);
  assert.match(report, /avgScore backend=2 v3=3/);
});

test("parseArgs supports game-stats options", () => {
  const options = parseArgs(
    [
      "--comp-key",
      "comp2026",
      "--type",
      "game-stats",
      "--cohort",
      "paid",
      "--game-key",
      "nrl-01-001",
    ],
    {},
  );

  assert.equal(options.type, "game-stats");
  assert.equal(options.cohort, "paid");
  assert.equal(options.gameKey, "nrl-01-001");
  assert.deepEqual(options.fields, [
    "pctTipA",
    "pctTipB",
    "pctTipC",
    "pctTipD",
    "pctTipE",
    "avgScore",
    "avgScoreTipCount",
  ]);
});
