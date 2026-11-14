# Round start dates: dates only, at 0:00 UTC

Status: plan, not implemented. Builds on DESIGN-round-boundaries.md, where a
game belongs to the round with the latest start at or before its kickoff.

## Goal

A round starts at 0:00 UTC on a date. The time of day plays no part in grouping
games into rounds, and the admin edits a date, never a time.

## Evidence

Replaying the production 2025 and 2026 comps (read-only) with every round start
rounded down to 0:00 UTC on its date:

| Comp | Rounds | Games that change round | UTC dates holding two rounds | Kickoffs (UTC) |
|---|---|---|---|---|
| 2025 | 34 | 0 | none | 00:00 to 10:35 |
| 2026 | 27 | 0 | none | 01:30 to 10:30 |

Every game, including the Las Vegas games, kicks off within one UTC day, and no
round shares a UTC date with the next round.

## Rules

1. **A round's start is a UTC date.** The effective start is 0:00 UTC on the UTC
   date of the admin override if there is one, otherwise of the stored
   `roundStartDate`. Any time stored with either value is ignored.
2. **Overrides are saved as 0:00 UTC.** The admin picks a date; the app writes
   `YYYY-MM-DDT00:00:00.000Z`.
3. **New comps store 0:00 UTC starts.** When rounds are first built, each start is
   0:00 UTC on the UTC date of the round's first kickoff (replacing "first
   kickoff minus 3 hours"). The end keeps its last kickoff + 3h padding.
4. **Two rounds cannot share a date.** Starts must be on strictly increasing
   dates, which the existing "start must be after the previous round's start"
   check already gives. A game rescheduled onto the date the next round starts
   joins the next round; the split-round warning shows it.

Unchanged: the kickoff freeze, end recalculation and capping, scored-game
protection and the badge sum from DESIGN-round-boundaries.md. They read the
start through `getRoundStartDate()`, so they follow rule 1 with no change of
their own.

## Steps

Each step is written test-first.

### 1. One definition of the start (`packages/dau_shared`)

- `DAURound.getRoundStartDate()` returns `DateTime.utc(y, m, d)` from the UTC
  date of `adminOverrideRoundStartDate ?? firstGameKickOffUTC`. Document that it
  is a date boundary, not a kickoff.
- No caller changes: `Game.roundForKickoff`, `recalculateRoundEndDates`,
  `OutstandingTipsCalculator`, `DaucompsRoundsParser.applyCutoffFilter` and the
  kickoff refresh scheduler all go through it.
- `RoundsLinkingService.validateRoundStartDateEdit`: delete the check that a
  start cannot be on or before a fully scored previous round's
  `lastGameKickOffUTC`. That end carries +3h padding, so a late game could push
  it past midnight and block a valid next-day start. The check is also
  redundant: the scored-game check already stops any scored game changing
  round, and import caps a fully scored round's end one second before the next
  start.

### 2. Comp creation (`CombinedRoundsService`, `server.dart`)

- `combineGameGroupsIntoRounds` sets `firstGameKickOffUTC` to 0:00 UTC on the
  first kickoff's UTC date instead of subtracting 3 hours.
- Clustering compares UTC dates, not raw times: a league group joins the
  current round when its first kickoff's UTC date is on or before the UTC date
  of the round's last kickoff. Comparing raw times could leave two rounds on
  one date (one group ending 02:00Z, the next starting 09:00Z the same day),
  so both would start at the same 0:00 UTC and the later round would take the
  earlier round's games.
- `server.dart` writes that value as the round's `roundStartDate`.

### 3. Badge job (`functions/src/app_badge.ts`)

- Round the effective start (override, else stored) down to 0:00 UTC with the
  same rule as step 1, before working out the 48h activation and the empty-round
  check.

### 4. Admin page

- Replace `DateTimePickerField` with a date-only field: `showDatePicker` only,
  no `showTimePicker`. Pass `round.getRoundStartDate()` (a UTC value) as
  `initialDate` with no `.toLocal()`, so the picker shows the UTC calendar date,
  and return `DateTime.utc(picked.year, picked.month, picked.day)`.
- Picking the date a round already starts on changes nothing: ignore a
  selection equal to `round.getRoundStartDate()`, so the row does not turn bold
  and Save does not write an override or run a download and rescore.
- Decide whether round starts changed by comparing effective starts
  (`getRoundStartDate()`), not raw override values, in `_updateSaveButtonState`
  and `processAndSaveDauComp`. A legacy timed override and the same date at
  0:00 UTC count as unchanged.
- Replace `formatRoundDateTime` with a date-only formatter that calls
  `.toUtc()` before formatting, for example `Thu 12/11`, so the date is right
  in any device time zone. Delete the time formatting.
- Show every round in the admin table, including rounds with no games (0 and 0
  in the counts). Today rounds without games are hidden, so a whole-day edit
  that empties a round makes its row vanish and it cannot be edited back.
- Rename the rounds table heading from "First kickoff" to
  "Round Start (UTC)", and update the information dialog to say rounds run
  from one round's start date (0:00 UTC) to the next.
- The save path is unchanged apart from writing the UTC-midnight value it is
  given.

### 5. Tests

- `getRoundStartDate()`: a stored start and an override with a time (and a
  local, non-UTC `DateTime`) both return 0:00 UTC on the right date.
- `roundForKickoff`: a kickoff at 0:00 UTC on the start date belongs to the new
  round; 23:59:59 the day before belongs to the previous round.
- `CombinedRoundsService`: a first kickoff at 01:30 UTC gives a start at 0:00
  UTC that same date, not the previous date; two league groups on the same UTC
  date join one round; generated rounds have strictly increasing
  `getRoundStartDate()` values.
- `validateRoundStartDateEdit`: a fully scored previous round whose padded end
  crosses midnight does not block a next-day start; moving a start across a
  scored game is still rejected.
- Admin page: picking the current date leaves the round unbolded and Save
  disabled; a round emptied by an edit stays in the table.
- `app_badge.ts`: a start or override with a time activates 48h before 0:00 UTC
  on its date; client and server badge counts agree.
- Admin date field (widget test): no time picker opens; picking a date saves
  0:00 UTC on that date; the table shows the UTC date under the
  "Round Start (UTC)" heading.
- Existing tests that build rounds with timed starts: update the expected
  boundaries where a test relied on the time of day.

### 6. Release

1. Run the usual checks: `flutter analyze`, `flutter test`, the `dau_shared`,
   `functions_dart` and `functions` tests, `npm --prefix rules_test run test:dart`
   and `scripts/test-client-integration.sh`.
2. Deploy both function codebases, then release the client. Ship the functions
   together with the round-boundaries change (not yet deployed), so no empty
   round is ever stored with a timed end equal to a timed start. If they ship
   separately, run a fixture download on each live comp after this deploy so
   empty-round ends are rewritten at 0:00 UTC.

No data change is needed. Clients on `main` keep using the stored timestamps.
New overrides and new comps store 0:00 UTC, which old clients read the same
way. Existing timed starts differ only for a game on a round's first UTC date
before the stored time, and the replay above found none.

## Not changing

- Stored field names (`roundStartDate`, `adminOverrideRoundStartDate`,
  `firstGameKickOffUTC`); renaming them would touch the database and many tests.
- The demo generator, which assigns its own games before the app reads them.
- Round end dates, which keep their times (last kickoff + 3h, capped one second
  before the next round's start).
