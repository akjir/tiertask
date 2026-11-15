---
id: TEP-009
title: Label Context Hub and Label Reference Link Management
status: planned
type: feature
created: 2026-11-14
updated: 2026-11-14
---

# TEP-009: Label Context Hub and Label Reference Link Management

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal delivers the interactive **Label Context Hub** and reference link authoring workflows on top of **TierTask Data Format (`TDF`) `0.7.0`** (`spec/TDF_SPEC_0.7.0.md` and `TEP-006` in `tep-006-tdf-spec-0-7-0.md`). While `TEP-006` specifies and implements the `TDF 0.7.0` grammar, lexical/structural parser, canonical serializer, version migration chain, `TdfLabel.links` domain representation, three-way atomic list merge, undo preservation, and lossless round-trip persistence, this proposal exposes `TdfLabel.maxLinksPerLabel = 20` and aligns `TaskLink.tryParse` with `spec/TDF_SPEC_0.7.0.md` Section 2.8 Unicode scalar-value and single-line `<text>` validation (`lib/models/tdf_metadata.dart`), extends `TaskEditorLinksSection` (`lib/ui/widgets/task_editor_links_section.dart`) with optional inline link editing and adjacent move-up/move-down reordering controls, integrates link management into `EditLabelScreen` (`lib/ui/edit_labels_screen.dart`), introduces `LabelHubDialog` (`lib/ui/widgets/label_hub_dialog.dart`) to inspect a label's color, scope, description, clickable reference links, and activation conditions in one modal overlay, and wires one-tap Context Hub triggers across `HomeTopBar`, `HomeDrawer`, and `TaskInfoDialog` on Linux, Android, and Windows.

### 1.2 Motivation
`TEP-006` (`spec/TDF_SPEC_0.7.0.md` Section 4.2) extends root `label <label-id> [scoped] { ... }` blocks with `0..MAX_LINKS_PER_LABEL` (`20`) repeatable `link "<title>" "<uri>"` directives at canonical position `5` and preserves existing `label.links` losslessly across edits and synchronization. Without dedicated UI workflows, however, four practical gaps remain:
1. **No In-App Link Authoring, In-Place Editing, or Reordering on Labels:** `EditLabelScreen` (`lib/ui/edit_labels_screen.dart`) currently edits only `name`, `note`, `color`, `isScoped`, and `conditions` while passing `widget.label.links` through unchanged. Users cannot add, edit in place, reorder, launch, or remove shared project links (`https://...`, `mailto:...`, `file:///...`) on a `TdfLabel` without editing the `.tdf` file externally.
2. **UTF-16 vs. Unicode Scalar Validation Drift in `TaskLink.tryParse`:** `TaskLink.tryParse` (`lib/models/tdf_metadata.dart`) currently checks `trimmedTitle.length > maxTextLength` (counting UTF-16 code units rather than Unicode scalar values) and does not reject embedded ASCII control characters (`0x00..0x1F`, `0x7F`) or unpaired UTF-16 surrogates in `<title>`. Consequently, valid 500-scalar supplementary-plane titles are rejected by the UI helper, whereas pasted titles containing internal tabs or control characters pass `TaskLink.tryParse` and then throw an uncaught `TdfException` inside `TaskBoardMutator._validateLabelLinks` on save.
3. **Hidden Label Notes and Conditions During Daily Board Use:** Viewing a label's `note` or `condition` rules currently requires navigating through `HomeDrawer -> Edit -> EditLabelsScreen -> EditLabelScreen`. When `HomeScreen` is filtered to an active label (especially a `scoped` micro-workspace), the label's reference documentation and shared links are not reachable directly from `HomeTopBar` or `HomeDrawer`.
4. **Disconnected Context During Task Execution:** In `TaskInfoDialog` (`lib/ui/widgets/task_info_dialog.dart`), assigned labels render as static non-interactive rows (`_TaskInfoSectionCard._buildLabelChips`). Users executing a task in `Focus` (`Tier 1`) cannot open the parent label's shared runbooks, repositories, or project notes directly from the task info overlay.

### 1.3 Goals & Non-Goals
* **Goals:**
  1. Expose `TdfLabel.maxLinksPerLabel = maxTdfLinksPerLabel` (`20`) and align `TaskLink.tryParse` (`lib/models/tdf_metadata.dart`) with `spec/TDF_SPEC_0.7.0.md` Section 2.8 so `<title>` and `<uri>` reject ASCII control characters (`0x00..0x1F`, `0x7F`) at leading, embedded, and trailing positions before trimming spaces, `<title>` enforces `1..maxTextLength` (`500`) decoded Unicode scalar values, rejects unpaired UTF-16 surrogates, and rejects empty or whitespace-only strings identically to `TaskBoardMutator._validateSingleLineText`.
  2. Extend `TaskEditorLinksSection` (`lib/ui/widgets/task_editor_links_section.dart`) with optional inline link editing and adjacent move-up/move-down reordering controls while maintaining full backward compatibility with `EditTaskScreen`, and integrate it into `EditLabelScreen` (`lib/ui/edit_labels_screen.dart`) to create, edit in place, reorder, launch, and delete `0..20` `TaskLink` entries on `TdfLabel` with `InvalidUri` / forbidden-scheme (`javascript:`, `vbscript:`, `data:`) and `TdfLabel.maxLinksPerLabel` (`20`) validation.
  3. Introduce `LabelHubDialog` (`lib/ui/widgets/label_hub_dialog.dart`) displaying the label's `name`, `color` badge, `scoped` status badge, selectable multi-line `note` (with clipboard copy and confirmation `SnackBar`), clickable `link` rows launched via `LinkLauncherRepository`, active `condition` summaries (`day`, `time`, `location`), an informative empty-state hint when no metadata is configured, live Riverpod `.select(...)` updates across edits and external file watches, safe `ModalRoute`-aware auto-dismissal if the label is deleted externally or the workspace unloads, and a quick `Edit` action navigating to `EditLabelScreen`.
  4. Wire one-tap `LabelHubDialog` access across Linux, Android, and Windows from three UI surfaces:
     - `HomeTopBar` (`lib/ui/widgets/home_top_bar.dart`) when an active label filter is selected (`activeLabel != null`), including while inline search is open.
     - `HomeDrawer` (`lib/ui/widgets/home_drawer.dart`) via a compact trailing info icon button on each `_DrawerLabelTile` that closes the drawer and opens `LabelHubDialog` without altering `activeLabelId` or breaking the `scoped` indicator and task-count badge layout.
     - `TaskInfoDialog` (`lib/ui/widgets/task_info_dialog.dart`) by converting assigned label entries into interactive `ActionChip` widgets stacked below `LabelHubDialog`.
  5. Provide complete English (`en`) and German (`de`) ARB translations (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`) and `AppLogger.event` diagnostic instrumentation gated behind `AppLogger.shouldLog` with zero allocations when disabled and strict privacy redaction (`P-SECRET-HYGIENE`, `AGENTS.md` Section 6).
* **Non-Goals:**
  1. Modifying `.tdf` lexical/structural grammar, canonical serialization order, three-way synchronization rules, or version migration semantics already specified and delivered in `TEP-006` (`spec/TDF_SPEC_0.7.0.md`).
  2. Introducing a separate `project` block type or nested sub-label hierarchy.
  3. Automatically copying `TdfLabel.links` onto assigned `TaskItem.links` records.
  4. Recording label metadata edits on the `TEP-007` task undo stack (undo remains scoped to task mutations, while `updateLabel` leaves unrelated task undo entries intact unless task state or queue placement changes).

### 1.4 Description

#### 1.4.1 Label Reference Link Management in `EditLabelScreen`
`EditLabelScreen` (`lib/ui/edit_labels_screen.dart`) embeds `TaskEditorLinksSection` inside `_EditLabelForm` between `_LabelScopedCard` and `_LabelConditionsSection`:
* **Creating Links:** Users enter a single-line `<title>` (`1..500` decoded Unicode scalar values without ASCII control characters `0x00..0x1F` or `0x7F`, `ValueKey('editor_link_title_input')`) and single-line `<uri>` (`1..2048` decoded Unicode scalar values with a valid RFC-3986 scheme prefix `[a-zA-Z][a-zA-Z0-9+.-]*:`, rejecting `javascript:`, `vbscript:`, `data:` case-insensitively and ASCII control characters, `ValueKey('editor_link_uri_input')`) and press Enter on the URI field or tap `+` (`ValueKey('editor_add_link_button')`).
* **Editing Existing Links In Place:** Tapping the edit icon (`ValueKey('editor_edit_link_$index')`) on an existing link row loads `link.title` and `link.uri` into the title and URI inputs, visually highlights `ValueKey('editor_link_item_$index')`, switches `ValueKey('editor_add_link_button')` to a check icon (`Icons.check_rounded`, tooltip `tooltipSaveLink`), and exposes a cancel-edit icon button (`ValueKey('editor_cancel_edit_link_button')`, tooltip `tooltipCancelEditLink`). Confirming updates `_links[index]` in place so declaration order is preserved; cancelling clears both inputs and exits edit mode without modifying `_links`.
* **Reordering Links & Tracking Active Edits:** Because `spec/TDF_SPEC_0.7.0.md` Section 4.2 and Section 7.1 preserve declaration order for `0..20` `link` directives inside a `label` block, each row in `EditLabelScreen` renders compact move-up (`ValueKey('editor_move_link_up_$index')`) and move-down (`ValueKey('editor_move_link_down_$index')`) icon buttons (disabled with `onPressed: null` at indices `0` and `links.length - 1` respectively). If a row is moved while `_editingLinkIndex` is active, `_editingLinkIndex` moves with the swapped element so subsequent confirmation updates the intended link.
* **Launching & Removing Links:** Tapping open (`ValueKey('editor_open_link_$index')`) launches `link.uri` via `linkLauncherRepositoryProvider` inside a screen-local `ScaffoldMessenger` boundary on `EditLabelScreen`, showing `errorOpenLinkFailed` in a `SnackBar` on `LinkLaunchException` without leaking notifications to underlying routes. Tapping remove (`ValueKey('editor_remove_link_$index')`) deletes `_links[index]`: if `index == _editingLinkIndex`, active edit mode is cancelled and both link controllers are cleared; if `index < _editingLinkIndex`, `_editingLinkIndex` decrements by `1` to stay aligned with the edited item.
* **Pending Draft, Active Edit & Bounds Validation on Save:** Clicking `Save` (`ValueKey('task_editor_save_button')`) checks whether `_editingLinkIndex != null` or either link input contains non-whitespace text. When true, `_addOrUpdateLink()` runs before persisting: if invalid (`linkErrorInvalid`) or if adding a new link when `_links.length >= TdfLabel.maxLinksPerLabel` (`labelLinkErrorMaxExceeded`), `EditLabelScreen` displays the inline error at `ValueKey('editor_link_error_text')` and aborts submission so unconfirmed drafts or cleared in-place edits are never silently discarded or persisted with invalid schemes. When valid, `EditLabelScreen` passes `links: List<TaskLink>.unmodifiable(_links)` to `TaskNotifier.updateLabel`.

#### 1.4.2 `LabelHubDialog` Presentation, Live Reactivity & Actions
`showLabelHubDialog(BuildContext context, {required String labelId})` opens `LabelHubDialog` (`ValueKey('label_hub_dialog')`) as a Material 3 modal `AlertDialog`:
* **Live State Subscription & Safe Auto-Dismissal:** `LabelHubDialog` accepts `labelId` (`String`) and scopes Riverpod rebuilds via `taskNotifierProvider.select(...)` to `hasValue`, `board.findLabel(labelId)`, and `board.locations` (`P-SELECT-REBUILDS`), avoiding rebuilds on unrelated task completions or subtask toggles. Editing the label via the quick `Edit` button (or receiving an external `.tdf` watch update) immediately updates the displayed `name`, `color`, `isScoped`, `note`, `links`, and `conditions` in place. If the label is deleted externally or the workspace unloads so `!hasValue || label == null`, `_LabelHubDialogState` schedules a single guarded post-frame callback that pops the dialog when `route.isCurrent` or calls `Navigator.of(context).removeRoute(route)` when another route such as `EditLabelScreen` is stacked above it.
* **Header:** Displays `labelHubDialogTitle` alongside a circular color swatch (`ValueKey('label_hub_color_badge')`, resolved via `TdfColor.tryParseArgb(label.color)` with theme primary fallback), the label `name`, and a `scoped` status badge (`ValueKey('label_hub_scoped_badge')`, displaying `Icons.visibility_off_outlined` and `labelScopedSwitchTitle`) whenever `label.isScoped` is `true`.
* **Note Card (`ValueKey('label_hub_note_section')`):** Rendered when `label.note` is non-null and non-empty, displaying `taskNoteLabel`, a `SelectableText` body (`ValueKey('label_hub_note_text')`) preserving multi-line formatting, and a copy `IconButton` (`ValueKey('label_hub_copy_note_button')`, tooltip `tooltipCopyNote`) that copies `note` to the system clipboard and shows `noteCopiedSnackBar`.
* **Links Card (`ValueKey('label_hub_links_section')`):** Rendered when `label.links.isNotEmpty`, displaying `linksSectionTitle` and one interactive row (`ValueKey('label_hub_link_item_$index')`) per link in declaration order. Tapping either the row or its trailing open button (`ValueKey('label_hub_open_link_$index')`, tooltip `tooltipOpenLink`) invokes private `_openLabelResourceLink(context, ref.read(linkLauncherRepositoryProvider), link.uri)` (`P-IO-ISOLATION`), catching `LinkLaunchException` and showing `errorOpenLinkFailed` via `ScaffoldMessenger.maybeOf(context)` when `context.mounted`.
* **Conditions Summary Card (`ValueKey('label_hub_conditions_section')`):** Rendered when `label.conditions.isNotEmpty`, displaying `taskConditionsSectionTitle` and formatting active `day`, `time`, and `location` rules via shared `formatConditionSummary` using localized short weekday names (`en` / `de`), `HH:MM - HH:MM` ranges, and resolved `TdfLocation.name` labels (falling back to `<location-id>` or legacy coordinates when unresolved).
* **Empty State Hint (`ValueKey('label_hub_empty_hint')`):** Rendered inside a muted surface card when `note` is null/empty, `links` is empty, and `conditions` is empty, displaying `labelHubEmptyHint` so newly created labels remain clear and actionable via the `Edit` button.
* **Footer Actions:** An `Edit` button (`ValueKey('label_hub_edit_button')`, `actionEdit`) invokes `openEditLabelScreen(context, label: label)` using the latest live `TdfLabel` snapshot, and a `Close` button (`ValueKey('label_hub_close_button')`, `actionClose`) dismisses the dialog.

#### 1.4.3 One-Tap Entry Points Across Linux, Android, and Windows
1. **`HomeTopBar`:** When `activeLabel != null`, `_TopBarTitle` (`ValueKey('top_bar_title')`) wraps the ellipsized label title and a compact trailing `Icons.info_outline_rounded` (`16px`) inside a `Tooltip` (`tooltipOpenLabelHub`) and `Material(type: MaterialType.transparency)` + `InkWell` (`ValueKey('top_bar_label_hub_trigger')`). Tapping the active label title opens `showLabelHubDialog(context, labelId: activeLabel.id)` in both standard tier view and expanded search view without overflowing narrow viewports. When `activeLabel == null`, neither `top_bar_title` nor `top_bar_label_hub_trigger` is rendered.
2. **`HomeDrawer`:** Each `_DrawerLabelTile` (`ValueKey('drawer_label_tile_${label.id}')`) renders a compact `28x28` trailing `IconButton` (`ValueKey('drawer_label_hub_button_${label.id}')`, `Icons.info_outline_rounded` at `16px`, tooltip `tooltipOpenLabelHub`) to the left of the optional `drawer_label_scoped_indicator_${label.id}` icon and `drawer_label_badge_${label.id}` task-count badge. Tapping the tile body continues toggling the active label filter (`onSelectLabel`), whereas tapping `drawer_label_hub_button_${label.id}` closes the drawer route and opens `LabelHubDialog` on the host scaffold context without modifying `activeLabelId`.
3. **`TaskInfoDialog`:** Assigned label entries in `_TaskInfoSectionCard` render inside `_TaskInfoLabelChips` as interactive `ActionChip` widgets (`ValueKey('task_info_label_chip_${label.id}')`, tooltip `tooltipOpenLabelHub`) with the label's `10x10` color avatar and `label.name` text, opening `showLabelHubDialog(context, labelId: label.id)` stacked cleanly above `TaskInfoDialog`.

### 1.5 Alternatives
1. **Navigate Directly to `EditLabelScreen` Instead of `LabelHubDialog`:** Rejected because opening a mutable form screen solely to read a multi-line project note or launch a repository link risks accidental edits and obscures multi-line note reading behind 3-line form text fields. A read-focused modal Context Hub with one-tap link launching, full multi-line `SelectableText`, and a direct `Edit` button separates consumption from mutation.
2. **Drag-and-Drop `ReorderableListView` Inside `EditLabelScreen`:** Rejected because `_EditLabelForm` is already a `SingleChildScrollView` hosting multiple cards; nesting `ReorderableListView` with `shrinkWrap: true` degrades layout performance and creates vertical drag-vs-scroll gesture ambiguity on Android touchscreens. Explicit move-up/move-down icon buttons for `0..20` links are $O(1)$, deterministic, and accessible via touch, mouse, and keyboard across Linux, Android, and Windows.
3. **Render All Label Links Directly Inside Every Assigned `TierTaskPill`:** Rejected because repeating shared project links inside every task expansion panel clutters `Focus` and `Ready` lists. Keeping task-specific links on `TierTaskPill` and shared label resources one tap away via `HomeTopBar`, `HomeDrawer`, and `TaskInfoDialog` preserves visual hierarchy.
4. **Expose Shared `formatConditionSummary` on `TaskInfoDialog` (`task_info_dialog.dart`):** Rejected because `task_info_dialog.dart` must import `label_hub_dialog.dart` to invoke `showLabelHubDialog` from `_TaskInfoLabelChips`; having `label_hub_dialog.dart` also import `task_info_dialog.dart` would create a 2-node Strongly Connected Component (`label_hub_dialog.dart <-> task_info_dialog.dart`), violating `P-ACYCLIC-DAG`. Placing `formatConditionSummary` in `label_hub_dialog.dart` keeps the import edge strictly one-way (`task_info_dialog.dart -> label_hub_dialog.dart`).

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules

All cross-file dependencies preserve `0` Strongly Connected Components (`SCCs`) and strict bottom-up layer rank ordering (`Rank 0: app_logger.dart < Rank 1: models < Rank 2: l10n < Rank 3: services < Rank 4: repositories < Rank 5: providers < Rank 6: ui < Rank 7: main.dart`). Within `Rank 6` (`lib/ui/`), imports follow the strict topological order:
`app_theme.dart` -> `clearable_text_field.dart` -> `task_editor_sections.dart` -> `task_editor_links_section.dart` -> `edit_labels_screen.dart` -> `label_hub_dialog.dart` -> `{home_top_bar.dart, home_drawer.dart, task_info_dialog.dart}` -> `home_screen.dart`.

| Layer / Scope | File | Change Type | Responsibility |
| :--- | :--- | :--- | :--- |
| Domain Models (`Rank 1`) | `lib/models/tdf_metadata.dart` | Modify | Add `static const int maxLinksPerLabel = maxTdfLinksPerLabel;` (`20`) on `TdfLabel` and update `TaskLink.tryParse` to reject ASCII control characters (`0x00..0x1F`, `0x7F`) in `rawTitle` and `rawUri` before `.trim()` and validate `<title>` via `_countUnicodeScalars` (`1..maxTextLength` Unicode scalar values, rejecting unpaired UTF-16 surrogates and empty/whitespace-only strings). |
| Localization (`Rank 2`) | `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | Modify | Add English and German localization keys for `LabelHubDialog` titles, empty-state hint, hub open tooltip, link edit/cancel/save/reorder tooltips, and the 20-link label limit error. |
| UI (`Rank 6`) | `lib/ui/widgets/task_editor_links_section.dart` | Modify | Add optional `editingIndex`, `onCancelEdit`, `onEditLink`, `onMoveLinkDown`, and `onMoveLinkUp` parameters and extract private `StatelessWidget` subtrees so every `build()` stays under 40 lines while preserving `EditTaskScreen` compatibility. |
| UI (`Rank 6`) | `lib/ui/edit_labels_screen.dart` | Modify | Add link controllers, edit/reorder/remove state, screen-local `ScaffoldMessenger` link-launch error feedback, save-time pending-draft and active-edit guard, `AppLogger` instrumentation, `_EditLabelScaffoldBody`, and `_LabelLinksSection` inside `_EditLabelForm`. |
| UI (`Rank 6`) | `lib/ui/widgets/label_hub_dialog.dart` | New | Implement `LabelHubDialog`, `showLabelHubDialog`, and shared top-level `formatConditionSummary` with `.select(...)` subscriptions, `ModalRoute`-aware auto-dismissal on label deletion, clipboard note copy, `LinkLauncherRepository` launching, and `Edit` navigation. |
| UI (`Rank 6`) | `lib/ui/widgets/task_info_dialog.dart` | Modify | Delegate condition formatting to `formatConditionSummary` in `label_hub_dialog.dart` and extract `_TaskInfoLabelChips` rendering interactive `ActionChip` widgets (`task_info_label_chip_${label.id}`) that invoke `showLabelHubDialog` while keeping `_TaskInfoSectionCard.build` under 40 lines. |
| UI (`Rank 6`) | `lib/ui/widgets/home_top_bar.dart`, `lib/ui/home_screen.dart` | Modify | Pass optional `activeLabelId: activeLabel?.id` from `_LandingScaffoldBody` to `HomeTopBar` and extract `_TopBarInteractiveTitle` / `_TopBarTitleRow` inside `_TopBarTitle` wrapping `ValueKey('top_bar_label_hub_trigger')` when `activeLabelId != null`. |
| UI (`Rank 6`) | `lib/ui/widgets/home_drawer.dart` | Modify | Add `ValueKey('drawer_label_hub_button_${label.id}')` to `_DrawerLabelTrailing`, safely closing an open drawer (`ScaffoldState.isDrawerOpen`) and opening `LabelHubDialog` without changing `activeLabelId` or modifying `HomeDrawer.build`. |
| Dev Tooling & Test Harness | `.agents/scripts/tiertask_dev.py`, `test/ui/test_helpers.dart` | Modify | Map `lib/ui/widgets/task_editor_links_section.dart` to both `test/ui/edit_task_screen_test.dart` and `test/ui/edit_labels_screen_test.dart` in `_SUBSYSTEM_TEST_MAP`, and add optional `LinkLauncherRepository? linkLauncherRepository` override to `pumpLeafWidget`. |
| Tests | `test/models/tdf_v050_primitives_test.dart`, `test/ui/edit_labels_screen_test.dart`, `test/ui/widgets/label_hub_dialog_test.dart`, `test/ui/home_screen_test.dart`, `test/ui/home_drawer_test.dart`, `test/ui/widgets/task_info_dialog_test.dart` | Modify / New | Red-Green-Refactor unit and widget tests covering scalar/control-char `TaskLink.tryParse` rules, `EditLabelScreen` link CRUD/reorder/bounds, `LabelHubDialog` live updates/deletion/clipboard/links, and all three one-tap entry points. |
| Documentation | `ARCHITECTURE.md`, `README.md`, `CHANGELOG.md` | Modify | Register `lib/ui/widgets/label_hub_dialog.dart` and `test/ui/widgets/label_hub_dialog_test.dart`, update UI architecture and feature descriptions, and record user-facing additions under `## [Unreleased]`. |

### 2.2 TDF Schema, Localization & State Changes

#### 2.2.1 TDF `0.7.0` Schema Reliance & Domain Validation Alignment (`lib/models/tdf_metadata.dart`)
No changes to `spec/TDF_SPEC_0.7.0.md` are required beyond `TEP-006` Topic 1:
* **Constant Exposure:** Add `static const int maxLinksPerLabel = maxTdfLinksPerLabel;` (`20`, imported from `tdf_error.dart`) on `TdfLabel` (`lib/models/tdf_metadata.dart`), matching `TaskLink.maxLinksPerTask = 20`.
* **`TaskLink.tryParse` Single-Line `<text>` & `<uri>` Control-Character Parity:** Update `TaskLink.tryParse` (`lib/models/tdf_metadata.dart`) to first scan `rawTitle` and `rawUri` in a single $O(N)$ code-unit pass rejecting any ASCII control character (`unit <= 0x1F || unit == 0x7F`) BEFORE calling `.trim()` (because Dart's `String.trim()` strips all `codeUnit <= 0x20`, which would otherwise silently strip leading/trailing NUL `\x00`, `\n`, `\r`, or `\t` bytes instead of rejecting them). After `final trimmedTitle = rawTitle.trim();` and `final trimmedUri = rawUri.trim();`, validate `_countUnicodeScalars(trimmedTitle)` (`null` or `> maxTextLength` -> `null`), require at least one non-space graphic code unit (`unit != 0x20`) in `trimmedTitle`, and validate `isValidUri(trimmedUri)`. This aligns `TaskLink.tryParse` 1:1 with `spec/TDF_SPEC_0.7.0.md` Section 2.8 and `TaskBoardMutator._validateLabelLinks` so `500` supplementary-plane scalar values succeed and pasted control characters, trailing NUL bytes, or lone surrogates fail cleanly with `null` in the UI instead of throwing `TdfException` during `updateLabel`.
* **Revision & Undo Semantics:** `TaskBoard.updateLabel` and `TaskNotifier.updateLabel` already accept `Iterable<TaskLink>? links`, advancing `label.modified = max(now, previousEffectiveModified + 1s)` only when the normalized payload `(scoped, name, note, color, link, condition)` changes while leaving `queue.modified`, task `modified` timestamps, and valid task undo entries untouched.

#### 2.2.2 Localization Keys (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`)

Existing localization keys reused without duplication: `actionCancel`, `actionClose`, `actionEdit`, `actionSave`, `conditionDayAnyLabel`, `conditionGlobalAnyLabel`, `conditionLocationAnyLabel`, `conditionTimeAnyLabel`, `errorOpenLinkFailed`, `labelScopedSwitchTitle`, `linkErrorInvalid`, `linksSectionTitle`, `linkTitleHint`, `linkUriHint`, `noteCopiedSnackBar`, `taskConditionsSectionTitle`, `taskNoteLabel`, `tooltipAddLink`, `tooltipCopyNote`, `tooltipOpenLink`, `tooltipRemoveLink`, and `weekdayMon`..`weekdaySun`.

New ARB keys to add via `tiertask_dev.py l10n --set`:

| Key | English (`app_en.arb`) | German (`app_de.arb`) |
| :--- | :--- | :--- |
| `labelHubDialogTitle` | `"Label Context"` | `"Label-Kontext"` |
| `labelHubEmptyHint` | `"No note, links, or activation conditions configured for this label."` | `"Für dieses Label sind keine Notiz, Links oder Aktivierungsbedingungen hinterlegt."` |
| `labelLinkErrorMaxExceeded` | `"Maximum of 20 links per label reached."` | `"Maximal 20 Links pro Label erreicht."` |
| `tooltipCancelEditLink` | `"Cancel link edit"` | `"Link-Bearbeitung abbrechen"` |
| `tooltipEditLink` | `"Edit link"` | `"Link bearbeiten"` |
| `tooltipMoveLinkDown` | `"Move link down"` | `"Link nach unten verschieben"` |
| `tooltipMoveLinkUp` | `"Move link up"` | `"Link nach oben verschieben"` |
| `tooltipOpenLabelHub` | `"Show label details and links"` | `"Labeldetails und Links anzeigen"` |
| `tooltipSaveLink` | `"Update link"` | `"Link aktualisieren"` |

### 2.3 Implementation Details

#### 2.3.1 `TaskEditorLinksSection` & `EditLabelScreen` (`lib/ui/widgets/task_editor_links_section.dart`, `lib/ui/edit_labels_screen.dart`)
* **`TaskEditorLinksSection` Constructor & Subtrees (`P-FLATTEN-BUILD` < 40 lines per `build()`):**
  - Keep existing required parameters (`canAddLink`, `errorMessage`, `links`, `titleController`, `uriController`, `onAddLink`, `onOpenLink`, `onRemoveLink`) so `EditTaskScreen` requires zero call-site changes, and add optional named parameters:
    ```dart
    this.editingIndex,
    this.onCancelEdit,
    this.onEditLink,
    this.onMoveLinkDown,
    this.onMoveLinkUp,
    ```
  - Extract dedicated private `StatelessWidget` classes rather than helper methods returning `Widget`:
    - `_TaskEditorLinksList`: renders `for (var i = 0; i < links.length; i++) _TaskEditorLinkRow(...)` with `isEditing: editingIndex == i`, passing `onMoveUp: onMoveLinkUp != null && i > 0 ? () => onMoveLinkUp?.call(i) : null` and `onMoveDown: onMoveLinkDown != null && i + 1 < links.length ? () => onMoveLinkDown?.call(i) : null`, while still rendering disabled `IconButton`s (`onPressed: null`) at boundary indices `0` and `links.length - 1` whenever `onMoveLinkUp != null || onMoveLinkDown != null`.
    - `_TaskEditorLinkRow` (`ValueKey('editor_link_item_$index')`): highlights the row background/border when `isEditing` is `true` and delegates trailing buttons to `_TaskEditorLinkRowActions` (`editor_move_link_up_$index` with `Icons.arrow_upward_rounded`, `editor_move_link_down_$index` with `Icons.arrow_downward_rounded`, `editor_edit_link_$index` with `Icons.edit_outlined`, `editor_open_link_$index` with `Icons.open_in_new_rounded`, and `editor_remove_link_$index` with `Icons.close_rounded`).
    - `_TaskEditorLinkInputRow`, `_TaskEditorLinkTextField`, and `_TaskEditorLinkSubmitButtons`: when `isEditing` (`editingIndex != null`), `ValueKey('editor_add_link_button')` renders `Icons.check_rounded` with tooltip `localizations.tooltipSaveLink`, followed by `IconButton` (`ValueKey('editor_cancel_edit_link_button')`, `Icons.close_rounded`, tooltip `localizations.tooltipCancelEditLink`, `onPressed: onCancelEdit`).
* **`_EditLabelScreenState` & `_LabelLinksSection` (`lib/ui/edit_labels_screen.dart`):**
  - Add instance fields in `AGENTS.md` Section 2.5 order:
    - `int? _editingLinkIndex;`
    - `bool _lastCanSubmitLink = false;`
    - `String? _linkErrorMessage;`
    - `final TextEditingController _linkTitleController = TextEditingController();`
    - `final TextEditingController _linkUriController = TextEditingController();`
    - `late final List<TaskLink> _links;` (initialized in `initState()` via `List<TaskLink>.of(widget.label.links)`)
    - `final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();`
  - Computed getter:
    ```dart
    bool get _canSubmitLink =>
        (_editingLinkIndex != null ||
            _links.length < TdfLabel.maxLinksPerLabel) &&
        (_linkTitleController.text.trim().isNotEmpty ||
            _linkUriController.text.trim().isNotEmpty);
    ```
  - Register `_linkTitleController.addListener(_handleLinkInputChanged)` and `_linkUriController.addListener(_handleLinkInputChanged)` in `initState()`, and remove listeners and `.dispose()` both controllers in `dispose()` (`P-DISPOSE-RESOURCES`).
  - Wrap `EditLabelScreen`'s `Scaffold` in `ScaffoldMessenger(key: _scaffoldMessengerKey, ...)`, delegate the `Scaffold` body to `_EditLabelScaffoldBody({required this.state})` -> `_EditLabelForm({required this.state})`, and place `_LabelLinksSection({required this.state})` between `_LabelScopedCard` and `_LabelConditionsSection` so `_EditLabelScreenState.build`, `_EditLabelScaffoldBody.build`, `_EditLabelForm.build`, and `_LabelLinksSection.build` each stay well under 40 lines (`P-FLATTEN-BUILD`).
  - `_addOrUpdateLink()`:
    - When `_editingLinkIndex == null && _links.length >= TdfLabel.maxLinksPerLabel`, calls `setState(() => _linkErrorMessage = localizations.labelLinkErrorMaxExceeded)` and returns `false` (`P-BOUND-ALLOC`).
    - Calls `TaskLink.tryParse(rawTitle: _linkTitleController.text, rawUri: _linkUriController.text)`; when `null`, calls `setState(() => _linkErrorMessage = localizations.linkErrorInvalid)` and returns `false`.
    - Inside `setState`: if `_editingLinkIndex case final editIndex?` (`0 <= editIndex && editIndex < _links.length`), assigns `_links[editIndex] = parsed`; otherwise `_links.add(parsed)`. Resets `_editingLinkIndex = null`, `_lastCanSubmitLink = false`, `_linkErrorMessage = null`, and clears `_linkTitleController` and `_linkUriController`, returning `true`.
  - `_beginEditLink(int index)`:
    - Guards `if (index < 0 || index >= _links.length) return;`, and inside `setState` sets `_editingLinkIndex = index` and `_linkErrorMessage = null` first (so `_canSubmitLink` evaluates with active edit state even at `20` links), populates `_linkTitleController.text = _links[index].title` and `_linkUriController.text = _links[index].uri`, and updates `_lastCanSubmitLink = _canSubmitLink`.
  - `_cancelEditLink()`:
    - Inside `setState`, resets `_editingLinkIndex = null`, `_linkErrorMessage = null`, and `_lastCanSubmitLink = false`, and clears both link controllers.
  - `_moveLink(int index, int delta)`:
    - Computes `targetIndex = index + delta`; returns early unless `0 <= index && index < _links.length && 0 <= targetIndex && targetIndex < _links.length`.
    - Swaps `_links[index]` and `_links[targetIndex]` inside `setState`, updating `_editingLinkIndex` (`index -> targetIndex` or `targetIndex -> index`) so an active in-place edit follows the moved link.
  - `_openLink(String uri)`:
    - Invokes `await ref.read(linkLauncherRepositoryProvider).openLink(uri);` inside `try / on LinkLaunchException`, checking `if (!mounted) return;` before showing `SnackBar(content: Text(AppLocalizations.of(context).errorOpenLinkFailed))` on `_scaffoldMessengerKey.currentState` (`P-IO-ISOLATION`).
  - `_removeLink(int index)`:
    - Guards `if (index < 0 || index >= _links.length) return;`.
    - Removes `_links.removeAt(index)` inside `setState`: if `_editingLinkIndex == index`, clears `_editingLinkIndex = null` and both link controllers; else if `_editingLinkIndex case final editIndex? when index < editIndex`, sets `_editingLinkIndex = editIndex - 1`. Clears `_linkErrorMessage = null` and updates `_lastCanSubmitLink = _canSubmitLink`.
  - `_submit()`:
    - Validates label name and hex color first, then checks `hasPendingLink = _linkTitleController.text.trim().isNotEmpty || _linkUriController.text.trim().isNotEmpty`.
    - If `(_editingLinkIndex != null || hasPendingLink) && !_addOrUpdateLink()`, aborts submission immediately.
    - Emits `AppLogger.event(LogLevel.info, LogTag.ui, 'ui.label_editor.save', fields: <String, Object?>{'id': widget.label.id, 'links': _links.length, 'scoped': _isScoped})` gated behind `if (AppLogger.shouldLog(LogLevel.info))` (`P-SECRET-HYGIENE`, `P-ZERO-ALLOC`).
    - Awaits `ref.read(taskNotifierProvider.notifier).updateLabel(widget.label.id, ..., links: List<TaskLink>.unmodifiable(_links), conditions: _conditionController.buildConditions())`, checks `if (!mounted) return;`, and pops `Navigator.of(context)`.

#### 2.3.2 `LabelHubDialog` & Shared Condition Formatting (`lib/ui/widgets/label_hub_dialog.dart`)
* **Top-Level Entry & Formatting Functions:**
  ```dart
  String formatConditionSummary(
    TaskCondition condition,
    Iterable<TdfLocation> locations,
    AppLocalizations localizations,
  )

  Future<void> showLabelHubDialog(
    BuildContext context, {
    required String labelId,
  })
  ```
  - `formatConditionSummary` uses an exhaustive `switch (condition)` ordered by `TaskCondition` declaration order (`DayTaskCondition`, `GlobalResetTaskCondition`, `GroupResetTaskCondition`, `LocationTaskCondition`, `TimeWindowTaskCondition`) without a `default:` branch (`P-EXHAUSTIVE-SWITCH`).
  - `showLabelHubDialog` gates `AppLogger.event(LogLevel.info, LogTag.ui, 'ui.label_hub.open', fields: <String, Object?>{'id': labelId})` behind `if (AppLogger.shouldLog(LogLevel.info))` and calls `showDialog<void>(context: context, builder: (_) => LabelHubDialog(labelId: labelId))`.
* **`LabelHubDialog` (`ConsumerStatefulWidget`) & Subtrees (`P-FLATTEN-BUILD`, `P-SELECT-REBUILDS`):**
  - `_LabelHubDialogState` holds `bool _didScheduleClose = false;` and watches only:
    - `final hasBoard = ref.watch(taskNotifierProvider.select((asyncBoard) => asyncBoard.hasValue));`
    - `final label = ref.watch(taskNotifierProvider.select((asyncBoard) => asyncBoard.asData?.value.findLabel(widget.labelId)));`
    - `final locations = ref.watch(taskNotifierProvider.select((asyncBoard) => asyncBoard.asData?.value.locations ?? const <TdfLocation>[]));`
  - When `!hasBoard || label == null`, calls `_scheduleAutoClose()` and returns `const SizedBox.shrink()`. `_scheduleAutoClose()` sets `_didScheduleClose = true` once and registers `WidgetsBinding.instance.addPostFrameCallback` which checks `if (!mounted) return;`, inspects `final route = ModalRoute.of(context);`, and when `route != null && route.isActive` calls `Navigator.of(context).pop()` if `route.isCurrent` or `Navigator.of(context).removeRoute(route)` if another route (`EditLabelScreen`) is stacked above `LabelHubDialog`.
  - Extracts private `StatelessWidget` classes (`_LabelHubHeader`, `_LabelHubBody`, `_LabelHubSectionCard`, `_LabelHubNoteSection`, `_LabelHubLinksSection`, `_LabelHubLinkRow`, `_LabelHubConditionsSection`, `_LabelHubEmptyCard`) so every `build()` method stays under 40 lines and `<= 3` indentation levels (`P-FLAT-CONTROL-FLOW`).
  - Note copying (`_copyLabelNoteToClipboard`) gates `AppLogger.event(LogLevel.info, LogTag.ui, 'label.note.copied', fields: <String, Object?>{'id': labelId, 'length': note.length})` behind `if (AppLogger.shouldLog(LogLevel.info))`, awaits `Clipboard.setData(ClipboardData(text: note))`, checks `if (!context.mounted) return;`, and shows `localizations.noteCopiedSnackBar` via `ScaffoldMessenger.maybeOf(context)`.
  - Link launching (`_openLabelResourceLink`) awaits `repository.openLink(uri)` (`P-IO-ISOLATION`) inside `try / on LinkLaunchException`, checks `if (!context.mounted) return;`, and shows `localizations.errorOpenLinkFailed` via `ScaffoldMessenger.maybeOf(context)` without importing or modifying `tier_task_subtasks_section.dart`.

#### 2.3.3 `HomeTopBar`, `HomeScreen`, `HomeDrawer` & `TaskInfoDialog` Wiring
* **`HomeScreen` & `HomeTopBar` (`lib/ui/home_screen.dart`, `lib/ui/widgets/home_top_bar.dart`):**
  - `_LandingScaffoldBody` (`lib/ui/home_screen.dart`) passes `activeLabelId: activeLabel?.id` to `HomeTopBar` without touching `_HomeScreenState` or `_HomeScaffold` (keeping `_HomeScaffold.build` at 38 lines and `_LandingScaffoldBody.build` at 31 lines, `< 40` lines per `P-FLATTEN-BUILD`).
  - `HomeTopBar` (`lib/ui/widgets/home_top_bar.dart`, importing `label_hub_dialog.dart`) accepts optional `this.activeLabelId` (`final String? activeLabelId;`) and passes it through `_TopBarCenterArea` -> `_TopBarAnimatedSlots` -> `_TopBarTitle`.
  - Inside `lib/ui/widgets/home_top_bar.dart`, keep `_TopBarTitle` (`ValueKey('top_bar_title')`) under 40 lines by extracting `_TopBarInteractiveTitle` and `_TopBarTitleRow` (`StatelessWidget`s): when `activeLabelId case final labelId?`, render `Tooltip(message: localizations.tooltipOpenLabelHub)` -> `Material(type: MaterialType.transparency)` -> `InkWell(key: const ValueKey('top_bar_label_hub_trigger'), borderRadius: BorderRadius.circular(8), onTap: () => showLabelHubDialog(context, labelId: labelId))` -> `Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4))` -> `_TopBarTitleRow`, which uses `LayoutBuilder` and `Row(mainAxisSize: MainAxisSize.min)` (`mainAxisSize: MainAxisSize.min` is required so `_TopBarLayoutDelegate` centers short titles horizontally) containing `Flexible(child: Text(title, key: ValueKey<String>(title), maxLines: 1, overflow: TextOverflow.ellipsis, ...))` plus a `6px` gap and `16px` `Icons.info_outline_rounded` whenever `innerConstraints.maxWidth >= 28`.
* **`HomeDrawer` (`lib/ui/widgets/home_drawer.dart`):**
  - Keep `HomeDrawer`, `_DrawerLabelsSection`, and `_DrawerLabelTile` signatures and `build()` line counts unchanged (`HomeDrawer.build` stays at 39 lines, `< 40` lines per `P-FLATTEN-BUILD`).
  - In `_DrawerLabelTrailing`, always render a `Row(mainAxisSize: MainAxisSize.min)` containing:
    1. `IconButton` (`key: ValueKey('drawer_label_hub_button_${label.id}')`, `visualDensity: VisualDensity.compact`, `padding: EdgeInsets.zero`, `constraints: const BoxConstraints(minWidth: 28, minHeight: 28)`, `tooltip: localizations.tooltipOpenLabelHub`, `icon: Icon(Icons.info_outline_rounded, size: 16, color: iconColor)`, `onPressed: () => _openDrawerLabelHub(context, label.id)`),
    2. `const SizedBox(width: 4)`,
    3. when `label.isScoped`, the existing `Tooltip` + `Icon` (`ValueKey('drawer_label_scoped_indicator_${label.id}')`, `Icons.visibility_off_outlined`, `size: 16`) + `const SizedBox(width: 6)`,
    4. `Badge.count` (`ValueKey('drawer_label_badge_${label.id}')`, `count: count`).
  - Private helper `_openDrawerLabelHub(BuildContext context, String labelId)` inspects `final scaffoldState = Scaffold.maybeOf(context); final hostContext = scaffoldState?.context ?? Navigator.of(context).context;`, closes the drawer via `scaffoldState.closeDrawer()` when `scaffoldState != null && scaffoldState.isDrawerOpen` (or `Navigator.of(context).pop()` only when `Navigator.of(context).canPop()`, preventing root-route pop crashes in isolated `pumpLeafWidget` harnesses), and invokes `showLabelHubDialog(hostContext, labelId: labelId)` without invoking `onSelectLabel`.
* **`TaskInfoDialog` (`lib/ui/widgets/task_info_dialog.dart`):**
  - Replace duplicate private condition formatting helpers (`_formatCondition`, `_formatDayCondition`, `_formatGroupResetCondition`, `_formatLocationCondition`, `_formatWeekday`) with `formatConditionSummary(condition, board.locations, localizations)` imported from `label_hub_dialog.dart`.
  - Extract `_TaskInfoLabelChips` (`StatelessWidget`) from `_TaskInfoSectionCard._buildLabelChips` while keeping `_TaskInfoSectionCard.build` under 40 lines (`P-FLATTEN-BUILD`), rendering `Wrap(spacing: 8, runSpacing: 6)` of `ActionChip` widgets (`key: ValueKey('task_info_label_chip_${label.id}')`, `tooltip: localizations.tooltipOpenLabelHub`, `visualDensity: VisualDensity.compact`, `materialTapTargetSize: MaterialTapTargetSize.shrinkWrap`, `10x10` circular color `avatar`, `label: Text(label.name)`, `onPressed: () => showLabelHubDialog(context, labelId: label.id)`).

### 2.4 Testing Strategy
1. **`test/models/tdf_v050_primitives_test.dart` (`M-EXTREME-BOUND-TESTS`, `M-DELIM-INJECT-TESTS`, `M-URI-PATH-EDGE-TESTS`):**
   - Verify `TdfLabel.maxLinksPerLabel == 20`.
   - Verify `TaskLink.tryParse` counts decoded Unicode scalar values rather than UTF-16 code units: `500` supplementary-plane scalar values (`'\u{10400}' * 500`, `1000` UTF-16 code units) succeed, whereas `501` scalar values (`'\u{10400}' * 501` and `'a' * 501`) return `null`; `<uri>` at `2048` scalar values succeeds and `2049` scalar values returns `null`.
   - Verify `TaskLink.tryParse` rejects leading, embedded, and trailing `\n`, `\r`, `\t`, NUL (`\x00`), DEL (`\x7F`), and unpaired UTF-16 surrogates (`String.fromCharCodes(<int>[0x41, 0xD800, 0x42])`) in `<title>` and `<uri>` (while still trimming surrounding ASCII spaces), empty/space-only `<title>`, missing URI schemes, and case-insensitive `javascript:`, `vbscript:`, and `data:` schemes while preserving valid `https://`, `mailto:`, and `file:///` URIs containing `#fragment`, `?query=1&b=2`, spaces, and Windows/POSIX path segments.
2. **`test/ui/edit_labels_screen_test.dart` (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`, `M-DELIM-INJECT-TESTS`, `M-URI-PATH-EDGE-TESTS`, `M-IO-TESTS`):**
   - Verify creating links (via `+` button and keyboard Enter submit), editing an existing link in place (preserving declaration index, showing check + cancel buttons, and restoring state on `editor_cancel_edit_link_button`), moving links up and down (verifying disabled boundary buttons at `0` and `N - 1`, tracking `_editingLinkIndex` across swaps, and persisting the exact declaration order on `TdfLabel.links`), and removing links (including removing a link before `_editingLinkIndex` and removing the actively edited link itself without `RangeError`).
   - Verify save-time validation: valid pending draft auto-submits on `Save`; cleared in-place edit (`_editingLinkIndex != null` with empty inputs) or invalid pending URI (`example.com`, `javascript:alert(1)`, `vbscript:msgbox`, `DaTa:text/html,1`, control characters, or empty `<title>`) aborts `Save` and renders `linkErrorInvalid` at `editor_link_error_text`.
   - Verify `M-EXTREME-BOUND-TESTS`: `19 -> 20` links accepted, `editor_add_link_button` disabled at `20` links when not editing, `21st` pending link rejected on Enter/`Save` with `labelLinkErrorMaxExceeded`, while editing one of the `20` existing links in place succeeds; verify `<title>` `500` vs. `501` Unicode scalar values (`\u{10400}`) and `<uri>` `2048` vs. `2049` scalar values.
   - Verify launching a link from `EditLabelScreen` via `FakeLinkLauncherRepository` (both success recording `launchedUris` and `shouldThrow: true` displaying `errorOpenLinkFailed` inside `EditLabelScreen`'s `ScaffoldMessenger`), and verify `ui.label_editor.save` diagnostic logging omits raw names, notes, link titles, and URIs.
3. **`test/ui/widgets/label_hub_dialog_test.dart` (`M-EXHAUSTIVE-STATE-TESTS`, `M-IO-TESTS`, `M-REAL-MECHANICS-TESTS`):**
   - Mount `LabelHubDialog` via `pumpLeafWidget` (`FakeTaskNotifier` + `FakeLinkLauncherRepository`) across all combinations: empty metadata (`label_hub_empty_hint`), custom `#RRGGBB` vs. fallback color badge, `scoped` vs. regular badge visibility, multi-line `note` `SelectableText` + clipboard copy (`Clipboard.getData` mock channel + `noteCopiedSnackBar`), multiple `links` (both row tap and `label_hub_open_link_$index` tap, plus `LinkLaunchException` `SnackBar`), and `day` / `time` / `location` (resolved `TdfLocation.name` and unresolved fallback) condition summaries in both `en` and `de` locales.
   - Verify tapping `label_hub_edit_button` pushes `EditLabelScreen`, saves updated `name`, `isScoped`, `note`, `links`, and `conditions`, immediately updates the open `LabelHubDialog` upon pop, and passes the updated `TdfLabel` if `Edit` is opened a second time.
   - Verify safe auto-dismissal when `labelId` is deleted externally while `LabelHubDialog` is current (`route.isCurrent`) AND when `EditLabelScreen` is stacked above `LabelHubDialog` (`!route.isCurrent`, removing `LabelHubDialog` via `removeRoute` without popping `EditLabelScreen`).
   - Verify `AppLogger` `ui.label_hub.open` and `label.note.copied` events are suppressed with zero entries when `diagnosticsEnabled == false` and omit raw label names, notes, link titles, and URIs when enabled (`P-SECRET-HYGIENE`).
4. **`test/ui/home_screen_test.dart`, `test/ui/home_drawer_test.dart` & `test/ui/widgets/task_info_dialog_test.dart` (`M-EXHAUSTIVE-STATE-TESTS`, `M-REAL-MECHANICS-TESTS`):**
   - Verify `top_bar_label_hub_trigger` is absent in the unfiltered global view, appears inside `top_bar_title` when a label filter is active (without `RenderFlex` overflow on 500-character label names or narrow search layouts), and opens `LabelHubDialog` on tap in both tier view and active search view.
   - Verify tapping `drawer_label_hub_button_<id>` in `HomeDrawer` closes the drawer and opens `LabelHubDialog` while leaving `activeLabelId` unchanged and preserving the horizontal ordering `labelTitle <= hubButton <= scopedIndicator <= badge`, whereas tapping `drawer_label_tile_<id>` still toggles the board filter.
   - Verify tapping `task_info_label_chip_<id>` inside `TaskInfoDialog` opens `LabelHubDialog` stacked above `TaskInfoDialog`, reflects edits in both `LabelHubDialog` and the underlying `TaskInfoDialog`, and exercises real `Directory.watch` / `LocalFileRepository` external `.tdf` reconciliation (`M-REAL-MECHANICS-TESTS`) updating `label.links` and retiring a label while `LabelHubDialog` is open, as well as preserving unrelated task undo entries across `updateLabel`.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [ ] Run `python3 .agents/scripts/tiertask_dev.py verify --fast` to confirm a clean baseline after `TEP-006`.
- [ ] Add English and German localization keys (`labelHubDialogTitle`, `labelHubEmptyHint`, `labelLinkErrorMaxExceeded`, `tooltipCancelEditLink`, `tooltipEditLink`, `tooltipMoveLinkDown`, `tooltipMoveLinkUp`, `tooltipOpenLabelHub`, `tooltipSaveLink`) to `lib/l10n/app_en.arb` and `lib/l10n/app_de.arb` via `tiertask_dev.py l10n --set` and run `flutter gen-l10n`.
- [ ] Update `_SUBSYSTEM_TEST_MAP` in `.agents/scripts/tiertask_dev.py` for `lib/ui/widgets/task_editor_links_section.dart` and add optional `linkLauncherRepository` override support to `pumpLeafWidget` in `test/ui/test_helpers.dart`.
- [ ] Write failing unit and widget tests first in `test/models/tdf_v050_primitives_test.dart`, `test/ui/edit_labels_screen_test.dart`, `test/ui/widgets/label_hub_dialog_test.dart`, `test/ui/home_screen_test.dart`, `test/ui/home_drawer_test.dart`, and `test/ui/widgets/task_info_dialog_test.dart` (TDD Red Phase — `P-TDD-FIRST`).
- [ ] Implement `TdfLabel.maxLinksPerLabel` and Unicode-scalar `TaskLink.tryParse` validation in `lib/models/tdf_metadata.dart`, inline edit/reorder controls in `lib/ui/widgets/task_editor_links_section.dart`, link management in `lib/ui/edit_labels_screen.dart`, `LabelHubDialog` and `formatConditionSummary` in `lib/ui/widgets/label_hub_dialog.dart`, and one-tap Context Hub entry points in `lib/ui/widgets/home_top_bar.dart`, `lib/ui/home_screen.dart`, `lib/ui/widgets/home_drawer.dart`, and `lib/ui/widgets/task_info_dialog.dart` with `AppLogger` instrumentation (TDD Green & Refactor Phase).
- [ ] Update Parts 1 and 2 if implementation details evolve during coding.
- [ ] Run `python3 .agents/scripts/tiertask_dev.py arch --sync-tree --set lib/ui/widgets/label_hub_dialog.dart "Modal Label Context Hub dialog and shared condition summary formatter displaying a label's color, scope, selectable note, clickable links, conditions, and edit action."` and synchronize `ARCHITECTURE.md` and `README.md` per **`update-documentation`**.
- [ ] Update `CHANGELOG.md` under `## [Unreleased]` per **`changelog-updater`**.
- [ ] Run `python3 .agents/scripts/tiertask_dev.py verify --full --fix`.
- [ ] Set `status: review`, update `BOARD.md`, and request user approval.
- [ ] After user approval, set `status: completed`, update `BOARD.md`, and list delivered artifacts in Part 3.3.

### 3.2 Work Log & Decisions
* **2026-11-14:** Drafted initial concept (`status: concept`) for the Label Context Hub and `EditLabelScreen` reference link management workflows built on top of `TEP-006` (`spec/TDF_SPEC_0.7.0.md` Topic 1).
* **2026-11-14:** Elaborated full technical specification (`status: planned`): aligned `TaskLink.tryParse` with `spec/TDF_SPEC_0.7.0.md` Section 2.8 Unicode scalar-value and control-character rules, added `TdfLabel.maxLinksPerLabel`, placed shared `formatConditionSummary` in `label_hub_dialog.dart` to preserve `0` SCCs (`P-ACYCLIC-DAG`), specified deterministic `_editingLinkIndex` tracking across move/remove/save, defined `ModalRoute`-aware auto-dismissal on external label deletion, and expanded `M-*` TDD test coverage.

### 3.3 Delivered Artifacts
*(Pending — proposal is in `planned` stage)*
