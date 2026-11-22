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
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
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
        (root / "lib" / "providers").mkdir(parents=True)
        (root / "lib" / "ui").mkdir(parents=True)
        (root / "test" / "models").mkdir(parents=True)
        (root / "test" / "ui").mkdir(parents=True)
        (root / "spec").mkdir(parents=True)
        (root / ".agents" / "skills").mkdir(parents=True)
        (root / ".dart_tool").mkdir(parents=True)

        (root / "pubspec.yaml").write_text("name: tiertask\nversion: 0.1.0+1\n", encoding="utf-8")
        (root / "l10n.yaml").write_text("arb-dir: lib/l10n\n", encoding="utf-8")
        (root / "analysis_options.yaml").write_text("include: package:flutter_lints/flutter.yaml\n", encoding="utf-8")
        (root / "README.md").write_text("# TierTask\n\n## Overview\n\nSummary text.\n", encoding="utf-8")
        (root / "AGENTS.md").write_text("# TierTask AI Agent Rules\n\n## 1. Core Principles\n", encoding="utf-8")
        (root / "CHANGELOG.md").write_text("# Changelog\n\n## [Unreleased]\n", encoding="utf-8")
        (root / "spec" / "TDF_SPEC_0.8.0.md").write_text(
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

        provider_code = (
            GPL_HEADER
            + "\nimport '../models/sample_model.dart';\n\n"
            + "/// Sample state holder.\nclass SampleState {\n"
            + "  /// Creates a sample state.\n  const SampleState(this.model);\n\n"
            + "  /// Model reference.\n  final SampleModel model;\n}\n"
        )
        (root / "lib" / "providers" / "sample_provider.dart").write_text(provider_code, encoding="utf-8")

        ui_code = (
            GPL_HEADER
            + "\nimport '../l10n/app_localizations.dart';\n"
            + "import '../models/sample_model.dart';\n"
            + "import '../providers/sample_provider.dart';\n\n"
            + "/// Sample screen.\nclass SampleScreen {\n"
            + "  /// Creates a sample screen.\n  const SampleScreen(this.state, this.model);\n\n"
            + "  /// State reference.\n  final SampleState state;\n\n"
            + "  /// Direct domain model reference.\n  final SampleModel model;\n\n"
            + "  /// Resolves localized title.\n  String title(AppLocalizations localizations) => localizations.appTitle;\n}\n"
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
├── AGENTS.md
├── ARCHITECTURE.md
├── CHANGELOG.md
├── README.md
├── analysis_options.yaml
├── l10n.yaml
├── pubspec.yaml
├── spec/
│   └── TDF_SPEC_0.8.0.md
├── lib/
│   ├── l10n/
│   │   ├── app_de.arb
│   │   └── app_en.arb
│   ├── models/
│   │   └── sample_model.dart
│   ├── providers/
│   │   └── sample_provider.dart
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
| `lib/providers/sample_provider.dart` | Holds `SampleState`. |

## Design System

| File | Function |
| :--- | :--- |

## User Interface

| File | Function |
| :--- | :--- |
| `lib/ui/sample_screen.dart` | Renders `SampleScreen` view. |
"""
        (root / "ARCHITECTURE.md").write_text(arch_md, encoding="utf-8")

    def _build_minimal_design_system(self, root: Path) -> None:
        for sub in (
            "lib/ui/tokens",
            "lib/ui/primitives",
            "lib/ui/layout",
            "lib/ui/components",
            "test/ui/tokens",
            "test/ui/primitives",
        ):
            (root / sub).mkdir(parents=True, exist_ok=True)

        (root / "lib" / "ui" / "tokens" / "ui_focus_tokens.dart").write_text(
            GPL_HEADER + "\n/// Focus tokens.\nclass UiFocusTokens {}\n",
            encoding="utf-8",
        )
        (root / "lib" / "ui" / "tokens" / "custom_token.dart").write_text(
            GPL_HEADER + "\n/// Custom token helper.\nclass CustomToken {}\n",
            encoding="utf-8",
        )
        (root / "lib" / "ui" / "tokens" / "ui_theme_tokens.dart").write_text(
            GPL_HEADER
            + "\nimport 'custom_token.dart';\n"
            + "import 'ui_focus_tokens.dart';\n\n"
            + "/// Theme tokens.\nclass UiThemeTokens {\n"
            + "  /// Creates theme tokens.\n  const UiThemeTokens(this.focus, this.custom);\n"
            + "  /// Focus tokens.\n  final UiFocusTokens focus;\n"
            + "  /// Custom token.\n  final CustomToken custom;\n}\n",
            encoding="utf-8",
        )
        (root / "lib" / "ui" / "primitives" / "ui_button.dart").write_text(
            GPL_HEADER
            + "\nimport '../tokens/ui_theme_tokens.dart';\n\n"
            + "/// Button primitive.\nclass UiButton {\n"
            + "  /// Creates a button.\n  const UiButton(this.tokens);\n"
            + "  /// Theme tokens.\n  final UiThemeTokens tokens;\n}\n",
            encoding="utf-8",
        )
        (root / "lib" / "ui" / "layout" / "ui_page_header.dart").write_text(
            GPL_HEADER
            + "\nimport '../primitives/ui_button.dart';\n"
            + "import '../tokens/ui_theme_tokens.dart';\n\n"
            + "/// Page header layout.\nclass UiPageHeader {\n"
            + "  /// Creates a page header.\n  const UiPageHeader(this.button, this.tokens);\n"
            + "  /// Action button.\n  final UiButton button;\n"
            + "  /// Theme tokens.\n  final UiThemeTokens tokens;\n}\n",
            encoding="utf-8",
        )
        (root / "lib" / "ui" / "components" / "ui_dialog_frame.dart").write_text(
            GPL_HEADER
            + "\nimport '../layout/ui_page_header.dart';\n"
            + "import '../primitives/ui_button.dart';\n"
            + "import '../tokens/ui_theme_tokens.dart';\n\n"
            + "/// Dialog frame composite.\nclass UiDialogFrame {\n"
            + "  /// Creates a dialog frame.\n  const UiDialogFrame(this.header, this.button, this.tokens);\n"
            + "  /// Header layout.\n  final UiPageHeader header;\n"
            + "  /// Primary button.\n  final UiButton button;\n"
            + "  /// Theme tokens.\n  final UiThemeTokens tokens;\n}\n",
            encoding="utf-8",
        )
        (root / "test" / "ui" / "tokens" / "ui_theme_tokens_test.dart").write_text(
            GPL_HEADER
            + "\nimport 'package:flutter_test/flutter_test.dart';\n"
            + "import 'package:tiertask/ui/tokens/custom_token.dart';\n"
            + "import 'package:tiertask/ui/tokens/ui_focus_tokens.dart';\n"
            + "import 'package:tiertask/ui/tokens/ui_theme_tokens.dart';\n\n"
            + "void main() {\n"
            + "  test('checks UiThemeTokens, UiFocusTokens, and CustomToken', () {\n"
            + "    const tokens = UiThemeTokens(UiFocusTokens(), CustomToken());\n"
            + "    expect(tokens.focus, isA<UiFocusTokens>());\n"
            + "  });\n"
            + "}\n",
            encoding="utf-8",
        )
        (root / "test" / "ui" / "primitives" / "ui_button_test.dart").write_text(
            GPL_HEADER
            + "\nimport 'package:flutter_test/flutter_test.dart';\n"
            + "import 'package:tiertask/ui/primitives/ui_button.dart';\n"
            + "import 'package:tiertask/ui/tokens/custom_token.dart';\n"
            + "import 'package:tiertask/ui/tokens/ui_focus_tokens.dart';\n"
            + "import 'package:tiertask/ui/tokens/ui_theme_tokens.dart';\n\n"
            + "void main() {\n"
            + "  testWidgets('renders UiButton', (tester) async {\n"
            + "    expect(const UiButton(UiThemeTokens(UiFocusTokens(), CustomToken())), isNotNull);\n"
            + "  });\n"
            + "}\n",
            encoding="utf-8",
        )

        for rel_path, desc in (
            ("lib/ui/tokens/custom_token.dart", "Custom token helper."),
            ("lib/ui/tokens/ui_focus_tokens.dart", "Focus tokens."),
            ("lib/ui/tokens/ui_theme_tokens.dart", "Theme tokens."),
            ("lib/ui/primitives/ui_button.dart", "Button primitive."),
            ("lib/ui/layout/ui_page_header.dart", "Page header layout."),
            ("lib/ui/components/ui_dialog_frame.dart", "Dialog frame composite."),
        ):
            tiertask_dev.set_architecture_row(root, rel_path, desc)
        tiertask_dev.sync_architecture_tree(root)

    def test_outline_markdown_and_dart_signatures(self) -> None:
        md_out = tiertask_dev.outline_file(self.root, self.root / "spec" / "TDF_SPEC_0.8.0.md")
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
        self.assertTrue(any("spec/TDF_SPEC_0.8.0.md" in m for m in spec_matches))

        ui_spec = self.root / "spec" / "UI_DESIGN_SYSTEM.md"
        ui_spec.write_text("# UI Design System\n\n## 2. Surface Hierarchy\n", encoding="utf-8")
        ui_spec_matches = tiertask_dev.find_in_repo(self.root, "Surface Hierarchy", layer="spec")
        self.assertTrue(any("spec/UI_DESIGN_SYSTEM.md" in m for m in ui_spec_matches))

        provider_matches = tiertask_dev.find_in_repo(self.root, "SampleState", layer="providers")
        self.assertTrue(any("lib/providers/sample_provider.dart" in m for m in provider_matches))

    def test_deps_computes_transitive_reverse_dependencies(self) -> None:
        info = tiertask_dev.compute_dependencies(self.root, "lib/models/sample_model.dart")
        self.assertIn("lib/ui/sample_screen.dart", info["reverse_lib"])
        self.assertIn("test/models/sample_model_test.dart", info["reverse_tests"])

        helper_model = self.root / "lib" / "models" / "unmirrored_helper.dart"
        helper_model.write_text(
            GPL_HEADER + "\nclass UnmirroredHelper {}\n",
            encoding="utf-8",
        )
        provider_file = self.root / "lib" / "providers" / "sample_provider.dart"
        provider_file.write_text(
            GPL_HEADER
            + "\nimport '../models/sample_model.dart';\n"
            + "import '../models/unmirrored_helper.dart';\n\n"
            + "class SampleState {\n"
            + "  const SampleState(this.model, this.helper);\n"
            + "  final SampleModel model;\n"
            + "  final UnmirroredHelper helper;\n"
            + "}\n",
            encoding="utf-8",
        )
        unmirrored_info = tiertask_dev.compute_dependencies(
            self.root,
            "lib/models/unmirrored_helper.dart",
        )
        self.assertIn("lib/ui/sample_screen.dart", unmirrored_info["reverse_lib"])
        self.assertIn("test/ui/sample_screen_test.dart", unmirrored_info["reverse_tests"])

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
        ui_file = self.root / "lib" / "ui" / "sample_screen.dart"
        ui_file.write_text(
            ui_file.read_text(encoding="utf-8") + "\nString greet(dynamic l10n) => l10n.greetUser('a', '1');\n",
            encoding="utf-8",
        )
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

        tiertask_dev.scaffold_file(
            self.root,
            "lib/ui/primitives/ui_pill.dart",
            description="Defines `UiPill` badge and chip primitive.",
        )
        pill_file = self.root / "lib" / "ui" / "primitives" / "ui_pill.dart"
        self.assertTrue(pill_file.exists())
        arch_text = (self.root / "ARCHITECTURE.md").read_text(encoding="utf-8")
        ds_section = arch_text.split("## Design System", 1)[1].split("## User Interface", 1)[0]
        self.assertIn("`lib/ui/primitives/ui_pill.dart`", ds_section)
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

    def test_eight_rank_dag_and_ui_repository_boundary(self) -> None:
        expected_ranks = [
            ("lib/services/app_logger.dart", 0),
            ("lib/models/sample_model.dart", 1),
            ("lib/l10n/tier_localization_extension.dart", 2),
            ("lib/services/tdf_service.dart", 3),
            ("lib/repositories/local_file_repository.dart", 4),
            ("lib/providers/task_providers.dart", 5),
            ("lib/ui/tier_task_shell_screen.dart", 6),
            ("lib/ui/tokens/ui_theme_tokens.dart", 6),
            ("lib/main.dart", 7),
        ]
        for rel_path, expected in expected_ranks:
            self.assertEqual(
                tiertask_dev._lib_layer_rank(rel_path),
                expected,
                f"Unexpected rank for {rel_path}",
            )
        self.assertIsNone(tiertask_dev._lib_layer_rank("lib/presentation/settings_controller.dart"))
        self.assertIsNone(tiertask_dev._lib_layer_rank("lib/ui_v2/tier_task_shell_screen.dart"))

        (self.root / "lib" / "services").mkdir(parents=True, exist_ok=True)
        (self.root / "lib" / "repositories").mkdir(parents=True, exist_ok=True)

        (self.root / "lib" / "services" / "app_logger.dart").write_text(
            GPL_HEADER + "\nclass AppLogger {}\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "services" / "tdf_service.dart").write_text(
            GPL_HEADER + "\nclass TdfService {}\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "repositories" / "local_repo.dart").write_text(
            GPL_HEADER + "\nimport 'dart:ffi';\nimport 'dart:io';\nclass LocalRepo {}\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "l10n" / "tier_localization_extension.dart").write_text(
            GPL_HEADER + "\nclass TierExt {}\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "main.dart").write_text(
            GPL_HEADER + "\nimport 'ui/sample_screen.dart';\nclass TierTaskApp {}\n",
            encoding="utf-8",
        )
        # Valid app UI file freely importing models, l10n, services, providers, and flutter_riverpod.
        (self.root / "lib" / "ui" / "good_ui.dart").write_text(
            GPL_HEADER
            + "\nimport 'package:flutter_riverpod/flutter_riverpod.dart';\n\n"
            + "import '../l10n/app_localizations.dart';\n"
            + "import '../l10n/tier_localization_extension.dart';\n"
            + "import '../models/sample_model.dart';\n"
            + "import '../providers/sample_provider.dart';\n"
            + "import '../services/app_logger.dart';\n"
            + "import '../services/tdf_service.dart';\n\n"
            + "class GoodUi {}\n",
            encoding="utf-8",
        )
        # Invalid UI file directly importing lib/repositories/ (existing and non-existent) and upward lib/main.dart.
        (self.root / "lib" / "ui" / "bad_ui.dart").write_text(
            GPL_HEADER
            + "\nimport '../main.dart';\n"
            + "import '../repositories/local_repo.dart';\n"
            + "import '../repositories/missing_repo.dart';\n\n"
            + "class BadUi {}\n",
            encoding="utf-8",
        )
        # Invalid upward provider -> ui import.
        (self.root / "lib" / "providers" / "bad_provider.dart").write_text(
            GPL_HEADER
            + "\nimport '../ui/sample_screen.dart';\n\n"
            + "class BadProvider {}\n",
            encoding="utf-8",
        )

        dag_issues = tiertask_dev._check_acyclic_dag(self.root)
        joined = "\n".join(dag_issues)
        self.assertNotIn("lib/ui/good_ui.dart", joined)
        self.assertIn("P-UDF-ARCHITECTURE", joined)
        self.assertIn("lib/ui/bad_ui.dart -> lib/repositories/local_repo.dart", joined)
        self.assertIn("lib/ui/bad_ui.dart -> lib/main.dart", joined)
        self.assertIn("(rank 6 -> 7)", joined)
        self.assertIn("lib/providers/bad_provider.dart -> lib/ui/sample_screen.dart", joined)
        self.assertIn("(rank 5 -> 6)", joined)

        static_joined = "\n".join(tiertask_dev.run_static_checks(self.root, fix=False))
        self.assertIn("lib/ui/bad_ui.dart -> lib/repositories/missing_repo.dart", static_joined)

    def test_design_system_layer_ranks_acyclic_dag_and_independence(self) -> None:
        expected_ds_ranks = [
            ("lib/ui/tokens/ui_color_tokens.dart", 0),
            ("lib/ui/primitives/ui_button.dart", 1),
            ("lib/ui/layout/ui_page_header.dart", 2),
            ("lib/ui/components/ui_dialog_frame.dart", 3),
            ("lib/ui/widgets/entity_note_section.dart", None),
            ("lib/ui/dialogs/workspaces_modal.dart", None),
            ("lib/ui/views/tasks_view.dart", None),
            ("lib/ui/tier_task_shell_screen.dart", None),
            ("lib/ui/ui_domain_mappers.dart", None),
            ("lib/models/sample_model.dart", None),
        ]
        for rel_path, expected in expected_ds_ranks:
            self.assertEqual(
                tiertask_dev._design_system_layer_rank(rel_path),
                expected,
                f"Unexpected design-system rank for {rel_path}",
            )

        self._build_minimal_design_system(self.root)
        self.assertEqual(tiertask_dev.run_static_checks(self.root, fix=False), [])

        # Upward design-system imports across all 3 rank boundaries: 0->1, 1->2, 2->3.
        (self.root / "lib" / "ui" / "tokens" / "ui_focus_tokens.dart").write_text(
            GPL_HEADER
            + "\nimport '../primitives/ui_button.dart';\n\n"
            + "class UiFocusTokens {}\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "ui" / "primitives" / "bad_prim.dart").write_text(
            GPL_HEADER
            + "\nimport '../layout/ui_page_header.dart';\n\n"
            + "class BadPrim {}\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "ui" / "layout" / "bad_layout.dart").write_text(
            GPL_HEADER
            + "\nimport '../components/ui_dialog_frame.dart';\n\n"
            + "class BadLayout {}\n",
            encoding="utf-8",
        )
        # Circular cycle inside layout.
        (self.root / "lib" / "ui" / "layout" / "a_layout.dart").write_text(
            GPL_HEADER + "\nimport 'b_layout.dart';\nclass ALayout {}\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "ui" / "layout" / "b_layout.dart").write_text(
            GPL_HEADER + "\nimport 'a_layout.dart';\nclass BLayout {}\n",
            encoding="utf-8",
        )

        # Create app UI and lower-layer targets to test P-DESIGN-SYSTEM-INDEPENDENCE.
        for sub in ("lib/ui/widgets", "lib/ui/dialogs", "lib/ui/views", "lib/services", "lib/repositories"):
            (self.root / sub).mkdir(parents=True, exist_ok=True)
        for target_rel in (
            "lib/ui/widgets/sample_widget.dart",
            "lib/ui/dialogs/sample_dialog.dart",
            "lib/ui/views/sample_view.dart",
            "lib/ui/tier_task_shell_screen.dart",
            "lib/ui/ui_domain_mappers.dart",
            "lib/l10n/app_localizations.dart",
            "lib/l10n/tier_localization_extension.dart",
            "lib/services/app_logger.dart",
            "lib/repositories/local_repo.dart",
            "lib/main.dart",
        ):
            (self.root / target_rel).write_text(GPL_HEADER + "\nclass Stub {}\n", encoding="utf-8")

        (self.root / "lib" / "ui" / "components" / "bad_independence.dart").write_text(
            GPL_HEADER
            + "\nimport 'dart:ffi';\n"
            + "import 'dart:io';\n"
            + "import 'package:flutter_riverpod/flutter_riverpod.dart';\n"
            + "import 'package:tiertask/models/missing_model.dart';\n\n"
            + "import '../dialogs/sample_dialog.dart';\n"
            + "import '../tier_task_shell_screen.dart';\n"
            + "import '../ui_domain_mappers.dart';\n"
            + "import '../views/sample_view.dart';\n"
            + "import '../widgets/sample_widget.dart';\n"
            + "import '../../l10n/app_localizations.dart';\n"
            + "import '../../l10n/tier_localization_extension.dart';\n"
            + "import '../../main.dart';\n"
            + "import '../../models/sample_model.dart';\n"
            + "import '../../providers/sample_provider.dart';\n"
            + "import '../../repositories/local_repo.dart';\n"
            + "import '../../services/app_logger.dart';\n\n"
            + "class BadIndependence {}\n",
            encoding="utf-8",
        )

        dag_issues = tiertask_dev._check_acyclic_dag(self.root)
        dag_joined = "\n".join(dag_issues)
        self.assertIn(
            "lib/ui/tokens/ui_focus_tokens.dart -> lib/ui/primitives/ui_button.dart",
            dag_joined,
        )
        self.assertIn("(rank 0 -> 1)", dag_joined)
        self.assertIn(
            "lib/ui/primitives/bad_prim.dart -> lib/ui/layout/ui_page_header.dart",
            dag_joined,
        )
        self.assertIn("(rank 1 -> 2)", dag_joined)
        self.assertIn(
            "lib/ui/layout/bad_layout.dart -> lib/ui/components/ui_dialog_frame.dart",
            dag_joined,
        )
        self.assertIn("(rank 2 -> 3)", dag_joined)
        cycle_lines = [i for i in dag_issues if "a_layout.dart" in i and "b_layout.dart" in i]
        self.assertEqual(len(cycle_lines), 1)

        static_issues = tiertask_dev.run_static_checks(self.root, fix=False)
        joined = "\n".join(static_issues)
        for forbidden_target in (
            "lib/ui/widgets/sample_widget.dart",
            "lib/ui/dialogs/sample_dialog.dart",
            "lib/ui/views/sample_view.dart",
            "lib/ui/tier_task_shell_screen.dart",
            "lib/ui/ui_domain_mappers.dart",
            "lib/models/sample_model.dart",
            "lib/models/missing_model.dart",
            "lib/l10n/app_localizations.dart",
            "lib/l10n/tier_localization_extension.dart",
            "lib/services/app_logger.dart",
            "lib/repositories/local_repo.dart",
            "lib/providers/sample_provider.dart",
            "lib/main.dart",
        ):
            self.assertIn(
                f"P-DESIGN-SYSTEM-INDEPENDENCE: Forbidden non-design-system import "
                f"`lib/ui/components/bad_independence.dart -> {forbidden_target}`",
                joined,
            )
        self.assertIn(
            "P-DESIGN-SYSTEM-INDEPENDENCE: Forbidden `package:flutter_riverpod/flutter_riverpod.dart` import",
            joined,
        )
        self.assertIn("P-DESIGN-SYSTEM-INDEPENDENCE: Forbidden `dart:io` import", joined)
        self.assertIn("P-DESIGN-SYSTEM-INDEPENDENCE: Forbidden `dart:ffi` import", joined)
        self.assertIn("P-IO-ISOLATION: Forbidden `dart:io` import", joined)
        self.assertIn("P-IO-ISOLATION: Forbidden `dart:ffi` import", joined)

    def test_static_checks_enforce_io_isolation_export_part_ban_and_retired_dirs(self) -> None:
        for obsolete_name in (
            "UI_PACKAGE_REL",
            "UI_EXAMPLE_REL",
            "UI_BARREL_REL",
            "_PUBSPEC_FORBIDDEN_DEP_RE",
            "_check_ui_package_pubspecs",
            "_ui_pkg_layer_rank",
            "partition_tests_by_package",
            "_is_allowed_ui_import",
            "_FORBIDDEN_UI_PROVIDERS",
            "_FORBIDDEN_UI_PROVIDER_RE",
            "_UI_FORBIDDEN_PROVIDER_DECL_RE",
        ):
            self.assertFalse(
                hasattr(tiertask_dev, obsolete_name),
                f"Obsolete symbol {obsolete_name} must be removed",
            )

        (self.root / "lib" / "repositories").mkdir(parents=True, exist_ok=True)
        (self.root / "lib" / "services").mkdir(parents=True, exist_ok=True)

        (self.root / "lib" / "providers" / "bad_prov.dart").write_text(
            GPL_HEADER
            + "\nimport 'dart:io';\nimport 'dart:ffi';\n"
            + "void bad() { HttpClient(); }\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "repositories" / "good_repo.dart").write_text(
            GPL_HEADER
            + "\nimport 'dart:io';\nimport 'dart:ffi';\n"
            + "class GoodRepo { void open() { HttpClient(); } }\n",
            encoding="utf-8",
        )
        # Unconditional export, part, and part of bans across lib/ and test/.
        (self.root / "lib" / "services" / "bad_directives.dart").write_text(
            GPL_HEADER
            + "\nexport '../models/sample_model.dart';\n"
            + "part 'other.dart';\n"
            + "part of 'parent.dart';\n",
            encoding="utf-8",
        )
        (self.root / "test" / "ui" / "bad_test_export.dart").write_text(
            GPL_HEADER + "\nexport 'sample_screen_test.dart';\n",
            encoding="utf-8",
        )

        retired_dirs = (
            "packages/tiertask_ui",
            "lib/presentation",
            "test/presentation",
            "lib/ui_v2",
            "test/ui_v2",
        )
        for retired in retired_dirs:
            (self.root / retired).mkdir(parents=True, exist_ok=True)

        issues = tiertask_dev.run_static_checks(self.root, fix=False)
        joined = "\n".join(issues)
        io_issues = [i for i in issues if i.startswith("P-IO-ISOLATION:")]
        webdav_issues = [i for i in issues if i.startswith("P-WEBDAV-API:")]

        self.assertIn("P-IO-ISOLATION: Forbidden `dart:io` import in `lib/providers/bad_prov.dart", joined)
        self.assertIn("P-IO-ISOLATION: Forbidden `dart:ffi` import in `lib/providers/bad_prov.dart", joined)
        self.assertIn("P-WEBDAV-API: Forbidden `HttpClient` usage outside repositories in `lib/providers/bad_prov.dart", joined)
        self.assertFalse(any("lib/repositories/good_repo.dart" in i for i in io_issues))
        self.assertFalse(any("lib/repositories/good_repo.dart" in i for i in webdav_issues))

        self.assertIn("P-FILE-SIZE: Forbidden `export`/`part` directive in `lib/services/bad_directives.dart:16`", joined)
        self.assertIn("P-FILE-SIZE: Forbidden `export`/`part` directive in `lib/services/bad_directives.dart:17`", joined)
        self.assertIn("P-FILE-SIZE: Forbidden `export`/`part` directive in `lib/services/bad_directives.dart:18`", joined)
        self.assertIn("P-FILE-SIZE: Forbidden `export`/`part` directive in `test/ui/bad_test_export.dart:16`", joined)

        for retired in retired_dirs:
            self.assertIn(f"P-UDF-ARCHITECTURE: Forbidden retired directory '{retired}/'", joined)

    def test_single_package_arch_sections_deps_impacted_tests_and_digest(self) -> None:
        self._build_minimal_design_system(self.root)

        expected_sections = [
            ("lib/ui/tokens/ui_theme_tokens.dart", "## Design System"),
            ("lib/ui/primitives/ui_button.dart", "## Design System"),
            ("lib/ui/layout/ui_page_header.dart", "## Design System"),
            ("lib/ui/components/ui_dialog_frame.dart", "## Design System"),
            ("lib/ui/views/tasks_view.dart", "## User Interface"),
            ("lib/ui/widgets/entity_note_section.dart", "## User Interface"),
            ("lib/ui/dialogs/workspaces_modal.dart", "## User Interface"),
            ("lib/ui/tier_task_shell_screen.dart", "## User Interface"),
            ("lib/ui/ui_domain_mappers.dart", "## User Interface"),
            ("lib/main.dart", "## User Interface"),
            ("lib/providers/ui_telemetry.dart", "## State Providers"),
        ]
        for rel_path, expected_section in expected_sections:
            self.assertEqual(
                tiertask_dev._layer_section_for_path(rel_path),
                expected_section,
                f"Unexpected ARCHITECTURE section for {rel_path}",
            )

        self.assertEqual(tiertask_dev._dart_roots(self.root), ["lib", "test"])
        self.assertTrue(tiertask_dev._is_test_dart("test/ui/primitives/ui_button_test.dart"))
        self.assertFalse(tiertask_dev._is_test_dart("packages/tiertask_ui/test/primitives/ui_button_test.dart"))
        self.assertFalse(tiertask_dev._is_code_relevant_change("packages/tiertask_ui/lib/src/primitives/ui_button.dart"))
        self.assertTrue(tiertask_dev._is_code_relevant_change("lib/ui/primitives/ui_button.dart"))
        self.assertTrue(tiertask_dev._is_code_relevant_change("pubspec.yaml"))

        # Tree stays root-package only (never expands packages/).
        tree = tiertask_dev.generate_architecture_tree(self.root)
        self.assertNotIn("packages/", tree)
        self.assertIn("tokens/", tree)
        self.assertIn("primitives/", tree)

        # Digest tracks root config and Dart files.
        digest_before = tiertask_dev.compute_code_digest(self.root)
        (self.root / "pubspec.yaml").write_text("name: tiertask\nversion: 0.2.0+2\n", encoding="utf-8")
        digest_after = tiertask_dev.compute_code_digest(self.root)
        self.assertNotEqual(digest_before, digest_after)

        # Direct mirror resolution for design-system primitive.
        button_tests = tiertask_dev.resolve_impacted_tests(
            self.root,
            ["lib/ui/primitives/ui_button.dart"],
        )
        self.assertEqual(button_tests, ["test/ui/primitives/ui_button_test.dart"])

        # Subsystem-mapped token leaf resolves to ui_theme_tokens_test.dart.
        focus_tests = tiertask_dev.resolve_impacted_tests(
            self.root,
            ["lib/ui/tokens/ui_focus_tokens.dart"],
        )
        self.assertEqual(focus_tests, ["test/ui/tokens/ui_theme_tokens_test.dart"])

        # Unmirrored token helper resolves through dependency graph.
        custom_tests = tiertask_dev.resolve_impacted_tests(
            self.root,
            ["lib/ui/tokens/custom_token.dart"],
        )
        self.assertIn("test/ui/tokens/ui_theme_tokens_test.dart", custom_tests)

        # Direct mirror for ui_domain_mappers.dart.
        (self.root / "lib" / "ui" / "ui_domain_mappers.dart").write_text(
            GPL_HEADER + "\nclass UiDomainMappers {}\n",
            encoding="utf-8",
        )
        (self.root / "test" / "ui" / "ui_domain_mappers_test.dart").write_text(
            GPL_HEADER + "\nimport 'package:tiertask/ui/ui_domain_mappers.dart';\nvoid main() {}\n",
            encoding="utf-8",
        )
        mapper_tests = tiertask_dev.resolve_impacted_tests(
            self.root,
            ["lib/ui/ui_domain_mappers.dart"],
        )
        self.assertEqual(mapper_tests, ["test/ui/ui_domain_mappers_test.dart"])

        # Find with layer="ui" locates integrated design-system symbols.
        ui_matches = tiertask_dev.find_in_repo(self.root, "UiButton", layer="ui")
        self.assertTrue(any("lib/ui/primitives/ui_button.dart" in m for m in ui_matches))
        self.assertEqual(tiertask_dev.find_in_repo(self.root, "UiButton", layer="models"), [])

        # CLI help reflects single-package layers only.
        parser = tiertask_dev._build_parser()
        find_parser = parser._subparsers._group_actions[0].choices["find"]
        find_help = " ".join(find_parser.format_help().split())
        self.assertIn("models, services, repositories, providers, ui, l10n, spec", find_help)
        self.assertNotIn("ui_pkg", find_help)
        self.assertNotIn("presentation", find_help)

    def test_audit_l10n_detects_orphan_metadata_and_comment_or_collision_unused_keys(self) -> None:
        en_arb = {
            "@@locale": "en",
            "appTitle": "TierTask",
            "@appTitle": {"description": "App title"},
            "extOnlyKey": "Ext",
            "@extOnlyKey": {"description": "Used bare in l10n extension"},
            "urlLineKey": "URL",
            "@urlLineKey": {"description": "Used after URL string on same line"},
            "commentOnlyKey": "Commented",
            "@commentOnlyKey": {"description": "Only appears in comment"},
            "activeFilterLabel": "Legacy",
            "@activeFilterLabel": {"description": "Collides with bare named param"},
            "@orphanMeta": {"description": "Orphan metadata block"},
        }
        de_arb = {
            "@@locale": "de",
            "appTitle": "TierTask",
            "extOnlyKey": "Ext DE",
            "urlLineKey": "URL DE",
            "commentOnlyKey": "Kommentar",
            "activeFilterLabel": "Alt",
        }
        (self.root / "lib" / "l10n" / "app_en.arb").write_text(json.dumps(en_arb, indent=2) + "\n", encoding="utf-8")
        (self.root / "lib" / "l10n" / "app_de.arb").write_text(json.dumps(de_arb, indent=2) + "\n", encoding="utf-8")
        (self.root / "lib" / "l10n" / "app_localizations.dart").write_text(
            "String get commentOnlyKey; String get activeFilterLabel;\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "l10n" / "tier_localization_extension.dart").write_text(
            GPL_HEADER + "\nextension Ext on Object { String f() => extOnlyKey; }\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "ui" / "sample_screen.dart").write_text(
            GPL_HEADER
            + "\nString render(dynamic localizations, {String? activeFilterLabel}) {\n"
            + "  // localizations.commentOnlyKey\n"
            + "  final url = 'https://example.com/${localizations.urlLineKey}';\n"
            + "  return '$url ${localizations.appTitle} $activeFilterLabel';\n"
            + "}\n",
            encoding="utf-8",
        )

        issues = tiertask_dev.audit_l10n(self.root)
        joined = "\n".join(issues)
        self.assertIn("L10N: Orphan metadata '@orphanMeta' in app_en.arb", joined)
        self.assertIn("L10N: Unused ARB key 'commentOnlyKey' in app_en.arb (P-NO-DEAD-CODE)", joined)
        self.assertIn("L10N: Unused ARB key 'activeFilterLabel' in app_en.arb (P-NO-DEAD-CODE)", joined)
        self.assertNotIn("'appTitle'", joined)
        self.assertNotIn("'extOnlyKey'", joined)
        self.assertNotIn("'urlLineKey'", joined)


if __name__ == "__main__":
    unittest.main()
