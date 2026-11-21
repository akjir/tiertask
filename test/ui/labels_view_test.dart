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

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/presentation/app_shell_controller.dart';
import 'package:tiertask/presentation/floating_notice_controller.dart';
import 'package:tiertask/presentation/shell_models.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/ui/views/labels_view.dart';
import 'package:tiertask/ui/widgets/entity_conditions_section.dart';
import 'package:tiertask/ui/widgets/entity_note_section.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import 'test_helpers.dart';

class _ControlledLabelTaskNotifier extends FakeTaskNotifier {
  _ControlledLabelTaskNotifier(
    super.initialBoard, {
    this.addLabelCompleter,
    this.throwOnAddLabel = false,
  });

  final Completer<void>? addLabelCompleter;
  final bool throwOnAddLabel;

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
    final completer = addLabelCompleter;
    if (completer != null) {
      await completer.future;
    }
    if (throwOnAddLabel) {
      throw const FormatException('Simulated local persistence error');
    }
    await super.addLabel(
      name,
      color: color,
      id: id,
      note: note,
      isScoped: isScoped,
      links: links,
      conditions: conditions,
      currentDate: currentDate,
    );
  }
}

void main() {
  String? lastCopiedText;

  setUp(() {
    lastCopiedText = null;
    AppLogger.resetForTesting(clock: () => DateTime.utc(2026, 11, 21, 12, 0));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final arguments = call.arguments;
            if (arguments is Map<Object?, Object?>) {
              final text = arguments['text'];
              if (text is String) {
                lastCopiedText = text;
              }
            }
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    AppLogger.resetForTesting();
  });

  group('LabelsView header, empty state, and returnContext', () {
    testWidgets(
      'renders header, count 0, empty state banner, and hides Back button without returnContext',
      (tester) async {
        await pumpLeafWidget(
          tester,
          const Scaffold(body: LabelsView()),
          board: TaskBoard.empty(),
        );

        expect(find.text('Labels'), findsOneWidget);
        expect(
          find.text(
            'Contexts, scoped queues, reference links, and inherited conditions.',
          ),
          findsOneWidget,
        );
        expect(find.text('0'), findsOneWidget);
        expect(find.text('No labels created yet.'), findsOneWidget);
        expect(find.text('Back to tasks'), findsNothing);
        expect(find.text('Back to search'), findsNothing);
        expect(find.byType(UiQuickComposer), findsOneWidget);
      },
    );

    testWidgets(
      'shows Back to tasks when returnContext is from Tasks and restores full task context',
      (tester) async {
        const label = TdfLabel(id: 'lbl_work', name: 'Work', color: '#2196F3');
        final task = TaskItem(
          id: 'tsk_1',
          title: 'Write release notes',
          labelIds: const <String>['lbl_work'],
        );
        final board = TaskBoard(
          focus: <TaskItem>[task],
          labels: const <TdfLabel>[label],
        );

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LabelsView()),
          board: board,
        );

        final shell = container.read(appShellControllerProvider.notifier);
        shell.selectTier(ShellTier.ready);
        shell.selectLabelFilter('lbl_work');
        shell.expandEntity(const EntityRef(kind: EntityKind.task, id: 'tsk_1'));
        shell.openEntityInManager(
          const EntityRef(kind: EntityKind.label, id: 'lbl_work'),
          preserveReturnContext: true,
        );
        await tester.pumpAndSettle();

        expect(find.text('Back to tasks'), findsOneWidget);
        await tester.tap(find.text('Back to tasks'));
        await tester.pumpAndSettle();

        final restored = container.read(appShellControllerProvider);
        expect(restored.view, ShellView.tasks);
        expect(restored.activeTier, ShellTier.ready);
        expect(restored.activeLabelId, 'lbl_work');
        expect(
          restored.expandedEntity,
          const EntityRef(kind: EntityKind.task, id: 'tsk_1'),
        );
        expect(restored.returnContext, isNull);
      },
    );

    testWidgets(
      'shows Back to search when returnContext originated from Global Search',
      (tester) async {
        const label = TdfLabel(id: 'lbl_home', name: 'Home', color: '#4CAF50');
        final board = TaskBoard(labels: const <TdfLabel>[label]);

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LabelsView()),
          board: board,
        );

        final shell = container.read(appShellControllerProvider.notifier);
        shell.openSearch();
        shell.updateSearchQuery('groceries');
        shell.openEntityInManager(
          const EntityRef(kind: EntityKind.label, id: 'lbl_home'),
          preserveReturnContext: true,
        );
        await tester.pumpAndSettle();

        expect(find.text('Back to search'), findsOneWidget);
        await tester.tap(find.text('Back to search'));
        await tester.pumpAndSettle();

        final restored = container.read(appShellControllerProvider);
        expect(restored.view, ShellView.tasks);
        expect(restored.searchOpen, isTrue);
        expect(restored.searchQuery, 'groceries');
        expect(restored.returnContext, isNull);
      },
    );
  });

  group('LabelsView Quick-Create and validation', () {
    testWidgets(
      'quick-creates labels with rotating preset colors, auto-expands newest card, and handles duplicate/empty errors',
      (tester) async {
        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LabelsView()),
          board: TaskBoard.empty(),
        );

        final composerInput = find.descendant(
          of: find.byType(UiQuickComposer),
          matching: find.byType(TextField),
        );

        // Empty submission shows validation error without creating a label.
        await tester.tap(find.widgetWithText(UiButton, 'Add'));
        await tester.pumpAndSettle();
        expect(find.text('Please enter a label name.'), findsOneWidget);
        expect(
          container.read(taskNotifierProvider).asData?.value.labels,
          isEmpty,
        );

        // First label gets preset #2196F3 and auto-expands.
        await tester.enterText(composerInput, 'Alpha');
        await tester.tap(find.widgetWithText(UiButton, 'Add'));
        await tester.pumpAndSettle();

        var labels =
            container.read(taskNotifierProvider).asData?.value.labels ??
            const <TdfLabel>[];
        expect(labels, hasLength(1));
        expect(labels.first.name, 'Alpha');
        expect(labels.first.color, '#2196F3');
        expect(
          container.read(appShellControllerProvider).expandedEntity,
          EntityRef(kind: EntityKind.label, id: labels.first.id),
        );
        expect(
          tester.widget<TextField>(composerInput).controller?.text,
          isEmpty,
          reason: 'Quick-create input clears after successful creation',
        );
        expect(
          container.read(floatingNoticeControllerProvider)?.message,
          'Label saved.',
        );

        // Second label gets next rotating preset #4CAF50 and takes over single-expand.
        await tester.enterText(composerInput, 'Beta');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        labels =
            container.read(taskNotifierProvider).asData?.value.labels ??
            const <TdfLabel>[];
        expect(labels, hasLength(2));
        final beta = labels.firstWhere((item) => item.name == 'Beta');
        expect(beta.color, '#4CAF50');
        expect(
          container.read(appShellControllerProvider).expandedEntity,
          EntityRef(kind: EntityKind.label, id: beta.id),
        );

        // Case-insensitive duplicate keeps typed input, shows inline error, and emits danger toast.
        await tester.enterText(composerInput, 'alpha');
        await tester.tap(find.widgetWithText(UiButton, 'Add'));
        await tester.pumpAndSettle();

        expect(
          find.text('A label with this name already exists.'),
          findsOneWidget,
        );
        expect(
          tester.widget<TextField>(composerInput).controller?.text,
          'alpha',
          reason: 'Failed quick-create preserves typed input',
        );
        final notice = container.read(floatingNoticeControllerProvider);
        expect(notice?.tone, NoticeTone.danger);
        expect(notice?.message, 'A label with this name already exists.');
      },
    );

    testWidgets(
      'suspends Quick-Create cleanly during mid-flight async persistence',
      (tester) async {
        final completer = Completer<void>();
        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LabelsView()),
          taskNotifierFactory: () => _ControlledLabelTaskNotifier(
            TaskBoard.empty(),
            addLabelCompleter: completer,
          ),
        );

        final composerInput = find.descendant(
          of: find.byType(UiQuickComposer),
          matching: find.byType(TextField),
        );
        await tester.enterText(composerInput, 'InFlight');
        await tester.tap(find.widgetWithText(UiButton, 'Add'));
        await tester.pump();

        expect(
          tester.widget<UiQuickComposer>(find.byType(UiQuickComposer)).enabled,
          isFalse,
          reason: 'Quick-Create disables overlapping submits while persistence is in flight',
        );

        completer.complete();
        await tester.pumpAndSettle();

        expect(
          container.read(taskNotifierProvider).asData?.value.labels.length,
          1,
        );
        expect(
          tester.widget<UiQuickComposer>(find.byType(UiQuickComposer)).enabled,
          isTrue,
        );
      },
    );

    testWidgets(
      'preserves Quick-Create text and displays sanitized error when persistence fails',
      (tester) async {
        await pumpLeafWidget(
          tester,
          const Scaffold(body: LabelsView()),
          taskNotifierFactory: () => _ControlledLabelTaskNotifier(
            TaskBoard.empty(),
            throwOnAddLabel: true,
          ),
        );

        final composerInput = find.descendant(
          of: find.byType(UiQuickComposer),
          matching: find.byType(TextField),
        );
        await tester.enterText(composerInput, 'Transient');
        await tester.tap(find.widgetWithText(UiButton, 'Add'));
        await tester.pumpAndSettle();

        expect(
          tester.widget<TextField>(composerInput).controller?.text,
          'Transient',
          reason: 'Quick-Create text stays intact when persistence fails',
        );
        expect(
          find.textContaining('Failed to write local TDF file'),
          findsOneWidget,
        );
      },
    );
  });

  group('LabelsView uncommitted Label Draft Card', () {
    testWidgets(
      'replaces Quick-Create in place, seeds title and preset color, cancels cleanly, and commits full label',
      (tester) async {
        const office = TdfLocation(
          id: 'loc_office',
          name: 'Office',
          latitude: 52.52,
          longitude: 13.405,
          radius: 150,
        );
        const existing = TdfLabel(
          id: 'lbl_existing',
          name: 'Existing',
          color: '#2196F3',
        );
        final board = TaskBoard(
          labels: const <TdfLabel>[existing],
          locations: const <TdfLocation>[office],
        );

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LabelsView()),
          board: board,
        );

        final composerInput = find.descendant(
          of: find.byType(UiQuickComposer),
          matching: find.byType(TextField),
        );
        await tester.enterText(composerInput, 'Deep Work');
        await tester.tap(find.text('Open as draft'));
        await tester.pumpAndSettle();

        expect(find.byType(UiQuickComposer), findsNothing);
        expect(find.text('New Label (Draft)'), findsOneWidget);
        expect(
          find.text(
            'Uncommitted · saved to the TDF file only when you click Create.',
          ),
          findsOneWidget,
        );

        // Name field is seeded from Quick-Create and color is seeded with nextPresetColorHex (#4CAF50).
        final draftNameField = find.descendant(
          of: find.byKey(const ValueKey<String>('label_draft_name_field')),
          matching: find.byType(TextField),
        );
        expect(
          tester.widget<TextField>(draftNameField).controller?.text,
          'Deep Work',
        );
        expect(
          tester.widget<UiColorWheel>(find.byType(UiColorWheel)).value,
          const Color(0xFF4CAF50),
        );

        // Cancel discards draft and restores Quick-Create without mutating board.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('New Label (Draft)'), findsNothing);
        expect(find.byType(UiQuickComposer), findsOneWidget);
        expect(
          container.read(taskNotifierProvider).asData?.value.labels.length,
          1,
        );

        // Re-open draft and commit a full label with color, scope, note, link, and conditions.
        await tester.enterText(composerInput, 'Existing');
        await tester.tap(find.text('Open as draft'));
        await tester.pumpAndSettle();

        // Duplicate name shows inline validation error and keeps draft open.
        await tester.ensureVisible(find.text('Create label'));
        await tester.tap(find.text('Create label'));
        await tester.pumpAndSettle();
        expect(
          find.text('A label with this name already exists.'),
          findsOneWidget,
        );
        expect(find.text('New Label (Draft)'), findsOneWidget);

        // Fix name, pick preset #FF9100, switch to Scoped Queue, add Note, Link, and Conditions.
        await tester.enterText(draftNameField, 'Project Focus');
        await tester.tap(find.text('#FF9100'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Scoped Queue'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('label_draft_add_note')),
        );
        await tester.pumpAndSettle();
        final draftNoteField = find.descendant(
          of: find.byKey(const ValueKey<String>('label_draft_note_field')),
          matching: find.byType(TextField),
        );
        await tester.enterText(draftNoteField, 'Weekly focus context note');

        await tester.tap(
          find.byKey(const ValueKey<String>('label_draft_add_links')),
        );
        await tester.pumpAndSettle();
        final draftLinkTitle = find.descendant(
          of: find.byKey(const ValueKey<String>('label_draft_link_title')),
          matching: find.byType(TextField),
        );
        final draftLinkUri = find.descendant(
          of: find.byKey(const ValueKey<String>('label_draft_link_uri')),
          matching: find.byType(TextField),
        );
        await tester.enterText(draftLinkTitle, 'Spec');
        await tester.enterText(draftLinkUri, 'https://example.com/spec');
        await tester.tap(find.text('Add link'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('label_draft_add_conditions')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('label_draft_add_conditions')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('label_draft_cond_day_1')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('label_draft_cond_day_1')),
        );
        await tester.pumpAndSettle();

        final startTimeField = find.descendant(
          of: find.byKey(const ValueKey<String>('label_draft_cond_time_start')),
          matching: find.byType(TextField),
        );
        final endTimeField = find.descendant(
          of: find.byKey(const ValueKey<String>('label_draft_cond_time_end')),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(startTimeField);
        await tester.pumpAndSettle();
        await tester.enterText(startTimeField, '09:00');
        await tester.enterText(endTimeField, '17:00');
        await tester.ensureVisible(find.text('Add time window'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add time window'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('label_draft_cond_loc_loc_office')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('label_draft_cond_loc_loc_office')),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Create label'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create label'));
        await tester.pumpAndSettle();

        expect(find.text('New Label (Draft)'), findsNothing);
        expect(find.byType(UiQuickComposer), findsOneWidget);

        final updatedLabels =
            container.read(taskNotifierProvider).asData?.value.labels ??
            const <TdfLabel>[];
        final created = updatedLabels.firstWhere(
          (item) => item.name == 'Project Focus',
        );
        expect(created.color, '#FF9100');
        expect(created.isScoped, isTrue);
        expect(created.note, 'Weekly focus context note');
        expect(created.links, hasLength(1));
        expect(created.links.first.title, 'Spec');
        expect(created.links.first.uri, 'https://example.com/spec');
        expect(created.conditions, hasLength(3));
        expect(
          container.read(appShellControllerProvider).expandedEntity,
          EntityRef(kind: EntityKind.label, id: created.id),
        );
      },
    );
  });

  group('LabelsView expandable cards, inline editors, and live controls', () {
    testWidgets(
      'displays uncapped collapsed metadata strip and enforces single-expand accordion',
      (tester) async {
        const office = TdfLocation(
          id: 'loc_office',
          name: 'Office',
          latitude: 52.52,
          longitude: 13.405,
          radius: 150,
        );
        final alpha = TdfLabel(
          id: 'lbl_alpha',
          name: 'Alpha',
          color: '#2196F3',
          isScoped: true,
          note: 'Alpha details',
          links: const <TaskLink>[
            TaskLink(title: 'Docs', uri: 'https://example.com'),
          ],
          conditions: <TaskCondition>[
            DayTaskCondition.fromWeekdays(const <int>[DateTime.monday]),
          ],
        );
        const beta = TdfLabel(
          id: 'lbl_beta',
          name: 'Beta',
          color: '#E91E63',
          isScoped: false,
        );
        final task = TaskItem(
          id: 'tsk_1',
          title: 'Open alpha task',
          labelIds: const <String>['lbl_alpha'],
        );
        final board = TaskBoard(
          focus: <TaskItem>[task],
          labels: <TdfLabel>[alpha, beta],
          locations: const <TdfLocation>[office],
        );

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LabelsView()),
          board: board,
        );

        final alphaCard = find.byKey(
          const ValueKey<String>('label_card_lbl_alpha'),
        );
        final betaCard = find.byKey(
          const ValueKey<String>('label_card_lbl_beta'),
        );
        expect(alphaCard, findsOneWidget);
        expect(betaCard, findsOneWidget);

        // Uncapped collapsed metadata on Alpha: Scope + open count + Note + 1 link + Conditions.
        expect(
          find.descendant(of: alphaCard, matching: find.text('Scoped Queue')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: alphaCard, matching: find.text('1 open')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: alphaCard, matching: find.text('Note')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: alphaCard, matching: find.text('1 link')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: alphaCard,
            matching: find.text('Activation conditions'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: betaCard, matching: find.text('Global Context')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: betaCard, matching: find.text('0 open')),
          findsOneWidget,
        );
        // Edit Name pencil hidden while collapsed.
        expect(
          find.byKey(const ValueKey<String>('label_edit_name_lbl_alpha')),
          findsNothing,
        );

        // Tapping collapsed metadata strip expands Alpha.
        await tester.tap(
          find.descendant(of: alphaCard, matching: find.text('Scoped Queue')),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).expandedEntity,
          const EntityRef(kind: EntityKind.label, id: 'lbl_alpha'),
        );
        expect(find.text('ID: lbl_alpha'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('label_edit_name_lbl_alpha')),
          findsOneWidget,
        );
        expect(find.byType(Switch), findsNothing);

        // Expanding Beta collapses Alpha (strict single-expand).
        await tester.scrollUntilVisible(
          find.text('Beta'),
          200.0,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Beta'));
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).expandedEntity,
          const EntityRef(kind: EntityKind.label, id: 'lbl_beta'),
        );
        expect(find.text('ID: lbl_alpha'), findsNothing);
        expect(find.text('ID: lbl_beta'), findsOneWidget);

        // Tapping expanded Beta header collapses it.
        await tester.ensureVisible(find.text('Beta'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Beta'));
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).expandedEntity,
          isNull,
        );
        expect(find.text('ID: lbl_beta'), findsNothing);
      },
    );

    testWidgets(
      'supports inline name edit, live Board Scope switch, inline Color editor with UiColorWheel, Copy ID, and inline Delete confirmation',
      (tester) async {
        const alpha = TdfLabel(
          id: 'lbl_alpha',
          name: 'Alpha',
          color: '#2196F3',
          isScoped: false,
        );
        const beta = TdfLabel(
          id: 'lbl_beta',
          name: 'Beta',
          color: '#4CAF50',
          isScoped: false,
        );
        final board = TaskBoard(labels: const <TdfLabel>[alpha, beta]);

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LabelsView()),
          board: board,
        );

        await tester.tap(find.text('Alpha'));
        await tester.pumpAndSettle();

        // Copy ID copies label.id and emits labelIdCopiedNotice.
        await tester.tap(find.byTooltip('Copy'));
        await tester.pumpAndSettle();
        expect(lastCopiedText, 'lbl_alpha');
        expect(
          container.read(floatingNoticeControllerProvider)?.message,
          'Label ID copied to clipboard.',
        );

        // Inline name edit rejects duplicate, then saves valid name.
        await tester.tap(
          find.byKey(const ValueKey<String>('label_edit_name_lbl_alpha')),
        );
        await tester.pumpAndSettle();
        final nameInput = find.descendant(
          of: find.byKey(const ValueKey<String>('label_name_input_lbl_alpha')),
          matching: find.byType(TextField),
        );
        await tester.enterText(nameInput, 'Beta');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(
          find.text('A label with this name already exists.'),
          findsOneWidget,
        );

        await tester.enterText(nameInput, 'Alpha Renamed');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(
          container
              .read(taskNotifierProvider)
              .asData
              ?.value
              .findLabel('lbl_alpha')
              ?.name,
          'Alpha Renamed',
        );

        // Live Board Scope segmented control commits immediately without Save/Cancel.
        expect(find.byType(Switch), findsNothing);
        await tester.tap(find.text('Scoped Queue'));
        await tester.pumpAndSettle();
        expect(
          container
              .read(taskNotifierProvider)
              .asData
              ?.value
              .findLabel('lbl_alpha')
              ?.isScoped,
          isTrue,
        );

        // Inline Color editor embeds UiColorWheel, updates color, and clears color.
        await tester.tap(
          find.byKey(const ValueKey<String>('label_edit_color_lbl_alpha')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(UiColorWheel), findsOneWidget);
        await tester.tap(find.text('#E91E63'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(
          container
              .read(taskNotifierProvider)
              .asData
              ?.value
              .findLabel('lbl_alpha')
              ?.color,
          '#E91E63',
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('label_edit_color_lbl_alpha')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(
          container
              .read(taskNotifierProvider)
              .asData
              ?.value
              .findLabel('lbl_alpha')
              ?.color,
          isNull,
        );

        // Inline Delete confirmation: Keep cancels, Yes, delete commits without Undo or external notice.
        await tester.ensureVisible(find.byTooltip('Delete label'));
        await tester.tap(find.byTooltip('Delete label'));
        await tester.pumpAndSettle();
        expect(find.text('Delete this label?'), findsOneWidget);

        await tester.tap(find.text('Keep'));
        await tester.pumpAndSettle();
        expect(
          container
              .read(taskNotifierProvider)
              .asData
              ?.value
              .findLabel('lbl_alpha'),
          isNotNull,
        );

        await tester.tap(find.byTooltip('Delete label'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Yes, delete'));
        await tester.pumpAndSettle();
        expect(
          container
              .read(taskNotifierProvider)
              .asData
              ?.value
              .findLabel('lbl_alpha'),
          isNull,
        );
        expect(
          container.read(appShellControllerProvider).expandedEntity,
          isNull,
        );
        final deleteNotice = container.read(floatingNoticeControllerProvider);
        expect(deleteNotice?.message, 'Label deleted.');
        expect(deleteNotice?.hasUndoAction, isFalse);
      },
    );

    testWidgets(
      'supports adding, editing, copying, and clearing Note, Links, and Activation Conditions including location navigation',
      (tester) async {
        const office = TdfLocation(
          id: 'loc_office',
          name: 'Office',
          latitude: 52.52,
          longitude: 13.405,
          radius: 150,
        );
        const label = TdfLabel(
          id: 'lbl_context',
          name: 'Context',
          color: '#00BCD4',
        );
        final board = TaskBoard(
          labels: const <TdfLabel>[label],
          locations: const <TdfLocation>[office],
        );

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LabelsView()),
          board: board,
        );

        await tester.tap(find.text('Context'));
        await tester.pumpAndSettle();

        // All three optional sections start unset in the + Add chips bar.
        expect(find.text('+ Note'), findsOneWidget);
        expect(find.text('+ Links'), findsOneWidget);
        expect(find.text('+ Conditions'), findsOneWidget);

        // Add Note, copy Note (emits telemetry), and verify + Note disappears.
        AppLogger.setEnabled(true, minimumLevel: LogLevel.info);
        await tester.tap(find.text('+ Note'));
        await tester.pumpAndSettle();
        expect(find.text('+ Note'), findsNothing);
        await tester.enterText(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.hintText ==
                    'Optional note or description...',
          ),
          'Context guidance line',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('Context guidance line'), findsOneWidget);
        expect(find.text('+ Note'), findsNothing);

        await tester.tap(find.byTooltip('Copy note'));
        await tester.pumpAndSettle();
        expect(lastCopiedText, 'Context guidance line');
        expect(
          AppLogger.lines.any(
            (line) =>
                line.contains('label.note.copied') &&
                line.contains('id=lbl_context') &&
                !line.contains('Context guidance line'),
          ),
          isTrue,
          reason: 'Copying a label note must log redacted label.note.copied telemetry',
        );

        // Clear Note via inline editor footer and confirm + Note chip returns.
        final editNoteButton = find.descendant(
          of: find.byType(EntityNoteSection),
          matching: find.byTooltip('Edit'),
        );
        await tester.ensureVisible(editNoteButton);
        await tester.pumpAndSettle();
        await tester.tap(editNoteButton);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Clear'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(
          container
              .read(taskNotifierProvider)
              .asData
              ?.value
              .findLabel('lbl_context')
              ?.note,
          isNull,
        );
        expect(find.text('+ Note'), findsOneWidget);

        // Add Link via + Links chip.
        await tester.ensureVisible(find.text('+ Links'));
        await tester.tap(find.text('+ Links'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.hintText ==
                    'Link title (e.g. Documentation)',
          ),
          'Runbook',
        );
        await tester.enterText(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.hintText == 'URI (e.g. https://example.com)',
          ),
          'https://example.com/runbook',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('Runbook'), findsOneWidget);
        expect(find.text('+ Links'), findsNothing);

        // Add Conditions via + Conditions chip and navigate to Office location with preserveReturnContext: false.
        await tester.ensureVisible(find.text('+ Conditions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('+ Conditions'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('cond_loc_loc_office')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('cond_loc_loc_office')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('+ Conditions'), findsNothing);

        // Navigate to Office location with preserveReturnContext: false, then return and clear Conditions.
        await tester.ensureVisible(find.text('Office'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Office'));
        await tester.pumpAndSettle();

        final shellState = container.read(appShellControllerProvider);
        expect(shellState.view, ShellView.locations);
        expect(
          shellState.expandedEntity,
          const EntityRef(kind: EntityKind.location, id: 'loc_office'),
        );
        expect(
          shellState.returnContext,
          isNull,
          reason: 'Navigating from Labels to Locations must pass preserveReturnContext: false',
        );

        // Re-expand Context label and clear Activation Conditions.
        container
            .read(appShellControllerProvider.notifier)
            .expandEntity(
              const EntityRef(kind: EntityKind.label, id: 'lbl_context'),
            );
        await tester.pumpAndSettle();
        final editConditionsButton = find.descendant(
          of: find.byType(EntityConditionsSection),
          matching: find.byTooltip('Edit'),
        );
        await tester.ensureVisible(editConditionsButton);
        await tester.pumpAndSettle();
        await tester.tap(editConditionsButton);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Clear'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(
          container
              .read(taskNotifierProvider)
              .asData
              ?.value
              .findLabel('lbl_context')
              ?.conditions,
          isEmpty,
        );
        expect(find.text('+ Conditions'), findsOneWidget);
      },
    );

    testWidgets(
      'renders cleanly at compact 390px viewport and honors revealEntityRequest',
      (tester) async {
        final labels = <TdfLabel>[
          for (var i = 1; i <= 12; i++)
            TdfLabel(
              id: 'lbl_${i.toString().padLeft(2, '0')}',
              name: 'Label ${i.toString().padLeft(2, '0')}',
              color: '#2196F3',
            ),
        ];
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        final container = await pumpLeafWidget(
          tester,
          Scaffold(body: LabelsView(scrollController: scrollController)),
          board: TaskBoard(labels: labels),
          surfaceSize: const Size(390, 844),
          presetId: 'plum_umber',
          themeMode: ThemeMode.dark,
        );

        expect(
          tester
              .widget<UiQuickComposer>(find.byType(UiQuickComposer))
              .isCollapsibleOnCompact,
          isFalse,
        );
        expect(tester.takeException(), isNull);

        container
            .read(appShellControllerProvider.notifier)
            .expandEntity(
              const EntityRef(kind: EntityKind.label, id: 'lbl_12'),
              reveal: true,
            );
        await tester.pumpAndSettle();

        expect(
          container.read(appShellControllerProvider).revealEntityRequest,
          isNull,
          reason: 'One-shot revealEntityRequest clears once revealed',
        );
        expect(
          find.byKey(const ValueKey<String>('label_card_lbl_12')),
          findsOneWidget,
        );
      },
    );
  });
}
