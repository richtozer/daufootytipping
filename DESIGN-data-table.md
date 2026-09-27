# Design: a table component sized to this app

## Status

AppTable and its first production caller, the round leaderboard, are implemented
on 27 September 2026. Written after two `data_table_2` defects were worked around
rather than fixed. Native iPad/Duo review remains outstanding before converting
the remaining seven tables.

## Why not keep `data_table_2`, and why not fork it

Two defects surfaced during tablet testing:

- **Frozen columns open a gap.** `_calculateDataColumnSizes` subtracts a fixed
  column's width from the budget and then divides the remainder by
  `columns.length` — the fixed column included. Roughly one column's width is
  allocated to nobody. See `data_table_2-3.0.0/lib/src/data_table_2.dart:1378`.
  Worked around in `9f16e4f` by disabling freezing, which cost the frozen name
  column on every table.
- **The vertical scrollbar overlays the last column.** Worked around in
  `e308860` with a 14px edge margin on all nine tables.

Neither workaround is satisfying, and two standing wants are out of reach
entirely: **flexible column widths on narrow displays**, and **vertical column
labels** to keep dense tables tight.

Forking is the wrong shape of answer. The package is 3,698 lines, of which
`async_paginated_data_table_2.dart`, `paginated_data_table_2.dart` and
`data_table_2_resizable.dart` are 1,840 that this app never touches. A fork
means owning all of it, and re-merging upstream forever, to change perhaps
fifty lines.

The deeper reason is that `data_table_2` applies fixed size ratios, while the
rest of this app now measures its content and picks a layout from the result.
`TipsCardLayout` does exactly that for the tips cards. A table built the same
way gets flexible widths and vertical labels as natural consequences rather
than as features fought for.

## What the app actually uses

Eight tables, all in `lib/pages/user_home/`:

| File | Notes |
| --- | --- |
| `user_home_stats_compleaderboard.dart` | widest, 9 columns |
| `user_home_stats_roundleaderboard.dart` | |
| `user_home_stats_roundwinners.dart` | froze 2 columns, not 1 |
| `user_home_stats_roundpointsfortipper.dart` | |
| `user_home_stats_roundgamescoresfortipper.dart` | |
| `user_home_stats_roundmissingtipsstats.dart` | |
| `user_home_team_games_history_page.dart` | |
| `user_home_league_ladder_historical.dart` | |

Features in use: a sticky heading row, sortable columns with a sort indicator,
row tap, per-row background colour (highlighting the current tipper), cell
widgets rather than plain text (avatars, icons, coloured deltas), a horizontal
scroll for narrow displays, a minimum width, and a numeric right-alignment.

**Not used, and not to be built:** pagination, async data sources, resizable
columns, checkbox selection, row selection state.

`ColumnSize` appears twice in the whole codebase; `fixedWidth` sixteen times.
The sizing model is barely exercised, which is another sign the general
component is the wrong tool.

## The design

A measurement pass, then a dumb render — the same shape as `TipsCardLayout`.

1. **Measure** every column's content with `TextPainter` at the current
   `TextScaler`: the heading, and the widest cell in that column. Non-text
   cells declare an intrinsic width.
2. **Decide** from the available width:
   - everything fits → lay out at natural widths, distributing slack
   - does not fit → in order: shrink padding, wrap or rotate headings, elide
     the widest text column, and only then scroll horizontally
3. **Render** a `Table` or `CustomMultiChildLayout` from the resolved widths.

### Requirements the current component cannot meet

- **Flexible widths on narrow displays.** Columns size to their content, not to
  a fixed ratio. A column of single digits should not claim the same share as
  one holding names.
- **Vertical headings.** A `RotatedBox` heading for narrow numeric columns, so
  a column of two-digit values is as wide as its values, not as its label. This
  should be chosen by the measurement, not set by hand per table.
- **Frozen first column that works.** Lay out the frozen column and the
  scrolling remainder from one width budget, so the two cannot disagree — the
  defect above cannot occur by construction.
- **Scrollbar in its own lane.** Reserve its width in the layout rather than
  letting it overlay the last column.

### API sketch

```dart
AppTable(
  columns: [
    AppColumn.text('Name', grow: true, sortable: true),
    AppColumn.numeric('Rank', sortable: true),
    AppColumn.numeric('Total', sortable: true),
  ],
  rows: [for (final e in entries) AppRow(cells: [...], onTap: ..., colour: ...)],
  frozenLeading: 1,
  sort: AppSort(column: 1, ascending: true),
  onSort: (column, ascending) => ...,
)
```

Keep the sizing decisions inside the component. A caller saying "this column is
140 wide" is what produced the current problems.

## Migration

One table at a time, each its own commit, `development` as usual.

1. Build `AppTable` with unit tests for the measurement, no callers yet.
2. Convert `user_home_stats_roundleaderboard.dart` first — mid-sized, few
   custom cells. Verify on iPad and iPhone Duo, portrait and landscape.
3. Convert `user_home_stats_compleaderboard.dart` — the widest, 9 columns, the
   one where the gap and scrollbar defects were found.
4. The remaining six.
5. Remove `data_table_2` from `pubspec.yaml`.

Do not convert them in one change. The tables differ more than they look.

## Testing

- **Unit tests on the measurement**, as with `TipsCardLayout`: a pure function
  from (columns, rows, width, text scale) to resolved widths. These are the
  tests that matter and they need no widget tree.
- **Absolute-width assertions**: a column of two-digit numbers is narrow at
  360px; headings rotate below a stated width; the frozen column and the
  scrolling remainder sum to the available width exactly.
- **Goldens** at 360, 768 and 1280, at text scale 1.0 and 1.5.

Note that the existing list goldens render `AdaptiveTipsPrototypeApp`, the dev
harness, not production widgets — so they guard less than they appear to. Do
not assume a passing golden covers a production table.

## Out of scope

Leave the bottom navigation padding, the sticky header's translucency, and the
`lib/dev/` prototype harness alone. They are separate threads.

## Component checkpoint

Import `lib/widgets/app_table/app_table.dart`. This exports the models and the
pure `AppTableLayout.measure` function alongside the widget. Place the widget
in a bounded area (normally `Expanded`). A rendered example:

```dart
AppTable(
  columns: const [
    AppColumn.text('Name', grow: true, sortable: true),
    AppColumn.numeric('Points', sortable: true),
  ],
  rows: const [
    AppRow(cells: [AppCell.text('Alex'), AppCell.text('42')]),
  ],
  frozenLeading: 1,
  sort: const AppSort(column: 1, ascending: false),
  onSort: (column, ascending) { /* update caller-owned sorting */ },
)
```

`AppCell.text` optionally accepts a style and a leading widget with its
declared `leadingSize`, for avatars or navigation icons. `AppCell.widget`
requires an `intrinsicSize` and a semantic label; its declared size must match
the widget at the current text scale. Custom widgets are not silently shrunk.
Truncated text retains its full label through tooltips and semantics. Sort
direction labels can be localized through widget arguments.

The measurement pass tries natural widths, compact padding, wrapped/rotated
headings and text elision, then horizontal scrolling. Remaining width goes to
`grow` columns, or evenly to all columns when none grow. Numeric cell text is
not shortened to make a table fit. Sort indicators keep an upright arrow when
their heading text rotates.

The renderer uses explicit-width rows instead of an intrinsically sized Table.
One horizontal viewport contains a pinned heading and a lazy vertical list.
Frozen cells counteract the horizontal offset within each row: they share the
same widths and vertical position as the scrolling cells, without synchronizing
separate vertical lists. A 14 px trailing lane reserves the vertical scrollbar;
horizontal scrolling adds a separate bottom lane. No package is added.

Two edge policies to review before migration:

- If freezing the requested columns would leave less than 48 px for the
  scrolling region, the effective frozen count is reduced. Columns remain
  accessible through horizontal scrolling.
- In a very short viewport with large text, the heading retains a pinned
  viewport but becomes vertically scrollable itself so rows remain accessible.
  Text is not reduced to fit.

Checks are under `test/widgets/app_table_*`: pure measurement assertions,
sorting and row taps, frozen rows during both-axis scrolling, scrollbar lanes,
full-name semantics, custom cell footprints, empty data, RTL/resize, short
landscape panes and lazy row construction. Six goldens render AppTable itself
at 360/768/1280 px and 1.0/1.5 text scale. They are component baselines, not
coverage of the future migrated production pages. No native-device validation
or performance benchmark is claimed by this checkpoint.

Validation on 27 September: `flutter analyze --no-pub` reports no issues;
`flutter test --no-pub` passes all 484 tests, including 21 new table checks.
The existing production pages and the `data_table_2` dependency are unchanged.

### Step 1 review follow-up

Content extraction now lives in `AppTableMetrics.extract`: it measures all
cells once and retains per-column maxima, minimum widths, row height, heading
sizes and individual cell footprints. `AppTableLayout.resolve` accepts those
metrics and a viewport width without reading any rows. The original `measure`
entry point remains a convenience for one-off pure measurements.

AppTable owns a single-entry `AppTableMeasurementCache`, keyed by row-list and
column-list identity, text scaler, direction, and heading/body styles. Callers
must replace lists when their contents change and retain them for unrelated
rebuilds. In-place mutation is not supported. Recreating lists on every parent
build remains correct but forfeits caching; migration should preserve stable
lists between data changes. Row taps, colours and sorting remain caller-owned.
Tests assert cache reuse/invalidation and zero row reads during width resolution;
no release-mode frame-time claim is made.

Rotated sortable headings now reserve at least the sort icon width. Body text
gets a tooltip only when its measured footprint exceeds the allocated space;
custom icon/widget cells retain descriptive tooltips. Short tables do not
request a persistent vertical thumb. The two visual row surfaces share one
accessible tap action and one keyboard focus target per row.

Review follow-up validation: analysis is clean and all 490 tests pass, including
27 table checks. All six component goldens still match without regeneration.

### Step 2: round leaderboard

`StatRoundLeaderboard` now uses AppTable with a frozen Name column and measured
numeric columns. Existing sorting rules, current-tipper highlighting, avatar
Heroes, back navigation and live-score warning remain. Tapping anywhere in a
row opens that tipper's round details. Changing the round on retained page state
reloads its data.

The caller retains its column and row lists across resize and unchanged stats
notifications. It compares an ordered snapshot of displayed primitive values,
including name/photo and round, so changes to mutable scoring models invalidate
the rows. This small comparison still runs on rebuild; expensive text measurement
is reused when values, selection and highlight colour are unchanged. Changed
data correctly triggers measurement again.

Six additional goldens render the production round leaderboard at widths
360/768/1280 and text scales 1.0/1.5. At 360, these fixtures have table headings
approximately 92/116 px tall. At 1.5 the UPS column needs horizontal scrolling;
the Name column remains frozen. These measurements differ from the component
fixture because heading labels and available widths differ. This page has its
own round title above the table; it does not embed the Tips list's sticky round
header.

Page tests cover sorting across notifications, changed and unchanged data,
resize cache reuse, selection highlighting, whole-row navigation, round changes,
and frozen names/pinned headings during scrolling. Native iPad and iPhone Duo
portrait/landscape usability review remains a manual checkpoint, especially the
vertical space consumed by headings. No device validation is claimed.

Validation: analysis clean; full suite 500 passing, followed by 20 passing
page checks after adding the final frozen-column/pinned-heading assertion.
The other seven callers and the package dependency remain unchanged.
