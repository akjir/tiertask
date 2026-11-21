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

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/location_state.dart';
import '../models/task_board.dart';
import '../models/tdf_error.dart';
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_timezone.dart';
import '../providers/config_providers.dart';
import '../providers/location_providers.dart';
import '../providers/sync_providers.dart';
import '../providers/task_providers.dart';
import '../providers/workspace_providers.dart';
import '../services/app_logger.dart';
import 'app_shell_controller.dart';
import 'board_v2_view_models.dart';
import 'floating_notice_controller.dart';
import 'location_editor_controller.dart';
import 'task_editor_controller.dart';
import 'ui_telemetry.dart';
import 'ui_v2_shell_models.dart';

/// Provides the model-free v2 Labels and Locations mutation and geocoding controller.
final entityV2ControllerProvider =
    NotifierProvider<EntityV2Controller, EntityV2ControllerState>(
      EntityV2Controller.new,
    );

/// Default geofence radius in meters assigned when quick-creating a location.
const double _defaultQuickCreateRadiusMeters = 200.0;

/// Minimum permitted location geofence radius in meters (`0.01m`).
const double _minLocationRadiusMeters = 0.01;

/// Sealed model-free outcome returned by [EntityV2Controller.resolveLocationSource] and [EntityV2Controller.applyDisambiguatedCandidate].
sealed class LocationV2SourceResult {
  /// Creates a [LocationV2SourceResult].
  const LocationV2SourceResult();
}

/// Outcome returned when address or Plus Code source resolution fails.
@immutable
final class LocationV2SourceError extends LocationV2SourceResult {
  /// Creates a [LocationV2SourceError] carrying a localized [message].
  const LocationV2SourceError({required this.message});

  /// Localized validation or lookup failure message.
  final String message;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationV2SourceError && other.message == message;
  }

  @override
  int get hashCode => message.hashCode;
}

/// Outcome returned when forward geocoding yields multiple choices requiring user selection.
@immutable
final class LocationV2SourceNeedsDisambiguation extends LocationV2SourceResult {
  /// Creates a [LocationV2SourceNeedsDisambiguation] carrying unmodifiable [candidates].
  LocationV2SourceNeedsDisambiguation({
    required Iterable<GeocodingCandidateViewModel> candidates,
    required this.sourceType,
    this.shortPlusCode,
  }) : candidates = List<GeocodingCandidateViewModel>.unmodifiable(candidates);

  /// Ranked model-free geocoding candidates indexed for [EntityV2Controller.applyDisambiguatedCandidate].
  final List<GeocodingCandidateViewModel> candidates;

  /// Optional short Plus Code awaiting reference-coordinate recovery.
  final String? shortPlusCode;

  /// Source mode under which disambiguation was requested.
  final ShellLocationSourceType sourceType;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationV2SourceNeedsDisambiguation &&
        other.sourceType == sourceType &&
        other.shortPlusCode == shortPlusCode &&
        listEquals(other.candidates, candidates);
  }

  @override
  int get hashCode =>
      Object.hash(sourceType, shortPlusCode, Object.hashAll(candidates));
}

/// Outcome returned when a source input resolves into formatted WGS-84 coordinates.
@immutable
final class LocationV2SourceResolved extends LocationV2SourceResult {
  /// Creates a [LocationV2SourceResolved].
  const LocationV2SourceResolved({
    required this.latitudeText,
    required this.longitudeText,
    required this.normalizedSource,
    required this.sourceType,
  });

  /// Formatted WGS-84 latitude rounded to at most 6 decimal places.
  final String latitudeText;

  /// Formatted WGS-84 longitude rounded to at most 6 decimal places.
  final String longitudeText;

  /// Canonical single-line source string persisted alongside the coordinates.
  final String normalizedSource;

  /// Source mode under which coordinates were resolved.
  final ShellLocationSourceType sourceType;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationV2SourceResolved &&
        other.latitudeText == latitudeText &&
        other.longitudeText == longitudeText &&
        other.normalizedSource == normalizedSource &&
        other.sourceType == sourceType;
  }

  @override
  int get hashCode =>
      Object.hash(latitudeText, longitudeText, normalizedSource, sourceType);
}

/// Model-free intent controller coordinating Label and Location creation, inline saves, deletion, GPS seeding, and geocoding.
class EntityV2Controller extends Notifier<EntityV2ControllerState> {
  List<GeocodingCandidate> _cachedCandidates = const <GeocodingCandidate>[];
  String? _cachedLocalityQuery;
  String? _cachedShortPlusCode;

  @override
  EntityV2ControllerState build() {
    ref.watch(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
    );
    _clearPendingDisambiguation();
    return const EntityV2ControllerState();
  }

  /// Applies the cached geocoding candidate at [candidateIndex] and returns a model-free [LocationV2SourceResult].
  LocationV2SourceResult applyDisambiguatedCandidate({
    required int candidateIndex,
    required ShellLocationSourceType sourceType,
    String? shortPlusCode,
    Locale? locale,
  }) {
    final localizations = _localizations(locale);
    if (candidateIndex < 0 || candidateIndex >= _cachedCandidates.length) {
      return LocationV2SourceError(
        message: localizations.locationResolveErrorNotFound,
      );
    }
    final candidate = _cachedCandidates[candidateIndex];
    final locationController = ref.read(locationEditorControllerProvider);
    final result = locationController.applyDisambiguatedCandidate(
      candidate: candidate,
      sourceType: _mapLocationSourceType(sourceType),
      shortPlusCode: shortPlusCode ?? _cachedShortPlusCode,
      localityQuery: _cachedLocalityQuery,
      locale: locale,
    );
    return switch (result) {
      LocationSourceResolved(
        :final latitude,
        :final longitude,
        :final normalizedSource,
        :final sourceType,
      ) =>
        _completeDisambiguatedResolution(
          locationController: locationController,
          latitude: latitude,
          longitude: longitude,
          normalizedSource: normalizedSource,
          sourceType: sourceType,
          localizations: localizations,
        ),
      LocationSourceResolutionError(:final localizedMessage) =>
        LocationV2SourceError(message: localizedMessage),
      LocationSourceNotNeeded() ||
      LocationSourceNeedsDisambiguation() => LocationV2SourceError(
        message: localizations.locationResolveErrorNotFound,
      ),
    };
  }

  /// Clears the custom `#RRGGBB` color on label [labelId].
  Future<V2ActionResult> clearLabelColor(String labelId, {Locale? locale}) {
    return _saveLabelSection(
      labelId: labelId,
      section: LabelSectionKind.color,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLabel(labelId, clearColor: true),
    );
  }

  /// Clears all inherited activation conditions on label [labelId].
  Future<V2ActionResult> clearLabelConditions(
    String labelId, {
    Locale? locale,
  }) {
    return _saveLabelSection(
      labelId: labelId,
      section: LabelSectionKind.conditions,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLabel(labelId, conditions: const <TaskCondition>[]),
    );
  }

  /// Clears the optional note on label [labelId].
  Future<V2ActionResult> clearLabelNote(String labelId, {Locale? locale}) {
    return _saveLabelSection(
      labelId: labelId,
      section: LabelSectionKind.note,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLabel(labelId, clearNote: true),
    );
  }

  /// Clears the optional note on location [locationId].
  Future<V2ActionResult> clearLocationNote(
    String locationId, {
    Locale? locale,
  }) {
    return _saveLocationSection(
      locationId: locationId,
      section: LocationSectionKind.note,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLocation(locationId, clearNote: true),
    );
  }

  /// Validates and commits an uncommitted [LabelDraftInput], closes the draft, expands and reveals the card, and emits a notice.
  Future<V2ActionResult> createLabelDraft(
    LabelDraftInput input, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final board = _currentBoard();
    final fieldErrors = <String, String>{};

    final validatedName = _validateLabelName(
      rawName: input.name,
      board: board,
      excludingLabelId: null,
      localizations: localizations,
    );
    if (validatedName.error case final nameError?) {
      fieldErrors['name'] = nameError;
    }

    final validatedColor = _validateOptionalColor(
      input.colorHex,
      localizations,
    );
    if (validatedColor.error case final colorError?) {
      fieldErrors['color'] = colorError;
    }

    final validatedNote = _validateOptionalNote(input.note, localizations);
    if (validatedNote.error case final noteError?) {
      fieldErrors['note'] = noteError;
    }

    final validatedLinks = _validateLabelLinks(input.links, localizations);
    if (validatedLinks.error case final linksError?) {
      fieldErrors['links'] = linksError;
    }

    final validatedConditions = switch (input.conditionDraft) {
      final draft? => _validateLabelConditions(draft, board, localizations),
      null => (conditions: const <TaskCondition>[], error: null),
    };
    if (validatedConditions.error case final conditionsError?) {
      fieldErrors['conditions'] = conditionsError;
    }

    if (fieldErrors.isNotEmpty) {
      return V2ActionValidationFailed(
        message: fieldErrors.values.first,
        fieldErrors: fieldErrors,
      );
    }

    final trimmedName = validatedName.value;
    if (trimmedName == null) {
      return V2ActionValidationFailed(
        message: localizations.labelNameErrorEmpty,
        fieldErrors: <String, String>{
          'name': localizations.labelNameErrorEmpty,
        },
      );
    }

    final newId = generateLabelId(
      timestamp: _nowUtc(),
      existingIds: _collectAllUsedEntityIds(board),
    );
    return _runBusyMutation(
      localizations: localizations,
      action: () async {
        await ref
            .read(taskNotifierProvider.notifier)
            .addLabel(
              trimmedName,
              id: newId,
              color: validatedColor.normalizedHex,
              note: validatedNote.normalizedNote,
              isScoped: input.isScoped,
              links: validatedLinks.links,
              conditions:
                  validatedConditions.conditions ?? const <TaskCondition>[],
            );
        if (!ref.mounted) {
          return V2ActionSucceeded(
            entityId: newId,
            noticeMessage: localizations.labelSavedNotice,
          );
        }
        final shellController = ref.read(appShellControllerProvider.notifier);
        shellController.cancelDraft();
        UiTelemetry.logEntityDraftCommitted(EntityDraftKind.label.name);
        shellController.expandEntity(
          EntityRef(kind: EntityKind.label, id: newId),
          reveal: true,
        );
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(localizations.labelSavedNotice);
        return V2ActionSucceeded(
          entityId: newId,
          noticeMessage: localizations.labelSavedNotice,
        );
      },
    );
  }

  /// Validates and commits an uncommitted [LocationDraftInput], closes the draft, expands and reveals the card, and emits a notice.
  Future<V2ActionResult> createLocationDraft(
    LocationDraftInput input, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final board = _currentBoard();
    final locationController = ref.read(locationEditorControllerProvider);
    final fieldErrors = <String, String>{};

    if (board.locations.length >= maxTdfLocations) {
      fieldErrors['limit'] = localizations.errorLocalFileTooLarge;
    }

    final validatedName = _validateRequiredSingleLineText(
      input.name,
      localizations.locationNameErrorEmpty,
    );
    if (validatedName.error case final nameError?) {
      fieldErrors['name'] = nameError;
    }

    final validatedCoordinates = _parseCoordinates(
      rawLatitude: input.rawLatitude,
      rawLongitude: input.rawLongitude,
      locationController: locationController,
      errorMessage: localizations.locationCoordinatesErrorInvalid,
    );
    if (validatedCoordinates.error case final coordinatesError?) {
      fieldErrors['coordinates'] = coordinatesError;
    }

    final radiusMeters = _parseRadiusMeters(input.rawRadius);
    if (radiusMeters == null) {
      fieldErrors['radius'] = localizations.locationRadiusErrorInvalid;
    }

    final validatedSource = _validateLocationSource(
      sourceType: input.sourceType,
      rawSource: input.rawSource,
      localizations: localizations,
    );
    if (validatedSource.error case final sourceError?) {
      fieldErrors['source'] = sourceError;
    }

    final validatedNote = _validateOptionalNote(input.note, localizations);
    if (validatedNote.error case final noteError?) {
      fieldErrors['note'] = noteError;
    }

    if (fieldErrors.isNotEmpty) {
      return V2ActionValidationFailed(
        message: fieldErrors.values.first,
        fieldErrors: fieldErrors,
      );
    }

    final trimmedName = validatedName.value;
    final latitude = validatedCoordinates.latitude;
    final longitude = validatedCoordinates.longitude;
    if (trimmedName == null ||
        latitude == null ||
        longitude == null ||
        radiusMeters == null) {
      return V2ActionValidationFailed(
        message: localizations.locationCoordinatesErrorInvalid,
      );
    }

    final newId = generateLocationId(
      timestamp: _nowUtc(),
      existingIds: _collectAllUsedEntityIds(board),
    );
    return _runBusyMutation(
      localizations: localizations,
      action: () async {
        await ref
            .read(taskNotifierProvider.notifier)
            .addLocation(
              trimmedName,
              id: newId,
              latitude: latitude,
              longitude: longitude,
              radiusMeters: radiusMeters,
              source: validatedSource.normalizedSource ?? '',
              note: validatedNote.normalizedNote,
            );
        if (!ref.mounted) {
          return V2ActionSucceeded(
            entityId: newId,
            noticeMessage: localizations.locationSavedNotice,
          );
        }
        final shellController = ref.read(appShellControllerProvider.notifier);
        shellController.cancelDraft();
        UiTelemetry.logEntityDraftCommitted(EntityDraftKind.location.name);
        shellController.expandEntity(
          EntityRef(kind: EntityKind.location, id: newId),
          reveal: true,
        );
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(localizations.locationSavedNotice);
        return V2ActionSucceeded(
          entityId: newId,
          noticeMessage: localizations.locationSavedNotice,
        );
      },
    );
  }

  /// Deletes label [labelId] under local-mutation suppression, collapses the card, and emits `labelDeletedNotice` without Undo.
  Future<V2ActionResult> deleteLabel(String labelId, {Locale? locale}) {
    final localizations = _localizations(locale);
    final target = EntityRef(kind: EntityKind.label, id: labelId);
    return _runBusyMutation(
      localizations: localizations,
      action: () async {
        await ref
            .read(appShellControllerProvider.notifier)
            .runLocalEntityMutation(
              target,
              () =>
                  ref.read(taskNotifierProvider.notifier).deleteLabel(labelId),
            );
        if (!ref.mounted) {
          return V2ActionSucceeded(
            entityId: labelId,
            noticeMessage: localizations.labelDeletedNotice,
          );
        }
        ref.read(appShellControllerProvider.notifier).collapseEntity();
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(localizations.labelDeletedNotice);
        return V2ActionSucceeded(
          entityId: labelId,
          noticeMessage: localizations.labelDeletedNotice,
        );
      },
    );
  }

  /// Deletes location [locationId] under local-mutation suppression, collapses the card, and emits `locationDeletedNotice` without Undo.
  Future<V2ActionResult> deleteLocation(String locationId, {Locale? locale}) {
    final localizations = _localizations(locale);
    final target = EntityRef(kind: EntityKind.location, id: locationId);
    return _runBusyMutation(
      localizations: localizations,
      action: () async {
        await ref
            .read(appShellControllerProvider.notifier)
            .runLocalEntityMutation(
              target,
              () => ref
                  .read(taskNotifierProvider.notifier)
                  .deleteLocation(locationId),
            );
        if (!ref.mounted) {
          return V2ActionSucceeded(
            entityId: locationId,
            noticeMessage: localizations.locationDeletedNotice,
          );
        }
        ref.read(appShellControllerProvider.notifier).collapseEntity();
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(localizations.locationDeletedNotice);
        return V2ActionSucceeded(
          entityId: locationId,
          noticeMessage: localizations.locationDeletedNotice,
        );
      },
    );
  }

  /// Quick-creates a label named [rawName] with the next rotating preset color, expands and reveals it, and emits `labelSavedNotice`.
  Future<V2ActionResult> quickCreateLabel(
    String rawName, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final board = _currentBoard();
    final validatedName = _validateLabelName(
      rawName: rawName,
      board: board,
      excludingLabelId: null,
      localizations: localizations,
    );
    if (validatedName.error case final nameError?) {
      if (validatedName.isDuplicate) {
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(nameError, tone: NoticeTone.danger);
      }
      return V2ActionValidationFailed(
        message: nameError,
        fieldErrors: <String, String>{'name': nameError},
      );
    }

    final trimmedName = validatedName.value;
    if (trimmedName == null) {
      return V2ActionValidationFailed(
        message: localizations.labelNameErrorEmpty,
        fieldErrors: <String, String>{
          'name': localizations.labelNameErrorEmpty,
        },
      );
    }

    final colorHex =
        canonicalLabelPresetHexColors[board.labels.length %
            canonicalLabelPresetHexColors.length];
    final newId = generateLabelId(
      timestamp: _nowUtc(),
      existingIds: _collectAllUsedEntityIds(board),
    );
    return _runBusyMutation(
      localizations: localizations,
      action: () async {
        await ref
            .read(taskNotifierProvider.notifier)
            .addLabel(trimmedName, id: newId, color: colorHex);
        if (!ref.mounted) {
          return V2ActionSucceeded(
            entityId: newId,
            noticeMessage: localizations.labelSavedNotice,
          );
        }
        ref
            .read(appShellControllerProvider.notifier)
            .expandEntity(
              EntityRef(kind: EntityKind.label, id: newId),
              reveal: true,
            );
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(localizations.labelSavedNotice);
        return V2ActionSucceeded(
          entityId: newId,
          noticeMessage: localizations.labelSavedNotice,
        );
      },
    );
  }

  /// Quick-creates a location named [rawName] seeded from the active GPS fix (or `0.0, 0.0`) with `200m` radius, expands and reveals it, and emits `locationSavedNotice`.
  Future<V2ActionResult> quickCreateLocation(
    String rawName, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final board = _currentBoard();
    final validatedName = _validateRequiredSingleLineText(
      rawName,
      localizations.locationNameErrorEmpty,
    );
    if (validatedName.error case final nameError?) {
      return V2ActionValidationFailed(
        message: nameError,
        fieldErrors: <String, String>{'name': nameError},
      );
    }

    if (board.locations.length >= maxTdfLocations) {
      final limitMessage = localizations.errorLocalFileTooLarge;
      ref
          .read(floatingNoticeControllerProvider.notifier)
          .showNotice(limitMessage, tone: NoticeTone.danger);
      return V2ActionValidationFailed(
        message: limitMessage,
        fieldErrors: <String, String>{'limit': limitMessage},
      );
    }

    final trimmedName = validatedName.value;
    if (trimmedName == null) {
      return V2ActionValidationFailed(
        message: localizations.locationNameErrorEmpty,
        fieldErrors: <String, String>{
          'name': localizations.locationNameErrorEmpty,
        },
      );
    }

    final seededCoordinates = _seedCoordinatesFromForegroundFix();
    final newId = generateLocationId(
      timestamp: _nowUtc(),
      existingIds: _collectAllUsedEntityIds(board),
    );
    return _runBusyMutation(
      localizations: localizations,
      action: () async {
        await ref
            .read(taskNotifierProvider.notifier)
            .addLocation(
              trimmedName,
              id: newId,
              latitude: seededCoordinates.latitude,
              longitude: seededCoordinates.longitude,
              radiusMeters: _defaultQuickCreateRadiusMeters,
              source: '',
            );
        if (!ref.mounted) {
          return V2ActionSucceeded(
            entityId: newId,
            noticeMessage: localizations.locationSavedNotice,
          );
        }
        ref
            .read(appShellControllerProvider.notifier)
            .expandEntity(
              EntityRef(kind: EntityKind.location, id: newId),
              reveal: true,
            );
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(localizations.locationSavedNotice);
        return V2ActionSucceeded(
          entityId: newId,
          noticeMessage: localizations.locationSavedNotice,
        );
      },
    );
  }

  /// Resolves the active foreground GPS fix formatted to 6 decimal places, emitting `gpsAppliedNotice` when found.
  Future<({String latitudeText, String longitudeText})?>
  resolveCurrentGpsPosition({Locale? locale}) async {
    if (state.isResolvingLocation) {
      return null;
    }
    final localizations = _localizations(locale);
    final locationController = ref.read(locationEditorControllerProvider);
    state = state.copyWith(isResolvingLocation: true);
    try {
      final coordinates = await locationController.resolveCurrentGpsPosition();
      if (!ref.mounted || coordinates == null) {
        return null;
      }
      final formattedLatitude = locationController.formatGpsCoordinate(
        coordinates.latitude,
      );
      final formattedLongitude = locationController.formatGpsCoordinate(
        coordinates.longitude,
      );
      ref
          .read(floatingNoticeControllerProvider.notifier)
          .showNotice(localizations.gpsAppliedNotice);
      return (
        latitudeText: formattedLatitude,
        longitudeText: formattedLongitude,
      );
    } finally {
      if (ref.mounted) {
        state = state.copyWith(isResolvingLocation: false);
      }
    }
  }

  /// Resolves an address or Plus Code [rawSource] under [sourceType], caching candidates privately for disambiguation.
  Future<LocationV2SourceResult> resolveLocationSource({
    required ShellLocationSourceType sourceType,
    required String rawSource,
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    _clearPendingDisambiguation();
    if (sourceType == ShellLocationSourceType.gps) {
      return LocationV2SourceError(
        message: localizations.locationResolveErrorNotFound,
      );
    }
    if (_containsAsciiControlChar(rawSource) ||
        TdfCalendar.countUnicodeScalars(rawSource) == null) {
      return LocationV2SourceError(
        message: sourceType == ShellLocationSourceType.plusCode
            ? localizations.locationResolveErrorInvalidPlusCode
            : localizations.locationResolveErrorNotFound,
      );
    }
    if (state.isResolvingLocation) {
      return LocationV2SourceError(
        message: localizations.locationResolveErrorNotFound,
      );
    }

    final locationController = ref.read(locationEditorControllerProvider);
    state = state.copyWith(isResolvingLocation: true);
    try {
      final result = await locationController.resolveSource(
        sourceType: _mapLocationSourceType(sourceType),
        rawSource: rawSource,
        locale: locale,
      );
      if (!ref.mounted) {
        return LocationV2SourceError(
          message: localizations.locationResolveErrorNotFound,
        );
      }
      return switch (result) {
        LocationSourceResolved(
          :final latitude,
          :final longitude,
          :final normalizedSource,
          :final sourceType,
        ) =>
          _completeDirectResolution(
            locationController: locationController,
            latitude: latitude,
            longitude: longitude,
            normalizedSource: normalizedSource,
            sourceType: sourceType,
            localizations: localizations,
          ),
        LocationSourceNeedsDisambiguation(
          :final candidates,
          :final sourceType,
          :final shortPlusCode,
          :final localityQuery,
        ) =>
          _cacheDisambiguationCandidates(
            candidates: candidates,
            sourceType: sourceType,
            shortPlusCode: shortPlusCode,
            localityQuery: localityQuery,
          ),
        LocationSourceResolutionError(:final localizedMessage) =>
          LocationV2SourceError(message: localizedMessage),
        LocationSourceNotNeeded() => LocationV2SourceError(
          message: localizations.locationResolveErrorNotFound,
        ),
      };
    } on Exception {
      if (AppLogger.shouldLog(LogLevel.warn)) {
        AppLogger.event(
          LogLevel.warn,
          LogTag.ui,
          'ui.location_source.resolve_failed',
          fields: <String, Object?>{'source_type': sourceType.name},
        );
      }
      return LocationV2SourceError(
        message: localizations.locationResolveErrorNotFound,
      );
    } finally {
      if (ref.mounted) {
        state = state.copyWith(isResolvingLocation: false);
      }
    }
  }

  /// Validates and saves [rawColorHex] onto label [labelId] (clearing color when blank).
  Future<V2ActionResult> saveLabelColor(
    String labelId,
    String rawColorHex, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final validatedColor = _validateOptionalColor(rawColorHex, localizations);
    if (validatedColor.error case final colorError?) {
      return V2ActionValidationFailed(
        message: colorError,
        fieldErrors: <String, String>{'color': colorError},
      );
    }
    final normalizedHex = validatedColor.normalizedHex;
    return _saveLabelSection(
      labelId: labelId,
      section: LabelSectionKind.color,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLabel(
            labelId,
            color: normalizedHex,
            clearColor: normalizedHex == null,
          ),
    );
  }

  /// Validates and saves activation conditions from [draft] onto label [labelId].
  Future<V2ActionResult> saveLabelConditions(
    String labelId,
    ConditionDraftViewModel draft, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final board = _currentBoard();
    final validated = _validateLabelConditions(draft, board, localizations);
    if (validated.error case final conditionsError?) {
      return V2ActionValidationFailed(
        message: conditionsError,
        fieldErrors: <String, String>{'conditions': conditionsError},
      );
    }
    return _saveLabelSection(
      labelId: labelId,
      section: LabelSectionKind.conditions,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLabel(
            labelId,
            conditions: validated.conditions ?? const <TaskCondition>[],
          ),
    );
  }

  /// Validates and saves reference [links] (`<= 20`) onto label [labelId].
  Future<V2ActionResult> saveLabelLinks(
    String labelId,
    List<EntityLinkViewModel> links, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final validated = _validateLabelLinks(links, localizations);
    if (validated.error case final linksError?) {
      return V2ActionValidationFailed(
        message: linksError,
        fieldErrors: <String, String>{'links': linksError},
      );
    }
    return _saveLabelSection(
      labelId: labelId,
      section: LabelSectionKind.links,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLabel(labelId, links: validated.links ?? const <TaskLink>[]),
    );
  }

  /// Validates and saves an updated name [rawName] onto label [labelId].
  Future<V2ActionResult> saveLabelName(
    String labelId,
    String rawName, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final board = _currentBoard();
    if (board.findLabel(labelId) == null) {
      return _handleMissingEntity(localizations);
    }
    final validatedName = _validateLabelName(
      rawName: rawName,
      board: board,
      excludingLabelId: labelId,
      localizations: localizations,
    );
    if (validatedName.error case final nameError?) {
      return V2ActionValidationFailed(
        message: nameError,
        fieldErrors: <String, String>{'name': nameError},
      );
    }
    final trimmedName = validatedName.value;
    if (trimmedName == null) {
      return V2ActionValidationFailed(
        message: localizations.labelNameErrorEmpty,
        fieldErrors: <String, String>{
          'name': localizations.labelNameErrorEmpty,
        },
      );
    }
    return _saveLabelSection(
      labelId: labelId,
      section: LabelSectionKind.title,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLabel(labelId, name: trimmedName),
    );
  }

  /// Validates and saves [rawNote] (`<= 2000` scalars) onto label [labelId], clearing when blank.
  Future<V2ActionResult> saveLabelNote(
    String labelId,
    String rawNote, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final validated = _validateOptionalNote(rawNote, localizations);
    if (validated.error case final noteError?) {
      return V2ActionValidationFailed(
        message: noteError,
        fieldErrors: <String, String>{'note': noteError},
      );
    }
    final normalizedNote = validated.normalizedNote;
    return _saveLabelSection(
      labelId: labelId,
      section: LabelSectionKind.note,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLabel(
            labelId,
            note: normalizedNote,
            clearNote: normalizedNote == null,
          ),
    );
  }

  /// Validates and saves coordinates, geofence radius, and source metadata onto location [locationId].
  Future<V2ActionResult> saveLocationCoordinates(
    String locationId, {
    required ShellLocationSourceType sourceType,
    required String rawSource,
    required String rawLatitude,
    required String rawLongitude,
    required String rawRadius,
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final locationController = ref.read(locationEditorControllerProvider);
    final fieldErrors = <String, String>{};

    final validatedCoordinates = _parseCoordinates(
      rawLatitude: rawLatitude,
      rawLongitude: rawLongitude,
      locationController: locationController,
      errorMessage: localizations.locationCoordinatesErrorInvalid,
    );
    if (validatedCoordinates.error case final coordinatesError?) {
      fieldErrors['coordinates'] = coordinatesError;
    }

    final radiusMeters = _parseRadiusMeters(rawRadius);
    if (radiusMeters == null) {
      fieldErrors['radius'] = localizations.locationRadiusErrorInvalid;
    }

    final validatedSource = _validateLocationSource(
      sourceType: sourceType,
      rawSource: rawSource,
      localizations: localizations,
    );
    if (validatedSource.error case final sourceError?) {
      fieldErrors['source'] = sourceError;
    }

    if (fieldErrors.isNotEmpty) {
      return V2ActionValidationFailed(
        message: fieldErrors.values.first,
        fieldErrors: fieldErrors,
      );
    }

    final latitude = validatedCoordinates.latitude;
    final longitude = validatedCoordinates.longitude;
    if (latitude == null || longitude == null || radiusMeters == null) {
      return V2ActionValidationFailed(
        message: localizations.locationCoordinatesErrorInvalid,
      );
    }
    final normalizedSource = validatedSource.normalizedSource;
    return _saveLocationSection(
      locationId: locationId,
      section: LocationSectionKind.coordinates,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLocation(
            locationId,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            source: normalizedSource,
            clearSource: normalizedSource == null,
          ),
    );
  }

  /// Validates and saves an updated name [rawName] onto location [locationId].
  Future<V2ActionResult> saveLocationName(
    String locationId,
    String rawName, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final validatedName = _validateRequiredSingleLineText(
      rawName,
      localizations.locationNameErrorEmpty,
    );
    if (validatedName.error case final nameError?) {
      return V2ActionValidationFailed(
        message: nameError,
        fieldErrors: <String, String>{'name': nameError},
      );
    }
    final trimmedName = validatedName.value;
    if (trimmedName == null) {
      return V2ActionValidationFailed(
        message: localizations.locationNameErrorEmpty,
        fieldErrors: <String, String>{
          'name': localizations.locationNameErrorEmpty,
        },
      );
    }
    return _saveLocationSection(
      locationId: locationId,
      section: LocationSectionKind.title,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLocation(locationId, name: trimmedName),
    );
  }

  /// Validates and saves [rawNote] (`<= 2000` scalars) onto location [locationId], clearing when blank.
  Future<V2ActionResult> saveLocationNote(
    String locationId,
    String rawNote, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final validated = _validateOptionalNote(rawNote, localizations);
    if (validated.error case final noteError?) {
      return V2ActionValidationFailed(
        message: noteError,
        fieldErrors: <String, String>{'note': noteError},
      );
    }
    final normalizedNote = validated.normalizedNote;
    return _saveLocationSection(
      locationId: locationId,
      section: LocationSectionKind.note,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLocation(
            locationId,
            note: normalizedNote,
            clearNote: normalizedNote == null,
          ),
    );
  }

  /// Immediately persists the live Board Scope switch (`isScoped`) onto label [labelId].
  Future<V2ActionResult> setLabelScoped(
    String labelId,
    bool isScoped, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    if (_currentBoard().findLabel(labelId) == null) {
      return _handleMissingEntity(localizations);
    }
    return _runBusyMutation(
      localizations: localizations,
      action: () async {
        await ref
            .read(taskNotifierProvider.notifier)
            .updateLabel(labelId, isScoped: isScoped);
        if (!ref.mounted) {
          return V2ActionSucceeded(
            entityId: labelId,
            noticeMessage: localizations.labelSavedNotice,
          );
        }
        if (AppLogger.shouldLog(LogLevel.info)) {
          AppLogger.event(
            LogLevel.info,
            LogTag.ui,
            'ui.label_scope.toggled',
            fields: <String, Object?>{'id': labelId, 'scoped': isScoped},
          );
        }
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(localizations.labelSavedNotice);
        return V2ActionSucceeded(
          entityId: labelId,
          noticeMessage: localizations.labelSavedNotice,
        );
      },
    );
  }

  /// Caches raw [GeocodingCandidate] entries privately and returns model-free disambiguation candidates.
  LocationV2SourceNeedsDisambiguation _cacheDisambiguationCandidates({
    required List<GeocodingCandidate> candidates,
    required LocationSourceType sourceType,
    required String? shortPlusCode,
    required String? localityQuery,
  }) {
    _cachedCandidates = candidates;
    _cachedShortPlusCode = shortPlusCode;
    _cachedLocalityQuery = localityQuery;
    final viewModels = <GeocodingCandidateViewModel>[
      for (var i = 0; i < candidates.length; i++)
        GeocodingCandidateViewModel(
          index: i,
          displayName: candidates[i].displayName,
          latitude: candidates[i].latitude,
          longitude: candidates[i].longitude,
          coordinatesSummary: candidates[i].formattedCoordinates,
        ),
    ];
    return LocationV2SourceNeedsDisambiguation(
      candidates: viewModels,
      sourceType: _mapShellLocationSourceType(sourceType),
      shortPlusCode: shortPlusCode,
    );
  }

  /// Clears any privately cached geocoding disambiguation state.
  void _clearPendingDisambiguation() {
    _cachedCandidates = const <GeocodingCandidate>[];
    _cachedShortPlusCode = null;
    _cachedLocalityQuery = null;
  }

  /// Formats a resolved geocoding coordinate pair, emits `locationResolvedNotice`, and returns [LocationV2SourceResolved].
  LocationV2SourceResolved _completeDirectResolution({
    required LocationEditorController locationController,
    required double latitude,
    required double longitude,
    required String normalizedSource,
    required LocationSourceType sourceType,
    required AppLocalizations localizations,
  }) {
    ref
        .read(floatingNoticeControllerProvider.notifier)
        .showNotice(localizations.locationResolvedNotice);
    return LocationV2SourceResolved(
      latitudeText: locationController.formatGpsCoordinate(latitude),
      longitudeText: locationController.formatGpsCoordinate(longitude),
      normalizedSource: normalizedSource,
      sourceType: _mapShellLocationSourceType(sourceType),
    );
  }

  /// Clears pending disambiguation cache after candidate selection and delegates to [_completeDirectResolution].
  LocationV2SourceResolved _completeDisambiguatedResolution({
    required LocationEditorController locationController,
    required double latitude,
    required double longitude,
    required String normalizedSource,
    required LocationSourceType sourceType,
    required AppLocalizations localizations,
  }) {
    _clearPendingDisambiguation();
    return _completeDirectResolution(
      locationController: locationController,
      latitude: latitude,
      longitude: longitude,
      normalizedSource: normalizedSource,
      sourceType: sourceType,
      localizations: localizations,
    );
  }

  /// Returns the currently loaded [TaskBoard] or an empty board before initialization completes.
  TaskBoard _currentBoard() =>
      ref.read(taskNotifierProvider).asData?.value ?? TaskBoard.empty();

  /// Closes any active inline edit and returns a localized missing-entity validation error.
  V2ActionValidationFailed _handleMissingEntity(
    AppLocalizations localizations,
  ) {
    ref.read(appShellControllerProvider.notifier).closeInlineEdit();
    return V2ActionValidationFailed(
      message: localizations.entityRemovedExternallyNotice,
    );
  }

  /// Resolves [AppLocalizations] from [locale] or the active [appLocaleProvider].
  AppLocalizations _localizations(Locale? locale) =>
      lookupAppLocalizations(locale ?? ref.read(appLocaleProvider));

  /// Emits redacted inline or general persistence-failure diagnostics.
  void _logPersistenceFailure({
    required String? inlineEntityKind,
    required String? inlineEntityId,
    required String? inlineSection,
    required String errorKind,
  }) {
    if (inlineEntityKind != null &&
        inlineEntityId != null &&
        inlineSection != null) {
      UiTelemetry.logInlineEditFailed(
        kind: inlineEntityKind,
        entityId: inlineEntityId,
        section: inlineSection,
      );
      return;
    }
    if (AppLogger.shouldLog(LogLevel.warn)) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.ui,
        'ui.entity_v2.persist_failed',
        fields: <String, Object?>{'kind': errorKind},
      );
    }
  }

  /// Returns the current UTC timestamp from [clockProvider].
  DateTime _nowUtc() => ref.read(clockProvider)().toUtc();

  /// Executes [action] under a serialized `isBusy` guard and maps persistence exceptions into sanitized [V2ActionPersistFailed] outcomes.
  Future<V2ActionResult> _runBusyMutation({
    required AppLocalizations localizations,
    required Future<V2ActionResult> Function() action,
    String? inlineEntityKind,
    String? inlineEntityId,
    String? inlineSection,
  }) async {
    if (state.isBusy) {
      return V2ActionPersistFailed(
        message: localizations.errorSaveLocalFileFailed(
          localizations.fileReadStatusUnreadable,
        ),
      );
    }
    state = state.copyWith(isBusy: true);
    try {
      return await action();
    } on TdfException catch (error) {
      _logPersistenceFailure(
        inlineEntityKind: inlineEntityKind,
        inlineEntityId: inlineEntityId,
        inlineSection: inlineSection,
        errorKind: error.kind.name,
      );
      return V2ActionPersistFailed(
        message: _mapTdfPersistError(error.kind, localizations),
      );
    } on Exception {
      _logPersistenceFailure(
        inlineEntityKind: inlineEntityKind,
        inlineEntityId: inlineEntityId,
        inlineSection: inlineSection,
        errorKind: 'exception',
      );
      return V2ActionPersistFailed(
        message: localizations.errorSaveLocalFileFailed(
          localizations.fileReadStatusUnreadable,
        ),
      );
    } finally {
      if (ref.mounted) {
        state = state.copyWith(isBusy: false);
      }
    }
  }

  /// Persists a single inline section update on label [labelId], closing the inline editor and emitting telemetry and notice.
  Future<V2ActionResult> _saveLabelSection({
    required String labelId,
    required LabelSectionKind section,
    required Locale? locale,
    required Future<void> Function() persist,
  }) async {
    final localizations = _localizations(locale);
    if (_currentBoard().findLabel(labelId) == null) {
      return _handleMissingEntity(localizations);
    }
    return _runBusyMutation(
      localizations: localizations,
      inlineEntityKind: EntityKind.label.name,
      inlineEntityId: labelId,
      inlineSection: section.name,
      action: () async {
        await persist();
        if (!ref.mounted) {
          return V2ActionSucceeded(
            entityId: labelId,
            noticeMessage: localizations.labelSavedNotice,
          );
        }
        final syncState = ref.read(syncStateProvider);
        if (syncState.errorMessage != null || syncState.hasOpenConflict) {
          _logPersistenceFailure(
            inlineEntityKind: EntityKind.label.name,
            inlineEntityId: labelId,
            inlineSection: section.name,
            errorKind: syncState.hasOpenConflict ? 'conflict' : 'error',
          );
          final message = syncState.errorMessage;
          return V2ActionPersistFailed(
            message: message != null && message.trim().isNotEmpty
                ? message
                : localizations.syncStatusError,
          );
        }
        ref.read(appShellControllerProvider.notifier).closeInlineEdit();
        UiTelemetry.logInlineEditSaved(
          kind: EntityKind.label.name,
          entityId: labelId,
          section: section.name,
        );
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(localizations.labelSavedNotice);
        return V2ActionSucceeded(
          entityId: labelId,
          noticeMessage: localizations.labelSavedNotice,
        );
      },
    );
  }

  /// Persists a single inline section update on location [locationId], closing the inline editor and emitting telemetry and notice.
  Future<V2ActionResult> _saveLocationSection({
    required String locationId,
    required LocationSectionKind section,
    required Locale? locale,
    required Future<void> Function() persist,
  }) async {
    final localizations = _localizations(locale);
    if (_currentBoard().findLocation(locationId) == null) {
      return _handleMissingEntity(localizations);
    }
    return _runBusyMutation(
      localizations: localizations,
      inlineEntityKind: EntityKind.location.name,
      inlineEntityId: locationId,
      inlineSection: section.name,
      action: () async {
        await persist();
        if (!ref.mounted) {
          return V2ActionSucceeded(
            entityId: locationId,
            noticeMessage: localizations.locationSavedNotice,
          );
        }
        final syncState = ref.read(syncStateProvider);
        if (syncState.errorMessage != null || syncState.hasOpenConflict) {
          _logPersistenceFailure(
            inlineEntityKind: EntityKind.location.name,
            inlineEntityId: locationId,
            inlineSection: section.name,
            errorKind: syncState.hasOpenConflict ? 'conflict' : 'error',
          );
          final message = syncState.errorMessage;
          return V2ActionPersistFailed(
            message: message != null && message.trim().isNotEmpty
                ? message
                : localizations.syncStatusError,
          );
        }
        ref.read(appShellControllerProvider.notifier).closeInlineEdit();
        UiTelemetry.logInlineEditSaved(
          kind: EntityKind.location.name,
          entityId: locationId,
          section: section.name,
        );
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(localizations.locationSavedNotice);
        return V2ActionSucceeded(
          entityId: locationId,
          noticeMessage: localizations.locationSavedNotice,
        );
      },
    );
  }

  /// Seeds initial coordinates from the active foreground GPS fix rounded to 6 decimal places, defaulting to `(0.0, 0.0)`.
  ({double latitude, double longitude}) _seedCoordinatesFromForegroundFix() {
    final fix = ref.read(locationStateProvider).fix;
    if (fix == null || !fix.hasCoordinates) {
      return (latitude: 0.0, longitude: 0.0);
    }
    final rawLatitude = fix.latitude;
    final rawLongitude = fix.longitude;
    if (rawLatitude == null || rawLongitude == null) {
      return (latitude: 0.0, longitude: 0.0);
    }
    final locationController = ref.read(locationEditorControllerProvider);
    if (!locationController.isValidCoordinates(rawLatitude, rawLongitude)) {
      return (latitude: 0.0, longitude: 0.0);
    }
    final latitude =
        double.tryParse(TdfLocation.formatRoundedDouble(rawLatitude, 6)) ?? 0.0;
    final longitude =
        double.tryParse(TdfLocation.formatRoundedDouble(rawLongitude, 6)) ??
        0.0;
    return (latitude: latitude, longitude: longitude);
  }
}

/// Immutable operational status state of [EntityV2Controller].
@immutable
class EntityV2ControllerState {
  /// Creates an [EntityV2ControllerState].
  const EntityV2ControllerState({
    this.isBusy = false,
    this.isResolvingLocation = false,
  });

  /// Whether an entity create, inline save, or delete mutation is currently in flight.
  final bool isBusy;

  /// Whether a GPS refresh or address/Plus Code forward-geocoding lookup is currently in flight.
  final bool isResolvingLocation;

  /// Returns a copy of this [EntityV2ControllerState] with updated fields.
  EntityV2ControllerState copyWith({bool? isBusy, bool? isResolvingLocation}) {
    return EntityV2ControllerState(
      isBusy: isBusy ?? this.isBusy,
      isResolvingLocation: isResolvingLocation ?? this.isResolvingLocation,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EntityV2ControllerState &&
        other.isBusy == isBusy &&
        other.isResolvingLocation == isResolvingLocation;
  }

  @override
  int get hashCode => Object.hash(isBusy, isResolvingLocation);
}

/// Immutable model-free geocoding candidate presented in disambiguation dialogs.
@immutable
class GeocodingCandidateViewModel {
  /// Creates a [GeocodingCandidateViewModel].
  const GeocodingCandidateViewModel({
    required this.index,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.coordinatesSummary,
  });

  /// Formatted coordinate preview string rounded to at most 6 decimal places.
  final String coordinatesSummary;

  /// Human-readable street address or locality display name.
  final String displayName;

  /// Zero-based index passed back to [EntityV2Controller.applyDisambiguatedCandidate].
  final int index;

  /// Candidate WGS-84 latitude in decimal degrees.
  final double latitude;

  /// Candidate WGS-84 longitude in decimal degrees.
  final double longitude;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GeocodingCandidateViewModel &&
        other.index == index &&
        other.displayName == displayName &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.coordinatesSummary == coordinatesSummary;
  }

  @override
  int get hashCode =>
      Object.hash(index, displayName, latitude, longitude, coordinatesSummary);
}

/// Immutable model-free input payload submitted from an uncommitted Label Draft Card.
@immutable
class LabelDraftInput {
  /// Creates a [LabelDraftInput].
  LabelDraftInput({
    required this.name,
    this.colorHex = '',
    this.isScoped = false,
    this.note = '',
    Iterable<EntityLinkViewModel> links = const <EntityLinkViewModel>[],
    this.conditionDraft,
  }) : links = List<EntityLinkViewModel>.unmodifiable(links);

  /// Optional `#RRGGBB` hexadecimal color text, or empty when unset.
  final String colorHex;

  /// Optional inherited activation conditions draft.
  final ConditionDraftViewModel? conditionDraft;

  /// Whether this label acts as a Scoped Queue (`label <id> scoped {`).
  final bool isScoped;

  /// Unmodifiable list of reference links (`0..20`).
  final List<EntityLinkViewModel> links;

  /// Raw label display name (`1..500` Unicode scalar values).
  final String name;

  /// Raw optional multi-line label note (`<= 2000` Unicode scalar values).
  final String note;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LabelDraftInput &&
        other.name == name &&
        other.colorHex == colorHex &&
        other.isScoped == isScoped &&
        other.note == note &&
        listEquals(other.links, links) &&
        other.conditionDraft == conditionDraft;
  }

  @override
  int get hashCode => Object.hash(
    name,
    colorHex,
    isScoped,
    note,
    Object.hashAll(links),
    conditionDraft,
  );
}

/// Immutable model-free input payload submitted from an uncommitted Location Draft Card.
@immutable
class LocationDraftInput {
  /// Creates a [LocationDraftInput].
  const LocationDraftInput({
    required this.name,
    this.sourceType = ShellLocationSourceType.gps,
    this.rawSource = '',
    required this.rawLatitude,
    required this.rawLongitude,
    required this.rawRadius,
    this.note = '',
  });

  /// Raw location display name (`1..500` Unicode scalar values).
  final String name;

  /// Raw optional multi-line location note (`<= 2000` Unicode scalar values).
  final String note;

  /// Raw WGS-84 latitude input (`-90..90`, supporting `.` or `,`).
  final String rawLatitude;

  /// Raw WGS-84 longitude input (`-180..180`, supporting `.` or `,`).
  final String rawLongitude;

  /// Raw geofence radius input (`0.01m..100km`, supporting `m`/`km` and `.`/`,`).
  final String rawRadius;

  /// Raw address or Plus Code source text (ignored when [sourceType] is GPS).
  final String rawSource;

  /// Selected coordinate resolution source mode.
  final ShellLocationSourceType sourceType;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationDraftInput &&
        other.name == name &&
        other.sourceType == sourceType &&
        other.rawSource == rawSource &&
        other.rawLatitude == rawLatitude &&
        other.rawLongitude == rawLongitude &&
        other.rawRadius == rawRadius &&
        other.note == note;
  }

  @override
  int get hashCode => Object.hash(
    name,
    sourceType,
    rawSource,
    rawLatitude,
    rawLongitude,
    rawRadius,
    note,
  );
}

/// Validates and appends referenced location IDs from [selectedLocationIds] into [rules].
String? _appendValidatedLocationIds(
  List<String> selectedLocationIds,
  TaskBoard board,
  List<TaskCondition> rules,
  AppLocalizations localizations,
) {
  if (selectedLocationIds.length > maxTdfLocationRefsPerEntity) {
    return localizations.conditionLocationErrorInvalid;
  }
  final deduplicatedIds = <String>[];
  final seenIds = <String>{};
  for (final locationId in selectedLocationIds) {
    if (board.findLocation(locationId) == null) {
      return localizations.conditionLocationErrorInvalid;
    }
    if (seenIds.add(locationId)) {
      deduplicatedIds.add(locationId);
    }
  }
  rules.add(LocationTaskCondition.fromIds(deduplicatedIds));
  return null;
}

/// Validates and appends daily [timeWindows] into [rules], enforcing [maxTdfConditionRulesPerEntity].
String? _appendValidatedTimeWindows(
  List<TimeWindowDraftViewModel> timeWindows,
  List<TaskCondition> rules,
  AppLocalizations localizations,
) {
  for (final window in timeWindows) {
    if (_containsAsciiControlChar(window.start) ||
        _containsAsciiControlChar(window.end)) {
      return localizations.conditionTimeErrorInvalid;
    }
    final parsed = TimeWindowTaskCondition.tryParse(window.start, window.end);
    if (parsed == null) {
      return localizations.conditionTimeErrorInvalid;
    }
    rules.add(parsed);
    if (rules.length > maxTdfConditionRulesPerEntity) {
      return localizations.errorLocalFileTooLarge;
    }
  }
  return null;
}

/// Collects all live and tombstoned entity identifiers currently referenced on [board].
Set<String> _collectAllUsedEntityIds(TaskBoard board) => <String>{
  for (final task in board.allTasks) task.id,
  for (final task in board.allTasks) ...task.blockedByTaskIds,
  for (final task in board.allTasks) ...task.labelIds,
  for (final label in board.labels) label.id,
  for (final location in board.locations) location.id,
  for (final record in board.deletedBlock.tasks) record.taskId,
  for (final record in board.deletedBlock.labels) record.labelId,
  for (final record in board.deletedBlock.locations) record.locationId,
};

/// Returns `true` when [value] contains any ASCII control character (`0x00..0x1F` or `0x7F`).
bool _containsAsciiControlChar(String value) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit <= 0x1F || unit == 0x7F) {
      return true;
    }
  }
  return false;
}

/// Maps model-free [ShellLocationSourceType] to domain [LocationSourceType].
LocationSourceType _mapLocationSourceType(ShellLocationSourceType sourceType) {
  return switch (sourceType) {
    ShellLocationSourceType.gps => LocationSourceType.gps,
    ShellLocationSourceType.address => LocationSourceType.address,
    ShellLocationSourceType.plusCode => LocationSourceType.plusCode,
  };
}

/// Maps domain [LocationSourceType] to model-free [ShellLocationSourceType].
ShellLocationSourceType _mapShellLocationSourceType(
  LocationSourceType sourceType,
) {
  return switch (sourceType) {
    LocationSourceType.gps => ShellLocationSourceType.gps,
    LocationSourceType.address => ShellLocationSourceType.address,
    LocationSourceType.plusCode => ShellLocationSourceType.plusCode,
  };
}

/// Maps a [TdfErrorKind] raised during persistence to a sanitized localized error string.
String _mapTdfPersistError(TdfErrorKind kind, AppLocalizations localizations) {
  return switch (kind) {
    TdfErrorKind.invalidColor => localizations.labelColorErrorInvalid,
    TdfErrorKind.invalidUri => localizations.linkErrorInvalid,
    TdfErrorKind.invalidCondition || TdfErrorKind.unknownLocationReference =>
      localizations.conditionLocationErrorInvalid,
    TdfErrorKind.limitExceeded => localizations.errorLocalFileTooLarge,
    TdfErrorKind.unexpectedToken => localizations.schedulingNoteErrorInvalid,
    _ => localizations.errorSaveLocalFileFailed(
      localizations.fileReadStatusUnreadable,
    ),
  };
}

/// Parses and validates WGS-84 [rawLatitude] and [rawLongitude] rounded to 6 decimal places.
({double? latitude, double? longitude, String? error}) _parseCoordinates({
  required String rawLatitude,
  required String rawLongitude,
  required LocationEditorController locationController,
  required String errorMessage,
}) {
  final parsedLatitude = _tryParseDecimalString(
    rawLatitude,
    allowNegative: true,
  );
  final parsedLongitude = _tryParseDecimalString(
    rawLongitude,
    allowNegative: true,
  );
  if (parsedLatitude == null ||
      parsedLongitude == null ||
      !locationController.isValidCoordinates(parsedLatitude, parsedLongitude)) {
    return (latitude: null, longitude: null, error: errorMessage);
  }
  final roundedLatitude = double.tryParse(
    TdfLocation.formatRoundedDouble(parsedLatitude, 6),
  );
  final roundedLongitude = double.tryParse(
    TdfLocation.formatRoundedDouble(parsedLongitude, 6),
  );
  if (roundedLatitude == null ||
      roundedLongitude == null ||
      !locationController.isValidCoordinates(
        roundedLatitude,
        roundedLongitude,
      )) {
    return (latitude: null, longitude: null, error: errorMessage);
  }
  return (latitude: roundedLatitude, longitude: roundedLongitude, error: null);
}

/// Parses a geofence radius string (`0.01m..100km`, supporting `m`/`km` and `.`/`,`) into meters rounded to 2 decimals.
double? _parseRadiusMeters(String rawRadius) {
  if (_containsAsciiControlChar(rawRadius)) {
    return null;
  }
  final trimmed = rawRadius.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final lower = trimmed.toLowerCase();
  var numericPart = trimmed;
  var multiplier = 1.0;
  if (lower.endsWith('km')) {
    numericPart = trimmed.substring(0, trimmed.length - 2).trim();
    multiplier = 1000.0;
  } else if (lower.endsWith('m')) {
    numericPart = trimmed.substring(0, trimmed.length - 1).trim();
  }
  final numeric = _tryParseDecimalString(numericPart, allowNegative: false);
  if (numeric == null) {
    return null;
  }
  final meters = numeric * multiplier;
  if (!meters.isFinite ||
      meters < _minLocationRadiusMeters ||
      meters > maxTdfLocationRadius) {
    return null;
  }
  final roundedMeters = double.tryParse(
    TdfLocation.formatRoundedDouble(meters, 2),
  );
  if (roundedMeters == null ||
      roundedMeters < _minLocationRadiusMeters ||
      roundedMeters > maxTdfLocationRadius) {
    return null;
  }
  return roundedMeters;
}

/// Parses a strict finite decimal string accepting `.` or `,` without exponents, or returns `null`.
double? _tryParseDecimalString(String raw, {required bool allowNegative}) {
  if (raw.isEmpty || _containsAsciiControlChar(raw)) {
    return null;
  }
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.length > maxTdfNumberLength) {
    return null;
  }
  var index = 0;
  if (trimmed.codeUnitAt(0) == 0x2D) {
    if (!allowNegative || trimmed.length == 1) {
      return null;
    }
    index = 1;
  }
  var hasIntegerDigits = false;
  var decimalSeparatorIndex = -1;
  var hasFractionalDigits = false;
  for (; index < trimmed.length; index++) {
    final unit = trimmed.codeUnitAt(index);
    final isDigit = unit >= 0x30 && unit <= 0x39;
    if (isDigit) {
      if (decimalSeparatorIndex < 0) {
        hasIntegerDigits = true;
      } else {
        hasFractionalDigits = true;
      }
      continue;
    }
    final isSeparator = unit == 0x2E || unit == 0x2C;
    if (isSeparator && decimalSeparatorIndex < 0 && hasIntegerDigits) {
      decimalSeparatorIndex = index;
      continue;
    }
    return null;
  }
  if (!hasIntegerDigits ||
      (decimalSeparatorIndex >= 0 && !hasFractionalDigits)) {
    return null;
  }
  final normalized =
      decimalSeparatorIndex >= 0 &&
          trimmed.codeUnitAt(decimalSeparatorIndex) == 0x2C
      ? '${trimmed.substring(0, decimalSeparatorIndex)}.${trimmed.substring(decimalSeparatorIndex + 1)}'
      : trimmed;
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed.isNaN || parsed.isInfinite) {
    return null;
  }
  return parsed == 0.0 ? 0.0 : parsed;
}

/// Validates and compiles a label [ConditionDraftViewModel] into canonical TDF [TaskCondition] rules.
({List<TaskCondition>? conditions, String? error}) _validateLabelConditions(
  ConditionDraftViewModel draft,
  TaskBoard board,
  AppLocalizations localizations,
) {
  final rules = <TaskCondition>[];
  if (draft.daysMode != ConditionDimensionMode.any &&
      draft.selectedWeekdays.isNotEmpty) {
    for (final weekday in draft.selectedWeekdays) {
      if (weekday < DateTime.monday || weekday > DateTime.sunday) {
        return (
          conditions: null,
          error: localizations.conditionTimeErrorInvalid,
        );
      }
    }
    rules.add(DayTaskCondition.fromWeekdays(draft.selectedWeekdays));
  }

  if (draft.timesMode != ConditionDimensionMode.any &&
      draft.timeWindows.isNotEmpty) {
    final timeError = _appendValidatedTimeWindows(
      draft.timeWindows,
      rules,
      localizations,
    );
    if (timeError != null) {
      return (conditions: null, error: timeError);
    }
  }

  if (draft.locationsMode != ConditionDimensionMode.any &&
      draft.selectedLocationIds.isNotEmpty) {
    final locationError = _appendValidatedLocationIds(
      draft.selectedLocationIds,
      board,
      rules,
      localizations,
    );
    if (locationError != null) {
      return (conditions: null, error: locationError);
    }
  }

  if (rules.length > maxTdfConditionRulesPerEntity) {
    return (conditions: null, error: localizations.errorLocalFileTooLarge);
  }
  return (conditions: List<TaskCondition>.unmodifiable(rules), error: null);
}

/// Validates and converts [links] into canonical [TaskLink] entries respecting [maxTdfLinksPerLabel].
({List<TaskLink>? links, String? error}) _validateLabelLinks(
  Iterable<EntityLinkViewModel> links,
  AppLocalizations localizations,
) {
  final validated = <TaskLink>[];
  for (final link in links) {
    if (validated.length >= maxTdfLinksPerLabel) {
      return (links: null, error: localizations.labelLinkErrorMaxExceeded);
    }
    final parsed = TaskLink.tryParse(rawTitle: link.title, rawUri: link.uri);
    if (parsed == null) {
      return (links: null, error: localizations.linkErrorInvalid);
    }
    validated.add(parsed);
  }
  return (
    links: validated.isEmpty
        ? const <TaskLink>[]
        : List<TaskLink>.unmodifiable(validated),
    error: null,
  );
}

/// Validates a label name against single-line `<text>` bounds and case-insensitive uniqueness on [board].
({String? value, String? error, bool isDuplicate}) _validateLabelName({
  required String rawName,
  required TaskBoard board,
  required String? excludingLabelId,
  required AppLocalizations localizations,
}) {
  final validatedText = _validateRequiredSingleLineText(
    rawName,
    localizations.labelNameErrorEmpty,
  );
  if (validatedText.error case final textError?) {
    return (value: null, error: textError, isDuplicate: false);
  }
  final trimmedName = validatedText.value;
  if (trimmedName == null) {
    return (
      value: null,
      error: localizations.labelNameErrorEmpty,
      isDuplicate: false,
    );
  }
  if (board.hasDuplicateLabelName(
    trimmedName,
    excludingLabelId: excludingLabelId,
  )) {
    return (
      value: null,
      error: localizations.labelNameErrorDuplicate,
      isDuplicate: true,
    );
  }
  return (value: trimmedName, error: null, isDuplicate: false);
}

/// Validates an optional location source string according to [sourceType] and single-line `<text>` bounds.
({String? normalizedSource, String? error}) _validateLocationSource({
  required ShellLocationSourceType sourceType,
  required String rawSource,
  required AppLocalizations localizations,
}) {
  if (sourceType == ShellLocationSourceType.gps) {
    return (normalizedSource: null, error: null);
  }
  if (_containsAsciiControlChar(rawSource)) {
    return (
      normalizedSource: null,
      error: localizations.locationSourceErrorEmpty,
    );
  }
  final trimmed = rawSource.trim();
  if (trimmed.isEmpty) {
    return (normalizedSource: null, error: null);
  }
  final scalarCount = TdfCalendar.countUnicodeScalars(trimmed);
  if (scalarCount == null || scalarCount > maxTdfTextLength) {
    return (
      normalizedSource: null,
      error: localizations.locationSourceErrorEmpty,
    );
  }
  return (normalizedSource: trimmed, error: null);
}

/// Validates an optional `#RRGGBB` color input string, rejecting control characters and malformed hex values.
({String? normalizedHex, String? error}) _validateOptionalColor(
  String rawColorHex,
  AppLocalizations localizations,
) {
  if (_containsAsciiControlChar(rawColorHex)) {
    return (normalizedHex: null, error: localizations.labelColorErrorInvalid);
  }
  final trimmed = rawColorHex.trim();
  if (trimmed.isEmpty) {
    return (normalizedHex: null, error: null);
  }
  final normalized = TdfColor.normalizeHex(trimmed);
  if (normalized == null) {
    return (normalizedHex: null, error: localizations.labelColorErrorInvalid);
  }
  return (normalizedHex: normalized, error: null);
}

/// Normalizes and validates an optional multi-line `<note>` string against `maxTdfNoteLength` (`2000`) and control-char rules.
({String? normalizedNote, String? error}) _validateOptionalNote(
  String rawNote,
  AppLocalizations localizations,
) {
  final normalizedNote = TaskEditorController.normalizeSchedulingNote(rawNote);
  final noteError = TaskEditorController.validateSchedulingNote(
    normalizedNote,
    localizations,
  );
  if (noteError != null) {
    return (normalizedNote: null, error: noteError);
  }
  return (normalizedNote: normalizedNote, error: null);
}

/// Validates a required single-line `<text>` field (`1..500` Unicode scalar values, zero ASCII control characters).
({String? value, String? error}) _validateRequiredSingleLineText(
  String rawText,
  String errorMessage,
) {
  if (_containsAsciiControlChar(rawText)) {
    return (value: null, error: errorMessage);
  }
  final trimmed = rawText.trim();
  if (trimmed.isEmpty) {
    return (value: null, error: errorMessage);
  }
  final scalarCount = TdfCalendar.countUnicodeScalars(trimmed);
  if (scalarCount == null || scalarCount > maxTdfTextLength) {
    return (value: null, error: errorMessage);
  }
  return (value: trimmed, error: null);
}
