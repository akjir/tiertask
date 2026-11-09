---
id: TEP-006
title: TDF Specification 0.7.0 Exploratory Design and Idea Collection
status: concept
type: spec
created: 2026-11-09
updated: 2026-11-09
---

# TEP-006: TDF Specification 0.7.0 Exploratory Design and Idea Collection

> [!NOTE]
> **Exploratory Idea Collection (`status: concept`):** This proposal serves as the living design collection for **TierTask Data Format (`TDF`) `0.7.0`**. New candidate specification features, domain refinements, and workflow ideas for `0.7.0` are collected, evaluated, and refined here before advancing to `planned` and updating the normative specification.

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal collects and evaluates candidate enhancements for **TierTask Data Format (`TDF`) `0.7.0`**. The initial anchor topic (**Topic 1: Label Links and Context Hubs**) extends root `label <label-id> [scoped] { ... }` blocks with repeatable `link "<title>" "<uri>"` directives (`0..MAX_LINKS_PER_LABEL`) and elevates labels in the TierTask UI from passive filter tags to lightweight **Project Collections and Context Hubs** that bundle a context's tasks, description (`note`), reference URIs (`link`), visibility scope (`scoped`), and activation rules (`condition`) in one place.

### 1.2 Motivation

#### 1.2.1 Topic 1: Why Label Links and Project / Context Hubs Are Valuable
In `TDF 0.6.0`, `task` blocks support repeatable `link "<title>" "<uri>"` directives (`0..20`), whereas `label` blocks are limited to `name`, `color`, `note`, `modified`, and `condition`. Extending `label` with `link` directives and presenting labels as dedicated **Context Hubs** solves five structural problems without adding a separate `project` entity type:

1. **Single Source of Truth for Shared Project Resources (No Link Duplication Across Tasks):**
   * Labels frequently represent ongoing projects, clients, university courses, infrastructure domains, or areas of responsibility (for example, `"Tax Return 2026"`, `"IT & Servers"`, `"Client: Acme"`, or `"Home & Garden"`).
   * Almost every task in such a label relies on the same shared entry points: a Git repository (`https://github.com/...`), an issue tracker board (`https://jira.example.com/...`), a cloud or local document folder (`file:///home/user/documents/tax2026`), a runbook wiki, or a dashboard URL.
   * When only `task` blocks can hold `link` directives, users and external CLI/AI agents must either duplicate the same 3–5 project links across dozens of tasks (bloating the `.tdf` file and making URI updates require $O(N)$ task edits) or create an artificial "meta-task" that is never meant to be completed solely to store project links (polluting the active pull queue or `Someday`).
   * Storing shared links directly on the `label` block places permanent context resources at the hierarchy level where they belong, while keeping task-level `link` directives focused on task-specific artifacts (such as a specific pull request, invoice PDF, or email thread).
2. **Labels as Lightweight Project / Context Hubs Without Hierarchy Bloat:**
   * TierTask intentionally avoids deep folder trees, sub-projects, or separate project databases.
   * In `TDF 0.6.0`, a `label` already aggregates visual identity (`name`, `color`), extended documentation (`note` up to `2000` Unicode scalar values), global-view isolation (`scoped`), and environmental activation rules (`condition` for `day`, `time`, and `location`).
   * Adding `link "<title>" "<uri>"` completes the `label` entity as a self-contained **Context Hub**: selecting a label in the navigation drawer filters the 6-tier board to that context and immediately gives the user one-tap access to the label's `note` and `link` collection from the top bar or drawer.
3. **Synergy with `scoped` Labels (Self-Contained Micro-Workspaces):**
   * `TDF 0.6.0` introduced `label <label-id> scoped { ... }` so dedicated project backlogs, study modules, or checklists do not flood the unfiltered global `Focus` and `Ready` tiers.
   * Combining `scoped` + `note` + `link` turns a scoped label into a lightweight micro-workspace inside a single `.tdf` file: when the user switches into that scoped label view, all reference links (`file://`, `https://`, `mailto:`) and project notes are immediately accessible at the top of the board.
4. **Contextual Reference Access During `Focus` Execution:**
   * When executing a task in `Focus` (`Tier 1`) or inspecting a task via `TaskInfoDialog`, the user can access both the task's own `link` entries (specific to that step) and the assigned label hub's `link` entries (general project environment) without leaving the current workflow.
5. **AI Agent and CLI Context Discovery with Zero New Lexical Primitives:**
   * Autonomous CLI tools and AI agents inspecting a `.tdf` file can read a `label` block's `link` and `note` directives to discover the associated local repository path (`file://...`), documentation URL, or issue tracker URL for all tasks carrying that `<label-id>`.
   * Because `link "<title>" "<uri>"` already exists in the `TDF 0.6.0` grammar with full lexical, length, and scheme-security validation (`InvalidUri` for missing schemes or `javascript:`, `vbscript:`, `data:`), reusing `link` inside `label` blocks requires zero new lexical token types and preserves single-pass $O(N)$ scanning and parsing.

### 1.3 Goals & Non-Goals
* **Goals (Initial `0.7.0` Idea Collection):**
  * Collect and evaluate candidate features for `TDF 0.7.0` in a structured, incremental specification proposal.
  * **Topic 1 (`label.link` & Label Context Hub):**
    * Permit `0..MAX_LINKS_PER_LABEL` (`20`) repeatable `link "<title>" "<uri>"` directives inside `label` blocks using the exact lexical, character-length (`MAX_TEXT_LENGTH = 500`, `MAX_URI_LENGTH = 2048`), and scheme-validation rules (`InvalidUri` on missing scheme or `javascript:`, `vbscript:`, `data:`) defined for `task.link`.
    * Define canonical serialization order inside `label` blocks (`1. name`, `2. color`, `3. note`, `4. modified`, `5. link`, `6. condition`).
    * Define normalization, payload comparison, and three-way baseline merge rules for `label.link` (merging the ordered `link` list on a `label` as one atomic merge unit, matching `task.link`).
    * Design a **Label Context Hub** UI flow (in `EditLabelScreen`, `HomeTopBar` when a label filter is active, `HomeDrawer`, and `TaskInfoDialog`) so users can view a label's `note` and launch its `link` URIs directly.
* **Non-Goals (Current Stage):**
  * Introducing a separate `project` root block type that duplicates `label` semantics.
  * Modifying `lib/` or `spec/TDF_SPEC_0.6.0.md` while `TEP-006` remains in `status: concept`.
  * Altering 6-tier derivation (`Section 5`) or condition evaluation (`Section 4.4`) based on `label.link` metadata.

### 1.4 Candidate Topics for TDF 0.7.0

#### 1.4.1 Topic 1: Label Links (`link "<title>" "<uri>"` in `label`) and Label Context Hub
* **TDF Grammar & Schema (`label` Block):**
  ```text
  label 9kLm2P0aBc scoped {
      name     "IT & Servers"
      color    "#2196F3"
      note     "Primary homelab and backup infrastructure"
      modified 2026-11-09 18:00
      link     "Proxmox Dashboard" "https://pve.lan.example.com:8006"
      link     "Ansible Playbooks" "file:///home/stefan/infra/ansible"

      condition {
          day  mon tue wed thu fri
          time 08:00 18:00
      }
  }
  ```
* **Validation Rules:**
  * Identical to `task.link` (Sections 2.8, 4.1.2, 7, and 8):
    * Requires exactly `2` quoted string arguments (`"<title>"` and `"<uri>"`, accepting `"..."` or `'...'` in input and emitting double-quoted `"..."` canonically).
    * `<title>`: Single-line `<text>` (`1..MAX_TEXT_LENGTH = 500` decoded Unicode scalar values; `EmptyText` if empty or ASCII whitespace only; `UnexpectedToken` if decoded `\n`, `\r`, or `\t` is present; `LimitExceeded` if $> 500$).
    * `<uri>`: Single-line `<uri>` (`1..MAX_URI_LENGTH = 2048` decoded Unicode scalar values; `EmptyText` if empty or ASCII whitespace only; `InvalidUri` if decoded control characters exist, if the scheme prefix `[a-zA-Z][a-zA-Z0-9+.-]*:` is missing, or if the scheme is `javascript:`, `vbscript:`, or `data:` matched case-insensitively; `LimitExceeded` if $> 2048$).
    * Multiplicity: `0..MAX_LINKS_PER_LABEL` (`20`, or unified `MAX_LINKS_PER_ENTITY = 20`) per `label` block in preserved declaration order (`LimitExceeded` on the 21st `link` directive in a `label` block).
* **Ordinary Mutation & Synchronization Rules:**
  * Adding, editing, reordering, or removing a `link` on a `label` updates `label.modified = max(now, previousEffectiveModified + 1 second)` and leaves task revisions and `queue.modified` untouched.
  * In Section 6.7.3 (`Normalized Payloads`), extend `Label payload` to `(scoped, name, note, color, link, condition)`.
  * In Section 6.7.5 (`Merge Units and Three-Way Rules`), merge a `label`'s complete ordered `link` list as an independent atomic merge unit alongside `scoped`, `name`, `note`, `color`, and `condition`.
* **UI / UX: Label Context Hub & Editor Integration:**
  1. **Label Editor (`EditLabelScreen`):** Reuse `TaskEditorLinksSection` inside `EditLabelScreen` so creating and editing links on a label is identical to editing links on a task.
  2. **Active Label Context Hub (`HomeTopBar` / `LabelHubDialog`):** When an active label filter is selected in `HomeScreen` (or via an info icon on a label row in `HomeDrawer` / `TaskInfoDialog`), tapping the active label header opens a compact **Label Hub Dialog / Sheet** displaying:
     * Label `name`, `color` badge, and `scoped` status indicator.
     * Full multi-line `note` (selectable text) when present.
     * Clickable `link` rows (`title` + `uri` with open-in-external-app action) when present.
     * Summary of active `condition` rules (`day`, `time`, `location`) when present.
     * Quick `Edit` action to open `EditLabelScreen` for that label.

#### 1.4.2 Open Slot for Additional 0.7.0 Ideas
*(Additional ideas for `TDF 0.7.0` will be appended here as `Topic 2`, `Topic 3`, etc. during the `concept` phase.)*

### 1.5 Alternatives Considered
1. **Introduce a Separate Root `project <project-id> { ... }` Block Type:**
   * *Rejected:* A separate `project` entity would duplicate almost every attribute already present on `label` (`name`, `color`, `note`, `scoped`, `condition`, `modified`, `deleted` records, and task assignment directives), increasing grammar surface area, synchronization complexity, and UI navigation clutter. Enhancing `label` with `link` and a Context Hub view achieves the exact goal while keeping the data model minimal and orthogonal.
2. **Embed Label Links Inside `label.note` as Raw Markdown Text:**
   * *Rejected:* Tasks already use structured `link "<title>" "<uri>"` directives with explicit `<title>` and `<uri>` validation, scheme security checks (`InvalidUri`), and dedicated clickable UI controls. Forcing label links into unstructured `note` text would lose schema validation, structured agent discoverability, and consistent UI rendering between tasks and labels.
3. **Copy Label Links Automatically onto Every Assigned Task:**
   * *Rejected:* Copying links onto tasks duplicates data in the `.tdf` file and creates ambiguity when a link is updated on the label or deleted on a single task. Keeping project/context links on the `label` block and task-specific links on the `task` block maintains clean normalization.

## Part 2: Technical Design & Code Changes

> [!NOTE]
> Part 2 outlines the preliminary technical design for Topic 1 and will be expanded as additional `0.7.0` ideas are collected and finalized for the transition to `status: planned`.

### 2.1 Architecture & Affected Modules (Preliminary for Topic 1)
* **Specification:** `spec/TDF_SPEC_0.7.0.md` (or evolution from `spec/TDF_SPEC_0.6.0.md` with load-time migration `0.6.0 -> 0.7.0`).
* **Domain Models (`lib/models/`):**
  * `lib/models/tdf_metadata.dart`: Add `final List<TaskLink> links;` (unmodifiable, defaulting to `const <TaskLink>[]`) to `TdfLabel` (or generalize `TaskLink` / `TdfLink`).
  * `lib/models/tdf_payload_comparison.dart`: Include `label.links` in `TdfLabel` payload equality and lexicographical comparison (`(scoped, name, note, color, link, condition)`).
  * `lib/models/task_board_reconciler.dart`: Merge `label.links` as an independent ordered-list merge unit during three-way `TdfLabel` reconciliation.
  * `lib/models/task_board_mutator.dart`: Support updating `links` on `TdfLabel` mutations and advancing `label.modified`.
* **Parser & Serializer (`lib/services/`):**
  * `lib/services/tdf_Block_parser.dart` / `lib/services/tdf_parser.dart`: Accept repeatable `link "<title>" "<uri>"` directives inside `label` blocks up to `maxLinksPerLabel = 20` (`MAX_LINKS_PER_LABEL` / `MAX_LINKS_PER_ENTITY`).
  * `lib/services/tdf_serializer.dart`: Emit `link` directives at canonical position 5 inside `label` blocks (after `modified` and before `condition`).
* **UI & Localization (`lib/ui/`, `lib/l10n/`):**
  * `lib/ui/edit_labels_screen.dart`: Integrate `TaskEditorLinksSection` into `EditLabelScreen`.
  * `lib/ui/widgets/home_top_bar.dart`, `lib/ui/widgets/home_drawer.dart`, and a new `lib/ui/widgets/label_hub_dialog.dart`: Provide one-tap access to the **Label Context Hub** (displaying label `note`, clickable `links`, and `condition` summary) when viewing a filtered label or inspecting a label.
  * `lib/l10n/app_en.arb` & `lib/l10n/app_de.arb`: Add English and German localization strings for the Label Context Hub.

### 2.2 TDF Schema, Localization & State Changes (Preliminary for Topic 1)
* **Canonical `label` Directive Order (`6` Positions in `0.7.0`):**
  1. `name`
  2. `color`
  3. `note`
  4. `modified`
  5. `link` (`0..20`, in declaration order)
  6. `condition`
* **Resource Bounds (`Section 7`):**
  * `MAX_LINKS_PER_LABEL = 20` (matching `MAX_LINKS_PER_TASK = 20`).

### 2.3 Implementation Details
* Maintain strict unidirectional data flow (`P-UDF-ARCHITECTURE`), repository I/O isolation (`P-IO-ISOLATION`), single-pass $O(N)$ scanning and serialization (`P-ZERO-COPY`, `P-NO-QUADRATIC`), pre-checked `maxLinksPerLabel` bounds before allocating the $(N+1)$-th link (`P-BOUND-ALLOC`), and `AppLogger` diagnostic redaction (never logging raw link titles or URIs in diagnostic logs).

### 2.4 Testing Strategy
* `M-EXHAUSTIVE-STATE-TESTS`: Parse, normalize, compare, merge, and serialize `label` blocks with `0`, `1`, and multiple `link` directives; verify load-time conversion from `0.6.0` to `0.7.0`.
* `M-EXTREME-BOUND-TESTS`: Verify `20` links accepted and `21` links rejected with `LimitExceeded` on a `label` block; verify `MAX_TEXT_LENGTH` (`500`) and `MAX_URI_LENGTH` (`2048`) boundaries on `label.link`.
* `M-DELIM-INJECT-TESTS` & `M-URI-PATH-EDGE-TESTS`: Verify rejection of `javascript:`, `vbscript:`, `data:`, missing schemes, control characters, and unquoted arguments on `label.link` with `InvalidUri`, `EmptyText`, or `UnexpectedToken`.
* Widget tests (`test/ui/`): Verify adding/removing/opening links in `EditLabelScreen` and opening the Label Context Hub dialog from `HomeTopBar` / `HomeDrawer`.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [ ] Collect and refine all candidate topics for `TDF 0.7.0` with the user (`status: concept`).
- [ ] Advance `TEP-006` to `status: planned` and run **`spec-verification-loop`** once the `0.7.0` scope is frozen.
- [ ] Update specification documents per **`tdf-spec-workflow`**.
- [ ] Write failing unit and widget tests first in `test/` (TDD Red Phase — `P-TDD-FIRST`).
- [ ] Implement production changes in `lib/` with `AppLogger` instrumentation (TDD Green & Refactor Phase).
- [ ] Run `python3 .agents/scripts/tiertask_dev.py verify --full --fix`.
- [ ] Synchronize `README.md`, `ARCHITECTURE.md`, `AGENTS.md`, and `CHANGELOG.md`.

### 3.2 Work Log & Decisions
* **2026-11-09:** Created `TEP-006` (`status: concept`) as the exploratory idea collection for `TDF 0.7.0`, starting with Topic 1 (`link` directives on `label` blocks and Labels as Project / Context Hubs).

### 3.3 Delivered Artifacts
*(Pending — proposal is in `concept` stage)*
