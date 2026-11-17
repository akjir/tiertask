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
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/repositories/link_launcher_repository.dart';
import 'package:tiertask/services/tdf_service.dart';
import 'package:tiertask/ui/widgets/task_editor_history_section.dart';

import '../test_helpers.dart';

void main() {
  test('TaskHistoryInputValidator enforces zero-copy single-line sanitization, Unicode scalar/control/surrogate bounds, and Proleptic Gregorian local-to-UTC timestamp bounds', () async {
    final enL10n = await AppLocalizations.delegate.load(const Locale('en'));
    final deL10n = await AppLocalizations.delegate.load(const Locale('de'));

    // 1. sanitizeSingleLineText: empty/whitespace, zero-copy identity, substring trim, internal CR/LF/TAB collapse, U+00A0 & C0 retention
    expect(TaskHistoryInputValidator.sanitizeSingleLineText(''), equals(''));
    expect(
      TaskHistoryInputValidator.sanitizeSingleLineText('  \r\n\t  '),
      equals(''),
    );

    const clean = 'Left voicemail  with #support "ref \\42" {ok}';
    expect(
      identical(TaskHistoryInputValidator.sanitizeSingleLineText(clean), clean),
      isTrue,
      reason: 'Clean single-line text must return rawText with zero copy',
    );
    expect(
      TaskHistoryInputValidator.sanitizeSingleLineText(' \tHello  World\r\n '),
      equals('Hello  World'),
    );
    expect(
      TaskHistoryInputValidator.sanitizeSingleLineText(
        'Line 1\r\nLine 2\nLine 3\tTabbed\rLine 4',
      ),
      equals('Line 1 Line 2 Line 3 Tabbed Line 4'),
      reason: 'CRLF must collapse to a single 0x20 space alongside standalone CR, LF, and TAB',
    );
    expect(
      TaskHistoryInputValidator.sanitizeSingleLineText('\u00A0'),
      equals('\u00A0'),
      reason: 'Non-ASCII U+00A0 graphic space must not be stripped',
    );
    expect(
      TaskHistoryInputValidator.sanitizeSingleLineText('  \x07  '),
      equals('\x07'),
      reason: 'Disallowed C0 control characters must survive trimming so validateText rejects them as invalid rather than empty',
    );

    // 2. validateText: 0, 1, 500, 501 Unicode scalars (including 4-byte surrogate pairs), C0/DEL, unpaired surrogates
    expect(
      TaskHistoryInputValidator.validateText('', enL10n),
      equals(enL10n.historyErrorTextEmpty),
    );
    expect(
      TaskHistoryInputValidator.validateText('   ', deL10n),
      equals(deL10n.historyErrorTextEmpty),
    );
    expect(TaskHistoryInputValidator.validateText('x', enL10n), isNull);
    expect(TaskHistoryInputValidator.validateText('\u00A0', enL10n), isNull);
    expect(TaskHistoryInputValidator.validateText(clean, enL10n), isNull);

    final fiveHundredEmoji = '\u{1F4DD}' * 500;
    expect(fiveHundredEmoji.length, equals(1000));
    expect(
      TaskHistoryInputValidator.validateText(fiveHundredEmoji, enL10n),
      isNull,
      reason: '500 4-byte UTF-8 Unicode scalar values (1000 UTF-16 code units) must pass maxTdfTextLength',
    );
    expect(
      TaskHistoryInputValidator.validateText('${fiveHundredEmoji}a', enL10n),
      equals(enL10n.historyErrorTextTooLong),
    );
    expect(
      TaskHistoryInputValidator.validateText('a' * 501, deL10n),
      equals(deL10n.historyErrorTextTooLong),
    );

    for (final bad in <String>[
      '\x00',
      '\x07',
      '\x1F',
      '\x7F',
      'ok\x00bad',
      '\uD800',
      '\uDC00',
      'prefix\uD800suffix',
    ]) {
      expect(
        TaskHistoryInputValidator.validateText(bad, enL10n),
        equals(enL10n.historyErrorTextInvalid),
        reason: 'Control characters and unpaired surrogates must fail with historyErrorTextInvalid',
      );
    }
    expect(
      TaskHistoryInputValidator.validateText('\x07', deL10n),
      equals(deL10n.historyErrorTextInvalid),
    );

    // TDF round-trip of delimiter-heavy sanitized text:
    const tdfService = TdfService();
    final roundTripTask = TaskItem(
      id: 'valRnd0001',
      title: 'Validator Round-Trip',
      createdAt: DateTime.utc(2026, 11, 15, 10, 0),
      history: <TaskHistoryEntry>[
        TaskHistoryEntry(
          timestampUtc: DateTime.utc(2026, 11, 15, 10, 5, 30),
          text: clean,
        ),
      ],
    );
    final serialized = tdfService.serialize(
      TaskBoard.evaluate(
        tasks: <TaskItem>[roundTripTask],
        evaluationTime: DateTime.utc(2026, 11, 15, 10, 0),
      ),
    );
    expect(
      tdfService.parse(serialized).findTask('valRnd0001')!.history.single.text,
      equals(clean),
    );

    // 3. resolveEntryTimestampUtc: fallback, untouched preservation, local offset conversion, and 0001..9999 bounds
    const plusTwoConfig = WebDavConfig(
      timeZoneMode: AppTimeZoneMode.manual,
      manualTimeZoneOffsetMinutes: 120,
    );
    const minusTwoConfig = WebDavConfig(
      timeZoneMode: AppTimeZoneMode.manual,
      manualTimeZoneOffsetMinutes: -120,
    );
    final fallbackUtc = DateTime.utc(2026, 11, 15, 14, 22, 9, 450);

    expect(
      TaskHistoryInputValidator.resolveEntryTimestampUtc(
        configuration: plusTwoConfig,
        fallbackNowUtc: fallbackUtc,
        rawTimestamp: '   ',
      ),
      equals(DateTime.utc(2026, 11, 15, 14, 22, 9)),
      reason: 'Blank timestamp must normalize fallbackNowUtc to UTC seconds',
    );
    expect(
      TaskHistoryInputValidator.resolveEntryTimestampUtc(
        configuration: plusTwoConfig,
        fallbackNowUtc: DateTime.utc(0, 12, 31, 23, 59, 59),
        rawTimestamp: '',
      ),
      isNull,
      reason: 'Out-of-bounds fallbackNowUtc must return null',
    );

    // Untouched preserved timestamp at 0001-01-01 00:00:00 UTC in UTC-02:00 (where local wall-clock formatted year would otherwise clamp/shift):
    final minBoundUtc = DateTime.utc(1, 1, 1);
    expect(
      TaskHistoryInputValidator.resolveEntryTimestampUtc(
        configuration: minusTwoConfig,
        fallbackNowUtc: fallbackUtc,
        preservedTimestampText: '0000-12-31 22:00',
        preservedTimestampUtc: minBoundUtc,
        rawTimestamp: '  0000-12-31 22:00  ',
      ),
      equals(minBoundUtc),
      reason: 'Untouched preserved timestamp text must preserve original UTC instant verbatim',
    );

    expect(
      TaskHistoryInputValidator.resolveEntryTimestampUtc(
        configuration: plusTwoConfig,
        fallbackNowUtc: fallbackUtc,
        rawTimestamp: '2026-11-15',
      ),
      equals(DateTime.utc(2026, 11, 14, 22, 0)),
    );
    expect(
      TaskHistoryInputValidator.resolveEntryTimestampUtc(
        configuration: plusTwoConfig,
        fallbackNowUtc: fallbackUtc,
        rawTimestamp: '2026-11-15 14:30:45',
      ),
      equals(DateTime.utc(2026, 11, 15, 12, 30, 45)),
    );

    // Proleptic Gregorian local-offset boundary rejections and exact edges:
    expect(
      TaskHistoryInputValidator.resolveEntryTimestampUtc(
        configuration: plusTwoConfig,
        fallbackNowUtc: fallbackUtc,
        rawTimestamp: '0001-01-01 00:00',
      ),
      isNull,
      reason: '0001-01-01 00:00 in UTC+02:00 shifts to year 0000 UTC',
    );
    expect(
      TaskHistoryInputValidator.resolveEntryTimestampUtc(
        configuration: plusTwoConfig,
        fallbackNowUtc: fallbackUtc,
        rawTimestamp: '0001-01-01 02:00',
      ),
      equals(DateTime.utc(1, 1, 1)),
    );
    expect(
      TaskHistoryInputValidator.resolveEntryTimestampUtc(
        configuration: minusTwoConfig,
        fallbackNowUtc: fallbackUtc,
        rawTimestamp: '9999-12-31 23:00',
      ),
      isNull,
      reason: '9999-12-31 23:00 in UTC-02:00 shifts to year 10000 UTC',
    );
    expect(
      TaskHistoryInputValidator.resolveEntryTimestampUtc(
        configuration: minusTwoConfig,
        fallbackNowUtc: fallbackUtc,
        rawTimestamp: '9999-12-31 21:59:59',
      ),
      equals(DateTime.utc(9999, 12, 31, 23, 59, 59)),
    );

    const autoConfig = WebDavConfig(timeZoneMode: AppTimeZoneMode.automatic);
    const winterLocalInput = '2026-01-15 12:00:00';
    final expectedAutoWinterUtc = autoConfig.localWallClockToUtc(
      DateTime.utc(2026, 1, 15, 12),
    );
    expect(
      TaskHistoryInputValidator.resolveEntryTimestampUtc(
        configuration: autoConfig,
        fallbackNowUtc: fallbackUtc,
        rawTimestamp: winterLocalInput,
      ),
      equals(expectedAutoWinterUtc),
      reason: 'Automatic OS time zone must resolve local wall-clock input via TDF-CAL-001',
    );

    for (final malformed in <String>[
      'not-a-date',
      '2026-02-30',
      '2026-11-15 24:00',
      '2026-11-15 12:00:60',
      '2026-11-15 12:00 extra',
    ]) {
      expect(
        TaskHistoryInputValidator.resolveEntryTimestampUtc(
          configuration: plusTwoConfig,
          fallbackNowUtc: fallbackUtc,
          rawTimestamp: malformed,
        ),
        isNull,
        reason: 'Malformed timestamp "$malformed" must return null',
      );
    }
  });

  testWidgets(
    'TaskEditorHistorySection renders <= 5 rows in Column, virtualizes > 5 up to 500 rows in ListView.builder, keeps URI text passive, and supports English/German edit, cancel, clear, and date/time pickers',
    (WidgetTester tester) async {
      final fakeLauncher = FakeLinkLauncherRepository();
      const config = WebDavConfig(
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: 60,
      );
      final textController = TextEditingController();
      final timestampController = TextEditingController(
        text: '2026-11-15 14:30:45',
      );
      addTearDown(textController.dispose);
      addTearDown(timestampController.dispose);

      var addOrSaveCalls = 0;
      var cancelCalls = 0;
      var clearTimestampCalls = 0;
      int? lastEditedIndex;
      int? lastRemovedIndex;

      final fiveEntries = <TaskHistoryEntry>[
        TaskHistoryEntry(
          timestampUtc: DateTime.utc(2026, 11, 15, 9, 0),
          text: 'https://example.com/passive',
        ),
        TaskHistoryEntry(
          timestampUtc: DateTime.utc(2026, 11, 15, 9, 1, 30),
          text: 'javascript:alert(1)',
        ),
        TaskHistoryEntry(
          timestampUtc: DateTime.utc(2026, 11, 15, 9, 2),
          text: 'file:///etc/passwd',
        ),
        TaskHistoryEntry(
          timestampUtc: DateTime.utc(2026, 11, 15, 9, 3),
          text: '../../secret.tdf',
        ),
        TaskHistoryEntry(
          timestampUtc: DateTime.utc(2026, 11, 15, 9, 4),
          text: 'Fifth entry',
        ),
      ];

      await pumpLeafWidget(
        tester,
        SingleChildScrollView(
          child: TaskEditorHistorySection(
            configuration: config,
            entries: fiveEntries,
            textController: textController,
            timestampController: timestampController,
            onAddOrSaveEntry: () => addOrSaveCalls++,
            onCancelEdit: () => cancelCalls++,
            onClearTimestamp: () => clearTimestampCalls++,
            onEditEntry: (index) => lastEditedIndex = index,
            onPickDate: () {},
            onPickTime: () {},
            onRemoveEntry: (index) => lastRemovedIndex = index,
          ),
        ),
        config: config,
        linkLauncherRepository: fakeLauncher,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('task_editor_history_card')),
        findsOneWidget,
      );
      expect(find.text('History'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('editor_history_list')),
        findsNothing,
        reason: '5 or fewer entries must render in Column without ListView',
      );
      // UTC 09:00 in UTC+01:00 -> 10:00; UTC 09:01:30 -> 10:01:30
      expect(find.text('2026-11-15 10:00'), findsOneWidget);
      expect(find.text('2026-11-15 10:01:30'), findsOneWidget);

      // Tapping URI-like / path-traversal strings in SelectableText must never invoke LinkLauncherRepository:
      for (final passiveText in <String>[
        'https://example.com/passive',
        'javascript:alert(1)',
        'file:///etc/passwd',
        '../../secret.tdf',
      ]) {
        await tester.tap(find.text(passiveText));
        await tester.pump();
      }
      expect(
        fakeLauncher.launchedUris,
        isEmpty,
        reason: 'History text must remain strictly passive SelectableText',
      );

      // Clear timestamp button invokes onClearTimestamp:
      await tester.tap(
        find.byKey(const ValueKey('editor_history_timestamp_clear_button')),
      );
      await tester.pump();
      expect(clearTimestampCalls, equals(1));
      expect(timestampController.text, isEmpty);

      // Edit, remove, and Enter submit callbacks:
      await tester.tap(find.byKey(const ValueKey('editor_edit_history_2')));
      expect(lastEditedIndex, equals(2));
      await tester.tap(find.byKey(const ValueKey('editor_remove_history_4')));
      expect(lastRemovedIndex, equals(4));

      await tester.enterText(
        find.byKey(const ValueKey('editor_history_text_input')),
        'Quick note',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(addOrSaveCalls, equals(1));

      // 500 entries in German locale with editingIndex = 0 and errorMessage:
      final fiveHundredEntries = <TaskHistoryEntry>[
        for (var i = 0; i < 500; i++)
          TaskHistoryEntry(
            timestampUtc: DateTime.utc(2026, 11, 15).add(Duration(seconds: i)),
            text: 'Eintrag #$i',
          ),
      ];
      await pumpLeafWidget(
        tester,
        SingleChildScrollView(
          child: TaskEditorHistorySection(
            configuration: config,
            editingIndex: 0,
            entries: fiveHundredEntries,
            errorMessage: 'Bitte einen Verlaufstext eingeben.',
            textController: textController,
            timestampController: timestampController,
            onAddOrSaveEntry: () => addOrSaveCalls++,
            onCancelEdit: () => cancelCalls++,
            onClearTimestamp: () => clearTimestampCalls++,
            onEditEntry: (index) => lastEditedIndex = index,
            onPickDate: () {},
            onPickTime: () {},
            onRemoveEntry: (index) => lastRemovedIndex = index,
          ),
        ),
        config: config,
        locale: const Locale('de'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Verlauf'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('editor_history_list')),
        findsOneWidget,
        reason: '> 5 entries must virtualize inside ListView.builder',
      );
      expect(find.text('Eintrag #0'), findsOneWidget);
      expect(
        find.text('Eintrag #499'),
        findsNothing,
        reason: 'ListView.builder must lazily avoid building offscreen row 499',
      );
      expect(
        find.byKey(const ValueKey('editor_cancel_edit_history_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor_history_error_text')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('editor_cancel_edit_history_button')),
      );
      expect(cancelCalls, equals(1));

      // Date picker & time picker helpers (preserving :SS and clamping out-of-range fallback clocks):
      String? pickedDateResult;
      String? pickedTimeResult;
      await pumpLeafWidget(
        tester,
        Builder(
          builder: (context) => Column(
            children: <Widget>[
              ElevatedButton(
                key: const ValueKey('test_pick_date_btn'),
                onPressed: () async {
                  pickedDateResult =
                      await TaskEditorHistorySection.pickHistoryDate(
                        context: context,
                        currentText: '2026-11-15 14:30:45',
                        fallbackLocal: DateTime.utc(1, 1, 1),
                      );
                },
                child: const Text('Pick Date'),
              ),
              ElevatedButton(
                key: const ValueKey('test_pick_clamp_btn'),
                onPressed: () async {
                  pickedDateResult =
                      await TaskEditorHistorySection.pickHistoryDate(
                        context: context,
                        currentText: '',
                        fallbackLocal: DateTime.utc(9999, 12, 31),
                      );
                },
                child: const Text('Pick Clamped Date'),
              ),
              ElevatedButton(
                key: const ValueKey('test_pick_time_btn'),
                onPressed: () async {
                  pickedTimeResult =
                      await TaskEditorHistorySection.pickHistoryTime(
                        context: context,
                        currentText: '2026-11-15 14:30:45',
                        fallbackLocal: DateTime.utc(2026, 11, 15, 8, 15),
                      );
                },
                child: const Text('Pick Time'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('test_pick_date_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('16'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        pickedDateResult,
        equals('2026-11-16 14:30:45'),
        reason: 'pickHistoryDate must preserve existing HH:MM:SS suffix',
      );

      await tester.tap(find.byKey(const ValueKey('test_pick_clamp_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        pickedDateResult,
        equals('2100-12-31'),
        reason:
            'Out-of-range fallback year 9999 must clamp cleanly to 2100-12-31',
      );

      await tester.tap(find.byKey(const ValueKey('test_pick_time_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(pickedTimeResult, equals('2026-11-15 14:30'));
    },
  );
}
