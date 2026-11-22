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
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/providers/floating_notice_providers.dart';
import 'package:tiertask/providers/shell_providers.dart';
import 'package:tiertask/providers/task_schedule_helper.dart';
import 'package:tiertask/repositories/link_launcher_repository.dart';
import 'package:tiertask/ui/primitives/ui_button.dart';
import 'package:tiertask/ui/primitives/ui_field.dart';
import 'package:tiertask/ui/primitives/ui_pill.dart';
import 'package:tiertask/ui/primitives/ui_segmented_control.dart';
import 'package:tiertask/ui/tokens/ui_focus_tokens.dart';
import 'package:tiertask/ui/widgets/entity_card_chrome.dart';
import 'package:tiertask/ui/widgets/entity_conditions_section.dart';
import 'package:tiertask/ui/widgets/entity_date_time_fields.dart';
import 'package:tiertask/ui/widgets/entity_inline_name_editor.dart';
import 'package:tiertask/ui/widgets/entity_label_picker.dart';
import 'package:tiertask/ui/widgets/entity_links_section.dart';
import 'package:tiertask/ui/widgets/entity_note_section.dart';
import 'package:tiertask/ui/widgets/entity_reveal_scroll_controller.dart';

import 'test_helpers.dart';

void main() {
  group('EntityCardMetaBar', () {
    testWidgets(
      'displays monospace entity ID, status pill, copy ID, and inline delete confirmation swap',
      (tester) async {
        var copyCount = 0;
        var requestDeleteCount = 0;
        var cancelDeleteCount = 0;
        var confirmDeleteCount = 0;
        var confirmingDelete = false;

        await pumpLeafWidget(
          tester,
          Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: EntityCardMetaBar(
                    entityId: 'task-42',
                    copyIdTooltip: 'Copy task ID',
                    onCopyId: () => copyCount++,
                    deleteTooltip: 'Delete',
                    deleteConfirmMessage: 'Delete this task?',
                    isConfirmingDelete: confirmingDelete,
                    onRequestDelete: () {
                      requestDeleteCount++;
                      setState(() => confirmingDelete = true);
                    },
                    onCancelDelete: () {
                      cancelDeleteCount++;
                      setState(() => confirmingDelete = false);
                    },
                    onConfirmDelete: () => confirmDeleteCount++,
                    statusPillLabel: 'Completed · restore task to edit',
                    statusPillTone: UiPillTone.soft,
                  ),
                );
              },
            ),
          ),
        );

        expect(find.text('ID: task-42'), findsOneWidget);
        expect(find.text('Completed · restore task to edit'), findsOneWidget);
        expect(find.text('Delete this task?'), findsNothing);

        await tester.tap(find.byTooltip('Copy task ID'));
        await tester.pump();
        expect(copyCount, equals(1));

        await tester.tap(find.byTooltip('Delete'));
        await tester.pumpAndSettle();
        expect(requestDeleteCount, equals(1));
        expect(find.text('Delete this task?'), findsOneWidget);
        expect(find.text('Keep'), findsOneWidget);
        expect(find.text('Yes, delete'), findsOneWidget);

        await tester.tap(find.text('Keep'));
        await tester.pumpAndSettle();
        expect(cancelDeleteCount, equals(1));
        expect(find.text('Delete this task?'), findsNothing);

        await tester.tap(find.byTooltip('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Yes, delete'));
        await tester.pump();
        expect(confirmDeleteCount, equals(1));
      },
    );

    testWidgets(
      'wraps cleanly without overflow on compact 390px viewport in Plum Umber dark mode',
      (tester) async {
        await pumpLeafWidget(
          tester,
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12.0),
              child: EntityCardMetaBar(
                entityId: 'long-entity-identifier-123456',
                copyIdTooltip: 'Copy ID',
                onCopyId: () {},
                deleteTooltip: 'Delete',
                deleteConfirmMessage: 'Delete this task?',
                isConfirmingDelete: true,
                onRequestDelete: () {},
                onCancelDelete: () {},
                onConfirmDelete: () {},
                statusPillLabel: '12 open',
              ),
            ),
          ),
          surfaceSize: const Size(390, 844),
          presetId: 'plum_umber',
          themeMode: ThemeMode.dark,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Delete this task?'), findsOneWidget);
        expect(find.text('Keep'), findsOneWidget);
        expect(find.text('Yes, delete'), findsOneWidget);
      },
    );
  });

  group('EntityInlineEditorFooter', () {
    testWidgets(
      'shows error text, Clear, Cancel, and Save, and disables actions when busy',
      (tester) async {
        var cleared = 0;
        var cancelled = 0;
        var saved = 0;
        var busy = false;

        await pumpLeafWidget(
          tester,
          Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      EntityInlineEditorFooter(
                        errorText: 'Validation error message',
                        clearLabel: 'Clear',
                        onClear: () => cleared++,
                        onCancel: () => cancelled++,
                        onSave: () => saved++,
                        isBusy: busy,
                        saveLabel: 'Apply',
                      ),
                      TextButton(
                        onPressed: () => setState(() => busy = !busy),
                        child: const Text('Toggle busy'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );

        expect(find.text('Validation error message'), findsOneWidget);
        expect(find.text('Clear'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Apply'), findsOneWidget);

        await tester.tap(find.text('Clear'));
        await tester.tap(find.text('Cancel'));
        await tester.tap(find.text('Apply'));
        await tester.pump();
        expect(cleared, equals(1));
        expect(cancelled, equals(1));
        expect(saved, equals(1));

        await tester.tap(find.text('Toggle busy'));
        await tester.pump();
        await tester.tap(find.text('Clear'));
        await tester.tap(find.text('Cancel'));
        await tester.tap(find.text('Apply'));
        await tester.pump();
        expect(
          cleared,
          equals(1),
          reason: 'Clear must be disabled while isBusy is true',
        );
        expect(
          cancelled,
          equals(1),
          reason: 'Cancel must be disabled while isBusy is true',
        );
        expect(
          saved,
          equals(1),
          reason: 'Save must be disabled while isBusy is true',
        );

        final saveButton = tester.widget<UiButton>(
          find.widgetWithText(UiButton, 'Apply'),
        );
        expect(saveButton.isLoading, isTrue);
      },
    );
  });

  group('EntityHybridDateTimeField & EntityHybridTimeField', () {
    testWidgets(
      'merges date picker and 24-hour time picker into YYYY-MM-DD HH:MM seeding from fallbackLocalDateTime',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final changes = <String>[];

        await pumpLeafWidget(
          tester,
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: EntityHybridDateTimeField(
                controller: controller,
                label: 'Due',
                fallbackLocalDateTime: '2026-11-10 14:30',
                onChanged: changes.add,
              ),
            ),
          ),
        );

        await tester.tap(find.byIcon(Icons.calendar_today_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text('15'));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(controller.text, equals('2026-11-15 14:30'));
        expect(changes.last, equals('2026-11-15 14:30'));

        controller.text = '2026-02-31 09:45';
        await tester.tap(find.byIcon(Icons.calendar_today_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text('20'));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(
          controller.text,
          equals('2026-11-20 09:45'),
          reason: 'Invalid calendar date falls back to fallbackLocalDateTime while preserving valid HH:MM time',
        );

        await tester.tap(find.byIcon(Icons.schedule_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(controller.text, equals('2026-11-20 09:45'));
      },
    );

    testWidgets('EntityHybridTimeField formats picked time as HH:MM', (
      tester,
    ) async {
      final controller = TextEditingController(text: '08:15');
      addTearDown(controller.dispose);

      await pumpLeafWidget(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: EntityHybridTimeField(
              controller: controller,
              label: 'Start',
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.schedule_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(controller.text, equals('08:15'));
    });
  });

  group('EntityNoteSection', () {
    testWidgets(
      'read-only mode copies note to clipboard, emits floating notice, and hides edit pencil when read-only',
      (tester) async {
        String? copiedClipboardText;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                final args = call.arguments as Map<Object?, Object?>;
                copiedClipboardText = args['text'] as String?;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        var copyCallbackCount = 0;
        var startEditCount = 0;

        final container = await pumpLeafWidget(
          tester,
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: EntityNoteSection(
                note: 'Line 1\nLine 2',
                isEditing: false,
                canEdit: false,
                onStartEdit: () => startEditCount++,
                onCancelEdit: () {},
                onSave: (_) async => const ActionSucceeded(),
                onClear: () {},
                onNoteCopied: () => copyCallbackCount++,
              ),
            ),
          ),
        );

        expect(find.byType(SelectableText), findsOneWidget);
        expect(find.text('Line 1\nLine 2'), findsOneWidget);
        expect(
          find.byIcon(Icons.edit_outlined),
          findsNothing,
          reason: 'Edit pencil must be hidden when canEdit is false',
        );

        await tester.tap(find.byTooltip('Copy note'));
        await tester.pumpAndSettle();

        expect(copiedClipboardText, equals('Line 1\nLine 2'));
        expect(copyCallbackCount, equals(1));
        expect(startEditCount, equals(0));
        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Note copied to clipboard.'),
        );
      },
    );

    testWidgets(
      'inline edit mode saves, shows validation errors, and exposes Clear only when note exists',
      (tester) async {
        String? savedNote;
        var clearedCount = 0;
        var cancelCount = 0;
        var failValidation = true;

        await pumpLeafWidget(
          tester,
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: EntityNoteSection(
                note: 'Existing note',
                isEditing: true,
                canEdit: true,
                onStartEdit: () {},
                onCancelEdit: () => cancelCount++,
                onSave: (rawNote) async {
                  if (failValidation) {
                    return ActionValidationFailed(
                      message: 'Note contains unsupported control characters.',
                    );
                  }
                  savedNote = rawNote;
                  return const ActionSucceeded();
                },
                onClear: () => clearedCount++,
              ),
            ),
          ),
        );

        final field = tester.widget<UiField>(find.byType(UiField));
        expect(field.kind, equals(UiFieldKind.multiline));
        expect(field.maxLength, equals(2000));
        expect(field.autofocus, isTrue);
        expect(find.text('Clear'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Updated body\nSecond');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(
          find.text('Note contains unsupported control characters.'),
          findsOneWidget,
        );
        expect(savedNote, isNull);

        failValidation = false;
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(savedNote, equals('Updated body\nSecond'));
        expect(
          find.text('Note contains unsupported control characters.'),
          findsNothing,
        );

        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(clearedCount, equals(1));

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(cancelCount, equals(1));
      },
    );

    testWidgets(
      'keeps Save spinning during mid-flight async save and safely handles persist error and unmount',
      (tester) async {
        final saveCompleter = Completer<ActionResult>();
        var saveInvocations = 0;
        var mountedChild = true;

        await pumpLeafWidget(
          tester,
          Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                if (!mountedChild) {
                  return const SizedBox.shrink();
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    EntityNoteSection(
                      note: 'Initial',
                      isEditing: true,
                      canEdit: true,
                      onStartEdit: () {},
                      onCancelEdit: () {},
                      onSave: (_) {
                        saveInvocations++;
                        return saveCompleter.future;
                      },
                      onClear: () {},
                    ),
                    TextButton(
                      onPressed: () => setState(() => mountedChild = false),
                      child: const Text('Unmount'),
                    ),
                  ],
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Save'));
        await tester.pump();
        expect(saveInvocations, equals(1));

        final busySaveButton = tester.widget<UiButton>(
          find.widgetWithText(UiButton, 'Save'),
        );
        expect(busySaveButton.isLoading, isTrue);

        await tester.tap(find.text('Save'));
        await tester.pump();
        expect(
          saveInvocations,
          equals(1),
          reason: 'Second Save tap must be ignored while async save suspends',
        );

        saveCompleter.complete(
          const ActionPersistFailed(message: 'Failed to persist note.'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Failed to persist note.'), findsOneWidget);

        await tester.tap(find.text('Unmount'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('hides Clear button when creating a brand-new note', (
      tester,
    ) async {
      await pumpLeafWidget(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: EntityNoteSection(
              note: null,
              isEditing: true,
              canEdit: true,
              onStartEdit: () {},
              onCancelEdit: () {},
              onSave: (_) async => const ActionSucceeded(),
              onClear: () {},
            ),
          ),
        ),
      );

      expect(find.text('Clear'), findsNothing);
    });

    testWidgets(
      'resets submitting state via try/finally when EntityNoteSection onSave throws',
      (tester) async {
        var saveAttempts = 0;

        await pumpLeafWidget(
          tester,
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: EntityNoteSection(
                note: 'Initial note',
                isEditing: true,
                canEdit: true,
                onStartEdit: () {},
                onCancelEdit: () {},
                onSave: (_) async {
                  saveAttempts++;
                  if (saveAttempts == 1) {
                    throw StateError('Simulated unexpected save failure');
                  }
                  return const ActionSucceeded();
                },
                onClear: () {},
              ),
            ),
          ),
        );

        final capturedErrors = <Object>[];
        await runZonedGuarded(() async {
          await tester.tap(find.text('Save'));
          await tester.pump();
        }, (error, _) => capturedErrors.add(error));
        await tester.pump();

        expect(capturedErrors, hasLength(1));
        expect(capturedErrors.single, isA<StateError>());
        expect(saveAttempts, equals(1));
        expect(
          tester
              .widget<UiButton>(find.widgetWithText(UiButton, 'Save'))
              .isLoading,
          isFalse,
          reason: 'Throwing during EntityNoteSection save must still reset _isSubmitting in finally',
        );

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(
          saveAttempts,
          equals(2),
          reason: 'Save button must remain interactive after an exception resets _isSubmitting',
        );
      },
    );
  });

  group('EntityLinksSection', () {
    testWidgets(
      'read-only mode launches links via openExternalLinkProvider and shows danger notice on failure',
      (tester) async {
        final fakeLauncher = FakeLinkLauncherRepository();
        final container = await pumpLeafWidget(
          tester,
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: EntityLinksSection(
                links: const <TaskLink>[
                  TaskLink(title: 'Spec Docs', uri: 'https://example.com/spec'),
                ],
                isEditing: false,
                canEdit: true,
                isLabel: false,
                onStartEdit: () {},
                onCancelEdit: () {},
                onSave: (_) async => const ActionSucceeded(),
              ),
            ),
          ),
          linkLauncherRepository: fakeLauncher,
        );

        expect(find.text('Links'), findsOneWidget);
        expect(find.text('1 / 20'), findsOneWidget);
        expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);

        await tester.tap(find.text('Spec Docs'));
        await tester.pumpAndSettle();
        expect(
          fakeLauncher.launchedUris,
          equals(<String>['https://example.com/spec']),
        );
        expect(container.read(floatingNoticeProvider), isNull);

        fakeLauncher.shouldThrow = true;
        await tester.tap(find.text('Spec Docs'));
        await tester.pumpAndSettle();
        final notice = container.read(floatingNoticeProvider);
        expect(notice, isNotNull);
        expect(notice?.tone, equals(FloatingNoticeTone.danger));
        expect(notice?.message, equals('Could not open link.'));
      },
    );

    testWidgets(
      'inline edit mode validates, adds, edits, cancels row edit, reorders, removes, clears, and saves links',
      (tester) async {
        final savedSnapshots = <List<TaskLink>>[];

        await pumpLeafWidget(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: EntityLinksSection(
                links: const <TaskLink>[
                  TaskLink(title: 'Alpha', uri: 'https://alpha.example'),
                  TaskLink(title: 'Beta', uri: 'https://beta.example'),
                ],
                isEditing: true,
                canEdit: true,
                isLabel: false,
                onStartEdit: () {},
                onCancelEdit: () {},
                onSave: (links) async {
                  savedSnapshots.add(links);
                  return const ActionSucceeded();
                },
              ),
            ),
          ),
        );

        expect(find.text('2 / 20'), findsOneWidget);

        final textFields = find.byType(TextField);
        await tester.enterText(textFields.at(0), 'Bad');
        await tester.enterText(textFields.at(1), 'not-a-uri');
        await tester.tap(find.text('Add link'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Enter both a link title and a valid URI with scheme (e.g. https://...).',
          ),
          findsOneWidget,
        );

        await tester.enterText(textFields.at(0), 'Gamma');
        await tester.enterText(textFields.at(1), 'https://gamma.example');
        await tester.tap(find.text('Add link'));
        await tester.pumpAndSettle();
        expect(find.text('3 / 20'), findsOneWidget);
        expect(find.text('Gamma'), findsOneWidget);

        await tester.tap(find.byTooltip('Edit link').at(1));
        await tester.pumpAndSettle();
        expect(find.text('Update link'), findsOneWidget);
        await tester.tap(find.byTooltip('Cancel link edit'));
        await tester.pumpAndSettle();
        expect(find.text('Add link'), findsOneWidget);

        await tester.tap(find.byTooltip('Edit link').at(0));
        await tester.pumpAndSettle();
        expect(find.text('Update link'), findsOneWidget);
        await tester.enterText(textFields.at(0), 'Alpha Edited');
        await tester.tap(find.text('Update link'));
        await tester.pumpAndSettle();
        expect(find.text('Alpha Edited'), findsOneWidget);
        expect(find.text('Add link'), findsOneWidget);

        await tester.tap(find.byTooltip('Move link down').at(0));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Remove link').at(2));
        await tester.pumpAndSettle();
        expect(find.text('2 / 20'), findsOneWidget);

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(
          savedSnapshots.last,
          equals(const <TaskLink>[
            TaskLink(title: 'Beta', uri: 'https://beta.example'),
            TaskLink(title: 'Alpha Edited', uri: 'https://alpha.example'),
          ]),
        );

        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(savedSnapshots.last, isEmpty);
      },
    );
  });

  group('EntityConditionsSection', () {
    const locations = <TdfLocation>[
      TdfLocation(
        id: 'loc-home',
        name: 'Home',
        latitude: 52.52,
        longitude: 13.405,
        radius: 200.0,
      ),
      TdfLocation(
        id: 'loc-office',
        name: 'Office',
        latitude: 52.51,
        longitude: 13.38,
        radius: 150.0,
      ),
    ];

    testWidgets(
      'read-only mode navigates clickable location chips and shows suspended warning',
      (tester) async {
        String? openedLocationId;

        await pumpLeafWidget(
          tester,
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: EntityConditionsSection(
                isTask: true,
                hasConditions: true,
                isSuspended: true,
                conditionsStatusLabel: 'Currently unmet (blocked)',
                conditionsSummary: const <ConditionSummaryChip>[
                  ConditionSummaryChip(label: 'Mon, Wed', isInherited: true),
                  ConditionSummaryChip(label: 'Home', locationId: 'loc-home'),
                ],
                conditionDraft: ConditionDraft(),
                allLocations: locations,
                isEditing: false,
                canEdit: true,
                onStartEdit: () {},
                onCancelEdit: () {},
                onSave: (_) async => const ActionSucceeded(),
                onClear: () {},
                onOpenLocation: (locationId) => openedLocationId = locationId,
              ),
            ),
          ),
        );

        expect(find.text('Activation Conditions'), findsOneWidget);
        expect(
          find.text(
            'Suspended is active: evaluation of all other conditions is disabled and this task appears under Blocked.',
          ),
          findsOneWidget,
        );
        expect(find.text('Currently unmet (blocked)'), findsOneWidget);
        expect(find.text('Mon, Wed'), findsOneWidget);

        await tester.tap(find.text('Home'));
        await tester.pump();
        expect(openedLocationId, equals('loc-home'));
      },
    );

    testWidgets(
      'inline edit mode dims and blocks controls when suspended while keeping footer interactive',
      (tester) async {
        var cancelCount = 0;

        await pumpLeafWidget(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: EntityConditionsSection(
                isTask: true,
                hasConditions: true,
                isSuspended: true,
                conditionsSummary: const <ConditionSummaryChip>[],
                conditionDraft: ConditionDraft(
                  daysMode: ConditionDimensionMode.custom,
                  weekdays: const <int>[1],
                ),
                allLocations: locations,
                isEditing: true,
                canEdit: true,
                onStartEdit: () {},
                onCancelEdit: () => cancelCount++,
                onSave: (_) async => const ActionSucceeded(),
                onClear: () {},
              ),
            ),
          ),
        );

        expect(
          find.text(
            'Suspended is active: evaluation of all other conditions is disabled and this task appears under Blocked.',
          ),
          findsOneWidget,
        );

        final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
        expect(
          opacityWidgets.any(
            (widget) =>
                widget.opacity == UiFocusTokens.standard.suspendedDimmedOpacity,
          ),
          isTrue,
          reason: 'Suspended condition controls must dim to 0.45 opacity',
        );

        final ignorePointers = tester.widgetList<IgnorePointer>(
          find.byType(IgnorePointer),
        );
        expect(
          ignorePointers.any((widget) => widget.ignoring),
          isTrue,
          reason: 'Suspended condition controls must ignore pointer events',
        );

        await tester.tap(find.text('Cancel'));
        await tester.pump();
        expect(cancelCount, equals(1));
      },
    );

    testWidgets(
      'inline edit mode supports task Inherit/Any/Custom switches, global reset, weekday, time window add/remove, and location editing',
      (tester) async {
        ConditionDraft? savedDraft;
        var clearedCount = 0;

        await pumpLeafWidget(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: EntityConditionsSection(
                isTask: true,
                hasConditions: true,
                conditionsSummary: const <ConditionSummaryChip>[],
                conditionDraft: ConditionDraft(),
                allLocations: locations,
                isEditing: true,
                canEdit: true,
                onStartEdit: () {},
                onCancelEdit: () {},
                onSave: (draft) async {
                  savedDraft = draft;
                  return const ActionSucceeded();
                },
                onClear: () => clearedCount++,
              ),
            ),
          ),
        );

        expect(find.text('Any (ignore label conditions)'), findsOneWidget);
        expect(
          find.byType(UiSegmentedControl<ConditionDimensionMode>),
          findsNWidgets(3),
        );

        final customSegments = find.text('Custom condition');
        await tester.tap(customSegments.at(0));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Wed'));
        await tester.tap(find.text('Mon'));
        await tester.pumpAndSettle();

        await tester.tap(customSegments.at(1));
        await tester.pumpAndSettle();
        final timeFields = find.byType(TextField);
        await tester.enterText(timeFields.at(0), '09:00');
        await tester.enterText(timeFields.at(1), '09:00');
        await tester.tap(find.text('Add time window'));
        await tester.pumpAndSettle();
        expect(
          find.text('Enter valid 24-hour times (HH:MM).'),
          findsOneWidget,
          reason: 'Equal start and end time must fail validation',
        );

        await tester.enterText(timeFields.at(0), '09:00');
        await tester.enterText(timeFields.at(1), '17:30');
        await tester.tap(find.text('Add time window'));
        await tester.pumpAndSettle();
        expect(find.text('09:00 - 17:30'), findsOneWidget);

        await tester.enterText(timeFields.at(0), '19:00');
        await tester.enterText(timeFields.at(1), '21:00');
        await tester.tap(find.text('Add time window'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Remove time window').at(1));
        await tester.pumpAndSettle();
        expect(find.text('19:00 - 21:00'), findsNothing);

        await tester.tap(customSegments.at(2));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Office'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(
          savedDraft,
          equals(
            ConditionDraft(
              daysMode: ConditionDimensionMode.custom,
              weekdays: const <int>[1, 3],
              timeMode: ConditionDimensionMode.custom,
              timeWindows: const <TimeWindowDraft>[
                TimeWindowDraft(start: '09:00', end: '17:30'),
              ],
              locationMode: ConditionDimensionMode.custom,
              locationIds: const <String>['loc-office'],
            ),
          ),
        );

        await tester.tap(find.text('Any day'));
        await tester.tap(find.text('Any time'));
        await tester.tap(find.text('Any location'));
        await tester.pumpAndSettle();
        expect(find.text('Mon'), findsNothing);

        await tester.tap(find.text('Any (ignore label conditions)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(savedDraft?.ignoreAllLabelConditions, isTrue);
        expect(savedDraft?.daysMode, equals(ConditionDimensionMode.any));
        expect(savedDraft?.timeMode, equals(ConditionDimensionMode.any));
        expect(savedDraft?.locationMode, equals(ConditionDimensionMode.any));

        await tester.tap(find.text('Clear'));
        await tester.pump();
        expect(clearedCount, equals(1));
      },
    );

    testWidgets(
      'label mode omits task reset controls and shows empty locations hint when none exist',
      (tester) async {
        await pumpLeafWidget(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: EntityConditionsSection(
                isTask: false,
                hasConditions: false,
                conditionsSummary: const <ConditionSummaryChip>[],
                conditionDraft: ConditionDraft(
                  daysMode: ConditionDimensionMode.custom,
                  timeMode: ConditionDimensionMode.custom,
                  locationMode: ConditionDimensionMode.custom,
                ),
                allLocations: const <TdfLocation>[],
                isEditing: true,
                canEdit: true,
                onStartEdit: () {},
                onCancelEdit: () {},
                onSave: (_) async => const ActionSucceeded(),
                onClear: () {},
              ),
            ),
          ),
        );

        expect(find.text('Any (ignore label conditions)'), findsNothing);
        expect(
          find.byType(UiSegmentedControl<ConditionDimensionMode>),
          findsNothing,
        );
        expect(find.text('Mon'), findsOneWidget);
        expect(find.text('No locations created yet.'), findsOneWidget);
      },
    );
  });

  group('EntitySearchableLabelPicker', () {
    const sampleLabels = <TdfLabel>[
      TdfLabel(id: 'lbl-work', name: 'Work', isScoped: true, color: '#2196F3'),
      TdfLabel(id: 'lbl-errands', name: 'Errands', color: '#4CAF50'),
    ];
    const sampleOpenCounts = <String, int>{'lbl-work': 4, 'lbl-errands': 2};

    testWidgets(
      'renders conditional scope pills only when both scoped and global labels exist, filters rows, and blocks cross-scope duplicate create',
      (tester) async {
        String? toggledId;
        String? infoId;

        await pumpLeafWidget(
          tester,
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: EntitySearchableLabelPicker(
                allLabels: sampleLabels,
                selectedIds: const <String>{'lbl-work'},
                openCountsByLabelId: sampleOpenCounts,
                onToggleLabel: (id) => toggledId = id,
                onCreateAndAssign: (_) {},
                onOpenLabelInfo: (id) => infoId = id,
              ),
            ),
          ),
        );

        expect(find.text('All (2)'), findsOneWidget);
        expect(find.text('Scoped (1)'), findsOneWidget);
        expect(find.text('Global (1)'), findsOneWidget);

        await tester.tap(find.text('Scoped (1)'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'errands');
        await tester.pumpAndSettle();
        expect(
          find.text('Create & assign "errands"'),
          findsNothing,
          reason: 'Exact match in another scope must suppress duplicate inline creation',
        );

        await tester.enterText(find.byType(TextField), '');
        await tester.tap(find.text('Global (1)'));
        await tester.pumpAndSettle();
        expect(find.text('Errands'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('picker_opt_lbl-work')),
          findsNothing,
        );

        await tester.tap(find.text('Errands'));
        await tester.pump();
        expect(toggledId, equals('lbl-errands'));

        await tester.tap(find.byTooltip('Open and expand label in Manage'));
        await tester.pump();
        expect(infoId, equals('lbl-errands'));
      },
    );

    testWidgets(
      'omits scope pills when all labels share the same scope and supports 500-char inline create',
      (tester) async {
        String? createdName;
        final longName = 'A' * 500;

        await pumpLeafWidget(
          tester,
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: EntitySearchableLabelPicker(
                allLabels: const <TdfLabel>[
                  TdfLabel(id: 'lbl-errands', name: 'Errands'),
                ],
                selectedIds: const <String>{},
                openCountsByLabelId: const <String, int>{'lbl-errands': 2},
                showSelectedChips: false,
                autoFocusSearch: true,
                onToggleLabel: (_) {},
                onCreateAndAssign: (name) => createdName = name,
                onOpenLabelInfo: (_) {},
              ),
            ),
          ),
        );

        expect(find.text('All (1)'), findsNothing);
        expect(find.text('Scoped (0)'), findsNothing);
        expect(find.text('Global (1)'), findsNothing);

        final searchField = tester.widget<UiField>(find.byType(UiField));
        expect(searchField.maxLength, equals(500));
        expect(searchField.autofocus, isTrue);

        await tester.enterText(find.byType(TextField), longName);
        await tester.pumpAndSettle();

        final createRowFinder = find.text('Create & assign "$longName"');
        expect(createRowFinder, findsOneWidget);
        await tester.tap(createRowFinder);
        await tester.pump();
        expect(createdName, equals(longName));
      },
    );

    testWidgets(
      'enforces isCompactSheet no-autofocus rule even when autoFocusSearch is true',
      (tester) async {
        await pumpLeafWidget(
          tester,
          Scaffold(
            body: SizedBox(
              height: 420.0,
              child: EntitySearchableLabelPicker(
                allLabels: sampleLabels,
                selectedIds: const <String>{},
                openCountsByLabelId: sampleOpenCounts,
                autoFocusSearch: true,
                isCompactSheet: true,
                onToggleLabel: (_) {},
                onCreateAndAssign: (_) {},
                onOpenLabelInfo: (_) {},
              ),
            ),
          ),
          surfaceSize: const Size(390, 844),
        );

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(
          textField.autofocus,
          isFalse,
          reason: 'Compact mobile bottom sheet must never autofocus search',
        );
        expect(textField.focusNode?.hasFocus ?? false, isFalse);
      },
    );
  });

  group('EntityInlineNameEditor', () {
    testWidgets(
      'adapts layout between desktop horizontal row and compact stacked column, validates, submits via Enter, cancels via Escape, and guards async submit',
      (tester) async {
        final savedValues = <String>[];
        var cancelCount = 0;
        Completer<ActionResult>? pendingSave;
        var showEditor = true;
        late StateSetter rebuildHost;

        await pumpLeafWidget(
          tester,
          Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuildHost = setState;
                if (!showEditor) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: EntityInlineNameEditor(
                    initialValue: 'Original Name',
                    hintText: 'Entity name',
                    semanticsLabel: 'Edit entity name',
                    inputKey: const ValueKey<String>('inline_name_input'),
                    saveKey: const ValueKey<String>('inline_name_save'),
                    cancelKey: const ValueKey<String>('inline_name_cancel'),
                    maxLength: 50,
                    validator: (value) =>
                        value.trim().isEmpty ? 'Name required.' : null,
                    onSave: (value) {
                      savedValues.add(value);
                      if (pendingSave case final gate?) {
                        return gate.future;
                      }
                      if (value.trim() == 'Duplicate') {
                        return Future<ActionResult>.value(
                          ActionValidationFailed(message: 'Already exists.'),
                        );
                      }
                      return Future<ActionResult>.value(
                        const ActionSucceeded(),
                      );
                    },
                    onCancel: () => cancelCount++,
                  ),
                );
              },
            ),
          ),
          surfaceSize: const Size(1280, 800),
        );

        final inputFinder = find.byKey(
          const ValueKey<String>('inline_name_input'),
        );
        final saveFinder = find.byKey(
          const ValueKey<String>('inline_name_save'),
        );
        final cancelFinder = find.byKey(
          const ValueKey<String>('inline_name_cancel'),
        );
        expect(inputFinder, findsOneWidget);
        expect(saveFinder, findsOneWidget);
        expect(cancelFinder, findsOneWidget);

        // Desktop (> 720): input and save button sit side by side horizontally.
        expect(
          tester.getTopLeft(saveFinder).dx,
          greaterThan(tester.getTopLeft(inputFinder).dx),
          reason: 'Desktop inline name editor must place actions beside input',
        );
        expect(
          (tester.getTopLeft(saveFinder).dy - tester.getTopLeft(inputFinder).dy)
              .abs(),
          lessThan(12.0),
        );

        // Client-side validator blocks blank save without calling onSave.
        await tester.enterText(
          find.descendant(of: inputFinder, matching: find.byType(TextField)),
          '   ',
        );
        await tester.tap(saveFinder);
        await tester.pump();
        expect(find.text('Name required.'), findsOneWidget);
        expect(savedValues, isEmpty);

        // Typing clears local error; ActionValidationFailed displays server/domain error inline.
        await tester.enterText(
          find.descendant(of: inputFinder, matching: find.byType(TextField)),
          'Duplicate',
        );
        await tester.pump();
        expect(find.text('Name required.'), findsNothing);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(savedValues, equals(<String>['Duplicate']));
        expect(find.text('Already exists.'), findsOneWidget);

        // In-flight submit disables double-submit and recovers cleanly via try/finally.
        pendingSave = Completer<ActionResult>();
        await tester.enterText(
          find.descendant(of: inputFinder, matching: find.byType(TextField)),
          'Updated Name',
        );
        await tester.pump();
        await tester.tap(saveFinder);
        await tester.pump();
        await tester.tap(saveFinder);
        await tester.pump();
        expect(
          savedValues.length,
          equals(2),
          reason: 'Double tap while submit is in flight must be ignored',
        );
        expect(tester.widget<UiButton>(saveFinder).isLoading, isTrue);

        pendingSave.complete(const ActionSucceeded());
        pendingSave = null;
        await tester.pumpAndSettle();
        expect(tester.widget<UiButton>(saveFinder).isLoading, isFalse);

        // Escape cancels inline name edit cleanly when input has focus.
        await tester.tap(
          find.descendant(of: inputFinder, matching: find.byType(TextField)),
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(cancelCount, equals(1));

        // Compact (<= 720): actions stack below the input field.
        tester.view.physicalSize = const Size(390, 800);
        await tester.binding.setSurfaceSize(const Size(390, 800));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(saveFinder).dy,
          greaterThan(tester.getBottomLeft(inputFinder).dy),
          reason: 'Compact inline name editor must stack actions below input',
        );

        // Unmounting disposes internal controller/focusNode post-frame with zero exceptions.
        rebuildHost(() => showEditor = false);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('EntityLinksEditorBody & EntityConditionsEditorBody', () {
    testWidgets(
      'EntityLinksEditorBody renders standalone links editor for draft reuse with custom key prefix',
      (tester) async {
        final titleController = TextEditingController();
        final uriController = TextEditingController();
        addTearDown(() {
          titleController.dispose();
          uriController.dispose();
        });
        var committed = 0;
        var reordered = false;

        await pumpLeafWidget(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: EntityLinksEditorBody(
                links: const <TaskLink>[
                  TaskLink(title: 'First', uri: 'https://first.example'),
                  TaskLink(title: 'Second', uri: 'https://second.example'),
                ],
                editingIndex: null,
                titleController: titleController,
                uriController: uriController,
                itemKeyPrefix: 'draft_link',
                onReorder: (oldIndex, newIndex) => reordered = true,
                onStartRowEdit: (link, index) {},
                onDeleteRow: (link, index) {},
                onCommitLink: () => committed++,
                onCancelRowEdit: () {},
              ),
            ),
          ),
        );

        expect(
          find.byKey(
            const ValueKey<String>('draft_link_0_https://first.example'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Move link down').first);
        await tester.pump();
        expect(reordered, isTrue);

        await tester.tap(find.text('Add link'));
        await tester.pump();
        expect(committed, equals(1));
      },
    );

    testWidgets(
      'EntityConditionsEditorBody supports standalone Task and Label modes with suspended dimming',
      (tester) async {
        final startController = TextEditingController();
        final endController = TextEditingController();
        addTearDown(() {
          startController.dispose();
          endController.dispose();
        });
        const locations = <TdfLocation>[
          TdfLocation(
            id: 'loc-1',
            name: 'Home',
            latitude: 52.52,
            longitude: 13.405,
            radius: 100.0,
          ),
        ];
        final toggledDays = <int>[];

        await pumpLeafWidget(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: EntityConditionsEditorBody(
                isTask: false,
                draft: ConditionDraft(
                  daysMode: ConditionDimensionMode.custom,
                  timeMode: ConditionDimensionMode.custom,
                  locationMode: ConditionDimensionMode.custom,
                ),
                allLocations: locations,
                timeStartController: startController,
                timeEndController: endController,
                onToggleWeekday: toggledDays.add,
                onAddTimeWindow: () {},
                onRemoveTimeWindow: (window, index) {},
                onToggleLocation: (_) {},
              ),
            ),
          ),
        );

        expect(
          find.byType(UiSegmentedControl<ConditionDimensionMode>),
          findsNothing,
        );
        await tester.tap(find.text('Tue'));
        await tester.pump();
        expect(toggledDays, equals(<int>[DateTime.tuesday]));
      },
    );
  });

  group('EntityRevealScrollMixin', () {
    testWidgets(
      'pre-scrolls offscreen lazy sliver cards, clears reveal request, scrolls to top on draft open, and defers controller disposal on swap',
      (tester) async {
        final entityIds = List<String>.generate(40, (index) => 'item_$index');
        final externalController = ScrollController();
        addTearDown(externalController.dispose);
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  height: 300.0,
                  child: _TestRevealScrollList(entityIds: entityIds),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('item_35'), findsNothing);

        container
            .read(shellProvider.notifier)
            .openEntityInManager(
              const EntityRef(kind: EntityKind.label, id: 'item_35'),
              preserveReturnContext: false,
            );
        await tester.pumpAndSettle();

        expect(
          find.text('item_35'),
          findsOneWidget,
          reason: 'Bounded offscreen reveal must scroll lazy sliver item_35 into view',
        );
        expect(
          container.read(shellProvider).revealEntityRequest,
          isNull,
          reason: 'Reveal request must be cleared after item_35 materializes',
        );

        // Swap from owned scroll controller to external controller mid-flight.
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  height: 300.0,
                  child: _TestRevealScrollList(
                    entityIds: entityIds.sublist(0, 10),
                    scrollController: externalController,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        externalController.jumpTo(externalController.position.maxScrollExtent);
        await tester.pump();
        expect(externalController.offset, greaterThan(0.0));

        container.read(shellProvider.notifier).openDraft(EntityDraftKind.label);
        await tester.pumpAndSettle();
        expect(
          externalController.offset,
          equals(0.0),
          reason: 'Opening matching draft kind must animate scroll controller back to top',
        );
      },
    );
  });
}

class _TestRevealScrollList extends ConsumerStatefulWidget {
  const _TestRevealScrollList({required this.entityIds, this.scrollController});

  final List<String> entityIds;
  final ScrollController? scrollController;

  @override
  ConsumerState<_TestRevealScrollList> createState() =>
      _TestRevealScrollListState();
}

class _TestRevealScrollListState extends ConsumerState<_TestRevealScrollList>
    with EntityRevealScrollMixin<_TestRevealScrollList> {
  @override
  ScrollController? get externalScrollController => widget.scrollController;

  @override
  EntityDraftKind get revealDraftKind => EntityDraftKind.label;

  @override
  EntityKind get revealEntityKind => EntityKind.label;

  @override
  void initState() {
    super.initState();
    initRevealScroll();
  }

  @override
  void didUpdateWidget(covariant _TestRevealScrollList oldWidget) {
    super.didUpdateWidget(oldWidget);
    handleScrollControllerSwap(oldWidget.scrollController);
  }

  @override
  void dispose() {
    disposeRevealScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    registerRevealShellListeners();
    pruneOwnedCardKeys(widget.entityIds);
    return CustomScrollView(
      controller: effectiveScrollController,
      slivers: <Widget>[
        SliverList.builder(
          itemCount: widget.entityIds.length,
          itemBuilder: (context, index) {
            final id = widget.entityIds[index];
            return SizedBox(
              key: resolveRevealCardKey(id),
              height: 84.0,
              child: Text(id),
            );
          },
        ),
      ],
    );
  }

  @override
  List<String> collectVisibleEntityIds() => widget.entityIds;
}
