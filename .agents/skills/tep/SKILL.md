---
name: tep
description: Manages TierTask Enhancement Proposals (TEP) in .agents/proposals/. Triggered by /tep or active TEP work; covers creation rules, proactive recommendations (including /plan), lifecycle stages, and templates.
---

# TierTask Enhancement Proposals (TEP) Workflow

## 1. Trigger & Recommendation Policy
- **Explicit Creation Only:** Create a TEP (`tep-XXX-<slug>.md` + `BOARD.md` entry) ONLY when the user invokes `/tep` or confirms a recommendation.
- **Excluded Scope:** Never create or recommend a TEP for minor UI tweaks, bug fixes, localization wording changes, small internal refactors, or isolated doc/test updates; use **`tiertask-dev-workflow`** directly.
- **Proactive Recommendation:**
  - *Standard Requests:* For high-complexity work, cross-layer architectural changes, or any change affecting `spec/TDF_SPEC_0.8.0.md`, recommend creating a TEP with concise justification and ask whether to use `/tep` or implement directly.
  - *During `/plan`:* Still deliver the full `implementation_plan.md`, and include a `> [!IMPORTANT]` recommendation advising the formal `/tep` process before direct implementation, asking how to proceed.

## 2. Files & Token Discipline
- **Paths:** `.agents/proposals/BOARD.md` (registry), `.agents/proposals/TEMPLATE.md`, `.agents/proposals/tep-XXX-<slug>.md`.
- **Token Rule:** Read `BOARD.md` first; open ONLY the single target `tep-XXX-*.md` file. Never batch-read all proposals.

## 3. Lifecycle Stages
- **`concept`:** Draft idea, motivation, goals/non-goals, and alternatives (Part 1).
- **`planned`:** Finalize architecture, `spec/TDF_SPEC_0.8.0.md` changes, ARB localization, and `M-*` test strategy with the user (Part 2). Run **`spec-verification-loop`** when `/tep <filepath>` is invoked to audit or finalize a TEP.
- **`in-progress`:** Confirm clean baseline (`python3 .agents/scripts/tiertask_dev.py verify --fast`), then implement via **`tiertask-dev-workflow`** (and **`tdf-spec-workflow`** if the TDF spec changes), including `AppLogger` instrumentation (`AGENTS.md` Section 6). Track tasks in Part 3.1 and update Parts 1–2 if design shifts.
- **`review`:** Pass `python3 .agents/scripts/tiertask_dev.py verify --full --fix`, sync docs (`update-documentation`, `tdf-spec-workflow`) and `CHANGELOG.md` (`changelog-updater`), set `status: review`, update `BOARD.md`, and ask for user approval. Never set `completed` without approval.
- **`completed`:** After approval, set `status: completed`, update `BOARD.md`, and list delivered artifacts in Part 3.3. Keep permanently; if superseded later, keep `status: completed` and add a top `> [!NOTE]` referencing the superseding TEP.
- **`rejected`:** Record the rejection reason and set `status: rejected`.

## 4. Creating a Proposal (`/tep`)
1. Pick the next 3-digit ID from `BOARD.md` (starting at `TEP-001`).
2. Copy `TEMPLATE.md` to `.agents/proposals/tep-XXX-<slug>.md`.
3. Complete YAML frontmatter, Part 1, and Part 2 (no `---` dividers in Markdown body per `P-LANG-RULES`).
4. Register the entry under `Active Proposals` in `BOARD.md`.
