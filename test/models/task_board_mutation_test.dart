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

      expect(
        board.hasDuplicateTaskTitle('  deploy cluster  '),
        isTrue,
        reason: 'hasDuplicateTaskTitle must detect case-insensitive duplicate titles',
      );
      expect(
        board.hasDuplicateTaskTitle('Deploy cluster', excludingTaskId: 't001'),
        isFalse,
        reason: 'hasDuplicateTaskTitle must ignore the task matching excludingTaskId',
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
        reason: 'updateTask must reject empty task titles',
      );

      final afterDuplicateUpdate = board.updateTask(
        't001',
        title: 'audit firewall',
        currentDate: fixedDate,
      );
      expect(
        afterDuplicateUpdate.findTask('t001')?.title,
        equals('Deploy cluster'),
        reason: 'updateTask must reject renaming a task to another existing task title',
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
        reason: 'Promoting edited task to Priority must place it at the top of Focus even when keeping its own title',
      );
      expect(
        promotedPriority.focus.first.note,
        isNull,
        reason: 'Updating note with empty string must clear the note',
      );
    });

    test('sets and updates suspended, blocked prerequisites with cycle prevention, and task condition rules while suspended short-circuits condition evaluation into Blocked', () {
      expect(
        TaskItem.tryParseTdfTimestampInput('  2026-11-05  '),
        equals(DateTime.utc(2026, 11, 5)),
        reason: 'Date-only input must parse to UTC midnight',
      );
      expect(
        TaskItem.tryParseTdfTimestampInput('2026-11-05 09:30'),
        equals(DateTime.utc(2026, 11, 5, 9, 30)),
        reason: 'Date and HH:MM input must parse accurately',
      );
      expect(
        TaskItem.tryParseTdfTimestampInput('2026-11-05 09:30:45'),
        equals(DateTime.utc(2026, 11, 5, 9, 30, 45)),
        reason: 'Date and HH:MM:SS input must parse accurately',
      );
      expect(
        TaskItem.tryParseTdfTimestampInput('2026-11-05 09:30 extra'),
        isNull,
        reason: 'Timestamp input with extra tokens must be rejected',
      );
      expect(
        DayTaskCondition.tryFromTokens(['sun', 'mon', 'mon']),
        equals(
          DayTaskCondition(
            weekdays: const [DateTime.monday, DateTime.sunday],
            dayTokens: const ['mon', 'sun'],
          ),
        ),
        reason: 'DayTaskCondition.tryFromTokens must canonicalize and deduplicate weekday tokens',
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
      expect(
        TimeWindowTaskCondition.tryParse('09:00', '09:00'),
        isNull,
        reason: 'Identical start and end times must be rejected',
      );
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
      expect(
        LocationTaskCondition.tryParse('95.0', '11.0328', '150'),
        isNull,
        reason: 'Out-of-range latitude must be rejected',
      );

      var board = TaskBoard(
        labels: [
          TdfLabel(
            id: 'office',
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
        labelIds: const ['office'],
        conditions: const [GlobalResetTaskCondition()],
        currentDate: fixedDate,
        id: 't_susp',
      );

      expect(
        board.blocked.map((task) => task.id),
        equals(['t_susp']),
        reason: 'Setting suspended in the future must disable evaluation of all other conditions (even condition any or Someday mode) and place the task under Blocked',
      );
      expect(
        board.someday,
        isEmpty,
        reason: 'Suspended task must appear in Blocked rather than Someday',
      );
      expect(board.findTask('t_susp')?.suspendedAt, equals(futureSuspend));

      board = board.updateTask(
        't_susp',
        title: 'Suspended Task With Satisfied Condition Any',
        clearSuspendedAt: true,
        currentDate: fixedDate,
      );
      expect(
        board.focus.map((task) => task.id),
        equals(['t_susp']),
        reason: 'Clearing suspendedAt must re-enable condition evaluation so condition any places the task in Focus',
      );

      board = board.addTask(
        'Dependent Task',
        blockedByTaskIds: const ['t_susp', 't_dependent'],
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
        labelIds: const ['office'],
        currentDate: fixedDate,
        id: 't_dependent',
      );

      expect(
        board.blocked.map((task) => task.id),
        equals(['t_dependent']),
        reason: 'Task with open prerequisite t_susp must be placed in Blocked',
      );
      expect(
        board.findTask('t_dependent')?.blockedByTaskIds,
        equals(['t_susp']),
        reason: 'Self-dependency on t_dependent must be stripped automatically',
      );
      expect(
        board.wouldCreateDependencyCycle('t_susp', 't_dependent'),
        isTrue,
        reason:
            'Adding t_dependent as a prerequisite of t_susp would form a cycle',
      );

      board = board.updateTask(
        't_susp',
        title: 'Suspended Task With Satisfied Condition Any',
        blockedByTaskIds: const ['t_dependent'],
        currentDate: fixedDate,
      );
      expect(
        board.findTask('t_susp')?.blockedByTaskIds,
        isEmpty,
        reason: 'updateTask must reject circular dependency references',
      );

      final serialized = tdfService.serialize(board);
      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(reparsed.blocked.map((task) => task.id), equals(['t_dependent']));
    });

    test('normalizes hex colors, parses/serializes label colors, and rejects duplicate label color directives', () {
      expect(
        TdfColor.normalizeHex('#4caf50'),
        equals('#4CAF50'),
        reason: 'Hex string with leading # must normalize to uppercase #RRGGBB',
      );
      expect(
        TdfColor.normalizeHex('  2196f3 '),
        equals('#2196F3'),
        reason:
            'Hex string without # must prepend # and normalize to uppercase',
      );
      expect(
        TdfColor.normalizeHex('#GGGGGG'),
        isNull,
        reason: 'Non-hex characters must be rejected',
      );
      expect(
        TdfColor.normalizeHex('#12345'),
        isNull,
        reason: '5-character hex string must be rejected',
      );
      expect(
        TdfColor.tryParseArgb('eb06ff'),
        equals(0xFFEB06FF),
        reason: 'Valid 6-digit hex must parse to opaque 32-bit ARGB int',
      );
      expect(
        TdfColor.formatArgb(0xFF00E5FF),
        equals('#00E5FF'),
        reason: '32-bit ARGB int must format to canonical #RRGGBB',
      );

      const labelWithColorTdf = '''
tdf 0.2.0

label office {
    name  "Main Office"
    color "#FF9100"
    note  "Downtown"
}
''';
      final parsed = tdfService.parse(
        labelWithColorTdf,
        evaluationTime: fixedDate,
      );
      expect(parsed.labels.single.id, equals('office'));
      expect(parsed.labels.single.name, equals('Main Office'));
      expect(
        parsed.labels.single.color,
        equals('#FF9100'),
        reason: 'Label block must parse optional color directive',
      );

      final serialized = tdfService.serialize(parsed);
      expect(
        serialized,
        contains('color "#FF9100"'),
        reason: 'Serializer must emit color directive for label block',
      );

      expect(
        () => tdfService.parse(
          'tdf 0.2.0\nlabel home {\n  name "Home"\n  color "#112233"\n  color "#445566"\n}',
          evaluationTime: fixedDate,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.duplicateDirective,
          ),
        ),
        reason: 'Duplicate color directive in label block must fail',
      );
    });

    test('adds and deletes labels on TaskBoard and assigns multiple labels to tasks', () {
      var board = TaskBoard.empty();
      board = board.addLabel('IT & Servers', color: '2196f3');
      board = board.addLabel('IT & Servers', color: '#4CAF50');
      board = board.addLabel('   ', color: '#000000');
      board = board.addLabel('Home Office', color: 'ff9100');

      expect(
        board.labels.map((label) => label.id),
        equals(['l_it_servers', 'l_it_servers_2', 'l_home_office']),
        reason: 'Duplicate label names must generate distinct TDF identifiers',
      );
      expect(
        board.labels.first.color,
        equals('#2196F3'),
        reason: 'Label color must be normalized to #RRGGBB',
      );

      board = board.addTask(
        'Configure VPN router',
        currentDate: fixedDate,
        labelIds: const ['l_it_servers', 'l_home_office'],
      );

      expect(
        board.focus.single.labelIds,
        equals(['l_it_servers', 'l_home_office']),
        reason: 'Task must store multiple selected label IDs',
      );

      board = board.deleteLabel('l_it_servers');
      expect(
        board.labels.map((label) => label.id),
        equals(['l_it_servers_2', 'l_home_office']),
        reason: 'Deleting a label must remove it from board.labels',
      );
      expect(
        board.focus.single.labelIds,
        equals(['l_home_office']),
        reason: 'Deleting a label must strip its ID from referencing tasks',
      );

      expect(
        board.openTaskCountForLabel('l_home_office'),
        equals(1),
        reason:
            'openTaskCountForLabel must count open tasks referencing the label',
      );
      expect(
        board.openTaskCountForLabel('l_it_servers_2'),
        equals(0),
        reason: 'openTaskCountForLabel must return 0 when no open tasks reference the label',
      );

      board = board.renameLabel('l_home_office', '  Remote Work  ');
      expect(
        board.labels.map((label) => label.name),
        equals(['IT & Servers', 'Remote Work']),
        reason: 'renameLabel must update the trimmed display name of the matching label',
      );

      board = board.renameLabel('l_home_office', '   ');
      expect(
        board.labels.map((label) => label.name),
        equals(['IT & Servers', 'Remote Work']),
        reason: 'renameLabel must ignore empty or whitespace-only names',
      );
    });
  });
}
