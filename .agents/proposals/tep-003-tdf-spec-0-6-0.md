---
id: TEP-003
title: TDF Specification 0.6.0 Exploratory Design and Conformance Roadmap
status: concept
type: spec
created: 2026-11-08
updated: 2026-11-08
---

# TEP-003: TDF Specification 0.6.0 Exploratory Design and Conformance Roadmap

> [!NOTE]
> **Exploratory Concept Document (`status: concept`):** This TEP collects, structures, and refines candidate specification concepts for **TDF `0.6.0`** based on operational feedback from `0.5.0` / `0.5.1` workflows and multi-tool/agent interoperability. The focus of this proposal is exclusively on [`TDF_SPEC.md`](../../TDF_SPEC.md) semantics, concurrency rules, schema evolution, and machine-readable conformance fixtures — not on auditing or modifying the current application implementation.

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal defines the specification roadmap for **TierTask Data Format (`TDF`) `0.6.0`**. It organizes the candidate capabilities into a **Mandatory Core Scope for `0.6.0`** and a **Restrained / Optional Scope**, structured into eight specification capability areas across Topics 1 through 11:
1. **Guarded Local Publication, Bounded CAS-Merge Loop (`MAX_CAS_RETRIES`), and Canonical Root-Block Sorting (Topic 1):** Normative SHA-256 `sourceDigest` verification before save, automatic three-way reload-and-merge on mismatch, atomic temp-file swap without sync-folder `.tdf.lock` ghost files, and deterministic ASCII-ID sorting of `label` and `task` root blocks so identical merged states yield byte-identical `.tdf` files.
2. **Non-Blocking Target Deadlines (`due`) Coupled with Schedule-Anchored Recurrence and Local Calendar Lead-Time Preservation (Topics 2 & 9):** A non-blocking `due <timestamp>` directive (pure deadline metadata with no `suspended <= due` parse constraint, merged as an independent scalar within the same occurrence) that acts as a fixed calendar anchor when combined with `repeat`, advancing both `due` and `suspended` by the same multiple $k \ge 1$ of `<count> <unit>` in local calendar space (or defaulting `suspended` to the start of the `newDue` local day when `suspended` was omitted) so DST transitions never shift local wake-up times.
3. **External Source References (`link` Convention vs. Dedicated `origin` Directive — Topic 3):** Preserving `link "<title>" "<uri>"` strictly for user-facing links while isolating optional machine correlation keys in a dedicated scalar directive `origin "<namespace>" "<external-key>"` (`0..1`) if needed beyond the `0.5.1` deduplication convention.
4. **Executable Conformance Suite and Historical Unicode Scalar-Value Clarification (Topic 4):** Versioned `.tdf` and `.json` test vectors under `spec/conformance/` and an explicit rule in Section 10.1.1 that all historical schemas (`0.2.0`–`0.5.1`) measure character limits in decoded Unicode scalar values.
5. **Elevating Concurrent Label Assignments on Deleted Labels to `DeletionConflict` (Topic 5):** Prohibiting silent removal of newly added `labels` references (both `L minus B` on existing tasks and all `labels` on newly created tasks absent from `B`) when the target label appears in remote `deleted`, preserving the assigning side's live `label` block and classifying the collision normatively as `DeletionConflict` (Section 6.8.2) so `Delete` vs. `Undelete` resolves it cleanly.
6. **View-Scoped Labels (`label <label-id> [scoped] {`), Global-View Flood Protection, and Context-Relative Downgrades (Topic 6):** Restricting tasks to explicit label views and search when all assigned labels carry `scoped`, ignoring `scoped` labels during global-view condition evaluation of mixed-label tasks, automatically unscheduling (`queue` removal to `Someday` while preserving `suspended`) tasks that lose their last label due to a `scoped` label deletion (across explicit deletes, conflict resolutions, and three-way merges), and evaluating the `Focus -> Ready` downgrade anchor (Section 6.3) strictly within the active filter context.
7. **Same-Occurrence Merge Unbundling, Key-Value Map Merge for `blocked`, Step-Wise `subtasks` Merge, and Independent `scoped` Flag Merge (Topics 6, 7 & 8):** Merging the `label` `scoped` flag as an independent boolean scalar, unbundling `priority`, `suspended`, `due`, `repeat`, `blocked`, and `subtasks` when `B.completions == L.completions == R.completions` and `finished` is absent, merging `blocked` as a `(targetId -> requiredCompletion)` map per `targetId`, and merging `subtasks` boolean steps individually when the ordered step text sequence matches across `B`, `L`, and `R`.
8. **Restrained Prerequisite Expiry Hygiene and Time Zone Hints (Topics 10 & 11):** Prohibiting automatic pruning of missing prerequisite IDs (preserving forward references) except at the exact 30-day expiry of a confirmed `deleted` record with `checkpoint >= requiredCompletion`, and keeping time zone context out of entity blocks.

### 1.2 Motivation
`TDF_SPEC.md` `0.5.0` and `0.5.1` established a deterministic, single-pass $O(N)$ grammar with dynamic 6-tier derivation (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`), monotonic entity revisions, shared `queue` and `deleted` blocks, completion occurrence counters, and three-way baseline synchronization. Practical multi-actor operation across the TierTask GUI, autonomous CLI/AI agents, and cloud file synchronizers (OneDrive, Nextcloud, Syncthing) motivates targeted specification refinements for `0.6.0`:

1. **Unguarded Local Overwrites and Non-Deterministic Block Order:** Without a mandatory SHA-256 `sourceDigest` check and reload-and-merge loop before local writes, a long-running application session can overwrite external agent edits or cloud-sync atomic file replacements. Furthermore, because `0.5.1` leaves root `label` and `task` block order dependent on declaration order, two clients merging the same state can emit byte-different files with different SHA-256 digests.
2. **Deadlines vs. Availability and Schedule Drift on Recurring Deadlines:** `suspended` blocks a task in `Tier 4` until its start instant arrives, whereas a deadline (`due`) must leave an actionable task in the active pull cycle (`Tier 1–3`) today. Moreover, recurring tasks with fixed calendar deadlines (such as monthly billing on the 15th with a preparation window starting on the 10th) drift if `repeat` only calculates from completion time (`localNow`) rather than advancing both `due` and `suspended` by the same local calendar interval multiple $k \ge 1$.
3. **User-Facing Links vs. Agent Deduplication Keys:** Overloading `link "<title>" "<uri>"` with a third synchronization parameter would couple internal agent deduplication to visible UI links that users freely edit or delete.
4. **Cross-Language Conformance and Historical Length Units:** Prose verification tables in `TDF_SPEC.md` cannot be executed automatically by independent parsers, and historical schema snapshots (`0.2.0`–`0.4.0`) lacked an explicit statement that character bounds count decoded Unicode scalar values rather than UTF-16 code units or UTF-8 bytes.
5. **Silent Loss vs. Actionable Resolution on Deleted Label References:** A concurrent local assignment of a label that was deleted remotely must neither vanish silently nor halt with an unrecoverable schema syntax error when the existing `DeletionConflict` (`Delete` vs. `Undelete`) workflow in Section 6.8.2 can resolve it directly.
6. **Dedicated Context Lists (`scoped` Labels) and Post-Deletion Queue Flooding:** Users need opt-in `scoped` labels whose tasks appear only when that label filter is selected (or in search). At the same time, deleting a `scoped` label (e.g., a 25-item vacation packing list in `queue`, whether locally, via conflict resolution, or during three-way merge) must not strip the label and suddenly dump 25 unlabeled tasks into the global `Focus` and `Ready` tiers.
7. **Coarse Same-Occurrence Merge Granularity:** Copying the entire occurrence state atomically when `completions` and `finished` are unchanged discards non-conflicting concurrent edits to `priority`, `suspended`, `due`, different `blocked` target IDs, or different `subtasks` steps.
8. **Forward Prerequisite References vs. Retired Tombstones and Entity Compactness:** Stripping unknown `blocked` IDs on load or save would break hand-edited forward references, whereas retiring a satisfied prerequisite reference when its 30-day deletion record expires is safe and deterministic; likewise, time zone configuration belongs at the operation or workspace level rather than inside every task block.

### 1.3 Prioritization & Scope Partitioning for `0.6.0`
To keep `TDF 0.6.0` focused and protect the single-pass $O(N)$ grammar:
* **Mandatory Core for `0.6.0` (Topics 1, 2 [with Topic 9 integrated], 4, 5, 6, 7, 8):**
  * **Topic 1:** SHA-256 `sourceDigest` CAS-merge loop (`MAX_CAS_RETRIES = 3`, updating `sourceDigest`, `B`, and `L` before each retry), atomic temp-file swap (no `.tdf.lock` inside synced folders), and canonical ASCII-ID sorting of `label` and `task` root blocks.
  * **Topic 2 (integrating Topic 9):** Non-blocking `due <timestamp>` directive coupled with schedule-anchored recurrence and DST-safe local calendar lead-time preservation.
  * **Topic 4:** Machine-readable conformance suite (`spec/conformance/`) and historical Unicode scalar-value clarification in Section 10.1.1.
  * **Topic 5:** Normative classification of concurrent label assignments to deleted labels (on both existing and newly created tasks) as `DeletionConflict` (Section 6.8.2).
  * **Topic 6:** View-scoped labels (`label <label-id> [scoped] {`), global-view flood protection on `scoped` label deletion across explicit deletes, conflict resolutions, and three-way merges (Sections 6.7.8, 6.8.1 & 6.8.2), and active-filter-relative step-down downgrade anchors (Section 6.3).
  * **Topics 7 & 8:** Independent boolean scalar merge for `label` `scoped`, same-occurrence three-way merge unbundling, key-value map merge for `blocked` (`targetId -> requiredCompletion`), and step-wise boolean merge for `subtasks` on matching step text lists.
* **Restrained / Optional or Deferred Scope (Topics 3, 10, 11):**
  * **Topic 3:** Primary reliance on the `0.5.1` deduplication convention; if a schema field is added, use a separate optional `origin "<namespace>" "<external-key>"` (`0..1`) directive rather than modifying `link`.
  * **Topic 10:** Strict preservation of missing `blocked` target IDs (protecting forward references); any automatic pruning is restricted exclusively to the moment a confirmed `deleted` record with `checkpoint >= requiredCompletion` expires after 30 days (Section 6.8.3).
  * **Topic 11:** Keep time zone hints out of entity blocks; defer or restrict to a minimal optional root directive if needed by headless tools.

### 1.4 Detailed Specification Design for TDF 0.6.0

#### 1.4.1 Topic 1: Guarded Local Publication, Bounded CAS-Merge Loop, and Canonical Root-Block Sorting
* **Normative Source Fingerprint (`sourceDigest` — Sections 6.7.2 & 6.7.7):**
  * Bind every loaded working copy and acknowledged baseline `B` to the exact byte length and SHA-256 digest (`sourceDigest`) of the raw `.tdf` byte stream (paired with HTTP `ETag` when synchronizing via WebDAV). Do not rely on filesystem `mtime` or inode numbers alone.
* **Pre-Write Compare-and-Swap (CAS) Merge Loop (`MAX_CAS_RETRIES = 3`):**
  * Before persisting a mutated or merged candidate `L` to a local `.tdf` path, execute a bounded loop with `attempt = 0..MAX_CAS_RETRIES`:
    1. Read the current byte stream `R_bytes` from the target path (resolving the path afresh on every attempt so atomic file replacements by OneDrive, Nextcloud, or Syncthing are always observed) and compute `diskDigest = SHA256(R_bytes)`.
    2. If the target file does not exist (initial creation) or `diskDigest == sourceDigest`, serialize the candidate `L` into `out_bytes`, validate canonical output bounds (Section 7.1), write `out_bytes` to a temporary file `<target>.tmp.<random>` in the same directory, flush, atomically rename over `<target>`, set `sourceDigest = SHA256(out_bytes)`, set baseline `B = L`, and return success.
    3. If `diskDigest != sourceDigest` and `attempt < MAX_CAS_RETRIES`:
       - Parse `R_bytes` as incoming document `R`.
       - Execute the full three-way reconciliation `M = merge(B, L, R)` (`B` = last acknowledged baseline, `L` = current in-memory candidate, `R` = current disk document) under Sections 6.7 through 6.11 and validate `M`.
       - **Update Loop State Before Retry:** Set `sourceDigest = diskDigest`, update the baseline to the observed disk state `B = R`, set the new write candidate `L = M`, increment `attempt`, and repeat from Step 1.
    4. If contention persists after `MAX_CAS_RETRIES` attempts (`attempt == MAX_CAS_RETRIES` and `diskDigest != sourceDigest`), or if parsing/reconciliation yields `DeletionConflict`, `RecoveryRequired`, `SyncGenerationRollback`, or a schema validation error, abort the write without modifying `<target>`, preserve the caller's pre-loop state, and report the outcome to the caller.
* **Prohibition of Sync-Folder `.tdf.lock` Artifacts:**
  * Conforming implementations MUST NOT create persistent or advisory `.tdf.lock` files inside the workspace directory, because cloud sync daemons (OneDrive, Nextcloud, Syncthing) replicate lock files across devices and create stale ghost locks. Any optional local inter-process lock MUST use OS-native file-descriptor advisory locking or reside in the local OS runtime temporary directory outside the synchronized folder.
* **Canonical Root-Block Ordering for Deterministic `sourceDigest` Checksums (Section 7.1):**
  * In `0.6.0`, a canonical serializer MUST emit root elements in this exact deterministic order:
    1. `tdf 0.6.0` version header.
    2. `deleted { ... }` block (when present; omitted only when `generation == 0` and zero records exist).
    3. `queue { ... }` block (when present; omitted only when `queue.modified` is epoch and zero entries exist).
    4. All `label` blocks sorted in ascending ASCII order of `<label-id>`.
    5. All `task` blocks sorted in ascending ASCII order of `<task-id>`.
  * Because active pull-cycle order is stored entirely in `queue` (Section 4.5), sorting `task` and `label` root blocks by ASCII ID never alters tier derivation or queue order, and guarantees that two independent clients merging the same state produce **byte-for-byte identical `.tdf` output and identical `sourceDigest` hashes**.
* **Verification Cases:**
  * Client A loads at $T_0$; Agent B modifies the file at $T_1$; Client A saves at $T_2$ -> Client A detects `diskDigest != sourceDigest`, merges `L` and `R` against `B`, updates `sourceDigest = diskDigest`, `B = R`, and `L = M`, and writes both changes atomically on the next loop iteration.
  * OneDrive replaces the file via temp-file rename at $T_1$ -> Client A's path-based pre-write check detects the new content digest and reconciles.
  * Client A and Client B perform the same three-way merge in opposite input orders (`merge(B, L, R)` vs. `merge(B, R, L)`) -> canonical serialization produces the exact same byte sequence and SHA-256 `sourceDigest`.

#### 1.4.2 Topic 2 (with Topic 9 Integrated): Non-Blocking Deadlines (`due`) and Schedule-Anchored Recurrence with Local Calendar Lead-Time Preservation
* **Directive Syntax, Canonical Position & Domain Rules (Sections 3.3, 4.1.2 & 7.1):**
  * Add optional single-valued directive `due <YYYY-MM-DD> [<HH:MM[:SS]>]` (`0..1`, listed in Section 3.3 so duplicate declarations produce `DuplicateDirective`) to `task` blocks, stored in UTC and converted from local calendar input under Section 6.10.
  * **Canonical Position & Formatting:** Emit `due YYYY-MM-DD HH:MM:SS` in UTC immediately after `suspended` and before `origin` / `link` (updating the canonical `task` directive list in Sections 4.1.2 and 7.1 from 13 to 14 positions, or 15 positions if `origin` is included).
  * **No `suspended <= due` Schema Constraint:** Do not enforce an ordering constraint between `suspended` and `due`. Manually deferring (`suspended`) an already-overdue task to tomorrow while keeping its original `due` date from last Friday is valid and must never fail parsing or validation.
* **Non-Blocking Tier Semantics (Section 5):**
  * `due` NEVER places a task into `Blocked` (`Tier 4`) and NEVER implicitly overrides `queue` order or `priority` in Section 5.5. `queue` membership and `priority` remain the sole determinants of `Focus`, `Ready`, and `Planned` slots; `due` serves as pure deadline metadata for UI display, filtering, and recurrence anchoring.
* **Ordinary Mutation Semantics (`Setting due` — Section 6.6):**
  * Setting or updating `due` converts local calendar input to UTC under Section 6.10, advances `task.modified` once, and **preserves `queue` membership and order unchanged** (unlike `suspended`, setting `due` on an unscheduled `Someday` task does not append the task to `queue`). Clearing `due` removes the directive, advances `task.modified` once, and preserves `queue` membership and order.
* **Coupled Recurrence Anchoring (`repeat` + `due` + `suspended` — Sections 6.4 & 6.10.3):**
  When completing a recurring task (`repeat <count> <days|weeks|months> [<repeat-time>]`):
  1. **Without `due` (`due` Omitted — Completion-Relative Mode):**
     - Exact `0.5.1` behavior: compute `<next_due>` from the completion instant `localNow` + `<count> <unit>` combined with `<repeat-time>` (defaulting to `00:00:00` local time) under Section 6.10.3, and store that UTC instant in `suspended`.
  2. **With `due` Present (`due` as Fixed Calendar Anchor + DST-Safe Local Calendar Lead Window):**
     - **Step A (Advance `due` Along Fixed Local Schedule):** Convert `oldDue` (UTC) into local calendar components $(Y_d, M_d, D_d, h_d, m_d, s_d)$ in the configured IANA time zone. Find the smallest integer multiple $k \ge 1$ such that advancing $(Y_d, M_d, D_d)$ by $k \times \text{<count> <unit>}$ (applying month-end clamping from Section 6.10.3 Step 4 against $D_d$, preserving `oldDue`'s local wall-clock time $(h_d, m_d, s_d)$, and resolving local-to-UTC via Section 6.10.2) produces a UTC instant `newDue > now`. Set `due = newDue`.
     - **Step B (Update `suspended` in Local Calendar Space):**
       - **Case 1 (`oldSuspended` present and `oldSuspended < oldDue`):** Convert `oldSuspended` (UTC) into local calendar components $(Y_s, M_s, D_s, h_s, m_s, s_s)$. Advance $(Y_s, M_s, D_s)$ by the **exact same multiple $k \times \text{<count> <unit>}$** (applying month-end clamping against $D_s$, using `repeat`'s normalized `<repeat-time>` when non-midnight (`!= 00:00:00`) or preserving `oldSuspended`'s local wall-clock time $(h_s, m_s, s_s)$ otherwise, and resolving local-to-UTC via Section 6.10.2) to obtain `candidateSuspended`. Set `suspended = min(candidateSuspended, newDue)`. Because `00:00:00` and an omitted `<repeat-time>` share the same canonical representation in Sections 6.7.3 and 6.10.3, preserving $(h_s, m_s, s_s)$ whenever the normalized repeat clock is `(0, 0, 0)` is invariant across canonical serialization and reload, and advancing in local calendar space guarantees that a preparation window (e.g., waking up on the 10th at `08:00` local time for a deadline on the 15th at `18:00` local time) never shifts by $\pm 1$ hour across Daylight Saving Time transitions.
       - **Case 2 (`oldSuspended` omitted or `oldSuspended >= oldDue`):** Compute `candidateSuspended` on `newDue`'s local calendar date using `repeat`'s normalized local clock `<repeat-time>` (which defaults to `00:00:00` local time when omitted, resolved to UTC via Section 6.10.2), and set `suspended = min(candidateSuspended, newDue)`. This defers the next occurrence until the start of the new due date (or `<repeat-time>` on that date) and remains idempotent across all subsequent completions.
* **Restoration & Merge Semantics (Sections 6.5 & 6.7.5):**
  * Restoring a completed standard task (Section 6.5) removes `finished`, `suspended`, and `due`.
  * Within the same occurrence (`B.completions == L.completions == R.completions` and `finished` absent), merge `due` as an independent scalar unit under Section 6.7.5.
* **Verification Cases:**
  * An open queued task with `due` next Friday and no `suspended` stays in `Focus`/`Ready`/`Planned` today.
  * Setting `due` on an unscheduled `Someday` task updates `due` and `task.modified` while keeping the task in `Someday` outside `queue`.
  * An overdue task (`due` yesterday) is manually deferred via `suspended` to tomorrow -> valid document; `Blocked` today, active tomorrow with original `due` preserved.
  * A monthly task (`repeat 1 months`) with `due` on `2026-10-15 18:00` local (CEST, UTC+2) and `suspended` on `2026-10-10 08:00` local is completed late on `2026-10-17` -> `newDue` advances by $k = 1$ month to `2026-11-15 18:00` local (CET, UTC+1) and `newSuspended` advances by $k = 1$ month to `2026-11-10 08:00` local (CET, UTC+1), preserving the exact `08:00` local wake-up clock despite the October DST transition.
  * A monthly task (`repeat 1 months`) with `due` on `2026-11-15 18:00` local and no `suspended` is completed early on `2026-11-12` -> `newDue` advances to `2026-12-15 18:00` local and `newSuspended` is set to `2026-12-15 00:00:00` local (so it stays in `Blocked` until Dec 15 begins rather than remaining in `Focus` on Nov 12).

#### 1.4.3 Topic 3: External Source References (`link` Convention vs. Optional `origin` Directive)
* **Strict Separation from `link`:**
  * Do not add a third argument to `link "<title>" "<uri>"`. `link` remains a user-facing repeatable directive (`0..20`) that users can freely edit, reorder, or delete in the UI without breaking external agent synchronization.
* **Two-Tier Approach:**
  1. **Default `0.5.1` / `0.6.0` Convention (Zero Schema Overhead):** Agents store source links in `link` (using permanent document/vault URIs or block fragments where available) and deduplicate across open and `Completed` tasks using `(link URI, task name, concrete outcome in note)`.
  2. **Optional `0.6.0` Schema Directive (`origin` — Restrained Scope):** If schema-level correlation is included in `0.6.0`, define an optional single-valued scalar directive `origin "<namespace>" "<external-key>"` (`0..1` per `task`, listed in Section 3.3, both arguments non-empty quoted strings up to `MAX_TEXT_LENGTH`), emitted canonically after `due` and before `link`, placed in `Task payload` (Section 6.7.3) immediately before `link`, merged as an independent scalar unit in Section 6.7.5, and preserved when the task enters `Completed`.

#### 1.4.4 Topic 4: Executable Conformance Fixtures and Historical Unicode Scalar-Value Clarification
* **Normative Historical Text-Length Unit Rule & `0.5.1` Snapshot Entry (Section 10.1.1):**
  * Add the immutable `0.5.1` Git commit and specification blob SHA-1 entry to the historical schema table in Section 10.1.1.
  * State explicitly in Section 10.1.1 that all historical source schemas (`0.2.0`, `0.3.0`, `0.4.0`, `0.5.0`, and `0.5.1`) measure text length bounds (`MAX_TEXT_LENGTH = 500`, `MAX_NOTE_LENGTH = 2000`, `MAX_URI_LENGTH = 2048`) in **decoded Unicode scalar values without Unicode normalization** (identical to Section 2.8), eliminating UTF-16 vs. UTF-8 vs. grapheme cluster ambiguity during chained import source validation.
* **Versioned Conformance Fixture Suite (`spec/conformance/v0.6.0/`):**
  * Provide machine-readable `.tdf` and `.json` test vectors covering:
    - Valid `.tdf` inputs paired with expected canonical `.tdf` output (verifying canonical root-block sorting and directive ordering) and normalized payload JSON.
    - Invalid `.tdf` inputs paired with `manifest.json` (`{ "error": "<TdfErrorKind>", "line": <1-based-int> }`).
    - Boundary fixtures for Unicode scalar values above `U+FFFF`, combining mark pairs (`U+0065 U+0301`), and **canonical output expansion** (`LimitExceeded` under Section 7.1 when canonical formatting pushes a near-limit input past `MAX_FILE_BYTES` or `MAX_LINE_COUNT`).
    - JSON vectors for three-way merge (including `DeletionConflict` on newly assigned deleted labels, map-based `blocked` merge, and step-wise `subtasks` merge), `Europe/Berlin` DST conversions, and `0.2.0 -> ... -> 0.6.0` chained migrations.

#### 1.4.5 Topic 5: Elevating Concurrent Label Assignments on Deleted Labels to `DeletionConflict`
* **Rule in Sections 6.7.5, 6.7.8 & 6.8.2:**
  * For every surviving live task $T$ during three-way merge, define the set of newly introduced label references on side $X \in \{L, R\}$ as:
    $$A_X(T) = \begin{cases} T_X.\text{labels} \setminus T_B.\text{labels} & \text{if } T \in B \\ T_X.\text{labels} & \text{if } T \notin B \text{ (newly created on side } X\text{)} \end{cases}$$
  * Compute merged `T.labels` for tasks present in `B` via `added = A_L(T) union A_R(T)` and `removed = (T_B.labels minus T_L.labels) union (T_B.labels minus T_R.labels)`, and retain $A_X(T)$ for tasks newly created on side $X$.
  * Never silently strip a label ID $l \in A_L(T) \cup A_R(T)$ merely because the opposing side contains a deletion record for `label` $l$ in `deleted`.
  * **Normative `DeletionConflict` Classification & Live `label` Preservation:** When any merged live task $T$ retains a newly introduced label ID $l \in A_L(T) \cup A_R(T)$ while `label` $l$ has a deletion record in `deleted` on the opposing side, the reconciler MUST retain the assigning side's live `label` block $l$ alongside the opposing side's deletion record (even when `label` $l$'s own payload was unchanged relative to `B`) and classify `label` $l$ as a **`DeletionConflict`** under Section 6.8.2 (rather than discarding `label` $l$ early or failing with a raw `UnknownLabelReference` schema error):
    - **User/Caller Chooses `Delete`:** Confirms deletion of `label` $l$ with `decisionRevision`, removes $l$ from all tasks in the candidate (advancing their `modified` timestamps and applying the `scoped` queue-eviction rule from Topic 6 if applicable), and publishes the valid result.
    - **User/Caller Chooses `Undelete`:** Restores the retained live `label` $l$ block with `modified = decisionRevision`, removes its record from `deleted`, increments `deleted.generation` once, and preserves the label assignment on all tasks.

#### 1.4.6 Topic 6: View-Scoped Labels (`label <label-id> [scoped] {`), Global-View Flood Protection, and Context-Relative Downgrades
* **Syntax, Payload Tuple Order & Merge Granularity (Sections 4.2, 6.7.3 & 6.7.5):**
  * Permit an optional `scoped` bare-word flag in the `label` block header:
    ```text
    label <label-id> [scoped] {
        name "<display_name>"
    }
    ```
    Any unknown or extra header flag on `label` produces `InvalidBlockHeader`.
  * Define the `Label payload` tuple in Section 6.7.3 in exact component order `(scoped, name, note, color, condition)` (where an omitted `scoped` flag is `false`, preceding `true`), and merge `scoped` as an **independent boolean scalar unit** alongside `name`, `note`, `color`, and `condition` when a live `label` block is merged across `B`, `L`, and `R` (Section 6.7.5).
* **Global-View Pre-Filtering Rule (Section 5.1):**
  Let $L(T)$ be the set of declared labels referenced in task $T$'s `labels` directive, and let $\text{isScoped}(l)$ be `true` when label $l$ has the `scoped` header flag:
  * **Active Label Filter Selected (`activeLabelId = l*`):** Unchanged. Every task $T$ with $l^* \in L(T)$ enters Sections 5.2 through 5.5.
  * **No Label Filter Selected (Global View):** Task $T$ is **restricted from the global view** (excluded in Section 5.1) if and only if $L(T)$ is non-empty and **every** assigned label in $L(T)$ is `scoped`:
    $$\text{isRestrictedFromGlobalView}(T) \iff L(T) \neq \varnothing \;\land\; \forall l \in L(T),\; \text{isScoped}(l)$$
    Tasks with $L(T) = \varnothing$ or with at least one regular (non-`scoped`) label ($\exists l \in L(T),\; \neg\text{isScoped}(l)$) enter the global view normally.
  * **Global Search & Prerequisite Resolution (`blocked`):** Search always inspects all tasks in the document. Prerequisite evaluation (`blocked` in Sections 5.4 and 6.9.2) always resolves across the complete document regardless of `scoped`.
* **Global-View Condition Evaluation for Mixed-Label Tasks (Section 4.3.3 Rule 4):**
  * When a task $T$ has at least one non-`scoped` label ($\exists l \in L(T),\; \neg\text{isScoped}(l)$) alongside one or more `scoped` labels, $T$ is evaluated in the **global view** strictly as if it had **no `scoped` labels**:
    $$L_{\text{global}}(T) = \{\, l \in L(T) \mid \neg\text{isScoped}(l) \,\}$$
  * Only the non-`scoped` labels $L_{\text{global}}(T)$ form candidate condition contexts (`OR` across $l \in L_{\text{global}}(T)$) in the global view.
* **Global-View Flood Protection on `scoped` Label Deletion (Sections 6.7.8, 6.8.1 & 6.8.2):**
  * Whenever a `scoped` label $l_{\text{del}}$ is removed from a live task $T$ — whether via an explicit label deletion command (Section 6.8.1), an explicit `Delete` conflict resolution (Section 6.8.2), or non-conflicting label removal during three-way merge reconciliation when $l_{\text{del}}$ was deleted on the opposing side (Section 6.7.8; where $l_{\text{del}}$ was `scoped` in `B` or on the side that held $T$):
    - If $T$ was restricted from the global view prior to removing the deleted label(s) ($L_{\text{before}}(T) \neq \varnothing \land \forall l \in L_{\text{before}}(T),\; \text{isScoped}(l)$), and removing the deleted label(s) leaves $T$ with **zero labels** ($L_{\text{after}}(T) = \varnothing$), and $T$ is currently listed in `queue`, **remove $T$'s task ID from `queue` and strip `priority` if present in the same atomic transaction while preserving `suspended`** (so unscheduled tasks without active deferrals enter `Someday` under Section 5.3, while deferred or recurring tasks keep their `suspended` schedule in `Blocked` -> `Someday` under Sections 5.3 and 5.4).
    - For explicit deletion mutations and conflict resolutions (Sections 6.8.1 & 6.8.2), advance `T.modified` and `queue.modified` using the mutation rule (`max(now, previous + 1 second)`). During three-way merge reconciliation (Section 6.7.8), compute `T.modified` and `queue.modified` strictly via the deterministic merge revision formulas (`max(B, L, R) + 1 second` under Sections 6.7.6 and 6.11.2) without reading the current clock.
    - This prevents a deleted `scoped` list (including tasks concurrently scheduled into `queue` on one device while their `scoped` label was deleted on another device) from flooding the global `Focus` and `Ready` tiers as unlabeled tasks.
    - If $T$ also carried a non-`scoped` label ($L_{\text{after}}(T)$ contains a regular label, so $T$ was already in the global view) or still retains another live `scoped` label ($L_{\text{after}}(T) \neq \varnothing$), keep $T$'s entry in `queue`.
* **Active-Filter-Relative Step-Down Downgrade Anchor (Section 6.3):**
  * Clarify in Section 6.3 that when downgrading an active task $T$ from `Focus` to `Ready`, $T$'s `priority` flag and target position in `queue` are determined **relative to the executable tasks matching the currently active filter context (`activeLabelId`)**:
    - Let $E_{\text{ctx}}$ be the ordered sequence of executable tasks in `queue` (excluding $T$ itself) that pass Section 5.1 through Section 5.4 for the active `activeLabelId` (`null` for global view, where `scoped`-only tasks are excluded; or `l*` for a filtered label view).
    - **If $|E_{\text{ctx}}| \ge 7$:** Strip `priority` if present (unless the 7th task in $E_{\text{ctx}}$ carries `priority`, in which case preserve `priority` to match the slot-8 anchor as in Section 6.3) and move $T$ in `queue` immediately after the **7th task in $E_{\text{ctx}}$** so $T$ occupies the 8th executable slot (the last slot of `Ready`) in the active filter context.
    - **If $1 \le |E_{\text{ctx}}| < 7$:** Strip `priority` if present and move $T$ in `queue` immediately after the **last task in $E_{\text{ctx}}$** (rather than appending $T$ to the very end of the global `queue` behind unrelated tasks from other labels).
    - **If $|E_{\text{ctx}}| = 0$:** Strip `priority` if present and keep $T$'s position in `queue` unchanged (applying the No-Op revision protection rule from Section 6.3 when neither `priority` nor `queue` order changes).

#### 1.4.7 Topics 7 & 8: Fine-Grained Same-Occurrence Merging, Key-Value Map Merge for `blocked`, Step-Wise `subtasks` Merge, and Independent `scoped` Flag Merge
* **Label `scoped` Flag Merge (Sections 6.7.3 & 6.7.5):**
  * When merging a live `label` block across `B`, `L`, and `R`, merge its `scoped` boolean header flag as an independent scalar unit alongside `name`, `note`, `color`, and `condition` (ordered as `(scoped, name, note, color, condition)` in the `Label payload` tuple of Section 6.7.3).
* **Two-Level Task Occurrence Merge Rule (Sections 6.7.3 & 6.7.5):**
  * Define the `Task state` tuple in Section 6.7.3 in exact component order `(completions, priority, finished, suspended, due, repeat, blocked, subtasks)`.
  1. **Cross-Occurrence or Completion-State Transition (`completions` or `finished` presence differs among `B`, `L`, `R`):**
     - Retain the atomic rule: copy the complete occurrence state (`completions`, `priority`, `finished`, `suspended`, `due`, `repeat`, `blocked`, `subtasks`) from the complete entity winner `W` (where the greater `completions` counter wins under Section 6.7.4).
  2. **Same-Occurrence Concurrent Edit (`B.completions == L.completions == R.completions` and `finished` is omitted in `B`, `L`, and `R`):**
     - Merge each operational unit independently using the three-way baseline `B` and complete entity winner `W`:
       - `priority`: Independent boolean scalar unit.
       - `suspended`: Independent deferral scalar unit.
       - `due`: Independent timestamp scalar unit.
       - `repeat`: Independent recurrence rule scalar unit.
       - `blocked`: **Key-Value Map Merge by `targetId`:**
         Using the normalized prerequisite maps $M_B, M_L, M_R : \text{TaskId} \rightharpoonup \mathbb{N}^+$ from Section 6.7.3 (where each entry maps a prerequisite `targetId` to its `requiredCompletion`, or `absent` if not referenced), resolve each `targetId` in $\text{dom}(M_B) \cup \text{dom}(M_L) \cup \text{dom}(M_R)$ independently:
         1. If $M_L(\text{id}) = M_R(\text{id})$, keep $M_L(\text{id})$.
         2. Else if $M_L(\text{id}) = M_B(\text{id})$, keep $M_R(\text{id})$ (incorporating independent prerequisite additions, removals, or requirement updates from `R`).
         3. Else if $M_R(\text{id}) = M_B(\text{id})$, keep $M_L(\text{id})$ (incorporating independent prerequisite additions, removals, or requirement updates from `L`).
         4. Else (both `L` and `R` changed `targetId` to different states), keep $M_W(\text{id})$.
         Validate the resulting dependency graph across the complete merged document for `CircularDependency` (Section 6.7.7).
       - `subtasks` (**Step-Wise Boolean Merge on Matching Step Texts**):
         - When `B.subtasks`, `L.subtasks`, and `R.subtasks` are all present and have the exact same ordered sequence of decoded step `<text>` strings $[s_1, \dots, s_m]$, merge the `auto-finish` header flag and each step $i$'s `<bool>` completion flag ($i \in 1..m$) independently via the three-way scalar rule.
         - Otherwise (if `subtasks` was added, removed, reordered, or had step `<text>` edited on either side), merge the complete `subtasks` block as one atomic unit via the three-way rule using `W` on conflict.
         - Preserve the Section 6.7.5 invariant: synchronization MUST NOT independently trigger task completion or recurrence even if all merged steps become `true` on a `subtasks auto-finish` block.

#### 1.4.8 Topics 10 & 11 (Restrained Scope): Prerequisite Expiry Hygiene and Time Zone Context
* **Topic 10 (Prerequisite Reference Hygiene — Section 6.8.3):**
  * Missing target `<task-id>` tokens in `blocked` MUST NOT be pruned during parsing, loading, or ordinary mutations, preserving hand-edited forward references (Section 10.4.1) and out-of-order sync arrivals.
  * Cleanup rule for `0.6.0`: Only during a guarded 30-day deletion record cleanup transaction (Section 6.8.3), when a task deletion record `task <id> <ts> <checkpoint>` is being retired after $> 30$ days and satisfies $\text{checkpoint} \ge \text{requiredCompletion}$ on a live task's `blocked` directive, that satisfied expired reference `<id>[:<req>]` MUST be removed in the same guarded cleanup transaction (advancing the affected live task's `modified` timestamp) so all clients converge on identical post-cleanup payloads.
* **Topic 11 (Time Zone Hint):**
  * Deferred / kept out of `task` and `label` blocks to preserve file compactness. Headless tools continue to pass an explicit IANA zone parameter (or read an optional workspace-level setting outside entity blocks).

### 1.5 Alternatives
1. **Use Physical `.tdf.lock` Files Inside the Workspace Directory (Topic 1 Alternative):**
   * *Rejected:* Cloud synchronization clients (Nextcloud, OneDrive, Syncthing) synchronize `.tdf.lock` files across devices, causing ghost locks if a process exits or sync lags. A SHA-256 `sourceDigest` CAS-merge loop (`MAX_CAS_RETRIES = 3`) with same-directory atomic temp-file rename provides lock-free cross-device safety.
2. **Implicit Priority Boost for Approaching `due` Dates or Raw UTC-Second Lead-Time Subtraction (Topic 2 Alternatives):**
   * *Rejected:* Implicitly promoting tasks based on `due` undermines the explicit pull-system guarantees of `queue` and `priority`. Subtracting raw UTC seconds ($\text{oldDue} - \text{oldSuspended}$) shifts local wake-up times by $\pm 1$ hour across DST transitions; advancing both `oldDue` and `oldSuspended` by the same multiple $k \ge 1$ of `<count> <unit>` in local calendar space preserves the exact local wake-up clock without adding extra keywords to `repeat`.
3. **Overload `link "<title>" "<uri>"` with a Third External-Key Parameter (Topic 3 Alternative):**
   * *Rejected:* Mixing visible user links with internal agent correlation keys causes deduplication breakage whenever a user edits or deletes a link in the UI.
4. **Abort Merge with `UnknownLabelReference` on Concurrent Assignment to a Deleted Label (Topic 5 Alternative):**
   * *Rejected for `0.6.0`:* Classifying the collision as `DeletionConflict` (Section 6.8.2) reuses the existing `Delete` vs. `Undelete` resolution mechanism instead of stranding the user with a low-level schema error.

## Part 2: Technical Design & Specification Impact

### 2.1 Affected Specification Sections (`TDF_SPEC.md`)
* **Section 2.8, Section 3.3 & Section 3.4 (Primitive Types, Single-Valued Directives & EBNF Grammar):**
  * Add `due` (and optional `origin`) to the single-valued `task` directive list in Section 3.3 (`DuplicateDirective` on repetition).
  * Add `scoped` header flag to `label-block` (`ws* "label" ws+ label-id [ ws+ "scoped" ] ws+ "{" ws* [ comment ] newline ...`) in Section 3.4.
  * Add `due-dir` (`ws* "due" ws+ timestamp ws* [ comment ] newline`) and optional `origin-dir` (`ws* "origin" ws+ quoted-string ws+ quoted-string ws* [ comment ] newline`) to `directive` in Section 3.4.
* **Section 4.0, 4.1 & 4.2 (`tdf 0.6.0` Header, `task` Block & `label` Block):**
  * Update current header to `tdf 0.6.0` (with load-time in-memory conversion from `0.5.1`, and chained in-memory conversion `0.5.0 -> 0.5.1 -> 0.6.0` for `0.5.0` documents).
  * Add `due` to `task` directives at canonical position 11 (immediately after `suspended` and before `origin` / `link`, updating the 13-position list to 14 positions, or 15 positions with `origin` at position 12) and `scoped` to `label` header flags.
* **Section 4.3.3 & Section 5.1 (Condition Contexts & 6-Tier Pre-Filtering):**
  * Define $\text{isRestrictedFromGlobalView}(T) \iff L(T) \neq \varnothing \land \forall l \in L(T),\; \text{isScoped}(l)$ in Section 5.1.
  * Define $L_{\text{global}}(T) = \{l \in L(T) \mid \neg\text{isScoped}(l)\}$ for global-view condition evaluation in Section 4.3.3 Rule 4.
* **Section 6.3, 6.4, 6.5, 6.6 & 6.10.3 (Downgrades, Completion, Restoration, Ordinary Mutations & Recurrence):**
  * Specify in Section 6.3 that the `Focus -> Ready` downgrade target position and `priority` matching are computed against the executable tasks $E_{\text{ctx}}$ of the active filter context (`activeLabelId`), placing the task immediately after the 7th task in $E_{\text{ctx}}$ when $|E_{\text{ctx}}| \ge 7$ (so it occupies slot 8 of `Ready`) and after the last task in $E_{\text{ctx}}$ when $1 \le |E_{\text{ctx}}| < 7$ rather than at the global end of `queue`.
  * Specify in Sections 6.4 and 6.10.3 that completing a `repeat` task with `due` present advances `oldDue` by the smallest multiple $k \ge 1$ of `<count> <unit>` in local calendar space until `newDue > now`, and updates `suspended` by advancing `oldSuspended` by the same local multiple $k \times \text{<count> <unit>}$ when `oldSuspended < oldDue` (using `<repeat-time>` when non-midnight or preserving `oldSuspended`'s local clock otherwise; or setting `suspended` to the start of `newDue`'s local calendar date at `<repeat-time>` / `00:00:00` local time when `oldSuspended` is omitted or `oldSuspended >= oldDue`).
  * Specify in Section 6.5 that restoring a completed task removes `finished`, `suspended`, and `due`.
  * Specify in Section 6.6 that setting, updating, or clearing `due` converts local input under Section 6.10, advances `task.modified`, and preserves `queue` membership and order unchanged.
* **Section 6.7 & Section 6.8 (Synchronization, Three-Way Merge & Deletions):**
  * Section 6.7.2 & 6.7.7: Normative SHA-256 `sourceDigest` CAS-merge loop (`MAX_CAS_RETRIES = 3`, updating `sourceDigest`, `B`, and `L` before each retry) and atomic temp-file swap.
  * Section 6.7.3 & 6.7.5: Update `Label payload` tuple to `(scoped, name, note, color, condition)` and merge `scoped` as an independent boolean scalar; update `Task state` tuple to `(completions, priority, finished, suspended, due, repeat, blocked, subtasks)` and unbundle same-occurrence task fields (`priority`, `suspended`, `due`, `repeat`, `blocked`, `subtasks`) when `B.completions == L.completions == R.completions` and `finished` is absent; merge `blocked` per `targetId` as a key-value map; merge `subtasks` step booleans per index when step text lists match.
  * Section 6.7.8, 6.8.1 & 6.8.2: Global-view flood protection (remove task from `queue` and strip `priority` while preserving `suspended` whenever a `scoped` label deletion — via explicit delete, `Delete` conflict resolution, or three-way merge — leaves a previously global-view-restricted task with $L_{\text{after}}(T) = \varnothing$, using deterministic merge revisions during Section 6.7.8); preserve the assigning side's live `label` block and elevate concurrent label assignments ($A_L(T) \cup A_R(T)$ on existing or newly created tasks) targeting a deleted label to `DeletionConflict`.
* **Section 7.1 (Canonical Output Validation):**
  * Mandate canonical root-block ordering (`tdf 0.6.0`, `deleted`, `queue`, `label` blocks sorted by ascending ASCII `<label-id>`, `task` blocks sorted by ascending ASCII `<task-id>`) and the updated 14-position (or 15-position) `task` directive order.
* **Section 10 (Version Import and Implementation Migrations):**
  * Section 10.1.1 & 10.2: Add `0.5.1` snapshot reference to the historical schema table, extend the adjacent migration chain to `0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0 -> 0.5.1 -> 0.6.0`, and clarify that all historical schemas (`0.2.0`–`0.5.1`) count decoded Unicode scalar values for text limits.
  * Section 10.7 & 10.8: Add adjacent migration and load-time conversion step `0.5.1 -> 0.6.0` as Section 10.7 (with chained in-memory load-time conversion `0.5.0 -> 0.5.1 -> 0.6.0` for `0.5.0` files), and renumber `Migration from the Initial Draft` to Section 10.8.

### 2.2 Conformance Suite Structure (`spec/conformance/v0.6.0/`)
* `spec/conformance/v0.6.0/parse_valid/` — Valid `.tdf` files with expected canonical `.tdf` (including ASCII-sorted `label` and `task` root blocks) and normalized JSON models.
* `spec/conformance/v0.6.0/parse_invalid/` — Invalid `.tdf` files with `manifest.json` (`error`, `line`).
* `spec/conformance/v0.6.0/bounds/` — Supplementary Unicode scalar values (`> U+FFFF`), combining marks, and canonical output expansion (`LimitExceeded`).
* `spec/conformance/v0.6.0/merge/` — JSON vectors for same-occurrence unbundled merges, `blocked` map merges, step-wise `subtasks` merges, `scoped` label deletion queue eviction, and `DeletionConflict` on newly assigned deleted labels.
* `spec/conformance/v0.6.0/timezone/` — JSON vectors for DST conversions and `repeat` + `due` + `suspended` local-calendar interval advancement across DST boundaries.
* `spec/conformance/v0.6.0/migration/` — Adjacent and chained import vectors (`0.2.0` through `0.6.0`).

### 2.3 Resolved Design Clarifications & Remaining Confirmation Before `planned`
1. **Topic 2 (`repeat` + `due` when `suspended` is omitted — Resolved):** When a recurring task has `repeat` and `due`, but `suspended` is omitted (or `oldSuspended >= oldDue`), completing the occurrence advances `due` to `newDue` and sets `suspended` to the start of `newDue`'s local calendar date (at `<repeat-time>` if non-midnight, otherwise `00:00:00` local time, clamped to `newDue`). When `oldSuspended < oldDue`, both `oldDue` and `oldSuspended` advance by the same multiple $k \ge 1$ of `<count> <unit>` in local calendar space (using `<repeat-time>` when non-midnight or preserving `oldSuspended`'s local clock otherwise) so DST transitions and canonical serialization round-trips never shift the local wake-up clock.
2. **Topic 3 (`origin` Directive):** Confirm whether `origin "<namespace>" "<external-key>"` (`0..1`) should be included in `0.6.0` or deferred in favor of the `0.5.1` `link` deduplication convention.
3. **Transition to `status: planned`:** Once Point 2 is confirmed, `TEP-003` can transition directly to `status: planned` to draft the normative edits to `TDF_SPEC.md`.

### 2.4 Testing Strategy (Future Implementation Phase)
* Execute all machine-readable conformance fixtures (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`, `M-DELIM-INJECT-TESTS`, `M-IO-TESTS`) against the parser, serializer, evaluator, reconciler, and repositories following **`tdf-spec-workflow`** and **`tiertask-dev-workflow`**.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [x] Collect initial user thoughts (Topics 1–6) and supplementary specification proposals (Topics 7–11) into `TEP-003` (`status: concept`).
- [x] Incorporate prioritization, architectural refinements, and the 5 specification mechanisms (canonical root-block sorting, DST-safe local-calendar `repeat` + `due` + `suspended` advancement, `blocked` map merge, `scoped` label deletion flood protection across commands and merges, and active-filter-relative downgrade anchors).
- [x] Resolve the 7 edge cases in `TEP-003` (CAS retry loop state update, DST-safe local calendar lead window and omitted-`suspended` fallback, three-way merge `scoped` flood protection, $< 8$ filtered downgrade anchor, newly created task label conflict set $A_X(T)$, independent `scoped` boolean scalar merge, and editorial cleanup in Section 2.3).
- [x] Audit `TEP-003` against `TDF_SPEC.md` and fix editorial remnants, EBNF/section-numbering mismatches, payload tuple order, $|E_{\text{ctx}}| \ge 7$ downgrade slot math, canonical midnight `<repeat-time>` invariance, `suspended` preservation and deterministic merge revisions on `scoped` flood protection, live `label` retention on `DeletionConflict`, and Section 6.6 `due` mutation rules.
- [ ] Confirm Point 2 in Section 2.3 (`origin` directive vs. `0.5.1` convention) and transition `TEP-003` to `status: planned`.
- [ ] Draft normative `TDF_SPEC.md` `0.6.0` changes and machine-readable conformance vectors.

### 3.2 Work Log & Decisions
* **2026-11-08:** Created `TEP-003` in `concept` status to collect and structure specification ideas for TDF `0.6.0`.
* **2026-11-08:** Refined `TEP-003` with core vs. restrained scope prioritization and integrated five specification mechanisms.
* **2026-11-08:** Resolved seven edge cases in `TEP-003`: (1) updated `sourceDigest = diskDigest`, `B = R`, and `L = M` before each CAS retry iteration in Section 1.4.1; (2) defined idempotent local-day start fallback when `oldSuspended` is omitted on a recurring task with `due`; (3) replaced raw UTC-second $\Delta$ subtraction with DST-safe $k \times \text{<count> <unit>}$ local calendar advancement in Section 1.4.2; (4) extended `scoped` label deletion flood protection to three-way merge reconciliation in Section 1.4.6; (5) anchored `Focus -> Ready` downgrades with $1 \le |E_{\text{ctx}}| < 7$ after the last executable task in the active filter context rather than the global end of `queue`; (6) defined $A_X(T)$ to cover newly created tasks ($T \notin B$) in Section 1.4.5 and specified independent boolean scalar merging for `label` `scoped` in Sections 1.4.6 and 1.4.7; and (7) cleaned up Section 2.3.
* **2026-11-08:** Audited `TEP-003` against `TDF_SPEC.md` and resolved all editorial leftovers, EBNF non-terminal names (`label-block`, `due-dir`), Section 10.7/10.8 numbering and `0.5.1` historical schema entry, Section 6.7.3 payload tuple positions for `scoped` and `due`, $|E_{\text{ctx}}| \ge 7$ downgrade slot-8 placement and `priority` anchor matching, canonical midnight `<repeat-time>` invariance, preservation of `suspended` and deterministic merge revisions during `scoped` flood-protection queue eviction, live `label` preservation for `DeletionConflict`, and Section 6.6 `due` mutation rules.

### 3.3 Delivered Artifacts
*(Pending concept finalization and specification phase)*
