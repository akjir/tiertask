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
import '../../models/location_state.dart';
import '../../models/task_board.dart';
import '../../models/tdf_error.dart';
import '../../models/tdf_location.dart';
import '../../providers/entity_actions_provider.dart';
import '../../providers/floating_notice_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/shell_providers.dart';
import '../../providers/task_providers.dart';
import '../components/ui_quick_composer.dart';
import '../layout/ui_page_header.dart';
import '../primitives/ui_banner.dart';
import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';
import '../widgets/entity_reveal_scroll_controller.dart';
import 'location_card.dart';

/// Expandable Locations manager view with inline Quick-Create, uncommitted Draft Card,
/// single-expand location cards, coordinates/geocoding editing, and context-preserving Back navigation (`U-CARD-001`..`006`, `U-UX-002`).
class LocationsView extends ConsumerStatefulWidget {
  /// Creates a [LocationsView].
  const LocationsView({super.key, this.scrollController});

  /// Optional caller-owned scroll controller preserving scroll offset across shell views.
  final ScrollController? scrollController;

  @override
  ConsumerState<LocationsView> createState() => _LocationsViewState();
}

/// Immutable value-equality location list slice watched by [_LocationsViewState].
@immutable
class _LocationsBoardSlice {
  /// Creates a [_LocationsBoardSlice].
  const _LocationsBoardSlice(this.locations);

  /// Alphabetically sorted workspace locations.
  final List<TdfLocation> locations;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _LocationsBoardSlice &&
        listEquals(other.locations, locations);
  }

  @override
  int get hashCode => Object.hashAll(locations);
}

/// Lazy sliver list building expandable Location cards (`P-LAZY-LISTS`).
class _LocationsCardListSliver extends StatelessWidget {
  /// Creates a [_LocationsCardListSliver].
  const _LocationsCardListSliver({
    required this.locations,
    required this.contentPadding,
    required this.cardKeyFor,
  });

  /// Lookup returning the reveal [GlobalKey] for a location card.
  final GlobalKey Function(String locationId) cardKeyFor;

  /// Responsive viewport content padding applied around the card list.
  final EdgeInsets contentPadding;

  /// Alphabetically sorted domain locations.
  final List<TdfLocation> locations;

  @override
  Widget build(BuildContext context) {
    if (locations.isEmpty) {
      return SliverPadding(
        padding: EdgeInsets.only(bottom: contentPadding.bottom),
        sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
      );
    }
    final cardGap = UiThemeTokens.of(context).spacing.cardListGap;

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        contentPadding.left,
        0.0,
        contentPadding.right,
        contentPadding.bottom,
      ),
      sliver: SliverList.builder(
        itemCount: locations.length,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(
            bottom: index + 1 < locations.length ? cardGap : 0.0,
          ),
          child: LocationCard(
            key: ValueKey<String>('location_card_${locations[index].id}'),
            cardScrollKey: cardKeyFor(locations[index].id),
            location: locations[index],
          ),
        ),
      ),
    );
  }
}

/// Renders either the uncommitted Location Draft Card or the inline Quick-Create composer (`U-CARD-006`).
class _LocationsComposerSlot extends ConsumerWidget {
  /// Creates a [_LocationsComposerSlot].
  const _LocationsComposerSlot({
    required this.isDraftOpen,
    required this.draftSeedTitle,
    required this.quickCreateController,
    required this.quickCreateFocusNode,
    required this.isBusy,
    required this.onExpandDraft,
    required this.onSubmitQuickCreate,
  });

  /// Initial location name transferred from Quick-Create.
  final String draftSeedTitle;

  /// Whether an entity mutation is currently running.
  final bool isBusy;

  /// Whether the uncommitted Location Draft Card replaces Quick-Create in place.
  final bool isDraftOpen;

  /// Callback opening the uncommitted Location Draft Card.
  final VoidCallback onExpandDraft;

  /// Callback submitting the Quick-Create location name.
  final VoidCallback onSubmitQuickCreate;

  /// Controller for the Quick-Create bar.
  final TextEditingController quickCreateController;

  /// Focus node for the Quick-Create bar.
  final FocusNode quickCreateFocusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isDraftOpen) {
      final hasActiveGpsFix = ref.watch(
        locationStateProvider.select(
          (state) =>
              state.status == LocationStatus.found &&
              (state.fix?.hasCoordinates ?? false),
        ),
      );
      return LocationDraftCard(
        seedTitle: draftSeedTitle,
        hasActiveGpsFix: hasActiveGpsFix,
        isBusy: isBusy,
      );
    }
    final localizations = AppLocalizations.of(context);
    return UiQuickComposer(
      key: const ValueKey<String>('locations_quick_create_composer'),
      controller: quickCreateController,
      focusNode: quickCreateFocusNode,
      isCollapsibleOnCompact: false,
      maxLength: maxTdfTextLength,
      placeholder: localizations.quickCreateLocationHint,
      submitLabel: localizations.actionAdd,
      expandDraftLabel: localizations.actionOpenAsDraft,
      enabled: !isBusy,
      onExpandDraft: onExpandDraft,
      onSubmit: onSubmitQuickCreate,
    );
  }
}

/// Vertical header, composer/draft slot, and empty-state banner rendered inside [_LocationsHeaderSliver].
class _LocationsHeaderColumn extends StatelessWidget {
  /// Creates a [_LocationsHeaderColumn].
  const _LocationsHeaderColumn({
    required this.locationsCount,
    required this.backLabel,
    required this.isDraftOpen,
    required this.draftSeedTitle,
    required this.quickCreateController,
    required this.quickCreateFocusNode,
    required this.isBusy,
    required this.gap,
    required this.onBack,
    required this.onExpandDraft,
    required this.onSubmitQuickCreate,
  });

  /// Optional context-preserving Back button label (`U-UX-002`).
  final String? backLabel;

  /// Initial location name transferred from Quick-Create.
  final String draftSeedTitle;

  /// Vertical section spacing between header, composer, and list.
  final double gap;

  /// Whether an entity mutation is currently running.
  final bool isBusy;

  /// Whether the uncommitted Location Draft Card is open.
  final bool isDraftOpen;

  /// Total number of persisted locations.
  final int locationsCount;

  /// Callback restoring [ReturnContext] back to Tasks or Global Search.
  final VoidCallback onBack;

  /// Callback opening the uncommitted Location Draft Card.
  final VoidCallback onExpandDraft;

  /// Callback submitting Quick-Create.
  final VoidCallback onSubmitQuickCreate;

  /// Controller for the Quick-Create composer.
  final TextEditingController quickCreateController;

  /// Focus node for the Quick-Create composer.
  final FocusNode quickCreateFocusNode;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiPageHeader(
          title: localizations.drawerLocations,
          subtitle: localizations.locationsManagerSubtitle,
          countLabel: '$locationsCount',
          backLabel: backLabel,
          onBack: backLabel != null ? onBack : null,
        ),
        SizedBox(height: gap),
        _LocationsComposerSlot(
          isDraftOpen: isDraftOpen,
          draftSeedTitle: draftSeedTitle,
          quickCreateController: quickCreateController,
          quickCreateFocusNode: quickCreateFocusNode,
          isBusy: isBusy,
          onExpandDraft: onExpandDraft,
          onSubmitQuickCreate: onSubmitQuickCreate,
        ),
        SizedBox(height: gap),
        if (locationsCount == 0 && !isDraftOpen)
          UiBanner(
            key: const ValueKey<String>('locations_empty_banner'),
            variant: UiBannerVariant.emptyState,
            message: localizations.emptyLocationsHint,
          ),
      ],
    );
  }
}

/// Selective shell-state subscriber wiring header, busy flag, and draft state into [_LocationsHeaderColumn].
class _LocationsHeaderContent extends ConsumerWidget {
  /// Creates a [_LocationsHeaderContent].
  const _LocationsHeaderContent({
    required this.locationsCount,
    required this.quickCreateController,
    required this.quickCreateFocusNode,
    required this.onBack,
    required this.onExpandDraft,
    required this.onSubmitQuickCreate,
  });

  /// Total number of persisted locations.
  final int locationsCount;

  /// Callback restoring [ReturnContext] back to Tasks or Global Search.
  final VoidCallback onBack;

  /// Callback opening the uncommitted Location Draft Card.
  final VoidCallback onExpandDraft;

  /// Callback submitting Quick-Create.
  final VoidCallback onSubmitQuickCreate;

  /// Controller for the Quick-Create composer.
  final TextEditingController quickCreateController;

  /// Focus node for the Quick-Create composer.
  final FocusNode quickCreateFocusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final isDraftOpen = ref.watch(
      shellProvider.select(
        (shell) => shell.activeDraft == EntityDraftKind.location,
      ),
    );
    final returnContext = ref.watch(
      shellProvider.select((shell) => shell.returnContext),
    );
    final draftSeedTitle = ref.watch(
      shellProvider.select((shell) => shell.draftSeedTitle),
    );
    final isBusy = ref.watch(
      entityActionsProvider.select((state) => state.isBusy),
    );

    return _LocationsHeaderColumn(
      locationsCount: locationsCount,
      backLabel: _resolveBackLabel(returnContext, localizations),
      isDraftOpen: isDraftOpen,
      draftSeedTitle: draftSeedTitle,
      quickCreateController: quickCreateController,
      quickCreateFocusNode: quickCreateFocusNode,
      isBusy: isBusy,
      gap: tokens.spacing.space4,
      onBack: onBack,
      onExpandDraft: onExpandDraft,
      onSubmitQuickCreate: onSubmitQuickCreate,
    );
  }
}

/// Top padded sliver hosting [_LocationsHeaderContent] for [LocationsView].
class _LocationsHeaderSliver extends StatelessWidget {
  /// Creates a [_LocationsHeaderSliver].
  const _LocationsHeaderSliver({
    required this.locationsCount,
    required this.contentPadding,
    required this.quickCreateController,
    required this.quickCreateFocusNode,
    required this.onBack,
    required this.onExpandDraft,
    required this.onSubmitQuickCreate,
  });

  /// Responsive viewport content padding.
  final EdgeInsets contentPadding;

  /// Total number of persisted locations.
  final int locationsCount;

  /// Callback restoring [ReturnContext] back to Tasks or Global Search.
  final VoidCallback onBack;

  /// Callback opening the uncommitted Location Draft Card.
  final VoidCallback onExpandDraft;

  /// Callback submitting Quick-Create.
  final VoidCallback onSubmitQuickCreate;

  /// Controller for the Quick-Create composer.
  final TextEditingController quickCreateController;

  /// Focus node for the Quick-Create composer.
  final FocusNode quickCreateFocusNode;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        contentPadding.left,
        contentPadding.top,
        contentPadding.right,
        0.0,
      ),
      sliver: SliverToBoxAdapter(
        child: _LocationsHeaderContent(
          locationsCount: locationsCount,
          quickCreateController: quickCreateController,
          quickCreateFocusNode: quickCreateFocusNode,
          onBack: onBack,
          onExpandDraft: onExpandDraft,
          onSubmitQuickCreate: onSubmitQuickCreate,
        ),
      ),
    );
  }
}

/// Scrollable sliver viewport composing [_LocationsHeaderSliver] and [_LocationsCardListSliver].
class _LocationsScrollView extends StatelessWidget {
  /// Creates a [_LocationsScrollView].
  const _LocationsScrollView({
    required this.controller,
    required this.locations,
    required this.contentPadding,
    required this.quickCreateController,
    required this.quickCreateFocusNode,
    required this.cardKeyFor,
    required this.onBack,
    required this.onExpandDraft,
    required this.onSubmitQuickCreate,
  });

  /// Lookup returning the reveal [GlobalKey] for a location card.
  final GlobalKey Function(String locationId) cardKeyFor;

  /// Responsive viewport content padding.
  final EdgeInsets contentPadding;

  /// Active scroll controller for the Locations manager viewport.
  final ScrollController controller;

  /// Alphabetically sorted domain locations.
  final List<TdfLocation> locations;

  /// Callback restoring [ReturnContext] back to Tasks or Global Search.
  final VoidCallback onBack;

  /// Callback opening the uncommitted Location Draft Card.
  final VoidCallback onExpandDraft;

  /// Callback submitting Quick-Create.
  final VoidCallback onSubmitQuickCreate;

  /// Controller for the Quick-Create composer.
  final TextEditingController quickCreateController;

  /// Focus node for the Quick-Create composer.
  final FocusNode quickCreateFocusNode;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      slivers: <Widget>[
        _LocationsHeaderSliver(
          locationsCount: locations.length,
          contentPadding: contentPadding,
          quickCreateController: quickCreateController,
          quickCreateFocusNode: quickCreateFocusNode,
          onBack: onBack,
          onExpandDraft: onExpandDraft,
          onSubmitQuickCreate: onSubmitQuickCreate,
        ),
        _LocationsCardListSliver(
          locations: locations,
          contentPadding: contentPadding,
          cardKeyFor: cardKeyFor,
        ),
      ],
    );
  }
}

/// Manages Quick-Create composer state, card reveal keys, fallback scroll ownership, and view coordination for [LocationsView].
class _LocationsViewState extends ConsumerState<LocationsView>
    with EntityRevealScrollMixin<LocationsView> {
  final TextEditingController _quickCreateController = TextEditingController();
  final FocusNode _quickCreateFocusNode = FocusNode();

  @override
  ScrollController? get externalScrollController => widget.scrollController;

  @override
  double get revealAlignment => 0.12;

  @override
  EntityDraftKind get revealDraftKind => EntityDraftKind.location;

  @override
  EntityKind get revealEntityKind => EntityKind.location;

  @override
  void initState() {
    super.initState();
    initRevealScroll();
  }

  @override
  void didUpdateWidget(covariant LocationsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    handleScrollControllerSwap(oldWidget.scrollController);
  }

  @override
  void dispose() {
    disposeRevealScroll();
    _quickCreateController.dispose();
    _quickCreateFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    registerRevealShellListeners();
    final tokens = UiThemeTokens.of(context);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);
    final contentPadding = tokens.spacing.mainContentPadding(viewport);
    final locations = ref
        .watch(taskNotifierProvider.select(_selectLocationsBoardSlice))
        .locations;
    pruneOwnedCardKeys(locations.map((location) => location.id));

    return _LocationsScrollView(
      controller: effectiveScrollController,
      locations: locations,
      contentPadding: contentPadding,
      quickCreateController: _quickCreateController,
      quickCreateFocusNode: _quickCreateFocusNode,
      cardKeyFor: resolveRevealCardKey,
      onBack: _handleBackNavigation,
      onExpandDraft: _handleOpenDraft,
      onSubmitQuickCreate: _handleQuickCreateSubmit,
    );
  }

  @override
  List<String> collectVisibleEntityIds() {
    final locations =
        ref.read(taskNotifierProvider).asData?.value.sortedLocations ??
        const <TdfLocation>[];
    return <String>[for (final location in locations) location.id];
  }

  /// Restores the saved [ReturnContext] back to Tasks or Global Search.
  void _handleBackNavigation() {
    ref.read(shellProvider.notifier).navigateBackFromReturnContext();
  }

  /// Transfers Quick-Create text into an uncommitted Location Draft Card and clears the bar.
  void _handleOpenDraft() {
    final seedTitle = _quickCreateController.text.trim();
    _quickCreateController.clear();
    ref
        .read(shellProvider.notifier)
        .openDraft(EntityDraftKind.location, seedTitle: seedTitle);
    scrollToTop();
  }

  /// Quick-creates a location seeded from the active foreground GPS fix.
  void _handleQuickCreateSubmit() {
    unawaited(_submitQuickCreate());
  }

  /// Dispatches Quick-Create persistence through [EntityActionsNotifier.quickCreateLocation].
  Future<void> _submitQuickCreate() async {
    final isBusy = ref.read(entityActionsProvider).isBusy;
    if (isBusy) {
      return;
    }
    final result = await ref
        .read(entityActionsProvider.notifier)
        .quickCreateLocation(
          _quickCreateController.text,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        _quickCreateController.clear();
      case ActionValidationFailed(:final message, :final fieldErrors):
        if (!fieldErrors.containsKey('limit')) {
          ref
              .read(floatingNoticeProvider.notifier)
              .showNotice(message, tone: FloatingNoticeTone.danger);
        }
        _quickCreateFocusNode.requestFocus();
      case ActionPersistFailed(:final message):
        ref
            .read(floatingNoticeProvider.notifier)
            .showNotice(message, tone: FloatingNoticeTone.danger);
    }
  }
}

/// Resolves the localized Back button label from [returnContext], or `null` when absent.
String? _resolveBackLabel(
  ReturnContext? returnContext,
  AppLocalizations localizations,
) {
  return switch (returnContext) {
    final savedContext? =>
      savedContext.searchOpen
          ? localizations.actionBackToSearch
          : localizations.actionBackToTasks,
    null => null,
  };
}

/// Extracts value-compared sorted workspace locations from [boardAsync].
_LocationsBoardSlice _selectLocationsBoardSlice(
  AsyncValue<TaskBoard> boardAsync,
) {
  return _LocationsBoardSlice(
    boardAsync.asData?.value.sortedLocations ?? const <TdfLocation>[],
  );
}
