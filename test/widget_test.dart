import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';

void main() {
  testWidgets(
    'TierTask UI renders # Fokus, # Bereit, and adds tasks via QuickAddBar',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(),
            ),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Verify main headings and Quick-Add bar are visible
      expect(find.text('TierTask (T2)'), findsOneWidget);
      expect(find.text('# Fokus'), findsWidgets);
      expect(find.text('# Bereit'), findsWidgets);
      expect(find.text('# Geplant (Standard)'), findsOneWidget);

      // Add a task via the Quick-Add bar (defaults to # Geplant and cascades to # Fokus)
      await tester.enterText(find.byType(TextField), 'Neue Fokus-Aufgabe');
      await tester.tap(find.text('Hinzufügen'));
      await tester.pumpAndSettle();

      expect(find.text('Neue Fokus-Aufgabe'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
    },
  );
}
