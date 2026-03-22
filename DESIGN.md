# Design Guidelines

UI design principles for DAU Footy Tipping, derived from industry best practices and our established app patterns.

## Core Principles

### 1. Affordances & Signifiers
- UI should **communicate how things work without instructions** — containers show grouping, highlights show selection, greyed-out text signals inactive states
- Use button press states, active nav highlights, hover states, and tooltips to tell users what the UI can do
- Arrow icons on table rows indicate they are tappable/navigable

### 2. Visual Hierarchy
- Use **size, position, and colour** to establish importance
- Most important elements: large, bold, top of the layout
- Hierarchy comes from **contrast** — the difference between small/big, colourful/not
- Use icons and visual cues instead of text labels where possible
- Team logos (SVG, 20-28px) alongside team names add instant recognition

### 3. Grids, Layouts & Spacing
- Use a **4-point grid system** (all spacing multiples of 4) for consistency
- **White space is more important than grids** — let things breathe
- Group related elements closer together (proximity = relationship)
- Standard horizontal padding: `16.0` across all pages

### 4. Typography
- **One font family** — stick with the theme's default sans-serif
- **Bold column headers** in all data tables (`FontWeight.bold`)
- Description text uses `bodyMedium` with `Colors.grey[600]`
- Page titles use `titleLarge` with `FontWeight.bold`
- Tighten letter spacing on headers for a polished look

### 5. Colour
- Start with **one primary/brand colour**, lighten for backgrounds, darken for text
- Use **semantic colours** with meaning: green for correct tips, red for incorrect, blue for home team, purple for away team
- League colours for top-8 shading (AFL/NRL branded)
- **Use colour for purpose, not just decoration**

### 6. Dark Mode
- Lower border contrast (light borders are too harsh)
- No shadows — create depth by making cards **lighter than the background**
- Dim saturation and brightness on bright chips/badges

### 7. Shadows
- Most default shadows are **too strong** — reduce opacity and increase blur
- **If the shadow is the first thing you notice, it's wrong**
- Cards need less shadow, floating content (popovers, modals) needs more

### 8. Icons & Buttons
- Icons should **match font line height** (typically 24px for body, 40px for headers)
- Button padding guideline: **double the height for the width**
- Primary + secondary CTAs work well side-by-side (filled + ghost)
- FloatingActionButton for back navigation on detail pages

### 9. Feedback & States
- **Every user action needs a response**
- Buttons: default, hovered, active/pressed, disabled, loading (with spinner)
- Inputs: focus state, error state with red border + message
- Show `CircularProgressIndicator` when loading data
- Show meaningful empty states when no data available

### 10. Micro Interactions
- Animations should **confirm the user's action**
- Hero animations on team logos and league icons between pages
- Keep animations practical and purposeful

### 11. Overlays & Images
- Don't put text directly on images
- Use a **linear gradient** that shows the image then fades to a text-readable background

---

## App-Specific Patterns

### Page Structure
Every stats/detail page follows this structure:
1. `Scaffold` with `FloatingActionButton` (back navigation)
2. `HeaderWidget` in portrait only (40px Hero-animated icon + bold title)
3. Description text (`bodyMedium`, grey, with usage hints like "Tap column headings to sort")
4. Data content (typically `DataTable2`)

### Data Tables (DataTable2)
- **Bold column headers** — always `TextStyle(fontWeight: FontWeight.bold)`
- **Team logos** (20px SVG) next to team names in all tables
- Table border: `TableBorder.all(width: 1.0, color: Colors.grey.shade300)`
- Heading row height: `36-40px`
- Data row height: `48px`
- Use `ColumnSize.L` (flexible) for the primary content column; fixed widths for compact columns
- `columnSpacing: 8`, `horizontalMargin: 8`
- Fixed top row for headers, fixed left column in portrait for the primary identifier
- Arrow icon (`Icons.arrow_forward`, 16px, grey) on navigable rows

### HeaderWidget
- 100px height `SizedBox` containing a `Row`
- Leading icon: 35-40px, wrapped in `Hero` for page transitions
- Title: bold text, typically includes the entity name or league

### Embedded Sections (e.g., Historical Matchups within a page)
- Preceded by `Divider(thickness: 1, height: 16)`
- Section icon (40px) + bold title in a `Row`
- Same description text styling as standalone pages
- Same `DataTable2` conventions

### Navigation Indicators
- `Icons.arrow_forward` (16px, grey) in first table cell = row navigates to detail page
- `Hero` animations on icons/logos for smooth page transitions
- `onTap` handlers on `DataCell` for row-level navigation

### Colours & Badges
- Home/Away badges: small bordered containers with 10px text
  - Home: blue tint (`Colors.blue` at 0.1 alpha)
  - Away: purple tint (`Colors.purple` at 0.1 alpha)
- Win/Loss indicators: `Icons.check_circle` (green) / `Icons.cancel` (red), 14px
- Top-8 row highlighting: league colour brightened (light mode) or darkened (dark mode)
