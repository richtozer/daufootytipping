# Design: a table component sized to this app

## Status

Proposed, not started. Written 27 September 2026 after two `data_table_2`
defects were worked around rather than fixed. Implementation is a separate
piece of work with its own review.

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
