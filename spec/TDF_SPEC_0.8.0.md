# TierTask Data Format (TDF) Specification

**Version:** 0.8.0
**Status:** Working draft
**File Extension:** `.tdf`
**Character Encoding:** UTF-8

This working draft defines the TierTask Data Format (`TDF`) version `0.8.0`. Sections 1 through 13 and Appendix A are normative unless explicitly marked `*(Informative)*`. Appendix B is informative except for the byte-exact canonical test vector (`Vector 4`) in Appendix B.1.

## Table of Contents

- [1. Scope, Terminology, and Conformance](#1-scope-terminology-and-conformance)
  - [1.1 Purpose and Design Principles](#11-purpose-and-design-principles)
  - [1.2 Normative Conventions and Rule Identifiers](#12-normative-conventions-and-rule-identifiers)
  - [1.3 Conformance Roles](#13-conformance-roles)
  - [1.4 Version Compatibility](#14-version-compatibility)
  - [1.5 Introductory Example *(Informative)*](#15-introductory-example-informative)
- [Part A: Format and Document Model](#part-a-format-and-document-model)
  - [2. Document Model and Invariants](#2-document-model-and-invariants)
  - [3. Lexical Syntax and Structural Grammar](#3-lexical-syntax-and-structural-grammar)
  - [4. Primitive Value Types](#4-primitive-value-types)
  - [5. Entity and Directive Reference](#5-entity-and-directive-reference)
  - [6. Validation and Resource Bounds](#6-validation-and-resource-bounds)
  - [7. Canonical Serialization](#7-canonical-serialization)
- [Part B: Task Behavior](#part-b-task-behavior)
  - [8. Evaluation Context and Time Interpretation](#8-evaluation-context-and-time-interpretation)
  - [9. Tier Derivation](#9-tier-derivation)
  - [10. Mutations and Lifecycle Transitions](#10-mutations-and-lifecycle-transitions)
- [Part C: Synchronization and Persistence](#part-c-synchronization-and-persistence)
  - [11. Synchronization Model and Phase Overview](#11-synchronization-model-and-phase-overview)
  - [12. Reconciliation Rules](#12-reconciliation-rules)
  - [13. Guarded Publication, Retention Pruning, and Recovery](#13-guarded-publication-retention-pruning-and-recovery)
- [Appendix A: Error Index, Conformance Vector Index, and Rule ID Index](#appendix-a-error-index-conformance-vector-index-and-rule-id-index)
- [Appendix B: Explanatory Examples and Design Rationale *(Informative)*](#appendix-b-explanatory-examples-and-design-rationale-informative)

## 1. Scope, Terminology, and Conformance

The TierTask Data Format (`TDF`) is a deterministic, line-oriented, block-based plain-text data format for representing tasks, checklists, prerequisite dependencies, label contexts, reusable geofence locations, activation conditions, deadlines, machine correlation keys, reference links, chronological task history, recent deletion records, and the shared scheduling order. It combines human readability in standard text editors with structured `{ ... }` blocks and single-line directives.

This specification is organized into three normative parts:

| Part | Guiding Question | Scope |
| :--- | :--- | :--- |
| [Part A: Format and Document Model](#part-a-format-and-document-model) (Sections 2–7) | Which `.tdf` byte sequences are valid, what logical values do they denote, and how are they serialized canonically? | Logical model, lexical tokens, structural grammar, primitive types, entity/directive syntax, bounds, and canonical output |
| [Part B: Task Behavior](#part-b-task-behavior) (Sections 8–10) | How do evaluation and user commands interpret and change a document? | Evaluation context, 6-tier derivation, revisions, cleanup matrix, local calendar arithmetic, and atomic mutations |
| [Part C: Synchronization and Persistence](#part-c-synchronization-and-persistence) (Sections 11–13) | How are concurrent edits reconciled and published safely across processes and devices? | Reconciliation contract, baseline, merge rules, tombstones, conflicts, guarded publication, retention, and recovery |

### 1.1 Purpose and Design Principles

1. **Data vs. View Separation:** A `.tdf` document stores factual entity state, recent deletion records (`deleted`), and the shared open-task scheduling order (`queue`). It stores no explicit tier number (`[1]` through `[6]`) on any task; all six operational tiers (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`) are derived dynamically under [Section 9](#9-tier-derivation).
2. **No Empty Directives:** Optional directives that have no value (`finished`, `suspended`, `due`, `origin`, `link`, `history`, `note`, `color`, `source`, `modified`, `labels`, `blocked`, `repeat`, `completions`) MUST be omitted rather than written with zero arguments.
3. **Single-Pass Linear Grammar:** Conforming scanners and parsers tokenize and parse `.tdf` documents in a single $O(N)$ linear pass without regular expressions or backtracking.
4. **Two-Layer Validation:** Lexical and structural analysis scan identifiers and arguments as UTF-8 string tokens ([Section 3](#3-lexical-syntax-and-structural-grammar)); semantic and schema validation check types, value domains, resource bounds, and cross-block references ([Sections 4–6](#4-primitive-value-types)).

### 1.2 Normative Conventions and Rule Identifiers

#### Normative and Informative Text (`TDF-META-001`)

The key words `MUST`, `MUST NOT`, `REQUIRED`, `SHALL`, `SHALL NOT`, `SHOULD`, `SHOULD NOT`, `RECOMMENDED`, `NOT RECOMMENDED`, `MAY`, and `OPTIONAL` in this document are to be interpreted as described in BCP 14 ([RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174)) when, and only when, they appear in all capitals, as shown here. Lowercase uses of those words carry their normal English meaning.

Normative sections remain binding in full even where declarative sentences or mathematical definitions do not repeat uppercase BCP 14 keywords. Explanatory notes, illustrations, and sections marked `*(Informative)*` clarify intent or provide background rationale and never override normative rules or add hidden requirements. Normative test vectors in [Section 7.5](#75-normative-canonical-byte-and-sha-256-digest-vectors-tdf-ser-005), [Appendix A.2](#a2-conformance-vector-and-verification-suite-index-tdf-vec-001), and the canonical byte representation of [Appendix B.1](#b1-complete-canonical-document-example-tiertasktdf) are binding conformance requirements.

#### Stable Rule Identifiers (`TDF-META-002`)

Cohesive normative rules carry chapter-independent identifiers of the form `TDF-<AREA>-<NNN>` (for example, `TDF-EVAL-005` or `TDF-MERGE-010`), listed in [Appendix A.3](#a3-normative-rule-id-index-tdf-trace-001):

- Moving or renumbering sections in future revisions MUST NOT alter existing Rule IDs, and Rule IDs MUST NOT be reassigned to unrelated semantics.
- Error index entries ([Appendix A.1](#a1-structured-error-and-outcome-index-tdf-err-001)), conformance vectors ([Appendix A.2](#a2-conformance-vector-and-verification-suite-index-tdf-vec-001)), and enhancement proposals reference Rule IDs alongside section links.
- Semantics-preserving editorial refinements retain the existing Rule ID.

### 1.3 Conformance Roles

#### Role Obligations (`TDF-CONF-001`)

An implementation conforms to one or more of the roles below and MUST satisfy every normative section assigned to each claimed role without weakening any mandatory check, error code, or boundary condition:

| Role | Responsibility | Required Normative Sections |
| :--- | :--- | :--- |
| **Reader (Parser / Loader)** | Load a `.tdf` byte stream into the normalized in-memory document model without storage side effects or wall-clock cleanup. | Sections 1–6; Appendix A.1 |
| **Serializer** | Emit a normalized in-memory document model in byte-exact canonical `tdf 0.8.0` UTF-8 form and validate output resource bounds. | Sections 2, 4, 6, 7; Appendix A.1 |
| **Evaluator** | Compute the six operational tiers and active-pull ordering from an immutable decoded document model and evaluation context without mutating stored data or revisions. | Sections 2, 4, 5.2–5.5, 5.7, 8, 9; Appendix A.1.2 |
| **Mutating Client** | Execute user or API domain mutations, open-task cleanup, calendar scheduling, revision updates, and guarded atomic persistence. | All **Reader**, **Serializer**, and **Evaluator** sections, plus Sections 10 and 13; Appendix A.1–A.2 |
| **Reconciler (Synchronizing Client)** | Maintain durable baselines (`sourceDigest` / `ETag` and `acknowledgedGeneration`), reconcile concurrent edits, manage tombstones and conflicts, prune expired records, and execute guarded publication and recovery. | All **Mutating Client** sections, plus Sections 11–13; Appendix A.1–A.2 |

### 1.4 Version Compatibility

#### Version Handling Contract (`TDF-COMPAT-001`)

`tdf 0.8.0` is a standalone baseline format. No load-time version conversion or legacy import chain exists. Every conforming Reader MUST apply this single-version contract to the initial root statement:

| Initial Depth-`0` Statement | Required Behavior | Storage Effect During Load | Normative Reference |
| :--- | :--- | :--- | :--- |
| `tdf 0.8.0` (single unquoted argument) | Parse and validate directly under [Part A](#part-a-format-and-document-model). | None | [Section 5.1](#51-the-tdf-version-header-tdf-ent-001), [Section 6](#6-validation-and-resource-bounds) |
| Empty/comment-only input, first statement at depth `0` not `tdf <version>`, or bare `tdf` with zero arguments | Reject with `MissingVersionHeader`. | None | [Section 5.1](#51-the-tdf-version-header-tdf-ent-001), [Section 6.1](#61-validation-contract-and-deterministic-error-precedence-tdf-val-001) |
| Any `<version>` token other than unquoted `0.8.0` (including any `0.x.y` or other version token), quoted `"0.8.0"`, or extra header arguments | Reject with `UnsupportedVersion`. | None | [Section 5.1](#51-the-tdf-version-header-tdf-ent-001) |

### 1.5 Introductory Example *(Informative)*

The following short canonical `tdf 0.8.0` document declares one scheduled open task in `queue`, one `label`, and one prioritized `task` with a deadline and a two-step checklist (`453` UTF-8 bytes, `23` `LF`-terminated lines):

```text
tdf 0.8.0

queue {
    modified 2026-11-16 09:00:00
    task 8jKaCdOkD2
}

label 4x9p2mOkD2 {
    name  "Home"
    color "#4CAF50"
}

task 8jKaCdOkD2 priority {
    name     "Inspect heating pressure"
    created  2026-11-16 08:30
    modified 2026-11-16 09:00
    labels   4x9p2mOkD2
    due      2026-11-20 17:00:00 anchor 2026-11-20 18:00:00
    subtasks {
        step false "Check boiler gauge"
        step false "Bleed upstairs radiator"
    }
}
```

A comprehensive canonical example exercising every root block and directive (`tiertask.tdf`) appears in [Appendix B.1](#b1-complete-canonical-document-example-tiertasktdf).

## Part A: Format and Document Model

Part A specifies what constitutes a syntactically and semantically valid `tdf 0.8.0` document, the normalized logical data model it represents, its resource bounds, and its canonical UTF-8 byte serialization. Part A rules depend neither on wall-clock evaluation time `now` nor on conflict-resolution heuristics.

## 2. Document Model and Invariants

### 2.1 Processing Stages: Decoding, Evaluation, and Cleanup (`TDF-MODEL-001`)

Implementations MUST keep the three operations below strictly distinct:

| Operation | Purpose and Example | Mutates Domain State or Revisions? | Governing Sections |
| :--- | :--- | :--- | :--- |
| **1. Decoding and Normalization** | Unescape quoted strings, deduplicate and sort `labels` and `history`, coalesce `condition location` tokens, resolve structural defaults (such as omitted `completions -> 0`). | **No.** Strictly deterministic and independent of wall-clock `now`; preserves `sourceDigest` and raw explicit-vs-omitted `modified` presence. | [Sections 2–6](#2-document-model-and-invariants) |
| **2. Read-Only Evaluation** | Derive the six operational tiers against a captured UTC instant `now`, treating finite `suspended <= now` or missing/satisfied `blocked` entries as non-blocking and computing `hasEffectivePriority`. | **No.** Stored directives (`suspended`, `blocked`, `priority`, `passive`), `queue` order, and `modified` timestamps remain untouched. | [Sections 8–9](#8-evaluation-context-and-time-interpretation) |
| **3. State Cleanup During Mutation or Sync** | Strip expired finite `suspended <= now` (with its note) and resolved `blocked` entries from open tasks during a committed mutation or `cleanupMode = final` reconciliation, or prune `> 30`-day `Completed` tasks and `deleted` tombstones during guarded publication. | **Yes.** Modifies stored document state and updates `modified` timestamps or `deleted.generation` under explicit revision rules. | [Section 10.1](#101-mutation-contract-revisions-and-cleanup-matrix), [Sections 12–13](#12-reconciliation-rules) |

Because decoding is wall-clock-free, a conforming Reader MUST NEVER strip expired deferrals, remove satisfied prerequisites, prune completed tasks, or advance revisions while parsing or loading a file.

### 2.2 Entities, Containers, and Identity Namespaces

#### Namespaces and Cross-Part Container Split (`TDF-MODEL-002`)

A decoded TDF document consists of three independent entity maps and two singleton document-level containers:

1. **Disjoint Entity Namespaces (`task`, `label`, `location`):**
   - Each live `task`, `label`, or `location` block is identified by `(namespace, id)`, where `namespace` is `task`, `label`, or `location` and `id` is an immutable 10-character Base62 identifier.
   - The `task`, `label`, and `location` namespaces are completely disjoint: an identical 10-character Base62 token in two different namespaces identifies two distinct entities and is valid.
   - Within any single namespace, an ID MUST appear at most once across all live blocks and `deleted` records in the same document (`DuplicateIdentifier` on duplicate live blocks, duplicate deletion records, or a live block colliding with a deletion record in the same namespace).
2. **Singleton Document Containers (`deleted` and `queue`):**
   - `deleted` stores the document's monotonic deletion history `generation` and recent entity tombstones (`task`, `label`, `location`).
   - `queue` stores the single shared ordered list of scheduled open `<task-id>` references and a container-level UTC `modified` timestamp.
   - Across this specification, `deleted` and `queue` rules are partitioned by concern without duplicating their format definitions:
     - **Part A** ([Sections 5.6–5.7](#56-the-deleted-block-tdf-ent-005), [Section 6](#6-validation-and-resource-bounds), [Section 7](#7-canonical-serialization)) defines their syntax, decoded model, defaults, reference validity, and canonical serialization.
     - **Part B** ([Section 9](#9-tier-derivation), [Section 10](#10-mutations-and-lifecycle-transitions)) defines how `queue` membership and order govern active tiers vs. `Someday` and how lifecycle mutations update `queue` and create `deleted` records.
     - **Part C** ([Sections 11–13](#11-synchronization-model-and-phase-overview)) defines `queue` merging, tombstone retention, `DeletionConflict` resolution, `deleted.generation` comparison, and recovery.

#### Entity ID Generation and Lifetime Identity (`TDF-ID-001`)

Generate a new 10-character Base62 ID (`<6xBase62Random><4xBase62Time>`) **only** when creating a new `task`, `label`, or `location` entity ([Section 10.4.1](#1041-creating-entities-tdf-mut-003)) or explicitly recovering an ambiguous entity as new after tombstone expiry ([Section 13.3.2](#1332-recoveryrequired-resolution-and-new-identity-rewriting-tdf-rec-002)):

1. **6-Character Cryptographic Random Segment (`<6xBase62Random>`):** Select `6` independent characters uniformly at random from the 62-character Base62 alphabet (`0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz`) using a cryptographically secure random number generator ($62^6 = 56\,800\,235\,584$ combinations).
2. **4-Character Rolling UTC Seconds Segment (`<4xBase62Time>`):**
   - Take the current UTC timestamp in whole Unix seconds: `unixUtcSeconds = floor(nowUtcMilliseconds / 1000)`.
   - Compute `timeValue = unixUtcSeconds mod 14776336` ($62^4 = 14\,776\,336$, spanning a rolling ~171-day cycle at 1-second resolution).
   - Encode `timeValue` in Base62 as `4` characters, most significant digit first, left-padded with `0`.
3. **Concatenation:** Concatenate `<6xBase62Random>` and `<4xBase62Time>` into `<6xBase62Random><4xBase62Time>`.
4. **Uniqueness Check:** Reject any candidate ID already present in live entity blocks, entity references (`labels`, `blocked`, `condition location`, `queue`), or retained `deleted` records, and generate a fresh candidate until unique.
5. **Read-Only Loading Preservation:** Loading MUST preserve existing valid entity IDs and references verbatim and MUST NOT generate IDs, repair malformed identifiers, serialize documents, or write to storage.
6. **Lifetime Immutability:** An entity's ID MUST remain unchanged throughout its lifetime across loading, editing, serialization, Undelete, and synchronization.

### 2.3 Stored Facts, Derived Tiers, and Passive Metadata (`TDF-MODEL-003`)

- **Stored Facts vs. Derived Tiers:** Membership in `queue` is the sole stored indicator of whether an open task (`finished` absent) is scheduled into the active pull cycle or unscheduled (`Someday`, unless held in `Blocked` by an active `suspended` deferral). The six tiers (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`) are pure read-only projections computed from stored entity state, `queue`, and the evaluation context ([Section 9](#9-tier-derivation)).
- **Passive Non-Blocking Metadata:** `origin`, `task.link`, `label.link`, `history`, `due`'s local `anchor`, scheduling notes (`suspended` `"<note>"` and `due` `"<note>"`), and `location.source` are passive metadata. They NEVER classify a task as `Blocked`, NEVER alter `condition` evaluation, and NEVER reorder `queue` entries. (`due` itself never blocks a task; a non-`passive` `due` within the evaluation lead window $W_{\text{due}}$ contributes only to derived `hasEffectivePriority` on already eligible tasks in `queue` under [Section 9.4](#94-six-tier-classification-pipeline-tdf-eval-005).)

### 2.4 Collection Models, Absent Fields, and Defaults (`TDF-MODEL-004`)

Decoded fields use the normalized logical containers and absence defaults below:

| Construct | Logical Model | Default / Effective Value When Omitted |
| :--- | :--- | :--- |
| Optional scalar directives (`note`, `finished`, `suspended`, `due`, `repeat`, `origin`, `color`, `source`) | Optional value (`absent` vs. decoded value) | `absent` |
| Header and modifier flags (`task` `priority`, `label` `scoped`, `due` `passive`, `subtasks` `auto-finish`) | Boolean (`false` or `true`) | `false` |
| `task.completions` | Integer in `0..MAX_COMPLETIONS` | `0` |
| `task.labels` | Deduplicated set of `<label-id>`, ordered by ascending ASCII ID | Empty set (`∅`) |
| `task.blocked` | Map `targetTaskId -> requiredCompletion` (`1..MAX_COMPLETIONS`), retaining the greatest requirement on duplicate target IDs, ordered by ascending ASCII `targetTaskId` | Empty map (`∅`) |
| `blocked` `:<required-completion>` suffix | Positive integer in `1..MAX_COMPLETIONS` | `1` when `:suffix` is omitted on a present `<dependency>` token |
| `task.link` and `label.link` | Ordered list of `(decodedTitle, decodedUri)` pairs in preserved declaration order | Empty list (`[]`) |
| `task.history` | Deduplicated set/list of `(utcComponents, decodedText)` pairs sorted by ascending UTC epoch seconds, then ascending unsigned UTF-8 bytes of `decodedText` | Empty list (`[]`) |
| `task.subtasks` | Optional `(autoFinish, orderedSteps)` where `orderedSteps` is a non-empty list of `(completed, decodedText)` in declaration order (`absent` differs from a present checklist) | `absent` |
| `task.condition` and `label.condition` | `(globalAny, dayGroup, timeGroup, locationGroup)` where each group is `(resetAny, orderedRules)` and `locationGroup` coalesces all `<location-id>` tokens in first-seen declaration order | `globalAny = false`, all three groups `(resetAny = false, orderedRules = [])` |
| `repeat` optional `<repeat-time>` and `lead <N> days` | `localClock = (hour, minute, second)` and integer `leadDays` | `localClock = (0, 0, 0)` (`00:00:00` local) and `leadDays = 0` |
| `due` optional `anchor`, `passive`, and `"<note>"` | `(utcComponents, optionalLocalAnchorComponents, passive, optionalDecodedDueNote)` | When `due` is present: `optionalLocalAnchorComponents = absent`, `passive = false`, `optionalDecodedDueNote = absent` |
| `task.modified` | Explicit UTC timestamp or `absent` (retaining explicit-vs-omitted state) | Effective revision fallback: `max(created, finished)` in UTC ([Section 10.1.2](#1012-entity-and-queue-revision-rules-tdf-mut-002)) |
| `label.modified` and `location.modified` | Explicit UTC timestamp or `absent` (retaining explicit-vs-omitted state) | Effective revision fallback: `1970-01-01 00:00:00` UTC ([Section 10.1.2](#1012-entity-and-queue-revision-rules-tdf-mut-002)) |
| Root `deleted` block | `(generation, taskRecords, labelRecords, locationRecords)` keyed by `(namespace, id)` | `generation = 0`, all record maps empty |
| Root `deleted` `task` `<checkpoint>` | Integer in `0..MAX_COMPLETIONS` | `0` when omitted on a `deleted` `task` record |
| Root `queue` block | `(modified, orderedTaskIds)` | `modified = 1970-01-01 00:00:00` UTC, `orderedTaskIds = []` |

### 2.5 UTC Instants vs. Local Calendar Values (`TDF-MODEL-005`)

TDF distinguishes fixed points on the universal timeline from civil calendar values:

- **Stored UTC Instants:** `created`, `finished`, `modified` (on `task`, `label`, `location`, and `queue`), `due`'s primary deadline timestamp, `history` timestamps, finite `suspended` timestamps, and `deleted` record timestamps represent UTC instants in the proleptic Gregorian range `0001-01-01 00:00:00` through `9999-12-31 23:59:59` UTC. Parsing and serialization perform zero time-zone conversion on these fields.
- **Stored Local Calendar Values:** `due`'s optional `anchor <YYYY-MM-DD> [<HH:MM[:SS]>]` timestamp (`0001-01-01 00:00:00..9999-12-31 23:59:59` proleptic Gregorian local components), `repeat`'s `<repeat-time>` (`HH:MM[:SS]`), `condition day` weekdays, and `condition time` windows (`HH:MM`) represent civil wall-clock values in the user's configured time zone without stored UTC offsets or time-zone identifiers inside entity blocks.

[Section 8](#8-evaluation-context-and-time-interpretation) defines read-only evaluation of UTC instants and local calendar rules; [Section 10.2](#102-local-calendar-resolution-and-recurrence-calculation) defines local-to-UTC point resolution and recurrence calendar arithmetic.

### 2.6 Decoded Value Normalization and Structural Equality (`TDF-MODEL-006`)

Two `.tdf` representations denote equal entity or container values when their normalized decoded models are identical, ignoring comments, blank lines, horizontal spacing, root-block declaration order (except `queue` entry order), and input quote style (`"..."` vs. `'...'`):

- **Strings (`<text>`, `<note>`, `<uri>`):** Decode double-quoted escape sequences (`\"`, `\\`, `\n`, `\r`, `\t`) under [Section 3.3](#33-delimiters-identifiers-and-arguments-tdf-lex-003) and preserve exact Unicode scalar sequences without applying Unicode normalization (`NFC` or `NFD`) or collapsing `\r\n` / `\r` into `\n`.
- **Timestamps:** Expand every UTC `<timestamp>` into `(year, month, day, hour, minute, second)` (and equivalent UTC epoch seconds), and expand `due`'s optional local `anchor` `<timestamp>` into its six local calendar components `(year, month, day, hour, minute, second)` without time-zone conversion, defaulting an omitted clock to `00:00:00` and omitted seconds to `:00` ([Section 4.4](#44-booleans-weekdays-clocks-and-timestamps-tdf-type-004)).
- **Time Windows (`condition time`):** Represent each `<HH:MM>` endpoint as an integer minute of day (`hour * 60 + minute` in `0..1439`).
- **Recurrence (`repeat`):** Normalize to `(count, unit, localClock, leadDays)` with `localClock = (hour, minute, second)` (`(0, 0, 0)` when omitted) and `leadDays = 0` when `lead` is omitted.
- **Deferrals (`suspended`):** Normalize to `absent` when omitted, `(false, utcComponents, optionalDecodedSuspendedNote)` for finite UTC timestamps, and `(true, emptyList, optionalDecodedSuspendedNote)` for `forever`.
- **Deadlines (`due`):** Normalize to `absent` when omitted, or `(utcComponents, optionalLocalAnchorComponents, passive, optionalDecodedDueNote)` when present.
- **Origins (`origin`):** Normalize to `absent` when omitted, or `(decodedNamespace, decodedExternalKey)` when present.
- **History (`history`):** Deduplicate exact `(utcComponents, decodedText)` duplicates within the same `task` block and sort by ascending UTC epoch seconds, breaking ties by ascending unsigned UTF-8 byte order of `decodedText`.
- **Colors (`color`):** Normalize hexadecimal digits `a`–`f` to uppercase `A`–`F` (`"#RRGGBB"`).
- **Decimal Numbers (`coordinates`, `radius`):** Normalize each valid ASCII decimal literal (`-?[0-9]+(\.[0-9]+)?`) to canonical decimal text:
  1. Strip redundant leading integer zeros while keeping at least one integer digit (`007.5 -> 7.5`, `000 -> 0`).
  2. Strip trailing fractional zeros (`150.00 -> 150`, `50.978700 -> 50.9787`).
  3. Strip a trailing decimal point when no non-zero fractional digits remain.
  4. Preserve the `-` sign on non-zero negative values and normalize signed zero (`-0`, `-0.0`) to `0`.
- **Conditions (`condition`):** Normalize inline and block forms into `(globalAny, dayGroup, timeGroup, locationGroup)`:
  - Preserve rule declaration order within `dayGroup` (each rule holding its ordered `<weekday>` list) and `timeGroup` (each rule holding `(startMinute, endMinute)`).
  - Coalesce all `location <loc-1> [<loc-2> ...]` rules declared on the same `task` or `label` into a single ordered list of `<location-id>` tokens deduplicated in first-seen declaration order across the entity (`1..MAX_LOCATION_REFS_PER_ENTITY`).

Conflict-resolving lexicographic ordering over normalized entity payload tuples is used exclusively during synchronization winner selection and is defined in [Section 12.2.1](#1221-conflict-resolving-payload-tuple-order-tdf-merge-002).

## 3. Lexical Syntax and Structural Grammar

### 3.1 Character Encoding (`TDF-LEX-001`)

- Every `.tdf` document MUST be a valid UTF-8 byte sequence.
- Reject ill-formed UTF-8 byte sequences, null bytes (`U+0000`), and ASCII control characters (`U+0001`–`U+001F` and `U+007F`, except `U+0009` `HT`, `U+000A` `LF`, and `U+000D` `CR` where permitted below) before or during lexical scanning with `UnexpectedToken`.
- Scanners MUST respect UTF-8 code-point boundaries at all times.

### 3.2 Whitespace, Line Terminators, and Comments (`TDF-LEX-002`)

- **Horizontal Whitespace:** Outside quoted strings and comments, only ASCII Space (`U+0020`, `' '`) and ASCII Horizontal Tab (`U+0009`, `'\t'`) separate tokens on a line. Reject any non-ASCII Unicode whitespace character (such as `U+00A0`) outside quoted strings and comments with `UnexpectedToken`. Inside `#` comments, non-ASCII Unicode whitespace is valid comment text.
- **Line Terminators:** Each block header, directive, and closing brace is terminated by `LF` (`U+000A`, `"\n"`) or `CRLF` (`U+000D U+000A`, `"\r\n"`), with `EOF` also accepted on a standalone `tdf` version header, on the closing `}` line, or on a trailing empty/comment line. Reject a standalone `CR` (`U+000D`) not followed by `LF` outside double-quoted `\r` escapes with `UnexpectedToken`. Ignore empty lines (containing only optional horizontal whitespace and an optional `#` comment) anywhere in the input.
- **Comments:** `#` (`U+0023`) outside a quoted string starts a line or inline comment extending to (but excluding) the next `LF`, `CRLF`, or `EOF`. A `#` immediately following a bare word (such as `8jKaCdOkD2#note`) terminates the bare word (`8jKaCdOkD2`) and starts a comment. `#` inside `"..."` or `'...'` (such as `"#4CAF50"` or URI fragments) is literal content. Multi-line block comments do not exist. Comments remain subject to `TDF-LEX-001` UTF-8 and control-character checks (`U+0000` inside a comment produces `UnexpectedToken`).

### 3.3 Delimiters, Identifiers, and Arguments (`TDF-LEX-003`)

#### Reserved Punctuation

Outside quoted strings, five ASCII characters carry syntactic meaning: `{` (`U+007B`, opens block), `}` (`U+007D`, closes block), `#` (`U+0023`, starts comment), `"` (`U+0022`, delimits double-quoted string), and `'` (`U+0027`, delimits single-quoted literal string). Semicolons (`;`) are not statement terminators; a `;` in an unquoted token is part of that bare word.

#### Identifiers (Block and Directive Names)

The leading token of every block header or directive is an **Identifier**:

- MUST be an unquoted bare word (`InvalidIdentifier` if quoted).
- **Character set:** ASCII letters (`a-z`, `A-Z`), digits (`0-9`), underscore (`_`), and hyphen (`-`).
- **Start character:** MUST start with `a-z`, `A-Z`, or `_` (never `0-9` or `-`; `InvalidIdentifier` otherwise).

#### Argument Lexical Forms

Each argument passed to a block header or directive takes one of three forms (a `"` or `'` opening or closing mid-token without separating horizontal whitespace, such as `foo"bar"` or `"foo"bar`, MUST fail with `UnexpectedToken`):

1. **Bare Word (Unquoted Token):** One or more contiguous UTF-8 characters excluding `' '`, `'\t'`, `\r`, `\n`, ASCII control characters (`U+0000`–`U+001F`, `U+007F`), non-ASCII Unicode whitespace, and `{`, `}`, `#`, `"`, `'`. Used for Base62 IDs, header flags (`priority`, `scoped`, `auto-finish`), modifiers (`forever`, `anchor`, `passive`, `lead`, `days`, `weeks`, `months`), condition keywords (`day`, `time`, `location`, `any`), weekdays (`mon`..`sun`), booleans (`true`, `false`), numbers, and ISO-8601 date/clock tokens.
2. **Double-Quoted String (`"..."`):** Enclosed in `"` (`U+0022`). May contain horizontal whitespace, `#`, `{`, `}`, and `'`. Raw unescaped `\r`, `\n`, or `EOF` before the closing `"` MUST fail with `UnterminatedString`. Backslash (`\`, `U+005C`) introduces one of five escape sequences:
   - `\"` -> `U+0022` (`"`), `\\` -> `U+005C` (`\`), `\n` -> `U+000A` (`LF`), `\r` -> `U+000D` (`CR`), `\t` -> `U+0009` (`HT`).
   - Any other backslash escape sequence MUST fail with `InvalidEscapeSequence`.
3. **Single-Quoted String (`'...'`):** Enclosed in `'` (`U+0027`). Literal single-line string: `\` and `"` are literal characters with no escape processing. Raw `\r`, `\n`, or `EOF` before the closing `'` MUST fail with `UnterminatedString`.

### 3.4 Document Structure, Blocks, and Directives (`TDF-GRAM-001`)

1. **Nesting Depth (`0..MAX_NESTING_DEPTH`, `MAX_NESTING_DEPTH = 2`):**
   - **Depth `0` (Document Root):** Mandatory initial `tdf <version>` header ([Section 5.1](#51-the-tdf-version-header-tdf-ent-001)), followed by zero or more root blocks (`task`, `label`, `location`, `deleted`, `queue`), blank lines, and comments. Any directive at depth `0` after the initial `tdf` header (including a duplicate `tdf` directive) fails with `UnexpectedRootDirective`. Any `}` at depth `0` fails with `UnexpectedClosingBrace`.
   - **Depth `1` (Root Block Body):** Directives and permitted nested sub-blocks (`subtasks` and `condition` inside `task`; `condition` inside `label`). `location`, `deleted`, and `queue` forbid nested blocks (`UnknownBlockType`).
   - **Depth `2` (Sub-Block Body):** `step` inside `subtasks`, or `day`, `time`, and `location` inside `condition` (where `any <args...>` is recognized at depth `2` solely to reject parameterized global resets with `InvalidCondition`, zero-argument identifiers without `{` fail with `MissingDirectiveArgument`, and any other directive identifier outside `{day, time, location, any}` — including `condition any` or `condition day mon` — fails with `UnknownDirective`). Further nested `{` blocks at depth `2` exceed `MAX_NESTING_DEPTH = 2` and fail with `LimitExceeded` (after checking attached `{` -> `InvalidBlockHeader`).
2. **Block Framing:**
   - Syntax: `<identifier> [<argument> ...] {` on one line, zero or more body statements on subsequent lines, and `}` on its own logical line.
   - `{` MUST be separated from the preceding identifier or argument by at least one horizontal whitespace character (`InvalidBlockHeader` if attached, such as `task 8jKaCdOkD2{` or `condition{`).
   - Only optional horizontal whitespace and an optional `#` comment may follow `{` before the newline, or follow `}` before the newline/`EOF` (`UnexpectedToken` if non-comment tokens follow `{` or `}`, including single-line `{}`).
   - Reaching `EOF` while nesting depth `> 0` fails with `UnclosedBlock`.
   - Required body statements: `task` requires `name` and `created`; `label` requires `name`; `location` requires `name`, `coordinates`, and `radius`; `deleted` requires `generation`; `queue` requires `modified`; `subtasks` requires `>= 1` `step`; `condition { ... }` requires `>= 1` rule (`MissingRequiredDirective` otherwise).
3. **Directive Arity and Multiplicity:**
   - Every directive line has the form `<identifier> <argument> [<argument> ...]` (`>= 1` argument, `<= MAX_ARGS_PER_STMT = 64` arguments). A standalone identifier inside a block with zero arguments and no `{` fails with `MissingDirectiveArgument`.
   - **Singleton Directives and Blocks (`0..1` per scope, `DuplicateDirective` on repetition):**
     - Root blocks: `deleted`, `queue` (`0..1` per document); `subtasks` (`0..1` per `task`).
     - `task`: `name`, `note`, `created`, `finished`, `modified`, `completions`, `repeat`, `labels`, `blocked`, `suspended`, `due`, `origin`.
     - `label`: `name`, `color`, `note`, `modified`.
     - `location`: `name`, `note`, `source`, `coordinates`, `radius`, `modified`.
     - `deleted`: `generation`; `queue`: `modified`.
   - **Repeatable Directives (exempt from `DuplicateDirective` within their cardinality bounds):** `link` (`task`, `label`), `history` (`task`), `condition` (`task`, `label`), `step` (`subtasks`), `task`/`label`/`location` records (`deleted`), and `task` entries (`queue`).

### 3.5 Formal Grammar (EBNF) (`TDF-GRAM-002`)

```ebnf
(* Document Root: Mandatory Version Header followed by Blocks, Comments, and Blank Lines *)
document        = { empty-line } version-header { empty-line | root-block } [ trailing-empty ] ;

version-header  = ws* "tdf" ws+ "0.8.0" ws* [ comment ] ( newline | eof ) ;

root-block      = task-block
                | label-block
                | location-block
                | deleted-block
                | queue-block ;

queue-block     = ws* "queue" ws+ "{" ws* [ comment ] newline
                  { empty-line | queue-modified-dir | queue-task-dir }
                  ws* "}" ws* [ comment ] ( newline | eof ) ;

queue-modified-dir = ws* "modified" ws+ timestamp ws* [ comment ] newline ;
queue-task-dir  = ws* "task" ws+ task-id ws* [ comment ] newline ;

deleted-block   = ws* "deleted" ws+ "{" ws* [ comment ] newline
                  { empty-line | generation-dir | deleted-task-dir | deleted-label-dir | deleted-location-dir }
                  ws* "}" ws* [ comment ] ( newline | eof ) ;

generation-dir  = ws* "generation" ws+ bare-word ws* [ comment ] newline ;
deleted-task-dir = ws* "task" ws+ task-id ws+ timestamp [ ws+ completion-count ] ws* [ comment ] newline ;
deleted-label-dir = ws* "label" ws+ label-id ws+ timestamp ws* [ comment ] newline ;
deleted-location-dir = ws* "location" ws+ location-id ws+ timestamp ws* [ comment ] newline ;
timestamp       = date [ ws+ clock ] ;
date            = digit digit digit digit "-" digit digit "-" digit digit ;
clock           = digit digit ":" digit digit [ ":" digit digit ] ;
digit           = "0".."9" ;

(* Root & Sub-Blocks: task-block permits task directives (including link and history) and condition/subtasks blocks;
   label-block permits label directives (including link) and condition blocks *)
task-block      = ws* "task" ws+ task-id [ ws+ "priority" ] ws+ "{" ws* [ comment ] newline
                  { block-item }
                  ws* "}" ws* [ comment ] ( newline | eof ) ;

label-block     = ws* "label" ws+ label-id [ ws+ "scoped" ] ws+ "{" ws* [ comment ] newline
                  { block-item }
                  ws* "}" ws* [ comment ] ( newline | eof ) ;

location-block  = ws* "location" ws+ location-id ws+ "{" ws* [ comment ] newline
                  { empty-line | directive }
                  ws* "}" ws* [ comment ] ( newline | eof ) ;

block           = ws* identifier { ws+ argument } ws+ "{" ws* [ comment ] newline
                  { block-item }
                  ws* "}" ws* [ comment ] ( newline | eof ) ;

block-item      = empty-line
                | block
                | directive ;

(* Directives: Must contain at least one argument and end with a newline *)
directive       = labels-dir
                | blocked-dir
                | suspended-dir
                | due-dir
                | origin-dir
                | repeat-dir
                | history-dir
                | ws* link-directive ws* [ comment ] newline
                | ws* identifier ws+ argument { ws+ argument } ws* [ comment ] newline ;

labels-dir      = ws* "labels" ws+ label-id { ws+ label-id } ws* [ comment ] newline ;
blocked-dir     = ws* "blocked" ws+ dependency { ws+ dependency } ws* [ comment ] newline ;
dependency      = task-id [ ":" positive-count ] ;
completion-count = "0" | positive-count ;
positive-count  = "1".."9" { "0".."9" } ;
link-directive  = "link" ws+ ( quoted-string | single-string ) ws+ ( quoted-string | single-string ) ;
suspended-dir   = ws* "suspended" ws+ ( "forever" | timestamp ) [ ws+ ( quoted-string | single-string ) ] ws* [ comment ] newline ;
due-dir         = ws* "due" ws+ timestamp [ ws+ "anchor" ws+ timestamp ] [ ws+ "passive" ] [ ws+ ( quoted-string | single-string ) ] ws* [ comment ] newline ;
origin-dir      = ws* "origin" ws+ ( quoted-string | single-string ) ws+ ( quoted-string | single-string ) ws* [ comment ] newline ;
repeat-dir      = ws* "repeat" ws+ positive-count ws+ repeat-unit [ ws+ clock ] [ ws+ "lead" ws+ positive-count ws+ "days" ] ws* [ comment ] newline ;
repeat-unit     = "days" | "weeks" | "months" ;
history-dir     = ws* "history" ws+ timestamp ws+ ( quoted-string | single-string ) ws* [ comment ] newline ;

(* Entity Identifiers: Mandatory 10-Character Base62 Format *)
task-id         = base62-random base62-time ;
label-id        = base62-random base62-time ;
location-id     = base62-random base62-time ;
base62-random   = base62-char base62-char base62-char base62-char base62-char base62-char ;
base62-time     = base62-char base62-char base62-char base62-char ;
base62-char     = "0".."9" | "A".."Z" | "a".."z" ;

(* Lexical Tokens *)
identifier      = id-start { id-continue } ;
id-start        = "a".."z" | "A".."Z" | "_" ;
id-continue     = id-start | "0".."9" | "-" ;

argument        = quoted-string
                | single-string
                | bare-word ;

bare-word       = bare-char { bare-char } ;
bare-char       = ? any UTF-8 char except ASCII control chars (U+0000..U+001F, U+007F),
                    whitespace, '{', '}', '#', '"', '\'' ? ;

quoted-string   = '"' { quoted-char | escape-seq } '"' ;
quoted-char     = ? any UTF-8 char except '"', '\\', '\r', '\n', and ASCII control chars
                    (U+0000..U+001F except '\t', U+007F) ? ;
escape-seq      = "\\" ( '"' | "\\" | "n" | "r" | "t" ) ;

single-string   = "'" { single-char } "'" ;
single-char     = ? any UTF-8 char except '\'', '\r', '\n', and ASCII control chars
                    (U+0000..U+001F except '\t', U+007F) ? ;

(* Whitespace & Comments *)
empty-line      = ws* [ comment ] newline ;
trailing-empty  = ws* [ comment ] eof ;
comment         = "#" { ? any UTF-8 char except '\r', '\n', and ASCII control chars
                          (U+0000..U+001F except '\t', U+007F) ? } ;
ws              = " " | "\t" ;
newline         = "\n" | "\r\n" ;
```

## 4. Primitive Value Types

All block headers and directives reference the primitive value types defined in this section rather than repeating lexical, length, or escape rules per directive.

### 4.1 Unicode Scalar Length Measurement (`TDF-TYPE-001`)

Measure all text, note, and URI length bounds (`MAX_TEXT_LENGTH`, `MAX_NOTE_LENGTH`, `MAX_URI_LENGTH`) in **decoded Unicode scalar values** after escape decoding:

- A Unicode scalar value is any code point in `U+0000..U+10FFFF` outside the UTF-16 surrogate range `U+D800..U+DFFF`.
- Count each combining mark (`U+0301`, etc.) as a separate scalar value.
- Count each supplementary character (`> U+FFFF`) as `1` scalar value.
- Do NOT count UTF-8 bytes, UTF-16 code units, or extended grapheme clusters, and do NOT apply Unicode normalization (`NFC` or `NFD`) before counting.

### 4.2 Versions and Base62 Entity Identifiers (`TDF-TYPE-002`)

- **Version (`<version>`):** Unquoted semantic version bare word `<MAJOR>.<MINOR>.<PATCH>` of non-negative ASCII decimal integers (`0.8.0`; see [Section 1.4](#14-version-compatibility)).
- **Base62 Alphabet (`<base62-char>`):** The `62` ASCII alphanumeric characters in canonical index order `0..61`:
  `0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz` (`0-9`, `A-Z`, `a-z`).
- **Entity Identifiers (`<task-id>`, `<label-id>`, `<location-id>`):** Unquoted 10-character Base62 bare word matching `[0-9A-Za-z]{10}` (`<6xBase62Random><4xBase62Time>` when newly generated under `TDF-ID-001`, such as `8jKaCdOkD2`, `4x9p2mOkD2`, `7pQr9mOkD2`). Any quoted or non-`[0-9A-Za-z]{10}` entity ID component in a block header, `labels`, `blocked`, `condition location`, `queue`, or `deleted` statement MUST fail with `InvalidIdentifier` without generating a replacement.

### 4.3 Single-Line Text and Multi-Line Notes (`TDF-TYPE-003`)

- **Single-Line Text (`<text>`):** Quoted string (`"..."` or `'...'` in input; double-quoted `"..."` canonically) containing `1..MAX_TEXT_LENGTH` (`500`) decoded Unicode scalar values. Used by `task.name`, `label.name`, `location.name`, `location.source`, `subtasks` `step` `<text>`, `link` `<title>`, `origin` `"<namespace>"` and `"<external-key>"`, and `history` `"<text>"`. Evaluate validation checks in this exact precedence order:
  1. Unknown backslash escape sequences in `"..."` fail at the lexical layer with `InvalidEscapeSequence` (`TDF-LEX-003`).
  2. **Single-line & surrogate check (before emptiness):** If the decoded string contains `LF` (`\n`, `0x0A`), `CR` (`\r`, `0x0D`), `HT` (`\t`, `0x09` — whether via `\t` escape or literal tab inside quotes), or an unpaired UTF-16 surrogate (`U+D800..U+DFFF`), fail with `UnexpectedToken`.
  3. **Emptiness check:** If the decoded string is `""` or contains only ASCII spaces (`0x20`), fail with `EmptyText` (non-ASCII Unicode whitespace such as `U+00A0` counts as graphic content).
  4. **Length bound:** If decoded length exceeds `MAX_TEXT_LENGTH` (`500`) scalar values, fail with `LimitExceeded`.
- **Multi-Line Note (`<note>`):** Quoted string (`"..."` or `'...'` in input; emitted canonically on a single physical `.tdf` line as `"..."` with `\"`, `\\`, `\n`, `\r`, `\t` escapes) containing `1..MAX_NOTE_LENGTH` (`2000`) decoded Unicode scalar values without `\r\n` / `\r` -> `\n` collapsing. Used by `task.note`, `label.note`, `location.note`, `suspended` `"<note>"`, and `due` `"<note>"`. Escaped `\n`, `\r`, `\t` and literal horizontal tabs are permitted. Evaluate checks in this exact precedence order:
  1. Unknown backslash escapes in `"..."` fail with `InvalidEscapeSequence`.
  2. Unpaired UTF-16 surrogates (`U+D800..U+DFFF`) fail with `UnexpectedToken` (checked before emptiness).
  3. If the decoded string is `""` or contains only ASCII whitespace characters (`0x20`, `\t` `0x09`, `\n` `0x0A`, `\r` `0x0D`), fail with `EmptyText` (non-ASCII Unicode whitespace such as `U+00A0` counts as graphic content).
  4. If decoded length exceeds `MAX_NOTE_LENGTH` (`2000`) scalar values, fail with `LimitExceeded`.

### 4.4 Booleans, Weekdays, Clocks, and Timestamps (`TDF-TYPE-004`)

- **Boolean (`<bool>`):** Exact case-sensitive unquoted bare word `true` or `false` (`InvalidBoolean` otherwise).
- **Weekday (`<weekday>`):** Exact case-sensitive lowercase unquoted bare word in `{mon, tue, wed, thu, fri, sat, sun}` (`InvalidCondition` inside `condition day` otherwise).
- **Time of Day (`<time>`):** Unquoted 24-hour minute-precision local clock `<HH:MM>` (`00..23` hours, `00..59` minutes, such as `08:00` or `20:00`), used in `condition time <start> <end>` (`start != end`; `InvalidCondition` if quoted, malformed, or `start == end`).
- **Repeat Clock (`<repeat-time>`):** Unquoted 24-hour local clock `HH:MM` or `HH:MM:SS` (`00..23` hours, `00..59` minutes, `00..59` seconds, omitted `:SS` defaulting to `:00`; `InvalidTime` if quoted or outside `00:00:00..23:59:59`).
- **Timestamp (`<timestamp>`):** Proleptic Gregorian ISO-8601 date with optional 24-hour clock, written as `1` or `2` unquoted bare words:
  - Date-only (`1` token): `<YYYY-MM-DD>` (defaults to `00:00:00`).
  - Date and clock (`2` whitespace-separated tokens): `<YYYY-MM-DD> <HH:MM[:SS]>` (minute precision `<HH:MM>` defaults to `:00` seconds).
  - **Calendar & Supported Range:** Four-digit ASCII years in `0001..9999` (reject year `0000` or `>= 10000`), months `01..12`, valid calendar day `DD` for `(YYYY, MM)` under proleptic Gregorian leap-year rules (`divisible by 4`, except century years not `divisible by 400`, so `2000-02-29` is valid and `1900-02-29` is invalid), hours `00..23`, minutes `00..59`, seconds `00..59`. Valid range is `0001-01-01 00:00:00` through `9999-12-31 23:59:59` inclusive for all stored UTC instants, `due` local `anchor` timestamps, and local calendar conversion/recurrence arithmetic. Any quoted leading token, malformed date/clock, or out-of-range input or arithmetic result MUST fail with `InvalidTimestamp` (aborting the entire mutation without partial changes).

### 4.5 Numbers, Colors, and URIs (`TDF-TYPE-005`)

- **Decimal Number (`<number>`):** Unquoted finite ASCII decimal token matching `-?[0-9]+(\.[0-9]+)?`:
  - Raw ASCII token length `> MAX_NUMBER_LENGTH` (`24` characters) MUST fail with `LimitExceeded`.
  - Quoted tokens, `NaN`, `Infinity`, `-Infinity`, leading `+`, scientific notation (`1e5`, `1E-3`), or any other malformed token MUST fail with `InvalidNumber` (unless directive arity rules specify `UnexpectedToken` for quoted coordinates/radius).
  - **Coordinate & Radius Precision:** After decimal normalization (`TDF-MODEL-006`), `location` `<lat>` (`[-90.0, 90.0]`) and `<lon>` (`[-180.0, 180.0]`) in `tdf 0.8.0` MUST have at most **6 non-zero fractional digits** (`InvalidNumber` if out of range or `> 6` fractional digits), and `<radius>` MUST have at most **2 non-zero fractional digits** with $0 < \text{meters} \le \text{MAX\_LOCATION\_RADIUS}$ (`100_000`; `InvalidNumber` if `<= 0` or `> 2` fractional digits; `LimitExceeded` if `> 100_000`).
- **Hexadecimal Color (`<color>`):** Quoted 7-character string `"#RRGGBB"` or `'#RRGGBB'` where each `R`, `G`, `B` is in `0-9`, `a-f`, `A-F` (`InvalidColor` otherwise; quoting is mandatory because unquoted `#` begins a comment).
- **URI (`<uri>`):** Quoted string (`"..."` or `'...'` in input; double-quoted `"..."` canonically) used as the second argument of `link "<title>" "<uri>"`. Evaluate validation checks in this exact precedence order:
  1. Unknown backslash escapes in `"..."` fail with `InvalidEscapeSequence`.
  2. Unpaired UTF-16 surrogates (`U+D800..U+DFFF`) fail with `UnexpectedToken`.
  3. **Emptiness check (before scheme check):** If decoded `<uri>` is `""` or contains only ASCII whitespace (`0x20`, `\t`, `\n`, `\r`), fail with `EmptyText` (non-ASCII Unicode whitespace such as `U+00A0` counts as graphic content).
  4. **Length bound:** If decoded length exceeds `MAX_URI_LENGTH` (`2048`) scalar values, fail with `LimitExceeded`.
  5. **Control-character & scheme check:** If decoded `<uri>` contains `\n` (`0x0A`), `\r` (`0x0D`), `\t` (`0x09`), or any other ASCII control character, lacks a scheme prefix matching `[a-zA-Z][a-zA-Z0-9+.-]*:` (such as `https://`, `http://`, `file://`, `mailto:`), or uses a forbidden executable or inline-payload scheme (`javascript:`, `vbscript:`, or `data:`, matched case-insensitively on the scheme prefix), fail with `InvalidUri`.
  - Parsing performs no filesystem existence or network reachability check so `file://` and custom-scheme links remain portable across operating systems.

### 4.6 Counters and Prerequisite References (`TDF-TYPE-006`)

- **Deletion History Generation (`<generation>`):** Unquoted canonical non-negative ASCII decimal integer in `0..MAX_SYNC_GENERATION` (`9_007_199_254_740_991`) without sign or leading zeros except `"0"` (`InvalidNumber` if quoted, signed, negative, leading-zero, or non-integer; `LimitExceeded` if `> MAX_SYNC_GENERATION`).
- **Completion Count (`<completion-count>`):** Unquoted canonical non-negative ASCII decimal integer in `0..MAX_COMPLETIONS` (`9_007_199_254_740_991`) without sign or leading zeros except `"0"` (`InvalidNumber` if invalid; `LimitExceeded` if `> MAX_COMPLETIONS`).
- **Prerequisite Reference (`<dependency>`):** Single unquoted token `<task-id>[:<required-completion>]`. The `<task-id>` prefix MUST satisfy `TDF-TYPE-002` (`[0-9A-Za-z]{10}`, `InvalidIdentifier` if quoted or malformed). When `:` is present, `<required-completion>` MUST be a canonical positive ASCII integer without sign or leading zeros in `1..MAX_COMPLETIONS` (`InvalidNumber` if `0`, signed, leading-zero, empty, or non-integer; `LimitExceeded` if `> MAX_COMPLETIONS`). Omitting `:suffix` means required completion `1`.

## 5. Entity and Directive Reference

At depth `0`, a `tdf 0.8.0` document MUST start with the `tdf` version header ([Section 5.1](#51-the-tdf-version-header-tdf-ent-001)), followed by zero or more root blocks from [Sections 5.2–5.4](#52-the-task-block-tdf-ent-002) and [5.6–5.7](#56-the-deleted-block-tdf-ent-005). Any other root directive produces `UnexpectedRootDirective`; any other root block produces `UnknownBlockType`. Simple scalar directives are defined completely in each entity's table via [Section 4](#4-primitive-value-types) types; complex directives receive dedicated subsections below. Canonical block and directive ordering is defined once in [Section 7](#7-canonical-serialization).

### 5.1 The `tdf` Version Header (`TDF-ENT-001`)

```text
tdf 0.8.0
```

- **Placement & Syntax:** MUST be the first statement at depth `0` (preceded only by optional blank lines and `#` comments) and takes the single unquoted `<version>` argument `0.8.0`.
- **Version Dispatch:** `0.8.0` is parsed and validated directly under [Part A](#part-a-format-and-document-model) with zero storage side effects ([Section 1.4](#14-version-compatibility)). No load-time version conversion or legacy import chain exists.
- **Errors:** Empty/comment-only file, first statement at depth `0` not `tdf <version>`, or bare `tdf` with zero arguments -> `MissingVersionHeader`; any `<version>` token other than unquoted `0.8.0` (including any `0.x.y` or other version token), quoted `"0.8.0"`, or extra header arguments -> `UnsupportedVersion`; second `tdf` statement later at depth `0` -> `UnexpectedRootDirective`.
- **Canonical Output:** Always emitted as `tdf 0.8.0\n` at byte offset `0` ([Section 7.2](#72-root-level-section-order-and-block-omission-tdf-ser-002)).

### 5.2 The `task` Block (`TDF-ENT-002`)

```text
task <task-id> [priority] {
    ...
}
```

- **Header Arguments:**
  1. `<task-id>` (**Required**, `<task-id>`): Unique task identity (`InvalidIdentifier` if quoted or not `[0-9A-Za-z]{10}`; `DuplicateIdentifier` if colliding with another `task` block or `deleted` `task` record).
  2. `priority` (**Optional**, bare-word flag, default `false`): When present, grants explicit priority in [Section 9.4](#94-six-tier-classification-pipeline-tdf-eval-005); when omitted, the task enters the effective-priority partition only while a non-`passive` `due` satisfies `isDueUrgent`.
  - Missing `<task-id>`, unknown flag, quoted `"priority"`, or extra header arguments MUST fail with `InvalidBlockHeader`.
- **Task Directives and Sub-Blocks Overview** (canonical 16-position output order is specified in [Section 7.3](#73-intra-block-directive-order-and-value-formatting-tdf-ser-003)):

| Directive / Sub-Block | Req. | Mult. | Syntax / Type ([Section 4](#4-primitive-value-types)) | Default & Domain Rules |
| :--- | :--- | :--- | :--- | :--- |
| `name` | Yes | `1` | `"<text>"` | Required task title (`MissingRequiredDirective` if absent; `1..MAX_TEXT_LENGTH` single-line `<text>`). |
| `note` | No | `0..1` | `"<note>"` | Optional standing description (`absent` when omitted; `1..MAX_NOTE_LENGTH` `<note>`). |
| `created` | Yes | `1` | `<timestamp>` (UTC) | Required UTC creation instant (`MissingRequiredDirective` if absent). |
| `finished` | No | `0..1` | `<timestamp>` (UTC) | Optional UTC completion instant (`absent` when omitted). When present, requires effective `completions >= 1` (`InvalidCompletionState` if `0`), forbids `queue` membership (`InvalidQueueMembership`), classifies task in `Completed` ([Section 9.4](#94-six-tier-classification-pipeline-tdf-eval-005)), and triggers `> 30`-day retention pruning during persistence ([Section 13.2](#132-thirty-day-retention-pruning-tdf-pub-004)). |
| `modified` | No | `0..1` | `<timestamp>` (UTC) | Optional UTC entity revision (`absent` when omitted; effective fallback `max(created, finished)` under [Section 10.1.2](#1012-entity-and-queue-revision-rules-tdf-mut-002)). |
| `completions` | No | `0..1` | `<completion-count>` | Monotonic completed-occurrence counter (default `0`; `InvalidCompletionState` if `finished` is present and effective `completions == 0`; `UnexpectedToken` if `>= 2` arguments; [Section 10.3](#103-completion-counters-and-prerequisite-arming-tdf-occ-001)). |
| `repeat` | No | `0..1` | `<count> <unit> [<repeat-time>] [lead <N> days]` | Local calendar recurrence rule (`absent` when omitted). Defined in [Section 5.2.1](#521-recurrence-and-preparation-lead-repeat-tdf-dir-001). |
| `labels` | No | `0..1` | `<label-id1> [<label-id2> ...]` | `1..MAX_ARGS_PER_STMT` unquoted `<label-id>` tokens (default `∅`). Each ID MUST match a declared `label` block (`InvalidIdentifier` if quoted/malformed; `UnknownLabelReference` if undeclared or tombstoned). Deduplicated into an ASCII-sorted set (`TDF-MODEL-006`). |
| `blocked` | No | `0..1` | `<dependency1> [<dependency2> ...]` | Stored prerequisite requirements (default `∅`). Defined in [Section 5.2.2](#522-prerequisite-dependencies-blocked-tdf-dir-002). |
| `suspended` | No | `0..1` | `(<timestamp> \| forever) ["<note>"]` | UTC deferral or indefinite lock with optional note (`absent` when omitted). Defined in [Section 5.2.3](#523-deferrals-and-deferral-notes-suspended-tdf-dir-003). |
| `due` | No | `0..1` | `<timestamp> [anchor <timestamp>] [passive] ["<note>"]` | Non-blocking UTC deadline with optional local anchor, `passive` opt-out, and note (`absent` when omitted). Defined in [Section 5.2.4](#524-deadlines-schedule-anchors-passive-flag-and-notes-due-tdf-dir-004). |
| `origin` | No | `0..1` | `"<namespace>" "<external-key>"` | Passive machine correlation key (`absent` when omitted). Defined in [Section 5.2.5](#525-machine-correlation-keys-origin-tdf-dir-005). |
| `link` | No | `0..20` | `"<title>" "<uri>"` | Repeatable reference link (`[]` when omitted; `MAX_LINKS_PER_TASK = 20`). Defined in [Section 5.2.6](#526-reference-links-link-tdf-dir-006). |
| `history` | No | `0..500` | `<timestamp> "<text>"` | Repeatable UTC journal entry (`[]` when omitted; `MAX_HISTORY_PER_TASK = 500` raw lines). Defined in [Section 5.2.7](#527-chronological-task-journal-history-tdf-dir-007). |
| `condition` | No | `0..512` | Inline rule/reset or `condition { ... }` | Task activation conditions and group/global resets. Defined in [Section 5.5](#55-activation-conditions-condition-tdf-dir-009). |
| `subtasks` | No | `0..1` | `subtasks [auto-finish] { step ... }` | Ordered checklist sub-block (`absent` when omitted). Defined in [Section 5.2.8](#528-checklist-sub-blocks-subtasks-tdf-dir-008). |

#### 5.2.1 Recurrence and Preparation Lead (`repeat`) (`TDF-DIR-001`)

1. **Purpose, Scope, and Multiplicity:** Schedules recurring task occurrences in local calendar arithmetic with an optional wake-up clock and optional calendar-day preparation lead offset before `due`. Valid inside `task` at depth `1` (`0..1`, `DuplicateDirective` on repetition).
2. **Syntax and Types:** `repeat <count> <days|weeks|months> [<repeat-time>] [lead <lead-count> days]` (`2..6` unquoted tokens; `<count>` and `<lead-count>` in `1..MAX_REPEAT_COUNT = 3650`; `<repeat-time>` as `<repeat-time>` in [Section 4.4](#44-booleans-weekdays-clocks-and-timestamps-tdf-type-004)).
3. **Decoded Value and Default:** `absent` when omitted; otherwise `(count, unit, localClock, leadDays)` with `localClock` defaulting to `(0, 0, 0)` (`00:00:00`) and `leadDays` defaulting to `0`. `lead <lead-count> days` is valid regardless of whether `due` is present on the task (preserving schema closure during independent Case 2 unit merges; Mode 1 ignores `leadDays` when `due` is omitted).
4. **Validation and Error Precedence:**
   - `0` arguments without `{` -> `MissingDirectiveArgument`; `{` follows `repeat` -> `UnknownBlockType`.
   - `1` argument (`repeat 1`) -> `UnexpectedToken`.
   - `args[0]` (`<count>`): unquoted canonical integer in `1..3650` (`InvalidNumber` if quoted, non-integer, signed, leading-zero, or `0`; `LimitExceeded` if raw length `> 24` or value `> 3650`).
   - `args[1]` (`<unit>`): exact unquoted `days`, `weeks`, or `months` (`UnexpectedToken` if quoted or any other token).
   - Optional `args[2]` when present and `!= "lead"`: validate as `<repeat-time>` (`InvalidTime` if quoted or invalid).
   - Remaining arguments after `<unit>` (or `<repeat-time>`), when non-empty: MUST begin with unquoted `lead` (`UnexpectedToken` otherwise) followed by **exactly `2` tokens** (`UnexpectedToken` if `< 2` or `> 2` tokens follow `lead`): `<lead-count>` (`1..3650`, same `InvalidNumber` / `LimitExceeded` rules as `<count>`) and exact unquoted `days` (`UnexpectedToken` if quoted or any other unit).
5. **Behavioral Cross-References:** Completion rescheduling in [Sections 10.2.2–10.2.3](#1022-mode-1-completion-relative-recurrence-due-omitted-tdf-cal-002) and [Section 10.4.4](#1044-completing-a-task-tdf-mut-006); ordinary edits in [Section 10.4.6](#1046-ordinary-directive-and-entity-mutations-tdf-mut-008); atomic unit merge and `V.repeat`-aware `blocked` pre-normalization in [Section 12.4.2](#1242-two-level-task-occurrence-merge-tdf-merge-010); canonical output in [Section 7.3](#73-intra-block-directive-order-and-value-formatting-tdf-ser-003).
6. **Examples:**
   - Valid: `repeat 1 months 09:00 lead 5 days`, `repeat 2 weeks lead 3 days`, `repeat 7 days`
   - Invalid: `repeat 0 days` (`InvalidNumber`), `repeat 1 months 25:00` (`InvalidTime`), `repeat 1 months lead 2 weeks` (`UnexpectedToken`)

#### 5.2.2 Prerequisite Dependencies (`blocked`) (`TDF-DIR-002`)

1. **Purpose, Scope, and Multiplicity:** Declares prerequisite task completion thresholds that must be reached before an open dependent task can enter `Focus`, `Ready`, or `Planned`. Valid inside `task` at depth `1` (`0..1`, `DuplicateDirective` on repetition).
2. **Syntax and Types:** `blocked <dependency1> [<dependency2> ...]` (`1..MAX_ARGS_PER_STMT = 64` `<dependency>` tokens `<task-id>[:<required-completion>]` under `TDF-TYPE-006`).
3. **Decoded Value and Default:** Empty map when omitted; otherwise `targetTaskId -> maxRequiredCompletion`, retaining the greatest required number if a `<task-id>` is repeated on the same line. Unknown forward-reference `<task-id>`s (absent from both live `task` blocks and `deleted` records) are valid, non-blocking, and preserved across parsing, loading, mutations, and synchronization.
4. **Validation and Error Precedence:**
   - `0` arguments without `{` -> `MissingDirectiveArgument`; `{` follows `blocked` -> `UnknownBlockType`; `> 64` arguments -> `LimitExceeded`.
   - Quoted token or malformed `<task-id>` prefix -> `InvalidIdentifier`; invalid `:<req>` suffix -> `InvalidNumber` or `LimitExceeded` (`TDF-TYPE-006`).
   - Direct self-dependency or indirect cycle across two or more `task` blocks (including already satisfied references) -> `CircularDependency` ([Section 6.3](#63-reference-integrity-completion-state-and-acyclicity-tdf-val-003)).
5. **Behavioral Cross-References:** Satisfaction check in [Section 9.3](#93-prerequisite-satisfaction-tdf-eval-004); arming/rearming in [Section 10.3](#103-completion-counters-and-prerequisite-arming-tdf-occ-001); cleanup predicates and matrix in [Section 10.1.3–10.1.4](#1013-open-task-block-reason-cleanup-predicates-tdf-clean-001); `V.repeat`-aware map merge in [Section 12.4.2](#1242-two-level-task-occurrence-merge-tdf-merge-010); 30-day tombstone expiry hygiene in [Section 13.2](#132-thirty-day-retention-pruning-tdf-pub-004); canonical output in [Section 7.3](#73-intra-block-directive-order-and-value-formatting-tdf-ser-003).
6. **Examples:**
   - Valid: `blocked 8jKaCdOkD2 5vWx9ZOk91:8`
   - Invalid: `blocked "8jKaCdOkD2"` (`InvalidIdentifier`), `blocked 8jKaCdOkD2:0` (`InvalidNumber`), `A -> B -> A` (`CircularDependency`)

#### 5.2.3 Deferrals and Deferral Notes (`suspended`) (`TDF-DIR-003`)

1. **Purpose, Scope, and Multiplicity:** Holds an open task in `Blocked` until a finite UTC instant passes or indefinitely (`forever`), optionally carrying a transient deferral reason `<note>`. Valid inside `task` at depth `1` (`0..1`, `DuplicateDirective` on repetition).
2. **Syntax and Types:** `suspended (<timestamp> | forever) ["<note>"]` (finite `<timestamp>` in UTC under `TDF-TYPE-004`; optional trailing `<note>` under `TDF-TYPE-003`).
3. **Decoded Value and Default:** `absent` when omitted; `(false, utcComponents, optionalDecodedNote)` for finite UTC timestamps; `(true, emptyList, optionalDecodedNote)` for `forever`.
4. **Validation, Ownership, and Diagnostic Redaction:**
   - `0` arguments without `{` -> `MissingDirectiveArgument`; `{` follows `suspended` -> `UnknownBlockType`.
   - `args[0]` quoted (`suspended "2026-11-11"` or `suspended "forever"`) -> `InvalidTimestamp`.
   - Any non-final argument (`1 <= i < args.length - 1`) quoted -> `UnexpectedToken`.
   - When `args[0] == "forever"`: `1` arg = valid; `2` args = `args[1]` MUST be a quoted `<note>` (`UnexpectedToken` if unquoted or unpaired surrogate, `EmptyText` if blank, `LimitExceeded` if `> 2000`); `>= 3` args -> `UnexpectedToken`.
   - When `args[0] != "forever"`: if `args.length >= 2` and `args.last` is quoted, validate `args[0 .. args.length - 2]` as a `1..2`-token UTC `<timestamp>` (`InvalidTimestamp` if `1..2` tokens are invalid, `UnexpectedToken` if `>= 3` bare tokens precede the note) and `args.last` as `<note>`; otherwise validate all `args` as a UTC `<timestamp>` (`InvalidTimestamp` on `1..2` invalid tokens, `UnexpectedToken` on `>= 3` tokens).
   - **Parent Coupling & Redaction:** A deferral `<note>` cannot exist without `suspended` and is cleared whenever `suspended` expires during cleanup, is cleared manually, moves to `Someday`, completes, recurs, or restores. Diagnostic logs MUST NOT emit raw `suspended` `<note>` text.
5. **Behavioral Cross-References:** UTC active evaluation (`forever` or `suspended > now`) in [Section 8.2](#82-utc-instants-versus-local-wall-clock-evaluation-tdf-ctx-002) and [Section 9.4](#94-six-tier-classification-pipeline-tdf-eval-005); cleanup matrix in [Section 10.1.4](#1014-cleanup-matrix-across-lifecycle-stages-tdf-clean-002); mutations in [Section 10.4.6](#1046-ordinary-directive-and-entity-mutations-tdf-mut-008); stage-gated Case 2 pre-normalization and atomic merge in [Section 12.4.2](#1242-two-level-task-occurrence-merge-tdf-merge-010); canonical output in [Section 7.3](#73-intra-block-directive-order-and-value-formatting-tdf-ser-003).
6. **Examples:**
   - Valid: `suspended 2026-11-04 23:00:00 "Wait for dry forecast"`, `suspended forever`
   - Invalid: `suspended "forever"` (`InvalidTimestamp`), `suspended forever unquoted` (`UnexpectedToken`)

#### 5.2.4 Deadlines, Schedule Anchors, Passive Flag, and Notes (`due`) (`TDF-DIR-004`)

1. **Purpose, Scope, and Multiplicity:** Records a non-blocking target deadline in UTC, optionally paired with an intended local calendar schedule `anchor` (preventing month-end `29..31` clamping drift and DST gap clock drift across recurring occurrences), an occurrence-scoped `passive` flag opting out of lead-window effective priority, and a deadline `<note>`. Valid inside `task` at depth `1` (`0..1`, `DuplicateDirective` on repetition).
2. **Syntax and Types:** `due <YYYY-MM-DD> [<HH:MM[:SS]>] [anchor <YYYY-MM-DD> [<HH:MM[:SS]>]] [passive] ["<note>"]`.
3. **Decoded Value and Default:** `absent` when omitted; when present, `(utcComponents, optionalLocalAnchorComponents, passive, optionalDecodedDueNote)`, with omitted `anchor -> absent`, omitted `passive -> false`, and omitted note `-> absent`. `anchor` is valid on `due` whether or not `repeat` is present, and TDF imposes **no** schema constraint requiring `suspended <= due` or time-zone agreement between `due` and `anchor`.
4. **Token Disambiguation, Ownership, and Diagnostic Redaction:**
   - `0` arguments without `{` -> `MissingDirectiveArgument`; `{` follows `due` -> `UnknownBlockType`.
   - `args[0]` quoted (`due "2026-11-11"`) -> `InvalidTimestamp`.
   - Any non-final argument (`1 <= i < args.length - 1`) quoted (such as `due 2026-11-11 "note" passive` or `due 2026-11-11 anchor "2026-11-11" passive`) -> `UnexpectedToken`.
   - If `args.length >= 2`, `args[args.length - 2] == "anchor"` (unquoted), and `args[args.length - 1]` is quoted (`due ... anchor "2026-11-11"`), fail with `InvalidTimestamp`.
   - Otherwise, set `end = args.length` and peel trailing modifiers from right to left:
     1. If `end >= 2` and `args[end - 1]` is quoted, record `rawNoteToken = args[end - 1]` and set `end -= 1`.
     2. If `end >= 2` and `args[end - 1] == "passive"` (unquoted), record `passive = true` and set `end -= 1`.
     3. If `end >= 2` and `args[end - 1] == "passive"` (duplicate `passive`), fail with `UnexpectedToken`.
     4. Scan `args[1 .. end - 1]` for unquoted `"anchor"`:
        - More than one `"anchor"` -> `UnexpectedToken`.
        - Exactly one `"anchor"` at `anchorIdx` (`1 <= anchorIdx < end`): if `"passive"` appears anywhere in `args[1 .. anchorIdx - 1]` (`due <ts> passive anchor <ts>`) or `args[anchorIdx + 1 .. end - 1]`, fail with `UnexpectedToken`. Let `dueSlice = args[0 .. anchorIdx - 1]` and `anchorSlice = args[anchorIdx + 1 .. end - 1]`. If `dueSlice.length >= 3`, `anchorSlice.isEmpty` (`due <ts> anchor`), or `anchorSlice.length >= 3`, fail with `UnexpectedToken`. Validate `dueSlice` (`1..2` bare tokens) as the UTC `<timestamp>` (`InvalidTimestamp` if invalid) and `anchorSlice` (`1..2` bare tokens) as the local calendar `<timestamp>` (`InvalidTimestamp` if invalid).
        - Zero `"anchor"` tokens: validate `args[0 .. end - 1]` as the UTC `<timestamp>` (`InvalidTimestamp` on `1..2` invalid tokens; `UnexpectedToken` if `end >= 3`).
     5. If `rawNoteToken` was recorded, validate it as `<note>` (`TDF-TYPE-003`).
   - **Parent Coupling & Redaction:** Neither `anchor`, `passive`, nor a deadline `<note>` can exist without `due`. Overdue `due <= now`, `anchor`, `passive`, and `due` notes remain intact on open tasks (and into `Completed` on standard tasks). Diagnostic logs MUST NOT emit raw `due` `<note>` text.
5. **Behavioral Cross-References:** Effective priority (`isDueUrgent`) in [Section 9.4](#94-six-tier-classification-pipeline-tdf-eval-005); Mode 2 anchor progression and `passive` reset in [Section 10.2.3](#1023-mode-2-schedule-anchored-recurrence-with-due-tdf-cal-003); downgrade `passive` setting in [Section 10.4.3](#1043-downgrading-active-tasks-focus-ready-planned-tdf-mut-005); restoration clearing in [Section 10.4.5](#1045-completed-checklists-and-restoring-from-completed-tdf-mut-007); setting/editing `due` in [Section 10.4.6](#1046-ordinary-directive-and-entity-mutations-tdf-mut-008); atomic 4-tuple merge in [Section 12.4.2](#1242-two-level-task-occurrence-merge-tdf-merge-010); canonical output in [Section 7.3](#73-intra-block-directive-order-and-value-formatting-tdf-ser-003).
6. **Examples:**
   - Valid: `due 2026-02-28 17:00:00 anchor 2026-01-31 18:00:00 passive "Month-end cutoff"`
   - Invalid: `due 2026-11-11 passive anchor 2026-11-11` (`UnexpectedToken`), `due 2026-11-11 anchor "2026-11-11"` (`InvalidTimestamp`)

#### 5.2.5 Machine Correlation Keys (`origin`) (`TDF-DIR-005`)

1. **Purpose, Scope, and Multiplicity:** Attaches a stable external `(namespace, externalKey)` correlation pair so scripts, connectors, and agents can deduplicate tasks across edits and completion states. Valid inside `task` at depth `1` (`0..1`, `DuplicateDirective` on repetition). Distinct `task` blocks MAY share an identical `(namespace, externalKey)` pair without triggering `DuplicateIdentifier`.
2. **Syntax and Types:** `origin "<namespace>" "<external-key>"` (both `<text>` under `TDF-TYPE-003`).
3. **Decoded Value and Default:** `absent` when omitted; `(decodedNamespace, decodedExternalKey)` when present.
4. **Validation, Security, and Diagnostic Redaction:**
   - `0` arguments without `{` -> `MissingDirectiveArgument`; `{` follows `origin` -> `UnknownBlockType`.
   - `1` argument, `>= 3` arguments, or either argument unquoted -> `UnexpectedToken`.
   - Validate both arguments as `<text>` (`TDF-TYPE-003`).
   - **Passive Security & Redaction:** `origin` values MUST NEVER be executed, opened as filesystem paths, or dereferenced over the network by a parser, evaluator, or reconciler. Diagnostic logs MUST NOT emit raw `<external-key>` values (log at most `<task-id>` and `<namespace>` or `hasOrigin`).
5. **Behavioral Cross-References:** Passive in evaluation ([Section 2.3](#23-stored-facts-derived-tiers-and-passive-metadata-tdf-model-003)); preserved across completion, recurrence, and restoration ([Section 10.4](#104-individual-mutations-and-lifecycle-actions)); merged as one atomic pair ([Section 12.3.1](#1231-merge-units-and-scalar-three-way-rules-tdf-merge-005)); canonical output in [Section 7.3](#73-intra-block-directive-order-and-value-formatting-tdf-ser-003).
6. **Examples:**
   - Valid: `origin "https://jira.example.com" "HOME-42"`
   - Invalid: `origin jira "HOME-42"` (`UnexpectedToken`), `origin "ns" ""` (`EmptyText`)

#### 5.2.6 Reference Links (`link`) (`TDF-DIR-006`)

1. **Purpose, Scope, and Multiplicity:** Attaches ordered user-facing external or local URI references to a `task` (`0..MAX_LINKS_PER_TASK = 20`) or a `label` (`0..MAX_LINKS_PER_LABEL = 20`) at depth `1` (`LimitExceeded` on the 21st `link` in either block).
2. **Syntax and Types:** `link "<title>" "<uri>"` (`<title>` as `<text>` under `TDF-TYPE-003`; `<uri>` as `<uri>` under `TDF-TYPE-005`).
3. **Decoded Value and Default:** Empty list `[]` when omitted; ordered list of `(decodedTitle, decodedUri)` pairs in preserved declaration order.
4. **Validation and Diagnostic Redaction:**
   - `0` arguments without `{` -> `MissingDirectiveArgument`; `{` follows `link` -> `UnknownBlockType`.
   - `1` argument, `>= 3` arguments, or either argument unquoted -> `UnexpectedToken`.
   - Validate `<title>` under `TDF-TYPE-003` and `<uri>` under `TDF-TYPE-005`.
   - Diagnostic logs on `label.link` (and `task.link`) MUST NOT emit raw `<title>` or `<uri>` strings.
5. **Behavioral Cross-References:** Passive in evaluation ([Section 2.3](#23-stored-facts-derived-tiers-and-passive-metadata-tdf-model-003)); mutations in [Section 10.4.6](#1046-ordinary-directive-and-entity-mutations-tdf-mut-008) (editing `label.link` advances `label.modified` only); merged as one complete atomic ordered list per entity ([Section 12.3.1](#1231-merge-units-and-scalar-three-way-rules-tdf-merge-005)); canonical output in [Section 7.3](#73-intra-block-directive-order-and-value-formatting-tdf-ser-003).
6. **Examples:**
   - Valid: `link "Runbook Repo" "https://git.example.com/ops/runbooks"`
   - Invalid: `link "XSS" "javascript:alert(1)"` (`InvalidUri`), `link "Blank" "   "` (`EmptyText`)

#### 5.2.7 Chronological Task Journal (`history`) (`TDF-DIR-007`)

1. **Purpose, Scope, and Multiplicity:** Records an occurrence-independent chronological trail of UTC-timestamped progress entries on a `task`, separate from standing `note` descriptions and transient `suspended`/`due` notes. Valid **only** inside `task` at depth `1` (`UnknownDirective` inside `label`, `location`, `deleted`, `queue`, `subtasks`, or `condition`; `UnexpectedRootDirective` at depth `0`). Maximum `MAX_HISTORY_PER_TASK = 500` raw `history` directives per `task` block **counted before deduplication** (`LimitExceeded` before allocating the 501st directive).
2. **Syntax and Types:** `history <YYYY-MM-DD> [<HH:MM[:SS]>] "<text>"` (UTC `<timestamp>` under `TDF-TYPE-004` + `<text>` under `TDF-TYPE-003`).
3. **Decoded Value and Default:** Empty list `[]` when omitted; deduplicated `(utcComponents, decodedText)` pairs sorted by ascending UTC epoch seconds, then ascending unsigned UTF-8 bytes of `decodedText` (`TDF-MODEL-006`).
4. **Token Disambiguation, Security, and Diagnostic Redaction:**
   - `0` arguments without `{` -> `MissingDirectiveArgument`; `{` follows `history` -> `UnknownBlockType` (after checking `InvalidBlockHeader` on attached `history{`).
   - `1` argument (`history 2026-11-10` or `history "text"`), `>= 4` arguments (`4..MAX_ARGS_PER_STMT`), `3` arguments where `args[1]` is quoted (`history 2026-11-10 "08:05:00" "text"`), or `2..3` arguments where `args.last` is unquoted -> `UnexpectedToken`.
   - Validate `args[0 .. args.length - 2]` (`1..2` tokens) as a UTC `<timestamp>` (`InvalidTimestamp` if `args[0]` is quoted — such as `history "2026-11-10" "text"` — or date/clock is invalid).
   - Validate `args.last` as single-line `<text>` (`TDF-TYPE-003`).
   - **Passive Security & Redaction:** `history` `<text>` values are plain text and MUST NEVER be executed, opened as paths, or dereferenced as URIs. Diagnostic logs MUST NOT emit raw `history` `<text>` (log at most `<task-id>` and entry count).
5. **Behavioral Cross-References:** Passive in evaluation ([Section 2.3](#23-stored-facts-derived-tiers-and-passive-metadata-tdf-model-003)); retained intact across completion, recurrence, `Someday` moves, restoration, and Undelete (removed only when the enclosing `task` block is deleted or pruned after `> 30` days in `Completed`); set-based mutation with no-op guard in [Section 10.4.6](#1046-ordinary-directive-and-entity-mutations-tdf-mut-008); occurrence-independent `(timestampUtc, text)` set merge in [Section 12.3.4](#1234-occurrence-independent-task-history-set-merge-tdf-merge-008); canonical output in [Section 7.3](#73-intra-block-directive-order-and-value-formatting-tdf-ser-003).
6. **Examples:**
   - Valid: `history 2026-11-01 18:05:00 "Checked blade part number"`
   - Invalid: `history "2026-11-01" "Checked"` (`InvalidTimestamp`), `history 2026-11-01 "Line 1\nLine 2"` (`UnexpectedToken`)

#### 5.2.8 Checklist Sub-Blocks (`subtasks`) (`TDF-DIR-008`)

1. **Purpose, Scope, and Multiplicity:** Defines an ordered checklist inside a `task` block (header at depth `1`, body at depth `2`, `0..1` per `task`, `DuplicateDirective` on repetition).
2. **Syntax and Types:**
   ```text
   subtasks [auto-finish] {
       step <true|false> "<text>"
   }
   ```
   - `auto-finish` (optional bare-word header flag, default `false`): when present, checking the final `false` step triggers guarded task completion ([Section 10.3](#103-completion-counters-and-prerequisite-arming-tdf-occ-001), [Section 10.4.4](#1044-completing-a-task-tdf-mut-006)); when omitted, completing all steps leaves the enclosing task open.
   - `step <bool> "<text>"` (`1..MAX_STMTS_PER_BLOCK` repeatable directives at depth `2`): `<bool>` (`false` = open, `true` = completed) followed by single-line `<text>` (`TDF-TYPE-003`).
3. **Decoded Value and Default:** `absent` when omitted (distinct from a present checklist); `(autoFinish, orderedSteps)` in preserved declaration order when present.
4. **Validation Rules:** Unknown or extra header argument on `subtasks` -> `InvalidBlockHeader`; zero `step` directives -> `MissingRequiredDirective`; nested `{` block inside `subtasks` -> `LimitExceeded` (`MAX_NESTING_DEPTH = 2`); directive other than `step` -> `UnknownDirective`; wrong `step` arity or unquoted `<text>` -> `MissingDirectiveArgument` (`0` args) or `UnexpectedToken` (`1` or `>= 3` args, or unquoted `<text>`).
5. **Behavioral Cross-References:** Completion/recurrence/restoration step transitions in [Sections 10.4.4–10.4.5](#1044-completing-a-task-tdf-mut-006); step-wise boolean Case 2 merge in [Section 12.4.2](#1242-two-level-task-occurrence-merge-tdf-merge-010); `$W_{\text{bool}}$` column alignment in [Section 7.4](#74-byte-level-formatting-and-column-alignment-tdf-ser-004).
6. **Examples:**
   - Valid: `subtasks auto-finish {` with `step false "Get mower"`
   - Invalid: `subtasks { }` (`MissingRequiredDirective`), `subtasks urgent {` (`InvalidBlockHeader`)

### 5.3 The `label` Block (`TDF-ENT-003`)

```text
label <label-id> [scoped] {
    ...
}
```

- **Header Arguments:**
  1. `<label-id>` (**Required**, `<label-id>`): Unique label identity in the `label` namespace (`InvalidIdentifier` if quoted or malformed; `DuplicateIdentifier` on collision with another `label` block or `deleted` `label` record).
  2. `scoped` (**Optional**, bare-word flag, default `false`): Marks a view-scoped context list. Tasks whose assigned labels are non-empty and all `scoped` are excluded from the unfiltered global view ([Section 9.1](#91-pre-filtering-and-scoped-label-exclusion-tdf-eval-001)), `scoped` labels are ignored when forming global-view condition contexts on mixed-label tasks ([Section 9.2.1](#921-condition-inheritance-and-context-resolution-tdf-eval-002)), and deleting a `scoped` label evicts global-view-restricted open tasks left with zero labels from `queue` ([Section 10.4.7](#1047-deleting-live-entities-and-reference-cascades-tdf-mut-009), [Section 12.5](#125-entity-presence-and-post-merge-cascades-tdf-merge-011)). When omitted, tasks enter both the global view and the filtered label view.
  - Missing `<label-id>`, unknown flag, quoted `"scoped"`, or extra arguments MUST fail with `InvalidBlockHeader`.
- **Label Directives and Sub-Blocks** (canonical 6-position output order is specified in [Section 7.3](#73-intra-block-directive-order-and-value-formatting-tdf-ser-003)):

| Directive / Sub-Block | Req. | Mult. | Syntax / Type ([Section 4](#4-primitive-value-types)) | Default & Domain Rules |
| :--- | :--- | :--- | :--- | :--- |
| `name` | Yes | `1` | `"<text>"` | Required display name (`MissingRequiredDirective` if absent; `1..MAX_TEXT_LENGTH` `<text>`). |
| `color` | No | `0..1` | `"<color>"` | Optional `"#RRGGBB"` color (`absent` when omitted; `InvalidColor` if malformed). |
| `note` | No | `0..1` | `"<note>"` | Optional description (`absent` when omitted; `1..MAX_NOTE_LENGTH` `<note>`). |
| `modified` | No | `0..1` | `<timestamp>` (UTC) | Optional UTC revision (`absent` when omitted; effective fallback `1970-01-01 00:00:00` UTC under [Section 10.1.2](#1012-entity-and-queue-revision-rules-tdf-mut-002)). |
| `link` | No | `0..20` | `"<title>" "<uri>"` | Repeatable shared context link (`[]` when omitted; `MAX_LINKS_PER_LABEL = 20`; [Section 5.2.6](#526-reference-links-link-tdf-dir-006)). |
| `condition` | No | `0..512` | Inline rule or `condition { ... }` | Inheritable `day`, `time`, `location` rules (`any` and `<type> any` forbidden on `label` with `InvalidCondition`; [Section 5.5](#55-activation-conditions-condition-tdf-dir-009)). |

### 5.4 The `location` Block (`TDF-ENT-004`)

```text
location <location-id> {
    ...
}
```

- **Header & Cardinality:** Requires exactly `1` unquoted `<location-id>` (`InvalidBlockHeader` if missing or extra arguments; `InvalidIdentifier` if quoted or malformed; `DuplicateIdentifier` on collision in the `location` namespace). At most `MAX_LOCATIONS = 200` `location` blocks per document (`LimitExceeded` on the 201st `location` block, while also counting toward `MAX_BLOCKS_PER_DOC = 4_096`). Nested blocks inside `location` are forbidden (`UnknownBlockType`).
- **Location Directives** (all single-valued, `DuplicateDirective` on repetition, `UnknownDirective` on any other directive; canonical 6-position output order is specified in [Section 7.3](#73-intra-block-directive-order-and-value-formatting-tdf-ser-003)):

| Directive | Req. | Mult. | Syntax / Type ([Section 4](#4-primitive-value-types)) | Default & Domain Rules |
| :--- | :--- | :--- | :--- | :--- |
| `name` | Yes | `1` | `"<text>"` | Required place title (`MissingRequiredDirective` if absent; `1..MAX_TEXT_LENGTH` `<text>`). |
| `note` | No | `0..1` | `"<note>"` | Optional place note (`absent` when omitted; `1..MAX_NOTE_LENGTH` `<note>`). |
| `source` | No | `0..1` | `"<text>"` | Optional address, Plus Code, or What3words code (`absent` when omitted; `1..MAX_TEXT_LENGTH` `<text>`). |
| `coordinates` | Yes | `1` | `<lat> <lon>` | Required WGS-84 decimal degrees (`MissingRequiredDirective` if absent; `MissingDirectiveArgument` on `0` args; `UnexpectedToken` if quoted or arg count `!= 2`; `<lat>` in `[-90.0, 90.0]` and `<lon>` in `[-180.0, 180.0]`, each `<= 6` non-zero fractional digits under `TDF-TYPE-005`). |
| `radius` | Yes | `1` | `<meters>` | Required geofence radius in meters (`MissingRequiredDirective` if absent; `MissingDirectiveArgument` on `0` args; `UnexpectedToken` if quoted or `>= 2` args; $0 < \text{meters} \le 100\,000$ with `<= 2` non-zero fractional digits under `TDF-TYPE-005`). |
| `modified` | No | `0..1` | `<timestamp>` (UTC) | Optional UTC revision (`absent` when omitted; effective fallback `1970-01-01 00:00:00` UTC under [Section 10.1.2](#1012-entity-and-queue-revision-rules-tdf-mut-002)). |

- **Passive `source` Security & SSRF Prohibition:** `location.source` is passive textual metadata. A conforming Reader, Evaluator, Mutating Client, or Reconciler MUST NEVER automatically invoke external geocoding services, network APIs, or filesystem/UNC paths (`\\server\share`) when processing `source`. If an application offers an explicit user action to open `source` in a map viewer, it MUST URL-encode `source` into a safe `https:` or `geo:` URI template rather than executing `source` as a raw URI or OS command.
- **Diagnostic Redaction:** Diagnostic logs MUST record only the opaque `<location-id>` and MUST NEVER emit `location.name`, `location.note`, `location.source`, or `location.coordinates`.

### 5.5 Activation Conditions (`condition`) (`TDF-DIR-009`)

1. **Purpose, Scope, and Syntactic Forms:** Restricts when a `label` or `task` is active by weekday (`day`), local time window (`time`), or geofence (`location`), and allows `task` blocks to override or clear inherited `label` condition groups. Valid at depth `1` inside `label` and `task` blocks in two equivalent syntactic forms that decode to the same model (`TDF-MODEL-006`):
   - **Block Form (`condition { ... }`, body at depth `2`):** Zero header arguments (`InvalidBlockHeader` otherwise), `>= 1` rule directive (`MissingRequiredDirective` if empty), and no nested `{` sub-blocks (`LimitExceeded` under `MAX_NESTING_DEPTH = 2`).
   - **Inline Shorthand (`condition <type> <args...>`, `condition <type> any`, or `condition any`):** Single-line directive at depth `1` (repeatable across lines).
2. **Built-In Rule Types and Task-Level Resets:**

| Rule / Reset | Block Form (`depth 2`) | Inline Form (`depth 1`) | Valid Scope & Argument Rules |
| :--- | :--- | :--- | :--- |
| `day` | `day <d1> [<d2> ...]` | `condition day <d1> [<d2> ...]` | `task` and `label`. `1..MAX_ARGS_PER_STMT` `<weekday>` tokens (`mon`..`sun`, `InvalidCondition` otherwise), combined with logical `OR`. |
| `time` | `time <start> <end>` | `condition time <start> <end>` | `task` and `label`. Exactly `2` `<time>` tokens `<HH:MM>` with `start != end` (`InvalidCondition` otherwise). |
| `location` | `location <loc-1> [<loc-2> ...]` | `condition location <loc-1> [<loc-2> ...]` | `task` and `label`. `1..MAX_LOCATION_REFS_PER_ENTITY` unquoted `<location-id>` tokens (`InvalidIdentifier` if quoted/malformed; `UnknownLocationReference` if matching no declared `location` block), combined with logical `OR`. |
| `<type> any` | `day any` / `time any` / `location any` | `condition day any` / `condition time any` / `condition location any` | **`task` only** (`InvalidCondition` on `label`, if repeated for the same `<type>`, or if combined with any rule of the same `<type>` group on the same `task`). Clears inherited group `<type>` while preserving other inherited groups. |
| `any` | *(forbidden -> `MissingDirectiveArgument` on bare `any`, `InvalidCondition` on `any <args...>`)* | `condition any` | **`task` inline only** (`InvalidCondition` on `label`, on `any <args...>` at depth `2` inside `condition { ... }`, or when combined with any other `condition` rule/reset on the same `task`; standalone `any` with zero arguments inside `condition { ... }` fails earlier with `MissingDirectiveArgument` under `TDF-GRAM-001`, and `condition any` inside `condition { ... }` fails earlier with `UnknownDirective`). Disables all inherited `label` condition groups. |

   - **Depth-`2` Statement Disambiguation Inside `condition { ... }`:**
     1. Nested `{` block at depth `2` (after checking attached `{` -> `InvalidBlockHeader`) -> `LimitExceeded` (`MAX_NESTING_DEPTH = 2`).
     2. Zero-argument identifier without `{` (`any`, `day`, `time`, `location`, `condition`) -> `MissingDirectiveArgument`.
     3. `any <args...>` -> `InvalidCondition` (`any` is recognized at depth `2` solely to reject parameterized global resets with `InvalidCondition`).
     4. Any other directive identifier at depth `2` outside `{day, time, location, any}` (including `condition any` or `condition day mon`) -> `UnknownDirective`.

3. **Entity-Wide Cardinality Bounds (Checked Before Coalescing/Deduplication):**
   - `MAX_CONDITION_RULES_PER_ENTITY = 512`: Count every input `day`, `time`, or `location` rule statement, every `<type> any` reset, and `condition any` across all inline `condition` directives and `condition { ... }` blocks on one `task` or `label` (`1` statement with multiple weekdays or `<location-id>`s counts as `1` rule). Reject the 513th rule with `LimitExceeded`.
   - `MAX_LOCATION_REFS_PER_ENTITY = 63`: Count every `<location-id>` token across all `location` condition rules on a single `task` or `label` **before deduplication** (`63` matches `MAX_ARGS_PER_STMT - 1` so coalescing into `condition location <loc-1> ... <loc-63>` never exceeds `64` arguments). Reject the 64th `<location-id>` token with `LimitExceeded`. Inherited label rules belong to the declaring `label` and do not count toward a referencing `task`'s limits.
4. **Behavioral Cross-References:** Group inheritance, `scoped` label exclusion, Haversine geofence check, and `day -> time -> location` short-circuit evaluation in [Section 9.2](#92-condition-resolution-and-evaluation); mutations in [Section 10.4.6](#1046-ordinary-directive-and-entity-mutations-tdf-mut-008) and `location` deletion cascade in [Section 10.4.7](#1047-deleting-live-entities-and-reference-cascades-tdf-mut-009); group-wise and `W`-anchored `locationGroup` merge in [Section 12.3.3](#1233-tombstone-stripping-and-group-wise-condition-merge-tdf-merge-007); canonical coalescing and inline-vs-block serialization in [Section 7.3](#73-intra-block-directive-order-and-value-formatting-tdf-ser-003).
5. **Examples:**
   - Valid: `condition time 09:00 18:00`, `condition day any`, `condition any`
   - Invalid: `condition time 09:00 09:00` (`InvalidCondition`), `condition any` inside `label` (`InvalidCondition`), `any mon` inside `condition { ... }` (`InvalidCondition`), `condition any` inside `condition { ... }` (`UnknownDirective`)

### 5.6 The `deleted` Block (`TDF-ENT-005`)

```text
deleted {
    generation 4
    task 6uCk8N0aB1 2026-11-01 12:00:00
    label 1rQv7S0cD2 2026-11-02 09:00:00
    location 9mTw3K0eF4 2026-11-03 15:30:00
}
```

- **Scope, Header, and Multiplicity:** Optional singleton root block (`0..1` per document, `DuplicateDirective` if repeated). Zero header arguments (`InvalidBlockHeader` otherwise); nested blocks forbidden (`UnknownBlockType`). Permits `1` `generation` directive plus up to `MAX_DELETED_RECORDS = 4_096` total tombstone directives (`LimitExceeded` on the 4,097th record).
- **Directives in `deleted`:**

| Directive | Req. | Mult. | Arguments ([Section 4](#4-primitive-value-types)) | Decoded Model Meaning |
| :--- | :--- | :--- | :--- | :--- |
| `generation` | Yes | `1` | `<generation>` | Monotonic deletion history generation (`MissingRequiredDirective` if absent in a present `deleted` block; `UnexpectedToken` if `>= 2` args). |
| `task` | No | `0..N` | `<task-id> <timestamp> [<completion-count>]` | Deleted task ID, UTC deletion revision, and optional last known completion checkpoint (default `0` when omitted). |
| `label` | No | `0..N` | `<label-id> <timestamp>` | Deleted label ID and UTC deletion revision (`UnexpectedToken` if a completion count or extra token is attached). |
| `location` | No | `0..N` | `<location-id> <timestamp>` | Deleted location ID and UTC deletion revision (`UnexpectedToken` if a completion count or extra token is attached). |

- **Token Parsing & Uniqueness:** Zero arguments on `generation`, `task`, `label`, or `location` fail with `MissingDirectiveArgument`; `1` argument on `task`, `label`, or `location` (missing `<timestamp>`) or extra trailing arguments (`>= 5` arguments on `task`, or `>= 4` arguments / a completion checkpoint on `label` or `location`) fail with `UnexpectedToken`. On a `deleted` `task` line, read `<task-id>` (`InvalidIdentifier` if invalid), then `<date>`, then an optional `<clock>` token containing `:` (`InvalidTimestamp` if the date or clock is malformed or quoted), followed by an optional `<completion-count>` (`0..MAX_COMPLETIONS`, `InvalidNumber` or `LimitExceeded` if invalid). Tombstones store no entity names, notes, or coordinates. Within each namespace (`task`, `label`, `location`), duplicate tombstone IDs or a tombstone sharing an ID with a live entity block in the same document MUST fail with `DuplicateIdentifier`.
- **Default When Block Omitted:** `generation = 0` and zero records. A present `deleted` block with `generation > 0` and zero records is valid and preserved.
- **Cross-References:** Canonical omission (`generation == 0` and `0` records) and ordering in [Section 7.2–7.3](#72-root-level-section-order-and-block-omission-tdf-ser-002); creating tombstones in [Section 10.4.7](#1047-deleting-live-entities-and-reference-cascades-tdf-mut-009); tombstone merging and `DeletionConflict` in [Section 12.6](#126-deletion-records-checkpoints-and-deletionconflict); 30-day retention pruning and generation recovery in [Sections 13.2–13.3](#132-thirty-day-retention-pruning-tdf-pub-004).

### 5.7 The `queue` Block (`TDF-ENT-006`)

```text
queue {
    modified 2026-11-04 12:00:00
    task AAAAAAAAAA
    task BBBBBBBBBB
}
```

- **Scope, Header, and Multiplicity:** Optional singleton root block (`0..1` per document, `DuplicateDirective` if repeated). Zero header arguments (`InvalidBlockHeader` otherwise); nested blocks forbidden (`UnknownBlockType`). Permits `1` `modified` directive plus `0..MAX_QUEUE_ENTRIES` (`4_096`) `task` directives (`LimitExceeded` on the 4,097th entry).
- **Directives in `queue`:**

| Directive | Req. | Mult. | Arguments ([Section 4](#4-primitive-value-types)) | Decoded Model Meaning |
| :--- | :--- | :--- | :--- | :--- |
| `modified` | Yes | `1` | `<timestamp>` (UTC) | UTC revision timestamp for the complete ordered queue list (`MissingRequiredDirective` if absent in a present `queue` block). |
| `task` | No | `0..4096` | `<task-id>` | One scheduled open task reference in saved queue order (`UnexpectedToken` if `>= 2` args; `InvalidIdentifier` if quoted or malformed). |

- **Membership & Reference Integrity (Resolved After Reading Complete Document):**
  - Every `task <task-id>` entry MUST appear at most once in `queue` (`DuplicateIdentifier` on duplicate queue entries).
  - Every `task <task-id>` entry MUST reference a declared live open `task` block (`finished` absent) in the same document. Referencing an unknown `<task-id>`, a tombstoned `<task-id>` in `deleted`, or a completed `task` (`finished` present) MUST fail at that `queue` line with `InvalidQueueMembership`.
  - Root `task` block declaration order in the file has zero effect on `queue` order.
- **Default When Block Omitted:** Empty list `[]` with `modified = 1970-01-01 00:00:00` UTC. Non-epoch empty queues (`modified != 1970-01-01 00:00:00` UTC with `0` entries) remain valid and preserved.
- **Cross-References:** Canonical omission (`0` entries and epoch `modified`) and ordering in [Section 7.2–7.3](#72-root-level-section-order-and-block-omission-tdf-ser-002); active pull-cycle filtering in [Section 9.4](#94-six-tier-classification-pipeline-tdf-eval-005); queue mutations in [Section 10.4](#104-individual-mutations-and-lifecycle-actions); queue reconciliation in [Section 12.7](#127-shared-queue-reconciliation-tdf-qsync-001).

## 6. Validation and Resource Bounds

### 6.1 Validation Contract and Deterministic Error Precedence (`TDF-VAL-001`)

A conforming Reader MUST reject any invalid `.tdf` input deterministically with the structured error code ([Appendix A.1](#a1-structured-error-and-outcome-index-tdf-err-001)) and 1-based physical line number of the offending construct, applying checks in this deterministic order:

1. **File Size & Lexical Encoding Gate:** Check `MAX_FILE_BYTES` before reading/allocating byte `1_048_577` (`LimitExceeded`). Validate UTF-8 encoding, null bytes, standalone `CR`, disallowed control characters, non-ASCII horizontal whitespace outside quotes/comments, and mid-token attached quotes (`UnexpectedToken`), string termination (`UnterminatedString`), and double-quoted escape sequences (`InvalidEscapeSequence`).
2. **Line, Depth, Block & Statement Bounds + Structural Framing:** Check `MAX_LINE_COUNT`, `MAX_BLOCKS_PER_DOC`, `MAX_NESTING_DEPTH` (including any nested `{` block opened at depth `2` inside `subtasks` or `condition`), `MAX_STMTS_PER_BLOCK` (`MAX_DELETED_RECORDS` in `deleted`, `MAX_QUEUE_ENTRIES` in `queue`), and `MAX_ARGS_PER_STMT` **before** scanning or allocating the $(N+1)$-th element (`LimitExceeded`). Validate attached `{` without whitespace (`InvalidBlockHeader`), unmatched `}` at depth `0` (`UnexpectedClosingBrace`), trailing tokens after `{` or `}` (`UnexpectedToken`), initial `tdf <version>` presence (`MissingVersionHeader` / `UnsupportedVersion`), root directives (`UnexpectedRootDirective`), identifier syntax (`InvalidIdentifier`), zero-argument directives without `{` (`MissingDirectiveArgument`), allowed block types at depth `0`–`1` (`UnknownBlockType`), block header parameters (`InvalidBlockHeader` / `InvalidIdentifier`), allowed directive names per block — including `{step}` in `subtasks` and `{day, time, location, any}` at depth `2` in `condition { ... }` (`UnknownDirective` for any other directive name, including `condition any` or `condition day mon` inside `condition { ... }`, whereas `any <args...>` inside `condition { ... }` fails in Step 3 with `InvalidCondition`), singleton multiplicity (`DuplicateDirective`), entity-specific cardinalities (`MAX_LOCATIONS`, `MAX_LINKS_PER_TASK`, `MAX_LINKS_PER_LABEL`, `MAX_HISTORY_PER_TASK`, `MAX_CONDITION_RULES_PER_ENTITY`, `MAX_LOCATION_REFS_PER_ENTITY` -> `LimitExceeded`), and unclosed blocks at `EOF` (`UnclosedBlock`).
3. **Directive Argument & Primitive Semantic Checks:** Apply each directive's token-disambiguation rules ([Section 5](#5-entity-and-directive-reference)) and primitive value checks ([Section 4](#4-primitive-value-types)), including `<text>` single-line/surrogate `UnexpectedToken` before `EmptyText` before `LimitExceeded`, `<note>` surrogate `UnexpectedToken` before `EmptyText` before `LimitExceeded`, `<uri>` surrogate `UnexpectedToken` before `EmptyText` before `LimitExceeded` before `InvalidUri`, and `<number>` `MAX_NUMBER_LENGTH` `LimitExceeded` before `InvalidNumber` before `MAX_LOCATION_RADIUS` `LimitExceeded`. Verify required directives per block before closing `}` (`MissingRequiredDirective`) and `finished` vs. `completions` (`InvalidCompletionState`).
4. **Document-Wide Identity, Reference & Acyclicity Checks:** Verify intra-namespace uniqueness across live blocks, `deleted` records, and `queue` entries (`DuplicateIdentifier`), `labels` references (`UnknownLabelReference`), `condition location` references (`UnknownLocationReference`), `queue` live-open-task membership (`InvalidQueueMembership`, reported at the offending `queue` line), and `blocked` dependency acyclicity (`CircularDependency`).

### 6.2 Resource Bounds (`TDF-VAL-002`)

Enforce every resource limit below **before** scanning or allocating the $(N+1)$-th element (`LimitExceeded` on violation):

| Bound Name | Limit | Scope and Counting Rule |
| :--- | :--- | :--- |
| `MAX_FILE_BYTES` | `1_048_576` (`1 MiB`) | Maximum input or canonical serialized output size in UTF-8 bytes. |
| `MAX_LINE_COUNT` | `16_384` | Maximum logical lines per `.tdf` document (input or canonical output). |
| `MAX_NESTING_DEPTH` | `2` | Maximum open `{ ... }` block depth (`0` root, `1` root block, `2` `subtasks` or `condition`). |
| `MAX_BLOCKS_PER_DOC` | `4_096` | Maximum total blocks (`task`, `label`, `location`, `deleted`, `queue`, `subtasks`, `condition`). |
| `MAX_LOCATIONS` | `200` | Maximum root-level `location` blocks per document (also counted toward `MAX_BLOCKS_PER_DOC`). |
| `MAX_STMTS_PER_BLOCK` | `1_024` | Maximum direct child statements per ordinary block. Each nested sub-block counts as `1` statement in its parent; its inner lines count toward that sub-block's own limit. `deleted` permits `1` `generation` + `MAX_DELETED_RECORDS`; `queue` permits `1` `modified` + `MAX_QUEUE_ENTRIES`. |
| `MAX_CONDITION_RULES_PER_ENTITY` | `512` | Maximum condition rule/reset statements across all inline `condition` directives and `condition { ... }` blocks on one `task` or `label`. |
| `MAX_LOCATION_REFS_PER_ENTITY` | `63` | Maximum `<location-id>` tokens across all `location` condition rules on one `task` or `label`, counted **before** deduplication. |
| `MAX_QUEUE_ENTRIES` | `4_096` | Maximum `task` directives inside `queue` (including temporarily blocked tasks). |
| `MAX_DELETED_RECORDS` | `4_096` | Maximum total `task`, `label`, and `location` tombstone directives inside `deleted`. |
| `MAX_SYNC_GENERATION` | `9_007_199_254_740_991` | Maximum `deleted.generation` ($2^{53} - 1$; overflow fails with `LimitExceeded`, never wraps). |
| `MAX_COMPLETIONS` | `9_007_199_254_740_991` | Maximum `completions` counter, `deleted` task checkpoint, or `blocked` `:<required-completion>`. |
| `MAX_ARGS_PER_STMT` | `64` | Maximum arguments on a single block header or directive statement. |
| `MAX_TEXT_LENGTH` | `500` | Maximum decoded Unicode scalar values in any `<text>` argument (`TDF-TYPE-003`). |
| `MAX_NOTE_LENGTH` | `2_000` | Maximum decoded Unicode scalar values in any `<note>` argument (`TDF-TYPE-003`). |
| `MAX_URI_LENGTH` | `2_048` | Maximum decoded Unicode scalar values in any `link` `<uri>` argument (`TDF-TYPE-005`). |
| `MAX_LINKS_PER_TASK` | `20` | Maximum `link` directives in a single `task` block. |
| `MAX_LINKS_PER_LABEL` | `20` | Maximum `link` directives in a single `label` block. |
| `MAX_HISTORY_PER_TASK` | `500` | Maximum raw `history` directives in a single `task` block, counted **before** deduplication. |
| `MAX_REPEAT_COUNT` | `3_650` | Maximum `<count>` or `<lead-count>` in `repeat <count> <unit> [<repeat-time>] [lead <lead-count> days]`. |
| `MAX_LOCATION_RADIUS` | `100_000` | Maximum `location` `radius` in meters (`100 km`; `0 < radius <= 100_000`). |
| `MAX_NUMBER_LENGTH` | `24` | Maximum raw ASCII characters in a `<number>` token. |

For tier evaluation ([Section 8.1](#81-evaluation-context-parameters-tdf-ctx-001), [Section 9.4](#94-six-tier-classification-pipeline-tdf-eval-005)), `DEFAULT_DUE_LEAD_SECONDS = 86_400` (`24` hours) is the normative default deadline lead-window duration $W_{\text{due}}$ when not overridden or disabled by the client.

### 6.3 Reference Integrity, Completion State, and Acyclicity (`TDF-VAL-003`)

After parsing all blocks in a document (or constructing a mutated/merged candidate):

1. **Namespace Uniqueness (`DuplicateIdentifier`):** Within `task`, within `label`, and within `location`, no ID may be declared more than once across live entity blocks and `deleted` records, and no `<task-id>` may appear more than once in `queue`.
2. **Label References (`UnknownLabelReference`):** Every `<label-id>` in `task.labels` MUST match a live `label` block in the document.
3. **Location References (`UnknownLocationReference`):** Every `<location-id>` in `task` or `label` `condition location` rules MUST match a live `location` block in the document.
4. **Queue Membership (`InvalidQueueMembership`):** Every `<task-id>` in `queue` MUST match a live open `task` block (`finished` absent).
5. **Completion State (`InvalidCompletionState`):** Every `task` block with `finished` present MUST have an explicit `completions` counter `>= 1`.
6. **Dependency Acyclicity (`CircularDependency`):** The directed graph formed by `task` -> `blocked` `<target-id>` edges across all `task` blocks in the document (including already satisfied prerequisite thresholds) MUST be a Directed Acyclic Graph (DAG); any self-loop (`T -> T`) or cycle (`T1 -> ... -> Tk -> T1`) fails with `CircularDependency`. Missing or deleted `<target-id>`s have out-degree `0` and remain valid non-blocking references.

## 7. Canonical Serialization

### 7.1 Canonical Serialization Contract (`TDF-SER-001`)

Two independently implemented canonical serializers MUST emit **byte-for-byte identical UTF-8 output and identical SHA-256 `sourceDigest` values** for the same normalized document model (including explicit-versus-omitted `modified` directive presence on `label`, `location`, and `task` blocks).

- Parsing canonical output MUST reproduce the identical normalized values ([Section 2.6](#26-decoded-value-normalization-and-structural-equality-tdf-model-006)), entity identities, explicit-vs-omitted `modified` presence, `deleted` state, and saved `queue` order.
- Validate the complete serialized byte stream against all schema and resource bounds (`MAX_FILE_BYTES`, `MAX_LINE_COUNT`, `MAX_STMTS_PER_BLOCK`, `MAX_ARGS_PER_STMT`, etc.) before publication. Because canonical escaping or indentation can increase byte or line counts relative to hand-edited input, fail with `LimitExceeded` if canonical output exceeds any bound — NEVER truncate `history`, `link`, or `condition` entries or split the canonical `condition` block to force publication, and preserve the prior document and baseline on failure.

### 7.2 Root-Level Section Order and Block Omission (`TDF-SER-002`)

Emit root-level elements in this exact 6-section order:

1. `tdf 0.8.0`
2. `deleted { ... }` — MUST be omitted **when and only when** `deleted.generation == 0` and zero deletion records (`task`, `label`, `location`) exist; otherwise emit `deleted { ... }`.
3. `queue { ... }` — MUST be omitted **when and only when** zero `task` entries exist and `queue.modified == 1970-01-01 00:00:00` UTC; otherwise emit `queue { ... }` (preserving non-epoch empty queue revisions).
4. `label` blocks sorted by ascending ASCII `<label-id>` (`label <id> {` when `scoped == false`; `label <id> scoped {` when `scoped == true`).
5. `location` blocks sorted by ascending ASCII `<location-id>` (`location <id> {`).
6. `task` blocks sorted by ascending ASCII `<task-id>` (`task <id> {` when `priority == false`; `task <id> priority {` when `priority == true`).

### 7.3 Intra-Block Directive Order and Value Formatting (`TDF-SER-003`)

This section is the sole authoritative definition of intra-block statement ordering across all block types:

- **Inside `deleted { ... }`:**
  1. `generation <generation>`
  2. `task <task-id> <YYYY-MM-DD HH:MM:SS> [<checkpoint>]` sorted by ascending ASCII `<task-id>` (omitting `<checkpoint>` when `0`, emitting `<checkpoint>` when `>= 1`).
  3. `label <label-id> <YYYY-MM-DD HH:MM:SS>` sorted by ascending ASCII `<label-id>`.
  4. `location <location-id> <YYYY-MM-DD HH:MM:SS>` sorted by ascending ASCII `<location-id>`.
- **Inside `queue { ... }`:**
  1. `modified <YYYY-MM-DD HH:MM:SS>`
  2. `task <task-id>` entries, one per line, in saved queue order.
- **Inside each `label` block (6 positions, omitting absent optional items):**
  1. `name "<escaped-text>"`
  2. `color "#RRGGBB"` (uppercase hexadecimal digits `0-9`, `A-F`)
  3. `note "<escaped-note>"`
  4. `modified <timestamp>` (emitted **if and only if** an explicit `modified` directive is present on the `label`)
  5. `link "<escaped-title>" "<escaped-uri>"` (in preserved declaration order)
  6. `condition` (formatted under the canonical `condition` rule below)
- **Inside each `location` block (6 positions, omitting absent optional items):**
  1. `name "<escaped-text>"`
  2. `note "<escaped-note>"`
  3. `source "<escaped-text>"`
  4. `coordinates <normalizedLat> <normalizedLon>` (`TDF-MODEL-006` decimal normalization)
  5. `radius <normalizedRadius>` (`TDF-MODEL-006` decimal normalization)
  6. `modified <timestamp>` (emitted **if and only if** an explicit `modified` directive is present on the `location`)
- **Inside each `task` block (16 positions, omitting absent optional items):**
  1. `name "<escaped-text>"`
  2. `note "<escaped-note>"`
  3. `created <timestamp>`
  4. `finished <timestamp>`
  5. `modified <timestamp>` (emitted **if and only if** an explicit `modified` directive is present on the `task`)
  6. `completions <count>` (omitted when `0`; emitted when `>= 1`)
  7. `repeat <count> <days|weeks|months> [<clock>] [lead <lead-count> days]` (omitting `<clock>` when `00:00:00`, emitting non-midnight `<clock>` as `HH:MM` when `second == 0` or `HH:MM:SS` when `second != 0`; omitting `lead <lead-count> days` when `leadDays == 0`)
  8. `labels <id-1> [<id-2> ...]` (deduplicated, sorted by ascending ASCII `<label-id>`)
  9. `blocked <dep-1> [<dep-2> ...]` (sorted by ascending ASCII `<task-id>`, omitting `:1` when `requiredCompletion == 1` and emitting `:<req>` when `req >= 2`)
  10. `suspended (<YYYY-MM-DD HH:MM:SS> | forever) ["<escaped-note>"]` (UTC)
  11. `due <YYYY-MM-DD HH:MM:SS> [anchor <YYYY-MM-DD HH:MM:SS>] [passive] ["<escaped-note>"]` (`<due>` in UTC, `anchor` in local calendar components when `anchor != absent`, `passive` when `true`, `"<escaped-note>"` when present)
  12. `origin "<escaped-namespace>" "<escaped-external-key>"`
  13. `link "<escaped-title>" "<escaped-uri>"` (in preserved declaration order)
  14. `history <YYYY-MM-DD HH:MM:SS> "<escaped-text>"` (in UTC, deduplicated `(timestampUtc, text)` pairs sorted by ascending UTC epoch seconds, then ascending unsigned UTF-8 byte order of `text`)
  15. `condition` (formatted under the canonical `condition` rule below)
  16. `subtasks [auto-finish] { ... }` (`step` directives in preserved declaration order)
- **Canonical `condition` Coalescing and Inline-vs-Block Formatting (`label` position 6 and `task` position 15):**
  - Coalesce all `location` condition rules on the entity into at most `1` canonical `location <loc-1> [<loc-2> ...]` rule containing all referenced `<location-id>` tokens deduplicated in first-seen declaration order (`TDF-MODEL-006`).
  - `0` canonical rules and `globalAny == false` -> omit `condition`.
  - `globalAny == true` (`task` only) -> emit inline `condition any`.
  - Exactly `1` canonical rule after coalescing `location` references (including `<type> any` or a single coalesced `location <loc-1> ...`) -> emit single-line shorthand `condition <key> <args...>`.
  - `>= 2` canonical rules after coalescing `location` references -> emit one `condition { ... }` sub-block with rules ordered by group `day`, then `time`, then `location` (preserving declaration order within `day` and `time`, and emitting the single coalesced `location <loc-1> ...` rule or `location any` last).

### 7.4 Byte-Level Formatting and Column Alignment (`TDF-SER-004`)

Every canonical serializer MUST obey these exact byte-level rules:

1. **UTF-8, Comments, and `LF` Terminators:**
   - Encode in UTF-8 **without** a Byte Order Mark (`BOM`).
   - Emit **zero `#` comments** anywhere in output.
   - Terminate **every** emitted line — including `tdf 0.8.0\n` on an empty document and the closing `}` of the final root block — with a single `LF` (`0x0A`, `"\n"`), with zero trailing spaces (`0x20`) or tabs (`0x09`) before `LF`.
2. **Blank-Line Placement:**
   - Emit `tdf 0.8.0\n` at byte offset `0` with zero preceding blank lines.
   - Precede every emitted root block (`deleted`, `queue`, `label`, `location`, `task`) with **exactly one blank line** (`"\n"`).
   - Emit **zero blank lines** inside any block body (including before or after `condition { ... }` or `subtasks [auto-finish] { ... }`).
3. **Indentation and Header Spacing:**
   - Indent using **`4` ASCII spaces (`0x20`) per open block depth** (never `\t`): `0` spaces at depth `0` (`tdf 0.8.0`, root headers, root `}`), `4` spaces at depth `1` (direct child directives, sub-block headers `    condition {` and `    subtasks [auto-finish] {`, and sub-block closing `    }`), and `8` spaces at depth `2` (statements inside `condition { ... }` and `subtasks { ... }`).
   - Separate all tokens on a block header line (including trailing `{`) by `1` ASCII space (`0x20`).
4. **Per-Block Keyword Padding and Argument Spacing:**
   - Separate consecutive arguments on the same directive line by **exactly `1` ASCII space (`0x20`)**.
   - **Inside `deleted { ... }` and `queue { ... }` (Unpadded):** Separate each directive identifier (`generation`, `task`, `label`, `location`, `modified`) from its first argument by **exactly `1` ASCII space (`0x20`)** without column padding.
   - **Inside `label`, `location`, and `task` Root Blocks ($W_{\text{dir}}$ Alignment):** Let $\mathcal{D}_{\text{direct}}$ be the set of **single-line direct-child directives** emitted at depth `1` of that block instance (**including** an inline `condition <key> <args...>` directive uniformly on both `label` and `task` when `1` canonical condition rule is emitted, and **excluding** nested sub-block headers `condition {` and `subtasks [auto-finish] {`). Let $W_{\text{dir}} = \max_{d \in \mathcal{D}_{\text{direct}}} \text{length}(d.\text{identifier})$. Emit each $d \in \mathcal{D}_{\text{direct}}$ as `4` leading spaces + $d.\text{identifier}$ right-padded with ASCII spaces (`0x20`) to width $W_{\text{dir}}$ + `1` separating ASCII space (`0x20`) + its canonical arguments.
   - **Inside `condition { ... }` Sub-Blocks ($W_{\text{cond}}$ Alignment):** Let $W_{\text{cond}} = \max_{r} \text{length}(r.\text{key})$ across the emitted rules of that `condition { ... }` sub-block (`day` = `3`, `time` = `4`, `location` = `8`). Emit each rule $r$ as `8` leading spaces + $r.\text{key}$ right-padded with `0x20` to width $W_{\text{cond}}$ + `1` separating `0x20` + $r.\text{args}$.
   - **Inside `subtasks [auto-finish] { ... }` Sub-Blocks ($W_{\text{bool}}$ Alignment):** Let $W_{\text{bool}} = 5$ if at least one `step` in that `subtasks` block has `<bool> == false`, and $W_{\text{bool}} = 4$ if every `step` has `<bool> == true`. Emit each step as `8` leading spaces + `step ` + (`true` or `false` right-padded with `0x20` to width $W_{\text{bool}}$) + `1` separating `0x20` + `"<escaped-text>"`.
5. **String Quoting, Escaping, and Timestamp Precision:**
   - Emit all quoted string arguments (`name`, `color`, `note`, `source`, `origin`, `link`, `history`, `step`, `suspended` note, `due` note) using double quotes `"`, escaping **only** `"` (`\"`), `\` (`\\`), `LF` (`\n`), `CR` (`\r`), and `HT` (`\t`), and emitting all other decoded Unicode scalar values (`'`, `#`, `{`, `}`, non-ASCII UTF-8 scalars) unescaped without Unicode normalization.
   - Emit `deleted` record timestamps, `queue.modified`, finite `suspended`, `due` UTC timestamps, `due` local `anchor` timestamps, and `history` timestamps as `YYYY-MM-DD HH:MM:SS` (`19` ASCII characters with explicit zero-padded seconds). Emit `created`, `finished`, and entity `modified` (`task.modified`, `label.modified`, `location.modified`) as `YYYY-MM-DD HH:MM` (`16` ASCII characters) when `second == 0` and `YYYY-MM-DD HH:MM:SS` (`19` ASCII characters) when `second != 0`. Emit `condition time` endpoints as zero-padded `HH:MM` (`5` ASCII characters).

### 7.5 Normative Canonical Byte and SHA-256 Digest Vectors (`TDF-SER-005`)

Conforming `0.8.0` serializers MUST reproduce the exact UTF-8 byte lengths, line counts, and lowercase SHA-256 `sourceDigest` values below (and for Vector 4 in [Appendix B.1](#b1-complete-canonical-document-example-tiertasktdf)):

1. **Vector 1 — Empty Document (`10` UTF-8 bytes, `1` line, SHA-256 `7904b7a8e8cd221287ac91710477af38bbb7beb14dea75e2c827dfa2bfd2097a`):**
   ```text
   tdf 0.8.0
   ```
2. **Vector 2 — Minimal Single-Task Alignment (`76` UTF-8 bytes, `6` lines, $W_{\text{dir}} = 7$, SHA-256 `3211d46b392b7b1efbf53cf07a0c0c6131f987a4b17dba9a733b9971108f7090`):**
   ```text
   tdf 0.8.0

   task AAAAAAAAAA {
       name    "A"
       created 2026-11-16 00:00
   }
   ```
3. **Vector 3 — Multi-Section Alignment, Inline `label` `condition` ($W_{\text{dir}} = 9$), Task `condition` Sub-Block ($W_{\text{dir}} = 8$, $W_{\text{cond}} = 4$), `due ... anchor ...`, and `subtasks` ($W_{\text{bool}} = 5$) (`856` UTF-8 bytes, `41` lines, SHA-256 `8e5771dedbdde3bf9451c247bbab1a826298f90e0c2e20a57e98ed75f53cf7cd`):**
   ```text
   tdf 0.8.0

   deleted {
       generation 1
       task 6uCk8N0aB1 2026-11-01 12:00:00 2
   }

   queue {
       modified 2026-11-16 09:00:00
       task 8jKaCdOkD2
   }

   label 4x9p2mOkD2 {
       name      "Home"
       color     "#4CAF50"
       condition location 7pQr9mOkD2
   }

   location 7pQr9mOkD2 {
       name        "Office"
       coordinates 50.9787 11.0328
       radius      150
   }

   task 8jKaCdOkD2 priority {
       name     "Close monthly books"
       note     "Line 1\nLine 2 with \"quotes\""
       created  2026-01-01 08:00
       modified 2026-01-31 18:00:05
       repeat   1 months 08:00 lead 2 days
       labels   4x9p2mOkD2
       due      2026-02-28 17:00:00 anchor 2026-01-31 18:00:00 "Month-end cutoff"
       condition {
           day  mon tue wed thu fri
           time 08:00 18:00
       }
       subtasks auto-finish {
           step false "Reconcile ledger"
           step true  "Export statements"
       }
   }
   ```

## Part B: Task Behavior

Part B defines how an Evaluator projects a decoded document onto the six operational tiers ([Sections 8–9](#8-evaluation-context-and-time-interpretation)) and how a Mutating Client updates entity facts, calendar schedules, completion counters, tombstones, and the shared `queue` ([Section 10](#10-mutations-and-lifecycle-transitions)).

## 8. Evaluation Context and Time Interpretation

### 8.1 Evaluation Context Parameters (`TDF-CTX-001`)

Pure tier derivation evaluates an immutable decoded document against one captured evaluation context:

| Parameter | Domain | Meaning |
| :--- | :--- | :--- |
| `now` | UTC `<timestamp>` | Single captured UTC reference instant used consistently across the entire evaluation pass. |
| `timeZone` | IANA time-zone rules | Configured civil time zone used to derive `localNow` (`date`, `weekday`, `minuteOfDay`) from `now` using the zone's historical and future transition rules for the converted date (a fixed current UTC offset is insufficient). |
| $W_{\text{due}}$ | Non-negative integer seconds or `absent` | Optional deadline urgency lead window (`DEFAULT_DUE_LEAD_SECONDS = 86_400` / `24 hours` by normative default; `absent` when client lead-window auto-promotion is disabled). |
| `activeLabelId` | `<label-id>` or `absent` | Optional active label filter (`absent` = unfiltered global view; `l*` = single-label context view). |
| `currentCoordinates` | `(lat, lon)` or `absent` | Optional current device WGS-84 GPS coordinates (`absent` when GPS hardware is unavailable or location sensing is disabled). |

If local `condition` evaluation requires `localNow` and `timeZone`'s transition rules are unavailable, fail with `TimeZoneContextRequired` without mutating document state. Evaluation parameters are runtime inputs and add zero directives or fields to `.tdf` blocks.

### 8.2 UTC Instants Versus Local Wall-Clock Evaluation (`TDF-CTX-002`)

- **Deferrals (`suspended`):** Evaluated strictly in UTC against `now`. For an open task, `suspended` is active when and only when its value is `forever` or a finite UTC timestamp satisfying `suspended > now`. At exact equality (`suspended == now`) or earlier (`suspended < now`), a finite deferral has expired and does not block the task. Two devices in different time zones evaluate the same finite UTC `suspended` timestamp identically against the same `now`, and autumn daylight-saving clock rollback MUST NOT reactivate an expired UTC deferral.
- **Deadlines (`due`):** Evaluated in UTC against `now + W_due` solely for `isDueUrgent` ([Section 9.4](#94-six-tier-classification-pipeline-tdf-eval-005)). `due` (whether `due > now` or overdue `due <= now`) NEVER blocks a task, and `due.anchor` is completely inert during evaluation.
- **Activation Conditions (`condition day`, `condition time`):** Evaluated against `localNow`'s local calendar weekday and local 24-hour clock in `timeZone`.
- **Stored Date-Only Values & Time-Zone Changes:** A stored date-only UTC timestamp (`YYYY-MM-DD`) means `00:00:00` UTC (`TDF-TYPE-004`). Changing the configured `timeZone` MUST NOT rewrite or reinterpret already stored UTC `suspended`, `due`, or `history` timestamps (or stored local `due.anchor` components); the new zone applies only to subsequent evaluations and local calendar mutations. (`history` UTC timestamps are converted to local time only for UI display.)
- **Read-Only Evaluation Purity:** Evaluation MUST NEVER remove expired `suspended` directives, strip satisfied `blocked` entries, write `priority` or `passive` flags, reorder `queue`, or alter `modified` timestamps (`TDF-MODEL-001`).

## 9. Tier Derivation

### 9.1 Pre-Filtering and `scoped` Label Exclusion (`TDF-EVAL-001`)

Let $L(T)$ be the set of declared `label` blocks referenced in task $T$'s `labels` directive, and let $\text{isScoped}(l)$ be `true` when `label` $l$ carries the `scoped` header flag ([Section 5.3](#53-the-label-block-tdf-ent-003)):

- **Filtered Label View (`activeLabelId = l*`):** Retain every task $T$ with $l^* \in L(T)$ (whether $l^*$ is regular or `scoped`) and scope all six tiers (`Completed`, `Someday`, `Blocked`, `Focus`, `Ready`, `Planned`) to that label view.
- **Unfiltered Global View (`activeLabelId = absent`):** Exclude task $T$ from the global view if and only if $L(T)$ is non-empty and **every** assigned label in $L(T)$ is `scoped`:
  $$\text{isRestrictedFromGlobalView}(T) \iff L(T) \neq \varnothing \;\land\; \forall l \in L(T),\; \text{isScoped}(l)$$
  Retain all tasks with $L(T) = \varnothing$ or with at least one non-`scoped` label ($\exists l \in L(T),\; \neg\text{isScoped}(l)$). Tasks restricted from the global view remain excluded from the global view even when their `due` timestamp lies within $W_{\text{due}}$ or is overdue; they receive effective priority inside their `activeLabelId` view.
- **Full-Board Search & Prerequisite Resolution:** Full-board search inspects all tasks regardless of `scoped`, and `blocked` prerequisite evaluation ([Section 9.3](#93-prerequisite-satisfaction-tdf-eval-004)) resolves across the complete document regardless of `scoped` or `activeLabelId`.

### 9.2 Condition Resolution and Evaluation

#### 9.2.1 Condition Inheritance and Context Resolution (`TDF-EVAL-002`)

Task-level condition rules override or clear inherited `label` rules per rule group (`day`, `time`, `location`) without altering `task.labels`:

1. **Per-Group Resolution Against a Single Label Context:** When forming task $T$'s effective condition context against a given `label` $l$ (or with no label):
   - **Global Reset (`condition any`):** If $T$ specifies `condition any`, all three effective rule groups (`day`, `time`, `location`) are empty (`0` rules, unrestricted), ignoring all conditions on $l$.
   - **Selective Group Resolution:** Otherwise, resolve each group $G \in \{\text{day}, \text{time}, \text{location}\}$ independently:
     - **Task Group Reset (`G any`):** If $T$ specifies `day any`, `time any`, or `location any` for $G$, effective group $G$ is empty (`0` rules, unrestricted), ignoring $l$'s rules for $G$.
     - **Task Group Override (`G <args...>`):** If $T$ defines `>= 1` rule for $G$, replace $l$'s rules for $G$ with $T$'s rules for $G$.
     - **Label Group Inheritance:** If $T$ defines neither a rule nor a reset for $G$, inherit $l$'s rules for $G$ (or leave $G$ empty if $l$ defines none).
2. **Candidate Context Set by View Mode:**
   - **Unlabeled Task ($L(T) = \varnothing$):** Single candidate context $\{C_1\}$ containing only $T$'s own `day`, `time`, and `location` groups.
   - **Filtered Label View (`activeLabelId = l*`):** Single candidate context $\{C_1\}$ resolved via Step 1 against the selected `label` $l^*$ (whether regular or `scoped`).
   - **Unfiltered Global View ($L(T) \neq \varnothing$, retained by `TDF-EVAL-001`):** Ignore `scoped` labels and form candidate contexts strictly from non-`scoped` assigned labels:
     $$L_{\text{global}}(T) = \{\, l \in L(T) \mid \neg\text{isScoped}(l) \,\}$$
     Each $l_i \in L_{\text{global}}(T)$ forms a self-contained effective context $C_i$ under Step 1 (NEVER pool `day`, `time`, and `location` rules across distinct labels). Evaluate $\{C_1, \dots, C_k\}$ in ascending ASCII `<label-id>` order with logical `OR` across contexts (`OR` short-circuit at the first satisfied $C_i$).

#### 9.2.2 Rule Semantics and Short-Circuit Group Order (`TDF-EVAL-003`)

Individual rule types evaluate as follows:

1. **Weekday Rule (`day <d1> [<d2> ...]`):** `true` when `localNow`'s weekday matches at least one listed `<weekday>`. Multiple `day` rules in the same group combine with logical `OR`.
2. **Time Window Rule (`time <start> <end>`):**
   - **Same-day window (`start < end`):** `true` when `start <= localCurrentMinute <= end` (inclusive endpoints, such as `08:00` to `20:00`).
   - **Overnight window (`start > end`):** Spans midnight; `true` when `localCurrentMinute >= start || localCurrentMinute <= end` (such as `22:00` to `06:00`).
   - Multiple `time` rules in the same group (such as `08:00 12:00` and `14:00 18:00`) combine with logical `OR`.
3. **Geofence Location Rule (`location <loc-1> [<loc-2> ...]`):**
   - If `currentCoordinates` is `absent`, evaluate to `true`.
   - Otherwise, compute the offline great-circle Haversine distance (using mean Earth radius $R = 6\,371\,000\text{ m}$) between `currentCoordinates` and each referenced live `location` block `loc_i.coordinates`; evaluate to `true` as soon as $\text{distance} \le \text{loc}_i.\text{radius}$ holds for at least one `<location-id>` (logical `OR` short-circuit).

Evaluate each candidate context $C$ in deterministic order of increasing computational cost — **`1. day` -> `2. time` -> `3. location`**:

- **Empty Group (`G = ∅`):** Satisfied (`true`); advance to the next group.
- **Non-Empty Group (`|G| >= 1`, Intra-Group `OR`):** Test rules (and `<location-id>` tokens) in order; short-circuit the group to `true` at the first `true` item.
- **Group Failure (Inter-Group `AND`):** If every rule in a non-empty group is `false`, short-circuit context $C$ immediately to `false` without evaluating subsequent groups in $C$.

Formally, for group $G$, context $C$, and candidate context list $\{C_1, \dots, C_k\}$:

$$\text{isGroupSatisfied}(G) = (G = \varnothing) \lor \bigvee_{r \in G}\text{evaluate}(r)$$

$$\text{isContextSatisfied}(C) = \text{isGroupSatisfied}(C.\text{day}) \land \text{isGroupSatisfied}(C.\text{time}) \land \text{isGroupSatisfied}(C.\text{location})$$

$$\text{isSatisfied} = \bigvee_{i=1}^{k} \text{isContextSatisfied}(C_i)$$

### 9.3 Prerequisite Satisfaction (`TDF-EVAL-004`)

For each entry `(targetId -> requiredCompletion)` in an open task's `blocked` map ([Section 5.2.2](#522-prerequisite-dependencies-blocked-tdf-dir-002)):

- Look up `targetId` across **all** live `task` blocks in the document (ignoring `scoped` and `activeLabelId`).
- If `targetId` is absent from live `task` blocks (whether tombstoned in `deleted` or an unknown forward reference), the entry is **satisfied** (non-blocking).
- If `targetId` matches live task $P$, the entry is **satisfied** when and only when:
  $$P.\text{completions} \ge \text{requiredCompletion}$$
  Once satisfied, subsequent recurring completions of $P$ keep $P.\text{completions} \ge \text{requiredCompletion}$ true and never re-block the current dependent occurrence. A bare `blocked <task-id>` token always requires completion `1`, even if $P.\text{completions}$ already exceeds `1`.

### 9.4 Six-Tier Classification Pipeline (`TDF-EVAL-005`)

Classify every task $T$ retained by [Section 9.1](#91-pre-filtering-and-scoped-label-exclusion-tdf-eval-001) into exactly one of the six operational tiers:

1. **Tier 6 — `Completed`:**
   - **Selection:** All retained tasks with `finished` present.
   - **Behavior:** Ignore `suspended`, `due`, `blocked`, and `condition` for tier classification. Retain `history`, `origin`, `link`, and any preserved `(due, anchor, passive, due-note)` intact. (Garbage collection of tasks with `now - finished > 2_592_000` seconds runs only during guarded persistence under [Section 13.2](#132-thirty-day-retention-pruning-tdf-pub-004), never during loading or evaluation.)
2. **Tier 5 — `Someday`:**
   - **Selection:** Retained open tasks (`finished` absent) whose `<task-id>` is **not** in `queue` and that have **no** active `suspended` deferral (`suspended` is absent or finite `suspended <= now` in UTC).
   - **Behavior:** Unscheduled backlog; excluded from the active pull cycle regardless of `due` (even when `due <= now + W_due` or overdue).
3. **Tier 4 — `Blocked`:**
   - **Selection:**
     - Any retained open task **in `queue`** that fails at least one restriction below, OR
     - Any retained open task **not in `queue`** that carries an active `suspended` deferral (`forever` or finite `suspended > now` in UTC; once a finite `suspended` on a task outside `queue` expires at `suspended <= now`, it classifies directly as `Someday` above).
   - **Deterministic Restriction Order:**
     1. *Active Deferral (`suspended`):* `forever` or `suspended > now` in UTC (`TDF-CTX-002`) -> classify immediately as `Blocked` without testing `blocked` or `condition`.
     2. *Unmet Prerequisite (`blocked`):* At least one live target in `T.blocked` has `P.completions < requiredCompletion` (`TDF-EVAL-004`) -> classify as `Blocked`.
     3. *Unmet Condition (`condition`):* $\text{isSatisfied} = \text{false}$ under `TDF-EVAL-002`–`TDF-EVAL-003` -> classify as `Blocked`.
   - `due` (including overdue `due <= now`) NEVER classifies a task as `Blocked` and NEVER overrides a Tier 4 restriction.
   - **Slot Non-Consumption:** Tasks in `queue` classified as `Blocked` consume zero `Focus` or `Ready` slots while keeping their exact saved position in `queue` so they reclaim their slot automatically when all restrictions clear.
4. **Active Pull Cycle — Tier 1 `Focus`, Tier 2 `Ready`, and Tier 3 `Planned`:**
   - **Step 1 (Filter Queue):** Filter `queue`'s ordered `<task-id>` list to retain open tasks that passed [Section 9.1](#91-pre-filtering-and-scoped-label-exclusion-tdf-eval-001) and were not classified as `Blocked`, preserving saved `queue` order.
   - **Step 2 (Effective Priority Partition):** For each executable task $T$ from Step 1, evaluate:
     $$\text{isDueUrgent}(T, \text{now}, W_{\text{due}}) \iff W_{\text{due}} \neq \text{absent} \;\land\; T.\text{due} \neq \text{absent} \;\land\; \neg T.\text{passive} \;\land\; T.\text{due} \le \text{now} + W_{\text{due}}$$
     $$\text{hasEffectivePriority}(T, \text{now}, W_{\text{due}}) \iff T.\text{priority} \;\lor\; \text{isDueUrgent}(T, \text{now}, W_{\text{due}})$$
     Exact boundary equality ($T.\text{due} - \text{now} = W_{\text{due}}$) yields `isDueUrgent = true`, and overdue tasks ($T.\text{due} \le \text{now}$) satisfy $T.\text{due} \le \text{now} + W_{\text{due}}$ for every $W_{\text{due}} \ge 0$ (including $W_{\text{due}} = 0$). Partition the Step 1 sequence stably into two buckets without sorting by `due` timestamp or block declaration order:
     - First, all tasks with $\text{hasEffectivePriority} = \text{true}$ in saved `queue` order;
     - Second, all tasks with $\text{hasEffectivePriority} = \text{false}$ in saved `queue` order.
   - **Step 3 (Bounded Slot Slicing):** Slice positions `1..3` into `Focus` (`Tier 1`, at most `3` tasks), positions `4..8` into `Ready` (`Tier 2`, at most `5` tasks), and positions `9..N` into `Planned` (`Tier 3`). Recompute the entire assignment from scratch whenever restrictions, `now`, $W_{\text{due}}$, or `activeLabelId` change (so an unblocked earlier task can displace current `Focus` tasks into `Ready` and `Ready` tasks into `Planned` without rewriting `queue` or `modified`). With indexed task lookup, Steps 1–3 run in $O(|\text{queue}|)$ time plus condition/prerequisite checks.

*Illustration (Informative):* For ten tasks `A..J` in `queue` in saved order with equal effective priority:

| Condition State | `Focus` (`1..3`) | `Ready` (`4..8`) | `Planned` (`9..N`) | `Blocked` |
| :--- | :--- | :--- | :--- | :--- |
| `A` is blocked | `B, C, D` | `E, F, G, H, I` | `J` | `A` |
| `A` becomes eligible | `A, B, C` | `D, E, F, G, H` | `I, J` | *(empty)* |

## 10. Mutations and Lifecycle Transitions

### 10.1 Mutation Contract, Revisions, and Cleanup Matrix

#### 10.1.1 Atomic Mutation Contract (`TDF-MUT-001`)

Every domain mutation in [Section 10.4](#104-individual-mutations-and-lifecycle-actions) obeys this uniform contract unless an individual action specifies an additional rule:

| Contract Element | Requirement |
| :--- | :--- |
| **Captured Context** | Capture one UTC instant `now` (and configured `timeZone` / evaluation parameters where required) for the complete transaction. |
| **Pure No-Op Guard** | If preconditions make the command a pure no-op (for example, downgrading a task outside `Focus`/`Ready`/`Planned`, retrying an already applied `expectedCompletions`, or editing `history` without changing the normalized set), leave all entities, `queue`, and revisions untouched and **skip** board-wide block-reason cleanup. |
| **Atomic Application** | Apply entity changes, `queue` updates, deletion cascades, and open-task block-reason cleanup (`TDF-CLEAN-001`) together in memory on an immutable candidate copy. |
| **Revision Update** | Advance `modified` at most **once** per changed entity or changed `queue` in the transaction (`TDF-MUT-002`). Never advance `modified` on bystander tasks merely because their derived tier shifted. |
| **Validation & Rollback** | Validate the complete candidate document against all [Section 6](#6-validation-and-resource-bounds) and [Section 7.1](#71-canonical-serialization-contract-tdf-ser-001) rules before guarded publication ([Section 13.1](#131-candidate-validation-and-guarded-publication)). On any validation or persistence error, abort and preserve the complete prior document and baseline unchanged. |

#### 10.1.2 Entity and Queue Revision Rules (`TDF-MUT-002`)

- **Effective Revision Fallbacks (Read-Only, Without Mutating the Entity):**
  - `task`: `task.modified` when present; otherwise $\max(\text{created}, \text{finished})$ over present timestamps in UTC.
  - `label` or `location`: `modified` when present; otherwise `1970-01-01 00:00:00` UTC.
  - `queue`: `queue.modified` when `queue` is present; otherwise `1970-01-01 00:00:00` UTC.
- **Standard Mutation Revision Formula:** Whenever an ordinary mutation (or open-task cleanup during a committed mutation) changes an existing `task`, `label`, `location`, or `queue` at UTC instant `now`, set its explicit UTC second-precision `modified` timestamp to:
  ```text
  modified = max(now, previousEffectiveModifiedAt + 1 second)
  ```
  If the resulting timestamp exceeds `9999-12-31 23:59:59` UTC, fail the entire mutation with `InvalidTimestamp`. Newly created entities initialize `modified = now` in UTC ([Section 10.4.1](#1041-creating-entities-tdf-mut-003)). Synchronization result revisions follow [Section 12.2.3](#1223-result-revision-assignment-tdf-merge-004) and [Section 12.7](#127-shared-queue-reconciliation-tdf-qsync-001).

#### 10.1.3 Open-Task Block-Reason Cleanup Predicates (`TDF-CLEAN-001`)

This subsection is the sole authoritative definition of the open-task block-reason cleanup predicates. When invoked at UTC instant `now` against a target set of tombstoned task IDs (`deletedTasks`) and live tasks (`liveTasks`), inspect each live **open** task $D$ (`finished` absent):

1. **Expired Finite Deferrals:** If $D.\text{suspended}$ is a finite UTC timestamp with $D.\text{suspended} \le \text{now}$, remove both `suspended` and any attached `suspended` `<note>` from $D$ (open tasks in `queue` keep their exact `queue` position with `queue.modified` unchanged; open tasks outside `queue` remain in `Someday`; `suspended forever` never expires by wall-clock time).
2. **Confirmed Deleted Prerequisites:** Remove every `<target-id>[:<req>]` entry from $D.\text{blocked}$ where `<target-id>` is in `deletedTasks` (omitting `blocked` when empty).
3. **Satisfied Non-Recurring-to-Recurring Prerequisites:** Remove every `<target-id>[:<req>]` entry from $D.\text{blocked}$ where `<target-id>` matches a live task $T_{\text{target}} \in \text{liveTasks}$ satisfying $T_{\text{target}}.\text{completions} \ge \text{req}$ **and** ($D.\text{repeat} = \text{absent}$ $\lor$ $T_{\text{target}}.\text{repeat} = \text{absent}$), omitting `blocked` when empty.
4. **Preserved Items:** Retain `<target-id>[:<req>]` when **both** $D.\text{repeat}$ and $T_{\text{target}}.\text{repeat}$ are present (until $D$ completes its occurrence and rearms under `TDF-OCC-001`), retain unknown forward references (`<target-id>` in neither `liveTasks` nor `deletedTasks`), retain overdue `due <= now` deadlines (with `anchor`, `passive`, and `due` `<note>`), and retain `condition` rules.

#### 10.1.4 Cleanup Matrix Across Lifecycle Stages (`TDF-CLEAN-002`)

Because cleanup timing, target snapshot, and revision behavior differ across parsing, evaluation, mutation, multi-stage synchronization, and retention pruning, implementations MUST apply `TDF-CLEAN-001` and retention cleanup strictly according to this matrix:

| Stage / Operation | Trigger Timing | Inspected Snapshot | Effect on Stored Data | Effect on Revisions / Generation | Governing Rules |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Parsing & Read-Only Loading** | On file read | Input `.tdf` document | Decode and normalize values only; **zero** time-dependent or prerequisite cleanup | **None** (`sourceDigest` preserved) | `TDF-MODEL-001` |
| **2. Pure Tier Evaluation** | At one captured `now` | Immutable in-memory model | Treat `suspended <= now` and missing/satisfied `blocked` as non-blocking in view projection only | **None** | `TDF-CTX-002`, `TDF-EVAL-005` |
| **3. Ordinary Committed Mutation** | After applying a non-no-op mutation, before publication | Candidate board after requested mutation | Apply `TDF-CLEAN-001` across all live open tasks | Advance `D.modified` once via `TDF-MUT-002` on each task whose stored directives changed | `TDF-MUT-001`, `TDF-CLEAN-001` |
| **4. Merge Pre-Normalization (`cleanupMode = final`)** | Before Case 2 unit comparison on final/single-stage sync | Each variant $V \in \{B, L, R\}$, using $V.\text{repeat}$ against `(mergedTasksById, mergedDeletedTasks)` | Compute comparison copies (`V.suspended <= now -> absent`, resolved `V.blocked` entries `-> absent`); keep raw `B, L, R` intact for winner `W` | Do not alter input revisions; result revision computed in Phase 8 (`TDF-MERGE-004`) | `TDF-MERGE-009`, `TDF-MERGE-010` |
| **5. Merge Post-Cleanup (`cleanupMode = final`)** | After entity merge and label/location cascades on final/single-stage sync | Merged candidate $M_{\text{uncleaned}}$ (using merged $D_M.\text{repeat}$) | Strip remaining `TDF-CLEAN-001` items to form $M_{\text{clean}}$ | If $M_{\text{clean}} \neq M_{\text{uncleaned}}$ (and $\neq G$), set `modified = max(now, max_{X in I}(X.effectiveModifiedAt) + 1s)` | `TDF-MERGE-004`, `TDF-MERGE-011` |
| **6. Intermediate Local Stage Before Remote Sync (`cleanupMode = deferred`)** | Intermediate cache/file reconciliation or pre-sync mutation rebasing | Raw revisions and uncleaned intermediate candidate | **Defer** both Case 2 pre-normalization and post-merge block cleanup ($M_{\text{clean}} = M_{\text{uncleaned}}$) | Preserve un-inflated revisions (clock-free `+ 1s` only on non-cleanup edits) so final remote winner `W` is never shifted | `TDF-MERGE-009`, `TDF-MERGE-004` |
| **7. Tombstone & `Completed` Retention Expiry** | During guarded publication against authoritative shared source | Current shared source snapshot at `now` | Prune `Completed` tasks with `now - finished > 2_592_000s` into `deleted`; remove `deleted` records with `now - ts > 2_592_000s` and strip remaining `blocked <id>` on all live tasks (including `Completed`) | New tombstones use `TDF-MUT-002` (`generation` unchanged); expiring `>= 1` tombstone increments `deleted.generation` once and updates affected task `modified` | `TDF-PUB-004` |

### 10.2 Local Calendar Resolution and Recurrence Calculation

#### 10.2.1 Resolving Local Calendar Inputs to UTC (`TDF-CAL-001`)

When a scheduling mutation ([Section 10.4.6](#1046-ordinary-directive-and-entity-mutations-tdf-mut-008)) or recurrence calculation (`TDF-CAL-002`–`TDF-CAL-003`) resolves a local civil date and clock `(Y, M, D, h, m, s)` (defaulting a date-only local input to `00:00:00` local midnight) in a configured IANA `timeZone`:

1. **Unique Instant:** If `(Y, M, D, h, m, s)` identifies exactly one UTC instant in `timeZone`, select that instant.
2. **Autumn Overlap (Fold):** If `(Y, M, D, h, m, s)` occurs twice during a backward clock transition, select the **first** occurrence (the earlier UTC instant, following [RFC 5545, Section 3.3.5](https://www.rfc-editor.org/rfc/rfc5545#section-3.3.5)).
3. **Spring Forward Gap:** If `(Y, M, D, h, m, s)` falls inside a nonexistent forward clock gap, apply the UTC offset that was in effect immediately **before** the gap (shifting the resolved local wall time forward by the gap duration while keeping `<repeat-time>` and `due.anchor` unshifted at `(h, m, s)`).

Require `timeZone`'s transition rules (`TimeZoneContextRequired` if unavailable). Reject any input or converted UTC instant outside `0001-01-01 00:00:00..9999-12-31 23:59:59` with `InvalidTimestamp`, and persist converted UTC `suspended` and `due` instants with explicit `YYYY-MM-DD HH:MM:SS` seconds.

#### 10.2.2 Mode 1 Completion-Relative Recurrence (`due` Omitted) (`TDF-CAL-002`)

When completing a recurring task (`repeat <count> <unit> [<repeat-time>] [lead <lead-count> days]`) that has **no `due` directive** (`due == absent`, so `leadDays` is ignored):

1. Convert completion instant `now` (UTC) into `localNow` in `timeZone`.
2. Add `<count> <unit>` to `localNow`'s local calendar date:
   - `days`: add `<count>` calendar days; `weeks`: add `7 * <count>` calendar days.
   - `months`: advance `(year, month)` by `<count>` proleptic Gregorian months and clamp the day to $\min(\text{sourceDay}, \text{daysInMonth}(Y', M'))$.
3. Combine the target local date with `repeat`'s normalized `<repeat-time>` (`00:00:00` when omitted).
4. Resolve to UTC via `TDF-CAL-001` to obtain `nextSuspended`.
5. Require `nextSuspended > now` within `0001-01-01 00:00:00..9999-12-31 23:59:59` UTC (`InvalidTimestamp` if out of range).
6. Set `suspended = nextSuspended` with no `suspended` `<note>`.

#### 10.2.3 Mode 2 Schedule-Anchored Recurrence With `due` (`TDF-CAL-003`)

When completing a recurring task (`repeat <count> <unit> [<repeat-time>] [lead <lead-count> days]`) that **carries `due`** (`oldDue`, optional `oldAnchor`, `passive`, optional `due` `<note>`):

1. **Resolve Local Schedule Anchor `(Y_a, M_a, D_a, h_a, m_a, s_a)`:** Extract `(Y_a, M_a, D_a, h_a, m_a, s_a) = oldAnchor` when `oldAnchor != absent`; otherwise (`oldAnchor == absent`), convert `oldDue` (UTC) into local calendar components `(Y_a, M_a, D_a, h_a, m_a, s_a)` in `timeZone`.
2. **Advance `due` Beyond `max(oldDue, now)`:** Let `referenceUtc = max(oldDue, now)` and compute the target occurrence date `(Y'_d, M'_d, D'_d)` and `newDue` in $O(1)$ calendar arithmetic (without unbounded step-by-step iteration):
   - **For `days` and `weeks`:** Advance `(Y_a, M_a, D_a)` by $k \times \text{<count>}$ calendar days (`days`) or $7 \times k \times \text{<count>}$ calendar days (`weeks`) to `(Y'_d, M'_d, D'_d)` for the smallest integer $k \ge 1$ such that resolving `(Y'_d, M'_d, D'_d, h_a, m_a, s_a)` via `TDF-CAL-001` yields `newDue > referenceUtc` (`InvalidTimestamp` if out of range).
   - **For `months`:** Convert `oldDue` (UTC) in `timeZone` to obtain the current occurrence's local year-month `(Y_cur, M_cur)`. Find the smallest integer $k \ge 1$ such that advancing `(Y_cur, M_cur)` by $k \times \text{<count>}$ proleptic Gregorian months to `(Y'_d, M'_d)` with day clamped against the **anchor day** $D'_d = \min(D_a, \text{daysInMonth}(Y'_d, M'_d))$ and clock `(h_a, m_a, s_a)` resolved via `TDF-CAL-001` yields `newDue > referenceUtc` (`InvalidTimestamp` if out of range).
3. **Update or Preserve `due.anchor` (`newAnchor`):**
   - For `days` and `weeks`, and for `months` when unclamped ($D'_d = D_a$), set `newAnchor = (Y'_d, M'_d, D'_d, h_a, m_a, s_a)`.
   - For `months` when clamped ($D'_d < D_a$, such as $D_a = 31$ clamped to `28` in February or `30` in April, or $D_a = 29$ in a non-leap February), set `newAnchor = (Y_a, M_a, D_a, h_a, m_a, s_a)` (preserving `oldAnchor` when already present, or persisting `oldDue`'s derived `(Y_a, M_a, D_a, h_a, m_a, s_a)` on initial clamp) so `newAnchor` is always a valid Gregorian `<timestamp>` while retaining `D_a` (`29..31`) and `(h_a, m_a, s_a)` across clamped months and `repeat` interval changes.
4. **Compute Preparation Date:** Subtract `leadDays` (`0` when `lead` is omitted) calendar days from `(Y'_d, M'_d, D'_d)` to obtain `targetSuspendedLocalDate` (`InvalidTimestamp` if outside `0001-01-01..9999-12-31`).
5. **Resolve Wake-Up Instant:** Combine `targetSuspendedLocalDate` with `repeat`'s `<repeat-time>` (`00:00:00` when omitted), resolve to UTC via `TDF-CAL-001` to obtain `candidateSuspended`, and clamp `newSuspended = min(candidateSuspended, newDue)`.
6. **Commit Next Occurrence Deadline & Deferral:** Set `due = newDue`, `due.anchor = newAnchor`, reset occurrence-scoped `passive = false` (omitted), preserve `due`'s `<note>` unchanged, clear any `suspended` `<note>`, and either set `suspended = newSuspended` when `newSuspended > now` or **omit `suspended` immediately when `newSuspended <= now`** (making an overdue occurrence completed inside the next cycle's open preparation window immediately eligible without persisting an expired deferral).

Manual `suspended` edits (snoozing a single occurrence, even past `due`) modify only `suspended` and MUST NOT alter `<repeat-time>`, `leadDays`, or `due.anchor`.

### 10.3 Completion Counters and Prerequisite Arming (`TDF-OCC-001`)

- **Monotonic Counter (`completions`):** Numbers completed occurrences (`0..MAX_COMPLETIONS`, `0` omitted canonically) within a task's lifetime identity. It MUST NOT decrease during ordinary mutations, restoration, Undelete, or synchronization, and fails with `LimitExceeded` before overflowing `MAX_COMPLETIONS`. Concurrent completions of the same occurrence count once (`Section 12.4.2`).
- **Arming & Rearming Prerequisite Thresholds (`blocked`):** When adding a new `<target-id>` to `blocked`, or rearming retained prerequisites upon recurring task completion (`TDF-MUT-006`) or restoration from `Completed` (`TDF-MUT-007`), capture `requiredCompletion` from a single consistent board snapshot (`LimitExceeded` if `> MAX_COMPLETIONS`):
  - Existing **open** prerequisite (`finished` absent): `prerequisite.completions + 1`.
  - Existing **finished** prerequisite (`finished` present): `prerequisite.completions` (already satisfied; stripped on open non-recurring-to-recurring dependents by `TDF-CLEAN-001`).
  - **Missing** forward-reference prerequisite: `1` when newly added, or its existing stored `requiredCompletion` when rearming.
  - Editing `blocked` retains the existing `requiredCompletion` for any `<target-id>` kept in the list; removing and re-adding `<target-id>` captures a fresh requirement. Changing `repeat`, `queue`, `priority`, `suspended`, `due`, or `condition` alone MUST NOT rearm existing `blocked` thresholds.
- **Guarded Atomic Completion (`expectedCompletions`):** Every completion command (explicit user completion or `subtasks auto-finish` trigger) MUST specify `expectedCompletions`. If the task already has `finished` present or `task.completions != expectedCompletions`, treat the command as a pure no-op (`TDF-MUT-001`) so command retries never advance two occurrences. Setting all checklist steps to `true` or `false` during completion, restoration, or synchronization MUST NOT recursively trigger another completion.

### 10.4 Individual Mutations and Lifecycle Actions

All actions below inherit the atomic mutation, cleanup, validation, and rollback contract of [Section 10.1](#101-mutation-contract-revisions-and-cleanup-matrix).

#### 10.4.1 Creating Entities (`TDF-MUT-003`)

- **Precondition:** Validate all supplied directives under [Section 5](#5-entity-and-directive-reference) and document bounds (`MAX_BLOCKS_PER_DOC`, `MAX_LOCATIONS`, `MAX_QUEUE_ENTRIES`, etc.).
- **State Change:** Generate a unique 10-character Base62 ID under `TDF-ID-001`. Initialize `completions = 0` on tasks (`omitted` canonically).
  - *Scheduled Task (`Planned`, or `Focus` with `priority`):* Set `created = now` and `modified = now` in UTC, set `priority = true` when targeting `Focus`, append `<task-id>` to `queue`, and advance `queue.modified` via `TDF-MUT-002`.
  - *Unscheduled Task (`Someday`):* Set `created = now` and `modified = now` in UTC; leave `queue` and `queue.modified` unchanged.
  - *Label or Location:* Create `label` (`[scoped]`) or `location` with `modified = now` in UTC; leave `queue` unchanged.

#### 10.4.2 Scheduling, Moving to `Someday`, and Explicit Queue Moves (`TDF-MUT-004`)

- **Scheduling from `Someday`:** For an open task not in `queue`, append `<task-id>` to the end of `queue` and advance `queue.modified`, preserving `(due, anchor, passive, due-note)`, `origin`, and `history`. When explicitly promoting to `Focus` (`priority` set to `true`), also reset `due.passive` to `false` (omitted) and advance `task.modified`; if zero task-level attributes change, leave `task.modified` unchanged.
- **Moving to `Someday`:** Remove `<task-id>` from `queue` and advance `queue.modified` (if it was in `queue`). Strip `priority` and `suspended` (with any `suspended` `<note>`) if present, advancing `task.modified` only when `priority` or `suspended` was removed. Preserve `(due, anchor, passive, due-note)`, `origin`, and `history`.
- **Explicit Queue Reordering:** Remove an existing `<task-id>` from `queue` and insert it immediately before or after a specified anchor `<anchor-task-id>` (which MUST exist in the current `queue` and differ from `<task-id>`) or at the end of `queue`. Advance `queue.modified` only if the ordered list changed; leave `task.modified` unchanged unless `priority` was simultaneously modified.

#### 10.4.3 Downgrading Active Tasks (`Focus`, `Ready`, `Planned`) (`TDF-MUT-005`)

Evaluate the board under [Section 9](#9-tier-derivation) at the active evaluation context (`now`, `localNow`, `timeZone`, $W_{\text{due}}$, `activeLabelId`, `currentCoordinates`). If target task $T$'s derived tier is outside `{Focus, Ready, Planned}`, return as a pure no-op (`TDF-MUT-001`). Let $E_{\text{ctx}}$ be the [Section 9.4](#94-six-tier-classification-pipeline-tdf-eval-005) Step 2 effective-priority-partitioned sequence of **other** executable tasks (`[...focus, ...ready, ...planned]` excluding $T$) in the active context (`activeLabelId = absent` excluding `scoped`-only tasks, or `activeLabelId = l*`):

1. **Downgrade from `Focus` to `Ready` (Context-Relative Slot-8 Anchor):**
   - *Case A (`|E_ctx| >= 7` and the 7th task in $E_{\text{ctx}}$ has `hasEffectivePriority == true`):* Preserve `due.anchor`, `T.passive`, `due` `<note>`, and `history`; keep `T.priority` unchanged if `isDueUrgent(T, now, W_due)` is `true` (never stripping explicit `priority` while `due` is urgent) or set `T.priority = true` when `isDueUrgent` is `false` (advancing `task.modified` only if `T.priority` changed from `false` to `true`); move $T$ in `queue` immediately after the **7th task in $E_{\text{ctx}}$** so $T$ occupies executable slot `8` (`Ready`).
   - *Case B (`|E_ctx| < 7` or the 7th task in $E_{\text{ctx}}$ has `hasEffectivePriority == false`):* Strip `T.priority` if present **and** set `T.passive = true` when `isDueUrgent(T, now, W_due)` is `true` (preserving `due.anchor`, `due` `<note>`, and `history`, advancing `task.modified` if either flag changed). Move $T$ in `queue` immediately after the 7th task in $E_{\text{ctx}}$ when $|E_{\text{ctx}}| \ge 7$, immediately after the **last task in $E_{\text{ctx}}$** when $1 \le |E_{\text{ctx}}| < 7$, or keep $T$'s `queue` position when $|E_{\text{ctx}}| = 0$.
2. **Downgrade from `Ready` to `Planned`:** Strip `T.priority` if present and set `T.passive = true` when `isDueUrgent(T, now, W_due)` is `true` (preserving `due.anchor`, `due` `<note>`, and `history`, advancing `task.modified` only if an attribute changed), and move $T$ to the **end of `queue`** (entering `Planned` at slot `>= 9` when `>= 8` other executable tasks exist, or occupying the last available `Focus`/`Ready` slot when `< 8` exist).
3. **Downgrade from `Planned` to `Someday`:** Execute Moving to `Someday` (`TDF-MUT-004`).

Preserve the relative `queue` order of all other tasks (including `Blocked` tasks and tasks outside `activeLabelId`). Advance `queue.modified` only if `queue` order/membership changed. If neither `T`'s attributes nor `queue` order changed (for example, downgrading a non-effective-priority task already at the end of `queue`), return as a pure no-op (`TDF-MUT-001`).

#### 10.4.4 Completing a Task (`TDF-MUT-006`)

Guard the command with `expectedCompletions` (`TDF-OCC-001`):

- **Standard Task (`repeat` Omitted):** Increment `completions` by `1`, set `finished = now` in UTC, set every `subtasks` `step` to `true`, clear `suspended` (with any `suspended` `<note>`) and `blocked` on the completed task, preserve `(due, anchor, passive, due-note)`, `origin`, and all `history` entries intact, advance `task.modified` once, remove `<task-id>` from `queue` (advancing `queue.modified` if it was present), and run `TDF-CLEAN-001` across remaining open tasks (stripping newly satisfied non-recurring-to-recurring `blocked` references on open dependents).
- **Recurring Task (`repeat` Present):** Keep `finished` omitted, increment `completions` by `1`, reset every `subtasks` `step` to `false`, set `priority = true`, rearm retained `blocked` prerequisites for the new occurrence under `TDF-OCC-001`, preserve `origin` and all `history` entries intact without rotation, calculate the next schedule via Mode 1 (`TDF-CAL-002`, when `due` is omitted) or Mode 2 (`TDF-CAL-003`, when `due` is present), advance `task.modified` once, retain `<task-id>` at its existing `queue` position (or append `<task-id>` to `queue` and advance `queue.modified` if completed while not in `queue`), and run `TDF-CLEAN-001` across open tasks.

#### 10.4.5 Completed Checklists and Restoring From `Completed` (`TDF-MUT-007`)

- **Checklist Locking While `finished` Is Present:** While a task has `finished` present, existing `step` booleans remain locked at `true`; adding or removing steps is permitted, and any newly added step MUST be marked `true` and locked.
- **Restoring from `Completed`:** Requires a `finished` task and target tier in `{Someday, Planned, Focus}`:
  - Remove `finished`, `suspended` (including `forever`, expired timestamps, and any `suspended` `<note>`), and `due` (including `anchor`, `passive`, and any `due` `<note>`).
  - Preserve `completions`, `repeat` (including `<repeat-time>` and `lead`), `origin`, and `history` unchanged.
  - Reset all `subtasks` steps to `false` and rearm `blocked` prerequisites under `TDF-OCC-001`.
  - Scheduling target:
    - *`Someday`:* Strip `priority` if present; keep outside `queue` (`queue.modified` unchanged).
    - *`Planned`:* Strip `priority` if present; append `<task-id>` to `queue` and advance `queue.modified`.
    - *`Focus`:* Set `priority = true`; append `<task-id>` to `queue` and advance `queue.modified`.
  - Advance `task.modified` once and run `TDF-CLEAN-001` across open tasks.

#### 10.4.6 Ordinary Directive and Entity Mutations (`TDF-MUT-008`)

- **Setting or Clearing `suspended`:** Resolve local finite input via `TDF-CAL-001` (future UTC instant) or set `forever`, validate optional `<note>` (`TDF-TYPE-003`), append `<task-id>` to `queue` (advancing `queue.modified`) if not already in `queue` or preserve its existing `queue` position, and advance `task.modified`. Clearing `suspended` removes `suspended` and its `<note>`, preserves `queue` order, and advances `task.modified`. Editing/clearing `suspended`'s `<note>` alone advances `task.modified` once.
- **Setting or Clearing `due`:** Resolve intended local input `(Y_in, M_in, D_in, h_in, m_in, s_in)` to UTC `due` via `TDF-CAL-001` and store `due.anchor = (Y_in, M_in, D_in, h_in, m_in, s_in)` so intended month-end days (`29..31`) and pre-gap clocks are preserved; validate optional `<note>`; preserve `queue` membership and order unchanged (setting `due` on a `Someday` task NEVER adds it to `queue`); reset `passive` to `false` whenever `due` or `anchor` changes unless `passive` is explicitly supplied (explicitly setting `priority = true` also resets `passive = false`); advance `task.modified` once. Clearing `due` removes `due`, `anchor`, `passive`, and `due` `<note>`, preserves `queue`, and advances `task.modified`. Editing `passive` or `due` `<note>` alone advances `task.modified` once.
- **Setting or Clearing `repeat`:** Validate under `TDF-DIR-001`, preserve `suspended`, `(due, anchor, passive, due-note)`, `history`, `completions`, and existing `blocked` thresholds, advance `task.modified`, and run `TDF-CLEAN-001` (stripping any satisfied prerequisite made non-recurring-to-recurring when `repeat` is cleared).
- **Setting `blocked`:** Capture/preserve thresholds under `TDF-OCC-001` (preserving unknown forward references), enforce `<= 64` arguments and `CircularDependency` acyclicity (`TDF-VAL-003`), and advance `task.modified` without altering `completions`.
- **Setting or Clearing `origin`:** Validate `<namespace>` and `<external-key>` (`TDF-DIR-005`), preserve `queue`, and advance `task.modified` once.
- **Setting `link` (`task` or `label`):** Add, edit, reorder, or remove `link` entries (`TDF-DIR-006`) and advance `task.modified` or `label.modified` once (updating `label.link` leaves task revisions and `queue.modified` untouched).
- **Setting `history` (`task`):** Add `(timestampUtc, text)`, replace `(oldTs, oldText) -> (newTs, newText)` via `(history \ {(oldTs, oldText)}) ∪ {(newTs, newText)}` when `(oldTs, oldText)` is present, or remove `(timestampUtc, text)`, validating UTC `<timestamp>`, `<text>`, `<= MAX_HISTORY_PER_TASK` (`500` normalized entries), and `<= MAX_STMTS_PER_BLOCK` (`1_024`; guaranteed non-colliding for every valid canonical `task` block since `34 + 500 = 534 <= 1_024`). If the normalized `(timestampUtc, text)` set changed, update `task.history`, preserve `queue`, and advance `task.modified` once; if the normalized set is unchanged, return as a pure no-op (`TDF-MUT-001`).
- **Setting `condition` (`task` or `label`) or Updating `label` / `location` Fields:** Validate under [Sections 5.3–5.5](#53-the-label-block-tdf-ent-003) (coalescing `location` rules per entity) and advance the modified entity's `modified` once.

#### 10.4.7 Deleting Live Entities and Reference Cascades (`TDF-MUT-009`)

Deleting a live `task`, `label`, or `location` removes its root block and inserts its tombstone in `deleted` (creating `deleted` with `generation 0` if absent, **never** incrementing `deleted.generation`, and setting the tombstone timestamp via `TDF-MUT-002` against the deleted entity's prior effective revision) in one atomic transaction:

1. **Deleting a `task <id>`:**
   - Copy `task.completions` into the `deleted` `task` record's `<checkpoint>` when `completions >= 1` (`0` omitted). (`task.history` is deleted with the `task` block and never individually tombstoned.)
   - Remove `<id>` from `queue` (advancing `queue.modified` if present).
   - Strip `blocked <id>[:<req>]` immediately from all live **open** tasks (`finished` absent), omitting `blocked` when empty and advancing each affected open task's `modified` once. (Any stored `blocked <id>` on a `Completed` task is retired upon 30-day tombstone expiry under `TDF-PUB-004`.)
2. **Deleting a `label <id>` (With `scoped` Global-View Flood Protection):**
   - For every live task $T$ referencing `<id>`, let $L_{\text{before}}(T)$ and $L_{\text{after}}(T) = L_{\text{before}}(T) \setminus \{\text{id}\}$ be $T$'s label sets before and after removal (omitting `labels` when empty).
   - If $T$ was global-view-restricted before deletion ($L_{\text{before}}(T) \neq \varnothing \land \forall l \in L_{\text{before}}(T),\; \text{isScoped}(l)$), is left with **zero labels** ($L_{\text{after}}(T) = \varnothing$), and is listed in `queue`, **remove $T$ from `queue` (advancing `queue.modified`) and strip `T.priority` if present while preserving `suspended` (with its note), `(due, anchor, passive, due-note)`, `origin`, and `history`**.
   - Advance `T.modified` once on every task whose `labels` or `priority` changed.
3. **Deleting a `location <id>` (Strict `label`-Before-`task` Order & `location any` Cascade):**
   - **Step 1 (`label` blocks first):** Remove `<id>` from every live `label`'s `condition` `locationGroup`; if `0` `<location-id>` tokens remain on a `label`, clear its `locationGroup` to empty (omitting `condition` if all groups are empty) and advance `label.modified` once.
   - **Step 2 (`task` blocks second, against post-cascade labels):** Remove `<id>` from every live `task`'s `condition` `locationGroup`:
     - If `>= 1` live `<location-id>` tokens remain on $T$, keep the remaining tokens.
     - If removing `<id>` empties $T$'s `<location-id>` list **and** at least one live `label` in $T.\text{labels}$ still defines a non-empty post-cascade `locationGroup`, replace $T$'s emptied `location` rule with **`location any` (`condition location any`)** so $T$ does not silently inherit a label location restriction.
     - Otherwise, clear $T$'s `locationGroup` to empty (omitting `condition` if all groups are empty).
     - Advance `T.modified` once on each affected task.

## Part C: Synchronization and Persistence

Part C defines how Reconcilers and Mutating Clients combine concurrent modifications deterministically ([Sections 11–12](#11-synchronization-model-and-phase-overview)) and publish validated snapshots safely to local filesystems and WebDAV servers while managing 30-day retention and generation recovery ([Section 13](#13-guarded-publication-retention-pruning-and-recovery)).

## 11. Synchronization Model and Phase Overview

### 11.1 Reconciliation Contract (`TDF-SYNC-001`)

Synchronization reconciles decoded entity models using one revision timestamp per entity (`task`, `label`, `location`), one revision timestamp for `queue`, and one monotonic `deleted.generation` counter (without per-field or per-step timestamps):

| Contract Element | Specification |
| :--- | :--- |
| **Inputs** | Common baseline `B` (optional, proven via `TDF-MERGE-001`), local document `L`, incoming shared document `R`, optional `acknowledgedGeneration`, source fingerprint (`sourceDigest` / HTTP `ETag`), single captured UTC instant `now`, and `cleanupMode ∈ {final, deferred}`. |
| **Preconditions** | Both `L` and `R` (and `B`, when present) satisfy all [Part A](#part-a-format-and-document-model) validation rules (`TDF-VAL-001`–`TDF-VAL-003`), and `B` is bound to the active dataset and format version `0.8.0`. |
| **Named Intermediate States** | 1. Raw decoded snapshots `B`, `L`, `R`; 2. Combined tombstones (`mergedDeletedTasks`, `DeletedLabels`, `DeletedLocations`) and conflict set; 3. Raw complete-entity winners `W` and `Loser` (`TDF-MERGE-003`); 4. Pre-cascade label sets $L_{\text{before}}(T)$ and post-cascade $L_{\text{after}}(T)$ (`TDF-MERGE-006`); 5. Cascade-normalized `condition` models (`TDF-MERGE-007`); 6. Merged `(completions, finished, repeat)` map `mergedTasksById` and (in `final` mode) Case 2 pre-normalized task units (`TDF-MERGE-010`); 7. Uncleaned merged task payload $M_{\text{uncleaned}}$ and post-cleanup payload $M_{\text{clean}}$ (`TDF-MERGE-004`, `TDF-MERGE-011`); 8. Reconciled `queue` against live open non-evicted set `O` (`TDF-QSYNC-001`). |
| **Outputs** | Either a fully validated canonical `tdf 0.8.0` candidate `M`, OR a structured non-publishing outcome (`DeletionConflict`, `RecoveryRequired`, `SyncGenerationRollback`, or a [Part A](#part-a-format-and-document-model) error such as `CircularDependency` or `LimitExceeded`). |
| **Side-Effect Boundary** | Reconciliation computes `M` purely in memory without mutating `B`, `L`, `R`, or storage. Only a succeeding guarded publication ([Section 13.1](#131-candidate-validation-and-guarded-publication)) writes bytes and advances `sourceDigest`, `acknowledgedGeneration`, and durable baseline `B`. |
| **Core Invariants** | **Commutativity:** For fixed `B`, fixed `now`, and fixed `cleanupMode`, `merge(B, L, R)` and `merge(B, R, L)` produce identical payloads, `queue` order, and revisions. **Idempotence:** Merging identical already-clean snapshots advances zero revisions. **Protected Counters:** `completions` and `deleted.generation` never decrease. **Stage Fairness:** Intermediate stages in `cleanupMode = deferred` never inflate `modified` via `now`. |

### 11.2 Reconciliation Phase Pipeline and Dependencies (`TDF-SYNC-002`)

Reconcilers MUST execute the logical dependencies below in order (never reordering phases in a way that alters intermediate states):

1. **Phase 1 — Input Validation and Generation Gate ([Section 6](#6-validation-and-resource-bounds), [Section 13.3.1](#1331-generation-comparison-syncgenerationrollback-and-refresh-reconciliation-tdf-rec-001)):** Validate `L` and `R`. Compare `R.deleted.generation` against `acknowledgedGeneration`: abort on rollback (`SyncGenerationRollback`), or run the generation-refresh and `RecoveryRequired` ambiguity check when `R.deleted.generation > acknowledgedGeneration` or `acknowledgedGeneration` is unknown.
2. **Phase 2 — Tombstone Combination and `DeletionConflict` Screening ([Section 12.6](#126-deletion-records-checkpoints-and-deletionconflict)):** Combine deletion records, detect baseline-implied deletions within a compatible generation, and evaluate both direct non-cleanup payload edits and newly introduced references $A_X(T)$ / $A^{\text{loc}}_X(E)$ on raw `L` and `R` against opposing tombstones. Retain `DeletionConflict` entities without silent cascade stripping.
3. **Phase 3 — Raw Complete-Entity Winner Selection ([Section 12.2.2](#1222-complete-entity-winner-selection-tdf-merge-003)):** For each entity present on both `L` and `R`, select complete winner `W` (and opposing `Loser`) from **raw un-normalized** payloads and timestamps, checking for completion-counter regression below `B` (`RecoveryRequired`).
4. **Phase 4 — Surviving Entities and Pre-Cascade Label Reconstruction ([Section 12.3.2](#1232-label-reference-set-merge-and-pre-cascade-reconstruction-tdf-merge-006), [Section 12.5](#125-entity-presence-and-post-merge-cascades-tdf-merge-011)):** Determine surviving live `label`, `location`, and `task` entities (discarding unchanged cached copies deleted on the other side) and reconstruct each surviving task's $L_{\text{before}}(T)$ and $L_{\text{after}}(T) = L_{\text{before}}(T) \setminus \text{DeletedLabels}$.
5. **Phase 5 — Live `label` and `location` Merging in `label`-Before-`task` Order ([Section 12.3.1](#1231-merge-units-and-scalar-three-way-rules-tdf-merge-005), [Section 12.3.3](#1233-tombstone-stripping-and-group-wise-condition-merge-tdf-merge-007)):** Strip non-conflicting tombstoned `<location-id>`s from `label` variants and merge all surviving `label` and `location` blocks first so each post-cascade live label's `locationGroup` is known before merging tasks.
6. **Phase 6 — Surviving `task` Metadata and Occurrence Merging ([Section 12.3](#123-entity-merge-units-and-three-way-rules), [Section 12.4](#124-task-occurrence-reconciliation-and-stage-fairness)):** Resolve `mergedTasksById` `(completions, finished, repeat)` first; merge occurrence-independent task units (`name`, `note`, `labels`, `origin`, `link`, `history` set, and cascade-normalized `condition` evaluated against post-cascade $L_{\text{after}}(T)$) and `Task state` (Case 1 atomic vs. Case 2 unbundled, applying Case 2 pre-normalization strictly in `cleanupMode = final`). Apply `scoped` label deletion flood protection (`Section 12.5`) to produce $M_{\text{uncleaned}}$ (and Case 2 pre-normalized state).
7. **Phase 7 — Post-Merge Open-Task Block Cleanup ([Section 12.5](#125-entity-presence-and-post-merge-cascades-tdf-merge-011)):** In `cleanupMode = final`, apply `TDF-CLEAN-001` using merged $D_M.\text{repeat}$ to obtain $M_{\text{clean}}$; in `cleanupMode = deferred`, keep $M_{\text{clean}} = M_{\text{uncleaned}}$.
8. **Phase 8 — Entity Revision Assignment ([Section 12.2.3](#1223-result-revision-assignment-tdf-merge-004)):** Assign deterministic `modified` revisions to every surviving `label`, `location`, and `task` by comparing $M_{\text{clean}}$ and $M_{\text{uncleaned}}$ against greatest raw input $G$.
9. **Phase 9 — Shared `queue` Reconciliation and Full Candidate Validation ([Section 12.7](#127-shared-queue-reconciliation-tdf-qsync-001), [Section 13.1.1](#1311-complete-result-validation-tdf-pub-001)):** Merge `queue`, normalize entries against surviving open non-evicted task set `O`, assign `queue.modified`, and validate the complete candidate `M` (aborting on any unresolved `DeletionConflict` / `RecoveryRequired` or validation error before publication).

## 12. Reconciliation Rules

### 12.1 Common Baseline and Source Fingerprint (`TDF-MERGE-001`)

- A common baseline `B` is the last shared `.tdf` snapshot successfully published or acknowledged by the client prior to both `L` and `R`. Store `B` and its `acknowledgedGeneration` durably in client synchronization state (adding zero fields to `.tdf` entity blocks).
- Bind both the loaded working copy and `B` to the dataset, format version (`0.8.0`), entity identities, and the **exact byte length and lowercase SHA-256 digest (`sourceDigest`) of the raw `.tdf` byte stream** (paired with HTTP `ETag` on WebDAV). Never rely on filesystem `mtime` or inode numbers alone to detect external changes, and never infer common ancestry from `modified` timestamps alone.
- Apply per-unit three-way merging **only** when proven `B` contains that entity. When `B` is absent (or an entity was created independently on both sides), select complete winner `W` (`TDF-MERGE-003`) for all units of that entity **except** `task.history` (which unions via `TDF-MERGE-008`) and `queue` concurrent open additions (`TDF-QSYNC-001`).
- Any dataset switch MUST invalidate any baseline bound to another dataset, and any stored baseline not bound to format version `0.8.0` MUST be invalidated.

### 12.2 Payload Tuple Order, Complete Entity Winner, and Result Revisions

#### 12.2.1 Conflict-Resolving Payload Tuple Order (`TDF-MERGE-002`)

To break equal-timestamp ties without input-direction bias, construct normalized entity payload tuples ([Section 2.6](#26-decoded-value-normalization-and-structural-equality-tdf-model-006)) excluding `modified` (`priority`, `passive`, and `scoped` default to `false`; `completions` defaults to `0`):

| Tuple | Ordered Components |
| :--- | :--- |
| **Task payload** | `(name, note, created, labels, origin, link, history, condition, Task state)` |
| **Label payload** | `(scoped, name, note, color, link, condition)` |
| **Location payload** | `(name, note, Location geographic unit, radius)` |
| **Task state** | `(completions, priority, finished, suspended, due, repeat, blocked, subtasks)` |
| **Subtasks** | `(auto-finish, ordered (completed, text) steps)` (`absent` precedes a present checklist) |
| **Origin** | `(decodedNamespace, decodedExternalKey)` |
| **Link** | `(decodedTitle, decodedUri)` |
| **History entry** | `(utcComponents [UTC epoch seconds], decodedText)` |
| **Location geographic unit** | `((normalizedLat, normalizedLon), optionalDecodedSource)` |

Compare tuples and lists lexicographically at the first differing component: `absent < present`; `false < true`; integers numerically; strings (including `normalizedLat`, `normalizedLon`, `normalizedRadius`) by unsigned UTF-8 byte values; and when one list (`history`, `link`, `labels`, `blocked`, `steps`, `condition` rules) is an exact prefix of another, the shorter list precedes the longer list.

#### 12.2.2 Complete Entity Winner Selection (`TDF-MERGE-003`)

Given two raw un-normalized versions of the same entity `(namespace, id)`, select the greater version (`W`, with the other side denoted `Loser`) by testing these four criteria in order:

1. **Task Completion Progress (`task` only):** If `completions` differs, the greater `completions` counter wins.
2. **Effective Revision Timestamp:** Otherwise, the later `effectiveModifiedAt` (`TDF-MUT-002`) wins.
3. **Payload Tuple Tie-Break:** At equal `effectiveModifiedAt`, the greater payload tuple under `TDF-MERGE-002` wins.
4. **Explicit `modified` Presence:** At equal payloads and equal `effectiveModifiedAt`, a version carrying an explicit `modified` directive wins over a version omitting `modified`.

If all four criteria are equal, both versions are identical. Input order (`(L, R)` vs. `(R, L)`) MUST NEVER affect winner selection, and reusing an existing version preserves its explicit-versus-omitted `modified` state verbatim.

#### 12.2.3 Result Revision Assignment (`TDF-MERGE-004`)

Let $\mathcal{I} = \{B, L, R\}$ when `B` contains the entity, or $\mathcal{I} = \{L, R\}$ otherwise, and let $G$ be the greatest raw input version in $\mathcal{I}$ under `TDF-MERGE-003` ($G = W$ when `B` is absent). Fail with `InvalidTimestamp` if any calculated revision exceeds `9999-12-31 23:59:59` UTC:

- **For `label` and `location` entities:** If the final post-cascade payload equals $G$'s raw payload, preserve $G$'s `modified` (including omission); otherwise set $\text{modified} = \max_{X \in \mathcal{I}}(X.\text{effectiveModifiedAt}) + 1\text{ second}$.
- **For `task` entities:** Let $M_{\text{uncleaned}}$ be the merged task payload after `Section 12.3`–`12.4` reconciliation (including baseline-free `history` union when `B` is absent) and `Section 12.5` Points 1–2 `label`/`location` cascades **without** Case 2 `suspended <= now` or `blocked` pre-normalization and **without** `Section 12.5` Point 3 post-merge open-task block cleanup, and let $M_{\text{clean}}$ be the final task payload for the active `cleanupMode` ($M_{\text{clean}} = M_{\text{uncleaned}}$ throughout `cleanupMode = deferred`):
  1. **Idempotent Reuse of Greatest Existing Version:** If $G$'s raw un-normalized payload equals $M_{\text{clean}}$, preserve $G$'s existing `modified` verbatim (including omission).
  2. **Deterministic Clock-Free Merge Revision ($M_{\text{clean}} = M_{\text{uncleaned}}$):** Otherwise, if $M_{\text{clean}} = M_{\text{uncleaned}}$ (always true in `cleanupMode = deferred`, and true in `cleanupMode = final` whenever neither Case 2 pre-normalization nor post-merge block cleanup changed the payload), set without reading wall-clock `now`:
     ```text
     modified = max_{X in I}(X.effectiveModifiedAt) + 1 second
     ```
  3. **Block-Cleanup Revision (`cleanupMode = final` and $M_{\text{clean}} \neq M_{\text{uncleaned}}$):** Otherwise (strictly in `cleanupMode = final` when Case 2 pre-normalization or post-merge open-task block cleanup altered the payload relative to $M_{\text{uncleaned}}$), set:
     ```text
     modified = max(now, max_{X in I}(X.effectiveModifiedAt) + 1 second)
     ```

When canonical serialized output already matches the stored byte stream (`SHA256(out_bytes) == sourceDigest`), skip redundant write-back.

### 12.3 Entity Merge Units and Three-Way Rules

#### 12.3.1 Merge Units and Scalar Three-Way Rules (`TDF-MERGE-005`)

When `B`, `L`, and `R` all contain a live entity (with raw complete winner `W` from `TDF-MERGE-003`), keep entity `(namespace, id)` unchanged, take `task.created` from `W`, and reconcile units as follows:

| Entity | Merge Unit | Rule |
| :--- | :--- | :--- |
| `task`, `label`, `location` | `name`, `note` | Independent scalar units (three-way rule below). |
| `label` | `scoped`, `color`, complete `link` list | Three independent atomic units (three-way rule below). |
| `location` | `(coordinates, source)`, `radius` | Two independent atomic units; coupling `(normalizedLat, normalizedLon)` with optional `source` prevents hybrid mismatches between relocated coordinates and an edited old address. |
| `task` | `origin`, complete `link` list | Two independent atomic units (three-way rule below). |
| `task` | `labels` | Pre-cascade reconstruction + tombstone stripping (`TDF-MERGE-006`). |
| `task`, `label` | `condition` | `label`-before-`task` tombstone stripping + group-wise / `W`-anchored merge (`TDF-MERGE-007`). |
| `task` | `history` | Occurrence-independent `(timestampUtc, text)` set merge (`TDF-MERGE-008`). |
| `task` | `Task state` (`completions`, `priority`, `finished`, `suspended`, `due`, `repeat`, `blocked`, `subtasks`) | Two-level occurrence merge gated by `cleanupMode` (`TDF-MERGE-009`–`TDF-MERGE-010`). |

For every normalized scalar or atomic unit `(B.u, L.u, R.u)` (treating clearing an optional field to `absent` as an explicit value change and using the same `W` across all true unit conflicts):

1. If `L.u == R.u`, keep `L.u`.
2. Else if `L.u == B.u`, keep `R.u`.
3. Else if `R.u == B.u`, keep `L.u`.
4. Otherwise, keep `W.u`.

#### 12.3.2 Label Reference Set Merge and Pre-Cascade Reconstruction (`TDF-MERGE-006`)

For each side $X \in \{L, R\}$, let $D^{\text{label}}_X$ be the set of `<label-id>`s deleted on side $X$ (listed in $X.\text{deleted}$'s label records, or present in proven `B`'s live `label` blocks and absent from $X$'s live `label` blocks within a compatible generation), and let $\text{DeletedLabels}$ be the set of non-conflicting tombstoned `<label-id>`s in the merged `deleted` block (excluding `DeletionConflict` labels, since any newly added reference $l \in A_L(T) \cup A_R(T)$ targeting an opposing tombstone is classified as `DeletionConflict` in `TDF-DEL-002` rather than silently stripped).

Exclude cascade-driven absences ($D^{\text{label}}_X$) from explicit unassignments to reconstruct each surviving task $T$'s pre-cascade label set $L_{\text{before}}(T)$:

- **With Common Baseline ($T \in B$, $T$ live on both `L` and `R`):**
  ```text
  added            = (L.labels minus B.labels) union (R.labels minus B.labels)
  explicitRemovedL = (B.labels minus L.labels) minus D_label_L
  explicitRemovedR = (B.labels minus R.labels) minus D_label_R
  L_before(T)      = (B.labels minus (explicitRemovedL union explicitRemovedR)) union added
  ```
- **Without Common Baseline (`B` absent, $T$ live on both `L` and `R` with winner `W` and opposing `Loser`):**
  ```text
  L_before(T)      = W.labels union (Loser.labels intersect (D_label_W minus D_label_Loser))
  ```
- **One-Sided Surviving Live Task ($T$ live on only $X \in \{L, R\}$):**
  ```text
  L_before(T)      = T_X.labels
  ```

Set post-cascade $T_M.\text{labels} = L_{\text{after}}(T) = L_{\text{before}}(T) \setminus \text{DeletedLabels}$ (`omitted` when empty).

#### 12.3.3 Tombstone Stripping and Group-Wise `condition` Merge (`TDF-MERGE-007`)

After screening newly introduced location references $A^{\text{loc}}_X(E)$ on raw inputs for `DeletionConflict` (`TDF-DEL-002`) and resolving $L_{\text{after}}(T)$ (`TDF-MERGE-006`), process `condition` models in **strict `label`-before-`task` order**:

1. **Pre-Merge Location Tombstone Normalization:** Strip every **non-conflictingly tombstoned** `<location-id>` in merged `deleted` from each present variant $V \in \{B, L, R\}$:
   - *On `label` blocks (merged first):* If stripping tombstoned `<location-id>`s leaves $V.\text{locationGroup}$ with `0` tokens, set $V.\text{locationGroup} = (\text{resetAny} = \text{false}, \text{orderedRules} = [])$. Complete all live `label` merges first so every live label's post-cascade `locationGroup` is known.
   - *On `task` blocks (evaluated against post-cascade $L_{\text{after}}(T)$):* If $V.\text{locationGroup}$ had `>= 1` `<location-id>` tokens and stripping non-conflicting tombstoned tokens leaves `0` tokens, convert $V.\text{locationGroup}$ directly into its cascade target state before comparison:
     - Set $V.\text{locationGroup} = (\text{resetAny} = \text{true}, \text{orderedRules} = [])$ (`location any`) if at least one live `label` in $L_{\text{after}}(T)$ has a non-empty post-cascade `locationGroup`;
     - Otherwise set $V.\text{locationGroup} = (\text{resetAny} = \text{false}, \text{orderedRules} = [])$ (and if no live label in $L_{\text{after}}(T)$ has a non-empty post-cascade `locationGroup` while `B.locationGroup` had `>= 1` tokens that were all tombstoned on side $X \in \{L, R\}$ and side $X$ carries cascade-inserted `location any`, normalize $X.\text{locationGroup}$ to empty as well).
2. **Condition Reconciliation on Cascade-Normalized `(B, L, R)`:**
   - **Global Reset (`globalAny == true` in any of `B`, `L`, `R`):** Merge the entire `condition` model as one atomic unit via `TDF-MERGE-005` using `W`.
   - **Group-Wise Merge (`globalAny == false` in all three):**
     - `dayGroup` and `timeGroup`: Merge independently as scalar units via `TDF-MERGE-005` using `W`.
     - `locationGroup` (**Commutative `W`-Anchored Ordered-List Merge**):
       1. If `L.locationGroup == R.locationGroup`, keep `L.locationGroup`.
       2. Else if `L.locationGroup == B.locationGroup`, keep `R.locationGroup`.
       3. Else if `R.locationGroup == B.locationGroup`, keep `L.locationGroup`.
       4. Else if `resetAny == true` (`location any`) in any of `B`, `L`, or `R`, keep `W.locationGroup`.
       5. Otherwise (both `L` and `R` edited `<location-id>` lists with `resetAny == false`), start from `W.locationGroup`'s ordered list, remove every `<location-id>` in `B minus Loser`, and append every `<location-id>` in `Loser minus B` not already present, in `Loser`'s declaration order.

#### 12.3.4 Occurrence-Independent Task History Set Merge (`TDF-MERGE-008`)

Reconcile `task.history` **outside `Task state` and independently of `completions` and `finished`** across both Case 1 and Case 2:

- **With Common Baseline ($T \in B$, $T$ live on both `L` and `R`):**
  $$\text{added} = (T_L.\text{history} \setminus T_B.\text{history}) \cup (T_R.\text{history} \setminus T_B.\text{history})$$
  $$\text{removed} = (T_B.\text{history} \setminus T_L.\text{history}) \cup (T_B.\text{history} \setminus T_R.\text{history})$$
  $$T_M.\text{history} = \text{canonicalSort}((T_B.\text{history} \setminus \text{removed}) \cup \text{added})$$
- **Without Common Baseline ($T \notin B$, $T$ live on both `L` and `R`):**
  $$T_M.\text{history} = \text{canonicalSort}(T_L.\text{history} \cup T_R.\text{history})$$
- **One-Sided Surviving Live Task ($T$ live on only $X \in \{L, R\}$):**
  $$T_M.\text{history} = T_X.\text{history}$$

Enforce $|T_M.\text{history}| \le \text{MAX\_HISTORY\_PER\_TASK}$ (`500`) during candidate validation (`LimitExceeded` on overflow; never silently truncate).

### 12.4 Task Occurrence Reconciliation and Stage Fairness

#### 12.4.1 Multi-Stage Synchronization Fairness (`cleanupMode`) (`TDF-MERGE-009`)

Every reconciliation pass executes in one of two explicit cleanup modes:

- **`cleanupMode = final` (Single-Stage Sync & Final Remote Stage of Multi-Stage Sync):** Enables Case 2 `suspended <= now` and `blocked` pre-normalization (`TDF-MERGE-010`), post-merge open-task block cleanup (`TDF-MERGE-011` Point 3), and Step 3 `now`-based revision advancement (`TDF-MERGE-004`).
- **`cleanupMode = deferred` (Intermediate Local/Cache Stages & Pre-Sync Mutation Rebasing):** Skips Case 2 `suspended <= now` and `blocked` pre-normalization, skips post-merge open-task block cleanup, and skips Step 3 `now`-based revision advancement ($M_{\text{clean}} = M_{\text{uncleaned}}$), while preserving pre-cleanup revisions on untouched open bystander tasks whose cleanup-normalized payloads equal the origin snapshot. Running intermediate local stages in `cleanupMode = deferred` guarantees that a locally edited task carrying an expired deferral (for example, `B` at `T10` with `suspended = T50`, `L` edited `name = "Z"` at `T11`, `R` edited `name = "Y"` at `T12`, evaluated at `now = T100`) keeps revision `T11` into the final remote merge so `R` (`T12`) wins identically to a direct `merge(B, L, R)` before final cleanup advances `modified` to `T100`.

#### 12.4.2 Two-Level Task Occurrence Merge (`TDF-MERGE-010`)

First check completion-counter monotonicity against proven `B`: if `L.completions < B.completions` or `R.completions < B.completions`, abort with `RecoveryRequired` (`Section 13.3`). Next resolve `mergedDeletedTasks` and every surviving live task's merged `(completions, finished, repeat)` (`mergedTasksById`, none of which depend on `blocked`):

- **Case 1 — Cross-Occurrence or Completion Transition (`completions` differs among `B`, `L`, `R`, or `finished` is present in at least one of `B`, `L`, `R`):**
  Copy the complete `Task state` (`completions`, `priority`, `finished`, `suspended`, `due`, `repeat`, `blocked`, `subtasks`) atomically from raw complete winner `W` (where the greater `completions` counter wins under `TDF-MERGE-003`; concurrent completions of the same occurrence have equal `B.completions + 1` and keep a single increment). Never mix occurrence fields across occurrences. In `cleanupMode = final`, post-merge cleanup (`TDF-MERGE-011` Point 3) still runs if `W` is open (`finished` absent).
- **Case 2 — Same-Occurrence Concurrent Edit (`B.completions == L.completions == R.completions` and `finished` is absent in `B`, `L`, and `R`):**
  Unbundle and reconcile the six `Task state` units independently via `B` and `W`:
  1. `priority`: Independent boolean scalar (`TDF-MERGE-005`).
  2. `suspended` (**Stage-Gated Expiry Pre-Normalization + Atomic 3-Tuple**): In `cleanupMode = final`, pre-normalize any $V \in \{B, L, R\}$ with finite `V.suspended <= now` to `absent` (in `cleanupMode = deferred`, keep `V.suspended` raw), then apply `TDF-MERGE-005`.
  3. `due`: Independent atomic `(utcComponents, optionalLocalAnchorComponents, passive, optionalDecodedDueNote)` unit (`TDF-MERGE-005`).
  4. `repeat`: Independent atomic `(count, unit, localClock, leadDays)` unit (`TDF-MERGE-005`).
  5. `blocked` (**Stage-Gated `V.repeat`-Aware Pre-Normalization + Per-`targetId` Map Merge**): On open task $D$, in `cleanupMode = final` pre-normalize each variant $V \in \{B, L, R\}$'s dependency map $M_V \to M'_V$ using **$V.\text{repeat}$** against `(mergedTasksById, mergedDeletedTasks)`: map $M_V(\text{id}) = \text{req}$ to `absent` whenever $\text{id} \in \text{mergedDeletedTasks}$ OR ($\text{id} \in \text{mergedTasksById}$ with $T_{\text{target}} = \text{mergedTasksById}[\text{id}]$, $T_{\text{target}}.\text{completions} \ge \text{req}$, AND ($V.\text{repeat} = \text{absent} \lor T_{\text{target}}.\text{repeat} = \text{absent}$)); in `cleanupMode = deferred`, keep $M'_V = M_V$ un-normalized. For each $\text{id} \in \text{dom}(M'_B) \cup \text{dom}(M'_L) \cup \text{dom}(M'_R)$:
     - If $M'_L(\text{id}) = M'_R(\text{id})$, keep $M'_L(\text{id})$;
     - Else if $M'_L(\text{id}) = M'_B(\text{id})$, keep $M'_R(\text{id})$;
     - Else if $M'_R(\text{id}) = M'_B(\text{id})$, keep $M'_L(\text{id})$;
     - Otherwise keep $M'_W(\text{id})$.
  6. `subtasks` (**Step-Wise Boolean Merge on Identical Step Texts**): If `B.subtasks`, `L.subtasks`, and `R.subtasks` are all present with the exact same ordered sequence of decoded step `<text>` strings $[s_1, \dots, s_m]$, merge `auto-finish` and each step $i$'s `<bool>` completion flag ($i \in 1..m$) independently via `TDF-MERGE-005` using `W`; otherwise merge the entire `subtasks` block atomically via `TDF-MERGE-005` using `W`. Synchronization MUST NOT trigger `auto-finish` completion or recurrence even if all merged steps become `true`.

### 12.5 Entity Presence and Post-Merge Cascades (`TDF-MERGE-011`)

- Within a compatible `deleted.generation`, if an entity (`task`, `label`, `location`) is present in `B`, unchanged on one side (after `TDF-DEL-002` open-task baseline-cleanup normalization for open tasks), and absent on the other side, discard the unchanged cached copy (creating its deletion record under `TDF-DEL-001` if not already tombstoned). Never treat entity deletion as field-by-field clearing. Preserve local-only additions (`entity ∉ B`) automatically only within a compatible acknowledged generation (`Section 13.3.1`).
- Apply three deterministic post-merge cascades before Phase 8 revision assignment (`TDF-MERGE-004`) and Phase 9 queue normalization (`TDF-QSYNC-001`):
  1. **Non-Conflicting `label` Deletion & `scoped` Flood Protection:** Set $T_M.\text{labels} = L_{\text{after}}(T)$ (`TDF-MERGE-006`). Resolving $\text{isScoped}(l)$ from merged live labels (or from whichever of `L`, `R`, `B` holds `label` $l$'s live block when $l \in \text{DeletedLabels}$), if surviving task $T_M$ is open (`finished` absent), had non-empty all-`scoped` $L_{\text{before}}(T)$, has $L_{\text{after}}(T) = \varnothing$, and **no input side $X \in \{L, R\}$ already lists $T \in X.\text{queue}$ with $T_X.\text{labels} = \varnothing$**, strip `T_M.priority` if present, preserve `suspended` (with note), `(due, anchor, passive, due-note)`, `origin`, and `history`, and mark $T_M$ as `scoped`-evicted for `TDF-QSYNC-001`.
  2. **Non-Conflicting `location` Deletion Cascade:** Already embedded in `TDF-MERGE-007` (`label`-before-`task` tombstone stripping with `location any` inheritance-trap protection).
  3. **Post-Merge Open-Task Block Cleanup (`cleanupMode = final` Only):** In `cleanupMode = final`, apply `TDF-CLEAN-001` across all surviving open tasks $D_M$ using merged $D_M.\text{repeat}$, `mergedTasksById`, and `mergedDeletedTasks` to form $M_{\text{clean}}$.

### 12.6 Deletion Records, Checkpoints, and `DeletionConflict`

#### 12.6.1 Combining Deletion Records and Baseline-Implied Deletions (`TDF-DEL-001`)

- Within a compatible generation, merge `deleted` record sets by `(namespace, id)`:
  - For matching records, keep the **later** UTC deletion timestamp (equal timestamps denote the same deletion).
  - For `task` records, independently keep the **greatest** `<completion-count>` checkpoint (`0` omitted canonically) without restarting the record's 30-day retention clock.
- When proven `B` contains an entity that is absent on side $X$ without a tombstone in $X.\text{deleted}$ (within a compatible generation), synthesize its `deleted` record during reconciliation using `TDF-MUT-002` at `now` against its prior effective revision (never during read-only parsing, and never recreating expired records after a generation advance).
- Do not reintroduce tombstones already retired by a newer generation (`Section 13.3.1`), and never assign a tombstoned ID to a newly created entity (`TDF-ID-001`).

#### 12.6.2 `DeletionConflict` Classification (`TDF-DEL-002`)

For each side $X \in \{L, R\}$, define newly introduced label references on live or `DeletionConflict`-retained task $T$ and newly introduced location references on live or `DeletionConflict`-retained entity $E \in \text{Tasks} \cup \text{Labels}$ (evaluated on raw inputs before condition merging or cascades):

$$A_X(T) = \begin{cases} T_X.\text{labels} \setminus T_B.\text{labels} & \text{if } T \in B \\ T_X.\text{labels} & \text{if } T \notin B \end{cases} \qquad A^{\text{loc}}_X(E) = \begin{cases} \text{locRefs}(E_X) \setminus \text{locRefs}(E_B) & \text{if } E \in B \\ \text{locRefs}(E_X) & \text{if } E \notin B \end{cases}$$

Classify an entity `(namespace, id)` as `DeletionConflict` — preserving both the live entity block, the opposing tombstone, and referencing entities without automatic resolution by timestamp or input direction — whenever **either** condition holds:

1. **Direct Payload Edit vs. Deletion (With Open-Task Baseline-Cleanup Normalization):** One side holds a tombstone in `deleted` while the other side holds a live block whose normalized payload (`TDF-MODEL-006`) differs from `B` (or `B` is absent). When both $T_X$ and $T_B$ are open tasks (`finished` absent), compare $T_X$ and $T_B$ **after applying `TDF-CLEAN-001` at `now` to both snapshots** against non-conflicting combined tombstones and surviving live prerequisites (ignoring a `modified` advance caused solely by `TDF-CLEAN-001`; apply this identical cleanup normalization when comparing retired entities against an origin snapshot for pending local mutations). Automatic block cleanup alone never triggers `DeletionConflict`; any user edit to `history` or any other non-cleaned field triggers `DeletionConflict`.
2. **Newly Introduced Reference vs. Deletion:** Any live or `DeletionConflict`-retained task $T$ on side $X$ introduces $l \in A_X(T)$ while `label` $l$ is tombstoned on the opposing side, OR any live or `DeletionConflict`-retained task or label $E$ on side $X$ introduces $\text{loc} \in A^{\text{loc}}_X(E)$ while `location` $\text{loc}$ is tombstoned on the opposing side (even when `l` or `loc`'s own payload matched `B`).

#### 12.6.3 Explicit `Delete` and `Undelete` Resolution (`TDF-DEL-003`)

Require an explicit user decision (`Delete` or `Undelete`) bound to the exact presented live payload, live revision, and deletion revision (if any of those change before publication, re-evaluate and request a fresh decision). Compute:

```text
decisionRevision = max(now, eachObservedRevision + 1 second)
```

across the live version, deletion record, and available `B` (`InvalidTimestamp` on overflow), and for tasks let `maxCounter` be the greatest completion count across live `completions`, `B.completions`, and the deletion `<checkpoint>`:

| Decision | Atomic Transition |
| :--- | :--- |
| **`Delete`** | Remove the live block, retain its `deleted` record with timestamp `decisionRevision` (restarting its 30-day retention window) and task checkpoint `maxCounter` (if `>= 1`), and execute the `TDF-MUT-009` cascade (`task`: remove from `queue` + strip open-task `blocked`; `label`: strip `labels` + `scoped` queue eviction; `location`: `label`-before-`task` `location any` cascade), advancing `modified` on affected entities. **Do NOT increment `deleted.generation`.** |
| **`Undelete`** | Restore the live `task`, `label`, or `location` block with its original `(namespace, id)` and `modified = decisionRevision` (setting `task.completions = maxCounter` and preserving `history` and all selected fields), remove its record from `deleted`, **increment `deleted.generation` once** (preserving the `deleted` block with nonzero generation even if `0` records remain), preserve all `labels` and `condition location` references, and include a restored open task (`finished` absent) in `queue` at its surviving live variant's position (reconciled via `TDF-QSYNC-001`, unless evicted by a concurrent `scoped` label deletion) **if and only if** `<task-id>` was listed in the surviving live variant's `queue` (otherwise keep outside `queue`). |

### 12.7 Shared Queue Reconciliation (`TDF-QSYNC-001`)

Reconcile `queue` after Phases 1–8 (`TDF-MERGE-011`):

1. **Complete Queue Winner (`W.queue`):** Select between `L.queue` and `R.queue` by later effective `queue.modified` (`1970-01-01 00:00:00` UTC when absent), breaking ties by lexicographically greater ordered `<task-id>` list (unsigned ASCII order; shorter exact-prefix list precedes longer list).
2. **Three-Way / Two-Way List Merge:**
   - If `B` is present and `L.queue == R.queue`, start from `L.queue`.
   - Else if `B` is present and `L.queue == B.queue`, start from `R.queue`.
   - Else if `B` is present and `R.queue == B.queue`, start from `L.queue`.
   - Otherwise (both `L.queue` and `R.queue` diverged from `B.queue`, or `B` is absent), start from `W.queue` and append any concurrent additions from `Loser.queue` (`id ∈ Loser.queue \ B.queue` when `B` is present; or live open tasks present only on `Loser` and listed in `Loser.queue` when `B` is absent) not already present, ordered by ascending UTC `task.created` timestamp, then ascending ASCII `<task-id>`.
3. **Post-Merge Normalization Against Surviving Open Set `O`:** Let `O` be the set of surviving live open tasks in the merged document (`finished` absent, not tombstoned in `deleted`, and not `scoped`-evicted in `TDF-MERGE-011` Point 1). Filter the merged list to keep only IDs in `O` (preserving relative order and deduplicating any repeated ID). Filtering `queue` never deletes a task block and never resurrects a tombstoned or `RecoveryRequired` task.
4. **Deterministic Queue Revision (Clock-Free):** Compare available `B.queue`, `L.queue`, and `R.queue` by Step 1's winner order: if the greatest existing queue already has the exact post-normalization list, preserve its `modified` revision (including implicit epoch omission); otherwise set `queue.modified = max_{X in I}(X.queue.effectiveModifiedAt) + 1 second` without reading wall-clock `now`.

## 13. Guarded Publication, Retention Pruning, and Recovery

### 13.1 Candidate Validation and Guarded Publication

#### 13.1.1 Complete Result Validation (`TDF-PUB-001`)

Before publishing any mutated or merged candidate `M`, validate the complete document and its canonical byte serialization (`Section 6` and `Section 7`), including exact `queue` membership, `UnknownLabelReference`, `UnknownLocationReference`, `CircularDependency`, `MAX_ARGS_PER_STMT = 64` (on merged `labels`, `blocked`, and coalesced `condition location`), `MAX_LOCATION_REFS_PER_ENTITY = 63`, `MAX_LOCATIONS = 200`, `MAX_LINKS_PER_TASK = 20`, `MAX_LINKS_PER_LABEL = 20`, `MAX_HISTORY_PER_TASK = 500`, `MAX_STMTS_PER_BLOCK = 1_024`, `MAX_LINE_COUNT = 16_384`, and `MAX_FILE_BYTES = 1_048_576`. If validation fails (or any `DeletionConflict`, `RecoveryRequired`, or `SyncGenerationRollback` outcome is pending), abort without writing bytes, without truncating collections, and without advancing `sourceDigest` or `B`.

#### 13.1.2 Mandatory Host-Local Cooperative Lock (`TDF-PUB-002`)

Because POSIX, Windows, and Android filesystems offer no kernel atomic compare-and-rename conditioned on a target path's prior SHA-256 content digest, and locking an open descriptor of `<target>` does not block another writer replacing `<target>` via `rename`, **every conforming local TDF writer on the same host user environment MUST serialize local publication through a shared host-local runtime lock outside the synchronized workspace folder**:

1. **Sync-Folder `.tdf.lock` Prohibition:** Implementations MUST NOT create `.tdf.lock` files inside the synchronized workspace directory (preventing cloud sync daemons from replicating stale ghost locks across devices).
2. **Canonical Lock Path:** Resolve `<target>`'s parent directory to its canonical real path, join with `<target_basename>` (UTF-8, `/` separators, lowercased on case-insensitive Windows NTFS volumes), and compute `targetPathHash = lowercase_hex(SHA256(UTF8(<canonical_target>)))` (`64` hex chars). Place the lock file at `<host_lock_dir>/tdf-<targetPathHash>.lock`, where `<host_lock_dir>` is `$XDG_RUNTIME_DIR/tdf-locks` when `$XDG_RUNTIME_DIR` is non-empty on POSIX/Linux, `<os_temp_dir>/tdf-locks-<uid>` (`0700` permissions) otherwise on POSIX/Android, and `%LOCALAPPDATA%\Temp\tdf-locks` on Windows.
3. **Exclusive Lock Acquisition & Non-Unlink Invariant:** Acquire an in-process per-`<targetPathHash>` mutex first, then open/create `<host_lock_dir>/tdf-<targetPathHash>.lock` and acquire an OS-native exclusive descriptor lock:
   - **POSIX / Linux / Android:** Open/create `<host_lock_dir>/tdf-<targetPathHash>.lock` (`O_CREAT | O_RDWR`, `0600` permissions) and acquire `flock(fd, LOCK_EX)`.
   - **Windows:** Open `<host_lock_dir>/tdf-<targetPathHash>.lock` via `CreateFileW` with `OPEN_ALWAYS`, `GENERIC_READ | GENERIC_WRITE`, and `dwShareMode = FILE_SHARE_READ | FILE_SHARE_WRITE` (**omitting `FILE_SHARE_DELETE`** so the open lock file cannot be unlinked or renamed while held and contending cooperative writers do not fail on `CreateFileW` with `ERROR_SHARING_VIOLATION`), then acquire an exclusive lock via `LockFileEx` with `LOCKFILE_EXCLUSIVE_LOCK` over bytes `0..1`.
   **NEVER `unlink` or delete `<host_lock_dir>/tdf-<targetPathHash>.lock` on release** (unlinking lets a racing process lock a distinct inode/file object under the same path). Always release the descriptor lock and in-process mutex on completion or failure.

#### 13.1.3 Guarded Local Retry Loop, Conditional WebDAV PUT, and Concurrency Scope (`TDF-PUB-003`)

- **Local Bounded Publish-Merge Retry Loop (`MAX_PUBLISH_RETRIES = 3`, Parameterized by `cleanupMode ∈ {final, deferred}`):** Callers pass `cleanupMode = final` for standalone local-only mutations/synchronizations and for final local write-back after authoritative remote WebDAV reconciliation, and pass `cleanupMode = deferred` when reconciling or persisting an intermediate local stage prior to remote WebDAV reconciliation ([Section 12.4.1](#1241-multi-stage-synchronization-fairness-cleanupmode-tdf-merge-009)). Acquire the `TDF-PUB-002` lock for `<target>`, set loop-local `loopDigest = sourceDigest`, `loopB = B` (`absent` if `<target>` did not exist initially), and `loopL = L`, and iterate `attempt = 0..MAX_PUBLISH_RETRIES` while holding the exclusive lock across every read-compare-and-rename critical section:
  1. *Read & Fingerprint:* Read current bytes `R_bytes` from `<target>` afresh by path and compute `diskDigest = SHA256(R_bytes)` (`absent` if `<target>` does not exist).
  2. *Digest Match — Atomic Temp-File Publication:* When `diskDigest == loopDigest` (including both `absent` on initial creation), serialize `loopL` to canonical `out_bytes` (`Section 7`) and validate bounds (`TDF-PUB-001`). Create `.<target_basename>.tmp.<csprng_hex>` in `<target>`'s directory with a `>= 128`-bit (`32`-hex-char) CSPRNG suffix, exclusive creation (`O_CREAT | O_EXCL | O_WRONLY` on POSIX, `CREATE_NEW` on Windows, never following symlinks), and `0600` POSIX permissions where supported by the target filesystem. Write `out_bytes`, flush (`fsync` on the temp file and parent directory where supported on POSIX), and atomically replace `<target>` (`rename` on POSIX/Android; `MoveFileExW` with `MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH` on Windows). **Only after atomic replacement succeeds**, commit `sourceDigest = SHA256(out_bytes)`, `B = loopL`, and `acknowledgedGeneration = loopL.deleted.generation`, release the lock, and return. On any write/flush/rename error, `unlink` the temp file, release the lock, and preserve caller `sourceDigest`, `B`, and `L` untouched.
  3. *Digest Mismatch — Reload & Reconcile (`diskDigest != loopDigest` and `attempt < 3`):* If `diskDigest == absent` while `loopDigest != absent` (external file removal), evaluate under `TDF-REC-001`: if `loopL` contains any live `task`, `label`, or `location`, abort immediately under Step 4 with `RecoveryRequired` without recreating `<target>`; otherwise set `R` to empty `tdf 0.8.0`. When `diskDigest != absent`, parse `R_bytes` as `R`. Reconcile `M = merge(loopB, loopL, R)` using the caller's `cleanupMode` (`final` or `deferred`) under [Sections 11–12](#11-synchronization-model-and-phase-overview) (when `loopB == absent` because `<target>` was created externally after initialization, reconcile without a common baseline under [Section 12.5](#125-entity-presence-and-post-merge-cascades-tdf-merge-011) and [Section 13.3.1](#1331-generation-comparison-syncgenerationrollback-and-refresh-reconciliation-tdf-rec-001)), validate `M`, update loop-local `loopDigest = diskDigest`, `loopB = R`, `loopL = M` (without mutating durable `sourceDigest` or `B`), increment `attempt`, and repeat from Step 1.
  4. *Contention Exhaustion or Conflict Abort:* If `attempt == 3` with `diskDigest != loopDigest`, or parsing/reconciliation yields `DeletionConflict`, `RecoveryRequired`, `SyncGenerationRollback`, or a validation error, abort without modifying `<target>`, release the lock, and preserve caller `sourceDigest`, `B`, and `L` unchanged.
- **Remote WebDAV Conditional Publication:** Include `If-Match: <acknowledged_etag>` on HTTP `PUT` whenever the acknowledged remote snapshot supplied a strong `ETag` (and `If-None-Match: *` on initial creation where supported). On `412 Precondition Failed`, reload the remote `.tdf` and `ETag`, reconcile in `cleanupMode = final`, and retry up to `MAX_PUBLISH_RETRIES = 3` attempts.
- **Explicit Concurrency Guarantee Scope:**
  - *Strict No-Lost-Update Guarantee:* Guaranteed across all in-process operations, across all conforming local TDF writers on the same host OS user profile (serialized by `TDF-PUB-002`), and across WebDAV clients backed by servers enforcing strong `ETag` `If-Match` / `If-None-Match` preconditions.
  - *Bounded Best-Effort Detection:* Uncooperative external actors that replace `<target>` without acquiring `<host_lock_dir>/tdf-<targetPathHash>.lock` (cloud sync daemons such as OneDrive, Nextcloud, or Syncthing, plain text editors, cross-host SMB/NFS writers) and WebDAV servers omitting/ignoring `ETag` preconditions lie outside OS/server atomic CAS guarantees: changes completed before Step 1's read are detected via `diskDigest != loopDigest` and merged, whereas an uncooperative replacement occurring strictly between Step 1's read and Step 2's `rename` (or between `GET` and unconditional `PUT`) cannot be prevented by user-space code alone.

### 13.2 Thirty-Day Retention Pruning (`TDF-PUB-004`)

Thirty days equals exactly `2_592_000` seconds. Evaluate all retention ages against one captured UTC `now` **only** during guarded publication against the current authoritative shared source (never during read-only loading or on an unacknowledged offline cache):

1. **`Completed` Task Garbage Collection (`> 30` Days):** Any live `task` block with `finished` present and `now - finished > 2_592_000` seconds (retaining tasks at exact equality `2_592_000`s or future `finished > now`) is removed in full (including its `history` entries) and replaced by a `deleted` `task` record via `TDF-MUT-009` using the current deletion revision (never the old `finished` timestamp), starting a fresh 30-day tombstone retention window without incrementing `deleted.generation`.
2. **Tombstone Expiry & Prerequisite Reference Hygiene (`> 30` Days):** Any `deleted` record (`task`, `label`, or `location`) with `now - deletionRevision > 2_592_000` seconds (retaining records at exact `2_592_000`s or future timestamps; never expiring records early to satisfy `MAX_DELETED_RECORDS`) is removed:
   - Whenever a `deleted` `task <id> <ts> [<checkpoint>]` record expires, **strip any remaining `blocked <id>[:<req>]` reference targeting `<id>` across all live tasks (including `Completed` tasks)** in the same guarded transaction (omitting `blocked` if empty and advancing affected tasks' `modified` via `TDF-MUT-002`), guaranteeing zero dangling references survive tombstone retirement while keeping unknown forward references untouched.
   - **Single Generation Increment:** Increment `deleted.generation` (starting from the current shared source generation, failing with `LimitExceeded` instead of wrapping above `MAX_SYNC_GENERATION`) **at most once** per guarded transaction when `>= 1` tombstone is retired by 30-day expiry or explicit `Undelete` (`0` increments when `0` records are retired or on `Delete` alone; `1` increment even when multiple expired tombstones and an `Undelete` share one transaction). Preserve the `deleted` block with its nonzero `generation` even when `0` records remain.

### 13.3 Generation Checks and Recovery

#### 13.3.1 Generation Comparison, `SyncGenerationRollback`, and Refresh Reconciliation (`TDF-REC-001`)

Before publishing local changes against shared snapshot `R`, compare `R.deleted.generation` with the client's durable `acknowledgedGeneration`:

- **Equal (`R.deleted.generation == acknowledgedGeneration`):** Execute normal reconciliation (`Section 12`).
- **Rollback (`R.deleted.generation < acknowledgedGeneration`):** Abort immediately with `SyncGenerationRollback`; preserve both `L` and `R` and the prior `acknowledgedGeneration` without overwriting `R`.
- **Advanced or Unknown (`R.deleted.generation > acknowledgedGeneration` or `acknowledgedGeneration == absent`):** Refresh against `R` and classify entities as follows:
  1. Reconcile entities (`task`, `label`, `location`) live in both `L` and `R` via proven `B` when available (`Section 12.3`–`12.4`), or via complete winner `W` + `history` union when `B` is absent.
  2. Discard unchanged cached entities (`entity ∈ B`, absent from `R`, and unchanged on `L` — comparing open tasks after applying `TDF-DEL-002` baseline-cleanup normalization at `now` so automatic `suspended <= now` or resolved `blocked` cleanup never causes a false `RecoveryRequired`).
  3. Classify locally modified entities (`entity ∈ B`, absent from `R`, non-cleanup payload including `history` changed relative to `B`) and unacknowledged local-only entities (`entity ∉ B`, absent from `R`) as ambiguous recovery items (`ambiguousTaskIds`, `ambiguousLabelIds`, `ambiguousLocationIds`).
  4. Discard old acknowledged deletion records superseded by the newer generation while retaining unacknowledged local deletion intents.
  5. Adopt `R.deleted.generation` plus any retirement increment required by `TDF-PUB-004`.

If any ambiguous recovery items exist (or completion history regressed below `B` in `TDF-MERGE-010`), return `RecoveryRequired` and withhold publication and baseline advancement until resolved.

#### 13.3.2 `RecoveryRequired` Resolution and New-Identity Rewriting (`TDF-REC-002`)

- **Discarding Retired Entities:** Whenever cached or local-only tasks absent from `R` are discarded (automatically in Step 2 above, by explicit user discard during `RecoveryRequired`, or when rebasing pending local mutations onto an advanced generation), **strip all `blocked <id>[:<req>]` references targeting those discarded `<task-id>`s from every surviving live open task** (advancing `modified` via `TDF-MUT-002` when changed) so retired tasks whose tombstones already expired never persist as false forward references.
- **Explicit Recovery as New Entities:** When the user chooses to keep one or more ambiguous `task`, `label`, or `location` entities after tombstone expiry, generate a **fresh 10-character Base62 ID** under `TDF-ID-001` for every recovered entity, preserve `task.history` and attributes, rewrite `labels`, `blocked`, and `condition location` references among recovered entities through the old-to-new ID map, strip `blocked` references to non-recovered discarded tasks on open tasks, validate the complete candidate (`TDF-PUB-001`), and publish via `TDF-PUB-003`.

## Appendix A: Error Index, Conformance Vector Index, and Rule ID Index

### A.1 Structured Error and Outcome Index (`TDF-ERR-001`)

Conforming Readers, Serializers, Evaluators, Mutating Clients, and Reconcilers MUST report the exact structured error or outcome codes below (with 1-based line numbers on `.tdf` input errors). Detailed trigger algorithms and error precedences reside in the referenced authoritative rules — specifically [Section 6.1 (`TDF-VAL-001`)](#61-validation-contract-and-deterministic-error-precedence-tdf-val-001) and the token-disambiguation rules for `repeat` (`TDF-DIR-001`), `suspended` (`TDF-DIR-003`), `due` (`TDF-DIR-004`), `history` (`TDF-DIR-007`), `condition` (`TDF-DIR-009`), and `deleted` (`TDF-ENT-005`).

#### A.1.1 Lexical, Structural, Semantic, and Bound Errors

| Error Code | Summary Meaning | Authoritative Rule IDs & Sections |
| :--- | :--- | :--- |
| `MissingVersionHeader` | Empty/comment-only input, first statement at depth `0` is not `tdf <version>`, or bare `tdf` with zero arguments. | `TDF-ENT-001` ([Section 5.1](#51-the-tdf-version-header-tdf-ent-001)), `TDF-VAL-001` ([Section 6.1](#61-validation-contract-and-deterministic-error-precedence-tdf-val-001)) |
| `UnsupportedVersion` | Initial `tdf <version>` specifies any version token other than unquoted `0.8.0`, quotes `"0.8.0"`, or supplies extra arguments. | `TDF-COMPAT-001` ([Section 1.4](#14-version-compatibility)), `TDF-ENT-001` ([Section 5.1](#51-the-tdf-version-header-tdf-ent-001)) |
| `UnexpectedRootDirective` | Any directive at depth `0` other than the initial `tdf` header (including a later duplicate `tdf` or root-level `history`). | `TDF-GRAM-001` ([Section 3.4](#34-document-structure-blocks-and-directives-tdf-gram-001)), `TDF-ENT-001` ([Section 5.1](#51-the-tdf-version-header-tdf-ent-001)) |
| `MissingDirectiveArgument` | Standalone identifier inside a block with zero arguments and no opening `{`. | `TDF-GRAM-001` ([Section 3.4](#34-document-structure-blocks-and-directives-tdf-gram-001)), `TDF-DIR-001`–`TDF-DIR-009` ([Section 5](#5-entity-and-directive-reference)) |
| `InvalidIdentifier` | Quoted or malformed block/directive name, entity ID component (`<task-id>`, `<label-id>`, `<location-id>`), or `blocked` target prefix. | `TDF-LEX-003` ([Section 3.3](#33-delimiters-identifiers-and-arguments-tdf-lex-003)), `TDF-TYPE-002` ([Section 4.2](#42-versions-and-base62-entity-identifiers-tdf-type-002)), `TDF-TYPE-006` ([Section 4.6](#46-counters-and-prerequisite-references-tdf-type-006)) |
| `InvalidBlockHeader` | Attached `{` without whitespace (`task 8jKaCdOkD2{`, `condition{`), missing required entity ID, or unknown/quoted/extra header argument. | `TDF-GRAM-001` ([Section 3.4](#34-document-structure-blocks-and-directives-tdf-gram-001)), `TDF-ENT-002`–`TDF-ENT-006` ([Section 5](#5-entity-and-directive-reference)) |
| `UnexpectedToken` | Invalid UTF-8, null/disallowed control char, standalone `CR`, non-ASCII whitespace outside quotes/comments, attached mid-token quote, trailing tokens after `{`/`}`, invalid argument count/quoting/modifier order (`repeat`, `suspended`, `due`, `origin`, `link`, `history`, `coordinates`, `radius`, `deleted` `label`/`location` checkpoint), decoded `\n`/`\r`/`\t` in `<text>`, or unpaired surrogate in `<text>`/`<note>`/`<uri>`. | `TDF-LEX-001`–`TDF-LEX-003` ([Section 3](#3-lexical-syntax-and-structural-grammar)), `TDF-TYPE-003` ([Section 4.3](#43-single-line-text-and-multi-line-notes-tdf-type-003)), `TDF-TYPE-005` ([Section 4.5](#45-numbers-colors-and-uris-tdf-type-005)), `TDF-DIR-001`–`TDF-DIR-008` ([Section 5.2](#52-the-task-block-tdf-ent-002)) |
| `UnclosedBlock` | `EOF` reached while open block depth `> 0`. | `TDF-GRAM-001` ([Section 3.4](#34-document-structure-blocks-and-directives-tdf-gram-001)) |
| `UnexpectedClosingBrace` | `}` encountered at depth `0`. | `TDF-GRAM-001` ([Section 3.4](#34-document-structure-blocks-and-directives-tdf-gram-001)) |
| `UnterminatedString` | `"` or `'` string hits raw `\r`, `\n`, or `EOF` before its closing quote. | `TDF-LEX-003` ([Section 3.3](#33-delimiters-identifiers-and-arguments-tdf-lex-003)) |
| `InvalidEscapeSequence` | Unknown backslash escape sequence inside `"..."` (outside `\"`, `\\`, `\n`, `\r`, `\t`). | `TDF-LEX-003` ([Section 3.3](#33-delimiters-identifiers-and-arguments-tdf-lex-003)) |
| `UnknownBlockType` | Disallowed block name at depth `0` or depth `1` (including `{` after non-block directives in `task`/`label` or any nested `{` block inside `location`, `deleted`, or `queue`; nested `{` at depth `2` inside `subtasks` or `condition` fails earlier with `LimitExceeded` under `MAX_NESTING_DEPTH = 2`). | `TDF-GRAM-001` ([Section 3.4](#34-document-structure-blocks-and-directives-tdf-gram-001)), `TDF-ENT-002`–`TDF-ENT-006` ([Section 5](#5-entity-and-directive-reference)) |
| `UnknownDirective` | Directive name is invalid for its enclosing block (including `history` outside `task`, any directive other than `step` inside `subtasks`, or any depth-`2` identifier outside `{day, time, location, any}` inside `condition { ... }` such as `condition any` or `condition day mon`). | `TDF-ENT-002`–`TDF-ENT-006`, `TDF-DIR-008`–`TDF-DIR-009` ([Section 5](#5-entity-and-directive-reference)) |
| `MissingRequiredDirective` | Missing `name`/`created` on `task`, `name` on `label`, `name`/`coordinates`/`radius` on `location`, `generation` on `deleted`, `modified` on `queue`, or empty `subtasks` / `condition { ... }`. | `TDF-GRAM-001` ([Section 3.4](#34-document-structure-blocks-and-directives-tdf-gram-001)), `TDF-ENT-002`–`TDF-ENT-006` ([Section 5](#5-entity-and-directive-reference)) |
| `DuplicateDirective` | Repeated singleton directive or singleton block (`subtasks`, `deleted`, `queue`). | `TDF-GRAM-001` ([Section 3.4](#34-document-structure-blocks-and-directives-tdf-gram-001)) |
| `DuplicateIdentifier` | Duplicate ID within the `task`, `label`, or `location` namespace (across live blocks and `deleted` records) or duplicate `<task-id>` in `queue`. | `TDF-MODEL-002` ([Section 2.2](#22-entities-containers-and-identity-namespaces)), `TDF-VAL-003` ([Section 6.3](#63-reference-integrity-completion-state-and-acyclicity-tdf-val-003)) |
| `InvalidQueueMembership` | `queue` entry references an unknown, tombstoned, or `finished` task. | `TDF-ENT-006` ([Section 5.7](#57-the-queue-block-tdf-ent-006)), `TDF-VAL-003` ([Section 6.3](#63-reference-integrity-completion-state-and-acyclicity-tdf-val-003)) |
| `UnknownLabelReference` | `task.labels` references a `<label-id>` with no declared live `label` block. | `TDF-ENT-002` ([Section 5.2](#52-the-task-block-tdf-ent-002)), `TDF-VAL-003` ([Section 6.3](#63-reference-integrity-completion-state-and-acyclicity-tdf-val-003)) |
| `UnknownLocationReference` | `condition location` references a `<location-id>` with no declared live `location` block. | `TDF-DIR-009` ([Section 5.5](#55-activation-conditions-condition-tdf-dir-009)), `TDF-VAL-003` ([Section 6.3](#63-reference-integrity-completion-state-and-acyclicity-tdf-val-003)) |
| `CircularDependency` | `blocked` references form a self-dependency or multi-task cycle. | `TDF-DIR-002` ([Section 5.2.2](#522-prerequisite-dependencies-blocked-tdf-dir-002)), `TDF-VAL-003` ([Section 6.3](#63-reference-integrity-completion-state-and-acyclicity-tdf-val-003)) |
| `EmptyText` | Decoded `<text>` (`""` or `0x20` only after single-line check), `<note>`, or `<uri>` (`""` or ASCII whitespace `0x20`/`\t`/`\n`/`\r` only) is blank. | `TDF-TYPE-003` ([Section 4.3](#43-single-line-text-and-multi-line-notes-tdf-type-003)), `TDF-TYPE-005` ([Section 4.5](#45-numbers-colors-and-uris-tdf-type-005)) |
| `InvalidUri` | Non-blank `<uri>` within `MAX_URI_LENGTH` contains ASCII control chars (`\n`, `\r`, `\t`, etc.), lacks `[a-zA-Z][a-zA-Z0-9+.-]*:`, or uses `javascript:`, `vbscript:`, or `data:`. | `TDF-TYPE-005` ([Section 4.5](#45-numbers-colors-and-uris-tdf-type-005)), `TDF-DIR-006` ([Section 5.2.6](#526-reference-links-link-tdf-dir-006)) |
| `InvalidTimestamp` | Quoted leading timestamp token, malformed date/clock, year outside `0001..9999` (or invalid leap day), or out-of-range revision/calendar arithmetic result. | `TDF-TYPE-004` ([Section 4.4](#44-booleans-weekdays-clocks-and-timestamps-tdf-type-004)), `TDF-DIR-003`–`TDF-DIR-004` ([Section 5.2](#52-the-task-block-tdf-ent-002)), `TDF-MUT-002` ([Section 10.1.2](#1012-entity-and-queue-revision-rules-tdf-mut-002)), `TDF-CAL-001`–`TDF-CAL-003` ([Section 10.2](#102-local-calendar-resolution-and-recurrence-calculation)) |
| `InvalidBoolean` | Checklist `step` boolean is not unquoted `true` or `false`. | `TDF-TYPE-004` ([Section 4.4](#44-booleans-weekdays-clocks-and-timestamps-tdf-type-004)), `TDF-DIR-008` ([Section 5.2.8](#528-checklist-sub-blocks-subtasks-tdf-dir-008)) |
| `InvalidNumber` | Malformed/non-finite/scientific `<number>`, out-of-range `lat`/`lon`, `> 6` coordinate or `> 2` radius fractional digits, `radius <= 0`, or invalid `<count>`, `<lead-count>`, `<generation>`, `<completion-count>`, or `:<req>`. | `TDF-TYPE-005`–`TDF-TYPE-006` ([Sections 4.5–4.6](#45-numbers-colors-and-uris-tdf-type-005)), `TDF-DIR-001` ([Section 5.2.1](#521-recurrence-and-preparation-lead-repeat-tdf-dir-001)) |
| `InvalidCondition` | Invalid `<weekday>`, invalid `<time>` window or `start == end`, `any`/`<type> any` on `label`, `any <args...>` at depth `2` inside `condition { ... }`, `condition any` combined with other rules/resets on `task`, or `<type> any` repeated or combined with same-group rules. | `TDF-TYPE-004` ([Section 4.4](#44-booleans-weekdays-clocks-and-timestamps-tdf-type-004)), `TDF-DIR-009` ([Section 5.5](#55-activation-conditions-condition-tdf-dir-009)) |
| `InvalidColor` | `label.color` is not quoted 7-character `"#RRGGBB"` / `'#RRGGBB'` hex. | `TDF-TYPE-005` ([Section 4.5](#45-numbers-colors-and-uris-tdf-type-005)), `TDF-ENT-003` ([Section 5.3](#53-the-label-block-tdf-ent-003)) |
| `InvalidCompletionState` | `task` has `finished` present while effective `completions` is `0`. | `TDF-ENT-002` ([Section 5.2](#52-the-task-block-tdf-ent-002)), `TDF-VAL-003` ([Section 6.3](#63-reference-integrity-completion-state-and-acyclicity-tdf-val-003)) |
| `InvalidTime` | `repeat` `<repeat-time>` is quoted or outside `00:00:00..23:59:59`. | `TDF-TYPE-004` ([Section 4.4](#44-booleans-weekdays-clocks-and-timestamps-tdf-type-004)), `TDF-DIR-001` ([Section 5.2.1](#521-recurrence-and-preparation-lead-repeat-tdf-dir-001)) |
| `LimitExceeded` | Any `MAX_*` bound in `Section 6.2` is exceeded on input, mutation, merge, or canonical output (counted before deduplication for `history`, condition rules, and location refs). | `TDF-VAL-002` ([Section 6.2](#62-resource-bounds-tdf-val-002)), `TDF-SER-001` ([Section 7.1](#71-canonical-serialization-contract-tdf-ser-001)), `TDF-PUB-001` ([Section 13.1.1](#1311-complete-result-validation-tdf-pub-001)) |

#### A.1.2 Synchronization and Runtime Context Outcomes

These outcomes represent synchronization conflicts or missing runtime context rather than malformed `.tdf` syntax; while unresolved, they withhold publication and baseline advancement:

| Outcome Code | Category | Summary Meaning | Authoritative Rule IDs & Sections |
| :--- | :--- | :--- | :--- |
| `RecoveryRequired` | Sync Outcome | Ambiguous local/edited entities after generation advance (or missing file removal), or completion counter regression below proven `B`. | `TDF-MERGE-010` ([Section 12.4.2](#1242-two-level-task-occurrence-merge-tdf-merge-010)), `TDF-PUB-003` ([Section 13.1.3](#1313-guarded-local-retry-loop-conditional-webdav-put-and-concurrency-scope-tdf-pub-003)), `TDF-REC-001`–`TDF-REC-002` ([Section 13.3](#133-generation-checks-and-recovery)) |
| `DeletionConflict` | Sync Outcome | Non-cleanup payload edit or newly introduced `labels` / `condition location` reference conflicts with an opposing deletion record; requires explicit `Delete` or `Undelete`. | `TDF-DEL-002`–`TDF-DEL-003` ([Sections 12.6.2–12.6.3](#1262-deletionconflict-classification-tdf-del-002)) |
| `SyncGenerationRollback` | Sync Outcome | Shared `deleted.generation` is strictly lower than `acknowledgedGeneration`. | `TDF-REC-001` ([Section 13.3.1](#1331-generation-comparison-syncgenerationrollback-and-refresh-reconciliation-tdf-rec-001)) |
| `TimeZoneContextRequired` | Runtime Context | Local calendar evaluation or scheduling mutation lacks a configured IANA `timeZone` or its transition rules. | `TDF-CTX-001` ([Section 8.1](#81-evaluation-context-parameters-tdf-ctx-001)), `TDF-CAL-001` ([Section 10.2.1](#1021-resolving-local-calendar-inputs-to-utc-tdf-cal-001)) |

### A.2 Conformance Vector and Verification Suite Index (`TDF-VEC-001`)

Machine-readable conformance fixtures in `spec/conformance/v0.8.0/` and the normative verification tables below map directly to Rule IDs:

| Fixture Suite Directory | Verified Contract | Target Rule IDs |
| :--- | :--- | :--- |
| `parse_valid/` | Valid `.tdf` inputs, exact `.canonical.tdf` outputs, `.normalized.json` models, and `canonicalSourceDigest` SHA-256 digests. | `TDF-MODEL-001`–`TDF-MODEL-006`, `TDF-SER-001`–`TDF-SER-005` |
| `parse_invalid/` | Invalid `.tdf` fixtures paired with `manifest.json` (`expectedError` and 1-based `expectedLine`). | `TDF-LEX-001`–`TDF-GRAM-002`, `TDF-TYPE-001`–`TDF-TYPE-006`, `TDF-ENT-001`–`TDF-DIR-009`, `TDF-VAL-001`, `TDF-VAL-003` |
| `bounds/` | Exact `N` (accept) and `N + 1` (`LimitExceeded`) boundary fixtures across all `MAX_*` constants and supplementary Unicode scalars. | `TDF-TYPE-001`, `TDF-VAL-002`, `TDF-SER-001` |
| `merge/` | Three-way and baseline-free entity/queue reconciliation, `cleanupMode = final` vs. `deferred`, `history` set merge, `L_before(T)` `scoped` flood protection, `location any` cascade, and `DeletionConflict` vectors. | `TDF-SYNC-001`–`TDF-SYNC-002`, `TDF-MERGE-001`–`TDF-QSYNC-001`, `TDF-PUB-001`–`TDF-REC-002` |
| `timezone/` | `Europe/Berlin` CET/CEST gaps, folds, month-end `due.anchor` preservation (`k = 1 + 1` vs. `k = 2` and `repeat` interval changes), `W_due` effective priority, and `downgradeTask` vectors. | `TDF-CTX-001`–`TDF-EVAL-005`, `TDF-CAL-001`–`TDF-CAL-003`, `TDF-MUT-005` |

#### A.2.1 Normative Boundary and Lexical Verification Cases

| Verification Case | Required Outcome | Rule IDs |
| :--- | :--- | :--- |
| Ordinary block with `1_024` vs. `1_025` direct child statements | Accept `1_024`; reject `1_025` with `LimitExceeded`. | `TDF-VAL-002` |
| Full-capacity canonical `task` block (`12` scalar + `20` `link` + `500` `history` + `1` `condition` + `1` `subtasks` = `534` statements) | Accept (`534 <= 1_024`) and allow lifecycle mutations without statement-bound collision. | `TDF-VAL-002`, `TDF-MUT-008` |
| `task` declares `500` vs. `501` raw `history` directives (including duplicate lines counted before deduplication) | Accept `500` (deduplicate and sort canonically); reject `501` with `LimitExceeded` before allocation. | `TDF-DIR-007`, `TDF-VAL-002` |
| `label` or `task` declares `20` vs. `21` `link` directives | Accept `20`; reject `21` with `LimitExceeded`. | `TDF-DIR-006`, `TDF-VAL-002` |
| `repeat 1 months 09:00 lead 3650 days` vs. `lead 3651 days` vs. `lead 0 days` / `lead -1 days` | Accept `3650`; `3651` -> `LimitExceeded`; `0` or `-1` -> `InvalidNumber`. | `TDF-DIR-001`, `TDF-VAL-002` |
| Entity declares `512` vs. `513` condition rules across multiple `condition` blocks (such as two blocks of `300` rules) | Accept `512`; reject rule `513` with `LimitExceeded` before canonical serialization. | `TDF-DIR-009`, `TDF-VAL-002` |
| Depth-2 disambiguation inside `condition { ... }`: nested `{` block vs. zero-arg identifier (`any`, `day`, `time`, `location`, `condition`) vs. `any <args...>` vs. other identifier (`condition any`, `condition day mon`) | Nested `{` -> `LimitExceeded` (`MAX_NESTING_DEPTH = 2`); zero-arg identifier without `{` -> `MissingDirectiveArgument`; `any <args...>` -> `InvalidCondition`; identifier outside `{day, time, location, any}` (including `condition any` or `condition day mon`) -> `UnknownDirective`. | `TDF-GRAM-001`, `TDF-DIR-009`, `TDF-VAL-001` |
| Entity references `63` vs. `64` `<location-id>` tokens across `location` rules (counted before deduplication) | Accept `63` (coalesce in first-seen order); reject token `64` with `LimitExceeded`. | `TDF-DIR-009`, `TDF-VAL-002` |
| Document declares `200` vs. `201` root `location` blocks | Accept `200`; reject block `201` with `LimitExceeded`. | `TDF-ENT-004`, `TDF-VAL-002` |
| `location` `radius 100000` / `99999.99` vs. `100000.01` vs. `0` / `-5` / `10.125` | Accept `<= 100000`; `100000.01` -> `LimitExceeded`; `0`, `-5`, `10.125` -> `InvalidNumber`. | `TDF-TYPE-005`, `TDF-ENT-004` |
| `<number>` token with `24` ASCII chars (`-123.456789`) vs. `25` ASCII chars (`0000000000000000000000150`) | Accept `24` when domain bounds hold; `25` -> `LimitExceeded`. | `TDF-TYPE-005`, `TDF-VAL-002` |
| Arbitrary root-block input order or multiple equivalent `condition` forms; canonical output exceeds `MAX_FILE_BYTES` / `MAX_LINE_COUNT` | Accept input and serialize to unique canonical form; if output exceeds bound, fail with `LimitExceeded` without truncation or writes. | `TDF-SER-001`–`TDF-SER-003` |
| Condition evaluation: all effective groups empty; one non-empty false group + others empty; `<type> any` reset clearing inherited group | Evaluate to `true`; `false`; cleared group `true` while evaluating remaining groups. | `TDF-EVAL-002`–`TDF-EVAL-003` |
| Timestamps at `0001-01-01 00:00:00` / `9999-12-31 23:59:59` and `2000-02-29` vs. year `0000` / `10000`, `1900-02-29`, or revision/`targetSuspendedLocalDate` overflow | Accept valid endpoints and `2000-02-29`; reject invalid/overflowing dates with `InvalidTimestamp` without partial changes. | `TDF-TYPE-004`, `TDF-MUT-002`, `TDF-CAL-003` |
| `500` vs. `501` scalar values `> U+FFFF` (or `250` x `U+0065 U+0301` = `500` scalars) in `<text>`; `2000` vs. `2001` scalars in `<note>` | Accept `500` (`<text>`) and `2000` (`<note>`); reject `501` and `2001` with `LimitExceeded`. | `TDF-TYPE-001`, `TDF-TYPE-003` |
| Escaped `\n` inside `<text>`, non-blank `<uri>`, and `<note>` | Reject `<text>` with `UnexpectedToken` (even when `"\n"` alone), reject `<uri>` with `InvalidUri`, accept `<note>` (`1` scalar value). | `TDF-TYPE-003`, `TDF-TYPE-005` |
| `U+00A0` in `#` comment vs. `U+00A0` separating tokens vs. `U+0000` in `#` comment | Accept `U+00A0` in comment; reject `U+00A0` token separator and `U+0000` in comment with `UnexpectedToken`. | `TDF-LEX-001`–`TDF-LEX-002` |
| `deleted` lines `task AAAAAAAAAA 2026-11-01 7` and `task AAAAAAAAAA 2026-11-01 12:30 7` | Decode `00:00:00` UTC + checkpoint `7` and `12:30:00` UTC + checkpoint `7`. | `TDF-ENT-005` |

#### A.2.2 Normative Calendar, Recurrence, Prerequisite, and Restoration Vectors

Local-to-UTC point conversion vectors in `Europe/Berlin` (`TDF-CAL-001`):

| Intended Local Date and Clock | Stored UTC Instant | Resolved Local Time in `Europe/Berlin` |
| :--- | :--- | :--- |
| `2026-03-28 09:00:00` | `2026-03-28 08:00:00` | `09:00:00` CET |
| `2026-03-29 09:00:00` | `2026-03-29 07:00:00` | `09:00:00` CEST |
| `2026-03-29 02:30:00` | `2026-03-29 01:30:00` | `03:30:00` CEST (shifted forward across spring gap) |
| `2026-03-30 02:30:00` | `2026-03-30 00:30:00` | `02:30:00` CEST (`<repeat-time>` / `due.anchor` preserved) |
| `2026-10-25 02:30:00` | `2026-10-25 00:30:00` | First `02:30:00` CEST (before autumn overlap repeats) |
| `2026-10-25 09:00:00` | `2026-10-25 08:00:00` | `09:00:00` CET |
| `2026-11-05 00:00:00` | `2026-11-04 23:00:00` | `00:00:00` CET (local midnight) |

Additional calendar, occurrence, and restoration cases:

| Verification Case | Required Outcome | Rule IDs |
| :--- | :--- | :--- |
| Deferral `2026-10-25 00:30:00` UTC evaluated at `2026-10-25 01:10:00` UTC (across autumn rollback) or across two devices in different zones | Remains expired in every zone; committed mutation/sync strips finite `suspended <= now` (+ note) while keeping overdue `due <= now` (+ `anchor`, `passive`, note). | `TDF-CTX-002`, `TDF-CLEAN-001` |
| Monthly Mode 2 (`repeat 1 months 08:00 lead 5 days`, `due 2026-10-15 16:00:00 anchor 2026-10-15 18:00:00` CEST) completed late on `2026-10-17` after `suspended` expired | Advances by $k = 1$ to `due 2026-11-15 17:00:00 anchor 2026-11-15 18:00:00` (CET) and `suspended 2026-11-10 07:00:00` (`08:00` CET), preserving 5-day lead and `08:00` clock across DST. | `TDF-CAL-003` |
| Month-end anchor preservation (`k = 1 + 1` vs. `k = 2` and `repeat` interval edit on clamped month): `repeat 1 months 08:00 lead 2 days`, `due 2026-01-31 17:00:00 anchor 2026-01-31 18:00:00` (`Europe/Berlin`) | Jan 31 completion clamps `newDue = 2026-02-28 17:00:00` UTC, preserves `anchor 2026-01-31 18:00:00` (`28 < 31`), sets `suspended 2026-02-26 07:00:00` UTC; Feb 28 completion advances `(Y_cur, M_cur) = (2026, 2)` by $k = 1$ month with $D_a = 31$ to `newDue = 2026-03-31 16:00:00` UTC, `anchor 2026-03-31 18:00:00`, `suspended 2026-03-29 06:00:00` UTC — identical to completing Jan 31 once on `2026-03-10` ($k = 2$). Editing `repeat 1 months -> repeat 2 months` on the clamped Feb 28 state and completing on Feb 28 advances `(Y_cur, M_cur) = (2026, 2)` by `2` months to `due 2026-04-30 16:00:00` UTC (`18:00` CEST) while still preserving `anchor 2026-01-31 18:00:00` (`30 < 31`) so June (`30`) and August (`31`) stay anchored to the 31st. | `TDF-CAL-003` |
| Forward DST gap deadline-clock preservation (`k = 1 + 1` vs. `k = 2`): `repeat 1 days`, `due 2026-03-28 01:30:00 anchor 2026-03-28 02:30:00` (`Europe/Berlin`) | Mar 28 completion sets `newDue = 2026-03-29 01:30:00` UTC (`03:30` CEST) and `anchor 2026-03-29 02:30:00`; Mar 29 completion restores `newDue = 2026-03-30 00:30:00` UTC (`02:30` CEST) and `anchor 2026-03-30 02:30:00`, matching direct $k = 2$. | `TDF-CAL-001`, `TDF-CAL-003` |
| Mode 2 early completion (`newSuspended > now`) vs. overdue completion inside open preparation window (`newSuspended <= now`, e.g. Nov 15 due completed on Dec 15 `10:00` local with `leadDays = 0`) | Early completion persists `newSuspended > now`; overdue completion inside open window (`newSuspended = Dec 15 00:00 <= now`) omits `suspended` immediately; both reset `passive = false`, clear `suspended` note, and preserve `due` note, `origin`, `history`. | `TDF-CAL-003`, `TDF-MUT-006` |
| Prerequisite counter `7` vs. requirement `8` -> advances to `8` -> advances to `9` -> recurring dependent completes at `9` -> prerequisite reaches `10` during deferral | Blocked at `7`; satisfied at `8` (stripped if either task lacks `repeat`, retained across `9` if both have `repeat`); rearmed to `10` on dependent completion; already satisfied when dependent wakes. | `TDF-EVAL-004`, `TDF-CLEAN-001`, `TDF-OCC-001` |
| Completed prerequisite restored at `completions = 1`; retry of identical `expectedCompletions`; concurrent completion of same occurrence on two devices | Earlier `:1` stays satisfied while newly added dependencies arm at `:2`; retry is a pure no-op; concurrent completion keeps `1` increment. | `TDF-OCC-001`, `TDF-MERGE-010` |
| Restore `Completed` task carrying `suspended forever "n"`, `due ... anchor ... passive "n"`, `origin`, `history`, `completions = 7`, `repeat 1 months 09:00 lead 5 days` to `Someday` / `Planned` / `Focus` | Strip `finished`, `suspended` (+ note), and `due` (+ `anchor`, `passive`, note); preserve `origin`, `history`, `completions = 7`, and `repeat`; reset steps to `false` and rearm prerequisites; apply target `priority` and `queue` membership (deriving `Blocked` if a prerequisite is unmet). | `TDF-MUT-007` |

#### A.2.3 Normative Synchronization, Deletion, and Queue Verification Cases

Scalar three-way merge vectors (`TDF-MERGE-003`–`TDF-MERGE-005`; shared task with `B`: `name = N0`, `note = Q0`, `modified = T10`, `completions = 0`, where `Tn = 2026-11-04 12:00:00 UTC + n seconds`; must produce identical results when `L` and `R` are swapped; without `B`, independent edits keep `T12` complete version while unioning `history`):

| Case | Local `L` | Incoming `R` | Merged Payload | Result Revision |
| :--- | :--- | :--- | :--- | :--- |
| Independent edits | `name = N1`, `T11` | `note = Q1`, `T12` | `name = N1`, `note = Q1` | `T13` |
| Matching edits | `name = N1`, `T11` | `name = N1`, `T12` | `name = N1`, `note = Q0` | `T12` |
| Same-field conflict | `name = N1`, `T11` | `name = N2`, `T12` | `name = N2`, `note = Q0` | `T12` |
| Equal-timestamp conflict | `name = Alpha`, `T12` | `name = Zulu`, `T12` | `name = Zulu`, `note = Q0` | `T12` |
| Conflict + independent edit | `name = N1`, `note = Alpha`, `T11` | `note = Zulu`, `T12` | `name = N1`, `note = Zulu` | `T13` |
| Unstamped external edit | Unchanged, `T20` | `name = N1`, `T10` | `name = N1`, `note = Q0` | `T21` |

Additional synchronization, deletion, and queue cases:

| Verification Case | Required Outcome | Rule IDs |
| :--- | :--- | :--- |
| Delete `scoped` label on one side while scheduling open task carrying only that label on the other side | $L_{\text{before}}(T)$ retains the cascade-stripped `scoped` label; task has `priority` stripped and is evicted from merged `queue` in both `(L, R)` and `(R, L)` directions. | `TDF-MERGE-006`, `TDF-MERGE-011`, `TDF-QSYNC-001` |
| Multi-stage sync fairness (`cleanupMode = deferred` on local stage, `final` on remote stage): `B` (`name = "A"`, `T10`, `suspended = T50`), `L` (`name = "Z"`, `T11`, `suspended = T50`), `R` (`name = "Y"`, `T12`, `suspended = T50`) at `now = T100` | Intermediate local stage keeps `T11` un-inflated; final merge selects `R` (`name = "Y"`, `T12`) and strips `suspended <= T100` with `modified = T100`, matching direct `merge(B, L, R)`. | `TDF-MERGE-009`, `TDF-MERGE-004` |
| Local publish Step 3 contention retry under `cleanupMode = deferred` in an intermediate local stage prior to remote WebDAV sync | Step 3 `merge(loopB, loopL, R)` executes in `cleanupMode = deferred`, leaving `suspended <= now` and resolved `blocked` uncleaned and preserving un-inflated task `modified` revisions for the subsequent `cleanupMode = final` remote merge. | `TDF-PUB-003`, `TDF-MERGE-009`, `TDF-MERGE-004` |
| Case 2 `suspended <= now` and `V.repeat`-aware `blocked` pre-normalization in `cleanupMode = final` | Offline cleanup on one side never overwrites a future deferral extension on the other, nor resurrects an expired deferral; completing one-shot `A` neither wipes out concurrent `blocked A:2` nor strips a newly added recurring pipeline (`D.repeat` added while `A.repeat` present). | `TDF-MERGE-010` |
| Occurrence-independent `history` merge across Case 1, Case 2, and baseline-free two-way union | Completing/finishing on `L` and adding/editing/removing `history` on `R` preserves occurrence winner `W` AND reconciles `history` set without loss (advancing `modified` to `max(L, R) + 1s` when two-way union adds entries beyond `W`). | `TDF-MERGE-008`, `TDF-MERGE-004` |
| Coupled `location` `(coordinates, source)` merge & `label`-before-`task` `location` tombstone stripping | Relocating `(coordinates, source)` never mixes with old `source` typo edit; all-tombstoned task `locationGroup` normalizes to `location any` when a live post-cascade label in $L_{\text{after}}(T)$ has a `location` rule (or empty otherwise), while explicit user removal on the opposing side wins cleanly. | `TDF-MERGE-005`, `TDF-MERGE-007` |
| Tombstone age `== 30` days (`2_592_000`s) vs. `> 30` days; last tombstone expires; multiple tombstones + `Undelete` in one transaction | Keep at exact `30` days; at `> 30` days remove record, strip remaining `blocked <id>` on all live tasks (including `Completed`), preserve `deleted` block with nonzero `generation` when empty, and increment `deleted.generation` at most once per transaction. | `TDF-PUB-004` |
| `DeletionConflict` screening and `Delete` vs. `Undelete` decisions | Ignore automatic open-task block cleanup differences; flag non-cleanup edits (including `history`) and newly added $A_X(T)$ / $A^{\text{loc}}_X(E)$ references as `DeletionConflict`; `Delete` cascades without incrementing `generation`; `Undelete` restores original ID, greatest checkpoint, `history`, `queue` position iff open and in `queue` on surviving side, and increments `generation` once. | `TDF-DEL-002`–`TDF-DEL-003` |
| Generation comparison (`<`, `==`, `>`, unknown) and explicit `RecoveryRequired` resolution | `<` -> `SyncGenerationRollback`; `>` or unknown discards unchanged cached copies (stripping `blocked` refs to discarded tasks) and flags edited/unacknowledged entities with `RecoveryRequired`; recovering as new generates fresh Base62 IDs, preserves `history`, and rewrites references. | `TDF-REC-001`–`TDF-REC-002` |
| Guarded local publication (`<host_lock_dir>/tdf-<targetPathHash>.lock`) on POSIX/Android and Windows, and strong-`ETag` WebDAV `If-Match` | Conforming writers serialize read-compare-and-rename under exclusive host lock (`flock(LOCK_EX)` on POSIX/Android; Windows `CreateFileW` with `OPEN_ALWAYS`, `GENERIC_READ \| GENERIC_WRITE`, and `FILE_SHARE_READ \| FILE_SHARE_WRITE` omitting `FILE_SHARE_DELETE` so contenders wait on `LockFileEx` `LOCKFILE_EXCLUSIVE_LOCK` over `0..1` instead of `ERROR_SHARING_VIOLATION`; never creating workspace `.tdf.lock` or unlinking the host lock file) and retry up to `3` times without lost updates; uncooperative external replacements obey the explicit best-effort boundary. | `TDF-PUB-002`–`TDF-PUB-003` |
| `Focus -> Ready` (`E_ctx` slot-8 anchor), `Ready -> Planned`, pure no-op downgrade at end of `queue`, and concurrent `queue` additions | Anchor relative to $E_{\text{ctx}}$, preserving explicit `priority` when slot-7 anchor has effective priority and `isDueUrgent` is `true`, or setting `passive = true` when stepping below regular tasks; pure no-op leaves revisions untouched; concurrent `Loser.queue` additions append by `(created, id)` and normalize against `O`. | `TDF-MUT-005`, `TDF-QSYNC-001` |

### A.3 Normative Rule ID Index (`TDF-TRACE-001`)

This index maps every active `TDF-*` Rule ID in `tdf 0.8.0` (ordered by section appearance) to its normative title and authoritative section:

| Rule ID | Normative Rule Title | Authoritative `0.8.0` Section |
| :--- | :--- | :--- |
| `TDF-META-001` | Normative and Informative Text | [Section 1.2](#normative-and-informative-text-tdf-meta-001) |
| `TDF-META-002` | Stable Rule Identifiers | [Section 1.2](#stable-rule-identifiers-tdf-meta-002) |
| `TDF-CONF-001` | Role Obligations | [Section 1.3](#role-obligations-tdf-conf-001) |
| `TDF-COMPAT-001` | Version Handling Contract | [Section 1.4](#version-handling-contract-tdf-compat-001) |
| `TDF-MODEL-001` | Processing Stages: Decoding, Evaluation, and Cleanup | [Section 2.1](#21-processing-stages-decoding-evaluation-and-cleanup-tdf-model-001) |
| `TDF-MODEL-002` | Namespaces and Cross-Part Container Split | [Section 2.2](#namespaces-and-cross-part-container-split-tdf-model-002) |
| `TDF-ID-001` | Entity ID Generation and Lifetime Identity | [Section 2.2](#entity-id-generation-and-lifetime-identity-tdf-id-001) |
| `TDF-MODEL-003` | Stored Facts, Derived Tiers, and Passive Metadata | [Section 2.3](#23-stored-facts-derived-tiers-and-passive-metadata-tdf-model-003) |
| `TDF-MODEL-004` | Collection Models, Absent Fields, and Defaults | [Section 2.4](#24-collection-models-absent-fields-and-defaults-tdf-model-004) |
| `TDF-MODEL-005` | UTC Instants vs. Local Calendar Values | [Section 2.5](#25-utc-instants-vs-local-calendar-values-tdf-model-005) |
| `TDF-MODEL-006` | Decoded Value Normalization and Structural Equality | [Section 2.6](#26-decoded-value-normalization-and-structural-equality-tdf-model-006) |
| `TDF-LEX-001` | Character Encoding | [Section 3.1](#31-character-encoding-tdf-lex-001) |
| `TDF-LEX-002` | Whitespace, Line Terminators, and Comments | [Section 3.2](#32-whitespace-line-terminators-and-comments-tdf-lex-002) |
| `TDF-LEX-003` | Delimiters, Identifiers, and Arguments | [Section 3.3](#33-delimiters-identifiers-and-arguments-tdf-lex-003) |
| `TDF-GRAM-001` | Document Structure, Blocks, and Directives | [Section 3.4](#34-document-structure-blocks-and-directives-tdf-gram-001) |
| `TDF-GRAM-002` | Formal Grammar (EBNF) | [Section 3.5](#35-formal-grammar-ebnf-tdf-gram-002) |
| `TDF-TYPE-001` | Unicode Scalar Length Measurement | [Section 4.1](#41-unicode-scalar-length-measurement-tdf-type-001) |
| `TDF-TYPE-002` | Versions and Base62 Entity Identifiers | [Section 4.2](#42-versions-and-base62-entity-identifiers-tdf-type-002) |
| `TDF-TYPE-003` | Single-Line Text and Multi-Line Notes | [Section 4.3](#43-single-line-text-and-multi-line-notes-tdf-type-003) |
| `TDF-TYPE-004` | Booleans, Weekdays, Clocks, and Timestamps | [Section 4.4](#44-booleans-weekdays-clocks-and-timestamps-tdf-type-004) |
| `TDF-TYPE-005` | Numbers, Colors, and URIs | [Section 4.5](#45-numbers-colors-and-uris-tdf-type-005) |
| `TDF-TYPE-006` | Counters and Prerequisite References | [Section 4.6](#46-counters-and-prerequisite-references-tdf-type-006) |
| `TDF-ENT-001` | The `tdf` Version Header | [Section 5.1](#51-the-tdf-version-header-tdf-ent-001) |
| `TDF-ENT-002` | The `task` Block | [Section 5.2](#52-the-task-block-tdf-ent-002) |
| `TDF-DIR-001` | Recurrence and Preparation Lead (`repeat`) | [Section 5.2.1](#521-recurrence-and-preparation-lead-repeat-tdf-dir-001) |
| `TDF-DIR-002` | Prerequisite Dependencies (`blocked`) | [Section 5.2.2](#522-prerequisite-dependencies-blocked-tdf-dir-002) |
| `TDF-DIR-003` | Deferrals and Deferral Notes (`suspended`) | [Section 5.2.3](#523-deferrals-and-deferral-notes-suspended-tdf-dir-003) |
| `TDF-DIR-004` | Deadlines, Schedule Anchors, Passive Flag, and Notes (`due`) | [Section 5.2.4](#524-deadlines-schedule-anchors-passive-flag-and-notes-due-tdf-dir-004) |
| `TDF-DIR-005` | Machine Correlation Keys (`origin`) | [Section 5.2.5](#525-machine-correlation-keys-origin-tdf-dir-005) |
| `TDF-DIR-006` | Reference Links (`link`) | [Section 5.2.6](#526-reference-links-link-tdf-dir-006) |
| `TDF-DIR-007` | Chronological Task Journal (`history`) | [Section 5.2.7](#527-chronological-task-journal-history-tdf-dir-007) |
| `TDF-DIR-008` | Checklist Sub-Blocks (`subtasks`) | [Section 5.2.8](#528-checklist-sub-blocks-subtasks-tdf-dir-008) |
| `TDF-ENT-003` | The `label` Block | [Section 5.3](#53-the-label-block-tdf-ent-003) |
| `TDF-ENT-004` | The `location` Block | [Section 5.4](#54-the-location-block-tdf-ent-004) |
| `TDF-DIR-009` | Activation Conditions (`condition`) | [Section 5.5](#55-activation-conditions-condition-tdf-dir-009) |
| `TDF-ENT-005` | The `deleted` Block | [Section 5.6](#56-the-deleted-block-tdf-ent-005) |
| `TDF-ENT-006` | The `queue` Block | [Section 5.7](#57-the-queue-block-tdf-ent-006) |
| `TDF-VAL-001` | Validation Contract and Deterministic Error Precedence | [Section 6.1](#61-validation-contract-and-deterministic-error-precedence-tdf-val-001) |
| `TDF-VAL-002` | Resource Bounds | [Section 6.2](#62-resource-bounds-tdf-val-002) |
| `TDF-VAL-003` | Reference Integrity, Completion State, and Acyclicity | [Section 6.3](#63-reference-integrity-completion-state-and-acyclicity-tdf-val-003) |
| `TDF-SER-001` | Canonical Serialization Contract | [Section 7.1](#71-canonical-serialization-contract-tdf-ser-001) |
| `TDF-SER-002` | Root-Level Section Order and Block Omission | [Section 7.2](#72-root-level-section-order-and-block-omission-tdf-ser-002) |
| `TDF-SER-003` | Intra-Block Directive Order and Value Formatting | [Section 7.3](#73-intra-block-directive-order-and-value-formatting-tdf-ser-003) |
| `TDF-SER-004` | Byte-Level Formatting and Column Alignment | [Section 7.4](#74-byte-level-formatting-and-column-alignment-tdf-ser-004) |
| `TDF-SER-005` | Normative Canonical Byte and SHA-256 Digest Vectors | [Section 7.5](#75-normative-canonical-byte-and-sha-256-digest-vectors-tdf-ser-005), [Appendix B.1](#b1-complete-canonical-document-example-tiertasktdf) |
| `TDF-CTX-001` | Evaluation Context Parameters | [Section 8.1](#81-evaluation-context-parameters-tdf-ctx-001) |
| `TDF-CTX-002` | UTC Instants Versus Local Wall-Clock Evaluation | [Section 8.2](#82-utc-instants-versus-local-wall-clock-evaluation-tdf-ctx-002) |
| `TDF-EVAL-001` | Pre-Filtering and `scoped` Label Exclusion | [Section 9.1](#91-pre-filtering-and-scoped-label-exclusion-tdf-eval-001) |
| `TDF-EVAL-002` | Condition Inheritance and Context Resolution | [Section 9.2.1](#921-condition-inheritance-and-context-resolution-tdf-eval-002) |
| `TDF-EVAL-003` | Rule Semantics and Short-Circuit Group Order | [Section 9.2.2](#922-rule-semantics-and-short-circuit-group-order-tdf-eval-003) |
| `TDF-EVAL-004` | Prerequisite Satisfaction | [Section 9.3](#93-prerequisite-satisfaction-tdf-eval-004) |
| `TDF-EVAL-005` | Six-Tier Classification Pipeline | [Section 9.4](#94-six-tier-classification-pipeline-tdf-eval-005) |
| `TDF-MUT-001` | Atomic Mutation Contract | [Section 10.1.1](#1011-atomic-mutation-contract-tdf-mut-001) |
| `TDF-MUT-002` | Entity and Queue Revision Rules | [Section 10.1.2](#1012-entity-and-queue-revision-rules-tdf-mut-002) |
| `TDF-CLEAN-001` | Open-Task Block-Reason Cleanup Predicates | [Section 10.1.3](#1013-open-task-block-reason-cleanup-predicates-tdf-clean-001) |
| `TDF-CLEAN-002` | Cleanup Matrix Across Lifecycle Stages | [Section 10.1.4](#1014-cleanup-matrix-across-lifecycle-stages-tdf-clean-002) |
| `TDF-CAL-001` | Resolving Local Calendar Inputs to UTC | [Section 10.2.1](#1021-resolving-local-calendar-inputs-to-utc-tdf-cal-001) |
| `TDF-CAL-002` | Mode 1 Completion-Relative Recurrence (`due` Omitted) | [Section 10.2.2](#1022-mode-1-completion-relative-recurrence-due-omitted-tdf-cal-002) |
| `TDF-CAL-003` | Mode 2 Schedule-Anchored Recurrence With `due` | [Section 10.2.3](#1023-mode-2-schedule-anchored-recurrence-with-due-tdf-cal-003) |
| `TDF-OCC-001` | Completion Counters and Prerequisite Arming | [Section 10.3](#103-completion-counters-and-prerequisite-arming-tdf-occ-001) |
| `TDF-MUT-003` | Creating Entities | [Section 10.4.1](#1041-creating-entities-tdf-mut-003) |
| `TDF-MUT-004` | Scheduling, Moving to `Someday`, and Explicit Queue Moves | [Section 10.4.2](#1042-scheduling-moving-to-someday-and-explicit-queue-moves-tdf-mut-004) |
| `TDF-MUT-005` | Downgrading Active Tasks (`Focus`, `Ready`, `Planned`) | [Section 10.4.3](#1043-downgrading-active-tasks-focus-ready-planned-tdf-mut-005) |
| `TDF-MUT-006` | Completing a Task | [Section 10.4.4](#1044-completing-a-task-tdf-mut-006) |
| `TDF-MUT-007` | Completed Checklists and Restoring From `Completed` | [Section 10.4.5](#1045-completed-checklists-and-restoring-from-completed-tdf-mut-007) |
| `TDF-MUT-008` | Ordinary Directive and Entity Mutations | [Section 10.4.6](#1046-ordinary-directive-and-entity-mutations-tdf-mut-008) |
| `TDF-MUT-009` | Deleting Live Entities and Reference Cascades | [Section 10.4.7](#1047-deleting-live-entities-and-reference-cascades-tdf-mut-009) |
| `TDF-SYNC-001` | Reconciliation Contract | [Section 11.1](#111-reconciliation-contract-tdf-sync-001) |
| `TDF-SYNC-002` | Reconciliation Phase Pipeline and Dependencies | [Section 11.2](#112-reconciliation-phase-pipeline-and-dependencies-tdf-sync-002) |
| `TDF-MERGE-001` | Common Baseline and Source Fingerprint | [Section 12.1](#121-common-baseline-and-source-fingerprint-tdf-merge-001) |
| `TDF-MERGE-002` | Conflict-Resolving Payload Tuple Order | [Section 12.2.1](#1221-conflict-resolving-payload-tuple-order-tdf-merge-002) |
| `TDF-MERGE-003` | Complete Entity Winner Selection | [Section 12.2.2](#1222-complete-entity-winner-selection-tdf-merge-003) |
| `TDF-MERGE-004` | Result Revision Assignment | [Section 12.2.3](#1223-result-revision-assignment-tdf-merge-004) |
| `TDF-MERGE-005` | Merge Units and Scalar Three-Way Rules | [Section 12.3.1](#1231-merge-units-and-scalar-three-way-rules-tdf-merge-005) |
| `TDF-MERGE-006` | Label Reference Set Merge and Pre-Cascade Reconstruction | [Section 12.3.2](#1232-label-reference-set-merge-and-pre-cascade-reconstruction-tdf-merge-006) |
| `TDF-MERGE-007` | Tombstone Stripping and Group-Wise `condition` Merge | [Section 12.3.3](#1233-tombstone-stripping-and-group-wise-condition-merge-tdf-merge-007) |
| `TDF-MERGE-008` | Occurrence-Independent Task History Set Merge | [Section 12.3.4](#1234-occurrence-independent-task-history-set-merge-tdf-merge-008) |
| `TDF-MERGE-009` | Multi-Stage Synchronization Fairness (`cleanupMode`) | [Section 12.4.1](#1241-multi-stage-synchronization-fairness-cleanupmode-tdf-merge-009) |
| `TDF-MERGE-010` | Two-Level Task Occurrence Merge | [Section 12.4.2](#1242-two-level-task-occurrence-merge-tdf-merge-010) |
| `TDF-MERGE-011` | Entity Presence and Post-Merge Cascades | [Section 12.5](#125-entity-presence-and-post-merge-cascades-tdf-merge-011) |
| `TDF-DEL-001` | Combining Deletion Records and Baseline-Implied Deletions | [Section 12.6.1](#1261-combining-deletion-records-and-baseline-implied-deletions-tdf-del-001) |
| `TDF-DEL-002` | `DeletionConflict` Classification | [Section 12.6.2](#1262-deletionconflict-classification-tdf-del-002) |
| `TDF-DEL-003` | Explicit `Delete` and `Undelete` Resolution | [Section 12.6.3](#1263-explicit-delete-and-undelete-resolution-tdf-del-003) |
| `TDF-QSYNC-001` | Shared Queue Reconciliation | [Section 12.7](#127-shared-queue-reconciliation-tdf-qsync-001) |
| `TDF-PUB-001` | Complete Result Validation | [Section 13.1.1](#1311-complete-result-validation-tdf-pub-001) |
| `TDF-PUB-002` | Mandatory Host-Local Cooperative Lock | [Section 13.1.2](#1312-mandatory-host-local-cooperative-lock-tdf-pub-002) |
| `TDF-PUB-003` | Guarded Local Retry Loop, Conditional WebDAV PUT, and Concurrency Scope | [Section 13.1.3](#1313-guarded-local-retry-loop-conditional-webdav-put-and-concurrency-scope-tdf-pub-003) |
| `TDF-PUB-004` | Thirty-Day Retention Pruning | [Section 13.2](#132-thirty-day-retention-pruning-tdf-pub-004) |
| `TDF-REC-001` | Generation Comparison, `SyncGenerationRollback`, and Refresh Reconciliation | [Section 13.3.1](#1331-generation-comparison-syncgenerationrollback-and-refresh-reconciliation-tdf-rec-001) |
| `TDF-REC-002` | `RecoveryRequired` Resolution and New-Identity Rewriting | [Section 13.3.2](#1332-recoveryrequired-resolution-and-new-identity-rewriting-tdf-rec-002) |
| `TDF-ERR-001` | Structured Error and Outcome Index | [Appendix A.1](#a1-structured-error-and-outcome-index-tdf-err-001) |
| `TDF-VEC-001` | Conformance Vector and Verification Suite Index | [Appendix A.2](#a2-conformance-vector-and-verification-suite-index-tdf-vec-001) |
| `TDF-TRACE-001` | Normative Rule ID Index | [Appendix A.3](#a3-normative-rule-id-index-tdf-trace-001) |

## Appendix B: Explanatory Examples and Design Rationale *(Informative)*

### B.1 Complete Canonical Document Example (`tiertask.tdf`)

*(Normative Vector 4 under `TDF-SER-005`: the code block below is in exact canonical `tdf 0.8.0` form — `3_086` UTF-8 bytes, `106` `LF`-terminated lines including the final `LF`, zero comments, zero intra-block blank lines, and canonical SHA-256 `sourceDigest` `cf9d9f26158d9d58d9561802d9169bb704bac7df64f09d120a1d8a2b0bb17016`. The explanatory notes following the block are informative.)*

```text
tdf 0.8.0

deleted {
    generation 4
    task 6uCk8N0aB1 2026-11-01 12:00:00
    label 1rQv7S0cD2 2026-11-02 09:00:00
    location 8tYp4M0eF3 2026-11-02 10:15:00
}

queue {
    modified 2026-11-01 19:30:00
    task 8jKaCdOkD2
    task 5vWx9ZOk91
    task 3nQp7ROkB8
}

label 4x9p2mOkD2 {
    name     "Home & Garden"
    modified 2026-11-01 08:00
    condition {
        day      sat sun
        time     08:00 20:00
        location 7pQr9mOkD2
    }
}

label 9kLm2P0aBc scoped {
    name     "IT & Servers"
    color    "#2196F3"
    note     "Infrastructure runbooks and maintenance"
    modified 2026-11-01 08:00
    link     "Grafana Dashboard" "https://grafana.example.com/d/nas"
    link     "Runbook Repo" "https://git.example.com/ops/runbooks"
    condition {
        day  mon tue wed thu fri
        time 08:00 12:00
        time 14:00 18:00
    }
}

location 7pQr9mOkD2 {
    name        "Home"
    note        "Main residence driveway and garden"
    source      "Erfurt, Germany"
    coordinates 50.9787 11.0328
    radius      150
    modified    2026-11-01 08:00
}

task 2bDf6HOkA4 {
    name     "Design 3D-printed enclosure for backup NAS"
    created  2026-11-01 12:00
    modified 2026-11-01 12:00
    labels   9kLm2P0aBc
}

task 3nQp7ROkB8 {
    name      "Order replacement lawnmower blades online"
    created   2026-11-01 18:00
    modified  2026-11-01 18:20
    labels    4x9p2mOkD2
    due       2026-11-03 17:00:00 anchor 2026-11-03 18:00:00 passive "Order before seasonal supplier cutoff"
    origin    "https://jira.example.com" "HOME-42"
    link      "Portal Login" "https://example.com/portal#login"
    link      "Local Folder" "file:///home/user/documents/tax2026"
    history   2026-11-01 18:05:00 "Checked blade part number against mower manual"
    history   2026-11-01 18:20:00 "Confirmed OEM stock with dealer"
    condition any
}

task 5vWx9ZOk91 {
    name        "Clean dust filters on home NAS server"
    created     2026-10-01 09:00
    modified    2026-11-01 10:00
    completions 1
    repeat      1 months 09:00 lead 5 days
    labels      4x9p2mOkD2 9kLm2P0aBc
    due         2026-02-28 17:00:00 anchor 2026-01-31 18:00:00 "Verify SMART health after cleaning"
    history     2026-10-01 09:30:00 "Replaced front intake filter pad"
}

task 7mPr4T09xY {
    name        "Mount winter tires"
    created     2026-10-20 14:00
    finished    2026-10-29 16:45
    modified    2026-10-29 16:45
    completions 1
    labels      4x9p2mOkD2
    history     2026-10-29 16:40:00 "Torqued lug nuts to 120 Nm"
}

task 8jKaCdOkD2 priority {
    name      "Mow the lawn"
    note      "Check fuel level before starting"
    created   2026-11-01 19:30
    modified  2026-11-01 19:30
    labels    4x9p2mOkD2
    blocked   3nQp7ROkB8
    suspended 2026-11-04 23:00:00 "Wait for blade delivery and dry forecast"
    due       2026-11-07 16:00:00 anchor 2026-11-07 17:00:00 "Before first frost"
    condition time 09:00 18:00
    subtasks auto-finish {
        step false "Get lawnmower from the shed"
        step true  "Empty grass catcher bag"
    }
}
```

Entity roles in `Europe/Berlin` local calendar context *(Informative)*:

- `2bDf6HOkA4`: Unscheduled open task in `Someday` (absent from `queue`; assigned only to `scoped` label `9kLm2P0aBc`, so excluded from the unfiltered global view under `TDF-EVAL-001`).
- `3nQp7ROkB8`: Scheduled prerequisite task in `queue` with an occurrence-scoped `passive` deadline, local `anchor`, deadline note, `origin` key, `link` entries, chronological `history`, and `condition any` global override.
- `5vWx9ZOk91`: Scheduled monthly recurring task (`repeat 1 months 09:00 lead 5 days`) whose February occurrence clamped `due` to `2026-02-28 17:00:00` UTC (`18:00` CET) while preserving `anchor 2026-01-31 18:00:00` so March resumes the 31st.
- `7mPr4T09xY`: Completed task (`finished` present, absent from `queue`) retaining its `history` entry until `> 30`-day retention pruning.
- `8jKaCdOkD2`: Scheduled prioritized task overriding only `time` (`condition time 09:00 18:00`) while inheriting `day sat sun` and `location 7pQr9mOkD2` from `4x9p2mOkD2`.

### B.2 Prerequisite Occurrence Walkthrough *(Informative)*

```text
tdf 0.8.0

queue {
    modified 2026-11-04 09:00:00
    task 8jKaCdOkD2
    task 3nQp7ROkB8
}

task 3nQp7ROkB8 {
    name     "Install update"
    created  2026-11-04 09:00
    modified 2026-11-04 09:00
    blocked  8jKaCdOkD2:8
}

task 8jKaCdOkD2 {
    name        "Create backup"
    created     2026-11-01 08:00
    modified    2026-11-04 08:00
    completions 7
    repeat      1 days 09:00
}
```

`3nQp7ROkB8` waits for `8jKaCdOkD2` completion `8`. When `8jKaCdOkD2` completes occurrence `8`, non-recurring `3nQp7ROkB8`'s satisfied `blocked 8jKaCdOkD2:8` entry is stripped by `TDF-CLEAN-001`, releasing the update into the active pull cycle while the backup schedules occurrence `9`. If `3nQp7ROkB8` also carried `repeat`, `blocked 8jKaCdOkD2:8` would remain stored and satisfied across backup completion `9` until `3nQp7ROkB8` completed its own occurrence and rearmed.

### B.3 Design Rationale *(Informative)*

- **Single `queue` Source of Truth:** Storing scheduling order and membership once in `queue` eliminates split-brain inconsistencies between per-task flags and shared list order and allows temporary `Blocked` restrictions to release tasks back into their exact saved slots without rewriting `queue` or `modified`.
- **Explicit Local `due.anchor`:** A single UTC `due` instant loses whether `2026-02-28` originated on the 28th or was clamped from January 31 (and loses a pre-gap `02:30` local clock shifted to `03:30`). Recording optional `anchor` on `due` while advancing monthly recurrences from `oldDue`'s current local year-month makes sequential `k = 1` completions commute with multi-month `k = 2` jumps and `repeat` interval changes without embedding an IANA zone inside `.tdf`.
- **Stage-Gated `cleanupMode = deferred`:** In multi-stage local-cache-plus-remote synchronization (including intermediate local contention retries), stripping `suspended <= now` and advancing `modified = now` during an intermediate local stage would artificially elevate an older local edit's timestamp above a newer remote edit's timestamp. Deferring `now`-based cleanup until the final stage (`cleanupMode = final`) preserves direct-merge commutativity.
- **Host-Local Cooperative Locks Outside Sync Folders:** Advisory `.tdf.lock` files inside cloud-synced folders are replicated across machines as stale ghost locks, whereas locking open file descriptors of `<target>` alone fails when writers replace `<target>` via `rename`. Placing non-unlinked `flock`/`LockFileEx` locks (`FILE_SHARE_READ | FILE_SHARE_WRITE` without `FILE_SHARE_DELETE` on Windows) in `$XDG_RUNTIME_DIR/tdf-locks` or `%LOCALAPPDATA%\Temp\tdf-locks` closes intra-host races cleanly without polluting synced workspaces.
