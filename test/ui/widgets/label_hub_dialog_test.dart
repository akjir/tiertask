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

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/link_launcher_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/ui/widgets/label_hub_dialog.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'LabelHubDialog renders empty-state hint, fallback vs custom color badge, and scoped vs regular badge in English and German',
    (WidgetTester tester) async {
      const emptyLabel = TdfLabel(id: 'empLblOkD2', name: 'Minimal Label');
      const scopedCustomLabel = TdfLabel(
        id: 'scpLblOkD2',
        name: 'Scoped Engineering',
        color: '#E91E63',
        isScoped: true,
      );
      final board = TaskBoard.empty().copyWith(
        labels: const [emptyLabel, scopedCustomLabel],
      );

      await pumpLeafWidget(
        tester,
        const LabelHubDialog(labelId: 'empLblOkD2'),
        board: board,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('label_hub_dialog')),
        findsOneWidget,
        reason:
            'LabelHubDialog root AlertDialog must carry label_hub_dialog key',
      );
      expect(find.text('Label Context'), findsOneWidget);
      expect(find.text('Minimal Label'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('label_hub_color_badge')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('label_hub_scoped_badge')),
        findsNothing,
        reason: 'Regular label must omit the scoped badge',
      );
      expect(
        find.byKey(const ValueKey('label_hub_empty_hint')),
        findsOneWidget,
        reason: 'Empty metadata label must render label_hub_empty_hint',
      );
      expect(
        find.text(
          'No note, links, or activation conditions configured for this label.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('label_hub_note_section')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('label_hub_links_section')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('label_hub_conditions_section')),
        findsNothing,
      );

      // Mount scoped label with custom hex color in German locale.
      await pumpLeafWidget(
        tester,
        const LabelHubDialog(labelId: 'scpLblOkD2'),
        board: board,
        locale: const Locale('de'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Label-Kontext'), findsOneWidget);
      expect(find.text('Scoped Engineering'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('label_hub_scoped_badge')),
        findsOneWidget,
        reason: 'Scoped label must render label_hub_scoped_badge',
      );
      expect(
        find.text(
          'Für dieses Label sind keine Notiz, Links oder Aktivierungsbedingungen hinterlegt.',
        ),
        findsOneWidget,
      );
      final badgeWidget = tester.widget<Container>(
        find.byKey(const ValueKey('label_hub_color_badge')),
      );
      final decoration = badgeWidget.decoration;
      expect(decoration, isA<BoxDecoration>());
      if (decoration is BoxDecoration) {
        expect(decoration.color, equals(const Color(0xFFE91E63)));
      }
    },
  );

  testWidgets(
    'LabelHubDialog copies multi-line note, launches links via row and button taps, formats all condition branches, and enforces AppLogger privacy gating',
    (WidgetTester tester) async {
      String? copiedClipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            final arguments = methodCall.arguments;
            if (arguments is Map<Object?, Object?>) {
              final text = arguments['text'];
              if (text is String) {
                copiedClipboardText = text;
              }
            }
          }
          return null;
        },
      );
      AppLogger.clear();
      AppLogger.setEnabled(false, persistToDisk: false);
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        AppLogger.setEnabled(false, persistToDisk: false);
        AppLogger.clear();
      });

      const office = TdfLocation(
        id: 'locOffc001',
        name: 'Berlin Office',
        latitude: 52.52,
        longitude: 13.405,
        radius: 150,
      );
      final richLabel = TdfLabel(
        id: 'rchLblOkD2',
        name: 'PrivateOpsName',
        color: '#009688',
        isScoped: true,
        note: 'Line 1 SecretNote\nLine 2 Escalation',
        links: const <TaskLink>[
          TaskLink(title: 'SecretDashboard', uri: 'https://ops.example.com/1'),
          TaskLink(title: 'SecretRunbook', uri: 'mailto:oncall@example.com'),
        ],
        conditions: <TaskCondition>[
          DayTaskCondition.fromWeekdays(const <int>[1, 3, 5]),
          const TimeWindowTaskCondition(
            startMinutes: 540,
            endMinutes: 1020,
            startToken: '09:00',
            endToken: '17:00',
          ),
          LocationTaskCondition.fromIds(const <String>[
            'locOffc001',
            'locMissing9',
          ]),
        ],
      );
      final board = TaskBoard.empty().copyWith(
        labels: [richLabel],
        locations: const [office],
      );
      final fakeLauncher = FakeLinkLauncherRepository();

      // Open via showLabelHubDialog while diagnostics are disabled -> zero log lines!
      await pumpLeafWidget(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            key: const ValueKey('open_hub_btn'),
            onPressed: () => showLabelHubDialog(context, labelId: 'rchLblOkD2'),
            child: const Text('Open Hub'),
          ),
        ),
        board: board,
        linkLauncherRepository: fakeLauncher,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open_hub_btn')));
      await tester.pumpAndSettle();
      expect(
        AppLogger.lines,
        isEmpty,
        reason: 'Disabled AppLogger must emit zero lines when opening LabelHubDialog',
      );

      expect(find.byKey(const ValueKey('label_hub_empty_hint')), findsNothing);
      expect(
        find.byKey(const ValueKey('label_hub_note_section')),
        findsOneWidget,
      );
      final noteWidget = tester.widget<SelectableText>(
        find.byKey(const ValueKey('label_hub_note_text')),
      );
      expect(noteWidget.data, equals('Line 1 SecretNote\nLine 2 Escalation'));

      // Enable logging and copy note -> logs id & length without raw note text!
      AppLogger.setEnabled(
        true,
        persistToDisk: false,
        minimumLevel: LogLevel.info,
      );
      AppLogger.clear();

      await tester.tap(
        find.byKey(const ValueKey('label_hub_copy_note_button')),
      );
      await tester.pumpAndSettle();

      expect(
        copiedClipboardText,
        equals('Line 1 SecretNote\nLine 2 Escalation'),
      );
      expect(find.text('Note copied to clipboard.'), findsOneWidget);
      expect(AppLogger.fullLogText, contains('label.note.copied'));
      expect(AppLogger.fullLogText, contains('id=rchLblOkD2'));
      expect(AppLogger.fullLogText, isNot(contains('SecretNote')));

      // Verify links launch via row tap (index 0) and trailing open button tap (index 1), plus LinkLaunchException SnackBar.
      await tester.tap(find.byKey(const ValueKey('label_hub_link_item_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('label_hub_open_link_1')));
      await tester.pumpAndSettle();
      expect(
        fakeLauncher.launchedUris,
        equals(const <String>[
          'https://ops.example.com/1',
          'mailto:oncall@example.com',
        ]),
      );

      fakeLauncher.shouldThrow = true;
      await tester.tap(find.byKey(const ValueKey('label_hub_open_link_0')));
      await tester.pumpAndSettle();
      expect(find.text('Could not open link.'), findsOneWidget);

      // Verify active condition summaries (day, time, resolved + unresolved location).
      expect(
        find.byKey(const ValueKey('label_hub_conditions_section')),
        findsOneWidget,
      );
      expect(find.text('Mon, Wed, Fri'), findsOneWidget);
      expect(find.text('09:00 - 17:00'), findsOneWidget);
      expect(find.text('Berlin Office, locMissing9'), findsOneWidget);

      // Close via Close button, then reopen with logging enabled to verify ui.label_hub.open privacy.
      await tester.tap(find.byKey(const ValueKey('label_hub_close_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('label_hub_dialog')), findsNothing);

      AppLogger.clear();
      await tester.tap(find.byKey(const ValueKey('open_hub_btn')));
      await tester.pumpAndSettle();
      expect(AppLogger.fullLogText, contains('ui.label_hub.open'));
      expect(AppLogger.fullLogText, contains('id=rchLblOkD2'));
      expect(AppLogger.fullLogText, isNot(contains('PrivateOpsName')));
      expect(AppLogger.fullLogText, isNot(contains('SecretDashboard')));

      // Exhaustively verify shared formatConditionSummary across all TaskCondition sealed variants in English and German.
      final enLoc = lookupAppLocalizations(const Locale('en'));
      final deLoc = lookupAppLocalizations(const Locale('de'));
      expect(
        formatConditionSummary(
          DayTaskCondition.fromWeekdays(const <int>[1, 2, 3, 4, 5, 6, 7]),
          const [office],
          deLoc,
        ),
        equals('Mo, Di, Mi, Do, Fr, Sa, So'),
      );
      expect(
        formatConditionSummary(const GlobalResetTaskCondition(), const [
          office,
        ], enLoc),
        equals(enLoc.conditionGlobalAnyLabel),
      );
      expect(
        formatConditionSummary(
          const GroupResetTaskCondition(targetGroup: ConditionGroup.day),
          const [office],
          enLoc,
        ),
        equals(enLoc.conditionDayAnyLabel),
      );
      expect(
        formatConditionSummary(
          const GroupResetTaskCondition(targetGroup: ConditionGroup.time),
          const [office],
          enLoc,
        ),
        equals(enLoc.conditionTimeAnyLabel),
      );
      expect(
        formatConditionSummary(
          const GroupResetTaskCondition(targetGroup: ConditionGroup.location),
          const [office],
          enLoc,
        ),
        equals(enLoc.conditionLocationAnyLabel),
      );
      final legacyCoord = LocationTaskCondition.tryParse(
        '48.137',
        '11.576',
        '200',
      );
      expect(legacyCoord, isNotNull);
      if (legacyCoord != null) {
        expect(
          formatConditionSummary(legacyCoord, const [office], enLoc),
          equals('48.137, 11.576 (200m)'),
        );
      }
    },
  );

  testWidgets(
    'LabelHubDialog updates live after EditLabelScreen save and safely auto-dismisses on external label deletion both when current and when stacked under EditLabelScreen',
    (WidgetTester tester) async {
      const initialLabel = TdfLabel(id: 'livLblOkD2', name: 'Initial Hub Name');
      const currentRouteLabel = TdfLabel(
        id: 'curLblOkD2',
        name: 'Current Route Label',
      );
      final container = await pumpLeafWidget(
        tester,
        Builder(
          builder: (context) => Column(
            children: [
              ElevatedButton(
                key: const ValueKey('launch_hub'),
                onPressed: () =>
                    showLabelHubDialog(context, labelId: 'livLblOkD2'),
                child: const Text('Launch'),
              ),
              ElevatedButton(
                key: const ValueKey('launch_current_hub'),
                onPressed: () =>
                    showLabelHubDialog(context, labelId: 'curLblOkD2'),
                child: const Text('Launch Current'),
              ),
            ],
          ),
        ),
        board: TaskBoard.empty().copyWith(
          labels: const [initialLabel, currentRouteLabel],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('launch_hub')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('label_hub_empty_hint')),
        findsOneWidget,
      );

      // Tap Edit -> EditLabelScreen opens -> update name, scoped, note, and add a link -> Save -> LabelHubDialog reflects live state!
      await tester.tap(find.byKey(const ValueKey('label_hub_edit_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit_label_screen')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('task_editor_title_input')),
        'Live Updated Name',
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_note_input')),
        'Fresh Hub Note',
      );
      await tester.tap(
        find.byKey(const ValueKey('label_editor_scoped_switch')),
      );
      await tester.pumpAndSettle();

      final titleInput = find.byKey(const ValueKey('editor_link_title_input'));
      final uriInput = find.byKey(const ValueKey('editor_link_uri_input'));
      await tester.ensureVisible(titleInput);
      await tester.enterText(titleInput, 'Architecture');
      await tester.enterText(uriInput, 'https://example.com/arch');
      await tester.pump();

      final saveBtn = find.byKey(const ValueKey('task_editor_save_button'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Back in LabelHubDialog: verify live updates!
      expect(find.byKey(const ValueKey('label_hub_dialog')), findsOneWidget);
      expect(find.text('Live Updated Name'), findsOneWidget);
      expect(find.text('Fresh Hub Note'), findsOneWidget);
      expect(find.text('Architecture'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('label_hub_scoped_badge')),
        findsOneWidget,
      );

      // Tap Edit a second time: EditLabelScreen receives the latest updated snapshot, AND while EditLabelScreen is stacked above LabelHubDialog, delete the label externally!
      await tester.tap(find.byKey(const ValueKey('label_hub_edit_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit_label_screen')), findsOneWidget);
      expect(find.text('Live Updated Name'), findsWidgets);

      await container
          .read(taskNotifierProvider.notifier)
          .deleteLabel('livLblOkD2');
      await tester.pumpAndSettle();

      // EditLabelScreen must STILL be the active current route (not accidentally popped!), while LabelHubDialog beneath it was safely removed via removeRoute!
      expect(
        find.byKey(const ValueKey('edit_label_screen')),
        findsOneWidget,
        reason: 'Removing non-current LabelHubDialog must not pop stacked EditLabelScreen',
      );
      await tester.tap(find.byKey(const ValueKey('task_editor_cancel_button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('label_hub_dialog')),
        findsNothing,
        reason: 'LabelHubDialog must already be removed after external label deletion',
      );

      // Open LabelHubDialog for curLblOkD2 as current route, then delete label -> auto-pops cleanly!
      await tester.tap(find.byKey(const ValueKey('launch_current_hub')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('label_hub_dialog')), findsOneWidget);

      await container
          .read(taskNotifierProvider.notifier)
          .deleteLabel('curLblOkD2');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('label_hub_dialog')),
        findsNothing,
        reason:
            'Current LabelHubDialog must auto-pop when its label is deleted',
      );
    },
  );
}
