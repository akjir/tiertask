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
import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';
import '../widgets/entity_card_chrome.dart';
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

  /// Callback switching [LocationSourceType].
  final ValueChanged<LocationSourceType> onSourceTypeChanged;

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
  final LocationSourceType sourceType;

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

  /// Callback switching the selected [LocationSourceType].
  final ValueChanged<LocationSourceType> onSourceTypeChanged;

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
  final LocationSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final isGps = sourceType == LocationSourceType.gps;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LocationSourceAndLookupFields(
          keyPrefix: keyPrefix,
          sourceType: sourceType,
          sourceController: sourceController,
          sourceErrorText: sourceErrorText,
          isBusy: isBusy,
          isResolving: isResolving,
          onSourceTypeChanged: onSourceTypeChanged,
          onUseCurrentGps: onUseCurrentGps,
          onResolveSource: onResolveSource,
          onFieldChanged: onFieldChanged,
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
    extends ConsumerState<_LocationCoordinatesSection> {
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  late final TextEditingController _radiusController;
  late final TextEditingController _sourceController;

  String? _errorText;
  Map<String, String> _fieldErrors = const <String, String>{};
  bool _isSubmitting = false;
  late LocationSourceType _sourceType;

  @override
  void initState() {
    super.initState();
    final sourceType = PlusCodeService.classifySource(widget.location.source);
    _sourceType = sourceType;
    _sourceController = TextEditingController(
      text: _locationSourceDisplayValue(widget.location, sourceType),
    );
    _latitudeController = TextEditingController(
      text: widget.location.latitudeText,
    );
    _longitudeController = TextEditingController(
      text: widget.location.longitudeText,
    );
    _radiusController = TextEditingController(
      text: TaskScheduleHelper.formatRadiusMeters(widget.location.radius),
    );
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
      entityActionsProvider.select((state) => state.isResolvingLocation),
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
      case LocationSourceResolved(
        :final latitude,
        :final longitude,
        :final normalizedSource,
        :final sourceType,
      ):
        setState(() {
          _sourceType = sourceType;
          _sourceController.text = normalizedSource;
          _latitudeController.text = TdfLocation.formatRoundedDouble(
            latitude,
            6,
          );
          _longitudeController.text = TdfLocation.formatRoundedDouble(
            longitude,
            6,
          );
          _errorText = null;
          _fieldErrors = const <String, String>{};
        });
      case LocationSourceResolutionError(:final localizedMessage):
        setState(() => _errorText = localizedMessage);
      case LocationSourceNeedsDisambiguation():
        setState(() => _errorText = localizations.locationResolveErrorNotFound);
      case LocationSourceNotNeeded():
        break;
    }
  }

  /// Validates and persists coordinates, source, and radius via [EntityActionsNotifier.saveLocationCoordinates].
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
        .read(entityActionsProvider.notifier)
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
      case ActionSucceeded():
        setState(() => _isSubmitting = false);
      case ActionValidationFailed(:final message, :final fieldErrors):
        setState(() {
          _isSubmitting = false;
          _fieldErrors = fieldErrors;
          _errorText = _resolveBannerErrorText(
            fallbackMessage: message,
            fieldErrors: fieldErrors,
            inlineFieldKeys: const <String>{'source', 'radius'},
          );
        });
      case ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
    }
  }

  /// Updates the active source mode and clears stale lookup errors.
  void _handleSourceTypeChanged(LocationSourceType nextSourceType) {
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
        .read(entityActionsProvider.notifier)
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
  void _resetDraftFromLocation(TdfLocation location) {
    final sourceType = PlusCodeService.classifySource(location.source);
    _sourceType = sourceType;
    _sourceController.text = _locationSourceDisplayValue(location, sourceType);
    _latitudeController.text = location.latitudeText;
    _longitudeController.text = location.longitudeText;
    _radiusController.text = TaskScheduleHelper.formatRadiusMeters(
      location.radius,
    );
    _errorText = null;
    _fieldErrors = const <String, String>{};
    _isSubmitting = false;
  }
}

/// Manages controllers, geocoding resolution, and commit submission for [LocationDraftCard].
class _LocationDraftCardState extends ConsumerState<LocationDraftCard> {
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  late final TextEditingController _nameController;
  late final TextEditingController _noteController;
  late final TextEditingController _radiusController;
  late final TextEditingController _sourceController;

  String? _errorText;
  Map<String, String> _fieldErrors = const <String, String>{};
  bool _isSubmitting = false;
  LocationSourceType _sourceType = LocationSourceType.gps;

  @override
  void initState() {
    super.initState();
    final seededCoordinates = _readForegroundSeedCoordinates(
      ref,
      hasActiveGpsFix: widget.hasActiveGpsFix,
    );
    _nameController = TextEditingController(text: widget.seedTitle);
    _sourceController = TextEditingController();
    _latitudeController = TextEditingController(
      text: seededCoordinates.latitudeText,
    );
    _longitudeController = TextEditingController(
      text: seededCoordinates.longitudeText,
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
      entityActionsProvider.select((state) => state.isResolvingLocation),
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
    ref.read(shellProvider.notifier).cancelDraft();
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
      case LocationSourceResolved(
        :final latitude,
        :final longitude,
        :final normalizedSource,
        :final sourceType,
      ):
        setState(() {
          _sourceType = sourceType;
          _sourceController.text = normalizedSource;
          _latitudeController.text = TdfLocation.formatRoundedDouble(
            latitude,
            6,
          );
          _longitudeController.text = TdfLocation.formatRoundedDouble(
            longitude,
            6,
          );
          _errorText = null;
          _fieldErrors = const <String, String>{};
        });
      case LocationSourceResolutionError(:final localizedMessage):
        setState(() => _errorText = localizedMessage);
      case LocationSourceNeedsDisambiguation():
        setState(() => _errorText = localizations.locationResolveErrorNotFound);
      case LocationSourceNotNeeded():
        break;
    }
  }

  /// Switches the active coordinate source mode inside the draft card.
  void _handleSourceTypeChanged(LocationSourceType nextSourceType) {
    setState(() {
      _sourceType = nextSourceType;
      _errorText = null;
      _fieldErrors = const <String, String>{};
    });
  }

  /// Validates and commits the uncommitted location draft via [EntityActionsNotifier.createLocationDraft].
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
        .read(entityActionsProvider.notifier)
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
      case ActionSucceeded():
        setState(() => _isSubmitting = false);
      case ActionValidationFailed(:final message, :final fieldErrors):
        setState(() {
          _isSubmitting = false;
          _fieldErrors = fieldErrors;
          _errorText = _resolveBannerErrorText(
            fallbackMessage: message,
            fieldErrors: fieldErrors,
            inlineFieldKeys: const <String>{'name', 'source', 'radius', 'note'},
          );
        });
      case ActionPersistFailed(:final message):
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
        .read(entityActionsProvider.notifier)
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
  final ValueChanged<LocationSourceType> onSourceTypeChanged;

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
  final LocationSourceType sourceType;

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

/// Form body inside [LocationDraftCard] pairing Name, Coordinates & Radius well, and Note well.
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

  /// Callback switching [LocationSourceType].
  final ValueChanged<LocationSourceType> onSourceTypeChanged;

  /// Callback applying the current foreground GPS fix.
  final VoidCallback onUseCurrentGps;

  /// Geofence radius controller.
  final TextEditingController radiusController;

  /// Address or Plus Code source controller.
  final TextEditingController sourceController;

  /// Currently selected coordinate source type.
  final LocationSourceType sourceType;

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
class _LocationInlineNameEditor extends ConsumerStatefulWidget {
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
  ConsumerState<_LocationInlineNameEditor> createState() =>
      _LocationInlineNameEditorState();
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

/// Arranges the inline name field and action buttons in a compact column or wide row.
class _LocationInlineNameEditorLayout extends StatelessWidget {
  /// Creates a [_LocationInlineNameEditorLayout].
  const _LocationInlineNameEditorLayout({
    required this.isCompact,
    required this.field,
    required this.actions,
  });

  /// Compact Save and Cancel button row.
  final Widget actions;

  /// Inline location name text input.
  final Widget field;

  /// Stacks [actions] below [field] on compact viewports.
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
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
    _controller = TextEditingController(text: widget.location.name);
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

    return _LocationInlineNameEditorLayout(
      isCompact: isCompact,
      field: UiField(
        key: ValueKey<String>('location_name_editor_${widget.location.id}'),
        controller: _controller,
        autofocus: true,
        maxLength: maxTdfTextLength,
        hintText: localizations.locationNameLabel,
        semanticLabel: localizations.inlineEditNameTooltip,
        enabled: !effectiveBusy,
        errorText: _errorText,
        textInputAction: TextInputAction.done,
        onChanged: _handleChanged,
        onSubmitted: (_) => unawaited(_handleSave()),
      ),
      actions: _LocationInlineNameEditorActions(
        locationId: widget.location.id,
        isBusy: effectiveBusy,
        onSave: () => unawaited(_handleSave()),
        onCancel: ref.read(shellProvider.notifier).closeInlineEdit,
      ),
    );
  }

  /// Clears inline validation errors once typing resumes.
  void _handleChanged(String _) {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  /// Validates and commits the updated location name via [EntityActionsNotifier.saveLocationName].
  Future<void> _handleSave() async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    final result = await ref
        .read(entityActionsProvider.notifier)
        .saveLocationName(
          widget.location.id,
          _controller.text,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        setState(() => _isSubmitting = false);
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
    }
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
        _LocationCoordinatesPairGrid(
          keyPrefix: keyPrefix,
          isGps: isGps,
          isBusy: isBusy,
          latitudeController: latitudeController,
          longitudeController: longitudeController,
          onFieldChanged: onFieldChanged,
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
    required this.sourceType,
    required this.sourceController,
    required this.sourceErrorText,
    required this.isBusy,
    required this.isResolving,
    required this.onSourceTypeChanged,
    required this.onUseCurrentGps,
    required this.onResolveSource,
    required this.onFieldChanged,
  });

  /// Whether a persistence mutation is currently active.
  final bool isBusy;

  /// Whether a GPS or geocoding lookup is currently active.
  final bool isResolving;

  /// Stable prefix for deterministic widget keys.
  final String keyPrefix;

  /// Callback notified whenever any text field changes.
  final VoidCallback onFieldChanged;

  /// Callback resolving the current address or Plus Code source.
  final VoidCallback onResolveSource;

  /// Callback switching the selected [LocationSourceType].
  final ValueChanged<LocationSourceType> onSourceTypeChanged;

  /// Callback applying the current foreground GPS fix.
  final VoidCallback onUseCurrentGps;

  /// Controller for the optional address or Plus Code source input.
  final TextEditingController sourceController;

  /// Optional inline validation error for [sourceController].
  final String? sourceErrorText;

  /// Active coordinate source mode (`gps`, `address`, or `plusCode`).
  final LocationSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final isGps = sourceType == LocationSourceType.gps;

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

/// Segmented `GPS` / `Address` / `Plus Code` control inside [_LocationSourceSelectorField].
class _LocationSourceSegmentedControl extends StatelessWidget {
  /// Creates a [_LocationSourceSegmentedControl].
  const _LocationSourceSegmentedControl({
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
    return UiSegmentedControl<LocationSourceType>(
      key: ValueKey<String>('${keyPrefix}_source_type_segmented'),
      value: sourceType,
      enabled: enabled,
      semanticLabel: localizations.locationSourceTypeLabel,
      onChanged: onChanged,
      segments: <UiSegment<LocationSourceType>>[
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
      ],
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
        _LocationSourceSegmentedControl(
          keyPrefix: keyPrefix,
          sourceType: sourceType,
          enabled: enabled,
          onChanged: onChanged,
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
}) async {
  final locale = Localizations.localeOf(context);
  final result = await ref
      .read(entityActionsProvider.notifier)
      .resolveLocationSource(
        sourceType: sourceType,
        rawSource: rawSource,
        locale: locale,
      );
  if (!context.mounted) {
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
