---
name: tdf-spec-workflow
description: >-
  Enforces Spec-Driven Test-Driven Development (TDD) for the TierTask Data Format (TDF) defined in TDF_SPEC.md. Activate whenever TDF_SPEC.md is modified or when implementing or changing the TDF lexical scanner, structural parser, serializer, dynamic tier derivation pipeline, or document mutation rules in lib/services/ and lib/models/.
---

# TDF Spec-Driven Development Workflow

## 1. Standalone Specification Boundary (`TDF_SPEC.md`)
- **Language- & Project-Agnostic Format Spec:** Keep `TDF_SPEC.md` strictly focused on the `.tdf` file format, its lexical/structural grammar, directive semantics (including behavior when optional flags or directives are omitted), dynamic 6-tier derivation pipeline, state mutations, resource bounds, and error conditions.
- **No Implementation Specifics in `TDF_SPEC.md`:** Never place Dart/Flutter types, repository file paths (`lib/services/`), CLI test commands (`flutter test`), or `AGENTS.md` rule identifiers (`P-TDD-FIRST`, `P-BOUND-ALLOC`) inside `TDF_SPEC.md`. All TierTask implementation mappings belong in this skill, `AGENTS.md`, and `ARCHITECTURE.md`.

## 2. TierTask Architectural Mapping for `TDF_SPEC.md`
- **Target Parser & Serializer Layer (`lib/services/`):** Implement the TDF lexical scanner, structural block/directive parser, and canonical `LF` (`\n`) serializer in `lib/services/` using only the Dart standard library (`dart:core`, `dart:convert`, `StringBuffer`) in a single $O(N)$ pass (`P-STDLIB-FIRST`, `P-NO-QUADRATIC`, `P-ZERO-COPY`).
- **Target Domain Model Layer (`lib/models/`):** Implement immutable domain models (`P-IMMUTABLE-MODELS`), the $O(N)$ 6-tier evaluation pipeline (`Completed`, `Someday`, `Blocked`, `Focus`, `Ready`, `Planned` per `TDF_SPEC.md` Section 5), and deterministic state mutations (`TDF_SPEC.md` Section 6) in `lib/models/`.
- **Resource Bounds Enforcement (`P-BOUND-ALLOC`):** Map the normative bounds in `TDF_SPEC.md` Section 7 (`MAX_FILE_BYTES`, `MAX_LINE_COUNT`, `MAX_NESTING_DEPTH`, `MAX_BLOCKS_PER_DOC`, `MAX_STMTS_PER_BLOCK`, `MAX_ARGS_PER_STMT`, `MAX_TEXT_LENGTH`, `MAX_NOTE_LENGTH`, `MAX_DELETED_RECORDS`) to `static const int max*` constants and check every cardinality bound **before** scanning or allocating the $(N+1)$-th element.

## 3. Spec-Driven Modification Protocol (`P-TDD-FIRST`)
Whenever the user modifies `TDF_SPEC.md` or instructs you to implement or change TDF parsing, serialization, or domain evaluation rules, execute these exact steps in order:

1. **Outline & Diff Spec:** Run `python3 .agents/scripts/tiertask_dev.py outline TDF_SPEC.md` (or `git diff TDF_SPEC.md`) to locate exact section `StartLine-EndLine` ranges, then read only the relevant sections of `TDF_SPEC.md` (Sections 2 through 10). Never paginate blindly through all 2,226 lines of `TDF_SPEC.md`.
2. **Update Tests First (TDD Red Phase — `P-TDD-FIRST`, `P-TEST-MIRROR`):**
   - Locate the corresponding domain or service test suite in `test/services/` and `test/models/` using `python3 .agents/scripts/tiertask_dev.py outline` or `find`.
   - Add or update positive test cases for valid TDF `0.5.1` syntax, root blocks (`queue`, `deleted`, `label`, `task`), present vs. omitted directive/flag semantics (`priority`, `finished`, `modified`, `blocked`, `suspended`, `repeat`, `condition`, `link`, `subtasks auto-finish`), 6-tier derivation, three-way synchronization, and document mutations.
   - Add or update negative test cases for every error condition in `TDF_SPEC.md` Section 8 and resource bound in Section 7 (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`, `M-DELIM-INJECT-TESTS`).
   - Run `flutter test --no-pub --no-test-assets -r failures-only <target_tests>` to verify that the new or updated tests fail as expected against the current implementation.
3. **Update Implementation (TDD Green & Refactor Phase — `P-FILE-SIZE`):**
   - Modify the scanner, parser, serializer, importer (`lib/services/`), and domain models (`lib/models/`) to satisfy `TDF_SPEC.md` while adhering to `AGENTS.md` layout, responsibility-based modularity (`P-FILE-SIZE`), and memory rules (`P-STDLIB-FIRST`, `P-NO-QUADRATIC`, `P-BOUND-ALLOC`, `P-ZERO-COPY`, `P-FLAT-CONTROL-FLOW`, `P-NO-NESTED-LOOPS`).
4. **Update Documentation:** Synchronize `README.md`, `ARCHITECTURE.md`, `AGENTS.md`, and `CHANGELOG.md` per **`update-documentation`** and **`changelog-updater`**.
5. **Verify:** Run `python3 .agents/scripts/tiertask_dev.py verify --full --fix` until all static checks, analyzer diagnostics, formatting, and tests pass with zero warnings.
