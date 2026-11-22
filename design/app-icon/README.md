# DAU app icon

The shared sources are `design.json` and `assets/icon/DAU-football-black.svg`.
The latter also supplies the Tips tab. Generated artwork is checked in so normal
Flutter builds do not need Node or an image-generation step.

The gradient runs from NRL green at bottom left to AFL red at top right. The
colours come from the `LeagueColour.colour` extension in
[`lib/models/league.dart`](../../lib/models/league.dart): NRL #04cf5d and AFL
#e21e31. This extends the enum defined in `packages/dau_shared/lib/models/league.dart`;
the Flutter colour values live in the app extension, not the shared package.
`design.json` mirrors these values explicitly; when the league colours change,
update it and regenerate the icons. The app's `nrlAflColourGradient` in
`lib/theme_data.dart` uses the same colours, but the icon retains its own direction
and gradient endpoints.
The gradient endpoints reproduce a 45-degree gradient whose length equals the
canvas width. The football's 24-unit canvas occupies 80% of the square, matching
the original icon's visible footprint. Android adaptive layers use 60%, keeping
the football inside the central 66/108 safe circle.

## Regenerate

Use Node.js compatible with Sharp 0.35.5. Install the generator dependency once:

```sh
npm --prefix scripts/icons install
```

Then, from the repository root:

```sh
node scripts/icons/generate.cjs
node scripts/icons/generate.cjs --check
```

`--check` compares all generated files without writing. The generator creates
the in-app PNG, reusable SVGs, Apple layer assets and flat fallback, Android
density-specific legacy/adaptive/monochrome PNGs, and web/PWA/favicon assets.
Do not run the old `flutter_launcher_icons` workflow over these outputs.

## Apple appearances

Open `ios/Runner/DAUAppIcon.icon` in Icon Composer. This is the editable Apple
project and is included in the Runner target for Debug, Profile and Release.
It has a gradient backdrop and a football layer. Default uses the full gradient
and a white football. Dark reduces the backdrop opacity and overrides the football
to charcoal grey (#666666). Mono hides the backdrop and uses 65% football opacity
for clear and tinted modes (stored as the `tinted` appearance in `icon.json`).
Tune glass, lighting and appearance settings in Icon Composer and save the file.
The generator refreshes only its two artwork files, preserving `icon.json` edits.
Close the document before regeneration, then reopen to see refreshed artwork.

Shared geometry/colour edits belong in `design.json` or the source football SVG;
Apple-only effects belong in Icon Composer and do not propagate to Android/web.
The generated 1024-unit football layer already contains its padding: leave its
Icon Composer scale at 1 for consistency with the shared design.

Xcode 26 or later compiles the layered icon and generates compatibility images
for older iOS releases. `AppIcon.appiconset` remains a flat fallback, but the
Runner target selects `DAUAppIcon`. Android uses its existing adaptive-icon XML
with separate background, foreground and monochrome resources. The web page
links `manifest.json`, which references both ordinary and maskable PNGs.

The previous experiment under `archive/original_assets` is historical and is not
used by this workflow. No network or generative image service is used to render.
