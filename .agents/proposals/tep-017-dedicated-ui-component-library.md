---
id: TEP-017
title: Phase 2 Dedicated UI Component Library (packages/tiertask_ui), Theme Presets, Gallery App, and Multi-Package Tooling
status: concept
type: architecture
created: 2026-11-21
updated: 2026-11-21
---

# TEP-017: Phase 2 Dedicated UI Component Library (`packages/tiertask_ui/`), Theme Presets, Gallery App, and Multi-Package Tooling

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal specifies **Phase 2** of the umbrella architecture roadmap in [`TEP-015`](tep-015-ui-architecture-and-design-system-roadmap.md). Following completion of Phase 1 ([`TEP-016`](tep-016-presentation-layer-decoupling.md)) and user sign-off on the Design Gate prototype (`.agents/prototypes/ui_v2/`, codified in [`spec/UI_DESIGN_SYSTEM.md`](../../spec/UI_DESIGN_SYSTEM.md)), Phase 2 builds a compiler-isolated local Flutter package (`packages/tiertask_ui/`) containing verified design tokens (`Calm` default and `Plum Umber`, Light and Dark), exactly 17 orthogonal reusable widgets (`8` primitives, `4` adaptive layouts, `5` domain-agnostic composites), a runnable `example/` widget gallery, isolated widget and WCAG AA contrast tests, and multi-package verification inside `.agents/scripts/tiertask_dev.py`.

### 1.2 Motivation
TierTask's existing UI (`lib/ui/`) mixes Material defaults, `Slate`/`Navy` theme constants, and screen-specific widget implementations across 35 files. Before Phase 3 replaces the legacy screens under a strict ViewModel contract, the visual foundation must exist as an independent, strictly typed, test-verified component library for four reasons:
1. **Compiler-Enforced Isolation:** Keeping UI tokens and widgets inside `packages/tiertask_ui/` with zero dependency on `package:tiertask` or `package:flutter_riverpod` guarantees domain-agnostic APIs by construction, not convention alone.
2. **Design System Fidelity (`P-UI-DESIGN-SYSTEM`):** Every surface alternation rule, `1px` border and focus ring, WCAG AA contrast ratio (`>= 4.5:1`), breakpoint boundary (`<= 720`, `721..820`, `> 820`), and adaptive interaction pattern codified in `spec/UI_DESIGN_SYSTEM.md` must be built and verified once in reusable primitives rather than re-implemented per screen.
3. **Maximum Reuse, Minimum Widget Count (`U-FIDELITY-003`):** Consolidating the entire component surface into 17 composable widgets prevents UI sprawl and guarantees visual consistency across Tasks, Labels, Locations, Settings, Diagnostics, and Conflict/Recovery flows.
4. **Automated Multi-Package Verification:** `.agents/scripts/tiertask_dev.py` currently scans, formats, analyzes, digests, and tests only root `lib/` and `test/`. Without multi-package support, edits to `packages/tiertask_ui/` would bypass static rule enforcement, verification stamps, and CI checks.

### 1.3 Goals & Non-Goals
- **Goals:**
  - Create `packages/tiertask_ui/` as a standalone local Flutter package depending strictly on `flutter` and `material_ui: ^1.11.1` (zero `tiertask`, zero `flutter_riverpod`, zero `dart:io`, zero `dart:ffi`, zero third-party packages).
  - Implement Layer 1 (`tokens/`) covering `UiBreakpoints`, `UiColorTokens`, `UiContrastChecker`, `UiTypographyTokens`, `UiSpacingTokens`, `UiRadiusTokens`, `UiFocusTokens`, `UiThemeTokens` (`ThemeExtension`), and extensible `UiThemePreset` (`Calm` default and `Plum Umber`, Light and Dark) matching `spec/UI_DESIGN_SYSTEM.md` Section 3 values exactly.
  - Implement the 17 orthogonal widgets across Layer 2 (`primitives/`, 8 widgets), Layer 3 (`layout/`, 4 widgets), and Layer 4 (`components/`, 5 widgets) exported through one curated package barrel (`packages/tiertask_ui/lib/tiertask_ui.dart`) with full `U-SURFACE-*`, `U-LAYOUT-*`, `U-BRAND-*`, `U-COMP-*`, `U-CARD-*`, and `U-A11Y-*` fidelity.
  - Build a runnable `packages/tiertask_ui/example/` interactive gallery app exercising all 17 widgets across `Calm`/`Plum Umber`, Light/Dark modes, `DEV` badge toggle, and simulated Desktop (`1280px`), Medium (`760px`), and Compact (`390px`) viewports.
  - Write comprehensive isolated widget and unit tests in `packages/tiertask_ui/test/` and `packages/tiertask_ui/example/test/` covering all 4 theme presets, automated WCAG AA contrast checks (`>= 4.5:1`), all enum/tone/density variants (`M-EXHAUSTIVE-STATE-TESTS`), breakpoint boundaries (`390`, `720`, `721`, `760`, `820`, `821`, `1280`; `M-EXTREME-BOUND-TESTS`), keyboard traversal, 1px focus rings, modal/sheet focus trapping, and non-autofocus mobile bottom sheets.
  - Extend `.agents/scripts/tiertask_dev.py` (and `.agents/scripts/tests/test_tiertask_dev.py`), root `analysis_options.yaml`, and `ARCHITECTURE.md` so `format`, `analyze`, `test`, `arch`, `outline`, `find`, `deps`, `compute_code_digest`, and static checks (`GPL-3.0`, `P-NO-IGNORE`, `P-IO-ISOLATION`, scoped `export` barrel exception, and package isolation checks) cover `packages/tiertask_ui/` and `packages/tiertask_ui/example/`.
- **Non-Goals:**
  - Any modification to `spec/TDF_SPEC_0.8.0.md`, `lib/models/`, `lib/services/`, `lib/repositories/`, `lib/providers/`, `lib/presentation/`, `lib/ui/`, `lib/l10n/`, `lib/main.dart`, or root `pubspec.yaml` runtime wiring (deferred to Phase 3).
  - Hardcoding English or German application copy inside `packages/tiertask_ui/`; all user-visible labels, tooltips, hints, and accessible names MUST be caller-supplied `String` parameters (Phase 3 binds `AppLocalizations`).
  - Migrating `AppThemePalette` (`slate`/`navy` -> `calm`/`plumUmber`) or changing `SettingsCodec` (deferred to Phase 3 per `TEP-015` Section 2.2).
  - Introducing third-party icon packs, animation libraries, or color-picker packages (`P-STDLIB-FIRST`).

### 1.4 Description

#### Package Architecture & Scoped Entrypoint
`packages/tiertask_ui/` is a self-contained Flutter library package under `packages/tiertask_ui/`:
- **Public API Boundary:** Consumers import `package:tiertask_ui/tiertask_ui.dart` exclusively (`packages/tiertask_ui/lib/tiertask_ui.dart`). All implementation leaves live under `packages/tiertask_ui/lib/src/{tokens,primitives,layout,components}/`. Nested internal barrels inside `lib/src/` remain forbidden (`P-FILE-SIZE`).
- **Domain & Locale Neutrality:** Zero imports of `package:tiertask/*`, `package:flutter_riverpod/*`, `dart:io`, or `dart:ffi`. Every visible string, tooltip, validation error, and accessible label is injected by the caller so `packages/tiertask_ui/` works identically in `en`, `de`, tests, and the `example/` gallery without coupling to `AppLocalizations`.
- **Automatic Surface Alternation (`U-SURFACE-003`):** To faithfully replicate `.agents/prototypes/ui_v2/`'s `bg -> panel -> bg(inset) -> panel(re-elevated)` surface ladder without verbose manual color parameters, `UiCard` exposes an internal `InheritedWidget` (`UiSurfaceScope`) indicating whether descendants sit on `panel` or inside an inset `bg` container. `UiField` and nested chips read `UiSurfaceScope` automatically so inputs inside an editing `UiCard.inset` re-elevate from `bg` to `panel` cleanly.
- **Iconography Under `P-STDLIB-FIRST` (`U-BRAND-003`..`004`):** `packages/tiertask_ui/` uses Flutter/`material_ui` outline and rounded `IconData` glyphs (`Icons.*_outlined` / `Icons.*_rounded`) sized strictly via `UiSpacingTokens` (`iconXs = 13`, `iconSm = 15`, `iconMd = 18`, `iconLg = 34`) with semantic coloring from `UiColorTokens`. Only the TierTask brand mark (`UiAppLogo`) and the HSV color wheel (`UiColorWheel`) use `CustomPainter`.

#### Gallery Application (`packages/tiertask_ui/example/`)
A standalone runnable Flutter app demonstrating every token and widget without requiring TierTask workspaces, `.tdf` files, or WebDAV servers:
- Interactive top preview bar switching Theme Preset (`Calm`, `Plum Umber`), Color Mode (`Light`, `Dark`), `DEV` build pill toggle, and Simulated Viewport Width (`Desktop 1280`, `Medium 760`, `Compact 390`).
- Live interactive sections for Tokens & Contrast readout, Primitives (`UiAppLogo`, `UiButton`, `UiPill`, `UiSegmentedControl`, `UiCard`, `UiField`, `UiToggleRow`, `UiBanner`), Adaptive Layouts (`UiAdaptiveAppShell`, `UiSidebarSection`, `UiPageHeader`, `UiResponsiveGrid`), and Composites (`UiDialogFrame` modal + bottom sheet, `UiQuickComposer` with upward popover & compact collapsed trigger, `UiSearchablePicker` with scope pills & inline create, `UiOrderedItemList` with reorder/edit/delete, and `UiColorWheel` with 8 presets + HSV modal).

#### Multi-Package Tooling & Root Analyzer Boundary
- Root `analysis_options.yaml` adds `packages/**` to `analyzer.exclude` so root `flutter analyze` analyzes only the root package against root's `package_config.json`, while `packages/tiertask_ui/` and `packages/tiertask_ui/example/` each carry their own strict `analysis_options.yaml` and are analyzed explicitly in their own working directories by `tiertask_dev.py`.
- `.agents/scripts/tiertask_dev.py` treats `packages/tiertask_ui/` as a first-class subpackage across formatting, static checks, digest hashing, impacted-test resolution, `flutter analyze`, `flutter test`, `outline`, `find`, `deps`, and `ARCHITECTURE.md` auditing.

### 1.5 Alternatives
- **Dart Pub Workspace (`resolution: workspace`) in root `pubspec.yaml`:** Rejected for Phase 2 to keep root `pubspec.yaml` and `pubspec.lock` untouched until Phase 3 wires `tiertask_ui` into the application. Standalone `path:` resolution in `packages/tiertask_ui/` and `packages/tiertask_ui/example/` keeps Phase 2 completely decoupled with zero root dependency churn.
- **Hand-coding 44 SVG path painters inside `packages/tiertask_ui/` for Lucide icons:** Rejected under `P-STDLIB-FIRST` and `U-FIDELITY-003`. Maintaining 44 custom path strings adds hundreds of lines of brittle geometry without meaningful UX gain over Flutter's built-in `Icons.*_outlined` / `Icons.*_rounded` glyphs sized to `13/15/18/34px`, while `IconData` preserves native `IconTheme`, RTL mirroring, and `find.byIcon` testability.
- **Bundling `example/` gallery inside root `lib/` behind a debug flag:** Rejected because mixing gallery code into `lib/` violates `P-NO-DEAD-CODE` and weakens isolation proof; keeping `example/` inside `packages/tiertask_ui/example/` proves third-party-style public barrel consumption.
- **Allowing arbitrary `export` directives across `packages/tiertask_ui/lib/src/`:** Rejected per `TEP-015` Section 2.1 and `AGENTS.md` `P-FILE-SIZE`; only the single package entrypoint `packages/tiertask_ui/lib/tiertask_ui.dart` is exempted in `tiertask_dev.py`.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules

#### Package Directory Layout (`packages/tiertask_ui/`)

```text
packages/tiertask_ui/
├── analysis_options.yaml
├── pubspec.yaml
├── lib/
│   ├── tiertask_ui.dart
│   └── src/
│       ├── tokens/
│       │   ├── ui_breakpoints.dart
│       │   ├── ui_color_tokens.dart
│       │   ├── ui_focus_tokens.dart
│       │   ├── ui_radius_tokens.dart
│       │   ├── ui_spacing_tokens.dart
│       │   ├── ui_theme_tokens.dart
│       │   └── ui_typography_tokens.dart
│       ├── primitives/
│       │   ├── ui_app_logo.dart
│       │   ├── ui_banner.dart
│       │   ├── ui_button.dart
│       │   ├── ui_card.dart
│       │   ├── ui_field.dart
│       │   ├── ui_pill.dart
│       │   ├── ui_segmented_control.dart
│       │   └── ui_toggle_row.dart
│       ├── layout/
│       │   ├── ui_adaptive_app_shell.dart
│       │   ├── ui_page_header.dart
│       │   ├── ui_responsive_grid.dart
│       │   └── ui_sidebar_section.dart
│       └── components/
│           ├── ui_color_wheel.dart
│           ├── ui_dialog_frame.dart
│           ├── ui_ordered_item_list.dart
│           ├── ui_quick_composer.dart
│           └── ui_searchable_picker.dart
├── test/
│   ├── test_helpers.dart
│   ├── tokens/
│   │   ├── ui_breakpoints_test.dart
│   │   ├── ui_color_tokens_test.dart
│   │   └── ui_theme_tokens_test.dart
│   ├── primitives/
│   │   ├── ui_app_logo_test.dart
│   │   ├── ui_banner_test.dart
│   │   ├── ui_button_test.dart
│   │   ├── ui_card_test.dart
│   │   ├── ui_field_test.dart
│   │   ├── ui_pill_test.dart
│   │   ├── ui_segmented_control_test.dart
│   │   └── ui_toggle_row_test.dart
│   ├── layout/
│   │   ├── ui_adaptive_app_shell_test.dart
│   │   ├── ui_page_header_test.dart
│   │   ├── ui_responsive_grid_test.dart
│   │   └── ui_sidebar_section_test.dart
│   └── components/
│       ├── ui_color_wheel_test.dart
│       ├── ui_dialog_frame_test.dart
│       ├── ui_ordered_item_list_test.dart
│       ├── ui_quick_composer_test.dart
│       └── ui_searchable_picker_test.dart
└── example/
    ├── analysis_options.yaml
    ├── pubspec.yaml
    ├── lib/
    │   ├── gallery_sections.dart
    │   └── main.dart
    └── test/
        └── gallery_smoke_test.dart
```

#### Internal Acyclic Dependency Order Inside `packages/tiertask_ui/lib/src/`
Enforced statically in `tiertask_dev.py`:
- `tokens/` -> zero internal `src/` imports
- `primitives/` -> `tokens/` and acyclic `primitives/`
- `layout/` -> `tokens/`, `primitives/`, and acyclic `layout/`
- `components/` -> `tokens/`, `primitives/`, `layout/`, and acyclic `components/`
- `lib/tiertask_ui.dart` -> sole permitted barrel exporting public symbols from all four `src/` layers

#### Modified Root Repository Files
- `analysis_options.yaml`: add `- packages/**` under `analyzer.exclude`.
- `.agents/scripts/tiertask_dev.py`: multi-package discovery, static checks, internal `packages/tiertask_ui/` DAG & isolation checks, digest hashing, formatting, analyzer/test execution, `outline`/`find`/`deps`, and `ARCHITECTURE.md` sync/audit.
- `.agents/scripts/tests/test_tiertask_dev.py`: unit tests covering all new multi-package static, isolation, digest, and architecture checks.
- `ARCHITECTURE.md`: update `## Directory Layout` (adding `packages/tiertask_ui/`), add `UI Component Library` row in `## Architectural Layers`, and add `## UI Component Library` file table.
- `AGENTS.md`: note `packages/tiertask_ui/` scoped barrel exception and multi-package `tiertask_dev.py verify` coverage if not already reflected.

### 2.2 TDF Schema, Localization & State Changes
- **`spec/TDF_SPEC_0.8.0.md`:** Zero changes.
- **`spec/UI_DESIGN_SYSTEM.md`:** Normative contract followed verbatim (`U-FIDELITY-001`..`U-GATE-001`); zero deviations expected during Phase 2.
- **Domain Models, Providers & Persistence (`lib/models/`, `lib/providers/`, `lib/repositories/`):** Zero changes.
- **ARB Localization (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`):** Zero changes. `packages/tiertask_ui/` accepts all text, tooltips, hints, and accessible labels via widget parameters.
- **Theme Token Contract:** `UiThemePresets.calm` (default) and `UiThemePresets.plumUmber` ship all 19 exact hex colors per Light/Dark mode from `spec/UI_DESIGN_SYSTEM.md` Section 3 (`U-TOKEN-005`), including the dark-mode `onAccent` polarity flip (`#132a36` for Calm Dark, `#1e1429` for Plum Umber Dark).

### 2.3 Implementation Details

#### Layer 1: Tokens (`packages/tiertask_ui/lib/src/tokens/`)
1. **`UiBreakpoints` (`ui_breakpoints.dart`):**
   - `enum UiViewportClass { compact, medium, expanded }`
   - `static const double compactMaxWidth = 720.0;`
   - `static const double mediumMaxWidth = 820.0;`
   - `static UiViewportClass classify(double width)`: `<= 720` -> `compact`, `<= 820` -> `medium`, else `expanded` (`U-LAYOUT-001`).
   - `static bool isCompact(double width)` / `static bool isMediumOrSmaller(double width)` / `static bool isExpanded(double width)`.
2. **`UiColorTokens` & `UiContrastChecker` (`ui_color_tokens.dart`):**
   - `@immutable class UiColorTokens` holding all 19 color roles (`pageBg`, `bg`, `panel`, `ink`, `muted`, `line`, `accent`, `soft`, `onAccent`, `danger`, `dangerBg`, `dangerBorder`, `warning`, `warningBg`, `warningBorder`, `success`, `successBg`, `successBorder`, `scrim`), `copyWith`, `lerp`, `==`, `hashCode`.
   - `const UiContrastChecker._()` implementing WCAG 2.1 relative luminance and `contrastRatio(Color foreground, Color background)` (compositing translucent foregrounds when needed) plus `meetsWcagAa(Color foreground, Color background)` (`>= 4.5`) and `verifyTokens(UiColorTokens tokens)` returning all failing contrast pairs across the 17 normative pairs (`U-TOKEN-006`).
3. **`UiTypographyTokens` (`ui_typography_tokens.dart`):**
   - `@immutable class UiTypographyTokens` exposing all 13 text roles (`pageTitle`, `brand`, `modalTitle`, `compactBrand`, `cardTitle`, `body`, `control`, `rawCode`, `meta`, `chip`, `monoSmall`, `eyebrow`, `micro`, `devBadge`) using system sans and mono font stacks (`U-TOKEN-001`), plus `static TextStyle tabular(TextStyle style)` attaching `FontFeature.tabularFigures()`, `lerp`, `==`, `hashCode`.
4. **`UiSpacingTokens` (`ui_spacing_tokens.dart`):**
   - `@immutable class UiSpacingTokens` holding `space1` (`4`) through `space6` (`24`), `touchTarget` (`40`), `touchTargetMobile` (`44`), `chromeHeight` (`62`), `sidebarWidth` (`244`), `drawerMaxWidth` (`300`), `shellMaxWidth` (`1280`), `iconXs` (`13`), `iconSm` (`15`), `iconMd` (`18`), `iconLg` (`34`), `cardListGap` (`11`), `sectionGridGap` (`14`), `lerp`, `==`, `hashCode` (`U-TOKEN-002`..`003`, `U-BRAND-003`).
5. **`UiRadiusTokens` (`ui_radius_tokens.dart`):**
   - `@immutable class UiRadiusTokens` holding `logoBar` (`2`), `dotSm` (`3`), `dotLg` (`4`), `tag` (`6`), `sm` (`7`), `md` (`8`), `tierSelect` (`9`), `row` (`11`), `card` (`13`), `shell` (`16`), `pill` (`999`), `borderWidth` (`1.0`), `circleBorderWidth` (`1.7`), `spinnerStrokeWidth` (`2.5`), `lerp`, `==`, `hashCode` (`U-TOKEN-004`).
6. **`UiFocusTokens` (`ui_focus_tokens.dart`):**
   - `@immutable class UiFocusTokens` holding `ringWidth` (`1.0`), `ringOffset` (`1.0`), transition durations (`hoverDuration = 120ms`, `expandDuration = 220ms`, `fadeDuration = 180ms`, `spinDuration = 1000ms`, `loadingSpinDuration = 850ms`), dimmed opacities (`disabledOpacity = 0.48`, `prereqDisabledOpacity = 0.50`, `suspendedDimmedOpacity = 0.45`, `readonlyOpacity = 0.72`), and the exact 5 restricted drop shadows (`segmentedShadow`, `toastShadow`, `popoverShadow`, `bottomSheetShadow`, `modalShadow`) from `U-SURFACE-002` and `U-A11Y-004`.
7. **`UiThemeTokens` & `UiThemePresets` (`ui_theme_tokens.dart`):**
   - `@immutable class UiThemeTokens extends ThemeExtension<UiThemeTokens>` with `brightness`, `colors`, `typography`, `spacing`, `radii`, `focus`, `UiThemeTokens.of(BuildContext)` (asserts extension presence or falls back safely to `calmLight`), and `ThemeData toThemeData()` configuring flat zero-elevation Material 3 styling (`elevation: 0`, `scrolledUnderElevation: 0`, `surfaceTintColor: Colors.transparent`, `1px` `line` borders, `1px` `accent` focus borders).
   - `@immutable class UiThemePreset { final String id; final UiThemeTokens light; final UiThemeTokens dark; }`
   - `const UiThemePresets._()` providing `calm` (`id: 'calm'`, default), `plumUmber` (`id: 'plum_umber'`), `all`, and `byId(String id)` (falling back to `calm`).

#### Layer 2: Eight Core Primitives (`packages/tiertask_ui/lib/src/primitives/`)
All interactive primitives render a `1px` `accent` focus-visible ring (`ringOffset = 1px`) on keyboard focus (`FocusHighlightMode.traditional`) and expose explicit `Semantics` labels (`U-A11Y-001`, `U-A11Y-005`).
1. **`UiAppLogo` (`ui_app_logo.dart`):** `CustomPaint` drawing the three left-aligned stepped bars (`22x22` grid: `(0, 2, 22, 4) @ 1.0`, `(0, 9, 16.5, 4) @ 0.72`, `(0, 16, 11, 4) @ 0.42`, radius `2.0`) in `color ?? tokens.colors.accent`, marked `excludeFromSemantics: true` (`U-BRAND-001`).
2. **`UiButton` (`ui_button.dart`):**
   - `enum UiButtonVariant { primary, secondary, text, danger, icon }`
   - `enum UiButtonDensity { standard, compact }`
   - Enforces `40px` standard (`44px` when compact touch target requested) and `32px`/`30px` compact minimum heights, `isLoading` continuous rotation (`spinDuration`), `isDangerHover` danger-tinted hover state on icon buttons, `isAccent` accent tint, `isFullWidth`, `disabledOpacity = 0.48`.
3. **`UiPill` (`ui_pill.dart`):**
   - `enum UiPillVariant { badge, count, tag, meta, splitChip, addField, selectable }`
   - `enum UiPillTone { neutral, soft, accent, warning, danger, success }`
   - Supports optional `colorDot` (`8x8px` rounded square, radius `3px`), `icon`, `label`, `onPressed`, `onRemove` + `removeTooltip` (for `splitChip` with danger-hover `x` button), `isSelected` (`aria-pressed`/toggled semantics), `isDirect` (solid vs dashed border on `addField`), `isMono` (`DEV` badge), and tabular figures on `count` pills (`U-COMP-002`).
4. **`UiSegmentedControl<T>` (`ui_segmented_control.dart`):**
   - Immutable `UiSegment<T> { final T value; final String label; final IconData? icon; final bool enabled; }`
   - Equal-width horizontal segments inside a `bg` trough (`1px` `line`, `padding: 3px`, `gap: 4px`, `radiusMd: 8px`); selected tab uses `panel` fill, `accent` weight `600`, and `segmentedShadow`; supports `ArrowLeft`/`ArrowRight` focus stepping and `Semantics(selected: ...)` (`U-COMP-002`).
5. **`UiCard` & `UiSurfaceScope` (`ui_card.dart`):**
   - `enum UiCardVariant { standard, inset, draft, expandable }`
   - `enum UiSurfaceLevel { panel, insetWell }` exposed via internal `UiSurfaceScope` (`InheritedWidget`) so `UiField` and nested chips inside an editing `UiCard.inset` automatically flip from `bg` to `panel` (`U-SURFACE-003`).
   - `UiCard.standard`: flat `panel` + `1px` `line`, `radiusCard (13px)`, `16px` padding, optional header (`headerIcon`, `headerTitle`, `headerBadge`, `headerTrailing`).
   - `UiCard.inset`: `bg` well (`radiusRow: 11px`, `11x13px` padding); when `isEditing: true`, border changes to `1px` `accent` and `UiSurfaceScope` signals `UiSurfaceLevel.insetWell`.
   - `UiCard.draft`: `panel` + persistent `1px` `accent` border (`radiusCard: 13px`), header title/subtitle/close, body, inline error, and footer slots (`U-CARD-006`).
   - `UiCard.expandable`: unified entity card (`leading`, `title`, `trailingActions`, `collapsedMetadata`, `expandedChild`, `isExpanded`, `isCompleted`, `onToggleExpand`) with `34x34px` leading slot, `36px` desktop / `0px` compact collapsed metadata indent hidden when expanded, hover `accent` border suppressed while expanded, and `220ms` ease-out + `180ms` opacity reveal (`U-CARD-001`).
6. **`UiField` (`ui_field.dart`):**
   - `enum UiFieldKind { text, multiline, password, select, readOnlyDisplay }`
   - Reads `UiSurfaceScope.of(context)` to choose `bg` fill (on `panel`) or `panel` fill (inside `insetWell`).
   - Renders optional `label`, `TextField` / `DropdownButtonFormField` / monospace read-only well, single clear button when `showClearButton: true`, built-in `eye`/`eye-off` toggle for `password`, optional `helperText`, and `errorText` (`danger`, `11px`–`12px`, `Semantics(liveRegion: true)`), `readonly` at `0.72` opacity, and `1px` `accent` focus border (`U-A11Y-001`).
7. **`UiToggleRow` (`ui_toggle_row.dart`):**
   - Checkbox row (`17x17px` standard / `16x16px` dense) with `label`, optional muted `description`, `value`, `onChanged`, and full-row tap target (`minHeight: 40px` standard / `30px` dense); upholds the no-Switch convention (`U-COMP-002`).
8. **`UiBanner` (`ui_banner.dart`):**
   - `enum UiBannerVariant { status, toast, inlineWarning, inlineConfirm, emptyState, loadingState, fullError }`
   - `enum UiBannerTone { neutral, warning, danger, success }`
   - Covers status banners (optional `sublines`, primary action, dismiss `x`), floating bottom toast/Undo overlay (`maxWidth: 620`, `toastShadow`, optional action + mono `kbdHint` + dismiss), inline warning box, inline destructive confirmation bar (`cancelLabel` / `confirmLabel`), plain-text empty state, centered `32px` spinning loading state (`0.85s`), and centered `fullError` state (`34px` icon + diagnostics card + action buttons) with polite/alert `Semantics` (`U-COMP-002`, `U-A11Y-005`).

#### Layer 3: Four Adaptive Layout Primitives (`packages/tiertask_ui/lib/src/layout/`)
1. **`UiAdaptiveAppShell` (`ui_adaptive_app_shell.dart`):**
   - Evaluates `UiBreakpoints.classify(constraints.maxWidth)` via `LayoutBuilder`.
   - Renders `62px` top chrome bar (`brand`, `mobileActiveFilter`, `workspaceTrigger`, `searchWidget`, `isSearchOpen`, `trailingActions`, `isDrawerOpen`, `onToggleDrawer`) collapsing chrome siblings when `isCompact && isSearchOpen`, swapping `brand` for `mobileActiveFilter` when `isCompact && !isSearchOpen && mobileActiveFilter != null`, and revealing the `44x44px` menu toggle on `compact`.
   - Below chrome: persistent `244px` left sidebar (`> 720px`) OR slide-over drawer (`min(300px, 92% width)`) over `scrim` backdrop (`<= 720px`) with pinned `sidebarFooter`.
   - Main column splits `.main-scroll-wrap` (`Expanded` `Stack` with scrollable `body` or flexible `fullHeightBody` + bottom-anchored non-blocking `floatingNotice` `12px`/`10px` above bottom) from conditional pinned `bottomDock` (`bg` + top `1px` `line`) (`U-LAYOUT-002`..`005`).
   - Exposes `sidebarScrollController` and `mainScrollController` for scroll preservation (`U-LAYOUT-007`).
2. **`UiSidebarSection` (`ui_sidebar_section.dart`):**
   - Immutable `UiSidebarNavItem` data model (`id`, `label`, `subtitle`, `icon`, `colorDot`, `countLabel`, `isSelected`, `onTap`, `trailingIcon`, `trailingTooltip`, `onTrailingTap`).
   - Collapsible header showing eyebrow title, optional collapsed total count + active color dot (visible ONLY when `isCollapsed: true`), and up to 3 compact header icon buttons (`Filter`, `Manage`, `Collapse/Expand` at `26px` desktop / `34px` compact). Toggling filter while collapsed invokes `onExpandAndOpenFilter` / auto-focuses filter input; collapsing clears filter (`U-UX-001`).
3. **`UiPageHeader` (`ui_page_header.dart`):**
   - Optional top `backLabel` button (`onBack`), `28px` title + optional inline clickable `activeFilterLabel` (ellipsized, shown on desktop and conditionally on compact when `showInlineFilterOnCompact: true`) + tabular-nums `countLabel` pill + optional `trailing` action cluster + optional `subtitle` (`maxWidth: 58ch`) (`U-LAYOUT-004`).
4. **`UiResponsiveGrid` (`ui_responsive_grid.dart`):**
   - `enum UiGridPreset { twoColumnMediumCollapse, twoColumnCompactCollapse, fourActionCompactTwo }`
   - Uses `LayoutBuilder` against `UiBreakpoints` (`820px` and `720px`) to render equal-width columns with uniform `spacing`/`runSpacing` and top-aligned cells (`CrossAxisAlignment.start`), guaranteeing zero horizontal overflow (`U-LAYOUT-006`).

#### Layer 4: Five Domain-Agnostic Composites (`packages/tiertask_ui/lib/src/components/`)
1. **`UiDialogFrame` (`ui_dialog_frame.dart`):**
   - `enum UiDialogSize { small, medium, large }` (`420`, `520`, `600` logical px).
   - Renders bordered header (`17px` title + close `x`), independently scrollable body (`maxHeight: min(86% viewport, 720px)`), and bordered right-aligned footer inside `radiusShell (16px)` `panel` card with `modalShadow`.
   - Static helpers `UiDialogFrame.showModal<T>(...)` and `UiDialogFrame.showBottomSheet<T>(...)` (compact sheet: top `16px` radius, `maxHeight: 78%`, `36x4px` centered `line` handle, header with title/count/`doneLabel`, `bottomSheetShadow`, scrim dismiss).
   - Wraps overlay content in cyclical `FocusScope` + `FocusTraversalGroup`, traps `Tab`/`Shift+Tab`, supports `Escape` dismissal, and restores originating `FocusNode` on pop (`U-COMP-004`, `U-A11Y-003`).
2. **`UiQuickComposer` (`ui_quick_composer.dart`):**
   - Supports both docked Task Quick-Add (`isCollapsibleOnCompact: true`) and inline entity Quick-Create (`isCollapsibleOnCompact: false`).
   - On `compact` when collapsed, renders full-width primary `compactTriggerLabel` button; expanding shows stacked title field (`16px` on compact), `modeWidget`, `modeHint`, draft chips, `expandDraftLabel` (`Open as draft`), `submitLabel`, and compact close `x`.
   - On desktop, anchors `popoverContent` upward above the dock (`bottom: 100% + 8px`, `width: min(460px, available)`, `popoverShadow`) using `CompositedTransformTarget`/`CompositedTransformFollower` or `OverlayPortal` with outside-tap dismissal (`U-CARD-006`, `U-COMP-004`).
3. **`UiSearchablePicker<T>` (`ui_searchable_picker.dart`):**
   - Immutable `UiPickerOption<T> { final String id; final T value; final String label; final Color? colorDot; final String? badgeLabel; final String? countLabel; final String? disabledHint; final bool enabled; final bool hasInfoAction; }`
   - Immutable `UiPickerScopeFilter { final String id; final String label; }`
   - Renders optional selected removable chips, single-clear search input (`autoFocusSearch`, strictly defaulting to `false` inside compact bottom sheets per `U-A11Y-003`), conditional scope filter pills (rendered ONLY when `scopeFilters.length >= 2`), lazy `ListView.builder` (`maxHeight: 224px` desktop, `44px` rows compact) with custom `16x16px` check box + dot + name + badge + count + optional `info` button + disabled `0.5` opacity rows (`Cycle prevented`), and optional `inlineCreateLabel` row.
   - Keyboard handling: `ArrowDown`/`ArrowUp` step highlight across options + inline-create row (`ensureVisible`), `Enter` toggles highlighted (or first) option or creates, first `Escape` clears non-empty query, second `Escape` calls `onRequestClose` (`U-COMP-005`, `U-A11Y-002`).
4. **`UiOrderedItemList<T>` (`ui_ordered_item_list.dart`):**
   - Displays optional header (`title`, `countLabel` e.g. `N / 20` or `N / 200`), hairline-separated list (`ListView.builder` when scrollable or bounded `Column` inside scrollable parent), `editingIndex` highlight (`soft` fill + `radiusMd`), boundary-disabled `Move up` (disabled at `0`) and `Move down` (disabled at `length - 1`), optional inline `Edit` and danger-hover `Delete` compact icon buttons, `emptyText`, and bottom `addBar` slot (`U-COMP-006`).
5. **`UiColorWheel` (`ui_color_wheel.dart`):**
   - Exposes `static const List<Color> canonicalPresets` (`#2196F3`, `#4CAF50`, `#FF9100`, `#E91E63`, `#9C27B0`, `#00BCD4`, `#EB06FF`, `#00E5FF`).
   - Inline row (`34px` circular swatch, `110px` mono `#RRGGBB` input, `Custom color` compact button) + wrapping preset chips (`UiPill` / mono hex + dot, selected highlighted in `soft`/`accent`).
   - Modal picker (`UiDialogFrame` `small` width): live swatch + hex preview bar, `210x210px` circular `CustomPaint` HSV wheel (`SweepGradient` hues + radial white-to-transparent saturation + darkness overlay for Value `v`, drag/tap `GestureDetector` clamping to wheel radius, `8px`-radius filled thumb with `2.5px` white + `1px` dark halo), and `0..100%` Value `Slider` driven by local `ValueNotifier<HSVColor>` so dragging updates canvas and hex readout smoothly without parent rebuilds (`U-COMP-007`).

#### Multi-Package Tooling Changes (`.agents/scripts/tiertask_dev.py`)
1. **Package Registry:** Define `UI_PACKAGE_REL = Path("packages/tiertask_ui")` and `UI_EXAMPLE_REL = Path("packages/tiertask_ui/example")` helper paths checked conditionally (`if (root / UI_PACKAGE_REL).exists():`) so tests and tool runs work cleanly before and after scaffolding.
2. **`_iter_dart_files`:** Include `packages/tiertask_ui/lib`, `packages/tiertask_ui/test`, `packages/tiertask_ui/example/lib`, and `packages/tiertask_ui/example/test`.
3. **Static Checks (`run_static_checks`):**
   - Verify verbatim `GPL-3.0` header, LF line endings, and zero `// ignore:` directives across all `packages/tiertask_ui/**/*.dart` files.
   - Allow `export` directives ONLY in `packages/tiertask_ui/lib/tiertask_ui.dart`; reject `export`/`part`/`part of` in all other files (including `packages/tiertask_ui/lib/src/**`).
   - Enforce **strict package isolation** on every file under `packages/tiertask_ui/`: forbid `package:tiertask/`, `package:flutter_riverpod/`, `dart:io`, `dart:ffi`, and `HttpClient`.
   - Enforce **internal acyclic DAG** inside `packages/tiertask_ui/lib/src/`: `0: tokens < 1: primitives < 2: layout < 3: components`, zero circular SCCs, zero upward imports.
4. **`compute_code_digest` & `resolve_impacted_tests`:**
   - Hash `packages/tiertask_ui/pubspec.yaml`, `packages/tiertask_ui/analysis_options.yaml`, `packages/tiertask_ui/example/pubspec.yaml`, `packages/tiertask_ui/example/analysis_options.yaml`, and all `.dart` files under `packages/tiertask_ui/` so verification stamps invalidate on any UI package edit.
   - Resolve changed files in `packages/tiertask_ui/lib/src/<layer>/<name>.dart` to mirrored `packages/tiertask_ui/test/<layer>/<name>_test.dart` (and `packages/tiertask_ui/example/` changes to `packages/tiertask_ui/example/test/`), running `flutter test` in each impacted package's working directory.
5. **`run_verify`:**
   - `--fix` / `--full` runs `dart format` across root `lib test` AND `packages/tiertask_ui/lib packages/tiertask_ui/test packages/tiertask_ui/example/lib packages/tiertask_ui/example/test`.
   - Runs `flutter analyze --no-pub --fatal-infos --fatal-warnings` in root, `packages/tiertask_ui/`, and `packages/tiertask_ui/example/` (on `--full`, or on `--fast` for each package with relevant changes).
   - Runs `flutter test --no-pub --no-test-assets -r failures-only` per package (impacted suites on `--fast`, all suites in all three targets on `--full`).
6. **`ARCHITECTURE.md` & Lookup (`outline`, `find`, `deps`, `arch`):**
   - Extend `generate_architecture_tree` to include `packages/tiertask_ui/` (`lib/`, `test/`, `example/`), add `_layer_section_for_path` mapping `packages/tiertask_ui/lib/**` -> `## UI Component Library`, and extend `audit_architecture` to validate every `packages/tiertask_ui/lib/**/*.dart` row.
   - Extend `find_in_repo` (`--layer ui_pkg` or automatic inclusion when `--layer` is omitted) and `outline_repo_overview` to display `packages/tiertask_ui/`.

### 2.4 Testing Strategy
Develop every module via strict Red-Green-Refactor TDD (`P-TDD-FIRST`, `P-TEST-MIRROR`) with zero Riverpod or domain setup in `packages/tiertask_ui/test/`:
- **Shared Test Harness (`packages/tiertask_ui/test/test_helpers.dart`):** `pumpUiWidget(tester, child, {UiThemeTokens? tokens, Size surfaceSize})` wrapping the widget under test in `MaterialApp(theme: tokens.toThemeData(), home: Scaffold(body: child))` with explicit viewport sizing (`tester.view.physicalSize` + `devicePixelRatio: 1.0`, reset via `addTearDown`).
- **Token & Contrast Suites (`test/tokens/`):**
  - `M-EXHAUSTIVE-STATE-TESTS`: Verify all 4 built-in presets (`calm.light`, `calm.dark`, `plumUmber.light`, `plumUmber.dark`), exact hex values (`U-TOKEN-005`), `UiThemePreset` fallback lookup, `ThemeExtension.lerp` at `0.0 / 0.5 / 1.0`, and automated WCAG AA (`>= 4.5:1`) contrast across all 17 foreground/background pairs per preset (`68` pairs total, asserting exact `>= 4.5` pass and verifying failure detection on deliberately low-contrast synthetic tokens).
  - `M-EXTREME-BOUND-TESTS`: Verify `UiBreakpoints.classify` at exact boundaries `0`, `390`, `720` (`compact`), `721`, `760`, `820` (`medium`), `821`, `1280` (`expanded`).
- **Primitive Suites (`test/primitives/`):**
  - `M-EXHAUSTIVE-STATE-TESTS`: Every `UiButtonVariant` x `UiButtonDensity` + `isLoading` + disabled `0.48` opacity; every `UiPillVariant` x `UiPillTone` + split remove callback + dashed vs direct add chip; `UiSegmentedControl` selection + `ArrowLeft`/`ArrowRight`; every `UiCardVariant` (`standard`, `inset` editing surface re-elevation via `UiSurfaceScope`, `draft` accent border, `expandable` single reveal + hover suppression when expanded + desktop `36px` vs compact `0px` metadata indent); every `UiFieldKind` (password eye toggle, single clear button, inline error, `0.72` readonly opacity, `panel` fill inside `UiCard.inset(isEditing: true)`); `UiToggleRow` toggle + disabled; every `UiBannerVariant` x `UiBannerTone` + toast `maxWidth: 620` + Undo/kbd hint + semantics (`liveRegion`).
  - `UiAppLogo`: Golden-free geometry verification confirming `CustomPaint` renders 3 bars in `accent` color with `1.0 / 0.72 / 0.42` opacities and `excludeFromSemantics: true`.
- **Layout Suites (`test/layout/`):**
  - `UiAdaptiveAppShell` (`M-EXTREME-BOUND-TESTS` at `390`, `720`, `721`, `820`, `821`, `1280`): persistent `244px` sidebar (`>= 721`) vs slide-over drawer + scrim (`<= 720`), compact search hiding sibling chrome items, compact active label swapping brand slot, floating notice sitting strictly above pinned `bottomDock` without overlapping dock controls, and scroll controller offset preservation.
  - `UiSidebarSection`: collapsed count + active dot visibility, 3 header icon targets (`26px` desktop / `34px` compact), auto-expand on filter toggle, clear-filter on collapse.
  - `UiPageHeader`: inline active filter visibility desktop vs compact (`showInlineFilterOnCompact`), clear callback, tabular count pill, back button.
  - `UiResponsiveGrid`: exact column counts at `390`, `720`, `721`, `820`, `821`, `1280` for all 3 `UiGridPreset` variants.
- **Composite Suites (`test/components/`):**
  - `UiDialogFrame`: modal sizes (`420`/`520`/`600`), bottom sheet (`78%` max height, drag handle), cyclical `Tab`/`Shift+Tab` focus trap, `Escape` close, and focus restoration to trigger button on close.
  - `UiQuickComposer`: desktop always-open + upward popover with outside-tap dismissal vs compact collapsed `+ New task` toggle + expanded stacked layout + close `x`.
  - `UiSearchablePicker`: scope pills hidden when `< 2` scopes and shown when `>= 2`, inline create row on unique `1..120`-char query, disabled `Cycle prevented` rows (`0.5` opacity), keyboard `ArrowDown`/`ArrowUp`/`Enter`, two-step `Escape` (clear query first, close second), and `autoFocusSearch: false` enforcement in compact bottom sheet mode.
  - `UiOrderedItemList`: boundary-disabled `Move up` at index `0` and `Move down` at `length - 1`, `editingIndex` highlight, edit/delete callbacks, count readout.
  - `UiColorWheel`: exact 8 `canonicalPresets`, hex input parsing (`#RRGGBB`, invalid input rejection), HSV wheel drag/tap color conversion accuracy, and Value slider updating color smoothly.
- **Gallery Smoke Suite (`packages/tiertask_ui/example/test/gallery_smoke_test.dart`):** Pumps gallery across `Calm`/`Plum Umber`, Light/Dark, and `390px`/`760px`/`1280px` verifying interactive switches and zero layout overflow exceptions.
- **Tooling Suite (`.agents/scripts/tests/test_tiertask_dev.py`):** Verifies `packages/tiertask_ui/` scoped barrel carve-out (passes `lib/tiertask_ui.dart`, rejects `export` inside `lib/src/`), forbidden `package:tiertask/` / `package:flutter_riverpod/` / `dart:io` / `dart:ffi` rejection, internal `tokens -> primitives -> layout -> components` DAG enforcement, digest invalidation on package edits, and `ARCHITECTURE.md` audit coverage.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [ ] Review and finalize `TEP-017` (optionally via `/tep .agents/proposals/tep-017-dedicated-ui-component-library.md`) and advance status from `concept` to `planned`.
- [ ] Run `python3 .agents/scripts/tiertask_dev.py verify --fast` to confirm a clean baseline.
- [ ] Extend `.agents/scripts/tiertask_dev.py` (with Red-Green TDD in `.agents/scripts/tests/test_tiertask_dev.py`) and root `analysis_options.yaml` for `packages/tiertask_ui/` and `packages/tiertask_ui/example/` multi-package support.
- [ ] Scaffold `packages/tiertask_ui/` (`pubspec.yaml`, `analysis_options.yaml`, `lib/tiertask_ui.dart`, `test/test_helpers.dart`) and run `flutter pub get` inside `packages/tiertask_ui/`.
- [ ] Implement Layer 1 (`tokens/`: 7 files) with Red-Green-Refactor TDD tests (including automated WCAG AA contrast verification and breakpoint boundary tests).
- [ ] Implement Layer 2 (`primitives/`: 8 widgets) with Red-Green-Refactor TDD widget tests across all variants, densities, tones, focus rings, and surface alternation.
- [ ] Implement Layer 3 (`layout/`: 4 adaptive layouts) with Red-Green-Refactor TDD widget tests across `390 / 720 / 721 / 760 / 820 / 821 / 1280` viewports.
- [ ] Implement Layer 4 (`components/`: 5 composites) with Red-Green-Refactor TDD widget tests covering focus trapping, keyboard navigation, bottom-sheet hygiene, and HSV wheel interaction.
- [ ] Build `packages/tiertask_ui/example/` runnable interactive gallery app and passing smoke tests.
- [ ] Update Parts 1 and 2 if implementation refines any API detail.
- [ ] Run `python3 .agents/scripts/tiertask_dev.py verify --full --fix` and `python3 -m unittest discover -s .agents/scripts/tests -v`.
- [ ] Follow **`update-documentation`** to synchronize `ARCHITECTURE.md` and `AGENTS.md` (skip `CHANGELOG.md` because `packages/tiertask_ui/` is internal infrastructure not yet user-facing until Phase 3 cutover).
- [ ] Set `status: review`, update `BOARD.md`, and request user approval.
- [ ] After user approval, set `status: completed`, update `BOARD.md`, check off Phase 2 in `TEP-015`, and list delivered artifacts in Part 3.3.

### 3.2 Work Log & Decisions
- **2026-11-21:** Drafted Phase 2 child proposal `TEP-017` under [`TEP-015`](tep-015-ui-architecture-and-design-system-roadmap.md) aligned with [`spec/UI_DESIGN_SYSTEM.md`](../../spec/UI_DESIGN_SYSTEM.md) and the signed-off `.agents/prototypes/ui_v2/` concept.

### 3.3 Delivered Artifacts
*(Complete upon approval)*
