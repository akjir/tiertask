---
name: tep
description: >-
  Manage, specify, and track TierTask Enhancement Proposals (TEP) in .agents/proposals/. Triggered when the user types `/tep` or works on an existing TEP. Covers TEP trigger rules, proactive recommendations on complex or spec/TDF_SPEC_0.6.0.md changes (including during `/plan`), lifecycle stages, 3-part specification template (Concept, Design, Implementation), and TDD transitions.
---

# TierTask Enhancement Proposals (TEP) Workflow

## 1. Trigger, Scope & Recommendation Policy
* **Explicit Creation Only (`/tep`):** Create a new TEP (`tep-XXX-<slug>.md` and `BOARD.md` entry) **only** when the user explicitly invokes `/tep` (or explicitly confirms after a recommendation). Never create a TEP autonomously without user confirmation.
* **Excluded Scope (No TEP):** Never create or recommend a TEP for minor UI adjustments, bug fixes, localization wording tweaks, small internal refactorings, or isolated test/documentation updates. Execute those directly via **`tiertask-dev-workflow`**.
* **Proactive Recommendation (Standard Requests & `/plan`):**
  * **Standard Requests:** When a user request (without `/tep`) involves high complexity — such as cross-layer architectural changes, major new capabilities, or **especially any change affecting `spec/TDF_SPEC_0.6.0.md`** — recommend creating a TEP with a concise factual justification and ask the user whether to proceed via `/tep` or implement directly.
  * **When `/plan` is Used:** When the user invokes `/plan` (without `/tep`) for a complex feature or `spec/TDF_SPEC_0.6.0.md` modification, elaborate the full implementation plan in `implementation_plan.md` as usual for `/plan`, **and** include a reasoned recommendation (`> [!IMPORTANT]`) advising that the change should go through the formal TEP process (`/tep` in `.agents/proposals/`) rather than direct implementation, asking the user how they want to proceed.

## 2. Files & Structure
* **Directory:** `.agents/proposals/`
* **Board:** `.agents/proposals/BOARD.md` (table of TEP IDs, titles, types, statuses)
* **Template:** `.agents/proposals/TEMPLATE.md`
* **Proposals:** `tep-XXX-<slug>.md` (e.g., `tep-001-example-feature.md`)

## 3. Lifecycle Stages
* **`concept`:** Define the idea, motivation, goals/non-goals, and alternatives (Part 1).
* **`planned`:** Agree on architecture, `spec/TDF_SPEC_0.6.0.md` schema changes, localization (`app_en.arb`, `app_de.arb`), and `M-*` TDD test strategy with the user (Part 2). Run **`spec-verification-loop`** (`.agents/skills/spec-verification-loop/SKILL.md`) whenever `/tep <filepath>` is invoked to audit or finalize a TEP specification.
* **`in-progress`:** Run `python3 .agents/scripts/tiertask_dev.py verify --fast` first to confirm a clean baseline. Implement with strict Red-Green-Refactor TDD per **`tiertask-dev-workflow`** (and **`tdf-spec-workflow`** when `spec/TDF_SPEC_0.6.0.md` changes). Track tasks in Part 3.1. Update Parts 1 and 2 if the design changes during coding.
* **`review`:** Pass `python3 .agents/scripts/tiertask_dev.py verify --full --fix`, sync `README.md`, `ARCHITECTURE.md`, `AGENTS.md`, and `spec/TDF_SPEC_0.6.0.md` per **`update-documentation`** and **`tdf-spec-workflow`**, update `CHANGELOG.md` per **`changelog-updater`**, set `status: review`, update `BOARD.md`, and ask the user for approval. Never set `completed` without user approval.
* **`completed`:** After user approval, set `status: completed`, update `BOARD.md`, and record delivered artifacts in Part 3.3. Keep completed proposals permanently. If superseded later, keep `status: completed` and add a `> [!NOTE]` block at the top referencing the superseding TEP.
* **`rejected`:** Document the rejection reason and set `status: rejected`.

## 4. Creating a Proposal (`/tep`)
1. Pick the next 3-digit ID from `BOARD.md` (starting at `TEP-001`).
2. Copy `TEMPLATE.md` to `tep-XXX-<slug>.md`.
3. Complete the YAML frontmatter, Part 1, and Part 2 (without using `---` horizontal rules in the Markdown body per `P-LANG-RULES`).
4. Add the proposal to the `Active Proposals` table in `BOARD.md`.

## 5. Implementation Rules
* **Strict TDD (`P-TDD-FIRST`):** Write failing tests in `test/` before modifying production code in `lib/`.
* **Unidirectional Architecture & I/O Isolation (`P-UDF-ARCHITECTURE`, `P-IO-ISOLATION`):** Keep domain models (`lib/models/`), services (`lib/services/`), and UI (`lib/ui/`) pure; isolate all network, file, and secure storage I/O in `lib/repositories/`.
* **Bounds & Performance (`P-BOUND-ALLOC`, `P-ZERO-COPY`, `P-NO-QUADRATIC`):** Enforce explicit `max*` bounds before reading or allocating the $(N+1)$-th element and maintain single-pass $O(N)$ TDF scanning and serialization.
* **Diagnostic Instrumentation (`AGENTS.md` Section 6):** Instrument all new or modified domain mutations, TDF parser/migration rules, sync logic, and repository operations with `AppLogger`.
* **Sync Docs:** Follow **`tdf-spec-workflow`**, **`update-documentation`**, and **`changelog-updater`** when `.tdf` syntax, architecture, files, or user-facing features change.

## 6. Token Efficiency
* Read `BOARD.md` first.
* Read only the specific `tep-XXX-*.md` file required for the active task. Never read all proposals at once.
