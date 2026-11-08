#!/usr/bin/env python3
# TierTask
# Copyright (C) 2026  Stefan Stark
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <https://www.gnu.org/licenses/>.

"""Zero-dependency developer and AI agent automation CLI for TierTask."""

from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Any


GPL_HEADER_LINES = [
    "// TierTask",
    "// Copyright (C) 2026  Stefan Stark",
    "//",
    "// This program is free software: you can redistribute it and/or modify it under",
    "// the terms of the GNU General Public License as published by the Free Software",
    "// Foundation, either version 3 of the License, or (at your option)",
    "// any later version.",
    "//",
    "// This program is distributed in the hope that it will be useful, but WITHOUT",
    "// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS",
    "// FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.",
    "//",
    "// You should have received a copy of the GNU General Public License along with",
    "// this program.  If not, see <https://www.gnu.org/licenses/>.",
]
GPL_HEADER = "\n".join(GPL_HEADER_LINES) + "\n"

MAX_ARCH_ROW_WORDS = 65
STAMP_REL_PATH = Path(".dart_tool/tiertask_verify_stamp.json")

_MD_HEADING_RE = re.compile(r"^(#{1,4})\s+(.+?)\s*$")
_DART_TYPE_RE = re.compile(
    r"^(?:(abstract|sealed|base|final|interface|mixin)\s+)*"
    r"(class|enum|extension|typedef|mixin)\s+([A-Za-z_][A-Za-z0-9_]*)",
)
_DART_PROVIDER_RE = re.compile(
    r"^final\s+([A-Za-z_][A-Za-z0-9_]*Provider)\s*=",
)
_DART_IMPORT_RE = re.compile(r"^\s*import\s+['\"]([^'\"]+)['\"]")
_DART_FORBIDDEN_DIRECTIVE_RE = re.compile(r"^\s*(?:export\s+['\"]|part\s+['\"]|part\s+of\s+)")
_TRAILING_GENERIC_RE = re.compile(r"<[^>]*>$")
_TEST_CALL_START_RE = re.compile(r"^(\s*)(group|test|testWidgets)\(\s*(.*)$")
_STRING_LITERAL_RE = re.compile(r"(['\"])((?:\\.|(?!\1).)*)\1")
_VALUE_KEY_RE = re.compile(r"(?:ValueKey|Key)\(\s*['\"]([^'\"$]+)['\"]\s*\)")
_PLACEHOLDER_RE = re.compile(r"\{([a-zA-Z_][a-zA-Z0-9_]*)\}")
_IGNORE_COMMENT_RE = re.compile(r"//\s*ignore(?:_for_file)?:")
_EMOJI_RE = re.compile(
    r"[\U0001F300-\U0001FAFF\U00002700-\U000027BF\U0001F600-\U0001F64F\U0001F680-\U0001F6FF]",
)


def repo_root() -> Path:
    """Resolves the TierTask repository root relative to this script."""
    return Path(__file__).resolve().parents[2]


def _is_generated_dart(rel_path: str) -> bool:
    """Returns True for generated localization Dart files."""
    name = Path(rel_path).name
    return name.startswith("app_localizations") and name.endswith(".dart")


def _iter_dart_files(root: Path, include_generated: bool = False) -> list[Path]:
    """Returns sorted Dart files under lib/ and test/."""
    results: list[Path] = []
    for sub in ("lib", "test"):
        base = root / sub
        if not base.exists():
            continue
        for p in sorted(base.rglob("*.dart")):
            rel = p.relative_to(root).as_posix()
            if not include_generated and _is_generated_dart(rel):
                continue
            results.append(p)
    return results


def _find_matching_brace_line(
    lines: list[str],
    start_idx: int,
    allow_inside_parens: bool = False,
) -> int:
    """Finds the 0-based line index where body braces opened at or after start_idx close."""
    brace_depth = 0
    paren_depth = 0
    opened = False
    in_str: str | None = None
    for idx in range(start_idx, len(lines)):
        line = lines[idx]
        i = 0
        while i < len(line):
            ch = line[i]
            if in_str is not None:
                if ch == "\\":
                    i += 2
                    continue
                if line.startswith(in_str, i):
                    i += len(in_str)
                    in_str = None
                    continue
                i += 1
                continue
            if ch in ("'", '"'):
                if line[i : i + 3] in ("'''", '"""'):
                    in_str = line[i : i + 3]
                    i += 3
                    continue
                in_str = ch
                i += 1
                continue
            if ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
                break
            if not opened:
                if ch == "(":
                    paren_depth += 1
                elif ch == ")":
                    paren_depth = max(0, paren_depth - 1)
                elif ch == "{" and (allow_inside_parens or paren_depth == 0):
                    brace_depth = 1
                    opened = True
                elif ch == ";" and paren_depth == 0:
                    return idx
            else:
                if ch == "{":
                    brace_depth += 1
                elif ch == "}":
                    brace_depth -= 1
                    if brace_depth <= 0:
                        return idx
            i += 1
    return len(lines) - 1


def _collect_signature(lines: list[str], start_idx: int, max_len: int = 120) -> tuple[str, int]:
    """Collects a normalized single-line signature up to body `{`, `=>`, `;`, or initializer `:`."""
    chars: list[str] = []
    paren_depth = 0
    seen_close_paren = False
    end_idx = start_idx
    for idx in range(start_idx, min(len(lines), start_idx + 15)):
        end_idx = idx
        raw = lines[idx].strip()
        if raw.startswith("//"):
            break
        if chars:
            chars.append(" ")
        i = 0
        done = False
        while i < len(raw):
            ch = raw[i]
            if ch == "(":
                paren_depth += 1
                chars.append(ch)
            elif ch == ")":
                paren_depth = max(0, paren_depth - 1)
                if paren_depth == 0:
                    seen_close_paren = True
                chars.append(ch)
            elif paren_depth == 0 and ch == "{":
                done = True
                break
            elif paren_depth == 0 and raw.startswith("=>", i):
                done = True
                break
            elif paren_depth == 0 and ch == ";":
                done = True
                break
            elif paren_depth == 0 and seen_close_paren and ch == ":":
                done = True
                break
            else:
                chars.append(ch)
            i += 1
        if done:
            break
    joined = re.sub(r"\s+", " ", "".join(chars)).strip()
    if len(joined) > max_len and "(" in joined and joined.endswith(")"):
        head = joined[: max_len - 5].rstrip(" ,")
        joined = f"{head}, ...)"
    return joined, end_idx


def outline_markdown(lines: list[str]) -> list[str]:
    """Builds a line-range outline of Markdown headings outside fenced code blocks."""
    headings: list[tuple[int, int, str, str]] = []
    in_fence = False
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = _MD_HEADING_RE.match(line)
        if m:
            level = len(m.group(1))
            headings.append((idx + 1, level, m.group(1), m.group(2)))

    out: list[str] = []
    total = len(lines)
    for i, (start_ln, level, hashes, title) in enumerate(headings):
        end_ln = total
        for next_ln, next_level, _, _ in headings[i + 1 :]:
            if next_level <= level:
                end_ln = next_ln - 1
                break
        indent = "  " * (level - 1)
        out.append(f"{indent}{start_ln}-{end_ln}: {hashes} {title}")
    return out


def outline_dart_lib(lines: list[str]) -> list[str]:
    """Builds a line-range and signature outline for a production Dart file."""
    out: list[str] = []
    idx = 0
    total = len(lines)
    while idx < total:
        line = lines[idx]
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or stripped.startswith("import ") or stripped.startswith("@"):
            idx += 1
            continue

        pm = _DART_PROVIDER_RE.match(stripped)
        if pm:
            end_idx = _find_matching_brace_line(lines, idx, allow_inside_parens=True)
            out.append(f"  {idx + 1}-{end_idx + 1}: provider {pm.group(1)}")
            idx = end_idx + 1
            continue

        tm = _DART_TYPE_RE.match(stripped)
        if tm:
            kind = tm.group(2)
            name = tm.group(3)
            end_idx = _find_matching_brace_line(lines, idx)
            if kind in ("class", "enum", "extension", "mixin"):
                member_entries: list[str] = []
                priv_count = _outline_class_members(
                    lines,
                    idx + 1,
                    end_idx,
                    name,
                    member_entries,
                )
                span_len = end_idx - idx + 1
                out.append(
                    f"  {idx + 1}-{end_idx + 1}: {kind} {name} ({span_len}L, {priv_count} private methods)"
                )
                out.extend(member_entries)
            else:
                out.append(f"  {idx + 1}-{end_idx + 1}: {kind} {name}")
            idx = end_idx + 1
            continue

        if not line.startswith(" ") and "(" in stripped and not stripped.startswith("const "):
            sig, _ = _collect_signature(lines, idx)
            end_idx = _find_matching_brace_line(lines, idx)
            out.append(f"  {idx + 1}-{end_idx + 1}: fn {sig}")
            idx = end_idx + 1
            continue

        idx += 1
    return out


_IDENT_TOKEN_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def _extract_method_identifier(sig: str) -> str | None:
    """Extracts the method identifier before the parameter list `(`, handling Dart 3 record return types."""
    s = sig.strip()
    if s.startswith("static "):
        s = s[len("static ") :].strip()
    angle = 0
    paren = 0
    last_ident: str | None = None
    i = 0
    while i < len(s):
        ch = s[i]
        if ch == "<":
            angle += 1
            i += 1
        elif ch == ">":
            angle = max(0, angle - 1)
            i += 1
        elif ch == "(":
            if angle == 0 and paren == 0 and last_ident is not None and last_ident != "Function":
                return last_ident if "(" not in s[i + 1 :] or s.endswith(")") else last_ident
            paren += 1
            i += 1
        elif ch == ")":
            paren = max(0, paren - 1)
            i += 1
        elif angle == 0 and paren == 0:
            m = _IDENT_TOKEN_RE.match(s, i)
            if m:
                tok = m.group(0)
                if tok not in ("static", "async", "sync", "covariant", "external", "operator"):
                    last_ident = tok
                i = m.end()
            else:
                i += 1
        else:
            i += 1
    return None


def _outline_class_members(
    lines: list[str],
    body_start: int,
    body_end: int,
    class_name: str,
    out: list[str],
) -> int:
    """Extracts constructors, getters, and methods inside a class body and returns private method count."""
    idx = body_start
    priv_count = 0
    while idx < body_end:
        line = lines[idx]
        if not line.startswith("  ") or line.startswith("    "):
            idx += 1
            continue
        stripped = line.strip()
        if (
            not stripped
            or stripped.startswith("//")
            or stripped.startswith("@")
            or stripped.startswith("static const ")
            or stripped.startswith("static final ")
            or stripped.startswith("final ")
            or stripped.startswith("late ")
        ):
            idx += 1
            continue

        is_ctor = (
            stripped.startswith(f"const {class_name}")
            or stripped.startswith(f"{class_name}(")
            or stripped.startswith(f"{class_name}.")
            or stripped.startswith(f"factory {class_name}")
        )
        is_getter = " get " in stripped
        prefix_before_paren = stripped.split("(", 1)[0] if "(" in stripped else ""
        has_parens = (
            "(" in stripped
            and "=" not in prefix_before_paren
            and "Function(" not in stripped
        )

        if is_ctor or is_getter or has_parens:
            sig, _ = _collect_signature(lines, idx)
            end_idx = _find_matching_brace_line(lines, idx)
            out.append(f"    {idx + 1}-{end_idx + 1}: {sig}")
            if not is_ctor and not is_getter and "(" in sig:
                mname = _extract_method_identifier(sig)
                if mname and mname.startswith("_"):
                    priv_count += 1
            idx = max(idx + 1, end_idx + 1)
            continue

        idx += 1
    return priv_count


def _extract_test_call_title(lines: list[str], start_idx: int) -> str | None:
    """Extracts single- or multi-line string description from a group/test/testWidgets call."""
    parts: list[str] = []
    for idx in range(start_idx, min(len(lines), start_idx + 6)):
        line = lines[idx]
        if idx == start_idx and "(" in line:
            line = line.split("(", 1)[1]
        for m in _STRING_LITERAL_RE.finditer(line):
            parts.append(m.group(2))
        if parts and ("," in line or idx > start_idx):
            joined = "".join(parts)
            return f"'{joined}'"
    return None


def outline_dart_test(lines: list[str]) -> list[str]:
    """Builds a line-range outline of helper types and group/test/testWidgets blocks in a test file."""
    out: list[str] = []
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if not line.startswith(" "):
            tm = _DART_TYPE_RE.match(stripped)
            if tm:
                end_idx = _find_matching_brace_line(lines, idx)
                out.append(f"  {idx + 1}-{end_idx + 1}: {tm.group(2)} {tm.group(3)}")
                continue
        m = _TEST_CALL_START_RE.match(line)
        if m:
            kind = m.group(2)
            title = _extract_test_call_title(lines, idx) or "'...'"
            end_idx = _find_matching_brace_line(lines, idx, allow_inside_parens=True)
            indent = "  " if kind == "group" else "    "
            out.append(f"{indent}{idx + 1}-{end_idx + 1}: {kind}({title})")
    return out


def outline_file(root: Path, file_path: Path) -> str:
    """Generates an outline string with line ranges for a Markdown or Dart file."""
    rel = file_path.resolve().relative_to(root.resolve()).as_posix()
    text = file_path.read_text(encoding="utf-8")
    lines = text.splitlines()
    header = f"=== {rel} ({len(lines)} lines) ==="
    if file_path.suffix == ".md":
        entries = outline_markdown(lines)
    elif rel.startswith("test/"):
        entries = outline_dart_test(lines)
    else:
        entries = outline_dart_lib(lines)
    return "\n".join([header, *entries])


def outline_repo_overview(root: Path) -> str:
    """Prints a compact repository summary of all Dart files and line counts."""
    rows: list[str] = []
    for p in _iter_dart_files(root):
        rel = p.relative_to(root).as_posix()
        lines = p.read_text(encoding="utf-8").splitlines()
        if len(lines) > 900:
            flag = " [>900L]"
        elif len(lines) > 750:
            flag = " [>750L]"
        else:
            flag = ""
        if rel.startswith("test/"):
            test_entries = outline_dart_test(lines)
            test_count = sum(1 for e in test_entries if ": test(" in e or ": testWidgets(" in e)
            preview = test_entries[0].strip().split(": ", 1)[-1] if test_entries else "helpers"
            if len(preview) > 70:
                preview = preview[:67] + "..."
            rows.append(f"{rel} ({len(lines)}L{flag}, {test_count} tests): {preview}")
            continue
        symbols: list[str] = []
        for ln in lines:
            s = ln.strip()
            tm = _DART_TYPE_RE.match(s)
            if tm:
                symbols.append(tm.group(3))
            else:
                pm = _DART_PROVIDER_RE.match(s)
                if pm:
                    symbols.append(pm.group(1))
        sym_preview = ", ".join(symbols[:6])
        if len(symbols) > 6:
            sym_preview += f", +{len(symbols) - 6} more"
        rows.append(f"{rel} ({len(lines)}L{flag}): {sym_preview}")
    return "\n".join(rows)


def find_in_repo(root: Path, query: str, layer: str | None = None) -> list[str]:
    """Searches declarations, ARB keys, test blocks, and spec sections for query."""
    pattern = re.compile(re.escape(query), re.IGNORECASE)
    qual_class: str | None = None
    qual_member: re.Pattern[str] | None = None
    if "." in query and " " not in query:
        parts = query.split(".", 1)
        if parts[0] and parts[1]:
            qual_class = parts[0].lower()
            qual_member = re.compile(r"\b" + re.escape(parts[1]) + r"\b", re.IGNORECASE)

    results: list[str] = []

    md_targets: list[Path] = []
    spec_dir = root / "spec"
    if spec_dir.exists():
        md_targets.extend(sorted(spec_dir.glob("TDF_SPEC*.md")))
    md_targets.extend([root / "TDF_SPEC.md", root / "ARCHITECTURE.md"])
    for md in md_targets:
        if not md.exists():
            continue
        if layer and layer != "spec":
            continue
        rel = md.relative_to(root).as_posix()
        for entry in outline_markdown(md.read_text(encoding="utf-8").splitlines()):
            if pattern.search(entry):
                results.append(f"{rel}:{entry.strip()}")

    for arb_name in ("app_en.arb", "app_de.arb"):
        arb_path = root / "lib" / "l10n" / arb_name
        if not arb_path.exists():
            continue
        if layer and layer not in ("l10n", "ui"):
            continue
        rel = arb_path.relative_to(root).as_posix()
        for idx, line in enumerate(arb_path.read_text(encoding="utf-8").splitlines(), 1):
            if pattern.search(line) and not line.strip().startswith('"@'):
                results.append(f"{rel}:{idx}: {line.strip()}")

    for p in _iter_dart_files(root):
        rel = p.relative_to(root).as_posix()
        if layer and not rel.startswith(f"lib/{layer}") and not rel.startswith(f"test/{layer}"):
            continue
        lines = p.read_text(encoding="utf-8").splitlines()
        outlined = outline_dart_test(lines) if rel.startswith("test/") else outline_dart_lib(lines)
        matched_outline = False
        current_type = ""
        for item in outlined:
            stripped_item = item.strip()
            if not item.startswith("    "):
                parts = stripped_item.split()
                current_type = parts[2].lower() if len(parts) >= 3 else ""
            if pattern.search(item) or (
                qual_class is not None
                and qual_member is not None
                and current_type == qual_class
                and qual_member.search(stripped_item)
            ):
                results.append(f"{rel}:{stripped_item}")
                matched_outline = True
        if not matched_outline:
            for idx, line in enumerate(lines, 1):
                if pattern.search(line):
                    results.append(f"{rel}:{idx}: {line.strip()}")
                    if len(results) >= 80:
                        return results
    return results


def _resolve_dart_import(root: Path, source_file: Path, import_uri: str) -> str | None:
    """Resolves a relative or package:tiertask/ import to a repo-relative POSIX path."""
    if import_uri.startswith("dart:"):
        return None
    if import_uri.startswith("package:tiertask/"):
        rel = "lib/" + import_uri[len("package:tiertask/") :]
        candidate = root / rel
        return rel if candidate.exists() else None
    if import_uri.startswith("package:"):
        return None
    resolved = (source_file.parent / import_uri).resolve()
    try:
        rel_path = resolved.relative_to(root.resolve()).as_posix()
        return rel_path if resolved.exists() else None
    except ValueError:
        return None


def build_import_graph(root: Path) -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    """Builds forward (file -> imported files) and reverse (file -> importers) graphs."""
    forward: dict[str, set[str]] = {}
    reverse: dict[str, set[str]] = {}
    for p in _iter_dart_files(root, include_generated=True):
        rel = p.relative_to(root).as_posix()
        forward.setdefault(rel, set())
        reverse.setdefault(rel, set())
        for line in p.read_text(encoding="utf-8").splitlines():
            m = _DART_IMPORT_RE.match(line)
            if not m:
                continue
            target = _resolve_dart_import(root, p, m.group(1))
            if target:
                forward[rel].add(target)
                reverse.setdefault(target, set()).add(rel)
    return forward, reverse


def _extract_top_symbols(file_path: Path) -> list[str]:
    """Extracts public top-level type, provider, function names, and ValueKey tokens."""
    if not file_path.exists():
        return []
    text = file_path.read_text(encoding="utf-8")
    symbols: list[str] = []
    for line in text.splitlines():
        s = line.strip()
        tm = _DART_TYPE_RE.match(s)
        if tm and not tm.group(3).startswith("_"):
            symbols.append(tm.group(3))
            continue
        pm = _DART_PROVIDER_RE.match(s)
        if pm and not pm.group(1).startswith("_"):
            symbols.append(pm.group(1))
    for km in _VALUE_KEY_RE.finditer(text):
        symbols.append(f"'{km.group(1)}'")
    if file_path.name == "settings_screen.dart":
        symbols.append("openSettingsFromMenu")
    return symbols


_SUBSYSTEM_TEST_MAP: dict[str, list[str]] = {
    "lib/main.dart": ["test/ui/home_screen_test.dart"],
    "lib/l10n/tier_localization_extension.dart": ["test/ui/home_screen_test.dart"],
    "lib/models/task_board.dart": [
        "test/models/task_board_evaluation_test.dart",
        "test/models/task_board_lifecycle_test.dart",
        "test/models/task_board_v050_rules_test.dart",
    ],
    "lib/models/task_board_evaluator.dart": [
        "test/models/task_board_evaluation_test.dart",
        "test/models/task_board_lifecycle_test.dart",
        "test/models/task_board_v050_rules_test.dart",
    ],
    "lib/models/task_board_mutator.dart": [
        "test/models/task_board_mutation_test.dart",
        "test/models/task_board_lifecycle_test.dart",
    ],
    "lib/models/task_board_queue_mutator.dart": [
        "test/models/task_board_downgrade_test.dart",
        "test/models/task_board_mutation_test.dart",
    ],
    "lib/models/task_board_sync.dart": [
        "test/models/task_board_sync_test.dart",
        "test/models/tdf_v060_merge_conformance_test.dart",
    ],
    "lib/models/task_board_reconciler.dart": [
        "test/models/task_board_sync_test.dart",
        "test/models/tdf_v060_merge_conformance_test.dart",
    ],
    "lib/models/workspace_sync_state.dart": ["test/models/task_board_sync_test.dart"],
    "lib/models/tdf_payload_comparison.dart": [
        "test/models/task_board_v050_rules_test.dart",
        "test/models/task_board_sync_test.dart",
    ],
    "lib/models/tdf_sync_metadata.dart": [
        "test/models/task_board_v050_rules_test.dart",
        "test/models/task_board_sync_test.dart",
    ],
    "lib/models/task_item.dart": ["test/models/tdf_v050_primitives_test.dart"],
    "lib/models/task_tier.dart": ["test/models/tdf_v050_primitives_test.dart"],
    "lib/models/tdf_error.dart": ["test/models/tdf_v050_primitives_test.dart"],
    "lib/models/tdf_location.dart": ["test/models/tdf_location_test.dart"],
    "lib/models/tdf_metadata.dart": ["test/models/tdf_v050_primitives_test.dart"],
    "lib/models/tdf_timezone.dart": ["test/models/tdf_v050_primitives_test.dart"],
    "lib/models/webdav_config.dart": ["test/models/tdf_v050_primitives_test.dart"],
    "lib/services/tdf_service.dart": [
        "test/services/tdf_service_parser_test.dart",
        "test/services/tdf_service_bounds_test.dart",
        "test/services/tdf_v060_conformance_test.dart",
    ],
    "lib/services/tdf_scanner.dart": [
        "test/services/tdf_service_parser_test.dart",
        "test/services/tdf_service_bounds_test.dart",
    ],
    "lib/services/tdf_parser.dart": [
        "test/services/tdf_service_parser_test.dart",
        "test/services/tdf_service_bounds_test.dart",
        "test/services/tdf_v060_conformance_test.dart",
    ],
    "lib/services/tdf_directive_parser.dart": [
        "test/services/tdf_service_parser_test.dart",
        "test/services/tdf_service_bounds_test.dart",
        "test/services/tdf_v060_conformance_test.dart",
    ],
    "lib/services/tdf_serializer.dart": [
        "test/services/tdf_service_parser_test.dart",
        "test/services/tdf_service_bounds_test.dart",
        "test/services/tdf_v060_conformance_test.dart",
    ],
    "lib/services/tdf_importer.dart": [
        "test/services/tdf_migration_test.dart",
        "test/services/tdf_v060_conformance_test.dart",
    ],
    "lib/services/tdf_historical_parser.dart": [
        "test/services/tdf_migration_test.dart",
        "test/services/tdf_v060_conformance_test.dart",
    ],
    "lib/services/tdf_historical_serializer.dart": [
        "test/services/tdf_migration_test.dart",
        "test/services/tdf_v060_conformance_test.dart",
    ],
    "lib/services/tdf_id_migration.dart": [
        "test/services/tdf_migration_test.dart",
        "test/services/tdf_v060_conformance_test.dart",
    ],
    "lib/repositories/local_file_operations.dart": ["test/repositories/local_file_repository_test.dart"],
    "lib/providers/location_providers.dart": [
        "test/providers/workspace_providers_test.dart",
        "test/ui/location_ui_test.dart",
    ],
    "lib/ui/edit_locations_screen.dart": ["test/ui/edit_locations_screen_test.dart"],
    "lib/ui/widgets/home_top_bar.dart": ["test/ui/home_screen_test.dart"],
    "lib/ui/widgets/home_tier_pane.dart": ["test/ui/home_screen_test.dart"],
    "lib/ui/widgets/home_drawer.dart": ["test/ui/home_drawer_test.dart"],
    "lib/ui/widgets/settings_preference_cards.dart": ["test/ui/settings_screen_test.dart"],
    "lib/ui/widgets/settings_webdav_storage_section.dart": ["test/ui/settings_screen_test.dart"],
    "lib/ui/widgets/log_viewer_dialog.dart": ["test/ui/settings_screen_test.dart"],
    "lib/ui/widgets/settings_local_storage_section.dart": ["test/ui/local_directory_picker_test.dart"],
    "lib/ui/widgets/local_tdf_file_dialogs.dart": ["test/ui/local_directory_picker_test.dart"],
    "lib/ui/widgets/task_editor_sections.dart": ["test/ui/edit_task_screen_test.dart"],
    "lib/ui/widgets/task_editor_scheduling_card.dart": ["test/ui/edit_task_screen_test.dart"],
    "lib/ui/widgets/task_editor_subtasks_and_blockers.dart": ["test/ui/edit_task_screen_test.dart"],
    "lib/ui/widgets/task_editor_links_section.dart": ["test/ui/edit_task_screen_test.dart"],
    "lib/ui/widgets/condition_editor_controller.dart": ["test/ui/widgets/task_editor_conditions_test.dart"],
    "lib/ui/widgets/task_editor_conditions_section.dart": ["test/ui/widgets/task_editor_conditions_test.dart"],
    "lib/ui/widgets/workspace_row_card.dart": ["test/ui/widgets/workspace_dialog_test.dart"],
    "lib/ui/widgets/tier_task_subtasks_section.dart": ["test/ui/widgets/tier_task_subtasks_test.dart"],
}


def _find_mirror_tests(root: Path, lib_rel: str) -> set[str]:
    """Finds direct mirror or subsystem-mapped test files for a lib/ Dart file."""
    matched: set[str] = set()
    if not lib_rel.startswith("lib/") or not lib_rel.endswith(".dart"):
        return matched
    if lib_rel in _SUBSYSTEM_TEST_MAP:
        for cand_rel in _SUBSYSTEM_TEST_MAP[lib_rel]:
            if (root / cand_rel).exists():
                matched.add(cand_rel)
        if matched:
            return matched
    sub_rel = lib_rel[len("lib/") : -len(".dart")]
    exact = f"test/{sub_rel}_test.dart"
    if (root / exact).exists():
        matched.add(exact)
    stem = Path(sub_rel).name
    for suffix in ("_section", "_sections", "_dialog", "_dialogs", "_screen"):
        if stem.endswith(suffix) and len(stem) > len(suffix):
            short_stem = stem[: -len(suffix)]
            alt = f"test/{Path(sub_rel).parent.as_posix()}/{short_stem}_test.dart"
            if (root / alt).exists():
                matched.add(alt)
    if stem == "location_status_dialog" and (root / "test/ui/location_ui_test.dart").exists():
        matched.add("test/ui/location_ui_test.dart")
    layer_dir = root / "test" / Path(sub_rel).parts[0]
    if layer_dir.exists():
        for cand in layer_dir.rglob(f"{stem}_*_test.dart"):
            matched.add(cand.relative_to(root).as_posix())
    return matched


def compute_dependencies(root: Path, target_rel: str) -> dict[str, list[str]]:
    """Computes direct imports and transitive reverse lib/ and test/ dependents."""
    norm_target = Path(target_rel).as_posix()
    forward, reverse = build_import_graph(root)
    direct_imports = sorted(forward.get(norm_target, set()))

    app_hubs = {
        "lib/main.dart",
        "lib/ui/home_screen.dart",
        "lib/providers/config_providers.dart",
        "lib/providers/sync_providers.dart",
        "lib/providers/task_providers.dart",
        "lib/providers/workspace_providers.dart",
        "lib/services/app_logger.dart",
        "test/ui/test_helpers.dart",
    }
    is_pure_core = norm_target.startswith(("lib/models/", "lib/services/"))
    stop_at_hubs = norm_target not in app_hubs
    target_symbols = _extract_top_symbols(root / norm_target)

    visited_direct: set[str] = set()
    queue: deque[str] = deque([norm_target])
    while queue:
        curr = queue.popleft()
        for dep in reverse.get(curr, set()):
            if dep in visited_direct or dep == norm_target:
                continue
            if stop_at_hubs and dep in app_hubs:
                continue
            if is_pure_core and curr.startswith("lib/repositories/") and dep.startswith(("lib/ui/", "test/ui/")):
                continue
            visited_direct.add(dep)
            queue.append(dep)

    visited_all: set[str] = set()
    queue_all: deque[str] = deque([norm_target])
    while queue_all:
        curr = queue_all.popleft()
        for dep in reverse.get(curr, set()):
            if dep not in visited_all and dep != norm_target:
                visited_all.add(dep)
                queue_all.append(dep)

    reverse_lib = sorted(f for f in visited_all if f.startswith("lib/"))
    mirror_tests = _find_mirror_tests(root, norm_target)
    if mirror_tests:
        return {
            "target": [norm_target],
            "direct_imports": direct_imports,
            "reverse_lib": reverse_lib,
            "reverse_tests": sorted(mirror_tests),
        }

    impacted_tests: set[str] = set()
    for direct_lib in visited_direct:
        if not is_pure_core and direct_lib.startswith("lib/ui/"):
            impacted_tests.update(_find_mirror_tests(root, direct_lib))

    for f in sorted(visited_all):
        if not (f.startswith("test/") and f.endswith("_test.dart")):
            continue
        if f in visited_direct or not stop_at_hubs:
            impacted_tests.add(f)
            continue
        if is_pure_core and f.startswith("test/ui/"):
            continue
        if target_symbols:
            test_text = (root / f).read_text(encoding="utf-8")
            if any(sym in test_text for sym in target_symbols):
                impacted_tests.add(f)

    return {
        "target": [norm_target],
        "direct_imports": direct_imports,
        "reverse_lib": reverse_lib,
        "reverse_tests": sorted(impacted_tests),
    }


def query_l10n(root: Path, pattern: str) -> list[str]:
    """Searches ARB keys and English/German translations matching pattern."""
    regex = re.compile(re.escape(pattern), re.IGNORECASE)
    en_path = root / "lib" / "l10n" / "app_en.arb"
    de_path = root / "lib" / "l10n" / "app_de.arb"
    en_data: dict[str, Any] = json.loads(en_path.read_text(encoding="utf-8"))
    de_data: dict[str, Any] = json.loads(de_path.read_text(encoding="utf-8"))
    matches: list[str] = []
    for k, en_val in en_data.items():
        if k.startswith("@"):
            continue
        de_val = de_data.get(k, "")
        if regex.search(k) or regex.search(str(en_val)) or regex.search(str(de_val)):
            matches.append(f"{k}:\n  en: {en_val}\n  de: {de_val}")
    return matches


def update_l10n(
    root: Path,
    sets: list[tuple[str, str, str, str | None]],
    removes: list[str],
    run_codegen: bool = True,
) -> None:
    """Updates app_en.arb and app_de.arb with auto-generated placeholder metadata."""
    for key, en_val, de_val, _ in sets:
        en_ph = set(_PLACEHOLDER_RE.findall(en_val))
        de_ph = set(_PLACEHOLDER_RE.findall(de_val))
        if en_ph != de_ph:
            raise ValueError(
                f"Placeholder mismatch for '{key}': en={sorted(en_ph)} vs de={sorted(de_ph)}"
            )

    en_path = root / "lib" / "l10n" / "app_en.arb"
    de_path = root / "lib" / "l10n" / "app_de.arb"
    en_data: dict[str, Any] = json.loads(en_path.read_text(encoding="utf-8"))
    de_data: dict[str, Any] = json.loads(de_path.read_text(encoding="utf-8"))

    for key in removes:
        en_data.pop(key, None)
        en_data.pop(f"@{key}", None)
        de_data.pop(key, None)

    for key, en_val, de_val, desc in sets:
        existing_meta = en_data.get(f"@{key}", {})
        existing_desc = existing_meta.get("description") if isinstance(existing_meta, dict) else None
        final_desc = desc or existing_desc or f"Localized string for {key}"
        placeholders = _PLACEHOLDER_RE.findall(en_val)
        meta_obj: dict[str, Any] = {"description": final_desc}
        if placeholders:
            existing_ph = (
                existing_meta.get("placeholders", {})
                if isinstance(existing_meta, dict)
                else {}
            )
            ph_map: dict[str, Any] = {}
            for ph in dict.fromkeys(placeholders):
                ph_map[ph] = existing_ph.get(ph, {"type": "String"})
            meta_obj["placeholders"] = ph_map

        en_data[key] = en_val
        en_data[f"@{key}"] = meta_obj
        de_data[key] = de_val

    en_path.write_text(json.dumps(en_data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    de_path.write_text(json.dumps(de_data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    if run_codegen:
        subprocess.run(["flutter", "gen-l10n"], cwd=root, check=True)


def audit_l10n(root: Path) -> list[str]:
    """Verifies key and placeholder parity between app_en.arb and app_de.arb."""
    en_path = root / "lib" / "l10n" / "app_en.arb"
    de_path = root / "lib" / "l10n" / "app_de.arb"
    if not en_path.exists() or not de_path.exists():
        return ["L10N: Missing app_en.arb or app_de.arb"]
    en_data: dict[str, Any] = json.loads(en_path.read_text(encoding="utf-8"))
    de_data: dict[str, Any] = json.loads(de_path.read_text(encoding="utf-8"))

    en_keys = {k for k in en_data if not k.startswith("@")}
    de_keys = {k for k in de_data if not k.startswith("@")}
    issues: list[str] = []

    for k in sorted(en_keys - de_keys):
        issues.append(f"L10N: Key '{k}' present in app_en.arb but missing in app_de.arb")
    for k in sorted(de_keys - en_keys):
        issues.append(f"L10N: Key '{k}' present in app_de.arb but missing in app_en.arb")

    for k in sorted(en_keys & de_keys):
        en_ph = set(_PLACEHOLDER_RE.findall(str(en_data[k])))
        de_ph = set(_PLACEHOLDER_RE.findall(str(de_data[k])))
        if en_ph != de_ph:
            issues.append(f"L10N: Placeholder mismatch for '{k}': en={sorted(en_ph)} vs de={sorted(de_ph)}")
        if f"@{k}" not in en_data:
            issues.append(f"L10N: Missing '@{k}' metadata block in app_en.arb")
        elif isinstance(en_data[f"@{k}"], dict):
            meta_ph = set(en_data[f"@{k}"].get("placeholders", {}).keys())
            if en_ph != meta_ph:
                issues.append(
                    f"L10N: Metadata '@{k}.placeholders' {sorted(meta_ph)} does not match {sorted(en_ph)}"
                )
    return issues


def _render_dir_tree(base: Path, prefix: str = "") -> list[str]:
    """Recursively renders an ASCII tree for a directory."""
    entries = sorted(
        [p for p in base.iterdir() if not p.name.startswith(".")],
        key=lambda p: (p.is_dir(), p.name),
    )
    lines: list[str] = []
    for idx, entry in enumerate(entries):
        is_last = idx == len(entries) - 1
        connector = "└── " if is_last else "├── "
        child_prefix = prefix + ("    " if is_last else "│   ")
        if entry.is_dir():
            lines.append(f"{prefix}{connector}{entry.name}/")
            lines.extend(_render_dir_tree(entry, child_prefix))
        else:
            lines.append(f"{prefix}{connector}{entry.name}")
    return lines


def _render_spec_tree(base: Path, prefix: str = "") -> list[str]:
    """Renders top-level specification files and collapsed subdirectories in spec/."""
    entries = sorted(
        [p for p in base.iterdir() if not p.name.startswith(".")],
        key=lambda p: (p.is_dir(), p.name),
    )
    lines: list[str] = []
    for idx, entry in enumerate(entries):
        is_last = idx == len(entries) - 1
        connector = "└── " if is_last else "├── "
        if entry.is_dir():
            lines.append(f"{prefix}{connector}{entry.name}/")
        else:
            lines.append(f"{prefix}{connector}{entry.name}")
    return lines


def generate_architecture_tree(root: Path) -> str:
    """Generates the canonical ASCII directory layout block for ARCHITECTURE.md."""
    root_files = [
        "AGENTS.md",
        "ARCHITECTURE.md",
        "CHANGELOG.md",
        "LICENSE",
        "README.md",
        "TDF_SPEC.md",
        "analysis_options.yaml",
        "l10n.yaml",
        "pubspec.yaml",
    ]
    existing_root_files = [f for f in root_files if (root / f).exists()]
    collapsed_dirs = [d for d in ("android", "assets", "linux", "spec", "windows") if (root / d).exists()]
    expanded_dirs = [d for d in ("lib", "test") if (root / d).exists()]

    items: list[tuple[str, str]] = []
    for f in existing_root_files:
        items.append(("file", f))
    for d in collapsed_dirs:
        if d == "assets":
            items.append(("expanded_dir", d))
        elif d == "spec":
            items.append(("spec_dir", d))
        else:
            items.append(("collapsed_dir", d))
    for d in expanded_dirs:
        items.append(("expanded_dir", d))

    tree_lines = ["```text", "tiertask/"]
    for idx, (kind, name) in enumerate(items):
        is_last = idx == len(items) - 1
        connector = "└── " if is_last else "├── "
        child_prefix = "    " if is_last else "│   "
        if kind == "file":
            tree_lines.append(f"{connector}{name}")
        elif kind == "collapsed_dir":
            tree_lines.append(f"{connector}{name}/")
        elif kind == "spec_dir":
            tree_lines.append(f"{connector}{name}/")
            tree_lines.extend(_render_spec_tree(root / name, child_prefix))
        else:
            tree_lines.append(f"{connector}{name}/")
            tree_lines.extend(_render_dir_tree(root / name, child_prefix))
    tree_lines.append("```")
    return "\n".join(tree_lines)


def sync_architecture_tree(root: Path) -> bool:
    """Replaces the ## Directory Layout code block in ARCHITECTURE.md if changed."""
    arch_path = root / "ARCHITECTURE.md"
    if not arch_path.exists():
        return False
    content = arch_path.read_text(encoding="utf-8")
    new_tree = generate_architecture_tree(root)
    pattern = re.compile(r"(## Directory Layout\s*\n\s*)```text\n.*?\n```", re.DOTALL)
    updated = pattern.sub(lambda m: m.group(1) + new_tree, content, count=1)
    if updated != content:
        arch_path.write_text(updated, encoding="utf-8")
        return True
    return False


def _layer_section_for_path(rel_path: str) -> str:
    """Maps a repository-relative path to its section heading in ARCHITECTURE.md."""
    if "/" not in rel_path or rel_path.startswith("spec/"):
        return "## Root Files"
    if rel_path.startswith("lib/l10n/"):
        return "## Localization"
    if rel_path.startswith("lib/models/"):
        return "## Domain Models"
    if rel_path.startswith("lib/services/"):
        return "## Services"
    if rel_path.startswith("lib/repositories/"):
        return "## Repositories"
    if rel_path.startswith("lib/providers/"):
        return "## State Providers"
    return "## User Interface"


def set_architecture_row(root: Path, rel_path: str, description: str) -> None:
    """Inserts or updates a file row in the matching section table of ARCHITECTURE.md."""
    arch_path = root / "ARCHITECTURE.md"
    lines = arch_path.read_text(encoding="utf-8").splitlines()
    norm_path = Path(rel_path).as_posix()
    row_str = f"| `{norm_path}` | {description.strip()} |"
    prefix = f"| `{norm_path}` |"

    for idx, line in enumerate(lines):
        if line.strip().startswith(prefix):
            lines[idx] = row_str
            arch_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            return

    section_heading = _layer_section_for_path(norm_path)
    sec_idx = -1
    for idx, line in enumerate(lines):
        if line.strip() == section_heading:
            sec_idx = idx
            break
    if sec_idx == -1:
        raise ValueError(f"Section {section_heading} not found in ARCHITECTURE.md")

    insert_idx = sec_idx + 1
    while insert_idx < len(lines) and not lines[insert_idx].startswith("| :---"):
        insert_idx += 1
    if insert_idx < len(lines):
        insert_idx += 1
    while insert_idx < len(lines) and lines[insert_idx].startswith("| `"):
        existing_col = lines[insert_idx].split("|")[1].strip().strip("`")
        if existing_col > norm_path:
            break
        insert_idx += 1

    lines.insert(insert_idx, row_str)
    arch_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def audit_architecture(root: Path) -> list[str]:
    """Audits ARCHITECTURE.md tree and file tables for completeness and conciseness."""
    arch_path = root / "ARCHITECTURE.md"
    if not arch_path.exists():
        return ["ARCH: Missing ARCHITECTURE.md"]
    content = arch_path.read_text(encoding="utf-8")
    issues: list[str] = []

    expected_tree = generate_architecture_tree(root)
    if expected_tree not in content:
        issues.append("ARCH: Directory Layout ASCII tree is out of sync with disk (run `arch --sync-tree`)")

    table_files: dict[str, str] = {}
    for line in content.splitlines():
        if line.startswith("| `lib/") or line.startswith("| `AGENTS.md`"):
            parts = [p.strip() for p in line.split("|") if p.strip()]
            if len(parts) >= 2:
                fpath = parts[0].strip("`")
                desc = parts[1]
                table_files[fpath] = desc
                word_count = len(desc.split())
                if word_count > MAX_ARCH_ROW_WORDS:
                    issues.append(
                        f"ARCH: Table row for `{fpath}` has {word_count} words (max {MAX_ARCH_ROW_WORDS})"
                    )

    for p in _iter_dart_files(root):
        rel = p.relative_to(root).as_posix()
        if rel.startswith("lib/") and rel not in table_files:
            issues.append(f"ARCH: Missing layer table row for `{rel}` in ARCHITECTURE.md")

    for fpath in sorted(table_files):
        if fpath.startswith("lib/") and not (root / fpath).exists():
            issues.append(f"ARCH: Stale table row in ARCHITECTURE.md for non-existent file `{fpath}`")

    return issues


def scaffold_file(root: Path, rel_path: str, description: str | None = None) -> None:
    """Creates a new Dart file with the GPL-3.0 header and registers it in ARCHITECTURE.md."""
    norm_path = Path(rel_path).as_posix()
    target = root / norm_path
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        target.write_text(GPL_HEADER + "\n", encoding="utf-8")
    else:
        existing = target.read_text(encoding="utf-8")
        if not existing.startswith("// TierTask\n"):
            target.write_text(GPL_HEADER + "\n" + existing, encoding="utf-8")
    sync_architecture_tree(root)
    if norm_path.startswith("lib/"):
        stem_class = "".join(part.capitalize() for part in Path(norm_path).stem.split("_"))
        final_desc = description or f"Defines `{stem_class}` component."
        set_architecture_row(root, norm_path, final_desc)


def _check_markdown_rules(root: Path, fix: bool) -> list[str]:
    """Checks Markdown files for CRLF line endings, horizontal rules (---), and emojis."""
    issues: list[str] = []
    md_files: list[Path] = []
    for name in ("README.md", "ARCHITECTURE.md", "AGENTS.md", "CHANGELOG.md", "TDF_SPEC.md"):
        p = root / name
        if p.exists():
            md_files.append(p)
    spec_dir = root / "spec"
    if spec_dir.exists():
        md_files.extend(sorted(spec_dir.rglob("*.md")))
    agents_dir = root / ".agents"
    if agents_dir.exists():
        md_files.extend(sorted(agents_dir.rglob("*.md")))

    for p in md_files:
        rel = p.relative_to(root).as_posix()
        raw = p.read_bytes()
        is_tdf_spec = rel == "TDF_SPEC.md" or (rel.startswith("spec/TDF_SPEC") and rel.endswith(".md"))
        if not is_tdf_spec and b"\r\n" in raw:
            if fix:
                raw = raw.replace(b"\r\n", b"\n")
                p.write_bytes(raw)
            else:
                issues.append(f"P-LANG-RULES: CRLF line endings in `{rel}`")
        text = raw.decode("utf-8")
        lines = text.splitlines()
        in_fence = False
        in_frontmatter = False
        for idx, line in enumerate(lines, 1):
            stripped = line.strip()
            if idx == 1 and stripped == "---":
                in_frontmatter = True
                continue
            if in_frontmatter and stripped == "---":
                in_frontmatter = False
                continue
            if stripped.startswith("```") or stripped.startswith("~~~"):
                in_fence = not in_fence
                continue
            if not in_fence and not in_frontmatter and stripped == "---":
                issues.append(f"P-LANG-RULES: Forbidden Markdown horizontal rule `---` in `{rel}:{idx}`")
            if _EMOJI_RE.search(line):
                issues.append(f"P-LANG-RULES: Forbidden emoji character in `{rel}:{idx}`")
    return issues


def _lib_layer_rank(rel_path: str) -> int | None:
    """Returns the DAG architectural layer rank (0-7) for a non-generated lib/ Dart file."""
    if not rel_path.startswith("lib/") or _is_generated_dart(rel_path):
        return None
    if rel_path == "lib/services/app_logger.dart":
        return 0
    if rel_path.startswith("lib/models/"):
        return 1
    if rel_path.startswith("lib/l10n/"):
        return 2
    if rel_path.startswith("lib/services/"):
        return 3
    if rel_path.startswith("lib/repositories/"):
        return 4
    if rel_path.startswith("lib/providers/"):
        return 5
    if rel_path.startswith("lib/ui/"):
        return 6
    if rel_path == "lib/main.dart":
        return 7
    return None


def _check_acyclic_dag(root: Path) -> list[str]:
    """Enforces P-ACYCLIC-DAG via Tarjan SCC cycle detection and strict layer rank ordering."""
    forward, _ = build_import_graph(root)
    lib_nodes = sorted(
        rel for rel in forward if rel.startswith("lib/") and not _is_generated_dart(rel)
    )
    lib_set = set(lib_nodes)
    issues: list[str] = []

    index_counter = 0
    indices: dict[str, int] = {}
    lowlink: dict[str, int] = {}
    stack: list[str] = []
    on_stack: set[str] = set()
    sccs: list[list[str]] = []

    def strongconnect(node: str) -> None:
        nonlocal index_counter
        indices[node] = index_counter
        lowlink[node] = index_counter
        index_counter += 1
        stack.append(node)
        on_stack.add(node)

        for dst in sorted(forward.get(node, set())):
            if dst not in lib_set:
                continue
            if dst not in indices:
                strongconnect(dst)
                lowlink[node] = min(lowlink[node], lowlink[dst])
            elif dst in on_stack:
                lowlink[node] = min(lowlink[node], indices[dst])

        if lowlink[node] == indices[node]:
            scc: list[str] = []
            while True:
                w = stack.pop()
                on_stack.remove(w)
                scc.append(w)
                if w == node:
                    break
            sccs.append(scc)

    for node in lib_nodes:
        if node not in indices:
            strongconnect(node)

    for scc in sccs:
        if len(scc) > 1 or (len(scc) == 1 and scc[0] in forward.get(scc[0], set())):
            issues.append(
                f"P-ACYCLIC-DAG: Circular import cycle detected: {' <-> '.join(sorted(scc))}"
            )

    for src in lib_nodes:
        src_rank = _lib_layer_rank(src)
        if src_rank is None:
            continue
        for dst in sorted(forward.get(src, set())):
            if dst not in lib_set:
                continue
            dst_rank = _lib_layer_rank(dst)
            if dst_rank is not None and src_rank < dst_rank:
                issues.append(
                    f"P-ACYCLIC-DAG: Upward cross-layer import `{src} -> {dst}` (rank {src_rank} -> {dst_rank})"
                )

    return issues


def run_static_checks(root: Path, fix: bool = False) -> list[str]:
    """Runs fast static compliance checks for AGENTS.md rules, L10N, and ARCHITECTURE.md."""
    if fix:
        sync_architecture_tree(root)

    issues: list[str] = []
    issues.extend(_check_markdown_rules(root, fix=fix))

    for p in _iter_dart_files(root):
        rel = p.relative_to(root).as_posix()
        raw = p.read_bytes()
        if b"\r\n" in raw:
            if fix:
                raw = raw.replace(b"\r\n", b"\n")
                p.write_bytes(raw)
            else:
                issues.append(f"P-LICENSE-HEADER: CRLF line endings in `{rel}`")
        text = raw.decode("utf-8")
        if not text.startswith(GPL_HEADER):
            if fix:
                p.write_text(GPL_HEADER + "\n" + text.lstrip(), encoding="utf-8")
                text = p.read_text(encoding="utf-8")
            else:
                issues.append(f"P-LICENSE-HEADER: Missing verbatim GPL-3.0 header in `{rel}`")

        lines = text.splitlines()
        for idx, line in enumerate(lines, 1):
            if _IGNORE_COMMENT_RE.search(line):
                issues.append(f"P-NO-IGNORE: Forbidden analyzer ignore directive in `{rel}:{idx}`")
            if _DART_FORBIDDEN_DIRECTIVE_RE.match(line):
                issues.append(f"P-FILE-SIZE: Forbidden `export`/`part` directive in `{rel}:{idx}`")
            if rel.startswith(("lib/models/", "lib/services/", "lib/ui/")):
                m = _DART_IMPORT_RE.match(line)
                if m and m.group(1) == "dart:io":
                    issues.append(f"P-IO-ISOLATION: Forbidden `dart:io` import in `{rel}:{idx}`")
            if rel.startswith("lib/") and not rel.startswith("lib/repositories/"):
                if "HttpClient" in line and not line.strip().startswith("//"):
                    issues.append(f"P-WEBDAV-API: Forbidden `HttpClient` usage outside repositories in `{rel}:{idx}`")

    issues.extend(_check_acyclic_dag(root))
    issues.extend(audit_l10n(root))
    issues.extend(audit_architecture(root))
    return issues


def compute_code_digest(root: Path) -> str:
    """Computes a SHA-256 digest over all code, test, ARB, and build configuration files."""
    hasher = hashlib.sha256()
    candidates: list[Path] = []
    for name in ("pubspec.yaml", "l10n.yaml", "analysis_options.yaml"):
        p = root / name
        if p.exists():
            candidates.append(p)
    for sub in ("lib", "test", "linux", "windows", "android/app/src"):
        base = root / sub
        if base.exists():
            for p in sorted(base.rglob("*")):
                if p.is_file() and p.suffix in (".dart", ".arb", ".cc", ".cpp", ".h", ".kt", ".cmake", ".kts"):
                    candidates.append(p)
    for p in sorted(candidates):
        rel = p.relative_to(root).as_posix()
        hasher.update(rel.encode("utf-8"))
        hasher.update(b"\0")
        hasher.update(p.read_bytes())
        hasher.update(b"\0")
    return hasher.hexdigest()


def _changed_files_from_git(root: Path) -> list[str]:
    """Returns modified and untracked repository-relative file paths from git status."""
    res = subprocess.run(
        ["git", "status", "--porcelain", "-uall"],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    changed: list[str] = []
    for line in res.stdout.splitlines():
        if len(line) < 4:
            continue
        path_part = line[3:].strip()
        if " -> " in path_part:
            path_part = path_part.split(" -> ", 1)[1].strip()
        changed.append(path_part.strip('"'))
    return changed


def resolve_impacted_tests(root: Path, changed_files: list[str]) -> list[str]:
    """Maps changed lib/ and test/ files to all impacted test/**/*_test.dart suites."""
    impacted: set[str] = set()
    for rel in changed_files:
        norm_rel = Path(rel).as_posix()
        if norm_rel.startswith("test/") and norm_rel.endswith("_test.dart") and (root / norm_rel).exists():
            impacted.add(norm_rel)
        elif norm_rel.startswith("lib/") and norm_rel.endswith(".dart") and (root / norm_rel).exists():
            mirrors = _find_mirror_tests(root, norm_rel)
            if mirrors:
                impacted.update(mirrors)
            else:
                deps = compute_dependencies(root, norm_rel)
                impacted.update(deps["reverse_tests"])
        elif norm_rel.startswith("test/") and norm_rel.endswith(".dart") and (root / norm_rel).exists():
            deps = compute_dependencies(root, norm_rel)
            impacted.update(deps["reverse_tests"])
    return sorted(impacted)


def run_verify(
    root: Path,
    mode: str = "fast",
    fix: bool = False,
    force: bool = False,
    targets: list[str] | None = None,
) -> int:
    """Runs static checks, formatting, analyzer, and smart or cached test execution."""
    t0 = time.monotonic()
    issues = run_static_checks(root, fix=fix)
    if issues:
        for issue in issues:
            print(f"[FAIL] {issue}", file=sys.stderr)

    changed = targets if targets else _changed_files_from_git(root)
    arb_changed = any(f.startswith("lib/l10n/") and f.endswith(".arb") for f in changed)
    if fix and arb_changed:
        subprocess.run(["flutter", "gen-l10n"], cwd=root, check=True)

    dart_changed = [f for f in changed if f.endswith(".dart") and (root / f).exists()]
    if fix:
        if mode == "full":
            subprocess.run(["dart", "format", "lib", "test"], cwd=root, check=True)
        elif dart_changed:
            subprocess.run(["dart", "format", *dart_changed], cwd=root, check=True)

    digest = compute_code_digest(root)
    stamp_path = root / STAMP_REL_PATH
    cached_digest: str | None = None
    if stamp_path.exists():
        try:
            cached_data = json.loads(stamp_path.read_text(encoding="utf-8"))
            cached_digest = cached_data.get("code_digest")
        except (OSError, json.JSONDecodeError):
            cached_digest = None

    if not issues and not force and not targets and cached_digest == digest:
        dt = (time.monotonic() - t0) * 1000
        print(
            f"VERIFY OK ({dt:.0f}ms): Static, L10N, and ARCHITECTURE checks passed; "
            f"code/test tree matches verified stamp {digest[:12]}."
        )
        return 0

    code_relevant_changes = [
        f
        for f in changed
        if f.startswith(("lib/", "test/", "linux/", "windows/", "android/"))
        or f in ("pubspec.yaml", "l10n.yaml", "analysis_options.yaml")
    ]
    if not issues and not force and not code_relevant_changes and mode == "fast":
        dt = (time.monotonic() - t0) * 1000
        print(f"VERIFY OK ({dt:.0f}ms): Only documentation/agent files changed; static checks passed.")
        return 0

    if mode == "full":
        fmt_res = subprocess.run(
            ["dart", "format", "--output=none", "--set-exit-if-changed", "lib", "test"],
            cwd=root,
            check=False,
        )
        if fmt_res.returncode != 0:
            return fmt_res.returncode

    ana_res = subprocess.run(
        ["flutter", "analyze", "--no-pub", "--fatal-infos", "--fatal-warnings"],
        cwd=root,
        check=False,
    )
    if ana_res.returncode != 0:
        return ana_res.returncode

    if mode == "fast":
        target_tests = resolve_impacted_tests(root, changed)
        if not target_tests:
            if issues:
                return 1
            dt = time.monotonic() - t0
            print(f"VERIFY FAST OK ({dt:.2f}s): Analyzer and static checks passed (0 impacted test suites).")
            return 0
        test_cmd = [
            "flutter",
            "test",
            "--no-pub",
            "--no-test-assets",
            "-r",
            "failures-only",
            *target_tests,
        ]
        print(f"Running {len(target_tests)} impacted test suite(s): {', '.join(target_tests)}")
    else:
        test_cmd = [
            "flutter",
            "test",
            "--no-pub",
            "--no-test-assets",
            "-r",
            "failures-only",
        ]

    test_res = subprocess.run(test_cmd, cwd=root, check=False)
    if test_res.returncode != 0:
        return test_res.returncode
    if issues:
        return 1

    if mode == "full":
        stamp_path.parent.mkdir(parents=True, exist_ok=True)
        final_digest = compute_code_digest(root)
        stamp_path.write_text(
            json.dumps({"code_digest": final_digest, "timestamp": time.time()}, indent=2) + "\n",
            encoding="utf-8",
        )

    dt = time.monotonic() - t0
    print(f"VERIFY {mode.upper()} OK ({dt:.2f}s): All checks and tests passed.")
    return 0


_LOG_LEVEL_ORDER = {"DEBUG": 0, "INFO": 1, "WARN": 2, "ERROR": 3, "CRASH": 4}
_LOG_LINE_RE = re.compile(
    r"^(\S+)\s+\[(DEBUG|INFO\s?|WARN\s?|ERROR|CRASH)\]\s+\[([A-Z]+)\s*\]\s+(.*)$"
)


def _discover_latest_log_file(root: Path) -> Path | None:
    """Finds the most recently modified TierTask diagnostic log file."""
    candidates: list[Path] = []
    home = Path.home()
    search_dirs = [
        root,
        home / ".local" / "share" / "tiertask",
        home / ".config" / "tiertask",
    ]
    for directory in search_dirs:
        if not directory.exists():
            continue
        candidates.extend(directory.glob("tiertask_*.log"))
        legacy = directory / "tiertask.log"
        if legacy.exists():
            candidates.append(legacy)
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


def inspect_log_file(
    log_path: Path,
    min_level: str | None = None,
    tag_filter: str | None = None,
    event_filter: str | None = None,
    summary_only: bool = False,
) -> int:
    """Parses, filters, and summarizes a TierTask diagnostic log file."""
    if not log_path.exists():
        print(f"Log file not found: {log_path}", file=sys.stderr)
        return 1
    lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    min_rank = _LOG_LEVEL_ORDER.get((min_level or "DEBUG").upper(), 0)
    norm_tag = tag_filter.upper() if tag_filter else None
    meta_lines: list[str] = []
    level_counts = {k: 0 for k in _LOG_LEVEL_ORDER}
    tag_counts: dict[str, int] = {}
    matched_lines: list[str] = []

    for line in lines:
        if line.startswith("===") or line.startswith("@meta "):
            meta_lines.append(line)
            if not norm_tag and not event_filter and min_rank == 0:
                matched_lines.append(line)
            continue
        match = _LOG_LINE_RE.match(line)
        if not match:
            if not norm_tag and not event_filter:
                matched_lines.append(line)
            continue
        raw_level = match.group(2).strip()
        raw_tag = match.group(3).strip()
        payload = match.group(4)
        level_counts[raw_level] = level_counts.get(raw_level, 0) + 1
        tag_counts[raw_tag] = tag_counts.get(raw_tag, 0) + 1
        if _LOG_LEVEL_ORDER.get(raw_level, 0) < min_rank:
            continue
        if norm_tag and raw_tag != norm_tag:
            continue
        if event_filter and event_filter not in payload:
            continue
        matched_lines.append(line)

    if summary_only:
        print(f"Log file: {log_path}")
        for m in meta_lines:
            print(f"  {m}")
        print(
            "Level counts: "
            + ", ".join(f"{k}={v}" for k, v in level_counts.items())
        )
        print(
            "Tag counts: "
            + (", ".join(f"{k}={v}" for k, v in sorted(tag_counts.items())) or "none")
        )
        print(f"Matched lines: {len(matched_lines)}")
        return 0

    for line in matched_lines:
        print(line)
    return 0


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="TierTask developer and agent automation CLI.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_outline = sub.add_parser("outline", help="Print line-range and signature outline for files or repo.")
    p_outline.add_argument("targets", nargs="*", help="Files to outline (omit for repo overview).")

    p_find = sub.add_parser("find", help="Locate symbols, ARB keys, test blocks, and spec sections.")
    p_find.add_argument("queries", nargs="+", help="One or more substrings to search for.")
    p_find.add_argument("--layer", help="Optional layer filter (models, services, repositories, providers, ui, l10n, spec).")

    p_deps = sub.add_parser("deps", help="Show direct imports and transitive reverse lib/ and test/ dependents.")
    p_deps.add_argument("target", help="Repository-relative Dart file path (e.g., lib/ui/settings_screen.dart).")

    p_l10n = sub.add_parser("l10n", help="Query, add/update, remove, or audit ARB localization entries.")
    p_l10n.add_argument("--query", help="Search existing ARB keys and English/German strings.")
    p_l10n.add_argument(
        "--set",
        nargs=3,
        action="append",
        metavar=("KEY", "EN", "DE"),
        default=[],
        help="Set or update an ARB key in app_en.arb and app_de.arb.",
    )
    p_l10n.add_argument("--desc", help="Optional @key description for the --set entry.")
    p_l10n.add_argument("--remove", action="append", default=[], help="Remove an ARB key from both ARB files.")
    p_l10n.add_argument("--audit", action="store_true", help="Verify key and placeholder parity.")
    p_l10n.add_argument("--no-codegen", action="store_true", help="Skip running flutter gen-l10n.")

    p_arch = sub.add_parser("arch", help="Sync or audit ARCHITECTURE.md directory tree and layer tables.")
    p_arch.add_argument("--sync-tree", action="store_true", help="Regenerate ## Directory Layout ASCII tree.")
    p_arch.add_argument(
        "--set",
        nargs=2,
        action="append",
        metavar=("REL_PATH", "DESCRIPTION"),
        default=[],
        help="Insert or update a file row in ARCHITECTURE.md.",
    )
    p_arch.add_argument("--audit", action="store_true", help="Audit ARCHITECTURE.md against disk files.")

    p_scaffold = sub.add_parser("scaffold", help="Create a licensed Dart file and update ARCHITECTURE.md.")
    p_scaffold.add_argument("path", help="Repository-relative file path to create.")
    p_scaffold.add_argument("--desc", help="Concise ARCHITECTURE.md table description.")

    p_verify = sub.add_parser("verify", help="Run static checks, analyzer, and fast or full tests.")
    mode_grp = p_verify.add_mutually_exclusive_group()
    mode_grp.add_argument("--fast", action="store_true", help="Run only impacted test suites (default).")
    mode_grp.add_argument("--full", action="store_true", help="Run full test suite and update verification stamp.")
    p_verify.add_argument("--fix", action="store_true", help="Auto-fix formatting, CRLF, headers, and ARCH tree.")
    p_verify.add_argument("--force", action="store_true", help="Ignore cached verification stamp.")
    p_verify.add_argument(
        "targets",
        nargs="*",
        help="Optional explicit files to check/test (defaults to git status changes).",
    )

    p_log = sub.add_parser("log", help="Inspect, filter, and summarize TierTask diagnostic log files.")
    p_log.add_argument("path", nargs="?", help="Optional path to a .log file (defaults to latest local log).")
    p_log.add_argument("--level", choices=list(_LOG_LEVEL_ORDER), help="Minimum log severity level.")
    p_log.add_argument(
        "--tag",
        choices=["LIFECYCLE", "TDF", "DOMAIN", "SYNC", "STORAGE", "UI"],
        help="Subsystem tag filter.",
    )
    p_log.add_argument("--event", help="Event name or payload substring filter.")
    p_log.add_argument("--summary", action="store_true", help="Print session metadata and level/tag summary counts.")

    return parser


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    args = _build_parser().parse_args(argv)
    root = repo_root()

    if args.command == "outline":
        if not args.targets:
            print(outline_repo_overview(root))
            return 0
        for t in args.targets:
            p = (root / t).resolve()
            if not p.exists():
                print(f"File not found: {t}", file=sys.stderr)
                return 1
            print(outline_file(root, p))
        return 0

    if args.command == "find":
        seen: set[str] = set()
        matches: list[str] = []
        for query in args.queries:
            for m in find_in_repo(root, query, layer=args.layer):
                if m not in seen:
                    seen.add(m)
                    matches.append(m)
        for m in matches:
            print(m)
        return 0 if matches else 1

    if args.command == "deps":
        info = compute_dependencies(root, args.target)
        print(f"Target: {args.target}")
        print(f"Direct lib/ imports ({len(info['direct_imports'])}): {', '.join(info['direct_imports']) or 'none'}")
        print(f"Reverse lib/ dependents ({len(info['reverse_lib'])}): {', '.join(info['reverse_lib']) or 'none'}")
        print(f"Impacted test suites ({len(info['reverse_tests'])}): {', '.join(info['reverse_tests']) or 'none'}")
        return 0

    if args.command == "l10n":
        if args.query:
            for item in query_l10n(root, args.query):
                print(item)
        if args.set or args.remove:
            sets = [(k, en, de, args.desc) for k, en, de in args.set]
            update_l10n(root, sets=sets, removes=args.remove, run_codegen=not args.no_codegen)
            print(f"L10N updated ({len(sets)} set, {len(args.remove)} removed).")
        if args.audit or (not args.query and not args.set and not args.remove):
            issues = audit_l10n(root)
            if issues:
                for i in issues:
                    print(i, file=sys.stderr)
                return 1
            print("L10N audit OK: 100% key and placeholder parity.")
        return 0

    if args.command == "arch":
        if args.sync_tree:
            changed = sync_architecture_tree(root)
            print("ARCHITECTURE.md tree synced." if changed else "ARCHITECTURE.md tree already up to date.")
        for rel_path, desc in args.set:
            set_architecture_row(root, rel_path, desc)
            print(f"ARCHITECTURE.md row updated for {rel_path}.")
        if args.audit or (not args.sync_tree and not args.set):
            issues = audit_architecture(root)
            if issues:
                for i in issues:
                    print(i, file=sys.stderr)
                return 1
            print("ARCHITECTURE.md audit OK.")
        return 0

    if args.command == "scaffold":
        scaffold_file(root, args.path, description=args.desc)
        print(f"Scaffolded {args.path}.")
        return 0

    if args.command == "verify":
        mode = "full" if args.full else "fast"
        return run_verify(root, mode=mode, fix=args.fix, force=args.force, targets=args.targets)

    if args.command == "log":
        target_log = Path(args.path).resolve() if args.path else _discover_latest_log_file(root)
        if target_log is None:
            print("No diagnostic log file found.", file=sys.stderr)
            return 1
        return inspect_log_file(
            target_log,
            min_level=args.level,
            tag_filter=args.tag,
            event_filter=args.event,
            summary_only=args.summary,
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
