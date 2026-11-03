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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/ui/widgets/app_logo.dart';
import 'package:tiertask/ui/widgets/workspace_dialog.dart';

void main() {
  testWidgets(
    'Drawer displays active workspace card between Dividers beneath TierTask and opens WorkspaceDialog to create, switch, rename, and delete workspaces without data loss',
    (WidgetTester tester) async {
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            clockProvider.overrideWithValue(
              () => DateTime.utc(2026, 11, 3, 12, 0),
            ),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('add_task_fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('quick_add_input')),
        'Primary Workspace Task',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        find.text('Primary Workspace Task'),
        findsOneWidget,
        reason: 'Task added in default Tasks workspace must be visible',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      final drawerFinder = find.byType(Drawer);
      final logoFinder = find.descendant(
        of: drawerFinder,
        matching: find.byType(AppLogo),
      );
      final titleFinder = find.descendant(
        of: drawerFinder,
        matching: find.text('TierTask'),
      );
      final switcherFinder = find.byKey(
        const ValueKey('drawer_workspace_switcher'),
      );
      final labelsHeaderFinder = find.descendant(
        of: drawerFinder,
        matching: find.text('Labels'),
      );
      final dividersInDrawer = find.descendant(
        of: drawerFinder,
        matching: find.byType(Divider),
      );

      expect(
        switcherFinder,
        findsOneWidget,
        reason: 'Navigation drawer must render DrawerWorkspaceCard',
      );
      expect(
        dividersInDrawer,
        findsNWidgets(3),
        reason: 'Navigation drawer must render a Divider above and below DrawerWorkspaceCard plus one before footer actions',
      );
      expect(
        find.descendant(of: switcherFinder, matching: find.text('Tasks')),
        findsOneWidget,
        reason: 'DrawerWorkspaceCard must display active workspace name Tasks',
      );
      expect(
        find.descendant(of: switcherFinder, matching: find.text('tasks.tdf')),
        findsOneWidget,
        reason: 'DrawerWorkspaceCard must display active .tdf file tasks.tdf',
      );
      expect(
        find.descendant(
          of: switcherFinder,
          matching: find.byIcon(Icons.unfold_more_rounded),
        ),
        findsOneWidget,
        reason: 'DrawerWorkspaceCard must display unfold_more_rounded icon',
      );

      final logoRect = tester.getRect(logoFinder);
      final titleRect = tester.getRect(titleFinder);
      final firstDividerRect = tester.getRect(dividersInDrawer.at(0));
      final switcherRect = tester.getRect(switcherFinder);
      final secondDividerRect = tester.getRect(dividersInDrawer.at(1));
      final labelsRect = tester.getRect(labelsHeaderFinder);

      expect(
        logoRect.right <= titleRect.left,
        isTrue,
        reason: 'AppLogo must remain to the left of TierTask',
      );
      expect(
        firstDividerRect.top >= titleRect.bottom &&
            firstDividerRect.bottom <= switcherRect.top,
        isTrue,
        reason:
            'First Divider must sit between TierTask and DrawerWorkspaceCard',
      );
      expect(
        secondDividerRect.top >= switcherRect.bottom &&
            secondDividerRect.bottom <= labelsRect.top,
        isTrue,
        reason:
            'Second Divider must sit between DrawerWorkspaceCard and Labels',
      );

      await tester.tap(switcherFinder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workspace_dialog')),
        findsOneWidget,
        reason: 'Clicking DrawerWorkspaceCard must open WorkspaceDialog',
      );
      expect(find.text('Workspaces'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workspace_tile_tasks')),
        findsOneWidget,
        reason: 'WorkspaceDialog must list the Tasks workspace',
      );
      expect(
        find.text('Active'),
        findsOneWidget,
        reason: 'Active workspace must display the Active badge',
      );

      final singleDeleteButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('workspace_delete_button_tasks')),
      );
      expect(
        singleDeleteButton.onPressed,
        isNull,
        reason: 'Delete button must be disabled when only one workspace exists',
      );

      await tester.enterText(
        find.byKey(const ValueKey('workspace_create_input')),
        'Arbeit',
      );
      await tester.pump();

      expect(
        find.text('TDF file: arbeit.tdf'),
        findsOneWidget,
        reason: 'Typing a workspace name must preview the derived .tdf file',
      );

      await tester.tap(
        find.byKey(const ValueKey('workspace_create_submit_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workspace_dialog')),
        findsNothing,
        reason: 'Creating and activating a workspace must close the dialog',
      );
      expect(
        find.text('Primary Workspace Task'),
        findsNothing,
        reason: 'Switching to new Arbeit workspace must unload Tasks board from memory',
      );

      await tester.tap(find.byKey(const ValueKey('add_task_fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('quick_add_input')),
        'Work Sprint Task',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        find.text('Work Sprint Task'),
        findsOneWidget,
        reason: 'Task added in Arbeit workspace must appear on the board',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: switcherFinder, matching: find.text('Arbeit')),
        findsOneWidget,
        reason: 'DrawerWorkspaceCard must now display Arbeit',
      );
      expect(
        find.descendant(of: switcherFinder, matching: find.text('arbeit.tdf')),
        findsOneWidget,
        reason: 'DrawerWorkspaceCard must now display arbeit.tdf',
      );

      await tester.tap(switcherFinder);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('workspace_create_input')),
        'Tasks',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('workspace_create_submit_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workspace_error_banner')),
        findsOneWidget,
        reason: 'Duplicate workspace name must display the error banner',
      );
      expect(
        find.text('A workspace with this name already exists.'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('workspace_rename_button_arbeit')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('workspace_rename_input_arbeit')),
        'Kunde Nord',
      );
      await tester.tap(
        find.byKey(const ValueKey('workspace_rename_save_button_arbeit')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Kunde Nord'),
        findsOneWidget,
        reason: 'Inline rename must update workspace name to Kunde Nord',
      );

      await tester.tap(find.byKey(const ValueKey('workspace_select_tasks')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workspace_dialog')),
        findsNothing,
        reason: 'Selecting Tasks workspace must close the dialog',
      );
      expect(
        find.text('Primary Workspace Task'),
        findsOneWidget,
        reason: 'Switching back to Tasks must restore Primary Workspace Task',
      );
      expect(
        find.text('Work Sprint Task'),
        findsNothing,
        reason: 'Switching back to Tasks must unload Kunde Nord tasks',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(switcherFinder);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('workspace_delete_button_arbeit')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workspace_delete_confirm_bar_arbeit')),
        findsOneWidget,
        reason: 'Tapping delete must show inline confirmation bar',
      );

      await tester.tap(
        find.byKey(const ValueKey('workspace_cancel_delete_button_arbeit')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workspace_delete_confirm_bar_arbeit')),
        findsNothing,
        reason: 'Cancelling delete must hide inline confirmation bar',
      );

      await tester.tap(
        find.byKey(const ValueKey('workspace_delete_button_arbeit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace_confirm_delete_button_arbeit')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workspace_tile_arbeit')),
        findsNothing,
        reason: 'Confirming delete must remove Kunde Nord from the dialog',
      );
      expect(find.byType(DrawerWorkspaceCard), findsNothing);
    },
  );

  testWidgets(
    'WorkspaceDialog supports German localization, resets active label and search filters on switch, and falls back cleanly when deleting the active workspace',
    (WidgetTester tester) async {
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(language: AppLanguage.german),
      );
      await settingsRepository.createWorkspace(
        'Privat',
        config: const WebDavConfig(
          localFilePath: 'privat.tdf',
          filePath: 'privat.tdf',
          language: AppLanguage.german,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            clockProvider.overrideWithValue(
              () => DateTime.utc(2026, 11, 3, 12, 0),
            ),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('drawer_create_label_tile')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('create_label_input')),
        'Büro',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('create_label_submit_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Büro'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('top_bar_title')),
        findsOneWidget,
        reason: 'Selected Büro label must appear in the top bar before switch',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('drawer_workspace_switcher')));
      await tester.pumpAndSettle();

      expect(find.text('Arbeitsbereiche'), findsOneWidget);
      expect(find.text('Aktiv'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('workspace_rename_button_privat')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('workspace_rename_input_privat')),
        '   ',
      );
      await tester.tap(
        find.byKey(const ValueKey('workspace_rename_save_button_privat')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workspace_error_banner')),
        findsOneWidget,
        reason: 'Blank workspace rename must show localized error banner',
      );
      expect(
        find.text('Bitte einen gültigen Namen eingeben (1–128 Zeichen).'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('workspace_rename_cancel_button_privat')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('workspace_select_privat')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('top_bar_title')),
        findsNothing,
        reason: 'Switching workspaces must clear the active label filter',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('drawer_workspace_switcher')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('workspace_delete_button_privat')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace_confirm_delete_button_privat')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workspace_tile_privat')),
        findsNothing,
        reason: 'Deleting active Privat workspace must remove it from list',
      );
      expect(
        find.byKey(const ValueKey('workspace_tile_tasks')),
        findsOneWidget,
        reason: 'Fallback Tasks workspace must remain active',
      );
      await tester.tap(
        find.byKey(const ValueKey('workspace_dialog_close_button')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('workspace_dialog')), findsNothing);
    },
  );
}
