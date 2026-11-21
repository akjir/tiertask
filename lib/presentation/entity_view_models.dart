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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/location_state.dart';
import '../models/task_board.dart';
import '../models/task_board_evaluator.dart';
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';
import '../providers/config_providers.dart';
import '../providers/location_providers.dart';
import '../providers/task_providers.dart';
import 'location_source_resolver.dart';
import 'shell_models.dart';
import 'view_model_primitives.dart';

/// Provides the model-free Labels manager projection for `lib/ui/`.
final labelsManagerViewModelProvider = Provider<LabelsManagerViewModel>((ref) {
  final locale = ref.watch(appLocaleProvider);
  final localizations = lookupAppLocalizations(locale);
  final board = ref.watch(
    taskNotifierProvider.select(
      (boardAsync) => boardAsync.asData?.value ?? TaskBoard.empty(),
    ),
  );
  final locationsById = <String, TdfLocation>{
    for (final location in board.locations) location.id: location,
  };
  final sortedLabels = TaskBoardEvaluator.sortLabelsAlphabetically(
    board.labels,
  );
  final sortedLocations = TaskBoardEvaluator.sortLocationsAlphabetically(
    board.locations,
  );

  final cards = <LabelCardViewModel>[
    for (final label in sortedLabels)
      _buildLabelCardViewModel(
        label: label,
        openCount: board.openTaskCountForLabel(label.id),
        locationsById: locationsById,
        localizations: localizations,
      ),
  ];

  final locationOptions = <LocationOptionViewModel>[
    for (final location in sortedLocations)
      LocationOptionViewModel(
        id: location.id,
        name: location.name,
        coordinatesSummary: ViewModelFormatters.formatCoordinatesSummary(
          location,
        ),
      ),
  ];

  final nextPresetColorHex =
      canonicalLabelPresetHexColors[board.labels.length %
          canonicalLabelPresetHexColors.length];

  return LabelsManagerViewModel(
    labels: cards,
    allLocations: locationOptions,
    nextPresetColorHex: nextPresetColorHex,
  );
});

/// Provides the model-free Locations manager projection for `lib/ui/`.
final locationsManagerViewModelProvider = Provider<LocationsManagerViewModel>((
  ref,
) {
  final locale = ref.watch(appLocaleProvider);
  final localizations = lookupAppLocalizations(locale);
  final board = ref.watch(
    taskNotifierProvider.select(
      (boardAsync) => boardAsync.asData?.value ?? TaskBoard.empty(),
    ),
  );
  final activeFix = ref.watch(
    locationStateProvider.select(
      (state) => state.status == LocationStatus.found ? state.fix : null,
    ),
  );
  final locationController = ref.watch(locationSourceResolverProvider);
  final sortedLocations = TaskBoardEvaluator.sortLocationsAlphabetically(
    board.locations,
  );

  final cards = <LocationCardViewModel>[
    for (final location in sortedLocations)
      _buildLocationCardViewModel(
        location: location,
        openCount: board.openTaskCountForLocation(location.id),
        locationController: locationController,
        localizations: localizations,
      ),
  ];

  final activeLat = activeFix?.latitude;
  final activeLon = activeFix?.longitude;
  return LocationsManagerViewModel(
    locations: cards,
    hasActiveGpsFix: activeLat != null && activeLon != null,
    activeGpsLatitudeText: activeLat != null
        ? locationController.formatGpsCoordinate(activeLat)
        : null,
    activeGpsLongitudeText: activeLon != null
        ? locationController.formatGpsCoordinate(activeLon)
        : null,
  );
});

/// Immutable expandable Label card projection for `LabelsView`.
@immutable
class LabelCardViewModel {
  /// Creates a [LabelCardViewModel].
  LabelCardViewModel({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.colorValue,
    required this.isScoped,
    required this.openCount,
    required this.note,
    required Iterable<EntityLinkViewModel> links,
    required this.hasConditions,
    required Iterable<ConditionSummaryChipViewModel> conditionsSummary,
    required this.conditionDraft,
    required Iterable<LabelSectionKind> unsetSections,
  }) : links = List<EntityLinkViewModel>.unmodifiable(links),
       conditionsSummary = List<ConditionSummaryChipViewModel>.unmodifiable(
         conditionsSummary,
       ),
       unsetSections = List<LabelSectionKind>.unmodifiable(unsetSections);

  /// Normalized `#RRGGBB` hex string, or empty string when unset.
  final String colorHex;

  /// Parsed ARGB integer color, or `null` when unset.
  final int? colorValue;

  /// Editable activation conditions draft state.
  final ConditionDraftViewModel conditionDraft;

  /// Human-readable condition summary chips.
  final List<ConditionSummaryChipViewModel> conditionsSummary;

  /// Whether this label declares inherited activation conditions.
  final bool hasConditions;

  /// Canonical label identifier.
  final String id;

  /// Whether this label acts as a Scoped Queue.
  final bool isScoped;

  /// Reference links attached to this label.
  final List<EntityLinkViewModel> links;

  /// Label display name.
  final String name;

  /// Optional multi-line note.
  final String? note;

  /// Count of open tasks referencing this label.
  final int openCount;

  /// Unset editable sections rendered in the bottom `+ Add` chips bar.
  final List<LabelSectionKind> unsetSections;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LabelCardViewModel &&
        other.id == id &&
        other.name == name &&
        other.colorHex == colorHex &&
        other.colorValue == colorValue &&
        other.isScoped == isScoped &&
        other.openCount == openCount &&
        other.note == note &&
        listEquals(other.links, links) &&
        other.hasConditions == hasConditions &&
        listEquals(other.conditionsSummary, conditionsSummary) &&
        other.conditionDraft == conditionDraft &&
        listEquals(other.unsetSections, unsetSections);
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    colorHex,
    colorValue,
    isScoped,
    openCount,
    note,
    Object.hashAll(links),
    hasConditions,
    Object.hashAll(conditionsSummary),
    conditionDraft,
    Object.hashAll(unsetSections),
  );
}

/// Immutable view model for the Labels manager view.
@immutable
class LabelsManagerViewModel {
  /// Creates a [LabelsManagerViewModel].
  LabelsManagerViewModel({
    required Iterable<LabelCardViewModel> labels,
    required Iterable<LocationOptionViewModel> allLocations,
    required this.nextPresetColorHex,
  }) : labels = List<LabelCardViewModel>.unmodifiable(labels),
       allLocations = List<LocationOptionViewModel>.unmodifiable(allLocations);

  /// Available saved locations for inherited GPS conditions.
  final List<LocationOptionViewModel> allLocations;

  /// Alphabetically sorted label cards.
  final List<LabelCardViewModel> labels;

  /// Next rotating preset `#RRGGBB` color assigned on Quick-Create.
  final String nextPresetColorHex;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LabelsManagerViewModel &&
        listEquals(other.labels, labels) &&
        listEquals(other.allLocations, allLocations) &&
        other.nextPresetColorHex == nextPresetColorHex;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(labels),
    Object.hashAll(allLocations),
    nextPresetColorHex,
  );
}

/// Immutable expandable Location card projection for `LocationsView`.
@immutable
class LocationCardViewModel {
  /// Creates a [LocationCardViewModel].
  LocationCardViewModel({
    required this.id,
    required this.name,
    required this.sourceType,
    required this.sourceValue,
    required this.sourceTypeLabel,
    required this.latitudeText,
    required this.longitudeText,
    required this.radiusText,
    required this.coordinatesSummary,
    required this.radiusSummary,
    required this.openCount,
    required this.note,
    required Iterable<LocationSectionKind> unsetSections,
  }) : unsetSections = List<LocationSectionKind>.unmodifiable(unsetSections);

  /// Compact 4dp coordinate + radius summary for collapsed strip.
  final String coordinatesSummary;

  /// Canonical location identifier.
  final String id;

  /// Normalized decimal latitude text for inline editing.
  final String latitudeText;

  /// Normalized decimal longitude text for inline editing.
  final String longitudeText;

  /// Location display name.
  final String name;

  /// Optional multi-line note.
  final String? note;

  /// Count of open tasks referencing this location directly or via labels.
  final int openCount;

  /// Formatted radius display label (e.g. `250m` or `1.5km`).
  final String radiusSummary;

  /// Editable radius text (e.g. `250m`).
  final String radiusText;

  /// Classified coordinate source type.
  final ShellLocationSourceType sourceType;

  /// Localized source type badge label.
  final String sourceTypeLabel;

  /// Raw address or Plus Code string, or empty for direct GPS.
  final String sourceValue;

  /// Unset editable sections rendered in the bottom `+ Add` chips bar.
  final List<LocationSectionKind> unsetSections;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationCardViewModel &&
        other.id == id &&
        other.name == name &&
        other.sourceType == sourceType &&
        other.sourceValue == sourceValue &&
        other.sourceTypeLabel == sourceTypeLabel &&
        other.latitudeText == latitudeText &&
        other.longitudeText == longitudeText &&
        other.radiusText == radiusText &&
        other.coordinatesSummary == coordinatesSummary &&
        other.radiusSummary == radiusSummary &&
        other.openCount == openCount &&
        other.note == note &&
        listEquals(other.unsetSections, unsetSections);
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    sourceType,
    sourceValue,
    sourceTypeLabel,
    latitudeText,
    longitudeText,
    radiusText,
    coordinatesSummary,
    radiusSummary,
    openCount,
    note,
    Object.hashAll(unsetSections),
  );
}

/// Immutable view model for the Locations manager view.
@immutable
class LocationsManagerViewModel {
  /// Creates a [LocationsManagerViewModel].
  LocationsManagerViewModel({
    required Iterable<LocationCardViewModel> locations,
    required this.hasActiveGpsFix,
    this.activeGpsLatitudeText,
    this.activeGpsLongitudeText,
  }) : locations = List<LocationCardViewModel>.unmodifiable(locations);

  /// Active foreground GPS latitude formatted to 6dp, if available.
  final String? activeGpsLatitudeText;

  /// Active foreground GPS longitude formatted to 6dp, if available.
  final String? activeGpsLongitudeText;

  /// Whether a live foreground GPS fix is currently available.
  final bool hasActiveGpsFix;

  /// Alphabetically sorted location cards.
  final List<LocationCardViewModel> locations;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationsManagerViewModel &&
        listEquals(other.locations, locations) &&
        other.hasActiveGpsFix == hasActiveGpsFix &&
        other.activeGpsLatitudeText == activeGpsLatitudeText &&
        other.activeGpsLongitudeText == activeGpsLongitudeText;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(locations),
    hasActiveGpsFix,
    activeGpsLatitudeText,
    activeGpsLongitudeText,
  );
}

/// Builds a single [LabelCardViewModel] from [label].
LabelCardViewModel _buildLabelCardViewModel({
  required TdfLabel label,
  required int openCount,
  required Map<String, TdfLocation> locationsById,
  required AppLocalizations localizations,
}) {
  final summaryChips = ViewModelFormatters.buildConditionSummaryChips(
    ownRules: label.conditions,
    inheritedRules: const <TaskCondition>[],
    locationsById: locationsById,
    localizations: localizations,
  );
  final labelNote = label.note;
  final unset = <LabelSectionKind>[
    if (labelNote == null || labelNote.trim().isEmpty) LabelSectionKind.note,
    if (label.links.isEmpty) LabelSectionKind.links,
    if (label.conditions.isEmpty) LabelSectionKind.conditions,
  ];
  return LabelCardViewModel(
    id: label.id,
    name: label.name,
    colorHex: label.color ?? '',
    colorValue: ViewModelFormatters.parseLabelColorValue(label.color),
    isScoped: label.isScoped,
    openCount: openCount,
    note: label.note,
    links: <EntityLinkViewModel>[
      for (final link in label.links)
        EntityLinkViewModel(title: link.title, uri: link.uri),
    ],
    hasConditions: label.conditions.isNotEmpty,
    conditionsSummary: summaryChips,
    conditionDraft: ViewModelFormatters.buildConditionDraft(
      label.conditions,
      isTask: false,
    ),
    unsetSections: unset,
  );
}

/// Builds a single [LocationCardViewModel] from [location].
LocationCardViewModel _buildLocationCardViewModel({
  required TdfLocation location,
  required int openCount,
  required LocationSourceResolver locationController,
  required AppLocalizations localizations,
}) {
  final sourceType = locationController.classifySource(location.source);
  final shellSourceType = switch (sourceType) {
    LocationSourceType.gps => ShellLocationSourceType.gps,
    LocationSourceType.address => ShellLocationSourceType.address,
    LocationSourceType.plusCode => ShellLocationSourceType.plusCode,
  };
  final sourceTypeLabel = switch (shellSourceType) {
    ShellLocationSourceType.gps => localizations.locationSourceTypeGps,
    ShellLocationSourceType.address => localizations.locationSourceTypeAddress,
    ShellLocationSourceType.plusCode =>
      localizations.locationSourceTypePlusCode,
  };
  final rawSource = location.source?.trim() ?? '';
  final sourceValue =
      shellSourceType == ShellLocationSourceType.gps ||
          rawSource.toLowerCase() == 'manual' ||
          rawSource.toLowerCase() == 'gps'
      ? ''
      : rawSource;
  final radiusSummary = ViewModelFormatters.formatRadiusMeters(location.radius);
  final locationNote = location.note;
  final unset = <LocationSectionKind>[
    if (locationNote == null || locationNote.trim().isEmpty)
      LocationSectionKind.note,
  ];
  return LocationCardViewModel(
    id: location.id,
    name: location.name,
    sourceType: shellSourceType,
    sourceValue: sourceValue,
    sourceTypeLabel: sourceTypeLabel,
    latitudeText: location.latitudeText,
    longitudeText: location.longitudeText,
    radiusText: radiusSummary,
    coordinatesSummary: ViewModelFormatters.formatCoordinatesSummary(location),
    radiusSummary: radiusSummary,
    openCount: openCount,
    note: location.note,
    unsetSections: unset,
  );
}
