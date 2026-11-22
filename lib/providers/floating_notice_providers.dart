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
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/settings_codec.dart';
import '../models/task_board_undo.dart';
import 'config_providers.dart';
import 'task_providers.dart';
import 'ui_telemetry.dart';
import 'workspace_providers.dart';

/// Provides the active [FloatingNotice] for the floating toast and Undo overlay (`U-UX-004`).
final floatingNoticeProvider =
    NotifierProvider<FloatingNoticeNotifier, FloatingNotice?>(
      FloatingNoticeNotifier.new,
    );

/// Semantic visual tone for floating bottom notices and toasts.
enum FloatingNoticeTone {
  /// Default neutral informational toast.
  neutral,

  /// Accent-highlighted toast (e.g. Undo notice).
  accent,

  /// Amber warning toast (e.g. external removal or startup recovery).
  warning,

  /// Crimson danger toast (e.g. duplicate title or persistence error).
  danger,

  /// Green success toast.
  success,
}

/// Immutable model describing the active floating toast or Undo overlay (`U-UX-004`).
@immutable
class FloatingNotice {
  /// Creates a [FloatingNotice].
  const FloatingNotice({
    required this.id,
    required this.message,
    required this.tone,
    this.actionLabel,
    this.undoSequence,
    this.shortcutHint,
    this.persistent = false,
    this.autoHideDuration,
  });

  /// Optional action button label (e.g. `Undo`).
  final String? actionLabel;

  /// Optional auto-hide duration (`8s` Undo, `5s` standard, or `null` when persistent).
  final Duration? autoHideDuration;

  /// Monotonically increasing notice identifier for timer correlation.
  final int id;

  /// Localized message displayed inside the floating toast.
  final String message;

  /// Whether this notice remains visible until manually dismissed.
  final bool persistent;

  /// Optional desktop keyboard shortcut hint (e.g. `Ctrl+Z`, omitted on Android).
  final String? shortcutHint;

  /// Visual severity tone of the floating toast.
  final FloatingNoticeTone tone;

  /// Optional session Undo sequence bound to the action button.
  final int? undoSequence;

  /// Whether this notice carries an actionable Undo callback.
  bool get hasUndoAction => undoSequence != null && actionLabel != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FloatingNotice &&
        other.id == id &&
        other.message == message &&
        other.tone == tone &&
        other.actionLabel == actionLabel &&
        other.undoSequence == undoSequence &&
        other.shortcutHint == shortcutHint &&
        other.persistent == persistent &&
        other.autoHideDuration == autoHideDuration;
  }

  @override
  int get hashCode => Object.hash(
    id,
    message,
    tone,
    actionLabel,
    undoSequence,
    shortcutHint,
    persistent,
    autoHideDuration,
  );
}

/// Manages floating toasts, LIFO Undo notices (`8000ms`), standard notices (`5000ms`), and persistent recovery alerts.
class FloatingNoticeNotifier extends Notifier<FloatingNotice?> {
  /// Standard auto-hide duration for informational and feedback toasts (`U-UX-004`).
  static const Duration standardDuration = Duration(milliseconds: 5000);

  /// Auto-hide duration for Undo recovery toasts (`U-UX-004`).
  static const Duration undoDuration = Duration(milliseconds: 8000);

  String? _activeWorkspaceId;
  Timer? _autoHideTimer;
  int _lastUndoSequenceShown = 0;
  int _nextNoticeId = 1;
  int _undoInFlightCount = 0;
  int _workspaceGeneration = 0;

  /// Whether an Undo mutation initiated by [undoLatest] is currently executing.
  bool get _isApplyingUndo => _undoInFlightCount > 0;

  @override
  FloatingNotice? build() {
    _cancelTimer();
    _lastUndoSequenceShown = 0;
    _undoInFlightCount = 0;
    _workspaceGeneration = 0;
    ref.onDispose(_cancelTimer);

    final initialWorkspaceId = ref
        .read(activeWorkspaceProvider)
        .asData
        ?.value
        .id;
    _activeWorkspaceId = initialWorkspaceId;

    ref.listen<String?>(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
      _handleWorkspaceIdChanged,
    );

    ref.listen<TaskUndoState>(taskUndoStateProvider, (previous, next) {
      final notice = next.latestNotice;
      if (notice == null) {
        if (!_isApplyingUndo && (state?.hasUndoAction ?? false)) {
          dismiss();
        }
        return;
      }
      if (notice.sequence <= _lastUndoSequenceShown) {
        return;
      }
      _lastUndoSequenceShown = notice.sequence;
      _presentUndoNotice(notice);
    });

    if (initialWorkspaceId != null) {
      scheduleMicrotask(() {
        if (ref.mounted) {
          showStartupRecoveryNoticeIfPending();
        }
      });
    }
    return null;
  }

  /// Dismisses the currently displayed floating notice and cancels its timer.
  void dismiss() {
    _cancelTimer();
    state = null;
  }

  /// Displays a floating notice with [message], [tone], optional [duration], or [persistent] mode.
  void showNotice(
    String message, {
    FloatingNoticeTone tone = FloatingNoticeTone.neutral,
    Duration? duration = standardDuration,
    bool persistent = false,
    String? actionLabel,
    int? undoSequence,
    String? shortcutHint,
  }) {
    _cancelTimer();
    final noticeId = _nextNoticeId++;
    final effectiveDuration = persistent ? null : duration;
    state = FloatingNotice(
      id: noticeId,
      message: message,
      tone: tone,
      actionLabel: actionLabel,
      undoSequence: undoSequence,
      shortcutHint: shortcutHint,
      persistent: persistent,
      autoHideDuration: effectiveDuration,
    );
    if (effectiveDuration != null) {
      _autoHideTimer = Timer(effectiveDuration, () {
        if (ref.mounted && state?.id == noticeId) {
          state = null;
        }
      });
    }
  }

  /// Consumes any one-shot startup settings recovery notice and presents it as a persistent warning toast.
  void showStartupRecoveryNoticeIfPending({Locale? locale}) {
    if (locale == null && !ref.read(activeWorkspaceProvider).hasValue) {
      return;
    }
    final notice = _consumeStartupRecoveryNotice(locale: locale);
    if (notice == null) {
      return;
    }
    _cancelTimer();
    state = notice;
  }

  /// Executes the latest undoable task mutation and announces remaining Undo stack depth.
  Future<bool> undoLatest({bool fromShortcut = false, Locale? locale}) async {
    if (_isApplyingUndo) {
      return false;
    }
    final undoState = ref.read(taskUndoStateProvider);
    if (!undoState.canUndo) {
      return false;
    }
    final latestNotice = undoState.latestNotice;
    if (fromShortcut) {
      UiTelemetry.logUndoShortcut(stackDepth: undoState.stackDepth);
    } else if (latestNotice != null) {
      UiTelemetry.logUndoSnackBarAction(
        taskId: latestNotice.taskId,
        kind: latestNotice.kind,
        sequence: latestNotice.sequence,
      );
    }

    final expectedSequence = fromShortcut ? null : state?.undoSequence;
    final generation = _workspaceGeneration;
    _undoInFlightCount++;
    final bool applied;
    try {
      applied = await ref
          .read(taskNotifierProvider.notifier)
          .undoLastAction(expectedSequence: expectedSequence);
    } finally {
      _undoInFlightCount--;
    }
    if (!ref.mounted || _workspaceGeneration != generation) {
      return false;
    }
    if (!applied) {
      if ((state?.hasUndoAction ?? false) &&
          ref.read(taskUndoStateProvider).latestNotice == null) {
        dismiss();
      }
      return false;
    }

    final remaining = ref.read(taskUndoStateProvider).stackDepth;
    final localizations = lookupAppLocalizations(
      locale ?? ref.read(appLocaleProvider),
    );
    final message = remaining > 0
        ? localizations.actionUndoneRemainingNotice('$remaining')
        : localizations.actionUndoneNotice;
    showNotice(message);
    return true;
  }

  /// Cancels any active auto-hide timer.
  void _cancelTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  /// Consumes any pending one-shot startup settings recovery notice and wraps it as a persistent warning toast.
  FloatingNotice? _consumeStartupRecoveryNotice({Locale? locale}) {
    final recoveryNotice = ref
        .read(settingsRepositoryProvider)
        .takeLastRecoveryNotice();
    if (recoveryNotice == null) {
      return null;
    }
    final localizations = lookupAppLocalizations(
      locale ?? ref.read(appLocaleProvider),
    );
    final message = switch (recoveryNotice.kind) {
      SettingsRecoveryKind.recoveredFromBackup =>
        localizations.settingsRecoveredFromBackupNotice,
      SettingsRecoveryKind.resetAfterQuarantine =>
        localizations.settingsResetAfterQuarantineNotice,
    };
    if (message.isEmpty) {
      return null;
    }
    return FloatingNotice(
      id: _nextNoticeId++,
      message: message,
      tone: FloatingNoticeTone.warning,
      persistent: true,
    );
  }

  /// Clears active notices on workspace switches, ignores transient `AsyncLoading`, and consumes startup recovery notices.
  void _handleWorkspaceIdChanged(
    String? previousWorkspaceId,
    String? nextWorkspaceId,
  ) {
    if (nextWorkspaceId == null) {
      return;
    }
    final switchedWorkspace =
        _activeWorkspaceId != null && _activeWorkspaceId != nextWorkspaceId;
    _activeWorkspaceId = nextWorkspaceId;
    if (switchedWorkspace) {
      _workspaceGeneration++;
      _lastUndoSequenceShown = 0;
      dismiss();
    }
    showStartupRecoveryNoticeIfPending();
  }

  /// Formats and presents an `8000ms` floating Undo notice for [notice] with platform-gated shortcut hint.
  void _presentUndoNotice(TaskUndoNotice notice) {
    final localizations = lookupAppLocalizations(ref.read(appLocaleProvider));
    final message = switch (notice.kind) {
      TaskUndoActionKind.complete => localizations.taskCompletedUndoSnackBar(
        notice.taskTitle,
      ),
      TaskUndoActionKind.downgrade => localizations.taskDowngradedUndoSnackBar(
        notice.taskTitle,
      ),
      TaskUndoActionKind.delete => localizations.taskDeletedUndoSnackBar(
        notice.taskTitle,
      ),
    };
    UiTelemetry.logUndoSnackBarShown(
      taskId: notice.taskId,
      kind: notice.kind,
      sequence: notice.sequence,
    );
    final shortcutHint = ref.read(supportsDesktopWindowControlsProvider)
        ? 'Ctrl+Z'
        : null;
    showNotice(
      message,
      tone: FloatingNoticeTone.accent,
      duration: undoDuration,
      actionLabel: localizations.actionUndo,
      undoSequence: notice.sequence,
      shortcutHint: shortcutHint,
    );
  }
}
