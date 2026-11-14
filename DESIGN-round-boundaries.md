# Round boundaries: remove the editable round end date

Status: plan, not implemented. Agreed in discussion 2026-11-13 (off-season, so
the functions side ships with the client work).

## Goal

Remove the admin-editable round end date. Which round a game belongs to comes
from the round start dates alone. `roundEndDate` stays in the database as a
value that is always derived from the round's games, because:

- clients on `main` parse it unconditionally (`DAURound.fromJson`,
  `DateTime.parse(data[roundEndDateKey])`) and would crash without it;
- `app_badge.ts` skips any round without a `roundEndDate` string, and uses it to
  keep the 15-minute badge cron quiet between rounds;
- `latestsCompletedRoundNumber` and the badge calculation need "when this
  round's games finish", which is not the same as "when the next round starts".

## Rules

1. **Scored** means both official scores are present
   (`homeTeamScore != null && awayTeamScore != null`), not
   `GameState.startedResultKnown`, which also waits 2h after kickoff.
2. **A scored game is fixed.** Its kickoff cannot change, an admin start edit
   cannot move it to another round, and an admin cannot set a league cutoff
   earlier than the latest scored game in that league.
3. **A kickoff is frozen once it enters the grace window.** If the stored kickoff
   is at or before `now + maxTipGracePeriodSeconds` (15 minutes), fixture import
   keeps the stored kickoff (`DateUtc` and `DateUtcEpochMs`). Every other field
   still updates. Tipping closes at kickoff plus a grace period of up to 900s,
   so freezing at `now + maxTipGracePeriodSeconds` stops a late postponement
   during an import from reopening tipping after tips are visible. A game
   postponed after that point stays closed in its original round and is scored
   there when the result arrives.
4. **Everything else can change.** Unstarted games can be rescheduled. A
   started, unscored game can change round through an admin start edit; any
   live-score points follow it because the full rescore runs afterwards
   (`replaceRoundStats`, `allowEmptyRound`).
5. **A fully scored round keeps its end, capped before the next round.** Import
   does not recalculate it from its games, but still caps its stored end at one
   second before the next round's start (in case it became fully scored when an
   admin start edit moved its last unscored game into the next round). The
   next round's start is no longer checked against that end: the scored-game
   check and the cap cover it (removed with DESIGN-round-start-dates.md).

Showing other tippers' tips needs no change: tips are shown after tipping
closes, so a real kickoff running late cannot leak anything. The only leak is
a closed game reopening, which rule 3 prevents.

## Steps

Each step is written test-first. Regression tests are run against the current
code first to show they fail.

### 1. Assigning games to rounds (`packages/dau_shared`)

- One shared lookup: a game's round is the round with the latest effective
  start at or before its kickoff.
- For a comp's own games, the final round has no upper bound. The per-league
  cutoffs still filter games, including when only one league has a cutoff.
- `findTipAcrossCompetitions` / `_gameBelongsToComp`
  (`lib/view_models/tips_viewmodel.dart`) bound the final round by its stored
  end, so last season's final round does not claim this season's games.
- `Game.getDAURound(comp)` uses the lookup. Delete `Game.isGameInRound` and
  `_isDateInRound`, and move the callers:
  - `lib/view_models/games_viewmodel.dart` (`getGamesForRound`)
  - `functions_dart/bin/server.dart` (round linking before the badge count)
  - `functions_dart/bin/demo_stats.dart`

### 2. Fixture import (`functions_dart/bin/server.dart`, `FixtureImportApplier`)

- Read the existing games before `buildGameUpdates` and apply the kickoff
  freeze (rule 3). Log every ignored kickoff change.
- On every import (not only when the rounds are first created), recalculate
  each round's `roundEndDate` from the games as stored after the freeze, not
  from the raw feed:
  - end = latest assigned kickoff + 3h, capped at one second before the next
    round's start, so clients on `main` (inclusive start-to-end per round)
    never show a game in two rounds;
  - a round with no games gets end = start;
  - a fully scored round keeps its stored end, still capped at one second
    before the next round's start (rule 5).
- Write `roundEndDate` only where it changed.
- The full rescore continues to run after every import.

### 3. Badge

- Add up outstanding tips across every round whose badge window contains now,
  instead of taking the first matching round, on the client
  (`DAUCompsViewModel.appBadgeOutstandingTipsCount`) and the server
  (`server.dart` badge count). A postponed game can extend a round into the
  next round's 48h activation window; summing handles both rounds correctly.
- `functions/src/app_badge.ts`:
  - skip rounds whose end is at or before their start, so an empty round does
    not open a 48h cron window;
  - use the override start when there is one, not `Math.min(stored, override)`;
  - drop the `adminOverrideRoundEndDate` handling, keep reading `roundEndDate`.

### 4. Admin

- Remove `adminOverrideRoundEndDate`, `adminOverrideRoundEndDateKey` and
  `DAURound.getRoundEndDate()`; callers read `lastGameKickOffUTC` directly
  (`appBadgeRoundForTime`, the snapshot applier, the save path).
- Remove the end-date column from `AdminDaucompsEditRoundsTable` and the
  `isStartDate` branch in `admin_daucomps_edit.dart`.
- Validate start edits: each effective start strictly after the previous
  round's; no scored game changes round. Round numbers are unchanged.
- Validate cutoff edits: not earlier than the latest scored game in that league.
- Keep the in-memory `_recalculateGameCounts` so the NRL/AFL counts and the
  warnings update before saving.
- Fix `_updateSaveButtonState`, which works only from the text fields, so a
  text edit after a round date change no longer disables Save.
- Admin save re-runs start and cutoff validation against in-memory games
  before writing only the start overrides and cutoffs. When round starts or
  cutoffs changed, it then runs the cloud fixture download
  (`getNetworkFixtureData`), which recalculates the ends from the comp's full
  fixture list and rescores; it shows the download message on success and
  reports a failed download separately from the save.
- **Split-round warning.**
  - A pure function in `lib/services`: for each league round (league +
    `fixtureRoundNumber`), the home DAU round is the one holding most of its
    games (an even split picks the earlier DAU round). List every game in that
    league round that is in a different DAU round, has not started, and is
    within the league cutoff.
  - Computed wherever `unassignedGames` is computed
    (`DAUCompsViewModel`, rounds linking) and exposed as `splitRoundGames`.
  - `AdminDaucompsEditWarning` takes a title, a message and a list of games, so
    both warnings use one widget: red for unassigned games, amber for split
    games. Each split entry shows the game, its DAU round and its home DAU
    round. New text goes into constants.
  - Why: under the new rule a game moved earlier than its round's start joins
    the previous round silently instead of showing as unassigned. The admin
    fixes it by moving the round start back.

### 5. Tests

- A game rescheduled into the gap between two rounds lands in the earlier round.
- A postponed final-round game extends the final round, with and without cutoffs.
- Old (inclusive per-round) and new assignment rules agree on the same round
  data, including rounds close together, exact boundaries and leftover overrides.
- Two overlapping badge windows: counts before and after the postponed kickoff,
  matching between client and server.
- A kickoff change after the stored kickoff has passed is ignored, including a
  new time inside the grace period.
- A game scored less than 2h after kickoff counts as scored.
- Admin start and cutoff edits are rejected across scored games; a start edit
  across a started, unscored game is allowed.
- A live-scored game moved between rounds is rescored in both rounds.
- An empty round opens no badge window.
- The save button stays enabled after a date change followed by a text edit.
- Split-round warning: a game moved earlier is flagged; a whole league round in
  one DAU round is not; a started game is not; an even split names the earlier
  round; a game past the cutoff is not; widget test with both warnings showing,
  and the split warning clearing once the start is moved back.
- Historical tip lookup with the final-round bound and per-league cutoffs.
- Snapshot updates that change only the end, and fixture and round updates
  arriving in either order.

Existing tests to update: `test/models/game_test.dart` (boundary test),
`test/models/dauround_test.dart` (override cases),
`packages/dau_shared/test/outstanding_tips_calculator_test.dart`,
`test/pages/admin_daucomps/admin_daucomps_edit_rounds_table_test.dart`,
`functions/src/app_badge.test.ts`, `functions_dart/test/server_test.dart`.

### 6. Release

1. `flutter analyze`, `flutter test`, `(cd packages/dau_shared && dart test)`,
   `(cd functions_dart && dart test)`, `npm --prefix functions test`,
   `npm --prefix rules_test run test:dart`,
   `scripts/test-client-integration.sh`.
2. Deploy both function codebases first, so clients on `main` get the
   recalculated ends.
3. Release the client.

Leave existing `adminOverrideRoundEndDate` values in place. New functions and
new clients ignore them, but clients on `main` still use them, and fully
scored rounds keep their stored `roundEndDate`. In the 2026 comp, rounds 23
and 25 have override ends covering a game that kicked off after the stored end
(`afl-22-185`, `afl-24-207`). Deleting those overrides would leave both games
unassigned on old clients.

## Not changing

- The 3h round padding and the 6h completed-round leeway.
- Round clustering when a comp is created (`CombinedRoundsService`).
- The per-league cutoff filters.
- The field name `lastGameKickOffUTC` (it holds kickoff + 3h); renaming it
  touches about 60 test files.
