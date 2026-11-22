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

import '../../l10n/app_localizations.dart';
import '../../models/location_state.dart';
import '../../models/tdf_error.dart';
import '../../models/tdf_location.dart';
import '../../providers/entity_actions_provider.dart';
import '../../providers/floating_notice_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/location_source_resolver.dart';
import '../../providers/shell_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/task_schedule_helper.dart';
import '../../services/plus_code_service.dart';
import '../dialogs/geocoding_candidates_modal.dart';
import '../layout/ui_responsive_grid.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../primitives/ui_field.dart';
import '../primitives/ui_pill.dart';
import '../primitives/ui_segmented_control.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';
import '../widgets/entity_card_chrome.dart';
import '../widgets/entity_inline_name_editor.dart';
import '../widgets/entity_note_section.dart';

/// Default formatted geofence radius seeding an uncommitted [LocationDraftCard].
const String _defaultDraftRadiusText = '200m';

/// Unified expandable Location card sharing single-expand coordination (`U-CARD-001`..`005`).
class LocationCard extends ConsumerWidget {
  /// Creates a [LocationCard].
  const LocationCard({
    super.key,
    required this.cardScrollKey,
    required this.location,
  });

  /// [GlobalKey] attached around the card for smooth reveal scrolling.
  final GlobalKey cardScrollKey;

  /// Persisted domain location rendered by this card.
  final TdfLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationRef = EntityRef(kind: EntityKind.location, id: location.id);
    final openCount = ref.watch(
      taskNotifierProvider.select(
        (boardAsync) =>
            boardAsync.asData?.value.openTaskCountsByLocation[location.id] ?? 0,
      ),
    );
    final isExpanded = ref.watch(
      shellProvider.select((shell) => shell.expandedEntity == locationRef),
    );
    final activeInlineSection = ref.watch(
      shellProvider.select(
        (shell) => shell.activeInlineEdit?.entity == locationRef
            ? shell.activeInlineEdit?.sectionKey
            : null,
      ),
    );
    final isConfirmingDelete = ref.watch(
      shellProvider.select((shell) => shell.activeDeleteConfirm == locationRef),
    );
    final isBusy = ref.watch(
      entityActionsProvider.select((state) => state.isBusy),
    );

    return KeyedSubtree(
      key: cardScrollKey,
      child: _LocationExpandableCardView(
        location: location,
        openCount: openCount,
        isExpanded: isExpanded,
        activeInlineSection: activeInlineSection,
        isConfirmingDelete: isConfirmingDelete,
        isBusy: isBusy,
      ),
    );
  }
}

/// Accent-bordered uncommitted Location Draft Card replacing Quick-Create in place (`U-CARD-006`).
class LocationDraftCard extends ConsumerStatefulWidget {
  /// Creates a [LocationDraftCard].
  const LocationDraftCard({
    super.key,
    required this.seedTitle,
    required this.hasActiveGpsFix,
    required this.isBusy,
  });

  /// Whether a valid foreground GPS fix is currently available for seeding.
  final bool hasActiveGpsFix;

  /// Whether a parent entity mutation is currently running.
  final bool isBusy;

  /// Initial location name transferred from the Quick-Create bar.
  final String seedTitle;

  @override
  ConsumerState<LocationDraftCard> createState() => _LocationDraftCardState();
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

  /// Unset optional sections computed from the location.
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

/// Conditionally renders [_LocationAddChipsBar] with top spacing when unset sections remain visible.
class _LocationAddChipsSlot extends StatelessWidget {
  /// Creates a [_LocationAddChipsSlot].
  const _LocationAddChipsSlot({
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

  /// Canonical location identifier.
  final String locationId;

  /// Callback opening the inline editor for a chosen section.
  final ValueChanged<LocationSectionKind> onOpenSection;

  /// Unset optional sections computed from the location.
  final List<LocationSectionKind> unsetSections;

  @override
  Widget build(BuildContext context) {
    final hasAddChips = unsetSections.any(
      (section) => section.name != activeInlineSection,
    );
    if (!hasAddChips) {
      return const SizedBox.shrink();
    }
    final tokens = UiThemeTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.space3),
      child: _LocationAddChipsBar(
        locationId: locationId,
        unsetSections: unsetSections,
        activeInlineSection: activeInlineSection,
        isBusy: isBusy,
        onOpenSection: onOpenSection,
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
    required this.openCount,
    required this.onToggleExpand,
  });

  /// Persisted domain location providing source, coordinate, and note data.
  final TdfLocation location;

  /// Callback toggling expansion of the owning location card.
  final VoidCallback onToggleExpand;

  /// Count of open tasks referencing [location].
  final int openCount;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final sourceType = PlusCodeService.classifySource(location.source);

    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        UiPill(
          label: _locationSourceTypeLabel(sourceType, localizations),
          icon: Icons.my_location_rounded,
          variant: UiPillVariant.meta,
          onPressed: onToggleExpand,
        ),
        UiPill(
          label: TaskScheduleHelper.formatCoordinatesSummary(location),
          variant: UiPillVariant.meta,
          isMono: true,
          onPressed: onToggleExpand,
        ),
        UiPill(
          label: localizations.openTasksCountPill('$openCount'),
          variant: UiPillVariant.meta,
          tone: UiPillTone.soft,
          onPressed: onToggleExpand,
        ),
        if (_hasNonEmptyNote(location.note))
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
class _LocationCardExpandedPanel extends ConsumerWidget {
  /// Creates a [_LocationCardExpandedPanel].
  const _LocationCardExpandedPanel({
    required this.location,
    required this.openCount,
    required this.activeInlineSection,
    required this.isConfirmingDelete,
    required this.isBusy,
  });

  /// Currently open inline section key on this location card, if any.
  final String? activeInlineSection;

  /// Whether an entity mutation is currently in progress.
  final bool isBusy;

  /// Whether the inline delete confirmation prompt is open for this card.
  final bool isConfirmingDelete;

  /// Expanded domain location.
  final TdfLocation location;

  /// Count of open tasks referencing [location].
  final int openCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = UiThemeTokens.of(context);
    final shellNotifier = ref.read(shellProvider.notifier);
    final entityNotifier = ref.read(entityActionsProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LocationCardMetaBar(
          locationId: location.id,
          openCount: openCount,
          isConfirmingDelete: isConfirmingDelete,
        ),
        SizedBox(height: tokens.spacing.space3),
        _LocationCardExpandedSections(
          location: location,
          activeInlineSection: activeInlineSection,
          isBusy: isBusy,
          onOpenSection: (section) => shellNotifier.openInlineEdit(
            InlineEditTarget.location(location.id, section),
          ),
          onCancelInlineEdit: shellNotifier.closeInlineEdit,
          onSaveNote: (rawNote) => entityNotifier.saveLocationNote(
            location.id,
            rawNote,
            locale: Localizations.localeOf(context),
          ),
          onClearNote: () => _clearLocationNote(context, ref, location.id),
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

  /// Expanded domain location.
  final TdfLocation location;

  /// Callback cancelling the active inline editor.
  final VoidCallback onCancelInlineEdit;

  /// Callback clearing the persisted location note.
  final Future<void> Function() onClearNote;

  /// Callback opening a specific section editor.
  final ValueChanged<LocationSectionKind> onOpenSection;

  /// Callback persisting an edited location note.
  final Future<ActionResult> Function(String rawNote) onSaveNote;

  @override
  Widget build(BuildContext context) {
    final isEditingNote = activeInlineSection == LocationSectionKind.note.name;
    final isEditingCoordinates =
        activeInlineSection == LocationSectionKind.coordinates.name;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LocationNoteSectionSlot(
          location: location,
          isEditing: isEditingNote,
          isBusy: isBusy,
          onStartEdit: () => onOpenSection(LocationSectionKind.note),
          onCancelEdit: onCancelInlineEdit,
          onSave: onSaveNote,
          onClear: onClearNote,
        ),
        _LocationCoordinatesSection(
          location: location,
          isEditing: isEditingCoordinates,
          isBusy: isBusy,
          onStartEdit: () => onOpenSection(LocationSectionKind.coordinates),
          onCancelEdit: onCancelInlineEdit,
        ),
        _LocationAddChipsSlot(
          locationId: location.id,
          unsetSections: _computeUnsetLocationSections(location),
          activeInlineSection: activeInlineSection,
          isBusy: isBusy,
          onOpenSection: onOpenSection,
        ),
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

/// Location-specific [EntityCardMetaBar] wiring Copy ID, open count pill, and inline Delete confirmation.
class _LocationCardMetaBar extends ConsumerWidget {
  /// Creates a [_LocationCardMetaBar].
  const _LocationCardMetaBar({
    required this.locationId,
    required this.openCount,
    required this.isConfirmingDelete,
  });

  /// Whether inline delete confirmation is open.
  final bool isConfirmingDelete;

  /// Canonical location identifier.
  final String locationId;

  /// Count of open tasks referencing this location.
  final int openCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final shellNotifier = ref.read(shellProvider.notifier);
    final locationRef = EntityRef(kind: EntityKind.location, id: locationId);

    return EntityCardMetaBar(
      entityId: locationId,
      copyIdTooltip: localizations.actionCopy,
      onCopyId: () => unawaited(_copyLocationId(context, ref, locationId)),
      statusPillLabel: localizations.openTasksCountPill('$openCount'),
      statusPillTone: UiPillTone.soft,
      deleteTooltip: localizations.tooltipDeleteLocation,
      deleteConfirmMessage: localizations.inlineDeleteLocationConfirm,
      isConfirmingDelete: isConfirmingDelete,
      onRequestDelete: () => shellNotifier.requestInlineDelete(locationRef),
      onCancelDelete: shellNotifier.cancelInlineDelete,
      onConfirmDelete: () =>
          unawaited(_confirmDeleteLocation(context, ref, locationId)),
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
  final LocationSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isGps = sourceType == LocationSourceType.gps;
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
          density: UiButtonDensity.compact,
          isLoading: isResolving && !isGps,
          onPressed: canResolve ? onResolveSource : null,
        ),
      ],
    );
  }
}

/// Shared inset Coordinates & Radius editor body used by both live card edit and Location Draft Card.
class _LocationCoordinatesEditorBody extends StatelessWidget {
  /// Creates a [_LocationCoordinatesEditorBody].
  const _LocationCoordinatesEditorBody({
    this.cardKey,
    required this.keyPrefix,
    required this.data,
    this.isEditing = false,
    this.footer,
  });

  /// Optional stable key placed on the outer [UiCard.inset].
  final Key? cardKey;

  /// Bundled coordinate controllers, error texts, and lookup callbacks.
  final _LocationCoordinatesFormData data;

  /// Optional bottom footer rendered for live inline editing.
  final Widget? footer;

  /// Renders the accent editing border when true (live card inline edit).
  final bool isEditing;

  /// Deterministic prefix applied to all nested field and button keys.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiCard.inset(
      key: cardKey,
      isEditing: isEditing,
      headerIcon: Icons.my_location_rounded,
      headerTitle: localizations.locationCoordinatesSectionTitle,
      footer: footer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _LocationSourceAndLookupFields(keyPrefix: keyPrefix, data: data),
          SizedBox(height: tokens.spacing.space2),
          _LocationLatitudeLongitudeRadiusFields(
            keyPrefix: keyPrefix,
            data: data,
          ),
        ],
      ),
    );
  }
}

/// Immutable bundle of Coordinates & Radius controllers, errors, and lookup callbacks.
@immutable
class _LocationCoordinatesFormData {
  /// Creates a [_LocationCoordinatesFormData].
  const _LocationCoordinatesFormData({
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

  /// Disables lookup actions while resolving GPS or geocoding.
  final bool isResolving;

  /// Controller for the WGS-84 latitude input.
  final TextEditingController latitudeController;

  /// Controller for the WGS-84 longitude input.
  final TextEditingController longitudeController;

  /// Callback notified whenever any text field changes.
  final VoidCallback onFieldChanged;

  /// Callback resolving the current address or Plus Code source.
  final VoidCallback onResolveSource;

  /// Callback switching the selected [LocationSourceType].
  final ValueChanged<LocationSourceType> onSourceTypeChanged;

  /// Callback applying the current foreground GPS fix.
  final VoidCallback onUseCurrentGps;

  /// Controller for the geofence radius input.
  final TextEditingController radiusController;

  /// Optional inline validation error for [radiusController].
  final String? radiusErrorText;

  /// Controller for the optional address or Plus Code source input.
  final TextEditingController sourceController;

  /// Optional inline validation error for [sourceController].
  final String? sourceErrorText;

  /// Active coordinate source mode (`gps`, `address`, or `plusCode`).
  final LocationSourceType sourceType;
}

/// Shared coordinate controllers, geocoding/GPS resolution, stale-token guards, and submit recovery.
mixin _LocationCoordinatesFormMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  /// Controller for the WGS-84 latitude input.
  late final TextEditingController latitudeController;

  /// Controller for the WGS-84 longitude input.
  late final TextEditingController longitudeController;

  /// Controller for the geofence radius input.
  late final TextEditingController radiusController;

  /// Controller for the optional address or Plus Code source input.
  late final TextEditingController sourceController;

  /// Banner or footer-level validation or lookup error message.
  String? errorText;

  /// Per-field inline validation errors keyed by logical field identifier.
  Map<String, String> fieldErrors = const <String, String>{};

  /// Re-entrancy guard preventing overlapping GPS or geocoding resolutions.
  bool isResolvingLocal = false;

  /// Re-entrancy guard preventing overlapping save/create submissions.
  bool isSubmitting = false;

  /// Monotonic token invalidating stale async GPS or geocoding lookups.
  int resolveRequestToken = 0;

  /// Currently active coordinate source mode (`gps`, `address`, or `plusCode`).
  LocationSourceType sourceType = LocationSourceType.gps;

  /// Whether the form is currently mounted and open for resolution results.
  bool get isFormActive => true;

  /// Whether an ancestor mutation is currently in progress.
  bool get isParentBusy;

  /// Builds the immutable [_LocationCoordinatesFormData] snapshot for [_LocationCoordinatesEditorBody].
  _LocationCoordinatesFormData buildCoordinatesFormData({
    required bool isResolving,
  }) {
    return _LocationCoordinatesFormData(
      sourceType: sourceType,
      sourceController: sourceController,
      latitudeController: latitudeController,
      longitudeController: longitudeController,
      radiusController: radiusController,
      sourceErrorText: fieldErrors['source'],
      radiusErrorText: fieldErrors['radius'],
      isBusy: isParentBusy || isSubmitting,
      isResolving: isResolving,
      onSourceTypeChanged: handleSourceTypeChanged,
      onUseCurrentGps: () => unawaited(handleUseCurrentGps()),
      onResolveSource: () => unawaited(handleResolveSource()),
      onFieldChanged: clearCoordinateErrors,
    );
  }

  /// Clears inline validation and lookup errors when the user edits an input.
  void clearCoordinateErrors() {
    if (errorText == null && fieldErrors.isEmpty) {
      return;
    }
    setState(() {
      errorText = null;
      fieldErrors = const <String, String>{};
    });
  }

  /// Disposes the four shared coordinate/source controllers.
  void disposeCoordinatesControllers() {
    sourceController.dispose();
    latitudeController.dispose();
    longitudeController.dispose();
    radiusController.dispose();
  }

  /// Resolves address or Plus Code input and opens disambiguation when multiple matches exist.
  Future<void> handleResolveSource() async {
    if (isParentBusy || isSubmitting || isResolvingLocal) {
      return;
    }
    final token = ++resolveRequestToken;
    setState(() {
      isResolvingLocal = true;
      errorText = null;
      fieldErrors = const <String, String>{};
    });
    try {
      final outcome = await _resolveLocationSourceWithDisambiguation(
        context,
        ref,
        sourceType: sourceType,
        rawSource: sourceController.text,
        isRequestCurrent: () =>
            mounted && isFormActive && token == resolveRequestToken,
      );
      if (!mounted ||
          !isFormActive ||
          token != resolveRequestToken ||
          outcome == null) {
        return;
      }
      _applyResolveOutcome(outcome);
    } finally {
      if (mounted && token == resolveRequestToken) {
        setState(() => isResolvingLocal = false);
      }
    }
  }

  /// Switches the active coordinate source mode and invalidates any in-flight lookup request.
  void handleSourceTypeChanged(LocationSourceType nextSourceType) {
    resolveRequestToken++;
    setState(() {
      sourceType = nextSourceType;
      isResolvingLocal = false;
      errorText = null;
      fieldErrors = const <String, String>{};
    });
  }

  /// Populates latitude and longitude inputs from the current foreground GPS fix.
  Future<void> handleUseCurrentGps() async {
    if (isParentBusy || isSubmitting || isResolvingLocal) {
      return;
    }
    final token = ++resolveRequestToken;
    setState(() {
      isResolvingLocal = true;
      errorText = null;
      fieldErrors = const <String, String>{};
    });
    try {
      final coordinates = await ref
          .read(entityActionsProvider.notifier)
          .resolveCurrentGpsPosition(locale: Localizations.localeOf(context));
      if (!mounted || !isFormActive || token != resolveRequestToken) {
        return;
      }
      _applyGpsCoordinates(coordinates);
    } finally {
      if (mounted && token == resolveRequestToken) {
        setState(() => isResolvingLocal = false);
      }
    }
  }

  /// Initializes the four shared coordinate/source controllers from initial form text.
  void initCoordinatesControllers({
    required LocationSourceType initialSourceType,
    required String sourceText,
    required String latitudeText,
    required String longitudeText,
    required String radiusText,
  }) {
    sourceType = initialSourceType;
    sourceController = TextEditingController(text: sourceText);
    latitudeController = TextEditingController(text: latitudeText);
    longitudeController = TextEditingController(text: longitudeText);
    radiusController = TextEditingController(text: radiusText);
  }

  /// Invalidates any in-flight GPS or geocoding resolution token.
  void invalidatePendingResolution() {
    resolveRequestToken++;
    isResolvingLocal = false;
  }

  /// Runs a guarded async submit [action] with `try/finally` recovery and inline error mapping.
  Future<void> runGuardedSubmit({
    required Future<ActionResult> Function() action,
    required Set<String> inlineFieldKeys,
  }) async {
    if (isParentBusy || isSubmitting) {
      return;
    }
    setState(() {
      isSubmitting = true;
      errorText = null;
      fieldErrors = const <String, String>{};
    });
    try {
      final result = await action();
      if (!mounted) {
        return;
      }
      _applyActionResult(result, inlineFieldKeys: inlineFieldKeys);
    } finally {
      if (mounted) {
        setState(() => isSubmitting = false);
      }
    }
  }

  /// Applies [result] from submitting coordinates or a draft to inline field and banner errors.
  void _applyActionResult(
    ActionResult result, {
    required Set<String> inlineFieldKeys,
  }) {
    switch (result) {
      case ActionSucceeded():
        break;
      case ActionValidationFailed(:final message, :final fieldErrors):
        setState(() {
          this.fieldErrors = fieldErrors;
          errorText = _resolveBannerErrorText(
            fallbackMessage: message,
            fieldErrors: fieldErrors,
            inlineFieldKeys: inlineFieldKeys,
          );
        });
      case ActionPersistFailed(:final message):
        setState(() => errorText = message);
    }
  }

  /// Applies resolved foreground GPS [coordinates] or displays the unavailable status error.
  void _applyGpsCoordinates(
    ({String latitudeText, String longitudeText})? coordinates,
  ) {
    if (coordinates case (:final latitudeText, :final longitudeText)) {
      setState(() {
        latitudeController.text = latitudeText;
        longitudeController.text = longitudeText;
        errorText = null;
        fieldErrors = const <String, String>{};
      });
      return;
    }
    setState(() {
      errorText = AppLocalizations.of(context).locationStatusUnavailable;
    });
  }

  /// Applies geocoding or Plus Code [outcome] to active coordinate controllers.
  void _applyResolveOutcome(LocationSourceResolutionResult outcome) {
    final localizations = AppLocalizations.of(context);
    switch (outcome) {
      case LocationSourceResolved(
        :final latitude,
        :final longitude,
        :final normalizedSource,
        :final sourceType,
      ):
        setState(() {
          this.sourceType = sourceType;
          sourceController.text = normalizedSource;
          latitudeController.text = TdfLocation.formatRoundedDouble(
            latitude,
            6,
          );
          longitudeController.text = TdfLocation.formatRoundedDouble(
            longitude,
            6,
          );
          errorText = null;
          fieldErrors = const <String, String>{};
        });
      case LocationSourceResolutionError(:final localizedMessage):
        setState(() => errorText = localizedMessage);
      case LocationSourceNeedsDisambiguation():
        setState(() => errorText = localizations.locationResolveErrorNotFound);
      case LocationSourceNotNeeded():
        break;
    }
  }
}

/// Responsive two-column WGS-84 latitude and longitude input grid.
class _LocationCoordinatesPairGrid extends StatelessWidget {
  /// Creates a [_LocationCoordinatesPairGrid].
  const _LocationCoordinatesPairGrid({
    required this.keyPrefix,
    required this.isGps,
    required this.isBusy,
    required this.latitudeController,
    required this.longitudeController,
    required this.onFieldChanged,
  });

  /// Disables inputs while saving.
  final bool isBusy;

  /// Keeps latitude and longitude editable in GPS mode and read-only in non-GPS modes.
  final bool isGps;

  /// Stable prefix for deterministic widget keys.
  final String keyPrefix;

  /// Controller for the WGS-84 latitude input.
  final TextEditingController latitudeController;

  /// Controller for the WGS-84 longitude input.
  final TextEditingController longitudeController;

  /// Callback clearing stale errors when text changes.
  final VoidCallback onFieldChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiResponsiveGrid(
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
    );
  }
}

/// Read-only coordinates summary lines displaying optional source text, monospace WGS-84 pair, and radius.
class _LocationCoordinatesReadOnlyBody extends StatelessWidget {
  /// Creates a [_LocationCoordinatesReadOnlyBody].
  const _LocationCoordinatesReadOnlyBody({
    required this.location,
    required this.sourceType,
  });

  /// Persisted domain location.
  final TdfLocation location;

  /// Classified coordinate source type for [location].
  final LocationSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final sourceValue = _locationSourceDisplayValue(location, sourceType);
    final showSourceValue =
        sourceType != LocationSourceType.gps && sourceValue.isNotEmpty;
    final radiusSummary = TaskScheduleHelper.formatRadiusMeters(
      location.radius,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showSourceValue) ...<Widget>[
          Text(
            sourceValue,
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
          localizations.locationRadiusReadout(radiusSummary),
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

  /// Persisted domain location.
  final TdfLocation location;

  /// Callback opening inline coordinate editing.
  final VoidCallback onStartEdit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final sourceType = PlusCodeService.classifySource(location.source);

    return UiCard.inset(
      key: ValueKey<String>('location_coords_section_${location.id}'),
      headerIcon: Icons.my_location_rounded,
      headerTitle: localizations.locationCoordinatesSectionTitle,
      headerBadge: UiPill(
        label: _locationSourceTypeLabel(sourceType, localizations),
      ),
      headerTrailing: UiButton(
        key: ValueKey<String>('location_edit_coords_button_${location.id}'),
        leadingIcon: Icons.edit_outlined,
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.dense,
        tooltip: localizations.actionEdit,
        onPressed: isBusy ? null : onStartEdit,
      ),
      child: _LocationCoordinatesReadOnlyBody(
        location: location,
        sourceType: sourceType,
      ),
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

  /// Persisted domain location.
  final TdfLocation location;

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
    extends ConsumerState<_LocationCoordinatesSection>
    with _LocationCoordinatesFormMixin<_LocationCoordinatesSection> {
  @override
  bool get isFormActive => widget.isEditing;

  @override
  bool get isParentBusy => widget.isBusy;

  @override
  void initState() {
    super.initState();
    final initialSourceType = PlusCodeService.classifySource(
      widget.location.source,
    );
    initCoordinatesControllers(
      initialSourceType: initialSourceType,
      sourceText: _locationSourceDisplayValue(
        widget.location,
        initialSourceType,
      ),
      latitudeText: widget.location.latitudeText,
      longitudeText: widget.location.longitudeText,
      radiusText: TaskScheduleHelper.formatRadiusMeters(widget.location.radius),
    );
  }

  @override
  void didUpdateWidget(covariant _LocationCoordinatesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      invalidatePendingResolution();
      _resetDraftFromLocation(widget.location);
    } else if (oldWidget.isEditing && !widget.isEditing) {
      invalidatePendingResolution();
      errorText = null;
      fieldErrors = const <String, String>{};
      isSubmitting = false;
    }
  }

  @override
  void dispose() {
    disposeCoordinatesControllers();
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
      entityActionsProvider.select((state) => state.isResolvingLocation),
    );
    return _LocationCoordinatesEditorBody(
      cardKey: ValueKey<String>('location_coords_editor_${widget.location.id}'),
      keyPrefix: 'location_coords_${widget.location.id}',
      isEditing: true,
      data: buildCoordinatesFormData(isResolving: isResolving),
      footer: EntityInlineEditorFooter(
        errorText: errorText,
        isBusy: widget.isBusy || isSubmitting,
        onCancel: widget.onCancelEdit,
        onSave: () => unawaited(_handleSave()),
      ),
    );
  }

  /// Validates and persists coordinates, source, and radius via [EntityActionsNotifier.saveLocationCoordinates].
  Future<void> _handleSave() {
    return runGuardedSubmit(
      inlineFieldKeys: const <String>{'source', 'radius'},
      action: () => ref
          .read(entityActionsProvider.notifier)
          .saveLocationCoordinates(
            widget.location.id,
            sourceType: sourceType,
            rawSource: sourceController.text,
            rawLatitude: latitudeController.text,
            rawLongitude: longitudeController.text,
            rawRadius: radiusController.text,
            locale: Localizations.localeOf(context),
          ),
    );
  }

  /// Re-seeds editor controllers from persisted [location] values when entering edit mode.
  void _resetDraftFromLocation(TdfLocation location) {
    final nextSourceType = PlusCodeService.classifySource(location.source);
    sourceType = nextSourceType;
    sourceController.text = _locationSourceDisplayValue(
      location,
      nextSourceType,
    );
    latitudeController.text = location.latitudeText;
    longitudeController.text = location.longitudeText;
    radiusController.text = TaskScheduleHelper.formatRadiusMeters(
      location.radius,
    );
    errorText = null;
    fieldErrors = const <String, String>{};
    isSubmitting = false;
  }
}

/// Manages controllers, geocoding resolution, and commit submission for [LocationDraftCard].
class _LocationDraftCardState extends ConsumerState<LocationDraftCard>
    with _LocationCoordinatesFormMixin<LocationDraftCard> {
  late final TextEditingController _nameController;
  late final TextEditingController _noteController;

  @override
  bool get isParentBusy => widget.isBusy;

  @override
  void initState() {
    super.initState();
    final seededCoordinates = _readForegroundSeedCoordinates(
      ref,
      hasActiveGpsFix: widget.hasActiveGpsFix,
    );
    _nameController = TextEditingController(text: widget.seedTitle);
    _noteController = TextEditingController();
    initCoordinatesControllers(
      initialSourceType: LocationSourceType.gps,
      sourceText: '',
      latitudeText: seededCoordinates.latitudeText,
      longitudeText: seededCoordinates.longitudeText,
      radiusText: _defaultDraftRadiusText,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    disposeCoordinatesControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isResolving = ref.watch(
      entityActionsProvider.select((state) => state.isResolvingLocation),
    );
    final effectiveBusy = widget.isBusy || isSubmitting;

    return UiCard.draft(
      key: const ValueKey<String>('location_draft_card'),
      title: localizations.draftNewLocationTitle,
      subtitle: localizations.draftUncommittedHint,
      closeTooltip: localizations.actionCancel,
      onClose: effectiveBusy ? null : _handleCancel,
      errorText: errorText,
      footer: _LocationDraftFooter(
        isBusy: effectiveBusy,
        isResolving: isResolving,
        onCancel: _handleCancel,
        onCreate: () => unawaited(_handleSubmit()),
      ),
      child: _LocationDraftFormBody(
        nameController: _nameController,
        noteController: _noteController,
        coordinatesData: buildCoordinatesFormData(isResolving: isResolving),
        fieldErrors: fieldErrors,
        isBusy: effectiveBusy,
        onFieldChanged: clearCoordinateErrors,
      ),
    );
  }

  /// Discards the uncommitted location draft without persisting changes.
  void _handleCancel() {
    invalidatePendingResolution();
    ref.read(shellProvider.notifier).cancelDraft();
  }

  /// Validates and commits the uncommitted location draft via [EntityActionsNotifier.createLocationDraft].
  Future<void> _handleSubmit() {
    return runGuardedSubmit(
      inlineFieldKeys: const <String>{'name', 'source', 'radius', 'note'},
      action: () => ref
          .read(entityActionsProvider.notifier)
          .createLocationDraft(
            LocationDraftInput(
              name: _nameController.text,
              sourceType: sourceType,
              rawSource: sourceController.text,
              rawLatitude: latitudeController.text,
              rawLongitude: longitudeController.text,
              rawRadius: radiusController.text,
              note: _noteController.text,
            ),
            locale: Localizations.localeOf(context),
          ),
    );
  }
}

/// Right-aligned `Cancel` and `Create location` footer row for [LocationDraftCard].
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

/// Form body inside [LocationDraftCard] pairing Name, Coordinates & Radius well, and Note well.
class _LocationDraftFormBody extends StatelessWidget {
  /// Creates a [_LocationDraftFormBody].
  const _LocationDraftFormBody({
    required this.nameController,
    required this.noteController,
    required this.coordinatesData,
    required this.fieldErrors,
    required this.isBusy,
    required this.onFieldChanged,
  });

  /// Bundled Coordinates & Radius controllers, errors, and lookup callbacks.
  final _LocationCoordinatesFormData coordinatesData;

  /// Per-field validation errors keyed by logical field identifier.
  final Map<String, String> fieldErrors;

  /// Disables inputs while saving.
  final bool isBusy;

  /// Location name controller.
  final TextEditingController nameController;

  /// Optional location note controller.
  final TextEditingController noteController;

  /// Callback clearing stale errors when inputs change.
  final VoidCallback onFieldChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LocationDraftNameField(
          nameController: nameController,
          isBusy: isBusy,
          errorText: fieldErrors['name'],
          onFieldChanged: onFieldChanged,
        ),
        SizedBox(height: tokens.spacing.space3),
        _LocationCoordinatesEditorBody(
          keyPrefix: 'location_draft',
          data: coordinatesData,
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

/// Location name text input rendered at the top of [_LocationDraftFormBody].
class _LocationDraftNameField extends StatelessWidget {
  /// Creates a [_LocationDraftNameField].
  const _LocationDraftNameField({
    required this.nameController,
    required this.isBusy,
    required this.errorText,
    required this.onFieldChanged,
  });

  /// Inline validation error for the name input.
  final String? errorText;

  /// Disables input while saving.
  final bool isBusy;

  /// Location name controller.
  final TextEditingController nameController;

  /// Callback clearing stale errors when text changes.
  final VoidCallback onFieldChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiField(
      key: const ValueKey<String>('location_draft_name_field'),
      controller: nameController,
      label: localizations.locationNameLabel,
      hintText: localizations.quickCreateLocationHint,
      maxLength: maxTdfTextLength,
      autofocus: true,
      enabled: !isBusy,
      errorText: errorText,
      onChanged: (_) => onFieldChanged(),
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
        maxLength: maxTdfNoteLength,
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
class _LocationEditNameButton extends ConsumerWidget {
  /// Creates a [_LocationEditNameButton].
  const _LocationEditNameButton({
    required this.locationId,
    required this.isBusy,
  });

  /// Disables the button while a mutation is in flight.
  final bool isBusy;

  /// Canonical location identifier.
  final String locationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return UiButton(
      key: ValueKey<String>('location_edit_name_button_$locationId'),
      leadingIcon: Icons.edit_outlined,
      variant: UiButtonVariant.icon,
      density: UiButtonDensity.dense,
      tooltip: localizations.inlineEditNameTooltip,
      onPressed: isBusy
          ? null
          : () => ref
                .read(shellProvider.notifier)
                .openInlineEdit(
                  InlineEditTarget.location(
                    locationId,
                    LocationSectionKind.title,
                  ),
                ),
    );
  }
}

/// Renders the expandable [UiCard.expandable] shell for [LocationCard].
class _LocationExpandableCardView extends ConsumerWidget {
  /// Creates a [_LocationExpandableCardView].
  const _LocationExpandableCardView({
    required this.location,
    required this.openCount,
    required this.isExpanded,
    required this.activeInlineSection,
    required this.isConfirmingDelete,
    required this.isBusy,
  });

  /// Currently open inline section key on this location card, if any.
  final String? activeInlineSection;

  /// Whether an entity mutation is currently active.
  final bool isBusy;

  /// Whether inline delete confirmation is open for this location card.
  final bool isConfirmingDelete;

  /// Whether this location card is expanded.
  final bool isExpanded;

  /// Persisted domain location.
  final TdfLocation location;

  /// Count of open tasks referencing [location].
  final int openCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEditingTitle =
        isExpanded && activeInlineSection == LocationSectionKind.title.name;
    void toggleExpand() => _toggleExpand(ref);

    return UiCard.expandable(
      title: location.name,
      isExpanded: isExpanded,
      isEditingTitle: isEditingTitle,
      onToggleExpand: toggleExpand,
      leading: _LocationCardLeadingIcon(
        isExpanded: isExpanded,
        semanticLabel: location.name,
        onPressed: toggleExpand,
      ),
      titleEditor: isEditingTitle
          ? _LocationInlineNameEditor(location: location, isBusy: isBusy)
          : null,
      trailingActions: <Widget>[
        if (isExpanded && !isEditingTitle)
          _LocationEditNameButton(locationId: location.id, isBusy: isBusy),
      ],
      collapsedMetadata: _LocationCardCollapsedMetadata(
        location: location,
        openCount: openCount,
        onToggleExpand: toggleExpand,
      ),
      expandedChild: isExpanded
          ? _LocationCardExpandedPanel(
              location: location,
              openCount: openCount,
              activeInlineSection: activeInlineSection,
              isConfirmingDelete: isConfirmingDelete,
              isBusy: isBusy,
            )
          : null,
    );
  }

  /// Toggles single-expand state for [location] in [shellProvider].
  void _toggleExpand(WidgetRef ref) {
    ref
        .read(shellProvider.notifier)
        .toggleExpandEntity(
          EntityRef(kind: EntityKind.location, id: location.id),
        );
  }
}

/// Inline location name editor swapped into the card header when editing [LocationSectionKind.title].
class _LocationInlineNameEditor extends ConsumerWidget {
  /// Creates a [_LocationInlineNameEditor].
  const _LocationInlineNameEditor({
    required this.location,
    required this.isBusy,
  });

  /// Disables actions while a parent mutation is active.
  final bool isBusy;

  /// Persisted domain location seeding the text field and target identifier.
  final TdfLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    return EntityInlineNameEditor(
      initialValue: location.name,
      hintText: localizations.locationNameLabel,
      semanticsLabel: localizations.inlineEditNameTooltip,
      inputKey: ValueKey<String>('location_name_editor_${location.id}'),
      saveKey: ValueKey<String>('location_name_save_${location.id}'),
      cancelKey: ValueKey<String>('location_name_cancel_${location.id}'),
      isBusy: isBusy,
      onCancel: ref.read(shellProvider.notifier).closeInlineEdit,
      onSave: (value) => ref
          .read(entityActionsProvider.notifier)
          .saveLocationName(location.id, value, locale: locale),
    );
  }
}

/// Responsive latitude/longitude pair and radius input inside [_LocationCoordinatesEditorBody].
class _LocationLatitudeLongitudeRadiusFields extends StatelessWidget {
  /// Creates a [_LocationLatitudeLongitudeRadiusFields].
  const _LocationLatitudeLongitudeRadiusFields({
    required this.keyPrefix,
    required this.data,
  });

  /// Bundled coordinate controllers, error texts, and callbacks.
  final _LocationCoordinatesFormData data;

  /// Stable prefix for deterministic widget keys.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LocationCoordinatesPairGrid(
          keyPrefix: keyPrefix,
          isGps: data.sourceType == LocationSourceType.gps,
          isBusy: data.isBusy,
          latitudeController: data.latitudeController,
          longitudeController: data.longitudeController,
          onFieldChanged: data.onFieldChanged,
        ),
        SizedBox(height: tokens.spacing.space2),
        UiField(
          key: ValueKey<String>('${keyPrefix}_radius_field'),
          controller: data.radiusController,
          label: localizations.locationRadiusLabel,
          hintText: _defaultDraftRadiusText,
          isMonospace: true,
          enabled: !data.isBusy,
          errorText: data.radiusErrorText,
          onChanged: (_) => data.onFieldChanged(),
        ),
      ],
    );
  }
}

/// Conditionally renders [EntityNoteSection] with bottom spacing when the location has a note or is editing it.
class _LocationNoteSectionSlot extends StatelessWidget {
  /// Creates a [_LocationNoteSectionSlot].
  const _LocationNoteSectionSlot({
    required this.location,
    required this.isEditing,
    required this.isBusy,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSave,
    required this.onClear,
  });

  /// Disables note actions while a mutation is running.
  final bool isBusy;

  /// Whether the note section is currently in inline edit mode.
  final bool isEditing;

  /// Expanded domain location.
  final TdfLocation location;

  /// Callback cancelling inline note editing.
  final VoidCallback onCancelEdit;

  /// Callback clearing the persisted location note.
  final Future<void> Function() onClear;

  /// Callback persisting an edited location note.
  final Future<ActionResult> Function(String rawNote) onSave;

  /// Callback entering inline note editing.
  final VoidCallback onStartEdit;

  @override
  Widget build(BuildContext context) {
    final showNoteSection = isEditing || _hasNonEmptyNote(location.note);
    if (!showNoteSection) {
      return const SizedBox.shrink();
    }
    final tokens = UiThemeTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.space3),
      child: EntityNoteSection(
        key: ValueKey<String>('location_note_section_${location.id}'),
        note: location.note,
        isEditing: isEditing,
        canEdit: true,
        isBusy: isBusy,
        onStartEdit: onStartEdit,
        onCancelEdit: onCancelEdit,
        onSave: onSave,
        onClear: onClear,
      ),
    );
  }
}

/// Groups the source selector, conditional source input, and GPS/Resolve lookup actions.
class _LocationSourceAndLookupFields extends StatelessWidget {
  /// Creates a [_LocationSourceAndLookupFields].
  const _LocationSourceAndLookupFields({
    required this.keyPrefix,
    required this.data,
  });

  /// Bundled coordinate controllers, error texts, and lookup callbacks.
  final _LocationCoordinatesFormData data;

  /// Stable prefix for deterministic widget keys.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final isGps = data.sourceType == LocationSourceType.gps;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LocationSourceSelectorField(
          keyPrefix: keyPrefix,
          sourceType: data.sourceType,
          enabled: !data.isBusy && !data.isResolving,
          onChanged: data.onSourceTypeChanged,
        ),
        if (!isGps) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          _LocationSourceInputField(
            keyPrefix: keyPrefix,
            sourceType: data.sourceType,
            controller: data.sourceController,
            enabled: !data.isBusy && !data.isResolving,
            errorText: data.sourceErrorText,
            onFieldChanged: data.onFieldChanged,
            onResolveSource: data.onResolveSource,
          ),
        ],
        SizedBox(height: tokens.spacing.space2),
        _LocationCoordinatesActionRow(
          keyPrefix: keyPrefix,
          sourceType: data.sourceType,
          isBusy: data.isBusy,
          isResolving: data.isResolving,
          onUseCurrentGps: data.onUseCurrentGps,
          onResolveSource: data.onResolveSource,
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
  final LocationSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isAddress = sourceType == LocationSourceType.address;

    return UiField(
      key: ValueKey<String>('${keyPrefix}_source_field'),
      controller: controller,
      label: isAddress
          ? localizations.locationSourceTypeAddress
          : localizations.locationSourceTypePlusCode,
      hintText: isAddress
          ? localizations.locationSourceAddressHint
          : localizations.locationSourcePlusCodeHint,
      maxLength: maxTdfTextLength,
      enabled: enabled,
      errorText: errorText,
      textInputAction: TextInputAction.search,
      onChanged: (_) => onFieldChanged(),
      onSubmitted: (_) => onResolveSource(),
    );
  }
}

/// Labeled `GPS` / `Address` / `Plus Code` segmented selector inside [_LocationCoordinatesEditorBody].
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
  final ValueChanged<LocationSourceType> onChanged;

  /// Currently selected coordinate source type.
  final LocationSourceType sourceType;

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
        UiSegmentedControl<LocationSourceType>(
          key: ValueKey<String>('${keyPrefix}_source_type_segmented'),
          value: sourceType,
          enabled: enabled,
          semanticLabel: localizations.locationSourceTypeLabel,
          onChanged: onChanged,
          segments: _locationSourceSegments(localizations),
        ),
      ],
    );
  }
}

/// Clears the optional note on [locationId] and reports any failure via floating notice.
Future<void> _clearLocationNote(
  BuildContext context,
  WidgetRef ref,
  String locationId,
) async {
  final result = await ref
      .read(entityActionsProvider.notifier)
      .clearLocationNote(locationId, locale: Localizations.localeOf(context));
  if (!context.mounted) {
    return;
  }
  _reportActionFailure(ref, result);
}

/// Computes the ordered optional [LocationSectionKind] sections not yet populated on [location].
List<LocationSectionKind> _computeUnsetLocationSections(TdfLocation location) {
  return <LocationSectionKind>[
    if (!_hasNonEmptyNote(location.note)) LocationSectionKind.note,
  ];
}

/// Deletes [locationId] via [EntityActionsNotifier.deleteLocation] and reports errors via floating notice.
Future<void> _confirmDeleteLocation(
  BuildContext context,
  WidgetRef ref,
  String locationId,
) async {
  final result = await ref
      .read(entityActionsProvider.notifier)
      .deleteLocation(locationId, locale: Localizations.localeOf(context));
  if (!context.mounted) {
    return;
  }
  _reportActionFailure(ref, result);
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
      .read(floatingNoticeProvider.notifier)
      .showNotice(copiedNotice, tone: FloatingNoticeTone.success);
}

/// Presents [showGeocodingCandidatesModal] and applies the chosen [GeocodingCandidate] via [entityActionsProvider].
Future<LocationSourceResolutionResult?> _disambiguateLocationCandidate(
  BuildContext context,
  WidgetRef ref, {
  required List<GeocodingCandidate> candidates,
  required LocationSourceType sourceType,
  required String? shortPlusCode,
  required String? localityQuery,
  required Locale locale,
}) async {
  final chosenCandidate = await showGeocodingCandidatesModal(
    context,
    candidates: candidates,
  );
  if (!context.mounted || chosenCandidate == null) {
    return null;
  }
  return ref
      .read(entityActionsProvider.notifier)
      .applyDisambiguatedCandidate(
        candidate: chosenCandidate,
        sourceType: sourceType,
        shortPlusCode: shortPlusCode,
        localityQuery: localityQuery,
        locale: locale,
      );
}

/// Returns `true` when [note] contains at least one non-whitespace character.
bool _hasNonEmptyNote(String? note) => note != null && note.trim().isNotEmpty;

/// Extracts the normalized editable source text for [location], omitting legacy GPS sentinel tokens.
String _locationSourceDisplayValue(
  TdfLocation location,
  LocationSourceType sourceType,
) {
  final rawSource = location.source?.trim() ?? '';
  final lower = rawSource.toLowerCase();
  if (sourceType == LocationSourceType.gps ||
      lower == 'manual' ||
      lower == 'gps') {
    return '';
  }
  return rawSource;
}

/// Builds the three segmented options (`GPS` / `Address` / `Plus Code`) for [_LocationSourceSelectorField].
List<UiSegment<LocationSourceType>> _locationSourceSegments(
  AppLocalizations localizations,
) {
  return <UiSegment<LocationSourceType>>[
    UiSegment<LocationSourceType>(
      value: LocationSourceType.gps,
      label: localizations.locationSourceTypeGps,
    ),
    UiSegment<LocationSourceType>(
      value: LocationSourceType.address,
      label: localizations.locationSourceTypeAddress,
    ),
    UiSegment<LocationSourceType>(
      value: LocationSourceType.plusCode,
      label: localizations.locationSourceTypePlusCode,
    ),
  ];
}

/// Maps [sourceType] exhaustively to its localized display label.
String _locationSourceTypeLabel(
  LocationSourceType sourceType,
  AppLocalizations localizations,
) {
  return switch (sourceType) {
    LocationSourceType.gps => localizations.locationSourceTypeGps,
    LocationSourceType.address => localizations.locationSourceTypeAddress,
    LocationSourceType.plusCode => localizations.locationSourceTypePlusCode,
  };
}

/// Reads initial 6-decimal foreground GPS coordinate strings from [locationStateProvider] when available.
({String latitudeText, String longitudeText}) _readForegroundSeedCoordinates(
  WidgetRef ref, {
  required bool hasActiveGpsFix,
}) {
  if (!hasActiveGpsFix) {
    return (latitudeText: '', longitudeText: '');
  }
  final locationState = ref.read(locationStateProvider);
  final fix = locationState.status == LocationStatus.found
      ? locationState.fix
      : null;
  if ((fix?.latitude, fix?.longitude) case (
    final double latitude,
    final double longitude,
  )) {
    return (
      latitudeText: TdfLocation.formatRoundedDouble(latitude, 6),
      longitudeText: TdfLocation.formatRoundedDouble(longitude, 6),
    );
  }
  return (latitudeText: '', longitudeText: '');
}

/// Emits a danger floating notice when [result] indicates validation or persistence failure.
void _reportActionFailure(WidgetRef ref, ActionResult result) {
  switch (result) {
    case ActionSucceeded():
      return;
    case ActionValidationFailed(:final message):
    case ActionPersistFailed(:final message):
      ref
          .read(floatingNoticeProvider.notifier)
          .showNotice(message, tone: FloatingNoticeTone.danger);
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

/// Resolves an address or Plus Code source through [entityActionsProvider], prompting for disambiguation when needed.
Future<LocationSourceResolutionResult?>
_resolveLocationSourceWithDisambiguation(
  BuildContext context,
  WidgetRef ref, {
  required LocationSourceType sourceType,
  required String rawSource,
  required bool Function() isRequestCurrent,
}) async {
  final locale = Localizations.localeOf(context);
  final result = await ref
      .read(entityActionsProvider.notifier)
      .resolveLocationSource(
        sourceType: sourceType,
        rawSource: rawSource,
        locale: locale,
      );
  if (!context.mounted || !isRequestCurrent()) {
    return null;
  }
  return switch (result) {
    LocationSourceResolved() ||
    LocationSourceResolutionError() ||
    LocationSourceNotNeeded() => result,
    LocationSourceNeedsDisambiguation(
      :final candidates,
      :final sourceType,
      :final shortPlusCode,
      :final localityQuery,
    ) =>
      _disambiguateLocationCandidate(
        context,
        ref,
        candidates: candidates,
        sourceType: sourceType,
        shortPlusCode: shortPlusCode,
        localityQuery: localityQuery,
        locale: locale,
      ),
  };
}
