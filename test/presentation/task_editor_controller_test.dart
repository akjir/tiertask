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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/task_editor_controller.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/services/app_logger.dart';

class _RecordingTaskNotifier extends TaskNotifier {
  Object? errorToThrow;
  String? lastAddedTitle;
  List<TaskHistoryEntry>? lastAddedHistory;
  String? lastUpdatedId;
  bool? lastUpdatedIsDuePassive;
  final List<String> deletedIds = <String>[];

  @override
  Future<TaskBoard> build() async => TaskBoard.empty();

  @override
  Future<void> addTask(
    String title, {
    String? note,
    TaskTier targetTier = TaskTier.planned,
    bool isPriority = false,
    bool subtasksAutoFinish = false,
    List<SubtaskItem> subtasks = const <SubtaskItem>[],
    List<String> labelIds = const <String>[],
    DateTime? dueAt,
    TdfLocalDateTime? dueLocalInput,
    TdfLocalDateTime? dueAnchor,
    bool isDuePassive = false,
    String? dueNote,
    TaskOrigin? origin,
    DateTime? suspendedAt,
    TdfLocalDateTime? suspendedLocalInput,
    bool isSuspendedForever = false,
    String? suspendedNote,
    TaskRepeatRule? repeatRule,
    List<String> blockedByTaskIds = const <String>[],
    List<TdfTaskDependency>? dependencies,
    List<TaskLink> links = const <TaskLink>[],
    Iterable<TaskHistoryEntry>? history,
    List<TaskCondition> conditions = const <TaskCondition>[],
    DateTime? currentDate,
    String? id,
  }) async {
    if (errorToThrow case final error?) {
      throw error;
    }
    lastAddedTitle = title;
    lastAddedHistory = history?.toList();
  }

  @override
  Future<void> deleteTask(String taskId, {DateTime? currentDate}) async {
    deletedIds.add(taskId);
  }

  @override
  Future<void> updateTask(
    String taskId, {
    String? title,
    String? note,
    TaskTier? targetTier,
    bool? isPriority,
    bool? subtasksAutoFinish,
    List<SubtaskItem>? subtasks,
    List<String>? labelIds,
    DateTime? dueAt,
    TdfLocalDateTime? dueLocalInput,
    TdfLocalDateTime? dueAnchor,
    bool? isDuePassive,
    String? dueNote,
    bool clearDueAt = false,
    bool clearDueAnchor = false,
    bool clearDueNote = false,
    TaskOrigin? origin,
    bool clearOrigin = false,
    DateTime? suspendedAt,
    TdfLocalDateTime? suspendedLocalInput,
    bool? isSuspendedForever,
    String? suspendedNote,
    bool clearSuspendedAt = false,
    bool clearSuspendedNote = false,
    TaskRepeatRule? repeatRule,
    bool clearRepeatRule = false,
    List<String>? blockedByTaskIds,
    List<TdfTaskDependency>? dependencies,
    List<TaskLink>? links,
    Iterable<TaskHistoryEntry>? history,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
  }) async {
    if (errorToThrow case final error?) {
      throw error;
    }
    lastUpdatedId = taskId;
    lastUpdatedIsDuePassive = isDuePassive;
  }
}

void main() {
  setUp(() {
    AppLogger.resetForTesting(clock: () => DateTime.utc(2026, 11, 21, 10));
  });

  tearDown(() {
    AppLogger.resetForTesting();
  });

  group('TaskEditorController pure helpers', () {
    test('parses repeat count/leadDays, sanitizes history, and enforces scheduling note bounds', () {
      final en = lookupAppLocalizations(const Locale('en'));

      expect(
        TaskEditorController.parseRepeatCount(isRepeating: true, rawCount: '0'),
        isNull,
      );
      expect(
        TaskEditorController.parseRepeatCount(
          isRepeating: true,
          rawCount: '${TaskRepeatRule.maxRepeatCount}',
        ),
        equals(TaskRepeatRule.maxRepeatCount),
      );
      expect(
        TaskEditorController.parseRepeatCount(
          isRepeating: true,
          rawCount: '${TaskRepeatRule.maxRepeatCount + 1}',
        ),
        isNull,
      );
      expect(
        TaskEditorController.parseLeadDays(
          hasDue: true,
          isRepeating: true,
          rawLeadDays: '3650',
        ),
        equals(3650),
      );
      expect(
        TaskEditorController.parseLeadDays(
          hasDue: true,
          isRepeating: true,
          rawLeadDays: '3651',
        ),
        isNull,
      );

      expect(
        TaskEditorController.sanitizeHistoryText('  line1\r\nline2\tpart3  '),
        equals('line1 line2 part3'),
      );
      expect(
        TaskEditorController.validateHistoryText('a' * maxTdfTextLength, en),
        isNull,
      );
      expect(
        TaskEditorController.validateHistoryText(
          'a' * (maxTdfTextLength + 1),
          en,
        ),
        equals(en.historyErrorTextTooLong),
      );

      expect(
        TaskEditorController.validateSchedulingNote('a' * maxTdfNoteLength, en),
        isNull,
      );
      expect(
        TaskEditorController.validateSchedulingNote(
          'a' * (maxTdfNoteLength + 1),
          en,
        ),
        equals(en.schedulingNoteErrorTooLong),
      );
      expect(
        TaskEditorController.validateSchedulingNote('bad\x00note', en),
        equals(en.schedulingNoteErrorInvalid),
      );
    });

    test('resolves due and suspended drafts preserving anchors and passive auto-reset', () {
      const utcConfig = WebDavConfig(
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: 0,
      );
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 21, 10)),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(taskEditorControllerProvider);

      final initialDueAt = DateTime.utc(2026, 11, 25, 14, 30);
      final initialAnchor = TdfLocalDateTime(2026, 11, 25, 14, 30);
      final unchangedDue = controller.resolveDueDraft(
        configuration: utcConfig,
        hasDue: true,
        rawDueText: '2026-11-25 14:30',
        initialDueAt: initialDueAt,
        initialDueAnchor: initialAnchor,
        initialDueText: '2026-11-25 14:30',
      );
      expect(unchangedDue.isValid, isTrue);
      expect(unchangedDue.isUnchanged, isTrue);
      expect(unchangedDue.dueAnchor, equals(initialAnchor));
      expect(
        controller.shouldResetAutoPrioritizeDue(
          didUserToggleAutoPrioritizeDue: false,
          autoPrioritizeDue: false,
          hasDue: true,
          candidateDue: unchangedDue,
          initialDueAt: initialDueAt,
          initialDueAnchor: initialAnchor,
        ),
        isFalse,
      );

      final editedDue = controller.resolveDueDraft(
        configuration: utcConfig,
        hasDue: true,
        rawDueText: '2026-11-26 09:00',
        initialDueAt: initialDueAt,
        initialDueAnchor: initialAnchor,
        initialDueText: '2026-11-25 14:30',
      );
      expect(editedDue.isValid, isTrue);
      expect(editedDue.isUnchanged, isFalse);
      expect(
        controller.shouldResetAutoPrioritizeDue(
          didUserToggleAutoPrioritizeDue: false,
          autoPrioritizeDue: false,
          hasDue: true,
          candidateDue: editedDue,
          initialDueAt: initialDueAt,
          initialDueAnchor: initialAnchor,
        ),
        isTrue,
      );

      final suspendedForever = controller.resolveSuspendedDraft(
        configuration: utcConfig,
        isSuspended: true,
        rawSuspendedText: '   ',
        initialSuspendedAt: null,
        initialSuspendedText: '',
      );
      expect(suspendedForever.isValid, isTrue);
      expect(suspendedForever.isForever, isTrue);

      final invalidSuspended = controller.resolveSuspendedDraft(
        configuration: utcConfig,
        isSuspended: true,
        rawSuspendedText: 'not-a-date',
        initialSuspendedAt: null,
        initialSuspendedText: '',
      );
      expect(invalidSuspended.isValid, isFalse);
    });
  });

  group('TaskEditorController.submitDraft and deleteTask', () {
    TaskEditorDraftInput buildInput({
      TaskItem? existingTask,
      TaskBoard? board,
      String rawTitle = 'Write tests',
      String rawNote = 'Private body note',
      bool hasDue = false,
      String rawDueText = '',
      String rawDueNote = '',
      bool isSuspended = false,
      String rawSuspendedText = '',
      String rawSuspendedNote = '',
      bool isRepeating = false,
      String rawRepeatCount = '1',
      String rawRepeatLeadDays = '',
      List<TaskHistoryEntry> historyEntries = const <TaskHistoryEntry>[],
      String rawHistoryTimestamp = '',
      String rawHistoryText = '',
    }) {
      return TaskEditorDraftInput(
        existingTask: existingTask,
        board: board ?? TaskBoard.empty(),
        configuration: const WebDavConfig(
          timeZoneMode: AppTimeZoneMode.manual,
          manualTimeZoneOffsetMinutes: 0,
        ),
        rawTitle: rawTitle,
        rawNote: rawNote,
        mode: QuickAddMode.standard,
        initialEditorMode: QuickAddMode.standard,
        autoFinish: false,
        subtasks: const <SubtaskItem>[],
        pendingSubtaskText: '',
        selectedLabelIds: const <String>{},
        selectedBlockedByIds: const <String>{},
        links: const <TaskLink>[],
        conditions: const <TaskCondition>[],
        hasDue: hasDue,
        rawDueText: rawDueText,
        initialDueAt: existingTask?.dueAt,
        initialDueAnchor: existingTask?.dueAnchor,
        initialDueText: '',
        autoPrioritizeDue: true,
        rawDueNote: rawDueNote,
        initialDueNote: existingTask?.dueNote,
        isSuspended: isSuspended,
        rawSuspendedText: rawSuspendedText,
        initialSuspendedAt: existingTask?.suspendedAt,
        initialSuspendedText: '',
        rawSuspendedNote: rawSuspendedNote,
        initialSuspendedNote: existingTask?.suspendedNote,
        isRepeating: isRepeating,
        rawRepeatCount: rawRepeatCount,
        rawRepeatLeadDays: rawRepeatLeadDays,
        repeatUnit: RepeatUnit.days,
        historyEntries: historyEntries,
        editingHistoryIndex: null,
        editingHistoryOriginalEntry: null,
        editingHistoryInitialTimestampText: '',
        rawHistoryTimestamp: rawHistoryTimestamp,
        rawHistoryText: rawHistoryText,
      );
    }

    test('returns ValidationFailed and emits redacted ui.edit_task.validation_failed telemetry', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.warn,
        persistToDisk: false,
      );
      final container = ProviderContainer(
        overrides: [
          taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
          appLocaleProvider.overrideWithValue(const Locale('en')),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final result = await container
          .read(taskEditorControllerProvider)
          .submitDraft(
            buildInput(
              rawTitle: '   ',
              hasDue: true,
              rawDueText: 'invalid',
              rawDueNote: 'secret due note \x00',
              isRepeating: true,
              rawRepeatCount: '0',
              rawRepeatLeadDays: '9999',
            ),
          );

      expect(result, isA<TaskEditorValidationFailed>());
      final errors = (result as TaskEditorValidationFailed).errors;
      expect(errors.titleError, isNotNull);
      expect(errors.dueError, isNotNull);
      expect(errors.dueNoteError, isNotNull);
      expect(errors.repeatError, isNotNull);
      expect(errors.repeatLeadDaysError, isNotNull);

      final logText = AppLogger.fullLogText;
      expect(logText, contains('ui.edit_task.validation_failed'));
      expect(logText, isNot(contains('secret due note')));
    });

    test('returns PersistFailed with committedHistoryEntries on TdfException, TdfContextException, and FormatException', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.warn,
        persistToDisk: false,
      );
      final taskNotifier = _RecordingTaskNotifier();
      final container = ProviderContainer(
        overrides: [
          taskNotifierProvider.overrideWith(() => taskNotifier),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 21, 10)),
          appLocaleProvider.overrideWithValue(const Locale('en')),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final controller = container.read(taskEditorControllerProvider);

      taskNotifier.errorToThrow = const TdfException(
        kind: TdfErrorKind.invalidUri,
        line: 0,
        message: 'Bad URI',
      );
      final uriFailed = await controller.submitDraft(
        buildInput(rawHistoryText: 'Pending confidential journal entry'),
      );
      expect(uriFailed, isA<TaskEditorPersistFailed>());
      final persistUri = uriFailed as TaskEditorPersistFailed;
      expect(persistUri.errors.linkError, isNotNull);
      expect(persistUri.committedHistoryEntries?.length, equals(1));

      taskNotifier.errorToThrow = const TdfContextException(
        kind: TdfContextOutcomeKind.timeZoneContextRequired,
        message: 'TZ required',
      );
      final tzFailed = await controller.submitDraft(
        buildInput(hasDue: true, rawDueText: '2026-11-25 10:00'),
      );
      expect(tzFailed, isA<TaskEditorPersistFailed>());
      expect((tzFailed as TaskEditorPersistFailed).errors.dueError, isNotNull);

      taskNotifier.errorToThrow = const FormatException('Bad format');
      final fmtFailed = await controller.submitDraft(
        buildInput(
          hasDue: true,
          rawDueText: '2026-11-25 10:00',
          isRepeating: true,
          rawRepeatCount: '1',
          rawRepeatLeadDays: '2',
        ),
      );
      expect(fmtFailed, isA<TaskEditorPersistFailed>());
      expect(
        (fmtFailed as TaskEditorPersistFailed).errors.repeatLeadDaysError,
        isNotNull,
      );

      final logText = AppLogger.fullLogText;
      expect(logText, contains('ui.edit_task.persist_rejected'));
      expect(logText, isNot(contains('Pending confidential journal entry')));
    });

    test('submits valid task with redacted saved telemetry and deletes task with redacted delete telemetry', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.info,
        persistToDisk: false,
      );
      final taskNotifier = _RecordingTaskNotifier();
      final container = ProviderContainer(
        overrides: [
          taskNotifierProvider.overrideWith(() => taskNotifier),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 21, 10)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final controller = container.read(taskEditorControllerProvider);
      final submitted = await controller.submitDraft(
        buildInput(
          rawTitle: 'Ship Phase 1',
          rawNote: 'Top secret body note',
          rawHistoryText: 'Secret history text',
        ),
      );
      expect(submitted, isA<TaskEditorSubmitted>());
      expect(taskNotifier.lastAddedTitle, equals('Ship Phase 1'));
      expect(taskNotifier.lastAddedHistory?.length, equals(1));

      await controller.deleteTask('task-42');
      expect(taskNotifier.deletedIds, equals(['task-42']));

      final logText = AppLogger.fullLogText;
      expect(logText, contains('ui.edit_task.saved | id=new'));
      expect(logText, contains('ui.delete_task.confirmed | id=task-42'));
      expect(logText, isNot(contains('Top secret body note')));
      expect(logText, isNot(contains('Secret history text')));
    });
  });
}
