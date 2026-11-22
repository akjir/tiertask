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

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_board.dart';
import '../../models/tdf_error.dart';
import '../../models/tdf_metadata.dart';
import '../../providers/entity_actions_provider.dart';
import '../../providers/shell_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/task_schedule_helper.dart';
import '../components/ui_quick_composer.dart';
import '../layout/ui_page_header.dart';
import '../primitives/ui_banner.dart';
import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';
import '../widgets/entity_card_chrome.dart';
import '../widgets/entity_reveal_scroll_controller.dart';
import 'label_card.dart';

/// Expandable Labels manager view with inline Quick-Create, uncommitted Label Draft Card,
/// single-expand entity cards, live Board Scope toggle, inline Color wheel editor, and context-preserving Back navigation.
class LabelsView extends ConsumerStatefulWidget {
  /// Creates a [LabelsView] with an optional caller-owned [scrollController].
  const LabelsView({super.key, this.scrollController});

  /// Optional caller-owned scroll controller preserving scroll offset across shell updates (`U-LAYOUT-007`).
  final ScrollController? scrollController;

  @override
  ConsumerState<LabelsView> createState() => _LabelsViewState();
}

/// Spaced lazy list slot hosting one [LabelCard].
class _LabelListSlot extends StatelessWidget {
  /// Creates a [_LabelListSlot].
  const _LabelListSlot({
    required this.cardScrollKey,
    required this.label,
    required this.bottomGap,
  });

  /// Bottom gap between sibling cards (`cardListGap` or `0.0` on final card).
  final double bottomGap;

  /// [GlobalKey] attached around the card for smooth reveal scrolling.
  final GlobalKey cardScrollKey;

  /// Persisted domain label rendered by this card.
  final TdfLabel label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: LabelCard(cardScrollKey: cardScrollKey, label: label),
    );
  }
}

/// Inline Quick-Create bar wrapping [UiQuickComposer] and an optional live-region inline error line (`U-CARD-006`).
class _LabelQuickCreateBar extends StatelessWidget {
  /// Creates a [_LabelQuickCreateBar].
  const _LabelQuickCreateBar({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.errorText,
    required this.onExpandDraft,
    required this.onSubmit,
  });

  /// Controller backing the label name input.
  final TextEditingController controller;

  /// Disables text input and actions while mutations are in flight.
  final bool enabled;

  /// Optional inline validation or persistence error text.
  final String? errorText;

  /// Focus node backing the label name input.
  final FocusNode focusNode;

  /// Callback opening the uncommitted Label Draft Card.
  final VoidCallback onExpandDraft;

  /// Callback submitting the Quick-Create label name.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final error = errorText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiQuickComposer(
          key: const ValueKey<String>('labels_quick_create_composer'),
          controller: controller,
          focusNode: focusNode,
          isCollapsibleOnCompact: false,
          maxLength: maxTdfTextLength,
          placeholder: localizations.quickCreateLabelHint,
          submitLabel: localizations.actionAdd,
          expandDraftLabel: localizations.actionOpenAsDraft,
          enabled: enabled,
          onExpandDraft: onExpandDraft,
          onSubmit: onSubmit,
        ),
        if (error != null && error.isNotEmpty) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          EntityInlineErrorText(message: error),
        ],
      ],
    );
  }
}

/// Immutable value-equality label list slice watched by [_LabelsViewState].
@immutable
class _LabelsBoardSlice {
  /// Creates a [_LabelsBoardSlice].
  const _LabelsBoardSlice(this.labels);

  /// Alphabetically sorted workspace labels.
  final List<TdfLabel> labels;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _LabelsBoardSlice && listEquals(other.labels, labels);
  }

  @override
  int get hashCode => Object.hashAll(labels);
}

/// Vertical header plus Quick-Create bar or uncommitted Label Draft Card inside [_LabelsHeaderContent].
class _LabelsHeaderColumn extends StatelessWidget {
  /// Creates a [_LabelsHeaderColumn].
  const _LabelsHeaderColumn({
    required this.labelsCount,
    required this.nextPresetColorHex,
    required this.returnContext,
    required this.isDraftOpen,
    required this.draftSeedTitle,
    required this.isQuickCreateBusy,
    required this.quickCreateController,
    required this.quickCreateFocusNode,
    required this.quickCreateError,
    required this.onBack,
    required this.onExpandDraft,
    required this.onQuickCreateSubmit,
    required this.onCancelDraft,
  });

  /// Seeded label name transferred into an open Label Draft Card.
  final String draftSeedTitle;

  /// Whether an uncommitted Label Draft Card replaces Quick-Create.
  final bool isDraftOpen;

  /// Whether Quick-Create is disabled while busy.
  final bool isQuickCreateBusy;

  /// Total number of persisted workspace labels.
  final int labelsCount;

  /// Next rotating preset `#RRGGBB` color seeding an open Label Draft Card.
  final String nextPresetColorHex;

  /// Back navigation callback when [returnContext] is set.
  final VoidCallback onBack;

  /// Callback cancelling the active draft card.
  final VoidCallback onCancelDraft;

  /// Callback opening the uncommitted draft card.
  final VoidCallback onExpandDraft;

  /// Callback submitting the Quick-Create label name.
  final Future<void> Function() onQuickCreateSubmit;

  /// Text controller backing the Quick-Create input.
  final TextEditingController quickCreateController;

  /// Optional inline Quick-Create validation or persistence error text.
  final String? quickCreateError;

  /// Focus node backing the Quick-Create input.
  final FocusNode quickCreateFocusNode;

  /// Saved originating task or search context, if any.
  final ReturnContext? returnContext;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiPageHeader(
          backLabel: _resolveBackLabel(returnContext, localizations),
          onBack: returnContext != null ? onBack : null,
          title: localizations.drawerLabels,
          subtitle: localizations.labelsManagerSubtitle,
          countLabel: '$labelsCount',
        ),
        SizedBox(height: tokens.spacing.space4),
        if (isDraftOpen)
          LabelDraftCard(
            seedTitle: draftSeedTitle,
            initialColorHex: nextPresetColorHex,
            onCancel: onCancelDraft,
          )
        else
          _LabelQuickCreateBar(
            controller: quickCreateController,
            focusNode: quickCreateFocusNode,
            enabled: !isQuickCreateBusy,
            errorText: quickCreateError,
            onExpandDraft: onExpandDraft,
            onSubmit: () => unawaited(onQuickCreateSubmit()),
          ),
      ],
    );
  }
}

/// Selective shell-state subscriber wiring return context, draft seed, and busy flags into [_LabelsHeaderColumn].
class _LabelsHeaderContent extends ConsumerWidget {
  /// Creates a [_LabelsHeaderContent].
  const _LabelsHeaderContent({
    required this.labelsCount,
    required this.nextPresetColorHex,
    required this.isDraftOpen,
    required this.isQuickCreating,
    required this.quickCreateController,
    required this.quickCreateFocusNode,
    required this.quickCreateError,
    required this.onBack,
    required this.onExpandDraft,
    required this.onQuickCreateSubmit,
    required this.onCancelDraft,
  });

  /// Whether an uncommitted Label Draft Card replaces Quick-Create.
  final bool isDraftOpen;

  /// Whether a local Quick-Create submission is currently awaiting persistence.
  final bool isQuickCreating;

  /// Total number of persisted workspace labels.
  final int labelsCount;

  /// Next rotating preset `#RRGGBB` color seeding an open Label Draft Card.
  final String nextPresetColorHex;

  /// Back navigation callback when `returnContext` is set.
  final VoidCallback onBack;

  /// Callback cancelling the active draft card.
  final VoidCallback onCancelDraft;

  /// Callback opening the uncommitted draft card.
  final VoidCallback onExpandDraft;

  /// Callback submitting the Quick-Create label name.
  final Future<void> Function() onQuickCreateSubmit;

  /// Text controller backing the Quick-Create input.
  final TextEditingController quickCreateController;

  /// Optional inline Quick-Create validation or persistence error text.
  final String? quickCreateError;

  /// Focus node backing the Quick-Create input.
  final FocusNode quickCreateFocusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final returnContext = ref.watch(
      shellProvider.select((shell) => shell.returnContext),
    );
    final draftSeedTitle = ref.watch(
      shellProvider.select((shell) => shell.draftSeedTitle),
    );
    final isBusy = ref.watch(
      entityActionsProvider.select((state) => state.isBusy),
    );

    return _LabelsHeaderColumn(
      labelsCount: labelsCount,
      nextPresetColorHex: nextPresetColorHex,
      returnContext: returnContext,
      isDraftOpen: isDraftOpen,
      draftSeedTitle: draftSeedTitle,
      isQuickCreateBusy: isBusy || isQuickCreating,
      quickCreateController: quickCreateController,
      quickCreateFocusNode: quickCreateFocusNode,
      quickCreateError: quickCreateError,
      onBack: onBack,
      onExpandDraft: onExpandDraft,
      onQuickCreateSubmit: onQuickCreateSubmit,
      onCancelDraft: onCancelDraft,
    );
  }
}

/// Padded [SliverToBoxAdapter] hosting the Labels header and Quick-Create or Draft surface.
class _LabelsHeaderSliver extends StatelessWidget {
  /// Creates a [_LabelsHeaderSliver].
  const _LabelsHeaderSliver({required this.padding, required this.child});

  /// Header subtree wrapped in this sliver.
  final Widget child;

  /// Outer padding aligned with the main content gutter.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: padding,
      sliver: SliverToBoxAdapter(child: child),
    );
  }
}

/// Padded sliver switching between the empty-state banner and the lazy [SliverList.builder] of Label cards.
class _LabelsListSliver extends StatelessWidget {
  /// Creates a [_LabelsListSliver].
  const _LabelsListSliver({
    required this.padding,
    required this.showEmptyState,
    required this.labels,
    required this.cardKeyFor,
  });

  /// Lookup returning the reveal [GlobalKey] for a label card.
  final GlobalKey Function(String labelId) cardKeyFor;

  /// Alphabetically sorted domain labels displayed in the manager list.
  final List<TdfLabel> labels;

  /// Outer padding applied around the empty state or label card list.
  final EdgeInsets padding;

  /// Whether to render the plain-text empty-state banner instead of label cards.
  final bool showEmptyState;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return SliverPadding(
      padding: padding,
      sliver: showEmptyState
          ? SliverToBoxAdapter(
              child: UiBanner(
                key: const ValueKey<String>('labels_empty_banner'),
                variant: UiBannerVariant.emptyState,
                message: localizations.emptyLabelsHint,
              ),
            )
          : SliverList.builder(
              itemCount: labels.length,
              itemBuilder: (context, index) => _LabelListSlot(
                cardScrollKey: cardKeyFor(labels[index].id),
                label: labels[index],
                bottomGap: index + 1 < labels.length
                    ? tokens.spacing.cardListGap
                    : 0.0,
              ),
            ),
    );
  }
}

/// Primary [CustomScrollView] housing the Labels header, Quick-Create or Draft Card, empty state, and lazy label cards.
class _LabelsScrollBody extends StatelessWidget {
  /// Creates a [_LabelsScrollBody].
  const _LabelsScrollBody({
    required this.scrollController,
    required this.labels,
    required this.nextPresetColorHex,
    required this.isDraftOpen,
    required this.isQuickCreating,
    required this.quickCreateController,
    required this.quickCreateFocusNode,
    required this.quickCreateError,
    required this.cardKeyFor,
    required this.onBack,
    required this.onExpandDraft,
    required this.onQuickCreateSubmit,
    required this.onCancelDraft,
  });

  /// Lookup returning the reveal [GlobalKey] for a label card.
  final GlobalKey Function(String labelId) cardKeyFor;

  /// Whether an uncommitted Label Draft Card currently replaces the Quick-Create bar.
  final bool isDraftOpen;

  /// Whether a local Quick-Create submission is currently awaiting persistence.
  final bool isQuickCreating;

  /// Alphabetically sorted workspace labels.
  final List<TdfLabel> labels;

  /// Next rotating preset `#RRGGBB` color seeding an open Label Draft Card.
  final String nextPresetColorHex;

  /// Back navigation callback wired when `returnContext` is active.
  final VoidCallback onBack;

  /// Callback cancelling the open Label Draft Card.
  final VoidCallback onCancelDraft;

  /// Callback opening the Label Draft Card from Quick-Create.
  final VoidCallback onExpandDraft;

  /// Callback submitting the Quick-Create label name.
  final Future<void> Function() onQuickCreateSubmit;

  /// Text controller backing the Quick-Create input.
  final TextEditingController quickCreateController;

  /// Optional inline Quick-Create validation or persistence error message.
  final String? quickCreateError;

  /// Focus node backing the Quick-Create input.
  final FocusNode quickCreateFocusNode;

  /// Scroll controller driving the outer [CustomScrollView].
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);
    final contentPadding = tokens.spacing.mainContentPadding(viewport);

    return CustomScrollView(
      controller: scrollController,
      slivers: <Widget>[
        _LabelsHeaderSliver(
          padding: contentPadding.copyWith(bottom: 0.0),
          child: _LabelsHeaderContent(
            labelsCount: labels.length,
            nextPresetColorHex: nextPresetColorHex,
            isDraftOpen: isDraftOpen,
            isQuickCreating: isQuickCreating,
            quickCreateController: quickCreateController,
            quickCreateFocusNode: quickCreateFocusNode,
            quickCreateError: quickCreateError,
            onBack: onBack,
            onExpandDraft: onExpandDraft,
            onQuickCreateSubmit: onQuickCreateSubmit,
            onCancelDraft: onCancelDraft,
          ),
        ),
        _LabelsListSliver(
          padding: contentPadding.copyWith(top: tokens.spacing.space4),
          showEmptyState: labels.isEmpty && !isDraftOpen,
          labels: labels,
          cardKeyFor: cardKeyFor,
        ),
      ],
    );
  }
}

/// Coordinates Quick-Create, scroll reveal, and draft lifecycle for [LabelsView].
class _LabelsViewState extends ConsumerState<LabelsView>
    with EntityRevealScrollMixin<LabelsView> {
  late final TextEditingController _quickCreateController;
  late final FocusNode _quickCreateFocusNode;

  bool _isQuickCreating = false;
  String? _quickCreateError;

  @override
  ScrollController? get externalScrollController => widget.scrollController;

  @override
  EntityDraftKind get revealDraftKind => EntityDraftKind.label;

  @override
  EntityKind get revealEntityKind => EntityKind.label;

  @override
  void initState() {
    super.initState();
    _quickCreateController = TextEditingController()
      ..addListener(_handleQuickCreateTextChanged);
    _quickCreateFocusNode = FocusNode();
    initRevealScroll();
  }

  @override
  void didUpdateWidget(covariant LabelsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    handleScrollControllerSwap(oldWidget.scrollController);
  }

  @override
  void dispose() {
    disposeRevealScroll();
    _quickCreateController
      ..removeListener(_handleQuickCreateTextChanged)
      ..dispose();
    _quickCreateFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    registerRevealShellListeners();
    final labels = ref
        .watch(taskNotifierProvider.select(_selectLabelsBoardSlice))
        .labels;
    final isDraftOpen = ref.watch(
      shellProvider.select(
        (shell) => shell.activeDraft == EntityDraftKind.label,
      ),
    );
    pruneOwnedCardKeys(labels.map((label) => label.id));

    return _LabelsScrollBody(
      scrollController: effectiveScrollController,
      labels: labels,
      nextPresetColorHex:
          canonicalLabelPresetHexColors[labels.length %
              canonicalLabelPresetHexColors.length],
      isDraftOpen: isDraftOpen,
      isQuickCreating: _isQuickCreating,
      quickCreateController: _quickCreateController,
      quickCreateFocusNode: _quickCreateFocusNode,
      quickCreateError: _quickCreateError,
      cardKeyFor: resolveRevealCardKey,
      onBack: _handleBack,
      onExpandDraft: _handleExpandDraft,
      onQuickCreateSubmit: _handleQuickCreateSubmit,
      onCancelDraft: _handleCancelDraft,
    );
  }

  @override
  List<String> collectVisibleEntityIds() {
    final labels =
        ref.read(taskNotifierProvider).asData?.value.sortedLabels ??
        const <TdfLabel>[];
    return <String>[for (final label in labels) label.id];
  }

  /// Restores saved task or search context via [shellProvider].
  void _handleBack() {
    ref.read(shellProvider.notifier).navigateBackFromReturnContext();
  }

  /// Cancels the active uncommitted Label Draft Card.
  void _handleCancelDraft() {
    ref.read(shellProvider.notifier).cancelDraft();
  }

  /// Transfers any typed Quick-Create name into an uncommitted Label Draft Card (`U-CARD-006`).
  void _handleExpandDraft() {
    final seedTitle = _quickCreateController.text.trim();
    _quickCreateController.clear();
    if (_quickCreateError != null) {
      setState(() => _quickCreateError = null);
    }
    ref
        .read(shellProvider.notifier)
        .openDraft(EntityDraftKind.label, seedTitle: seedTitle);
  }

  /// Submits Quick-Create text to [EntityActionsNotifier.quickCreateLabel] and clears input only on success.
  Future<void> _handleQuickCreateSubmit() async {
    if (_isQuickCreating) {
      return;
    }
    setState(() {
      _isQuickCreating = true;
      _quickCreateError = null;
    });
    try {
      final locale = Localizations.localeOf(context);
      final result = await ref
          .read(entityActionsProvider.notifier)
          .quickCreateLabel(_quickCreateController.text, locale: locale);
      if (!mounted) {
        return;
      }
      switch (result) {
        case ActionSucceeded():
          _quickCreateController.clear();
          setState(() => _quickCreateError = null);
        case ActionValidationFailed(:final message):
        case ActionPersistFailed(:final message):
          setState(() => _quickCreateError = message);
      }
    } finally {
      if (mounted) {
        setState(() => _isQuickCreating = false);
      }
    }
  }

  /// Clears transient inline Quick-Create validation errors when the user edits the input.
  void _handleQuickCreateTextChanged() {
    if (_quickCreateError != null && mounted) {
      setState(() => _quickCreateError = null);
    }
  }
}

/// Resolves the localized Back button label from [returnContext], or `null` when absent.
String? _resolveBackLabel(
  ReturnContext? returnContext,
  AppLocalizations localizations,
) {
  return switch (returnContext) {
    final saved? =>
      saved.searchOpen
          ? localizations.actionBackToSearch
          : localizations.actionBackToTasks,
    null => null,
  };
}

/// Extracts value-compared sorted workspace labels from [boardAsync].
_LabelsBoardSlice _selectLabelsBoardSlice(AsyncValue<TaskBoard> boardAsync) {
  return _LabelsBoardSlice(
    boardAsync.asData?.value.sortedLabels ?? const <TdfLabel>[],
  );
}
