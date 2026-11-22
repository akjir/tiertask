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
import '../models/task_board.dart';
import '../models/task_board_evaluator.dart';
import '../models/task_item.dart';
import '../models/task_tier.dart';
import '../models/tdf_error.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import '../models/webdav_config.dart';
import 'board_providers.dart';
import 'config_providers.dart';
import 'floating_notice_providers.dart';
import 'shell_providers.dart';
import 'sync_providers.dart';
import 'task_providers.dart';
import 'task_schedule_helper.dart';
import 'ui_telemetry.dart';
import 'workspace_providers.dart';

/// Provides [BoardActionsNotifier] and its [BoardActionsState] for domain-typed task mutations.
final boardActionsProvider =
    NotifierProvider<BoardActionsNotifier, BoardActionsState>(
      BoardActionsNotifier.new,
    );

/// Domain-typed coordinator owning Quick-Add, Task Draft creation,
/// live task controls, single-section inline editors, and non-jumping notices.
class BoardActionsNotifier extends Notifier<BoardActionsState> {
  String? _activeWorkspaceId;
  int _operationToken = 0;

  /// Latest loaded [TaskBoard] snapshot, or an empty board before load completes.
  TaskBoard get _currentBoard =>
      ref.read(taskNotifierProvider).asData?.value ?? TaskBoard.empty();

  /// Active workspace [WebDavConfig] snapshot resolved synchronously without reactive subscription.
  WebDavConfig get _currentConfiguration => readCurrentConfig(ref);

  @override
  BoardActionsState build() {
    _activeWorkspaceId = ref.read(activeWorkspaceProvider).asData?.value.id;
    ref.listen<String?>(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
      _handleWorkspaceIdChanged,
    );
    return const BoardActionsState();
  }

  /// Appends a single-line history journal entry onto [taskId] with optional local timestamp override.
  Future<ActionResult> addHistoryEntry(
    String taskId, {
    required String rawText,
    String? rawTimestampOverride,
    Locale? locale,
  }) => _runTaskAction(
    taskId: taskId,
    locale: locale,
    suppressLocalWatch: false,
    run: (_, task, localizations, commit) {
      final validated = _validateHistoryCandidate(
        task: task,
        rawText: rawText,
        rawTimestamp: rawTimestampOverride ?? '',
        configuration: _currentConfiguration,
        fallbackNowUtc: ref.read(clockProvider)().toUtc(),
        localizations: localizations,
      );
      if (validated.failure case final failure?) {
        return Future<ActionResult>.value(failure);
      }
      final candidate = validated.entry;
      if (candidate == null) {
        return Future<ActionResult>.value(
          ActionValidationFailed(
            message: localizations.historyErrorTextInvalid,
          ),
        );
      }
      if (task.history.length >= maxTdfHistoryPerTask) {
        return Future<ActionResult>.value(
          ActionValidationFailed(
            message: localizations.historyErrorMaxExceeded,
            fieldErrors: <String, String>{
              'text': localizations.historyErrorMaxExceeded,
            },
          ),
        );
      }
      return commit(
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .addTaskHistoryEntry(
              taskId,
              timestampUtc: candidate.timestampUtc,
              text: candidate.text,
            ),
        onCommitted: () {
          final postTask = _currentBoard.findTask(taskId);
          if (postTask == null || !postTask.history.contains(candidate)) {
            return ActionPersistFailed(
              message: _fallbackPersistError(localizations),
            );
          }
          return ActionSucceeded(entityId: taskId);
        },
      );
    },
  );

  /// Clears all task-level activation conditions on [taskId].
  Future<ActionResult> clearConditions(String taskId, {Locale? locale}) =>
      _runInlineSectionSave(
        taskId: taskId,
        section: TaskSectionKind.conditions,
        locale: locale,
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateTask(taskId, conditions: const <TaskCondition>[]),
      );

  /// Clears the due timestamp, anchor, due note, and Mode 2 repeat lead days on [taskId].
  Future<ActionResult> clearDue(String taskId, {Locale? locale}) =>
      _runEditableTaskSection(
        taskId: taskId,
        section: TaskSectionKind.due,
        locale: locale,
        onValidatedTask: (_, existingTask, localizations) {
          final clearedLeadRepeat = switch (existingTask.repeatRule) {
            final existingRule? when existingRule.leadDays > 0 =>
              existingRule.copyWith(leadDays: 0),
            _ => null,
          };
          return _commitInlineSectionSave(
            taskId: taskId,
            section: TaskSectionKind.due,
            localizations: localizations,
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
        },
      );

  /// Clears the body note on [taskId].
  Future<ActionResult> clearNote(String taskId, {Locale? locale}) =>
      _runInlineSectionSave(
        taskId: taskId,
        section: TaskSectionKind.note,
        locale: locale,
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateTask(taskId, note: ''),
      );

  /// Completes an open [taskId] (with local-mutation suppression and repeat/Undo handling) or restores a completed [taskId].
  Future<ActionResult> completeOrRestoreTask(String taskId, {Locale? locale}) =>
      _runTaskAction(
        taskId: taskId,
        locale: locale,
        run: (_, taskBefore, localizations, commit) {
          final wasCompleted =
              taskBefore.isCompleted || taskBefore.completedAt != null;
          return commit(
            persist: () => wasCompleted
                ? ref.read(taskNotifierProvider.notifier).restoreTask(taskId)
                : ref.read(taskNotifierProvider.notifier).completeTask(taskId),
            onCommitted: () {
              if (wasCompleted) {
                _collapseIfExpandedAndLeftActiveView(taskId);
                final noticeMessage = localizations.taskRestoredNotice(
                  taskBefore.title,
                );
                ref
                    .read(floatingNoticeProvider.notifier)
                    .showNotice(noticeMessage);
                return ActionSucceeded(
                  entityId: taskId,
                  noticeMessage: noticeMessage,
                );
              }
              return _finishCompletedTaskAction(
                taskId: taskId,
                taskBefore: taskBefore,
                localizations: localizations,
              );
            },
          );
        },
      );

  /// Atomically creates a new label with rotating preset color from [rawName] and assigns it to [taskId] in one persistence cycle.
  Future<ActionResult> createAndAssignLabel(
    String taskId,
    String rawName, {
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    final checked = _requireTask(
      taskId: taskId,
      localizations: localizations,
      requireOpen: true,
    );
    if (checked.failure case final failure?) {
      return failure;
    }
    final boardBefore = checked.board;
    final taskBefore = checked.task;
    if (taskBefore == null) {
      return ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    final nameCheck = TaskScheduleHelper.validateSingleLineText(
      rawText: rawName,
      emptyError: localizations.labelNameErrorEmpty,
      invalidError: localizations.historyErrorTextInvalid,
      tooLongError: localizations.historyErrorTextTooLong,
    );
    if (nameCheck.error case final error?) {
      return ActionValidationFailed(
        message: error,
        fieldErrors: <String, String>{'name': error},
      );
    }
    final trimmedName = nameCheck.trimmed;
    if (boardBefore.hasDuplicateLabelName(trimmedName)) {
      return ActionValidationFailed(
        message: localizations.labelNameErrorDuplicate,
        fieldErrors: <String, String>{
          'name': localizations.labelNameErrorDuplicate,
        },
      );
    }
    if (taskBefore.labelIds.length >= maxTdfArgsPerStmt) {
      return ActionValidationFailed(
        message: localizations.errorLocalFileTooLarge,
      );
    }
    final presetHex =
        canonicalLabelPresetHexColors[boardBefore.labels.length %
            canonicalLabelPresetHexColors.length];
    final generatedLabelId = generateLabelId(
      timestamp: ref.read(clockProvider)().toUtc(),
      existingIds: TaskScheduleHelper.collectAllUsedEntityIds(boardBefore),
    );
    final target = EntityRef(kind: EntityKind.task, id: taskId);

    return _runGuardedMutation(
      busyTaskId: taskId,
      localizations: localizations,
      action: (token) async {
        final createdLabel = await ref
            .read(shellProvider.notifier)
            .runLocalEntityMutation(
              target,
              () => ref
                  .read(taskNotifierProvider.notifier)
                  .createLabelAndAssignToTask(
                    taskId: taskId,
                    name: trimmedName,
                    color: presetHex,
                    id: generatedLabelId,
                  ),
            );
        if (!_isOperationActive(token)) {
          return ActionSucceeded(
            entityId: createdLabel?.id ?? generatedLabelId,
          );
        }
        if (createdLabel == null) {
          return ActionPersistFailed(
            message: _fallbackPersistError(localizations),
          );
        }
        final noticeMessage = localizations.noticeLabelCreatedAndAssigned(
          createdLabel.name,
        );
        ref.read(floatingNoticeProvider.notifier).showNotice(noticeMessage);
        return ActionSucceeded(
          entityId: createdLabel.id,
          noticeMessage: noticeMessage,
        );
      },
    );
  }

  /// Validates and commits a full [TaskDraftInput], closes the draft card, logs telemetry, and emits a non-jumping placement toast.
  Future<ActionResult> createTaskDraft(
    TaskDraftInput input, {
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final boardBefore = _currentBoard;
    final validation = _validateTaskDraft(
      input: input,
      board: boardBefore,
      configuration: _currentConfiguration,
      localizations: localizations,
    );
    if (validation.fieldErrors.isNotEmpty) {
      return ActionValidationFailed(
        message: validation.fieldErrors.values.first,
        fieldErrors: validation.fieldErrors,
      );
    }
    final newTaskId = generateTaskId(
      timestamp: ref.read(clockProvider)().toUtc(),
      existingIds: TaskScheduleHelper.collectAllUsedEntityIds(boardBefore),
    );
    final placementTarget = _resolvePlacementTarget(input.placement);
    return _commitTaskCreation(
      newTaskId: newTaskId,
      localizations: localizations,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .addTask(
            validation.trimmedTitle,
            id: newTaskId,
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
          ),
      onCreated: () {
        ref.read(shellProvider.notifier).cancelDraft();
        UiTelemetry.logEntityDraftCommitted('task');
      },
    );
  }

  /// Removes a specific `(timestampUtcIso, text)` history journal entry from [taskId].
  Future<ActionResult> deleteHistoryEntry(
    String taskId, {
    required String timestampUtcIso,
    required String text,
    Locale? locale,
  }) => _runTaskAction(
    taskId: taskId,
    locale: locale,
    suppressLocalWatch: false,
    run: (_, task, localizations, commit) {
      final timestampUtc = DateTime.tryParse(timestampUtcIso)?.toUtc();
      if (timestampUtc == null) {
        return Future<ActionResult>.value(
          ActionValidationFailed(
            message: localizations.historyErrorTimestampInvalid,
          ),
        );
      }
      final entry = TaskHistoryEntry(timestampUtc: timestampUtc, text: text);
      if (!task.history.contains(entry)) {
        return Future<ActionResult>.value(ActionSucceeded(entityId: taskId));
      }
      return commit(
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .removeTaskHistoryEntry(
              taskId,
              timestampUtc: entry.timestampUtc,
              text: entry.text,
            ),
      );
    },
  );

  /// Deletes [taskId] with local-mutation suppression, collapses its card, and clears delete confirmation.
  Future<ActionResult> deleteTask(String taskId, {Locale? locale}) =>
      _runTaskAction(
        taskId: taskId,
        locale: locale,
        run: (_, _, _, commit) => commit(
          persist: () =>
              ref.read(taskNotifierProvider.notifier).deleteTask(taskId),
          onCommitted: () {
            final target = EntityRef(kind: EntityKind.task, id: taskId);
            final shellState = ref.read(shellProvider);
            if (shellState.expandedEntity == target ||
                shellState.activeDeleteConfirm == target) {
              ref.read(shellProvider.notifier).collapseEntity();
            }
            return ActionSucceeded(entityId: taskId);
          },
        ),
      );

  /// Disables recurrence on [taskId].
  Future<ActionResult> disableRepeat(String taskId, {Locale? locale}) =>
      _runInlineSectionSave(
        taskId: taskId,
        section: TaskSectionKind.repeat,
        locale: locale,
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateTask(taskId, clearRepeatRule: true),
      );

  /// Downgrades active [taskId] under the active sidebar label filter.
  Future<ActionResult> downgradeTask(String taskId, {Locale? locale}) =>
      _runTaskAction(
        taskId: taskId,
        locale: locale,
        run: (_, _, _, commit) {
          final activeLabelId = ref.read(shellProvider).activeLabelId;
          return commit(
            persist: () => ref
                .read(taskNotifierProvider.notifier)
                .downgradeTask(taskId, activeFilterLabelId: activeLabelId),
            onCommitted: () {
              _collapseIfExpandedAndLeftActiveView(taskId);
              return ActionSucceeded(entityId: taskId);
            },
          );
        },
      );

  /// Validates and creates a task from the docked Quick-Add composer without switching tiers, scrolling, or expanding (`U-CARD-006`).
  Future<ActionResult> quickAddTask({
    required String rawTitle,
    required QuickAddMode placement,
    required List<String> labelIds,
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final boardBefore = _currentBoard;
    final titleValidation = _validateTaskTitleInput(
      board: boardBefore,
      rawTitle: rawTitle,
      excludingTaskId: null,
      localizations: localizations,
    );
    if (titleValidation.error case final error?) {
      if (error == localizations.taskNameErrorDuplicate) {
        ref
            .read(floatingNoticeProvider.notifier)
            .showNotice(error, tone: FloatingNoticeTone.danger);
      }
      return ActionValidationFailed(
        message: error,
        fieldErrors: <String, String>{'title': error},
      );
    }
    final orderedLabelIds = TaskScheduleHelper.collectOrderedLabelIds(
      boardBefore,
      labelIds.toSet(),
    );
    final placementTarget = _resolvePlacementTarget(placement);
    final newTaskId = generateTaskId(
      timestamp: ref.read(clockProvider)().toUtc(),
      existingIds: TaskScheduleHelper.collectAllUsedEntityIds(boardBefore),
    );
    return _commitTaskCreation(
      newTaskId: newTaskId,
      localizations: localizations,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .addTask(
            titleValidation.trimmed,
            id: newTaskId,
            targetTier: placementTarget.targetTier,
            isPriority: placementTarget.isPriority,
            labelIds: orderedLabelIds,
          ),
    );
  }

  /// Clears finite or indefinite suspension and its deferral note on [taskId].
  Future<ActionResult> resumeTask(String taskId, {Locale? locale}) =>
      _runInlineSectionSave(
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

  /// Compiles, validates, and saves activation conditions from [draft] onto [taskId].
  Future<ActionResult> saveConditions(
    String taskId,
    ConditionDraft draft, {
    Locale? locale,
  }) => _runEditableTaskSection(
    taskId: taskId,
    section: TaskSectionKind.conditions,
    locale: locale,
    onValidatedTask: (board, _, localizations) {
      final compiled = TaskScheduleHelper.compileConditionDraft(
        draft: draft,
        board: board,
        isTask: true,
        localizations: localizations,
      );
      if (compiled.error case final error?) {
        return _failInlineValidation(
          taskId: taskId,
          section: TaskSectionKind.conditions,
          fieldErrors: <String, String>{'conditions': error},
        );
      }
      return _commitInlineSectionSave(
        taskId: taskId,
        section: TaskSectionKind.conditions,
        localizations: localizations,
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateTask(taskId, conditions: compiled.conditions),
      );
    },
  );

  /// Validates and saves deadline timestamp, auto-priority flag, and deadline note onto [taskId].
  Future<ActionResult> saveDue(
    String taskId, {
    required String rawDue,
    required bool autoPrioritize,
    required String rawDueNote,
    Locale? locale,
  }) => _runEditableTaskSection(
    taskId: taskId,
    section: TaskSectionKind.due,
    locale: locale,
    onValidatedTask: (_, existingTask, localizations) {
      final configuration = _currentConfiguration;
      final initialDueText = existingTask.dueAt != null
          ? TaskScheduleHelper.formatLocalTimestamp(
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
          : TaskScheduleHelper.resolveDueDraft(
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
      final normalizedDueNote = _validateOptionalSchedulingNote(
        rawNote: rawDueNote,
        fieldKey: 'dueNote',
        localizations: localizations,
        fieldErrors: fieldErrors,
      );
      if (fieldErrors.isNotEmpty) {
        return _failInlineValidation(
          taskId: taskId,
          section: TaskSectionKind.due,
          fieldErrors: fieldErrors,
        );
      }
      return _commitInlineSectionSave(
        taskId: taskId,
        section: TaskSectionKind.due,
        localizations: localizations,
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
              clearDueAnchor:
                  dueDraft.dueLocalInput == null && dueDraft.dueAnchor == null,
              clearDueNote: normalizedDueNote == null,
            ),
      );
    },
  );

  /// Validates and saves the reference [links] list onto [taskId].
  Future<ActionResult> saveLinks(
    String taskId,
    List<TaskLink> links, {
    Locale? locale,
  }) => _runEditableTaskSection(
    taskId: taskId,
    section: TaskSectionKind.links,
    locale: locale,
    onValidatedTask: (_, _, localizations) {
      final validated = TaskScheduleHelper.validateLinksList(
        links: links,
        localizations: localizations,
      );
      if (validated.error case final error?) {
        return _failInlineValidation(
          taskId: taskId,
          section: TaskSectionKind.links,
          fieldErrors: <String, String>{'links': error},
        );
      }
      return _commitInlineSectionSave(
        taskId: taskId,
        section: TaskSectionKind.links,
        localizations: localizations,
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateTask(taskId, links: validated.links),
      );
    },
  );

  /// Validates and saves the multi-line body note onto [taskId].
  Future<ActionResult> saveNote(
    String taskId,
    String rawNote, {
    Locale? locale,
  }) => _runEditableTaskSection(
    taskId: taskId,
    section: TaskSectionKind.note,
    locale: locale,
    onValidatedTask: (_, _, localizations) {
      final fieldErrors = <String, String>{};
      final normalizedNote = _validateOptionalSchedulingNote(
        rawNote: rawNote,
        fieldKey: 'note',
        localizations: localizations,
        fieldErrors: fieldErrors,
      );
      if (fieldErrors.isNotEmpty) {
        return _failInlineValidation(
          taskId: taskId,
          section: TaskSectionKind.note,
          fieldErrors: fieldErrors,
        );
      }
      return _commitInlineSectionSave(
        taskId: taskId,
        section: TaskSectionKind.note,
        localizations: localizations,
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateTask(taskId, note: normalizedNote ?? ''),
      );
    },
  );

  /// Validates prerequisite dependencies against self/transitive cycles and statement bounds, then saves onto [taskId].
  Future<ActionResult> savePrerequisites(
    String taskId,
    List<String> prerequisiteTaskIds, {
    Locale? locale,
  }) => _runEditableTaskSection(
    taskId: taskId,
    section: TaskSectionKind.prerequisites,
    locale: locale,
    onValidatedTask: (board, _, localizations) {
      final selectedIds = <String>{};
      for (final rawId in prerequisiteTaskIds) {
        final candidateId = rawId.trim();
        if (candidateId.isEmpty) {
          continue;
        }
        if (candidateId == taskId ||
            board.wouldCreateDependencyCycle(taskId, candidateId)) {
          return _failInlineValidation(
            taskId: taskId,
            section: TaskSectionKind.prerequisites,
            fieldErrors: <String, String>{
              'prerequisites': localizations.prerequisiteCyclePreventedHint,
            },
          );
        }
        selectedIds.add(candidateId);
      }
      final orderedIds = TaskScheduleHelper.collectOrderedBlockedByIds(
        board,
        selectedIds,
      );
      if (orderedIds.length > maxTdfArgsPerStmt) {
        return _failInlineValidation(
          taskId: taskId,
          section: TaskSectionKind.prerequisites,
          fieldErrors: <String, String>{
            'prerequisites': localizations.errorLocalFileTooLarge,
          },
        );
      }
      return _commitInlineSectionSave(
        taskId: taskId,
        section: TaskSectionKind.prerequisites,
        localizations: localizations,
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateTask(taskId, blockedByTaskIds: orderedIds),
      );
    },
  );

  /// Validates recurrence count (`1..3650`) and Mode 2 lead days (`0..3650`) and saves onto [taskId].
  Future<ActionResult> saveRepeat(
    String taskId, {
    required String rawCount,
    required RepeatUnit unit,
    required String rawLeadDays,
    Locale? locale,
  }) => _runEditableTaskSection(
    taskId: taskId,
    section: TaskSectionKind.repeat,
    locale: locale,
    onValidatedTask: (_, existingTask, localizations) {
      final fieldErrors = <String, String>{};
      final nextRule = _validateRepeatFields(
        hasDue: existingTask.dueAt != null,
        rawCount: rawCount,
        unit: unit,
        rawLeadDays: rawLeadDays,
        clock: existingTask.repeatRule?.clock ?? TdfRepeatClock.midnight,
        localizations: localizations,
        fieldErrors: fieldErrors,
      );
      if (fieldErrors.isNotEmpty || nextRule == null) {
        return _failInlineValidation(
          taskId: taskId,
          section: TaskSectionKind.repeat,
          fieldErrors: fieldErrors,
        );
      }
      return _commitInlineSectionSave(
        taskId: taskId,
        section: TaskSectionKind.repeat,
        localizations: localizations,
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateTask(taskId, repeatRule: nextRule),
      );
    },
  );

  /// Strips blanks, enforces `1024`/`500` subtask bounds, saves onto [taskId], and atomically auto-finishes in one persistence cycle when all remaining steps are complete.
  Future<ActionResult> saveSubtasks(
    String taskId,
    List<SubtaskItem> subtasks, {
    required bool autoFinish,
    Locale? locale,
  }) => _runEditableTaskSection(
    taskId: taskId,
    section: TaskSectionKind.subtasks,
    locale: locale,
    onValidatedTask: (_, existingTask, localizations) {
      final validated = TaskScheduleHelper.validateSubtasksList(
        subtasks: subtasks,
        localizations: localizations,
      );
      if (validated.error case final error?) {
        return _failInlineValidation(
          taskId: taskId,
          section: TaskSectionKind.subtasks,
          fieldErrors: <String, String>{'subtasks': error},
        );
      }
      final steps = validated.subtasks;
      final triggersAutoFinish =
          autoFinish &&
          steps.isNotEmpty &&
          steps.every((step) => step.isCompleted);
      if (!triggersAutoFinish) {
        return _commitInlineSectionSave(
          taskId: taskId,
          section: TaskSectionKind.subtasks,
          localizations: localizations,
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
      return _runGuardedMutation(
        busyTaskId: taskId,
        localizations: localizations,
        onPersistFailure: () => UiTelemetry.logInlineEditFailed(
          kind: 'task',
          entityId: taskId,
          section: TaskSectionKind.subtasks.name,
        ),
        action: (token) async {
          final committed = await ref
              .read(shellProvider.notifier)
              .runLocalEntityMutation(
                target,
                () => ref
                    .read(taskNotifierProvider.notifier)
                    .updateTaskAndComplete(
                      taskId,
                      subtasks: steps,
                      subtasksAutoFinish: true,
                    ),
              );
          if (!_isOperationActive(token)) {
            return ActionSucceeded(entityId: taskId);
          }
          if (!committed) {
            UiTelemetry.logInlineEditFailed(
              kind: 'task',
              entityId: taskId,
              section: TaskSectionKind.subtasks.name,
            );
            return ActionPersistFailed(
              message: _fallbackPersistError(localizations),
            );
          }
          UiTelemetry.logInlineEditSaved(
            kind: 'task',
            entityId: taskId,
            section: TaskSectionKind.subtasks.name,
          );
          return _finishCompletedTaskAction(
            taskId: taskId,
            taskBefore: existingTask,
            localizations: localizations,
          );
        },
      );
    },
  );

  /// Validates finite or indefinite deferral settings and deferral note, then saves onto [taskId].
  Future<ActionResult> saveSuspended(
    String taskId, {
    required bool indefinitely,
    required String rawUntil,
    required String rawNote,
    Locale? locale,
  }) => _runEditableTaskSection(
    taskId: taskId,
    section: TaskSectionKind.suspended,
    locale: locale,
    onValidatedTask: (_, existingTask, localizations) {
      final fieldErrors = <String, String>{};
      final suspendedDraft = _resolveSuspendedInput(
        indefinitely: indefinitely,
        rawUntil: rawUntil,
        existingTask: existingTask,
        configuration: _currentConfiguration,
      );
      if (!indefinitely &&
          (!suspendedDraft.isValid || suspendedDraft.isForever)) {
        fieldErrors['suspended'] = localizations.taskSuspendedErrorInvalid;
      }
      final normalizedNote = _validateOptionalSchedulingNote(
        rawNote: rawNote,
        fieldKey: 'suspendedNote',
        localizations: localizations,
        fieldErrors: fieldErrors,
      );
      if (fieldErrors.isNotEmpty) {
        return _failInlineValidation(
          taskId: taskId,
          section: TaskSectionKind.suspended,
          fieldErrors: fieldErrors,
        );
      }
      return _commitInlineSectionSave(
        taskId: taskId,
        section: TaskSectionKind.suspended,
        localizations: localizations,
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
              clearSuspendedNote: normalizedNote == null,
            ),
      );
    },
  );

  /// Validates single-line `<text>` rules and duplicate uniqueness, then saves [rawTitle] onto [taskId].
  Future<ActionResult> saveTitle(
    String taskId,
    String rawTitle, {
    Locale? locale,
  }) => _runEditableTaskSection(
    taskId: taskId,
    section: TaskSectionKind.title,
    locale: locale,
    onValidatedTask: (board, _, localizations) {
      final titleValidation = _validateTaskTitleInput(
        board: board,
        rawTitle: rawTitle,
        excludingTaskId: taskId,
        localizations: localizations,
      );
      if (titleValidation.error case final titleError?) {
        return _failInlineValidation(
          taskId: taskId,
          section: TaskSectionKind.title,
          fieldErrors: <String, String>{'title': titleError},
        );
      }
      return _commitInlineSectionSave(
        taskId: taskId,
        section: TaskSectionKind.title,
        localizations: localizations,
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateTask(taskId, title: titleValidation.trimmed),
      );
    },
  );

  /// Switches active [taskId] placement between [QuickAddMode.standard], [QuickAddMode.priority], and [QuickAddMode.someday], collapsing if it moved tiers.
  Future<ActionResult> setPlacement(
    String taskId,
    QuickAddMode placement, {
    Locale? locale,
  }) => _runTaskAction(
    taskId: taskId,
    locale: locale,
    requireOpen: true,
    run: (boardBefore, taskBefore, localizations, commit) {
      final shellBefore = ref.read(shellProvider);
      final tierBefore = _evaluatedBoardForLabel(shellBefore.activeLabelId)
          .findTierOfTask(taskId);
      final wasQueued = boardBefore.queueBlock.taskIds.contains(taskId);
      final wasPriority = taskBefore.isPriority;
      final placementTarget = _resolvePlacementTarget(placement);
      return commit(
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateTask(
              taskId,
              targetTier: placementTarget.targetTier,
              isPriority: placementTarget.isPriority,
            ),
        onCommitted: () {
          final shellAfter = ref.read(shellProvider);
          final tierAfter = _evaluatedBoardForLabel(shellAfter.activeLabelId)
              .findTierOfTask(taskId);
          if (tierAfter != tierBefore && !shellAfter.searchOpen) {
            _collapseIfExpanded(EntityRef(kind: EntityKind.task, id: taskId));
          }
          final noticeMessage = _resolvePlacementToggleNotice(
            placement: placement,
            wasQueued: wasQueued,
            wasPriority: wasPriority,
            tierAfter: tierAfter,
            activeTier: shellAfter.activeTier,
            localizations: localizations,
          );
          ref.read(floatingNoticeProvider.notifier).showNotice(noticeMessage);
          return ActionSucceeded(
            entityId: taskId,
            noticeMessage: noticeMessage,
          );
        },
      );
    },
  );

  /// Adds or removes [labelId] on [taskId], collapses if the task left the active view/tier, and emits a contextual toast.
  Future<ActionResult> toggleLabel(
    String taskId,
    String labelId, {
    Locale? locale,
  }) => _runTaskAction(
    taskId: taskId,
    locale: locale,
    requireOpen: true,
    run: (boardBefore, taskBefore, localizations, commit) {
      final label = boardBefore.findLabel(labelId);
      if (label == null) {
        return Future<ActionResult>.value(
          ActionValidationFailed(
            message: localizations.entityRemovedExternallyNotice,
          ),
        );
      }
      final isRemoving = taskBefore.labelIds.contains(labelId);
      final nextSet = taskBefore.labelIds.toSet();
      if (isRemoving) {
        nextSet.remove(labelId);
      } else {
        nextSet.add(labelId);
      }
      final nextLabelIds = TaskScheduleHelper.collectOrderedLabelIds(
        boardBefore,
        nextSet,
      );
      if (nextLabelIds.length > maxTdfArgsPerStmt) {
        return Future<ActionResult>.value(
          ActionValidationFailed(message: localizations.errorLocalFileTooLarge),
        );
      }
      final shellBefore = ref.read(shellProvider);
      final tierBefore = _evaluatedBoardForLabel(shellBefore.activeLabelId)
          .findTierOfTask(taskId);
      return commit(
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateTask(taskId, labelIds: nextLabelIds),
        onCommitted: () {
          final boardAfter = _currentBoard;
          final taskAfter = boardAfter.findTask(taskId);
          final shellAfter = ref.read(shellProvider);
          final tierAfter = _evaluatedBoardForLabel(shellAfter.activeLabelId)
              .findTierOfTask(taskId);
          final leftCurrentView =
              tierAfter == null ||
              (!shellAfter.searchOpen && tierAfter != shellAfter.activeTier);
          if (leftCurrentView) {
            _collapseIfExpanded(EntityRef(kind: EntityKind.task, id: taskId));
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
              ? localizations.noticeTaskMovedToScopedQueue(
                  restrictingScopedName,
                )
              : (isRemoving
                    ? localizations.noticeLabelRemoved(label.name)
                    : localizations.noticeLabelAdded(label.name));
          ref.read(floatingNoticeProvider.notifier).showNotice(noticeMessage);
          return ActionSucceeded(
            entityId: taskId,
            noticeMessage: noticeMessage,
          );
        },
      );
    },
  );

  /// Toggles subtask step [stepIndex] on [taskId] inside `runLocalEntityMutation`, collapsing on auto-finish completion.
  Future<ActionResult> toggleSubtask(
    String taskId,
    int stepIndex, {
    Locale? locale,
  }) => _runTaskAction(
    taskId: taskId,
    locale: locale,
    requireOpen: true,
    run: (_, taskBefore, localizations, commit) {
      if (stepIndex < 0 || stepIndex >= taskBefore.subtasks.length) {
        return Future<ActionResult>.value(
          ActionValidationFailed(
            message: localizations.historyErrorTextInvalid,
          ),
        );
      }
      return commit(
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .toggleSubtask(taskId, stepIndex),
        onCommitted: () {
          final taskAfter = _currentBoard.findTask(taskId);
          final didAutoComplete =
              taskAfter != null &&
              (taskAfter.completions > taskBefore.completions ||
                  (!taskBefore.isCompleted && taskAfter.isCompleted));
          if (didAutoComplete) {
            return _finishCompletedTaskAction(
              taskId: taskId,
              taskBefore: taskBefore,
              localizations: localizations,
            );
          }
          return ActionSucceeded(entityId: taskId);
        },
      );
    },
  );

  /// Validates and replaces an existing `(oldTimestampUtcIso, oldText)` history entry on [taskId], rejecting duplicates.
  Future<ActionResult> updateHistoryEntry(
    String taskId, {
    required String oldTimestampUtcIso,
    required String oldText,
    required String rawNewText,
    required String rawNewTimestamp,
    Locale? locale,
  }) => _runTaskAction(
    taskId: taskId,
    locale: locale,
    suppressLocalWatch: false,
    run: (_, task, localizations, commit) {
      final oldTimestampUtc = DateTime.tryParse(oldTimestampUtcIso)?.toUtc();
      if (oldTimestampUtc == null) {
        return Future<ActionResult>.value(
          ActionValidationFailed(
            message: localizations.historyErrorTimestampInvalid,
          ),
        );
      }
      final oldEntry = TaskHistoryEntry(
        timestampUtc: oldTimestampUtc,
        text: oldText,
      );
      if (!task.history.contains(oldEntry)) {
        return Future<ActionResult>.value(
          ActionValidationFailed(
            message: localizations.entityRemovedExternallyNotice,
          ),
        );
      }
      final configuration = _currentConfiguration;
      final validated = _validateHistoryCandidate(
        task: task,
        rawText: rawNewText,
        rawTimestamp: rawNewTimestamp,
        configuration: configuration,
        fallbackNowUtc: ref.read(clockProvider)().toUtc(),
        preservedTimestampText: TaskScheduleHelper.formatLocalTimestamp(
          oldEntry.timestampUtc,
          configuration,
        ),
        preservedTimestampUtc: oldEntry.timestampUtc,
        ignoringDuplicateEntry: oldEntry,
        localizations: localizations,
      );
      if (validated.failure case final failure?) {
        return Future<ActionResult>.value(failure);
      }
      final replacement = validated.entry;
      if (replacement == null) {
        return Future<ActionResult>.value(
          ActionValidationFailed(
            message: localizations.historyErrorTextInvalid,
          ),
        );
      }
      if (replacement == oldEntry) {
        return Future<ActionResult>.value(ActionSucceeded(entityId: taskId));
      }
      return commit(
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateTaskHistoryEntry(
              taskId,
              oldTimestampUtc: oldEntry.timestampUtc,
              oldText: oldEntry.text,
              newTimestampUtc: replacement.timestampUtc,
              newText: replacement.text,
            ),
      );
    },
  );

  /// Collapses the currently expanded card when it matches [target].
  void _collapseIfExpanded(EntityRef target) {
    if (ref.read(shellProvider).expandedEntity == target) {
      ref.read(shellProvider.notifier).collapseEntity();
    }
  }

  /// Collapses [taskId] if it is currently expanded and left the active tier/filter view.
  void _collapseIfExpandedAndLeftActiveView(String taskId) {
    final shell = ref.read(shellProvider);
    final target = EntityRef(kind: EntityKind.task, id: taskId);
    if (shell.expandedEntity != target) {
      return;
    }
    final tierAfter = _evaluatedBoardForLabel(shell.activeLabelId)
        .findTierOfTask(taskId);
    final leftView =
        tierAfter == null ||
        (!shell.searchOpen && tierAfter != shell.activeTier);
    if (leftView) {
      ref.read(shellProvider.notifier).collapseEntity();
    }
  }

  /// Executes the guarded inline persistence pass for a pre-validated [taskId] and [section].
  Future<ActionResult> _commitInlineSectionSave({
    required String taskId,
    required TaskSectionKind section,
    required AppLocalizations localizations,
    required Future<bool> Function() persist,
  }) {
    final shellBefore = ref.read(shellProvider);
    final tierBefore = _evaluatedBoardForLabel(shellBefore.activeLabelId)
        .findTierOfTask(taskId);
    final target = EntityRef(kind: EntityKind.task, id: taskId);

    return _runGuardedMutation(
      busyTaskId: taskId,
      localizations: localizations,
      onPersistFailure: () => UiTelemetry.logInlineEditFailed(
        kind: 'task',
        entityId: taskId,
        section: section.name,
      ),
      action: (token) async {
        final committed = await ref
            .read(shellProvider.notifier)
            .runLocalEntityMutation(target, persist);
        if (!_isOperationActive(token)) {
          return ActionSucceeded(entityId: taskId);
        }
        if (!committed) {
          UiTelemetry.logInlineEditFailed(
            kind: 'task',
            entityId: taskId,
            section: section.name,
          );
          return ActionPersistFailed(
            message: _fallbackPersistError(localizations),
          );
        }
        UiTelemetry.logInlineEditSaved(
          kind: 'task',
          entityId: taskId,
          section: section.name,
        );
        final shellAfter = ref.read(shellProvider);
        if (shellAfter.activeInlineEdit?.entity == target) {
          ref.read(shellProvider.notifier).closeInlineEdit();
        }
        final tierAfter = _evaluatedBoardForLabel(shellAfter.activeLabelId)
            .findTierOfTask(taskId);
        final movedTiers = tierAfter != tierBefore;
        if (movedTiers &&
            !shellAfter.searchOpen &&
            tierAfter != shellAfter.activeTier) {
          _collapseIfExpanded(target);
        }
        final noticeMessage =
            (movedTiers &&
                tierAfter != null &&
                tierAfter != shellAfter.activeTier)
            ? localizations.noticeTaskSavedInTier(
                localizations.tierName(tierAfter),
              )
            : localizations.noticeTaskSaved;
        if (movedTiers) {
          ref.read(floatingNoticeProvider.notifier).showNotice(noticeMessage);
        }
        return ActionSucceeded(entityId: taskId, noticeMessage: noticeMessage);
      },
    );
  }

  /// Persists a newly validated task identified by [newTaskId], runs optional [onCreated], and emits its non-jumping placement notice.
  Future<ActionResult> _commitTaskCreation({
    required String newTaskId,
    required AppLocalizations localizations,
    required Future<bool> Function() persist,
    VoidCallback? onCreated,
  }) => _runGuardedMutation(
    localizations: localizations,
    action: (token) async {
      final committed = await persist();
      if (!_isOperationActive(token)) {
        return ActionSucceeded(entityId: newTaskId);
      }
      if (!committed) {
        return ActionPersistFailed(
          message: _fallbackPersistError(localizations),
        );
      }
      final boardAfter = _currentBoard;
      final createdTask = boardAfter.findTask(newTaskId);
      if (createdTask == null) {
        return ActionPersistFailed(
          message: _fallbackPersistError(localizations),
        );
      }
      onCreated?.call();
      final noticeMessage = _resolveTaskPlacementNotice(
        board: boardAfter,
        task: createdTask,
        localizations: localizations,
      );
      ref.read(floatingNoticeProvider.notifier).showNotice(noticeMessage);
      return ActionSucceeded(
        entityId: createdTask.id,
        noticeMessage: noticeMessage,
      );
    },
  );

  /// Reads the context-evaluated [TaskBoard] for [activeLabelId] from [evaluatedBoardProvider].
  TaskBoard _evaluatedBoardForLabel(String? activeLabelId) =>
      ref.read(evaluatedBoardProvider(activeLabelId)).asData?.value ??
      _currentBoard;

  /// Logs inline validation failure telemetry for [taskId] and [section] and returns [ActionValidationFailed].
  Future<ActionResult> _failInlineValidation({
    required String taskId,
    required TaskSectionKind section,
    required Map<String, String> fieldErrors,
  }) async {
    UiTelemetry.logInlineEditFailed(
      kind: 'task',
      entityId: taskId,
      section: section.name,
    );
    return ActionValidationFailed(
      message: fieldErrors.values.first,
      fieldErrors: fieldErrors,
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

  /// Collapses [taskId] after completion or auto-finish and emits the repeating-task reschedule notice when applicable.
  ActionSucceeded _finishCompletedTaskAction({
    required String taskId,
    required TaskItem taskBefore,
    required AppLocalizations localizations,
  }) {
    _collapseIfExpanded(EntityRef(kind: EntityKind.task, id: taskId));
    if (taskBefore.repeatRule != null) {
      final repeatNotice = localizations.taskCompletedRepeatNotice(
        taskBefore.title,
      );
      ref.read(floatingNoticeProvider.notifier).showNotice(repeatNotice);
      return ActionSucceeded(entityId: taskId, noticeMessage: repeatNotice);
    }
    return ActionSucceeded(entityId: taskId);
  }

  /// Resets in-flight busy state and invalidates stale operation tokens on actual workspace switches, ignoring transient `AsyncLoading`.
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
    if (!switchedWorkspace) {
      return;
    }
    _operationToken++;
    if (state != const BoardActionsState()) {
      state = const BoardActionsState();
    }
  }

  /// Returns `true` when this notifier is still mounted and [token] belongs to the active workspace session.
  bool _isOperationActive(int token) => ref.mounted && _operationToken == token;

  /// Checks busy guard, task existence, and open-state editability before an inline section save.
  ({TaskItem? task, ActionResult? failure}) _requireEditableTask({
    required String taskId,
    required TaskSectionKind section,
    required AppLocalizations localizations,
  }) {
    final checked = _requireTask(
      taskId: taskId,
      localizations: localizations,
      requireOpen: true,
    );
    if (checked.failure case final failure?) {
      if (failure is ActionValidationFailed) {
        UiTelemetry.logInlineEditFailed(
          kind: 'task',
          entityId: taskId,
          section: section.name,
        );
      }
      return (task: null, failure: failure);
    }
    return (task: checked.task, failure: null);
  }

  /// Checks busy guard, task presence on the current board, and optional open-state requirement for [taskId].
  ({TaskBoard board, TaskItem? task, ActionResult? failure}) _requireTask({
    required String taskId,
    required AppLocalizations localizations,
    bool requireOpen = false,
  }) {
    final board = _currentBoard;
    if (state.isBusy) {
      return (
        board: board,
        task: null,
        failure: ActionPersistFailed(message: localizations.syncStatusSyncing),
      );
    }
    final task = board.findTask(taskId);
    if (task == null) {
      return (
        board: board,
        task: null,
        failure: ActionValidationFailed(
          message: localizations.entityRemovedExternallyNotice,
        ),
      );
    }
    if (requireOpen && (task.isCompleted || task.completedAt != null)) {
      return (
        board: board,
        task: null,
        failure: ActionValidationFailed(
          message: localizations.completedReadOnlyPill,
        ),
      );
    }
    return (board: board, task: task, failure: null);
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
    final initialSuspendedText = TaskScheduleHelper.formatInitialSuspendedText(
      existingTask.suspendedAt,
      configuration,
    );
    return TaskScheduleHelper.resolveSuspendedDraft(
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
    final shell = ref.read(shellProvider);
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
    final evaluated = _evaluatedBoardForLabel(activeLabelId);
    final landedTier =
        evaluated.findTierOfTask(task.id) ??
        (activeLabelId != null
            ? _evaluatedBoardForLabel(null).findTierOfTask(task.id)
            : null);
    if (landedTier != null && landedTier != shell.activeTier) {
      return localizations.noticeTaskSavedInTier(
        localizations.tierName(landedTier),
      );
    }
    return localizations.noticeTaskSaved;
  }

  /// Verifies [taskId] is editable for [section] once and runs [onValidatedTask].
  Future<ActionResult> _runEditableTaskSection({
    required String taskId,
    required TaskSectionKind section,
    required Locale? locale,
    required Future<ActionResult> Function(
      TaskBoard board,
      TaskItem existingTask,
      AppLocalizations localizations,
    )
    onValidatedTask,
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
    final existingTask = checked.task;
    if (existingTask == null) {
      return ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    return onValidatedTask(_currentBoard, existingTask, localizations);
  }

  /// Executes [action] under the in-flight `isBusy` guard, mapping domain/calendar exceptions to [ActionPersistFailed].
  Future<ActionResult> _runGuardedMutation({
    String? busyTaskId,
    required AppLocalizations localizations,
    VoidCallback? onPersistFailure,
    required Future<ActionResult> Function(int token) action,
  }) async {
    if (state.isBusy) {
      return ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final token = _operationToken;
    state = BoardActionsState(isBusy: true, busyTaskId: busyTaskId);
    try {
      return await action(token);
    } on TdfException catch (error) {
      onPersistFailure?.call();
      return ActionPersistFailed(
        message: TaskScheduleHelper.mapTdfExceptionMessage(
          error.kind,
          localizations,
        ),
      );
    } on TdfContextException {
      onPersistFailure?.call();
      return ActionPersistFailed(
        message: localizations.taskSuspendedErrorInvalid,
      );
    } on FormatException {
      onPersistFailure?.call();
      return ActionPersistFailed(
        message: localizations.taskSuspendedErrorInvalid,
      );
    } finally {
      if (_isOperationActive(token)) {
        state = const BoardActionsState();
      }
    }
  }

  /// Validates [taskId] editability and executes a parameterless inline section clear/disable save.
  Future<ActionResult> _runInlineSectionSave({
    required String taskId,
    required TaskSectionKind section,
    required Locale? locale,
    required Future<bool> Function() persist,
  }) => _runEditableTaskSection(
    taskId: taskId,
    section: section,
    locale: locale,
    onValidatedTask: (_, _, localizations) => _commitInlineSectionSave(
      taskId: taskId,
      section: section,
      localizations: localizations,
      persist: persist,
    ),
  );

  /// Runs a guarded live task mutation with shared busy/lookup/open checks, local-watch suppression, and post-commit handling.
  Future<ActionResult> _runTaskAction({
    required String taskId,
    required Locale? locale,
    bool requireOpen = false,
    bool suppressLocalWatch = true,
    required Future<ActionResult> Function(
      TaskBoard boardBefore,
      TaskItem taskBefore,
      AppLocalizations localizations,
      Future<ActionResult> Function({
        required Future<bool> Function() persist,
        ActionResult Function()? onCommitted,
      })
      commit,
    )
    run,
  }) async {
    final localizations = _resolveLocalizations(locale);
    final checked = _requireTask(
      taskId: taskId,
      localizations: localizations,
      requireOpen: requireOpen,
    );
    if (checked.failure case final failure?) {
      return failure;
    }
    final boardBefore = checked.board;
    final taskBefore = checked.task;
    if (taskBefore == null) {
      return ActionValidationFailed(
        message: localizations.entityRemovedExternallyNotice,
      );
    }
    final target = EntityRef(kind: EntityKind.task, id: taskId);
    return run(boardBefore, taskBefore, localizations, ({
      required Future<bool> Function() persist,
      ActionResult Function()? onCommitted,
    }) {
      return _runGuardedMutation(
        busyTaskId: taskId,
        localizations: localizations,
        action: (token) async {
          final committed = suppressLocalWatch
              ? await ref
                    .read(shellProvider.notifier)
                    .runLocalEntityMutation(target, persist)
              : await persist();
          if (!_isOperationActive(token)) {
            return ActionSucceeded(entityId: taskId);
          }
          if (!committed) {
            return ActionPersistFailed(
              message: _fallbackPersistError(localizations),
            );
          }
          return onCommitted?.call() ?? ActionSucceeded(entityId: taskId);
        },
      );
    });
  }
}

/// Immutable in-flight concurrency state exposed by [boardActionsProvider].
@immutable
class BoardActionsState {
  /// Creates a [BoardActionsState].
  const BoardActionsState({this.isBusy = false, this.busyTaskId});

  /// Identifier of the task currently being mutated, or `null` for task creation or idle state.
  final String? busyTaskId;

  /// Whether an asynchronous task mutation is currently in flight.
  final bool isBusy;

  /// Returns a copy of this [BoardActionsState] with updated fields.
  BoardActionsState copyWith({
    bool? isBusy,
    String? busyTaskId,
    bool clearBusyTaskId = false,
  }) {
    return BoardActionsState(
      isBusy: isBusy ?? this.isBusy,
      busyTaskId: clearBusyTaskId ? null : (busyTaskId ?? this.busyTaskId),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BoardActionsState &&
        other.isBusy == isBusy &&
        other.busyTaskId == busyTaskId;
  }

  @override
  int get hashCode => Object.hash(isBusy, busyTaskId);
}

/// Immutable domain-typed draft payload submitted by the Task Draft Card (`U-CARD-006`).
@immutable
class TaskDraftInput {
  /// Creates a [TaskDraftInput].
  TaskDraftInput({
    required this.title,
    this.note = '',
    this.placement = QuickAddMode.standard,
    Iterable<String> labelIds = const <String>[],
    Iterable<TaskLink> links = const <TaskLink>[],
    Iterable<SubtaskItem> subtasks = const <SubtaskItem>[],
    this.subtasksAutoFinish = false,
    this.rawDue = '',
    this.autoPrioritizeDue = true,
    this.rawDueNote = '',
    this.isRepeating = false,
    this.rawRepeatCount = '1',
    this.repeatUnit = RepeatUnit.days,
    this.rawRepeatLeadDays = '0',
    this.isSuspended = false,
    this.suspendedIndefinitely = false,
    this.rawSuspendedUntil = '',
    this.rawSuspendedNote = '',
    Iterable<String> prerequisiteTaskIds = const <String>[],
    ConditionDraft? conditions,
  }) : labelIds = List<String>.unmodifiable(labelIds),
       links = List<TaskLink>.unmodifiable(links),
       subtasks = List<SubtaskItem>.unmodifiable(subtasks),
       prerequisiteTaskIds = List<String>.unmodifiable(prerequisiteTaskIds),
       conditions = conditions ?? ConditionDraft();

  /// Whether deadline lead-window auto-prioritization is enabled (`!isDuePassive`).
  final bool autoPrioritizeDue;

  /// Activation conditions draft configured on the task.
  final ConditionDraft conditions;

  /// Whether recurrence is enabled on the new task.
  final bool isRepeating;

  /// Whether deferral is enabled on the new task.
  final bool isSuspended;

  /// Assigned label identifiers.
  final List<String> labelIds;

  /// Reference links attached to the new task.
  final List<TaskLink> links;

  /// Raw multi-line task note text.
  final String note;

  /// Target placement mode ([QuickAddMode.standard], [QuickAddMode.priority], or [QuickAddMode.someday]).
  final QuickAddMode placement;

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

  /// Selected recurrence unit ([RepeatUnit.days], [RepeatUnit.weeks], or [RepeatUnit.months]).
  final RepeatUnit repeatUnit;

  /// Draft subtasks list.
  final List<SubtaskItem> subtasks;

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
    QuickAddMode? placement,
    Iterable<String>? labelIds,
    Iterable<TaskLink>? links,
    Iterable<SubtaskItem>? subtasks,
    bool? subtasksAutoFinish,
    String? rawDue,
    bool? autoPrioritizeDue,
    String? rawDueNote,
    bool? isRepeating,
    String? rawRepeatCount,
    RepeatUnit? repeatUnit,
    String? rawRepeatLeadDays,
    bool? isSuspended,
    bool? suspendedIndefinitely,
    String? rawSuspendedUntil,
    String? rawSuspendedNote,
    Iterable<String>? prerequisiteTaskIds,
    ConditionDraft? conditions,
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
      conditions: conditions ?? this.conditions,
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
        other.conditions == conditions;
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
    conditions,
  ]);
}

/// Validated draft payload record produced by [_validateTaskDraft].
typedef _ValidatedTaskDraft = ({
  List<TaskCondition> conditions,
  TdfLocalDateTime? dueLocalInput,
  String? dueNote,
  Map<String, String> fieldErrors,
  bool hasDue,
  bool isSuspendedForever,
  List<String> labelIds,
  List<TaskLink> links,
  String? normalizedNote,
  List<String> prerequisiteIds,
  TaskRepeatRule? repeatRule,
  List<SubtaskItem> subtasks,
  TdfLocalDateTime? suspendedLocalInput,
  String? suspendedNote,
  String trimmedTitle,
});

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

/// Maps [QuickAddMode] to `TaskNotifier.addTask` / `updateTask` target tier and priority parameters.
({TaskTier targetTier, bool isPriority}) _resolvePlacementTarget(
  QuickAddMode placement,
) {
  return switch (placement) {
    QuickAddMode.standard => (targetTier: TaskTier.planned, isPriority: false),
    QuickAddMode.priority => (targetTier: TaskTier.planned, isPriority: true),
    QuickAddMode.someday => (targetTier: TaskTier.someday, isPriority: false),
  };
}

/// Resolves the localized confirmation message after switching live task placement.
String _resolvePlacementToggleNotice({
  required QuickAddMode placement,
  required bool wasQueued,
  required bool wasPriority,
  required TaskTier? tierAfter,
  required TaskTier activeTier,
  required AppLocalizations localizations,
}) {
  return switch (placement) {
    QuickAddMode.someday => localizations.noticeMovedToSomeday,
    QuickAddMode.priority => localizations.noticePriorityEnabled,
    QuickAddMode.standard =>
      !wasQueued
          ? localizations.noticeMovedToQueue
          : (wasPriority
                ? localizations.noticePriorityDisabled
                : (tierAfter != null && tierAfter != activeTier
                      ? localizations.noticeTaskSavedInTier(
                          localizations.tierName(tierAfter),
                        )
                      : localizations.noticeMovedToQueue)),
  };
}

/// Validates optional `due` timestamp and `dueNote` fields on [input], recording errors in [fieldErrors].
({bool hasDue, TdfLocalDateTime? dueLocalInput, String? dueNote})
_validateDraftDue({
  required TaskDraftInput input,
  required WebDavConfig configuration,
  required AppLocalizations localizations,
  required Map<String, String> fieldErrors,
}) {
  if (input.rawDue.trim().isEmpty) {
    return (hasDue: false, dueLocalInput: null, dueNote: null);
  }
  final parsedDue = TaskScheduleHelper.tryParseLocalDateTimeInput(
    input.rawDue,
    configuration,
  );
  if (parsedDue == null) {
    fieldErrors['due'] = localizations.taskSuspendedErrorInvalid;
  }
  final dueNote = _validateOptionalSchedulingNote(
    rawNote: input.rawDueNote,
    fieldKey: 'dueNote',
    localizations: localizations,
    fieldErrors: fieldErrors,
  );
  return (hasDue: true, dueLocalInput: parsedDue?.localInput, dueNote: dueNote);
}

/// Validates optional deferral mode, timestamp, and `suspendedNote` on [input], recording errors in [fieldErrors].
({
  bool isSuspendedForever,
  TdfLocalDateTime? suspendedLocalInput,
  String? suspendedNote,
})
_validateDraftSuspended({
  required TaskDraftInput input,
  required WebDavConfig configuration,
  required AppLocalizations localizations,
  required Map<String, String> fieldErrors,
}) {
  if (!input.isSuspended) {
    return (
      isSuspendedForever: false,
      suspendedLocalInput: null,
      suspendedNote: null,
    );
  }
  TdfLocalDateTime? suspendedLocalInput;
  if (!input.suspendedIndefinitely) {
    final parsedSuspended = TaskScheduleHelper.tryParseLocalDateTimeInput(
      input.rawSuspendedUntil,
      configuration,
    );
    if (parsedSuspended == null) {
      fieldErrors['suspended'] = localizations.taskSuspendedErrorInvalid;
    } else {
      suspendedLocalInput = parsedSuspended.localInput;
    }
  }
  final suspendedNote = _validateOptionalSchedulingNote(
    rawNote: input.rawSuspendedNote,
    fieldKey: 'suspendedNote',
    localizations: localizations,
    fieldErrors: fieldErrors,
  );
  return (
    isSuspendedForever: input.suspendedIndefinitely,
    suspendedLocalInput: suspendedLocalInput,
    suspendedNote: suspendedNote,
  );
}

/// Validates a candidate history journal entry's text, timestamp, and uniqueness on [task].
({TaskHistoryEntry? entry, ActionValidationFailed? failure})
_validateHistoryCandidate({
  required TaskItem task,
  required String rawText,
  required String rawTimestamp,
  required WebDavConfig configuration,
  required DateTime fallbackNowUtc,
  String? preservedTimestampText,
  DateTime? preservedTimestampUtc,
  TaskHistoryEntry? ignoringDuplicateEntry,
  required AppLocalizations localizations,
}) {
  final sanitizedText = TaskScheduleHelper.sanitizeHistoryText(rawText);
  final textError = TaskScheduleHelper.validateHistoryText(
    sanitizedText,
    localizations,
  );
  if (textError != null) {
    return (
      entry: null,
      failure: ActionValidationFailed(
        message: textError,
        fieldErrors: <String, String>{'text': textError},
      ),
    );
  }
  final resolvedTimestampUtc = TaskScheduleHelper.resolveHistoryTimestampUtc(
    configuration: configuration,
    fallbackNowUtc: fallbackNowUtc,
    preservedTimestampText: preservedTimestampText,
    preservedTimestampUtc: preservedTimestampUtc,
    rawTimestamp: rawTimestamp,
  );
  if (resolvedTimestampUtc == null) {
    return (
      entry: null,
      failure: ActionValidationFailed(
        message: localizations.historyErrorTimestampInvalid,
        fieldErrors: <String, String>{
          'timestamp': localizations.historyErrorTimestampInvalid,
        },
      ),
    );
  }
  final candidate = TaskHistoryEntry(
    timestampUtc: resolvedTimestampUtc,
    text: sanitizedText,
  );
  if (candidate != ignoringDuplicateEntry && task.history.contains(candidate)) {
    return (
      entry: null,
      failure: ActionValidationFailed(
        message: localizations.historyErrorDuplicate,
        fieldErrors: <String, String>{
          'text': localizations.historyErrorDuplicate,
        },
      ),
    );
  }
  return (entry: candidate, failure: null);
}

/// Normalizes and validates an optional scheduling or body note, recording any error under [fieldKey] in [fieldErrors].
String? _validateOptionalSchedulingNote({
  required String rawNote,
  required String fieldKey,
  required AppLocalizations localizations,
  required Map<String, String> fieldErrors,
}) {
  final normalized = TaskScheduleHelper.normalizeSchedulingNote(rawNote);
  final error = TaskScheduleHelper.validateSchedulingNote(
    normalized,
    localizations,
  );
  if (error != null) {
    fieldErrors[fieldKey] = error;
  }
  return normalized;
}

/// Validates recurrence count (`1..3650`) and Mode 2 lead days (`0..3650`), recording errors in [fieldErrors].
TaskRepeatRule? _validateRepeatFields({
  required bool hasDue,
  required String rawCount,
  required RepeatUnit unit,
  required String rawLeadDays,
  required TdfRepeatClock clock,
  required AppLocalizations localizations,
  required Map<String, String> fieldErrors,
}) {
  final parsedCount = TaskScheduleHelper.parseRepeatCount(
    isRepeating: true,
    rawCount: rawCount,
  );
  final parsedLeadDays = TaskScheduleHelper.parseLeadDays(
    hasDue: hasDue,
    isRepeating: true,
    rawLeadDays: rawLeadDays,
  );
  if (parsedCount == null) {
    fieldErrors['repeatCount'] = localizations.repeatErrorInvalid;
  }
  if (parsedLeadDays == null) {
    fieldErrors['repeatLeadDays'] = localizations.repeatLeadDaysErrorInvalid;
  }
  if (parsedCount == null || parsedLeadDays == null) {
    return null;
  }
  return TaskRepeatRule(
    count: parsedCount,
    unit: unit,
    clock: clock,
    leadDays: parsedLeadDays,
  );
}

/// Validates every populated field of [input] against TDF `0.8.0` bounds and domain rules.
_ValidatedTaskDraft _validateTaskDraft({
  required TaskDraftInput input,
  required TaskBoard board,
  required WebDavConfig configuration,
  required AppLocalizations localizations,
}) {
  final fieldErrors = <String, String>{};
  final titleValidation = _validateTaskTitleInput(
    board: board,
    rawTitle: input.title,
    excludingTaskId: null,
    localizations: localizations,
  );
  if (titleValidation.error case final titleError?) {
    fieldErrors['title'] = titleError;
  }

  final normalizedNote = _validateOptionalSchedulingNote(
    rawNote: input.note,
    fieldKey: 'note',
    localizations: localizations,
    fieldErrors: fieldErrors,
  );

  final linksCheck = TaskScheduleHelper.validateLinksList(
    links: input.links,
    localizations: localizations,
  );
  if (linksCheck.error case final linkError?) {
    fieldErrors['links'] = linkError;
  }

  final subtasksCheck = TaskScheduleHelper.validateSubtasksList(
    subtasks: input.subtasks,
    localizations: localizations,
  );
  if (subtasksCheck.error case final subtaskError?) {
    fieldErrors['subtasks'] = subtaskError;
  }

  final dueCheck = _validateDraftDue(
    input: input,
    configuration: configuration,
    localizations: localizations,
    fieldErrors: fieldErrors,
  );
  final repeatRule = input.isRepeating
      ? _validateRepeatFields(
          hasDue: dueCheck.hasDue,
          rawCount: input.rawRepeatCount,
          unit: input.repeatUnit,
          rawLeadDays: input.rawRepeatLeadDays,
          clock: TdfRepeatClock.midnight,
          localizations: localizations,
          fieldErrors: fieldErrors,
        )
      : null;
  final suspendedCheck = _validateDraftSuspended(
    input: input,
    configuration: configuration,
    localizations: localizations,
    fieldErrors: fieldErrors,
  );

  final orderedLabelIds = TaskScheduleHelper.collectOrderedLabelIds(
    board,
    input.labelIds.toSet(),
  );
  if (orderedLabelIds.length > maxTdfArgsPerStmt) {
    fieldErrors['labels'] = localizations.errorLocalFileTooLarge;
  }

  final orderedPrerequisites = TaskScheduleHelper.collectOrderedBlockedByIds(
    board,
    input.prerequisiteTaskIds.toSet(),
  );
  if (orderedPrerequisites.length > maxTdfArgsPerStmt) {
    fieldErrors['prerequisites'] = localizations.errorLocalFileTooLarge;
  }

  final compiledConditions = TaskScheduleHelper.compileConditionDraft(
    draft: input.conditions,
    board: board,
    isTask: true,
    localizations: localizations,
  );
  if (compiledConditions.error case final conditionError?) {
    fieldErrors['conditions'] = conditionError;
  }

  return (
    trimmedTitle: titleValidation.trimmed,
    normalizedNote: normalizedNote,
    labelIds: orderedLabelIds,
    links: linksCheck.links,
    subtasks: subtasksCheck.subtasks,
    hasDue: dueCheck.hasDue,
    dueLocalInput: dueCheck.dueLocalInput,
    dueNote: dueCheck.dueNote,
    repeatRule: repeatRule,
    isSuspendedForever: suspendedCheck.isSuspendedForever,
    suspendedLocalInput: suspendedCheck.suspendedLocalInput,
    suspendedNote: suspendedCheck.suspendedNote,
    prerequisiteIds: orderedPrerequisites,
    conditions: compiledConditions.conditions,
    fieldErrors: fieldErrors,
  );
}

/// Validates a task title against single-line `<text>` bounds and case-insensitive uniqueness on [board].
({String trimmed, String? error}) _validateTaskTitleInput({
  required TaskBoard board,
  required String rawTitle,
  required String? excludingTaskId,
  required AppLocalizations localizations,
}) {
  final textCheck = TaskScheduleHelper.validateSingleLineText(
    rawText: rawTitle,
    emptyError: localizations.taskNameErrorEmpty,
    invalidError: localizations.historyErrorTextInvalid,
    tooLongError: localizations.historyErrorTextTooLong,
  );
  final error =
      textCheck.error ??
      TaskScheduleHelper.validateTaskTitle(
        board: board,
        rawTitle: textCheck.trimmed,
        excludingTaskId: excludingTaskId,
        localizations: localizations,
      );
  return (trimmed: textCheck.trimmed, error: error);
}
