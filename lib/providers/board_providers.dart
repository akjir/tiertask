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
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/location_state.dart';
import '../models/task_board.dart';
import '../models/task_board_evaluator.dart';
import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/webdav_config.dart';
import '../repositories/app_version_repository.dart';
import '../services/app_logger.dart';
import 'config_providers.dart';
import 'location_providers.dart';
import 'task_providers.dart';
import 'workspace_providers.dart';

/// Provides the formatted [AppVersionDisplay] for drawer and about footers.
final appVersionDisplayProvider = Provider<AppVersionDisplay>(
  (ref) => AppVersionDisplay.fromRawVersion(
    ref.watch(appVersionProvider).asData?.value ??
        AppVersionRepository.defaultFullVersion,
  ),
);

/// Provides the lifecycle-aware single wall-clock boundary timer exposing the scheduled UTC boundary.
final boardBoundaryTimerProvider =
    NotifierProvider.autoDispose<BoardBoundaryTimerNotifier, DateTime?>(
      BoardBoundaryTimerNotifier.new,
    );

/// Evaluates the live [TaskBoard] against clock, boundary ticks, location fix, lead window, and [activeLabelId].
final evaluatedBoardProvider = Provider.autoDispose
    .family<AsyncValue<TaskBoard>, String?>((ref, activeLabelId) {
      ref.watch(boundaryTickProvider);
      final boardAsync = ref.watch(taskNotifierProvider);
      final activeFix = ref.watch(
        locationStateProvider.select(
          (locationState) => locationState.status == LocationStatus.found
              ? locationState.fix
              : null,
        ),
      );
      final evaluationSlice =
          ref.watch(
            webDavConfigProvider.select(
              (asyncConfiguration) =>
                  _extractEvaluationSlice(asyncConfiguration.asData?.value),
            ),
          ) ??
          ref.watch(
            activeWorkspaceProvider.select(
              (asyncWorkspace) =>
                  _extractEvaluationSlice(asyncWorkspace.asData?.value.config),
            ),
          );
      final clock = ref.watch(clockProvider);
      return boardAsync.whenData((board) {
        final evaluationTime = clock().toUtc();
        final timeZoneConfiguration = evaluationSlice == null
            ? const WebDavConfig()
            : WebDavConfig(
                timeZoneMode: evaluationSlice.timeZoneMode,
                manualTimeZoneOffsetMinutes:
                    evaluationSlice.manualTimeZoneOffsetMinutes,
                dueLeadWindow: evaluationSlice.dueLeadWindow,
              );
        return board.evaluateForContext(
          activeLabelId: activeLabelId,
          currentLatitude: activeFix?.latitude,
          currentLongitude: activeFix?.longitude,
          evaluationTime: evaluationTime,
          localEvaluationTime: timeZoneConfiguration.toLocalWallClock(
            evaluationTime,
          ),
          dueLeadWindow: timeZoneConfiguration.dueLeadWindow.duration,
        );
      });
    });

/// Provides the auto-disposed Raw `TDF 0.8.0` serialization preview for `RawTdfView`.
final rawTdfPreviewProvider = Provider.autoDispose<RawTdfPreview>((ref) {
  final board = ref.watch(
    taskNotifierProvider.select((boardAsync) => boardAsync.asData?.value),
  );
  if (board == null) {
    return const RawTdfPreview(
      isLimitExceeded: false,
      content: '',
      byteCount: 0,
      lineCount: 0,
    );
  }
  final tdfService = ref.watch(tdfServiceProvider);
  try {
    final content = tdfService.serialize(board);
    final byteCount = utf8.encode(content).length;
    final lineCount = content.isEmpty ? 0 : '\n'.allMatches(content).length;
    final exceeded = byteCount > maxTdfFileBytes || lineCount > maxTdfLineCount;
    if (exceeded) {
      return RawTdfPreview(
        isLimitExceeded: true,
        content: '',
        byteCount: byteCount,
        lineCount: lineCount,
        errorMessage: lookupAppLocalizations(ref.watch(appLocaleProvider))
            .errorLocalFileTooLarge,
      );
    }
    return RawTdfPreview(
      isLimitExceeded: false,
      content: content,
      byteCount: byteCount,
      lineCount: lineCount,
    );
  } on TdfException {
    return RawTdfPreview(
      isLimitExceeded: true,
      content: '',
      byteCount: 0,
      lineCount: 0,
      errorMessage: lookupAppLocalizations(ref.watch(appLocaleProvider))
          .errorLocalFileTooLarge,
    );
  }
});

/// Provides sorted prerequisite picker candidates for [taskId], or all open tasks when `null` for an uncommitted Task Draft Card.
final taskPrerequisiteCandidatesProvider = Provider.autoDispose
    .family<List<PrerequisiteCandidate>, String?>((ref, taskId) {
      final board = ref.watch(
        taskNotifierProvider.select((boardAsync) => boardAsync.asData?.value),
      );
      if (board == null) {
        return const <PrerequisiteCandidate>[];
      }
      final allTasks = board.allTasks;
      if (taskId == null) {
        return _buildDraftPrerequisiteCandidates(allTasks);
      }
      final task = board.findTask(taskId);
      if (task == null || task.isCompleted) {
        return const <PrerequisiteCandidate>[];
      }
      return _buildTaskPrerequisiteCandidates(allTasks, task);
    });

/// Immutable split display view of the SemVer 2.0.0 application version and build metadata.
@immutable
class AppVersionDisplay {
  /// Creates an [AppVersionDisplay] with [versionLabel] and [buildSuffix].
  const AppVersionDisplay({
    required this.versionLabel,
    required this.buildSuffix,
  });

  /// Splits [rawVersion] (`v0.4.0+<build>`) into `Version 0.4.0` and `+<build>`.
  factory AppVersionDisplay.fromRawVersion(String rawVersion) {
    final trimmed = rawVersion.trim();
    final versionText = (trimmed.startsWith('v') || trimmed.startsWith('V'))
        ? trimmed.substring(1)
        : trimmed;
    final plusIndex = versionText.indexOf('+');
    if (plusIndex < 0) {
      return AppVersionDisplay(
        versionLabel: 'Version $versionText',
        buildSuffix: '',
      );
    }
    return AppVersionDisplay(
      versionLabel: 'Version ${versionText.substring(0, plusIndex)}',
      buildSuffix: versionText.substring(plusIndex),
    );
  }

  /// Build metadata suffix starting with `'+'`, or empty when absent.
  final String buildSuffix;

  /// Human-readable version prefix (for example, `'Version 0.4.0'`).
  final String versionLabel;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppVersionDisplay &&
        other.versionLabel == versionLabel &&
        other.buildSuffix == buildSuffix;
  }

  @override
  int get hashCode => Object.hash(versionLabel, buildSuffix);
}

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
    final configuration = readCurrentConfig(ref);
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

/// Immutable selectable candidate row inside the Prerequisite picker.
@immutable
class PrerequisiteCandidate {
  /// Creates a [PrerequisiteCandidate].
  const PrerequisiteCandidate({
    required this.id,
    required this.title,
    required this.wouldCreateCycle,
    required this.isCompleted,
  });

  /// Candidate task identifier.
  final String id;

  /// Whether the candidate task is already completed.
  final bool isCompleted;

  /// Candidate task title.
  final String title;

  /// Whether adding this candidate would create a dependency cycle.
  final bool wouldCreateCycle;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PrerequisiteCandidate &&
        other.id == id &&
        other.title == title &&
        other.wouldCreateCycle == wouldCreateCycle &&
        other.isCompleted == isCompleted;
  }

  @override
  int get hashCode => Object.hash(id, title, wouldCreateCycle, isCompleted);
}

/// Immutable Raw `TDF 0.8.0` serialization preview snapshot.
@immutable
class RawTdfPreview {
  /// Creates a [RawTdfPreview].
  const RawTdfPreview({
    required this.isLimitExceeded,
    required this.content,
    required this.byteCount,
    required this.lineCount,
    this.errorMessage,
  });

  /// UTF-8 byte count of the serialized document.
  final int byteCount;

  /// Serialized canonical TDF text, or empty when [isLimitExceeded] is true or loading.
  final String content;

  /// Localized error message when [isLimitExceeded] is true, or `null` otherwise.
  final String? errorMessage;

  /// Whether canonical `1 MiB` or `16,384`-line bounds were exceeded.
  final bool isLimitExceeded;

  /// Line count of the serialized document.
  final int lineCount;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RawTdfPreview &&
        other.isLimitExceeded == isLimitExceeded &&
        other.content == content &&
        other.byteCount == byteCount &&
        other.lineCount == lineCount &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode =>
      Object.hash(isLimitExceeded, content, byteCount, lineCount, errorMessage);
}

/// Minimal [WebDavConfig] slice affecting board evaluation in [evaluatedBoardProvider].
typedef _EvaluationSlice = ({
  DueLeadWindow dueLeadWindow,
  int manualTimeZoneOffsetMinutes,
  AppTimeZoneMode timeZoneMode,
});

/// Builds sorted open-task prerequisite picker candidates for an uncommitted Task Draft Card.
List<PrerequisiteCandidate> _buildDraftPrerequisiteCandidates(
  Iterable<TaskItem> allTasks,
) {
  final candidates = <PrerequisiteCandidate>[];
  for (final other in allTasks) {
    if (other.isCompleted) {
      continue;
    }
    candidates.add(
      PrerequisiteCandidate(
        id: other.id,
        title: other.title,
        wouldCreateCycle: false,
        isCompleted: false,
      ),
    );
  }
  candidates.sort(_comparePrerequisiteCandidatesByTitle);
  return List<PrerequisiteCandidate>.unmodifiable(candidates);
}

/// Builds sorted prerequisite picker candidates for [task], tagging cycle-creating candidates in a single $O(N + E)$ pass.
List<PrerequisiteCandidate> _buildTaskPrerequisiteCandidates(
  Iterable<TaskItem> allTasks,
  TaskItem task,
) {
  final selectedIds = task.blockedByTaskIds.toSet();
  final cyclicIds = TaskBoardEvaluator.collectCycleCreatingPrerequisiteIds(
    taskId: task.id,
    tasks: allTasks,
  );
  final candidates = <PrerequisiteCandidate>[];
  for (final other in allTasks) {
    if (other.id == task.id) {
      continue;
    }
    final isSelected = selectedIds.contains(other.id);
    if (other.isCompleted && !isSelected) {
      continue;
    }
    final wouldCycle = !isSelected && cyclicIds.contains(other.id);
    candidates.add(
      PrerequisiteCandidate(
        id: other.id,
        title: other.title,
        wouldCreateCycle: wouldCycle,
        isCompleted: other.isCompleted,
      ),
    );
  }
  candidates.sort(_comparePrerequisiteCandidatesByTitle);
  return List<PrerequisiteCandidate>.unmodifiable(candidates);
}

/// Compares two [PrerequisiteCandidate] items case-insensitively by title.
int _comparePrerequisiteCandidatesByTitle(
  PrerequisiteCandidate left,
  PrerequisiteCandidate right,
) => left.title.toLowerCase().compareTo(right.title.toLowerCase());

/// Extracts only the evaluation-relevant fields from [configuration], or `null` when unavailable.
_EvaluationSlice? _extractEvaluationSlice(WebDavConfig? configuration) {
  if (configuration == null) {
    return null;
  }
  return (
    dueLeadWindow: configuration.dueLeadWindow,
    manualTimeZoneOffsetMinutes: configuration.manualTimeZoneOffsetMinutes,
    timeZoneMode: configuration.timeZoneMode,
  );
}
