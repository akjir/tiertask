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

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/storage_file_read_status.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/sync_error_formatter.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_condition_draft_helper.dart';
import 'package:tiertask/providers/task_schedule_helper.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';

void main() {
  final englishLocalizations = lookupAppLocalizations(const Locale('en'));

  group('TaskScheduleHelper scheduling & draft resolution', () {
    test('parses repeat count and leadDays, sanitizes history, and enforces scheduling note and title bounds', () {
      expect(
        TaskScheduleHelper.parseRepeatCount(isRepeating: false, rawCount: '3'),
        isNull,
      );
      expect(
        TaskScheduleHelper.parseRepeatCount(isRepeating: true, rawCount: '0'),
        isNull,
      );
      expect(
        TaskScheduleHelper.parseRepeatCount(
          isRepeating: true,
          rawCount: '${TaskRepeatRule.maxRepeatCount}',
        ),
        equals(TaskRepeatRule.maxRepeatCount),
      );
      expect(
        TaskScheduleHelper.parseRepeatCount(
          isRepeating: true,
          rawCount: '${TaskRepeatRule.maxRepeatCount + 1}',
        ),
        isNull,
      );
      expect(
        TaskScheduleHelper.parseLeadDays(
          hasDue: false,
          isRepeating: true,
          rawLeadDays: '99999',
        ),
        equals(0),
      );
      expect(
        TaskScheduleHelper.parseLeadDays(
          hasDue: true,
          isRepeating: true,
          rawLeadDays: '3650',
        ),
        equals(3650),
      );
      expect(
        TaskScheduleHelper.parseLeadDays(
          hasDue: true,
          isRepeating: true,
          rawLeadDays: '3651',
        ),
        isNull,
      );

      expect(
        TaskScheduleHelper.sanitizeHistoryText('  line1\r\nline2\tpart3  '),
        equals('line1 line2 part3'),
      );
      expect(
        TaskScheduleHelper.validateHistoryText(
          'a' * maxTdfTextLength,
          englishLocalizations,
        ),
        isNull,
      );
      expect(
        TaskScheduleHelper.validateHistoryText(
          'a' * (maxTdfTextLength + 1),
          englishLocalizations,
        ),
        equals(englishLocalizations.historyErrorTextTooLong),
      );
      expect(
        TaskScheduleHelper.validateHistoryText('   ', englishLocalizations),
        equals(englishLocalizations.historyErrorTextEmpty),
      );
      expect(
        TaskScheduleHelper.validateHistoryText(
          'bad\x00entry',
          englishLocalizations,
        ),
        equals(englishLocalizations.historyErrorTextInvalid),
      );

      expect(TaskScheduleHelper.normalizeSchedulingNote('  \r\n\t  '), isNull);
      expect(
        TaskScheduleHelper.normalizeSchedulingNote('line1\r\nline2\rline3'),
        equals('line1\nline2\nline3'),
      );
      expect(
        TaskScheduleHelper.validateSchedulingNote(
          'a' * maxTdfNoteLength,
          englishLocalizations,
        ),
        isNull,
      );
      expect(
        TaskScheduleHelper.validateSchedulingNote(
          'a' * (maxTdfNoteLength + 1),
          englishLocalizations,
        ),
        equals(englishLocalizations.schedulingNoteErrorTooLong),
      );
      expect(
        TaskScheduleHelper.validateSchedulingNote(
          'bad\x00note',
          englishLocalizations,
        ),
        equals(englishLocalizations.schedulingNoteErrorInvalid),
      );

      final now = DateTime.utc(2026, 11, 21, 10);
      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[
          TaskItem(
            id: 'task000001',
            title: 'Existing Task',
            createdAt: now,
            modifiedAt: now,
          ),
          TaskItem(
            id: 'task000002',
            title: 'Second Task',
            createdAt: now,
            modifiedAt: now,
          ),
        ],
        labels: <TdfLabel>[
          TdfLabel(id: 'lbl0000001', name: 'Alpha', modifiedAt: now),
          TdfLabel(id: 'lbl0000002', name: 'Beta', modifiedAt: now),
        ],
        evaluationTime: now,
      );
      expect(
        TaskScheduleHelper.validateTaskTitle(
          board: board,
          rawTitle: '   ',
          excludingTaskId: null,
          localizations: englishLocalizations,
        ),
        equals(englishLocalizations.taskNameErrorEmpty),
      );
      expect(
        TaskScheduleHelper.validateTaskTitle(
          board: board,
          rawTitle: 'existing task',
          excludingTaskId: null,
          localizations: englishLocalizations,
        ),
        equals(englishLocalizations.taskNameErrorDuplicate),
      );
      expect(
        TaskScheduleHelper.validateTaskTitle(
          board: board,
          rawTitle: 'existing task',
          excludingTaskId: 'task000001',
          localizations: englishLocalizations,
        ),
        isNull,
      );
      expect(
        TaskScheduleHelper.collectOrderedBlockedByIds(board, <String>{
          'task000002',
          'task000001',
        }),
        equals(<String>['task000001', 'task000002']),
      );
      expect(
        TaskScheduleHelper.collectOrderedLabelIds(board, <String>{
          'lbl0000002',
          'lbl0000001',
        }),
        equals(<String>['lbl0000001', 'lbl0000002']),
      );
    });

    test('resolves due and suspended drafts statically, local timestamps, wall-clock anchors, and remaining durations', () {
      const utcConfig = WebDavConfig(timeZoneMode: AppTimeZoneMode.manual);
      final initialDueAt = DateTime.utc(2026, 11, 25, 14, 30);
      final initialAnchor = TdfLocalDateTime(2026, 11, 25, 14, 30);

      final unchangedDue = TaskScheduleHelper.resolveDueDraft(
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

      final editedDue = TaskScheduleHelper.resolveDueDraft(
        configuration: utcConfig,
        hasDue: true,
        rawDueText: '2026-11-26 09:00',
        initialDueAt: initialDueAt,
        initialDueAnchor: initialAnchor,
        initialDueText: '2026-11-25 14:30',
      );
      expect(editedDue.isValid, isTrue);
      expect(editedDue.isUnchanged, isFalse);
      expect(editedDue.dueAt, equals(DateTime.utc(2026, 11, 26, 9)));

      final suspendedForever = TaskScheduleHelper.resolveSuspendedDraft(
        configuration: utcConfig,
        isSuspended: true,
        rawSuspendedText: '   ',
        initialSuspendedAt: null,
        initialSuspendedText: '',
      );
      expect(suspendedForever.isValid, isTrue);
      expect(suspendedForever.isForever, isTrue);

      final invalidSuspended = TaskScheduleHelper.resolveSuspendedDraft(
        configuration: utcConfig,
        isSuspended: true,
        rawSuspendedText: 'not-a-date',
        initialSuspendedAt: null,
        initialSuspendedText: '',
      );
      expect(invalidSuspended.isValid, isFalse);

      expect(
        TaskScheduleHelper.formatInitialSuspendedText(null, utcConfig),
        isEmpty,
      );
      expect(
        TaskScheduleHelper.formatInitialSuspendedText(initialDueAt, utcConfig),
        equals('2026-11-25 14:30'),
      );
      expect(
        TaskScheduleHelper.formatLocalTimestamp(initialDueAt, utcConfig),
        equals('2026-11-25 14:30'),
      );
      expect(
        TaskScheduleHelper.resolveHistoryTimestampUtc(
          configuration: utcConfig,
          fallbackNowUtc: DateTime.utc(2026, 11, 21, 10, 0, 5),
          rawTimestamp: '',
        ),
        equals(DateTime.utc(2026, 11, 21, 10, 0, 5)),
      );

      expect(
        TaskScheduleHelper.differsFromWallClock(
          TdfLocalDateTime(2026, 11, 25, 14, 30),
          DateTime(2026, 11, 25, 14, 30),
        ),
        isFalse,
      );
      expect(
        TaskScheduleHelper.differsFromWallClock(
          TdfLocalDateTime(2026, 11, 25, 14, 30),
          DateTime(2026, 11, 25, 15, 30),
        ),
        isTrue,
      );

      expect(
        TaskScheduleHelper.formatRemainingDuration(
          const Duration(days: 2, hours: 5),
          englishLocalizations,
        ),
        equals(englishLocalizations.taskInfoDurationDaysHours('2', '5')),
      );
      expect(
        TaskScheduleHelper.formatRemainingDuration(
          const Duration(hours: 3, minutes: 15),
          englishLocalizations,
        ),
        equals(englishLocalizations.taskInfoDurationHoursMinutes('3', '15')),
      );
      expect(
        TaskScheduleHelper.formatRemainingDuration(
          const Duration(seconds: 20),
          englishLocalizations,
        ),
        equals(englishLocalizations.taskInfoDurationMinutes('1')),
      );
    });
  });

  group('TaskScheduleHelper condition drafts, compiler, and summary chips', () {
    final now = DateTime.utc(2026, 11, 21, 10);
    final locations = <TdfLocation>[
      for (var i = 0; i < maxTdfLocationRefsPerEntity + 1; i++)
        TdfLocation(
          id: 'loc${i.toString().padLeft(7, '0')}',
          name: 'Place $i',
          latitude: 47.0,
          longitude: 8.5,
          radius: 200.0,
          modifiedAt: now,
        ),
    ];
    final board = TaskBoard.evaluate(
      tasks: const <TaskItem>[],
      locations: locations,
      evaluationTime: now,
    );

    test('ConditionDraft and TimeWindowDraft enforce immutability, copyWith, and value equality', () {
      final draft = ConditionDraft(
        daysMode: ConditionDimensionMode.custom,
        weekdays: const <int>[1, 3],
        timeMode: ConditionDimensionMode.custom,
        timeWindows: const <TimeWindowDraft>[
          TimeWindowDraft(start: '08:00', end: '12:00'),
        ],
        locationMode: ConditionDimensionMode.custom,
        locationIds: const <String>['loc0000000'],
      );
      final updated = draft.copyWith(ignoreAllLabelConditions: true);
      expect(updated.ignoreAllLabelConditions, isTrue);
      expect(updated.weekdays, equals(const <int>[1, 3]));
      expect(
        draft,
        equals(
          ConditionDraft(
            daysMode: ConditionDimensionMode.custom,
            weekdays: const <int>[1, 3],
            timeMode: ConditionDimensionMode.custom,
            timeWindows: const <TimeWindowDraft>[
              TimeWindowDraft(start: '08:00', end: '12:00'),
            ],
            locationMode: ConditionDimensionMode.custom,
            locationIds: const <String>['loc0000000'],
          ),
        ),
      );
      expect(
        () => draft.weekdays.add(5),
        throwsUnsupportedError,
        reason: 'ConditionDraft collections must be unmodifiable',
      );
      expect(canonicalLabelPresetHexColors, hasLength(8));
    });

    test('buildConditionDraft and compileConditionDraft handle task resets, label rules, and bounds', () {
      // Task global reset short-circuits all other dimensions.
      final globalResetResult = TaskScheduleHelper.compileConditionDraft(
        draft: ConditionDraft(
          ignoreAllLabelConditions: true,
          daysMode: ConditionDimensionMode.custom,
          weekdays: const <int>[1],
        ),
        board: board,
        isTask: true,
        localizations: englishLocalizations,
      );
      expect(globalResetResult.error, isNull);
      expect(
        globalResetResult.conditions,
        equals(const <TaskCondition>[GlobalResetTaskCondition()]),
      );

      // Round-trip task draft with group reset + custom time + custom location.
      final taskDraft = ConditionDraft(
        daysMode: ConditionDimensionMode.any,
        timeMode: ConditionDimensionMode.custom,
        timeWindows: const <TimeWindowDraft>[
          TimeWindowDraft(start: '09:00', end: '17:30'),
        ],
        locationMode: ConditionDimensionMode.custom,
        locationIds: const <String>['loc0000000', 'loc0000000', 'loc0000001'],
      );
      final compiledTask = TaskScheduleHelper.compileConditionDraft(
        draft: taskDraft,
        board: board,
        isTask: true,
        localizations: englishLocalizations,
      );
      expect(compiledTask.error, isNull);
      expect(compiledTask.conditions, hasLength(3));
      final rebuiltTaskDraft = TaskScheduleHelper.buildConditionDraft(
        compiledTask.conditions,
        isTask: true,
      );
      expect(rebuiltTaskDraft.daysMode, equals(ConditionDimensionMode.any));
      expect(rebuiltTaskDraft.timeMode, equals(ConditionDimensionMode.custom));
      expect(
        rebuiltTaskDraft.locationIds,
        equals(const <String>['loc0000000', 'loc0000001']),
      );

      // Label ignores ignoreAllLabelConditions and group resets (`any`).
      final compiledLabel = TaskScheduleHelper.compileConditionDraft(
        draft: ConditionDraft(
          ignoreAllLabelConditions: true,
          daysMode: ConditionDimensionMode.any,
          timeMode: ConditionDimensionMode.custom,
          timeWindows: const <TimeWindowDraft>[
            TimeWindowDraft(start: '08:00', end: '10:00'),
          ],
          locationMode: ConditionDimensionMode.any,
        ),
        board: board,
        isTask: false,
        localizations: englishLocalizations,
      );
      expect(compiledLabel.error, isNull);
      expect(compiledLabel.conditions, hasLength(1));
      final rebuiltLabelDraft = TaskScheduleHelper.buildConditionDraft(
        compiledLabel.conditions,
        isTask: false,
      );
      expect(rebuiltLabelDraft.ignoreAllLabelConditions, isFalse);
      expect(rebuiltLabelDraft.daysMode, equals(ConditionDimensionMode.custom));
      expect(rebuiltLabelDraft.weekdays, isEmpty);

      // Invalid weekday rejected.
      final badWeekday = TaskScheduleHelper.compileConditionDraft(
        draft: ConditionDraft(
          daysMode: ConditionDimensionMode.custom,
          weekdays: const <int>[0, 8],
        ),
        board: board,
        isTask: true,
        localizations: englishLocalizations,
      );
      expect(
        badWeekday.error,
        equals(englishLocalizations.conditionTimeErrorInvalid),
      );

      // Invalid time window and control characters rejected.
      final badTime = TaskScheduleHelper.compileConditionDraft(
        draft: ConditionDraft(
          timeMode: ConditionDimensionMode.custom,
          timeWindows: const <TimeWindowDraft>[
            TimeWindowDraft(start: '08:00', end: '08:00'),
          ],
        ),
        board: board,
        isTask: true,
        localizations: englishLocalizations,
      );
      expect(
        badTime.error,
        equals(englishLocalizations.conditionTimeErrorInvalid),
      );

      // Unknown location rejected.
      final unknownLocation = TaskScheduleHelper.compileConditionDraft(
        draft: ConditionDraft(
          locationMode: ConditionDimensionMode.custom,
          locationIds: const <String>['missing001'],
        ),
        board: board,
        isTask: true,
        localizations: englishLocalizations,
      );
      expect(
        unknownLocation.error,
        equals(englishLocalizations.conditionLocationErrorInvalid),
      );

      // Exactly 63 location refs succeeds; 64 fails even when duplicated.
      final validLocationIds = <String>[
        for (var i = 0; i < maxTdfLocationRefsPerEntity; i++) locations[i].id,
      ];
      expect(
        TaskScheduleHelper.compileConditionDraft(
          draft: ConditionDraft(
            locationMode: ConditionDimensionMode.custom,
            locationIds: validLocationIds,
          ),
          board: board,
          isTask: true,
          localizations: englishLocalizations,
        ).error,
        isNull,
        reason: '63 location refs must satisfy maxTdfLocationRefsPerEntity',
      );
      expect(
        TaskScheduleHelper.compileConditionDraft(
          draft: ConditionDraft(
            locationMode: ConditionDimensionMode.custom,
            locationIds: List<String>.filled(
              maxTdfLocationRefsPerEntity + 1,
              locations.first.id,
            ),
          ),
          board: board,
          isTask: false,
          localizations: englishLocalizations,
        ).error,
        equals(englishLocalizations.errorLocalFileTooLarge),
        reason: '64 location refs must fail before deduplication',
      );

      // 512 time-window rules succeeds; 513 exceeds maxTdfConditionRulesPerEntity.
      final maxWindows = List<TimeWindowDraft>.filled(
        maxTdfConditionRulesPerEntity,
        const TimeWindowDraft(start: '08:00', end: '09:00'),
      );
      expect(
        TaskScheduleHelper.compileConditionDraft(
          draft: ConditionDraft(
            timeMode: ConditionDimensionMode.custom,
            timeWindows: maxWindows,
          ),
          board: board,
          isTask: true,
          localizations: englishLocalizations,
        ).error,
        isNull,
      );
      expect(
        TaskScheduleHelper.compileConditionDraft(
          draft: ConditionDraft(
            timeMode: ConditionDimensionMode.custom,
            timeWindows: <TimeWindowDraft>[
              ...maxWindows,
              const TimeWindowDraft(start: '09:00', end: '10:00'),
            ],
          ),
          board: board,
          isTask: true,
          localizations: englishLocalizations,
        ).error,
        equals(englishLocalizations.errorLocalFileTooLarge),
      );
    });

    test('buildConditionSummaryChips formats own, inherited, reset, and known vs unknown location chips', () {
      final locationsById = <String, TdfLocation>{
        'loc0000000': locations.first,
      };
      final chips = TaskScheduleHelper.buildConditionSummaryChips(
        ownRules: <TaskCondition>[
          DayTaskCondition.fromWeekdays(const <int>[1, 5]),
          const GroupResetTaskCondition(targetGroup: ConditionGroup.time),
          LocationTaskCondition.fromIds(const <String>[
            'loc0000000',
            'unknown001',
          ]),
        ],
        inheritedRules: const <TaskCondition>[
          TimeWindowTaskCondition(
            startMinutes: 480,
            endMinutes: 720,
            startToken: '08:00',
            endToken: '12:00',
          ),
        ],
        locationsById: locationsById,
        localizations: englishLocalizations,
      );
      expect(chips, hasLength(5));
      expect(
        chips[0],
        equals(
          ConditionSummaryChip(
            label:
                '${englishLocalizations.weekdayMon}, ${englishLocalizations.weekdayFri}',
          ),
        ),
      );
      expect(
        chips[1],
        equals(
          ConditionSummaryChip(
            label: englishLocalizations.conditionTimeAnyLabel,
          ),
        ),
      );
      expect(
        chips[2],
        equals(
          const ConditionSummaryChip(
            label: 'Place 0',
            locationId: 'loc0000000',
          ),
        ),
      );
      expect(chips[3], equals(const ConditionSummaryChip(label: 'unknown001')));
      expect(
        chips[4],
        equals(
          const ConditionSummaryChip(label: '08:00 - 12:00', isInherited: true),
        ),
      );

      // Global reset suppresses inherited chips.
      final resetChips = TaskScheduleHelper.buildConditionSummaryChips(
        ownRules: const <TaskCondition>[GlobalResetTaskCondition()],
        inheritedRules: <TaskCondition>[
          DayTaskCondition.fromWeekdays(const <int>[1]),
        ],
        locationsById: locationsById,
        localizations: englishLocalizations,
      );
      expect(
        resetChips,
        equals(<ConditionSummaryChip>[
          ConditionSummaryChip(
            label: englishLocalizations.conditionGlobalAnyLabel,
          ),
        ]),
      );
    });
  });

  group('TaskScheduleHelper domain formatters & validators', () {
    test('formats coordinates, radius, due/repeat/suspended details, file read diagnostics, color, and WIP limits', () {
      final location = TdfLocation(
        id: 'loc0000001',
        name: 'Office',
        latitude: 47.120412,
        longitude: 8.517345,
        radius: 250.0,
        modifiedAt: DateTime.utc(2026, 11, 21),
      );
      expect(
        TaskScheduleHelper.formatCoordinatesSummary(location),
        equals('47.1204, 8.5173 · 250m'),
      );
      expect(TaskScheduleHelper.formatRadiusMeters(1000.0), equals('1km'));
      expect(TaskScheduleHelper.formatRadiusMeters(1500.0), equals('1.5km'));
      expect(TaskScheduleHelper.formatRadiusMeters(12.345), equals('12.35m'));
      expect(
        TaskScheduleHelper.parseLabelColorValue('#2196F3'),
        equals(0xFF2196F3),
      );
      expect(TaskScheduleHelper.parseLabelColorValue('invalid'), isNull);

      for (final tier in TaskTier.values) {
        final expectedLimit = switch (tier) {
          TaskTier.focus => 3,
          TaskTier.ready => 5,
          TaskTier.planned ||
          TaskTier.blocked ||
          TaskTier.someday ||
          TaskTier.completed => null,
        };
        expect(
          TaskScheduleHelper.tierWipLimit(tier),
          equals(expectedLimit),
          reason: 'WIP limit mismatch for $tier',
        );
      }

      const shiftedConfig = WebDavConfig(
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: 120,
      );
      final dueAtUtc = DateTime.utc(2026, 11, 25, 10);
      final taskWithAnchor = TaskItem(
        id: 'tsk0000001',
        title: 'Due task',
        createdAt: DateTime.utc(2026, 11, 21),
        modifiedAt: DateTime.utc(2026, 11, 21),
        dueAt: dueAtUtc,
        dueAnchor: TdfLocalDateTime(2026, 11, 25, 10),
        suspendedAt: DateTime.utc(2026, 11, 24, 10),
      );
      expect(
        TaskScheduleHelper.formatDueAnchor(
          task: taskWithAnchor,
          config: shiftedConfig,
          localizations: englishLocalizations,
        ),
        equals(
          englishLocalizations.taskInfoDueAnchorDetail('2026-11-25 10:00'),
        ),
      );
      expect(
        TaskScheduleHelper.formatDueAnchor(
          task: taskWithAnchor,
          config: const WebDavConfig(timeZoneMode: AppTimeZoneMode.manual),
          localizations: englishLocalizations,
        ),
        isNull,
      );
      expect(
        TaskScheduleHelper.formatDueDetail(
          dueAtUtc: dueAtUtc,
          nowUtc: DateTime.utc(2026, 11, 25, 11),
          isOverdue: true,
          config: const WebDavConfig(timeZoneMode: AppTimeZoneMode.manual),
          localizations: englishLocalizations,
        ),
        equals(englishLocalizations.taskInfoDueOverdue('2026-11-25 10:00')),
      );
      expect(
        TaskScheduleHelper.formatDueAutoPriorityLabel(
          task: taskWithAnchor.copyWith(isDuePassive: true),
          isAutoPrioritized: false,
          dueLeadWindow: DueLeadWindow.hours24,
          localizations: englishLocalizations,
        ),
        equals(englishLocalizations.taskInfoDuePassiveHint),
      );
      expect(
        TaskScheduleHelper.formatDueAutoPriorityLabel(
          task: taskWithAnchor,
          isAutoPrioritized: false,
          dueLeadWindow: DueLeadWindow.off,
          localizations: englishLocalizations,
        ),
        equals(englishLocalizations.taskInfoDueLeadWindowOffHint),
      );
      expect(
        TaskScheduleHelper.formatDueAutoPriorityLabel(
          task: taskWithAnchor,
          isAutoPrioritized: true,
          dueLeadWindow: DueLeadWindow.hours24,
          localizations: englishLocalizations,
        ),
        equals(englishLocalizations.taskInfoDueAutoPromotedActive),
      );
      expect(
        TaskScheduleHelper.formatDueAutoPriorityLabel(
          task: taskWithAnchor,
          isAutoPrioritized: false,
          dueLeadWindow: DueLeadWindow.atDue,
          localizations: englishLocalizations,
        ),
        equals(englishLocalizations.taskInfoDueAutoPromoteAtDue),
      );
      expect(
        TaskScheduleHelper.formatDueAutoPriorityLabel(
          task: taskWithAnchor,
          isAutoPrioritized: false,
          dueLeadWindow: DueLeadWindow.days7,
          localizations: englishLocalizations,
        ),
        equals(
          englishLocalizations.taskInfoDueAutoPromoteScheduled(
            englishLocalizations.dueLeadWindowShort7Days,
          ),
        ),
      );

      expect(
        TaskScheduleHelper.formatRepeatPhrase(
          const TaskRepeatRule(count: 1, unit: RepeatUnit.weeks),
          englishLocalizations,
        ),
        equals(englishLocalizations.repeatEveryWeek),
      );
      expect(
        TaskScheduleHelper.formatRepeatPhrase(
          const TaskRepeatRule(count: 3, unit: RepeatUnit.months),
          englishLocalizations,
        ),
        equals(
          englishLocalizations.taskInfoRepeatEvery(
            '3',
            englishLocalizations.repeatUnitMonths,
          ),
        ),
      );

      expect(
        TaskScheduleHelper.formatSuspendedDetail(
          task: taskWithAnchor.copyWith(isSuspendedForever: true),
          nowUtc: DateTime.utc(2026, 11, 21, 10),
          config: const WebDavConfig(timeZoneMode: AppTimeZoneMode.manual),
          localizations: englishLocalizations,
        ),
        equals(englishLocalizations.taskInfoSuspendedForever),
      );
      expect(
        TaskScheduleHelper.formatSuspendedDetail(
          task: taskWithAnchor,
          nowUtc: DateTime.utc(2026, 11, 24, 8),
          config: const WebDavConfig(timeZoneMode: AppTimeZoneMode.manual),
          localizations: englishLocalizations,
        ),
        contains('2026-11-24 10:00'),
      );

      const report = StorageFileReadReport(
        local: StorageFileReadStatus.readable(StorageFileTarget.local),
        remote: StorageFileReadStatus.unsupportedVersion(
          StorageFileTarget.remote,
          version: '9.0.0',
        ),
      );
      final lines = TaskScheduleHelper.formatFileReadDiagnosticLines(
        report,
        englishLocalizations,
      );
      expect(lines, hasLength(2));
      expect(lines[0].isReadable, isTrue);
      expect(lines[1].isReadable, isFalse);
      expect(lines[1].statusText, contains('9.0.0'));
    });

    test('validates coordinates, radius, colors, location sources, links, subtasks, single-line text, and entity IDs', () {
      // Coordinates.
      final validCoordinates = TaskScheduleHelper.parseCoordinates(
        rawLatitude: '47,1234567',
        rawLongitude: '-8.5000001',
        localizations: englishLocalizations,
      );
      expect(validCoordinates.error, isNull);
      expect(validCoordinates.latitude, equals(47.123457));
      expect(validCoordinates.longitude, equals(-8.5));

      expect(
        TaskScheduleHelper.parseCoordinates(
          rawLatitude: '90.01',
          rawLongitude: '0',
          localizations: englishLocalizations,
        ).error,
        equals(englishLocalizations.locationCoordinatesErrorInvalid),
      );
      expect(
        TaskScheduleHelper.parseCoordinates(
          rawLatitude: '1e2',
          rawLongitude: '0',
          localizations: englishLocalizations,
        ).error,
        equals(englishLocalizations.locationCoordinatesErrorInvalid),
      );

      // Radius.
      expect(TaskScheduleHelper.parseRadiusMeters('0.01'), equals(0.01));
      expect(TaskScheduleHelper.parseRadiusMeters('200m'), equals(200.0));
      expect(TaskScheduleHelper.parseRadiusMeters('1,5 km'), equals(1500.0));
      expect(TaskScheduleHelper.parseRadiusMeters('100km'), equals(100000.0));
      expect(TaskScheduleHelper.parseRadiusMeters('0.009'), isNull);
      expect(TaskScheduleHelper.parseRadiusMeters('100.01km'), isNull);
      expect(TaskScheduleHelper.parseRadiusMeters('-10m'), isNull);
      expect(TaskScheduleHelper.parseRadiusMeters('100\x00m'), isNull);

      // Color.
      expect(
        TaskScheduleHelper.validateOptionalColor('', englishLocalizations),
        equals((normalizedHex: null, error: null)),
      );
      expect(
        TaskScheduleHelper.validateOptionalColor(
          ' #2196f3 ',
          englishLocalizations,
        ),
        equals((normalizedHex: '#2196F3', error: null)),
      );
      expect(
        TaskScheduleHelper.validateOptionalColor(
          '#12345',
          englishLocalizations,
        ).error,
        equals(englishLocalizations.labelColorErrorInvalid),
      );

      // Location source.
      expect(
        TaskScheduleHelper.validateLocationSource(
          sourceType: LocationSourceType.gps,
          rawSource: 'ignored',
          localizations: englishLocalizations,
        ),
        equals((normalizedSource: null, error: null)),
      );
      expect(
        TaskScheduleHelper.validateLocationSource(
          sourceType: LocationSourceType.address,
          rawSource: '  Bahnhofstrasse 1  ',
          localizations: englishLocalizations,
        ),
        equals((normalizedSource: 'Bahnhofstrasse 1', error: null)),
      );
      expect(
        TaskScheduleHelper.validateLocationSource(
          sourceType: LocationSourceType.plusCode,
          rawSource: 'bad\npluscode',
          localizations: englishLocalizations,
        ).error,
        equals(englishLocalizations.locationSourceErrorEmpty),
      );

      // Link input & list validation.
      expect(
        TaskScheduleHelper.validateLinkInput(
          rawTitle: 'Docs',
          rawUri: 'https://example.com',
          currentCount: maxTdfLinksPerTask,
          localizations: englishLocalizations,
        ),
        equals(englishLocalizations.linkErrorMaxExceeded),
      );
      expect(
        TaskScheduleHelper.validateLinkInput(
          rawTitle: 'Docs',
          rawUri: 'https://example.com',
          currentCount: maxTdfLinksPerLabel,
          localizations: englishLocalizations,
          isLabel: true,
        ),
        equals(englishLocalizations.labelLinkErrorMaxExceeded),
      );
      expect(
        TaskScheduleHelper.validateLinkInput(
          rawTitle: 'Docs',
          rawUri: 'https://example.com',
          currentCount: maxTdfLinksPerTask,
          localizations: englishLocalizations,
          isEditingExisting: true,
        ),
        isNull,
      );
      expect(
        TaskScheduleHelper.validateLinkInput(
          rawTitle: 'Bad',
          rawUri: 'javascript:alert(1)',
          currentCount: 0,
          localizations: englishLocalizations,
        ),
        equals(englishLocalizations.linkErrorInvalid),
      );
      final validLinks = TaskScheduleHelper.validateLinksList(
        links: const <TaskLink>[
          TaskLink(title: ' Docs ', uri: ' https://example.com '),
        ],
        localizations: englishLocalizations,
      );
      expect(validLinks.error, isNull);
      expect(
        validLinks.links,
        equals(const <TaskLink>[
          TaskLink(title: 'Docs', uri: 'https://example.com'),
        ]),
      );
      final overflowLinks = TaskScheduleHelper.validateLinksList(
        links: List<TaskLink>.filled(
          maxTdfLinksPerTask + 1,
          const TaskLink(title: 'Ref', uri: 'https://example.com'),
        ),
        localizations: englishLocalizations,
      );
      expect(
        overflowLinks.error,
        equals(englishLocalizations.linkErrorMaxExceeded),
      );

      // Single-line text validation.
      expect(
        TaskScheduleHelper.validateSingleLineText(
          rawText: '   ',
          emptyError: 'empty',
          invalidError: 'invalid',
          tooLongError: 'long',
        ).error,
        equals('empty'),
      );
      expect(
        TaskScheduleHelper.validateSingleLineText(
          rawText: 'line1\nline2',
          emptyError: 'empty',
          invalidError: 'invalid',
          tooLongError: 'long',
        ).error,
        equals('invalid'),
      );
      expect(
        TaskScheduleHelper.validateSingleLineText(
          rawText: 'a' * (maxTdfTextLength + 1),
          emptyError: 'empty',
          invalidError: 'invalid',
          tooLongError: 'long',
        ).error,
        equals('long'),
      );

      // Subtasks validation.
      final validSubtasks = TaskScheduleHelper.validateSubtasksList(
        subtasks: const <SubtaskItem>[
          SubtaskItem(title: '   '),
          SubtaskItem(title: ' Step 1 ', isCompleted: true),
        ],
        localizations: englishLocalizations,
      );
      expect(validSubtasks.error, isNull);
      expect(
        validSubtasks.subtasks,
        equals(const <SubtaskItem>[
          SubtaskItem(title: 'Step 1', isCompleted: true),
        ]),
      );
      expect(
        TaskScheduleHelper.validateSubtasksList(
          subtasks: const <SubtaskItem>[SubtaskItem(title: 'bad\x00step')],
          localizations: englishLocalizations,
        ).error,
        equals(englishLocalizations.historyErrorTextInvalid),
      );
      expect(
        TaskScheduleHelper.validateSubtasksList(
          subtasks: List<SubtaskItem>.filled(
            maxTdfStmtsPerBlock + 1,
            const SubtaskItem(title: 'Step'),
          ),
          localizations: englishLocalizations,
        ).error,
        equals(englishLocalizations.errorLocalFileTooLarge),
      );

      // Entity ID collection across live and deleted records.
      final now = DateTime.utc(2026, 11, 21);
      final boardWithDeleted = TaskBoard.evaluate(
        tasks: <TaskItem>[
          TaskItem(
            id: 'tsk0000001',
            title: 'Task',
            createdAt: now,
            modifiedAt: now,
            labelIds: const <String>['lbl0000001'],
          ),
        ],
        labels: <TdfLabel>[
          TdfLabel(id: 'lbl0000001', name: 'Work', modifiedAt: now),
        ],
        locations: <TdfLocation>[
          TdfLocation(
            id: 'loc0000001',
            name: 'Home',
            latitude: 0,
            longitude: 0,
            radius: 100,
            modifiedAt: now,
          ),
        ],
        deletedBlock: TdfDeletedBlock(
          generation: 2,
          tasks: <TdfDeletedTaskRecord>[
            TdfDeletedTaskRecord(taskId: 'deltsk0001', deletedAt: now),
          ],
          labels: <TdfDeletedLabelRecord>[
            TdfDeletedLabelRecord(labelId: 'dellbl0001', deletedAt: now),
          ],
          locations: <TdfDeletedLocationRecord>[
            TdfDeletedLocationRecord(locationId: 'delloc0001', deletedAt: now),
          ],
        ),
        evaluationTime: now,
      );
      expect(
        TaskScheduleHelper.collectAllUsedEntityIds(boardWithDeleted),
        containsAll(<String>[
          'tsk0000001',
          'lbl0000001',
          'loc0000001',
          'deltsk0001',
          'dellbl0001',
          'delloc0001',
        ]),
      );
    });

    test('formats sync errors, sync outcomes, and maps every TdfErrorKind exhaustively', () {
      for (final kind in TdfSyncOutcomeKind.values) {
        final message = TaskScheduleHelper.formatSyncOutcomeMessage(
          TdfSyncOutcomeException(kind: kind, message: 'outcome'),
          englishLocalizations,
        );
        expect(message, isNotEmpty, reason: 'Missing message for $kind');
      }

      expect(
        TaskScheduleHelper.formatSyncError(
          const LocalFileException('Local IO failed'),
          englishLocalizations,
        ),
        equals('Local IO failed'),
      );
      expect(
        TaskScheduleHelper.formatSyncError(
          const WebDavException('Auth failed', statusCode: 401),
          englishLocalizations,
        ),
        contains('Auth failed'),
      );
      expect(
        TaskScheduleHelper.formatSyncError(
          const WorkspaceException(
            WorkspaceErrorKind.emptyName,
            'Workspace name empty',
          ),
          englishLocalizations,
        ),
        equals(englishLocalizations.errorWorkspaceNameEmpty),
      );
      expect(
        TaskScheduleHelper.formatSyncError(
          const TdfException(
            kind: TdfErrorKind.invalidColor,
            line: 1,
            message: 'Bad color',
          ),
          englishLocalizations,
        ),
        equals('Bad color'),
      );
      expect(
        TaskScheduleHelper.formatSyncError(
          const StorageFileReadException(
            'fallback',
            report: StorageFileReadReport(
              local: StorageFileReadStatus.unreadable(
                StorageFileTarget.local,
                detail: 'Disk read error',
              ),
            ),
          ),
          englishLocalizations,
        ),
        contains('Disk read error'),
      );
      expect(
        TaskScheduleHelper.formatSyncError(
          StateError('boom'),
          englishLocalizations,
          isSave: true,
        ),
        contains('boom'),
      );

      for (final kind in TdfErrorKind.values) {
        expect(
          TaskScheduleHelper.mapTdfExceptionMessage(kind, englishLocalizations),
          isNotEmpty,
          reason: 'Every TdfErrorKind must map to a non-empty message: $kind',
        );
      }
      expect(
        TaskScheduleHelper.mapTdfExceptionMessage(
          TdfErrorKind.circularDependency,
          englishLocalizations,
        ),
        equals(englishLocalizations.prerequisiteCyclePreventedHint),
      );
      expect(
        TaskScheduleHelper.mapTdfExceptionMessage(
          TdfErrorKind.unknownLocationReference,
          englishLocalizations,
        ),
        equals(englishLocalizations.conditionLocationErrorInvalid),
      );
    });

    test('delegates unified error formatting to SyncErrorFormatter across sync and settings flows', () {
      for (final kind in TdfSyncOutcomeKind.values) {
        final message = SyncErrorFormatter.formatSyncOutcomeMessage(
          TdfSyncOutcomeException(kind: kind, message: 'outcome'),
          englishLocalizations,
        );
        expect(
          message,
          equals(
            TaskScheduleHelper.formatSyncOutcomeMessage(
              TdfSyncOutcomeException(kind: kind, message: 'outcome'),
              englishLocalizations,
            ),
          ),
          reason: 'Formatter parity failed for $kind',
        );
      }

      const fileReadError = StorageFileReadException(
        'Fallback message',
        report: StorageFileReadReport(
          remote: StorageFileReadStatus.unreadable(
            StorageFileTarget.remote,
            detail: 'Remote syntax failure',
            line: 7,
          ),
        ),
      );
      expect(
        SyncErrorFormatter.formatSyncError(fileReadError, englishLocalizations),
        contains('Remote syntax failure'),
      );
      expect(
        SyncErrorFormatter.formatSettingsError(
          fileReadError,
          englishLocalizations,
        ),
        contains('Remote syntax failure'),
      );
      expect(
        SyncErrorFormatter.formatSettingsError(
          StateError('plain settings failure'),
          englishLocalizations,
        ),
        equals('Bad state: plain settings failure'),
      );
      expect(
        SyncErrorFormatter.formatSyncError(
          StateError('plain sync failure'),
          englishLocalizations,
        ),
        equals(
          englishLocalizations.errorUnexpectedLoad(
            'Bad state: plain sync failure',
          ),
        ),
      );
    });

    test('validates WGS-84 coordinates and compiles condition drafts via TaskConditionDraftHelper', () {
      expect(TaskScheduleHelper.isValidCoordinates(0.0, 0.0), isTrue);
      expect(TaskScheduleHelper.isValidCoordinates(-90.0, 180.0), isTrue);
      expect(TaskScheduleHelper.isValidCoordinates(90.0001, 0.0), isFalse);
      expect(TaskScheduleHelper.isValidCoordinates(0.0, -180.0001), isFalse);
      expect(TaskScheduleHelper.isValidCoordinates(double.nan, 0.0), isFalse);
      expect(
        TaskScheduleHelper.isValidCoordinates(0.0, double.infinity),
        isFalse,
      );

      expect(
        TaskScheduleHelper.tierWipLimit(TaskTier.focus),
        equals(TaskBoard.focusSoftLimit),
      );
      expect(
        TaskScheduleHelper.tierWipLimit(TaskTier.ready),
        equals(TaskBoard.readySoftLimit),
      );

      final board = TaskBoard.empty().addLocation(
        'Studio',
        id: 'loc0000001',
        latitude: 47.0,
        longitude: 8.0,
        radius: 150,
      );
      final compiled = TaskConditionDraftHelper.compileConditions(
        ignoreAllLabelConditions: false,
        daysMode: ConditionCompileMode.custom,
        weekdays: const <int>[DateTime.monday, DateTime.friday],
        timeMode: ConditionCompileMode.any,
        timeWindows: const <({String start, String end})>[],
        locationMode: ConditionCompileMode.custom,
        locationIds: const <String>['loc0000001'],
        board: board,
        isTask: true,
        localizations: englishLocalizations,
      );
      expect(compiled.error, isNull);
      expect(compiled.conditions, hasLength(3));

      final extracted = TaskConditionDraftHelper.extractDraftFields(
        compiled.conditions,
        isTask: true,
      );
      expect(
        extracted.weekdays,
        equals(<int>[DateTime.monday, DateTime.friday]),
      );
      expect(extracted.timeAny, isTrue);
      expect(extracted.locationIds, equals(<String>['loc0000001']));

      final summary = TaskConditionDraftHelper.buildSummaryChips(
        ownRules: compiled.conditions,
        inheritedRules: const <TaskCondition>[],
        locationsById: <String, TdfLocation>{
          for (final location in board.locations) location.id: location,
        },
        localizations: englishLocalizations,
      );
      expect(summary, hasLength(3));
      expect(summary.last.label, equals('Studio'));
      expect(summary.last.locationId, equals('loc0000001'));
    });
  });
}
