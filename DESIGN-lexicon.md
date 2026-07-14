# Design: Product Lexicon

## Status
- Draft
- This document defines the canonical user-facing terminology for DAU Footy Tipping.
- It is intentionally separate from model names and internal variable names.

## Summary
The app currently uses several overlapping terms for the same concepts.

Some of that variation is acceptable when it reflects different contexts, but a few terms leak into user-facing copy inconsistently. The clearest example is the alias dialog calling the user a `player` while the rest of the app uses `tipper`.

This document sets a default lexicon so future UI, help content, and docs can use the same words consistently.

## Sources Reviewed
- User-facing app copy under `lib/pages/` and `lib/widgets/`
- Linked Google Docs:
  - Help: https://docs.google.com/document/d/e/2PACX-1vTOEzPdzyfKuDJJoyPz5ge4Z-dlwFQUNBilzguZZloxCqvKNp214Pp_-bxWTFY_MPmit1iZrhUQKpzm/pub
  - FAQ: https://docs.google.com/document/d/e/2PACX-1vRAHQvWC-CvaeAVa7rPh7YCZAWb5nbzn7oOBt_qbyeXh4HWg96srmig13tz86h0PgOLGP9YnqGElRwk/pub

## Goals
- Use one preferred term for each user-facing concept.
- Keep internal shorthand out of user copy unless it is clearly intentional.
- Make support docs match the app's vocabulary.
- Reduce ambiguity where the same word currently means two different things.

## Non-Goals
- Renaming data models, database keys, or code symbols.
- Removing domain-specific shorthand from internal code.
- Forcing identical wording in every context when the meaning is different.

## Canonical Terms

| Concept | Preferred term | Allowed alternatives | Avoid in user-facing copy | Notes |
| --- | --- | --- | --- | --- |
| Person using the app | `tipper` | `tipper alias` when referring to the display name | `player`, `user` | `tipper` is already dominant in the app and docs. |
| Display name | `tipper alias` | `alias`, `name` in narrow contexts | `player name` | Use when the value is the visible competition nickname. |
| Contest | `competition` | `comp` only in admin/internal contexts | `comp` in general user copy | Keep user-facing language explicit. |
| Individual tipping event | `game` | `match` only where a sentence specifically needs a matchup sense | `fixture` in generic user copy | `game` is the current default in the tips flow and docs. |
| Weekly grouping | `round` | `week` only in explanatory prose | `matchday` | `round` is already the app's core unit. |
| Prediction | `tip` | `pick` in explanatory prose if needed | `guess` | This is the app's established action term. |
| Rankings of tippers | `leaderboard` | `comp leaderboard` in page titles if needed | `table` | Use this for tipper rankings and round rankings. |
| Team rankings | `ladder` | `premiership ladder` when domain-specific | `leaderboard` for team rankings | Keep `ladder` distinct from person ranking tables. |
| Analytics / user progress area | `stats` | `scoring` only when describing calculations | `results` as a page name | `Stats` is the current tab label. |
| Scoring rules and calculations | `scoring` | `points system` in help text | `stats` when referring to the calculations themselves | Use `scoring` for the math, not the whole section. |
| Start time of a game | `kickoff` | `kick off` in sentence prose | `start` when talking about game timing | Pick one spelling and use it consistently. |
| Authentication action | `sign in` | `log in` only if a legacy flow requires it | `login`, `logon` in user copy | Prefer `sign in` in the app. |
| Support content | `Help` / `FAQ` | none | `support` as a page label | The existing buttons are already aligned here. |

## Current Inconsistencies

### 1. `player` appears only in the alias dialog
This is the clearest lexicon mismatch.

- `lib/pages/user_auth/user_auth.dart` uses `other players will see you as`
- `lib/pages/user_home/user_home_profile.dart` uses the same wording

Recommendation:
- Replace `player` with `tipper` in that copy.

### 2. `stats` and `scoring` are overlapping but not identical
The app currently uses `Stats` as the primary section label, while many screens and docs talk about scoring, points, and live score data.

This is acceptable only if the distinction stays deliberate:
- `stats` = the section the user visits to see rankings, summaries, and analytics
- `scoring` = the calculation system that produces points and rankings

Places where the distinction matters:
- `lib/pages/user_home/user_home_stats.dart`
- `lib/widgets/live_scores_warning_card.dart`
- `lib/pages/user_home/user_home_tips_scoringtile.dart`
- the Help / FAQ docs

### 3. `game`, `match`, and `fixture` are mixed
The tipping UI mostly uses `game`, but there are still places where `match` or `fixture` appear.

Recommended treatment:
- `game` for user-facing tipping flow
- `match` only when a sentence is specifically about a matchup or comparative stats
- `fixture` only for backend/admin/infrastructure language

Relevant examples:
- `lib/pages/user_home/user_home_tips_gameinfo.dart`
- `lib/pages/user_home/user_home_league_ladder_page.dart`
- `lib/pages/user_home/user_home_team_games_history_page.dart`

### 4. `competition` and `comp` are both in use
The app can keep `comp` internally, but the user-facing terms should default to `competition`.

Recommended treatment:
- `competition` in user-facing copy
- `comp` in admin screens, logs, and internal code comments only

Examples:
- `lib/pages/user_home/user_home_profile.dart`
- `lib/pages/user_home/user_home_tips.dart`
- `lib/pages/admin_tippers/admin_tippers_list.dart`

### 5. `sign in`, `log in`, `login`, and `logon` are mixed
This is mostly a consistency issue rather than a functional bug.

Recommended treatment:
- `sign in` in the app UI
- `log in` only in legacy FAQ text if it reflects the original flow
- `login` and `logon` only where a technical field name or legacy system term is required

### 6. `leaderboard` and `ladder` should stay distinct
This distinction is useful and should be preserved.

- `leaderboard` = tipper ranking
- `ladder` = team ranking

This is already close to the current app language and should be kept stable.

## Proposed Rules

1. Prefer the canonical term in new UI copy.
2. Use shorthand only when the audience is clearly internal or admin-only.
3. Do not introduce a new synonym unless it adds meaning that the canonical term does not already carry.
4. When a screen combines two concepts, label them explicitly instead of reusing one term for both.
5. Keep help docs and FAQ aligned with the app lexicon, not the other way around.

## Suggested Rollout Order

1. Fix the alias dialog wording from `player` to `tipper`.
2. Standardize `sign in` / `log in` user-facing copy.
3. Review `competition` vs `comp` on profile and admin screens.
4. Review `game` vs `match` on help text and game info cards.
5. Decide whether `Stats` remains the section label or whether a future rename is warranted.

## Open Questions
- Should `Stats` remain the visible tab label, or should it be renamed to something more explicit like `Scoring` or `Results`?
- Should `competition` become the default user-facing term everywhere, or should `comp` remain visible in some places for brevity?
- Should the Help and FAQ docs be rewritten to match the app lexicon exactly, or kept slightly more conversational?

## Notes
- This document is for product language, not implementation naming.
- Internal identifiers such as `DAUComp`, `Game`, and `Tipper` can remain as code names even when the visible copy changes.
