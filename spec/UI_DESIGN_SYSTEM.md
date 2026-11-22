# TierTask UI Design System & Interaction Guidelines

> [!IMPORTANT]
> This specification is the authoritative source for TierTask visual design tokens, layout geometry, reusable component boundaries, interaction patterns, keyboard shortcuts, and accessibility rules derived from the approved `.agents/prototypes/ui_v2/` concept. All work on `lib/ui/{tokens,primitives,layout,components}/` and app `lib/ui/` MUST enforce these rules (`P-UI-DESIGN-SYSTEM`) via the **`ui-design-system`** skill.

## 1. Scope, Governance & Fidelity Policy

### `U-FIDELITY-001` Initial Prototype Parity
The integrated `lib/ui/{tokens,primitives,layout,components}/` design system and adaptive `lib/ui/` shell and views MUST match the visual design, layout proportions, surface hierarchy, token values, and interaction flows established from `.agents/prototypes/ui_v2/` across Desktop (`Linux`, `Windows`) and Mobile (`Android`), English (`en`) and German (`de`), and all built-in theme presets (`Calm` and `Plum Umber`, Light and Dark).

### `U-FIDELITY-002` Post-Cutover Evolution
Following completion of the UI migration, future iterations of the Flutter application MAY refine, extend, or diverge from `.agents/prototypes/ui_v2/`. Any intentional divergence MUST update `spec/UI_DESIGN_SYSTEM.md` in the same change so this document remains the single source of truth; backporting changes to the historical HTML prototype is not required.

### `U-FIDELITY-003` Maximum Reuse & Minimum Widget Count
`lib/ui/{tokens,primitives,layout,components}/` MUST stay compact and orthogonal around the 17 core widgets defined in Section 6 (`8` primitives, `4` adaptive layouts, `5` domain-agnostic composites). Introduce a new widget ONLY when existing primitives and layouts cannot express a pattern cleanly through composition, slots, or semantic variants. Feature screens in `lib/ui/` MUST compose these shared building blocks rather than duplicating bespoke one-off widgets across Tasks, Labels, Locations, Settings, Conflicts, and Modals.

## 2. Surface Hierarchy, Flatness & Elevation

### `U-SURFACE-001` Flat Border-Delimited Resting Surfaces
Resting UI elements MUST remain strictly flat and separated by `1px` hairline borders (`borderWidth: 1.0`, token `line`). Cards, top chrome bar, sidebar, bottom docks, log console, raw TDF preview, and read-report panels MUST carry zero drop shadows.

### `U-SURFACE-002` Restricted Shadow Allowlist & Z-Index Ladder
Drop shadows and inset rings are permitted ONLY on the following surfaces:

| Surface | Z-Index Layer | Elevation / Shadow |
| :--- | :--- | :--- |
| Base shell, chrome, sidebar, main scroll, bottom dock | `0` | None |
| Selected segmented control tab | `0` | `0 1px 2px rgba(0, 0, 0, 0.06)` |
| Keyboard-highlighted selected picker row | `0` | Inset `1px` `accent` ring |
| Floating notice / Undo toast overlay | `10` | `0 8px 24px rgba(0, 0, 0, 0.20)` |
| Compact drawer backdrop scrim | `11` | Solid translucent `scrim` |
| Compact slide-over navigation drawer | `12` | Border-delimited over scrim |
| Desktop anchored popover (composer label picker) | `25` | `0 14px 36px rgba(0, 0, 0, 0.24)` |
| Compact modal bottom sheet | `35` | `0 -10px 30px rgba(0, 0, 0, 0.28)` |
| Centered modal dialog | `40` | `0 18px 42px rgba(0, 0, 0, 0.24)` |

### `U-SURFACE-003` Surface Alternation Ladder
Establish figure-ground depth through surface alternation rather than elevation:
1. **`pageBg`:** Outer canvas backdrop (if windowed).
2. **`bg`:** Application shell canvas, main scrollable list background, pinned bottom docks, and inset containers placed inside `panel` surfaces (expanded `.info-card` wells, standard form inputs/selects/textareas, segmented control trough, chips, badges, chrome pills, sidebar filter input, workspace rows, resolved preview box).
3. **`panel`:** Top chrome bar, sidebar/drawer, top-level cards (entity cards, draft cards, static settings/conflict cards, quick-create bar, quick-add composer card, log console, raw TDF block), secondary buttons, count pills, selected segmented tab, overlays (toasts, popovers, sheets, modals), and **re-elevated interactive controls nested inside `bg` inset cards** (inline section edit inputs, color preset chips, subtask edit inputs, label picker search/list, read-only link rows, inline location chips, workspace rename input, history inline edit inputs).
4. **`soft`:** Accent-tinted active/selected surface paired exclusively with `accent` foreground (active nav items, active chips/toggles, hovered icon buttons, active workspace card, Undo button, `tone-soft` and `tone-accent` badges).

### `U-SURFACE-004` Semantic Surface Triples & Neutral Card Rule
Every semantic status (`danger`, `warning`, `success`) MUST pair three dedicated tokens: high-contrast foreground, soft tinted fill (`*Bg`), and mid-contrast border (`*Border`). Entity card containers (`.task`) MUST stay neutral (`panel` fill with `1px` `line` border) even when overdue, prioritized, blocked, or suspended; communicate state strictly through semantic badges, icons, and section text rather than full-card tints or colored side rails.

## 3. Design Tokens, Typography, Sizing & WCAG AA Palettes

### `U-TOKEN-001` Typography Scale & Text Wrapping
- **Font Families:** System sans-serif (`Inter`, `Segoe UI`, system UI sans) for UI prose and controls; monospace (`Cascadia Code`, `JetBrains Mono`, `Menlo`, `Consolas`, system monospace) for IDs, file paths, URLs, coordinates, hex colors, SemVer build strings, `DEV` badge, keyboard hints, log console, and raw `.tdf` preview.
- **Scale:**

| Role | Size | Weight (CSS / Flutter) | Line Height / Tracking | Primary Consumers |
| :--- | :--- | :--- | :--- | :--- |
| Page Title | `28px` | `650` (`w600`–`w700`) | `1.2` / `-0.7px` | View headings (`h2`) |
| Brand / Active Filter | `18px` | `650` / `600` (`w600`) | `1.2` / `-0.5px` (`-0.25px` filter) | Top bar brand wordmark, desktop inline active label |
| Modal Title | `17px` | `650` (`w600`) | `1.3` | Modal dialog header |
| Compact Brand / Input | `16px` | `650` / `400` | `-0.3px` (button) | Compact active-label top bar button, compact quick-add input |
| Card Title | `15px` | `550` / `600` (`w500`–`w600`) | `1.45` | Entity titles, draft/inline title inputs, mono preview, mobile search filter |
| Body | `14px` | `400` / `600` | `1.45` | Default text, static card headings (`600`), bottom-sheet header |
| Control | `13px` | `400` / `500` / `600` | `1.45` | Sidebar nav rows, danger buttons, checkbox labels, search input, card body text, empty states |
| Raw Code | `12.5px` | `400` | `1.55` | Raw `.tdf` preview (mono) |
| Meta / Compact Control | `12px` | `400` / `500` / `550` / `600` | `1.45` (`1.5` log console) | Subtitles, field labels, count pills, compact/text buttons, segmented tabs, banners, toasts, errors, log lines |
| Compact Chip / Mono Small | `11.5px` | `400` / `550` / `600` | `1.45` | Tag chips, meta pills, scope filter pills, color preset chips, paths/URLs/IDs |
| Eyebrow / Badge | `11px` | `400` / `500` / `600` | `0.9px` uppercase (eyebrows) | Section eyebrows, `pill-badge` (`600`), field help/errors, sidebar counts, version footer |
| Micro Meta | `10.5px` | `400` | `1.45` | `Scoped Queue` subtitle/badge, keyboard shortcut hint (mono) |
| Dev Build Pill | `10px` | `700` (`w700`) | `1.2` / `0.7px` | Inline `DEV` badge (mono) |

- **Tabular Figures:** Apply `FontFeature.tabularFigures()` to count/limit readouts (`N / 3`, `N / 5`, open counts, progress ratios) in Flutter to prevent horizontal jitter during live updates.
- **Truncation & Wrapping Discipline:**
  - Single-line ellipsis: active-label filter names (desktop heading and compact top bar), workspace card titles and filenames.
  - Non-wrapping atomic tokens: count pills, badges, sidebar counts, scoped badges.
  - Arbitrary soft wrap (`overflow-wrap: anywhere` / soft break): entity titles, sidebar label names, label picker names, assigned label chips.
  - Hard character break (`break-all`): monospace paths, URLs, IDs, coordinates.
  - Preserved whitespace: multi-line entity notes (`pre-wrap`), diagnostic log lines (`pre`).

### `U-TOKEN-002` Spacing Scale & Shell Dimensions
- **Base Scale:** `space1 = 4`, `space2 = 8`, `space3 = 12`, `space4 = 16`, `space5 = 20`, `space6 = 24` logical pixels.
- **Shell Constants:** Top chrome `minHeight = 62` (`padding: 10x16` desktop, `8x10` compact); persistent desktop sidebar `width = 244`; compact drawer `width = min(300, 92% viewport)`; desktop app shell `maxWidth = 1280`; main content padding `22, 26, 24` desktop (`16, 14, 20` compact); bottom dock padding `10, 26, 12` desktop (`10, 14, 12` compact); card list vertical gap `11`; section card grid gap `14`.

### `U-TOKEN-003` Touch Targets & Control Density Ladder
- **Primary Hit Targets:** Desktop `touchTarget = 40px` (standard buttons, icon buttons, text/select fields); Compact/Mobile `touchTargetMobile = 44px` (drawer menu button, mobile tier selector, bottom-sheet picker rows).
- **Secondary Densities:** `38px` (nav rows, inline add inputs), `36px` (back link, search input, weekday/selectable chips), `34px` (chrome workspace/sync pills, segmented tabs, entity leading hit box, inline filter selects, compact sidebar header buttons), `32px` (compact buttons, sidebar filter input, history timestamp input), `30px` (text buttons, compact icon buttons, subtask rows), `28px` (card title hit line, picker info icon, slider), `26px` (desktop sidebar header buttons, search clear button), `24px` (sidebar filter clear button).

### `U-TOKEN-004` Radii, Borders & Focus Ring Tokens
- **Radii:** `2px` (logo bars), `3px` (`8px` color dot), `4px` (`12px` dot, `16px` custom checkbox, kbd hint, log line), `radiusTag = 6px` (badges, chips, pills, segmented buttons, `DEV` pill), `radiusSm = 7px` (sidebar header icon buttons, inline active filter, picker rows, weekday pills), `radiusMd = 8px` (buttons, inputs, selects, textareas, segmented trough, nav rows, chrome controls, inline warnings, link rows), `9px` (mobile tier select), `radiusRow = 11px` (nested `.info-card`, banners, toasts, log meta card, workspace cards, color preview bar), `radiusCard = 13px` (top-level entity/draft/edit cards, composer form, popover, log console, raw TDF preview), `radiusShell = 16px` (app frame, modal dialogs, top corners of mobile bottom sheets), `radiusPill = 999px` (count pills, `pill-badge`, scope filter pills, sheet handle, progress bar), circular `50%` (task completion circle, spinner, color swatch, HSV wheel).
- **Borders & Focus Ring:** `borderWidth = 1px` (`1.7px` task completion circle, `2.5px` loading spinner); `focusRingWidth = 1px`; `focusRingOffset = 1px`.

### `U-TOKEN-005` Built-In Theme Preset Color Matrix
All four built-in presets (`Calm` default, `Plum Umber`, Light and Dark) MUST use these exact color values. Note the intentional dark-mode `onAccent` polarity flip (`#132a36` and `#1e1429`) paired with pastel dark accents:

| Token | Calm Light | Calm Dark | Plum Umber Light | Plum Umber Dark |
| :--- | :--- | :--- | :--- | :--- |
| `pageBg` | `#e7eef2` | `#111b20` | `#ece5e0` | `#161110` |
| `bg` | `#f0f4f7` | `#19262d` | `#f6f2ef` | `#1f1918` |
| `panel` | `#ffffff` | `#243239` | `#fffdfb` | `#2b2322` |
| `ink` | `#202c33` | `#edf2f5` | `#2c2220` | `#f3ecea` |
| `muted` | `#53646f` | `#b5c4cc` | `#63534f` | `#c3b4b0` |
| `line` | `#d8e2e8` | `#3e505a` | `#e2d7d2` | `#473a38` |
| `accent` | `#00648b` | `#9ac7e9` | `#6b3fa0` | `#c5a3f5` |
| `soft` | `#e0eff7` | `#1c4255` | `#f0e7f8` | `#362945` |
| `onAccent` | `#ffffff` | `#132a36` | `#ffffff` | `#1e1429` |
| `danger` | `#a12a2a` | `#ffc0c0` | `#a12a2a` | `#ffb8b8` |
| `dangerBg` | `#fdecec` | `#472529` | `#fcebeb` | `#4a2326` |
| `dangerBorder` | `#d99b9b` | `#8d4b52` | `#d99b9b` | `#8d494e` |
| `warning` | `#8a4b00` | `#f5c26b` | `#8a4b00` | `#f5c26b` |
| `warningBg` | `#fff3df` | `#3b2f1d` | `#fdf1df` | `#3e2e1d` |
| `warningBorder` | `#dfb87a` | `#785b2c` | `#dfb87a` | `#7a5c2c` |
| `success` | `#17633b` | `#8be0ad` | `#17633b` | `#8be0ad` |
| `successBg` | `#e6f5ec` | `#1a3b2c` | `#e6f4ec` | `#1d3a2a` |
| `successBorder` | `#9bd1b2` | `#387556` | `#9bd1b2` | `#3b7454` |
| `scrim` | `rgba(16, 28, 36, 0.46)` | `rgba(7, 13, 17, 0.62)` | `rgba(24, 16, 15, 0.48)` | `rgba(12, 8, 8, 0.64)` |

### `U-TOKEN-006` WCAG AA Contrast Invariant
Every foreground/background text pair (`ink`/`muted`/`accent` on `panel`/`bg`, `accent` on `soft`, `onAccent` on `accent`, and `danger`/`warning`/`success` on `*Bg`) MUST meet WCAG AA contrast (`>= 4.5:1`). All built-in presets verify at `>= 5.55:1`. Any future theme preset added via `UiThemePreset` MUST pass automated contrast verification in tests before merging.

## 4. Responsive Breakpoints & Adaptive Shell Geometry

### `U-LAYOUT-001` Non-Overlapping Breakpoint Partition
Use one canonical, non-overlapping viewport width partition (`UiBreakpoints`):
- **`compact`:** `width <= 720`
- **`medium`:** `width > 720 && width <= 820`
- **`expanded`:** `width > 820`

### `U-LAYOUT-002` Persistent Sidebar vs Compact Slide-Over Drawer
- **`medium` and `expanded` (`> 720`):** Render a persistent `244px` left sidebar with independent vertical scrolling and a scrollable bottom version footer aligned to the bottom when navigation content fits.
- **`compact` (`<= 720`):** Hide the persistent rail and present the sidebar as a slide-over drawer (`width = min(300, 92% viewport)`) anchored below the `62px` top chrome bar over a translucent `scrim` backdrop. Selecting any navigation item or tapping the scrim closes the drawer.

### `U-LAYOUT-003` Top Chrome Bar & Compact Adaptations
- **Desktop (`> 720`):** Left to right: Brand button (`UiAppLogo` + `TierTask`), Workspace switcher pill (`bg` fill, `workspaces` grid icon + name + `chevrons-up-down` icon), optional inline `DEV` pill, flexible spacer, Global Search toggle/input (`40px` hit target, `18px` icon), conditional Location Status icon button (`40px` hit target, `18px` icon, `accent` tint when fix found, shown only when `locationEnabled`), Sync status button (`bg` fill, `muted` foreground in neutral states, icon + text label), and on desktop platforms (`Linux`, `Windows`) a trailing Window Close icon button (`40px` hit target, `18px` `x` icon, `isDangerHover: true`).
- **Frameless Desktop Chrome (`Linux`, `Windows`):** Native OS window titlebars and caption buttons are removed on Linux and Windows. Empty background space in the top chrome bar supports native window dragging and double-click maximize/restore behind interactive controls without introducing click latency on buttons. Android omits both the trailing window close button and chrome window drag/maximize gestures at all viewport widths.
- **Edge-to-Edge System Bar & IME Insets (`Android`):** `UiAdaptiveAppShell` applies brightness-matched `SystemUiOverlayStyle` (transparent status bar over `panel`, `bg`-colored navigation bar with disabled contrast scrim) and pads the top chrome bar, sidebar/drawer, main body, floating notices, and pinned bottom dock using `MediaQuery.paddingOf` (status bar, display cutouts, gesture/3-button navigation bars) and `MediaQuery.viewInsetsOf` (on-screen keyboard). Consumed `MediaQuery.padding` is cleared for descendants while preserving `viewPadding` and `viewInsets` for overlay popups. Linux and Windows have zero insets and remain pixel-identical.
- **Compact (`<= 720`):** Reveal leading `44x44px` menu toggle (swaps `menu`/`x` icons), hide Workspace pill (relocate Workspace card to the top of the drawer), display the optional `DEV` pill beside the `TierTask` brand wordmark when no compact active-label filter is shown, collapse Sync button to an icon-only bordered `bg` pill, keep the desktop-only trailing Window Close button on Linux/Windows, hide keyboard shortcut hints, and tighten horizontal chrome padding (`8px 10px`, gap `6px`).
- **Compact Search Mode:** When Global Search is open on `compact` viewports, hide all sibling chrome controls so the search input expands to `100%` of the top bar width.

### `U-LAYOUT-004` Inline Active-Label Filter Placement
Never add a separate stacked active-filter banner row above headings:
- **Desktop (`> 720`):** Render the active label filter inline inside the page heading row (`h2` + clickable truncated label name + trailing count pill). Clicking clears the filter.
- **Compact Tasks View (`<= 720`, `!searchOpen`):** Hide the `TierTask` brand button and heading label filter; render a clickable `UiAppLogo` + truncated active label name directly in the top chrome bar brand slot. Clicking clears the filter.
- **Compact Search View (`<= 720`, `searchOpen`):** Because Search occupies the entire top chrome bar, render the clickable truncated active label filter inline inside the Search heading row.
- **Clear-Filter Side Effects:** Clearing the active label resets quick-add draft labels, closes open draft label pickers, closes the drawer, and clears expanded entity state unless Search is active.

### `U-LAYOUT-005` Scroll Container Decoupled From Docks & Floating Notices
The main content column MUST split into two non-overlapping vertical regions:
1. **Scroll Region + Floating Overlay Stack (`.main-scroll-wrap`):** Contains the vertically scrollable main pane AND the non-blocking floating notice/Undo overlay anchored `12px` (`10px` compact) above the bottom of the scroll region (`maxWidth: 620px`).
2. **Conditional Pinned Bottom Dock:** Positioned outside and strictly below the scroll region (`bg` surface with top `1px` `line` border) for the Task Quick-Add composer (on Tasks view when not searching, loading, full-error, or drafting a task) OR view action footers (Settings Save/Test Sync with dirty indicator; Conflict/Recovery Cancel + Apply).

This invariant guarantees floating toasts and Undo bars NEVER obscure docked inputs or action buttons and stay anchored without layout jitter during scrolling.

### `U-LAYOUT-006` Responsive Grids, Flex Discipline & Overflow Containment
- **Multi-Column Grids:** Settings and dual-column edit grids render 2 columns on `expanded` (`> 820`) and collapse to 1 column on `medium`/`compact` (`<= 820`). Nested 2-column field pairs collapse to 1 column on `compact` (`<= 720`). The 4-action local storage grid renders 4 columns on `> 720` and `2x2` on `compact`.
- **Overflow Discipline:** Never compress scroll children inside bounded viewports. Constrain flexible text children (`minWidth: 0` / `Expanded` / `Flexible`) so long strings wrap or ellipsize instead of pushing trailing actions off-screen. Restrict horizontal scrolling exclusively to the Diagnostic Log Console and Raw `.tdf` code block, both of which flex to fill remaining viewport height (`minHeight: 220px`).

### `U-LAYOUT-007` Scroll Offset Preservation
Preserve independent scroll positions across in-scope state updates: sidebar scroll while `activeWorkspaceId` is unchanged; main list scroll while `(workspaceId, view, tier, labelFilter, searchOpen)` is unchanged; label picker list scroll while `(mode, targetId, scopeFilter, query)` is unchanged. Smoothly scroll newly expanded or navigated entity cards into view (`nearest`).

## 5. Brand Identity & Iconography

### `U-BRAND-001` Minimal Three-Bar Accent Mark (`UiAppLogo`)
Render the in-app TierTask mark exclusively as three left-aligned stepped horizontal bars in `accent` color on a `22x18` (or `22x22` square) reference grid: each bar is `4px` tall with `2px` corner radius and `3px` vertical gap; bar widths and opacities are `100%` at `1.0`, `75%` at `0.72`, and `50%` at `0.42`. Never revert to the retired squircle-and-checkmark icon inside the app chrome.

### `U-BRAND-002` Build Profile & Version Chrome
- Display an inline `DEV` pill (`10px` bold mono, `warningBg`/`warning`/`warningBorder`, `radiusTag`) immediately after the Workspace switcher pill on desktop (`> 720px`) and beside the `TierTask` brand wordmark on compact (`<= 720px`) whenever `AppBuildProfile.isDev` is true.
- Render the monospace SemVer build string (`Version X.Y.Z` at full opacity + `+<hash>` at `0.65` opacity) as a non-sticky footer inside the scrollable sidebar/drawer separated by a top `1px` `line` border, aligned to the bottom when navigation content fits and scrolling naturally below `Tools` when navigation overflows.

### `U-BRAND-003` Offline Stroke Icon Standard
Use crisp, uniform outline stroke icons (`1.75` stroke weight, rounded caps and joins, zero external network assets) in four standard sizes: `13px` (badges, compact buttons, add chips, row controls), `15px` (standard buttons, section titles, banners, toasts, chrome pills, card actions), `18px` (sidebar navigation, primary chrome icons, modal close, location lead), and `34px` (full-screen error hero icon).

### `U-BRAND-004` Canonical Tier Icons & Semantic Tinting
Map the 6 derived tiers consistently:
- **Focus:** `zap` (lightning bolt)
- **Ready:** `list-ordered` (ordered list)
- **Planned:** `calendar-days` (calendar)
- **Blocked:** `circle-slash` (blocked circle)
- **Someday:** `lightbulb`
- **Completed:** `circle-check`

Default inactive icons to `muted`; use `accent` for active navigation, section headers, links, entity location leads, and interactive hover; use `danger`/`warning`/`success` exclusively for semantic status feedback and destructive hover targets.

## 6. Component Architecture & Domain-Agnostic Catalog

### `U-COMP-001` Isolated Four-Layer Design System (`lib/ui/{tokens,primitives,layout,components}/`)
Organize the universal design system inside `lib/ui/` into four strict bottom-up sub-ranks (`tokens (0) < primitives (1) < layout (2) < components (3)`) imported directly by leaf path (zero barrel `export`, `part`, or `part of` shims per `P-FILE-SIZE`):
- Zero imports from `lib/ui/{widgets,dialogs,views}/`, `lib/ui/tier_task_shell_screen.dart`, `lib/ui/ui_domain_mappers.dart`, `lib/models/`, `lib/l10n/`, `lib/services/`, `lib/repositories/`, `lib/providers/`, `package:flutter_riverpod/*`, `dart:io`, or `dart:ffi`.
- Built on Flutter and `material_ui` platform primitives (IME, focus traversal, scrolling, semantics) styled 100% through `UiThemeTokens` (`ThemeExtension`).

### `U-COMP-002` Eight Core Primitives (`primitives/`)
1. **`UiAppLogo`:** Minimal three-bar accent mark (`U-BRAND-001`).
2. **`UiButton`:** Semantic variants (`primary`, `secondary`, `text`, `danger`, `icon`), optional `compact` density (`32px`/`30px`), danger-hover tinting for icon buttons, optional loading spin icon, and disabled opacity (`0.48`).
3. **`UiPill`:** Unified count pill, `DEV` badge, full-radius status badge (`badge`), `6px`-radius collapsed metadata pill (`meta` with transparent resting border on `neutral`/`soft`/`accent`, accent border on interactive hover, and semantic borders on `warning`/`danger`/`success`), color-dotted tag chip (`tag`, `6px` radius, `1px` `line` border), split removable/navigable label chip, dashed `+ Add` chip, direct toggle chip, and weekday pill.
4. **`UiSegmentedControl`:** Supports two modes via `UiSegmentedControlMode`:
   - `horizontal` (default): Equal-width columns inside a `bg` trough with `1px` `line` border (`padding: 3px`, `gap: 4px`); selected segment uses `panel` fill, `accent` bold label, and subtle shadow.
   - `vertical`: Compact flat combobox trigger (`bg` fill re-elevating to `panel` inside `insetWell`, `1px` `line` border switching to `accent` on hover/focus/open, `8px` radius, `40px` min height, optional selected icon, selected label, rotating chevron) that reveals a direction-aware animated (`160ms` ease-out fade + vertical expansion) `panel` popover (`1px` `line` border, `popoverShadow`, `TapRegion` non-swallowing outside dismissal, `34px` desktop / `44px` compact option rows, `soft`/`accent` selected row with check, `1px` inset `accent` keyboard highlight, full `Enter`/`Space`/`ArrowDown`/`ArrowUp`/`Escape` parity). Sizes intrinsically in unconstrained horizontal rows and stretches in tight full-width containers.
5. **`UiCard`:** Unified bordered `panel` surface supporting static section cards (with header icon/title/badge slot), expandable entity cards, nested `bg` `.info-card` wells (switching border to `accent` and re-elevating inputs to `panel` while editing), and accent-bordered uncommitted draft cards.
6. **`UiField`:** Labeled text, multiline, password (with `eye`/`eye-off` toggle), select, and date/time wrapper with helper text, inline `danger` validation error, readonly `0.72` opacity, and `1px` `accent` focus border.
7. **`UiToggleRow`:** Labeled checkbox row with optional muted description. **No sliding Switch convention:** binary preferences use either 2-way `UiSegmentedControl` (e.g., Location Off/On) or `UiToggleRow` checkboxes.
8. **`UiBanner`:** Unified status banner (`warning`, `danger`, `success`), floating bottom toast/Undo notice, inline card warning box, inline destructive confirmation bar, plain-text empty state (no decorative graphics), and centered loading/full-error state surfaces.

### `U-COMP-003` Four Adaptive Layout Primitives (`layout/`)
1. **`UiAdaptiveAppShell`:** Coordinates top chrome bar, persistent desktop sidebar / compact slide-over drawer, scrollable main region, floating overlay layer, and conditional pinned bottom dock (`U-LAYOUT-002`..`005`).
2. **`UiSidebarSection`:** Collapsible, optionally filterable navigation group with eyebrow header, collapsed count + active-dot indicator, 3 header icon actions (`Filter`, `Manage`, `Collapse/Expand`), inline search box, and nav rows (`U-UX-001`).
3. **`UiPageHeader`:** Optional back button, `28px` heading + optional inline active-filter chip + count pill, subtitle (`maxWidth: 58ch`), and optional trailing action cluster.
4. **`UiResponsiveGrid`:** Adaptive grid collapsing `expanded` 2-column layouts at `<= 820px` and 2-column fields / 4-column actions at `<= 720px` (`U-LAYOUT-006`).

### `U-COMP-004` Modal Dialogs, Compact Bottom Sheets & Popovers (`UiDialogFrame`)
- **Centered Modal Dialog (`UiDialogFrame`):** Three-part anatomy (bordered header with `17px` title + close `x`, independently scrollable body, right-aligned bordered footer) in three widths: `small = 420px`, `medium = 520px`, `large = 600px`; `maxHeight = min(86vh, 720px)`. Respects `MediaQuery.paddingOf` and `MediaQuery.viewInsetsOf` margins so dialogs never collide with system bars or the Android soft keyboard.
- **Compact Bottom Sheet:** Top `16px` radius, `maxHeight = min(78% viewport, available height below top inset and above IME)`, `36x4px` centered `line` handle bar, header with title/count/`Done`, scrollable body with `44px` minimum row height, scrim tap dismissal, bottom/horizontal system bar safe-area padding, and upward lift above `MediaQuery.viewInsetsOf.bottom`.
- **Desktop Upward Popover:** Used for the docked Quick-Add label picker (`bottom: 100% + 8px`, `width: min(460px, 100%)`), dismissing on outside pointer clicks without swallowing clicks on interactive targets.

### `U-COMP-005` Searchable Picker Composite (`UiSearchablePicker`)
Shared across Label Picker (`task` live, `draft` quick-add, `entity-draft` card), Prerequisite Picker, and Local `.tdf` File Picker:
- **Adaptive Label Picker Container:** Inline editing card inside desktop expanded/draft cards; upward popover from desktop Quick-Add composer; unified modal bottom sheet for all three modes on `compact` (`<= 720`).
- **Label Picker Controls:** Compact selected-chips bar (omitted in desktop composer popover where chips already show below), search input (`maxLength: 500` Unicode scalar values, canonical `maxTdfTextLength`, clear `x`), conditional scope filter pills (`All`, `Scoped`, `Global` rendered ONLY when workspace has both scoped and global labels), scrollable multi-select listbox (`maxHeight: 224px` desktop, `44px` rows compact) with custom checkbox, color dot, name, `Scoped Queue` badge, open count, and `info` hub trigger, plus inline `Create & assign "<name>"` row when trimmed query is `1..500` Unicode scalar values and not a case-insensitive duplicate.
- **Prerequisite Picker:** Selected removable chips above search box and unselected candidates (excluding self and non-selected completed tasks). Candidates that would introduce a dependency cycle render disabled (`opacity: 0.5`) with an explicit `Cycle prevented` hint.

### `U-COMP-006` Ordered Item List Composite (`UiOrderedItemList`)
Repeatable add, inline edit, boundary-disabled `Move up`/`Move down`, and remove pattern reused across:
- **Subtasks:** Cap `1024` steps (`maxTdfStmtsPerBlock`), `500` Unicode scalar values per item (`maxTdfTextLength`), done checkbox, bottom add bar (`Enter` adds and refocuses), `Auto-finish` checkbox, blank items stripped on save.
- **Reference Links:** Cap `20` (`N / 20`), title + scheme-validated URI, inline edit highlights target row (`soft` fill) and swaps `Add link` to `Update link` + `Cancel`; read-only view renders clickable full-width cards with `external-link` icon.
- **Time Windows:** `HH:MM - HH:MM` add/remove rows paired with weekday toggle pills (`Mon..Sun`, sorted `1..7`) and location multi-select toggles; tasks support `Ignore all label conditions` and per-dimension `Inherit / Any / Custom`, dimming/disabling controls (`opacity: 0.45`) with an inline warning when the task is suspended.
- **History Journal:** Cap `500` (`N / 500`, canonical `maxTdfHistoryPerTask`), `500` Unicode scalar values per entry (`maxTdfTextLength`), optional clock toggle exposing local timestamp override (defaults to current local time when opened; empty/closed uses `now`), inline text + timestamp edit, whitespace collapse (`[\r\n\t]+` to single space) and trim, exact `(timestampUtc, text)` duplicate rejection, and canonical UTC-ascending + text-lexicographical sort.

### `U-COMP-007` Color Wheel & Preset Composite (`UiColorWheel`)
- **Inline Trigger Row:** `34x34px` circular live swatch + `110px` mono `#RRGGBB` input (`maxLength: 7`) + `Custom color` button + 8 preset chips.
- **Canonical 8 Label Color Presets:** `#2196F3`, `#4CAF50`, `#FF9100`, `#E91E63`, `#9C27B0`, `#00BCD4`, `#EB06FF`, `#00E5FF`.
- **HSV Wheel Modal (`small` width):** Live swatch + hex preview bar, `210x210px` circular custom-painted HSV wheel (angle = Hue `0..360`, radius = Saturation `0..1`, pointer-capture drag, `8px`-radius filled thumb with white + dark double halo), and `0..100%` Brightness slider updating preview smoothly without rebuilding the modal tree.

## 7. Unified Expandable Entity Cards, Badges & Draft Creation

### `U-CARD-001` Single-Expand Accordion Across Tasks, Labels & Locations
Replace legacy multi-tab editors and separate info/hub dialogs with unified expandable entity cards sharing one shell:
- **Strict Single-Expand:** At most one `{ kind, id }` card is expanded at a time. Expanding another card clears open inline edits, delete confirmations, history edits, and label pickers, then reveals the panel smoothly (`220ms` ease-out size + `180ms` opacity). Clicking an expanded card header collapses it.
- **Header Anatomy:** Optical `34x34px` leading control (task `21px` completion circle, label `12px` color dot, location `18px` `map-pin`), wrapping `15px` title, and right-aligned actions (`4px` spacing): inline title/name edit pencil (visible ONLY when expanded and editable), danger-styled Trash button (`dangerBg` fill, `1px` `dangerBorder` border, `danger` icon matching the inline delete confirmation banner; visible ONLY when expanded and disabled while the inline delete confirmation banner is shown), and Downgrade chevron (`chevron-right`, visible on active tasks in Tiers `0..2` only).
- **Collapsed Metadata Strip:** Indented `36px` left on desktop (`0` on compact), completely hidden while the card is expanded. Hovering a collapsed card highlights its border to `accent`; expanded cards keep a steady `line` border on hover.

### `U-CARD-002` Expanded Panel Anatomy & Progressive Disclosure
Inside every expanded entity card:
1. **Top Meta Bar:** Hairline top divider, monospace `ID: <id>` and optional contextual status pill (`Completed · restore task to edit` for completed tasks; `<N> open` for labels/locations) on the left, right-aligned Copy ID button flush with the card inner right edge, and a prominent full-width inline delete confirmation banner (`Keep` / `Yes, delete`) revealed immediately below the ID row while confirming deletion.
2. **Populated-Only Section Cards (canonical vertical order):** Section header trailing actions (Copy, Edit, Done) align flush with the right inner edge of each inset well (`Expanded` leading cluster + trailing controls).
   - **Tasks:** Note -> Links -> Subtasks -> History (always visible) -> Labels -> Due -> Queue & Priority (only when active and `priority` or `someday`) -> Repeat -> Suspended -> Prerequisites -> Activation Conditions.
   - **Labels:** Note -> Links -> Color (always visible) -> Board Scope (always visible) -> Activation Conditions.
   - **Locations:** Note -> Coordinates & Radius (always visible; source selector `GPS` / `Address` / `Plus Code`, `Use Current GPS` vs `Resolve` mutual gating, `0.01m..100km` radius accepting `m`/`km` and `,`/`.`).
3. **Bottom `+ Add` Chips Bar:** Lists only unset editable sections as dashed chips (`+ Note`, `+ Links`, etc.). For active tasks in `queue` mode, expose solid 1-click `Priority` and `Someday` direct toggle chips.

### `U-CARD-003` Inline Section Editing vs Immediate Live Controls
- **Single Active Section Editor:** At most one section editor is open at a time. Opening an edit focuses the first non-checkbox text/textarea control, switches its `.info-card` border to `accent`, elevates inner inputs to `panel`, and renders an inline error slot, optional left danger clear action (`Clear` / `Disable repeat` / `Resume task`, shown only when set), and right `Cancel` + `Save`.
- **Immediate Live Controls (commit without Save/Cancel):**
  - Subtask checkboxes (auto-finish triggers `completeTask()`, pushes Undo, collapses card, and shows Undo toast when final unchecked step completes; inline subtask save with all steps done + auto-finish behaves identically).
  - History journal add, inline edit, and delete.
  - Task Placement (`Queue` / `Priority` / `Someday`) segmented switch and direct chips (collapses card and announces tier change if the task moves tiers).
  - Task Label chip removal and Searchable Label Picker toggles (collapses card and announces move if the task leaves the current view or tier).
  - Label Board Scope (`Global Context` / `Scoped Queue`) segmented switch.

### `U-CARD-004` Read-Only Completed Task Card Exceptions
Completed tasks display struck-through `muted` titles, checked `accent` circles, and the `Completed · restore task to edit` meta pill:
- **Hidden / Disabled:** Title edit pencil, all section edit pencils, `+ Add` chips bar, label remove `x` buttons, Placement switch, Downgrade button, and Subtask checkboxes (disabled).
- **Retained Interactive Controls:** Restore circle button, expand/collapse, header danger Delete button + full-width Inline Delete confirmation (with Undo), Copy ID, Copy Note, clickable external Links, context-preserving Label and Condition Location navigation, and **fully interactive History journal** (add, edit, delete).

### `U-CARD-005` Collapsed Task Badge Order & Bounded Overflow
Render collapsed task metadata using `6px`-radius (`radiusTag`) chips: `UiPillVariant.tag` (`1px` `line` border) for assigned labels and `UiPillVariant.meta` (transparent resting border on `neutral`, `tone-soft`, and `tone-accent`; semantic border on `tone-warning` and `tone-danger`; `accent` border on interactive hover) for all primary, secondary, and overflow badges in this exact deterministic order:
1. **Assigned Label Chips** (exempt from overflow cap; clickable to open Label manager with `returnContext`).
2. **Primary Badges** (exempt from overflow cap):
   - Tier badge (`tone-soft`, tier icon + name): shown ONLY in Global Search.
   - Due / Overdue badge (`calendar-days`): `tone-danger` when active and overdue; `tone-warning` when active and within `dueLeadWindow`; neutral otherwise or when completed.
3. **Secondary Badges** (capped at `3` visible pills in strict priority order, all toggling card expansion):
   1. Manual Priority (`zap`, `tone-accent`) OR Automatic Priority escalation (`zap`, `tone-warning`, `due.auto`)
   2. Suspended (`pause-circle`, `tone-warning`)
   3. Blocked by Prerequisites (`lock`, `tone-warning`, `<done>/<total>`; omitted once satisfied)
   4. Activation Conditions (`sliders`, `tone-warning` if unmet, neutral if met)
   5. Subtasks (`check-square` if auto-finish else `list-checks`, `<done>/<total>`)
   6. Repeat (`repeat`, formatted interval summary)
   7. Note (`file-text`)
   8. Links (`link`, singular/plural count)
   9. History (`history`, count)
4. **Overflow Indicator:** When more than `3` secondary badges exist, show the first `3` plus a clickable `+<N> more` pill that expands the card.

Collapsed Label cards show Scope -> `<N> open` -> Note -> Links -> Conditions. Collapsed Location cards show Source type -> `<lat(4dp)>, <lon(4dp)> · <radius>` -> `<N> open` -> Note. Neither caps secondary badges.

### `U-CARD-006` Quick-Add, Quick-Create & Uncommitted Draft Cards
- **Docked Task Quick-Add (`UiQuickComposer`):** Permanently pinned in the bottom dock on Tasks view (zero jump-to-composer button). Contains a `15px` title input (`New task...` / `Neue Aufgabe...`, `maxLength: 500` Unicode scalar values, canonical `maxTdfTextLength`), a `UiSegmentedControlMode.vertical` placement combobox (`Queue`, `Priority`, `Someday`, sized intrinsically inline next to `+ Add` across all desktop widths `> 720px`, stretched full-width above the divider on compact `<= 720px`, and opening its animated option popup upward from the bottom dock), a `40px` standard primary `+ Add` button with leading `+` icon, a hairline top-bordered footer row pairing draft label chips + `+ Labels` dashed trigger on the left with a borderless `Open as draft` text button (`sliders` icon) on the right, and the muted placement helper caption rendered outside and strictly below the bordered composer card. Active label filter auto-seeds draft labels. On `compact` (`<= 720`), collapses to a full-width primary `+ New task` button (leading `+` icon with `New task` / `Neue Aufgabe` text label) that toggles open the stacked composer form with a close `x` and keeps the placement helper caption below the card.
- **Non-Jumping Task Creation:** Adding a task via Quick-Add or Draft Card MUST NOT switch tiers, navigate views, scroll the list, or auto-expand the task. Announce placement via floating notice (`Moved to scoped queue: <label>`, `Saved · now in <Tier>`, or `Task saved`). Duplicate titles (case-insensitive) trigger a `danger` toast while preserving draft input.
- **Entity Quick-Create Bars:** Rendered inline at the top of Labels and Locations manager views (`maxLength: 500` Unicode scalar values, canonical `maxTdfTextLength`, borderless `Open as draft` text button with icon, `40px` primary `+ Add` button with leading `+` icon); Quick-Create Label assigns the next rotating preset color; Quick-Create Location seeds current GPS fix if found.
- **Uncommitted Draft Cards:** Clicking `Open as draft` transfers typed inputs into an accent-bordered Draft Card at top of the view (`Uncommitted · saved only when you click Create`), resets quick-add, clears expanded state, scrolls main to `0`, and focuses the draft title input. **While an entity draft is open, hide the docked Task Quick-Add composer (for task drafts) or replace the Label/Location quick-create bar in place.** Canceling (`Cancel`, `Escape`, or navigating away) discards without mutation; committing a Label or Location draft auto-expands and smoothly scrolls to the new card.

## 8. Navigation, Feedback, Settings & Error/Recovery UX

### `U-UX-001` Collapsible & Filterable Sidebar Sections
- **Tasks Section:** Fixed 6 tiers with live filtered counts; Focus appends ` / 3` and Ready appends ` / 5` in page headings.
- **Labels & Locations Sections:** Eyebrow header shows total count (and active label color dot for Labels) ONLY while collapsed. Right-aligned 3-icon action cluster (`26px` desktop, `34px` compact): `Filter`, `Manage` (pencil), and `Collapse/Expand` (chevron).
- **Filter Interaction:** Toggling `Filter` while collapsed auto-expands the section, reveals the inline search input, and focuses it. Toggling `Filter` off or collapsing the section closes and clears the filter query.
- **Row Layout:** Labels always lead with `All Tasks`, followed by alphabetically sorted rows split into primary filter selection (dot, name, `Scoped Queue` subtitle, open count) and trailing `info` hub link. Locations sort alphabetically with single-button hub navigation and open task count.
- **Tools Section:** Conditionally show `Diagnostic Log` (only when `diagnosticsEnabled`), alongside `TDF Source` and `Settings` (manual synchronization is triggered from the top chrome Sync button or Settings).

### `U-UX-002` Context-Preserving Back Navigation (`returnContext`)
Navigating to a Label or Location card from Tasks or Search (via task chips, expanded chips, sidebar info buttons, picker info buttons, or condition location chips) MUST save `{ view, tier, label, searchOpen, searchQuery, expandedEntity }`. The destination view renders `Back to search` (when `searchOpen` was true) or `Back to tasks`, restoring full context and scrolling back to the previously expanded task. Direct top-level chrome or sidebar navigation clears `returnContext`.

### `U-UX-003` Compact Tier Navigation (No Swipe Gestures)
On `compact` (`<= 720`) viewports, tier navigation uses the slide-over drawer and the native tier dropdown (`<TierName> · <count>`) positioned above the tier heading (hidden during Search). Horizontal swipe gestures between tiers are intentionally excluded to avoid conflicts with OS back gestures and nested controls.

### `U-UX-004` Floating Toast & LIFO Undo Recovery
- Render notices in `.floating-notice-layer` (`aria-live="polite"`, `maxWidth: 620px`) above the bottom dock.
- **Auto-Hide Durations:** `8000ms` when showing `Undo` (`Ctrl+Z` hint on desktop); `5000ms` for standard notices; persistent (manual `Close` only) for startup settings recovery notices.
- **Undo Stack (max depth `10`):**
  - **Pushes Undo:** Complete task, Auto-finish task, Downgrade task, Delete task.
  - **Does NOT Push Undo:** Restore task, Create task, regular edits, Placement/Label toggles, Delete label/location, History edits.
  - **Clears Undo Stack:** Workspace switch, Wipe TDF, applying Deletion Conflict (`TDF-DEL-003`) or Recovery (`TDF-REC-002`) resolution.

### `U-UX-005` Confirmation Patterns (Inline vs Typed Destructive Modal)
- **Inline In-Place Confirmation:** Use a prominent full-width danger confirmation bar (warning icon, bold prompt, right-aligned `Keep` / `Yes, delete`) for entity deletion inside expanded cards (Task, Label, Location, disabling the header Trash button while open) and workspace removal inside the Workspaces modal (noting the `.tdf` file is preserved; disabled when only one workspace exists).
- **Typed-Guard Modal Confirmation:** Use for irreversible destructive actions (Wipe Local TDF, Wipe Remote TDF): commit button stays disabled until the user types the exact `.tdf` base filename (without extension), paired with a default-checked `.bak / .bak.001+` backup checkbox.

### `U-UX-006` Settings Dual-Persistence & Dirty-State Contract
- **Auto-Saved Cards (`Auto-saved` badge):** Language, Appearance, Color Palette, Time Zone (including `37` manual UTC offsets matching `WebDavConfig.supportedUtcOffsetMinutes`), Deadline Lead Window, Foreground Location, Diagnostic Logging, Storage Mode, Local file watch toggle (desktop only), and Local file actions commit immediately.
- **Explicit WebDAV Dirty Flow:** Editing WebDAV URL, username, password, or path marks settings dirty and shows a `warning` `Unsaved changes` pill in BOTH the WebDAV card header and the docked footer.
- **Dynamic Dock Emphasis:** When dirty, `Save` promotes to `primary` and `Test Connection / Sync Now` demotes to `secondary`; when clean, `Test Connection / Sync Now` is `primary` (disabled in `local`-only mode) and `Save` is `secondary`. Switching to `local` clears dirty state and validation errors.
- **Validation & Platform Guards:** Validate HTTP(S) scheme with non-empty host, reject URL userinfo (`user:pass@`), require credentials, and reject `..`, `\`, and ASCII control characters in remote path with both per-field error text and a top danger banner. Show live resolved endpoint preview and password visibility toggle. Gate Local Storage `Move` (disabled with an explanatory desktop-only tooltip when unsupported) and `Select` (native OS file chooser vs in-app `UiDialogFrame` + `UiSearchablePicker` `.tdf` modal) on platform capability (`supportsDirectoryPickerProvider`), and hide the Local file watch toggle when `supportsLocalFileWatchProvider` is `false` (Android), rather than gating on viewport width.

### `U-UX-007` Operational, Diagnostic & Conflict/Recovery Views
- **Initial Loading:** Centered spinner + heading/subtitle replacing Tasks view and hiding the bottom dock.
- **Banner Hierarchy:** Unconfigured WebDAV (`warning`, non-dismissible, `Configure`); Sync Error and Generation Rollback (`danger`, dismissible, `Retry`/`Settings`); Partial File Read (`danger`, dismissible, per-target summary keeping board usable); Deletion Conflict (`TDF-DEL-003`) and Recovery (`TDF-REC-002`) (`warning`, non-dismissible, hidden while inside the resolution view; top chrome Sync button in `Conflict` state routes directly to resolution).
- **Full-Screen File-Read Error:** Replaces Tasks view and hides bottom dock; shows hero `cloud-off` icon, structured per-target Local/Remote diagnostics card, and `Settings` + `Retry` buttons.
- **Raw TDF Limit Exceeded:** Disables `Copy`, displays byte/line counts, and replaces the code block with a `warning` alert citing `TDF 0.8.0` Section 6.2 (`1 MiB` / `16,384` lines).
- **Conflict & Recovery Resolution Views:** List affected tasks, labels, and locations (`ENTITY · id`, title, detail) with safe default segmented choices (`Keep Edit (Undelete)` vs `Confirm Deletion`; `Recover as New (fresh ID)` vs `Discard Local Change`) and a docked footer (`Cancel` + `Apply & Sync`).
- **Forward-Geocoding Disambiguation & Diagnostics:** Single match auto-fills 6dp coordinates; multiple matches open a candidate selection modal. Diagnostic Log Viewer houses session metadata, a `Min Level` select, and multi-select `Subsystem` toggle pills (`UiPillVariant.selectable`) inside a unified flat `panel` control card (`1px` internal hairlines) with an active-subsystem count pill (`UiPillVariant.count`) and right-aligned compact `All`/`None` secondary buttons in the subsystem header row, alongside severity row styling (`meta`/`warn`/`error`/`crash`), distinct empty vs empty-filtered console hints, inline multi-line text selection and clipboard copy, automatic scrolling to the latest entries, conditional `Upload Log`, `Copy All`, `Copy Filtered`, `Scroll to Top`, and `Clear` (retaining `@meta` header lines).

## 9. Keyboard Shortcuts, Focus Management, Motion & Accessibility

### `U-A11Y-001` Thin Focus Rings & Composite Input Focus
- All interactive controls MUST display a `1px solid accent` focus-visible ring with `1px` offset (`focusRingWidth = 1`, `focusRingOffset = 1`).
- Standard bordered text inputs/selects/textareas switch their `1px` border color to `accent` on focus instead of drawing a doubled outer outline.
- Composite search and composer containers (`chrome-search`, sidebar filter, label picker search, quick-add box, quick-create bar) suppress inner field outlines and highlight the outer container border on focus-within, stripping redundant platform clear buttons so only one clear control renders.

### `U-A11Y-002` Desktop Keyboard Shortcuts & Layered `Escape` Order
- `Ctrl+F` / `Cmd+F` (works inside inputs; blocked only during modal, loading, or full-error) and `/` (outside inputs): open Global Search on Tasks view, close drafts, focus search field.
- `n` (outside inputs, when Task Quick-Add is available): expand compact composer if collapsed and focus Quick-Add title input.
- `Ctrl+Z` / `Cmd+Z` (outside inputs, Tasks view, no modal, non-empty Undo stack): trigger Undo.
- `ArrowLeft` / `ArrowRight` (outside inputs, Tasks view, not searching, no modal): step active tier (`0..5`) and clear expanded card.
- `ArrowDown` / `ArrowUp` (inside label picker search): highlight filtered labels and inline-create row with nearest-scroll visibility; `Enter` toggles or creates+assigns.
- `Enter`: submits/commits active single-line form, inline edit, draft title, subtask/link/history input, workspace create/rename, file picker/rename, or wipe confirmation.
- **Strict 9-Layer `Escape` Dismissal Order (highest priority first):**
  1. Label picker search query (clears non-empty query first; second `Escape` closes picker)
  2. Sidebar label/location filter input (closes and clears)
  3. Active modal dialog (closes and restores focus)
  4. Any open label picker
  5. Open uncommitted entity draft card
  6. Global Search (closes and clears query)
  7. Active inline section edit
  8. Active inline delete confirmation
  9. Expanded entity card

### `U-A11Y-003` Focus Trapping, Restoration & Mobile Keyboard Hygiene
- **Modal & Sheet Trapping:** Cyclically trap `Tab` / `Shift+Tab` inside active modal dialogs and compact bottom sheets. Record originating focus on open and restore it on close (clearing saved target on view/workspace switches).
- **Re-Render Stability:** Preserve active input focus and caret selection across in-scope state updates.
- **Mobile Bottom-Sheet Rule:** Opening the label picker in a desktop popover/inline card auto-focuses the search input; opening it in a compact mobile bottom sheet MUST NOT auto-focus the search input, avoiding immediate virtual-keyboard occlusion of the list.

### `U-A11Y-004` Motion & Opacity States
- Keep hover transitions crisp (`100ms`–`140ms` ease) and card expansion smooth (`220ms` ease-out + `180ms` opacity fade); spin active sync/location icons (`1s` linear) and loading indicator (`0.85s` linear).
- Standardize dimmed visual states: disabled controls (`0.48`), cycle-blocked prerequisites (`0.50`), suspended-disabled conditions (`0.45`), read-only coordinate inputs (`0.72`).

### `U-A11Y-005` Semantic Roles, Live Regions & Hit Targets
- Mark dialogs and mobile bottom sheets as modal semantics routes; announce floating notices and loading states politely (`liveRegion`); mark error/conflict/recovery/limit banners as alerts.
- Provide explicit accessible labels for every icon-only button, task complete/restore circle (`"<title> Complete|Restore"`), and clearable active-label filter; exclude decorative icons and sheet drag handles from the semantics tree.
- Enforce `40px` desktop and `44px` compact minimum touch targets and WCAG AA `>= 4.5:1` contrast across all presets.

## 10. Cross-Phase Verification Gates

### `U-GATE-001` Design System (`lib/ui/{tokens,primitives,layout,components}/`) Verification Gate
Widget tests in `test/ui/{tokens,primitives,layout,components}/` MUST prove:
- Strict internal sub-rank order (`tokens (0) < primitives (1) < layout (2) < components (3)`) and zero imports from app `lib/ui/` files, `lib/models/`, `lib/l10n/`, `lib/services/`, `lib/repositories/`, `lib/providers/`, `flutter_riverpod`, `dart:io`, or `dart:ffi`.
- All 4 presets (`Calm` and `Plum Umber`, Light and Dark) render cleanly and pass automated WCAG AA contrast checks (`>= 4.5:1`).
- Every primitive variant, density, and tone (`M-EXHAUSTIVE-STATE-TESTS`), focus/keyboard traversal, and breakpoint boundary (`390`, `720`, `721`, `760`, `820`, `821`, `1280`; `M-EXTREME-BOUND-TESTS`) match Sections 2–9.

### `U-GATE-002` Feature Shell & Interaction Verification Gate
Feature widget and integration tests in `test/ui/` MUST prove:
- Strict Rank `6` domain-direct UI compliance: app `lib/ui/` consumes `lib/models/`, `lib/l10n/`, pure `lib/services/`, `lib/providers/`, and `flutter_riverpod` directly through granular `.select(...)` and `.autoDispose` subscriptions while forbidding direct `lib/repositories/`, `dart:io`, `dart:ffi`, and `HttpClient` imports.
- Full feature, `en`/`de` localization, keyboard shortcut, 9-layer `Escape`, badge-order/overflow, non-jumping task creation, Settings auto-save vs WebDAV dirty flow, and `M-REAL-MECHANICS-TESTS` parity across Linux, Android, and Windows.

### `U-GATE-003` Retirement & Global Lock Verification Gate
Legacy UI code, retired `packages/tiertask_ui/`, `lib/presentation/`, `test/presentation/`, transitional `lib/ui_v2/` and `test/ui_v2/` directories, and unused ARB keys are removed (`P-NO-DEAD-CODE`), the 8-rank bottom-up DAG (`0..7`), universal Rank `0..3` design-system isolation, `lib/ui/ -> lib/repositories/` ban, and unconditional `export`/`part` ban apply globally, and `spec/UI_DESIGN_SYSTEM.md`, `ARCHITECTURE.md`, `AGENTS.md`, `README.md`, and `CHANGELOG.md` are synchronized with `tiertask_dev.py verify --full --fix` passing cleanly.
