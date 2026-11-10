---
id: TEP-006
title: TDF Specification 0.7.0 Exploratory Design and Idea Collection
status: concept
type: spec
created: 2026-11-09
updated: 2026-11-10
---

# TEP-006: TDF Specification 0.7.0 Exploratory Design and Idea Collection

> [!NOTE]
> **Exploratory Idea Collection (`status: concept`):** This proposal serves as the living design collection for **TierTask Data Format (`TDF`) `0.7.0`**. New candidate specification features, domain refinements, and workflow ideas for `0.7.0` are collected, evaluated, and refined here before advancing to `planned` and updating the normative specification.

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal collects and evaluates candidate enhancements for **TierTask Data Format (`TDF`) `0.7.0`**:
1. **Topic 1 — Label Links and Context Hubs:** Extends root `label <label-id> [scoped] { ... }` blocks with repeatable `link "<title>" "<uri>"` directives (`0..MAX_LINKS_PER_LABEL`) and elevates labels in the TierTask UI from passive filter tags to lightweight **Project Collections and Context Hubs** that bundle a context's tasks, description (`note`), reference URIs (`link`), visibility scope (`scoped`), and activation rules (`condition`) in one place.
2. **Topic 2 — Deadline-Driven Effective Priority (`due` Lead-Window Auto-Promotion):** Evolves `due` from purely informational metadata into an active pull signal during tier evaluation (`TaskBoardEvaluator`). Scheduled, executable tasks in `queue` whose non-`passive` `due` timestamp lies within a defined lead window (`due <= now + W_due`, defaulting normatively to `24 hours` / `86,400` seconds, including overdue tasks with `due <= now`) receive derived **effective priority** during Section 5.5 evaluation, automatically pulling time-critical tasks from `Planned` or `Ready` into `Focus` as their deadline approaches without mutating the `.tdf` file on disk. An optional `passive` modifier (`due <YYYY-MM-DD> [<HH:MM[:SS]>] [passive]`) supports informational-only deadlines and deterministic manual downgrades (`Section 6.3`).

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
   * Supporting an optional `passive` modifier on `due` (`due <timestamp> [passive]`) allows users to record soft informational dates without auto-promotion and ensures that manually downgrading (`downgradeTask`, `Section 6.3`) a deadline-promoted task steps it down cleanly behind regular tasks instead of bouncing back into `Focus`.

### 1.3 Goals & Non-Goals
* **Goals (Initial `0.7.0` Idea Collection):**
  * Collect and evaluate candidate features for `TDF 0.7.0` in a structured, incremental specification proposal.
  * **Topic 1 (`label.link` & Label Context Hub):**
    * Permit `0..MAX_LINKS_PER_LABEL` (`20`) repeatable `link "<title>" "<uri>"` directives inside `label` blocks using the exact lexical, character-length (`MAX_TEXT_LENGTH = 500`, `MAX_URI_LENGTH = 2048`), and scheme-validation rules (`InvalidUri` on missing scheme or `javascript:`, `vbscript:`, `data:`) defined for `task.link`.
    * Define canonical serialization order inside `label` blocks (`1. name`, `2. color`, `3. note`, `4. modified`, `5. link`, `6. condition`).
    * Define normalization, payload comparison, and three-way baseline merge rules for `label.link` (merging the ordered `link` list on a `label` as one atomic merge unit, matching `task.link`).
    * Design a **Label Context Hub** UI flow (in `EditLabelScreen`, `HomeTopBar` when a label filter is active, `HomeDrawer`, and `TaskInfoDialog`) so users can view a label's `note` and launch its `link` URIs directly.
  * **Topic 2 (`due` Lead-Window Effective Priority & Pull Promotion):**
    * Define derived effective priority in `Section 5.5` (`TaskBoardEvaluator`): an eligible scheduled task in `queue` has effective priority at UTC instant `now` when `isPriority` is `true` OR when it carries a non-`passive` `due` timestamp within the lead window (`due <= now + W_due`, with normative specification default `DEFAULT_DUE_LEAD_SECONDS = 86400` / `24 hours`, including overdue tasks where `due <= now`).
    * Preserve relative `queue` order within both partitions of `Section 5.5 Step 2` (`effectivePriority` tasks in `queue` order followed by regular tasks in `queue` order) so manual drag/reorder via `moveTaskInQueue` remains deterministic across both `priority`-flagged and deadline-promoted tasks.
    * Extend the `due` directive syntax to `due <YYYY-MM-DD> [<HH:MM[:SS]>] [passive]` so soft informational deadlines can opt out of auto-promotion and explicit `downgradeTask` mutations (`Section 6.3`) can demote deadline-promoted tasks below regular tasks without clearing `due`.
    * Provide a workspace-scoped lead-window preference (`Off`, `At deadline (0h)`, `12h`, `24h` default, `48h`, `7d`) in `WebDavConfig` / `SettingsScreen`, live clock/resume re-evaluation in `HomeScreen`, and visual lead-window / overdue urgency indicators on `TierTaskPill` and `TaskInfoDialog`.
* **Non-Goals (Current Stage):**
  * Introducing separate `project` or `config` root block types in `.tdf`.
  * Modifying `lib/` or `spec/TDF_SPEC_0.6.0.md` while `TEP-006` remains in `status: concept`.
  * Altering 6-tier derivation (`Section 5`) or condition evaluation (`Section 4.4`) based on `label.link` metadata.
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

#### 1.4.2 Topic 2: Deadline-Driven Effective Priority (`due` Lead-Window Auto-Promotion)
* **TDF Grammar & Schema (`due` Directive in `task`):**
  ```text
  task 8jKaCdOkD2 {
      name     "Submit VAT declaration"
      created  2026-11-01 09:00:00
      modified 2026-11-01 09:00:00
      due      2026-11-11 17:00:00
  }

  task 4mNpQr9xYz {
      name     "Redeem hardware voucher before expiry"
      created  2026-11-02 10:00:00
      modified 2026-11-10 14:30:00
      due      2026-11-11 23:59:00 passive
  }
  ```
* **Validation & Canonical Serialization Rules (`Section 4.1.2` & `Section 7`):**
  * Syntax: `due <YYYY-MM-DD> [<HH:MM[:SS]>] [passive]` (`0..1` per `task` block at canonical position `11`, between `suspended` at `10` and `origin` at `12`).
  * `<YYYY-MM-DD> [<HH:MM[:SS]>]`: Unchanged UTC `<timestamp>` rules (`InvalidTimestamp` on malformed or out-of-range dates/times; no ordering constraint against `suspended`).
  * `passive` (**Optional**, Unquoted Bare Word Modifier):
    * **When omitted (`isDuePassive = false`):** `due` participates in lead-window effective priority during Section 5.5 evaluation.
    * **When present (`isDuePassive = true`):** `due` remains informational and anchors Mode 2 `repeat` schedules (`Section 6.10.3`), without granting derived effective priority in Section 5.5. Accepts both date-only (`due 2026-11-11 passive`, midnight UTC) and explicit-time (`due 2026-11-11 23:59:00 passive`) input forms.
    * When a 3rd token is present (after `<YYYY-MM-DD> <HH:MM[:SS]>`), reject a quoted `"passive"`, an unknown modifier, or any 4th argument with `UnexpectedToken`; when only 2 tokens are present and the 2nd token is not bare-word `passive`, validate the 2nd token as `<HH:MM[:SS]>` (`InvalidTimestamp` if quoted or malformed).
  * Canonical serializer output emits `due YYYY-MM-DD HH:MM:SS` when `isDuePassive` is `false` and `due YYYY-MM-DD HH:MM:SS passive` when `isDuePassive` is `true`.
  * Load-time conversion from `tdf 0.6.0` initializes `isDuePassive = false` for all existing `due` directives without mutating storage.
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
         * When $|E_{\text{ctx}}| \ge 7$ and the 7th task in $E_{\text{ctx}}$ (the slot-8 anchor) has `hasEffectivePriority == true`: keep `isDuePassive` unchanged, set `T.isPriority` to `false` if `isDueUrgent(T, now, W_due)` is already `true` (or `true` otherwise to match the prioritized slot-8 anchor), and move $T$ in `queue` immediately after the 7th task so $T$ occupies slot 8 (`Ready`).
         * When $|E_{\text{ctx}}| < 7$ or the 7th task in $E_{\text{ctx}}$ has `hasEffectivePriority == false`: strip `T.isPriority` if present AND set `T.isDuePassive = true` when `isDueUrgent(T, now, W_due)` is `true` (advancing `task.modified` when either attribute changes), moving $T$ after the 7th task, after the last task in $E_{\text{ctx}}$ when $1 \le |E_{\text{ctx}}| < 7$, or keeping $T$'s `queue` position unchanged when $|E_{\text{ctx}}| = 0$ (preserving the strict no-op revision rule when neither task attributes nor `queue` order changed). Setting `passive` prevents $T$ from immediately jumping back ahead of regular tasks into `Focus` upon re-evaluation.
       * **From `Ready` to `Planned`:** Strip `T.isPriority` if present, set `T.isDuePassive = true` when `isDueUrgent(T, now, W_due)` is `true` (advancing `task.modified` only when a task attribute changed), and move $T$ to the end of `queue` (advancing `queue.modified` only if its `queue` position changed).
       * **From `Planned` to `Someday` (`Section 6.2` & `6.3`):** Remove $T$ from `queue` (advancing `queue.modified`), strip `T.isPriority` and `suspended` if present, and preserve `(due, isDuePassive)`.
  2. **Automatic Reset of `passive` on Explicit Re-Prioritization, Deadline Edits, Restoration, and Recurrence (`Sections 6.4, 6.5, 6.6 & 6.10.3`):**
     * Explicitly promoting a task to `Focus` (`isPriority = true`), changing `due` to a different timestamp (unless `passive` is explicitly requested in the same edit), restoring a completed task (`Section 6.5`, which clears `due`), or completing a Mode 2 recurring task (`repeat` + `due` advancing `due` to `newDue > now` alongside `Section 6.4` Step 3 `priority` wake-up) resets `isDuePassive = false` so future deadlines auto-promote normally.
  3. **Normalized Payload & Three-Way Baseline Merge (`Section 6.7`):**
     * Extend the `due` component in normalized task payloads (`Section 6.7.3`) and same-occurrence three-way reconciliation (`Section 6.7.5`) to the atomic pair `(dueAt, isDuePassive)` (matching `origin`'s atomic `(namespace, externalKey)` scalar-pair merge semantics).
* **UI, Workspace Settings & Live Re-Evaluation:**
  1. **Workspace Preference (`WebDavConfig` & `SettingsScreen`):** Add a `DueLeadWindow` enum (`off`, `atDue` = `0h`, `hours12` = `12h`, `hours24` = `24h` default, `hours48` = `48h`, `days7` = `168h`) persisted per workspace in `AppWorkspace` / `WebDavConfig`.
  2. **Task Editor (`EditTaskScreen`):** Display an inline toggle (`Auto-prioritize near deadline`, inverted to `isDuePassive`) whenever a `due` timestamp is configured on a task.
  3. **Urgency Indicators (`TierTaskPill` & `TaskInfoDialog`):** Highlight `due_task_badge_<id>` on open tasks with a warning/accent color when `isDueUrgent` (`due <= now + W_due`) and `colorScheme.error` when overdue (`due <= now`), and display the active lead-window auto-priority status inside `TaskInfoDialog`.
  4. **Time-Boundary & Resume Re-Evaluation (`HomeScreen` & Providers):** Update `HomeScreen._evaluateBoard` to evaluate `board.evaluateForContext(...)` with `evaluationTime` and `configuration.dueLeadWindow.duration` even when `activeLabel == null && !hasCoordinates`, and trigger clock re-evaluation on app lifecycle `resumed` and next upcoming `suspended` / `due - W_due` threshold boundary so tasks pull into `Focus` live without manual reload.

#### 1.4.3 Open Slot for Additional 0.7.0 Ideas
*(Additional ideas for `TDF 0.7.0` will be appended here as `Topic 3`, `Topic 4`, etc. during the `concept` phase.)*

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

## Part 2: Technical Design & Code Changes

> [!NOTE]
> Part 2 outlines the preliminary technical design for Topics 1 and 2 and will be expanded as additional `0.7.0` ideas are collected and finalized for the transition to `status: planned`.

### 2.1 Architecture & Affected Modules (Preliminary for Topics 1 & 2)
* **Specification:** `spec/TDF_SPEC_0.7.0.md` (evolved from `spec/TDF_SPEC_0.6.0.md` with load-time conversion `0.6.0 -> 0.7.0` alongside chained `0.5.0 -> 0.5.1 -> 0.6.0 -> 0.7.0` support).
* **Domain Models (`lib/models/`):**
  * `lib/models/tdf_metadata.dart`: Add `final List<TaskLink> links;` (unmodifiable, defaulting to `const <TaskLink>[]`) to `TdfLabel` (Topic 1).
  * `lib/models/task_item.dart`: Add `final bool isDuePassive;` (defaulting to `false`, automatically normalized to `false` when `dueAt == null`) and `bool isWithinDueLeadWindow(DateTime nowUtc, Duration? dueLeadWindow)` on `TaskItem` (Topic 2).
  * `lib/models/task_board_evaluator.dart`: Define `static const Duration defaultDueLeadWindow = Duration(hours: 24);`, accept `Duration? dueLeadWindow = defaultDueLeadWindow` in `evaluate` and `reevaluateBoard`, partition `_orderEligibleByQueue` by `task.isPriority || task.isWithinDueLeadWindow(now, dueLeadWindow)`, and include `due_urgent` counts in deduplicated `eval.summary` debug logs (Topic 2).
  * `lib/models/task_board_queue_mutator.dart`: Align `downgradeTask` (`_downgradeFromFocus` and `_downgradeToQueueTail`) with `hasEffectivePriority` so demoting a deadline-promoted task below regular tasks sets `isDuePassive: true` and advances `task.modified` instead of bouncing back into `Focus` (Topic 2).
  * `lib/models/task_board_mutator.dart` & `lib/models/task_board.dart`: Support updating `links` on `TdfLabel` (Topic 1); support `isDuePassive` in `addTask`/`updateTask`, reset `isDuePassive` on `dueAt` timestamp changes and Mode 2 `repeat` completion, and forward `dueLeadWindow` through `TaskBoard.evaluate`, `evaluateForContext`, `applyAutoPull`, and `downgradeTask` (Topic 2).
  * `lib/models/tdf_payload_comparison.dart` & `lib/models/task_board_reconciler.dart`: Include `label.links` in `TdfLabel` payload comparison and three-way reconciliation as an ordered-list merge unit (Topic 1); extend `due` payload comparison and same-occurrence reconciliation to the atomic `(dueAt, isDuePassive)` pair (Topic 2).
  * `lib/models/webdav_config.dart` & `lib/models/app_workspace.dart`: Add `DueLeadWindow` enum (`off`, `atDue`, `hours12`, `hours24`, `hours48`, `days7`) to `WebDavConfig` and workspace serialization (Topic 2).
* **Parser & Serializer (`lib/services/`):**
  * `lib/services/tdf_directive_parser.dart` & `lib/services/tdf_parser.dart`: Accept repeatable `link "<title>" "<uri>"` directives inside `label` blocks up to `maxLinksPerLabel = 20` (Topic 1); accept optional trailing bare word `passive` on `due` directives in `tdf 0.7.0` while rejecting `passive` in `< 0.7.0` documents during version-gated load-time validation (Topic 2).
  * `lib/services/tdf_serializer.dart`: Emit `link` directives at canonical position `5` inside `label` blocks (Topic 1); emit `due YYYY-MM-DD HH:MM:SS [passive]` at canonical position `11` inside `task` blocks (Topic 2).
* **Providers (`lib/providers/`):**
  * `lib/providers/config_providers.dart` & `lib/providers/task_providers.dart`: Persist `DueLeadWindow` updates via `webDavConfigProvider`, pass `configuration.dueLeadWindow.duration` into `TaskNotifier` board evaluations/mutations, and trigger clock refresh on app resume and upcoming lead-window / deferral boundaries (Topic 2).
* **UI & Localization (`lib/ui/`, `lib/l10n/`):**
  * `lib/ui/edit_labels_screen.dart`, `lib/ui/widgets/home_top_bar.dart`, `lib/ui/widgets/home_drawer.dart`, and `lib/ui/widgets/label_hub_dialog.dart`: Integrate `TaskEditorLinksSection` into `EditLabelScreen` and provide one-tap access to the **Label Context Hub** (Topic 1).
  * `lib/ui/home_screen.dart`, `lib/ui/edit_task_screen.dart`, `lib/ui/settings_screen.dart`, `lib/ui/widgets/settings_preference_cards.dart`, `lib/ui/widgets/tier_task_pill.dart`, and `lib/ui/widgets/task_info_dialog.dart`: Evaluate `dueLeadWindow` live in `HomeScreen._evaluateBoard`, expose the `passive` deadline toggle in `EditTaskScreen` and `DueLeadWindow` selector in `SettingsScreen`, and render lead-window / overdue urgency highlights on `TierTaskPill` and `TaskInfoDialog` (Topic 2).
  * `lib/l10n/app_en.arb` & `lib/l10n/app_de.arb`: Add English and German localization strings for the Label Context Hub (Topic 1) and deadline lead-window settings, editor toggle, and urgency status text (Topic 2).

### 2.2 TDF Schema, Localization & State Changes (Preliminary for Topics 1 & 2)
* **Canonical `label` Directive Order (`6` Positions in `0.7.0` — Topic 1):**
  1. `name`
  2. `color`
  3. `note`
  4. `modified`
  5. `link` (`0..20`, in declaration order)
  6. `condition`
* **Extended `due` Directive in `task` (`Position 11 of 15` in `0.7.0` — Topic 2):**
  * `due <YYYY-MM-DD> [<HH:MM[:SS]>] [passive]` (serialized canonically in UTC as `due YYYY-MM-DD HH:MM:SS` or `due YYYY-MM-DD HH:MM:SS passive`).
* **Resource Bounds & Normative Evaluation Constants (`Sections 5 & 7`):**
  * `MAX_LINKS_PER_LABEL = 20` (matching `MAX_LINKS_PER_TASK = 20`).
  * `DEFAULT_DUE_LEAD_SECONDS = 86400` (`24 hours` normative default lead window for `due` effective-priority derivation in `Section 5.5`).

### 2.3 Implementation Details
* Maintain strict unidirectional data flow (`P-UDF-ARCHITECTURE`), repository I/O isolation (`P-IO-ISOLATION`), single-pass $O(N)$ scanning, parsing, tier evaluation, and serialization (`P-ZERO-COPY`, `P-NO-QUADRATIC`), pre-checked `maxLinksPerLabel` bounds before allocating the $(N+1)$-th link (`P-BOUND-ALLOC`), read-only evaluation purity (never mutating `TaskItem.isPriority` or `modifiedAt` during `TaskBoardEvaluator.evaluate`), and `AppLogger` diagnostic redaction (logging anonymized `due_urgent` counts and `task.downgrade` transitions without logging raw task titles, link titles, or URIs).

### 2.4 Testing Strategy
* `M-EXHAUSTIVE-STATE-TESTS`:
  * Topic 1: Parse, normalize, compare, merge, and serialize `label` blocks with `0`, `1`, and multiple `link` directives; verify load-time conversion from `0.6.0` to `0.7.0`.
  * Topic 2: Verify `TaskBoardEvaluator` across every `DueLeadWindow` variant (`off`, `atDue`, `hours12`, `hours24`, `hours48`, `days7`), `isDuePassive` (`false` vs. `true`), explicit `isPriority` combinations, `Someday` (`unqueued`), `Blocked` (`suspended > now`, unmet `blocked` prerequisite, unmet `condition`), `scoped` label exclusion vs. active label view, `moveTaskInQueue` stability within `Focus`/`Ready`, `downgradeTask` (`Focus -> Ready -> Planned -> Someday` with and without prioritized slot-8 anchors), Mode 2 `repeat` reset of `isDuePassive`, and atomic `(dueAt, isDuePassive)` three-way reconciliation.
* `M-EXTREME-BOUND-TESTS`:
  * Topic 1: Verify `20` links accepted and `21` links rejected with `LimitExceeded` on a `label` block; verify `MAX_TEXT_LENGTH` (`500`) and `MAX_URI_LENGTH` (`2048`) boundaries on `label.link`.
  * Topic 2: Verify exact UTC second boundaries around the lead window (`due - now == 86,401` s remains regular; `due - now == 86,400` s promotes to effective priority; `due == now` and `due - now == -1` s remain prioritized; `W_due = 0` s promotes at `due <= now` and not at `due == now + 1` s) and WIP soft-limit slicing when `2`, `3`, `4`, `8`, and `9` queued tasks are simultaneously within the `due` lead window.
* `M-DELIM-INJECT-TESTS` & `M-URI-PATH-EDGE-TESTS`:
  * Topic 1: Verify rejection of `javascript:`, `vbscript:`, `data:`, missing schemes, control characters, and unquoted arguments on `label.link` with `InvalidUri`, `EmptyText`, or `UnexpectedToken`.
  * Topic 2: Verify acceptance of `due YYYY-MM-DD passive` and `due YYYY-MM-DD HH:MM:SS passive` in `tdf 0.7.0`, and rejection of 3-token quoted `"passive"`, duplicate `passive passive`, unknown 3rd modifiers (`UnexpectedToken`), 2-token non-`passive` malformed times (`InvalidTimestamp`), and `due ... passive` inside `< 0.7.0` documents (`InvalidTimestamp` on 2-token or `UnexpectedToken` on 3-token forms).
* Widget tests (`test/ui/`):
  * Topic 1: Verify adding/removing/opening links in `EditLabelScreen` and opening the Label Context Hub dialog from `HomeTopBar` / `HomeDrawer`.
  * Topic 2: Verify `DueLeadWindow` selection in `SettingsScreen`, `passive` deadline toggle in `EditTaskScreen`, live promotion in `HomeScreen` when advancing `clockProvider` into the lead window, and urgency badge colors/text in `TierTaskPill` and `TaskInfoDialog`.

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

### 3.3 Delivered Artifacts
*(Pending — proposal is in `concept` stage)*
