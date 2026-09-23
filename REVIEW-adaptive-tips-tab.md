# Adaptive Tips Tab — implementation review

22 September 2026. Review of [the exported brief](DESIGN-adaptive-tips-tab.md)
against the current code and Richard's discussion with the implementing agent.

The exported brief remains unchanged: its shared document is the living copy.
These are proposed amendments for the reviewer to carry back to that document,
not a replacement brief or a record of approval for every recommendation below.
No implementation or commits have been made.

## Confirmed requirements

- Preserve the familiar standard layout and swipe interaction.
- Adapt to the card's available width and the user's text settings, including
  rotation and split-screen, without choosing layouts by device name.
- Prototype separately on `codex/adaptive-tips-prototype`, based on development
  commit `793751a`, in this worktree.
- Use the four original [baseline screenshots](screenshots/tips-baseline-2026-09-22/README.md).
- Retain review checkpoints before integration and merge.

## Proposed amendments to the living brief

1. **Keep the carousel; start with a uniform calculated card extent.** This is
   the recommended experiment, not proof that every layout will fit. The
   carousel needs an explicit height, but an external sizing mechanism could
   update that height without replacing the package. Active-page sizing does
   not inherently require a package swap. Prefer stable height while swiping.

2. **Include usable width in sizing.** A layout mode and a single text-scale
   number do not capture wrapping. Account for actual text scaling at the font
   sizes used, styles, padding, banners and neighbouring-page previews. Validate
   long names, venue details, AFL labels/scores and loading states. A shorter
   wide card is desirable only if all its panels fit. Keep one arrangement and
   extent across games for the initial experiment.

3. **Distinguish outer card extent from carousel height.** In stacked mode the
   matchup sits above the carousel. Its height, spacing and card margins must
   be included in the outer extent; passing that entire extent into the carousel
   would count the matchup space twice. Feed consistent layout metrics to both
   rendering and every navigation/section calculation.

4. **Separate resize restoration from startup navigation.** Simply adding width
   to the startup signature may send users back to the first untipped game.
   Remember the visible game's identity and its position relative to the usable
   viewport; recalculate geometry and restore that position, clamped near list
   boundaries. Preserve selected tips and semantic panel identity too. Include
   changing safe areas and sticky-header dimensions in this verification.

5. **Keep name and score associated, allowing wrapping.** Prefer the same line
   where it fits, with a readable fallback within each team's group at extreme
   widths/text sizes. Do not require an unbreakable line or reduce user text size.

6. **Measure hit areas before declaring a visual conflict.** Visible chip size
   and tappable area are not identical. Investigate whether surrounding space
   can provide larger, non-overlapping targets without altering the standard
   appearance. Present any unavoidable visual tradeoff to Richard.

7. **Capture the unchanged baseline in this worktree.** Do not add baseline
   commits to development before branching: the isolated branch already exists.
   Standard/default-text comparisons should remain stable; reference captures
   at wide/narrow widths and large text document behaviour intended to improve.
   Add cases narrower than 360 logical pixels, around measured transitions,
   larger than 1.5 text scaling, and landscape with limited height.

8. **Use the intended components with a temporary development harness.** This
   remains the implementing agent's recommendation for prototype structure.
   Exercise sample multi-round lists, navigation and sticky headers, and both
   Tips and Percentage Tipped. Remove the temporary harness before merge.

9. **Avoid expanding cleanup scope.** One clean worktree was removed. The two
   retained worktrees contain modified files or commits outside development;
   they are not established as disposable. Shared-model layout cleanup should
   follow a caller audit. The current method is `pixelHeightUpToRound`, not
   `getPixelHeight`. Do not introduce blanket formatting contrary to Richard's
   repository instructions, or treat this brief as release authorization.

10. **Keep device and interaction claims provisional.** Do not invent hinge
    metrics for the proposed device. Validate reported display features when
    available and explicitly define the first prototype's scope. Audit actual
    keyboard focus behaviour before claiming chips are unreachable. Hero tags
    must be unique within the route; repeated teams across rounds need attention
    as well as duplicate layout variants. An unbuilt lazy-list item cannot be
    reached merely by calling `ensureVisible` on a key, so that is not a complete
    fallback scrolling strategy.

## Screenshot observations

The four supplied images are now available as visual references. Loading
percentage chips show progress indicators as well as their reserved footprint;
the sample should reproduce that state rather than merely blank chips. Existing
header/content overlap is recorded in the references and must not be mistaken
for the desired baseline. Use synthetic equivalents of these states in the
harness; there is no need to access live personal tipping data to reproduce them.

## Next review checkpoint

Review the uniform-extent carousel experiment and prototype structure with
Richard/the reviewer before implementation. No exact breakpoints, extent
formula, hinge-specific behaviour or touch-target tradeoff is approved by this
note. Re-export the living brief after its amendments are incorporated.
