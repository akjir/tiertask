---
id: TEP-017
title: Phase 2 Dedicated UI Component Library (packages/tiertask_ui), Theme Presets, Gallery App, and Multi-Package Tooling
status: completed
type: architecture
created: 2026-11-21
updated: 2026-11-21
---

# TEP-017: Phase 2 Dedicated UI Component Library (`packages/tiertask_ui/`), Theme Presets, Gallery App, and Multi-Package Tooling

> [!NOTE]
> Superseded in architecture by [`TEP-020`](tep-020-unified-ui-integration-and-reactive-architecture.md): `TEP-020` dissolved the standalone `packages/tiertask_ui/` package split and retired the mandatory `lib/presentation/` adapter layer by integrating the 24 design-system modules into `lib/ui/{tokens,primitives,layout,components}/` and restoring direct reactive `lib/ui/ -> lib/providers/` state access while preserving 100% of the visual design system and UX contracts.

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
  - Create `packages/tiertask_ui/` as a standalone local Flutter package (`publish_to: none`, `sdk: ^3.14.0`) depending strictly on `flutter` and `material_ui: ^1.11.1`, with dev dependencies `flutter_test` and `flutter_lints: ^6.0.0` (zero `tiertask`, zero `flutter_riverpod`, zero `dart:io`, zero `dart:ffi`, zero third-party packages).
  - Implement Layer 1 (`tokens/`) covering `UiBreakpoints`, `UiColorTokens`, `UiContrastChecker`, `UiTypographyTokens`, `UiSpacingTokens`, `UiRadiusTokens`, `UiFocusTokens`, `UiSurfaceLevel`/`UiSurfaceScope`, `UiThemeTokens` (`ThemeExtension`), and extensible `UiThemePreset` (`Calm` default and `Plum Umber`, Light and Dark) matching `spec/UI_DESIGN_SYSTEM.md` Section 3 values exactly.
  - Implement the strictly minimal orthogonal catalog of 17 widgets across Layer 2 (`primitives/`, 8 widgets), Layer 3 (`layout/`, 4 widgets), and Layer 4 (`components/`, 5 widgets) exported through one curated package barrel (`packages/tiertask_ui/lib/tiertask_ui.dart`), proving every view and interaction in `spec/UI_DESIGN_SYSTEM.md` composes cleanly in Phase 3 without adding bespoke duplicate widgets.
  - Build a runnable `packages/tiertask_ui/example/` interactive gallery app (`uses-material-design: true`, minimal `linux/` desktop runner) exercising all 17 widgets across `Calm`/`Plum Umber`, Light/Dark modes, `DEV` badge toggle, and simulated Desktop (`1280px`), Medium (`760px`), and Compact (`390px`) viewports.
  - Write comprehensive isolated widget and unit tests in `packages/tiertask_ui/test/` and `packages/tiertask_ui/example/test/` covering all 4 theme presets, automated WCAG AA contrast checks (`>= 4.5:1` across all 17 normative color pairs), all enum/tone/density variants (`M-EXHAUSTIVE-STATE-TESTS`), breakpoint boundaries (`390`, `720`, `721`, `760`, `820`, `821`, `1280`; `M-EXTREME-BOUND-TESTS`), keyboard traversal, `1px` focus rings and input focus borders, modal/sheet focus trapping, non-swallowing popover outside-tap dismissal, and non-autofocus mobile bottom sheets.
  - Extend `.agents/scripts/tiertask_dev.py` (and `.agents/scripts/tests/test_tiertask_dev.py`), root `analysis_options.yaml`, `ARCHITECTURE.md`, and `AGENTS.md` so `format`, `analyze`, `test`, `arch`, `scaffold`, `outline`, `find`, `deps`, `compute_code_digest`, and static checks (`GPL-3.0`, `P-NO-IGNORE`, `P-IO-ISOLATION`, scoped `export` barrel exception, and package isolation checks) cover `packages/tiertask_ui/` and `packages/tiertask_ui/example/`.
- **Non-Goals:**
  - Any modification to `spec/TDF_SPEC_0.8.0.md`, `lib/models/`, `lib/services/`, `lib/repositories/`, `lib/providers/`, `lib/presentation/`, `lib/ui/`, `lib/l10n/`, `lib/main.dart`, or root `pubspec.yaml` runtime wiring (deferred to Phase 3).
  - Hardcoding English or German application copy inside `packages/tiertask_ui/`; all user-visible labels, tooltips, hints, validation messages, and accessible names MUST be caller-supplied `String` parameters (Phase 3 binds `AppLocalizations`).
  - Migrating `AppThemePalette` (`slate`/`navy` -> `calm`/`plumUmber`) or changing `SettingsCodec` (deferred to Phase 3 per `TEP-015` Section 2.2).
  - Introducing third-party icon packs, animation libraries, dashed-border packages, or color-picker packages (`P-STDLIB-FIRST`).

### 1.4 Description

#### Package Architecture & Scoped Entrypoint
`packages/tiertask_ui/` is a self-contained Flutter library package under `packages/tiertask_ui/`:
- **Public API Boundary:** Consumers import `package:tiertask_ui/tiertask_ui.dart` exclusively (`packages/tiertask_ui/lib/tiertask_ui.dart`). All implementation leaves live under `packages/tiertask_ui/lib/src/{tokens,primitives,layout,components}/`. Nested internal barrels inside `lib/src/` and direct `package:tiertask_ui/src/...` imports from `test/` or `example/` remain forbidden (`P-FILE-SIZE`).
- **Domain & Locale Neutrality:** Zero imports of `package:tiertask/*`, `package:flutter_riverpod/*`, `dart:io`, or `dart:ffi`. Every visible string, tooltip, validation error, and accessible label is injected by the caller so `packages/tiertask_ui/` works identically in `en`, `de`, tests, and the `example/` gallery without coupling to `AppLocalizations`.
- **Automatic Surface Alternation (`U-SURFACE-003`):** To faithfully replicate `.agents/prototypes/ui_v2/`'s `bg -> panel -> bg(inset) -> panel(re-elevated)` surface ladder without verbose manual color parameters or circular primitive imports, Layer 1 (`tokens/ui_theme_tokens.dart`) defines `UiSurfaceLevel` (`panel`, `insetWell`) and `UiSurfaceScope` (`InheritedWidget`). Every `UiCard.inset` (`bg` fill, whether reading or editing) wraps its subtree in `UiSurfaceScope(level: UiSurfaceLevel.insetWell)`, and `UiField`, `UiPill`, and nested interactive rows read `UiSurfaceScope.of(context)` automatically to re-elevate from `bg` to `panel`.
- **Iconography & Custom Painting Under `P-STDLIB-FIRST` (`U-BRAND-003`..`004`):** `packages/tiertask_ui/` realizes `U-BRAND-003` offline stroke iconography using Flutter/`material_ui` outline and rounded `IconData` glyphs (`Icons.*_outlined` / `Icons.*_rounded`) sized strictly via `UiSpacingTokens` (`iconXs = 13`, `iconSm = 15`, `iconMd = 18`, `iconLg = 34`) with semantic coloring from `UiColorTokens`. Exactly three internal `CustomPainter` implementations exist in the package: the three-bar brand mark (`UiAppLogo`), the dashed rounded-rectangle border for `UiPillVariant.addField` (`isDirect: false`), and the circular HSV wheel (`UiColorWheel`).

#### Gallery Application (`packages/tiertask_ui/example/`)
A standalone runnable Flutter app (including a minimal `linux/` desktop runner and `uses-material-design: true`) demonstrating every token and widget without requiring TierTask workspaces, `.tdf` files, or WebDAV servers:
- Interactive top preview bar switching Theme Preset (`Calm`, `Plum Umber`), Color Mode (`Light`, `Dark`), `DEV` build pill toggle, and Simulated Viewport Width (`Desktop 1280`, `Medium 760`, `Compact 390`).
- Live interactive sections for Tokens & Contrast readout, Primitives (`UiAppLogo`, `UiButton`, `UiPill`, `UiSegmentedControl`, `UiCard`, `UiField`, `UiToggleRow`, `UiBanner`), Adaptive Layouts (`UiAdaptiveAppShell`, `UiSidebarSection`, `UiPageHeader`, `UiResponsiveGrid`), and Composites (`UiDialogFrame` modal + bottom sheet, `UiQuickComposer` with upward `TapRegion` popover, compact collapsed trigger, and inline quick-create variant, `UiSearchablePicker` in multi-select and single-select modes with scope pills & inline create, `UiOrderedItemList` with optional reorder/progress/edit/delete, and `UiColorWheel` with 8 presets + HSV modal).

#### Multi-Package Tooling & Root Analyzer Boundary
- Root `analysis_options.yaml` adds `packages/**` to `analyzer.exclude` so root `flutter analyze` analyzes only the root package against root's `package_config.json`. Both `packages/tiertask_ui/` and `packages/tiertask_ui/example/` carry dedicated `analysis_options.yaml` files mirroring root's strict language flags (`strict-casts`, `strict-inference`, `strict-raw-types`) and all 12 custom linter rules (without root's legacy `deprecated_member_use_from_same_package: ignore`) and are analyzed explicitly in their own working directories by `tiertask_dev.py`.
- `.agents/scripts/tiertask_dev.py` treats `packages/tiertask_ui/` and `packages/tiertask_ui/example/` as first-class subpackages across formatting, static checks, digest hashing, impacted-test resolution, `flutter analyze`, `flutter test`, `outline`, `find`, `deps`, `scaffold`, and `ARCHITECTURE.md` auditing.

### 1.5 Alternatives
- **Dart Pub Workspace (`resolution: workspace`) in root `pubspec.yaml`:** Rejected for Phase 2 to keep root `pubspec.yaml` and `pubspec.lock` untouched until Phase 3 wires `tiertask_ui` into the application. Standalone `path:` resolution in `packages/tiertask_ui/` and `packages/tiertask_ui/example/` keeps Phase 2 completely decoupled with zero root dependency churn.
- **Hand-coding 56 SVG path painters inside `packages/tiertask_ui/` for prototype icons:** Rejected under `P-STDLIB-FIRST` and `U-FIDELITY-003`. Maintaining 56 custom path strings (`.agents/prototypes/ui_v2/icons.js`) adds brittle geometry without meaningful UX gain over Flutter's built-in `Icons.*_outlined` / `Icons.*_rounded` glyphs sized to `13/15/18/34px`, while `IconData` preserves native `IconTheme`, RTL mirroring, and `find.byIcon` testability.
- **Merging further below 17 widgets (e.g., folding `UiButton` into `UiPill` or removing `UiPageHeader`/`UiResponsiveGrid`):** Rejected because folding unrelated semantics into god-widgets violates `P-CLASS-COHESION` and `P-EXHAUSTIVE-SWITCH`, while removing layout or composite primitives pushes duplicated responsive breakpoint, keyboard-picker, and focus-trapping code into 3 to 9 Phase 3 screens.
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
    ├── linux/
    ├── lib/
    │   ├── gallery_sections.dart
    │   └── main.dart
    └── test/
        └── gallery_smoke_test.dart
```

#### Internal Acyclic Dependency Order Inside `packages/tiertask_ui/`
Enforced statically in `tiertask_dev.py`:
- Rank `0` (`lib/src/tokens/`) -> acyclic Rank `0` only (zero imports from `primitives/`, `layout/`, `components/`, or `lib/tiertask_ui.dart`; also houses `UiSurfaceLevel` and `UiSurfaceScope` in `ui_theme_tokens.dart` so all primitives share surface alternation with zero circular imports)
- Rank `1` (`lib/src/primitives/`) -> Rank `0` and acyclic Rank `1`
- Rank `2` (`lib/src/layout/`) -> Ranks `0`..`1` and acyclic Rank `2`
- Rank `3` (`lib/src/components/`) -> Ranks `0`..`2` and acyclic Rank `3`
- Rank `4` (`lib/tiertask_ui.dart`) -> sole permitted barrel exporting public symbols from Ranks `0`..`3`; no `lib/src/` file may import `lib/tiertask_ui.dart`, and `test/` and `example/` import `package:tiertask_ui/tiertask_ui.dart` exclusively (never `package:tiertask_ui/src/...`)

#### Minimal-Widget Reuse Justification & Phase 3 Coverage Matrix (`U-FIDELITY-003`)
The catalog is capped at strictly **17 orthogonal widgets** (as few as possible, as many as necessary so Phase 3 achieves 100% parity with `spec/UI_DESIGN_SYSTEM.md` without bespoke widget sprawl):

| Layer | Widget | Primary Phase 3 Consumers & Reuse Justification |
| :--- | :--- | :--- |
| Primitives (`8`) | `UiAppLogo` | Three-bar brand mark (`CustomPaint`) reused in desktop brand button and compact active-label chrome button (`U-BRAND-001`, `U-LAYOUT-004`). |
| Primitives | `UiButton` | All primary, secondary, text, danger, icon, chrome workspace/sync, sidebar header, and `44px` compact touch actions. |
| Primitives | `UiPill` | Status badges, tabular count pills, `DEV` pill, color-dotted label tags, split navigable/removable chips, dashed `+ Add` chips, direct toggles, weekday pills, scope pills, and color preset chips. |
| Primitives | `UiSegmentedControl<T>` | Placement (`Queue`/`Priority`/`Someday`), Label Scope, Theme Mode, Location/Diagnostics Off/On, Conflict/Recovery decisions, Condition modes, and Location Source (`8+` consumers; replaces Switch widgets). |
| Primitives | `UiCard` | Static Settings/Conflict/Workspace/Console/Raw-TDF cards (`standard`), nested `bg` section wells (`inset`), uncommitted draft cards (`draft`), and unified Task/Label/Location accordions (`expandable`). |
| Primitives | `UiField` | Single-line text, multiline notes, password with reveal toggle, flat bordered selects (including `44px` compact tier select), tap-to-pick date/time fields, focus-within search inputs (chrome search, sidebar filter, picker search), and monospace read-only wells. |
| Primitives | `UiToggleRow` | Binary checkbox rows with optional descriptions (Local file watch, Wipe `.bak` backup, Subtasks Auto-finish, Conditions ignore/location toggles). |
| Primitives | `UiBanner` | Status/sync/conflict/limit banners (0 to 2 actions), floating bottom Undo/status toasts, inline card warnings, inline destructive delete confirmations, plain-text empty states, centered loading states, and full-screen file-read error views. |
| Layouts (`4`) | `UiAdaptiveAppShell` | Single adaptive application frame across all 9 views (top chrome, persistent sidebar vs below-chrome compact drawer, lazy-list-compatible viewport + floating notice stack, pinned bottom dock). |
| Layouts | `UiSidebarSection` | Reused 4 times in sidebar (`Tasks`, `Labels`, `Locations`, `Tools`) covering static eyebrow groups and collapsible/filterable groups with split or single-button nav rows. |
| Layouts | `UiPageHeader` | Reused across all 9 views (`Tasks`, `Search`, `Labels`, `Locations`, `Settings`, `Diagnostics`, `Raw TDF`, `Conflict`, `Recovery`) with back link, `28px` title, inline active-label filter, tabular count pill, trailing actions, and `58ch` subtitle. |
| Layouts | `UiResponsiveGrid` | Reused across Settings, inline/draft form pairs, 4-action Local Storage bar, and Conflict/Recovery cards using canonical `820px` and `720px` breakpoints. |
| Composites (`5`) | `UiDialogFrame` | Focus-trapped centered modals (`Workspaces`, `Location Status`, `Select Local File`, `Rename Local File`, `Wipe TDF`, `Color Picker`, `Geocoding Candidates`) and compact mobile bottom sheets (`Label Picker`). |
| Composites | `UiQuickComposer` | Docked Task Quick-Add (with compact `+ New task` collapse and upward desktop popover) and inline Labels/Locations Quick-Create bars (`3` views). |
| Composites | `UiSearchablePicker<T>` | Multi-select Label Picker (`3` modes + bottom sheet), Prerequisite Picker (cycle-disabled rows), and single-select Local `.tdf` File Picker and Geocoding Candidate Picker (`4` pickers). |
| Composites | `UiOrderedItemList<T>` | Repeatable list pattern for Subtasks (checkbox, progress bar, reorder, Auto-finish), Reference Links (reorder, inline edit, read-only cards), Time Windows (add/remove), and History Journal (inline edit, timestamp add bar, canonical sort). |
| Composites | `UiColorWheel` | Inline swatch + `#RRGGBB` input + 8 canonical presets + `CustomPaint` HSV wheel modal with Value slider (Label expanded card and Label draft card). |

Domain-specific single-use micro-elements (such as the task completion circle passed into `UiCard.expandable(leading: ...)`, or horizontal `SingleChildScrollView` log/TDF code text placed inside `UiCard.standard`) compose directly in Phase 3 using Layer 1 tokens without adding an 18th reusable widget.

#### Modified Root Repository Files
- `analysis_options.yaml`: add `- packages/**` under `analyzer.exclude`.
- `.agents/scripts/tiertask_dev.py`: multi-package discovery, static checks, internal `packages/tiertask_ui/` DAG & isolation checks, `package:tiertask_ui/` import/export graph resolution, digest hashing, formatting, analyzer/test execution, `outline`/`find`/`deps`/`scaffold`, and `ARCHITECTURE.md` sync/audit.
- `.agents/scripts/tests/test_tiertask_dev.py`: unit tests covering all new multi-package static, isolation, digest, impacted-test, and architecture checks.
- `ARCHITECTURE.md`: update `## Directory Layout` (adding `packages/tiertask_ui/`), add `UI Component Library` row in `## Architectural Layers`, and add `## UI Component Library` file table.
- `AGENTS.md`: document the `packages/tiertask_ui/lib/tiertask_ui.dart` scoped barrel exception under `P-FILE-SIZE` and multi-package `tiertask_dev.py verify` coverage.

### 2.2 TDF Schema, Localization & State Changes
- **`spec/TDF_SPEC_0.8.0.md`:** Zero changes.
- **`spec/UI_DESIGN_SYSTEM.md`:** Normative contract followed verbatim (`U-FIDELITY-001`..`U-GATE-001`). Offline stroke iconography (`U-BRAND-003`) is realized under `P-STDLIB-FIRST` via Flutter/`material_ui` outlined and rounded `IconData` glyphs sized via `UiSpacingTokens`; zero visual or behavioral regressions from `.agents/prototypes/ui_v2/`.
- **Domain Models, Providers & Persistence (`lib/models/`, `lib/providers/`, `lib/repositories/`):** Zero changes.
- **ARB Localization (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`):** Zero changes. `packages/tiertask_ui/` accepts all visible strings, tooltips, hints, validation errors, and accessible labels via widget parameters.
- **Theme Token Contract:** `UiThemePresets.calm` (default) and `UiThemePresets.plumUmber` ship all 19 exact hex colors per Light/Dark mode from `spec/UI_DESIGN_SYSTEM.md` Section 3 (`U-TOKEN-005`), including the dark-mode `onAccent` polarity flip (`#132a36` for Calm Dark, `#1e1429` for Plum Umber Dark).

### 2.3 Implementation Details

#### Package Configuration (`packages/tiertask_ui/` & `packages/tiertask_ui/example/`)
- **`packages/tiertask_ui/pubspec.yaml`:** `name: tiertask_ui`, `publish_to: none`, `environment: sdk: ^3.14.0`, `dependencies: flutter (sdk)` and `material_ui: ^1.11.1`, `dev_dependencies: flutter_test (sdk)` and `flutter_lints: ^6.0.0`.
- **`packages/tiertask_ui/example/pubspec.yaml`:** `name: tiertask_ui_example`, `publish_to: none`, `environment: sdk: ^3.14.0`, `dependencies: flutter (sdk)`, `material_ui: ^1.11.1`, and `tiertask_ui: path: ..`, `dev_dependencies: flutter_test (sdk)` and `flutter_lints: ^6.0.0`, `flutter: uses-material-design: true`.
- **`analysis_options.yaml` (both subpackages):** Include `package:flutter_lints/flutter.yaml`, enforce `strict-casts: true`, `strict-inference: true`, `strict-raw-types: true`, exclude `build/**` (plus `linux/**` in `example/`), and enable all 12 root linter rules (`avoid_print`, `cancel_subscriptions`, `close_sinks`, `directives_ordering`, `prefer_const_constructors`, `prefer_const_declarations`, `prefer_const_literals_to_create_immutables`, `prefer_relative_imports`, `require_trailing_commas`, `unawaited_futures`, `use_build_context_synchronously`, `use_super_parameters`) with zero `ignore` entries.

#### Layer 1: Tokens (`packages/tiertask_ui/lib/src/tokens/`)
1. **`UiBreakpoints` (`ui_breakpoints.dart`):**
   - `enum UiViewportClass { compact, medium, expanded }`
   - `static const double compactMaxWidth = 720.0;`
   - `static const double mediumMaxWidth = 820.0;`
   - `static UiViewportClass classify(double width)`: `<= 720` -> `compact`, `<= 820` -> `medium`, else `expanded` (`U-LAYOUT-001`).
   - `static bool isCompact(double width)` / `static bool isMediumOrSmaller(double width)` / `static bool isExpanded(double width)`.
2. **`UiColorTokens` & `UiContrastChecker` (`ui_color_tokens.dart`):**
   - `@immutable class UiColorTokens` holding all 19 color roles (`pageBg`, `bg`, `panel`, `ink`, `muted`, `line`, `accent`, `soft`, `onAccent`, `danger`, `dangerBg`, `dangerBorder`, `warning`, `warningBg`, `warningBorder`, `success`, `successBg`, `successBorder`, `scrim`), `copyWith`, `lerp`, `==`, `hashCode`.
   - `const UiContrastChecker._()` implementing WCAG 2.1 relative luminance and `contrastRatio(Color foreground, Color background)` (alpha-compositing translucent foregrounds over background when needed), `meetsWcagAa(Color foreground, Color background)` (`>= 4.5`), and `verifyTokens(UiColorTokens tokens)` validating all **17 normative foreground/background pairs** (`U-TOKEN-006` + inline semantic text on resting surfaces):
     - `ink`, `muted`, `accent`, `danger`, `warning`, `success` on `panel` (`6` pairs) and on `bg` (`6` pairs)
     - `accent` on `soft` (`1` pair) and `onAccent` on `accent` (`1` pair)
     - `danger` on `dangerBg`, `warning` on `warningBg`, `success` on `successBg` (`3` pairs)
3. **`UiTypographyTokens` (`ui_typography_tokens.dart`):**
   - `@immutable class UiTypographyTokens` exposing `sansFontFamily`, `monoFontFamily`, and **14 `TextStyle` fields covering all 13 scale rows of `U-TOKEN-001`** (`pageTitle`, `brand`, `modalTitle`, `compactBrand`, `cardTitle`, `body`, `control`, `rawCode`, `meta`, `chip`, `monoSmall`, `eyebrow`, `micro`, `devBadge`) plus `static TextStyle mono(TextStyle style)` and `static TextStyle tabular(TextStyle style)` attaching `FontFeature.tabularFigures()`, `lerp`, `==`, `hashCode`.
4. **`UiSpacingTokens` (`ui_spacing_tokens.dart`):**
   - `@immutable class UiSpacingTokens` holding base spacing (`space1 = 4` through `space6 = 24`), control density heights (`touchTarget = 40`, `touchTargetMobile = 44`, `navRowHeight = 38`, `fieldCompactHeight = 36`, `chromeControlHeight = 34`, `buttonCompactHeight = 32`, `buttonDenseHeight = 30`, `sidebarActionDesktop = 26`, `sidebarActionCompact = 34`), shell geometry (`chromeHeight = 62`, `sidebarWidth = 244`, `drawerMaxWidth = 300`, `shellMaxWidth = 1280`, `minConsoleHeight = 220`, `floatingNoticeInsetDesktop = 12`, `floatingNoticeInsetCompact = 10`, `cardListGap = 11`, `sectionGridGap = 14`), canonical `EdgeInsets` (`chromePaddingDesktop`, `chromePaddingCompact`, `mainPaddingDesktop`, `mainPaddingCompact`, `dockPaddingDesktop`, `dockPaddingCompact`), icon sizes (`iconXs = 13`, `iconSm = 15`, `iconMd = 18`, `iconLg = 34`), helper `EdgeInsets mainContentPadding(UiViewportClass viewport)`, `lerp`, `==`, `hashCode` (`U-TOKEN-002`..`003`, `U-BRAND-003`).
5. **`UiRadiusTokens` (`ui_radius_tokens.dart`):**
   - `@immutable class UiRadiusTokens` holding `logoBar` (`2`), `dotSm` (`3`), `dotLg` (`4`), `tag` (`6`), `sm` (`7`), `md` (`8`), `tierSelect` (`9`), `row` (`11`), `card` (`13`), `shell` (`16`), `pill` (`999`), `borderWidth` (`1.0`), `circleBorderWidth` (`1.7`), `spinnerStrokeWidth` (`2.5`), `lerp`, `==`, `hashCode` (`U-TOKEN-004`).
6. **`UiFocusTokens` (`ui_focus_tokens.dart`):**
   - `@immutable class UiFocusTokens` holding `ringWidth` (`1.0`), `ringOffset` (`1.0`), transition durations (`hoverDuration = 120ms`, `expandDuration = 220ms`, `fadeDuration = 180ms`, `spinDuration = 1000ms`, `loadingSpinDuration = 850ms`), dimmed opacities (`disabledOpacity = 0.48`, `prereqDisabledOpacity = 0.50`, `suspendedDimmedOpacity = 0.45`, `readonlyOpacity = 0.72`), the exact 5 restricted drop shadows (`segmentedShadow`: `(0, 1) blur 2 alpha 0.06`, `toastShadow`: `(0, 8) blur 24 alpha 0.20`, `popoverShadow`: `(0, 14) blur 36 alpha 0.24`, `bottomSheetShadow`: `(0, -10) blur 30 alpha 0.28`, `modalShadow`: `(0, 18) blur 42 alpha 0.24`), `lerp`, `==`, `hashCode` (`U-SURFACE-002`, `U-A11Y-004`).
7. **`UiThemeTokens`, `UiThemePresets` & `UiSurfaceScope` (`ui_theme_tokens.dart`):**
   - `enum UiSurfaceLevel { panel, insetWell }` and `class UiSurfaceScope extends InheritedWidget` with `static UiSurfaceLevel of(BuildContext context)` defaulting to `UiSurfaceLevel.panel` (`U-SURFACE-003`).
   - `@immutable class UiThemeTokens extends ThemeExtension<UiThemeTokens>` with `brightness`, `colors`, `typography`, `spacing`, `radii`, `focus`, deterministic `UiThemeTokens.of(BuildContext)` returning `Theme.of(context).extension<UiThemeTokens>() ?? (Theme.of(context).brightness == Brightness.dark ? UiThemePresets.calm.dark : UiThemePresets.calm.light)`, and `ThemeData toThemeData()` configuring flat zero-elevation Material 3 styling (`elevation: 0`, `scrolledUnderElevation: 0`, `surfaceTintColor: Colors.transparent`, `scaffoldBackgroundColor: colors.bg`, `cardColor: colors.panel`, `dividerColor: colors.line`, `1px` `line` borders, `1px` `accent` focus borders).
   - `@immutable class UiThemePreset { final String id; final UiThemeTokens light; final UiThemeTokens dark; }`
   - `const UiThemePresets._()` providing `calm` (`id: 'calm'`, default), `plumUmber` (`id: 'plum_umber'`), `all`, and `byId(String id)` (matching `'calm'` and `'plum_umber'`, falling back to `calm`).

#### Layer 2: Eight Core Primitives (`packages/tiertask_ui/lib/src/primitives/`)
Non-input interactive primitives (`UiButton`, `UiPill`, `UiSegmentedControl`, `UiToggleRow`, `UiCard.expandable` header button) render an outer `1px` `accent` focus-visible ring (`ringOffset = 1px`) on keyboard focus (`FocusHighlightMode.traditional`), whereas bordered input and search containers (`UiField`) switch their `1px` container border to `accent` without a doubled outer ring (`U-A11Y-001`). Every icon-only or interactive primitive exposes explicit caller-supplied `Semantics` labels (`U-A11Y-005`).
1. **`UiAppLogo` (`ui_app_logo.dart`):** `CustomPaint` drawing the three left-aligned stepped bars (`22x22` grid: `(0, 2, 22, 4) @ 1.0`, `(0, 9, 16.5, 4) @ 0.72`, `(0, 16, 11, 4) @ 0.42`, radius `2.0`) in `color ?? tokens.colors.accent`, wrapped in `ExcludeSemantics` (`U-BRAND-001`).
2. **`UiButton` (`ui_button.dart`):**
   - `enum UiButtonVariant { primary, secondary, text, danger, icon }`
   - `enum UiButtonDensity { standard, chrome, compact, dense, mobileTouch, sidebarDesktop }` mapping directly to `UiSpacingTokens` heights (`40`, `34`, `32`, `30`, `44`, `26` logical px).
   - `enum UiButtonTone { neutral, accent, warning, danger }` (supports chrome Sync status states and icon accenting).
   - Supports `label`, `leadingIcon`, `trailingIcon` (workspace pill chevron), `tooltip`, `semanticLabel`, `isLoading` continuous rotation (`spinDuration`), `isActive` (`soft` fill + `accent` foreground/border for toggled filter/manage controls), `isDangerHover` danger-tinted hover state on icon buttons, `isFullWidth`, and `disabledOpacity = 0.48`.
3. **`UiPill` (`ui_pill.dart`):**
   - `enum UiPillVariant { badge, count, tag, meta, splitChip, addField, selectable }`
   - `enum UiPillTone { neutral, soft, accent, warning, danger, success }`
   - Reads `UiSurfaceScope.of(context)` so nested `selectable`/`tag`/`addField` pills inside `UiCard.inset` re-elevate cleanly from `bg` to `panel`.
   - Supports optional `colorDot` (`8x8px` radius `3px`, or `dotSize` override for `12x12px` radius `4px`), `icon`, `label`, `onPressed`, `onRemove` + `removeTooltip` (for `splitChip` where primary half navigates via `onPressed` and optional `x` removes via `onRemove` with danger-hover), `isSelected` (`Semantics(toggled: isSelected)`), `isDirect` (solid border vs internal `_DashedRoundedBorderPainter` `CustomPainter` on `addField`), `isMono` (`DEV` badge, hex preset chips), and tabular figures on `count` pills (`U-COMP-002`).
4. **`UiSegmentedControl<T>` (`ui_segmented_control.dart`):**
   - Immutable `UiSegment<T> { final T value; final String label; final IconData? icon; final bool enabled; }`
   - Equal-width horizontal segments inside a `bg` trough (`1px` `line`, `padding: 3px`, `gap: 4px`, `radiusMd: 8px`); selected tab uses `panel` fill, `accent` weight `600`, and `segmentedShadow`; supports `ArrowLeft`/`ArrowRight` focus stepping and `Semantics(selected: ...)` (`U-COMP-002`).
5. **`UiCard` (`ui_card.dart`):**
   - `enum UiCardVariant { standard, inset, draft, expandable }`
   - `UiCard.standard`: flat `panel` + `1px` `line` (or `soft` + `1px` `accent` when `isHighlighted: true`, e.g. active workspace card), `radiusCard (13px)`, configurable `padding` (default `16px`, supporting zero/tight padding for Log Console and Raw `.tdf` containers), optional header (`headerIcon`, `headerTitle`, `headerBadge`, `headerTrailing`).
   - `UiCard.inset`: `bg` well (`radiusRow: 11px`, `11x13px` padding), optional header (`headerIcon`, `headerTitle`, `headerBadge`, `headerTrailing`), and optional `footer` slot. Unconditionally wraps its subtree in `UiSurfaceScope(level: UiSurfaceLevel.insetWell)` so both reading and editing nested controls re-elevate to `panel` (`U-SURFACE-003`). Setting `isEditing: true` switches the `1px` border from `line` to `accent`.
   - `UiCard.draft`: `panel` + persistent `1px` `accent` border (`radiusCard: 13px`), header title/subtitle/close button (`closeTooltip`), body, inline error (`Semantics(liveRegion: true)`), and footer slots (`U-CARD-006`).
   - `UiCard.expandable`: unified entity card (`leading`, `title`, `titleEditor`, `isEditingTitle`, `trailingActions`, `collapsedMetadata`, `expandedChild`, `isExpanded`, `isCompleted`, `onToggleExpand`) with `34x34px` leading slot, `isCompleted` struck-through `muted` title styling (`U-CARD-004`), header swap to `titleEditor` when `isEditingTitle: true`, `36px` desktop / `0px` compact collapsed metadata indent hidden when expanded, hover `accent` border suppressed while expanded, `Semantics(button: true, expanded: isExpanded)`, and `AnimatedSize` (`220ms`, `Curves.easeOut`) + `AnimatedOpacity` (`180ms`) reveal (`U-CARD-001`).
6. **`UiField` (`ui_field.dart`):**
   - `enum UiFieldKind { text, multiline, password, select, dateTime, search, readOnlyDisplay }`
   - Reads `UiSurfaceScope.of(context)` to choose `bg` fill (on `panel`) or `panel` fill (inside `insetWell`).
   - Renders optional `label`, `hintText`, `controller`, `focusNode`, `maxLength`, `isMonospace`, `leadingIcon`, `trailingAction`, `readOnly` (`0.72` opacity vs `0.48` disabled), `helperText`, `errorText` (`danger`, `11px`–`12px`, `Semantics(liveRegion: true)`), and `onSubmitted`.
   - Kind specifics:
     - `text` / `multiline`: flat `1px` bordered `TextField` switching border to `accent` on focus, optional single clear button (`showClearButton: true`, `clearTooltip`).
     - `password`: built-in `eye`/`eye-off` visibility toggle (`showPasswordTooltip` / `hidePasswordTooltip`).
     - `select`: flat `1px` bordered focus-aware container wrapping `DropdownButtonHideUnderline` + `DropdownButton<String>` backed by `UiSelectOption` (no Material underline; keeps `UiField` non-generic under `strict-inference`; supports `40px` standard, `34px` inline filter, and `44px` / `radiusTierSelect (9px)` compact tier select via `height`/`borderRadius` parameters).
     - `dateTime`: tap-to-pick bordered display field with formatted value, calendar/clock icon, optional clear button, and `onTap` callback so Phase 3 invokes platform/localized date-time pickers with uniform chrome (`U-COMP-002`).
     - `search`: composite focus-within bordered container (`chrome-search`, sidebar filter, picker search) with leading search icon, borderless inner `TextField`, single clear `x` button, and optional compact height (`36px`/`32px`) (`U-A11Y-001`).
     - `readOnlyDisplay`: flat selectable monospace readout well (`bg` or `panel` via `UiSurfaceScope`).
7. **`UiToggleRow` (`ui_toggle_row.dart`):**
   - Checkbox row (`17x17px` standard / `16x16px` dense) with `label`, optional muted `description`, `value`, `onChanged`, and full-row tap target (`minHeight: 40px` standard / `30px` dense); upholds the no-Switch convention (`U-COMP-002`).
8. **`UiBanner` (`ui_banner.dart`):**
   - `enum UiBannerVariant { status, toast, inlineWarning, inlineConfirm, emptyState, loadingState, fullError }`
   - `enum UiBannerTone { neutral, warning, danger, success }`
   - Covers `status` banners (optional `sublines`, `List<Widget> actions` supporting `0` to `2` buttons such as `Retry` + `Settings`, optional dismiss `x` + `dismissTooltip`), floating bottom `toast` / Undo overlay (`maxWidth: 620`, `toastShadow`, all 4 tones including `danger` duplicate-title notices, optional action + mono `kbdHint` auto-hidden on `compact` viewports + dismiss), `inlineWarning` box, `inlineConfirm` destructive bar (`message`, `cancelLabel`, `confirmLabel`, `isDestructive`), plain-text `emptyState`, centered `32px` spinning `loadingState` (`850ms`, `2.5px` stroke), and centered `fullError` state (`34px` hero icon + optional `detailsChild` diagnostics slot + `List<Widget> actions`) with polite/alert `Semantics` (`U-COMP-002`, `U-UX-004`, `U-UX-007`, `U-A11Y-005`).

#### Layer 3: Four Adaptive Layout Primitives (`packages/tiertask_ui/lib/src/layout/`)
1. **`UiAdaptiveAppShell` (`ui_adaptive_app_shell.dart`):**
   - Evaluates `UiBreakpoints.classify(constraints.maxWidth)` via `LayoutBuilder`.
   - Renders `62px` top chrome bar (`brand`, `mobileActiveFilter`, `workspaceTrigger`, `searchWidget`, `isSearchOpen`, `trailingActions`, `isDrawerOpen`, `onToggleDrawer`, `menuOpenTooltip`, `menuCloseTooltip`) collapsing chrome siblings when `isCompact && isSearchOpen`, swapping `brand` for `mobileActiveFilter` when `isCompact && !isSearchOpen && mobileActiveFilter != null`, and revealing the `44x44px` menu toggle (`menu`/`x`) on `compact` (`U-LAYOUT-003`..`004`).
   - Below the `62px` top chrome bar, renders a `Stack` (NOT full-screen `Scaffold.drawer`) so the persistent `244px` left sidebar (`> 720px`) or slide-over compact drawer (`min(300px, 92% width)`) over translucent `scrim` backdrop (`<= 720px`) anchors strictly below the top chrome bar, keeping the top bar menu toggle visible and interactive (`U-LAYOUT-002`). Sidebar hosts optional compact `sidebarHeader` (workspace card), independently scrollable `sidebarBody` (`sidebarScrollController`), and top-bordered pinned `sidebarFooter` (`U-BRAND-002`, `U-LAYOUT-007`).
   - Main column splits the `Expanded` viewport `Stack` (hosting caller's `body`, compatible with `CustomScrollView`/`SliverList.builder` per `P-LAZY-LISTS`, `SingleChildScrollView`, or flex-filling Log/Raw `.tdf` `Column`, plus non-blocking bottom-anchored `floatingNotice` `12px` desktop / `10px` compact above the stack bottom) from the conditional pinned `bottomDock` (`bg` + top `1px` `line`, canonical dock padding) strictly below it (`U-LAYOUT-005`).
2. **`UiSidebarSection` (`ui_sidebar_section.dart`):**
   - Immutable `UiSidebarNavItem` data model (`id`, `label`, `subtitle`, `icon`, `colorDot`, `countLabel`, `isSelected`, `onTap`, `trailingIcon`, `trailingTooltip`, `isTrailingActive`, `onTrailingTap`, `trailingHintIcon` excluded from semantics for single-button Location rows).
   - Supports non-collapsible static groups (`isCollapsible: false`, rendering eyebrow title + nav rows for `Tasks` and `Tools`) and collapsible/filterable groups (`isCollapsible: true`, for `Labels` and `Locations`) showing collapsed total count + optional active color dot ONLY when `isCollapsed: true`, up to 3 header icon buttons (`26px` desktop / `34px` compact) with caller-supplied tooltips (`filterTooltip`, `manageTooltip`, `collapseTooltip`, `expandTooltip`), inline `UiField` (`UiFieldKind.search`) filter box (`filterPlaceholder`, `filterClearTooltip`, `filterEmptyText`), auto-expand + focus on filter toggle while collapsed, and filter clear on collapse (`U-UX-001`).
3. **`UiPageHeader` (`ui_page_header.dart`):**
   - Optional top `backLabel` button (`onBack`), `28px` title + optional inline clickable `activeFilterLabel` + `activeFilterTooltip` (ellipsized, shown on desktop and conditionally on compact when `showInlineFilterOnCompact: true`) + tabular-nums `countLabel` pill + optional `trailing` action cluster + optional `subtitle` (`maxWidth: 58ch`) (`U-LAYOUT-004`).
4. **`UiResponsiveGrid` (`ui_responsive_grid.dart`):**
   - `enum UiGridPreset { twoColumnMediumCollapse, twoColumnCompactCollapse, fourActionCompactTwo }`
   - Uses `LayoutBuilder` against `UiBreakpoints` (`820px` and `720px`) to render equal-width columns with uniform `spacing`/`runSpacing` and top-aligned cells (`CrossAxisAlignment.start`), guaranteeing zero horizontal overflow (`U-LAYOUT-006`).

#### Layer 4: Five Domain-Agnostic Composites (`packages/tiertask_ui/lib/src/components/`)
1. **`UiDialogFrame` (`ui_dialog_frame.dart`):**
   - `enum UiDialogSize { small, medium, large }` (`420`, `520`, `600` logical px).
   - Renders bordered header (`17px` title, optional muted `subtitle`, close `x` button with `closeTooltip`), independently scrollable body (`maxHeight: min(86% viewport, 720px)`), and optional bordered right-aligned footer inside `radiusShell (16px)` `panel` card with `modalShadow`.
   - Static helpers `UiDialogFrame.showModal<T>(...)` and `UiDialogFrame.showBottomSheet<T>(...)` (`barrierColor: tokens.colors.scrim`; compact sheet: top `16px` radius, `maxHeight: 78%`, `36x4px` centered `line` handle wrapped in `ExcludeSemantics`, header with optional `icon`, `title`, `countLabel`, and `doneLabel` button, `bottomSheetShadow`, scrim tap dismissal).
   - Wraps overlay content in `Semantics(scopesRoute: true, explicitChildNodes: true)` + cyclical `FocusScope` + `FocusTraversalGroup`, traps `Tab`/`Shift+Tab`, supports `Escape` dismissal, and restores originating `FocusNode` on pop (`U-COMP-004`, `U-A11Y-003`, `U-A11Y-005`).
2. **`UiQuickComposer` (`ui_quick_composer.dart`):**
   - Supports both docked Task Quick-Add (`isCollapsibleOnCompact: true`, `maxLength: 300`) and inline Labels/Locations Quick-Create (`isCollapsibleOnCompact: false`, `maxLength: 120`, omitting `modeWidget`/`modeHint`/`draftChips`/`popoverContent`).
   - Exposes `controller`, `focusNode`, `placeholder`, `maxLength`, `submitLabel`, `onSubmit`, `expandDraftLabel`, `onExpandDraft`, `compactTriggerLabel`, `compactCloseTooltip`, and optional `modeWidget`, `modeHint`, `draftChips`, `popoverContent`, `isPopoverOpen`, `onDismissPopover`.
   - On `compact` when collapsible and collapsed, renders full-width primary `compactTriggerLabel` button; expanding shows stacked title field (`16px` on compact), optional `modeWidget`/`modeHint`/draft chips, `expandDraftLabel`, `submitLabel`, and compact close `x`.
   - On desktop, anchors `popoverContent` upward above the dock (`offset: Offset(0, -8)`, `width: min(460px, available)`, `popoverShadow`) using `OverlayPortal` paired with `CompositedTransformTarget`/`CompositedTransformFollower` and `TapRegion(onTapOutside: ...)` so outside pointer clicks dismiss the popover WITHOUT swallowing clicks on interactive targets (`U-CARD-006`, `U-COMP-004`).
3. **`UiSearchablePicker<T>` (`ui_searchable_picker.dart`):**
   - `enum UiPickerSelectionMode { multiple, single }`
   - Immutable `UiPickerOption<T> { final String id; final T value; final String label; final String? subtitle; final IconData? icon; final Color? colorDot; final String? badgeLabel; final String? countLabel; final String? disabledHint; final bool isMonospace; final bool enabled; final bool hasInfoAction; }`
   - Immutable `UiPickerScopeFilter { final String id; final String label; }`
   - Supports `selectionMode` (`multiple` with custom `16x16px` checkbox vs `single` row highlight for Local `.tdf` File Picker and Geocoding Candidates), `showSearch` (default `true`, optional `maxLength`), `showSelectedChips` (default `true`; set `false` inside desktop composer popover per `U-COMP-005`), `autoFocusSearch` (strictly `false` inside compact bottom sheets per `U-A11Y-003`), optional `scrollController` (`U-LAYOUT-007`), conditional scope filter pills (rendered ONLY when `scopeFilters.length >= 2`), lazy `ListView.builder` (`maxHeight: 224px` desktop, `44px` rows compact) with optional `info` button + disabled `0.5` opacity rows (`Cycle prevented`), and caller-supplied localized copy (`searchPlaceholder`, `searchClearTooltip`, `infoTooltip`, `removeChipTooltip`, `emptyText`, and optional `inlineCreateLabel` row).
   - Keyboard handling: `ArrowDown`/`ArrowUp` step highlight across options + inline-create row (`ensureVisible`), `Enter` toggles/selects highlighted (or first) option or creates, first `Escape` clears non-empty query, second `Escape` calls `onRequestClose` (`U-COMP-005`, `U-A11Y-002`).
4. **`UiOrderedItemList<T>` (`ui_ordered_item_list.dart`):**
   - Accepts `items`, deterministic `itemKey` (`Key Function(T item, int index)` per `P-LAZY-LISTS`), `itemBuilder` (`Widget Function(BuildContext, T item, int index, bool isEditing)`), optional header (`title`, `countLabel`, `headerTrailing`), optional `progressValue` (`0.0..1.0` rendering a `6px` `accent` bar on `radiusPill`), optional `editingIndex` highlight (`soft` fill + `radiusMd`), optional `onReorder` (renders boundary-disabled `Move up` at `0` and `Move down` at `length - 1` ONLY when provided, omitting reorder arrows for Time Windows and History Journal), optional `onEdit` and `onDelete` (with caller-supplied tooltips), `emptyText`, optional `maxHeight` (scrollable `ListView.builder` when bounded, or `shrinkWrap: true` `NeverScrollableScrollPhysics` `ListView.builder` inside a parent scroll view), and optional `addBar` and `footer` slots (`U-COMP-006`).
5. **`UiColorWheel` (`ui_color_wheel.dart`):**
   - Exposes `static const List<Color> canonicalPresets` (`#2196F3`, `#4CAF50`, `#FF9100`, `#E91E63`, `#9C27B0`, `#00BCD4`, `#EB06FF`, `#00E5FF`).
   - All visible strings (`inputLabel`, `customButtonLabel`, `modalTitle`, `brightnessLabel`, `cancelLabel`, `confirmLabel`, `closeTooltip`, `invalidHexError`) are caller-supplied parameters (`TEP-017` Section 1.3 locale neutrality).
   - Inline row (`34px` circular swatch, `110px` mono `#RRGGBB` `maxLength: 7` input validating case-insensitive `#RRGGBB` and normalizing uppercase on commit, `customButtonLabel` compact button) + wrapping preset chips (`UiPill` with `UiPillVariant.selectable`, mono hex + dot, selected highlighted in `soft`/`accent`).
   - Modal picker (`UiDialogFrame` `small` width): live swatch + hex preview bar, `210x210px` circular `CustomPaint` HSV wheel (`SweepGradient` hues + radial white-to-transparent saturation + darkness overlay for Value `v`, drag/tap `GestureDetector` clamping to wheel radius, `8px`-radius filled thumb with `2.5px` white + `1px` dark halo), and `0..100%` Value `Slider` driven by local `ValueNotifier<HSVColor>` disposed in `State.dispose()` (`P-DISPOSE-RESOURCES`) so dragging updates canvas and hex readout smoothly without parent rebuilds (`U-COMP-007`).

#### Multi-Package Tooling Changes (`.agents/scripts/tiertask_dev.py`)
1. **Package Registry:** Define `UI_PACKAGE_REL = Path("packages/tiertask_ui")` and `UI_EXAMPLE_REL = Path("packages/tiertask_ui/example")` helper paths checked conditionally (`if (root / UI_PACKAGE_REL).exists():`) so tests and tool runs work cleanly before and after scaffolding.
2. **`_iter_dart_files`, `_resolve_dart_import` & `build_import_graph`:**
   - Include `packages/tiertask_ui/lib`, `packages/tiertask_ui/test`, `packages/tiertask_ui/example/lib`, and `packages/tiertask_ui/example/test` in `_iter_dart_files`.
   - Extend `_resolve_dart_import` to resolve `package:tiertask_ui/<path>` -> `packages/tiertask_ui/lib/<path>` in addition to `package:tiertask/` and relative imports.
   - Extend `build_import_graph` to follow `export '...'` directives in `packages/tiertask_ui/lib/tiertask_ui.dart` so `deps` and reverse-impact analysis traverse the package barrel cleanly.
3. **Static Checks (`run_static_checks`):**
   - Verify verbatim `GPL-3.0` header, LF line endings, and zero `// ignore:` directives across all `packages/tiertask_ui/**/*.dart` files.
   - Allow `export` directives ONLY in `packages/tiertask_ui/lib/tiertask_ui.dart`; reject `export`/`part`/`part of` in all other files (including `packages/tiertask_ui/lib/src/**`).
   - Enforce **strict package isolation** across every `.dart` file (`import` and `export` directives) and `pubspec.yaml` under `packages/tiertask_ui/`: forbid `package:tiertask/`, `package:flutter_riverpod/`, `tiertask`/`flutter_riverpod` pubspec dependencies, `dart:io`, `dart:ffi`, and `HttpClient`; forbid `package:tiertask_ui/src/` imports in `packages/tiertask_ui/test/` and `packages/tiertask_ui/example/`.
   - Enforce **internal acyclic DAG** inside `packages/tiertask_ui/lib/`: `0: tokens < 1: primitives < 2: layout < 3: components < 4: lib/tiertask_ui.dart`, zero circular SCCs, zero upward imports.
4. **`compute_code_digest` & `resolve_impacted_tests`:**
   - Hash `packages/tiertask_ui/pubspec.yaml`, `packages/tiertask_ui/analysis_options.yaml`, `packages/tiertask_ui/example/pubspec.yaml`, `packages/tiertask_ui/example/analysis_options.yaml`, and all `.dart` files under `packages/tiertask_ui/` so verification stamps invalidate on any UI package edit.
   - Resolve changed files in `packages/tiertask_ui/lib/src/<layer>/<name>.dart` to mirrored `packages/tiertask_ui/test/<layer>/<name>_test.dart`; when no 1:1 mirror test exists (including token sub-files `ui_focus_tokens.dart`, `ui_radius_tokens.dart`, `ui_spacing_tokens.dart`, `ui_typography_tokens.dart`, as well as `lib/tiertask_ui.dart` and `test/test_helpers.dart`), fall back to reverse test dependents via `build_import_graph`. Map `packages/tiertask_ui/example/` changes to `packages/tiertask_ui/example/test/`. Partition impacted test paths by package root (`root`, `packages/tiertask_ui`, `packages/tiertask_ui/example`) and pass **package-relative** test paths when invoking `flutter test` in each package's working directory.
5. **`run_verify`:**
   - Extend `code_relevant_changes` to include `"packages/"` so `verify --fast` never skips analyzer/tests when only `packages/tiertask_ui/` files change.
   - Run `dart format` (`--fix`) AND `dart format --output=none --set-exit-if-changed` (`--full`) across root `lib test` plus all existing Dart roots under `packages/tiertask_ui/` (`lib`, `test`, `example/lib`, `example/test`).
   - Run `flutter analyze --no-pub --fatal-infos --fatal-warnings` in root, `packages/tiertask_ui/`, and `packages/tiertask_ui/example/` (all three on `--full`, or each package with relevant changes on `--fast`).
   - Run `flutter test --no-pub --no-test-assets -r failures-only` per package (impacted package-relative suites on `--fast`, all suites in all three packages on `--full`).
6. **`ARCHITECTURE.md`, `scaffold`, & Lookup (`outline`, `find`, `deps`, `arch`):**
   - Extend `generate_architecture_tree` to include `packages/` (`packages/tiertask_ui/`), collapsing platform runner dirs (`android/`, `linux/`, `windows/`) and skipping `build/` and `ephemeral/` inside `_render_dir_tree`.
   - Extend `_layer_section_for_path` (`packages/tiertask_ui/lib/**` -> `## UI Component Library`), `scaffold_file` (registering `packages/tiertask_ui/lib/**` rows), and `audit_architecture` (validating and stale-checking `| \`packages/tiertask_ui/lib/` rows in `ARCHITECTURE.md`).
   - Update `outline_file`, `outline_repo_overview`, and `find_in_repo` to classify `packages/tiertask_ui/test/` and `packages/tiertask_ui/example/test/` as test files (`outline_dart_test`), automatically include `packages/tiertask_ui/` in `find_in_repo` when `--layer` is omitted, and support `--layer ui_pkg` explicitly in `_build_parser`.

### 2.4 Testing Strategy
Develop every module via strict Red-Green-Refactor TDD (`P-TDD-FIRST`, `P-TEST-MIRROR`) with zero Riverpod or domain setup in `packages/tiertask_ui/test/`:
- **Shared Test Harness (`packages/tiertask_ui/test/test_helpers.dart`):** `pumpUiWidget(tester, child, {UiThemeTokens? tokens, Size surfaceSize})` wrapping the widget under test in `MaterialApp(theme: tokens.toThemeData(), home: Scaffold(body: child))` with explicit viewport sizing (`tester.view.physicalSize` + `devicePixelRatio: 1.0`, reset via `addTearDown`).
- **Token & Contrast Suites (`test/tokens/`):**
  - `M-EXHAUSTIVE-STATE-TESTS`: Verify all 4 built-in presets (`calm.light`, `calm.dark`, `plumUmber.light`, `plumUmber.dark`), exact hex values (`U-TOKEN-005`), `UiThemePresets.byId` and brightness-aware `UiThemeTokens.of` fallbacks, `UiSurfaceScope` default (`panel`) and nested (`insetWell`) lookup, `ThemeExtension.lerp` at `0.0 / 0.5 / 1.0`, and automated WCAG AA (`>= 4.5:1`) contrast across all 17 enumerated foreground/background pairs per preset (`68` pairs total, verifying pass and failure detection on synthetic low-contrast tokens).
  - `M-EXTREME-BOUND-TESTS`: Verify `UiBreakpoints.classify` at exact boundaries `0`, `390`, `720` (`compact`), `721`, `760`, `820` (`medium`), `821`, `1280` (`expanded`).
- **Primitive Suites (`test/primitives/`):**
  - `M-EXHAUSTIVE-STATE-TESTS`: Every `UiButtonVariant` x `UiButtonDensity` x `UiButtonTone` + `trailingIcon` + `isActive` + `isLoading` + disabled `0.48` opacity; every `UiPillVariant` x `UiPillTone` + split navigate/remove callbacks + solid vs dashed `CustomPaint` add chip + `UiSurfaceScope` re-elevation; `UiSegmentedControl` selection + `ArrowLeft`/`ArrowRight`; every `UiCardVariant` (`standard` with `isHighlighted` + custom `padding`, `inset` unconditional `UiSurfaceScope(insetWell)` in both read and edit states + `accent` border on `isEditing`, `draft` accent border, `expandable` single reveal + inline `titleEditor` swap + `isCompleted` strike-through + hover suppression when expanded + desktop `36px` vs compact `0px` metadata indent); every `UiFieldKind` (`text`, `multiline`, `password` eye toggle, flat bordered `select` including `44px` compact tier select, `dateTime` tap/clear, `search` focus-within border + single clear button, `readOnlyDisplay`, `0.72` readonly opacity, `panel` fill inside `UiCard.inset`); `UiToggleRow` toggle + disabled; every `UiBannerVariant` x `UiBannerTone` + multi-action `status` / `fullError` (`detailsChild`) + `toast` `maxWidth: 620` with compact `kbdHint` hiding + `inlineConfirm` + semantics (`liveRegion`).
  - `UiAppLogo`: Golden-free geometry verification confirming `CustomPaint` renders 3 bars in `accent` color with `1.0 / 0.72 / 0.42` opacities and `ExcludeSemantics`.
- **Layout Suites (`test/layout/`):**
  - `UiAdaptiveAppShell` (`M-EXTREME-BOUND-TESTS` at `390`, `720`, `721`, `820`, `821`, `1280`): persistent `244px` sidebar (`>= 721`) vs below-chrome slide-over drawer + scrim (`<= 720`, verifying top bar menu button remains uncovered and clickable), compact `sidebarHeader`, compact search hiding sibling chrome items, compact active label swapping brand slot, lazy `ListView.builder` / `SliverList.builder` body compatibility (`P-LAZY-LISTS`), floating notice sitting strictly above pinned `bottomDock` without overlapping dock controls, and scroll controller offset preservation.
  - `UiSidebarSection`: static (`isCollapsible: false`) vs collapsible modes, split-button vs single-button nav rows, collapsed count + active dot visibility, 3 header icon targets (`26px` desktop / `34px` compact), auto-expand on filter toggle, filter empty text, clear-filter on collapse.
  - `UiPageHeader`: inline active filter visibility desktop vs compact (`showInlineFilterOnCompact`), clear callback, tabular count pill, back button.
  - `UiResponsiveGrid`: exact column counts at `390`, `720`, `721`, `820`, `821`, `1280` for all 3 `UiGridPreset` variants.
- **Composite Suites (`test/components/`):**
  - `UiDialogFrame`: modal sizes (`420`/`520`/`600`) with optional `subtitle`, bottom sheet (`78%` max height, `ExcludeSemantics` drag handle, `scrim` barrier), `Semantics(scopesRoute: true)`, cyclical `Tab`/`Shift+Tab` focus trap, `Escape` close, and focus restoration to trigger button on close.
  - `UiQuickComposer`: desktop always-open + upward `OverlayPortal` popover with `TapRegion` outside-tap dismissal verifying outside buttons still receive taps (`U-COMP-004`), compact collapsed `+ New task` toggle + expanded stacked layout + close `x`, and inline Labels/Locations Quick-Create mode (`isCollapsibleOnCompact: false`).
  - `UiSearchablePicker`: `multiple` vs `single` selection modes, `showSelectedChips: false` (desktop popover), `showSearch: false`, scope pills hidden when `< 2` scopes and shown when `>= 2`, inline create row on unique `1..120`-char query, disabled `Cycle prevented` rows (`0.5` opacity), keyboard `ArrowDown`/`ArrowUp`/`Enter`, two-step `Escape` (clear query first, close second), `scrollController` retention, and `autoFocusSearch: false` enforcement in compact bottom sheet mode.
  - `UiOrderedItemList`: optional `onReorder` (shown and boundary-disabled at `0` / `length - 1` when provided; omitted when `null`), `editingIndex` highlight, optional `progressValue` bar, custom `itemBuilder` + deterministic `itemKey`, edit/delete callbacks, count readout.
  - `UiColorWheel`: exact 8 `canonicalPresets`, caller-supplied localized modal labels, hex input parsing (`#RRGGBB`, invalid input rejection), HSV wheel drag/tap color conversion accuracy, and Value slider updating color smoothly with clean `ValueNotifier` disposal.
- **Gallery Smoke Suite (`packages/tiertask_ui/example/test/gallery_smoke_test.dart`):** Pumps gallery across `Calm`/`Plum Umber`, Light/Dark, and `390px`/`760px`/`1280px` verifying interactive switches and zero layout overflow exceptions.
- **Tooling Suite (`.agents/scripts/tests/test_tiertask_dev.py`):** Verifies `packages/tiertask_ui/` scoped barrel carve-out (passes `lib/tiertask_ui.dart`, rejects `export` inside `lib/src/` and `package:tiertask_ui/src/` imports in `test/`/`example/`), forbidden `package:tiertask/` / `package:flutter_riverpod/` / `dart:io` / `dart:ffi` rejection across Dart files and `pubspec.yaml`, internal `tokens -> primitives -> layout -> components -> tiertask_ui.dart` DAG enforcement, `code_relevant_changes` detection for `packages/`, package-relative impacted test mapping, digest invalidation on package edits, and `ARCHITECTURE.md` tree/table audit coverage (skipping `build/` and collapsing `example/linux/`).

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [x] Review and finalize `TEP-017` and advance status from `concept` to `planned`.
- [x] Run `python3 .agents/scripts/tiertask_dev.py verify --fast` to confirm a clean baseline.
- [x] Extend `.agents/scripts/tiertask_dev.py` (with Red-Green TDD in `.agents/scripts/tests/test_tiertask_dev.py`) and root `analysis_options.yaml` for `packages/tiertask_ui/` and `packages/tiertask_ui/example/` multi-package support.
- [x] Scaffold `packages/tiertask_ui/` and `packages/tiertask_ui/example/` (`pubspec.yaml`, `analysis_options.yaml`, `lib/tiertask_ui.dart`, `test/test_helpers.dart`, minimal `example/linux/` runner) and run `flutter pub get` in both `packages/tiertask_ui/` and `packages/tiertask_ui/example/`.
- [x] Implement Layer 1 (`tokens/`: 7 files) with Red-Green-Refactor TDD tests (including automated WCAG AA contrast verification across all 17 pairs and breakpoint boundary tests).
- [x] Implement Layer 2 (`primitives/`: 8 widgets) with Red-Green-Refactor TDD widget tests across all variants, densities, tones, focus rings, input focus borders, and `UiSurfaceScope` surface alternation.
- [x] Implement Layer 3 (`layout/`: 4 adaptive layouts) with Red-Green-Refactor TDD widget tests across `390 / 720 / 721 / 760 / 820 / 821 / 1280` viewports.
- [x] Implement Layer 4 (`components/`: 5 composites) with Red-Green-Refactor TDD widget tests covering focus trapping, keyboard navigation, non-swallowing popovers, bottom-sheet hygiene, and HSV wheel interaction.
- [x] Build `packages/tiertask_ui/example/` runnable interactive gallery app and passing smoke tests.
- [x] Update Parts 1 and 2 if implementation refines any API detail.
- [x] Run `python3 .agents/scripts/tiertask_dev.py verify --full --fix` and `python3 -m unittest discover -s .agents/scripts/tests -v`.
- [x] Follow **`update-documentation`** to synchronize `ARCHITECTURE.md` and `AGENTS.md` (skip `CHANGELOG.md` because `packages/tiertask_ui/` is internal infrastructure not yet user-facing until Phase 3 cutover).
- [x] Set `status: review`, update `BOARD.md`, and request user approval.
- [x] After user approval, set `status: completed`, update `BOARD.md`, check off Phase 2 in `TEP-015`, and list delivered artifacts in Part 3.3.

### 3.2 Work Log & Decisions
- **2026-11-21:** Drafted Phase 2 child proposal `TEP-017` under [`TEP-015`](tep-015-ui-architecture-and-design-system-roadmap.md) aligned with [`spec/UI_DESIGN_SYSTEM.md`](../../spec/UI_DESIGN_SYSTEM.md) and the signed-off `.agents/prototypes/ui_v2/` concept.
- **2026-11-21:** Completed `/spec-verification-loop` audit of `TEP-017`: locked strictly minimal 17-widget reuse catalog with full Phase 3 coverage matrix, moved `UiSurfaceScope` to Layer 1 (`ui_theme_tokens.dart`) with unconditional `UiCard.inset` surface re-elevation, aligned all token/primitive/layout/composite contracts with `spec/UI_DESIGN_SYSTEM.md` and `P-LAZY-LISTS`, and closed multi-package `tiertask_dev.py` tooling gaps.
- **2026-11-21:** Implemented Phase 2 end to end with Red-Green-Refactor TDD: extended `.agents/scripts/tiertask_dev.py` (17 unit tests) and root `analysis_options.yaml`, built `packages/tiertask_ui/` (7 token leaves, 8 primitives, 4 layouts, 5 composites, 52 isolated tests covering all 68 WCAG AA contrast pairs and breakpoint/focus/keyboard invariants), built runnable `packages/tiertask_ui/example/` Linux gallery app with smoke tests, synchronized `ARCHITECTURE.md` and `AGENTS.md`, and advanced `TEP-017` to `review`. Kept `UiField` non-generic with `UiSelectOption` (`String` values) for clean `strict-inference` ergonomics.
- **2026-11-21:** User approved `TEP-017`; finalized `status: completed`, moved entry to `Completed Proposals` in `BOARD.md`, and checked off Phase 2 in `TEP-015`.

### 3.3 Delivered Artifacts
- **Component Library Package (`packages/tiertask_ui/`):**
  - Package configuration and public barrel: `packages/tiertask_ui/pubspec.yaml`, `packages/tiertask_ui/analysis_options.yaml`, `packages/tiertask_ui/lib/tiertask_ui.dart`.
  - Layer 1 (`tokens/`): `ui_breakpoints.dart`, `ui_color_tokens.dart`, `ui_focus_tokens.dart`, `ui_radius_tokens.dart`, `ui_spacing_tokens.dart`, `ui_theme_tokens.dart`, `ui_typography_tokens.dart`.
  - Layer 2 (`primitives/`): `ui_app_logo.dart`, `ui_banner.dart`, `ui_button.dart`, `ui_card.dart`, `ui_field.dart`, `ui_pill.dart`, `ui_segmented_control.dart`, `ui_toggle_row.dart`.
  - Layer 3 (`layout/`): `ui_adaptive_app_shell.dart`, `ui_page_header.dart`, `ui_responsive_grid.dart`, `ui_sidebar_section.dart`.
  - Layer 4 (`components/`): `ui_color_wheel.dart`, `ui_dialog_frame.dart`, `ui_ordered_item_list.dart`, `ui_quick_composer.dart`, `ui_searchable_picker.dart`.
  - Isolated test suite (`packages/tiertask_ui/test/`): `test_helpers.dart` plus 20 mirrored unit/widget suites (`52` passing tests including all 68 WCAG AA contrast pairs).
- **Interactive Gallery App (`packages/tiertask_ui/example/`):**
  - `pubspec.yaml`, `analysis_options.yaml`, `linux/` desktop runner, `lib/main.dart`, `lib/gallery_sections.dart`, and `test/gallery_smoke_test.dart`.
- **Multi-Package Tooling & Documentation:**
  - `analysis_options.yaml` (`packages/**` exclude), `.agents/scripts/tiertask_dev.py`, `.agents/scripts/tests/test_tiertask_dev.py` (`17` passing tests), `ARCHITECTURE.md`, and `AGENTS.md`.
