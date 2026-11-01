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
- **Resource Bounds Enforcement (`P-BOUND-ALLOC`):** Map the normative bounds in `TDF_SPEC.md` Section 7 (`MAX_FILE_BYTES`, `MAX_LINE_COUNT`, `MAX_NESTING_DEPTH`, `MAX_BLOCKS_PER_DOC`, `MAX_STMTS_PER_BLOCK`, `MAX_ARGS_PER_STMT`, `MAX_TEXT_LENGTH`) to `static const int max*` constants and check every cardinality bound **before** scanning or allocating the $(N+1)$-th element.

## 3. Spec-Driven Modification Protocol (`P-TDD-FIRST`)
Whenever the user modifies `TDF_SPEC.md` or instructs you to implement or change TDF parsing, serialization, or domain evaluation rules, execute these exact steps in order:

1. **Diff & Analyze Spec:** Read `TDF_SPEC.md` and identify the exact lexical, grammatical, schema, tier evaluation, mutation, or resource bound changes in Sections 2 through 8.
2. **Update Tests First (TDD Red Phase — `P-TDD-FIRST`):**
   - Locate the test suite in `test/`.
   - Add or update positive test cases for valid TDF syntax, present vs. omitted directive/flag semantics (`priority`, `queued`, `finished`, `blocked`, `suspended`, `condition`, `auto-finish`), 6-tier derivation, and document mutations.
   - Add or update negative test cases for every error condition in `TDF_SPEC.md` Section 8 and resource bound in Section 7 (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`, delimiter/quote/newline/comment injection).
   - Run `flutter test` to verify that the new or updated tests fail as expected against the current implementation.
3. **Update Implementation (TDD Green & Refactor Phase):**
   - Modify the scanner, parser, serializer (`lib/services/`), and domain models (`lib/models/`) to satisfy `TDF_SPEC.md` while strictly adhering to `AGENTS.md` layout and memory rules (`P-STDLIB-FIRST`, `P-NO-QUADRATIC`, `P-BOUND-ALLOC`, `P-ZERO-COPY`, `P-FLAT-CONTROL-FLOW`, `P-NO-NESTED-LOOPS`).
4. **Update Documentation:** Synchronize `README.md`, `ARCHITECTURE.md`, `AGENTS.md`, and `CHANGELOG.md` per **`update-documentation`** and **`changelog-updater`**.
5. **Verify:** Run `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze --fatal-infos --fatal-warnings`, and `flutter test` until all checks pass with zero warnings.
