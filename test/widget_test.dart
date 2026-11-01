// TierTask
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tiertask/main.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';

void main() {
  testWidgets(
    'TierTask UI renders numbered English tiers by default and adds tasks via QuickAddBar',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(language: AppLanguage.english),
              ),
            ),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('TierTask (T2)'), findsOneWidget);
      expect(find.text('# [1] Focus'), findsWidgets);
      expect(find.text('# [2] Ready'), findsWidgets);
      expect(find.text('# [3] Planned (Default)'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'New Focus Task');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('New Focus Task'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
    },
  );

  testWidgets(
    'TierTask UI renders numbered German tiers when German language is selected',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(language: AppLanguage.german),
              ),
            ),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('# [1] Fokus'), findsWidgets);
      expect(find.text('# [2] Bereit'), findsWidgets);
      expect(find.text('# [3] Geplant (Standard)'), findsOneWidget);
      expect(find.text('Hinzufügen'), findsOneWidget);
    },
  );

  testWidgets(
    'SettingsScreen switches display language between English and German',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(language: AppLanguage.english),
              ),
            ),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Language'), findsOneWidget);
      await tester.tap(find.text('Deutsch'));
      await tester.pumpAndSettle();

      expect(find.text('Sprache'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('# [1] Fokus'), findsWidgets);
      expect(find.text('# [3] Geplant (Standard)'), findsOneWidget);
    },
  );
}
