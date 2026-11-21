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
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/presentation/label_editor_controller.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/services/app_logger.dart';

class _RecordingTaskNotifier extends TaskNotifier {
  final List<String> addedLabels = <String>[];
  final List<String> deletedLabels = <String>[];
  String? updatedLabelId;
  String? updatedName;
  String? updatedColor;
  bool? updatedClearColor;
  String? updatedNote;
  bool? updatedClearNote;
  bool? updatedIsScoped;
  List<TaskLink>? updatedLinks;
  List<TaskCondition>? updatedConditions;

  @override
  Future<TaskBoard> build() async => TaskBoard.empty();

  @override
  Future<void> addLabel(
    String name, {
    String? color,
    String? id,
    String? note,
    bool isScoped = false,
    Iterable<TaskLink>? links,
    List<TaskCondition> conditions = const <TaskCondition>[],
    DateTime? currentDate,
  }) async {
    addedLabels.add(name);
  }

  @override
  Future<void> deleteLabel(String labelId, {DateTime? currentDate}) async {
    deletedLabels.add(labelId);
  }

  @override
  Future<void> updateLabel(
    String labelId, {
    String? name,
    bool? isScoped,
    String? color,
    bool clearColor = false,
    String? note,
    bool clearNote = false,
    Iterable<TaskLink>? links,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
  }) async {
    updatedLabelId = labelId;
    updatedName = name;
    updatedColor = color;
    updatedClearColor = clearColor;
    updatedNote = note;
    updatedClearNote = clearNote;
    updatedIsScoped = isScoped;
    updatedLinks = links?.toList();
    updatedConditions = conditions;
  }
}

void main() {
  setUp(() {
    AppLogger.resetForTesting(clock: () => DateTime.utc(2026, 11, 21, 10));
  });

  tearDown(() {
    AppLogger.resetForTesting();
  });

  group('LabelEditorController', () {
    test('validates empty name, case-insensitive duplicates excluding self, and hex color', () {
      final container = ProviderContainer(
        overrides: [appLocaleProvider.overrideWithValue(const Locale('en'))],
      );
      addTearDown(container.dispose);

      final controller = container.read(labelEditorControllerProvider);
      final en = lookupAppLocalizations(const Locale('en'));
      final board = TaskBoard.empty()
          .addLabel('Work', id: 'l1', currentDate: DateTime.utc(2026, 11, 21))
          .addLabel(
            'Personal',
            id: 'l2',
            currentDate: DateTime.utc(2026, 11, 21),
          );

      final empty = controller.validateLabel(
        board: board,
        labelId: 'l1',
        rawName: '   ',
        rawColor: '',
      );
      expect(empty.isValid, isFalse);
      expect(empty.errorKind, equals(LabelValidationErrorKind.emptyName));
      expect(empty.errorMessage, equals(en.labelNameErrorEmpty));

      final duplicate = controller.validateLabel(
        board: board,
        labelId: 'l1',
        rawName: 'personal',
        rawColor: '',
      );
      expect(duplicate.isValid, isFalse);
      expect(
        duplicate.errorKind,
        equals(LabelValidationErrorKind.duplicateName),
      );
      expect(duplicate.errorMessage, equals(en.labelNameErrorDuplicate));

      final selfCaseChange = controller.validateLabel(
        board: board,
        labelId: 'l1',
        rawName: 'WORK',
        rawColor: '#1a2b3c',
      );
      expect(selfCaseChange.isValid, isTrue);
      expect(selfCaseChange.trimmedName, equals('WORK'));
      expect(selfCaseChange.normalizedColor, equals('#1A2B3C'));

      final badColor = controller.validateLabel(
        board: board,
        labelId: 'l1',
        rawName: 'Work',
        rawColor: 'not-a-hex',
      );
      expect(badColor.isValid, isFalse);
      expect(badColor.errorKind, equals(LabelValidationErrorKind.invalidColor));
      expect(badColor.errorMessage, equals(en.labelColorErrorInvalid));
    });

    test(
      'persists addLabel, saveLabel with redacted telemetry, and deleteLabel',
      () async {
        AppLogger.setEnabled(
          true,
          minimumLevel: LogLevel.info,
          persistToDisk: false,
        );
        final taskNotifier = _RecordingTaskNotifier();
        final container = ProviderContainer(
          overrides: [taskNotifierProvider.overrideWith(() => taskNotifier)],
        );
        addTearDown(container.dispose);
        await container.read(taskNotifierProvider.future);

        final controller = container.read(labelEditorControllerProvider);

        await controller.addLabel('   ');
        expect(taskNotifier.addedLabels, isEmpty);
        await controller.addLabel('  Focus  ');
        expect(taskNotifier.addedLabels, equals(['Focus']));

        const links = <TaskLink>[
          TaskLink(title: 'Secret Docs', uri: 'https://secret.example.com/key'),
        ];
        await controller.saveLabel(
          labelId: 'l1',
          name: 'Work',
          normalizedColor: '#112233',
          clearColor: false,
          note: 'Confidential label note',
          isScoped: true,
          links: links,
          conditions: const <TaskCondition>[],
        );

        expect(taskNotifier.updatedLabelId, equals('l1'));
        expect(taskNotifier.updatedName, equals('Work'));
        expect(taskNotifier.updatedColor, equals('#112233'));
        expect(taskNotifier.updatedClearColor, isFalse);
        expect(taskNotifier.updatedNote, equals('Confidential label note'));
        expect(taskNotifier.updatedClearNote, isFalse);
        expect(taskNotifier.updatedIsScoped, isTrue);
        expect(taskNotifier.updatedLinks, equals(links));

        final logText = AppLogger.fullLogText;
        expect(
          logText,
          contains('ui.label_editor.save | id=l1 links=1 scoped=true'),
        );
        expect(logText, isNot(contains('Confidential label note')));
        expect(logText, isNot(contains('secret.example.com')));

        await controller.deleteLabel('l1');
        expect(taskNotifier.deletedLabels, equals(['l1']));
      },
    );
  });
}
