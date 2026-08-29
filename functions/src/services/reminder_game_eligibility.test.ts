import {strict as assert} from "node:assert";
import {test} from "node:test";
import {isReminderGameWithinCompCutoff} from
  "./reminder_game_eligibility";

test("AFL reminders exclude games after the AFL comp cutoff", () => {
  assert.equal(
    isReminderGameWithinCompCutoff(
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

test("NRL reminders exclude games after the NRL comp cutoff", () => {
  assert.equal(
    isReminderGameWithinCompCutoff(
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

test("reminders include games at or before their league cutoff", () => {
  const cutoffs = {
    aflRegularCompEndDateUTC: "2026-08-31T23:59:59Z",
    nrlRegularCompEndDateUTC: "2026-10-04T23:59:59Z",
  };

  assert.equal(
    isReminderGameWithinCompCutoff(
      "afl-24-001",
      "2026-08-31 23:59:59Z",
      cutoffs,
    ),
    true,
  );
  assert.equal(
    isReminderGameWithinCompCutoff(
      "nrl-28-001",
      "2026-10-04 20:00:00Z",
      cutoffs,
    ),
    true,
  );
});

test("reminders include games when their league cutoff is absent", () => {
  assert.equal(
    isReminderGameWithinCompCutoff(
      "afl-24-001",
      "2026-09-01 10:00:00Z",
      {nrlRegularCompEndDateUTC: "2026-10-04T23:59:59Z"},
    ),
    true,
  );
});
