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
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/location_repository.dart';
import 'package:tiertask/services/app_logger.dart';

class _ControlledLocationRepository implements LocationRepository {
  _ControlledLocationRepository({this.onLookup});

  int callCount = 0;
  bool lastForceRefresh = false;
  final Future<LocationFix?> Function({required bool forceRefresh})? onLookup;

  @override
  Future<LocationFix?> determineLocation({bool forceRefresh = false}) {
    callCount++;
    lastForceRefresh = forceRefresh;
    if (onLookup case final callback?) {
      return callback(forceRefresh: forceRefresh);
    }
    return Future<LocationFix?>.value();
  }

  @override
  Future<List<GeocodingCandidate>> searchLocations(String query) async {
    return const <GeocodingCandidate>[];
  }
}

class _PendingActiveWorkspaceNotifier extends ActiveWorkspaceNotifier {
  final Completer<AppWorkspace> _completer = Completer<AppWorkspace>();

  @override
  Future<AppWorkspace> build() => _completer.future;
}

class _PendingWebDavConfigNotifier extends WebDavConfigNotifier {
  final Completer<WebDavConfig> _completer = Completer<WebDavConfig>();

  @override
  Future<WebDavConfig> build() => _completer.future;

  void emitConfig(WebDavConfig configuration) {
    state = AsyncData<WebDavConfig>(configuration);
  }
}

class _StubActiveWorkspaceNotifier extends ActiveWorkspaceNotifier {
  _StubActiveWorkspaceNotifier(this._workspace);

  final AppWorkspace _workspace;

  @override
  Future<AppWorkspace> build() async => _workspace;
}

class _ToggleableLocationEnabledNotifier extends Notifier<bool> {
  _ToggleableLocationEnabledNotifier(this._initialValue);

  final bool _initialValue;

  @override
  bool build() => _initialValue;

  void setEnabled(bool enabled) {
    state = enabled;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.resetForTesting(clock: () => DateTime.utc(2026, 11, 22, 12));
  });

  tearDown(() {
    AppLogger.resetForTesting();
  });

  group('locationEnabledProvider', () {
    test('falls back to activeWorkspaceProvider while webDavConfigProvider is loading', () async {
      final configNotifier = _PendingWebDavConfigNotifier();
      const workspace = AppWorkspace(
        id: 'default',
        name: 'Default',
        config: WebDavConfig(locationEnabled: true),
      );
      final container = ProviderContainer(
        overrides: [
          activeWorkspaceProvider.overrideWith(
            () => _StubActiveWorkspaceNotifier(workspace),
          ),
          webDavConfigProvider.overrideWith(() => configNotifier),
        ],
      );
      addTearDown(container.dispose);

      await container.read(activeWorkspaceProvider.future);
      expect(
        container.read(locationEnabledProvider),
        isTrue,
        reason: 'locationEnabledProvider must read activeWorkspaceProvider while webDavConfigProvider is loading',
      );

      configNotifier.emitConfig(const WebDavConfig());
      expect(
        container.read(locationEnabledProvider),
        isFalse,
        reason: 'Loaded webDavConfigProvider value must override activeWorkspaceProvider fallback',
      );
    });

    test('defaults to false while both config and workspace are loading', () {
      final container = ProviderContainer(
        overrides: [
          activeWorkspaceProvider.overrideWith(
            _PendingActiveWorkspaceNotifier.new,
          ),
          webDavConfigProvider.overrideWith(_PendingWebDavConfigNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(locationEnabledProvider), isFalse);
    });
  });

  group('LocationNotifier disposal and error handling', () {
    test('disposing mid-flight initial lookup produces zero UnmountedRefException or unhandled errors', () async {
      final unhandledErrors = <Object>[];
      LocationState? initialState;
      var callCount = 0;

      await runZonedGuarded(
        () async {
          final lookupCompleter = Completer<LocationFix?>();
          final repository = _ControlledLocationRepository(
            onLookup: ({required forceRefresh}) => lookupCompleter.future,
          );
          final container = ProviderContainer(
            overrides: [
              clockProvider.overrideWithValue(
                () => DateTime.utc(2026, 11, 22, 12),
              ),
              locationEnabledProvider.overrideWithValue(true),
              locationRepositoryProvider.overrideWithValue(repository),
            ],
          );

          initialState = container.read(locationStateProvider);
          callCount = repository.callCount;

          container.dispose();
          lookupCompleter.complete(
            const LocationFix(
              latitude: 52.52,
              longitude: 13.405,
              placeName: 'Berlin, Germany',
              source: LocationSource.gps,
            ),
          );
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);
        },
        (error, stackTrace) {
          unhandledErrors.add(error);
        },
      );

      expect(initialState?.status, equals(LocationStatus.searching));
      expect(callCount, equals(1));
      expect(
        unhandledErrors,
        isEmpty,
        reason: 'Completing an in-flight lookup after container disposal must not throw',
      );
    });

    test('disposing mid-flight lookup that rejects produces zero UnmountedRefException or unhandled errors', () async {
      final unhandledErrors = <Object>[];
      LocationState? initialState;

      await runZonedGuarded(
        () async {
          final lookupCompleter = Completer<LocationFix?>();
          final repository = _ControlledLocationRepository(
            onLookup: ({required forceRefresh}) => lookupCompleter.future,
          );
          final container = ProviderContainer(
            overrides: [
              clockProvider.overrideWithValue(
                () => DateTime.utc(2026, 11, 22, 12),
              ),
              locationEnabledProvider.overrideWithValue(true),
              locationRepositoryProvider.overrideWithValue(repository),
            ],
          );

          initialState = container.read(locationStateProvider);

          container.dispose();
          lookupCompleter.completeError(
            StateError('Location channel failed after dispose'),
          );
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);
        },
        (error, stackTrace) {
          unhandledErrors.add(error);
        },
      );

      expect(initialState?.status, equals(LocationStatus.searching));
      expect(
        unhandledErrors,
        isEmpty,
        reason: 'Rejecting an in-flight lookup after container disposal must not leak unhandled errors',
      );
    });

    test('disposing mid-flight refreshLocation completes cleanly without UnmountedRefException', () async {
      const initialFix = LocationFix(
        latitude: 50.9787,
        longitude: 11.0328,
        placeName: 'Erfurt, Germany',
        source: LocationSource.system,
      );
      final refreshCompleter = Completer<LocationFix?>();
      final repository = _ControlledLocationRepository(
        onLookup: ({required forceRefresh}) {
          if (!forceRefresh) {
            return Future<LocationFix?>.value(initialFix);
          }
          return refreshCompleter.future;
        },
      );
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 22, 12)),
          locationEnabledProvider.overrideWithValue(true),
          locationRepositoryProvider.overrideWithValue(repository),
        ],
      );

      container.read(locationStateProvider);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(locationStateProvider).status,
        equals(LocationStatus.found),
      );

      final refreshFuture = container
          .read(locationStateProvider.notifier)
          .refreshLocation();
      container.dispose();
      refreshCompleter.complete(
        const LocationFix(
          latitude: 52.52,
          longitude: 13.405,
          placeName: 'Berlin, Germany',
          source: LocationSource.gps,
        ),
      );

      await expectLater(refreshFuture, completes);
    });

    test('catches thrown determineLocation exceptions, logs redacted warning, and transitions to unavailable', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.debug,
        persistToDisk: false,
      );
      AppLogger.setSecretToRedact('secret-location-token');

      final now = DateTime.utc(2026, 11, 22, 12, 5);
      final repository = _ControlledLocationRepository(
        onLookup: ({required forceRefresh}) => Future<LocationFix?>.error(
          StateError('Daemon offline with secret-location-token'),
        ),
      );
      final unhandledErrors = <Object>[];
      LocationState? initial;
      LocationState? afterFailure;
      LocationState? afterManualFailure;

      await runZonedGuarded(
        () async {
          final container = ProviderContainer(
            overrides: [
              clockProvider.overrideWithValue(() => now),
              locationEnabledProvider.overrideWithValue(true),
              locationRepositoryProvider.overrideWithValue(repository),
            ],
          );
          addTearDown(container.dispose);

          initial = container.read(locationStateProvider);

          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);

          afterFailure = container.read(locationStateProvider);

          await container
              .read(locationStateProvider.notifier)
              .refreshLocation();
          afterManualFailure = container.read(locationStateProvider);
        },
        (error, stackTrace) {
          unhandledErrors.add(error);
        },
      );

      expect(
        unhandledErrors,
        isEmpty,
        reason: 'Thrown determineLocation errors must never escape unawaited lookups',
      );
      expect(initial?.status, equals(LocationStatus.searching));
      expect(
        afterFailure?.status,
        equals(LocationStatus.unavailable),
        reason: 'Thrown lookup error must move state out of searching into unavailable',
      );
      expect(afterFailure?.fix, isNull);
      expect(afterFailure?.updatedAt, equals(now));
      expect(
        afterManualFailure?.status,
        equals(LocationStatus.unavailable),
        reason: 'Manual refresh failure must transition to unavailable without throwing',
      );
      final warnLines = AppLogger.lines
          .where((line) => line.contains('[WARN ]'))
          .toList();
      expect(
        warnLines,
        isNotEmpty,
        reason: 'Failed lookup must emit a structured warning event',
      );
      expect(
        warnLines.any((line) => line.contains('location.lookup_failed')),
        isTrue,
      );
      expect(
        warnLines.every((line) => !line.contains('secret-location-token')),
        isTrue,
        reason: 'Warning log must redact registered secrets',
      );
    });
  });

  group('LocationNotifier stale generation cancellation', () {
    test('ignores stale in-flight initial lookup when refreshLocation supersedes it', () async {
      final initialCompleter = Completer<LocationFix?>();
      final refreshCompleter = Completer<LocationFix?>();
      var now = DateTime.utc(2026, 11, 22, 12);
      final repository = _ControlledLocationRepository(
        onLookup: ({required forceRefresh}) {
          return forceRefresh
              ? refreshCompleter.future
              : initialCompleter.future;
        },
      );
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          locationEnabledProvider.overrideWithValue(true),
          locationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(locationStateProvider).status,
        equals(LocationStatus.searching),
      );

      now = now.add(const Duration(seconds: 10));
      final refreshFuture = container
          .read(locationStateProvider.notifier)
          .refreshLocation();
      const newerFix = LocationFix(
        latitude: 52.52,
        longitude: 13.405,
        placeName: 'Berlin, Germany',
        source: LocationSource.gps,
      );
      refreshCompleter.complete(newerFix);
      await refreshFuture;

      expect(container.read(locationStateProvider).fix, equals(newerFix));

      initialCompleter.complete(
        const LocationFix(
          latitude: 48.1351,
          longitude: 11.582,
          placeName: 'Stale Munich',
          source: LocationSource.internet,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final currentState = container.read(locationStateProvider);
      expect(
        currentState.fix,
        equals(newerFix),
        reason: 'Stale lookup must not overwrite newer refreshLocation fix',
      );
      expect(currentState.status, equals(LocationStatus.found));
    });

    test('ignores stale in-flight lookup error when newer refreshLocation already succeeded', () async {
      final initialCompleter = Completer<LocationFix?>();
      final refreshCompleter = Completer<LocationFix?>();
      final repository = _ControlledLocationRepository(
        onLookup: ({required forceRefresh}) {
          return forceRefresh
              ? refreshCompleter.future
              : initialCompleter.future;
        },
      );
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 22, 12)),
          locationEnabledProvider.overrideWithValue(true),
          locationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      container.read(locationStateProvider);
      final refreshFuture = container
          .read(locationStateProvider.notifier)
          .refreshLocation();
      const newerFix = LocationFix(
        latitude: 52.52,
        longitude: 13.405,
        placeName: 'Berlin, Germany',
        source: LocationSource.gps,
      );
      refreshCompleter.complete(newerFix);
      await refreshFuture;

      initialCompleter.completeError(StateError('Stale daemon timeout'));
      await Future<void>.delayed(Duration.zero);

      final currentState = container.read(locationStateProvider);
      expect(
        currentState.status,
        equals(LocationStatus.found),
        reason: 'Stale lookup failure must not clobber a newer found fix',
      );
      expect(currentState.fix, equals(newerFix));
    });

    test('ignores refreshLocation and handleAppLifecycleState when disabled or disposed', () async {
      final repository = _ControlledLocationRepository();
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 22, 12)),
          locationEnabledProvider.overrideWithValue(false),
          locationRepositoryProvider.overrideWithValue(repository),
        ],
      );

      final notifier = container.read(locationStateProvider.notifier);
      expect(
        container.read(locationStateProvider).status,
        equals(LocationStatus.disabled),
      );

      notifier.handleAppLifecycleState(AppLifecycleState.resumed);
      await notifier.refreshLocation();
      expect(repository.callCount, equals(0));

      container.dispose();
      notifier.handleAppLifecycleState(AppLifecycleState.resumed);
      await expectLater(notifier.refreshLocation(), completes);
      expect(repository.callCount, equals(0));
    });

    test('ignores stale in-flight lookup when location is disabled before completion', () async {
      final lookupCompleter = Completer<LocationFix?>();
      final repository = _ControlledLocationRepository(
        onLookup: ({required forceRefresh}) => lookupCompleter.future,
      );
      final enabledToggleProvider =
          NotifierProvider<_ToggleableLocationEnabledNotifier, bool>(
            () => _ToggleableLocationEnabledNotifier(true),
          );
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 22, 12)),
          locationEnabledProvider.overrideWith(
            (ref) => ref.watch(enabledToggleProvider),
          ),
          locationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(locationStateProvider, (_, _) {});
      addTearDown(subscription.close);

      expect(
        container.read(locationStateProvider).status,
        equals(LocationStatus.searching),
      );

      container.read(enabledToggleProvider.notifier).setEnabled(false);
      expect(
        container.read(locationStateProvider).status,
        equals(LocationStatus.disabled),
      );

      lookupCompleter.complete(
        const LocationFix(
          latitude: 52.52,
          longitude: 13.405,
          placeName: 'Berlin, Germany',
          source: LocationSource.gps,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(locationStateProvider).status,
        equals(LocationStatus.disabled),
        reason: 'Disabling location must invalidate pending lookups so state stays disabled',
      );
    });
  });

  group('LocationNotifier lifecycle transitions and passive timer', () {
    test('enforces 5-minute resume cooldown, preserves found during refresh, and transitions unavailable to searching', () async {
      var now = DateTime.utc(2026, 11, 22, 12);
      Completer<LocationFix?>? activeCompleter;
      final repository = _ControlledLocationRepository(
        onLookup: ({required forceRefresh}) {
          if (activeCompleter case final completer?) {
            return completer.future;
          }
          return Future<LocationFix?>.value(
            const LocationFix(
              latitude: 50.9787,
              longitude: 11.0328,
              placeName: 'Erfurt, Germany',
              source: LocationSource.system,
            ),
          );
        },
      );
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          locationEnabledProvider.overrideWithValue(true),
          locationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      container.read(locationStateProvider);
      await Future<void>.delayed(Duration.zero);
      expect(repository.callCount, equals(1));
      expect(
        container.read(locationStateProvider).status,
        equals(LocationStatus.found),
      );

      // Resume before 5-minute cooldown must skip lookup.
      now = now.add(const Duration(minutes: 4, seconds: 59));
      container
          .read(locationStateProvider.notifier)
          .handleAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(
        repository.callCount,
        equals(1),
        reason: 'Resume under 5 minutes must skip refresh while found',
      );

      // Resume at >= 5 minutes must keep status found while lookup is in flight.
      now = now.add(const Duration(seconds: 1));
      final resumeFoundCompleter = Completer<LocationFix?>();
      activeCompleter = resumeFoundCompleter;
      container
          .read(locationStateProvider.notifier)
          .handleAppLifecycleState(AppLifecycleState.resumed);
      expect(repository.callCount, equals(2));
      expect(
        container.read(locationStateProvider).status,
        equals(LocationStatus.found),
        reason: 'Resume refresh from found must keep found status mid-flight',
      );
      expect(
        container.read(locationStateProvider).fix?.placeName,
        equals('Erfurt, Germany'),
      );

      // Complete with null to enter unavailable state.
      resumeFoundCompleter.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(locationStateProvider).status,
        equals(LocationStatus.unavailable),
      );

      // Resume from unavailable must immediately transition to searching even under 5 minutes.
      now = now.add(const Duration(seconds: 5));
      final resumeUnavailableCompleter = Completer<LocationFix?>();
      activeCompleter = resumeUnavailableCompleter;
      container
          .read(locationStateProvider.notifier)
          .handleAppLifecycleState(AppLifecycleState.resumed);
      expect(repository.callCount, equals(3));
      expect(
        container.read(locationStateProvider).status,
        equals(LocationStatus.searching),
        reason:
            'Resume from unavailable must transition immediately to searching',
      );

      // Resume while already searching must not start a duplicate lookup.
      container
          .read(locationStateProvider.notifier)
          .handleAppLifecycleState(AppLifecycleState.resumed);
      expect(
        repository.callCount,
        equals(3),
        reason: 'Resume while searching must not launch a duplicate lookup',
      );

      resumeUnavailableCompleter.complete(
        const LocationFix(
          latitude: 52.52,
          longitude: 13.405,
          placeName: 'Berlin, Germany',
          source: LocationSource.gps,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(locationStateProvider).status,
        equals(LocationStatus.found),
      );
      expect(
        container.read(locationStateProvider).fix?.placeName,
        equals('Berlin, Germany'),
      );
    });

    testWidgets(
      'runs 15-minute passive foreground refresh timer and stops it on hidden, paused, and detached',
      (tester) async {
        var now = DateTime.utc(2026, 11, 22, 12);
        final repository = _ControlledLocationRepository(
          onLookup: ({required forceRefresh}) async => const LocationFix(
            latitude: 52.52,
            longitude: 13.405,
            placeName: 'Berlin, Germany',
            source: LocationSource.system,
          ),
        );
        final container = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            locationEnabledProvider.overrideWithValue(true),
            locationRepositoryProvider.overrideWithValue(repository),
          ],
        );
        try {
          container.read(locationStateProvider);
          await tester.pump();
          expect(repository.callCount, equals(1));

          // 14m59s: passive timer has not fired yet.
          now = now.add(const Duration(minutes: 14, seconds: 59));
          await tester.pump(const Duration(minutes: 14, seconds: 59));
          expect(
            repository.callCount,
            equals(1),
            reason: 'Passive timer must not fire before 15 minutes',
          );

          // 15m00s: passive timer fires a non-forced refresh.
          now = now.add(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
          expect(
            repository.callCount,
            equals(2),
            reason: 'Passive timer must fire after 15 minutes in foreground',
          );
          expect(repository.lastForceRefresh, isFalse);

          // hidden stops passive timer.
          container
              .read(locationStateProvider.notifier)
              .handleAppLifecycleState(AppLifecycleState.hidden);
          now = now.add(const Duration(minutes: 30));
          await tester.pump(const Duration(minutes: 30));
          expect(
            repository.callCount,
            equals(2),
            reason:
                'AppLifecycleState.hidden must stop passive foreground timer',
          );

          // resumed restarts passive timer (and triggers resume refresh since >= 5m elapsed).
          container
              .read(locationStateProvider.notifier)
              .handleAppLifecycleState(AppLifecycleState.resumed);
          await tester.pump();
          expect(repository.callCount, equals(3));

          // paused stops passive timer.
          container
              .read(locationStateProvider.notifier)
              .handleAppLifecycleState(AppLifecycleState.paused);
          now = now.add(const Duration(minutes: 30));
          await tester.pump(const Duration(minutes: 30));
          expect(
            repository.callCount,
            equals(3),
            reason:
                'AppLifecycleState.paused must stop passive foreground timer',
          );

          // resumed restarts passive timer again.
          container
              .read(locationStateProvider.notifier)
              .handleAppLifecycleState(AppLifecycleState.resumed);
          await tester.pump();
          expect(repository.callCount, equals(4));

          // inactive preserves passive timer.
          container
              .read(locationStateProvider.notifier)
              .handleAppLifecycleState(AppLifecycleState.inactive);
          now = now.add(const Duration(minutes: 15));
          await tester.pump(const Duration(minutes: 15));
          expect(
            repository.callCount,
            equals(5),
            reason:
                'AppLifecycleState.inactive must keep passive timer running',
          );

          // detached stops passive timer.
          container
              .read(locationStateProvider.notifier)
              .handleAppLifecycleState(AppLifecycleState.detached);
          now = now.add(const Duration(minutes: 30));
          await tester.pump(const Duration(minutes: 30));
          expect(
            repository.callCount,
            equals(5),
            reason:
                'AppLifecycleState.detached must stop passive foreground timer',
          );
        } finally {
          // Dispose cancels all resources cleanly with zero pending timers.
          container.dispose();
        }
      },
    );
  });

  group('locationRepositoryProvider disposal', () {
    test('closes PlatformLocationRepository pooled HttpClient when ProviderContainer disposes', () async {
      final createdClients = <_CloseSpyHttpClient>[];
      await HttpOverrides.runZoned(
        () async {
          final container = ProviderContainer();
          final repository = container.read(locationRepositoryProvider);
          expect(repository, isA<PlatformLocationRepository>());

          // Trigger lazy HttpClient creation without external network I/O.
          final results = await repository.searchLocations('Berlin');
          expect(results, isEmpty);
          expect(createdClients, hasLength(1));
          expect(createdClients.single.closeCalls, equals(0));

          container.dispose();
          expect(
            createdClients.single.closeCalls,
            equals(1),
            reason: 'Disposing locationRepositoryProvider must close PlatformLocationRepository pooled HttpClient',
          );
        },
        createHttpClient: (_) {
          final client = _CloseSpyHttpClient();
          createdClients.add(client);
          return client;
        },
      );
    });
  });
}

class _CloseSpyHttpClient implements HttpClient {
  int closeCalls = 0;

  @override
  Duration? connectionTimeout;

  @override
  void close({bool force = false}) {
    closeCalls++;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      Future<HttpClientRequest>.error(const SocketException('hermetic'));

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
