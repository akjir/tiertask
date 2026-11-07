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

"""Unit tests for the TierTask developer and agent CLI (.agents/scripts/tiertask_dev.py)."""

from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

import tiertask_dev


GPL_HEADER = """// TierTask
// Copyright (C) 2026  Stefan Stark
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program.  If not, see <https://www.gnu.org/licenses/>.
"""


class TestTierTaskDev(unittest.TestCase):
    """Tests for outline, find, deps, l10n, arch, scaffold, and verify subcommands."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self._build_minimal_repo(self.root)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _build_minimal_repo(self, root: Path) -> None:
        (root / "lib" / "l10n").mkdir(parents=True)
        (root / "lib" / "models").mkdir(parents=True)
        (root / "lib" / "ui").mkdir(parents=True)
        (root / "test" / "models").mkdir(parents=True)
        (root / "test" / "ui").mkdir(parents=True)
        (root / ".agents" / "skills").mkdir(parents=True)
        (root / ".dart_tool").mkdir(parents=True)

        (root / "pubspec.yaml").write_text("name: tiertask\nversion: 0.1.0+1\n", encoding="utf-8")
        (root / "l10n.yaml").write_text("arb-dir: lib/l10n\n", encoding="utf-8")
        (root / "analysis_options.yaml").write_text("include: package:flutter_lints/flutter.yaml\n", encoding="utf-8")
        (root / "README.md").write_text("# TierTask\n\n## Overview\n\nSummary text.\n", encoding="utf-8")
        (root / "AGENTS.md").write_text("# TierTask AI Agent Rules\n\n## 1. Core Principles\n", encoding="utf-8")
        (root / "CHANGELOG.md").write_text("# Changelog\n\n## [Unreleased]\n", encoding="utf-8")
        (root / "TDF_SPEC.md").write_text(
            "# TierTask Data Format\n\n## 1. Introduction\nText.\n\n### 1.1 Scope\nMore text.\n",
            encoding="utf-8",
        )

        en_arb = {
            "@@locale": "en",
            "appTitle": "TierTask",
            "@appTitle": {"description": "The title of the application"},
        }
        de_arb = {
            "@@locale": "de",
            "appTitle": "TierTask",
        }
        (root / "lib" / "l10n" / "app_en.arb").write_text(
            json.dumps(en_arb, indent=2) + "\n",
            encoding="utf-8",
        )
        (root / "lib" / "l10n" / "app_de.arb").write_text(
            json.dumps(de_arb, indent=2) + "\n",
            encoding="utf-8",
        )

        model_code = (
            GPL_HEADER
            + "\n/// Sample model.\nclass SampleModel {\n"
            + "  /// Creates a sample model.\n  const SampleModel(this.id);\n\n"
            + "  /// Identifier.\n  final String id;\n\n"
            + "  /// Computes label.\n  String formatLabel(int count, {bool uppercase = false}) {\n"
            + "    return uppercase ? id.toUpperCase() : id;\n  }\n}\n"
        )
        (root / "lib" / "models" / "sample_model.dart").write_text(model_code, encoding="utf-8")

        ui_code = (
            GPL_HEADER
            + "\nimport '../models/sample_model.dart';\n\n"
            + "/// Sample screen.\nclass SampleScreen {\n"
            + "  /// Creates a sample screen.\n  const SampleScreen(this.model);\n\n"
            + "  /// Model reference.\n  final SampleModel model;\n}\n"
        )
        (root / "lib" / "ui" / "sample_screen.dart").write_text(ui_code, encoding="utf-8")

        test_model_code = (
            GPL_HEADER
            + "\nimport 'package:flutter_test/flutter_test.dart';\n"
            + "import 'package:tiertask/models/sample_model.dart';\n\n"
            + "void main() {\n"
            + "  group('SampleModel group', () {\n"
            + "    test('formats label', () {\n"
            + "      const model = SampleModel('abc');\n"
            + "      expect(model.formatLabel(1), equals('abc'));\n"
            + "    });\n"
            + "  });\n"
            + "}\n"
        )
        (root / "test" / "models" / "sample_model_test.dart").write_text(test_model_code, encoding="utf-8")

        test_ui_code = (
            GPL_HEADER
            + "\nimport 'package:flutter_test/flutter_test.dart';\n"
            + "import 'package:tiertask/ui/sample_screen.dart';\n\n"
            + "void main() {\n"
            + "  testWidgets('renders sample screen', (tester) async {});\n"
            + "}\n"
        )
        (root / "test" / "ui" / "sample_screen_test.dart").write_text(test_ui_code, encoding="utf-8")

        arch_md = """# TierTask Architecture and File Structure

## Directory Layout

```text
tiertask/
├── lib/
│   ├── l10n/
│   │   ├── app_de.arb
│   │   └── app_en.arb
│   ├── models/
│   │   └── sample_model.dart
│   └── ui/
│       └── sample_screen.dart
└── test/
    ├── models/
    │   └── sample_model_test.dart
    └── ui/
        └── sample_screen_test.dart
```

## Localization

| File | Function |
| :--- | :--- |
| `lib/l10n/app_en.arb` | English localization bundle. |
| `lib/l10n/app_de.arb` | German localization bundle. |

## Domain Models

| File | Function |
| :--- | :--- |
| `lib/models/sample_model.dart` | Defines immutable `SampleModel` value object. |

## Services

| File | Function |
| :--- | :--- |

## Repositories

| File | Function |
| :--- | :--- |

## State Providers

| File | Function |
| :--- | :--- |

## User Interface

| File | Function |
| :--- | :--- |
| `lib/ui/sample_screen.dart` | Renders `SampleScreen` view. |
"""
        (root / "ARCHITECTURE.md").write_text(arch_md, encoding="utf-8")

    def test_outline_markdown_and_dart_signatures(self) -> None:
        md_out = tiertask_dev.outline_file(self.root, self.root / "TDF_SPEC.md")
        self.assertIn("1-7: # TierTask Data Format", md_out)
        self.assertIn("3-7: ## 1. Introduction", md_out)
        self.assertIn("6-7: ### 1.1 Scope", md_out)

        dart_out = tiertask_dev.outline_file(self.root, self.root / "lib" / "models" / "sample_model.dart")
        self.assertIn("class SampleModel", dart_out)
        self.assertIn("const SampleModel(this.id)", dart_out)
        self.assertIn("String formatLabel(int count, {bool uppercase = false})", dart_out)

        test_out = tiertask_dev.outline_file(self.root, self.root / "test" / "models" / "sample_model_test.dart")
        self.assertIn("group('SampleModel group'", test_out)
        self.assertIn("test('formats label'", test_out)

    def test_find_locates_symbols_arb_and_spec_sections(self) -> None:
        matches = tiertask_dev.find_in_repo(self.root, "formatLabel")
        self.assertTrue(any("lib/models/sample_model.dart" in m for m in matches))

        arb_matches = tiertask_dev.find_in_repo(self.root, "appTitle")
        self.assertTrue(any("lib/l10n/app_en.arb" in m for m in arb_matches))

        spec_matches = tiertask_dev.find_in_repo(self.root, "Scope")
        self.assertTrue(any("TDF_SPEC.md" in m for m in spec_matches))

    def test_deps_computes_transitive_reverse_dependencies(self) -> None:
        info = tiertask_dev.compute_dependencies(self.root, "lib/models/sample_model.dart")
        self.assertIn("lib/ui/sample_screen.dart", info["reverse_lib"])
        self.assertIn("test/models/sample_model_test.dart", info["reverse_tests"])
        self.assertIn("test/ui/sample_screen_test.dart", info["reverse_tests"])

    def test_l10n_set_creates_placeholders_and_maintains_parity(self) -> None:
        tiertask_dev.update_l10n(
            self.root,
            sets=[("greetUser", "Hello {userName} ({count})", "Hallo {userName} ({count})", "Greeting banner")],
            removes=[],
            run_codegen=False,
        )
        en_data = json.loads((self.root / "lib" / "l10n" / "app_en.arb").read_text(encoding="utf-8"))
        de_data = json.loads((self.root / "lib" / "l10n" / "app_de.arb").read_text(encoding="utf-8"))
        self.assertEqual(en_data["greetUser"], "Hello {userName} ({count})")
        self.assertEqual(de_data["greetUser"], "Hallo {userName} ({count})")
        self.assertIn("@greetUser", en_data)
        self.assertIn("userName", en_data["@greetUser"]["placeholders"])
        self.assertIn("count", en_data["@greetUser"]["placeholders"])
        self.assertEqual(tiertask_dev.audit_l10n(self.root), [])

    def test_arch_sync_set_and_audit(self) -> None:
        new_widget = self.root / "lib" / "ui" / "widgets" / "custom_pill.dart"
        new_widget.parent.mkdir(parents=True, exist_ok=True)
        new_widget.write_text(GPL_HEADER + "\n/// Widget.\nclass CustomPill {}\n", encoding="utf-8")

        errors_before = tiertask_dev.audit_architecture(self.root)
        self.assertTrue(len(errors_before) > 0)

        tiertask_dev.sync_architecture_tree(self.root)
        tiertask_dev.set_architecture_row(
            self.root,
            "lib/ui/widgets/custom_pill.dart",
            "Renders `CustomPill` card widget.",
        )
        errors_after = tiertask_dev.audit_architecture(self.root)
        self.assertEqual(errors_after, [])

    def test_scaffold_creates_licensed_file_and_updates_arch(self) -> None:
        tiertask_dev.scaffold_file(
            self.root,
            "lib/services/sample_service.dart",
            description="Stateless `SampleService` helper.",
        )
        created = self.root / "lib" / "services" / "sample_service.dart"
        self.assertTrue(created.exists())
        self.assertTrue(created.read_text(encoding="utf-8").startswith("// TierTask"))
        self.assertEqual(tiertask_dev.audit_architecture(self.root), [])

    def test_static_checks_detect_license_ignore_io_and_markdown_hr(self) -> None:
        bad_ui = self.root / "lib" / "ui" / "sample_screen.dart"
        bad_ui.write_text(
            "import 'dart:io';\n// ignore: avoid_print\nclass SampleScreen {}\n",
            encoding="utf-8",
        )
        (self.root / "README.md").write_text("# TierTask\n\n---\n\nBad horizontal rule.\n", encoding="utf-8")
        issues = tiertask_dev.run_static_checks(self.root, fix=False)
        joined = "\n".join(issues)
        self.assertIn("P-LICENSE-HEADER", joined)
        self.assertIn("P-NO-IGNORE", joined)
        self.assertIn("P-IO-ISOLATION", joined)
        self.assertIn("P-LANG-RULES", joined)

    def test_outline_multiline_testwidgets_and_arrow_methods(self) -> None:
        model_file = self.root / "lib" / "models" / "sample_model.dart"
        model_file.write_text(
            GPL_HEADER
            + "\n/// Sample model.\nclass SampleModel {\n"
            + "  /// Primary constructor.\n  const SampleModel(this.id);\n\n"
            + "  /// Named constructor.\n  SampleModel.trimmed(String raw) : id = raw.trim();\n\n"
            + "  /// Identifier.\n  final String id;\n\n"
            + "  @override\n  String toString() => 'SampleModel($id)';\n}\n",
            encoding="utf-8",
        )
        dart_out = tiertask_dev.outline_file(self.root, model_file)
        self.assertIn("String toString()", dart_out)
        self.assertNotIn("raw.trim()", dart_out)

        ui_test = self.root / "test" / "ui" / "sample_screen_test.dart"
        ui_test.write_text(
            GPL_HEADER
            + "\nimport 'package:flutter_test/flutter_test.dart';\n\n"
            + "void main() {\n"
            + "  testWidgets(\n"
            + "    'renders multi-line formatted widget test',\n"
            + "    (WidgetTester tester) async {\n"
            + "      expect(1, equals(1));\n"
            + "    },\n"
            + "  );\n"
            + "}\n",
            encoding="utf-8",
        )
        test_out = tiertask_dev.outline_file(self.root, ui_test)
        self.assertIn("testWidgets('renders multi-line formatted widget test')", test_out)

    def test_deps_resolves_mirror_ui_tests_and_test_helpers(self) -> None:
        (self.root / "lib" / "ui" / "widgets").mkdir(parents=True, exist_ok=True)
        (self.root / "test" / "ui" / "widgets").mkdir(parents=True, exist_ok=True)
        (self.root / "lib" / "main.dart").write_text(
            GPL_HEADER + "\nimport 'ui/widgets/pill.dart';\nclass App {}\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "ui" / "widgets" / "pill.dart").write_text(
            GPL_HEADER + "\nclass PillWidget {}\n",
            encoding="utf-8",
        )
        (self.root / "test" / "ui" / "test_helpers.dart").write_text(
            GPL_HEADER + "\nclass FakeRepo {}\n",
            encoding="utf-8",
        )
        (self.root / "test" / "ui" / "widgets" / "pill_test.dart").write_text(
            GPL_HEADER
            + "\nimport 'package:tiertask/main.dart';\n"
            + "import '../test_helpers.dart';\n"
            + "void main() {}\n",
            encoding="utf-8",
        )
        pill_deps = tiertask_dev.compute_dependencies(self.root, "lib/ui/widgets/pill.dart")
        self.assertIn("test/ui/widgets/pill_test.dart", pill_deps["reverse_tests"])

        helper_tests = tiertask_dev.resolve_impacted_tests(self.root, ["test/ui/test_helpers.dart"])
        self.assertIn("test/ui/widgets/pill_test.dart", helper_tests)

    def test_l10n_rejects_mismatched_placeholders(self) -> None:
        with self.assertRaises(ValueError):
            tiertask_dev.update_l10n(
                self.root,
                sets=[("badKey", "Items: {count}", "Elemente: {anzahl}", "Mismatch")],
                removes=[],
                run_codegen=False,
            )


if __name__ == "__main__":
    unittest.main()
