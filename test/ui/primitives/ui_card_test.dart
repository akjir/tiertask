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

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/ui/primitives/ui_card.dart';
import 'package:tiertask/ui/primitives/ui_pill.dart';
import 'package:tiertask/ui/tokens/ui_theme_tokens.dart';

import '../test_helpers.dart';

void main() {
  group('UiCard', () {
    testWidgets(
      'standard supports isHighlighted, custom padding, and header slots',
      (tester) async {
        final tokens = UiThemePresets.calm.light;
        await pumpUiWidget(
          tester,
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              UiCard.standard(
                key: ValueKey<String>('std_card'),
                headerIcon: Icons.settings_outlined,
                headerTitle: 'General',
                headerBadge: UiPill(label: 'Auto-saved'),
                isHighlighted: true,
                padding: EdgeInsets.zero,
                child: Text('Card body'),
              ),
            ],
          ),
          tokens: tokens,
        );

        expect(find.text('General'), findsOneWidget);
        expect(find.text('Auto-saved'), findsOneWidget);
        expect(find.text('Card body'), findsOneWidget);

        final decorated = tester.widget<AnimatedContainer>(
          find
              .descendant(
                of: find.byKey(const ValueKey<String>('std_card')),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        final box = decorated.decoration as BoxDecoration?;
        expect(box?.color, equals(tokens.colors.soft));
        expect(box?.border, equals(Border.all(color: tokens.colors.accent)));
      },
    );

    testWidgets(
      'inset unconditionally provides UiSurfaceScope.insetWell and switches border on isEditing',
      (tester) async {
        final tokens = UiThemePresets.calm.light;
        late UiSurfaceLevel readSurfaceLevel;
        late UiSurfaceLevel editSurfaceLevel;

        await pumpUiWidget(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UiCard.inset(
                key: const ValueKey<String>('inset_read'),
                headerTitle: 'Note',
                child: Builder(
                  builder: (context) {
                    readSurfaceLevel = UiSurfaceScope.of(context);
                    return const Text('Read content');
                  },
                ),
              ),
              UiCard.inset(
                key: const ValueKey<String>('inset_edit'),
                headerTitle: 'Note edit',
                isEditing: true,
                footer: const Text('Footer actions'),
                child: Builder(
                  builder: (context) {
                    editSurfaceLevel = UiSurfaceScope.of(context);
                    return const Text('Edit content');
                  },
                ),
              ),
            ],
          ),
          tokens: tokens,
        );

        expect(readSurfaceLevel, equals(UiSurfaceLevel.insetWell));
        expect(editSurfaceLevel, equals(UiSurfaceLevel.insetWell));
        expect(find.text('Footer actions'), findsOneWidget);

        final readBox =
            tester
                    .widget<AnimatedContainer>(
                      find
                          .descendant(
                            of: find.byKey(
                              const ValueKey<String>('inset_read'),
                            ),
                            matching: find.byType(AnimatedContainer),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration?;
        expect(readBox?.color, equals(tokens.colors.bg));
        expect(readBox?.border, equals(Border.all(color: tokens.colors.line)));

        final editBox =
            tester
                    .widget<AnimatedContainer>(
                      find
                          .descendant(
                            of: find.byKey(
                              const ValueKey<String>('inset_edit'),
                            ),
                            matching: find.byType(AnimatedContainer),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration?;
        expect(editBox?.color, equals(tokens.colors.bg));
        expect(
          editBox?.border,
          equals(Border.all(color: tokens.colors.accent)),
        );
      },
    );

    testWidgets(
      'draft renders accent border, error region, and close callback',
      (tester) async {
        var closed = false;
        final tokens = UiThemePresets.calm.light;
        await pumpUiWidget(
          tester,
          UiCard.draft(
            key: const ValueKey<String>('draft_card'),
            title: 'New task draft',
            subtitle: 'Uncommitted',
            errorText: 'Title is required',
            closeTooltip: 'Close draft',
            onClose: () => closed = true,
            footer: const Text('Create'),
            child: const Text('Draft form'),
          ),
          tokens: tokens,
        );

        expect(find.text('New task draft'), findsOneWidget);
        expect(find.text('Uncommitted'), findsOneWidget);
        expect(find.text('Title is required'), findsOneWidget);
        await tester.tap(find.byTooltip('Close draft'));
        await tester.pump();
        expect(closed, isTrue);
      },
    );

    testWidgets(
      'expandable toggles reveal, swaps titleEditor, strikes through completed titles, suppresses hover border when expanded, and indents metadata on desktop vs compact',
      (tester) async {
        var expanded = false;
        var editingTitle = false;
        final tokens = UiThemePresets.calm.light;

        Widget buildExpandable({required bool isCompleted}) {
          return StatefulBuilder(
            builder: (context, setState) {
              return UiCard.expandable(
                key: const ValueKey<String>('exp_card'),
                title: 'Prepare release',
                isExpanded: expanded,
                isCompleted: isCompleted,
                isEditingTitle: editingTitle,
                titleEditor: const Text('Inline title editor'),
                leading: const Icon(Icons.radio_button_unchecked),
                collapsedMetadata: const Text(
                  'Collapsed meta',
                  key: ValueKey<String>('collapsed_meta'),
                ),
                expandedChild: const Text('Expanded panel'),
                onToggleExpand: () => setState(() => expanded = !expanded),
              );
            },
          );
        }

        // Desktop viewport: collapsed metadata indented 36px, hover highlights border.
        await pumpUiWidget(
          tester,
          buildExpandable(isCompleted: true),
          tokens: tokens,
        );

        final titleText = tester.widget<Text>(find.text('Prepare release'));
        expect(titleText.style?.decoration, equals(TextDecoration.lineThrough));
        expect(titleText.style?.color, equals(tokens.colors.muted));

        final metaLeftDesktop = tester
            .getTopLeft(find.byKey(const ValueKey<String>('collapsed_meta')))
            .dx;
        final cardLeftDesktop = tester
            .getTopLeft(find.byKey(const ValueKey<String>('exp_card')))
            .dx;
        expect(metaLeftDesktop - cardLeftDesktop, greaterThanOrEqualTo(48.0));

        // Hover while collapsed highlights border to accent.
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);
        await gesture.moveTo(
          tester.getCenter(find.byKey(const ValueKey<String>('exp_card'))),
        );
        await tester.pumpAndSettle();

        final hoveredBox =
            tester
                    .widget<AnimatedContainer>(
                      find
                          .descendant(
                            of: find.byKey(const ValueKey<String>('exp_card')),
                            matching: find.byType(AnimatedContainer),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration?;
        expect(
          hoveredBox?.border,
          equals(Border.all(color: tokens.colors.accent)),
        );

        // Tap header to expand: hides collapsed metadata, reveals panel, suppresses hover accent border.
        await tester.tap(find.text('Prepare release'));
        await tester.pumpAndSettle();
        expect(expanded, isTrue);
        expect(find.text('Expanded panel'), findsOneWidget);
        expect(find.text('Collapsed meta'), findsNothing);

        final expandedBox =
            tester
                    .widget<AnimatedContainer>(
                      find
                          .descendant(
                            of: find.byKey(const ValueKey<String>('exp_card')),
                            matching: find.byType(AnimatedContainer),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration?;
        expect(
          expandedBox?.border,
          equals(Border.all(color: tokens.colors.line)),
        );

        // Title editor swap when isEditingTitle is true.
        editingTitle = true;
        await pumpUiWidget(
          tester,
          buildExpandable(isCompleted: false),
          tokens: tokens,
          surfaceSize: const Size(390, 800),
        );
        expect(find.text('Inline title editor'), findsOneWidget);

        // Compact viewport collapsed metadata has 0 extra indent.
        expanded = false;
        editingTitle = false;
        await pumpUiWidget(
          tester,
          buildExpandable(isCompleted: false),
          tokens: tokens,
          surfaceSize: const Size(390, 800),
        );
        final metaLeftCompact = tester
            .getTopLeft(find.byKey(const ValueKey<String>('collapsed_meta')))
            .dx;
        final cardLeftCompact = tester
            .getTopLeft(find.byKey(const ValueKey<String>('exp_card')))
            .dx;
        expect(metaLeftCompact - cardLeftCompact, lessThan(24.0));
      },
    );

    testWidgets(
      'hovering an expanded UiCard.expandable does not rebuild expandedChild',
      (tester) async {
        var childBuilds = 0;
        final expandedBody = Builder(
          builder: (_) {
            childBuilds++;
            return const Text('Expanded body');
          },
        );
        await pumpUiWidget(
          tester,
          UiCard.expandable(
            key: const ValueKey<String>('hover_expanded_card'),
            title: 'Task',
            isExpanded: true,
            onToggleExpand: () {},
            expandedChild: expandedBody,
          ),
        );

        final initialBuilds = childBuilds;
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);

        await gesture.moveTo(
          tester.getCenter(
            find.byKey(const ValueKey<String>('hover_expanded_card')),
          ),
        );
        await tester.pump();
        await gesture.moveTo(Offset.zero);
        await tester.pump();

        expect(
          childBuilds,
          equals(initialBuilds),
          reason: 'Hovering an expanded card must not trigger setState rebuilds of expandedChild',
        );
      },
    );

    testWidgets(
      'omits idle AnimatedContainer on static standard/draft cards and omits AnimatedSize on collapsed expandable cards',
      (tester) async {
        var expanded = false;
        late StateSetter setOuterState;

        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              setOuterState = setState;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const UiCard.standard(
                    key: ValueKey<String>('static_std_card'),
                    child: Text('Static standard'),
                  ),
                  const UiCard.draft(
                    key: ValueKey<String>('static_draft_card'),
                    title: 'Draft title',
                    child: Text('Draft body'),
                  ),
                  UiCard.expandable(
                    key: const ValueKey<String>('lazy_exp_card'),
                    title: 'Collapsible item',
                    isExpanded: expanded,
                    onToggleExpand: () => setState(() => expanded = !expanded),
                    expandedChild: const Text('Expanded detail'),
                  ),
                ],
              );
            },
          ),
        );

        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('static_std_card')),
            matching: find.byType(AnimatedContainer),
          ),
          findsNothing,
          reason: 'Non-highlighted UiCard.standard must not allocate an idle AnimatedContainer',
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('static_draft_card')),
            matching: find.byType(AnimatedContainer),
          ),
          findsNothing,
          reason: 'UiCard.draft must not allocate an idle AnimatedContainer',
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('lazy_exp_card')),
            matching: find.byType(AnimatedSize),
          ),
          findsNothing,
          reason:
              'Collapsed UiCard.expandable must not mount an idle AnimatedSize',
        );

        setOuterState(() => expanded = true);
        await tester.pumpAndSettle();
        expect(find.text('Expanded detail'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('lazy_exp_card')),
            matching: find.byType(AnimatedSize),
          ),
          findsOneWidget,
          reason: 'Expanded UiCard.expandable mounts AnimatedSize while open',
        );

        setOuterState(() => expanded = false);
        await tester.pumpAndSettle();
        expect(find.text('Expanded detail'), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('lazy_exp_card')),
            matching: find.byType(AnimatedSize),
          ),
          findsNothing,
          reason: 'Collapsed UiCard.expandable unmounts AnimatedSize once collapse settles',
        );
      },
    );

    testWidgets(
      'aligns headerTrailing flush with inner content right edge on inset and standard cards',
      (tester) async {
        await pumpUiWidget(
          tester,
          const SizedBox(
            width: 720.0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                UiCard.inset(
                  key: ValueKey<String>('aligned_inset_note'),
                  headerIcon: Icons.description_outlined,
                  headerTitle: 'Note',
                  headerTrailing: SizedBox(
                    key: ValueKey<String>('note_trailing'),
                    width: 64.0,
                    height: 30.0,
                  ),
                  child: SizedBox(
                    key: ValueKey<String>('note_body'),
                    height: 20.0,
                  ),
                ),
                UiCard.inset(
                  key: ValueKey<String>('aligned_inset_links'),
                  headerIcon: Icons.link_rounded,
                  headerTitle: 'Links',
                  headerBadge: UiPill(
                    label: '18 / 20',
                    variant: UiPillVariant.count,
                  ),
                  headerTrailing: SizedBox(
                    key: ValueKey<String>('links_trailing'),
                    width: 30.0,
                    height: 30.0,
                  ),
                  child: SizedBox(
                    key: ValueKey<String>('links_body'),
                    height: 20.0,
                  ),
                ),
                UiCard.standard(
                  key: ValueKey<String>('aligned_std'),
                  headerTitle: 'Settings',
                  headerTrailing: SizedBox(
                    key: ValueKey<String>('std_trailing'),
                    width: 48.0,
                    height: 30.0,
                  ),
                  child: SizedBox(
                    key: ValueKey<String>('std_body'),
                    height: 20.0,
                  ),
                ),
              ],
            ),
          ),
        );

        final noteBodyRight = tester
            .getRect(find.byKey(const ValueKey<String>('note_body')))
            .right;
        final noteTrailingRight = tester
            .getRect(find.byKey(const ValueKey<String>('note_trailing')))
            .right;
        expect(
          noteTrailingRight,
          closeTo(noteBodyRight, 0.5),
          reason: 'Note header trailing controls must align flush with inset body right edge',
        );

        final linksBodyRight = tester
            .getRect(find.byKey(const ValueKey<String>('links_body')))
            .right;
        final linksTrailingRight = tester
            .getRect(find.byKey(const ValueKey<String>('links_trailing')))
            .right;
        expect(
          linksTrailingRight,
          closeTo(linksBodyRight, 0.5),
          reason: 'Links header trailing control must align flush with inset body right edge',
        );
        expect(
          linksTrailingRight,
          closeTo(noteTrailingRight, 0.5),
          reason: 'Trailing actions across stacked inset sections must align vertically',
        );

        final stdBodyRight = tester
            .getRect(find.byKey(const ValueKey<String>('std_body')))
            .right;
        final stdTrailingRight = tester
            .getRect(find.byKey(const ValueKey<String>('std_trailing')))
            .right;
        expect(
          stdTrailingRight,
          closeTo(stdBodyRight, 0.5),
          reason: 'Standard card header trailing control must align flush with body right edge',
        );
      },
    );
  });
}
