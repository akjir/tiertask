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

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/tier_localization_extension.dart';
import '../models/location_state.dart';
import '../models/task_board.dart';
import '../models/task_board_evaluator.dart';
import '../models/task_item.dart';
import '../models/task_tier.dart';
import '../models/tdf_error.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import '../models/webdav_config.dart';
import '../providers/config_providers.dart';
import '../providers/location_providers.dart';
import '../providers/sync_providers.dart';
import '../providers/task_providers.dart';
import '../providers/workspace_providers.dart';
import 'app_shell_controller.dart';
import 'board_v2_view_models.dart';
import 'floating_notice_controller.dart';
import 'task_editor_controller.dart';
import 'ui_telemetry.dart';
import 'ui_v2_shell_models.dart';

/// Provides [TaskV2Controller] and its [TaskV2ControllerState] for model-free v2 task mutations.
final taskV2ControllerProvider =
    NotifierProvider<TaskV2Controller, TaskV2ControllerState>(
      TaskV2Controller.new,
    );

/// Immutable model-free link draft input passed from v2 UI editors into presentation controllers.
@immutable
class EntityLinkInput {
  /// Creates an [EntityLinkInput].
  const EntityLinkInput({required this.title, required this.uri});

  /// Raw link display title entered by the user.
  final String title;

  /// Raw target URI entered by the user.
  final String uri;

  /// Returns a copy of this [EntityLinkInput] with updated fields.
  EntityLinkInput copyWith({String? title, String? uri}) {
    return EntityLinkInput(title: title ?? this.title, uri: uri ?? this.uri);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EntityLinkInput && other.title == title && other.uri == uri;
  }

  @override
  int get hashCode => Object.hash(title, uri);
}

/// Immutable model-free subtask draft input passed from v2 UI editors into presentation controllers.
@immutable
class SubtaskInput {
  /// Creates a [SubtaskInput].
  const SubtaskInput({required this.title, this.isCompleted = false});

  /// Whether this subtask step is marked completed.
  final bool isCompleted;

  /// Raw subtask step title entered by the user.
  final String title;

  /// Returns a copy of this [SubtaskInput] with updated fields.
  SubtaskInput copyWith({String? title, bool? isCompleted}) {
    return SubtaskInput(
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SubtaskInput &&
        other.title == title &&
        other.isCompleted == isCompleted;
  }

  @override
  int get hashCode => Object.hash(title, isCompleted);
}

/// Immutable model-free draft payload submitted by the v2 Task Draft Card (`U-CARD-006`).
@immutable
class TaskDraftInput {
  /// Creates a [TaskDraftInput].
  TaskDraftInput({
    required this.title,
    this.note = '',
    this.placement = TaskPlacementOption.queue,
    Iterable<String> labelIds = const <String>[],
    Iterable<EntityLinkInput> links = const <EntityLinkInput>[],
    Iterable<SubtaskInput> subtasks = const <SubtaskInput>[],
    this.subtasksAutoFinish = false,
    this.rawDue = '',
    this.autoPrioritizeDue = true,
    this.rawDueNote = '',
    this.isRepeating = false,
    this.rawRepeatCount = '1',
    this.repeatUnit = ShellRepeatUnit.days,
    this.rawRepeatLeadDays = '0',
    this.isSuspended = false,
    this.suspendedIndefinitely = false,
    this.rawSuspendedUntil = '',
    this.rawSuspendedNote = '',
    Iterable<String> prerequisiteTaskIds = const <String>[],
    this.conditionDraft,
  }) : labelIds = List<String>.unmodifiable(labelIds),
       links = List<EntityLinkInput>.unmodifiable(links),
       subtasks = List<SubtaskInput>.unmodifiable(subtasks),
       prerequisiteTaskIds = List<String>.unmodifiable(prerequisiteTaskIds);

  /// Whether deadline lead-window auto-prioritization is enabled (`!isDuePassive`).
  final bool autoPrioritizeDue;

  /// Optional activation conditions draft configured on the task.
  final ConditionDraftViewModel? conditionDraft;

  /// Whether recurrence is enabled on the new task.
  final bool isRepeating;

  /// Whether deferral is enabled on the new task.
  final bool isSuspended;

  /// Assigned label identifiers.
  final List<String> labelIds;

  /// Reference links attached to the new task.
  final List<EntityLinkInput> links;

  /// Raw multi-line task note text.
  final String note;

  /// Target placement mode (`queue`, `priority`, or `someday`).
  final TaskPlacementOption placement;

  /// Selected prerequisite task identifiers.
  final List<String> prerequisiteTaskIds;

  /// Raw local due timestamp string (`YYYY-MM-DD` or `YYYY-MM-DD HH:MM`).
  final String rawDue;

  /// Raw deadline note text.
  final String rawDueNote;

  /// Raw recurrence interval count string (`1..3650`).
  final String rawRepeatCount;

  /// Raw recurrence preparation lead-days string (`0..3650`).
  final String rawRepeatLeadDays;

  /// Raw deferral note text.
  final String rawSuspendedNote;

  /// Raw local suspended-until timestamp string (`YYYY-MM-DD` or `YYYY-MM-DD HH:MM`).
  final String rawSuspendedUntil;

  /// Selected recurrence unit (`days`, `weeks`, or `months`).
  final ShellRepeatUnit repeatUnit;

  /// Draft subtasks list.
  final List<SubtaskInput> subtasks;

  /// Whether completing all subtasks automatically completes the parent task.
  final bool subtasksAutoFinish;

  /// Whether deferral is indefinite (`suspended forever`).
  final bool suspendedIndefinitely;

  /// Raw task title text.
  final String title;

  /// Returns a copy of this [TaskDraftInput] with updated fields.
  TaskDraftInput copyWith({
    String? title,
    String? note,
    TaskPlacementOption? placement,
    Iterable<String>? labelIds,
    Iterable<EntityLinkInput>? links,
    Iterable<SubtaskInput>? subtasks,
    bool? subtasksAutoFinish,
    String? rawDue,
    bool? autoPrioritizeDue,
    String? rawDueNote,
    bool? isRepeating,
    String? rawRepeatCount,
    ShellRepeatUnit? repeatUnit,
    String? rawRepeatLeadDays,
    bool? isSuspended,
    bool? suspendedIndefinitely,
    String? rawSuspendedUntil,
    String? rawSuspendedNote,
    Iterable<String>? prerequisiteTaskIds,
    ConditionDraftViewModel? conditionDraft,
    bool clearConditionDraft = false,
  }) {
    return TaskDraftInput(
      title: title ?? this.title,
      note: note ?? this.note,
      placement: placement ?? this.placement,
      labelIds: labelIds ?? this.labelIds,
      links: links ?? this.links,
      subtasks: subtasks ?? this.subtasks,
      subtasksAutoFinish: subtasksAutoFinish ?? this.subtasksAutoFinish,
      rawDue: rawDue ?? this.rawDue,
      autoPrioritizeDue: autoPrioritizeDue ?? this.autoPrioritizeDue,
      rawDueNote: rawDueNote ?? this.rawDueNote,
      isRepeating: isRepeating ?? this.isRepeating,
      rawRepeatCount: rawRepeatCount ?? this.rawRepeatCount,
      repeatUnit: repeatUnit ?? this.repeatUnit,
      rawRepeatLeadDays: rawRepeatLeadDays ?? this.rawRepeatLeadDays,
      isSuspended: isSuspended ?? this.isSuspended,
      suspendedIndefinitely:
          suspendedIndefinitely ?? this.suspendedIndefinitely,
      rawSuspendedUntil: rawSuspendedUntil ?? this.rawSuspendedUntil,
      rawSuspendedNote: rawSuspendedNote ?? this.rawSuspendedNote,
      prerequisiteTaskIds: prerequisiteTaskIds ?? this.prerequisiteTaskIds,
      conditionDraft: clearConditionDraft
          ? null
          : (conditionDraft ?? this.conditionDraft),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskDraftInput &&
        other.title == title &&
        other.note == note &&
        other.placement == placement &&
        listEquals(other.labelIds, labelIds) &&
        listEquals(other.links, links) &&
        listEquals(other.subtasks, subtasks) &&
        other.subtasksAutoFinish == subtasksAutoFinish &&
        other.rawDue == rawDue &&
        other.autoPrioritizeDue == autoPrioritizeDue &&
        other.rawDueNote == rawDueNote &&
        other.isRepeating == isRepeating &&
        other.rawRepeatCount == rawRepeatCount &&
        other.repeatUnit == repeatUnit &&
        other.rawRepeatLeadDays == rawRepeatLeadDays &&
        other.isSuspended == isSuspended &&
        other.suspendedIndefinitely == suspendedIndefinitely &&
        other.rawSuspendedUntil == rawSuspendedUntil &&
        other.rawSuspendedNote == rawSuspendedNote &&
        listEquals(other.prerequisiteTaskIds, prerequisiteTaskIds) &&
        other.conditionDraft == conditionDraft;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    title,
    note,
    placement,
    Object.hashAll(labelIds),
    Object.hashAll(links),
    Object.hashAll(subtasks),
    subtasksAutoFinish,
    rawDue,
    autoPrioritizeDue,
    rawDueNote,
    isRepeating,
    rawRepeatCount,
    repeatUnit,
    rawRepeatLeadDays,
    isSuspended,
    suspendedIndefinitely,
    rawSuspendedUntil,
    rawSuspendedNote,
    Object.hashAll(prerequisiteTaskIds),
    conditionDraft,
  ]);
}

/// Model-free v2 intent controller owning Quick-Add, Task Draft creation,
/// live task controls, single-section inline editors, and non-jumping notices.
class TaskV2Controller extends Notifier<TaskV2ControllerState> {
  int _operationToken = 0;

  /// Latest loaded [TaskBoard] snapshot, or an empty board before load completes.
  TaskBoard get _currentBoard =>
      ref.read(taskNotifierProvider).asData?.value ?? TaskBoard.empty();

  /// Active workspace [WebDavConfig] snapshot, falling back to default configuration.
  WebDavConfig get _currentConfiguration =>
      ref.read(webDavConfigProvider).asData?.value ?? const WebDavConfig();

  @override
  TaskV2ControllerState build() {
    ref.watch(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
    );
    _operationToken++;
    return const TaskV2ControllerState();
  }

  /// Appends a single-line history journal entry onto [taskId] with optional local timestamp override.
  Future<V2ActionResult> addHistoryEntry(
    String taskId, {
    required String rawText,
    String? rawTimestampOverride,
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final task = _currentBoard.findTask(taskId);
    if (task == null) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    final sanitizedText = TaskEditorController.sanitizeHistoryText(rawText);
    final textError = TaskEditorController.validateHistoryText(
      sanitizedText,
      localizations,
    );
    if (textError != null) {
      return V2ActionValidationFailed(
        message: textError,
        fieldErrors: <String, String>{'text': textError},
      );
    }
    final resolvedTimestampUtc =
        TaskEditorController.resolveHistoryTimestampUtc(
          configuration: _currentConfiguration,
          fallbackNowUtc: ref.read(clockProvider)().toUtc(),
          rawTimestamp: rawTimestampOverride ?? '',
        );
    if (resolvedTimestampUtc == null) {
      return V2ActionValidationFailed(
        message: localizations.historyErrorTimestampInvalid,
        fieldErrors: <String, String>{
          'timestamp': localizations.historyErrorTimestampInvalid,
        },
      );
    }
    final candidate = TaskHistoryEntry(
      timestampUtc: resolvedTimestampUtc,
      text: sanitizedText,
    );
    if (task.history.contains(candidate)) {
      return V2ActionValidationFailed(
        message: localizations.historyErrorDuplicate,
        fieldErrors: <String, String>{
          'text': localizations.historyErrorDuplicate,
        },
      );
    }
    if (task.history.length >= maxTdfHistoryPerTask) {
      return V2ActionValidationFailed(
        message: localizations.historyErrorMaxExceeded,
        fieldErrors: <String, String>{
          'text': localizations.historyErrorMaxExceeded,
        },
      );
    }
    return _runGuardedMutation(
      busyTaskId: taskId,
      localizations: localizations,
      action: () async {
        await ref
            .read(taskNotifierProvider.notifier)
            .addTaskHistoryEntry(
              taskId,
              timestampUtc: candidate.timestampUtc,
              text: candidate.text,
            );
        if (!ref.mounted) {
          return V2ActionSucceeded(entityId: taskId);
        }
        final postTask = _currentBoard.findTask(taskId);
        if (postTask == null || !postTask.history.contains(candidate)) {
          return V2ActionPersistFailed(
            message: _fallbackPersistError(localizations),
          );
        }
        return V2ActionSucceeded(entityId: taskId);
      },
    );
  }

  /// Clears all task-level activation conditions on [taskId].
  Future<V2ActionResult> clearConditions(
    String taskId, {
    Locale? locale,
  }) async {
    return _runInlineSectionSave(
      taskId: taskId,
      section: TaskSectionKind.conditions,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateTask(taskId, conditions: const <TaskCondition>[]),
    );
  }

  /// Clears the due timestamp, anchor, due note, and Mode 2 repeat lead days on [taskId].
  Future<V2ActionResult> clearDue(String taskId, {Locale? locale}) async {
    final localizations = _resolveLocalizations(locale);
    final task = _requireEditableTask(
      taskId: taskId,
      section: TaskSectionKind.due,
      localizations: localizations,
    );
    if (task.failure case final failure?) {
      return failure;
    }
    final existingTask = task.task;
    if (existingTask == null) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    final clearedLeadRepeat = switch (existingTask.repeatRule) {
      final existingRule? when existingRule.leadDays > 0 =>
        existingRule.copyWith(leadDays: 0),
      _ => null,
    };
    return _runInlineSectionSave(
      taskId: taskId,
      section: TaskSectionKind.due,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateTask(
            taskId,
            clearDueAt: true,
            clearDueAnchor: true,
            clearDueNote: true,
            isDuePassive: false,
            repeatRule: clearedLeadRepeat,
          ),
    );
  }

  /// Clears the body note on [taskId].
  Future<V2ActionResult> clearNote(String taskId, {Locale? locale}) {
    return _runInlineSectionSave(
      taskId: taskId,
      section: TaskSectionKind.note,
      locale: locale,
      persist: () =>
          ref.read(taskNotifierProvider.notifier).updateTask(taskId, note: ''),
    );
  }

  /// Completes an open [taskId] (with local-mutation suppression and repeat/Undo handling) or restores a completed [taskId].
  Future<V2ActionResult> completeOrRestoreTask(
    String taskId, {
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final taskBefore = _currentBoard.findTask(taskId);
    if (taskBefore == null) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    final target = EntityRef(kind: EntityKind.task, id: taskId);
    if (taskBefore.isCompleted || taskBefore.completedAt != null) {
      return _runGuardedMutation(
        busyTaskId: taskId,
        localizations: localizations,
        action: () async {
          await ref
              .read(appShellControllerProvider.notifier)
              .runLocalEntityMutation(
                target,
                () =>
                    ref.read(taskNotifierProvider.notifier).restoreTask(taskId),
              );
          if (!ref.mounted) {
            return V2ActionSucceeded(entityId: taskId);
          }
          _collapseIfExpandedAndLeftActiveView(taskId);
          final noticeMessage = localizations.taskRestoredNotice(
            taskBefore.title,
          );
          ref
              .read(floatingNoticeControllerProvider.notifier)
              .showNotice(noticeMessage);
          return V2ActionSucceeded(
            entityId: taskId,
            noticeMessage: noticeMessage,
          );
        },
      );
    }

    return _runGuardedMutation(
      busyTaskId: taskId,
      localizations: localizations,
      action: () async {
        await ref
            .read(appShellControllerProvider.notifier)
            .runLocalEntityMutation(
              target,
              () =>
                  ref.read(taskNotifierProvider.notifier).completeTask(taskId),
            );
        if (!ref.mounted) {
          return V2ActionSucceeded(entityId: taskId);
        }
        _collapseIfExpanded(target);
        if (taskBefore.repeatRule != null) {
          final repeatMessage = localizations.taskCompletedRepeatNotice(
            taskBefore.title,
          );
          ref
              .read(floatingNoticeControllerProvider.notifier)
              .showNotice(repeatMessage);
          return V2ActionSucceeded(
            entityId: taskId,
            noticeMessage: repeatMessage,
          );
        }
        return V2ActionSucceeded(entityId: taskId);
      },
    );
  }

  /// Creates a new label with rotating preset color from [rawName] and assigns it to [taskId].
  Future<V2ActionResult> createAndAssignLabel(
    String taskId,
    String rawName, {
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final boardBefore = _currentBoard;
    final taskBefore = boardBefore.findTask(taskId);
    if (taskBefore == null) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    if (taskBefore.isCompleted || taskBefore.completedAt != null) {
      return V2ActionValidationFailed(
        message: localizations.completedReadOnlyPill,
      );
    }
    final nameCheck = _validateSingleLineText(
      rawText: rawName,
      emptyError: localizations.labelNameErrorEmpty,
      invalidError: localizations.historyErrorTextInvalid,
      tooLongError: localizations.historyErrorTextTooLong,
    );
    if (nameCheck.error case final error?) {
      return V2ActionValidationFailed(
        message: error,
        fieldErrors: <String, String>{'name': error},
      );
    }
    final trimmedName = nameCheck.trimmed;
    if (boardBefore.hasDuplicateLabelName(trimmedName)) {
      return V2ActionValidationFailed(
        message: localizations.labelNameErrorDuplicate,
        fieldErrors: <String, String>{
          'name': localizations.labelNameErrorDuplicate,
        },
      );
    }
    if (taskBefore.labelIds.length >= maxTdfArgsPerStmt) {
      return V2ActionValidationFailed(
        message: localizations.errorLocalFileTooLarge,
      );
    }
    final presetHex =
        canonicalLabelPresetHexColors[boardBefore.labels.length %
            canonicalLabelPresetHexColors.length];
    final beforeLabelIds = <String>{
      for (final label in boardBefore.labels) label.id,
    };
    final target = EntityRef(kind: EntityKind.task, id: taskId);

    return _runGuardedMutation(
      busyTaskId: taskId,
      localizations: localizations,
      action: () async {
        await ref
            .read(taskNotifierProvider.notifier)
            .addLabel(trimmedName, color: presetHex);
        if (!ref.mounted) {
          return V2ActionSucceeded(entityId: taskId);
        }
        final boardWithLabel = _currentBoard;
        final createdLabel = _findCreatedLabel(
          board: boardWithLabel,
          beforeIds: beforeLabelIds,
          trimmedName: trimmedName,
        );
        if (createdLabel == null) {
          return V2ActionPersistFailed(
            message: _fallbackPersistError(localizations),
          );
        }
        final liveTask = boardWithLabel.findTask(taskId);
        if (liveTask == null) {
          return V2ActionPersistFailed(
            message: localizations.entityRemovedExternallyNotice,
          );
        }
        final nextLabelIds = TaskEditorController.collectOrderedLabelIds(
          boardWithLabel,
          <String>{...liveTask.labelIds, createdLabel.id},
        );
        await ref
            .read(appShellControllerProvider.notifier)
            .runLocalEntityMutation(
              target,
              () => ref
                  .read(taskNotifierProvider.notifier)
                  .updateTask(taskId, labelIds: nextLabelIds),
            );
        if (!ref.mounted) {
          return V2ActionSucceeded(entityId: createdLabel.id);
        }
        final noticeMessage = localizations.noticeLabelCreatedAndAssigned(
          createdLabel.name,
        );
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(noticeMessage);
        return V2ActionSucceeded(
          entityId: createdLabel.id,
          noticeMessage: noticeMessage,
        );
      },
    );
  }

  /// Validates and commits a full [TaskDraftInput], closes the draft card, logs telemetry, and emits a non-jumping placement toast.
  Future<V2ActionResult> createTaskDraft(
    TaskDraftInput input, {
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final boardBefore = _currentBoard;
    final configuration = _currentConfiguration;
    final validation = _validateTaskDraft(
      input: input,
      board: boardBefore,
      configuration: configuration,
      localizations: localizations,
    );
    if (validation.fieldErrors.isNotEmpty) {
      return V2ActionValidationFailed(
        message: validation.fieldErrors.values.first,
        fieldErrors: validation.fieldErrors,
      );
    }

    final beforeTaskIds = <String>{
      for (final task in boardBefore.allTasks) task.id,
    };
    final placementTarget = _resolvePlacementTarget(input.placement);

    return _runGuardedMutation(
      localizations: localizations,
      action: () async {
        await ref
            .read(taskNotifierProvider.notifier)
            .addTask(
              validation.trimmedTitle,
              note: validation.normalizedNote,
              targetTier: placementTarget.targetTier,
              isPriority: placementTarget.isPriority,
              subtasksAutoFinish: input.subtasksAutoFinish,
              subtasks: validation.subtasks,
              labelIds: validation.labelIds,
              dueLocalInput: validation.dueLocalInput,
              isDuePassive: validation.hasDue && !input.autoPrioritizeDue,
              dueNote: validation.dueNote,
              suspendedLocalInput: validation.suspendedLocalInput,
              isSuspendedForever: validation.isSuspendedForever,
              suspendedNote: validation.suspendedNote,
              repeatRule: validation.repeatRule,
              blockedByTaskIds: validation.prerequisiteIds,
              links: validation.links,
              conditions: validation.conditions,
            );
        if (!ref.mounted) {
          return const V2ActionSucceeded();
        }
        final boardAfter = _currentBoard;
        final createdTask = _findCreatedTask(
          board: boardAfter,
          beforeIds: beforeTaskIds,
          trimmedTitle: validation.trimmedTitle,
        );
        if (createdTask == null) {
          return V2ActionPersistFailed(
            message: _fallbackPersistError(localizations),
          );
        }
        ref.read(appShellControllerProvider.notifier).cancelDraft();
        UiTelemetry.logEntityDraftCommitted('task');
        final noticeMessage = _resolveTaskPlacementNotice(
          board: boardAfter,
          task: createdTask,
          localizations: localizations,
        );
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(noticeMessage);
        return V2ActionSucceeded(
          entityId: createdTask.id,
          noticeMessage: noticeMessage,
        );
      },
    );
  }

  /// Removes a specific `(timestampUtcIso, text)` history journal entry from [taskId].
  Future<V2ActionResult> deleteHistoryEntry(
    String taskId, {
    required String timestampUtcIso,
    required String text,
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final task = _currentBoard.findTask(taskId);
    if (task == null) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    final timestampUtc = DateTime.tryParse(timestampUtcIso)?.toUtc();
    if (timestampUtc == null) {
      return V2ActionValidationFailed(
        message: localizations.historyErrorTimestampInvalid,
      );
    }
    return _runGuardedMutation(
      busyTaskId: taskId,
      localizations: localizations,
      action: () async {
        await ref
            .read(taskNotifierProvider.notifier)
            .removeTaskHistoryEntry(
              taskId,
              timestampUtc: timestampUtc,
              text: text,
            );
        return V2ActionSucceeded(entityId: taskId);
      },
    );
  }

  /// Deletes [taskId] with local-mutation suppression, collapses its card, and clears delete confirmation.
  Future<V2ActionResult> deleteTask(String taskId, {Locale? locale}) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    if (_currentBoard.findTask(taskId) == null) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    final target = EntityRef(kind: EntityKind.task, id: taskId);
    return _runGuardedMutation(
      busyTaskId: taskId,
      localizations: localizations,
      action: () async {
        await ref
            .read(appShellControllerProvider.notifier)
            .runLocalEntityMutation(
              target,
              () => ref.read(taskNotifierProvider.notifier).deleteTask(taskId),
            );
        if (!ref.mounted) {
          return V2ActionSucceeded(entityId: taskId);
        }
        final shellState = ref.read(appShellControllerProvider);
        if (shellState.expandedEntity == target ||
            shellState.activeDeleteConfirm == target) {
          ref.read(appShellControllerProvider.notifier).collapseEntity();
        }
        return V2ActionSucceeded(entityId: taskId);
      },
    );
  }

  /// Disables recurrence on [taskId].
  Future<V2ActionResult> disableRepeat(String taskId, {Locale? locale}) {
    return _runInlineSectionSave(
      taskId: taskId,
      section: TaskSectionKind.repeat,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateTask(taskId, clearRepeatRule: true),
    );
  }

  /// Downgrades active [taskId] under the active sidebar label filter.
  Future<V2ActionResult> downgradeTask(String taskId, {Locale? locale}) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    if (_currentBoard.findTask(taskId) == null) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    final activeLabelId = ref.read(appShellControllerProvider).activeLabelId;
    final target = EntityRef(kind: EntityKind.task, id: taskId);
    return _runGuardedMutation(
      busyTaskId: taskId,
      localizations: localizations,
      action: () async {
        await ref
            .read(appShellControllerProvider.notifier)
            .runLocalEntityMutation(
              target,
              () => ref
                  .read(taskNotifierProvider.notifier)
                  .downgradeTask(taskId, activeFilterLabelId: activeLabelId),
            );
        if (!ref.mounted) {
          return V2ActionSucceeded(entityId: taskId);
        }
        _collapseIfExpandedAndLeftActiveView(taskId);
        return V2ActionSucceeded(entityId: taskId);
      },
    );
  }

  /// Validates and creates a task from the docked Quick-Add composer without switching tiers, scrolling, or expanding (`U-CARD-006`).
  Future<V2ActionResult> quickAddTask({
    required String rawTitle,
    required TaskPlacementOption placement,
    required List<String> labelIds,
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final boardBefore = _currentBoard;
    final titleCheck = _validateSingleLineText(
      rawText: rawTitle,
      emptyError: localizations.taskNameErrorEmpty,
      invalidError: localizations.historyErrorTextInvalid,
      tooLongError: localizations.historyErrorTextTooLong,
    );
    if (titleCheck.error case final error?) {
      return V2ActionValidationFailed(
        message: error,
        fieldErrors: <String, String>{'title': error},
      );
    }
    final trimmedTitle = titleCheck.trimmed;
    final duplicateError = TaskEditorController.validateTaskTitle(
      board: boardBefore,
      rawTitle: trimmedTitle,
      excludingTaskId: null,
      localizations: localizations,
    );
    if (duplicateError != null) {
      if (duplicateError == localizations.taskNameErrorDuplicate) {
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(duplicateError, tone: NoticeTone.danger);
      }
      return V2ActionValidationFailed(
        message: duplicateError,
        fieldErrors: <String, String>{'title': duplicateError},
      );
    }

    final orderedLabelIds = TaskEditorController.collectOrderedLabelIds(
      boardBefore,
      labelIds.toSet(),
    );
    final placementTarget = _resolvePlacementTarget(placement);
    final beforeTaskIds = <String>{
      for (final task in boardBefore.allTasks) task.id,
    };

    return _runGuardedMutation(
      localizations: localizations,
      action: () async {
        await ref
            .read(taskNotifierProvider.notifier)
            .addTask(
              trimmedTitle,
              targetTier: placementTarget.targetTier,
              isPriority: placementTarget.isPriority,
              labelIds: orderedLabelIds,
            );
        if (!ref.mounted) {
          return const V2ActionSucceeded();
        }
        final boardAfter = _currentBoard;
        final createdTask = _findCreatedTask(
          board: boardAfter,
          beforeIds: beforeTaskIds,
          trimmedTitle: trimmedTitle,
        );
        if (createdTask == null) {
          return V2ActionPersistFailed(
            message: _fallbackPersistError(localizations),
          );
        }
        final noticeMessage = _resolveTaskPlacementNotice(
          board: boardAfter,
          task: createdTask,
          localizations: localizations,
        );
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(noticeMessage);
        return V2ActionSucceeded(
          entityId: createdTask.id,
          noticeMessage: noticeMessage,
        );
      },
    );
  }

  /// Clears finite or indefinite suspension and its deferral note on [taskId].
  Future<V2ActionResult> resumeTask(String taskId, {Locale? locale}) {
    return _runInlineSectionSave(
      taskId: taskId,
      section: TaskSectionKind.suspended,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateTask(
            taskId,
            clearSuspendedAt: true,
            clearSuspendedNote: true,
            isSuspendedForever: false,
          ),
    );
  }

  /// Compiles, validates, and saves activation conditions from [draft] onto [taskId].
  Future<V2ActionResult> saveConditions(
    String taskId,
    ConditionDraftViewModel draft, {
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    final checked = _requireEditableTask(
      taskId: taskId,
      section: TaskSectionKind.conditions,
      localizations: localizations,
    );
    if (checked.failure case final failure?) {
      return failure;
    }
    final compiled = _compileConditionDraft(
      draft: draft,
      board: _currentBoard,
      localizations: localizations,
    );
    if (compiled.error case final error?) {
      UiTelemetry.logInlineEditFailed(
        kind: 'task',
        entityId: taskId,
        section: TaskSectionKind.conditions.name,
      );
      return V2ActionValidationFailed(
        message: error,
        fieldErrors: <String, String>{'conditions': error},
      );
    }
    return _runInlineSectionSave(
      taskId: taskId,
      section: TaskSectionKind.conditions,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateTask(taskId, conditions: compiled.conditions),
    );
  }

  /// Validates and saves deadline timestamp, auto-priority flag, and deadline note onto [taskId].
  Future<V2ActionResult> saveDue(
    String taskId, {
    required String rawDue,
    required bool autoPrioritize,
    required String rawDueNote,
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    final checked = _requireEditableTask(
      taskId: taskId,
      section: TaskSectionKind.due,
      localizations: localizations,
    );
    if (checked.failure case final failure?) {
      return failure;
    }
    final existingTask = checked.task;
    if (existingTask == null) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    final configuration = _currentConfiguration;
    final initialDueText = existingTask.dueAt != null
        ? TaskEditorController.formatLocalTimestamp(
            existingTask.dueAt,
            configuration,
          )
        : '';
    final fieldErrors = <String, String>{};
    final dueDraft = rawDue.trim().isEmpty
        ? const ResolvedDueDraft(
            dueAt: null,
            dueLocalInput: null,
            dueAnchor: null,
            isUnchanged: false,
            isValid: false,
          )
        : ref
              .read(taskEditorControllerProvider)
              .resolveDueDraft(
                configuration: configuration,
                hasDue: true,
                rawDueText: rawDue,
                initialDueAt: existingTask.dueAt,
                initialDueAnchor: existingTask.dueAnchor,
                initialDueText: initialDueText,
              );
    if (!dueDraft.isValid) {
      fieldErrors['due'] = localizations.taskSuspendedErrorInvalid;
    }
    final normalizedDueNote = TaskEditorController.normalizeSchedulingNote(
      rawDueNote,
    );
    final dueNoteError = TaskEditorController.validateSchedulingNote(
      normalizedDueNote,
      localizations,
    );
    if (dueNoteError != null) {
      fieldErrors['dueNote'] = dueNoteError;
    }
    if (fieldErrors.isNotEmpty) {
      UiTelemetry.logInlineEditFailed(
        kind: 'task',
        entityId: taskId,
        section: TaskSectionKind.due.name,
      );
      return V2ActionValidationFailed(
        message: fieldErrors.values.first,
        fieldErrors: fieldErrors,
      );
    }
    return _runInlineSectionSave(
      taskId: taskId,
      section: TaskSectionKind.due,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateTask(
            taskId,
            dueAt: dueDraft.dueLocalInput == null ? dueDraft.dueAt : null,
            dueLocalInput: dueDraft.dueLocalInput,
            dueAnchor: dueDraft.dueLocalInput == null
                ? dueDraft.dueAnchor
                : null,
            isDuePassive: !autoPrioritize,
            dueNote: normalizedDueNote,
            clearDueAt: false,
            clearDueAnchor:
                dueDraft.dueLocalInput == null && dueDraft.dueAnchor == null,
            clearDueNote: normalizedDueNote == null,
          ),
    );
  }

  /// Validates and saves the reference [links] list onto [taskId].
  Future<V2ActionResult> saveLinks(
    String taskId,
    List<EntityLinkInput> links, {
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    final checked = _requireEditableTask(
      taskId: taskId,
      section: TaskSectionKind.links,
      localizations: localizations,
    );
    if (checked.failure case final failure?) {
      return failure;
    }
    final validated = _validateLinksList(
      links: links,
      localizations: localizations,
    );
    if (validated.error case final error?) {
      UiTelemetry.logInlineEditFailed(
        kind: 'task',
        entityId: taskId,
        section: TaskSectionKind.links.name,
      );
      return V2ActionValidationFailed(
        message: error,
        fieldErrors: <String, String>{'links': error},
      );
    }
    return _runInlineSectionSave(
      taskId: taskId,
      section: TaskSectionKind.links,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateTask(taskId, links: validated.links),
    );
  }

  /// Validates and saves the multi-line body note onto [taskId].
  Future<V2ActionResult> saveNote(
    String taskId,
    String rawNote, {
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    final checked = _requireEditableTask(
      taskId: taskId,
      section: TaskSectionKind.note,
      localizations: localizations,
    );
    if (checked.failure case final failure?) {
      return failure;
    }
    final normalizedNote = TaskEditorController.normalizeSchedulingNote(
      rawNote,
    );
    final noteError = TaskEditorController.validateSchedulingNote(
      normalizedNote,
      localizations,
    );
    if (noteError != null) {
      UiTelemetry.logInlineEditFailed(
        kind: 'task',
        entityId: taskId,
        section: TaskSectionKind.note.name,
      );
      return V2ActionValidationFailed(
        message: noteError,
        fieldErrors: <String, String>{'note': noteError},
      );
    }
    return _runInlineSectionSave(
      taskId: taskId,
      section: TaskSectionKind.note,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateTask(taskId, note: normalizedNote ?? ''),
    );
  }

  /// Validates prerequisite dependencies against self/transitive cycles and statement bounds, then saves onto [taskId].
  Future<V2ActionResult> savePrerequisites(
    String taskId,
    List<String> prerequisiteTaskIds, {
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    final checked = _requireEditableTask(
      taskId: taskId,
      section: TaskSectionKind.prerequisites,
      localizations: localizations,
    );
    if (checked.failure case final failure?) {
      return failure;
    }
    final board = _currentBoard;
    final selectedIds = <String>{};
    for (final rawId in prerequisiteTaskIds) {
      final candidateId = rawId.trim();
      if (candidateId.isEmpty) {
        continue;
      }
      if (candidateId == taskId ||
          board.wouldCreateDependencyCycle(taskId, candidateId)) {
        UiTelemetry.logInlineEditFailed(
          kind: 'task',
          entityId: taskId,
          section: TaskSectionKind.prerequisites.name,
        );
        return V2ActionValidationFailed(
          message: localizations.prerequisiteCyclePreventedHint,
          fieldErrors: <String, String>{
            'prerequisites': localizations.prerequisiteCyclePreventedHint,
          },
        );
      }
      selectedIds.add(candidateId);
    }
    final orderedIds = TaskEditorController.collectOrderedBlockedByIds(
      board,
      selectedIds,
    );
    if (orderedIds.length > maxTdfArgsPerStmt) {
      UiTelemetry.logInlineEditFailed(
        kind: 'task',
        entityId: taskId,
        section: TaskSectionKind.prerequisites.name,
      );
      return V2ActionValidationFailed(
        message: localizations.errorLocalFileTooLarge,
        fieldErrors: <String, String>{
          'prerequisites': localizations.errorLocalFileTooLarge,
        },
      );
    }
    return _runInlineSectionSave(
      taskId: taskId,
      section: TaskSectionKind.prerequisites,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateTask(taskId, blockedByTaskIds: orderedIds),
    );
  }

  /// Validates recurrence count (`1..3650`) and Mode 2 lead days (`0..3650`) and saves onto [taskId].
  Future<V2ActionResult> saveRepeat(
    String taskId, {
    required String rawCount,
    required ShellRepeatUnit unit,
    required String rawLeadDays,
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    final checked = _requireEditableTask(
      taskId: taskId,
      section: TaskSectionKind.repeat,
      localizations: localizations,
    );
    if (checked.failure case final failure?) {
      return failure;
    }
    final existingTask = checked.task;
    if (existingTask == null) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    final hasDue = existingTask.dueAt != null;
    final parsedCount = TaskEditorController.parseRepeatCount(
      isRepeating: true,
      rawCount: rawCount,
    );
    final parsedLeadDays = TaskEditorController.parseLeadDays(
      hasDue: hasDue,
      isRepeating: true,
      rawLeadDays: rawLeadDays,
    );
    final fieldErrors = <String, String>{};
    if (parsedCount == null) {
      fieldErrors['repeatCount'] = localizations.repeatErrorInvalid;
    }
    if (parsedLeadDays == null) {
      fieldErrors['repeatLeadDays'] = localizations.repeatLeadDaysErrorInvalid;
    }
    if (fieldErrors.isNotEmpty ||
        parsedCount == null ||
        parsedLeadDays == null) {
      UiTelemetry.logInlineEditFailed(
        kind: 'task',
        entityId: taskId,
        section: TaskSectionKind.repeat.name,
      );
      return V2ActionValidationFailed(
        message: fieldErrors.values.first,
        fieldErrors: fieldErrors,
      );
    }
    final nextRule = TaskRepeatRule(
      count: parsedCount,
      unit: _toRepeatUnit(unit),
      clock: existingTask.repeatRule?.clock ?? TdfRepeatClock.midnight,
      leadDays: parsedLeadDays,
    );
    return _runInlineSectionSave(
      taskId: taskId,
      section: TaskSectionKind.repeat,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateTask(taskId, repeatRule: nextRule, clearRepeatRule: false),
    );
  }

  /// Strips blanks, enforces `1024`/`500` subtask bounds, saves onto [taskId], and auto-finishes via `completeTask` when all remaining steps are complete.
  Future<V2ActionResult> saveSubtasks(
    String taskId,
    List<SubtaskInput> subtasks, {
    required bool autoFinish,
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    final checked = _requireEditableTask(
      taskId: taskId,
      section: TaskSectionKind.subtasks,
      localizations: localizations,
    );
    if (checked.failure case final failure?) {
      return failure;
    }
    final existingTask = checked.task;
    if (existingTask == null) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    final validated = _validateSubtasksList(
      subtasks: subtasks,
      localizations: localizations,
    );
    if (validated.error case final error?) {
      UiTelemetry.logInlineEditFailed(
        kind: 'task',
        entityId: taskId,
        section: TaskSectionKind.subtasks.name,
      );
      return V2ActionValidationFailed(
        message: error,
        fieldErrors: <String, String>{'subtasks': error},
      );
    }
    final steps = validated.subtasks;
    final triggersAutoFinish =
        autoFinish &&
        steps.isNotEmpty &&
        steps.every((step) => step.isCompleted);
    if (!triggersAutoFinish) {
      return _runInlineSectionSave(
        taskId: taskId,
        section: TaskSectionKind.subtasks,
        locale: locale,
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateTask(
              taskId,
              subtasks: steps,
              subtasksAutoFinish: autoFinish,
            ),
      );
    }

    final target = EntityRef(kind: EntityKind.task, id: taskId);
    final stagedSteps = <SubtaskItem>[
      for (var i = 0; i < steps.length; i++)
        i == steps.length - 1
            ? steps[i].copyWith(isCompleted: false)
            : steps[i],
    ];
    return _runGuardedMutation(
      busyTaskId: taskId,
      localizations: localizations,
      onPersistFailure: () {
        UiTelemetry.logInlineEditFailed(
          kind: 'task',
          entityId: taskId,
          section: TaskSectionKind.subtasks.name,
        );
      },
      action: () async {
        await ref
            .read(appShellControllerProvider.notifier)
            .runLocalEntityMutation(target, () async {
              final notifier = ref.read(taskNotifierProvider.notifier);
              await notifier.updateTask(
                taskId,
                subtasks: stagedSteps,
                subtasksAutoFinish: true,
              );
              await notifier.completeTask(taskId);
            });
        if (!ref.mounted) {
          return V2ActionSucceeded(entityId: taskId);
        }
        UiTelemetry.logInlineEditSaved(
          kind: 'task',
          entityId: taskId,
          section: TaskSectionKind.subtasks.name,
        );
        _collapseIfExpanded(target);
        if (existingTask.repeatRule != null) {
          final repeatNotice = localizations.taskCompletedRepeatNotice(
            existingTask.title,
          );
          ref
              .read(floatingNoticeControllerProvider.notifier)
              .showNotice(repeatNotice);
          return V2ActionSucceeded(
            entityId: taskId,
            noticeMessage: repeatNotice,
          );
        }
        return V2ActionSucceeded(entityId: taskId);
      },
    );
  }

  /// Validates finite or indefinite deferral settings and deferral note, then saves onto [taskId].
  Future<V2ActionResult> saveSuspended(
    String taskId, {
    required bool indefinitely,
    required String rawUntil,
    required String rawNote,
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    final checked = _requireEditableTask(
      taskId: taskId,
      section: TaskSectionKind.suspended,
      localizations: localizations,
    );
    if (checked.failure case final failure?) {
      return failure;
    }
    final existingTask = checked.task;
    if (existingTask == null) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    final configuration = _currentConfiguration;
    final fieldErrors = <String, String>{};
    final suspendedDraft = _resolveSuspendedInput(
      indefinitely: indefinitely,
      rawUntil: rawUntil,
      existingTask: existingTask,
      configuration: configuration,
    );
    if (!indefinitely &&
        (!suspendedDraft.isValid || suspendedDraft.isForever)) {
      fieldErrors['suspended'] = localizations.taskSuspendedErrorInvalid;
    }
    final normalizedNote = TaskEditorController.normalizeSchedulingNote(
      rawNote,
    );
    final noteError = TaskEditorController.validateSchedulingNote(
      normalizedNote,
      localizations,
    );
    if (noteError != null) {
      fieldErrors['suspendedNote'] = noteError;
    }
    if (fieldErrors.isNotEmpty) {
      UiTelemetry.logInlineEditFailed(
        kind: 'task',
        entityId: taskId,
        section: TaskSectionKind.suspended.name,
      );
      return V2ActionValidationFailed(
        message: fieldErrors.values.first,
        fieldErrors: fieldErrors,
      );
    }
    return _runInlineSectionSave(
      taskId: taskId,
      section: TaskSectionKind.suspended,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateTask(
            taskId,
            suspendedAt: indefinitely ? null : suspendedDraft.suspendedAt,
            suspendedLocalInput: indefinitely
                ? null
                : suspendedDraft.suspendedLocalInput,
            isSuspendedForever: indefinitely,
            suspendedNote: normalizedNote,
            clearSuspendedAt: false,
            clearSuspendedNote: normalizedNote == null,
          ),
    );
  }

  /// Validates single-line `<text>` rules and duplicate uniqueness, then saves [rawTitle] onto [taskId].
  Future<V2ActionResult> saveTitle(
    String taskId,
    String rawTitle, {
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    final checked = _requireEditableTask(
      taskId: taskId,
      section: TaskSectionKind.title,
      localizations: localizations,
    );
    if (checked.failure case final failure?) {
      return failure;
    }
    final titleCheck = _validateSingleLineText(
      rawText: rawTitle,
      emptyError: localizations.taskNameErrorEmpty,
      invalidError: localizations.historyErrorTextInvalid,
      tooLongError: localizations.historyErrorTextTooLong,
    );
    final titleError =
        titleCheck.error ??
        TaskEditorController.validateTaskTitle(
          board: _currentBoard,
          rawTitle: titleCheck.trimmed,
          excludingTaskId: taskId,
          localizations: localizations,
        );
    if (titleError != null) {
      UiTelemetry.logInlineEditFailed(
        kind: 'task',
        entityId: taskId,
        section: TaskSectionKind.title.name,
      );
      return V2ActionValidationFailed(
        message: titleError,
        fieldErrors: <String, String>{'title': titleError},
      );
    }
    return _runInlineSectionSave(
      taskId: taskId,
      section: TaskSectionKind.title,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateTask(taskId, title: titleCheck.trimmed),
    );
  }

  /// Switches active [taskId] placement between `queue`, `priority`, and `someday`, collapsing if it moved tiers.
  Future<V2ActionResult> setPlacement(
    String taskId,
    TaskPlacementOption placement, {
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final boardBefore = _currentBoard;
    final taskBefore = boardBefore.findTask(taskId);
    if (taskBefore == null) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    if (taskBefore.isCompleted || taskBefore.completedAt != null) {
      return V2ActionValidationFailed(
        message: localizations.completedReadOnlyPill,
      );
    }
    final shellBefore = ref.read(appShellControllerProvider);
    final tierBefore = _evaluateBoardForShell(
      boardBefore,
      shellBefore.activeLabelId,
    ).findTierOfTask(taskId);
    final wasQueued = boardBefore.queueBlock.taskIds.contains(taskId);
    final wasPriority = taskBefore.isPriority;
    final placementTarget = _resolvePlacementTarget(placement);
    final target = EntityRef(kind: EntityKind.task, id: taskId);

    return _runGuardedMutation(
      busyTaskId: taskId,
      localizations: localizations,
      action: () async {
        await ref
            .read(appShellControllerProvider.notifier)
            .runLocalEntityMutation(
              target,
              () => ref
                  .read(taskNotifierProvider.notifier)
                  .updateTask(
                    taskId,
                    targetTier: placementTarget.targetTier,
                    isPriority: placementTarget.isPriority,
                  ),
            );
        if (!ref.mounted) {
          return V2ActionSucceeded(entityId: taskId);
        }
        final shellAfter = ref.read(appShellControllerProvider);
        final tierAfter = _evaluateBoardForShell(
          _currentBoard,
          shellAfter.activeLabelId,
        ).findTierOfTask(taskId);
        if (tierAfter != tierBefore && !shellAfter.searchOpen) {
          _collapseIfExpanded(target);
        }
        final noticeMessage = _resolvePlacementToggleNotice(
          placement: placement,
          wasQueued: wasQueued,
          wasPriority: wasPriority,
          tierAfter: tierAfter,
          activeTier: shellAfter.activeTier,
          localizations: localizations,
        );
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(noticeMessage);
        return V2ActionSucceeded(
          entityId: taskId,
          noticeMessage: noticeMessage,
        );
      },
    );
  }

  /// Adds or removes [labelId] on [taskId], collapses if the task left the active view/tier, and emits a contextual toast.
  Future<V2ActionResult> toggleLabel(
    String taskId,
    String labelId, {
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final boardBefore = _currentBoard;
    final taskBefore = boardBefore.findTask(taskId);
    final label = boardBefore.findLabel(labelId);
    if (taskBefore == null || label == null) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    if (taskBefore.isCompleted || taskBefore.completedAt != null) {
      return V2ActionValidationFailed(
        message: localizations.completedReadOnlyPill,
      );
    }
    final isRemoving = taskBefore.labelIds.contains(labelId);
    final nextSet = taskBefore.labelIds.toSet();
    if (isRemoving) {
      nextSet.remove(labelId);
    } else {
      nextSet.add(labelId);
    }
    final nextLabelIds = TaskEditorController.collectOrderedLabelIds(
      boardBefore,
      nextSet,
    );
    if (nextLabelIds.length > maxTdfArgsPerStmt) {
      return V2ActionValidationFailed(
        message: localizations.errorLocalFileTooLarge,
      );
    }
    final shellBefore = ref.read(appShellControllerProvider);
    final tierBefore = _evaluateBoardForShell(
      boardBefore,
      shellBefore.activeLabelId,
    ).findTierOfTask(taskId);
    final target = EntityRef(kind: EntityKind.task, id: taskId);

    return _runGuardedMutation(
      busyTaskId: taskId,
      localizations: localizations,
      action: () async {
        await ref
            .read(appShellControllerProvider.notifier)
            .runLocalEntityMutation(
              target,
              () => ref
                  .read(taskNotifierProvider.notifier)
                  .updateTask(taskId, labelIds: nextLabelIds),
            );
        if (!ref.mounted) {
          return V2ActionSucceeded(entityId: taskId);
        }
        final boardAfter = _currentBoard;
        final taskAfter = boardAfter.findTask(taskId);
        final shellAfter = ref.read(appShellControllerProvider);
        final tierAfter = _evaluateBoardForShell(
          boardAfter,
          shellAfter.activeLabelId,
        ).findTierOfTask(taskId);
        final leftCurrentView =
            tierAfter == null ||
            (!shellAfter.searchOpen &&
                tierAfter != _toTaskTier(shellAfter.activeTier));
        if (leftCurrentView) {
          _collapseIfExpanded(target);
        }
        final labelMapAfter = <String, TdfLabel>{
          for (final existingLabel in boardAfter.labels)
            existingLabel.id: existingLabel,
        };
        final restrictingScopedName = taskAfter != null
            ? _findRestrictingScopedLabelName(
                task: taskAfter,
                labelMap: labelMapAfter,
                activeLabelId: shellAfter.activeLabelId,
              )
            : null;
        final noticeMessage =
            (restrictingScopedName != null &&
                tierBefore != null &&
                tierAfter == null)
            ? localizations.noticeTaskMovedToScopedQueue(restrictingScopedName)
            : (isRemoving
                  ? localizations.noticeLabelRemoved(label.name)
                  : localizations.noticeLabelAdded(label.name));
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(noticeMessage);
        return V2ActionSucceeded(
          entityId: taskId,
          noticeMessage: noticeMessage,
        );
      },
    );
  }

  /// Toggles subtask step [stepIndex] on [taskId] inside `runLocalEntityMutation`, collapsing on auto-finish completion.
  Future<V2ActionResult> toggleSubtask(
    String taskId,
    int stepIndex, {
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final taskBefore = _currentBoard.findTask(taskId);
    if (taskBefore == null) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    if (taskBefore.isCompleted || taskBefore.completedAt != null) {
      return V2ActionValidationFailed(
        message: localizations.completedReadOnlyPill,
      );
    }
    if (stepIndex < 0 || stepIndex >= taskBefore.subtasks.length) {
      return V2ActionValidationFailed(
        message: localizations.historyErrorTextInvalid,
      );
    }
    final target = EntityRef(kind: EntityKind.task, id: taskId);
    return _runGuardedMutation(
      busyTaskId: taskId,
      localizations: localizations,
      action: () async {
        await ref
            .read(appShellControllerProvider.notifier)
            .runLocalEntityMutation(
              target,
              () => ref
                  .read(taskNotifierProvider.notifier)
                  .toggleSubtask(taskId, stepIndex),
            );
        if (!ref.mounted) {
          return V2ActionSucceeded(entityId: taskId);
        }
        final taskAfter = _currentBoard.findTask(taskId);
        final didAutoComplete =
            taskAfter != null &&
            (taskAfter.completions > taskBefore.completions ||
                (!taskBefore.isCompleted && taskAfter.isCompleted));
        if (didAutoComplete) {
          _collapseIfExpanded(target);
          if (taskBefore.repeatRule != null) {
            final repeatNotice = localizations.taskCompletedRepeatNotice(
              taskBefore.title,
            );
            ref
                .read(floatingNoticeControllerProvider.notifier)
                .showNotice(repeatNotice);
            return V2ActionSucceeded(
              entityId: taskId,
              noticeMessage: repeatNotice,
            );
          }
        }
        return V2ActionSucceeded(entityId: taskId);
      },
    );
  }

  /// Validates and replaces an existing `(oldTimestampUtcIso, oldText)` history entry on [taskId], rejecting duplicates.
  Future<V2ActionResult> updateHistoryEntry(
    String taskId, {
    required String oldTimestampUtcIso,
    required String oldText,
    required String rawNewText,
    required String rawNewTimestamp,
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final task = _currentBoard.findTask(taskId);
    if (task == null) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    final oldTimestampUtc = DateTime.tryParse(oldTimestampUtcIso)?.toUtc();
    if (oldTimestampUtc == null) {
      return V2ActionValidationFailed(
        message: localizations.historyErrorTimestampInvalid,
      );
    }
    final oldEntry = TaskHistoryEntry(
      timestampUtc: oldTimestampUtc,
      text: oldText,
    );
    if (!task.history.contains(oldEntry)) {
      return V2ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    final sanitizedText = TaskEditorController.sanitizeHistoryText(rawNewText);
    final textError = TaskEditorController.validateHistoryText(
      sanitizedText,
      localizations,
    );
    if (textError != null) {
      return V2ActionValidationFailed(
        message: textError,
        fieldErrors: <String, String>{'text': textError},
      );
    }
    final configuration = _currentConfiguration;
    final preservedLocalText = TaskEditorController.formatLocalTimestamp(
      oldEntry.timestampUtc,
      configuration,
    );
    final newTimestampUtc = TaskEditorController.resolveHistoryTimestampUtc(
      configuration: configuration,
      fallbackNowUtc: ref.read(clockProvider)().toUtc(),
      preservedTimestampText: preservedLocalText,
      preservedTimestampUtc: oldEntry.timestampUtc,
      rawTimestamp: rawNewTimestamp,
    );
    if (newTimestampUtc == null) {
      return V2ActionValidationFailed(
        message: localizations.historyErrorTimestampInvalid,
        fieldErrors: <String, String>{
          'timestamp': localizations.historyErrorTimestampInvalid,
        },
      );
    }
    final replacement = TaskHistoryEntry(
      timestampUtc: newTimestampUtc,
      text: sanitizedText,
    );
    if (replacement == oldEntry) {
      return V2ActionSucceeded(entityId: taskId);
    }
    if (task.history.contains(replacement)) {
      return V2ActionValidationFailed(
        message: localizations.historyErrorDuplicate,
        fieldErrors: <String, String>{
          'text': localizations.historyErrorDuplicate,
        },
      );
    }
    return _runGuardedMutation(
      busyTaskId: taskId,
      localizations: localizations,
      action: () async {
        await ref
            .read(taskNotifierProvider.notifier)
            .updateTaskHistoryEntry(
              taskId,
              oldTimestampUtc: oldEntry.timestampUtc,
              oldText: oldEntry.text,
              newTimestampUtc: replacement.timestampUtc,
              newText: replacement.text,
            );
        if (!ref.mounted) {
          return V2ActionSucceeded(entityId: taskId);
        }
        final syncState = ref.read(syncStateProvider);
        if (syncState.errorMessage != null || syncState.hasOpenConflict) {
          return V2ActionPersistFailed(
            message: _fallbackPersistError(localizations),
          );
        }
        return V2ActionSucceeded(entityId: taskId);
      },
    );
  }

  /// Pure static validator for a single task or label reference link input against TDF `0.8.0` bounds.
  static String? validateLinkInput({
    required String rawTitle,
    required String rawUri,
    required int currentCount,
    required bool isEditingExisting,
    required bool isLabel,
    Locale? locale,
  }) {
    final localizations = lookupAppLocalizations(locale ?? const Locale('en'));
    final maxLinks = isLabel ? maxTdfLinksPerLabel : maxTdfLinksPerTask;
    if (!isEditingExisting && currentCount >= maxLinks) {
      return isLabel
          ? localizations.labelLinkErrorMaxExceeded
          : localizations.linkErrorMaxExceeded;
    }
    final parsed = TaskLink.tryParse(rawTitle: rawTitle, rawUri: rawUri);
    if (parsed == null) {
      return localizations.linkErrorInvalid;
    }
    return null;
  }

  /// Collapses the currently expanded card when it matches [target].
  void _collapseIfExpanded(EntityRef target) {
    if (ref.read(appShellControllerProvider).expandedEntity == target) {
      ref.read(appShellControllerProvider.notifier).collapseEntity();
    }
  }

  /// Collapses [taskId] if it is currently expanded and left the active tier/filter view.
  void _collapseIfExpandedAndLeftActiveView(String taskId) {
    final shell = ref.read(appShellControllerProvider);
    final target = EntityRef(kind: EntityKind.task, id: taskId);
    if (shell.expandedEntity != target) {
      return;
    }
    final tierAfter = _evaluateBoardForShell(
      _currentBoard,
      shell.activeLabelId,
    ).findTierOfTask(taskId);
    final leftView =
        tierAfter == null ||
        (!shell.searchOpen && tierAfter != _toTaskTier(shell.activeTier));
    if (leftView) {
      ref.read(appShellControllerProvider.notifier).collapseEntity();
    }
  }

  /// Evaluates [board] under [activeLabelId], current clock, workspace timezone, due lead window, and location fix.
  TaskBoard _evaluateBoardForShell(TaskBoard board, String? activeLabelId) {
    final configuration = _currentConfiguration;
    final nowUtc = ref.read(clockProvider)().toUtc();
    final locationState = ref.read(locationStateProvider);
    final activeFix = locationState.status == LocationStatus.found
        ? locationState.fix
        : null;
    return board.evaluateForContext(
      activeLabelId: activeLabelId,
      currentLatitude: activeFix?.latitude,
      currentLongitude: activeFix?.longitude,
      evaluationTime: nowUtc,
      localEvaluationTime: configuration.toLocalWallClock(nowUtc),
      dueLeadWindow: configuration.dueLeadWindow.duration,
    );
  }

  /// Returns a sanitized localized persistence failure message when a storage rollback occurred.
  String _fallbackPersistError(AppLocalizations localizations) {
    final syncError = ref.read(syncStateProvider).errorMessage;
    if (syncError != null && syncError.trim().isNotEmpty) {
      return syncError;
    }
    return localizations.syncStatusError;
  }

  /// Checks busy guard, task existence, and open-state editability before an inline section save.
  ({TaskItem? task, V2ActionResult? failure}) _requireEditableTask({
    required String taskId,
    required TaskSectionKind section,
    required AppLocalizations localizations,
  }) {
    if (state.isBusy) {
      return (
        task: null,
        failure: V2ActionPersistFailed(
          message: localizations.syncStatusSyncing,
        ),
      );
    }
    final task = _currentBoard.findTask(taskId);
    if (task == null) {
      UiTelemetry.logInlineEditFailed(
        kind: 'task',
        entityId: taskId,
        section: section.name,
      );
      return (
        task: null,
        failure: V2ActionValidationFailed(
          message: localizations.entityRemovedExternallyNotice,
        ),
      );
    }
    if (task.isCompleted || task.completedAt != null) {
      UiTelemetry.logInlineEditFailed(
        kind: 'task',
        entityId: taskId,
        section: section.name,
      );
      return (
        task: null,
        failure: V2ActionValidationFailed(
          message: localizations.completedReadOnlyPill,
        ),
      );
    }
    return (task: task, failure: null);
  }

  /// Resolves [AppLocalizations] from explicit [locale] or [appLocaleProvider].
  AppLocalizations _resolveLocalizations(Locale? locale) =>
      lookupAppLocalizations(locale ?? ref.read(appLocaleProvider));

  /// Resolves finite or indefinite suspension timestamp input for [existingTask].
  ResolvedSuspendedDraft _resolveSuspendedInput({
    required bool indefinitely,
    required String rawUntil,
    required TaskItem existingTask,
    required WebDavConfig configuration,
  }) {
    if (indefinitely) {
      return const ResolvedSuspendedDraft(
        suspendedAt: null,
        suspendedLocalInput: null,
        isForever: true,
        isValid: true,
      );
    }
    final trimmedUntil = rawUntil.trim();
    if (trimmedUntil.isEmpty) {
      return const ResolvedSuspendedDraft(
        suspendedAt: null,
        suspendedLocalInput: null,
        isForever: false,
        isValid: false,
      );
    }
    final initialSuspendedText =
        TaskEditorController.formatInitialSuspendedText(
          existingTask.suspendedAt,
          configuration,
        );
    return ref
        .read(taskEditorControllerProvider)
        .resolveSuspendedDraft(
          configuration: configuration,
          isSuspended: true,
          rawSuspendedText: trimmedUntil,
          initialSuspendedAt: existingTask.suspendedAt,
          initialSuspendedText: initialSuspendedText,
        );
  }

  /// Resolves the localized non-jumping placement toast for [task] on refreshed [board].
  String _resolveTaskPlacementNotice({
    required TaskBoard board,
    required TaskItem task,
    required AppLocalizations localizations,
  }) {
    final shell = ref.read(appShellControllerProvider);
    final activeLabelId = shell.activeLabelId;
    final labelMap = <String, TdfLabel>{
      for (final label in board.labels) label.id: label,
    };
    final scopedLabelName = _findRestrictingScopedLabelName(
      task: task,
      labelMap: labelMap,
      activeLabelId: activeLabelId,
    );
    if (scopedLabelName != null) {
      return localizations.noticeTaskMovedToScopedQueue(scopedLabelName);
    }
    final evaluated = _evaluateBoardForShell(board, activeLabelId);
    final landedTier =
        evaluated.findTierOfTask(task.id) ??
        _evaluateBoardForShell(board, null).findTierOfTask(task.id);
    if (landedTier != null && landedTier != _toTaskTier(shell.activeTier)) {
      return localizations.noticeTaskSavedInTier(
        localizations.tierName(landedTier),
      );
    }
    return localizations.noticeTaskSaved;
  }

  /// Executes [action] under the in-flight `isBusy` guard, mapping domain/calendar exceptions to [V2ActionPersistFailed].
  Future<V2ActionResult> _runGuardedMutation({
    String? busyTaskId,
    required AppLocalizations localizations,
    VoidCallback? onPersistFailure,
    required Future<V2ActionResult> Function() action,
  }) async {
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final token = _operationToken;
    state = TaskV2ControllerState(isBusy: true, busyTaskId: busyTaskId);
    try {
      return await action();
    } on TdfException catch (error) {
      onPersistFailure?.call();
      return V2ActionPersistFailed(
        message: _mapTdfExceptionMessage(error.kind, localizations),
      );
    } on TdfContextException {
      onPersistFailure?.call();
      return V2ActionPersistFailed(
        message: localizations.taskSuspendedErrorInvalid,
      );
    } on FormatException {
      onPersistFailure?.call();
      return V2ActionPersistFailed(
        message: localizations.taskSuspendedErrorInvalid,
      );
    } finally {
      if (ref.mounted && _operationToken == token) {
        state = const TaskV2ControllerState();
      }
    }
  }

  /// Persists a validated inline section edit on [taskId], logs telemetry, closes the editor, and handles tier transitions.
  Future<V2ActionResult> _runInlineSectionSave({
    required String taskId,
    required TaskSectionKind section,
    required Locale? locale,
    required Future<void> Function() persist,
  }) async {
    final localizations = _resolveLocalizations(locale);
    final checked = _requireEditableTask(
      taskId: taskId,
      section: section,
      localizations: localizations,
    );
    if (checked.failure case final failure?) {
      return failure;
    }
    final shellBefore = ref.read(appShellControllerProvider);
    final tierBefore = _evaluateBoardForShell(
      _currentBoard,
      shellBefore.activeLabelId,
    ).findTierOfTask(taskId);
    final target = EntityRef(kind: EntityKind.task, id: taskId);

    return _runGuardedMutation(
      busyTaskId: taskId,
      localizations: localizations,
      onPersistFailure: () {
        UiTelemetry.logInlineEditFailed(
          kind: 'task',
          entityId: taskId,
          section: section.name,
        );
      },
      action: () async {
        await ref
            .read(appShellControllerProvider.notifier)
            .runLocalEntityMutation(target, persist);
        if (!ref.mounted) {
          return V2ActionSucceeded(entityId: taskId);
        }
        final syncState = ref.read(syncStateProvider);
        if (syncState.errorMessage != null || syncState.hasOpenConflict) {
          UiTelemetry.logInlineEditFailed(
            kind: 'task',
            entityId: taskId,
            section: section.name,
          );
          return V2ActionPersistFailed(
            message: _fallbackPersistError(localizations),
          );
        }
        UiTelemetry.logInlineEditSaved(
          kind: 'task',
          entityId: taskId,
          section: section.name,
        );
        final shellAfter = ref.read(appShellControllerProvider);
        if (shellAfter.activeInlineEdit?.entity == target) {
          ref.read(appShellControllerProvider.notifier).closeInlineEdit();
        }
        final tierAfter = _evaluateBoardForShell(
          _currentBoard,
          shellAfter.activeLabelId,
        ).findTierOfTask(taskId);
        final movedTiers = tierAfter != tierBefore;
        if (movedTiers &&
            !shellAfter.searchOpen &&
            tierAfter != _toTaskTier(shellAfter.activeTier)) {
          _collapseIfExpanded(target);
        }
        final noticeMessage =
            (movedTiers &&
                tierAfter != null &&
                tierAfter != _toTaskTier(shellAfter.activeTier))
            ? localizations.noticeTaskSavedInTier(
                localizations.tierName(tierAfter),
              )
            : localizations.noticeTaskSaved;
        if (movedTiers) {
          ref
              .read(floatingNoticeControllerProvider.notifier)
              .showNotice(noticeMessage);
        }
        return V2ActionSucceeded(
          entityId: taskId,
          noticeMessage: noticeMessage,
        );
      },
    );
  }

  /// Validates every populated field of [input] against TDF `0.8.0` bounds and domain rules.
  ({
    String trimmedTitle,
    String? normalizedNote,
    List<String> labelIds,
    List<TaskLink> links,
    List<SubtaskItem> subtasks,
    bool hasDue,
    TdfLocalDateTime? dueLocalInput,
    String? dueNote,
    TaskRepeatRule? repeatRule,
    bool isSuspendedForever,
    TdfLocalDateTime? suspendedLocalInput,
    String? suspendedNote,
    List<String> prerequisiteIds,
    List<TaskCondition> conditions,
    Map<String, String> fieldErrors,
  })
  _validateTaskDraft({
    required TaskDraftInput input,
    required TaskBoard board,
    required WebDavConfig configuration,
    required AppLocalizations localizations,
  }) {
    final fieldErrors = <String, String>{};
    final titleCheck = _validateSingleLineText(
      rawText: input.title,
      emptyError: localizations.taskNameErrorEmpty,
      invalidError: localizations.historyErrorTextInvalid,
      tooLongError: localizations.historyErrorTextTooLong,
    );
    final titleError =
        titleCheck.error ??
        TaskEditorController.validateTaskTitle(
          board: board,
          rawTitle: titleCheck.trimmed,
          excludingTaskId: null,
          localizations: localizations,
        );
    if (titleError != null) {
      fieldErrors['title'] = titleError;
    }

    final normalizedNote = TaskEditorController.normalizeSchedulingNote(
      input.note,
    );
    final noteError = TaskEditorController.validateSchedulingNote(
      normalizedNote,
      localizations,
    );
    if (noteError != null) {
      fieldErrors['note'] = noteError;
    }

    final linksCheck = _validateLinksList(
      links: input.links,
      localizations: localizations,
    );
    if (linksCheck.error case final linkError?) {
      fieldErrors['links'] = linkError;
    }

    final subtasksCheck = _validateSubtasksList(
      subtasks: input.subtasks,
      localizations: localizations,
    );
    if (subtasksCheck.error case final subtaskError?) {
      fieldErrors['subtasks'] = subtaskError;
    }

    final hasDue = input.rawDue.trim().isNotEmpty;
    TdfLocalDateTime? dueLocalInput;
    String? dueNote;
    if (hasDue) {
      final parsedDue = TaskEditorController.tryParseLocalDateTimeInput(
        input.rawDue,
        configuration,
      );
      if (parsedDue == null) {
        fieldErrors['due'] = localizations.taskSuspendedErrorInvalid;
      } else {
        dueLocalInput = parsedDue.localInput;
      }
      dueNote = TaskEditorController.normalizeSchedulingNote(input.rawDueNote);
      final dueNoteError = TaskEditorController.validateSchedulingNote(
        dueNote,
        localizations,
      );
      if (dueNoteError != null) {
        fieldErrors['dueNote'] = dueNoteError;
      }
    }

    TaskRepeatRule? repeatRule;
    if (input.isRepeating) {
      final parsedCount = TaskEditorController.parseRepeatCount(
        isRepeating: true,
        rawCount: input.rawRepeatCount,
      );
      final parsedLeadDays = TaskEditorController.parseLeadDays(
        hasDue: hasDue,
        isRepeating: true,
        rawLeadDays: input.rawRepeatLeadDays,
      );
      if (parsedCount == null) {
        fieldErrors['repeatCount'] = localizations.repeatErrorInvalid;
      }
      if (parsedLeadDays == null) {
        fieldErrors['repeatLeadDays'] =
            localizations.repeatLeadDaysErrorInvalid;
      }
      if (parsedCount != null && parsedLeadDays != null) {
        repeatRule = TaskRepeatRule(
          count: parsedCount,
          unit: _toRepeatUnit(input.repeatUnit),
          leadDays: parsedLeadDays,
        );
      }
    }

    var isSuspendedForever = false;
    TdfLocalDateTime? suspendedLocalInput;
    String? suspendedNote;
    if (input.isSuspended) {
      if (input.suspendedIndefinitely) {
        isSuspendedForever = true;
      } else {
        final parsedSuspended = TaskEditorController.tryParseLocalDateTimeInput(
          input.rawSuspendedUntil,
          configuration,
        );
        if (parsedSuspended == null) {
          fieldErrors['suspended'] = localizations.taskSuspendedErrorInvalid;
        } else {
          suspendedLocalInput = parsedSuspended.localInput;
        }
      }
      suspendedNote = TaskEditorController.normalizeSchedulingNote(
        input.rawSuspendedNote,
      );
      final suspendedNoteError = TaskEditorController.validateSchedulingNote(
        suspendedNote,
        localizations,
      );
      if (suspendedNoteError != null) {
        fieldErrors['suspendedNote'] = suspendedNoteError;
      }
    }

    final orderedLabelIds = TaskEditorController.collectOrderedLabelIds(
      board,
      input.labelIds.toSet(),
    );
    if (orderedLabelIds.length > maxTdfArgsPerStmt) {
      fieldErrors['labels'] = localizations.errorLocalFileTooLarge;
    }

    final orderedPrerequisites =
        TaskEditorController.collectOrderedBlockedByIds(
          board,
          input.prerequisiteTaskIds.toSet(),
        );
    if (orderedPrerequisites.length > maxTdfArgsPerStmt) {
      fieldErrors['prerequisites'] = localizations.errorLocalFileTooLarge;
    }

    var compiledConditions = const <TaskCondition>[];
    if (input.conditionDraft case final conditionDraft?) {
      final compiled = _compileConditionDraft(
        draft: conditionDraft,
        board: board,
        localizations: localizations,
      );
      if (compiled.error case final conditionError?) {
        fieldErrors['conditions'] = conditionError;
      } else {
        compiledConditions = compiled.conditions;
      }
    }

    return (
      trimmedTitle: titleCheck.trimmed,
      normalizedNote: normalizedNote,
      labelIds: orderedLabelIds,
      links: linksCheck.links,
      subtasks: subtasksCheck.subtasks,
      hasDue: hasDue,
      dueLocalInput: dueLocalInput,
      dueNote: dueNote,
      repeatRule: repeatRule,
      isSuspendedForever: isSuspendedForever,
      suspendedLocalInput: suspendedLocalInput,
      suspendedNote: suspendedNote,
      prerequisiteIds: orderedPrerequisites,
      conditions: compiledConditions,
      fieldErrors: fieldErrors,
    );
  }
}

/// Immutable in-flight concurrency state exposed by [taskV2ControllerProvider].
@immutable
class TaskV2ControllerState {
  /// Creates a [TaskV2ControllerState].
  const TaskV2ControllerState({this.isBusy = false, this.busyTaskId});

  /// Identifier of the task currently being mutated, or `null` for task creation or idle state.
  final String? busyTaskId;

  /// Whether an asynchronous task mutation is currently in flight.
  final bool isBusy;

  /// Returns a copy of this [TaskV2ControllerState] with updated fields.
  TaskV2ControllerState copyWith({
    bool? isBusy,
    String? busyTaskId,
    bool clearBusyTaskId = false,
  }) {
    return TaskV2ControllerState(
      isBusy: isBusy ?? this.isBusy,
      busyTaskId: clearBusyTaskId ? null : (busyTaskId ?? this.busyTaskId),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskV2ControllerState &&
        other.isBusy == isBusy &&
        other.busyTaskId == busyTaskId;
  }

  @override
  int get hashCode => Object.hash(isBusy, busyTaskId);
}

/// Validates and appends a custom weekday condition to [rules], returning an error message or `null`.
String? _appendCustomDayCondition({
  required List<int> weekdays,
  required List<TaskCondition> rules,
  required AppLocalizations localizations,
}) {
  for (final weekday in weekdays) {
    if (weekday < DateTime.monday || weekday > DateTime.sunday) {
      return localizations.conditionTimeErrorInvalid;
    }
  }
  if (weekdays.isNotEmpty) {
    rules.add(DayTaskCondition.fromWeekdays(weekdays));
  }
  return null;
}

/// Validates and appends a custom location condition to [rules], returning an error message or `null`.
String? _appendCustomLocationCondition({
  required List<String> locationIds,
  required TaskBoard board,
  required List<TaskCondition> rules,
  required AppLocalizations localizations,
}) {
  if (locationIds.length > maxTdfLocationRefsPerEntity) {
    return localizations.errorLocalFileTooLarge;
  }
  for (final locationId in locationIds) {
    if (board.findLocation(locationId) == null) {
      return localizations.conditionLocationErrorInvalid;
    }
  }
  if (locationIds.isEmpty) {
    return null;
  }
  if (rules.length >= maxTdfConditionRulesPerEntity) {
    return localizations.errorLocalFileTooLarge;
  }
  rules.add(LocationTaskCondition.fromIds(locationIds));
  return null;
}

/// Validates and appends custom time-window conditions to [rules], returning an error message or `null`.
String? _appendCustomTimeConditions({
  required List<TimeWindowDraftViewModel> timeWindows,
  required List<TaskCondition> rules,
  required AppLocalizations localizations,
}) {
  for (final window in timeWindows) {
    if (rules.length >= maxTdfConditionRulesPerEntity) {
      return localizations.errorLocalFileTooLarge;
    }
    final parsedWindow = TimeWindowTaskCondition.tryParse(
      window.start,
      window.end,
    );
    if (parsedWindow == null) {
      return localizations.conditionTimeErrorInvalid;
    }
    rules.add(parsedWindow);
  }
  return null;
}

/// Compiles and validates a model-free [ConditionDraftViewModel] into canonical [TaskCondition] rules.
({List<TaskCondition> conditions, String? error}) _compileConditionDraft({
  required ConditionDraftViewModel draft,
  required TaskBoard board,
  required AppLocalizations localizations,
}) {
  if (draft.ignoreAllLabelConditions) {
    return (
      conditions: const <TaskCondition>[GlobalResetTaskCondition()],
      error: null,
    );
  }
  final rules = <TaskCondition>[];

  final dayError = _compileDayDimension(
    mode: draft.daysMode,
    weekdays: draft.selectedWeekdays,
    rules: rules,
    localizations: localizations,
  );
  if (dayError != null) {
    return (conditions: const <TaskCondition>[], error: dayError);
  }

  final timeError = _compileTimeDimension(
    mode: draft.timesMode,
    timeWindows: draft.timeWindows,
    rules: rules,
    localizations: localizations,
  );
  if (timeError != null) {
    return (conditions: const <TaskCondition>[], error: timeError);
  }

  final locationError = _compileLocationDimension(
    mode: draft.locationsMode,
    locationIds: draft.selectedLocationIds,
    board: board,
    rules: rules,
    localizations: localizations,
  );
  if (locationError != null) {
    return (conditions: const <TaskCondition>[], error: locationError);
  }

  return (conditions: List<TaskCondition>.unmodifiable(rules), error: null);
}

/// Compiles the weekday dimension for [mode] and appends to [rules], returning an error or `null`.
String? _compileDayDimension({
  required ConditionDimensionMode mode,
  required List<int> weekdays,
  required List<TaskCondition> rules,
  required AppLocalizations localizations,
}) {
  switch (mode) {
    case ConditionDimensionMode.inherit:
      return null;
    case ConditionDimensionMode.any:
      rules.add(const GroupResetTaskCondition(targetGroup: ConditionGroup.day));
      return null;
    case ConditionDimensionMode.custom:
      return _appendCustomDayCondition(
        weekdays: weekdays,
        rules: rules,
        localizations: localizations,
      );
  }
}

/// Compiles the location dimension for [mode] and appends to [rules], returning an error or `null`.
String? _compileLocationDimension({
  required ConditionDimensionMode mode,
  required List<String> locationIds,
  required TaskBoard board,
  required List<TaskCondition> rules,
  required AppLocalizations localizations,
}) {
  switch (mode) {
    case ConditionDimensionMode.inherit:
      return null;
    case ConditionDimensionMode.any:
      rules.add(
        const GroupResetTaskCondition(targetGroup: ConditionGroup.location),
      );
      return null;
    case ConditionDimensionMode.custom:
      return _appendCustomLocationCondition(
        locationIds: locationIds,
        board: board,
        rules: rules,
        localizations: localizations,
      );
  }
}

/// Compiles the time-window dimension for [mode] and appends to [rules], returning an error or `null`.
String? _compileTimeDimension({
  required ConditionDimensionMode mode,
  required List<TimeWindowDraftViewModel> timeWindows,
  required List<TaskCondition> rules,
  required AppLocalizations localizations,
}) {
  switch (mode) {
    case ConditionDimensionMode.inherit:
      return null;
    case ConditionDimensionMode.any:
      rules.add(
        const GroupResetTaskCondition(targetGroup: ConditionGroup.time),
      );
      return null;
    case ConditionDimensionMode.custom:
      return _appendCustomTimeConditions(
        timeWindows: timeWindows,
        rules: rules,
        localizations: localizations,
      );
  }
}

/// Returns `true` when [value] contains any ASCII control character (`0x00..0x1F` or `0x7F`).
bool _containsSingleLineControlChar(String value) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit <= 0x1F || unit == 0x7F) {
      return true;
    }
  }
  return false;
}

/// Locates a newly created label on [board] that was absent from [beforeIds], falling back to [trimmedName].
TdfLabel? _findCreatedLabel({
  required TaskBoard board,
  required Set<String> beforeIds,
  required String trimmedName,
}) {
  for (final label in board.labels) {
    if (!beforeIds.contains(label.id)) {
      return label;
    }
  }
  final targetLower = trimmedName.toLowerCase();
  for (final label in board.labels) {
    if (label.name.trim().toLowerCase() == targetLower) {
      return label;
    }
  }
  return null;
}

/// Locates a newly created task on [board] that was absent from [beforeIds], falling back to [trimmedTitle].
TaskItem? _findCreatedTask({
  required TaskBoard board,
  required Set<String> beforeIds,
  required String trimmedTitle,
}) {
  for (final task in board.allTasks) {
    if (!beforeIds.contains(task.id)) {
      return task;
    }
  }
  final targetLower = trimmedTitle.toLowerCase();
  for (final task in board.allTasks) {
    if (task.title.trim().toLowerCase() == targetLower) {
      return task;
    }
  }
  return null;
}

/// Returns the display name of the restricting scoped label when [task] is hidden from [activeLabelId]'s view.
String? _findRestrictingScopedLabelName({
  required TaskItem task,
  required Map<String, TdfLabel> labelMap,
  required String? activeLabelId,
}) {
  if (activeLabelId != null && task.labelIds.contains(activeLabelId)) {
    return null;
  }
  if (activeLabelId == null &&
      !TaskBoardEvaluator.isRestrictedFromGlobalView(task, labelMap)) {
    return null;
  }
  for (final labelId in task.labelIds) {
    final label = labelMap[labelId];
    if (label != null && label.isScoped && label.id != activeLabelId) {
      return label.name;
    }
  }
  return null;
}

/// Maps a domain [TdfErrorKind] into a sanitized localized persistence failure message.
String _mapTdfExceptionMessage(
  TdfErrorKind kind,
  AppLocalizations localizations,
) {
  return switch (kind) {
    TdfErrorKind.circularDependency =>
      localizations.prerequisiteCyclePreventedHint,
    TdfErrorKind.emptyText => localizations.taskNameErrorEmpty,
    TdfErrorKind.invalidColor => localizations.labelColorErrorInvalid,
    TdfErrorKind.invalidCondition => localizations.conditionTimeErrorInvalid,
    TdfErrorKind.invalidNumber => localizations.repeatErrorInvalid,
    TdfErrorKind.invalidUri => localizations.linkErrorInvalid,
    TdfErrorKind.limitExceeded => localizations.errorLocalFileTooLarge,
    TdfErrorKind.unexpectedToken => localizations.schedulingNoteErrorInvalid,
    _ => localizations.taskSuspendedErrorInvalid,
  };
}

/// Maps [TaskPlacementOption] to `TaskNotifier.addTask` / `updateTask` parameters.
({TaskTier targetTier, bool isPriority}) _resolvePlacementTarget(
  TaskPlacementOption placement,
) {
  return switch (placement) {
    TaskPlacementOption.queue => (
      targetTier: TaskTier.planned,
      isPriority: false,
    ),
    TaskPlacementOption.priority => (
      targetTier: TaskTier.planned,
      isPriority: true,
    ),
    TaskPlacementOption.someday => (
      targetTier: TaskTier.someday,
      isPriority: false,
    ),
  };
}

/// Resolves the localized confirmation message after switching live task placement.
String _resolvePlacementToggleNotice({
  required TaskPlacementOption placement,
  required bool wasQueued,
  required bool wasPriority,
  required TaskTier? tierAfter,
  required ShellTier activeTier,
  required AppLocalizations localizations,
}) {
  return switch (placement) {
    TaskPlacementOption.someday => localizations.noticeMovedToSomeday,
    TaskPlacementOption.priority => localizations.noticePriorityEnabled,
    TaskPlacementOption.queue =>
      !wasQueued
          ? localizations.noticeMovedToQueue
          : (wasPriority
                ? localizations.noticePriorityDisabled
                : (tierAfter != null && tierAfter != _toTaskTier(activeTier)
                      ? localizations.noticeTaskSavedInTier(
                          localizations.tierName(tierAfter),
                        )
                      : localizations.noticeMovedToQueue)),
  };
}

/// Maps presentation [ShellRepeatUnit] to domain [RepeatUnit].
RepeatUnit _toRepeatUnit(ShellRepeatUnit unit) {
  return switch (unit) {
    ShellRepeatUnit.days => RepeatUnit.days,
    ShellRepeatUnit.weeks => RepeatUnit.weeks,
    ShellRepeatUnit.months => RepeatUnit.months,
  };
}

/// Maps presentation [ShellTier] to domain [TaskTier].
TaskTier _toTaskTier(ShellTier tier) {
  return switch (tier) {
    ShellTier.focus => TaskTier.focus,
    ShellTier.ready => TaskTier.ready,
    ShellTier.planned => TaskTier.planned,
    ShellTier.blocked => TaskTier.blocked,
    ShellTier.someday => TaskTier.someday,
    ShellTier.completed => TaskTier.completed,
  };
}

/// Validates a bounded list of [EntityLinkInput] items (`<= 20`) into canonical [TaskLink] models.
({List<TaskLink> links, String? error}) _validateLinksList({
  required Iterable<EntityLinkInput> links,
  required AppLocalizations localizations,
}) {
  final validated = <TaskLink>[];
  for (final link in links) {
    if (validated.length >= maxTdfLinksPerTask) {
      return (
        links: const <TaskLink>[],
        error: localizations.linkErrorMaxExceeded,
      );
    }
    final parsed = TaskLink.tryParse(rawTitle: link.title, rawUri: link.uri);
    if (parsed == null) {
      return (links: const <TaskLink>[], error: localizations.linkErrorInvalid);
    }
    validated.add(parsed);
  }
  return (links: List<TaskLink>.unmodifiable(validated), error: null);
}

/// Validates single-line `<text>` (`1..500` Unicode scalars, rejecting control characters and unpaired surrogates).
({String trimmed, String? error}) _validateSingleLineText({
  required String rawText,
  required String emptyError,
  required String invalidError,
  required String tooLongError,
}) {
  if (_containsSingleLineControlChar(rawText) ||
      TdfCalendar.countUnicodeScalars(rawText) == null) {
    return (trimmed: '', error: invalidError);
  }
  final trimmed = rawText.trim();
  if (trimmed.isEmpty) {
    return (trimmed: '', error: emptyError);
  }
  final scalarCount = TdfCalendar.countUnicodeScalars(trimmed);
  if (scalarCount == null) {
    return (trimmed: '', error: invalidError);
  }
  if (scalarCount > maxTdfTextLength) {
    return (trimmed: trimmed, error: tooLongError);
  }
  return (trimmed: trimmed, error: null);
}

/// Strips blank steps and validates remaining subtasks against `maxTdfStmtsPerBlock` (`1024`) and `maxTdfTextLength` (`500`).
({List<SubtaskItem> subtasks, String? error}) _validateSubtasksList({
  required Iterable<SubtaskInput> subtasks,
  required AppLocalizations localizations,
}) {
  final validated = <SubtaskItem>[];
  for (final step in subtasks) {
    if (_containsSingleLineControlChar(step.title) ||
        TdfCalendar.countUnicodeScalars(step.title) == null) {
      return (
        subtasks: const <SubtaskItem>[],
        error: localizations.historyErrorTextInvalid,
      );
    }
    final trimmed = step.title.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (validated.length >= maxTdfStmtsPerBlock) {
      return (
        subtasks: const <SubtaskItem>[],
        error: localizations.errorLocalFileTooLarge,
      );
    }
    final scalarCount = TdfCalendar.countUnicodeScalars(trimmed);
    if (scalarCount == null) {
      return (
        subtasks: const <SubtaskItem>[],
        error: localizations.historyErrorTextInvalid,
      );
    }
    if (scalarCount > maxTdfTextLength) {
      return (
        subtasks: const <SubtaskItem>[],
        error: localizations.historyErrorTextTooLong,
      );
    }
    validated.add(SubtaskItem(title: trimmed, isCompleted: step.isCompleted));
  }
  return (subtasks: List<SubtaskItem>.unmodifiable(validated), error: null);
}
