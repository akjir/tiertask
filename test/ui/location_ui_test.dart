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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/location_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';

import 'test_helpers.dart';

/// Controllable [LocationRepository] allowing tests to hold a lookup in the `searching` state.
class _CompleterLocationRepository implements LocationRepository {
  Completer<LocationFix?> completer = Completer<LocationFix?>();
  int callCount = 0;

  @override
  Future<LocationFix?> determineLocation({bool forceRefresh = false}) {
    callCount++;
    return completer.future;
  }
}

void main() {
  final fixedDate = DateTime.utc(2026, 3, 29, 12, 0);

  testWidgets(
    'hides header location icon by default and shows it to the right of search icon when enabled in Settings',
    (WidgetTester tester) async {
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );
      final fakeLocationRepository = FakeLocationRepository(
        initialFix: const LocationFix(
          latitude: 50.9787,
          longitude: 11.0328,
          placeName: 'Erfurt, Germany',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => fixedDate),
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            locationRepositoryProvider.overrideWithValue(
              fakeLocationRepository,
            ),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      // By default locationEnabled is false -> no location icon in the top bar.
      expect(
        find.byKey(const ValueKey('top_bar_location_button')),
        findsNothing,
        reason: 'Location icon must be hidden when locationEnabled is false.',
      );

      // Navigate to Settings and verify Location Determination defaults to Off.
      await openSettingsFromMenu(tester);
      final segmentedFinder = find.byKey(
        const ValueKey('settings_location_segmented_button'),
      );
      await tester.scrollUntilVisible(
        segmentedFinder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Location Determination'), findsOneWidget);

      // Tap "On" to enable foreground location determination.
      await tester.tap(
        find.descendant(of: segmentedFinder, matching: find.text('On')),
      );
      await tester.pumpAndSettle();

      // Return to HomeScreen.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      final searchButtonFinder = find.byKey(
        const ValueKey('top_bar_search_button'),
      );
      final locationButtonFinder = find.byKey(
        const ValueKey('top_bar_location_button'),
      );
      expect(searchButtonFinder, findsOneWidget);
      expect(locationButtonFinder, findsOneWidget);

      final searchCenter = tester.getCenter(searchButtonFinder);
      final locationCenter = tester.getCenter(locationButtonFinder);
      expect(
        locationCenter.dx,
        greaterThan(searchCenter.dx),
        reason:
            'Location icon must be positioned to the right of the search icon.',
      );
    },
  );

  testWidgets(
    'renders searching, found, and unavailable icon states and displays popup with place, GPS coordinates, and Refresh',
    (WidgetTester tester) async {
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(
          language: AppLanguage.english,
          locationEnabled: true,
        ),
      );
      final controllableRepository = _CompleterLocationRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => fixedDate),
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            locationRepositoryProvider.overrideWithValue(
              controllableRepository,
            ),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 1. Searching state: icon is location_searching_rounded.
      final locationButtonFinder = find.byKey(
        const ValueKey('top_bar_location_button'),
      );
      expect(locationButtonFinder, findsOneWidget);
      expect(
        find.descendant(
          of: locationButtonFinder,
          matching: find.byIcon(Icons.location_searching_rounded),
        ),
        findsOneWidget,
        reason:
            'Header icon must indicate searching while lookup is in flight.',
      );

      // Open popup while searching.
      await tester.tap(locationButtonFinder);
      await tester.pump();
      expect(find.text('Location Status'), findsOneWidget);
      expect(find.text('Searching for location...'), findsOneWidget);

      // Complete lookup with a valid fix.
      controllableRepository.completer.complete(
        const LocationFix(
          latitude: 50.9787,
          longitude: 11.0328,
          placeName: 'Erfurt, Germany',
          source: LocationSource.gps,
        ),
      );
      await tester.pumpAndSettle();

      // 2. Found state: dialog updates to show Location found, place name, GPS coordinates, and source.
      expect(find.text('Location found'), findsOneWidget);
      expect(find.text('Erfurt, Germany'), findsOneWidget);
      expect(find.text('50.97870, 11.03280'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);
      expect(find.text('GPS'), findsOneWidget);
      expect(
        find.descendant(
          of: locationButtonFinder,
          matching: find.byIcon(Icons.location_on_rounded),
        ),
        findsOneWidget,
      );

      // 3. Click Refresh in dialog when next lookup returns null (unavailable).
      controllableRepository.completer = Completer<LocationFix?>()
        ..complete(null);
      await tester.tap(
        find.byKey(const ValueKey('location_dialog_refresh_button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('No location information available'), findsOneWidget);
      expect(
        find.descendant(
          of: locationButtonFinder,
          matching: find.byIcon(Icons.location_disabled_rounded),
        ),
        findsOneWidget,
      );

      // Close dialog.
      await tester.tap(
        find.byKey(const ValueKey('location_dialog_close_button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Location Status'), findsNothing);
    },
  );

  testWidgets(
    'evaluates task location conditions dynamically using determined GPS coordinates',
    (WidgetTester tester) async {
      const tdfWithLocationTask = '''
tdf 0.5.0

queue {
    modified 2026-03-29 08:00:00
    task loc100OkD2
}

task loc100OkD2 priority {
    name "Buy local specialty in Erfurt"
    created 2026-03-29 08:00
    queued 2026-03-29 08:00
    condition location 50.97870 11.03280 500
}
''';
      const config = WebDavConfig(
        language: AppLanguage.english,
        locationEnabled: true,
      );
      final settingsRepository = InMemorySettingsRepository(config);
      final fakeLocalRepo = FakeLocalFileRepository(
        config: config,
        initialTdf: tdfWithLocationTask,
      );
      final fakeLocationRepository = FakeLocationRepository(
        initialFix: const LocationFix(
          latitude: 50.9787,
          longitude: 11.0328,
          placeName: 'Erfurt, Germany',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => fixedDate),
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            localFileRepositoryProvider.overrideWithValue(fakeLocalRepo),
            locationRepositoryProvider.overrideWithValue(
              fakeLocationRepository,
            ),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Because the determined coordinates match (50.9787, 11.0328), the priority task is unblocked and shown in Focus!
      expect(
        find.text('Buy local specialty in Erfurt'),
        findsOneWidget,
        reason: 'Task with matching location condition must be promoted to Focus on HomeScreen.',
      );
    },
  );
}
