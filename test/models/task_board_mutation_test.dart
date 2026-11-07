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
import 'package:tiertask/models/tdf_metadata.dart';
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
          const LocationTaskCondition(
            latitude: 50.9787,
            longitude: 11.0328,
            radiusMeters: 200.0,
          ),
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
tdf 0.5.0

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
          'tdf 0.5.0\nlabel home00OkD2 {\n  name "Home"\n  color "#112233"\n  color "#445566"\n}',
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

      final overLimitLinks = List<TaskLink>.generate(
        TaskLink.maxLinksPerTask + 5,
        (index) =>
            TaskLink(title: 'Link $index', uri: 'https://example.com/$index'),
      );
      board = board.updateTask(
        taskId,
        currentDate: updateTime.add(const Duration(minutes: 5)),
        links: overLimitLinks,
      );
      expect(
        board.findTask(taskId)!.links.length,
        equals(TaskLink.maxLinksPerTask),
      );
    });
  });
}
