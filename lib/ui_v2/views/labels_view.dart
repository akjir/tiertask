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
import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../presentation/app_shell_controller.dart';
import '../../presentation/board_v2_view_models.dart';
import '../../presentation/entity_v2_controller.dart';
import '../../presentation/floating_notice_controller.dart';
import '../../presentation/task_v2_controller.dart';
import '../../presentation/ui_telemetry.dart';
import '../../presentation/ui_v2_shell_models.dart';
import 'entity_section_widgets.dart';

/// Estimated collapsed card height used to materialize offscreen targets before smooth reveal.
const double _estimatedCardExtent = 84.0;

/// Leading rounded-square color dot size inside expanded and collapsed Label card headers (`U-CARD-001`).
const double _labelColorDotSize = 12.0;

/// Maximum reference links permitted per label (`TDF 0.8.0`).
const int _maxLinksPerLabel = 20;

/// Maximum note character length (`maxTdfNoteLength`).
const int _maxNoteLength = 2000;

/// Maximum single-line text length (`maxTdfTextLength`).
const int _maxSingleLineLength = 500;

/// Duration for smooth scroll-to-card reveals (`U-CARD-001`).
const Duration _revealScrollDuration = Duration(milliseconds: 220);

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

/// Coordinates Quick-Create, scroll reveal, and draft lifecycle for [LabelsView].
class _LabelsViewState extends ConsumerState<LabelsView> {
  final Map<String, GlobalKey> _cardKeys = <String, GlobalKey>{};
  late final TextEditingController _quickCreateController;
  late final FocusNode _quickCreateFocusNode;

  bool _isQuickCreating = false;
  ScrollController? _ownedScrollController;
  String? _pendingRevealLabelId;
  String? _quickCreateError;

  /// Effective scroll controller shared with the primary [CustomScrollView].
  ScrollController get _effectiveScrollController {
    if (widget.scrollController case final external?) {
      return external;
    }
    return _ownedScrollController ??= ScrollController();
  }

  @override
  void initState() {
    super.initState();
    _quickCreateController = TextEditingController()
      ..addListener(_handleQuickCreateTextChanged);
    _quickCreateFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _scheduleReveal(ref.read(appShellControllerProvider).revealEntityRequest);
    });
  }

  @override
  void didUpdateWidget(covariant LabelsView oldWidget) {
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
    _quickCreateController
      ..removeListener(_handleQuickCreateTextChanged)
      ..dispose();
    _quickCreateFocusNode.dispose();
    _ownedScrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _registerShellListeners();
    final viewModel = ref.watch(labelsManagerViewModelProvider);
    final returnContext = ref.watch(
      appShellControllerProvider.select((shell) => shell.returnContext),
    );
    final activeDraft = ref.watch(
      appShellControllerProvider.select((shell) => shell.activeDraft),
    );
    final draftSeedTitle = ref.watch(
      appShellControllerProvider.select((shell) => shell.draftSeedTitle),
    );
    final isBusy = ref.watch(
      entityV2ControllerProvider.select((state) => state.isBusy),
    );
    _pruneCardKeys(viewModel.labels);

    return _LabelsScrollBody(
      scrollController: _effectiveScrollController,
      viewModel: viewModel,
      returnContext: returnContext,
      isDraftOpen: activeDraft == EntityDraftKind.label,
      draftSeedTitle: draftSeedTitle,
      isQuickCreateBusy: isBusy || _isQuickCreating,
      quickCreateController: _quickCreateController,
      quickCreateFocusNode: _quickCreateFocusNode,
      quickCreateError: _quickCreateError,
      cardKeyFor: _cardKeyFor,
      onBack: _handleBack,
      onExpandDraft: _handleExpandDraft,
      onQuickCreateSubmit: _handleQuickCreateSubmit,
      onCancelDraft: _handleCancelDraft,
    );
  }

  /// Returns a stable [GlobalKey] mapped to [labelId] for smooth reveal scrolling.
  GlobalKey _cardKeyFor(String labelId) =>
      _cardKeys.putIfAbsent(labelId, GlobalKey.new);

  /// Restores saved task or search context via `AppShellController`.
  void _handleBack() {
    ref
        .read(appShellControllerProvider.notifier)
        .navigateBackFromReturnContext();
  }

  /// Cancels the active uncommitted Label Draft Card.
  void _handleCancelDraft() {
    ref.read(appShellControllerProvider.notifier).cancelDraft();
  }

  /// Transfers any typed Quick-Create name into an uncommitted Label Draft Card (`U-CARD-006`).
  void _handleExpandDraft() {
    final seedTitle = _quickCreateController.text.trim();
    _quickCreateController.clear();
    if (_quickCreateError != null) {
      setState(() => _quickCreateError = null);
    }
    ref
        .read(appShellControllerProvider.notifier)
        .openDraft(EntityDraftKind.label, seedTitle: seedTitle);
  }

  /// Submits Quick-Create text to `EntityV2Controller.quickCreateLabel` and clears input only on success.
  Future<void> _handleQuickCreateSubmit() async {
    if (_isQuickCreating) {
      return;
    }
    setState(() {
      _isQuickCreating = true;
      _quickCreateError = null;
    });
    final locale = Localizations.localeOf(context);
    final result = await ref
        .read(entityV2ControllerProvider.notifier)
        .quickCreateLabel(_quickCreateController.text, locale: locale);
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        _quickCreateController.clear();
        setState(() {
          _isQuickCreating = false;
          _quickCreateError = null;
        });
      case V2ActionValidationFailed(:final message):
        setState(() {
          _isQuickCreating = false;
          _quickCreateError = message;
        });
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isQuickCreating = false;
          _quickCreateError = message;
        });
    }
  }

  /// Clears transient inline Quick-Create validation errors when the user edits the input.
  void _handleQuickCreateTextChanged() {
    if (_quickCreateError != null && mounted) {
      setState(() => _quickCreateError = null);
    }
  }

  /// Executes smooth `Scrollable.ensureVisible` to [labelId], pre-scrolling if offscreen in the lazy list.
  Future<void> _performReveal(String labelId) async {
    final targetContext = _cardKeys[labelId]?.currentContext;
    if (targetContext != null) {
      _pendingRevealLabelId = null;
      ref.read(appShellControllerProvider.notifier).clearRevealRequest();
      await Scrollable.ensureVisible(
        targetContext,
        duration: _revealScrollDuration,
        curve: Curves.easeOut,
        alignment: 0.15,
      );
      return;
    }

    final labels = ref.read(labelsManagerViewModelProvider).labels;
    final targetIndex = labels.indexWhere((label) => label.id == labelId);
    final controller = _effectiveScrollController;
    if (targetIndex < 0 || !controller.hasClients) {
      _pendingRevealLabelId = null;
      ref.read(appShellControllerProvider.notifier).clearRevealRequest();
      return;
    }

    final estimatedOffset = (targetIndex * _estimatedCardExtent).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    controller.jumpTo(estimatedOffset);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _revealMaterializedCard(labelId),
    );
  }

  /// Removes card [GlobalKey] entries for labels no longer present on the board.
  void _pruneCardKeys(List<LabelCardViewModel> labels) {
    if (_cardKeys.isEmpty) {
      return;
    }
    final activeIds = <String>{for (final label in labels) label.id};
    _cardKeys.removeWhere((id, _) => !activeIds.contains(id));
  }

  /// Registers Riverpod listeners coordinating smooth card reveal and draft scroll-to-top behavior.
  void _registerShellListeners() {
    ref.listen<EntityRef?>(
      appShellControllerProvider.select((shell) => shell.revealEntityRequest),
      (previous, next) {
        _scheduleReveal(next);
      },
    );
    ref.listen<EntityDraftKind?>(
      appShellControllerProvider.select((shell) => shell.activeDraft),
      (previous, next) {
        if (next == EntityDraftKind.label &&
            previous != EntityDraftKind.label) {
          _scrollToTop();
        }
      },
    );
  }

  /// Completes smooth reveal after an offscreen card materializes in the sliver viewport.
  void _revealMaterializedCard(String labelId) {
    if (!mounted) {
      return;
    }
    _pendingRevealLabelId = null;
    ref.read(appShellControllerProvider.notifier).clearRevealRequest();
    final materializedContext = _cardKeys[labelId]?.currentContext;
    if (materializedContext == null) {
      return;
    }
    unawaited(
      Scrollable.ensureVisible(
        materializedContext,
        duration: _revealScrollDuration,
        curve: Curves.easeOut,
        alignment: 0.15,
      ),
    );
  }

  /// Schedules a post-frame reveal scroll when [request] targets a label card.
  void _scheduleReveal(EntityRef? request) {
    if (request == null ||
        request.kind != EntityKind.label ||
        _pendingRevealLabelId == request.id) {
      return;
    }
    _pendingRevealLabelId = request.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_performReveal(request.id));
    });
  }

  /// Scrolls the view smoothly back to offset `0.0` when opening an uncommitted Draft Card (`U-CARD-006`).
  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final controller = _effectiveScrollController;
      if (controller.hasClients && controller.offset > 0.0) {
        unawaited(
          controller.animateTo(
            0.0,
            duration: _revealScrollDuration,
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }
}

/// Primary [CustomScrollView] housing the Labels header, Quick-Create or Draft Card, empty state, and lazy label cards.
class _LabelsScrollBody extends StatelessWidget {
  /// Creates a [_LabelsScrollBody].
  const _LabelsScrollBody({
    required this.scrollController,
    required this.viewModel,
    required this.returnContext,
    required this.isDraftOpen,
    required this.draftSeedTitle,
    required this.isQuickCreateBusy,
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

  /// Seeded name transferred into an open Label Draft Card.
  final String draftSeedTitle;

  /// Whether an uncommitted Label Draft Card currently replaces the Quick-Create bar.
  final bool isDraftOpen;

  /// Whether Quick-Create submissions are disabled while busy.
  final bool isQuickCreateBusy;

  /// Back navigation callback wired when [returnContext] is active.
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

  /// Saved originating task or search context for context-preserving Back navigation.
  final ReturnContext? returnContext;

  /// Scroll controller driving the outer [CustomScrollView].
  final ScrollController scrollController;

  /// Live model-free Labels manager projection.
  final LabelsManagerViewModel viewModel;

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
            viewModel: viewModel,
            returnContext: returnContext,
            isDraftOpen: isDraftOpen,
            draftSeedTitle: draftSeedTitle,
            isQuickCreateBusy: isQuickCreateBusy,
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
          showEmptyState: viewModel.labels.isEmpty && !isDraftOpen,
          viewModel: viewModel,
          cardKeyFor: cardKeyFor,
        ),
      ],
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
    required this.viewModel,
    required this.cardKeyFor,
  });

  /// Lookup returning the reveal [GlobalKey] for a label card.
  final GlobalKey Function(String labelId) cardKeyFor;

  /// Outer padding applied around the empty state or label card list.
  final EdgeInsets padding;

  /// Whether to render the plain-text empty-state banner instead of label cards.
  final bool showEmptyState;

  /// Live model-free Labels manager projection.
  final LabelsManagerViewModel viewModel;

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
              itemCount: viewModel.labels.length,
              itemBuilder: (context, index) => _LabelListSlot(
                cardScrollKey: cardKeyFor(viewModel.labels[index].id),
                label: viewModel.labels[index],
                allLocations: viewModel.allLocations,
                bottomGap: index + 1 < viewModel.labels.length
                    ? tokens.spacing.cardListGap
                    : 0.0,
              ),
            ),
    );
  }
}

/// Spaced lazy list slot hosting one [_LabelEntityCard].
class _LabelListSlot extends StatelessWidget {
  /// Creates a [_LabelListSlot].
  const _LabelListSlot({
    required this.cardScrollKey,
    required this.label,
    required this.allLocations,
    required this.bottomGap,
  });

  /// Saved workspace locations forwarded to Activation Conditions.
  final List<LocationOptionViewModel> allLocations;

  /// Bottom gap between sibling cards (`cardListGap` or `0.0` on final card).
  final double bottomGap;

  /// [GlobalKey] attached around the card for smooth reveal scrolling.
  final GlobalKey cardScrollKey;

  /// Label card view model.
  final LabelCardViewModel label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: _LabelEntityCard(
        cardScrollKey: cardScrollKey,
        label: label,
        allLocations: allLocations,
      ),
    );
  }
}

/// Top header plus Quick-Create bar or uncommitted Label Draft Card inside [_LabelsScrollBody].
class _LabelsHeaderContent extends StatelessWidget {
  /// Creates a [_LabelsHeaderContent].
  const _LabelsHeaderContent({
    required this.viewModel,
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

  /// Live model-free Labels manager projection.
  final LabelsManagerViewModel viewModel;

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
          countLabel: '${viewModel.labels.length}',
        ),
        SizedBox(height: tokens.spacing.space4),
        if (isDraftOpen)
          _LabelDraftCard(
            seedTitle: draftSeedTitle,
            initialColorHex: viewModel.nextPresetColorHex,
            allLocations: viewModel.allLocations,
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
          maxLength: _maxSingleLineLength,
          placeholder: localizations.quickCreateLabelHint,
          submitLabel: '+ ${localizations.actionAdd}',
          expandDraftLabel: localizations.actionOpenAsDraft,
          enabled: enabled,
          onExpandDraft: onExpandDraft,
          onSubmit: onSubmit,
        ),
        if (error != null && error.isNotEmpty) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          _LabelsErrorText(message: error),
        ],
      ],
    );
  }
}

/// Accent-bordered uncommitted Label Draft Card replacing the Quick-Create bar in place (`U-CARD-006`).
class _LabelDraftCard extends ConsumerStatefulWidget {
  /// Creates a [_LabelDraftCard].
  const _LabelDraftCard({
    required this.seedTitle,
    required this.initialColorHex,
    required this.allLocations,
    required this.onCancel,
  });

  /// Saved workspace locations selectable in draft GPS conditions.
  final List<LocationOptionViewModel> allLocations;

  /// Rotating preset `#RRGGBB` color seeding [UiColorWheel].
  final String initialColorHex;

  /// Callback discarding the draft without mutating the board.
  final VoidCallback onCancel;

  /// Initial label name transferred from Quick-Create.
  final String seedTitle;

  @override
  ConsumerState<_LabelDraftCard> createState() => _LabelDraftCardState();
}

/// Manages uncommitted form state for [_LabelDraftCard].
class _LabelDraftCardState extends ConsumerState<_LabelDraftCard> {
  late final TextEditingController _linkTitleController;
  late final TextEditingController _linkUriController;
  late final TextEditingController _nameController;
  late final TextEditingController _noteController;
  late final TextEditingController _timeEndController;
  late final TextEditingController _timeStartController;

  ConditionDraftViewModel _conditionDraft = ConditionDraftViewModel();
  List<EntityLinkViewModel> _draftLinks = const <EntityLinkViewModel>[];
  int? _editingLinkIndex;
  Map<String, String> _fieldErrors = const <String, String>{};
  String? _generalError;
  bool _isScoped = false;
  bool _isSubmitting = false;
  String? _linkInputError;
  late Color _selectedColor;
  bool _showConditions = false;
  bool _showLinks = false;
  bool _showNote = false;
  String? _timeInputError;

  /// Bundled draft activation conditions state and callbacks.
  _LabelDraftConditionsData get _conditionsData => _LabelDraftConditionsData(
    draft: _conditionDraft,
    allLocations: widget.allLocations,
    timeStartController: _timeStartController,
    timeEndController: _timeEndController,
    timeInputError: _timeInputError,
    onToggleWeekday: _handleToggleWeekday,
    onAddTimeWindow: _handleAddTimeWindow,
    onRemoveTimeWindow: _handleRemoveTimeWindow,
    onToggleLocation: _handleToggleLocation,
  );

  /// Bundled draft reference links state and callbacks.
  _LabelDraftLinksData get _linksData => _LabelDraftLinksData(
    links: _draftLinks,
    editingIndex: _editingLinkIndex,
    titleController: _linkTitleController,
    uriController: _linkUriController,
    inputError: _linkInputError,
    onReorder: _handleReorderLink,
    onEdit: _handleStartLinkEdit,
    onDelete: _handleDeleteLink,
    onInputChanged: _handleLinkInputChanged,
    onCommitLink: _handleCommitLinkInput,
    onCancelRowEdit: _handleCancelLinkEdit,
  );

  /// Bundled always-visible draft Name, Color, and Board Scope state and callbacks.
  _LabelDraftPrimaryData get _primaryData => _LabelDraftPrimaryData(
    nameController: _nameController,
    nameError: _fieldErrors['name'],
    selectedColor: _selectedColor,
    isScoped: _isScoped,
    onNameChanged: (_) => _clearFieldError('name'),
    onSubmitFromField: _handleSubmit,
    onColorChanged: _handleColorChanged,
    onScopeChanged: _handleScopeChanged,
  );

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.seedTitle);
    _noteController = TextEditingController();
    _linkTitleController = TextEditingController();
    _linkUriController = TextEditingController();
    _timeStartController = TextEditingController();
    _timeEndController = TextEditingController();
    _selectedColor =
        UiColorWheel.tryParseHex(widget.initialColorHex) ??
        UiColorWheel.canonicalPresets.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _linkTitleController.dispose();
    _linkUriController.dispose();
    _timeStartController.dispose();
    _timeEndController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isBusy =
        _isSubmitting ||
        ref.watch(entityV2ControllerProvider.select((state) => state.isBusy));

    return UiCard.draft(
      key: const ValueKey<String>('label_draft_card'),
      title: localizations.draftNewLabelTitle,
      subtitle: localizations.draftUncommittedHint,
      closeTooltip: localizations.actionCancel,
      onClose: isBusy ? null : widget.onCancel,
      errorText: _generalError,
      footer: _LabelDraftFooter(
        isBusy: isBusy,
        onCancel: widget.onCancel,
        onSubmit: _handleSubmit,
      ),
      child: _LabelDraftBody(
        primaryData: _primaryData,
        showNote: _showNote,
        noteController: _noteController,
        noteError: _fieldErrors['note'],
        onNoteChanged: (_) => _clearFieldError('note'),
        showLinks: _showLinks,
        linksData: _linksData,
        showConditions: _showConditions,
        conditionsData: _conditionsData,
        isBusy: isBusy,
        onRevealSection: _handleRevealSection,
      ),
    );
  }

  /// Applies [result] from `createLabelDraft` to busy and error state.
  void _applySubmitResult(V2ActionResult result) {
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message, :final fieldErrors):
        setState(() {
          _isSubmitting = false;
          _fieldErrors = fieldErrors;
          _generalError = _resolveDraftBannerError(
            message,
            fieldErrors,
            showNote: _showNote,
          );
        });
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _generalError = message;
        });
    }
  }

  /// Builds the immutable [LabelDraftInput] snapshot from active form state.
  LabelDraftInput _buildDraftInput() {
    final hasDraftConditions =
        _showConditions &&
        (_conditionDraft.selectedWeekdays.isNotEmpty ||
            _conditionDraft.timeWindows.isNotEmpty ||
            _conditionDraft.selectedLocationIds.isNotEmpty);
    return LabelDraftInput(
      name: _nameController.text,
      colorHex: UiColorWheel.formatHex(_selectedColor),
      isScoped: _isScoped,
      note: _showNote ? _noteController.text : '',
      links: _showLinks ? _draftLinks : const <EntityLinkViewModel>[],
      conditionDraft: hasDraftConditions ? _conditionDraft : null,
    );
  }

  /// Clears a single per-field validation error and any banner-level fallback error.
  void _clearFieldError(String fieldKey) {
    if (!_fieldErrors.containsKey(fieldKey) && _generalError == null) {
      return;
    }
    final nextErrors = Map<String, String>.of(_fieldErrors)..remove(fieldKey);
    setState(() {
      _fieldErrors = nextErrors;
      _generalError = null;
    });
  }

  /// Commits any typed pending link or time-window inputs before submitting the draft.
  bool _flushPendingSubInputs() {
    final hasPendingLink =
        _showLinks &&
        (_linkTitleController.text.trim().isNotEmpty ||
            _linkUriController.text.trim().isNotEmpty);
    if (hasPendingLink && !_handleCommitLinkInput()) {
      return false;
    }
    final hasPendingTime =
        _showConditions &&
        (_timeStartController.text.trim().isNotEmpty ||
            _timeEndController.text.trim().isNotEmpty);
    if (hasPendingTime && !_handleAddTimeWindow()) {
      return false;
    }
    return true;
  }

  /// Validates and appends a `HH:MM`..`HH:MM` daily time window into [_conditionDraft].
  bool _handleAddTimeWindow() {
    final localizations = AppLocalizations.of(context);
    final startToken = _timeStartController.text.trim();
    final endToken = _timeEndController.text.trim();
    final startMinutes = _parseDraftTimeMinutes(startToken);
    final endMinutes = _parseDraftTimeMinutes(endToken);
    if (startMinutes == null ||
        endMinutes == null ||
        startMinutes == endMinutes) {
      setState(() => _timeInputError = localizations.conditionTimeErrorInvalid);
      return false;
    }
    final nextWindows = <TimeWindowDraftViewModel>[
      ..._conditionDraft.timeWindows,
      TimeWindowDraftViewModel(start: startToken, end: endToken),
    ];
    setState(() {
      _conditionDraft = _conditionDraft.copyWith(timeWindows: nextWindows);
      _timeStartController.clear();
      _timeEndController.clear();
      _timeInputError = null;
      _generalError = null;
    });
    return true;
  }

  /// Cancels an in-progress draft link row update.
  void _handleCancelLinkEdit() {
    setState(() {
      _editingLinkIndex = null;
      _linkTitleController.clear();
      _linkUriController.clear();
      _linkInputError = null;
    });
  }

  /// Updates [_selectedColor] and clears any prior color error.
  void _handleColorChanged(Color color) {
    setState(() {
      _selectedColor = color;
      _generalError = null;
    });
    _clearFieldError('color');
  }

  /// Validates and inserts or updates the typed draft link row.
  bool _handleCommitLinkInput() {
    final editingIndex = _editingLinkIndex;
    final error = TaskV2Controller.validateLinkInput(
      rawTitle: _linkTitleController.text,
      rawUri: _linkUriController.text,
      currentCount: _draftLinks.length,
      isEditingExisting: editingIndex != null,
      isLabel: true,
      locale: Localizations.localeOf(context),
    );
    if (error != null) {
      setState(() => _linkInputError = error);
      return false;
    }
    final entry = EntityLinkViewModel(
      title: _linkTitleController.text.trim(),
      uri: _linkUriController.text.trim(),
    );
    final nextLinks = List<EntityLinkViewModel>.of(_draftLinks);
    if (editingIndex != null &&
        editingIndex >= 0 &&
        editingIndex < nextLinks.length) {
      nextLinks[editingIndex] = entry;
    } else {
      nextLinks.add(entry);
    }
    setState(() {
      _draftLinks = nextLinks;
      _editingLinkIndex = null;
      _linkTitleController.clear();
      _linkUriController.clear();
      _linkInputError = null;
      _generalError = null;
    });
    return true;
  }

  /// Deletes the draft link row at [index].
  void _handleDeleteLink(EntityLinkViewModel link, int index) {
    if (index < 0 || index >= _draftLinks.length) {
      return;
    }
    final nextLinks = List<EntityLinkViewModel>.of(_draftLinks)
      ..removeAt(index);
    int? nextEditing = _editingLinkIndex;
    if (nextEditing == index) {
      nextEditing = null;
      _linkTitleController.clear();
      _linkUriController.clear();
    } else if (nextEditing != null && nextEditing > index) {
      nextEditing -= 1;
    }
    setState(() {
      _draftLinks = nextLinks;
      _editingLinkIndex = nextEditing;
      _linkInputError = null;
    });
  }

  /// Clears inline draft link errors while editing link text fields.
  void _handleLinkInputChanged(String value) {
    if (_linkInputError != null) {
      setState(() => _linkInputError = null);
    }
  }

  /// Removes the draft time window at [index].
  void _handleRemoveTimeWindow(TimeWindowDraftViewModel window, int index) {
    if (index < 0 || index >= _conditionDraft.timeWindows.length) {
      return;
    }
    final nextWindows = List<TimeWindowDraftViewModel>.of(
      _conditionDraft.timeWindows,
    )..removeAt(index);
    setState(() {
      _conditionDraft = _conditionDraft.copyWith(timeWindows: nextWindows);
      _generalError = null;
    });
  }

  /// Moves a draft link row from [oldIndex] to [newIndex].
  void _handleReorderLink(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _draftLinks.length ||
        newIndex < 0 ||
        newIndex >= _draftLinks.length ||
        oldIndex == newIndex) {
      return;
    }
    final nextLinks = List<EntityLinkViewModel>.of(_draftLinks);
    final moved = nextLinks.removeAt(oldIndex);
    nextLinks.insert(newIndex, moved);
    int? nextEditing = _editingLinkIndex;
    if (nextEditing == oldIndex) {
      nextEditing = newIndex;
    } else if (nextEditing == newIndex) {
      nextEditing = oldIndex;
    }
    setState(() {
      _draftLinks = nextLinks;
      _editingLinkIndex = nextEditing;
    });
  }

  /// Opens one optional draft [section] (`note`, `links`, or `conditions`).
  void _handleRevealSection(LabelSectionKind section) {
    setState(() {
      switch (section) {
        case LabelSectionKind.note:
          _showNote = true;
        case LabelSectionKind.links:
          _showLinks = true;
        case LabelSectionKind.conditions:
          _showConditions = true;
        case LabelSectionKind.color:
        case LabelSectionKind.title:
          break;
      }
    });
  }

  /// Updates draft Board Scope selection (`Global Context` vs `Scoped Queue`).
  void _handleScopeChanged(bool nextScoped) {
    setState(() => _isScoped = nextScoped);
  }

  /// Loads draft [link] at [index] into the inline link inputs.
  void _handleStartLinkEdit(EntityLinkViewModel link, int index) {
    setState(() {
      _editingLinkIndex = index;
      _linkTitleController.text = link.title;
      _linkUriController.text = link.uri;
      _linkInputError = null;
    });
  }

  /// Validates pending sub-inputs and commits the full [LabelDraftInput] via `EntityV2Controller`.
  Future<void> _handleSubmit() async {
    if (_isSubmitting || !_flushPendingSubInputs()) {
      return;
    }
    final input = _buildDraftInput();
    setState(() {
      _isSubmitting = true;
      _fieldErrors = const <String, String>{};
      _generalError = null;
    });
    final result = await ref
        .read(entityV2ControllerProvider.notifier)
        .createLabelDraft(input, locale: Localizations.localeOf(context));
    _applySubmitResult(result);
  }

  /// Toggles [locationId] inside draft GPS location conditions.
  void _handleToggleLocation(String locationId) {
    final nextIds = List<String>.of(_conditionDraft.selectedLocationIds);
    if (!nextIds.remove(locationId)) {
      nextIds.add(locationId);
    }
    setState(() {
      _conditionDraft = _conditionDraft.copyWith(selectedLocationIds: nextIds);
      _generalError = null;
    });
  }

  /// Toggles ISO weekday [isoWeekday] (`1..7`) inside draft weekday conditions.
  void _handleToggleWeekday(int isoWeekday) {
    final nextDays = List<int>.of(_conditionDraft.selectedWeekdays);
    if (!nextDays.remove(isoWeekday)) {
      nextDays.add(isoWeekday);
      nextDays.sort();
    }
    setState(() {
      _conditionDraft = _conditionDraft.copyWith(selectedWeekdays: nextDays);
      _generalError = null;
    });
  }
}

/// Immutable bundle of Name, Color, and Board Scope form state inside [_LabelDraftCard].
@immutable
class _LabelDraftPrimaryData {
  /// Creates a [_LabelDraftPrimaryData].
  const _LabelDraftPrimaryData({
    required this.nameController,
    required this.nameError,
    required this.selectedColor,
    required this.isScoped,
    required this.onNameChanged,
    required this.onSubmitFromField,
    required this.onColorChanged,
    required this.onScopeChanged,
  });

  /// Draft Board Scope selection.
  final bool isScoped;

  /// Draft label name controller.
  final TextEditingController nameController;

  /// Optional inline validation error for label name.
  final String? nameError;

  /// Callback updating the draft color.
  final ValueChanged<Color> onColorChanged;

  /// Callback clearing name errors when typing.
  final ValueChanged<String> onNameChanged;

  /// Callback toggling draft Board Scope.
  final ValueChanged<bool> onScopeChanged;

  /// Callback submitting on Enter in the Name field.
  final Future<void> Function() onSubmitFromField;

  /// Currently selected draft color.
  final Color selectedColor;
}

/// Immutable bundle of draft Reference Links state and callbacks inside [_LabelDraftCard].
@immutable
class _LabelDraftLinksData {
  /// Creates a [_LabelDraftLinksData].
  const _LabelDraftLinksData({
    required this.links,
    required this.editingIndex,
    required this.titleController,
    required this.uriController,
    required this.inputError,
    required this.onReorder,
    required this.onEdit,
    required this.onDelete,
    required this.onInputChanged,
    required this.onCommitLink,
    required this.onCancelRowEdit,
  });

  /// Row index currently being edited, if any.
  final int? editingIndex;

  /// Optional link input validation error text.
  final String? inputError;

  /// Current draft links list.
  final List<EntityLinkViewModel> links;

  /// Callback cancelling an active link row edit.
  final VoidCallback onCancelRowEdit;

  /// Callback committing the typed link row.
  final VoidCallback onCommitLink;

  /// Callback deleting a draft link row.
  final UiOrderedItemActionCallback<EntityLinkViewModel> onDelete;

  /// Callback starting inline edit on a draft link row.
  final UiOrderedItemActionCallback<EntityLinkViewModel> onEdit;

  /// Callback clearing input errors when typing.
  final ValueChanged<String> onInputChanged;

  /// Callback reordering draft link rows.
  final UiOrderedItemReorderCallback onReorder;

  /// Link title text controller.
  final TextEditingController titleController;

  /// Link URI text controller.
  final TextEditingController uriController;
}

/// Immutable bundle of draft Activation Conditions state and callbacks inside [_LabelDraftCard].
@immutable
class _LabelDraftConditionsData {
  /// Creates a [_LabelDraftConditionsData].
  const _LabelDraftConditionsData({
    required this.draft,
    required this.allLocations,
    required this.timeStartController,
    required this.timeEndController,
    required this.timeInputError,
    required this.onToggleWeekday,
    required this.onAddTimeWindow,
    required this.onRemoveTimeWindow,
    required this.onToggleLocation,
  });

  /// Saved workspace locations selectable in draft GPS conditions.
  final List<LocationOptionViewModel> allLocations;

  /// Current editable condition draft.
  final ConditionDraftViewModel draft;

  /// Callback adding a typed `HH:MM`..`HH:MM` time window.
  final VoidCallback onAddTimeWindow;

  /// Callback removing a draft time window row.
  final UiOrderedItemActionCallback<TimeWindowDraftViewModel>
  onRemoveTimeWindow;

  /// Callback toggling a draft GPS location condition.
  final ValueChanged<String> onToggleLocation;

  /// Callback toggling a draft weekday condition.
  final ValueChanged<int> onToggleWeekday;

  /// End `HH:MM` controller.
  final TextEditingController timeEndController;

  /// Optional inline time window validation error text.
  final String? timeInputError;

  /// Start `HH:MM` controller.
  final TextEditingController timeStartController;
}

/// Vertical body container stacking primary draft fields, optional sections, and `+ Add` chips inside [_LabelDraftCard].
class _LabelDraftBody extends StatelessWidget {
  /// Creates a [_LabelDraftBody].
  const _LabelDraftBody({
    required this.primaryData,
    required this.showNote,
    required this.noteController,
    required this.noteError,
    required this.onNoteChanged,
    required this.showLinks,
    required this.linksData,
    required this.showConditions,
    required this.conditionsData,
    required this.isBusy,
    required this.onRevealSection,
  });

  /// Bundled draft conditions state and callbacks.
  final _LabelDraftConditionsData conditionsData;

  /// Disables all draft controls while submitting.
  final bool isBusy;

  /// Bundled draft links state and callbacks.
  final _LabelDraftLinksData linksData;

  /// Draft note controller.
  final TextEditingController noteController;

  /// Optional inline validation error for draft note.
  final String? noteError;

  /// Callback clearing note errors on text change.
  final ValueChanged<String> onNoteChanged;

  /// Callback revealing one optional draft section.
  final ValueChanged<LabelSectionKind> onRevealSection;

  /// Bundled always-visible Name, Color, and Board Scope state.
  final _LabelDraftPrimaryData primaryData;

  /// Whether draft Activation Conditions section is open.
  final bool showConditions;

  /// Whether draft Reference Links section is open.
  final bool showLinks;

  /// Whether draft Note section is open.
  final bool showNote;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final hasHiddenOptional = !showNote || !showLinks || !showConditions;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LabelDraftPrimaryFields(data: primaryData, isBusy: isBusy),
        _LabelDraftOptionalSections(
          showNote: showNote,
          noteController: noteController,
          noteError: noteError,
          onNoteChanged: onNoteChanged,
          showLinks: showLinks,
          linksData: linksData,
          showConditions: showConditions,
          conditionsData: conditionsData,
          isBusy: isBusy,
        ),
        if (hasHiddenOptional) ...<Widget>[
          SizedBox(height: tokens.spacing.space3),
          _LabelDraftAddChipsBar(
            showNote: !showNote,
            showLinks: !showLinks,
            showConditions: !showConditions,
            enabled: !isBusy,
            onOpenNote: () => onRevealSection(LabelSectionKind.note),
            onOpenLinks: () => onRevealSection(LabelSectionKind.links),
            onOpenConditions: () =>
                onRevealSection(LabelSectionKind.conditions),
          ),
        ],
      ],
    );
  }
}

/// Always-visible Name, Color, and Board Scope inputs inside [_LabelDraftCard].
class _LabelDraftPrimaryFields extends StatelessWidget {
  /// Creates a [_LabelDraftPrimaryFields].
  const _LabelDraftPrimaryFields({required this.data, required this.isBusy});

  /// Bundled primary draft field controllers, values, and callbacks.
  final _LabelDraftPrimaryData data;

  /// Disables controls while submitting.
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiField(
          key: const ValueKey<String>('label_draft_name_field'),
          kind: UiFieldKind.text,
          controller: data.nameController,
          label: localizations.labelNameLabel,
          hintText: localizations.labelNameHint,
          maxLength: _maxSingleLineLength,
          autofocus: true,
          enabled: !isBusy,
          errorText: data.nameError,
          onChanged: data.onNameChanged,
          onSubmitted: (_) => unawaited(data.onSubmitFromField()),
        ),
        SizedBox(height: tokens.spacing.space3),
        _LabelDraftColorSection(
          selectedColor: data.selectedColor,
          enabled: !isBusy,
          onColorChanged: data.onColorChanged,
        ),
        SizedBox(height: tokens.spacing.space2),
        _LabelScopeSection(
          labelId: 'draft',
          isScoped: data.isScoped,
          enabled: !isBusy,
          onChanged: data.onScopeChanged,
        ),
      ],
    );
  }
}

/// Always-visible Color inset card inside [_LabelDraftCard].
class _LabelDraftColorSection extends StatelessWidget {
  /// Creates a [_LabelDraftColorSection].
  const _LabelDraftColorSection({
    required this.selectedColor,
    required this.enabled,
    required this.onColorChanged,
  });

  /// Whether color controls accept interaction.
  final bool enabled;

  /// Callback emitted when a color is selected.
  final ValueChanged<Color> onColorChanged;

  /// Active draft color.
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      headerIcon: Icons.palette_outlined,
      headerTitle: localizations.labelColorSectionTitle,
      child: _LabelColorWheelField(
        value: selectedColor,
        enabled: enabled,
        onChanged: onColorChanged,
      ),
    );
  }
}

/// Optional Note, Links, and Activation Conditions cards revealed inside [_LabelDraftCard].
class _LabelDraftOptionalSections extends StatelessWidget {
  /// Creates a [_LabelDraftOptionalSections].
  const _LabelDraftOptionalSections({
    required this.showNote,
    required this.noteController,
    required this.noteError,
    required this.onNoteChanged,
    required this.showLinks,
    required this.linksData,
    required this.showConditions,
    required this.conditionsData,
    required this.isBusy,
  });

  /// Bundled draft conditions state and callbacks.
  final _LabelDraftConditionsData conditionsData;

  /// Disables inputs while submitting.
  final bool isBusy;

  /// Bundled draft links state and callbacks.
  final _LabelDraftLinksData linksData;

  /// Draft note controller.
  final TextEditingController noteController;

  /// Optional inline validation error for draft note.
  final String? noteError;

  /// Callback clearing note errors on text change.
  final ValueChanged<String> onNoteChanged;

  /// Whether draft Activation Conditions section is open.
  final bool showConditions;

  /// Whether draft Reference Links section is open.
  final bool showLinks;

  /// Whether draft Note section is open.
  final bool showNote;

  @override
  Widget build(BuildContext context) {
    if (!showNote && !showLinks && !showConditions) {
      return const SizedBox.shrink();
    }
    final gap = SizedBox(height: UiThemeTokens.of(context).spacing.space2);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showNote) ...<Widget>[
          gap,
          _LabelDraftNoteSection(
            controller: noteController,
            errorText: noteError,
            enabled: !isBusy,
            onChanged: onNoteChanged,
          ),
        ],
        if (showLinks) ...<Widget>[
          gap,
          _LabelDraftLinksSection(data: linksData, enabled: !isBusy),
        ],
        if (showConditions) ...<Widget>[
          gap,
          _LabelDraftConditionsSection(data: conditionsData, enabled: !isBusy),
        ],
      ],
    );
  }
}

/// Shared localized adapter wrapping [UiColorWheel] for both Label Draft and inline Color editing (`U-COMP-007`).
class _LabelColorWheelField extends StatelessWidget {
  /// Creates a [_LabelColorWheelField].
  const _LabelColorWheelField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  /// Whether color inputs and wheel trigger accept interaction.
  final bool enabled;

  /// Callback emitted when a color is selected.
  final ValueChanged<Color> onChanged;

  /// Active color value.
  final Color value;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiColorWheel(
      value: value,
      enabled: enabled,
      onChanged: onChanged,
      customButtonLabel: localizations.tooltipPickCustomColor,
      modalTitle: localizations.labelColorPickerDialogTitle,
      brightnessLabel: localizations.labelColorBrightnessLabel,
      cancelLabel: localizations.actionCancel,
      confirmLabel: localizations.actionSelectColor,
      closeTooltip: localizations.actionClose,
      invalidHexError: localizations.labelColorErrorInvalid,
    );
  }
}

/// Optional Note inset card inside the uncommitted Label Draft Card.
class _LabelDraftNoteSection extends StatelessWidget {
  /// Creates a [_LabelDraftNoteSection].
  const _LabelDraftNoteSection({
    required this.controller,
    required this.errorText,
    required this.enabled,
    required this.onChanged,
  });

  /// Multiline note controller.
  final TextEditingController controller;

  /// Whether the input accepts typing.
  final bool enabled;

  /// Optional inline validation error message.
  final String? errorText;

  /// Callback notified when note text changes.
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      headerIcon: Icons.description_outlined,
      headerTitle: localizations.taskNoteLabel,
      child: UiField(
        key: const ValueKey<String>('label_draft_note_field'),
        kind: UiFieldKind.multiline,
        controller: controller,
        hintText: localizations.taskNoteHint,
        maxLength: _maxNoteLength,
        enabled: enabled,
        errorText: errorText,
        onChanged: onChanged,
      ),
    );
  }
}

/// Optional Reference Links inset card inside the uncommitted Label Draft Card.
class _LabelDraftLinksSection extends StatelessWidget {
  /// Creates a [_LabelDraftLinksSection].
  const _LabelDraftLinksSection({required this.data, required this.enabled});

  /// Bundled draft links state and callbacks.
  final _LabelDraftLinksData data;

  /// Whether controls accept interaction.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      headerIcon: Icons.link_rounded,
      headerTitle: localizations.linksSectionTitle,
      headerBadge: UiPill(
        label: '${data.links.length} / $_maxLinksPerLabel',
        variant: UiPillVariant.count,
      ),
      child: UiOrderedItemList<EntityLinkViewModel>(
        items: data.links,
        itemKey: (link, index) =>
            ValueKey<String>('label_draft_link_${index}_${link.uri}'),
        editingIndex: data.editingIndex,
        onReorder: enabled ? data.onReorder : null,
        moveUpTooltip: localizations.tooltipMoveLinkUp,
        moveDownTooltip: localizations.tooltipMoveLinkDown,
        onEdit: enabled ? data.onEdit : null,
        editTooltip: localizations.tooltipEditLink,
        onDelete: enabled ? data.onDelete : null,
        deleteTooltip: localizations.tooltipRemoveLink,
        itemBuilder: (context, link, index, isEditing) =>
            _LabelDraftLinkRowContent(link: link),
        addBar: _LabelDraftLinkAddBar(data: data, enabled: enabled),
      ),
    );
  }
}

/// Renders one link title and monospace URI stack inside [_LabelDraftLinksSection].
class _LabelDraftLinkRowContent extends StatelessWidget {
  /// Creates a [_LabelDraftLinkRowContent].
  const _LabelDraftLinkRowContent({required this.link});

  /// Draft reference link to display.
  final EntityLinkViewModel link;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          link.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.typography.control.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2.0),
        Text(
          link.uri,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: UiTypographyTokens.mono(
            tokens.typography.monoSmall.copyWith(color: colors.muted),
          ),
        ),
      ],
    );
  }
}

/// Inline title/URI inputs and Add/Update action bar for draft label links.
class _LabelDraftLinkAddBar extends StatelessWidget {
  /// Creates a [_LabelDraftLinkAddBar].
  const _LabelDraftLinkAddBar({required this.data, required this.enabled});

  /// Bundled draft links state and callbacks.
  final _LabelDraftLinksData data;

  /// Whether fields and buttons are enabled.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final error = data.inputError;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LabelDraftLinkInputsGrid(data: data, enabled: enabled),
        if (error != null && error.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6.0),
          _LabelsErrorText(message: error),
        ],
        SizedBox(height: tokens.spacing.space2),
        _LabelDraftLinkAddActions(
          isEditingExisting: data.editingIndex != null,
          enabled: enabled,
          onSubmitLink: data.onCommitLink,
          onCancelRowEdit: data.onCancelRowEdit,
        ),
      ],
    );
  }
}

/// Two-column responsive title and URI inputs inside [_LabelDraftLinkAddBar].
class _LabelDraftLinkInputsGrid extends StatelessWidget {
  /// Creates a [_LabelDraftLinkInputsGrid].
  const _LabelDraftLinkInputsGrid({required this.data, required this.enabled});

  /// Bundled draft links state and callbacks.
  final _LabelDraftLinksData data;

  /// Whether link inputs accept typing.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    return UiResponsiveGrid(
      preset: UiGridPreset.twoColumnCompactCollapse,
      spacing: tokens.spacing.space2,
      runSpacing: tokens.spacing.space2,
      children: <Widget>[
        UiField(
          key: const ValueKey<String>('label_draft_link_title'),
          kind: UiFieldKind.text,
          controller: data.titleController,
          hintText: localizations.linkTitleHint,
          maxLength: _maxSingleLineLength,
          enabled: enabled,
          onChanged: data.onInputChanged,
          onSubmitted: (_) => data.onCommitLink(),
        ),
        UiField(
          key: const ValueKey<String>('label_draft_link_uri'),
          kind: UiFieldKind.text,
          controller: data.uriController,
          hintText: localizations.linkUriHint,
          isMonospace: true,
          enabled: enabled,
          onChanged: data.onInputChanged,
          onSubmitted: (_) => data.onCommitLink(),
        ),
      ],
    );
  }
}

/// Add/Update link button and optional row-edit Cancel trigger for [_LabelDraftLinkAddBar].
class _LabelDraftLinkAddActions extends StatelessWidget {
  /// Creates a [_LabelDraftLinkAddActions].
  const _LabelDraftLinkAddActions({
    required this.isEditingExisting,
    required this.enabled,
    required this.onSubmitLink,
    required this.onCancelRowEdit,
  });

  /// Whether buttons accept interaction.
  final bool enabled;

  /// Whether an existing link row is being edited.
  final bool isEditingExisting;

  /// Callback cancelling an active row edit.
  final VoidCallback onCancelRowEdit;

  /// Callback committing the typed link row.
  final VoidCallback onSubmitLink;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        UiButton(
          label: isEditingExisting
              ? localizations.tooltipSaveLink
              : localizations.tooltipAddLink,
          leadingIcon: isEditingExisting ? null : Icons.add_rounded,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          onPressed: enabled ? onSubmitLink : null,
        ),
        if (isEditingExisting)
          UiButton(
            label: localizations.actionCancel,
            variant: UiButtonVariant.text,
            density: UiButtonDensity.compact,
            tooltip: localizations.tooltipCancelEditLink,
            onPressed: enabled ? onCancelRowEdit : null,
          ),
      ],
    );
  }
}

/// Optional Activation Conditions inset card inside the uncommitted Label Draft Card.
class _LabelDraftConditionsSection extends StatelessWidget {
  /// Creates a [_LabelDraftConditionsSection].
  const _LabelDraftConditionsSection({
    required this.data,
    required this.enabled,
  });

  /// Bundled draft conditions state and callbacks.
  final _LabelDraftConditionsData data;

  /// Whether condition pickers accept input.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiCard.inset(
      headerIcon: Icons.tune_rounded,
      headerTitle: localizations.taskConditionsSectionTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            localizations.labelConditionsSectionDescription,
            style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
          ),
          _LabelDraftConditionGroup(
            title: localizations.conditionDayGroupTitle,
            child: _LabelDraftWeekdaysWrap(
              selectedWeekdays: data.draft.selectedWeekdays,
              enabled: enabled,
              onToggleWeekday: data.onToggleWeekday,
            ),
          ),
          _LabelDraftConditionGroup(
            title: localizations.conditionTimeGroupTitle,
            child: _LabelDraftTimeWindowsList(data: data, enabled: enabled),
          ),
          _LabelDraftConditionGroup(
            title: localizations.conditionLocationGroupTitle,
            child: _LabelDraftLocationsWrap(
              allLocations: data.allLocations,
              selectedLocationIds: data.draft.selectedLocationIds,
              enabled: enabled,
              onToggleLocation: data.onToggleLocation,
            ),
          ),
        ],
      ),
    );
  }
}

/// Titled condition dimension group inside [_LabelDraftConditionsSection].
class _LabelDraftConditionGroup extends StatelessWidget {
  /// Creates a [_LabelDraftConditionGroup].
  const _LabelDraftConditionGroup({required this.title, required this.child});

  /// Dimension picker widget rendered beneath [title].
  final Widget child;

  /// Localized condition dimension heading (`Days`, `Time`, `Locations`).
  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            style: tokens.typography.meta.copyWith(
              color: tokens.colors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: tokens.spacing.space2),
          child,
        ],
      ),
    );
  }
}

/// Ordered list of draft daily time windows paired with hybrid `HH:MM` start/end inputs.
class _LabelDraftTimeWindowsList extends StatelessWidget {
  /// Creates a [_LabelDraftTimeWindowsList].
  const _LabelDraftTimeWindowsList({required this.data, required this.enabled});

  /// Bundled draft conditions state and callbacks.
  final _LabelDraftConditionsData data;

  /// Whether adding and removing time windows is enabled.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiOrderedItemList<TimeWindowDraftViewModel>(
      items: data.draft.timeWindows,
      itemKey: (window, index) => ValueKey<String>(
        'label_draft_time_${index}_${window.start}_${window.end}',
      ),
      onDelete: enabled ? data.onRemoveTimeWindow : null,
      deleteTooltip: localizations.tooltipRemoveTimeCondition,
      itemBuilder: (context, window, index, isEditing) => Text(
        '${window.start} - ${window.end}',
        style: UiTypographyTokens.mono(
          tokens.typography.monoSmall.copyWith(color: tokens.colors.ink),
        ),
      ),
      addBar: _LabelDraftTimeWindowAddBar(data: data, enabled: enabled),
    );
  }
}

/// Selectable Monday..Sunday pills for draft label weekday conditions.
class _LabelDraftWeekdaysWrap extends StatelessWidget {
  /// Creates a [_LabelDraftWeekdaysWrap].
  const _LabelDraftWeekdaysWrap({
    required this.selectedWeekdays,
    required this.enabled,
    required this.onToggleWeekday,
  });

  /// Whether weekday pills are interactive.
  final bool enabled;

  /// Callback toggling an ISO weekday (`1..7`).
  final ValueChanged<int> onToggleWeekday;

  /// Selected ISO weekdays (`1..7`).
  final List<int> selectedWeekdays;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        for (var isoDay = DateTime.monday; isoDay <= DateTime.sunday; isoDay++)
          UiPill(
            key: ValueKey<String>('label_draft_cond_day_$isoDay'),
            label: _weekdayLabel(isoDay, localizations),
            variant: UiPillVariant.selectable,
            isSelected: selectedWeekdays.contains(isoDay),
            enabled: enabled,
            onPressed: enabled ? () => onToggleWeekday(isoDay) : null,
          ),
      ],
    );
  }
}

/// Start/end hybrid `HH:MM` inputs and Add time window trigger inside [_LabelDraftTimeWindowsList].
class _LabelDraftTimeWindowAddBar extends StatelessWidget {
  /// Creates a [_LabelDraftTimeWindowAddBar].
  const _LabelDraftTimeWindowAddBar({
    required this.data,
    required this.enabled,
  });

  /// Bundled draft conditions state and callbacks.
  final _LabelDraftConditionsData data;

  /// Whether fields and button are enabled.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final error = data.timeInputError;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LabelDraftTimeInputsGrid(data: data, enabled: enabled),
        if (error != null && error.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6.0),
          _LabelsErrorText(message: error),
        ],
        SizedBox(height: tokens.spacing.space2),
        Align(
          alignment: Alignment.centerLeft,
          child: UiButton(
            label: localizations.tooltipAddTimeCondition,
            leadingIcon: Icons.add_rounded,
            variant: UiButtonVariant.secondary,
            density: UiButtonDensity.compact,
            onPressed: enabled ? data.onAddTimeWindow : null,
          ),
        ),
      ],
    );
  }
}

/// Two-column responsive start and end `HH:MM` inputs inside [_LabelDraftTimeWindowAddBar].
class _LabelDraftTimeInputsGrid extends StatelessWidget {
  /// Creates a [_LabelDraftTimeInputsGrid].
  const _LabelDraftTimeInputsGrid({required this.data, required this.enabled});

  /// Bundled draft conditions state and callbacks.
  final _LabelDraftConditionsData data;

  /// Whether time inputs accept typing.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    return UiResponsiveGrid(
      preset: UiGridPreset.twoColumnCompactCollapse,
      spacing: tokens.spacing.space2,
      runSpacing: tokens.spacing.space2,
      children: <Widget>[
        EntityHybridTimeField(
          key: const ValueKey<String>('label_draft_cond_time_start'),
          controller: data.timeStartController,
          hintText: localizations.conditionTimeStartHint,
          enabled: enabled,
          onSubmitted: (_) => data.onAddTimeWindow(),
        ),
        EntityHybridTimeField(
          key: const ValueKey<String>('label_draft_cond_time_end'),
          controller: data.timeEndController,
          hintText: localizations.conditionTimeEndHint,
          enabled: enabled,
          onSubmitted: (_) => data.onAddTimeWindow(),
        ),
      ],
    );
  }
}

/// Selectable saved location pills for draft label GPS conditions.
class _LabelDraftLocationsWrap extends StatelessWidget {
  /// Creates a [_LabelDraftLocationsWrap].
  const _LabelDraftLocationsWrap({
    required this.allLocations,
    required this.selectedLocationIds,
    required this.enabled,
    required this.onToggleLocation,
  });

  /// Available saved locations.
  final List<LocationOptionViewModel> allLocations;

  /// Whether location chips accept input.
  final bool enabled;

  /// Callback toggling a location identifier.
  final ValueChanged<String> onToggleLocation;

  /// Selected location identifiers.
  final List<String> selectedLocationIds;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    if (allLocations.isEmpty) {
      return Text(
        localizations.emptyLocationsHint,
        style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
      );
    }
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        for (final location in allLocations)
          UiPill(
            key: ValueKey<String>('label_draft_cond_loc_${location.id}'),
            label: location.name,
            icon: Icons.place_outlined,
            variant: UiPillVariant.selectable,
            isSelected: selectedLocationIds.contains(location.id),
            enabled: enabled,
            onPressed: enabled ? () => onToggleLocation(location.id) : null,
          ),
      ],
    );
  }
}

/// Dashed `+ Add` chip bar revealing optional Note, Links, and Conditions sections inside [_LabelDraftCard].
class _LabelDraftAddChipsBar extends StatelessWidget {
  /// Creates a [_LabelDraftAddChipsBar].
  const _LabelDraftAddChipsBar({
    required this.showNote,
    required this.showLinks,
    required this.showConditions,
    required this.enabled,
    required this.onOpenNote,
    required this.onOpenLinks,
    required this.onOpenConditions,
  });

  /// Whether add chips accept clicks.
  final bool enabled;

  /// Callback revealing draft Conditions.
  final VoidCallback onOpenConditions;

  /// Callback revealing draft Links.
  final VoidCallback onOpenLinks;

  /// Callback revealing draft Note.
  final VoidCallback onOpenNote;

  /// Whether `+ Conditions` chip is shown.
  final bool showConditions;

  /// Whether `+ Links` chip is shown.
  final bool showLinks;

  /// Whether `+ Note` chip is shown.
  final bool showNote;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        if (showNote)
          UiPill(
            key: const ValueKey<String>('label_draft_add_note'),
            label: localizations.inlineAddNote,
            icon: Icons.description_outlined,
            variant: UiPillVariant.addField,
            enabled: enabled,
            onPressed: enabled ? onOpenNote : null,
          ),
        if (showLinks)
          UiPill(
            key: const ValueKey<String>('label_draft_add_links'),
            label: localizations.inlineAddLinks,
            icon: Icons.link_rounded,
            variant: UiPillVariant.addField,
            enabled: enabled,
            onPressed: enabled ? onOpenLinks : null,
          ),
        if (showConditions)
          UiPill(
            key: const ValueKey<String>('label_draft_add_conditions'),
            label: localizations.inlineAddConditions,
            icon: Icons.tune_rounded,
            variant: UiPillVariant.addField,
            enabled: enabled,
            onPressed: enabled ? onOpenConditions : null,
          ),
      ],
    );
  }
}

/// Right-aligned `Cancel` + `Create label` footer rendered at the bottom of [_LabelDraftCard].
class _LabelDraftFooter extends StatelessWidget {
  /// Creates a [_LabelDraftFooter].
  const _LabelDraftFooter({
    required this.isBusy,
    required this.onCancel,
    required this.onSubmit,
  });

  /// Disables actions and spins Create indicator while true.
  final bool isBusy;

  /// Callback cancelling the draft card.
  final VoidCallback onCancel;

  /// Callback committing the draft label.
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: tokens.colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: tokens.spacing.space3),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8.0,
          runSpacing: 8.0,
          children: <Widget>[
            UiButton(
              label: localizations.actionCancel,
              variant: UiButtonVariant.secondary,
              density: UiButtonDensity.compact,
              onPressed: isBusy ? null : onCancel,
            ),
            UiButton(
              label: localizations.actionCreateLabel,
              leadingIcon: isBusy ? Icons.sync_rounded : Icons.add_rounded,
              variant: UiButtonVariant.primary,
              density: UiButtonDensity.compact,
              isLoading: isBusy,
              onPressed: isBusy ? null : () => unawaited(onSubmit()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Unified expandable Label entity card sharing single-expand coordination (`U-CARD-001`..`005`).
class _LabelEntityCard extends ConsumerWidget {
  /// Creates a [_LabelEntityCard].
  const _LabelEntityCard({
    required this.cardScrollKey,
    required this.label,
    required this.allLocations,
  });

  /// Workspace locations passed into the Activation Conditions editor.
  final List<LocationOptionViewModel> allLocations;

  /// [GlobalKey] attached around the card for smooth reveal scrolling.
  final GlobalKey cardScrollKey;

  /// Immutable label card view model.
  final LabelCardViewModel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entityRef = EntityRef(kind: EntityKind.label, id: label.id);
    final isExpanded = ref.watch(
      appShellControllerProvider.select(
        (shell) => shell.expandedEntity == entityRef,
      ),
    );
    final editingSection = ref.watch(
      appShellControllerProvider.select(
        (shell) => _parseInlineEditSection(shell.activeInlineEdit, label.id),
      ),
    );
    final isConfirmingDelete = ref.watch(
      appShellControllerProvider.select(
        (shell) => shell.activeDeleteConfirm == entityRef,
      ),
    );
    final isBusy = ref.watch(
      entityV2ControllerProvider.select((state) => state.isBusy),
    );

    return KeyedSubtree(
      key: cardScrollKey,
      child: _LabelExpandableCardView(
        label: label,
        allLocations: allLocations,
        isExpanded: isExpanded,
        editingSection: editingSection,
        isConfirmingDelete: isConfirmingDelete,
        isBusy: isBusy,
      ),
    );
  }
}

/// Stateless presentation shell configuring [UiCard.expandable] for one label card.
class _LabelExpandableCardView extends ConsumerWidget {
  /// Creates a [_LabelExpandableCardView].
  const _LabelExpandableCardView({
    required this.label,
    required this.allLocations,
    required this.isExpanded,
    required this.editingSection,
    required this.isConfirmingDelete,
    required this.isBusy,
  });

  /// Saved workspace locations for Activation Conditions.
  final List<LocationOptionViewModel> allLocations;

  /// Currently open inline section editor on this card, if any.
  final LabelSectionKind? editingSection;

  /// Disables actions while a mutation is in flight.
  final bool isBusy;

  /// Whether inline delete confirmation is open.
  final bool isConfirmingDelete;

  /// Whether this card is currently expanded.
  final bool isExpanded;

  /// Label card view model.
  final LabelCardViewModel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEditingName =
        isExpanded && editingSection == LabelSectionKind.title;
    void toggleExpand() => _toggleExpand(ref);

    return UiCard.expandable(
      key: ValueKey<String>('label_card_${label.id}'),
      title: label.name,
      isExpanded: isExpanded,
      onToggleExpand: toggleExpand,
      leading: _LabelLeadingColorDot(
        colorValue: label.colorValue,
        onTap: toggleExpand,
      ),
      isEditingTitle: isEditingName,
      titleEditor: isEditingName
          ? _LabelInlineNameEditor(label: label, isBusy: isBusy)
          : null,
      trailingActions: <Widget>[
        if (isExpanded && !isEditingName)
          _LabelEditNameButton(labelId: label.id, isBusy: isBusy),
      ],
      collapsedMetadata: _LabelCollapsedMetadataStrip(
        label: label,
        onToggleExpand: toggleExpand,
      ),
      expandedChild: isExpanded
          ? _LabelExpandedPanel(
              label: label,
              allLocations: allLocations,
              editingSection: editingSection,
              isConfirmingDelete: isConfirmingDelete,
              isBusy: isBusy,
            )
          : null,
    );
  }

  /// Toggles single-expand state for [label] in `AppShellController`.
  void _toggleExpand(WidgetRef ref) {
    ref
        .read(appShellControllerProvider.notifier)
        .toggleExpandEntity(EntityRef(kind: EntityKind.label, id: label.id));
  }
}

/// Trailing inline name edit pencil rendered only while a Label card is expanded.
class _LabelEditNameButton extends ConsumerWidget {
  /// Creates a [_LabelEditNameButton].
  const _LabelEditNameButton({required this.labelId, required this.isBusy});

  /// Disables the button while busy.
  final bool isBusy;

  /// Canonical label identifier for deterministic test keys.
  final String labelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return UiButton(
      key: ValueKey<String>('label_edit_name_$labelId'),
      leadingIcon: Icons.edit_outlined,
      variant: UiButtonVariant.icon,
      density: UiButtonDensity.dense,
      tooltip: localizations.inlineEditNameTooltip,
      onPressed: isBusy
          ? null
          : () => ref
                .read(appShellControllerProvider.notifier)
                .openInlineEdit(
                  InlineEditTarget.label(labelId, LabelSectionKind.title),
                ),
    );
  }
}

/// Optical `12px` rounded-square color dot centered inside the `34x34px` leading header slot (`U-CARD-001`).
class _LabelLeadingColorDot extends StatelessWidget {
  /// Creates a [_LabelLeadingColorDot].
  const _LabelLeadingColorDot({required this.colorValue, required this.onTap});

  /// Parsed ARGB color value, falling back to `tokens.colors.accent` when unset.
  final int? colorValue;

  /// Toggles parent card expansion when tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final dotColor = switch (colorValue) {
      final int value => Color(value),
      null => tokens.colors.accent,
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: tokens.spacing.chromeControlHeight,
        height: tokens.spacing.chromeControlHeight,
        child: Center(
          child: ExcludeSemantics(
            child: Container(
              width: _labelColorDotSize,
              height: _labelColorDotSize,
              decoration: BoxDecoration(
                color: dotColor,
                borderRadius: BorderRadius.circular(tokens.radii.dotLg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline label name editor swapped into the expanded card header (`U-CARD-001`).
class _LabelInlineNameEditor extends ConsumerStatefulWidget {
  /// Creates a [_LabelInlineNameEditor].
  const _LabelInlineNameEditor({required this.label, required this.isBusy});

  /// Disables actions while a parent mutation is in flight.
  final bool isBusy;

  /// Persisted label projection seeding the text input and target identifier.
  final LabelCardViewModel label;

  @override
  ConsumerState<_LabelInlineNameEditor> createState() =>
      _LabelInlineNameEditorState();
}

/// Manages text controller and inline error feedback for [_LabelInlineNameEditor].
class _LabelInlineNameEditorState
    extends ConsumerState<_LabelInlineNameEditor> {
  late final TextEditingController _controller;

  String? _errorText;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.label.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final busy = widget.isBusy || _isSubmitting;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiField(
          key: ValueKey<String>('label_name_input_${widget.label.id}'),
          kind: UiFieldKind.text,
          controller: _controller,
          hintText: localizations.labelNameHint,
          maxLength: _maxSingleLineLength,
          autofocus: true,
          enabled: !busy,
          errorText: _errorText,
          onChanged: _handleChanged,
          onSubmitted: (_) => unawaited(_handleSave()),
        ),
        const SizedBox(height: 6.0),
        _LabelInlineNameActions(
          isBusy: busy,
          onCancel: ref
              .read(appShellControllerProvider.notifier)
              .closeInlineEdit,
          onSave: () => unawaited(_handleSave()),
        ),
      ],
    );
  }

  /// Clears transient validation error text once the user resumes typing.
  void _handleChanged(String value) {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  /// Submits the edited label name and renders any returned validation or persistence error inline.
  Future<void> _handleSave() async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    final result = await ref
        .read(entityV2ControllerProvider.notifier)
        .saveLabelName(
          widget.label.id,
          _controller.text,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
    }
  }
}

/// Right-aligned `Cancel` and `Save` buttons rendered beneath the inline name field.
class _LabelInlineNameActions extends StatelessWidget {
  /// Creates a [_LabelInlineNameActions].
  const _LabelInlineNameActions({
    required this.isBusy,
    required this.onCancel,
    required this.onSave,
  });

  /// Disables actions and spins Save indicator while busy.
  final bool isBusy;

  /// Callback closing inline name editing.
  final VoidCallback onCancel;

  /// Callback saving the edited name.
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        UiButton(
          label: localizations.actionCancel,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          onPressed: isBusy ? null : onCancel,
        ),
        UiButton(
          label: localizations.actionSave,
          leadingIcon: isBusy ? Icons.sync_rounded : null,
          variant: UiButtonVariant.primary,
          density: UiButtonDensity.compact,
          isLoading: isBusy,
          onPressed: isBusy ? null : onSave,
        ),
      ],
    );
  }
}

/// Uncapped collapsed metadata strip displaying Scope, open task count, Note, Links, and Conditions badges (`U-CARD-005`).
class _LabelCollapsedMetadataStrip extends StatelessWidget {
  /// Creates a [_LabelCollapsedMetadataStrip].
  const _LabelCollapsedMetadataStrip({
    required this.label,
    required this.onToggleExpand,
  });

  /// Label card projection.
  final LabelCardViewModel label;

  /// Callback toggling expansion of the owning label card.
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggleExpand,
        child: _LabelCollapsedMetadataBadges(label: label),
      ),
    );
  }
}

/// Static uncapped [Wrap] of collapsed label metadata badges inside [_LabelCollapsedMetadataStrip].
class _LabelCollapsedMetadataBadges extends StatelessWidget {
  /// Creates a [_LabelCollapsedMetadataBadges].
  const _LabelCollapsedMetadataBadges({required this.label});

  /// Label card projection.
  final LabelCardViewModel label;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final linksLabel = label.links.length == 1
        ? localizations.badgeLinkSingular
        : localizations.taskInfoLinksCount('${label.links.length}');

    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        UiPill(
          label: label.isScoped
              ? localizations.scopedQueueLabel
              : localizations.globalContextLabel,
          variant: UiPillVariant.meta,
          tone: label.isScoped ? UiPillTone.soft : UiPillTone.neutral,
          icon: Icons.layers_outlined,
        ),
        UiPill(
          label: localizations.openTasksCountPill('${label.openCount}'),
          variant: UiPillVariant.meta,
        ),
        if (_hasNonEmptyNote(label.note))
          UiPill(
            label: localizations.tooltipIndicatorNote,
            variant: UiPillVariant.meta,
            icon: Icons.description_outlined,
          ),
        if (label.links.isNotEmpty)
          UiPill(
            label: linksLabel,
            variant: UiPillVariant.meta,
            icon: Icons.link_rounded,
          ),
        if (label.hasConditions)
          UiPill(
            label: localizations.tooltipIndicatorConditions,
            variant: UiPillVariant.meta,
            icon: Icons.tune_rounded,
          ),
      ],
    );
  }
}

/// Expanded Label card body rendering meta bar, canonical sections (Note, Links, Color, Board Scope, Conditions), and `+ Add` chips (`U-CARD-002`).
class _LabelExpandedPanel extends ConsumerWidget {
  /// Creates a [_LabelExpandedPanel].
  const _LabelExpandedPanel({
    required this.label,
    required this.allLocations,
    required this.editingSection,
    required this.isConfirmingDelete,
    required this.isBusy,
  });

  /// Saved locations selectable inside the Activation Conditions section.
  final List<LocationOptionViewModel> allLocations;

  /// Currently open inline section editor on this label card, if any.
  final LabelSectionKind? editingSection;

  /// Disables interactive triggers while an asynchronous mutation is in flight.
  final bool isBusy;

  /// Whether the inline delete confirmation banner is active in [EntityCardMetaBar].
  final bool isConfirmingDelete;

  /// Label card projection.
  final LabelCardViewModel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = UiThemeTokens.of(context);
    final shellNotifier = ref.read(appShellControllerProvider.notifier);
    final visibleUnset = <LabelSectionKind>[
      for (final section in label.unsetSections)
        if (section != editingSection) section,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LabelCardMetaBar(label: label, isConfirmingDelete: isConfirmingDelete),
        _LabelExpandedSectionsStack(
          label: label,
          allLocations: allLocations,
          editingSection: editingSection,
          isBusy: isBusy,
        ),
        if (visibleUnset.isNotEmpty) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          _LabelUnsetChipsBar(
            sections: visibleUnset,
            enabled: !isBusy,
            onSelectSection: (section) => shellNotifier.openInlineEdit(
              InlineEditTarget.label(label.id, section),
            ),
          ),
        ],
      ],
    );
  }
}

/// Label-specific [EntityCardMetaBar] wiring Copy ID, open count pill, and inline Delete confirmation.
class _LabelCardMetaBar extends ConsumerWidget {
  /// Creates a [_LabelCardMetaBar].
  const _LabelCardMetaBar({
    required this.label,
    required this.isConfirmingDelete,
  });

  /// Whether inline delete confirmation is open.
  final bool isConfirmingDelete;

  /// Label card view model.
  final LabelCardViewModel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final shellNotifier = ref.read(appShellControllerProvider.notifier);
    final entityRef = EntityRef(kind: EntityKind.label, id: label.id);

    return EntityCardMetaBar(
      entityId: label.id,
      copyIdTooltip: localizations.actionCopy,
      onCopyId: () => unawaited(
        _copyLabelId(
          context,
          ref,
          labelId: label.id,
          copiedNotice: localizations.labelIdCopiedNotice,
        ),
      ),
      statusPillLabel: localizations.openTasksCountPill('${label.openCount}'),
      statusPillTone: UiPillTone.soft,
      deleteTooltip: localizations.tooltipDeleteLabel,
      deleteConfirmMessage: localizations.inlineDeleteLabelConfirm,
      isConfirmingDelete: isConfirmingDelete,
      onRequestDelete: () => shellNotifier.requestInlineDelete(entityRef),
      onCancelDelete: shellNotifier.cancelInlineDelete,
      onConfirmDelete: () =>
          unawaited(_confirmDeleteLabel(context, ref, label.id)),
    );
  }
}

/// Canonical vertical stack of populated-only and always-visible Label sections (`Note -> Links -> Color -> Board Scope -> Conditions`).
class _LabelExpandedSectionsStack extends StatelessWidget {
  /// Creates a [_LabelExpandedSectionsStack].
  const _LabelExpandedSectionsStack({
    required this.label,
    required this.allLocations,
    required this.editingSection,
    required this.isBusy,
  });

  /// Workspace locations for Activation Conditions.
  final List<LocationOptionViewModel> allLocations;

  /// Active inline section editor, if any.
  final LabelSectionKind? editingSection;

  /// Disables actions while busy.
  final bool isBusy;

  /// Label card view model.
  final LabelCardViewModel label;

  @override
  Widget build(BuildContext context) {
    final topGap = SizedBox(height: UiThemeTokens.of(context).spacing.space2);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LabelNoteSectionCard(
          label: label,
          isEditing: editingSection == LabelSectionKind.note,
          isBusy: isBusy,
        ),
        _LabelLinksSectionCard(
          label: label,
          isEditing: editingSection == LabelSectionKind.links,
          isBusy: isBusy,
        ),
        topGap,
        _LabelColorSectionCard(
          label: label,
          isEditing: editingSection == LabelSectionKind.color,
          isBusy: isBusy,
        ),
        topGap,
        _LabelScopeSectionCard(label: label, isBusy: isBusy),
        _LabelConditionsSectionCard(
          label: label,
          allLocations: allLocations,
          isEditing: editingSection == LabelSectionKind.conditions,
          isBusy: isBusy,
        ),
      ],
    );
  }
}

/// Wires [EntityNoteSection] to `EntityV2Controller` and `UiTelemetry` for one label card.
class _LabelNoteSectionCard extends ConsumerWidget {
  /// Creates a [_LabelNoteSectionCard].
  const _LabelNoteSectionCard({
    required this.label,
    required this.isEditing,
    required this.isBusy,
  });

  /// Disables controls while a mutation is in flight.
  final bool isBusy;

  /// Whether inline Note editing is active.
  final bool isEditing;

  /// Label card view model.
  final LabelCardViewModel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_hasNonEmptyNote(label.note) && !isEditing) {
      return const SizedBox.shrink();
    }
    final locale = Localizations.localeOf(context);
    final tokens = UiThemeTokens.of(context);
    final shellNotifier = ref.read(appShellControllerProvider.notifier);
    final entityNotifier = ref.read(entityV2ControllerProvider.notifier);

    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.space2),
      child: EntityNoteSection(
        note: label.note,
        isEditing: isEditing,
        canEdit: true,
        isBusy: isBusy,
        onStartEdit: () => shellNotifier.openInlineEdit(
          InlineEditTarget.label(label.id, LabelSectionKind.note),
        ),
        onCancelEdit: shellNotifier.closeInlineEdit,
        onSave: (rawNote) =>
            entityNotifier.saveLabelNote(label.id, rawNote, locale: locale),
        onClear: () => _clearLabelNote(context, ref, label.id),
        onNoteCopied: () => UiTelemetry.logLabelNoteCopied(
          labelId: label.id,
          length: label.note?.length ?? 0,
        ),
      ),
    );
  }
}

/// Wires [EntityLinksSection] (`isLabel: true`) to `EntityV2Controller` for one label card.
class _LabelLinksSectionCard extends ConsumerWidget {
  /// Creates a [_LabelLinksSectionCard].
  const _LabelLinksSectionCard({
    required this.label,
    required this.isEditing,
    required this.isBusy,
  });

  /// Disables controls while a mutation is in flight.
  final bool isBusy;

  /// Whether inline Links editing is active.
  final bool isEditing;

  /// Label card view model.
  final LabelCardViewModel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (label.links.isEmpty && !isEditing) {
      return const SizedBox.shrink();
    }
    final locale = Localizations.localeOf(context);
    final tokens = UiThemeTokens.of(context);
    final shellNotifier = ref.read(appShellControllerProvider.notifier);
    final entityNotifier = ref.read(entityV2ControllerProvider.notifier);

    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.space2),
      child: EntityLinksSection(
        links: label.links,
        isEditing: isEditing,
        canEdit: true,
        isLabel: true,
        isBusy: isBusy,
        onStartEdit: () => shellNotifier.openInlineEdit(
          InlineEditTarget.label(label.id, LabelSectionKind.links),
        ),
        onCancelEdit: shellNotifier.closeInlineEdit,
        onSave: (links) =>
            entityNotifier.saveLabelLinks(label.id, links, locale: locale),
      ),
    );
  }
}

/// Wires always-visible [_LabelColorSection] to `EntityV2Controller` for one label card.
class _LabelColorSectionCard extends ConsumerWidget {
  /// Creates a [_LabelColorSectionCard].
  const _LabelColorSectionCard({
    required this.label,
    required this.isEditing,
    required this.isBusy,
  });

  /// Disables controls while a mutation is in flight.
  final bool isBusy;

  /// Whether inline [UiColorWheel] editing is active.
  final bool isEditing;

  /// Label card view model.
  final LabelCardViewModel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    final shellNotifier = ref.read(appShellControllerProvider.notifier);
    final entityNotifier = ref.read(entityV2ControllerProvider.notifier);

    return _LabelColorSection(
      labelId: label.id,
      colorHex: label.colorHex,
      colorValue: label.colorValue,
      isEditing: isEditing,
      isBusy: isBusy,
      onStartEdit: () => shellNotifier.openInlineEdit(
        InlineEditTarget.label(label.id, LabelSectionKind.color),
      ),
      onCancelEdit: shellNotifier.closeInlineEdit,
      onSave: (colorHex) =>
          entityNotifier.saveLabelColor(label.id, colorHex, locale: locale),
      onClear: () => entityNotifier.clearLabelColor(label.id, locale: locale),
    );
  }
}

/// Wires always-visible live [_LabelScopeSection] to `EntityV2Controller.setLabelScoped`.
class _LabelScopeSectionCard extends ConsumerWidget {
  /// Creates a [_LabelScopeSectionCard].
  const _LabelScopeSectionCard({required this.label, required this.isBusy});

  /// Disables the segmented toggle while a mutation is in flight.
  final bool isBusy;

  /// Label card view model.
  final LabelCardViewModel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _LabelScopeSection(
      labelId: label.id,
      isScoped: label.isScoped,
      enabled: !isBusy,
      onChanged: (nextScoped) {
        if (nextScoped != label.isScoped) {
          unawaited(_updateLabelScope(context, ref, label.id, nextScoped));
        }
      },
    );
  }
}

/// Wires [EntityConditionsSection] (`isTask: false`) to `EntityV2Controller` and Locations navigation.
class _LabelConditionsSectionCard extends ConsumerWidget {
  /// Creates a [_LabelConditionsSectionCard].
  const _LabelConditionsSectionCard({
    required this.label,
    required this.allLocations,
    required this.isEditing,
    required this.isBusy,
  });

  /// Saved workspace locations selectable inside GPS conditions.
  final List<LocationOptionViewModel> allLocations;

  /// Disables controls while a mutation is in flight.
  final bool isBusy;

  /// Whether inline Activation Conditions editing is active.
  final bool isEditing;

  /// Label card view model.
  final LabelCardViewModel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!label.hasConditions && !isEditing) {
      return const SizedBox.shrink();
    }
    final locale = Localizations.localeOf(context);
    final tokens = UiThemeTokens.of(context);
    final shellNotifier = ref.read(appShellControllerProvider.notifier);
    final entityNotifier = ref.read(entityV2ControllerProvider.notifier);

    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.space2),
      child: EntityConditionsSection(
        isTask: false,
        hasConditions: label.hasConditions,
        conditionsSummary: label.conditionsSummary,
        conditionDraft: label.conditionDraft,
        allLocations: allLocations,
        isEditing: isEditing,
        canEdit: true,
        isBusy: isBusy,
        onStartEdit: () => shellNotifier.openInlineEdit(
          InlineEditTarget.label(label.id, LabelSectionKind.conditions),
        ),
        onCancelEdit: shellNotifier.closeInlineEdit,
        onSave: (draft) =>
            entityNotifier.saveLabelConditions(label.id, draft, locale: locale),
        onClear: () => _clearLabelConditions(context, ref, label.id),
        onOpenLocation: (locationId) => shellNotifier.openEntityInManager(
          EntityRef(kind: EntityKind.location, id: locationId),
          preserveReturnContext: false,
        ),
      ),
    );
  }
}

/// Always-visible Color inset section supporting read-only swatch/hex display and inline [UiColorWheel] editing.
class _LabelColorSection extends StatefulWidget {
  /// Creates a [_LabelColorSection].
  const _LabelColorSection({
    required this.labelId,
    required this.colorHex,
    required this.colorValue,
    required this.isEditing,
    required this.isBusy,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSave,
    required this.onClear,
  });

  /// Persisted `#RRGGBB` string, or empty string when unset.
  final String colorHex;

  /// Parsed ARGB integer color, or `null` when unset.
  final int? colorValue;

  /// Disables actions while a parent mutation is in flight.
  final bool isBusy;

  /// Whether inline [UiColorWheel] editing mode is active.
  final bool isEditing;

  /// Canonical label identifier for deterministic test keys.
  final String labelId;

  /// Callback cancelling inline editing.
  final VoidCallback onCancelEdit;

  /// Callback clearing the persisted label color.
  final Future<V2ActionResult> Function() onClear;

  /// Callback saving a normalized `#RRGGBB` color string.
  final Future<V2ActionResult> Function(String colorHex) onSave;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  @override
  State<_LabelColorSection> createState() => _LabelColorSectionState();
}

/// Manages selected color state and save/clear submission for [_LabelColorSection].
class _LabelColorSectionState extends State<_LabelColorSection> {
  String? _errorText;
  bool _isSubmitting = false;
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = _resolveSeedColor(widget.colorHex);
  }

  @override
  void didUpdateWidget(covariant _LabelColorSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _selectedColor = _resolveSeedColor(widget.colorHex);
      _errorText = null;
      _isSubmitting = false;
    } else if (oldWidget.isEditing && !widget.isEditing) {
      _errorText = null;
      _isSubmitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEditing) {
      return _LabelColorReadOnlyCard(
        labelId: widget.labelId,
        colorHex: widget.colorHex,
        colorValue: widget.colorValue,
        isBusy: widget.isBusy,
        onStartEdit: widget.onStartEdit,
      );
    }
    return _LabelColorEditCard(
      selectedColor: _selectedColor,
      hasPersistedColor: widget.colorHex.isNotEmpty,
      errorText: _errorText,
      isBusy: widget.isBusy || _isSubmitting,
      onColorChanged: _handleColorChanged,
      onClear: _handleClear,
      onCancel: widget.onCancelEdit,
      onSave: _handleSave,
    );
  }

  /// Applies [result] from save or clear to inline busy/error state.
  void _applyActionResult(V2ActionResult result) {
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
    }
  }

  /// Clears the persisted label color while guarding against overlapping submissions.
  Future<void> _handleClear() async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    final result = await widget.onClear();
    _applyActionResult(result);
  }

  /// Updates the active draft color selected from [UiColorWheel].
  void _handleColorChanged(Color color) {
    setState(() {
      _selectedColor = color;
      _errorText = null;
    });
  }

  /// Commits the selected `#RRGGBB` color string via [widget.onSave].
  Future<void> _handleSave() async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    final result = await widget.onSave(UiColorWheel.formatHex(_selectedColor));
    _applyActionResult(result);
  }

  /// Parses [colorHex] or falls back to the first canonical preset when color is unset.
  Color _resolveSeedColor(String colorHex) {
    return UiColorWheel.tryParseHex(colorHex) ??
        UiColorWheel.canonicalPresets.first;
  }
}

/// Read-only Color inset card displaying swatch, uppercase `#RRGGBB` hex, and Edit pencil.
class _LabelColorReadOnlyCard extends StatelessWidget {
  /// Creates a [_LabelColorReadOnlyCard].
  const _LabelColorReadOnlyCard({
    required this.labelId,
    required this.colorHex,
    required this.colorValue,
    required this.isBusy,
    required this.onStartEdit,
  });

  /// Persisted `#RRGGBB` string, or empty when unset.
  final String colorHex;

  /// Parsed ARGB integer color, or `null` when unset.
  final int? colorValue;

  /// Disables the Edit trigger while busy.
  final bool isBusy;

  /// Canonical label identifier for deterministic test keys.
  final String labelId;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      headerIcon: Icons.palette_outlined,
      headerTitle: localizations.labelColorSectionTitle,
      headerTrailing: UiButton(
        key: ValueKey<String>('label_edit_color_$labelId'),
        leadingIcon: Icons.edit_outlined,
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.dense,
        tooltip: localizations.actionEdit,
        onPressed: isBusy ? null : onStartEdit,
      ),
      child: _LabelColorSwatchReadout(
        colorHex: colorHex,
        colorValue: colorValue,
      ),
    );
  }
}

/// Displays the square-rounded swatch and monospace `#RRGGBB` readout (or hint when unset).
class _LabelColorSwatchReadout extends StatelessWidget {
  /// Creates a [_LabelColorSwatchReadout].
  const _LabelColorSwatchReadout({
    required this.colorHex,
    required this.colorValue,
  });

  /// Persisted `#RRGGBB` string, or empty when unset.
  final String colorHex;

  /// Parsed ARGB integer color, or `null` when unset.
  final int? colorValue;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final hasColor = colorHex.isNotEmpty && colorValue != null;
    final swatchColor = switch (colorValue) {
      final int value => Color(value),
      null => Colors.transparent,
    };

    return Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Container(
            width: 14.0,
            height: 14.0,
            decoration: BoxDecoration(
              color: swatchColor,
              borderRadius: BorderRadius.circular(tokens.radii.dotLg),
              border: Border.all(
                color: hasColor ? colors.line : colors.muted,
                width: tokens.radii.borderWidth,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8.0),
        Text(
          hasColor ? colorHex.toUpperCase() : localizations.labelColorHint,
          style: hasColor
              ? UiTypographyTokens.mono(
                  tokens.typography.monoSmall.copyWith(color: colors.ink),
                )
              : tokens.typography.meta.copyWith(color: colors.muted),
        ),
      ],
    );
  }
}

/// Inline Color editor inset card embedding [UiColorWheel] and [EntityInlineEditorFooter].
class _LabelColorEditCard extends StatelessWidget {
  /// Creates a [_LabelColorEditCard].
  const _LabelColorEditCard({
    required this.selectedColor,
    required this.hasPersistedColor,
    required this.errorText,
    required this.isBusy,
    required this.onColorChanged,
    required this.onClear,
    required this.onCancel,
    required this.onSave,
  });

  /// Optional inline validation or persistence error text.
  final String? errorText;

  /// Controls visibility of the footer `Clear` button.
  final bool hasPersistedColor;

  /// Disables controls while submitting.
  final bool isBusy;

  /// Callback cancelling inline editing.
  final VoidCallback onCancel;

  /// Callback clearing the persisted label color.
  final Future<void> Function() onClear;

  /// Callback emitted when the user chooses a color in [UiColorWheel].
  final ValueChanged<Color> onColorChanged;

  /// Callback saving the selected `#RRGGBB` color.
  final Future<void> Function() onSave;

  /// Active selected color.
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      isEditing: true,
      headerIcon: Icons.palette_outlined,
      headerTitle: localizations.labelColorSectionTitle,
      footer: EntityInlineEditorFooter(
        errorText: errorText,
        clearLabel: hasPersistedColor ? localizations.inlineClearAction : null,
        onClear: hasPersistedColor ? () => unawaited(onClear()) : null,
        onCancel: onCancel,
        onSave: () => unawaited(onSave()),
        isBusy: isBusy,
      ),
      child: _LabelColorWheelField(
        value: selectedColor,
        enabled: !isBusy,
        onChanged: onColorChanged,
      ),
    );
  }
}

/// Always-visible Board Scope inset card with a live 2-way [UiSegmentedControl] (`U-CARD-003`).
class _LabelScopeSection extends StatelessWidget {
  /// Creates a [_LabelScopeSection].
  const _LabelScopeSection({
    required this.labelId,
    required this.isScoped,
    required this.enabled,
    required this.onChanged,
  });

  /// Whether the segmented control accepts input.
  final bool enabled;

  /// Whether `Scoped Queue` is currently active.
  final bool isScoped;

  /// Label identifier (or `'draft'`) for deterministic keys.
  final String labelId;

  /// Callback invoked when the scope segment changes.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiCard.inset(
      headerIcon: Icons.layers_outlined,
      headerTitle: localizations.labelScopedSectionTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          UiSegmentedControl<bool>(
            key: ValueKey<String>('label_scope_switch_$labelId'),
            semanticLabel: localizations.labelScopedSectionTitle,
            value: isScoped,
            enabled: enabled,
            onChanged: onChanged,
            segments: <UiSegment<bool>>[
              UiSegment<bool>(
                value: false,
                label: localizations.globalContextLabel,
              ),
              UiSegment<bool>(
                value: true,
                label: localizations.scopedQueueLabel,
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.space2),
          Text(
            localizations.labelScopedSwitchSubtitle,
            style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
          ),
        ],
      ),
    );
  }
}

/// Bottom dashed `+ Add` chips bar for unset optional Label sections (`+ Note`, `+ Links`, `+ Conditions`).
class _LabelUnsetChipsBar extends StatelessWidget {
  /// Creates a [_LabelUnsetChipsBar].
  const _LabelUnsetChipsBar({
    required this.sections,
    required this.enabled,
    required this.onSelectSection,
  });

  /// Whether chips accept clicks.
  final bool enabled;

  /// Callback opening inline edit mode for the selected section.
  final ValueChanged<LabelSectionKind> onSelectSection;

  /// Ordered unset optional sections to expose as dashed chips.
  final List<LabelSectionKind> sections;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        for (final section in sections)
          _LabelUnsetSectionChip(
            section: section,
            enabled: enabled,
            onPressed: () => onSelectSection(section),
          ),
      ],
    );
  }
}

/// Single dashed `+ Add` chip opening inline editing for an unset [LabelSectionKind].
class _LabelUnsetSectionChip extends StatelessWidget {
  /// Creates a [_LabelUnsetSectionChip].
  const _LabelUnsetSectionChip({
    required this.section,
    required this.enabled,
    required this.onPressed,
  });

  /// Whether the chip accepts interaction.
  final bool enabled;

  /// Callback opening inline editing for [section].
  final VoidCallback onPressed;

  /// Unset label section represented by this chip.
  final LabelSectionKind section;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final metadata = _labelSectionChipMetadata(section, localizations);
    return UiPill(
      label: metadata.label,
      icon: metadata.icon,
      variant: UiPillVariant.addField,
      enabled: enabled,
      onPressed: enabled ? onPressed : null,
    );
  }
}

/// Renders an inline `danger` live-region validation or persistence error line.
class _LabelsErrorText extends StatelessWidget {
  /// Creates a [_LabelsErrorText].
  const _LabelsErrorText({required this.message});

  /// Localized error copy to display.
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: tokens.typography.meta.copyWith(
          color: tokens.colors.danger,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Clears all activation conditions on [labelId] and surfaces any failure via a danger floating notice.
Future<void> _clearLabelConditions(
  BuildContext context,
  WidgetRef ref,
  String labelId,
) async {
  final result = await ref
      .read(entityV2ControllerProvider.notifier)
      .clearLabelConditions(labelId, locale: Localizations.localeOf(context));
  if (!context.mounted) {
    return;
  }
  _reportActionFailure(ref, result);
}

/// Clears the optional note on [labelId] and surfaces any failure via a danger floating notice.
Future<void> _clearLabelNote(
  BuildContext context,
  WidgetRef ref,
  String labelId,
) async {
  final result = await ref
      .read(entityV2ControllerProvider.notifier)
      .clearLabelNote(labelId, locale: Localizations.localeOf(context));
  if (!context.mounted) {
    return;
  }
  _reportActionFailure(ref, result);
}

/// Confirms deletion of [labelId] and surfaces any persistence failure via a danger floating notice.
Future<void> _confirmDeleteLabel(
  BuildContext context,
  WidgetRef ref,
  String labelId,
) async {
  final result = await ref
      .read(entityV2ControllerProvider.notifier)
      .deleteLabel(labelId, locale: Localizations.localeOf(context));
  if (!context.mounted) {
    return;
  }
  _reportActionFailure(ref, result);
}

/// Copies canonical [labelId] to the system clipboard and emits [copiedNotice].
Future<void> _copyLabelId(
  BuildContext context,
  WidgetRef ref, {
  required String labelId,
  required String copiedNotice,
}) async {
  await Clipboard.setData(ClipboardData(text: labelId));
  if (!context.mounted) {
    return;
  }
  ref.read(floatingNoticeControllerProvider.notifier).showNotice(copiedNotice);
}

/// Returns `true` when [note] contains at least one non-whitespace character.
bool _hasNonEmptyNote(String? note) => note != null && note.trim().isNotEmpty;

/// Resolves localized label and outline icon for an unset [LabelSectionKind] add chip.
({String label, IconData icon}) _labelSectionChipMetadata(
  LabelSectionKind section,
  AppLocalizations localizations,
) {
  return switch (section) {
    LabelSectionKind.note => (
      label: localizations.inlineAddNote,
      icon: Icons.description_outlined,
    ),
    LabelSectionKind.links => (
      label: localizations.inlineAddLinks,
      icon: Icons.link_rounded,
    ),
    LabelSectionKind.conditions => (
      label: localizations.inlineAddConditions,
      icon: Icons.tune_rounded,
    ),
    LabelSectionKind.color => (
      label: localizations.labelColorSectionTitle,
      icon: Icons.palette_outlined,
    ),
    LabelSectionKind.title => (
      label: localizations.inlineEditNameTooltip,
      icon: Icons.edit_outlined,
    ),
  };
}

/// Parses two ASCII digits starting at [offset] in [raw], returning `null` for non-digits.
int? _parseAsciiTwoDigits(String raw, int offset) {
  if (offset < 0 || offset + 2 > raw.length) {
    return null;
  }
  final tens = raw.codeUnitAt(offset) - 0x30;
  final ones = raw.codeUnitAt(offset + 1) - 0x30;
  if (tens < 0 || tens > 9 || ones < 0 || ones > 9) {
    return null;
  }
  return tens * 10 + ones;
}

/// Parses a strict 24-hour `HH:MM` string into minutes since midnight (`0..1439`), or `null` if invalid.
int? _parseDraftTimeMinutes(String raw) {
  final trimmed = raw.trim();
  if (trimmed.length != 5 || trimmed.codeUnitAt(2) != 0x3A) {
    return null;
  }
  final hours = _parseAsciiTwoDigits(trimmed, 0);
  final minutes = _parseAsciiTwoDigits(trimmed, 3);
  if (hours == null ||
      minutes == null ||
      hours < 0 ||
      hours > 23 ||
      minutes < 0 ||
      minutes > 59) {
    return null;
  }
  return hours * 60 + minutes;
}

/// Resolves the active [LabelSectionKind] targeted by [target] when it belongs to [labelId].
LabelSectionKind? _parseInlineEditSection(
  InlineEditTarget? target,
  String labelId,
) {
  if (target == null ||
      target.entity.kind != EntityKind.label ||
      target.entity.id != labelId) {
    return null;
  }
  for (final section in LabelSectionKind.values) {
    if (section.name == target.sectionKey) {
      return section;
    }
  }
  return null;
}

/// Emits a `danger` floating notice when a non-inline controller mutation returns a failure [result].
void _reportActionFailure(WidgetRef ref, V2ActionResult result) {
  switch (result) {
    case V2ActionSucceeded():
      return;
    case V2ActionValidationFailed(:final message):
      ref
          .read(floatingNoticeControllerProvider.notifier)
          .showNotice(message, tone: NoticeTone.danger);
    case V2ActionPersistFailed(:final message):
      ref
          .read(floatingNoticeControllerProvider.notifier)
          .showNotice(message, tone: NoticeTone.danger);
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

/// Resolves any draft validation error lacking a visible inline field target for the card banner.
String? _resolveDraftBannerError(
  String fallbackMessage,
  Map<String, String> fieldErrors, {
  required bool showNote,
}) {
  if (fieldErrors.isEmpty) {
    return fallbackMessage;
  }
  for (final entry in fieldErrors.entries) {
    final hasFieldTarget =
        entry.key == 'name' || (showNote && entry.key == 'note');
    if (!hasFieldTarget) {
      return entry.value;
    }
  }
  return null;
}

/// Persists an immediate live Board Scope change on [labelId] and surfaces any failure notice.
Future<void> _updateLabelScope(
  BuildContext context,
  WidgetRef ref,
  String labelId,
  bool isScoped,
) async {
  final result = await ref
      .read(entityV2ControllerProvider.notifier)
      .setLabelScoped(
        labelId,
        isScoped,
        locale: Localizations.localeOf(context),
      );
  if (!context.mounted) {
    return;
  }
  _reportActionFailure(ref, result);
}

/// Maps an ISO weekday (`1..7`) to its localized short weekday copy.
String _weekdayLabel(int isoWeekday, AppLocalizations localizations) {
  return switch (isoWeekday) {
    DateTime.monday => localizations.weekdayMon,
    DateTime.tuesday => localizations.weekdayTue,
    DateTime.wednesday => localizations.weekdayWed,
    DateTime.thursday => localizations.weekdayThu,
    DateTime.friday => localizations.weekdayFri,
    DateTime.saturday => localizations.weekdaySat,
    DateTime.sunday => localizations.weekdaySun,
    _ => '',
  };
}
