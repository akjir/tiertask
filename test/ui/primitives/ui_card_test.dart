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
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/ui/primitives/ui_button.dart';
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

    testWidgets(
      'expands when tapping collapsed card background while excluding interactive controls and keeping collapse on header only',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          var expanded = false;
          var toggleCount = 0;
          var leadingTapCount = 0;
          var trailingTapCount = 0;
          var chipTapCount = 0;
          var editingTitle = false;
          var disableControls = false;
          late StateSetter setOuterState;

          await pumpUiWidget(
            tester,
            StatefulBuilder(
              builder: (context, setState) {
                setOuterState = setState;
                return SizedBox(
                  width: 600.0,
                  child: UiCard.expandable(
                    key: const ValueKey<String>('surface_expand_card'),
                    title: 'Review release checklist',
                    isExpanded: expanded,
                    isEditingTitle: editingTitle,
                    titleEditor: const Text('Title input'),
                    leading: UiButton(
                      key: const ValueKey<String>('leading_action_button'),
                      leadingIcon: Icons.check_circle_outline,
                      variant: UiButtonVariant.icon,
                      density: UiButtonDensity.compact,
                      onPressed: disableControls
                          ? null
                          : () => leadingTapCount++,
                    ),
                    trailingActions: <Widget>[
                      UiButton(
                        key: const ValueKey<String>('trailing_action_button'),
                        leadingIcon: Icons.chevron_right_rounded,
                        variant: UiButtonVariant.icon,
                        density: UiButtonDensity.compact,
                        onPressed: disableControls
                            ? null
                            : () => trailingTapCount++,
                      ),
                    ],
                    collapsedMetadata: Wrap(
                      spacing: 6.0,
                      children: <Widget>[
                        UiPill(
                          key: const ValueKey<String>('interactive_chip'),
                          label: 'Label Chip',
                          variant: UiPillVariant.tag,
                          onPressed: () => chipTapCount++,
                        ),
                        const UiPill(
                          key: ValueKey<String>('passive_meta_pill'),
                          label: 'Focus',
                          variant: UiPillVariant.meta,
                          tone: UiPillTone.soft,
                        ),
                      ],
                    ),
                    expandedChild: const SizedBox(
                      key: ValueKey<String>('expanded_body_area'),
                      height: 80.0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Expanded content'),
                      ),
                    ),
                    onToggleExpand: () {
                      toggleCount++;
                      setState(() => expanded = !expanded);
                    },
                  ),
                );
              },
            ),
          );

          final cardFinder = find.byKey(
            const ValueKey<String>('surface_expand_card'),
          );
          final cardRect = tester.getRect(cardFinder);

          final collapsedRegion = tester.widget<MouseRegion>(
            find
                .descendant(of: cardFinder, matching: find.byType(MouseRegion))
                .first,
          );
          expect(
            collapsedRegion.cursor,
            equals(SystemMouseCursors.click),
            reason:
                'Collapsed expandable card surface must show clickable cursor',
          );

          // Enabled leading, trailing, and interactive metadata controls keep their own actions.
          await tester.tap(
            find.byKey(const ValueKey<String>('leading_action_button')),
          );
          await tester.pump();
          expect(leadingTapCount, equals(1));
          expect(expanded, isFalse);

          await tester.tap(
            find.byKey(const ValueKey<String>('trailing_action_button')),
          );
          await tester.pump();
          expect(trailingTapCount, equals(1));
          expect(expanded, isFalse);

          await tester.tap(
            find.byKey(const ValueKey<String>('interactive_chip')),
          );
          await tester.pump();
          expect(chipTapCount, equals(1));
          expect(expanded, isFalse);

          // Disabled leading and trailing buttons must not leak taps to expand the card.
          setOuterState(() => disableControls = true);
          await tester.pump();

          await tester.tap(
            find.byKey(const ValueKey<String>('leading_action_button')),
          );
          await tester.pump();
          await tester.tap(
            find.byKey(const ValueKey<String>('trailing_action_button')),
          );
          await tester.pump();
          expect(
            expanded,
            isFalse,
            reason: 'Disabled leading and trailing controls must not bubble taps to card expansion',
          );
          expect(toggleCount, equals(0));

          // Tapping passive metadata pill expands via the card surface once.
          await tester.tap(
            find.byKey(const ValueKey<String>('passive_meta_pill')),
          );
          await tester.pumpAndSettle();
          expect(expanded, isTrue);
          expect(toggleCount, equals(1));

          // Expanded card restores default cursor and ignores background/body clicks.
          final expandedRegion = tester.widget<MouseRegion>(
            find
                .descendant(of: cardFinder, matching: find.byType(MouseRegion))
                .first,
          );
          expect(
            expandedRegion.cursor,
            equals(MouseCursor.defer),
            reason: 'Expanded card surface must not advertise a clickable card cursor',
          );

          final expandedCardRect = tester.getRect(cardFinder);
          await tester.tapAt(expandedCardRect.topLeft + const Offset(4.0, 4.0));
          await tester.pump();
          await tester.tapAt(
            expandedCardRect.bottomRight - const Offset(4.0, 4.0),
          );
          await tester.pump();
          await tester.tap(find.text('Expanded content'));
          await tester.pump();
          await tester.tapAt(
            tester.getCenter(
              find.byKey(const ValueKey<String>('expanded_body_area')),
            ),
          );
          await tester.pump();
          expect(
            expanded,
            isTrue,
            reason: 'Tapping expanded card padding or expanded body must not collapse the card',
          );
          expect(toggleCount, equals(1));

          // Header title still collapses the expanded card.
          await tester.tap(find.text('Review release checklist'));
          await tester.pumpAndSettle();
          expect(expanded, isFalse);
          expect(toggleCount, equals(2));

          // Tapping collapsed card padding corner expands the card.
          await tester.tapAt(cardRect.topLeft + const Offset(4.0, 4.0));
          await tester.pumpAndSettle();
          expect(
            expanded,
            isTrue,
            reason: 'Tapping collapsed card outer padding must expand the card',
          );
          expect(toggleCount, equals(3));

          // Collapse again and verify whitespace beside collapsed metadata expands the card.
          await tester.tap(find.text('Review release checklist'));
          await tester.pumpAndSettle();
          expect(expanded, isFalse);

          final refreshedCollapsedRect = tester.getRect(cardFinder);
          await tester.tapAt(
            Offset(
              refreshedCollapsedRect.right - 8.0,
              refreshedCollapsedRect.bottom - 8.0,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            expanded,
            isTrue,
            reason: 'Tapping collapsed card background next to metadata pills must expand the card',
          );
          expect(toggleCount, equals(5));

          // Collapse and verify isEditingTitle suppresses surface expansion.
          setOuterState(() {
            expanded = false;
            editingTitle = true;
          });
          await tester.pumpAndSettle();
          await tester.tapAt(cardRect.topLeft + const Offset(4.0, 4.0));
          await tester.pump();
          expect(
            expanded,
            isFalse,
            reason: 'Card surface tap must be disabled while isEditingTitle is true',
          );

          // Verify outer card semantics does not add a duplicate tap action over child controls.
          setOuterState(() {
            expanded = false;
            editingTitle = false;
          });
          await tester.pump();
          final cardSemantics = tester.getSemantics(cardFinder);
          expect(
            cardSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
            isFalse,
            reason: 'Card surface GestureDetector must stay excluded from semantics so header and child buttons remain distinct',
          );
        } finally {
          semanticsHandle.dispose();
        }
      },
    );
  });
}
