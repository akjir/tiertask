---
name: tdf-spec-workflow
description: Enforces Spec-Driven TDD for spec/TDF_SPEC_0.8.0.md. Activate when editing the TDF spec or changing TDF scanning, parsing, serialization, tier derivation, mutation, or sync rules.
---

# TDF Spec-Driven Workflow

## 1. Standalone Spec Boundary (`spec/TDF_SPEC_0.8.0.md`)
Keep `spec/TDF_SPEC_0.8.0.md` strictly language- and project-agnostic (lexical/structural grammar, directives with present vs. omitted semantics, 6-tier derivation, mutations, sync/publication, bounds, errors). Never place Dart/Flutter types, `lib/` paths, `flutter` commands, or `AGENTS.md` rule IDs inside `spec/TDF_SPEC_0.8.0.md`.

## 2. Codebase Mapping
- **Scanner, Parser & Serializer (`lib/services/`):** Dart SDK only, single-pass $O(N)$, canonical `LF` (`\n`) output (`tdf_scanner.dart`, `tdf_parser.dart`, `tdf_directive_parser.dart`, `tdf_serializer.dart`, `tdf_service.dart`; `P-STDLIB-FIRST`, `P-NO-QUADRATIC`, `P-ZERO-COPY`).
- **Domain Models, Evaluation, Mutations & Sync (`lib/models/`):** Immutable models, $O(N)$ 6-tier derivation (Sections 8–9), mutations (Section 10), and three-way sync/recovery (Sections 11–13) (`tdf_error.dart`, `tdf_metadata.dart`, `tdf_location.dart`, `tdf_timezone.dart`, `tdf_sync_metadata.dart`, `tdf_payload_comparison.dart`, `task_item.dart`, `task_board*.dart`).
- **Resource Bounds (`P-BOUND-ALLOC`):** Map every `MAX_*` constant in `spec/TDF_SPEC_0.8.0.md` Section 6.2 to `const int maxTdf*` in `lib/models/tdf_error.dart` and enforce before scanning or allocating the $(N+1)$-th element.

## 3. Spec-Driven TDD Steps (`P-TDD-FIRST`)
1. **Outline & Diff Spec:** Run `python3 .agents/scripts/tiertask_dev.py outline spec/TDF_SPEC_0.8.0.md` (or `git diff spec/TDF_SPEC_0.8.0.md`) and read only relevant line ranges.
2. **Red (Tests & Conformance Vectors First):**
   - Locate suites in `test/services/`, `test/models/`, and `spec/conformance/v0.8.0/` (`tdf_v080_conformance_test.dart`, `tdf_v080_merge_conformance_test.dart`).
   - Add/update positive cases (all root blocks, present vs. omitted directives/flags, 6-tier derivation, mutations, three-way sync) and negative cases covering `spec/TDF_SPEC_0.8.0.md` Appendix A.1 errors and Section 6.2 bounds (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`, `M-DELIM-INJECT-TESTS`).
   - Run `flutter test --no-pub --no-test-assets -r failures-only <target_tests>` and confirm failure.
3. **Green & Refactor:** Update `lib/services/` and `lib/models/` per `AGENTS.md` (Sections 1–4 and Section 6 `AppLogger` instrumentation).
4. **Sync Spec Appendices & Docs:** Keep `spec/TDF_SPEC_0.8.0.md` Appendix A.1–A.3, `README.md`, `ARCHITECTURE.md`, `AGENTS.md`, and `CHANGELOG.md` aligned (`update-documentation`, `changelog-updater`).
5. **Verify:** Run `python3 .agents/scripts/tiertask_dev.py verify --full --fix` until all checks pass with zero warnings.
