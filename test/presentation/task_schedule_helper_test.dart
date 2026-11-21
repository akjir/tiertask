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
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/task_schedule_helper.dart';

void main() {
  group('TaskScheduleHelper', () {
    test('parses repeat count/leadDays, sanitizes history, and enforces scheduling note and title bounds', () {
      final en = lookupAppLocalizations(const Locale('en'));

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
        TaskScheduleHelper.validateHistoryText('a' * maxTdfTextLength, en),
        isNull,
      );
      expect(
        TaskScheduleHelper.validateHistoryText(
          'a' * (maxTdfTextLength + 1),
          en,
        ),
        equals(en.historyErrorTextTooLong),
      );
      expect(
        TaskScheduleHelper.validateHistoryText('   ', en),
        equals(en.historyErrorTextEmpty),
      );
      expect(
        TaskScheduleHelper.validateHistoryText('bad\x00entry', en),
        equals(en.historyErrorTextInvalid),
      );

      expect(TaskScheduleHelper.normalizeSchedulingNote('  \r\n\t  '), isNull);
      expect(
        TaskScheduleHelper.normalizeSchedulingNote('line1\r\nline2\rline3'),
        equals('line1\nline2\nline3'),
      );
      expect(
        TaskScheduleHelper.validateSchedulingNote('a' * maxTdfNoteLength, en),
        isNull,
      );
      expect(
        TaskScheduleHelper.validateSchedulingNote(
          'a' * (maxTdfNoteLength + 1),
          en,
        ),
        equals(en.schedulingNoteErrorTooLong),
      );
      expect(
        TaskScheduleHelper.validateSchedulingNote('bad\x00note', en),
        equals(en.schedulingNoteErrorInvalid),
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
          localizations: en,
        ),
        equals(en.taskNameErrorEmpty),
      );
      expect(
        TaskScheduleHelper.validateTaskTitle(
          board: board,
          rawTitle: 'existing task',
          excludingTaskId: null,
          localizations: en,
        ),
        equals(en.taskNameErrorDuplicate),
      );
      expect(
        TaskScheduleHelper.validateTaskTitle(
          board: board,
          rawTitle: 'existing task',
          excludingTaskId: 'task000001',
          localizations: en,
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

    test('resolves due and suspended drafts, local timestamps, wall-clock anchors, and remaining durations', () {
      const utcConfig = WebDavConfig(
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: 0,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final helper = container.read(taskScheduleHelperProvider);

      final initialDueAt = DateTime.utc(2026, 11, 25, 14, 30);
      final initialAnchor = TdfLocalDateTime(2026, 11, 25, 14, 30);
      final unchangedDue = helper.resolveDueDraft(
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

      final editedDue = helper.resolveDueDraft(
        configuration: utcConfig,
        hasDue: true,
        rawDueText: '2026-11-26 09:00',
        initialDueAt: initialDueAt,
        initialDueAnchor: initialAnchor,
        initialDueText: '2026-11-25 14:30',
      );
      expect(editedDue.isValid, isTrue);
      expect(editedDue.isUnchanged, isFalse);
      expect(editedDue.dueAt, equals(DateTime.utc(2026, 11, 26, 9, 0)));

      final suspendedForever = helper.resolveSuspendedDraft(
        configuration: utcConfig,
        isSuspended: true,
        rawSuspendedText: '   ',
        initialSuspendedAt: null,
        initialSuspendedText: '',
      );
      expect(suspendedForever.isValid, isTrue);
      expect(suspendedForever.isForever, isTrue);

      final invalidSuspended = helper.resolveSuspendedDraft(
        configuration: utcConfig,
        isSuspended: true,
        rawSuspendedText: 'not-a-date',
        initialSuspendedAt: null,
        initialSuspendedText: '',
      );
      expect(invalidSuspended.isValid, isFalse);

      expect(
        TaskScheduleHelper.formatInitialSuspendedText(
          TaskItem.defaultSuspendedAt,
          utcConfig,
        ),
        isEmpty,
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
          TdfLocalDateTime(2026, 11, 25, 14, 30, 0),
          DateTime(2026, 11, 25, 14, 30, 0),
        ),
        isFalse,
      );
      expect(
        TaskScheduleHelper.differsFromWallClock(
          TdfLocalDateTime(2026, 11, 25, 14, 30, 0),
          DateTime(2026, 11, 25, 15, 30, 0),
        ),
        isTrue,
      );

      final en = lookupAppLocalizations(const Locale('en'));
      expect(
        TaskScheduleHelper.formatRemainingDuration(
          const Duration(days: 2, hours: 5),
          en,
        ),
        equals(en.taskInfoDurationDaysHours('2', '5')),
      );
      expect(
        TaskScheduleHelper.formatRemainingDuration(
          const Duration(hours: 3, minutes: 15),
          en,
        ),
        equals(en.taskInfoDurationHoursMinutes('3', '15')),
      );
      expect(
        TaskScheduleHelper.formatRemainingDuration(
          const Duration(seconds: 20),
          en,
        ),
        equals(en.taskInfoDurationMinutes('1')),
      );
    });
  });
}
