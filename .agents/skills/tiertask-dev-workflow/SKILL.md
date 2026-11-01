---
name: tiertask-dev-workflow
description: >-
  Build, test, and develop TierTask in Flutter and Dart. Enforces strict Red-Green-Refactor TDD, the edit-verify cycle, and testing standards.
---

# TierTask Development Workflow

## 1. TDD Edit-Analyze-Test Cycle (`P-TDD-FIRST`)
1. **Verify Baseline:** Run `flutter test` and `flutter analyze --fatal-infos --fatal-warnings` before editing files.
2. **Red Phase (Write Failing Tests First — `P-TDD-FIRST`):**
   - Before writing or modifying production code in `lib/`, write or update unit tests or widget tests in `test/` (mirroring `lib/<layer>/<name>.dart` in `test/<layer>/<name>_test.dart`).
   - Run `flutter test` and confirm that the new or updated test fails for the expected reason.
3. **Green Phase (Minimal Production Implementation — `AGENTS.md` Sections 1–3):** Place core logic in dedicated `snake_case.dart` leaf files:
   - **Layout & Imports (`P-LICENSE-HEADER`, `P-DIRECTIVES-ORDER`):** Follow the 7-part vertical layout (verbatim GPL-3.0 header + blank line + `///` docs + 3-group alphabetized imports: `dart:`, `package:`, relative imports in `lib/` or `package:tiertask/` in `test/`). Order class members strictly (constructors, `static const`/`static final`, `final` fields, getters, lifecycle overrides, public methods, `_private` methods, `==`/`hashCode`/`toString`).
   - **Types, Immutability & Docs (`P-FN-DOCS`, `P-IMMUTABLE-MODELS`, `P-CONST-WIDGETS`, `P-NO-DEAD-CODE`, `P-LANG-RULES`):** Favor immutable models (`const` constructors, `final` fields, `List.unmodifiable`, `copyWith`, value `==` and `hashCode`), `enum` / `sealed class` states over boolean flags, and `super.key` on widgets. Document every production item (`public`, `_private`, and extracted helpers) with concise English `///` comments (ASD-STE100 80%, zero emojis); omit redundant `///` on `test()` blocks. Write only directly called items.
4. **Refactor Phase — Flatness, Readability & Performance Gate (`P-VERTICAL-CLARITY`, `P-FLAT-CONTROL-FLOW`, `P-FLATTEN-BUILD`, `P-NO-NESTED-LOOPS`, `P-LOOP-MODULARITY`, `P-FUNCTIONAL-COMBINATORS`, `P-ZERO-ALLOC`, `P-BOUND-ALLOC`, `P-LAZY-LISTS`, `P-DISPOSE-RESOURCES`):**
   - Enforce zero nested loops (`P-NO-NESTED-LOOPS`), indentation $\le 3$ levels (`P-FLAT-CONTROL-FLOW`), loop bodies $< 25$ lines (`P-LOOP-MODULARITY`), and `build()` / dispatcher methods $< 40$ lines (`P-FLATTEN-BUILD`).
   - Extract UI subtrees into dedicated `const` `StatelessWidget` or `ConsumerWidget` classes rather than helper methods returning `Widget`.
   - Deconstruct nullable values and sealed types via Dart 3 pattern matching (`switch`, `if (value case final v?)`), `??`, or `?.` (never check `!= null` then force-unwrap with `!`). Prefer flat `for` loops calling a helper over complex combinator chains (`P-FUNCTIONAL-COMBINATORS`, `P-VERTICAL-CLARITY`).
   - Eliminate avoidable loop/build allocations (compile `RegExp` as `static final`, use `StringBuffer` for serialization, use `ListView.builder` for dynamic task lists), check `max*` resource bounds before scanning or allocating the $(N+1)$-th element (`P-BOUND-ALLOC`), and dispose all controllers, streams, and `HttpClient` instances (`P-DISPOSE-RESOURCES`).
5. **License, Documentation & Dead-Code Gate (`P-LICENSE-HEADER`, `P-FN-DOCS`, `P-NO-DEAD-CODE`, `P-NO-IGNORE`):** Verify license headers, `///` docs, zero `// ignore:` directives, and delete all orphaned functions, fields, enum variants, providers, imports, and obsolete tests.
6. **Format, Analyze & Test:** Run `dart format lib test`, `flutter analyze --fatal-infos --fatal-warnings`, and `flutter test` after every modification.
7. **Sync Docs & Changelog:** Follow **`update-documentation`** (`README.md`, `ARCHITECTURE.md`, `AGENTS.md`) and **`changelog-updater`** (`CHANGELOG.md`).

## 2. Testing Standards (`flutter test`)
- **Coverage & Assertions:** Write unit and widget tests for every feature, parser routine, state transition, repository method, widget interaction, or bug fix. Use semantic matchers (`contains()`, `equals()`, `isA<T>()`, `throwsA(isA<DomainException>())`) over brittle exact-string checks, and include concise `reason:` strings in `expect(..., reason: '...')` for loops, table-driven cases, and state transitions.
- **Required Edge Cases (`AGENTS.md` Section 5):** Cover all `enum` and `sealed class` branches (`M-EXHAUSTIVE-STATE-TESTS`), WIP/retention/`max*` boundaries (`M-EXTREME-BOUND-TESTS`), Markdown delimiter/newline/control/BiDi injection (`M-MARKDOWN-INJECT-TESTS`), generic WebDAV URI and local/remote path traversal edge cases (`M-URI-PATH-EDGE-TESTS`), and isolated HTTP, local file, and secure storage failure tests via mock repositories, temporary directories (`Directory.systemTemp`), or loopback `HttpServer` (`M-IO-TESTS`).
