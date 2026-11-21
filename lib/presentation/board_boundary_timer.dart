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

import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/webdav_config.dart';
import '../providers/config_providers.dart';
import '../providers/task_providers.dart';
import '../providers/workspace_providers.dart';
import '../services/app_logger.dart';

/// Provides the lifecycle-aware single wall-clock boundary timer exposing the scheduled UTC boundary.
final boardBoundaryTimerProvider =
    NotifierProvider.autoDispose<BoardBoundaryTimerNotifier, DateTime?>(
      BoardBoundaryTimerNotifier.new,
    );

/// Stateless boundary computation and delay-clamping helper for the single wall-clock timer.
class BoardBoundaryTimer {
  /// Prevents instantiation of [BoardBoundaryTimer].
  const BoardBoundaryTimer._();

  /// Maximum single [Timer] chunk (`7 days`) preventing 32-bit millisecond overflow on far-future timestamps.
  static const Duration maxTimerChunk = Duration(days: 7);

  /// Minimum [Timer] delay (`25 ms`) avoiding sub-millisecond busy spin on sub-second early wakeups.
  static const Duration minTimerDelay = Duration(milliseconds: 25);

  /// Clamps [rawDelay] into `[minTimerDelay, maxTimerChunk]`.
  static Duration clampTimerDelay(Duration rawDelay) {
    if (rawDelay <= minTimerDelay) {
      return minTimerDelay;
    }
    if (rawDelay > maxTimerChunk) {
      return maxTimerChunk;
    }
    return rawDelay;
  }

  /// Computes the earliest future wall-clock boundary (`> normalizeTimestamp(nowUtc)`) across open [tasks].
  static DateTime? nextBoundaryUtc({
    required Iterable<TaskItem> tasks,
    required DateTime nowUtc,
    required Duration? dueLeadWindow,
  }) {
    final now = TaskItem.normalizeTimestamp(nowUtc);
    DateTime? earliest;
    for (final task in tasks) {
      final candidate = _earliestTaskBoundary(task, now, dueLeadWindow);
      if (candidate != null) {
        earliest = _minUtc(earliest, candidate);
      }
    }
    return earliest;
  }

  /// Returns the earliest future deferral, lead-window start, or exact deadline boundary for a single open [task].
  static DateTime? _earliestTaskBoundary(
    TaskItem task,
    DateTime now,
    Duration? dueLeadWindow,
  ) {
    if (task.isCompleted || task.completedAt != null) {
      return null;
    }
    DateTime? candidate;
    if (!task.isSuspendedForever) {
      if (task.suspendedAt case final suspendedAt?
          when suspendedAt != TaskItem.defaultSuspendedAt &&
              suspendedAt.isAfter(now)) {
        candidate = _minUtc(candidate, suspendedAt);
      }
    }
    if (task.dueAt case final dueAt?) {
      if (dueLeadWindow != null && !task.isDuePassive) {
        final leadStart = dueAt.subtract(dueLeadWindow);
        if (leadStart.isAfter(now)) {
          candidate = _minUtc(candidate, leadStart);
        }
      }
      if (dueAt.isAfter(now)) {
        candidate = _minUtc(candidate, dueAt);
      }
    }
    return candidate;
  }

  /// Returns the earlier UTC instant between [current] and [candidate].
  static DateTime _minUtc(DateTime? current, DateTime candidate) {
    if (current == null || candidate.isBefore(current)) {
      return candidate;
    }
    return current;
  }
}

/// Manages the lifecycle-aware single wall-clock [Timer] that advances [boundaryTickProvider].
class BoardBoundaryTimerNotifier extends Notifier<DateTime?> {
  Timer? _boundaryTimer;
  bool _isAppResumed = true;
  bool _isDisposed = false;
  AppLifecycleListener? _lifecycleListener;
  DateTime? _scheduledBoundaryUtc;

  @override
  DateTime? build() {
    _disposeResources();
    _isDisposed = false;
    _isAppResumed = true;
    ref.onDispose(_disposeResources);
    _lifecycleListener = AppLifecycleListener(
      onStateChange: handleAppLifecycleState,
    );
    ref.listen<AsyncValue<TaskBoard>>(
      taskNotifierProvider,
      (_, _) => _syncFromProviders(updateState: true),
    );
    ref.listen<DueLeadWindow?>(
      webDavConfigProvider.select(
        (asyncConfiguration) => asyncConfiguration.asData?.value.dueLeadWindow,
      ),
      (_, _) => _syncFromProviders(updateState: true),
    );
    ref.listen<int>(
      boundaryTickProvider,
      (_, _) => _syncFromProviders(updateState: true),
    );
    return _syncFromProviders(updateState: false);
  }

  /// Pauses the timer in the background and catches up crossed boundaries on foreground resume.
  void handleAppLifecycleState(AppLifecycleState lifecycleState) {
    if (_isDisposed) {
      return;
    }
    if (lifecycleState == AppLifecycleState.resumed) {
      _isAppResumed = true;
      ref.read(boundaryTickProvider.notifier).increment();
      _syncFromProviders(updateState: true);
      return;
    }
    _isAppResumed = false;
    _cancelBoundaryTimer();
    state = null;
  }

  /// Cancels any active [_boundaryTimer] and clears [_scheduledBoundaryUtc].
  void _cancelBoundaryTimer() {
    _boundaryTimer?.cancel();
    _boundaryTimer = null;
    _scheduledBoundaryUtc = null;
  }

  /// Disposes the active timer and [AppLifecycleListener].
  void _disposeResources() {
    _isDisposed = true;
    _cancelBoundaryTimer();
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
  }

  /// Advances [boundaryTickProvider] once the scheduled boundary is reached, or re-arms on early wakeups.
  void _handleBoundaryTimerFired() {
    if (_isDisposed || !_isAppResumed) {
      return;
    }
    final rawUtcNow = ref.read(clockProvider)().toUtc();
    final normalizedNow = TaskItem.normalizeTimestamp(rawUtcNow);
    if (_scheduledBoundaryUtc case final target?
        when normalizedNow.isBefore(target)) {
      final remainingDelay = BoardBoundaryTimer.clampTimerDelay(
        target.difference(rawUtcNow),
      );
      _boundaryTimer = Timer(remainingDelay, _handleBoundaryTimerFired);
      return;
    }
    _scheduledBoundaryUtc = null;
    state = null;
    if (AppLogger.shouldLog(LogLevel.debug)) {
      AppLogger.event(
        LogLevel.debug,
        LogTag.ui,
        'ui.boundary_timer.fired',
        fields: <String, Object?>{'now_utc': normalizedNow.toIso8601String()},
      );
    }
    ref.read(boundaryTickProvider.notifier).increment();
  }

  /// Reads the latest board and configuration and schedules or cancels [_boundaryTimer].
  DateTime? _syncFromProviders({required bool updateState}) {
    if (_isDisposed || !_isAppResumed) {
      _cancelBoundaryTimer();
      if (updateState) {
        state = null;
      }
      return null;
    }
    final board = ref.read(taskNotifierProvider).asData?.value;
    if (board == null) {
      _cancelBoundaryTimer();
      if (updateState) {
        state = null;
      }
      return null;
    }
    final configuration =
        ref.read(webDavConfigProvider).asData?.value ??
        ref.read(activeWorkspaceProvider).asData?.value.config ??
        const WebDavConfig();
    final rawUtcNow = ref.read(clockProvider)().toUtc();
    final nextBoundary = BoardBoundaryTimer.nextBoundaryUtc(
      tasks: board.allTasks,
      nowUtc: rawUtcNow,
      dueLeadWindow: configuration.dueLeadWindow.duration,
    );
    if (nextBoundary == _scheduledBoundaryUtc &&
        (_boundaryTimer?.isActive ?? false)) {
      return _scheduledBoundaryUtc;
    }
    _cancelBoundaryTimer();
    _scheduledBoundaryUtc = nextBoundary;
    if (updateState) {
      state = nextBoundary;
    }
    if (nextBoundary == null) {
      return null;
    }
    final clampedDelay = BoardBoundaryTimer.clampTimerDelay(
      nextBoundary.difference(rawUtcNow),
    );
    _boundaryTimer = Timer(clampedDelay, _handleBoundaryTimerFired);
    if (AppLogger.shouldLog(LogLevel.debug)) {
      AppLogger.event(
        LogLevel.debug,
        LogTag.ui,
        'ui.boundary_timer.scheduled',
        fields: <String, Object?>{
          'target_utc': nextBoundary.toIso8601String(),
          'delay_ms': clampedDelay.inMilliseconds,
        },
      );
    }
    return nextBoundary;
  }
}
