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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../presentation/app_shell_controller.dart';
import '../../presentation/entity_controller.dart';
import '../../presentation/entity_view_models.dart';
import '../../presentation/floating_notice_controller.dart';
import '../../presentation/shell_models.dart';
import 'location_card.dart';

/// Maximum Unicode scalar length for single-line location names.
const int _maxLocationNameLength = 500;

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

/// Lazy sliver list building expandable Location cards (`P-LAZY-LISTS`).
class _LocationsCardListSliver extends StatelessWidget {
  /// Creates a [_LocationsCardListSliver].
  const _LocationsCardListSliver({
    required this.locations,
    required this.contentPadding,
    required this.isBusy,
  });

  /// Responsive viewport content padding applied around the card list.
  final EdgeInsets contentPadding;

  /// Whether an entity mutation is currently running.
  final bool isBusy;

  /// Alphabetically sorted location card view models.
  final List<LocationCardViewModel> locations;

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
          child: _LocationsCardSliverItem(
            location: locations[index],
            isBusy: isBusy,
          ),
        ),
      ),
    );
  }
}

/// Per-card selective shell-state subscriber wiring one [LocationCardViewModel] to [LocationCard] (`P-SELECT-REBUILDS`).
class _LocationsCardSliverItem extends ConsumerWidget {
  /// Creates a [_LocationsCardSliverItem].
  const _LocationsCardSliverItem({
    required this.location,
    required this.isBusy,
  });

  /// Whether an entity mutation is currently running.
  final bool isBusy;

  /// Projected location view model for this card.
  final LocationCardViewModel location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationRef = EntityRef(kind: EntityKind.location, id: location.id);
    final isExpanded = ref.watch(
      appShellControllerProvider.select(
        (shell) => shell.expandedEntity == locationRef,
      ),
    );
    final activeInlineSection = ref.watch(
      appShellControllerProvider.select(
        (shell) => shell.activeInlineEdit?.entity == locationRef
            ? shell.activeInlineEdit?.sectionKey
            : null,
      ),
    );
    final isConfirmingDelete = ref.watch(
      appShellControllerProvider.select(
        (shell) => shell.activeDeleteConfirm == locationRef,
      ),
    );
    final shouldReveal = ref.watch(
      appShellControllerProvider.select(
        (shell) => shell.revealEntityRequest == locationRef,
      ),
    );

    return LocationCard(
      key: ValueKey<String>('location_card_${location.id}'),
      location: location,
      isExpanded: isExpanded,
      activeInlineSection: activeInlineSection,
      isConfirmingDelete: isConfirmingDelete,
      shouldReveal: shouldReveal,
      isBusy: isBusy,
    );
  }
}

/// Renders either the uncommitted Location Draft Card or the inline Quick-Create composer (`U-CARD-006`).
class _LocationsComposerSlot extends StatelessWidget {
  /// Creates a [_LocationsComposerSlot].
  const _LocationsComposerSlot({
    required this.isDraftOpen,
    required this.draftSeedTitle,
    required this.hasActiveGpsFix,
    required this.activeGpsLatitudeText,
    required this.activeGpsLongitudeText,
    required this.quickCreateController,
    required this.quickCreateFocusNode,
    required this.isBusy,
    required this.onExpandDraft,
    required this.onSubmitQuickCreate,
  });

  /// Active foreground GPS latitude formatted to 6 decimal places, if available.
  final String? activeGpsLatitudeText;

  /// Active foreground GPS longitude formatted to 6 decimal places, if available.
  final String? activeGpsLongitudeText;

  /// Initial location name transferred from Quick-Create.
  final String draftSeedTitle;

  /// Whether a valid foreground GPS fix is currently available.
  final bool hasActiveGpsFix;

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
  Widget build(BuildContext context) {
    if (isDraftOpen) {
      return LocationDraftCard(
        seedTitle: draftSeedTitle,
        hasActiveGpsFix: hasActiveGpsFix,
        activeGpsLatitudeText: activeGpsLatitudeText,
        activeGpsLongitudeText: activeGpsLongitudeText,
        isBusy: isBusy,
      );
    }
    final localizations = AppLocalizations.of(context);
    return UiQuickComposer(
      key: const ValueKey<String>('locations_quick_create_composer'),
      controller: quickCreateController,
      focusNode: quickCreateFocusNode,
      isCollapsibleOnCompact: false,
      maxLength: _maxLocationNameLength,
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
    required this.hasActiveGpsFix,
    required this.activeGpsLatitudeText,
    required this.activeGpsLongitudeText,
    required this.quickCreateController,
    required this.quickCreateFocusNode,
    required this.isBusy,
    required this.gap,
    required this.onBack,
    required this.onExpandDraft,
    required this.onSubmitQuickCreate,
  });

  /// Active foreground GPS latitude formatted to 6 decimal places, if available.
  final String? activeGpsLatitudeText;

  /// Active foreground GPS longitude formatted to 6 decimal places, if available.
  final String? activeGpsLongitudeText;

  /// Optional context-preserving Back button label (`U-UX-002`).
  final String? backLabel;

  /// Initial location name transferred from Quick-Create.
  final String draftSeedTitle;

  /// Vertical section spacing between header, composer, and list.
  final double gap;

  /// Whether a valid foreground GPS fix is currently available.
  final bool hasActiveGpsFix;

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
          hasActiveGpsFix: hasActiveGpsFix,
          activeGpsLatitudeText: activeGpsLatitudeText,
          activeGpsLongitudeText: activeGpsLongitudeText,
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

/// Selective shell-state subscriber wiring header and draft state into [_LocationsHeaderColumn].
class _LocationsHeaderContent extends ConsumerWidget {
  /// Creates a [_LocationsHeaderContent].
  const _LocationsHeaderContent({
    required this.viewModel,
    required this.quickCreateController,
    required this.quickCreateFocusNode,
    required this.isBusy,
    required this.onBack,
    required this.onExpandDraft,
    required this.onSubmitQuickCreate,
  });

  /// Whether an entity mutation is currently running.
  final bool isBusy;

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

  /// Projected Locations manager view model.
  final LocationsManagerViewModel viewModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final isDraftOpen = ref.watch(
      appShellControllerProvider.select(
        (shell) => shell.activeDraft == EntityDraftKind.location,
      ),
    );
    final returnContext = ref.watch(
      appShellControllerProvider.select((shell) => shell.returnContext),
    );
    final draftSeedTitle = ref.watch(
      appShellControllerProvider.select((shell) => shell.draftSeedTitle),
    );

    return _LocationsHeaderColumn(
      locationsCount: viewModel.locations.length,
      backLabel: _resolveBackLabel(returnContext, localizations),
      isDraftOpen: isDraftOpen,
      draftSeedTitle: draftSeedTitle,
      hasActiveGpsFix: viewModel.hasActiveGpsFix,
      activeGpsLatitudeText: viewModel.activeGpsLatitudeText,
      activeGpsLongitudeText: viewModel.activeGpsLongitudeText,
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
    required this.viewModel,
    required this.contentPadding,
    required this.quickCreateController,
    required this.quickCreateFocusNode,
    required this.isBusy,
    required this.onBack,
    required this.onExpandDraft,
    required this.onSubmitQuickCreate,
  });

  /// Responsive viewport content padding.
  final EdgeInsets contentPadding;

  /// Whether an entity mutation is currently running.
  final bool isBusy;

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

  /// Projected Locations manager view model.
  final LocationsManagerViewModel viewModel;

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
          viewModel: viewModel,
          quickCreateController: quickCreateController,
          quickCreateFocusNode: quickCreateFocusNode,
          isBusy: isBusy,
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
    required this.viewModel,
    required this.contentPadding,
    required this.quickCreateController,
    required this.quickCreateFocusNode,
    required this.isBusy,
    required this.onBack,
    required this.onExpandDraft,
    required this.onSubmitQuickCreate,
  });

  /// Responsive viewport content padding.
  final EdgeInsets contentPadding;

  /// Active scroll controller for the Locations manager viewport.
  final ScrollController controller;

  /// Whether an entity mutation is currently running.
  final bool isBusy;

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

  /// Projected Locations manager view model.
  final LocationsManagerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      slivers: <Widget>[
        _LocationsHeaderSliver(
          viewModel: viewModel,
          contentPadding: contentPadding,
          quickCreateController: quickCreateController,
          quickCreateFocusNode: quickCreateFocusNode,
          isBusy: isBusy,
          onBack: onBack,
          onExpandDraft: onExpandDraft,
          onSubmitQuickCreate: onSubmitQuickCreate,
        ),
        _LocationsCardListSliver(
          locations: viewModel.locations,
          contentPadding: contentPadding,
          isBusy: isBusy,
        ),
      ],
    );
  }
}

/// Manages Quick-Create composer state, fallback scroll ownership, and top-level view coordination for [LocationsView].
class _LocationsViewState extends ConsumerState<LocationsView> {
  final TextEditingController _quickCreateController = TextEditingController();
  final FocusNode _quickCreateFocusNode = FocusNode();

  ScrollController? _ownedScrollController;

  /// Active scroll controller, creating a private fallback only when caller omits [LocationsView.scrollController].
  ScrollController get _scrollController {
    if (widget.scrollController case final external?) {
      return external;
    }
    return _ownedScrollController ??= ScrollController();
  }

  @override
  void didUpdateWidget(covariant LocationsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController &&
        widget.scrollController != null &&
        _ownedScrollController != null) {
      _ownedScrollController?.dispose();
      _ownedScrollController = null;
    }
  }

  @override
  void dispose() {
    _ownedScrollController?.dispose();
    _quickCreateController.dispose();
    _quickCreateFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<EntityDraftKind?>(
      appShellControllerProvider.select((shell) => shell.activeDraft),
      _handleActiveDraftChanged,
    );

    final tokens = UiThemeTokens.of(context);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);
    final contentPadding = tokens.spacing.mainContentPadding(viewport);
    final viewModel = ref.watch(locationsManagerViewModelProvider);
    final isBusy = ref.watch(
      entityControllerProvider.select((state) => state.isBusy),
    );

    return _LocationsScrollView(
      controller: _scrollController,
      viewModel: viewModel,
      contentPadding: contentPadding,
      quickCreateController: _quickCreateController,
      quickCreateFocusNode: _quickCreateFocusNode,
      isBusy: isBusy,
      onBack: _handleBackNavigation,
      onExpandDraft: _handleOpenDraft,
      onSubmitQuickCreate: _handleQuickCreateSubmit,
    );
  }

  /// Scrolls back to the top when a location draft card transitions open.
  void _handleActiveDraftChanged(
    EntityDraftKind? previous,
    EntityDraftKind? next,
  ) {
    if (previous != EntityDraftKind.location &&
        next == EntityDraftKind.location) {
      _scrollToTop();
    }
  }

  /// Restores the saved [ReturnContext] back to Tasks or Global Search.
  void _handleBackNavigation() {
    ref
        .read(appShellControllerProvider.notifier)
        .navigateBackFromReturnContext();
  }

  /// Transfers Quick-Create text into an uncommitted Location Draft Card and clears the bar.
  void _handleOpenDraft() {
    final seedTitle = _quickCreateController.text.trim();
    _quickCreateController.clear();
    ref
        .read(appShellControllerProvider.notifier)
        .openDraft(EntityDraftKind.location, seedTitle: seedTitle);
    _scrollToTop();
  }

  /// Quick-creates a location seeded from the active foreground GPS fix.
  void _handleQuickCreateSubmit() {
    unawaited(_submitQuickCreate());
  }

  /// Scrolls smoothly back to the top of the manager view when opening a Draft Card.
  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      if (_scrollController.offset <= 0.0) {
        return;
      }
      unawaited(
        _scrollController.animateTo(
          0.0,
          duration: UiThemeTokens.of(context).focus.expandDuration,
          curve: Curves.easeOut,
        ),
      );
    });
  }

  /// Dispatches Quick-Create persistence through [EntityController.quickCreateLocation].
  Future<void> _submitQuickCreate() async {
    final isBusy = ref.read(entityControllerProvider).isBusy;
    if (isBusy) {
      return;
    }
    final result = await ref
        .read(entityControllerProvider.notifier)
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
              .read(floatingNoticeControllerProvider.notifier)
              .showNotice(message, tone: NoticeTone.danger);
        }
        _quickCreateFocusNode.requestFocus();
      case ActionPersistFailed(:final message):
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(message, tone: NoticeTone.danger);
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
