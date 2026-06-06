import assert from "node:assert/strict";
import test from "node:test";

import {
  compareRoundStats,
  formatComparisonReport,
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
