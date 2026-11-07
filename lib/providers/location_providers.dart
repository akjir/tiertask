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

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/location_state.dart';
import '../repositories/location_repository.dart';
import 'config_providers.dart';
import 'workspace_providers.dart';

/// Provides whether foreground location determination is currently enabled in the active workspace.
final locationEnabledProvider = Provider<bool>((ref) {
  final configAsync = ref.watch(webDavConfigProvider);
  if (configAsync.asData?.value case final config?) {
    return config.locationEnabled;
  }
  final workspaceAsync = ref.watch(activeWorkspaceProvider);
  return workspaceAsync.asData?.value.config.locationEnabled ?? false;
});

/// Provides the [LocationRepository] for foreground location determination.
final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return PlatformLocationRepository();
});

/// Provides the reactive foreground [LocationState] governed by [LocationNotifier].
final locationStateProvider = NotifierProvider<LocationNotifier, LocationState>(
  LocationNotifier.new,
);

/// Manages foreground-only location determination with lifecycle cooldowns and passive refresh.
class LocationNotifier extends Notifier<LocationState> {
  /// Minimum interval before an app resume triggers a new location lookup when a fix is already available.
  static const Duration minResumeRefreshInterval = Duration(minutes: 5);

  /// Interval between passive location refreshes while the application remains continuously in the foreground.
  static const Duration passiveRefreshInterval = Duration(minutes: 15);

  AppLifecycleListener? _lifecycleListener;
  Timer? _passiveTimer;
  int _requestGeneration = 0;

  /// Whether location determination is currently enabled in the active [WebDavConfig].
  bool get _isLocationEnabled => ref.read(locationEnabledProvider);

  @override
  LocationState build() {
    final locationEnabled = ref.watch(locationEnabledProvider);
    _disposeResources();
    ref.onDispose(_disposeResources);

    if (!locationEnabled) {
      _requestGeneration++;
      return const LocationState(status: LocationStatus.disabled);
    }

    _registerLifecycleListener();
    _startPassiveTimer();
    final generation = ++_requestGeneration;
    unawaited(_performLookup(generation: generation, forceRefresh: false));
    return const LocationState(status: LocationStatus.searching);
  }

  /// Handles [AppLifecycleState] transitions to pause timers in background and refresh with cooldown on resume.
  void handleAppLifecycleState(AppLifecycleState lifecycleState) {
    if (!_isLocationEnabled) {
      return;
    }
    switch (lifecycleState) {
      case AppLifecycleState.resumed:
        _startPassiveTimer();
        final now = ref.read(clockProvider)();
        if (state.shouldRefreshOnResume(now, minResumeRefreshInterval)) {
          final generation = ++_requestGeneration;
          if (state.status != LocationStatus.found) {
            state = state.copyWith(status: LocationStatus.searching);
          }
          unawaited(
            _performLookup(generation: generation, forceRefresh: false),
          );
        }
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _stopPassiveTimer();
    }
  }

  /// Forces an immediate foreground location refresh when triggered by the user from the status dialog.
  Future<void> refreshLocation() async {
    if (!_isLocationEnabled) {
      return;
    }
    final generation = ++_requestGeneration;
    state = state.copyWith(status: LocationStatus.searching);
    await _performLookup(generation: generation, forceRefresh: true);
  }

  /// Cancels the passive refresh timer and disposes the lifecycle listener.
  void _disposeResources() {
    _stopPassiveTimer();
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
  }

  /// Queries [locationRepositoryProvider] and updates [state] if [generation] is still current.
  Future<void> _performLookup({
    required int generation,
    required bool forceRefresh,
  }) async {
    final repository = ref.read(locationRepositoryProvider);
    final fix = await repository.determineLocation(forceRefresh: forceRefresh);
    if (generation != _requestGeneration || !_isLocationEnabled) {
      return;
    }
    final now = ref.read(clockProvider)();
    if (fix != null) {
      state = LocationState(
        status: LocationStatus.found,
        fix: fix,
        updatedAt: now,
      );
      return;
    }
    state = LocationState(status: LocationStatus.unavailable, updatedAt: now);
  }

  /// Registers an [AppLifecycleListener] to observe foreground and background transitions.
  void _registerLifecycleListener() {
    _lifecycleListener?.dispose();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: handleAppLifecycleState,
    );
  }

  /// Starts or restarts the 15-minute passive foreground refresh timer.
  void _startPassiveTimer() {
    _stopPassiveTimer();
    _passiveTimer = Timer.periodic(passiveRefreshInterval, (_) {
      if (!_isLocationEnabled) {
        _stopPassiveTimer();
        return;
      }
      final generation = ++_requestGeneration;
      unawaited(_performLookup(generation: generation, forceRefresh: false));
    });
  }

  /// Cancels the active passive foreground refresh timer if running.
  void _stopPassiveTimer() {
    _passiveTimer?.cancel();
    _passiveTimer = null;
  }
}
