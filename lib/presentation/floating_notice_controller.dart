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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/task_board_undo.dart';
import '../providers/config_providers.dart';
import '../providers/task_providers.dart';
import '../providers/workspace_providers.dart';
import 'settings_controller.dart';
import 'ui_telemetry.dart';
import 'ui_v2_shell_models.dart';

/// Provides the active [FloatingNoticeViewModel] for the floating toast and Undo overlay (`U-UX-004`).
final floatingNoticeControllerProvider =
    NotifierProvider<FloatingNoticeController, FloatingNoticeViewModel?>(
      FloatingNoticeController.new,
    );

/// Manages floating toasts, LIFO Undo notices (`8000ms`), standard notices (`5000ms`), and persistent recovery alerts.
class FloatingNoticeController extends Notifier<FloatingNoticeViewModel?> {
  /// Standard auto-hide duration for informational and feedback toasts (`U-UX-004`).
  static const Duration standardDuration = Duration(milliseconds: 5000);

  /// Auto-hide duration for Undo recovery toasts (`U-UX-004`).
  static const Duration undoDuration = Duration(milliseconds: 8000);

  Timer? _autoHideTimer;
  int _lastUndoSequenceShown = 0;
  int _nextNoticeId = 1;

  @override
  FloatingNoticeViewModel? build() {
    ref.watch(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
    );
    _cancelTimer();
    _lastUndoSequenceShown = 0;
    ref.onDispose(_cancelTimer);

    ref.listen<TaskUndoState>(taskUndoStateProvider, (previous, next) {
      final notice = next.latestNotice;
      if (notice == null) {
        if (state?.hasUndoAction ?? false) {
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
    NoticeTone tone = NoticeTone.neutral,
    Duration? duration = standardDuration,
    bool persistent = false,
    String? actionLabel,
    int? undoSequence,
    String? shortcutHint,
  }) {
    _cancelTimer();
    final noticeId = _nextNoticeId++;
    final effectiveDuration = persistent ? null : duration;
    state = FloatingNoticeViewModel(
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
    final message = ref
        .read(settingsControllerProvider)
        .consumeStartupRecoveryNotice(locale: locale);
    if (message == null || message.isEmpty) {
      return;
    }
    showNotice(message, tone: NoticeTone.warning, persistent: true);
  }

  /// Executes the latest undoable task mutation and announces remaining Undo stack depth.
  Future<bool> undoLatest({bool fromShortcut = false, Locale? locale}) async {
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
    final applied = await ref
        .read(taskNotifierProvider.notifier)
        .undoLastAction(expectedSequence: expectedSequence);
    if (!ref.mounted) {
      return applied;
    }
    if (!applied) {
      return false;
    }

    final remaining = ref.read(taskUndoStateProvider).stackDepth;
    final localizations = lookupAppLocalizations(
      locale ?? ref.read(appLocaleProvider),
    );
    final message = remaining > 0
        ? localizations.actionUndoneRemainingNotice('$remaining')
        : localizations.actionUndoneNotice;
    showNotice(message, tone: NoticeTone.neutral);
    return true;
  }

  /// Cancels any active auto-hide timer.
  void _cancelTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  /// Formats and presents an `8000ms` floating Undo notice for [notice].
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
    showNotice(
      message,
      tone: NoticeTone.accent,
      duration: undoDuration,
      actionLabel: localizations.actionUndo,
      undoSequence: notice.sequence,
      shortcutHint: 'Ctrl+Z',
    );
  }
}
