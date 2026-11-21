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
import '../../presentation/ui_v2_shell_models.dart';
import '../dialogs/app_modals.dart';
import 'entity_section_widgets.dart';

/// Default geofence radius seeded into uncommitted location draft cards.
const String _defaultDraftRadiusText = '200m';

/// Maximum Unicode scalar length for location display names (`maxTdfTextLength`).
const int _maxLocationNameLength = 500;

/// Maximum Unicode scalar length for optional location notes (`maxTdfNoteLength`).
const int _maxLocationNoteLength = 2000;

/// Maximum Unicode scalar length for location address or Plus Code sources (`maxTdfTextLength`).
const int _maxLocationSourceLength = 500;

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
      (previous, next) {
        if (previous != EntityDraftKind.location &&
            next == EntityDraftKind.location) {
          _scrollToTop();
        }
      },
    );

    final tokens = UiThemeTokens.of(context);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);
    final contentPadding = tokens.spacing.mainContentPadding(viewport);
    final viewModel = ref.watch(locationsManagerViewModelProvider);
    final isBusy = ref.watch(
      entityV2ControllerProvider.select((state) => state.isBusy),
    );

    return CustomScrollView(
      controller: _scrollController,
      slivers: <Widget>[
        _LocationsHeaderSliver(
          viewModel: viewModel,
          contentPadding: contentPadding,
          quickCreateController: _quickCreateController,
          quickCreateFocusNode: _quickCreateFocusNode,
          isBusy: isBusy,
          onBack: _handleBackNavigation,
          onExpandDraft: _handleOpenDraft,
          onSubmitQuickCreate: _handleQuickCreateSubmit,
        ),
        _LocationsCardListSliver(
          locations: viewModel.locations,
          contentPadding: contentPadding,
          isBusy: isBusy,
        ),
      ],
    );
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

  /// Dispatches Quick-Create persistence through [EntityV2Controller.quickCreateLocation].
  Future<void> _submitQuickCreate() async {
    final isBusy = ref.read(entityV2ControllerProvider).isBusy;
    if (isBusy) {
      return;
    }
    final result = await ref
        .read(entityV2ControllerProvider.notifier)
        .quickCreateLocation(
          _quickCreateController.text,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        _quickCreateController.clear();
      case V2ActionValidationFailed(:final message, :final fieldErrors):
        if (!fieldErrors.containsKey('limit')) {
          ref
              .read(floatingNoticeControllerProvider.notifier)
              .showNotice(message, tone: NoticeTone.danger);
        }
        _quickCreateFocusNode.requestFocus();
      case V2ActionPersistFailed(:final message):
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(message, tone: NoticeTone.danger);
    }
  }
}

/// Bottom hairline-divided `+ Add` chips bar for unset optional location sections (`U-CARD-002`).
class _LocationAddChipsBar extends StatelessWidget {
  /// Creates a [_LocationAddChipsBar].
  const _LocationAddChipsBar({
    required this.locationId,
    required this.unsetSections,
    required this.activeInlineSection,
    required this.isBusy,
    required this.onOpenSection,
  });

  /// Currently open inline section key on this location card, if any.
  final String? activeInlineSection;

  /// Disables add chips while an entity mutation is running.
  final bool isBusy;

  /// Canonical location identifier used for deterministic chip keys.
  final String locationId;

  /// Callback opening the inline editor for a chosen section.
  final ValueChanged<LocationSectionKind> onOpenSection;

  /// Unset optional sections reported by [LocationCardViewModel.unsetSections].
  final List<LocationSectionKind> unsetSections;

  @override
  Widget build(BuildContext context) {
    final visibleSections = <LocationSectionKind>[
      for (final section in unsetSections)
        if (section.name != activeInlineSection) section,
    ];
    if (visibleSections.isEmpty) {
      return const SizedBox.shrink();
    }
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
        padding: const EdgeInsets.only(top: 10.0),
        child: Wrap(
          spacing: 6.0,
          runSpacing: 6.0,
          children: <Widget>[
            for (final section in visibleSections)
              _LocationAddFieldChip(
                locationId: locationId,
                section: section,
                isBusy: isBusy,
                onOpenSection: onOpenSection,
              ),
          ],
        ),
      ),
    );
  }
}

/// Dashed `+ Add` chip mapping one [LocationSectionKind] to its inline editor trigger.
class _LocationAddFieldChip extends StatelessWidget {
  /// Creates a [_LocationAddFieldChip].
  const _LocationAddFieldChip({
    required this.locationId,
    required this.section,
    required this.isBusy,
    required this.onOpenSection,
  });

  /// Disables interaction while a mutation is active.
  final bool isBusy;

  /// Canonical location identifier used for the widget key.
  final String locationId;

  /// Callback opening inline editing for [section].
  final ValueChanged<LocationSectionKind> onOpenSection;

  /// Target unset section represented by this chip.
  final LocationSectionKind section;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final (label, icon) = switch (section) {
      LocationSectionKind.note => (
        localizations.inlineAddNote,
        Icons.description_outlined,
      ),
      LocationSectionKind.coordinates => (
        localizations.locationCoordinatesSectionTitle,
        Icons.my_location_rounded,
      ),
      LocationSectionKind.title => (
        localizations.locationNameLabel,
        Icons.edit_outlined,
      ),
    };

    return UiPill(
      key: ValueKey<String>('location_add_${section.name}_$locationId'),
      label: label,
      icon: icon,
      variant: UiPillVariant.addField,
      enabled: !isBusy,
      onPressed: isBusy ? null : () => onOpenSection(section),
    );
  }
}

/// Uncapped collapsed metadata badge strip for a Location card (`U-CARD-005`).
class _LocationCardCollapsedMetadata extends StatelessWidget {
  /// Creates a [_LocationCardCollapsedMetadata].
  const _LocationCardCollapsedMetadata({
    required this.location,
    required this.onToggleExpand,
  });

  /// Location card view model providing formatted badge labels.
  final LocationCardViewModel location;

  /// Callback toggling expansion of the owning location card.
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final noteText = location.note;
    final hasNote = noteText != null && noteText.trim().isNotEmpty;

    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        UiPill(
          label: location.sourceTypeLabel,
          icon: Icons.my_location_rounded,
          variant: UiPillVariant.meta,
          onPressed: onToggleExpand,
        ),
        UiPill(
          label: location.coordinatesSummary,
          variant: UiPillVariant.meta,
          isMono: true,
          onPressed: onToggleExpand,
        ),
        UiPill(
          label: localizations.openTasksCountPill('${location.openCount}'),
          variant: UiPillVariant.meta,
          tone: UiPillTone.soft,
          onPressed: onToggleExpand,
        ),
        if (hasNote)
          UiPill(
            label: localizations.taskNoteLabel,
            icon: Icons.description_outlined,
            variant: UiPillVariant.meta,
            onPressed: onToggleExpand,
          ),
      ],
    );
  }
}

/// Expanded Location card body composing meta bar and progressive-disclosure sections (`U-CARD-002`).
class _LocationCardExpandedPanel extends StatelessWidget {
  /// Creates a [_LocationCardExpandedPanel].
  const _LocationCardExpandedPanel({
    required this.location,
    required this.activeInlineSection,
    required this.isConfirmingDelete,
    required this.isBusy,
    required this.onCopyId,
    required this.onRequestDelete,
    required this.onCancelDelete,
    required this.onConfirmDelete,
    required this.onOpenSection,
    required this.onCancelInlineEdit,
    required this.onSaveNote,
    required this.onClearNote,
  });

  /// Currently open inline section key on this location card, if any.
  final String? activeInlineSection;

  /// Whether an entity mutation is currently in progress.
  final bool isBusy;

  /// Whether the inline delete confirmation prompt is open for this card.
  final bool isConfirmingDelete;

  /// Expanded location view model.
  final LocationCardViewModel location;

  /// Callback cancelling inline delete confirmation.
  final VoidCallback onCancelDelete;

  /// Callback cancelling the active inline section editor.
  final VoidCallback onCancelInlineEdit;

  /// Callback clearing the location note.
  final Future<void> Function() onClearNote;

  /// Callback confirming deletion of this location.
  final VoidCallback onConfirmDelete;

  /// Callback copying the location ID to the clipboard.
  final VoidCallback onCopyId;

  /// Callback opening a specific section editor.
  final ValueChanged<LocationSectionKind> onOpenSection;

  /// Callback opening inline delete confirmation.
  final VoidCallback onRequestDelete;

  /// Callback persisting an edited location note.
  final Future<V2ActionResult> Function(String rawNote) onSaveNote;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        EntityCardMetaBar(
          entityId: location.id,
          copyIdTooltip: localizations.actionCopy,
          onCopyId: onCopyId,
          statusPillLabel: localizations.openTasksCountPill(
            '${location.openCount}',
          ),
          statusPillTone: UiPillTone.soft,
          deleteTooltip: localizations.tooltipDeleteLocation,
          deleteConfirmMessage: localizations.inlineDeleteLocationConfirm,
          isConfirmingDelete: isConfirmingDelete,
          onRequestDelete: onRequestDelete,
          onCancelDelete: onCancelDelete,
          onConfirmDelete: onConfirmDelete,
        ),
        SizedBox(height: tokens.spacing.space3),
        _LocationCardExpandedSections(
          location: location,
          activeInlineSection: activeInlineSection,
          isBusy: isBusy,
          onOpenSection: onOpenSection,
          onCancelInlineEdit: onCancelInlineEdit,
          onSaveNote: onSaveNote,
          onClearNote: onClearNote,
        ),
      ],
    );
  }
}

/// Populated Note section, always-visible Coordinates & Radius section, and `+ Add` bar inside an expanded Location card.
class _LocationCardExpandedSections extends StatelessWidget {
  /// Creates a [_LocationCardExpandedSections].
  const _LocationCardExpandedSections({
    required this.location,
    required this.activeInlineSection,
    required this.isBusy,
    required this.onOpenSection,
    required this.onCancelInlineEdit,
    required this.onSaveNote,
    required this.onClearNote,
  });

  /// Currently open inline section key on this location card, if any.
  final String? activeInlineSection;

  /// Whether an entity mutation is currently active.
  final bool isBusy;

  /// Expanded location view model.
  final LocationCardViewModel location;

  /// Callback cancelling the active inline editor.
  final VoidCallback onCancelInlineEdit;

  /// Callback clearing the persisted location note.
  final Future<void> Function() onClearNote;

  /// Callback opening a specific section editor.
  final ValueChanged<LocationSectionKind> onOpenSection;

  /// Callback persisting an edited location note.
  final Future<V2ActionResult> Function(String rawNote) onSaveNote;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final isEditingNote = activeInlineSection == LocationSectionKind.note.name;
    final isEditingCoordinates =
        activeInlineSection == LocationSectionKind.coordinates.name;
    final noteText = location.note;
    final showNoteSection =
        isEditingNote || (noteText != null && noteText.trim().isNotEmpty);
    final hasAddChips = location.unsetSections.any(
      (section) => section.name != activeInlineSection,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showNoteSection) ...<Widget>[
          EntityNoteSection(
            key: ValueKey<String>('location_note_section_${location.id}'),
            note: location.note,
            isEditing: isEditingNote,
            canEdit: true,
            isBusy: isBusy,
            onStartEdit: () => onOpenSection(LocationSectionKind.note),
            onCancelEdit: onCancelInlineEdit,
            onSave: onSaveNote,
            onClear: onClearNote,
          ),
          SizedBox(height: tokens.spacing.space3),
        ],
        _LocationCoordinatesSection(
          location: location,
          isEditing: isEditingCoordinates,
          isBusy: isBusy,
          onStartEdit: () => onOpenSection(LocationSectionKind.coordinates),
          onCancelEdit: onCancelInlineEdit,
        ),
        if (hasAddChips) ...<Widget>[
          SizedBox(height: tokens.spacing.space3),
          _LocationAddChipsBar(
            locationId: location.id,
            unsetSections: location.unsetSections,
            activeInlineSection: activeInlineSection,
            isBusy: isBusy,
            onOpenSection: onOpenSection,
          ),
        ],
      ],
    );
  }
}

/// Leading `18px` accent map-pin inside the `34x34px` optical box toggling card expansion (`U-CARD-001`).
class _LocationCardLeadingIcon extends StatelessWidget {
  /// Creates a [_LocationCardLeadingIcon].
  const _LocationCardLeadingIcon({
    required this.isExpanded,
    required this.semanticLabel,
    required this.onPressed,
  });

  /// Whether the owning location card is expanded.
  final bool isExpanded;

  /// Callback toggling card expansion.
  final VoidCallback onPressed;

  /// Accessible location name announced by assistive technologies.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Semantics(
      button: true,
      expanded: isExpanded,
      label: semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: tokens.spacing.chromeControlHeight,
            child: Center(
              child: Icon(
                Icons.location_on_outlined,
                size: tokens.spacing.iconMd,
                color: tokens.colors.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Single numeric monospace coordinate field supporting GPS editability and `0.72` read-only opacity.
class _LocationCoordinateInputField extends StatelessWidget {
  /// Creates a [_LocationCoordinateInputField].
  const _LocationCoordinateInputField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.hintText,
    required this.readOnly,
    required this.enabled,
    required this.onFieldChanged,
  });

  /// Controller holding the decimal coordinate string.
  final TextEditingController controller;

  /// Whether the field is enabled.
  final bool enabled;

  /// Deterministic widget key for the input field.
  final Key fieldKey;

  /// Coordinate example placeholder text.
  final String hintText;

  /// Localized field caption (`Latitude` or `Longitude`).
  final String label;

  /// Callback clearing stale errors when text changes.
  final VoidCallback onFieldChanged;

  /// Renders read-only at `0.72` opacity when coordinate source is Address or Plus Code.
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return UiField(
      key: fieldKey,
      controller: controller,
      label: label,
      hintText: hintText,
      isMonospace: true,
      readOnly: readOnly,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      onChanged: (_) => onFieldChanged(),
    );
  }
}

/// Mutually gated `Use Current GPS` vs `Resolve` action buttons (`U-CARD-002`).
class _LocationCoordinatesActionRow extends StatelessWidget {
  /// Creates a [_LocationCoordinatesActionRow].
  const _LocationCoordinatesActionRow({
    required this.keyPrefix,
    required this.sourceType,
    required this.isBusy,
    required this.isResolving,
    required this.onUseCurrentGps,
    required this.onResolveSource,
  });

  /// Disables actions while a persistence mutation is in progress.
  final bool isBusy;

  /// Disables actions and spins the active lookup button while resolving.
  final bool isResolving;

  /// Stable prefix for deterministic widget keys.
  final String keyPrefix;

  /// Callback resolving address or Plus Code inputs.
  final VoidCallback onResolveSource;

  /// Callback applying the current foreground GPS fix.
  final VoidCallback onUseCurrentGps;

  /// Active coordinate source mode governing mutual gating.
  final ShellLocationSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isGps = sourceType == ShellLocationSourceType.gps;
    final canUseGps = isGps && !isBusy && !isResolving;
    final canResolve = !isGps && !isBusy && !isResolving;

    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: <Widget>[
        UiButton(
          key: ValueKey<String>('${keyPrefix}_use_gps_button'),
          label: localizations.locationUseCurrentGpsButton,
          leadingIcon: isResolving && isGps
              ? Icons.sync_rounded
              : Icons.my_location_rounded,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          isLoading: isResolving && isGps,
          onPressed: canUseGps ? onUseCurrentGps : null,
        ),
        UiButton(
          key: ValueKey<String>('${keyPrefix}_resolve_button'),
          label: localizations.locationResolveButton,
          leadingIcon: isResolving && !isGps
              ? Icons.sync_rounded
              : Icons.search_rounded,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          isLoading: isResolving && !isGps,
          onPressed: canResolve ? onResolveSource : null,
        ),
      ],
    );
  }
}

/// Accent-bordered inset well hosting the inline Coordinates & Radius editor and footer.
class _LocationCoordinatesEditCard extends StatelessWidget {
  /// Creates a [_LocationCoordinatesEditCard].
  const _LocationCoordinatesEditCard({
    required this.locationId,
    required this.sourceType,
    required this.sourceController,
    required this.latitudeController,
    required this.longitudeController,
    required this.radiusController,
    required this.sourceErrorText,
    required this.radiusErrorText,
    required this.errorText,
    required this.isBusy,
    required this.isResolving,
    required this.onSourceTypeChanged,
    required this.onUseCurrentGps,
    required this.onResolveSource,
    required this.onFieldChanged,
    required this.onCancel,
    required this.onSave,
  });

  /// Footer validation or resolution error message.
  final String? errorText;

  /// Disables actions while saving.
  final bool isBusy;

  /// Disables lookups while resolving GPS or geocoding.
  final bool isResolving;

  /// Latitude text controller.
  final TextEditingController latitudeController;

  /// Canonical location identifier.
  final String locationId;

  /// Longitude text controller.
  final TextEditingController longitudeController;

  /// Callback cancelling inline edit mode.
  final VoidCallback onCancel;

  /// Callback clearing stale errors when inputs change.
  final VoidCallback onFieldChanged;

  /// Callback resolving address or Plus Code inputs.
  final VoidCallback onResolveSource;

  /// Callback saving edited coordinates and radius.
  final VoidCallback onSave;

  /// Callback switching [ShellLocationSourceType].
  final ValueChanged<ShellLocationSourceType> onSourceTypeChanged;

  /// Callback applying the active foreground GPS fix.
  final VoidCallback onUseCurrentGps;

  /// Geofence radius text controller.
  final TextEditingController radiusController;

  /// Inline radius field validation error.
  final String? radiusErrorText;

  /// Address or Plus Code source text controller.
  final TextEditingController sourceController;

  /// Inline source field validation error.
  final String? sourceErrorText;

  /// Currently selected coordinate source type.
  final ShellLocationSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      key: ValueKey<String>('location_coords_editor_$locationId'),
      isEditing: true,
      headerIcon: Icons.my_location_rounded,
      headerTitle: localizations.locationCoordinatesSectionTitle,
      footer: EntityInlineEditorFooter(
        errorText: errorText,
        isBusy: isBusy,
        onCancel: onCancel,
        onSave: onSave,
      ),
      child: _LocationCoordinatesEditorFields(
        keyPrefix: 'location_coords_$locationId',
        sourceType: sourceType,
        sourceController: sourceController,
        latitudeController: latitudeController,
        longitudeController: longitudeController,
        radiusController: radiusController,
        sourceErrorText: sourceErrorText,
        radiusErrorText: radiusErrorText,
        isBusy: isBusy,
        isResolving: isResolving,
        onSourceTypeChanged: onSourceTypeChanged,
        onUseCurrentGps: onUseCurrentGps,
        onResolveSource: onResolveSource,
        onFieldChanged: onFieldChanged,
      ),
    );
  }
}

/// Shared Coordinates & Radius form fields used by both Location Draft Card and inline card edit.
class _LocationCoordinatesEditorFields extends StatelessWidget {
  /// Creates a [_LocationCoordinatesEditorFields].
  const _LocationCoordinatesEditorFields({
    required this.keyPrefix,
    required this.sourceType,
    required this.sourceController,
    required this.latitudeController,
    required this.longitudeController,
    required this.radiusController,
    required this.isBusy,
    required this.isResolving,
    required this.onSourceTypeChanged,
    required this.onUseCurrentGps,
    required this.onResolveSource,
    required this.onFieldChanged,
    this.sourceErrorText,
    this.radiusErrorText,
  });

  /// Whether a persistence mutation is currently active.
  final bool isBusy;

  /// Whether a GPS or geocoding lookup is currently active.
  final bool isResolving;

  /// Stable prefix for deterministic widget keys.
  final String keyPrefix;

  /// Controller for the WGS-84 latitude input.
  final TextEditingController latitudeController;

  /// Controller for the WGS-84 longitude input.
  final TextEditingController longitudeController;

  /// Callback notified whenever any text field changes.
  final VoidCallback onFieldChanged;

  /// Callback resolving the current address or Plus Code source.
  final VoidCallback onResolveSource;

  /// Callback switching the selected [ShellLocationSourceType].
  final ValueChanged<ShellLocationSourceType> onSourceTypeChanged;

  /// Callback applying the current foreground GPS fix.
  final VoidCallback onUseCurrentGps;

  /// Controller for the geofence radius input (`0.01m..100km`, accepting `m`/`km` and `,`/`.`).
  final TextEditingController radiusController;

  /// Optional inline validation error for [radiusController].
  final String? radiusErrorText;

  /// Controller for the optional address or Plus Code source input.
  final TextEditingController sourceController;

  /// Optional inline validation error for [sourceController].
  final String? sourceErrorText;

  /// Active coordinate source mode (`gps`, `address`, or `plusCode`).
  final ShellLocationSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final isGps = sourceType == ShellLocationSourceType.gps;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LocationSourceSelectorField(
          keyPrefix: keyPrefix,
          sourceType: sourceType,
          enabled: !isBusy && !isResolving,
          onChanged: onSourceTypeChanged,
        ),
        if (!isGps) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          _LocationSourceInputField(
            keyPrefix: keyPrefix,
            sourceType: sourceType,
            controller: sourceController,
            enabled: !isBusy && !isResolving,
            errorText: sourceErrorText,
            onFieldChanged: onFieldChanged,
            onResolveSource: onResolveSource,
          ),
        ],
        SizedBox(height: tokens.spacing.space2),
        _LocationCoordinatesActionRow(
          keyPrefix: keyPrefix,
          sourceType: sourceType,
          isBusy: isBusy,
          isResolving: isResolving,
          onUseCurrentGps: onUseCurrentGps,
          onResolveSource: onResolveSource,
        ),
        SizedBox(height: tokens.spacing.space2),
        _LocationLatitudeLongitudeRadiusFields(
          keyPrefix: keyPrefix,
          isGps: isGps,
          isBusy: isBusy,
          latitudeController: latitudeController,
          longitudeController: longitudeController,
          radiusController: radiusController,
          radiusErrorText: radiusErrorText,
          onFieldChanged: onFieldChanged,
        ),
      ],
    );
  }
}

/// Read-only coordinates summary lines displaying optional source text, monospace WGS-84 pair, and radius.
class _LocationCoordinatesReadOnlyBody extends StatelessWidget {
  /// Creates a [_LocationCoordinatesReadOnlyBody].
  const _LocationCoordinatesReadOnlyBody({required this.location});

  /// Persisted location view model.
  final LocationCardViewModel location;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final showSourceValue =
        location.sourceType != ShellLocationSourceType.gps &&
        location.sourceValue.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showSourceValue) ...<Widget>[
          Text(
            location.sourceValue,
            style: tokens.typography.control.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 4.0),
        ],
        SelectableText(
          '${location.latitudeText}, ${location.longitudeText}',
          style: UiTypographyTokens.mono(
            tokens.typography.monoSmall.copyWith(color: colors.ink),
          ),
        ),
        const SizedBox(height: 4.0),
        Text(
          localizations.locationRadiusReadout(location.radiusSummary),
          style: tokens.typography.meta.copyWith(color: colors.muted),
        ),
      ],
    );
  }
}

/// Read-only inset well rendering persisted location source, monospace coordinates, and radius readout.
class _LocationCoordinatesReadOnlyCard extends StatelessWidget {
  /// Creates a [_LocationCoordinatesReadOnlyCard].
  const _LocationCoordinatesReadOnlyCard({
    required this.location,
    required this.isBusy,
    required this.onStartEdit,
  });

  /// Disables the edit trigger while a mutation is in flight.
  final bool isBusy;

  /// Persisted location view model.
  final LocationCardViewModel location;

  /// Callback opening inline coordinate editing.
  final VoidCallback onStartEdit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      key: ValueKey<String>('location_coords_section_${location.id}'),
      headerIcon: Icons.my_location_rounded,
      headerTitle: localizations.locationCoordinatesSectionTitle,
      headerBadge: UiPill(
        label: location.sourceTypeLabel,
        variant: UiPillVariant.badge,
      ),
      headerTrailing: UiButton(
        key: ValueKey<String>('location_edit_coords_button_${location.id}'),
        leadingIcon: Icons.edit_outlined,
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.dense,
        tooltip: localizations.actionEdit,
        onPressed: isBusy ? null : onStartEdit,
      ),
      child: _LocationCoordinatesReadOnlyBody(location: location),
    );
  }
}

/// Always-visible Coordinates & Radius section supporting read-only display and inline source/geocoding editing.
class _LocationCoordinatesSection extends ConsumerStatefulWidget {
  /// Creates a [_LocationCoordinatesSection].
  const _LocationCoordinatesSection({
    required this.location,
    required this.isEditing,
    required this.isBusy,
    required this.onStartEdit,
    required this.onCancelEdit,
  });

  /// Whether a parent entity mutation is currently running.
  final bool isBusy;

  /// Whether this section is currently in inline edit mode.
  final bool isEditing;

  /// Persisted location view model.
  final LocationCardViewModel location;

  /// Callback cancelling inline coordinate editing.
  final VoidCallback onCancelEdit;

  /// Callback entering inline coordinate editing.
  final VoidCallback onStartEdit;

  @override
  ConsumerState<_LocationCoordinatesSection> createState() =>
      _LocationCoordinatesSectionState();
}

/// Manages inline coordinate/source controllers, geocoding resolution, and save validation for [_LocationCoordinatesSection].
class _LocationCoordinatesSectionState
    extends ConsumerState<_LocationCoordinatesSection> {
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  late final TextEditingController _radiusController;
  late final TextEditingController _sourceController;

  String? _errorText;
  Map<String, String> _fieldErrors = const <String, String>{};
  bool _isSubmitting = false;
  late ShellLocationSourceType _sourceType;

  @override
  void initState() {
    super.initState();
    _sourceType = widget.location.sourceType;
    _sourceController = TextEditingController(
      text: widget.location.sourceValue,
    );
    _latitudeController = TextEditingController(
      text: widget.location.latitudeText,
    );
    _longitudeController = TextEditingController(
      text: widget.location.longitudeText,
    );
    _radiusController = TextEditingController(text: widget.location.radiusText);
  }

  @override
  void didUpdateWidget(covariant _LocationCoordinatesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _resetDraftFromLocation(widget.location);
    } else if (oldWidget.isEditing && !widget.isEditing) {
      _errorText = null;
      _fieldErrors = const <String, String>{};
      _isSubmitting = false;
    }
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEditing) {
      return _LocationCoordinatesReadOnlyCard(
        location: widget.location,
        isBusy: widget.isBusy,
        onStartEdit: widget.onStartEdit,
      );
    }
    final isResolving = ref.watch(
      entityV2ControllerProvider.select((state) => state.isResolvingLocation),
    );
    return _LocationCoordinatesEditCard(
      locationId: widget.location.id,
      sourceType: _sourceType,
      sourceController: _sourceController,
      latitudeController: _latitudeController,
      longitudeController: _longitudeController,
      radiusController: _radiusController,
      sourceErrorText: _fieldErrors['source'],
      radiusErrorText: _fieldErrors['radius'],
      errorText: _errorText,
      isBusy: widget.isBusy || _isSubmitting,
      isResolving: isResolving,
      onSourceTypeChanged: _handleSourceTypeChanged,
      onUseCurrentGps: () => unawaited(_handleUseCurrentGps()),
      onResolveSource: () => unawaited(_handleResolveSource()),
      onFieldChanged: _clearErrors,
      onCancel: widget.onCancelEdit,
      onSave: () => unawaited(_handleSave()),
    );
  }

  /// Clears inline validation and lookup errors when the user edits an input.
  void _clearErrors() {
    if (_errorText == null && _fieldErrors.isEmpty) {
      return;
    }
    setState(() {
      _errorText = null;
      _fieldErrors = const <String, String>{};
    });
  }

  /// Resolves address or Plus Code input and opens disambiguation when multiple matches exist.
  Future<void> _handleResolveSource() async {
    _clearErrors();
    final outcome = await _resolveLocationSourceWithDisambiguation(
      context,
      ref,
      sourceType: _sourceType,
      rawSource: _sourceController.text,
    );
    if (!mounted || outcome == null) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    switch (outcome) {
      case LocationV2SourceResolved(
        :final latitudeText,
        :final longitudeText,
        :final normalizedSource,
        :final sourceType,
      ):
        setState(() {
          _sourceType = sourceType;
          _sourceController.text = normalizedSource;
          _latitudeController.text = latitudeText;
          _longitudeController.text = longitudeText;
          _errorText = null;
          _fieldErrors = const <String, String>{};
        });
      case LocationV2SourceError(:final message):
        setState(() => _errorText = message);
      case LocationV2SourceNeedsDisambiguation():
        setState(() => _errorText = localizations.locationResolveErrorNotFound);
    }
  }

  /// Validates and persists coordinates, source, and radius via [EntityV2Controller.saveLocationCoordinates].
  Future<void> _handleSave() async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
      _fieldErrors = const <String, String>{};
    });
    final result = await ref
        .read(entityV2ControllerProvider.notifier)
        .saveLocationCoordinates(
          widget.location.id,
          sourceType: _sourceType,
          rawSource: _sourceController.text,
          rawLatitude: _latitudeController.text,
          rawLongitude: _longitudeController.text,
          rawRadius: _radiusController.text,
          locale: Localizations.localeOf(context),
        );
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
          _errorText = _resolveBannerErrorText(
            fallbackMessage: message,
            fieldErrors: fieldErrors,
            inlineFieldKeys: const <String>{'source', 'radius'},
          );
        });
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
    }
  }

  /// Updates the active source mode and clears stale lookup errors.
  void _handleSourceTypeChanged(ShellLocationSourceType nextSourceType) {
    setState(() {
      _sourceType = nextSourceType;
      _errorText = null;
      _fieldErrors = const <String, String>{};
    });
  }

  /// Populates latitude and longitude inputs from the current foreground GPS fix.
  Future<void> _handleUseCurrentGps() async {
    _clearErrors();
    final coordinates = await ref
        .read(entityV2ControllerProvider.notifier)
        .resolveCurrentGpsPosition(locale: Localizations.localeOf(context));
    if (!mounted) {
      return;
    }
    if (coordinates case (:final latitudeText, :final longitudeText)) {
      setState(() {
        _latitudeController.text = latitudeText;
        _longitudeController.text = longitudeText;
        _errorText = null;
        _fieldErrors = const <String, String>{};
      });
      return;
    }
    setState(() {
      _errorText = AppLocalizations.of(context).locationStatusUnavailable;
    });
  }

  /// Re-seeds editor controllers from persisted [location] values when entering edit mode.
  void _resetDraftFromLocation(LocationCardViewModel location) {
    _sourceType = location.sourceType;
    _sourceController.text = location.sourceValue;
    _latitudeController.text = location.latitudeText;
    _longitudeController.text = location.longitudeText;
    _radiusController.text = location.radiusText;
    _errorText = null;
    _fieldErrors = const <String, String>{};
    _isSubmitting = false;
  }
}

/// Accent-bordered uncommitted Location Draft Card replacing Quick-Create in place (`U-CARD-006`).
class _LocationDraftCard extends ConsumerStatefulWidget {
  /// Creates a [_LocationDraftCard].
  const _LocationDraftCard({
    required this.seedTitle,
    required this.hasActiveGpsFix,
    required this.activeGpsLatitudeText,
    required this.activeGpsLongitudeText,
    required this.isBusy,
  });

  /// Active foreground GPS latitude formatted to 6 decimal places, if available.
  final String? activeGpsLatitudeText;

  /// Active foreground GPS longitude formatted to 6 decimal places, if available.
  final String? activeGpsLongitudeText;

  /// Whether a valid foreground GPS fix is currently available for seeding.
  final bool hasActiveGpsFix;

  /// Whether a parent entity mutation is currently running.
  final bool isBusy;

  /// Initial location name transferred from the Quick-Create bar.
  final String seedTitle;

  @override
  ConsumerState<_LocationDraftCard> createState() => _LocationDraftCardState();
}

/// Manages controllers, geocoding resolution, and commit submission for [_LocationDraftCard].
class _LocationDraftCardState extends ConsumerState<_LocationDraftCard> {
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  late final TextEditingController _nameController;
  late final TextEditingController _noteController;
  late final TextEditingController _radiusController;
  late final TextEditingController _sourceController;

  String? _errorText;
  Map<String, String> _fieldErrors = const <String, String>{};
  bool _isSubmitting = false;
  ShellLocationSourceType _sourceType = ShellLocationSourceType.gps;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.seedTitle);
    _sourceController = TextEditingController();
    _latitudeController = TextEditingController(
      text: widget.hasActiveGpsFix ? (widget.activeGpsLatitudeText ?? '') : '',
    );
    _longitudeController = TextEditingController(
      text: widget.hasActiveGpsFix ? (widget.activeGpsLongitudeText ?? '') : '',
    );
    _radiusController = TextEditingController(text: _defaultDraftRadiusText);
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sourceController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isResolving = ref.watch(
      entityV2ControllerProvider.select((state) => state.isResolvingLocation),
    );
    final effectiveBusy = widget.isBusy || _isSubmitting;

    return UiCard.draft(
      key: const ValueKey<String>('location_draft_card'),
      title: localizations.draftNewLocationTitle,
      subtitle: localizations.draftUncommittedHint,
      closeTooltip: localizations.actionCancel,
      onClose: effectiveBusy ? null : _handleCancel,
      errorText: _errorText,
      footer: _LocationDraftFooter(
        isBusy: effectiveBusy,
        isResolving: isResolving,
        onCancel: _handleCancel,
        onCreate: () => unawaited(_handleSubmit()),
      ),
      child: _LocationDraftFormBody(
        nameController: _nameController,
        sourceType: _sourceType,
        sourceController: _sourceController,
        latitudeController: _latitudeController,
        longitudeController: _longitudeController,
        radiusController: _radiusController,
        noteController: _noteController,
        fieldErrors: _fieldErrors,
        isBusy: effectiveBusy,
        isResolving: isResolving,
        onSourceTypeChanged: _handleSourceTypeChanged,
        onUseCurrentGps: () => unawaited(_handleUseCurrentGps()),
        onResolveSource: () => unawaited(_handleResolveSource()),
        onFieldChanged: _clearErrors,
      ),
    );
  }

  /// Clears inline draft validation and resolution errors on input changes.
  void _clearErrors() {
    if (_errorText == null && _fieldErrors.isEmpty) {
      return;
    }
    setState(() {
      _errorText = null;
      _fieldErrors = const <String, String>{};
    });
  }

  /// Discards the uncommitted location draft without persisting changes.
  void _handleCancel() {
    ref.read(appShellControllerProvider.notifier).cancelDraft();
  }

  /// Resolves the entered address or Plus Code source and handles candidate disambiguation.
  Future<void> _handleResolveSource() async {
    _clearErrors();
    final outcome = await _resolveLocationSourceWithDisambiguation(
      context,
      ref,
      sourceType: _sourceType,
      rawSource: _sourceController.text,
    );
    if (!mounted || outcome == null) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    switch (outcome) {
      case LocationV2SourceResolved(
        :final latitudeText,
        :final longitudeText,
        :final normalizedSource,
        :final sourceType,
      ):
        setState(() {
          _sourceType = sourceType;
          _sourceController.text = normalizedSource;
          _latitudeController.text = latitudeText;
          _longitudeController.text = longitudeText;
          _errorText = null;
          _fieldErrors = const <String, String>{};
        });
      case LocationV2SourceError(:final message):
        setState(() => _errorText = message);
      case LocationV2SourceNeedsDisambiguation():
        setState(() => _errorText = localizations.locationResolveErrorNotFound);
    }
  }

  /// Switches the active coordinate source mode inside the draft card.
  void _handleSourceTypeChanged(ShellLocationSourceType nextSourceType) {
    setState(() {
      _sourceType = nextSourceType;
      _errorText = null;
      _fieldErrors = const <String, String>{};
    });
  }

  /// Validates and commits the uncommitted location draft via [EntityV2Controller.createLocationDraft].
  Future<void> _handleSubmit() async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
      _fieldErrors = const <String, String>{};
    });
    final result = await ref
        .read(entityV2ControllerProvider.notifier)
        .createLocationDraft(
          LocationDraftInput(
            name: _nameController.text,
            sourceType: _sourceType,
            rawSource: _sourceController.text,
            rawLatitude: _latitudeController.text,
            rawLongitude: _longitudeController.text,
            rawRadius: _radiusController.text,
            note: _noteController.text,
          ),
          locale: Localizations.localeOf(context),
        );
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
          _errorText = _resolveBannerErrorText(
            fallbackMessage: message,
            fieldErrors: fieldErrors,
            inlineFieldKeys: const <String>{'name', 'source', 'radius', 'note'},
          );
        });
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
    }
  }

  /// Populates draft coordinates from the current foreground GPS fix.
  Future<void> _handleUseCurrentGps() async {
    _clearErrors();
    final coordinates = await ref
        .read(entityV2ControllerProvider.notifier)
        .resolveCurrentGpsPosition(locale: Localizations.localeOf(context));
    if (!mounted) {
      return;
    }
    if (coordinates case (:final latitudeText, :final longitudeText)) {
      setState(() {
        _latitudeController.text = latitudeText;
        _longitudeController.text = longitudeText;
        _errorText = null;
        _fieldErrors = const <String, String>{};
      });
      return;
    }
    setState(() {
      _errorText = AppLocalizations.of(context).locationStatusUnavailable;
    });
  }
}

/// Right-aligned `Cancel` and `Create location` footer row for [_LocationDraftCard].
class _LocationDraftFooter extends StatelessWidget {
  /// Creates a [_LocationDraftFooter].
  const _LocationDraftFooter({
    required this.isBusy,
    required this.isResolving,
    required this.onCancel,
    required this.onCreate,
  });

  /// Disables actions and spins the Create button while persisting.
  final bool isBusy;

  /// Disables Create while geocoding or GPS resolution is running.
  final bool isResolving;

  /// Callback cancelling the uncommitted draft card.
  final VoidCallback onCancel;

  /// Callback committing the uncommitted draft card.
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8.0,
        runSpacing: 8.0,
        children: <Widget>[
          UiButton(
            key: const ValueKey<String>('location_draft_cancel_button'),
            label: localizations.actionCancel,
            variant: UiButtonVariant.secondary,
            density: UiButtonDensity.compact,
            onPressed: isBusy ? null : onCancel,
          ),
          UiButton(
            key: const ValueKey<String>('location_draft_create_button'),
            label: localizations.actionCreateLocation,
            leadingIcon: isBusy ? Icons.sync_rounded : Icons.add_rounded,
            variant: UiButtonVariant.primary,
            density: UiButtonDensity.compact,
            isLoading: isBusy,
            onPressed: (isBusy || isResolving) ? null : onCreate,
          ),
        ],
      ),
    );
  }
}

/// Form body inside [_LocationDraftCard] pairing Name, Coordinates & Radius well, and Note well.
class _LocationDraftFormBody extends StatelessWidget {
  /// Creates a [_LocationDraftFormBody].
  const _LocationDraftFormBody({
    required this.nameController,
    required this.sourceType,
    required this.sourceController,
    required this.latitudeController,
    required this.longitudeController,
    required this.radiusController,
    required this.noteController,
    required this.fieldErrors,
    required this.isBusy,
    required this.isResolving,
    required this.onSourceTypeChanged,
    required this.onUseCurrentGps,
    required this.onResolveSource,
    required this.onFieldChanged,
  });

  /// Per-field validation errors keyed by logical field identifier.
  final Map<String, String> fieldErrors;

  /// Disables inputs while saving.
  final bool isBusy;

  /// Disables resolution actions while lookup is active.
  final bool isResolving;

  /// Latitude controller.
  final TextEditingController latitudeController;

  /// Longitude controller.
  final TextEditingController longitudeController;

  /// Location name controller.
  final TextEditingController nameController;

  /// Optional location note controller.
  final TextEditingController noteController;

  /// Callback clearing stale errors when inputs change.
  final VoidCallback onFieldChanged;

  /// Callback resolving address or Plus Code inputs.
  final VoidCallback onResolveSource;

  /// Callback switching [ShellLocationSourceType].
  final ValueChanged<ShellLocationSourceType> onSourceTypeChanged;

  /// Callback applying the current foreground GPS fix.
  final VoidCallback onUseCurrentGps;

  /// Geofence radius controller.
  final TextEditingController radiusController;

  /// Address or Plus Code source controller.
  final TextEditingController sourceController;

  /// Currently selected coordinate source type.
  final ShellLocationSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiField(
          key: const ValueKey<String>('location_draft_name_field'),
          controller: nameController,
          label: localizations.locationNameLabel,
          hintText: localizations.quickCreateLocationHint,
          maxLength: _maxLocationNameLength,
          autofocus: true,
          enabled: !isBusy,
          errorText: fieldErrors['name'],
          onChanged: (_) => onFieldChanged(),
        ),
        SizedBox(height: tokens.spacing.space3),
        _LocationDraftCoordinatesWell(
          sourceType: sourceType,
          sourceController: sourceController,
          latitudeController: latitudeController,
          longitudeController: longitudeController,
          radiusController: radiusController,
          sourceErrorText: fieldErrors['source'],
          radiusErrorText: fieldErrors['radius'],
          isBusy: isBusy,
          isResolving: isResolving,
          onSourceTypeChanged: onSourceTypeChanged,
          onUseCurrentGps: onUseCurrentGps,
          onResolveSource: onResolveSource,
          onFieldChanged: onFieldChanged,
        ),
        SizedBox(height: tokens.spacing.space3),
        _LocationDraftNoteWell(
          noteController: noteController,
          isBusy: isBusy,
          errorText: fieldErrors['note'],
          onFieldChanged: onFieldChanged,
        ),
      ],
    );
  }
}

/// Inset well wrapping Coordinates & Radius controls inside [_LocationDraftFormBody].
class _LocationDraftCoordinatesWell extends StatelessWidget {
  /// Creates a [_LocationDraftCoordinatesWell].
  const _LocationDraftCoordinatesWell({
    required this.sourceType,
    required this.sourceController,
    required this.latitudeController,
    required this.longitudeController,
    required this.radiusController,
    required this.sourceErrorText,
    required this.radiusErrorText,
    required this.isBusy,
    required this.isResolving,
    required this.onSourceTypeChanged,
    required this.onUseCurrentGps,
    required this.onResolveSource,
    required this.onFieldChanged,
  });

  /// Disables inputs while saving.
  final bool isBusy;

  /// Disables lookup actions while resolving.
  final bool isResolving;

  /// Latitude controller.
  final TextEditingController latitudeController;

  /// Longitude controller.
  final TextEditingController longitudeController;

  /// Callback clearing errors on input edit.
  final VoidCallback onFieldChanged;

  /// Callback resolving source text.
  final VoidCallback onResolveSource;

  /// Callback switching source type.
  final ValueChanged<ShellLocationSourceType> onSourceTypeChanged;

  /// Callback applying current GPS coordinates.
  final VoidCallback onUseCurrentGps;

  /// Geofence radius controller.
  final TextEditingController radiusController;

  /// Inline radius validation error.
  final String? radiusErrorText;

  /// Source text controller.
  final TextEditingController sourceController;

  /// Inline source validation error.
  final String? sourceErrorText;

  /// Active coordinate source mode.
  final ShellLocationSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      headerIcon: Icons.my_location_rounded,
      headerTitle: localizations.locationCoordinatesSectionTitle,
      child: _LocationCoordinatesEditorFields(
        keyPrefix: 'location_draft',
        sourceType: sourceType,
        sourceController: sourceController,
        latitudeController: latitudeController,
        longitudeController: longitudeController,
        radiusController: radiusController,
        sourceErrorText: sourceErrorText,
        radiusErrorText: radiusErrorText,
        isBusy: isBusy,
        isResolving: isResolving,
        onSourceTypeChanged: onSourceTypeChanged,
        onUseCurrentGps: onUseCurrentGps,
        onResolveSource: onResolveSource,
        onFieldChanged: onFieldChanged,
      ),
    );
  }
}

/// Inset well wrapping the optional Note textarea inside [_LocationDraftFormBody].
class _LocationDraftNoteWell extends StatelessWidget {
  /// Creates a [_LocationDraftNoteWell].
  const _LocationDraftNoteWell({
    required this.noteController,
    required this.isBusy,
    required this.errorText,
    required this.onFieldChanged,
  });

  /// Inline validation error for the note input.
  final String? errorText;

  /// Disables note input while saving.
  final bool isBusy;

  /// Multi-line note controller.
  final TextEditingController noteController;

  /// Callback clearing stale errors when text changes.
  final VoidCallback onFieldChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      headerIcon: Icons.description_outlined,
      headerTitle: localizations.taskNoteLabel,
      child: UiField(
        key: const ValueKey<String>('location_draft_note_field'),
        kind: UiFieldKind.multiline,
        controller: noteController,
        hintText: localizations.taskNoteHint,
        maxLength: _maxLocationNoteLength,
        minLines: 2,
        maxLines: 4,
        enabled: !isBusy,
        errorText: errorText,
        onChanged: (_) => onFieldChanged(),
      ),
    );
  }
}

/// Trailing inline Name Edit pencil button rendered only on expanded location cards (`U-CARD-001`).
class _LocationEditNameButton extends StatelessWidget {
  /// Creates a [_LocationEditNameButton].
  const _LocationEditNameButton({
    required this.locationId,
    required this.isBusy,
    required this.onPressed,
  });

  /// Disables the button while a mutation is in flight.
  final bool isBusy;

  /// Canonical location identifier.
  final String locationId;

  /// Callback opening inline name editing.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiButton(
      key: ValueKey<String>('location_edit_name_button_$locationId'),
      leadingIcon: Icons.edit_outlined,
      variant: UiButtonVariant.icon,
      density: UiButtonDensity.dense,
      tooltip: localizations.inlineEditNameTooltip,
      onPressed: isBusy ? null : onPressed,
    );
  }
}

/// Single expandable Location card managing reveal scrolling, inline name editing, and panel coordination.
class _LocationExpandableCard extends ConsumerStatefulWidget {
  /// Creates a [_LocationExpandableCard].
  const _LocationExpandableCard({
    super.key,
    required this.location,
    required this.isExpanded,
    required this.activeInlineSection,
    required this.isConfirmingDelete,
    required this.shouldReveal,
    required this.isBusy,
  });

  /// Currently open inline section key on this location card, or `null`.
  final String? activeInlineSection;

  /// Whether an entity mutation is currently active.
  final bool isBusy;

  /// Whether inline delete confirmation is open for this location card.
  final bool isConfirmingDelete;

  /// Whether this location card is expanded in the single-expand accordion.
  final bool isExpanded;

  /// Projected location view model.
  final LocationCardViewModel location;

  /// Whether a one-shot reveal request targets this location card.
  final bool shouldReveal;

  @override
  ConsumerState<_LocationExpandableCard> createState() =>
      _LocationExpandableCardState();
}

/// Coordinates smooth post-frame `Scrollable.ensureVisible` reveal and card action dispatching for [_LocationExpandableCard].
class _LocationExpandableCardState
    extends ConsumerState<_LocationExpandableCard> {
  @override
  void initState() {
    super.initState();
    if (widget.shouldReveal) {
      _scheduleReveal();
    }
  }

  @override
  void didUpdateWidget(covariant _LocationExpandableCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.shouldReveal && widget.shouldReveal) {
      _scheduleReveal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    final isEditingTitle =
        widget.isExpanded &&
        widget.activeInlineSection == LocationSectionKind.title.name;

    return UiCard.expandable(
      title: location.name,
      isExpanded: widget.isExpanded,
      isEditingTitle: isEditingTitle,
      onToggleExpand: _handleToggleExpand,
      leading: _LocationCardLeadingIcon(
        isExpanded: widget.isExpanded,
        semanticLabel: location.name,
        onPressed: _handleToggleExpand,
      ),
      titleEditor: isEditingTitle
          ? _LocationInlineNameEditor(
              locationId: location.id,
              initialName: location.name,
              isBusy: widget.isBusy,
              onCancel: _handleCancelInlineEdit,
            )
          : null,
      trailingActions: widget.isExpanded && !isEditingTitle
          ? <Widget>[
              _LocationEditNameButton(
                locationId: location.id,
                isBusy: widget.isBusy,
                onPressed: () => _handleOpenSection(LocationSectionKind.title),
              ),
            ]
          : const <Widget>[],
      collapsedMetadata: _LocationCardCollapsedMetadata(
        location: location,
        onToggleExpand: _handleToggleExpand,
      ),
      expandedChild: _LocationCardExpandedPanel(
        location: location,
        activeInlineSection: widget.activeInlineSection,
        isConfirmingDelete: widget.isConfirmingDelete,
        isBusy: widget.isBusy,
        onCopyId: () => unawaited(_copyLocationId(context, ref, location.id)),
        onRequestDelete: _handleRequestDelete,
        onCancelDelete: _handleCancelDelete,
        onConfirmDelete: () => unawaited(_handleConfirmDelete()),
        onOpenSection: _handleOpenSection,
        onCancelInlineEdit: _handleCancelInlineEdit,
        onSaveNote: _handleSaveNote,
        onClearNote: _handleClearNote,
      ),
    );
  }

  /// Cancels inline delete confirmation on this card.
  void _handleCancelDelete() {
    ref.read(appShellControllerProvider.notifier).cancelInlineDelete();
  }

  /// Closes the currently open inline section editor.
  void _handleCancelInlineEdit() {
    ref.read(appShellControllerProvider.notifier).closeInlineEdit();
  }

  /// Clears the location note via [EntityV2Controller.clearLocationNote].
  Future<void> _handleClearNote() async {
    final result = await ref
        .read(entityV2ControllerProvider.notifier)
        .clearLocationNote(
          widget.location.id,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    _reportActionFailure(ref, result);
  }

  /// Deletes this location via [EntityV2Controller.deleteLocation] and reports errors via floating notice.
  Future<void> _handleConfirmDelete() async {
    final result = await ref
        .read(entityV2ControllerProvider.notifier)
        .deleteLocation(
          widget.location.id,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    _reportActionFailure(ref, result);
  }

  /// Opens the single active inline editor for [section] on this location.
  void _handleOpenSection(LocationSectionKind section) {
    ref
        .read(appShellControllerProvider.notifier)
        .openInlineEdit(InlineEditTarget.location(widget.location.id, section));
  }

  /// Opens the inline delete confirmation prompt on this card.
  void _handleRequestDelete() {
    ref
        .read(appShellControllerProvider.notifier)
        .requestInlineDelete(
          EntityRef(kind: EntityKind.location, id: widget.location.id),
        );
  }

  /// Persists an edited note via [EntityV2Controller.saveLocationNote].
  Future<V2ActionResult> _handleSaveNote(String rawNote) {
    return ref
        .read(entityV2ControllerProvider.notifier)
        .saveLocationNote(
          widget.location.id,
          rawNote,
          locale: Localizations.localeOf(context),
        );
  }

  /// Toggles expansion of this location card under strict single-expand coordination.
  void _handleToggleExpand() {
    ref
        .read(appShellControllerProvider.notifier)
        .toggleExpandEntity(
          EntityRef(kind: EntityKind.location, id: widget.location.id),
        );
  }

  /// Schedules post-frame smooth reveal scrolling and clears the one-shot reveal request.
  void _scheduleReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        Scrollable.ensureVisible(
          context,
          duration: UiThemeTokens.of(context).focus.expandDuration,
          curve: Curves.easeOut,
          alignment: 0.12,
        ),
      );
      ref.read(appShellControllerProvider.notifier).clearRevealRequest();
    });
  }
}

/// Inline location name editor swapped into the card header when editing [LocationSectionKind.title].
class _LocationInlineNameEditor extends ConsumerStatefulWidget {
  /// Creates a [_LocationInlineNameEditor].
  const _LocationInlineNameEditor({
    required this.locationId,
    required this.initialName,
    required this.isBusy,
    required this.onCancel,
  });

  /// Persisted location name seeding the text field.
  final String initialName;

  /// Disables actions while a parent mutation is active.
  final bool isBusy;

  /// Canonical location identifier.
  final String locationId;

  /// Callback closing inline name editing without saving.
  final VoidCallback onCancel;

  @override
  ConsumerState<_LocationInlineNameEditor> createState() =>
      _LocationInlineNameEditorState();
}

/// Manages text controller and save validation for [_LocationInlineNameEditor].
class _LocationInlineNameEditorState
    extends ConsumerState<_LocationInlineNameEditor> {
  late final TextEditingController _controller;

  String? _errorText;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isCompact = UiBreakpoints.isCompact(MediaQuery.sizeOf(context).width);
    final effectiveBusy = widget.isBusy || _isSubmitting;

    final field = UiField(
      key: ValueKey<String>('location_name_editor_${widget.locationId}'),
      controller: _controller,
      autofocus: true,
      maxLength: _maxLocationNameLength,
      hintText: localizations.locationNameLabel,
      semanticLabel: localizations.inlineEditNameTooltip,
      enabled: !effectiveBusy,
      errorText: _errorText,
      textInputAction: TextInputAction.done,
      onChanged: _handleChanged,
      onSubmitted: (_) => unawaited(_handleSave()),
    );
    final actions = _LocationInlineNameEditorActions(
      locationId: widget.locationId,
      isBusy: effectiveBusy,
      onSave: () => unawaited(_handleSave()),
      onCancel: widget.onCancel,
    );

    if (isCompact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          field,
          const SizedBox(height: 6.0),
          Align(alignment: Alignment.centerRight, child: actions),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: field),
        const SizedBox(width: 6.0),
        actions,
      ],
    );
  }

  /// Clears inline validation errors once typing resumes.
  void _handleChanged(String _) {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  /// Validates and commits the updated location name via [EntityV2Controller.saveLocationName].
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
        .saveLocationName(
          widget.locationId,
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
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
    }
  }
}

/// Compact Save and Cancel buttons paired with [_LocationInlineNameEditor].
class _LocationInlineNameEditorActions extends StatelessWidget {
  /// Creates a [_LocationInlineNameEditorActions].
  const _LocationInlineNameEditorActions({
    required this.locationId,
    required this.isBusy,
    required this.onSave,
    required this.onCancel,
  });

  /// Disables actions and spins the Save button while submitting.
  final bool isBusy;

  /// Canonical location identifier.
  final String locationId;

  /// Callback cancelling inline name editing.
  final VoidCallback onCancel;

  /// Callback saving the edited name.
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UiButton(
          key: ValueKey<String>('location_name_save_$locationId'),
          label: localizations.actionSave,
          variant: UiButtonVariant.primary,
          density: UiButtonDensity.compact,
          isLoading: isBusy,
          onPressed: isBusy ? null : onSave,
        ),
        const SizedBox(width: 6.0),
        UiButton(
          key: ValueKey<String>('location_name_cancel_$locationId'),
          label: localizations.actionCancel,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          onPressed: isBusy ? null : onCancel,
        ),
      ],
    );
  }
}

/// Responsive latitude/longitude pair and radius input inside [_LocationCoordinatesEditorFields].
class _LocationLatitudeLongitudeRadiusFields extends StatelessWidget {
  /// Creates a [_LocationLatitudeLongitudeRadiusFields].
  const _LocationLatitudeLongitudeRadiusFields({
    required this.keyPrefix,
    required this.isGps,
    required this.isBusy,
    required this.latitudeController,
    required this.longitudeController,
    required this.radiusController,
    required this.radiusErrorText,
    required this.onFieldChanged,
  });

  /// Disables inputs while saving.
  final bool isBusy;

  /// Keeps latitude/longitude editable in GPS mode and read-only (`0.72` opacity) in non-GPS modes.
  final bool isGps;

  /// Stable prefix for deterministic widget keys.
  final String keyPrefix;

  /// Controller for the WGS-84 latitude input.
  final TextEditingController latitudeController;

  /// Controller for the WGS-84 longitude input.
  final TextEditingController longitudeController;

  /// Callback clearing stale validation errors on input changes.
  final VoidCallback onFieldChanged;

  /// Controller for the geofence radius input.
  final TextEditingController radiusController;

  /// Optional inline validation error for the radius input.
  final String? radiusErrorText;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiResponsiveGrid(
          preset: UiGridPreset.twoColumnCompactCollapse,
          spacing: tokens.spacing.space3,
          runSpacing: tokens.spacing.space2,
          children: <Widget>[
            _LocationCoordinateInputField(
              fieldKey: ValueKey<String>('${keyPrefix}_latitude_field'),
              controller: latitudeController,
              label: localizations.locationLatitudeLabel,
              hintText: '50.9787',
              readOnly: !isGps,
              enabled: !isBusy,
              onFieldChanged: onFieldChanged,
            ),
            _LocationCoordinateInputField(
              fieldKey: ValueKey<String>('${keyPrefix}_longitude_field'),
              controller: longitudeController,
              label: localizations.locationLongitudeLabel,
              hintText: '11.0328',
              readOnly: !isGps,
              enabled: !isBusy,
              onFieldChanged: onFieldChanged,
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.space2),
        UiField(
          key: ValueKey<String>('${keyPrefix}_radius_field'),
          controller: radiusController,
          label: localizations.locationRadiusLabel,
          hintText: _defaultDraftRadiusText,
          isMonospace: true,
          enabled: !isBusy,
          errorText: radiusErrorText,
          onChanged: (_) => onFieldChanged(),
        ),
      ],
    );
  }
}

/// Conditional Address or Google Plus Code text input shown when coordinate source is not GPS.
class _LocationSourceInputField extends StatelessWidget {
  /// Creates a [_LocationSourceInputField].
  const _LocationSourceInputField({
    required this.keyPrefix,
    required this.sourceType,
    required this.controller,
    required this.enabled,
    required this.errorText,
    required this.onFieldChanged,
    required this.onResolveSource,
  });

  /// Controller for the address or Plus Code input.
  final TextEditingController controller;

  /// Whether editing is enabled.
  final bool enabled;

  /// Optional inline validation error text.
  final String? errorText;

  /// Stable prefix for deterministic widget keys.
  final String keyPrefix;

  /// Callback clearing stale errors when typing resumes.
  final VoidCallback onFieldChanged;

  /// Callback resolving the source when submitting from the keyboard.
  final VoidCallback onResolveSource;

  /// Active non-GPS source type selecting label and hint copy.
  final ShellLocationSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isAddress = sourceType == ShellLocationSourceType.address;

    return UiField(
      key: ValueKey<String>('${keyPrefix}_source_field'),
      controller: controller,
      label: isAddress
          ? localizations.locationSourceTypeAddress
          : localizations.locationSourceTypePlusCode,
      hintText: isAddress
          ? localizations.locationSourceAddressHint
          : localizations.locationSourcePlusCodeHint,
      maxLength: _maxLocationSourceLength,
      enabled: enabled,
      errorText: errorText,
      textInputAction: TextInputAction.search,
      onChanged: (_) => onFieldChanged(),
      onSubmitted: (_) => onResolveSource(),
    );
  }
}

/// Labeled `GPS` / `Address` / `Plus Code` segmented selector inside [_LocationCoordinatesEditorFields].
class _LocationSourceSelectorField extends StatelessWidget {
  /// Creates a [_LocationSourceSelectorField].
  const _LocationSourceSelectorField({
    required this.keyPrefix,
    required this.sourceType,
    required this.enabled,
    required this.onChanged,
  });

  /// Whether the segmented control is interactive.
  final bool enabled;

  /// Stable prefix for deterministic widget keys.
  final String keyPrefix;

  /// Callback notified when the user switches source type.
  final ValueChanged<ShellLocationSourceType> onChanged;

  /// Currently selected coordinate source type.
  final ShellLocationSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          localizations.locationSourceTypeLabel,
          style: tokens.typography.meta.copyWith(
            color: tokens.colors.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6.0),
        UiSegmentedControl<ShellLocationSourceType>(
          key: ValueKey<String>('${keyPrefix}_source_type_segmented'),
          value: sourceType,
          enabled: enabled,
          semanticLabel: localizations.locationSourceTypeLabel,
          onChanged: onChanged,
          segments: <UiSegment<ShellLocationSourceType>>[
            UiSegment<ShellLocationSourceType>(
              value: ShellLocationSourceType.gps,
              label: localizations.locationSourceTypeGps,
            ),
            UiSegment<ShellLocationSourceType>(
              value: ShellLocationSourceType.address,
              label: localizations.locationSourceTypeAddress,
            ),
            UiSegment<ShellLocationSourceType>(
              value: ShellLocationSourceType.plusCode,
              label: localizations.locationSourceTypePlusCode,
            ),
          ],
        ),
      ],
    );
  }
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

/// Per-card selective shell-state subscriber wiring one [LocationCardViewModel] to [_LocationExpandableCard] (`P-SELECT-REBUILDS`).
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

    return _LocationExpandableCard(
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
      return _LocationDraftCard(
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
      submitLabel: '+ ${localizations.actionAdd}',
      expandDraftLabel: localizations.actionOpenAsDraft,
      enabled: !isBusy,
      onExpandDraft: onExpandDraft,
      onSubmit: onSubmitQuickCreate,
    );
  }
}

/// Top sliver subscribing selectively to shell header/draft fields for [LocationsView].
class _LocationsHeaderSliver extends ConsumerWidget {
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
    final backLabel = switch (returnContext) {
      final savedContext? =>
        savedContext.searchOpen
            ? localizations.actionBackToSearch
            : localizations.actionBackToTasks,
      null => null,
    };

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        contentPadding.left,
        contentPadding.top,
        contentPadding.right,
        0.0,
      ),
      sliver: SliverToBoxAdapter(
        child: _LocationsHeaderColumn(
          locationsCount: viewModel.locations.length,
          backLabel: backLabel,
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
        ),
      ),
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

/// Copies [locationId] to the system clipboard and emits `locationIdCopiedNotice`.
Future<void> _copyLocationId(
  BuildContext context,
  WidgetRef ref,
  String locationId,
) async {
  final copiedNotice = AppLocalizations.of(context).locationIdCopiedNotice;
  await Clipboard.setData(ClipboardData(text: locationId));
  if (!context.mounted) {
    return;
  }
  ref
      .read(floatingNoticeControllerProvider.notifier)
      .showNotice(copiedNotice, tone: NoticeTone.success);
}

/// Presents [showGeocodingCandidatesModal] and applies the chosen candidate via [EntityV2Controller].
Future<LocationV2SourceResult?> _disambiguateLocationCandidate(
  BuildContext context,
  WidgetRef ref, {
  required List<GeocodingCandidateViewModel> candidates,
  required ShellLocationSourceType sourceType,
  required String? shortPlusCode,
  required Locale locale,
}) async {
  final chosenIndex = await showGeocodingCandidatesModal(
    context,
    candidates: candidates,
  );
  if (!context.mounted || chosenIndex == null) {
    return null;
  }
  return ref
      .read(entityV2ControllerProvider.notifier)
      .applyDisambiguatedCandidate(
        candidateIndex: chosenIndex,
        sourceType: sourceType,
        shortPlusCode: shortPlusCode,
        locale: locale,
      );
}

/// Emits a danger floating notice when [result] indicates validation or persistence failure.
void _reportActionFailure(WidgetRef ref, V2ActionResult result) {
  switch (result) {
    case V2ActionSucceeded():
      return;
    case V2ActionValidationFailed(:final message):
    case V2ActionPersistFailed(:final message):
      ref
          .read(floatingNoticeControllerProvider.notifier)
          .showNotice(message, tone: NoticeTone.danger);
  }
}

/// Returns the first error message not already rendered inline on a field in [inlineFieldKeys].
String? _resolveBannerErrorText({
  required String fallbackMessage,
  required Map<String, String> fieldErrors,
  required Set<String> inlineFieldKeys,
}) {
  if (fieldErrors.isEmpty) {
    return fallbackMessage;
  }
  for (final entry in fieldErrors.entries) {
    if (!inlineFieldKeys.contains(entry.key)) {
      return entry.value;
    }
  }
  return null;
}

/// Resolves an address or Plus Code source through [EntityV2Controller], prompting for disambiguation when needed.
Future<LocationV2SourceResult?> _resolveLocationSourceWithDisambiguation(
  BuildContext context,
  WidgetRef ref, {
  required ShellLocationSourceType sourceType,
  required String rawSource,
}) async {
  final locale = Localizations.localeOf(context);
  final result = await ref
      .read(entityV2ControllerProvider.notifier)
      .resolveLocationSource(
        sourceType: sourceType,
        rawSource: rawSource,
        locale: locale,
      );
  if (!context.mounted) {
    return null;
  }
  return switch (result) {
    LocationV2SourceResolved() || LocationV2SourceError() => result,
    LocationV2SourceNeedsDisambiguation(
      :final candidates,
      :final sourceType,
      :final shortPlusCode,
    ) =>
      _disambiguateLocationCandidate(
        context,
        ref,
        candidates: candidates,
        sourceType: sourceType,
        shortPlusCode: shortPlusCode,
        locale: locale,
      ),
  };
}
