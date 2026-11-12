---
id: TEP-006
title: TDF Specification 0.7.0 Exploratory Design and Idea Collection
status: concept
type: spec
created: 2026-11-09
updated: 2026-11-12
---

# TEP-006: TDF Specification 0.7.0 Exploratory Design and Idea Collection

> [!NOTE]
> **Exploratory Idea Collection (`status: concept`):** This proposal serves as the living design collection for **TierTask Data Format (`TDF`) `0.7.0`**. New candidate specification features, domain refinements, and workflow ideas for `0.7.0` are collected, evaluated, and refined here before advancing to `planned` and updating the normative specification.

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal collects and evaluates four cohesive candidate enhancements for **TierTask Data Format (`TDF`) `0.7.0`**:
1. **Topic 1 — Label Links and Context Hubs:** Extends root `label <label-id> [scoped] { ... }` blocks with repeatable `link "<title>" "<uri>"` directives (`0..MAX_LINKS_PER_LABEL`) and elevates labels in the TierTask UI from passive filter tags to lightweight **Project Collections and Context Hubs** that bundle a context's tasks, description (`note`), reference URIs (`link`), visibility scope (`scoped`), and activation rules (`condition`) in one place.
2. **Topic 2 — Deadline-Driven Effective Priority (`due` Lead-Window Auto-Promotion):** Evolves `due` from purely informational metadata into an active pull signal during tier evaluation (`TaskBoardEvaluator`). Scheduled, executable tasks in `queue` whose non-`passive` `due` timestamp lies within a defined lead window (`due <= now + W_due`, defaulting normatively to `24 hours` / `86,400` seconds, including overdue tasks with `due <= now`) receive derived **effective priority** during Section 5.5 evaluation, automatically pulling time-critical tasks from `Planned` or `Ready` into `Focus` as their deadline approaches without mutating the `.tdf` file on disk. An optional `passive` modifier (`due <YYYY-MM-DD> [<HH:MM[:SS]>] [passive] ["<note>"]`) supports informational-only deadlines and deterministic manual downgrades (`Section 6.3`).
3. **Topic 3 — Automatic Block-Reason Expiry & Resolution Cleanup and Explicit Recurring Preparation Lead Offset:** Automatically removes expired finite `suspended` deferrals (`suspended <= now` in UTC, together with any attached `suspended` note) and permanently resolved `blocked` prerequisite entries on open tasks during refresh/synchronization (`syncFromRemote` / `TaskSyncPipeline.synchronize`) and ordinary domain mutations, advancing `task.modified` once per cleaned task while preserving live recurring-to-recurring `blocked` pipelines (`dependent.repeat != null && prerequisite.repeat != null`), unknown forward references, and cyclical/spatial `condition` rules (`day`, `time`, `location`). Extends `repeat` to `repeat <count> <days|weeks|months> [<repeat-time>] [lead <lead-count> days]` so schedule-anchored recurring tasks (`repeat` + `due`) maintain deterministic multi-day preparation windows even after an expired `suspended` directive has been cleaned up or temporarily snoozed.
4. **Topic 4 — Deferral and Deadline Notes (`suspended` Note & `due` Note):** Extends `suspended` (`suspended (<timestamp> | forever) ["<note>"]`) and `due` (`due <timestamp> [passive] ["<note>"]`) with an optional trailing quoted `<note>` argument (`1..MAX_NOTE_LENGTH = 2000` Unicode scalar values). Enforces strict ownership and lifecycle coupling so temporary deferral notes self-delete automatically whenever `suspended` expires and is cleaned up (for example, `suspended 2026-11-11 12:00:00 "Wait for noon callback"` removed with its note when refreshing at `2026-11-11 12:00:01`), is manually cleared, or resets on recurrence, whereas `due` notes remain attached on overdue open tasks (`due <= now`), carry forward across Mode 2 (`repeat` + `due`) recurrences, stay preserved on standard `Completed` tasks, and clear when `due` is cleared or a completed task is restored.

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

#### 1.2.2 Topic 2: Why Deadline-Driven Effective Priority (`due` Lead-Window Auto-Promotion) Is Valuable
In `TDF 0.6.0`, the `due` timestamp on `TaskItem` is purely informational and has zero effect on `TaskBoardEvaluator` (`Section 5.5`), acting only as a UI display badge and a calendar anchor for Mode 2 `repeat` calculations (`Section 6.10.3`). Treating approaching or overdue `due` timestamps as derived effective priority during tier evaluation solves four operational gaps in the pull system:

1. **Preventing Silent Deadline Misses Behind Non-Urgent Queue Entries:**
   * When `Focus` (`3` slots) and `Ready` (`5` slots) are occupied by regular non-urgent tasks, a scheduled task in `Planned` (`Tier 3`, slot `9+`) or `Ready` (`Tier 2`) with a hard deadline tomorrow — or even an already-overdue deadline — remains buried behind regular work unless the user manually audits `Planned` and promotes it.
   * Granting effective priority once `now` enters a defined lead window (`due - now <= W_due`, such as `24 hours`, including `due <= now`) pulls time-critical tasks ahead of regular non-urgent tasks into `Focus` automatically as their deadline approaches.
2. **Opportunistic Early Pull Without `Blocked` Lock-In (Why `suspended` + `priority` Is Not Equivalent):**
   * In `TDF 0.6.0`, the only way to make a future-due task jump into `Focus` on a target date is to combine `priority` with a `suspended` deferral until `due - 24h`. However, `suspended` locks the task inside `Blocked` (`Tier 4`) beforehand, hiding it from `Ready` and `Focus` even if the user finishes all other work two days early and has free capacity.
   * With `due` lead-window promotion, a queued task without `suspended` remains open and pullable in `Planned` or `Ready` ahead of time (allowing early opportunistic completion whenever active slots vacate) and automatically escalates to effective priority once the lead window opens.
3. **Zero-Churn Read-Only Derivation (`Data vs. View Separation`):**
   * Computing `hasEffectivePriority(T, now)` dynamically inside `TaskBoardEvaluator` (`Section 5.5`) respects `Section 1.1` (`Data vs. View Separation`) and `Section 6.10.1` (read-only evaluation invariance): crossing the 24-hour lead threshold requires zero `.tdf` file writes, zero synthetic `priority` flag mutations, zero `queue` rewrites, and zero WebDAV synchronization churn across devices.
4. **Preserving Pull-System Guardrails and User Agency (`Blocked`, `Someday`, WIP Caps, and `downgradeTask`):**
   * Because effective priority operates strictly inside `Section 5.5` on scheduled, currently executable tasks, it never violates the `Focus` (`3`) or `Ready` (`5`) WIP soft limits, never pulls unscheduled `Someday` tasks (`Section 5.3`) into the active queue, never overrides active `Blocked` restrictions (`suspended`, `blocked`, or `condition` in `Section 5.4`), and never leaks `scoped`-only tasks into the unfiltered global view (`Section 5.1`).
   * Supporting an optional `passive` modifier on `due` (`due <timestamp> [passive] ["<note>"]`) allows users to record soft informational dates without auto-promotion and ensures that manually downgrading (`downgradeTask`, `Section 6.3`) a deadline-promoted task steps it down cleanly behind regular tasks instead of bouncing back into `Focus`.

#### 1.2.3 Topic 3: Why Automatic Block-Reason Expiry & Resolution Cleanup and Explicit Recurring Lead Offsets Are Valuable
In `TDF 0.6.0`, transient blocking directives remain stored on tasks long after their blocking condition has permanently passed, creating four concrete defects in `.tdf` storage, UI clarity, and recurrence behavior:

1. **Eliminating Zombie `suspended` Deferrals After Expiry:**
   * Once a finite `suspended` timestamp expires (`suspended <= now` in UTC), `TDF 0.6.0` evaluates the task as unblocked in memory (`Section 5.4` & `6.10.1`) yet never removes the expired `suspended` directive — even when the user explicitly refreshes/synchronizes (`syncFromRemote`) or mutates the board.
   * As a result, an active task in `Focus` continues displaying a stale `suspended` pause indicator on `TierTaskPill`, shows `Elapsed (<timestamp>)` inside `TaskInfoDialog`, and pre-fills `EditTaskScreen` with `Suspended` enabled on a past date so editing the task title inadvertently retains a dead deferral in `.tdf`.
   * Stripping expired finite `suspended` directives (`suspended <= now`, together with any attached `suspended` note) during refresh/synchronization and committed domain mutations aligns persisted `.tdf` state with operational reality while keeping raw `TdfService.parse` / `TdfBlockParser.parseDocument` and pure `TaskBoardEvaluator.evaluate` side-effect-free.
2. **Eliminating Up-to-60-Day Stale `blocked` Prerequisite Clutter:**
   * In `TDF 0.6.0`, when a one-shot prerequisite task `A` is completed, `blocked A` remains on dependent task `B` until `A` ages out of `Completed` after 30 days AND `A`'s deletion tombstone expires after another 30 days (`60` days total); even when `A` is explicitly deleted, `blocked A` remains on `B` for 30 days, rendering a padlock indicator and raw Base62 ID in `TaskInfoDialog`.
   * Immediately removing `blocked <id>[:<req>]` entries whose target is confirmed deleted in `deleted.tasks` OR whose requirement is satisfied (`target.completions >= req`) on non-recurring-to-recurring edges (`dependent.repeat == null || target.repeat == null`) keeps `.tdf` clean while preserving both intentional forward references (`<id>` absent from live tasks and `deleted.tasks`) and recurring-to-recurring pipelines (`dependent.repeat != null && target.repeat != null`, where `dependent` needs `<id>` upon completion to rearm `<id>:<completions + 1>`).
   * Cyclical and spatial `condition` rules (`day`, `time`, `location`) represent standing environmental rules that re-block when leaving the window or geofence and therefore remain untouched when temporarily satisfied.
3. **Decoupling Recurring Preparation Windows from Transient `suspended` State (`repeat ... [lead <N> days]`):**
   * `TDF 0.6.0` Section 6.10.3 Mode 2 inferred recurring multi-day preparation windows on `repeat` + `due` tasks by comparing `oldSuspended < oldDue` at completion time. That coupling had two flaws: (a) once an expired `suspended` directive is cleaned up on refresh before the user completes the task, `oldSuspended` is absent and the preparation window would be lost on the next cycle; and (b) temporarily snoozing a monthly task once (for example, `suspended 2026-11-28`) permanently overwrote future months' preparation wake-up dates.
   * Adding an optional `lead <lead-count> days` clause on `repeat` (`repeat 1 months 09:00 lead 5 days`) stores the recurring preparation offset declaratively on `repeat`, keeps `suspended` strictly per-occurrence, and replaces `0.6.0`'s 65-line month-end clamping heuristic with deterministic subtraction (`newDueLocalDate - leadDays`).

#### 1.2.4 Topic 4: Why Dedicated Notes on Deferrals (`suspended`) and Deadlines (`due`) Are Valuable
In `TDF 0.6.0`, a task has only a single general-purpose `note` directive (`task.note`), forcing users to mix permanent task documentation with transient scheduling reasons:

1. **Self-Cleaning Snooze Context on `suspended`:**
   * Deferring a task almost always carries a concrete temporary reason (`"Waiting for vendor callback until 12:00"`, `"Colleague on vacation until Monday"`, `"Paused pending Q1 budget decision"`).
   * Recording that reason in `task.note` leaves obsolete snooze notes mixed into permanent task instructions after the deferral expires. Attaching `"<note>"` directly to `suspended` (`suspended 2026-11-11 12:00:00 "Waiting for vendor callback"`) displays the reason right inside the `Suspended` status card while active and guarantees automatic removal alongside `suspended` the moment the expired deferral is cleaned up (such as refreshing at `2026-11-11 12:00:01`).
2. **Explicit Consequence & Cutoff Context on `due`:**
   * Deadlines benefit from concise context distinct from the task body (`"Statutory VAT filing deadline — late fee after midnight"`, `"Early-bird discount expires"`).
   * Unlike `suspended` (which is a temporary block that expires), `due` represents a target deadline: when `due <= now`, the task is overdue rather than resolved, so `due` and its `due` note remain visible on overdue open tasks and carry forward across schedule-anchored recurring occurrences (`repeat` + `due`).

### 1.3 Goals & Non-Goals
* **Goals (`0.7.0` Idea Collection):**
  * Collect and evaluate candidate features for `TDF 0.7.0` in a structured, incremental specification proposal.
  * **Topic 1 (`label.link` & Label Context Hub):**
    * Permit `0..MAX_LINKS_PER_LABEL` (`20`) repeatable `link "<title>" "<uri>"` directives inside `label` blocks using the exact lexical, character-length (`MAX_TEXT_LENGTH = 500`, `MAX_URI_LENGTH = 2048`), and scheme-validation rules (`InvalidUri` on missing scheme or `javascript:`, `vbscript:`, `data:`) defined for `task.link`.
    * Define canonical serialization order inside `label` blocks (`1. name`, `2. color`, `3. note`, `4. modified`, `5. link`, `6. condition`).
    * Define normalization, payload comparison, and three-way baseline merge rules for `label.link` (merging the ordered `link` list on a `label` as one atomic merge unit, matching `task.link`).
    * Design a **Label Context Hub** UI flow (in `EditLabelScreen`, `HomeTopBar` when a label filter is active, `HomeDrawer`, and `TaskInfoDialog`) so users can view a label's `note` and launch its `link` URIs directly.
  * **Topic 2 (`due` Lead-Window Effective Priority & Pull Promotion):**
    * Define derived effective priority in `Section 5.5` (`TaskBoardEvaluator`): an eligible scheduled task in `queue` has effective priority at UTC instant `now` when `isPriority` is `true` OR when it carries a non-`passive` `due` timestamp within the lead window (`due <= now + W_due`, with normative specification default `DEFAULT_DUE_LEAD_SECONDS = 86400` / `24 hours`, including overdue tasks where `due <= now`).
    * Preserve relative `queue` order within both partitions of `Section 5.5 Step 2` (`effectivePriority` tasks in `queue` order followed by regular tasks in `queue` order) so manual drag/reorder via `moveTaskInQueue` remains deterministic across both `priority`-flagged and deadline-promoted tasks.
    * Extend the `due` directive syntax with optional `passive` (`due <YYYY-MM-DD> [<HH:MM[:SS]>] [passive] ["<note>"]`) so soft informational deadlines can opt out of auto-promotion and explicit `downgradeTask` mutations (`Section 6.3`) can demote deadline-promoted tasks below regular tasks without clearing `due` or `dueNote`.
    * Provide a workspace-scoped lead-window preference (`Off`, `At deadline (0h)`, `12h`, `24h` default, `48h`, `7d`) in `WebDavConfig` / `SettingsScreen`, live clock/resume re-evaluation in `HomeScreen`, and visual lead-window / overdue urgency indicators on `TierTaskPill` and `TaskInfoDialog`.
  * **Topic 3 (Automatic Block-Reason Expiry & Resolution Cleanup + `repeat ... [lead <N> days]`):**
    * Remove expired finite `suspended` directives (`suspended <= now` in UTC, together with `suspendedNote`) and resolved `blocked` prerequisite entries (`target` in `deleted.tasks`, or live `target.completions >= req` when `dependent.repeat == null || target.repeat == null`) from open tasks during refresh/synchronization (`TaskBoardSync.merge` + `TaskBoardSync.stampAndNormalize`) and committed domain mutations, advancing `task.modified` once per cleaned task while keeping raw parsing (`TdfService.parse` / `TdfBlockParser.parseDocument`) and read-only evaluation (`TaskBoardEvaluator.evaluate`) pure.
    * Pre-normalize expired finite `suspended <= now` to `absent` across `B`, `L`, and `R` during `Section 6.7.5` same-occurrence reconciliation (and normalize automatic block-reason cleanup when comparing tasks against `B` in `Sections 6.8.2 & 6.8.4`) so an offline expiry cleanup never overwrites a concurrent offline deferral extension, never triggers false `DeletionConflict` or `RecoveryRequired` outcomes, and remains idempotent across repeated syncs.
    * Extend `repeat` to `repeat <count> <days|weeks|months> [<repeat-time>] [lead <lead-count> days]` (`1..3650` days) so Mode 2 (`repeat` + `due`) recurring preparation windows survive expired `suspended` cleanup and temporary snoozes.
    * Preserve full undo reversibility in `TaskBoardUndo` (`TEP-007`) by snapshotting stripped `TdfTaskDependency` entries in `previouslyBlockedDependencies` alongside `suspendedNote`, `dueNote`, and `isDuePassive` when undoing `complete`, `delete`, or `downgrade` actions.
  * **Topic 4 (`suspended` Note & `due` Note):**
    * Permit an optional trailing quoted `<note>` argument (`1..MAX_NOTE_LENGTH = 2000` Unicode scalar values) on `suspended` and `due` directives with strict LL(1) bare-word vs. quoted-string disambiguation and version-gated `< 0.7.0` validation.
    * Enforce ownership invariants (`suspendedNote == null` whenever `suspended` is absent; `dueNote == null` whenever `due` is absent), atomic merge coupling (`(isForever, suspendedAt, suspendedNote)` and `(dueAt, isDuePassive, dueNote)`), `AppLogger` text redaction, and lifecycle transitions across expiry, overdue retention, completion, recurrence, restoration, and manual clearing.
    * Expose `suspendedNote` and `dueNote` inputs in `TaskEditorSchedulingCard` / `EditTaskScreen` and render them in `TaskInfoDialog` while hiding expired `suspended` and satisfied `blocked` pill indicators immediately.
* **Non-Goals (Current Stage):**
  * Introducing separate `project` or `config` root block types in `.tdf`.
  * Modifying `lib/` or `spec/TDF_SPEC_0.6.0.md` while `TEP-006` remains in `status: concept`.
  * Altering 6-tier derivation (`Section 5`) or condition evaluation (`Section 4.4`) based on `label.link`, `suspendedNote`, or `dueNote` text.
  * Removing cyclical/spatial `condition` rules (`day`, `time`, `location`) when temporarily satisfied, removing live recurring-to-recurring `blocked` dependencies before the dependent recurring task completes, or auto-removing overdue `due` deadlines (`due <= now`).
  * Allowing `due` to bypass `Blocked` restrictions (`Section 5.4`), pull unscheduled `Someday` tasks without `queue` membership (`Section 5.3`), bypass `scoped` global-view exclusion (`Section 5.1`), or exceed the `Focus` (`3`) and `Ready` (`5`) WIP slot limits (`Section 5.5`).

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
* **Validation & Compatibility Rules:**
  * Identical to `task.link` (`Sections 2.8, 4.1.2, 4.2, 7, 8 & 10.1`):
    * Standalone `link` with `0` arguments fails with `MissingDirectiveArgument` (`UnknownBlockType` if `{` follows). In `tdf 0.7.0`, `link` inside a `label` block requires `2` quoted string arguments (`"<title>"` and `"<uri>"`, accepting `"..."` or `'...'` in input and emitting double-quoted `"..."` canonically; `UnexpectedToken` if `1` or `>= 3` arguments or if either argument is unquoted).
    * `<title>`: Single-line `<text>` (`1..MAX_TEXT_LENGTH = 500` decoded Unicode scalar values; `EmptyText` if empty or ASCII whitespace only; `UnexpectedToken` if decoded `\n`, `\r`, or `\t` is present; `LimitExceeded` if `> 500`).
    * `<uri>`: Single-line `<uri>` (`1..MAX_URI_LENGTH = 2048` decoded Unicode scalar values; `EmptyText` if empty or ASCII whitespace only; `InvalidUri` if decoded control characters exist, if the scheme prefix `[a-zA-Z][a-zA-Z0-9+.-]*:` is missing, or if the scheme is `javascript:`, `vbscript:`, or `data:` matched case-insensitively; `LimitExceeded` if `> 2048`).
    * Multiplicity: `0..MAX_LINKS_PER_LABEL` (`20`) per `label` block in preserved declaration order (`LimitExceeded` on the 21st `link` directive in a `label` block).
    * Historical version gate & load-time conversion: Documents declaring `< 0.7.0` (`0.5.0`, `0.5.1`, `0.6.0`) reject `link` with `>= 1` arguments inside a `label` block with `UnknownDirective` (`MissingDirectiveArgument` on `0` arguments; `UnknownBlockType` if `{` follows). Zero-mutation read-only load-time conversion (`0.5.0 -> 0.5.1 -> 0.6.0 -> 0.7.0`) initializes `label.links = []`.
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

#### 1.4.2 Topic 2: Deadline-Driven Effective Priority (`due` Lead-Window Auto-Promotion)
* **TDF Grammar & Schema (`due` Directive in `task`, Harmonized with Topic 4):**
  ```text
  task 8jKaCdOkD2 {
      name     "Submit VAT declaration"
      created  2026-11-01 09:00:00
      modified 2026-11-01 09:00:00
      due      2026-11-11 17:00:00 "Statutory filing cutoff"
  }

  task 4mNpQr9xYz {
      name     "Redeem hardware voucher before expiry"
      created  2026-11-02 10:00:00
      modified 2026-11-10 14:30:00
      due      2026-11-11 23:59:00 passive "Optional store credit"
  }
  ```
* **Validation & Canonical Serialization Rules (`Section 4.1.2` & `Section 7`):**
  * Syntax: `due <YYYY-MM-DD> [<HH:MM[:SS]>] [passive] ["<note>"]` (`0..1` per `task` block at canonical position `11`, between `suspended` at `10` and `origin` at `12`).
  * `<YYYY-MM-DD> [<HH:MM[:SS]>]`: Unchanged UTC `<timestamp>` rules (`InvalidTimestamp` on malformed or out-of-range dates/times; no ordering constraint against `suspended`).
  * `passive` (**Optional**, Unquoted Bare Word Modifier):
    * **When omitted (`isDuePassive = false`):** `due` participates in lead-window effective priority during Section 5.5 evaluation.
    * **When present (`isDuePassive = true`):** `due` remains informational and anchors Mode 2 `repeat` schedules (`Section 6.10.3`), without granting derived effective priority in Section 5.5. Accepts both date-only (`due 2026-11-11 passive ["<note>"]`, midnight UTC) and explicit-time (`due 2026-11-11 23:59:00 passive ["<note>"]`) input forms.
    * Exact token disambiguation and error mapping across `<timestamp>`, `passive`, and `"<note>"` are defined in Section 1.4.4.
  * Canonical serializer output emits `due YYYY-MM-DD HH:MM:SS`, `due YYYY-MM-DD HH:MM:SS "<escaped-note>"`, `due YYYY-MM-DD HH:MM:SS passive`, or `due YYYY-MM-DD HH:MM:SS passive "<escaped-note>"`.
  * Zero-mutation read-only load-time conversion (`0.5.0 -> 0.5.1 -> 0.6.0 -> 0.7.0`) initializes `isDuePassive = false` and `dueNote = null` for all existing `due` directives without mutating storage.
* **Dynamic Tier Evaluation Rules (`Section 5` & `TaskBoardEvaluator`):**
  1. **Strict Tier Boundaries (`Sections 5.1–5.4` Preserved):**
     * **Global Scope (`Section 5.1`):** Tasks restricted to `scoped` labels remain excluded from the unfiltered global view even when within the `due` lead window or overdue; they gain effective priority inside their filtered `activeLabelId` view.
     * **`Completed` (`Section 5.2`) & `Someday` (`Section 5.3`):** Tasks with `finished` stay in `Completed`. Open tasks omitted from `queue` (without an active `suspended` lock) stay in `Someday` regardless of `due`.
     * **`Blocked` (`Section 5.4`):** Active deferrals (`suspended > now` or `suspended forever`), unsatisfied `blocked` prerequisites, and unsatisfied `condition` groups (`day`, `time`, `location`) always take precedence in `Section 5.4`. For example, an overdue task manually deferred via `suspended` until tomorrow morning stays in `Blocked` today and pulls into `Focus` with effective priority once `suspended <= now`.
  2. **Derived Effective Priority Predicate (`Section 5.5 Step 2`):**
     * Let `now` be the UTC evaluation instant and $W_{\text{due}}$ be the active nullable lead-window duration (`DEFAULT_DUE_LEAD_SECONDS = 86400` / `24 hours` by normative specification default; `null` when client lead-window promotion is configured to `Off`):
       $$\text{isDueUrgent}(T, \text{now}, W_{\text{due}}) \iff W_{\text{due}} \neq \text{null} \;\land\; T.\text{due} \neq \text{null} \;\land\; \neg T.\text{isDuePassive} \;\land\; T.\text{due} \le \text{now} + W_{\text{due}}$$
       $$\text{hasEffectivePriority}(T, \text{now}, W_{\text{due}}) \iff T.\text{isPriority} \;\lor\; \text{isDueUrgent}(T, \text{now}, W_{\text{due}})$$
     * **Inclusive Boundary & Overdue Continuity:** At exact threshold equality (`T.due - now == W_due`, matching `suspended <= now` in `Section 6.10.1`), `isDueUrgent` evaluates to `true`. Overdue tasks (`T.due <= now`) satisfy `T.due <= now + W_due` for every $W_{\text{due}} \ge 0$ (including `W_due = 0` seconds for at-deadline-only promotion).
  3. **Stable Two-Bucket `queue` Partition & WIP Slicing (`Section 5.5 Steps 2–3`):**
     * Partition eligible executable tasks from `queue` stably into two ordered groups:
       1. All eligible tasks with `hasEffectivePriority(T, now, W_due) == true` in their saved relative `queue` order.
       2. All remaining eligible tasks (`hasEffectivePriority(T, now, W_due) == false`) in their saved relative `queue` order.
     * Slice positions `1..3` into `Focus` (`Tier 1`), positions `4..8` into `Ready` (`Tier 2`), and positions `9..N` into `Planned` (`Tier 3`). If more than `3` eligible tasks have effective priority, the first `3` in `queue` order occupy `Focus`, the next `5` occupy `Ready`, and any remainder wait at the top of `Planned`, pulling forward automatically as `Focus` tasks complete.
     * Read-only evaluation NEVER writes `priority` or `passive` to the task or alters `task.modified` or `queue.modified`.
* **State Transitions, Manual Downgrade, Recurrence & Merge Rules (`Section 6`):**
  1. **Context-Relative Downgrade (`Section 6.3` — Preventing Silent Bounce-Back):**
     * Let $E_{\text{ctx}}$ be the Section 5.5 Step 2 ordered sequence of other eligible tasks (`[...focus, ...ready, ...planned]` excluding $T$) in the active filter context:
       * **From `Focus` to `Ready`:**
         * When $|E_{\text{ctx}}| \ge 7$ and the 7th task in $E_{\text{ctx}}$ (the slot-8 anchor) has `hasEffectivePriority == true`: preserve `T.isDuePassive` and `T.dueNote` unchanged, keep `T.isPriority` unchanged if `isDueUrgent(T, now, W_due)` is already `true` (so an explicit `priority` flag is never lost when `due` is also urgent, leaving `task.modified` unchanged) or set `T.isPriority = true` when `isDueUrgent(T, now, W_due)` is `false` (advancing `task.modified` only if `T.isPriority` changed from `false` to `true`), and move $T$ in `queue` immediately after the 7th task in $E_{\text{ctx}}$ (advancing `queue.modified` only if `queue` order changed) so $T$ occupies slot 8 (`Ready`).
         * When $|E_{\text{ctx}}| < 7$ or the 7th task in $E_{\text{ctx}}$ has `hasEffectivePriority == false`: strip `T.isPriority` if present AND set `T.isDuePassive = true` (preserving `dueNote`) when `isDueUrgent(T, now, W_due)` is `true` (advancing `task.modified` when either attribute changes), moving $T$ after the 7th task, after the last task in $E_{\text{ctx}}$ when $1 \le |E_{\text{ctx}}| < 7$, or keeping $T$'s `queue` position unchanged when $|E_{\text{ctx}}| = 0$ (preserving the strict no-op rule when neither task attributes nor `queue` order changed). Setting `passive` prevents $T$ from immediately jumping back ahead of regular tasks into `Focus` upon re-evaluation.
       * **From `Ready` to `Planned`:** Strip `T.isPriority` if present, set `T.isDuePassive = true` (preserving `dueNote`) when `isDueUrgent(T, now, W_due)` is `true` (advancing `task.modified` only when a task attribute changed), and move $T$ to the end of `queue` (advancing `queue.modified` only if its `queue` position changed).
       * **From `Planned` to `Someday` (`Section 6.2` & `6.3`):** Remove $T$ from `queue` (advancing `queue.modified`), strip `T.isPriority`, `suspended`, and `suspendedNote` if present, and preserve `(dueAt, isDuePassive, dueNote)`.
  2. **Automatic Reset of `passive` on Explicit Re-Prioritization, Deadline Edits, Restoration, and Recurrence (`Sections 6.4, 6.5, 6.6 & 6.10.3`):**
     * Explicitly promoting a task to `Focus` (`isPriority = true`), changing `due` to a different timestamp (unless `passive` is explicitly requested in the same edit), restoring a completed task (`Section 6.5`, which clears `due` and `dueNote`), or completing a Mode 2 recurring task (`repeat` + `due` advancing `due` to `newDue > now` while preserving `dueNote` alongside `Section 6.4` Step 3 `priority` wake-up) resets `isDuePassive = false` so future deadlines auto-promote normally.
  3. **Normalized Payload & Three-Way Baseline Merge (`Section 6.7`):**
     * Extend the `due` component in normalized task payloads (`Section 6.7.3`) and same-occurrence three-way reconciliation (`Section 6.7.5`) to the atomic 3-tuple `(dueAt, isDuePassive, dueNote)`.
* **UI, Workspace Settings & Live Re-Evaluation:**
  1. **Workspace Preference (`WebDavConfig` & `SettingsScreen`):** Add a `DueLeadWindow` enum (`off`, `atDue` = `0h`, `hours12` = `12h`, `hours24` = `24h` default, `hours48` = `48h`, `days7` = `168h`) persisted per workspace in `AppWorkspace` / `WebDavConfig`.
  2. **Task Editor (`EditTaskScreen`):** Display an inline toggle (`Auto-prioritize near deadline`, inverted to `isDuePassive`) whenever a `due` timestamp is configured on a task.
  3. **Urgency Indicators (`TierTaskPill` & `TaskInfoDialog`):** Highlight `due_task_badge_<id>` on open tasks with a warning/accent color when `isDueUrgent` (`due <= now + W_due`) and `colorScheme.error` when overdue (`due <= now`), and display the active lead-window auto-priority status and optional `dueNote` inside `TaskInfoDialog`.
  4. **Time-Boundary & Resume Re-Evaluation (`HomeScreen` & Providers):** Update `_LandingContentSwitcher._evaluateBoard` in `lib/ui/home_screen.dart` to evaluate `board.evaluateForContext(...)` with `evaluationTime` and `configuration.dueLeadWindow.duration` even when `activeLabel == null && !hasCoordinates`, and trigger clock re-evaluation on app lifecycle `resumed` and next upcoming `suspended` / `due - W_due` threshold boundary so tasks unblock or pull into `Focus` live without manual reload.

#### 1.4.3 Topic 3: Automatic Block-Reason Expiry & Resolution Cleanup and Explicit Recurring Preparation Lead Offset
* **Block-Reason Resolution Rules Across All Section 5.4 Restrictions:**
  1. **Finite Deferral (`suspended <YYYY-MM-DD> [<HH:MM[:SS]>] ["<note>"]`):**
     * Active strictly while `suspended > now` in UTC (`Section 6.10.1`); expired once `suspended <= now` in UTC (for example, `suspended 2026-11-11 12:00:00 "Wait for noon callback"` is active at `11:59:59` and expired from `12:00:00` onward, including at `12:00:01`).
     * **Read-Only Parse & View Purity:** Raw parsing (`TdfService.parse` / `TdfBlockParser.parseDocument`) preserves stored `suspended` and `suspendedNote` verbatim so `sourceDigest` (`Section 6.7.2`) and baseline decoding remain exact. Pure view evaluation (`TaskBoardEvaluator.evaluate`) treats `suspended <= now` as non-blocking immediately without mutating storage, and UI components (`TierTaskPill`, `TaskInfoDialog`, `EditTaskScreen` initial state) treat finite `suspended <= now` as inactive immediately.
     * **Refresh / Synchronization & Committed Mutation Cleanup:** During any guarded refresh/synchronization (`syncFromRemote`, initial workspace load sync, `TaskBoardSync.merge`, `TaskBoardSync.stampAndNormalize`) or any committed domain mutation (`TaskBoardMutator`, `TaskBoardQueueMutator`) evaluated at UTC instant `now`, strip `suspended` AND `suspendedNote` from every open task (`finished` omitted) whose finite `suspended <= now`, advancing `task.modified = max(now, task.effectiveModifiedAt + 1 second)` once per cleaned task (failing with `InvalidTimestamp` if `effectiveModifiedAt + 1 second` exceeds `9999-12-31 23:59:59`). Pure no-op mutation calls (early-return guard clauses where the requested operation itself makes zero task, label, location, or `queue` changes, such as `downgradeTask` with $|E_{\text{ctx}}| = 0$ and no attribute changes, missing target ID, or rejected input validation) return the board unchanged without running board-wide block-reason cleanup. If an unqueued open task carried an expired `suspended` lock, stripping `suspended` leaves it outside `queue` (`Someday`); queued tasks retain their exact `queue` position (`queue.modified` unchanged).
  2. **Indefinite Deferral (`suspended forever ["<note>"]`):**
     * Never expires by wall-clock time. Stripped (together with `suspendedNote`) only on explicit `clearSuspendedAt`, move/downgrade to `Someday` (`Sections 6.2 & 6.3`), standard non-recurring completion (`Section 6.4`), or restoration from `Completed` (`Section 6.5`).
  3. **Prerequisite Completion Lock (`blocked <target-id>[:<req>]`):**
     * Evaluated against the current document snapshot (`liveTasksById` and `deleted.tasks`):
       * **Confirmed Deleted Target (`<target-id>` in `deleted.tasks`):** Permanently resolved; strip `<target-id>[:<req>]` immediately from every open task during `deleteTask`, ordinary mutations, and refresh/synchronization (omitting `blocked` when empty and advancing `task.modified` once). Retain Section 6.8.3 30-day tombstone-expiry stripping on `Completed` tasks (or legacy uncleaned tasks) so zero dangling references survive tombstone retirement.
       * **Satisfied One-Shot or Standard Prerequisite (`<target-id>` in `liveTasksById`, `target.completions >= req`, AND `(dependent.repeat == null || target.repeat == null)`):** Permanently fulfilled because either the dependent task will never cycle again or the non-recurring prerequisite has finished and would remain permanently satisfied across recurrences (`Section 6.9.3`); strip `<target-id>[:<req>]` immediately from the open dependent task during `completeTask`, ordinary mutations, and refresh/synchronization (advancing `dependent.modified` once).
       * **Live Recurring-to-Recurring Pipeline (`<target-id>` in `liveTasksById`, `target.completions >= req`, AND `dependent.repeat != null && target.repeat != null`):** Preserve `<target-id>[:<req>]` on `dependent` until `dependent` completes its current occurrence so `Section 6.9.3` rearms `<target-id>:<target.completions + 1>` for the next cycle; during the current occurrence, `target.completions >= req` evaluates as non-blocking in `Section 5.4` and hides the blocking padlock badge on `TierTaskPill`.
       * **Unknown Forward Reference (`<target-id>` absent from both `liveTasksById` and `deleted.tasks`):** Preserve untouched and non-blocking (`Sections 4.1.2 & 6.9.2`).
       * **Standard Task Completion (`Section 6.4`, `repeat` Omitted):** Completing a non-recurring task also clears any remaining `suspended`, `suspendedNote`, and `blocked` directives on that completed task in the same atomic mutation.
  4. **Activation Conditions (`condition` — `day`, `time`, `location`):**
     * Represent standing cyclical or spatial rules (`Section 4.4`) that re-block when leaving the time window or geofence; never removed when satisfied (`deleted` `<location-id>` tokens continue cascading immediately under `Section 6.7.8`).
* **Explicit Recurring Preparation Lead Offset (`repeat` Directive at Position `7`):**
  * **TDF Grammar & Canonical Serialization (`Section 4.1.2` & `Section 6.10.3`):**
    ```text
    repeat 1 months 09:00 lead 5 days
    repeat 2 weeks lead 3 days
    ```
    * Syntax: `repeat <count> <days|weeks|months> [<repeat-time>] [lead <lead-count> days]`.
    * `0` tokens (`repeat` without arguments) fails with `MissingDirectiveArgument` (`UnknownBlockType` if `{` follows); `1` token (`repeat 1`) fails with `UnexpectedToken`.
    * `<count>` (`1..MAX_REPEAT_COUNT = 3650`) and `<unit>` (`days|weeks|months`) keep `0.6.0` error mappings: `<count>` fails with `InvalidNumber` if quoted, non-integer, signed, leading-zero, or `0`, and fails with `LimitExceeded` if raw ASCII length `> MAX_NUMBER_LENGTH` (`24`) or value `> 3650`; `<unit>` fails with `UnexpectedToken` if quoted or not `days`, `weeks`, or `months`.
    * Optional `<repeat-time>`: When a 3rd token is present and is not unquoted bare word `lead`, validate it as `<HH:MM[:SS]>` (`InvalidTime` if quoted or outside `00:00:00..23:59:59`).
    * Optional `lead <lead-count> days` (`tdf 0.7.0` only; `< 0.7.0` documents reject `repeat 1 months lead` at token 3 with `InvalidTime` and reject `>= 4` tokens such as `repeat 1 months lead 5 days` or `repeat 1 months 09:00 lead 5 days` with `UnexpectedToken`):
      * After `<unit>` (or `<repeat-time>`), any remaining token MUST begin with unquoted bare word `lead` (`UnexpectedToken` otherwise).
      * `lead` requires two following tokens (`UnexpectedToken` if fewer tokens follow `lead` or if additional tokens follow `days`): `<lead-count>` (unquoted canonical positive integer in `1..MAX_REPEAT_COUNT = 3650`; `InvalidNumber` if quoted, non-integer, signed, leading-zero, or `0`; `LimitExceeded` if raw ASCII length `> MAX_NUMBER_LENGTH` (`24`) or value `> 3650`) and unquoted bare word `days` (`UnexpectedToken` if quoted or any other unit).
    * Canonical output omits midnight `00:00:00` `<repeat-time>` and omits `lead` when `leadDays == 0`, emitting `repeat <count> <unit> [<HH:MM[:SS]>] [lead <lead-count> days]`.
    * Syntactically valid on any `repeat` directive regardless of whether `due` is currently present, guaranteeing closure under independent `due` and `repeat` unit merges in `Section 6.7.5 Case 2` (when `due` is omitted, Mode 1 ignores `leadDays`).
  * **Mode 2 Schedule-Anchored Recurrence (`Section 6.10.3` Simplified & Hardened):**
    1. Advance `oldDue` along its fixed local calendar schedule by the smallest integer multiple $k \ge 1$ of `<count> <unit>` (with month-end clamping on `oldDue`'s day) until resolved `newDue > now` with target local calendar date $(Y'_d, M'_d, D'_d)$ and local wall clock $(h_d, m_d, s_d)$.
    2. Compute `targetSuspendedLocalDate` by subtracting `leadDays` (`0` when `lead` is omitted) calendar days from $(Y'_d, M'_d, D'_d)$ (`InvalidTimestamp` if outside `0001-01-01..9999-12-31`).
    3. Combine `targetSuspendedLocalDate` with `repeat`'s normalized local clock `<repeat-time>` (`00:00:00` when omitted), resolve to UTC via `Section 6.10.2` to obtain `candidateSuspended`, and set `newSuspended = min(candidateSuspended, newDue)`.
    4. Set `due = newDue`, `isDuePassive = false`, preserve `dueNote` unchanged, set `suspended = newSuspended` (or omit `suspended` immediately when `newSuspended <= now`), and clear `suspendedNote = null`.
    * Note on immediate preparation-window opening (`newSuspended <= now`): When the previous occurrence is completed after the next occurrence's preparation window has already opened (`newSuspended <= now < newDue`), omitting `suspended` directly at completion avoids writing an already-expired `suspended` timestamp that the next refresh would strip anyway.
  * **Load-Time Conversion & Explicit Migration (`0.6.0 -> 0.7.0`, `Sections 4.0 & 10.1`):**
    * Normal loading in `TDF 0.7.0` accepts `tdf 0.7.0` natively and chains zero-mutation read-only load-time conversion across `0.5.0 -> 0.5.1 -> 0.6.0 -> 0.7.0` (rejecting `0.2.0`, `0.3.0`, `0.4.0`, and unknown versions with `UnsupportedVersion`), initializing `leadDays = 0` on `TaskRepeatRule`.
    * Explicit `TdfImporter` migration (`0.6.0 -> 0.7.0` at the end of `0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0 -> 0.5.1 -> 0.6.0 -> 0.7.0`):
      1. Remains deterministic and wall-clock-free per `Section 10.1`: `migrate060To070` never strips `suspended` by wall-clock time, and strips only `blocked` entries on open tasks that are already confirmed deleted in `deleted.tasks` or satisfied (`target.completions >= req` with `dependent.repeat == null || target.repeat == null`) in the source document (expired `suspended <= now` is cleaned up upon workspace sync or mutation).
      2. If any open task (`finished` omitted) in the `0.6.0` input carries `repeat`, `due`, and a finite `suspended < due`, `migrate060To070` requires an available `sourceTimeZone` (throwing `TdfContextException` with `ImportContextRequired` when `sourceTimeZone` is omitted or unavailable so recurring preparation offsets and wake-up clocks are never silently lost).
      3. Using `sourceTimeZone`, convert `suspended` and `due` to local calendar dates and clocks: let $D = (\text{dueLocalDate} - \text{suspendedLocalDate})$ in calendar days; if $D \ge 1$, set `leadDays = min(D, 3650)`, and for $D \ge 0$ (including same-day $D = 0$ with `suspended < due`), if `<repeat-time>` was `00:00:00` while `suspended` had a non-midnight local clock, copy `suspended`'s local clock into `<repeat-time>` so existing `0.6.0` recurring preparation windows and wake-up clocks survive subsequent `suspended` expiry cleanup.
* **Commutative Three-Way Merge Pre-Normalization, Conflict Hygiene & Idempotent Revisions (`Sections 6.7.3–6.7.8, 6.8.2 & 6.8.4`):**
  1. **Deferral Expiry Pre-Normalization (`Section 6.7.5 Case 2`):** Raw payloads (`Sections 6.7.3 & 6.7.4`) remain un-normalized when selecting complete entity winners `W` and Case 1 cross-occurrence winners (`Section 6.9.5`). Inside `Section 6.7.5 Case 2` (`B.completions == L.completions == R.completions` and `finished` omitted in all three), before comparing `(B.suspended, L.suspended, R.suspended)` at UTC evaluation instant `now`, normalize any variant $V \in \{B, L, R\}$ whose `V.suspended` is a finite UTC timestamp with `V.suspended <= now` to `absent`.
     * If `B` had `suspended 2026-11-11 12:00`, `L` refreshed offline at `12:00:01` (`L.suspended = absent`, `L.modified = 12:00:01`), and `R` postponed the task offline at `11:30:00` to `2026-11-12 09:00` (`R.modified = 11:30:00`), pre-normalization at `12:05:00` yields `(B', L', R') = (absent, absent, 2026-11-12 09:00)`, so `L' == B'` and `R`'s explicit future deferral wins commutatively regardless of modification timestamps.
     * Conversely, if `R` edited `task.note` at `12:02:00` without touching `suspended`, `R'` also normalizes to `absent` (`L' == R' == absent`), preventing `R` from resurrecting the expired deferral.
  2. **Deletion-Conflict & Generation-Recovery Baseline Comparison Hygiene (`Sections 6.8.2 & 6.8.4`):** When testing whether a live open task $T_X$ ($X \in \{L, R\}$) changed relative to its proven baseline $T_B$ while the opposing side deleted $T$ (`Section 6.8.2` `DeletionConflict` classification, or `Section 6.8.4` Step 3 vs. Step 4 `RecoveryRequired` classification after generation advancement), compare $T_X$ and $T_B$ after normalizing both open snapshots at `now` by stripping finite `suspended <= now` (with `suspendedNote`) and stripping `blocked` entries resolved by non-conflicting tombstones in the combined `deleted.tasks` set or by surviving live prerequisites (`target.completions >= req` under `T.repeat == null || target.repeat == null`). Consequently, an automatic block-reason cleanup on one device never causes a false `DeletionConflict` or `RecoveryRequired` against an opposing deletion, whereas any user edit to non-cleaned fields still triggers conflict protection.
  3. **Post-Merge Block Cleanup & Idempotent Revision Selection (`Sections 6.7.6 & 6.7.8`):**
     * Let $M_{\text{uncleaned}}$ be the merged task payload produced without `Case 2` `suspended <= now` pre-normalization after `Section 6.7.5` entity reconciliation and `Section 6.7.8` `label`/`location` deletion cascades, and let $M_{\text{clean}}$ be the final post-cleanup payload obtained by applying `Case 2` `suspended <= now` pre-normalization and stripping any remaining finite `suspended <= now` (with `suspendedNote`) and resolved `blocked` entries (`target` non-conflictingly tombstoned in merged `deleted.tasks`, or live `target.completions >= req` with `dependent.repeat == null || target.repeat == null`) on surviving open tasks.
     * Let $\mathcal{I} = \{B, L, R\}$ when `B` is present, or $\{L, R\}$ when `B` is absent, and let $G = \max_{\text{6.7.4}}(\mathcal{I})$ be the greatest raw input version:
       1. If $G$'s raw (un-normalized) payload already equals $M_{\text{clean}}$ (or when `B` is absent and winner $W$'s raw payload equals $M_{\text{clean}}$), preserve that existing `modified` timestamp unchanged (`Section 6.7.6` idempotence).
       2. Otherwise, if $M_{\text{clean}}$ equals $M_{\text{uncleaned}}$ (neither `Case 2` pre-normalization nor post-merge block cleanup stripped any expired `suspended` or resolved `blocked` entry), assign the deterministic clock-free `Section 6.7.6` merge revision $\max_{X \in \mathcal{I}}(X.\text{effectiveModifiedAt}) + 1\text{ second}$.
       3. Otherwise (block-reason cleanup at `now` stripped an expired `suspended <= now` or resolved `blocked` entry relative to $M_{\text{uncleaned}}$), assign $\text{modified} = \max(\text{now},\; \max_{X \in \mathcal{I}}(X.\text{effectiveModifiedAt}) + 1\text{ second})$ (failing with `InvalidTimestamp` if the result exceeds `9999-12-31 23:59:59`). When serialized output matches the stored snapshot on disk/WebDAV, skip write-back (`skipWriteIfUnchanged`).
* **Undo Reversibility (`TEP-007` `TaskBoardUndo`):**
  * Extend `TaskUndoEntry` with `previouslyBlockedDependencies` (`Map<String, TdfTaskDependency>`), captured on `TaskUndoActionKind.complete` and `TaskUndoActionKind.delete` strictly for open dependents whose `TdfTaskDependency` targeting the completed or deleted task was actually stripped by that mutation (leaving higher unsatisfied thresholds such as `A:5` untouched when `A` advances `2 -> 3`).
  * When reversing `complete` or `delete`, re-insert each captured `TdfTaskDependency` verbatim on surviving open dependents that do not already reference that target (guarded by `dependencies.length < MAX_ARGS_PER_STMT = 64`, cycle validation, and advancing `dependent.modified` when mutated), and restore `snapshotTask.suspendedNote`, `snapshotTask.dueNote`, and `snapshotTask.isDuePassive` on the restored task snapshot.

#### 1.4.4 Topic 4: Deferral and Deadline Notes (`suspended` Note & `due` Note)
* **TDF Grammar & Canonical Serialization (`Section 4.1.2` Positions `10` & `11`):**
  ```text
  task 2pQr8vLmN4 {
      name      "Call supplier about shipment"
      created   2026-11-10 08:30:00
      modified  2026-11-10 08:30:00
      suspended 2026-11-11 12:00:00 "Dispatcher back at desk at noon"
      due       2026-11-12 16:00:00 "Carrier pickup cutoff"
  }

  task 7xYz1kBcD9 {
      name      "Evaluate secondary NAS hardware"
      created   2026-11-05 11:00:00
      modified  2026-11-09 19:15:00
      suspended forever "Paused until Q1 storage budget review"
  }
  ```
* **Lexical, Length & Token-Disambiguation Rules (`Sections 2.7, 2.8, 4.1.2, 7 & 8`):**
  1. **Note Argument Type (`"<note>"`):**
     * Optional final argument on `suspended` and `due`; MUST be a quoted string token (`"..."` or `'...'` in input; canonically serialized as double-quoted `"..."` on a single physical `.tdf` line with `\"`, `\\`, `\n`, `\r`, `\t` escapes; physical `CRLF` normalizes line endings only outside quoted strings, whereas raw `\r` or `\n` inside an unclosed quoted string fails with `UnterminatedString`).
     * Decoded value is validated and compared verbatim as `<note>` (`1..MAX_NOTE_LENGTH = 2000` decoded Unicode scalar values, preserving unescaped `\r`, `\n`, and `\t` without `\r\n` / `\r` -> `\n` collapsing or Unicode normalization):
       * `EmptyText` if decoded content is `""` or contains only ASCII whitespace (`0x20`, `\t`, `\n`, `\r`).
       * `LimitExceeded` if decoded length exceeds `MAX_NOTE_LENGTH` (`2000`) or contains unpaired UTF-16 surrogates.
       * `InvalidEscapeSequence` on unknown backslash escapes in double-quoted strings; `UnexpectedToken` on forbidden raw control characters outside quoted strings (`Section 2.1`).
  2. **Exact `suspended` Token Grammar (`tdf 0.7.0`):**
     * `0` tokens -> `MissingDirectiveArgument` (`UnknownBlockType` if `{` follows).
     * First token quoted (`suspended "2026-11-11"` or `suspended "forever"`) -> `InvalidTimestamp`.
     * Any non-final token (`1 <= i < args.length - 1`) quoted -> `UnexpectedToken`.
     * When `args[0]` is unquoted bare word `forever`:
       * `1` token: `isSuspendedForever = true`, `suspendedNote = null`.
       * `2` tokens: `args[1]` MUST be a quoted string validated as `<note>` (`UnexpectedToken` if `args[1]` is an unquoted bare word).
       * `>= 3` tokens: `UnexpectedToken`.
     * When `args[0]` is any other unquoted bare word:
       * If `args.length >= 2` and `args.last` is quoted, validate `args.sublist(0, args.length - 1)` as UTC `<timestamp>` (`1..2` bare words; `InvalidTimestamp` if malformed, `UnexpectedToken` if `>= 3` bare words precede the note) and then validate `args.last` as `<note>`.
       * Otherwise validate all `args` as UTC `<timestamp>` (`InvalidTimestamp` on malformed `1..2` tokens; `UnexpectedToken` on `>= 3` tokens).
  3. **Exact `due` Token Grammar (`tdf 0.7.0`):**
     * `0` tokens -> `MissingDirectiveArgument` (`UnknownBlockType` if `{` follows).
     * First token quoted -> `InvalidTimestamp`.
     * Any non-final token (`1 <= i < args.length - 1`) quoted (such as wrong order `due 2026-11-11 "note" passive`) -> `UnexpectedToken`.
     * Let `end = args.length`:
       1. If `end >= 2` and `args[end - 1]` is quoted, record `rawNoteToken = args[end - 1]` and decrement `end -= 1`.
       2. If `end >= 2` and `args[end - 1]` is unquoted bare word `passive`, set `isDuePassive = true` and decrement `end -= 1`.
       3. If `end == 2` and `args[1]` is unquoted bare word `passive` (duplicate `due 2026-11-11 passive passive`), report `UnexpectedToken`.
       4. Validate `args.sublist(0, end)` as UTC `<timestamp>` (`InvalidTimestamp` if `end` is `1` or `2` and malformed; `UnexpectedToken` if `end >= 3`).
       5. If `rawNoteToken` was recorded, validate it as `<note>` (`EmptyText` / `LimitExceeded`).
  4. **Historical Version Gate (`< 0.7.0`):** Documents declaring `tdf 0.6.0`, `0.5.1`, or `0.5.0` validate `suspended` and `due` strictly under their historical rules, rejecting `passive` and trailing note tokens (`InvalidTimestamp` on `2`-token forms such as `suspended forever "note"`, `suspended 2026-11-11 "note"`, `due 2026-11-11 passive`, or `due 2026-11-11 "note"`, and `UnexpectedToken` on `>= 3`-token forms). Zero-mutation read-only load-time conversion (`0.5.0 -> 0.5.1 -> 0.6.0 -> 0.7.0`) initializes `suspendedNote = null`, `isDuePassive = false`, and `dueNote = null`.
* **Ownership & Lifecycle Matrix (`Section 6`):**
  * **Strict Ownership Invariant:** `TaskItem` normalizes `suspendedNote` to `null` whenever `!isSuspendedForever && suspendedAt == null`, and normalizes `dueNote` to `null` whenever `dueAt == null`. Neither note can exist as an orphan without its parent directive.
  * **Transition Summary:**
    * *Finite `suspended` expires (`<= now`) + Refresh / Sync / Mutation:* Removes `suspended` AND `suspendedNote` together, advancing `task.modified`.
    * *Deadline `due` passes (`<= now`, Overdue):* Keeps `due`, `isDuePassive`, AND `dueNote` intact on the open task.
    * *Move / Downgrade to `Someday` (`Sections 6.2 & 6.3`):* Removes `priority`, `suspended`, and `suspendedNote`; preserves `(dueAt, isDuePassive, dueNote)`.
    * *Standard Completion (`Section 6.4`, `repeat` omitted):* Removes `suspended`, `suspendedNote`, and `blocked`; preserves `(dueAt, isDuePassive, dueNote)` and `origin` on the `Completed` task.
    * *Recurring Completion (`Section 6.4 & 6.10.3`, `repeat` present):* Clears one-off `suspendedNote = null` on both Mode 1 and Mode 2; preserves `dueNote` across Mode 2 (`repeat` + `due`) occurrences while advancing `due` to `newDue` and resetting `isDuePassive = false`.
    * *Restore from `Completed` (`Section 6.5`):* Clears `finished`, `suspended`, `suspendedNote`, `due`, `isDuePassive`, and `dueNote`.
    * *Explicit Edit / Clear (`Section 6.6`):* Clearing `suspended` clears `suspendedNote`; clearing `due` clears `isDuePassive` and `dueNote`; editing or clearing `suspendedNote` or `dueNote` while keeping its parent directive updates `task.modified` once.
* **Normalized Payloads, Three-Way Merge & Diagnostic Redaction (`Section 6.7` & `AppLogger`):**
  * **Normalized `suspended` Tuple (`Section 6.7.3`):** `absent` when omitted (or pre-normalized to `absent` when finite `suspended <= now` during live sync), `(false, utcComponents, optionalDecodedSuspendedNote)` for finite `suspended`, and `(true, emptyList, optionalDecodedSuspendedNote)` for `forever`. Merged as one atomic deferral unit in `Section 6.7.5 Case 2`.
  * **Normalized `due` Tuple (`Section 6.7.3`):** `absent` when omitted, or `(utcComponents, isDuePassive, optionalDecodedDueNote)` when present. Merged as one atomic deadline unit in `Section 6.7.5 Case 2`.
  * **Diagnostic Privacy (`AppLogger`):** Never log raw `suspendedNote` or `dueNote` strings; log only boolean presence flags or aggregate cleanup counts (`expired_suspended`, `resolved_blocked`).
* **UI / UX Integration (`EditTaskScreen`, `TaskEditorSchedulingCard`, `TierTaskPill`, `TaskInfoDialog`):**
  1. **Scheduling Card (`TaskEditorSchedulingCard`):**
     * When `Suspended` is enabled (`isSuspended == true`), display a clearable multi-line `suspendedNote` input (`1..3` visible lines, max `2000` chars, `ValueKey('task_editor_suspended_note_input')`) directly below `TaskEditorSuspendedField`.
     * When `Due` is enabled (`hasDue == true`), display the `Auto-prioritize near deadline` toggle and a clearable multi-line `dueNote` input (`1..3` visible lines, max `2000` chars, `ValueKey('task_editor_due_note_input')`) directly below the `due` timestamp field.
     * When both `Repeat` and `Due` are enabled (`isRepeating && hasDue`), display an optional `Preparation lead (days)` numeric input (`0..3650`, `ValueKey('task_editor_repeat_lead_days_input')`) inside `TaskEditorRepeatField`.
  2. **Board Pills & Info Dialog (`TierTaskPill` & `TaskInfoDialog`):**
     * Hide `suspended_task_indicator_<id>` and `TaskInfoDialog._buildSuspendedSection` whenever finite `suspendedAt <= nowUtc` (retiring `taskInfoSuspendedElapsed`). When active (`forever` or `> nowUtc`), render `suspendedNote` inside the `Suspended` section card.
     * Hide `blocked_by_task_indicator_<id>` when all dependencies on an open task are currently satisfied, and render `dueNote` inside `TaskInfoDialog._buildDueSection`.

#### 1.4.5 Open Slot for Additional 0.7.0 Ideas
*(Additional ideas for `TDF 0.7.0` may be appended here as `Topic 5`, `Topic 6`, etc. during the `concept` phase.)*

### 1.5 Alternatives Considered
1. **Introduce a Separate Root `project <project-id> { ... }` Block Type (Topic 1):**
   * *Rejected:* A separate `project` entity would duplicate almost every attribute already present on `label` (`name`, `color`, `note`, `scoped`, `condition`, `modified`, `deleted` records, and task assignment directives), increasing grammar surface area, synchronization complexity, and UI navigation clutter. Enhancing `label` with `link` and a Context Hub view achieves the exact goal while keeping the data model minimal and orthogonal.
2. **Embed Label Links Inside `label.note` as Raw Markdown Text (Topic 1):**
   * *Rejected:* Tasks already use structured `link "<title>" "<uri>"` directives with explicit `<title>` and `<uri>` validation, scheme security checks (`InvalidUri`), and dedicated clickable UI controls. Forcing label links into unstructured `note` text would lose schema validation, structured agent discoverability, and consistent UI rendering between tasks and labels.
3. **Copy Label Links Automatically onto Every Assigned Task (Topic 1):**
   * *Rejected:* Copying links onto tasks duplicates data in the `.tdf` file and creates ambiguity when a link is updated on the label or deleted on a single task. Keeping project/context links on the `label` block and task-specific links on the `task` block maintains clean normalization.
4. **Mutate the Stored `priority` Header Flag on Disk When `due` Enters the Lead Window (Topic 2):**
   * *Rejected:* Persisting `task <id> priority {` when wall-clock time crosses `due - W_due` violates `Section 1.1` (`Data vs. View Separation`) and `Section 6.10.1` (read-only evaluation invariance), triggers background disk and WebDAV writes when merely viewing the board, advances `task.modified` without user action, and causes unnecessary three-way merge churn across offline devices. Derived effective priority in `TaskBoardEvaluator` achieves identical `Focus` promotion purely at evaluation time.
5. **Sort Eligible Tasks by `due` Timestamp Instead of Preserving `queue` Order (Topic 2):**
   * *Rejected:* Sorting `Focus` and `Ready` by ascending `due` timestamp would break manual `moveTaskInQueue` drag/reorder control whenever multiple tasks have deadlines (reordering `queue` would have no visual effect) and would leave ordering between `priority` tasks without `due` and urgent `due` tasks inconsistent. Treating `isDueUrgent` as membership in the existing two-bucket stable `queue` partition preserves full manual queue ordering within `Focus` and `Ready`.
6. **Store `dueLeadWindow` Inside a New Root `config { ... }` Block in `.tdf` (Topic 2):**
   * *Rejected:* Adding a root `config` block for view-derivation preferences would expand the root block grammar, require dedicated revision timestamps and merge semantics, and couple personal lead-time preferences into shared `.tdf` files — contradicting `Section 6.10.1`'s rule that `timeZone` is an operation parameter rather than stored `.tdf` entity state. Combining a normative specification default (`86,400` seconds / `24 hours`) with an optional evaluation parameter keeps `.tdf` minimal and deterministic across CLI tools and UI clients.
7. **Strip Expired `suspended` Directives Inside `TdfService.parse` / `TdfBlockParser.parseDocument` or Pure Read-Only Evaluation (Topic 3):**
   * *Rejected:* Mutating task payloads inside `TdfService.parse` / `TdfBlockParser.parseDocument` would break `sourceDigest` comparison (`Section 6.7.2`), corrupt baseline `B` decoding during three-way merges, and make parser output depend on wall-clock time. Performing expiry/resolution cleanup exclusively during guarded refresh/synchronization and committed domain mutations preserves parser determinism while still hiding expired `suspended` indicators immediately at evaluation time.
8. **Strip `condition` Rules When Satisfied or Strip Recurring-to-Recurring `blocked` Entries Before Dependent Completion (Topic 3):**
   * *Rejected:* `condition` rules (`day`, `time`, `location`) are cyclical/spatial filters meant to re-block when leaving the window or geofence; deleting them on first satisfaction would permanently destroy context filtering. Similarly, deleting a satisfied `blocked` dependency between two recurring tasks before the dependent task completes its occurrence would lose the dependency link needed by `Section 6.9.3` to rearm `<target-id>:<completions + 1>` for the next cycle.
9. **Auto-Delete Overdue `due` Deadlines When `due <= now` (Topics 2, 3 & 4):**
   * *Rejected:* `due` is a target deadline, not a temporary blocking lock. Deleting `due` once `due <= now` would erase overdue status badges, break Topic 2 overdue `Focus` auto-promotion, destroy Mode 2 recurring calendar anchors, and discard `dueNote` right when deadline visibility is most critical.
10. **Introduce Separate `suspended-note` and `due-note` Directives Instead of Inline `"<note>"` Arguments (Topic 4):**
    * *Rejected:* Separate directives would expand the 15-position `task` directive table, require cross-directive orphan validation (`suspended-note` without `suspended` or `due-note` without `due`), and risk mismatched hybrid states if merged separately. Inline trailing quoted `"<note>"` arguments on `suspended` and `due` make orphan notes structurally impossible in `.tdf` and bind each note atomically to its parent directive.

## Part 2: Technical Design & Code Changes

> [!NOTE]
> Part 2 outlines the preliminary technical design for Topics 1 through 4 and will be finalized for the transition to `status: planned`.

### 2.1 Architecture & Affected Modules (Preliminary for Topics 1–4)
* **Specification:** `spec/TDF_SPEC_0.7.0.md` (evolved from `spec/TDF_SPEC_0.6.0.md` with zero-mutation load-time conversion across `0.5.0 -> 0.5.1 -> 0.6.0 -> 0.7.0` alongside chained `0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0 -> 0.5.1 -> 0.6.0 -> 0.7.0` explicit import migration).
* **Domain Models (`lib/models/`):**
  * `lib/models/tdf_metadata.dart`: Add `final List<TaskLink> links;` (unmodifiable, defaulting to `const <TaskLink>[]`) to `TdfLabel` (Topic 1).
  * `lib/models/task_item.dart`:
    * Add `final int leadDays;` (defaulting to `0`, `0..3650`) to `TaskRepeatRule` and simplify `nextScheduleAnchoredOccurrence` to compute `targetDueLocalDate - leadDays` at `<repeat-time>` without `oldSuspended` month-end heuristics (Topic 3).
    * Add `final bool isDuePassive;` (defaulting to `false`, normalized to `false` when `dueAt == null`), `final String? suspendedNote;` (normalized to `null` when `!isSuspendedForever && suspendedAt == null`), `final String? dueNote;` (normalized to `null` when `dueAt == null`), and `bool isWithinDueLeadWindow(DateTime nowUtc, Duration? dueLeadWindow)` on `TaskItem`; clear `suspended`, `suspendedNote`, and `dependencies` in `toCompleted` (Topics 2, 3 & 4).
  * `lib/models/task_board_evaluator.dart`: Define `static const Duration defaultDueLeadWindow = Duration(hours: 24);`, accept `Duration? dueLeadWindow = defaultDueLeadWindow` in `evaluate` and `reevaluateBoard`, partition `_orderEligibleByQueue` by `task.isPriority || task.isWithinDueLeadWindow(now, dueLeadWindow)`, add `cleanupResolvedTaskBlocks` helper stripping expired finite `suspended <= now` (with `suspendedNote`) and resolved `blocked` entries (`target` in `deletedBlock.tasks` or live `target.completions >= req` with `task.repeatRule == null || target.repeatRule == null`) on open tasks, and log anonymized counts via `AppLogger` (Topics 2 & 3).
  * `lib/models/task_board_queue_mutator.dart`: Align `downgradeTask` (`_downgradeFromFocus` and `_downgradeToQueueTail`) with `hasEffectivePriority` so demoting a deadline-promoted task below regular tasks sets `isDuePassive: true` (preserving `dueNote`) and advances `task.modified` while preserving explicit `isPriority` when slot 8 is also effective-priority, clears `suspended` and `suspendedNote` on downgrade to `Someday`, and skips board-wide cleanup on pure no-op guard returns (Topics 2, 3 & 4).
  * `lib/models/task_board_mutator.dart` & `lib/models/task_board.dart`: Support `links` on `TdfLabel` (Topic 1); support `isDuePassive`, `suspendedNote`, `dueNote`, and `TaskRepeatRule.leadDays` in `addTask`/`updateTask`, run `cleanupResolvedTaskBlocks` across open tasks on committed mutations (`completeTask`, `deleteTask`, `updateTask`, `addTask`) while leaving pure no-op calls unchanged, preserve `dueNote` while clearing `suspendedNote` (and omitting already-expired `newSuspended <= now`) in `_reschedule`, and forward `dueLeadWindow` through `TaskBoard` evaluation/downgrade methods (Topics 1–4).
  * `lib/models/tdf_payload_comparison.dart`, `lib/models/task_board_reconciler.dart` & `lib/models/task_board_sync.dart`: Include `label.links` in `TdfLabel` payload comparison and three-way reconciliation (Topic 1); extend normalized `repeat` to `(count, unit, clock, leadDays)`, `suspended` to `(isForever, suspendedAt, suspendedNote)` with `<= now` pre-normalization to `absent` in `Case 2`, and `due` to `(dueAt, isDuePassive, dueNote)`; normalize automatic block-reason cleanup when comparing open tasks against `B` in `Sections 6.8.2 & 6.8.4` (`DeletionConflict` and `RecoveryRequired`); run post-merge and `stampAndNormalize` block-reason cleanup with clock-free pure merge revisions and idempotent `Section 6.7.6` revision reuse (Topics 2, 3 & 4).
  * `lib/models/task_board_undo.dart`: Add `previouslyBlockedDependencies` (`Map<String, TdfTaskDependency>`) on `TaskUndoEntry` for `complete` and `delete` undo captures (recording only dependencies actually stripped by that mutation), re-inserting those captured `TdfTaskDependency` entries verbatim and restoring `suspendedNote`, `dueNote`, and `isDuePassive` on undo (Topics 2, 3 & 4).
  * `lib/models/webdav_config.dart` & `lib/models/app_workspace.dart`: Add `DueLeadWindow` enum (`off`, `atDue`, `hours12`, `hours24`, `hours48`, `days7`) to `WebDavConfig` and workspace serialization (Topic 2).
* **Service Facade, Parser, Serializer & Importer (`lib/services/`):**
  * `lib/services/tdf_service.dart`, `lib/services/tdf_directive_parser.dart` & `lib/services/tdf_parser.dart`: Expose `maxLinksPerLabel = 20`, `supportedVersion = '0.7.0'`, load-time conversion across `0.5.0 -> 0.5.1 -> 0.6.0 -> 0.7.0`, and optional `Duration? dueLeadWindow` on `TdfService.parse` / `TdfBlockParser.parseDocument`; version-gate `tdf 0.7.0` extensions (`link` in `label` up to `maxLinksPerLabel = 20`; optional `[lead <1..3650> days]` on `repeat`; optional trailing `"<note>"` on `suspended`; optional `[passive]` and trailing `"<note>"` on `due`) while preserving strict `< 0.7.0` rejection rules (Topics 1–4).
  * `lib/services/tdf_serializer.dart`: Emit `link` at position `5` in `label`; emit `repeat <count> <unit> [<clock>] [lead <N> days]`, `suspended (<timestamp> | forever) ["<note>"]`, and `due <timestamp> [passive] ["<note>"]` in `task` (Topics 1–4).
  * `lib/services/tdf_importer.dart`: Add wall-clock-free `migrate060To070` (`0.6.0 -> 0.7.0`) requiring an available `sourceTimeZone` (`ImportContextRequired` when omitted/unavailable) whenever an open task carries `repeat`, `due`, and finite `suspended < due`, converting multi-day offsets ($D \ge 1$) into `lead <min(D, 3650)> days`, copying non-midnight `suspended` clocks into `<repeat-time>` when `<repeat-time>` was `00:00:00` ($D \ge 0$), and stripping deterministically resolved `blocked` entries from document state (Topic 3).
* **Providers (`lib/providers/`):**
  * `lib/providers/config_providers.dart`, `lib/providers/sync_providers.dart` & `lib/providers/task_providers.dart`: Persist `DueLeadWindow`, ensure `TaskSyncPipeline.synchronize` writes cleaned boards back to local/WebDAV storage whenever `stampAndNormalize` removes expired `suspended` or resolved `blocked` entries (including after WebDAV `304 Not Modified`), and schedule boundary re-evaluation on app resume and upcoming `suspended` / `due - W_due` instants (Topics 2 & 3).
* **UI & Localization (`lib/ui/`, `lib/l10n/`):**
  * `lib/ui/edit_labels_screen.dart`, `lib/ui/widgets/home_top_bar.dart`, `lib/ui/widgets/home_drawer.dart`, and `lib/ui/widgets/label_hub_dialog.dart`: Integrate `TaskEditorLinksSection` into `EditLabelScreen` and provide one-tap access to the **Label Context Hub** (Topic 1).
  * `lib/ui/home_screen.dart` (`_LandingContentSwitcher._evaluateBoard`), `lib/ui/edit_task_screen.dart`, `lib/ui/settings_screen.dart`, `lib/ui/widgets/settings_preference_cards.dart`, `lib/ui/widgets/task_editor_scheduling_card.dart`, `lib/ui/widgets/tier_task_pill.dart`, and `lib/ui/widgets/task_info_dialog.dart`: Evaluate `dueLeadWindow` live, add `passive` deadline toggle, `suspendedNote` / `dueNote` inputs, and `repeat` preparation lead-days input in `TaskEditorSchedulingCard`, hide expired `suspended` and satisfied `blocked` indicators on `TierTaskPill` / `TaskInfoDialog` (retiring `taskInfoSuspendedElapsed`), and render `suspendedNote`, `dueNote`, and deadline urgency badges (Topics 2, 3 & 4).
  * `lib/l10n/app_en.arb` & `lib/l10n/app_de.arb`: Add English and German localization strings for the Label Context Hub, deadline lead-window settings/toggles, `suspended` and `due` note inputs, and `repeat` preparation lead days; remove obsolete `taskInfoSuspendedElapsed` (Topics 1–4).

### 2.2 TDF Schema, Localization & State Changes (Preliminary for Topics 1–4)
* **Canonical `label` Directive Order (`6` Positions in `0.7.0` — Topic 1):**
  1. `name`
  2. `color`
  3. `note`
  4. `modified`
  5. `link` (`0..20`, in declaration order)
  6. `condition`
* **Modified `task` Directives in `0.7.0` (15-Position Order Preserved — Topics 2, 3 & 4):**
  * Position `7` (`repeat`): `repeat <count> <days|weeks|months> [<HH:MM[:SS]>] [lead <lead-count> days]`
  * Position `10` (`suspended`): `suspended (<YYYY-MM-DD HH:MM:SS> | forever) ["<note>"]`
  * Position `11` (`due`): `due <YYYY-MM-DD HH:MM:SS> [passive] ["<note>"]`
* **Resource Bounds & Normative Evaluation Constants (`Sections 5 & 7`):**
  * `MAX_LINKS_PER_LABEL = 20` (matching `MAX_LINKS_PER_TASK = 20`).
  * `MAX_REPEAT_COUNT = 3650` (shared upper bound for both `<count>` and `<lead-count>` in `repeat`).
  * `MAX_NOTE_LENGTH = 2000` (shared upper bound for `task.note`, `label.note`, `location.note`, `suspended` `<note>`, and `due` `<note>`).
  * `DEFAULT_DUE_LEAD_SECONDS = 86400` (`24 hours` normative default lead window for `due` effective-priority derivation in `Section 5.5`).

### 2.3 Implementation Details
* Maintain strict unidirectional data flow (`P-UDF-ARCHITECTURE`), repository I/O isolation (`P-IO-ISOLATION`), single-pass $O(N)$ scanning, parsing, tier evaluation, block-reason cleanup, and serialization (`P-ZERO-COPY`, `P-NO-QUADRATIC`), pre-checked `maxLinksPerLabel` / `maxNoteLength` / `maxRepeatCount` bounds before allocating (`P-BOUND-ALLOC`), read-only parser and evaluator purity, commutative pre-merge normalization of expired `suspended <= now`, idempotent revision selection when an input already reflects cleanup, and `AppLogger` privacy redaction (never logging raw task titles, link titles/URIs, `suspendedNote`, or `dueNote`).

### 2.4 Testing Strategy
* `M-EXHAUSTIVE-STATE-TESTS`:
  * Topic 1: Parse, normalize, compare, merge, and serialize `label` blocks with `0`, `1`, and multiple `link` directives; verify zero-mutation load-time conversion across `0.5.0`, `0.5.1`, and `0.6.0` to `0.7.0`.
  * Topic 2: Verify `TaskBoardEvaluator` across every `DueLeadWindow` variant (`off`, `atDue`, `hours12`, `hours24`, `hours48`, `days7`), `isDuePassive` (`false` vs. `true`), explicit `isPriority` combinations, `Someday`, `Blocked`, `scoped` exclusion vs. active label view, `moveTaskInQueue` stability, `downgradeTask` (`Focus -> Ready -> Planned -> Someday`, including preserving explicit `isPriority` when slot 8 is also effective-priority), and Mode 2 `repeat` reset of `isDuePassive`.
  * Topic 3: Verify block-reason cleanup across all four Section 5.4 cases: (a) finite `suspended` + `suspendedNote` retained at `11:59:59` and stripped with `modified` bump upon refresh/sync/committed mutation at `12:00:00` and `12:00:01` (including `2026-11-11 12:00:00` refreshed at `2026-11-11 12:00:01` across local-only, WebDAV `200`, and WebDAV `304 Not Modified`, while pure no-op mutation calls leave the board untouched); (b) `suspended forever` + `suspendedNote` retained across refreshes and stripped on clear/`Someday`/standard completion/restore; (c) `blocked` stripped immediately on prerequisite completion or deletion when `dependent.repeat == null || target.repeat == null`, preserved when both have `repeat` until `dependent` completes, and preserved for unknown forward references; (d) `condition` rules preserved when satisfied. Verify `repeat ... lead <N> days` Mode 2 scheduling, `TdfImporter.migrate060To070` (`ImportContextRequired` when `sourceTimeZone` is missing on open `repeat` + `due` + `suspended < due` tasks, multi-day `leadDays`, and same-day non-midnight `<repeat-time>` preservation), offline 3-way merge pre-normalization (`L` expired cleanup vs. `R` future deferral extension, `DeletionConflict` / `RecoveryRequired` hygiene against opposing deletions, clock-free pure merge revisions, and idempotent re-sync without double revision bump), and `TaskBoardUndo` verbatim `previouslyBlockedDependencies` + note restoration on `complete`, `delete`, and `downgrade`.
  * Topic 4: Verify `suspendedNote` and `dueNote` ownership invariants, overdue retention (`due <= now` keeps `due` + `dueNote`), Mode 1 vs. Mode 2 recurrence (`suspendedNote` cleared; `dueNote` preserved on Mode 2), standard completion vs. restoration, and atomic `(isForever, suspendedAt, suspendedNote)` / `(dueAt, isDuePassive, dueNote)` 3-way merges.
* `M-EXTREME-BOUND-TESTS`:
  * Topic 1: Verify `20` links accepted and `21` links rejected with `LimitExceeded` on `label`; verify `MAX_TEXT_LENGTH` (`500`) and `MAX_URI_LENGTH` (`2048`).
  * Topic 2: Verify exact UTC second boundaries around `W_due` (`86,401` s vs. `86,400` s, `0` s, `-1` s) and WIP soft-limit slicing (`2`, `3`, `4`, `8`, `9` urgent tasks).
  * Topics 3 & 4: Verify exact UTC second boundaries on `suspended` expiry (`11:59:59` kept vs. `12:00:00` and `12:00:01` stripped), `lead 1 days` and `lead 3650 days` accepted vs. `lead 0 days` (`InvalidNumber`), `> 24`-char `<lead-count>` (`LimitExceeded`), and `lead 3651 days` (`LimitExceeded`), and `suspendedNote` / `dueNote` at `1` and `2000` decoded Unicode scalar values accepted vs. `0`/whitespace-only (`EmptyText`) and `2001` (`LimitExceeded`).
* `M-DELIM-INJECT-TESTS` & `M-URI-PATH-EDGE-TESTS`:
  * Topic 1: Reject `javascript:`, `vbscript:`, `data:`, missing schemes, control characters in `<uri>` (`InvalidUri`), `0` arguments (`MissingDirectiveArgument`), `1` or `>= 3` or unquoted arguments (`UnexpectedToken`), and `link` inside `label` in `< 0.7.0` documents (`UnknownDirective`).
  * Topics 2, 3 & 4: Verify escaped quotes, backslashes, `\n` / `\r` / `\t` escapes preserved verbatim in decoded `<note>` values, `#` characters inside quoted `suspended`/`due` notes, physical CRLF line-ending handling outside quotes vs. raw `\r`/`\n` inside unclosed quotes (`UnterminatedString`), forbidden raw control characters outside quotes (`UnexpectedToken`), and rejection of misordered `due 2026-11-11 "note" passive` (`UnexpectedToken`), duplicate `passive passive` (`UnexpectedToken`), unquoted notes (`InvalidTimestamp` or `UnexpectedToken`), incomplete `repeat 1 months lead` / `repeat 1 months lead 5` (`UnexpectedToken`), non-`days` lead unit (`UnexpectedToken`), and `0.7.0` modifiers inside `< 0.7.0` documents (`InvalidTime`, `InvalidTimestamp`, or `UnexpectedToken`).
* `M-IO-TESTS` & Widget Tests (`test/providers/`, `test/ui/`):
  * Verify `syncFromRemote()` at `2026-11-11 12:00:01` writes the cleaned `.tdf` (without `suspended 2026-11-11 12:00:00 "note"`) to local disk and loopback WebDAV server (both `200 OK` and `304 Not Modified`), and skips writes on a second refresh at `12:00:05` when no further changes occur.
  * Verify `EditLabelScreen` + Label Context Hub (Topic 1), `SettingsScreen` `DueLeadWindow` selector (Topic 2), `EditTaskScreen` `suspendedNote`, `dueNote`, `passive` toggle, and `repeat` lead-days inputs, and `TierTaskPill` / `TaskInfoDialog` live indicator hiding and note rendering (Topics 2–4).

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
* **2026-11-10:** Added Topic 2 (Deadline-Driven Effective Priority via `due` Lead-Window Auto-Promotion in `TaskBoardEvaluator`, `due <timestamp> [passive]` modifier for informational deadlines and deterministic `Section 6.3` downgrades, workspace `DueLeadWindow` configuration, and live UI urgency indicators).
* **2026-11-12:** Added Topic 3 (Automatic Block-Reason Expiry & Resolution Cleanup on refresh/synchronization and mutations for expired finite `suspended <= now` and resolved one-shot/deleted `blocked` prerequisites while preserving live recurring-to-recurring dependencies and `condition` rules, commutative 3-way merge pre-normalization, undo dependency restoration, and explicit `repeat ... [lead <lead-count> days]` preparation offsets) and Topic 4 (optional trailing `"<note>"` arguments on `suspended` and `due` with coupled lifecycle ownership, overdue/Mode-2 `dueNote` retention, and harmonized `(dueAt, isDuePassive, dueNote)` / `(isForever, suspendedAt, suspendedNote)` atomic merge units).

### 3.3 Delivered Artifacts
*(Pending — proposal is in `concept` stage)*
