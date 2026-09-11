import {strict as assert} from "node:assert";
import {test} from "node:test";
import {
  isGameWithinCompCutoff,
  parseFirebaseUtcTimestamp,
} from "./game_comp_eligibility";

test("AFL games after the AFL comp cutoff are excluded", () => {
  assert.equal(
    isGameWithinCompCutoff(
      "afl-24-001",
      "2026-09-01 10:00:00Z",
      {
        aflRegularCompEndDateUTC: "2026-08-31T23:59:59Z",
        nrlRegularCompEndDateUTC: "2026-10-04T23:59:59Z",
      },
    ),
    false,
  );
});

test("NRL games after the NRL comp cutoff are excluded", () => {
  assert.equal(
    isGameWithinCompCutoff(
      "nrl-28-001",
      "2026-10-05 10:00:00Z",
      {
        aflRegularCompEndDateUTC: "2026-08-31T23:59:59Z",
        nrlRegularCompEndDateUTC: "2026-10-04T23:59:59Z",
      },
    ),
    false,
  );
});

test("games at or before their league cutoff are included", () => {
  const cutoffs = {
    aflRegularCompEndDateUTC: "2026-08-31T23:59:59Z",
    nrlRegularCompEndDateUTC: "2026-10-04T23:59:59Z",
  };

  assert.equal(
    isGameWithinCompCutoff(
      "afl-24-001",
      "2026-08-31 23:59:59Z",
      cutoffs,
    ),
    true,
  );
  assert.equal(
    isGameWithinCompCutoff(
      "nrl-28-001",
      "2026-10-04 20:00:00Z",
      cutoffs,
    ),
    true,
  );
});

test("games are included when their league cutoff is absent", () => {
  assert.equal(
    isGameWithinCompCutoff(
      "afl-24-001",
      "2026-09-01 10:00:00Z",
      {nrlRegularCompEndDateUTC: "2026-10-04T23:59:59Z"},
    ),
    true,
  );
});

test("zone-less Firebase timestamps are parsed as UTC", () => {
  assert.equal(
    parseFirebaseUtcTimestamp("2026-09-07T00:00:00.000"),
    Date.parse("2026-09-07T00:00:00.000Z"),
  );
});
