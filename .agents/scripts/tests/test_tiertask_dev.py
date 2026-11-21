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
        (root / "spec" / "TDF_SPEC_0.6.0.md").write_text(
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

## Presentation

| File | Function |
| :--- | :--- |

## User Interface

| File | Function |
| :--- | :--- |
| `lib/ui/sample_screen.dart` | Renders `SampleScreen` view. |
"""
        (root / "ARCHITECTURE.md").write_text(arch_md, encoding="utf-8")

    def test_outline_markdown_and_dart_signatures(self) -> None:
        md_out = tiertask_dev.outline_file(self.root, self.root / "spec" / "TDF_SPEC_0.6.0.md")
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
        self.assertTrue(any("spec/TDF_SPEC_0.6.0.md" in m for m in spec_matches))

        ui_spec = self.root / "spec" / "UI_DESIGN_SYSTEM.md"
        ui_spec.write_text("# UI Design System\n\n## 2. Surface Hierarchy\n", encoding="utf-8")
        ui_spec_matches = tiertask_dev.find_in_repo(self.root, "Surface Hierarchy", layer="spec")
        self.assertTrue(any("spec/UI_DESIGN_SYSTEM.md" in m for m in ui_spec_matches))

    def test_deps_computes_transitive_reverse_dependencies(self) -> None:
        info = tiertask_dev.compute_dependencies(self.root, "lib/models/sample_model.dart")
        self.assertIn("lib/ui/sample_screen.dart", info["reverse_lib"])
        self.assertIn("test/models/sample_model_test.dart", info["reverse_tests"])

        helper_model = self.root / "lib" / "models" / "unmirrored_helper.dart"
        helper_model.write_text(
            GPL_HEADER + "\nclass UnmirroredHelper {}\n",
            encoding="utf-8",
        )
        ui_screen = self.root / "lib" / "ui" / "sample_screen.dart"
        ui_screen.write_text(
            GPL_HEADER
            + "\nimport '../models/sample_model.dart';\n"
            + "import '../models/unmirrored_helper.dart';\n\n"
            + "class SampleScreen {\n"
            + "  const SampleScreen(this.model, this.helper);\n"
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

    def test_layer_ranks_and_presentation_dag_boundaries(self) -> None:
        expected_ranks = [
            ("lib/services/app_logger.dart", 0),
            ("lib/models/sample_model.dart", 1),
            ("lib/l10n/tier_localization_extension.dart", 2),
            ("lib/services/tdf_service.dart", 3),
            ("lib/repositories/local_file_repository.dart", 4),
            ("lib/providers/task_providers.dart", 5),
            ("lib/presentation/settings_controller.dart", 6),
            ("lib/ui/home_screen.dart", 7),
            ("lib/main.dart", 8),
        ]
        for rel_path, expected in expected_ranks:
            self.assertEqual(
                tiertask_dev._lib_layer_rank(rel_path),
                expected,
                f"Unexpected rank for {rel_path}",
            )

        (self.root / "lib" / "services").mkdir(parents=True, exist_ok=True)
        (self.root / "lib" / "repositories").mkdir(parents=True, exist_ok=True)
        (self.root / "lib" / "providers").mkdir(parents=True, exist_ok=True)
        (self.root / "lib" / "presentation").mkdir(parents=True, exist_ok=True)

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
        (self.root / "lib" / "presentation" / "sample_controller.dart").write_text(
            GPL_HEADER + "\nimport '../ui/sample_screen.dart';\nclass SampleController {}\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "providers" / "sample_provider.dart").write_text(
            GPL_HEADER
            + "\nimport '../presentation/sample_controller.dart';\n"
            + "class SampleProvider {}\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "ui" / "bad_ui.dart").write_text(
            GPL_HEADER
            + "\nimport '../repositories/local_repo.dart';\n"
            + "import '../services/app_logger.dart';\n"
            + "import '../services/tdf_service.dart';\n"
            + "class BadUi {}\n",
            encoding="utf-8",
        )

        dag_issues = tiertask_dev._check_acyclic_dag(self.root)
        joined = "\n".join(dag_issues)
        self.assertIn("lib/presentation/sample_controller.dart -> lib/ui/sample_screen.dart", joined)
        self.assertIn("lib/providers/sample_provider.dart -> lib/presentation/sample_controller.dart", joined)
        self.assertIn("P-UDF-ARCHITECTURE", joined)
        self.assertIn("lib/ui/bad_ui.dart -> lib/repositories/local_repo.dart", joined)
        self.assertIn("lib/ui/bad_ui.dart -> lib/services/app_logger.dart", joined)
        self.assertIn("lib/ui/bad_ui.dart -> lib/services/tdf_service.dart", joined)

    def test_static_checks_enforce_extended_io_isolation_and_ui_provider_ban(self) -> None:
        (self.root / "lib" / "presentation").mkdir(parents=True, exist_ok=True)
        (self.root / "lib" / "providers").mkdir(parents=True, exist_ok=True)
        (self.root / "lib" / "repositories").mkdir(parents=True, exist_ok=True)

        (self.root / "lib" / "presentation" / "bad_pres.dart").write_text(
            GPL_HEADER + "\nimport 'dart:io';\nimport 'dart:ffi';\nclass BadPres {}\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "providers" / "bad_prov.dart").write_text(
            GPL_HEADER + "\nimport 'dart:io';\nimport 'dart:ffi';\nclass BadProv {}\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "repositories" / "good_repo.dart").write_text(
            GPL_HEADER + "\nimport 'dart:io';\nimport 'dart:ffi';\nclass GoodRepo {}\n",
            encoding="utf-8",
        )
        (self.root / "lib" / "ui" / "bad_providers_ui.dart").write_text(
            GPL_HEADER
            + "\n// Comment mentioning localFileRepositoryProvider is allowed.\n"
            + "void bad(dynamic ref) {\n"
            + "  ref.read(appVersionRepositoryProvider);\n"
            + "  ref.read(directoryPickerProvider);\n"
            + "  ref.read(filePickerProvider);\n"
            + "  ref.read(linkLauncherRepositoryProvider);\n"
            + "  ref.read(localFileRepositoryProvider);\n"
            + "  ref.read(locationRepositoryProvider);\n"
            + "  ref.read(settingsRepositoryProvider);\n"
            + "  ref.read(supportsDirectoryPickerProvider);\n"
            + "  ref.read(tdfServiceProvider);\n"
            + "  ref.read(webDavRepositoryProvider);\n"
            + "}\n",
            encoding="utf-8",
        )

        issues = tiertask_dev.run_static_checks(self.root, fix=False)
        joined = "\n".join(issues)
        io_issues = [i for i in issues if i.startswith("P-IO-ISOLATION:")]
        self.assertIn("P-IO-ISOLATION: Forbidden `dart:io` import in `lib/presentation/bad_pres.dart", joined)
        self.assertIn("P-IO-ISOLATION: Forbidden `dart:ffi` import in `lib/presentation/bad_pres.dart", joined)
        self.assertIn("P-IO-ISOLATION: Forbidden `dart:io` import in `lib/providers/bad_prov.dart", joined)
        self.assertIn("P-IO-ISOLATION: Forbidden `dart:ffi` import in `lib/providers/bad_prov.dart", joined)
        self.assertFalse(any("lib/repositories/good_repo.dart" in i for i in io_issues))

        for provider_name in (
            "appVersionRepositoryProvider",
            "directoryPickerProvider",
            "filePickerProvider",
            "linkLauncherRepositoryProvider",
            "localFileRepositoryProvider",
            "locationRepositoryProvider",
            "settingsRepositoryProvider",
            "supportsDirectoryPickerProvider",
            "tdfServiceProvider",
            "webDavRepositoryProvider",
        ):
            self.assertIn(
                f"P-UDF-ARCHITECTURE: Forbidden `{provider_name}` reference in `lib/ui/bad_providers_ui.dart",
                joined,
            )
        # Comment line (line 16) must not be flagged.
        self.assertNotIn("lib/ui/bad_providers_ui.dart:16", joined)

    def test_presentation_arch_section_and_find_layer(self) -> None:
        self.assertEqual(
            tiertask_dev._layer_section_for_path("lib/presentation/ui_telemetry.dart"),
            "## Presentation",
        )
        tiertask_dev.scaffold_file(
            self.root,
            "lib/presentation/sample_controller.dart",
            description="Presentation `SampleController`.",
        )
        (self.root / "lib" / "presentation" / "sample_controller.dart").write_text(
            GPL_HEADER + "\nclass SampleController {}\n",
            encoding="utf-8",
        )
        self.assertEqual(tiertask_dev.audit_architecture(self.root), [])
        matches = tiertask_dev.find_in_repo(
            self.root,
            "SampleController",
            layer="presentation",
        )
        self.assertTrue(
            any("lib/presentation/sample_controller.dart" in m for m in matches)
        )

    def _build_minimal_ui_package(self, root: Path) -> None:
        ui_root = root / "packages" / "tiertask_ui"
        for sub in (
            "lib/src/tokens",
            "lib/src/primitives",
            "lib/src/layout",
            "lib/src/components",
            "test/tokens",
            "test/primitives",
            "example/lib",
            "example/test",
            "example/linux/runner",
            "build/cache",
            "example/build/linux",
            "example/linux/flutter/ephemeral",
        ):
            (ui_root / sub).mkdir(parents=True, exist_ok=True)

        (ui_root / "pubspec.yaml").write_text(
            "name: tiertask_ui\npublish_to: none\ndependencies:\n  flutter:\n    sdk: flutter\n  material_ui: ^1.11.1\n",
            encoding="utf-8",
        )
        (ui_root / "analysis_options.yaml").write_text(
            "include: package:flutter_lints/flutter.yaml\n",
            encoding="utf-8",
        )
        (ui_root / "pubspec.lock").write_text("# lockfile\n", encoding="utf-8")
        (ui_root / "build" / "cache" / "artifact.dart").write_text("// ignore\n", encoding="utf-8")
        (ui_root / "example" / "pubspec.yaml").write_text(
            "name: tiertask_ui_example\npublish_to: none\ndependencies:\n  flutter:\n    sdk: flutter\n  tiertask_ui:\n    path: ..\n",
            encoding="utf-8",
        )
        (ui_root / "example" / "analysis_options.yaml").write_text(
            "include: package:flutter_lints/flutter.yaml\n",
            encoding="utf-8",
        )
        (ui_root / "example" / "pubspec.lock").write_text("# lockfile\n", encoding="utf-8")
        (ui_root / "example" / "linux" / "CMakeLists.txt").write_text("# cmake\n", encoding="utf-8")
        (ui_root / "example" / "linux" / "runner" / "main.cc").write_text("// cc\n", encoding="utf-8")

        (ui_root / "lib" / "src" / "tokens" / "ui_focus_tokens.dart").write_text(
            GPL_HEADER + "\n/// Focus tokens.\nclass UiFocusTokens {}\n",
            encoding="utf-8",
        )
        (ui_root / "lib" / "src" / "tokens" / "ui_theme_tokens.dart").write_text(
            GPL_HEADER
            + "\nimport 'ui_focus_tokens.dart';\n\n"
            + "/// Theme tokens.\nclass UiThemeTokens {\n"
            + "  /// Creates theme tokens.\n  const UiThemeTokens(this.focus);\n"
            + "  /// Focus tokens.\n  final UiFocusTokens focus;\n}\n",
            encoding="utf-8",
        )
        (ui_root / "lib" / "src" / "primitives" / "ui_button.dart").write_text(
            GPL_HEADER
            + "\nimport '../tokens/ui_theme_tokens.dart';\n\n"
            + "/// Button primitive.\nclass UiButton {\n"
            + "  /// Creates a button.\n  const UiButton(this.tokens);\n"
            + "  /// Theme tokens.\n  final UiThemeTokens tokens;\n}\n",
            encoding="utf-8",
        )
        (ui_root / "lib" / "tiertask_ui.dart").write_text(
            GPL_HEADER
            + "\nexport 'src/primitives/ui_button.dart';\n"
            + "export 'src/tokens/ui_focus_tokens.dart';\n"
            + "export 'src/tokens/ui_theme_tokens.dart';\n",
            encoding="utf-8",
        )
        (ui_root / "test" / "test_helpers.dart").write_text(
            GPL_HEADER
            + "\nimport 'package:tiertask_ui/tiertask_ui.dart';\n\n"
            + "UiThemeTokens defaultTokens() => const UiThemeTokens(UiFocusTokens());\n",
            encoding="utf-8",
        )
        (ui_root / "test" / "tokens" / "ui_theme_tokens_test.dart").write_text(
            GPL_HEADER
            + "\nimport 'package:flutter_test/flutter_test.dart';\n"
            + "import 'package:tiertask_ui/tiertask_ui.dart';\n"
            + "import '../test_helpers.dart';\n\n"
            + "void main() {\n"
            + "  test('checks UiThemeTokens and UiFocusTokens', () {\n"
            + "    expect(defaultTokens().focus, isA<UiFocusTokens>());\n"
            + "  });\n"
            + "}\n",
            encoding="utf-8",
        )
        (ui_root / "test" / "primitives" / "ui_button_test.dart").write_text(
            GPL_HEADER
            + "\nimport 'package:flutter_test/flutter_test.dart';\n"
            + "import 'package:tiertask_ui/tiertask_ui.dart';\n"
            + "import '../test_helpers.dart';\n\n"
            + "void main() {\n"
            + "  testWidgets('renders UiButton', (tester) async {\n"
            + "    expect(UiButton(defaultTokens()), isNotNull);\n"
            + "  });\n"
            + "}\n",
            encoding="utf-8",
        )
        (ui_root / "example" / "lib" / "main.dart").write_text(
            GPL_HEADER
            + "\nimport 'package:tiertask_ui/tiertask_ui.dart';\n\n"
            + "void main() {\n"
            + "  const UiButton(UiThemeTokens(UiFocusTokens()));\n"
            + "}\n",
            encoding="utf-8",
        )
        (ui_root / "example" / "test" / "gallery_smoke_test.dart").write_text(
            GPL_HEADER
            + "\nimport 'package:flutter_test/flutter_test.dart';\n"
            + "import 'package:tiertask_ui/tiertask_ui.dart';\n\n"
            + "void main() {\n"
            + "  testWidgets('gallery renders', (tester) async {\n"
            + "    expect(const UiFocusTokens(), isNotNull);\n"
            + "  });\n"
            + "}\n",
            encoding="utf-8",
        )

        arch_path = root / "ARCHITECTURE.md"
        arch_text = arch_path.read_text(encoding="utf-8")
        arch_text += (
            "\n## UI Component Library\n\n"
            "| File | Function |\n"
            "| :--- | :--- |\n"
            "| `packages/tiertask_ui/lib/tiertask_ui.dart` | Public UI library barrel. |\n"
            "| `packages/tiertask_ui/lib/src/tokens/ui_focus_tokens.dart` | Focus tokens. |\n"
            "| `packages/tiertask_ui/lib/src/tokens/ui_theme_tokens.dart` | Theme tokens. |\n"
            "| `packages/tiertask_ui/lib/src/primitives/ui_button.dart` | Button primitive. |\n"
        )
        arch_path.write_text(arch_text, encoding="utf-8")
        tiertask_dev.sync_architecture_tree(root)

    def test_ui_package_barrel_carveout_and_isolation_checks(self) -> None:
        self._build_minimal_ui_package(self.root)
        self.assertEqual(tiertask_dev.run_static_checks(self.root, fix=False), [])

        ui_root = self.root / "packages" / "tiertask_ui"
        # Nested export inside lib/src/ must be rejected.
        (ui_root / "lib" / "src" / "primitives" / "bad_export.dart").write_text(
            GPL_HEADER + "\nexport '../tokens/ui_focus_tokens.dart';\n",
            encoding="utf-8",
        )
        # Forbidden domain, riverpod, io, ffi, and HttpClient references.
        (ui_root / "lib" / "src" / "primitives" / "bad_isolation.dart").write_text(
            GPL_HEADER
            + "\nimport 'dart:ffi';\n"
            + "import 'dart:io';\n"
            + "import 'package:flutter_riverpod/flutter_riverpod.dart';\n"
            + "import 'package:tiertask/models/sample_model.dart';\n"
            + "void bad() { HttpClient(); }\n",
            encoding="utf-8",
        )
        # Forbidden package:tiertask_ui/src/ import in test/ and example/.
        (ui_root / "test" / "primitives" / "ui_button_test.dart").write_text(
            GPL_HEADER
            + "\nimport 'package:tiertask_ui/src/tokens/ui_focus_tokens.dart';\n"
            + "void main() {}\n",
            encoding="utf-8",
        )
        (ui_root / "example" / "lib" / "main.dart").write_text(
            GPL_HEADER
            + "\nimport 'package:tiertask_ui/src/primitives/ui_button.dart';\n"
            + "void main() {}\n",
            encoding="utf-8",
        )
        # Forbidden pubspec dependency in packages/tiertask_ui/pubspec.yaml.
        (ui_root / "pubspec.yaml").write_text(
            "name: tiertask_ui\ndependencies:\n  tiertask:\n    path: ../..\n  flutter_riverpod: ^3.5.0\n",
            encoding="utf-8",
        )

        issues = tiertask_dev.run_static_checks(self.root, fix=False)
        joined = "\n".join(issues)
        self.assertIn("packages/tiertask_ui/lib/src/primitives/bad_export.dart", joined)
        self.assertIn("P-FILE-SIZE", joined)
        self.assertIn("packages/tiertask_ui/lib/src/primitives/bad_isolation.dart", joined)
        self.assertIn("dart:io", joined)
        self.assertIn("dart:ffi", joined)
        self.assertIn("package:tiertask/", joined)
        self.assertIn("package:flutter_riverpod/", joined)
        self.assertIn("HttpClient", joined)
        self.assertIn("packages/tiertask_ui/test/primitives/ui_button_test.dart", joined)
        self.assertIn("packages/tiertask_ui/example/lib/main.dart", joined)
        self.assertIn("packages/tiertask_ui/pubspec.yaml", joined)

    def test_ui_package_internal_acyclic_dag(self) -> None:
        self._build_minimal_ui_package(self.root)
        ui_root = self.root / "packages" / "tiertask_ui"
        # Upward import: tokens -> primitives and src -> tiertask_ui.dart.
        (ui_root / "lib" / "src" / "tokens" / "ui_focus_tokens.dart").write_text(
            GPL_HEADER
            + "\nimport '../primitives/ui_button.dart';\n"
            + "import '../../tiertask_ui.dart';\n"
            + "class UiFocusTokens {}\n",
            encoding="utf-8",
        )
        # Cycle inside layout.
        (ui_root / "lib" / "src" / "layout" / "a_layout.dart").write_text(
            GPL_HEADER + "\nimport 'b_layout.dart';\nclass ALayout {}\n",
            encoding="utf-8",
        )
        (ui_root / "lib" / "src" / "layout" / "b_layout.dart").write_text(
            GPL_HEADER + "\nimport 'a_layout.dart';\nclass BLayout {}\n",
            encoding="utf-8",
        )

        dag_issues = tiertask_dev._check_acyclic_dag(self.root)
        joined = "\n".join(dag_issues)
        self.assertIn("ui_focus_tokens.dart -> packages/tiertask_ui/lib/src/primitives/ui_button.dart", joined)
        self.assertIn("ui_focus_tokens.dart -> packages/tiertask_ui/lib/tiertask_ui.dart", joined)
        self.assertIn("a_layout.dart", joined)
        self.assertIn("b_layout.dart", joined)

    def test_ui_package_impacted_tests_partitioning_and_digest(self) -> None:
        self._build_minimal_ui_package(self.root)
        ui_root = self.root / "packages" / "tiertask_ui"

        digest_before = tiertask_dev.compute_code_digest(self.root)
        (ui_root / "pubspec.yaml").write_text(
            (ui_root / "pubspec.yaml").read_text(encoding="utf-8") + "# tweak\n",
            encoding="utf-8",
        )
        digest_after_pubspec = tiertask_dev.compute_code_digest(self.root)
        self.assertNotEqual(digest_before, digest_after_pubspec)

        (ui_root / "example" / "analysis_options.yaml").write_text(
            "include: package:flutter_lints/flutter.yaml\n# tweak\n",
            encoding="utf-8",
        )
        digest_after_example = tiertask_dev.compute_code_digest(self.root)
        self.assertNotEqual(digest_after_pubspec, digest_after_example)

        # Direct mirror resolution for UI primitive.
        button_tests = tiertask_dev.resolve_impacted_tests(
            self.root,
            ["packages/tiertask_ui/lib/src/primitives/ui_button.dart"],
        )
        self.assertEqual(button_tests, ["packages/tiertask_ui/test/primitives/ui_button_test.dart"])

        # Fallback resolution for unmirrored token sub-file.
        focus_tests = tiertask_dev.resolve_impacted_tests(
            self.root,
            ["packages/tiertask_ui/lib/src/tokens/ui_focus_tokens.dart"],
        )
        self.assertIn("packages/tiertask_ui/test/tokens/ui_theme_tokens_test.dart", focus_tests)

        # Barrel and test_helpers resolve dependent suites.
        barrel_tests = tiertask_dev.resolve_impacted_tests(
            self.root,
            ["packages/tiertask_ui/lib/tiertask_ui.dart"],
        )
        self.assertIn("packages/tiertask_ui/test/primitives/ui_button_test.dart", barrel_tests)
        self.assertIn("packages/tiertask_ui/test/tokens/ui_theme_tokens_test.dart", barrel_tests)

        helper_tests = tiertask_dev.resolve_impacted_tests(
            self.root,
            ["packages/tiertask_ui/test/test_helpers.dart"],
        )
        self.assertIn("packages/tiertask_ui/test/primitives/ui_button_test.dart", helper_tests)

        # Example changes resolve example/test suites.
        example_tests = tiertask_dev.resolve_impacted_tests(
            self.root,
            ["packages/tiertask_ui/example/lib/main.dart"],
        )
        self.assertEqual(example_tests, ["packages/tiertask_ui/example/test/gallery_smoke_test.dart"])

        # Partitioning produces package-relative paths per package root.
        partitioned = tiertask_dev.partition_tests_by_package(
            [
                "test/models/sample_model_test.dart",
                "packages/tiertask_ui/test/primitives/ui_button_test.dart",
                "packages/tiertask_ui/example/test/gallery_smoke_test.dart",
            ],
        )
        self.assertEqual(partitioned[Path(".")], ["test/models/sample_model_test.dart"])
        self.assertEqual(
            partitioned[Path("packages/tiertask_ui")],
            ["test/primitives/ui_button_test.dart"],
        )
        self.assertEqual(
            partitioned[Path("packages/tiertask_ui/example")],
            ["test/gallery_smoke_test.dart"],
        )
        self.assertTrue(
            tiertask_dev._is_code_relevant_change("packages/tiertask_ui/lib/src/primitives/ui_button.dart")
        )

    def test_ui_package_arch_outline_find_and_scaffold(self) -> None:
        self._build_minimal_ui_package(self.root)
        tree = tiertask_dev.generate_architecture_tree(self.root)
        self.assertIn("packages/", tree)
        self.assertIn("tiertask_ui/", tree)
        self.assertIn("linux/", tree)
        self.assertNotIn("CMakeLists.txt", tree)
        self.assertNotIn("build/", tree)
        self.assertNotIn("ephemeral/", tree)
        self.assertNotIn("pubspec.lock", tree)

        self.assertEqual(tiertask_dev.audit_architecture(self.root), [])

        tiertask_dev.scaffold_file(
            self.root,
            "packages/tiertask_ui/lib/src/primitives/ui_pill.dart",
            description="Defines `UiPill` badge and chip widget.",
        )
        self.assertTrue((self.root / "packages" / "tiertask_ui" / "lib" / "src" / "primitives" / "ui_pill.dart").exists())
        self.assertEqual(tiertask_dev.audit_architecture(self.root), [])

        # Outline classifies package tests as test files.
        pkg_test_out = tiertask_dev.outline_file(
            self.root,
            self.root / "packages" / "tiertask_ui" / "test" / "primitives" / "ui_button_test.dart",
        )
        self.assertIn("testWidgets('renders UiButton')", pkg_test_out)
        ex_test_out = tiertask_dev.outline_file(
            self.root,
            self.root / "packages" / "tiertask_ui" / "example" / "test" / "gallery_smoke_test.dart",
        )
        self.assertIn("testWidgets('gallery renders')", ex_test_out)

        # Find includes packages/tiertask_ui/ when layer is None or ui_pkg.
        all_matches = tiertask_dev.find_in_repo(self.root, "UiButton")
        self.assertTrue(any("packages/tiertask_ui/lib/src/primitives/ui_button.dart" in m for m in all_matches))
        pkg_matches = tiertask_dev.find_in_repo(self.root, "UiButton", layer="ui_pkg")
        self.assertTrue(any("packages/tiertask_ui/lib/src/primitives/ui_button.dart" in m for m in pkg_matches))
        other_matches = tiertask_dev.find_in_repo(self.root, "UiButton", layer="models")
        self.assertEqual(other_matches, [])


if __name__ == "__main__":
    unittest.main()
