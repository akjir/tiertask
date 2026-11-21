---
name: ui-design-system
description: Enforces TierTask UI Design System and UX guidelines (spec/UI_DESIGN_SYSTEM.md) derived from .agents/prototypes/ui_v2/. Activate whenever designing, building, editing, reviewing, or testing packages/tiertask_ui/, lib/ui_v2/, lib/ui/, themes, tokens, layouts, widgets, dialogs, keyboard shortcuts, or UI proposals.
---

# TierTask UI Design System Workflow

Follow `AGENTS.md` and `spec/UI_DESIGN_SYSTEM.md` (`P-UI-DESIGN-SYSTEM`) for every task touching `packages/tiertask_ui/`, `lib/ui_v2/`, redesigned `lib/ui/`, UI themes, or UI proposals (`TEP-015` Phases 2–4).

## 1. Authoritative References & Token-Efficient Lookup
- **Normative Guidelines:** `spec/UI_DESIGN_SYSTEM.md` (`U-FIDELITY-*`, `U-SURFACE-*`, `U-TOKEN-*`, `U-LAYOUT-*`, `U-BRAND-*`, `U-COMP-*`, `U-CARD-*`, `U-UX-*`, `U-A11Y-*`, `U-GATE-*`).
- **Prototype Reference (Phases 2–3 Initial Cutover):** `.agents/prototypes/ui_v2/` (`tokens.css`, `components.css`, `icons.js`, `views_core.js`, `views_secondary.js`, `app.js`).
- **Fast Lookup:** Run `python3 .agents/scripts/tiertask_dev.py outline spec/UI_DESIGN_SYSTEM.md` or `python3 .agents/scripts/tiertask_dev.py find <query> --layer spec`, then read only the required section ranges.

## 2. Non-Negotiable Core Invariants
Verify every UI design, component, screen, or PR against these baseline rules before writing code:
1. **Flat Borders & Shadow Allowlist (`U-SURFACE-001`..`004`):** Resting cards, chrome, sidebar, docks, and consoles are flat with `1px` `line` borders and zero drop shadows. Shadows appear ONLY on active segmented tabs, floating toasts, desktop popovers, mobile bottom sheets, and modal dialogs. Keep entity card containers neutral (`panel`/`line`); use semantic badges for status.
2. **Surface Alternation & WCAG AA Contrast (`U-SURFACE-003`, `U-TOKEN-005`..`006`):** Alternate `bg` and `panel` (re-elevating inputs inside `bg` inline-edit wells back to `panel`). Ship `Calm` (default) and `Plum Umber` in Light and Dark with exact hex tokens (including dark-mode `onAccent` polarity flip) and verified `>= 4.5:1` contrast.
3. **17-Widget Reuse Cap & Package Isolation (`U-FIDELITY-003`, `U-COMP-001`):** Keep `packages/tiertask_ui/` strictly isolated (zero `tiertask`, `flutter_riverpod`, `dart:io`, `dart:ffi`) around its 17 orthogonal widgets (`8` primitives, `4` layouts, `5` composites) behind one package barrel (`lib/tiertask_ui.dart`). Compose feature views from those widgets instead of creating one-off duplicates.
4. **Adaptive Shell & Breakpoints (`U-LAYOUT-001`..`006`):** Enforce `compact <= 720`, `medium 721..820`, `expanded > 820`. Use `62px` top chrome, `244px` persistent desktop sidebar vs `min(300px, 92%)` compact drawer, and **decouple `.floating-notice-layer` inside the scroll region ABOVE the permanently pinned bottom dock** (Quick-Add composer or Settings/Conflict action footer).
5. **Inline Active-Label Filter (`U-LAYOUT-004`):** Never add a stacked active-filter bar. Place clickable active label inline inside the desktop heading row; on compact Tasks view, swap the brand button in top chrome to `UiAppLogo` + label name; on compact Search view, place it inline in the Search heading row.
6. **Branding & Controls (`U-BRAND-001`..`004`, `U-COMP-002`):** Use the three-bar stepped `UiAppLogo` (`100%/1.0`, `75%/0.72`, `50%/0.42`), inline `DEV` pill (`AppBuildProfile.isDev`), sidebar SemVer footer, and `1.75`-stroke outline icons. Never use sliding Switch widgets (use 2-way `UiSegmentedControl` or `UiToggleRow` checkboxes).
7. **Unified Expandable Entity Cards (`U-CARD-001`..`005`):** Single-expand accordion shared by Tasks, Labels, and Locations; populated-only nested sections + `+ Add` chips bar; single active section editor vs immediate live controls (subtasks with auto-finish, history, placement, labels, label scope); read-only Completed task panels keeping Restore, Copy, Links, entity nav, Delete, and live History. Enforce exact collapsed task badge order and cap secondary badges at `3` + clickable `+N more` pill.
8. **Non-Jumping Creation & Draft Cards (`U-CARD-006`):** Creating a task NEVER switches tiers, scrolls, or auto-expands (announce destination via floating toast). Opening an uncommitted Draft Card hides the docked Task Quick-Add composer (or replaces the Label/Location quick-create bar). No jump-to-composer button; mobile collapses Quick-Add to `+ New task`.
9. **Navigation, Undo & Settings UX (`U-UX-001`..`007`):** Collapsible/filterable sidebar sections; context-preserving `returnContext` back-navigation; button/select compact tier navigation (zero horizontal swipe gestures); LIFO Undo (`10` depth, `8s` undo / `5s` notice auto-hide); inline entity delete confirm vs typed-filename modal Wipe guard; Settings `Auto-saved` cards vs WebDAV `Unsaved changes` dirty badge with dynamic `Save`/`Test & Sync` primary swap and compact-viewport Move guard.
10. **Keyboard, Focus & Accessibility (`U-A11Y-001`..`005`):** `1px` focus-visible rings (`1px` offset) and container focus-within borders; desktop shortcuts (`Ctrl/Cmd+F`, `/`, `n`, `Ctrl/Cmd+Z`, `ArrowLeft`/`ArrowRight`, `Enter`) and strict 9-layer `Escape` order; modal/sheet `Tab` focus trapping + focus restoration; **never auto-focus search inside compact mobile bottom sheets**; `40px` desktop / `44px` compact hit targets.

## 3. Implementation & Verification Procedure
1. **Consult Spec & Prototype:** Outline and read the relevant `spec/UI_DESIGN_SYSTEM.md` sections; during Phases 2 and 3, cross-check `.agents/prototypes/ui_v2/` to ensure visual and behavioral fidelity (`U-FIDELITY-001`).
2. **TDD First (`P-TDD-FIRST`):** Write failing widget/unit tests covering all 4 theme presets (including WCAG AA contrast checks in Phase 2), all enum/tone variants (`M-EXHAUSTIVE-STATE-TESTS`), breakpoint boundaries `390 / 720 / 721 / 760 / 820 / 821 / 1280` (`M-EXTREME-BOUND-TESTS`), focus/keyboard/Escape paths, and `M-REAL-MECHANICS-TESTS` (Phase 3).
3. **Implement Cleanly:** Follow `AGENTS.md` Sections 1–4 (`P-UDF-ARCHITECTURE`, `P-FLATTEN-BUILD`, `P-CONST-WIDGETS`, `P-SELECT-REBUILDS`, `P-LAZY-LISTS`, `P-DISPOSE-RESOURCES`) and emit UI telemetry exclusively from `lib/presentation/` (`AGENTS.md` Section 6).
4. **Sync Spec on Post-Cutover Changes:** If a post-Phase-3 iteration intentionally changes tokens, layout, or UX behavior, update `spec/UI_DESIGN_SYSTEM.md` in the same change (`U-FIDELITY-002`).
5. **Verify:** Run `python3 .agents/scripts/tiertask_dev.py verify --full --fix` until all static, analyzer, architecture, and test gates pass cleanly.
