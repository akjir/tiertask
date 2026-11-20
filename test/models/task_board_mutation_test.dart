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

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/tdf_service.dart';

void main() {
  const tdfService = TdfService();
  final fixedDate = DateTime.utc(2026, 11, 1, 12, 0);

  group('TaskBoard Task & Label Mutations, Validation & Dependency Cycles', () {
    test(
      'Quick-Block moves task from Focus to Blocked and advances Ready upward',
      () {
        final board = TaskBoard(
          focus: [
            TaskItem(id: 'f1', title: 'Blocked Focus Task'),
            TaskItem(id: 'f2', title: 'F2'),
            TaskItem(id: 'f3', title: 'F3'),
          ],
          ready: [TaskItem(id: 'b1', title: 'B1')],
        );

        final blocked = board.blockTask('f1', currentDate: fixedDate);

        expect(
          blocked.focus.map((task) => task.title),
          equals(['F2', 'F3', 'B1']),
        );
        expect(blocked.ready, isEmpty);
        expect(
          blocked.blocked.map((task) => task.title),
          equals(['Blocked Focus Task']),
        );
      },
    );

    test('rejects empty and duplicate task titles in addTask and updateTask while updating all task fields and re-evaluating tiers', () {
      var board = TaskBoard(
        labels: const [
          TdfLabel(id: 'c_it', name: 'IT'),
          TdfLabel(id: 'c_ops', name: 'Ops'),
          TdfLabel(id: 'home', name: 'Home'),
          TdfLabel(id: 'office', name: 'Office'),
        ],
      );

      board = board.addTask(
        'Deploy cluster',
        note: 'Initial note',
        labelIds: const ['c_it', 'office'],
        currentDate: fixedDate,
        id: 't001',
      );
      board = board.addTask(
        'Audit firewall',
        currentDate: fixedDate.add(const Duration(minutes: 5)),
        id: 't002',
      );

      expect(board.hasDuplicateTaskTitle('  deploy cluster  '), isTrue);
      expect(
        board.hasDuplicateTaskTitle('Deploy cluster', excludingTaskId: 't001'),
        isFalse,
      );

      final afterDuplicateAdd = board.addTask(
        'DEPLOY CLUSTER',
        currentDate: fixedDate,
      );
      expect(
        afterDuplicateAdd.allTasks.length,
        equals(2),
        reason: 'addTask must reject duplicate task titles',
      );

      final afterEmptyUpdate = board.updateTask(
        't001',
        title: '   ',
        currentDate: fixedDate,
      );
      expect(
        afterEmptyUpdate.findTask('t001')?.title,
        equals('Deploy cluster'),
      );

      final afterDuplicateUpdate = board.updateTask(
        't001',
        title: 'audit firewall',
        currentDate: fixedDate,
      );
      expect(
        afterDuplicateUpdate.findTask('t001')?.title,
        equals('Deploy cluster'),
        reason: 'updateTask must reject renaming to another existing title',
      );

      final updatedSomeday = board.updateTask(
        't001',
        title: 'Deploy K8s cluster',
        note: 'Updated runbook',
        targetTier: TaskTier.someday,
        isPriority: false,
        labelIds: const ['c_ops', 'home'],
        subtasksAutoFinish: true,
        subtasks: const [
          SubtaskItem(title: 'Prepare nodes', isCompleted: true),
          SubtaskItem(title: 'Bootstrap control plane', isCompleted: false),
        ],
        currentDate: fixedDate,
      );

      expect(
        updatedSomeday.someday.map((task) => task.id),
        equals(['t001']),
        reason: 'Updating targetTier to Someday must move the task to Someday',
      );
      final editedTask = updatedSomeday.findTask('t001')!;
      expect(editedTask.title, equals('Deploy K8s cluster'));
      expect(editedTask.note, equals('Updated runbook'));
      expect(editedTask.labelIds, equals(['c_ops', 'home']));
      expect(editedTask.subtasksAutoFinish, isTrue);
      expect(editedTask.subtasks.length, equals(2));

      final promotedPriority = updatedSomeday.updateTask(
        't001',
        title: 'Deploy K8s cluster',
        note: '',
        targetTier: TaskTier.focus,
        isPriority: true,
        currentDate: fixedDate,
      );
      expect(
        promotedPriority.focus.first.id,
        equals('t001'),
        reason:
            'Promoting edited task to Priority must place it at top of Focus',
      );
      expect(promotedPriority.focus.first.note, isNull);
    });

    test('sets and updates suspended, blocked prerequisites with cycle prevention, and task condition rules while suspended short-circuits condition evaluation into Blocked', () {
      expect(
        TaskItem.tryParseTdfTimestampInput('  2026-11-05  '),
        equals(DateTime.utc(2026, 11, 5)),
      );
      expect(
        TaskItem.tryParseTdfTimestampInput('2026-11-05 09:30'),
        equals(DateTime.utc(2026, 11, 5, 9, 30)),
      );
      expect(
        TaskItem.tryParseTdfTimestampInput('2026-11-05 09:30:45'),
        equals(DateTime.utc(2026, 11, 5, 9, 30, 45)),
      );
      expect(
        TaskItem.tryParseTdfTimestampInput('2026-11-05 09:30 extra'),
        isNull,
      );
      expect(
        DayTaskCondition.tryFromTokens(['sun', 'mon', 'mon']),
        equals(
          DayTaskCondition(
            weekdays: const [DateTime.monday, DateTime.sunday],
            dayTokens: const ['mon', 'sun'],
          ),
        ),
      );
      expect(
        TimeWindowTaskCondition.tryParse('08:00', '17:30'),
        equals(
          const TimeWindowTaskCondition(
            startMinutes: 480,
            endMinutes: 1050,
            startToken: '08:00',
            endToken: '17:30',
          ),
        ),
      );
      expect(TimeWindowTaskCondition.tryParse('09:00', '09:00'), isNull);
      expect(
        LocationTaskCondition.tryParse('50.9787', '11.0328', '150'),
        equals(
          const LocationTaskCondition(
            latitude: 50.9787,
            longitude: 11.0328,
            radiusMeters: 150.0,
          ),
        ),
      );
      expect(LocationTaskCondition.tryParse('95.0', '11.0328', '150'), isNull);

      var board = TaskBoard(
        locations: const [
          TdfLocation(
            id: 'erfurtOkD2',
            name: 'Erfurt',
            latitude: 50.9787,
            longitude: 11.0328,
            radius: 200.0,
          ),
        ],
        labels: [
          TdfLabel(
            id: 'officeOkD2',
            name: 'Office',
            conditions: [
              DayTaskCondition(
                weekdays: const [DateTime.monday],
                dayTokens: const ['mon'],
              ),
            ],
          ),
        ],
      );

      final futureSuspend = DateTime.utc(2026, 11, 5, 9, 0);
      board = board.addTask(
        'Suspended Task With Satisfied Condition Any',
        targetTier: TaskTier.someday,
        suspendedAt: futureSuspend,
        labelIds: const ['officeOkD2'],
        conditions: const [GlobalResetTaskCondition()],
        currentDate: fixedDate,
        id: 'susp00OkD2',
      );

      expect(
        board.blocked.map((task) => task.id),
        equals(['susp00OkD2']),
        reason: 'Future suspendedAt must place the task under Blocked',
      );
      expect(board.someday, isEmpty);
      expect(board.findTask('susp00OkD2')?.suspendedAt, equals(futureSuspend));

      board = board.updateTask(
        'susp00OkD2',
        title: 'Suspended Task With Satisfied Condition Any',
        clearSuspendedAt: true,
        currentDate: fixedDate,
      );
      expect(
        board.focus.map((task) => task.id),
        equals(['susp00OkD2']),
        reason: 'Clearing suspendedAt re-enables condition any into Focus',
      );

      board = board.addTask(
        'Dependent Task',
        blockedByTaskIds: const ['susp00OkD2', 'dependOkD2'],
        conditions: [
          const GroupResetTaskCondition(targetGroup: ConditionGroup.day),
          const TimeWindowTaskCondition(
            startMinutes: 480,
            endMinutes: 1080,
            startToken: '08:00',
            endToken: '18:00',
          ),
          const LocationTaskCondition(locationIds: ['erfurtOkD2']),
        ],
        labelIds: const ['officeOkD2'],
        currentDate: fixedDate,
        id: 'dependOkD2',
      );

      expect(board.blocked.map((task) => task.id), equals(['dependOkD2']));
      expect(
        board.findTask('dependOkD2')?.blockedByTaskIds,
        equals(['susp00OkD2']),
        reason: 'Self-dependency on dependOkD2 must be stripped automatically',
      );
      expect(
        board.wouldCreateDependencyCycle('susp00OkD2', 'dependOkD2'),
        isTrue,
      );

      board = board.updateTask(
        'susp00OkD2',
        title: 'Suspended Task With Satisfied Condition Any',
        blockedByTaskIds: const ['dependOkD2'],
        currentDate: fixedDate,
      );
      expect(
        board.findTask('susp00OkD2')?.blockedByTaskIds,
        isEmpty,
        reason: 'updateTask must reject circular dependency references',
      );

      final serialized = tdfService.serialize(board);
      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(reparsed.blocked.map((task) => task.id), equals(['dependOkD2']));
    });

    test('normalizes hex colors, parses/serializes label colors, and rejects duplicate label color directives', () {
      expect(TdfColor.normalizeHex('#4caf50'), equals('#4CAF50'));
      expect(TdfColor.normalizeHex('  2196f3 '), equals('#2196F3'));
      expect(TdfColor.normalizeHex('#GGGGGG'), isNull);
      expect(TdfColor.normalizeHex('#12345'), isNull);
      expect(TdfColor.tryParseArgb('eb06ff'), equals(0xFFEB06FF));
      expect(TdfColor.formatArgb(0xFF00E5FF), equals('#00E5FF'));

      const labelWithColorTdf = '''
tdf 0.8.0

label officeOkD2 {
    name  "Main Office"
    color "#FF9100"
    note  "Downtown"
}
''';
      final parsed = tdfService.parse(
        labelWithColorTdf,
        evaluationTime: fixedDate,
      );
      expect(parsed.labels.single.id, equals('officeOkD2'));
      expect(parsed.labels.single.name, equals('Main Office'));
      expect(parsed.labels.single.color, equals('#FF9100'));

      final serialized = tdfService.serialize(parsed);
      expect(serialized, contains('color "#FF9100"'));

      expect(
        () => tdfService.parse(
          'tdf 0.8.0\nlabel home00OkD2 {\n  name "Home"\n  color "#112233"\n  color "#445566"\n}',
          evaluationTime: fixedDate,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.duplicateDirective,
          ),
        ),
      );
    });

    test('adds and deletes labels on TaskBoard with 10-character Base62 IDs and assigns multiple labels to tasks', () {
      var board = TaskBoard.empty();
      board = board.addLabel(
        'IT & Servers',
        color: '2196f3',
        currentDate: fixedDate,
      );
      board = board.addLabel(
        'IT & Servers',
        color: '#4CAF50',
        currentDate: fixedDate,
      );
      board = board.addLabel('   ', color: '#000000', currentDate: fixedDate);
      board = board.addLabel(
        'Home Office',
        color: 'ff9100',
        currentDate: fixedDate,
      );

      expect(board.labels.length, equals(3));
      final firstLabelId = board.labels[0].id;
      final secondLabelId = board.labels[1].id;
      final thirdLabelId = board.labels[2].id;
      final expectedTimeSuffix = encodeTdfBase62Time(fixedDate);
      for (final labelId in [firstLabelId, secondLabelId, thirdLabelId]) {
        expect(
          labelId.length,
          equals(10),
          reason: 'ID $labelId must be 10 chars',
        );
        expect(isValidLabelId(labelId), isTrue);
        expect(labelId.endsWith(expectedTimeSuffix), isTrue);
      }
      expect({firstLabelId, secondLabelId, thirdLabelId}.length, equals(3));
      expect(board.labels.first.color, equals('#2196F3'));

      board = board.addTask(
        'Configure VPN router',
        currentDate: fixedDate,
        labelIds: [firstLabelId, thirdLabelId],
      );

      final createdTask = board.focus.single;
      expect(createdTask.id.length, equals(10));
      expect(isValidTaskId(createdTask.id), isTrue);
      expect(createdTask.id.endsWith(expectedTimeSuffix), isTrue);
      expect(createdTask.labelIds, equals([firstLabelId, thirdLabelId]));

      board = board.deleteLabel(firstLabelId);
      expect(
        board.labels.map((label) => label.id),
        equals([secondLabelId, thirdLabelId]),
      );
      expect(board.focus.single.labelIds, equals([thirdLabelId]));
      expect(board.openTaskCountForLabel(thirdLabelId), equals(1));
      expect(board.openTaskCountForLabel(secondLabelId), equals(0));
      expect(
        board.openTaskCountsByLabel,
        equals(<String, int>{thirdLabelId: 1}),
      );
      expect(
        board.sortedLabels.map((label) => label.name),
        equals(['Home Office', 'IT & Servers']),
      );
      expect(board.findLabel(thirdLabelId)?.name, equals('Home Office'));
      expect(board.hasDuplicateLabelName('  home office  '), isTrue);
      expect(
        board.hasDuplicateLabelName(
          '  home office  ',
          excludingLabelId: thirdLabelId,
        ),
        isFalse,
      );

      final updateTime = fixedDate.add(const Duration(minutes: 10));
      board = board.updateLabel(
        thirdLabelId,
        name: '  Remote Work  ',
        color: '4caf50',
        note: '  Home desk setup  ',
        conditions: [
          DayTaskCondition.fromWeekdays(const [DateTime.saturday]),
          const GlobalResetTaskCondition(),
        ],
        currentDate: updateTime,
        localEvaluationTime: updateTime,
      );
      final updatedLabel = board.findLabel(thirdLabelId)!;
      expect(updatedLabel.name, equals('Remote Work'));
      expect(updatedLabel.color, equals('#4CAF50'));
      expect(updatedLabel.note, equals('Home desk setup'));
      expect(
        updatedLabel.conditions,
        equals([
          DayTaskCondition.fromWeekdays(const [DateTime.saturday]),
        ]),
      );
      expect(updatedLabel.modifiedAt, equals(updateTime));
      expect(
        board.blocked.map((task) => task.id),
        equals([createdTask.id]),
        reason: 'Unmet label condition must move referencing task to Blocked',
      );

      board = board.updateLabel(
        thirdLabelId,
        name: '   ',
        currentDate: updateTime,
      );
      expect(board.findLabel(thirdLabelId)?.name, equals('Remote Work'));

      board = board.updateLabel(
        thirdLabelId,
        clearColor: true,
        clearNote: true,
        conditions: const [],
        currentDate: updateTime.add(const Duration(seconds: 5)),
        localEvaluationTime: updateTime.add(const Duration(seconds: 5)),
      );
      final clearedLabel = board.findLabel(thirdLabelId)!;
      expect(clearedLabel.color, isNull);
      expect(clearedLabel.note, isNull);
      expect(clearedLabel.conditions, isEmpty);
      expect(board.focus.map((task) => task.id), equals([createdTask.id]));
    });

    test('toggleSubtask with subtasksAutoFinish on a recurring task reschedules it into Blocked and resets steps', () {
      var board = TaskBoard.empty().addTask(
        'Weekly server maintenance',
        currentDate: fixedDate,
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.weeks),
        subtasksAutoFinish: true,
        subtasks: const [
          SubtaskItem(title: 'Check disk health', isCompleted: true),
          SubtaskItem(title: 'Rotate logs', isCompleted: false),
        ],
      );
      final taskId = board.focus.single.id;

      final toggleTime = fixedDate.add(const Duration(hours: 2));
      board = board.toggleSubtask(taskId, 1, currentDate: toggleTime);

      expect(board.completed, isEmpty);
      expect(board.blocked.map((task) => task.id), equals([taskId]));
      final rescheduled = board.findTask(taskId)!;
      expect(rescheduled.isCompleted, isFalse);
      expect(rescheduled.isPriority, isTrue);
      expect(rescheduled.suspendedAt, equals(DateTime.utc(2026, 11, 8, 0, 0)));
      expect(board.queueTaskIds, equals([taskId]));
      expect(rescheduled.modifiedAt, equals(toggleTime));
      expect(rescheduled.subtasks.every((step) => !step.isCompleted), isTrue);

      final manualUnblockTime = DateTime.utc(2026, 11, 3, 10, 0);
      board = board.updateTask(
        taskId,
        clearSuspendedAt: true,
        currentDate: manualUnblockTime,
      );
      final unblocked = board.findTask(taskId)!;
      expect(unblocked.suspendedAt, isNull);
      expect(board.queueTaskIds, equals([taskId]));
      expect(board.focus.map((task) => task.id), equals([taskId]));
    });

    test('TaskLink validates URI schemes and TaskBoard addTask/updateTask manage links and advance modifiedAt', () {
      expect(TaskLink.isValidUri('https://example.com/docs'), isTrue);
      expect(TaskLink.isValidUri('mailto:ops@example.com'), isTrue);
      expect(TaskLink.isValidUri('obsidian://open?vault=Notes'), isTrue);
      expect(TaskLink.isValidUri('custom+scheme-1.0://resource'), isTrue);
      expect(TaskLink.isValidUri(''), isFalse);
      expect(TaskLink.isValidUri('   '), isFalse);
      expect(TaskLink.isValidUri('example.com/no-scheme'), isFalse);
      expect(TaskLink.isValidUri('://missing-scheme'), isFalse);
      expect(TaskLink.isValidUri('1http://digit-start'), isFalse);
      expect(TaskLink.isValidUri('ht_tp://underscore-in-scheme'), isFalse);
      expect(TaskLink.isValidUri('https://example.com/bad\nchar'), isFalse);
      expect(TaskLink.isValidUri('https://example.com/bad\x7Fchar'), isFalse);

      expect(
        TaskLink.tryParse(
          rawTitle: '  Runbook  ',
          rawUri: '  https://example.com/runbook  ',
        ),
        equals(
          const TaskLink(title: 'Runbook', uri: 'https://example.com/runbook'),
        ),
      );
      expect(
        TaskLink.tryParse(rawTitle: '   ', rawUri: 'https://example.com'),
        isNull,
      );
      expect(TaskLink.tryParse(rawTitle: 'Docs', rawUri: 'not-a-uri'), isNull);

      var board = TaskBoard.empty().addTask(
        'Deploy release',
        currentDate: fixedDate,
        links: const [
          TaskLink(title: 'Runbook', uri: 'https://example.com/runbook'),
          TaskLink(title: 'Ticket', uri: 'https://example.com/issues/42'),
        ],
      );
      final taskId = board.focus.single.id;
      expect(
        board.focus.single.links,
        equals(const [
          TaskLink(title: 'Runbook', uri: 'https://example.com/runbook'),
          TaskLink(title: 'Ticket', uri: 'https://example.com/issues/42'),
        ]),
      );

      final updateTime = fixedDate.add(const Duration(minutes: 15));
      board = board.updateTask(
        taskId,
        currentDate: updateTime,
        links: const [
          TaskLink(title: 'Runbook', uri: 'https://example.com/runbook-v2'),
        ],
      );
      final updated = board.findTask(taskId)!;
      expect(
        updated.links,
        equals(const [
          TaskLink(title: 'Runbook', uri: 'https://example.com/runbook-v2'),
        ]),
      );
      expect(updated.modifiedAt, equals(updateTime));

      final exactLimitLinks = List<TaskLink>.generate(
        maxTdfLinksPerTask,
        (index) =>
            TaskLink(title: 'Link $index', uri: 'https://example.com/$index'),
      );
      board = board.updateTask(
        taskId,
        currentDate: updateTime.add(const Duration(minutes: 5)),
        links: exactLimitLinks,
      );
      expect(board.findTask(taskId)!.links.length, equals(maxTdfLinksPerTask));

      final overLimitLinks = <TaskLink>[
        ...exactLimitLinks,
        const TaskLink(title: 'Link 20', uri: 'https://example.com/20'),
      ];
      expect(
        () => board.updateTask(
          taskId,
          currentDate: updateTime.add(const Duration(minutes: 6)),
          links: overLimitLinks,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'TDF-VAL-002: Exceeding maxTdfLinksPerTask (20) must fail with LimitExceeded',
      );
    });

    test('manages TDF 0.6.0 dueAt, origin, scoped labels with queue flood-protection on deletion, and locations with label-before-task deletion cascade and location any inheritance-trap protection', () {
      var board = TaskBoard.empty();
      board = board.addLocation(
        'Office',
        id: 'locOffOkD2',
        latitude: 50.9787,
        longitude: 11.0328,
        radius: 150,
        note: 'Main office',
        source: 'manual',
        currentDate: fixedDate,
      );
      board = board.addLocation(
        'Office',
        id: 'locAnnex01',
        latitude: 50.9800,
        longitude: 11.0350,
        radius: 100,
        currentDate: fixedDate,
      );
      expect(
        board.locations.length,
        equals(2),
        reason: 'Section 4.3: Duplicate location names must be permitted',
      );

      final updateLocTime = fixedDate.add(const Duration(minutes: 5));
      board = board.updateLocation(
        'locOffOkD2',
        name: 'HQ Office',
        latitude: 50.9790,
        longitude: 11.0330,
        radius: 200,
        note: 'Updated note',
        source: 'gps',
        currentDate: updateLocTime,
      );
      expect(board.findLocation('locOffOkD2')?.name, equals('HQ Office'));
      expect(
        board.findLocation('locOffOkD2')?.modifiedAt,
        equals(updateLocTime),
      );

      board = board.addLabel(
        'Scoped Sprint',
        id: 'lblScoped1',
        isScoped: true,
        currentDate: fixedDate,
      );
      board = board.addLabel(
        'Work',
        id: 'lblWork001',
        conditions: [
          LocationTaskCondition.fromIds(const ['locOffOkD2']),
        ],
        currentDate: fixedDate,
      );

      final dueDate = DateTime.utc(2026, 11, 15, 17, 0);
      const origin = TaskOrigin(namespace: 'caldav', externalKey: 'uid-12345');
      board = board.addTask(
        'Scoped Priority Task',
        id: 'tScpPri001',
        targetTier: TaskTier.focus,
        isPriority: true,
        suspendedAt: DateTime.utc(2026, 11, 10, 9, 0),
        dueAt: dueDate,
        origin: origin,
        labelIds: const ['lblScoped1'],
        currentDate: fixedDate,
      );
      expect(board.findTask('tScpPri001')?.dueAt, equals(dueDate));
      expect(board.findTask('tScpPri001')?.origin, equals(origin));
      expect(board.queueTaskIds, contains('tScpPri001'));

      board = board.addTask(
        'Someday Task With Due',
        id: 'tSomDue001',
        targetTier: TaskTier.someday,
        currentDate: fixedDate,
      );
      final dueUpdateTime = fixedDate.add(const Duration(minutes: 10));
      board = board.updateTask(
        'tSomDue001',
        dueAt: dueDate,
        origin: origin,
        currentDate: dueUpdateTime,
      );
      expect(
        board.queueTaskIds,
        isNot(contains('tSomDue001')),
        reason: 'Section 6.6: Setting due or origin on Someday task must not add it to queue',
      );
      expect(board.findTask('tSomDue001')?.dueAt, equals(dueDate));
      expect(board.findTask('tSomDue001')?.origin, equals(origin));

      board = board.updateTask(
        'tSomDue001',
        clearDueAt: true,
        clearOrigin: true,
        currentDate: dueUpdateTime.add(const Duration(minutes: 1)),
      );
      expect(board.findTask('tSomDue001')?.dueAt, isNull);
      expect(board.findTask('tSomDue001')?.origin, isNull);

      final deleteScopedTime = fixedDate.add(const Duration(minutes: 20));
      board = board.deleteLabel('lblScoped1', currentDate: deleteScopedTime);
      final afterScopedDelete = board.findTask('tScpPri001')!;
      expect(afterScopedDelete.labelIds, isEmpty);
      expect(
        afterScopedDelete.isPriority,
        isFalse,
        reason: 'Section 6.8.1: Deleting the last scoped label on a global-view-restricted task must strip priority',
      );
      expect(
        afterScopedDelete.suspendedAt,
        equals(DateTime.utc(2026, 11, 10, 9, 0)),
        reason: 'Section 6.8.1: Deleting the last scoped label must preserve suspended',
      );
      expect(
        board.queueTaskIds,
        isNot(contains('tScpPri001')),
        reason: 'Section 6.8.1: Deleting the last scoped label must remove the task from queue to prevent global-view flooding',
      );

      board = board.addTask(
        'Task Overriding Work Location to Annex',
        id: 'tOvrAnnex1',
        labelIds: const ['lblWork001'],
        conditions: [
          LocationTaskCondition.fromIds(const ['locAnnex01']),
        ],
        currentDate: fixedDate,
      );

      final deleteAnnexTime = fixedDate.add(const Duration(minutes: 30));
      board = board.deleteLocation('locAnnex01', currentDate: deleteAnnexTime);
      expect(
        board.deletedBlock.findLocationRecord('locAnnex01'),
        equals(
          TdfDeletedLocationRecord(
            locationId: 'locAnnex01',
            deletedAt: deleteAnnexTime,
          ),
        ),
      );
      expect(
        board.findTask('tOvrAnnex1')!.conditions,
        equals(const [
          GroupResetTaskCondition(targetGroup: ConditionGroup.location),
        ]),
        reason: 'Section 6.8.1: Deleting a task location override when an assigned label still has a live location rule must replace the emptied task rule with condition location any',
      );

      board = board.updateTask(
        'tOvrAnnex1',
        conditions: [
          LocationTaskCondition.fromIds(const ['locOffOkD2']),
        ],
        currentDate: deleteAnnexTime.add(const Duration(minutes: 1)),
      );
      final deleteOfficeTime = deleteAnnexTime.add(const Duration(minutes: 5));
      board = board.deleteLocation('locOffOkD2', currentDate: deleteOfficeTime);
      expect(board.findLabel('lblWork001')!.conditions, isEmpty);
      expect(
        board.findTask('tOvrAnnex1')!.conditions,
        isEmpty,
        reason: 'Section 6.8.1: Because label-before-task order removes locOffOkD2 from lblWork001 first, tOvrAnnex1 has no assigned label with a remaining location rule so its emptied location rule is removed completely',
      );
    });
  });

  group('TDF 0.7.0 Label Links, Schedule Notes, History Mutations, Validation & Log Redaction', () {
    tearDown(() {
      AppLogger.resetForTesting();
    });

    test('validates TdfLabel links (max 20, title/URI grammar, pure no-op guard) in addLabel and updateLabel', () {
      var board = TaskBoard.evaluate(
        tasks: <TaskItem>[
          TaskItem(
            id: 'bysExp0001',
            title: 'Bystander With Expired Suspension',
            createdAt: fixedDate.subtract(const Duration(hours: 2)),
            modifiedAt: fixedDate.subtract(const Duration(hours: 2)),
            suspendedAt: fixedDate.subtract(const Duration(hours: 1)),
            suspendedNote: 'Expired',
          ),
        ],
        evaluationTime: fixedDate.subtract(const Duration(hours: 2)),
      );

      final twentyLinks = <TaskLink>[
        for (var i = 0; i < maxTdfLinksPerLabel; i++)
          TaskLink(title: 'Link $i', uri: 'https://example.com/label/$i'),
      ];
      board = board.addLabel(
        'Engineering',
        links: twentyLinks,
        currentDate: fixedDate,
      );
      final createdLabel = board.labels.single;
      expect(createdLabel.links.length, equals(20));
      expect(
        board.findTask('bysExp0001')!.suspendedAt,
        isNull,
        reason: 'Committed addLabel mutation must clean expired task blocks',
      );

      // Pure no-op updateLabel must preserve modifiedAt and not advance revision:
      final unchangedBoard = board.updateLabel(
        createdLabel.id,
        name: 'Engineering',
        links: twentyLinks,
        currentDate: fixedDate.add(const Duration(minutes: 5)),
      );
      expect(
        unchangedBoard.findLabel(createdLabel.id)!.modifiedAt,
        equals(fixedDate),
      );

      // 21 links must throw LimitExceeded:
      expect(
        () => board.updateLabel(
          createdLabel.id,
          links: <TaskLink>[
            ...twentyLinks,
            const TaskLink(title: 'Overflow', uri: 'https://example.com/21'),
          ],
          currentDate: fixedDate.add(const Duration(minutes: 6)),
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
      );

      // Delimiter/control injection in label link title (\n before empty check -> UnexpectedToken) & dangerous URI scheme -> InvalidUri:
      expect(
        () => board.addLabel(
          'Bad Title',
          links: const <TaskLink>[
            TaskLink(title: 'Line1\nLine2', uri: 'https://example.com'),
          ],
          currentDate: fixedDate,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.unexpectedToken,
          ),
        ),
      );
      expect(
        () => board.addLabel(
          'Bad Scheme',
          links: const <TaskLink>[
            TaskLink(title: 'XSS', uri: 'javascript:alert(1)'),
          ],
          currentDate: fixedDate,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.invalidUri,
          ),
        ),
      );
      expect(
        () => board.addLabel(
          'Empty Title',
          links: const <TaskLink>[
            TaskLink(title: '   ', uri: 'https://example.com'),
          ],
          currentDate: fixedDate,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.emptyText,
          ),
        ),
      );
    });

    test('manages due/suspended notes, automatic isDuePassive reset on dueAt change, deleteTask dependent cleanup, and task history CRUD with strict redaction', () {
      AppLogger.resetForTesting(clock: () => fixedDate);
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.debug,
        persistToDisk: false,
      );

      var board = TaskBoard.evaluate(
        tasks: const <TaskItem>[],
        evaluationTime: fixedDate,
      );

      board = board.addTask(
        'Deploy Release',
        targetTier: TaskTier.planned,
        suspendedAt: fixedDate.add(const Duration(hours: 4)),
        suspendedNote: 'Secret freeze note\tline 2',
        dueAt: fixedDate.add(const Duration(hours: 12)),
        isDuePassive: true,
        dueNote: 'Confidential customer deadline\ndetails',
        repeatRule: const TaskRepeatRule(
          count: 1,
          unit: RepeatUnit.weeks,
          leadDays: 3,
        ),
        currentDate: fixedDate,
      );
      final taskId = board.allTasks.single.id;
      final added = board.findTask(taskId)!;
      expect(added.suspendedNote, equals('Secret freeze note\tline 2'));
      expect(added.dueNote, equals('Confidential customer deadline\ndetails'));
      expect(added.isDuePassive, isTrue);
      expect(added.repeatRule?.leadDays, equals(3));

      // Changing dueAt to a new timestamp without specifying isDuePassive resets isDuePassive to false:
      final t1 = fixedDate.add(const Duration(minutes: 1));
      board = board.updateTask(
        taskId,
        dueAt: fixedDate.add(const Duration(hours: 18)),
        currentDate: t1,
      );
      expect(
        board.findTask(taskId)!.isDuePassive,
        isFalse,
        reason: 'Updating dueAt to a different timestamp must reset prior isDuePassive=true to false unless explicitly set',
      );
      expect(
        board.findTask(taskId)!.dueNote,
        equals('Confidential customer deadline\ndetails'),
      );

      // History CRUD + strict no-op revision protection:
      final histTime = DateTime.utc(2026, 11, 1, 9, 30, 0);
      final t2 = fixedDate.add(const Duration(minutes: 2));
      board = board.addTaskHistoryEntry(
        taskId,
        timestampUtc: histTime,
        text: 'Private incident postmortem\u00A0entry',
        currentDate: t2,
      );
      expect(board.findTask(taskId)!.history.length, equals(1));
      expect(board.findTask(taskId)!.modifiedAt, equals(t2));
      final queueModBeforeNoOp = board.queueModifiedAt;

      // Duplicate addTaskHistoryEntry is a strict no-op:
      final afterDupAdd = board.addTaskHistoryEntry(
        taskId,
        timestampUtc: histTime,
        text: 'Private incident postmortem\u00A0entry',
        currentDate: fixedDate.add(const Duration(minutes: 3)),
      );
      expect(afterDupAdd.findTask(taskId)!.modifiedAt, equals(t2));
      expect(afterDupAdd.queueModifiedAt, equals(queueModBeforeNoOp));

      // Update history entry:
      final t3 = fixedDate.add(const Duration(minutes: 4));
      board = board.updateTaskHistoryEntry(
        taskId,
        oldEntry: TaskHistoryEntry(
          timestampUtc: histTime,
          text: 'Private incident postmortem\u00A0entry',
        ),
        newTimestampUtc: histTime.add(const Duration(minutes: 5)),
        newText: 'Updated confidential timeline note',
        currentDate: t3,
      );
      expect(
        board.findTask(taskId)!.history.single.text,
        equals('Updated confidential timeline note'),
      );
      expect(board.findTask(taskId)!.modifiedAt, equals(t3));

      // Remove non-existent entry is a strict no-op:
      final afterMissingRemove = board.removeTaskHistoryEntry(
        taskId,
        entry: TaskHistoryEntry(timestampUtc: histTime, text: 'Does not exist'),
        currentDate: fixedDate.add(const Duration(minutes: 5)),
      );
      expect(afterMissingRemove.findTask(taskId)!.modifiedAt, equals(t3));

      // Remove existing entry advances task.modified once:
      final t4 = fixedDate.add(const Duration(minutes: 6));
      board = board.removeTaskHistoryEntry(
        taskId,
        entry: board.findTask(taskId)!.history.single,
        currentDate: t4,
      );
      expect(board.findTask(taskId)!.history, isEmpty);
      expect(board.findTask(taskId)!.modifiedAt, equals(t4));

      // Assert AppLogger NEVER logged raw suspendedNote, dueNote, or history text!
      final logOutput = AppLogger.fullLogText;
      expect(logOutput, isNot(contains('Secret freeze note')));
      expect(logOutput, isNot(contains('Confidential customer deadline')));
      expect(logOutput, isNot(contains('Private incident postmortem')));
      expect(logOutput, isNot(contains('Updated confidential timeline note')));
      expect(logOutput, contains('task.history_add'));
      expect(logOutput, contains('historyCount=1'));

      // Validation errors on schedule notes, leadDays, and history entries:
      expect(
        () => board.updateTask(taskId, dueNote: ' \t\r\n ', currentDate: t4),
        throwsA(
          isA<TdfException>().having(
            (e) => e.kind,
            'kind',
            TdfErrorKind.emptyText,
          ),
        ),
      );
      expect(
        () => board.updateTask(taskId, dueNote: 'a' * 2001, currentDate: t4),
        throwsA(
          isA<TdfException>().having(
            (e) => e.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
      );
      expect(
        () => board.updateTask(
          taskId,
          repeatRule: const TaskRepeatRule(
            count: 1,
            unit: RepeatUnit.days,
            leadDays: 3651,
          ),
          currentDate: t4,
        ),
        throwsA(
          isA<TdfException>().having(
            (e) => e.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
      );
      expect(
        () => board.addTaskHistoryEntry(
          taskId,
          timestampUtc: histTime,
          text: '\t',
          currentDate: t4,
        ),
        throwsA(
          isA<TdfException>().having(
            (e) => e.kind,
            'kind',
            TdfErrorKind.unexpectedToken,
          ),
        ),
        reason: 'Control character \\t must fail with UnexpectedToken before EmptyText',
      );
      expect(
        () => board.addTaskHistoryEntry(
          taskId,
          timestampUtc: histTime,
          text: '   ',
          currentDate: t4,
        ),
        throwsA(
          isA<TdfException>().having(
            (e) => e.kind,
            'kind',
            TdfErrorKind.emptyText,
          ),
        ),
      );
      expect(
        () => board.addTaskHistoryEntry(
          taskId,
          timestampUtc: histTime,
          text: 'x' * 501,
          currentDate: t4,
        ),
        throwsA(
          isA<TdfException>().having(
            (e) => e.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
      );

      // Deleting a prerequisite task immediately strips blocked references to it from open dependents:
      board = board.addTask(
        'Dependent Waiting On Deploy',
        targetTier: TaskTier.focus,
        blockedByTaskIds: <String>[taskId],
        currentDate: t4.add(const Duration(minutes: 1)),
      );
      final depId = board.allTasks.firstWhere((t) => t.id != taskId).id;
      expect(board.findTask(depId)!.blockedByTaskIds, equals(<String>[taskId]));

      board = board.deleteTask(
        taskId,
        currentDate: t4.add(const Duration(minutes: 2)),
      );
      expect(
        board.findTask(depId)!.dependencies,
        isEmpty,
        reason: 'Deleting a task must immediately strip blocked references targeting its newly tombstoned ID',
      );
    });

    test('resets isDuePassive to false on explicit priority promotion in updateTask per Section 6.6 while honoring explicit overrides', () {
      final t0 = DateTime.utc(2026, 11, 15, 10, 0);
      final dueTime = DateTime.utc(2026, 11, 20, 12, 0);
      var board = TaskBoard.empty().addTask(
        'Passive Deadline Task',
        targetTier: TaskTier.planned,
        dueAt: dueTime,
        isDuePassive: true,
        dueNote: 'Cutoff',
        currentDate: t0,
      );
      final taskId = board.allTasks.single.id;
      expect(board.findTask(taskId)!.isDuePassive, isTrue);

      // Explicit isPriority: true resets isDuePassive to false and advances modifiedAt:
      final t1 = t0.add(const Duration(minutes: 5));
      board = board.updateTask(taskId, isPriority: true, currentDate: t1);
      final afterPriority = board.findTask(taskId)!;
      expect(
        afterPriority.isPriority,
        isTrue,
        reason: 'Task must have explicit priority enabled',
      );
      expect(
        afterPriority.isDuePassive,
        isFalse,
        reason: 'Section 6.6: explicitly setting priority to true must reset passive to false',
      );
      expect(
        afterPriority.dueNote,
        equals('Cutoff'),
        reason:
            'Resetting passive must preserve dueNote when dueAt is unchanged',
      );
      expect(afterPriority.effectiveModifiedAt, equals(t1));

      // Explicit isDuePassive: true alongside isPriority: true is honored:
      final t2 = t1.add(const Duration(minutes: 5));
      board = board.updateTask(
        taskId,
        isPriority: true,
        isDuePassive: true,
        currentDate: t2,
      );
      expect(
        board.findTask(taskId)!.isDuePassive,
        isTrue,
        reason: 'Explicit isDuePassive: true must be honored even on priority tasks',
      );

      // Editing an unrelated field (title) without passing isPriority or targetTier preserves isDuePassive:
      final t3 = t2.add(const Duration(minutes: 5));
      board = board.updateTask(
        taskId,
        title: 'Passive Deadline Task Renamed',
        currentDate: t3,
      );
      expect(
        board.findTask(taskId)!.isDuePassive,
        isTrue,
        reason: 'Unrelated updateTask calls must preserve existing isDuePassive on priority tasks',
      );

      // Explicit targetTier: TaskTier.focus resets isDuePassive to false when isDuePassive is omitted:
      final t4 = t3.add(const Duration(minutes: 5));
      board = board.updateTask(taskId, isPriority: false, currentDate: t4);
      expect(board.findTask(taskId)!.isDuePassive, isTrue);
      final t5 = t4.add(const Duration(minutes: 5));
      board = board.updateTask(
        taskId,
        targetTier: TaskTier.focus,
        currentDate: t5,
      );
      expect(
        board.findTask(taskId)!.isDuePassive,
        isFalse,
        reason: 'Explicit targetTier: focus promotion must reset isDuePassive to false',
      );
      expect(board.findTask(taskId)!.effectiveModifiedAt, equals(t5));
    });
  });

  group('TDF 0.8.0 Local Calendar Scheduling Inputs (TDF-CAL-001), dueAnchor & Bound Enforcement', () {
    test('resolves dueLocalInput and suspendedLocalInput across CET/CEST gap & fold, manages dueAnchor/isDuePassive/no-op invariants, and enforces queue/deleted bounds', () {
      final berlin = TdfTimeZoneContext.named('Europe/Berlin');
      final t0 = DateTime.utc(2026, 1, 15, 9, 0);

      // 1. Winter CET (UTC+1) dueLocalInput + Someday queue exclusion (TDF-MUT-008):
      var board = TaskBoard.empty().addTask(
        'Someday Winter Deadline',
        id: 'someDue001',
        targetTier: TaskTier.someday,
        dueLocalInput: TdfLocalDateTime(2026, 1, 31, 18, 0, 0),
        dueNote: 'Month-end cutoff',
        currentDate: t0,
        timeZone: berlin,
      );
      final someDue = board.findTask('someDue001')!;
      expect(
        someDue.dueAt,
        equals(DateTime.utc(2026, 1, 31, 17, 0, 0)),
        reason: 'CET (UTC+1) 18:00 local must resolve to 17:00 UTC',
      );
      expect(
        someDue.dueAnchor,
        equals(TdfLocalDateTime(2026, 1, 31, 18, 0, 0)),
      );
      expect(
        board.queueTaskIds,
        isNot(contains('someDue001')),
        reason: 'TDF-MUT-008: setting due on Someday never adds task to queue',
      );

      // Updating dueLocalInput on Someday across Spring DST Gap (2026-03-29 02:30 -> pre-gap UTC+1 = 01:30Z, anchor stays 02:30):
      final t1 = t0.add(const Duration(minutes: 5));
      board = board.updateTask(
        'someDue001',
        dueLocalInput: TdfLocalDateTime(2026, 3, 29, 2, 30, 0),
        isDuePassive: true,
        currentDate: t1,
        timeZone: berlin,
      );
      final gapDue = board.findTask('someDue001')!;
      expect(
        gapDue.dueAt,
        equals(DateTime.utc(2026, 3, 29, 1, 30, 0)),
        reason: 'TDF-CAL-001: spring-forward gap applies pre-gap UTC+1 offset',
      );
      expect(
        gapDue.dueAnchor,
        equals(TdfLocalDateTime(2026, 3, 29, 2, 30, 0)),
        reason: 'dueAnchor retains unshifted intended 02:30 local clock',
      );
      expect(gapDue.isDuePassive, isTrue);
      expect(
        board.queueTaskIds,
        isNot(contains('someDue001')),
        reason: 'Editing due on Someday task must keep it outside queue',
      );

      // Setting finite suspendedLocalInput across Autumn Fold (2026-10-25 02:30 -> earliest CEST UTC+2 = 00:30Z) places unscheduled task in queue:
      final t2 = t1.add(const Duration(minutes: 5));
      board = board.updateTask(
        'someDue001',
        suspendedLocalInput: TdfLocalDateTime(2026, 10, 25, 2, 30, 0),
        currentDate: t2,
        timeZone: berlin,
      );
      final foldSusp = board.findTask('someDue001')!;
      expect(
        foldSusp.suspendedAt,
        equals(DateTime.utc(2026, 10, 25, 0, 30, 0)),
        reason:
            'TDF-CAL-001: autumn fold selects earliest occurrence (CEST UTC+2)',
      );
      expect(
        board.queueTaskIds,
        contains('someDue001'),
        reason: 'TDF-MUT-008: setting future suspended on unscheduled task appends it to queue',
      );

      // Summer CEST (UTC+2) dueLocalInput + setting isSuspendedForever: true on Someday places task in queue:
      board = board.addTask(
        'Summer Someday Task',
        id: 'sumSome001',
        targetTier: TaskTier.someday,
        dueLocalInput: TdfLocalDateTime(2026, 7, 15, 12, 0, 0),
        currentDate: t2,
        timeZone: berlin,
      );
      expect(
        board.findTask('sumSome001')!.dueAt,
        equals(DateTime.utc(2026, 7, 15, 10, 0, 0)),
        reason: 'CEST (UTC+2) 12:00 local must resolve to 10:00 UTC',
      );
      expect(board.queueTaskIds, isNot(contains('sumSome001')));
      board = board.updateTask(
        'sumSome001',
        isSuspendedForever: true,
        currentDate: t2,
        timeZone: berlin,
      );
      expect(
        board.queueTaskIds,
        contains('sumSome001'),
        reason: 'TDF-MUT-008: setting suspended forever on unscheduled task appends it to queue',
      );

      // 2. Pure no-op guard vs dueAnchor-only mutation & isDuePassive reset:
      board = board.addTask(
        'Bystander Expired Deferral',
        id: 'bysNoOp001',
        targetTier: TaskTier.someday,
        currentDate: t0,
      );
      // Inject an expired deferral onto bystander without advancing modifiedAt to verify pure no-op skips cleanup:
      board = TaskBoard.evaluate(
        tasks: <TaskItem>[
          for (final item in board.allTasks)
            item.id == 'bysNoOp001'
                ? item.copyWith(
                    suspendedAt: t0.subtract(const Duration(minutes: 10)),
                    suspendedNote: 'Expired note',
                  )
                : item,
        ],
        queueBlock: board.queueBlock,
        evaluationTime: t2,
        timeZone: berlin,
      );
      final t3 = t2.add(const Duration(minutes: 5));
      final noopBoard = board.updateTask(
        'someDue001',
        dueAt: foldSusp.dueAt,
        dueAnchor: foldSusp.dueAnchor,
        currentDate: t3,
        timeZone: berlin,
      );
      expect(
        noopBoard,
        same(board),
        reason: 'TDF-MUT-001: unchanged dueAt + dueAnchor must return board untouched',
      );
      expect(
        noopBoard.findTask('bysNoOp001')!.suspendedAt,
        isNotNull,
        reason: 'Pure no-op must skip board-wide block-reason cleanup',
      );

      // Changing dueAnchor alone resets isDuePassive to false and advances modifiedAt once:
      board = board.updateTask(
        'someDue001',
        dueAnchor: TdfLocalDateTime(2026, 3, 31, 2, 30, 0),
        currentDate: t3,
        timeZone: berlin,
      );
      final anchorEdited = board.findTask('someDue001')!;
      expect(
        anchorEdited.dueAnchor,
        equals(TdfLocalDateTime(2026, 3, 31, 2, 30, 0)),
      );
      expect(
        anchorEdited.isDuePassive,
        isFalse,
        reason: 'TDF-MUT-008: changing dueAnchor must reset isDuePassive to false when omitted',
      );
      expect(anchorEdited.modifiedAt, equals(t3));
      expect(
        board.findTask('bysNoOp001')!.suspendedAt,
        isNull,
        reason: 'Committed anchor-only mutation must run block cleanup',
      );

      // Re-enable isDuePassive, then clearDueAnchor alone -> sets dueAnchor = null and resets isDuePassive = false:
      final t4 = t3.add(const Duration(minutes: 5));
      board = board.updateTask(
        'someDue001',
        isDuePassive: true,
        currentDate: t4,
        timeZone: berlin,
      );
      expect(board.findTask('someDue001')!.isDuePassive, isTrue);
      expect(
        board.findTask('someDue001')!.dueAnchor,
        equals(TdfLocalDateTime(2026, 3, 31, 2, 30, 0)),
      );

      final t5 = t4.add(const Duration(minutes: 5));
      board = board.updateTask(
        'someDue001',
        clearDueAnchor: true,
        currentDate: t5,
        timeZone: berlin,
      );
      final anchorCleared = board.findTask('someDue001')!;
      expect(anchorCleared.dueAt, equals(DateTime.utc(2026, 3, 29, 1, 30)));
      expect(anchorCleared.dueAnchor, isNull);
      expect(anchorCleared.isDuePassive, isFalse);
      expect(anchorCleared.modifiedAt, equals(t5));

      // clearDueAt clears dueAt, dueAnchor, isDuePassive, and dueNote:
      final t6 = t5.add(const Duration(minutes: 5));
      board = board
          .updateTask(
            'someDue001',
            dueAnchor: TdfLocalDateTime(2026, 3, 29, 3, 30, 0),
            isDuePassive: true,
            currentDate: t6,
            timeZone: berlin,
          )
          .updateTask(
            'someDue001',
            clearDueAt: true,
            currentDate: t6.add(const Duration(minutes: 1)),
            timeZone: berlin,
          );
      final dueCleared = board.findTask('someDue001')!;
      expect(dueCleared.dueAt, isNull);
      expect(dueCleared.dueAnchor, isNull);
      expect(dueCleared.isDuePassive, isFalse);
      expect(dueCleared.dueNote, isNull);

      // 3. Error mapping on dueLocalInput / suspendedLocalInput:
      expect(
        () => board.addTask(
          'Missing Zone Local Input',
          dueLocalInput: TdfLocalDateTime(2026, 5, 1, 10, 0),
          currentDate: t6,
          timeZone: const TdfTimeZoneContext.missing('Mars/Phobos'),
        ),
        throwsA(
          isA<TdfContextException>().having(
            (error) => error.kind,
            'kind',
            TdfContextOutcomeKind.timeZoneContextRequired,
          ),
        ),
      );
      expect(
        () => board.addTask(
          'Underflow 0001 Local Input',
          dueLocalInput: TdfLocalDateTime(1, 1, 1, 0, 0, 0),
          currentDate: t6,
          timeZone: berlin,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.invalidTimestamp,
          ),
        ),
      );

      // 4. maxTdfQueueEntries (4096) & maxTdfDeletedRecords (4096) bounds throw TdfException(limitExceeded):
      final fullQueueTasks = <TaskItem>[
        for (var i = 0; i < maxTdfQueueEntries; i++)
          TaskItem(
            id: 'fq${i.toString().padLeft(4, '0')}OkD2',
            title: 'Queued $i',
            createdAt: t0,
          ),
        TaskItem(id: 'someExtra1', title: 'Extra Someday', createdAt: t0),
      ];
      final fullQueueBoard = TaskBoard.evaluate(
        tasks: fullQueueTasks,
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: <String>[
            for (var i = 0; i < maxTdfQueueEntries; i++)
              'fq${i.toString().padLeft(4, '0')}OkD2',
          ],
        ),
        evaluationTime: t0,
      );
      expect(
        () => fullQueueBoard.scheduleTask('someExtra1', currentDate: t1),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Appending 4097th queue entry must throw TdfException(limitExceeded)',
      );

      final fullDeletedBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[
          TaskItem(id: 'delOverflow', title: 'Overflow Del', createdAt: t0),
        ],
        deletedBlock: TdfDeletedBlock(
          generation: 0,
          tasks: <TdfDeletedTaskRecord>[
            for (var i = 0; i < maxTdfDeletedRecords; i++)
              TdfDeletedTaskRecord(
                taskId: 'dt${i.toString().padLeft(4, '0')}OkD2',
                deletedAt: t0,
              ),
          ],
        ),
        evaluationTime: t0,
      );
      expect(
        () => fullDeletedBoard.deleteTask('delOverflow', currentDate: t1),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason:
            'Recording 4097th tombstone must throw TdfException(limitExceeded)',
      );
    });

    test('deleteLabel evicts queued scoped tasks in one queue.modified tick and preserves isPriority on unqueued or completed tasks', () {
      final t0 = DateTime.utc(2026, 7, 1, 10, 0, 0);
      final t1 = t0.add(const Duration(seconds: 10));
      const scopedLabel = TdfLabel(
        id: 'lblScpDel1',
        name: 'Private',
        isScoped: true,
      );
      final queuedA = TaskItem(
        id: 'scpQ000001',
        title: 'Queued Scoped A',
        isPriority: true,
        createdAt: t0,
        modifiedAt: t0,
        labelIds: const <String>['lblScpDel1'],
      );
      final queuedB = TaskItem(
        id: 'scpQ000002',
        title: 'Queued Scoped B',
        isPriority: true,
        createdAt: t0,
        modifiedAt: t0,
        labelIds: const <String>['lblScpDel1'],
      );
      final unqueuedSomeday = TaskItem(
        id: 'scpSome001',
        title: 'Unqueued Someday Scoped',
        isPriority: true,
        createdAt: t0,
        modifiedAt: t0,
        labelIds: const <String>['lblScpDel1'],
      );
      final completedScoped = TaskItem(
        id: 'scpDone001',
        title: 'Completed Scoped',
        isCompleted: true,
        completions: 1,
        isPriority: true,
        createdAt: t0,
        completedAt: t0,
        modifiedAt: t0,
        labelIds: const <String>['lblScpDel1'],
      );
      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[queuedA, queuedB, unqueuedSomeday, completedScoped],
        labels: const <TdfLabel>[scopedLabel],
        queueBlock: TdfQueueBlock(
          modifiedAt: t1,
          taskIds: const <String>['scpQ000001', 'scpQ000002'],
        ),
        evaluationTime: t1,
      );

      final afterDelete = board.deleteLabel('lblScpDel1', currentDate: t1);
      expect(afterDelete.queueTaskIds, isEmpty);
      expect(
        afterDelete.queueBlock.modifiedAt,
        equals(t1.add(const Duration(seconds: 1))),
        reason: 'Evicting multiple tasks from queue during deleteLabel must advance queue.modified at most once (+1s, not +Ns)',
      );
      expect(afterDelete.findTask('scpQ000001')!.isPriority, isFalse);
      expect(afterDelete.findTask('scpQ000002')!.isPriority, isFalse);
      expect(
        afterDelete.findTask('scpSome001')!.isPriority,
        isTrue,
        reason: 'Unqueued Someday task losing its sole scoped label must retain isPriority',
      );
      expect(
        afterDelete.findTask('scpDone001')!.isPriority,
        isTrue,
        reason: 'Completed task losing its sole scoped label must retain isPriority',
      );
    });

    test('updateTask enforces maxTdfCompletions on completion transition and maxTdfArgsPerStmt on dependencies', () {
      final t0 = DateTime.utc(2026, 7, 2, 10, 0, 0);
      final t1 = t0.add(const Duration(minutes: 1));
      final maxOpen = TaskItem(
        id: 'maxComp001',
        title: 'Max Completions Open',
        completions: maxTdfCompletions,
        createdAt: t0,
        modifiedAt: t0,
        subtasksAutoFinish: true,
        subtasks: const <SubtaskItem>[
          SubtaskItem(title: 'Last Step', isCompleted: false),
        ],
      );
      final maxDone = TaskItem(
        id: 'maxDone001',
        title: 'Max Completions Done',
        isCompleted: true,
        completions: maxTdfCompletions,
        createdAt: t0,
        completedAt: t0,
        modifiedAt: t0,
      );
      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[maxOpen, maxDone],
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: const <String>['maxComp001'],
        ),
        evaluationTime: t0,
      );

      expect(
        () => board.updateTask(
          'maxComp001',
          targetTier: TaskTier.completed,
          currentDate: t1,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Completing an open task at maxTdfCompletions via targetTier must throw LimitExceeded',
      );
      expect(
        () => board.updateTask(
          'maxComp001',
          subtasks: const <SubtaskItem>[
            SubtaskItem(title: 'Last Step', isCompleted: true),
          ],
          currentDate: t1,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Auto-finishing an open task at maxTdfCompletions via updateTask must throw LimitExceeded',
      );

      // Editing an already-Completed task at maxTdfCompletions must still succeed:
      final editedDone = board.updateTask(
        'maxDone001',
        note: 'Still completed at max',
        currentDate: t1,
      );
      expect(
        editedDone.findTask('maxDone001')!.completions,
        equals(maxTdfCompletions),
      );

      // _armDeps enforces maxTdfArgsPerStmt (64 allowed, 65 throws LimitExceeded):
      final sixtyFourIds = <String>[
        for (var i = 0; i < maxTdfArgsPerStmt; i++)
          'dep${i.toString().padLeft(4, '0')}Ok1',
      ];
      final sixtyFiveIds = <String>[...sixtyFourIds, 'dep0064Ok1'];
      final sixtyFiveDeps = <TdfTaskDependency>[
        for (final id in sixtyFiveIds)
          TdfTaskDependency(taskId: id, requiredCompletion: 1),
      ];

      final atLimit = board.addTask(
        'Exactly 64 Deps',
        id: 'depLim6401',
        blockedByTaskIds: sixtyFourIds,
        currentDate: t1,
      );
      expect(
        atLimit.findTask('depLim6401')!.dependencies.length,
        equals(maxTdfArgsPerStmt),
      );
      expect(
        () => board.addTask(
          'Over 64 Blocked Ids',
          blockedByTaskIds: sixtyFiveIds,
          currentDate: t1,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
      );
      expect(
        () => board.addTask(
          'Over 64 Explicit Deps',
          dependencies: sixtyFiveDeps,
          currentDate: t1,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
      );
    });

    test('addLabel and addLocation populate modifiedAt when currentDate and modifiedAt are omitted', () {
      final afterAdd = TaskBoard.empty()
          .addLabel('Default Stamp Label', id: 'lblDefStmp')
          .addLocation(
            'Default Stamp Location',
            id: 'locDefStmp',
            latitude: 52.52,
            longitude: 13.405,
            radius: 150,
          );
      expect(
        afterAdd.findLabel('lblDefStmp')!.modifiedAt,
        isNotNull,
        reason: 'addLabel must initialize modifiedAt even when currentDate and modifiedAt are omitted',
      );
      expect(
        afterAdd.findLocation('locDefStmp')!.modifiedAt,
        isNotNull,
        reason: 'addLocation must initialize modifiedAt even when currentDate and modifiedAt are omitted',
      );
    });

    test('deleteLocation aggregates multiple LocationTaskCondition objects without emitting mixed location any + concrete id', () {
      final t0 = DateTime.utc(2026, 7, 3, 10, 0, 0);
      final t1 = t0.add(const Duration(minutes: 1));
      const locA = TdfLocation(
        id: 'locDelA001',
        name: 'Site A',
        latitude: 52.5,
        longitude: 13.4,
        radius: 100,
      );
      const locB = TdfLocation(
        id: 'locKeepB01',
        name: 'Site B',
        latitude: 52.6,
        longitude: 13.5,
        radius: 100,
      );
      const locLabel = TdfLabel(
        id: 'lblLoc0001',
        name: 'Field',
        conditions: <TaskCondition>[
          LocationTaskCondition(locationIds: <String>['locKeepB01']),
        ],
      );
      final multiLocTask = TaskItem(
        id: 'tskMultiL1',
        title: 'Task With Multiple Location Rules',
        createdAt: t0,
        modifiedAt: t0,
        labelIds: const <String>['lblLoc0001'],
        conditions: const <TaskCondition>[
          LocationTaskCondition(locationIds: <String>['locDelA001']),
          LocationTaskCondition(locationIds: <String>['locKeepB01']),
        ],
      );
      final allDeletedLocTask = TaskItem(
        id: 'tskAllDel1',
        title: 'Task With Duplicate Deleted Location Rules',
        createdAt: t0,
        modifiedAt: t0,
        labelIds: const <String>['lblLoc0001'],
        conditions: const <TaskCondition>[
          LocationTaskCondition(locationIds: <String>['locDelA001']),
          LocationTaskCondition(locationIds: <String>['locDelA001']),
        ],
      );
      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[multiLocTask, allDeletedLocTask],
        labels: const <TdfLabel>[locLabel],
        locations: const <TdfLocation>[locA, locB],
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: const <String>['tskMultiL1', 'tskAllDel1'],
        ),
        evaluationTime: t0,
      );

      final afterDelete = board.deleteLocation('locDelA001', currentDate: t1);
      final updatedMulti = afterDelete.findTask('tskMultiL1')!;
      expect(
        updatedMulti.conditions,
        equals(const <TaskCondition>[
          LocationTaskCondition(locationIds: <String>['locKeepB01']),
        ]),
        reason: 'Surviving location ID in a second LocationTaskCondition must suppress GroupResetTaskCondition(location)',
      );
      final updatedAllDel = afterDelete.findTask('tskAllDel1')!;
      expect(
        updatedAllDel.conditions,
        equals(const <TaskCondition>[
          GroupResetTaskCondition(targetGroup: ConditionGroup.location),
        ]),
        reason: 'When all LocationTaskCondition objects become empty, emit exactly one location any reset',
      );
    });
  });
}
