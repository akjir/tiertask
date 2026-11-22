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
import '../l10n/storage_file_read_localization_extension.dart';
import '../l10n/tier_localization_extension.dart';
import '../models/app_workspace.dart';
import '../models/location_state.dart';
import '../models/task_board.dart';
import '../models/tdf_error.dart';
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../services/app_logger.dart';
import 'config_providers.dart';
import 'floating_notice_providers.dart';
import 'location_providers.dart';
import 'location_source_resolver.dart';
import 'shell_providers.dart';
import 'sync_error_formatter.dart';
import 'sync_providers.dart';
import 'task_providers.dart';
import 'task_schedule_helper.dart';
import 'ui_telemetry.dart';
import 'workspace_providers.dart';

/// Provides the Labels and Locations mutation and geocoding action coordinator.
final entityActionsProvider =
    NotifierProvider<EntityActionsNotifier, EntityActionsState>(
      EntityActionsNotifier.new,
    );

/// Provides manual synchronization, foreground location refresh, and conflict or recovery resolution actions.
final syncActionsProvider =
    NotifierProvider<SyncActionsNotifier, SyncActionsState>(
      SyncActionsNotifier.new,
    );

/// Provides workspace creation, switching, renaming, and deletion actions.
final workspaceActionsProvider =
    NotifierProvider<WorkspaceActionsNotifier, WorkspaceActionsState>(
      WorkspaceActionsNotifier.new,
    );

/// Default geofence radius in meters assigned when quick-creating a location.
const double _defaultQuickCreateRadiusMeters = 200.0;

/// Coordinates Label and Location creation, inline saves, deletion, GPS seeding, and source resolution.
class EntityActionsNotifier extends Notifier<EntityActionsState> {
  String? _activeWorkspaceId;
  int _operationToken = 0;

  @override
  EntityActionsState build() {
    _operationToken = 0;
    _activeWorkspaceId = ref.read(activeWorkspaceProvider).asData?.value.id;
    ref.listen<String?>(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
      _handleWorkspaceIdChanged,
    );
    return const EntityActionsState();
  }

  /// Applies a user-selected [candidate] for address or short Plus Code resolution and emits `locationResolvedNotice` on success.
  LocationSourceResolutionResult applyDisambiguatedCandidate({
    required GeocodingCandidate candidate,
    required LocationSourceType sourceType,
    String? shortPlusCode,
    String? localityQuery,
    Locale? locale,
  }) {
    final result = ref
        .read(locationSourceResolverProvider)
        .applyDisambiguatedCandidate(
          candidate: candidate,
          sourceType: sourceType,
          shortPlusCode: shortPlusCode,
          localityQuery: localityQuery,
          locale: locale,
        );
    if (result is LocationSourceResolved && ref.mounted) {
      final localizations = _localizations(locale);
      ref
          .read(floatingNoticeProvider.notifier)
          .showNotice(localizations.locationResolvedNotice);
    }
    return result;
  }

  /// Clears the custom `#RRGGBB` color on label [labelId].
  Future<ActionResult> clearLabelColor(String labelId, {Locale? locale}) =>
      _saveEntitySection(
        kind: EntityKind.label,
        entityId: labelId,
        sectionName: LabelSectionKind.color.name,
        locale: locale,
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateLabel(labelId, clearColor: true),
      );

  /// Clears all inherited activation conditions on label [labelId].
  Future<ActionResult> clearLabelConditions(String labelId, {Locale? locale}) =>
      _saveEntitySection(
        kind: EntityKind.label,
        entityId: labelId,
        sectionName: LabelSectionKind.conditions.name,
        locale: locale,
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateLabel(labelId, conditions: const <TaskCondition>[]),
      );

  /// Clears the optional note on label [labelId].
  Future<ActionResult> clearLabelNote(String labelId, {Locale? locale}) =>
      _saveEntitySection(
        kind: EntityKind.label,
        entityId: labelId,
        sectionName: LabelSectionKind.note.name,
        locale: locale,
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateLabel(labelId, clearNote: true),
      );

  /// Clears the optional note on location [locationId].
  Future<ActionResult> clearLocationNote(String locationId, {Locale? locale}) =>
      _saveEntitySection(
        kind: EntityKind.location,
        entityId: locationId,
        sectionName: LocationSectionKind.note.name,
        locale: locale,
        persist: () => ref
            .read(taskNotifierProvider.notifier)
            .updateLocation(locationId, clearNote: true),
      );

  /// Validates and commits an uncommitted [LabelDraftInput], closes the draft, expands and reveals the card, and emits a notice.
  Future<ActionResult> createLabelDraft(
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

    final validatedColor = TaskScheduleHelper.validateOptionalColor(
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

    final validatedLinks = TaskScheduleHelper.validateLinksList(
      links: input.links,
      localizations: localizations,
      isLabel: true,
    );
    if (validatedLinks.error case final linksError?) {
      fieldErrors['links'] = linksError;
    }

    final validatedConditions = TaskScheduleHelper.compileConditionDraft(
      draft: input.conditions,
      board: board,
      isTask: false,
      localizations: localizations,
    );
    if (validatedConditions.error case final conditionsError?) {
      fieldErrors['conditions'] = conditionsError;
    }

    if (fieldErrors.isNotEmpty) {
      return ActionValidationFailed(
        message: fieldErrors.values.first,
        fieldErrors: fieldErrors,
      );
    }

    final newId = generateLabelId(
      timestamp: _nowUtc(),
      existingIds: TaskScheduleHelper.collectAllUsedEntityIds(board),
    );
    return _commitCreatedEntity(
      kind: EntityKind.label,
      entityId: newId,
      localizations: localizations,
      closeDraft: true,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .addLabel(
            validatedName.trimmed,
            id: newId,
            color: validatedColor.normalizedHex,
            note: validatedNote.normalizedNote,
            isScoped: input.isScoped,
            links: validatedLinks.links,
            conditions: validatedConditions.conditions,
          ),
    );
  }

  /// Validates and commits an uncommitted [LocationDraftInput], closes the draft, expands and reveals the card, and emits a notice.
  Future<ActionResult> createLocationDraft(
    LocationDraftInput input, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final board = _currentBoard();
    final fieldErrors = <String, String>{};

    if (board.locations.length >= maxTdfLocations) {
      fieldErrors['limit'] = localizations.errorLocalFileTooLarge;
    }

    final validatedName = _validateLocationName(input.name, localizations);
    if (validatedName.error case final nameError?) {
      fieldErrors['name'] = nameError;
    }

    final validatedCoordinates = _validateLocationCoordinates(
      sourceType: input.sourceType,
      rawSource: input.rawSource,
      rawLatitude: input.rawLatitude,
      rawLongitude: input.rawLongitude,
      rawRadius: input.rawRadius,
      localizations: localizations,
      fieldErrors: fieldErrors,
    );

    final validatedNote = _validateOptionalNote(input.note, localizations);
    if (validatedNote.error case final noteError?) {
      fieldErrors['note'] = noteError;
    }

    if (fieldErrors.isNotEmpty) {
      return ActionValidationFailed(
        message: fieldErrors.values.first,
        fieldErrors: fieldErrors,
      );
    }

    final latitude = validatedCoordinates.latitude;
    final longitude = validatedCoordinates.longitude;
    final radiusMeters = validatedCoordinates.radiusMeters;
    if (latitude == null || longitude == null || radiusMeters == null) {
      return ActionValidationFailed(
        message: localizations.locationCoordinatesErrorInvalid,
      );
    }

    final newId = generateLocationId(
      timestamp: _nowUtc(),
      existingIds: TaskScheduleHelper.collectAllUsedEntityIds(board),
    );
    return _commitCreatedEntity(
      kind: EntityKind.location,
      entityId: newId,
      localizations: localizations,
      closeDraft: true,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .addLocation(
            validatedName.trimmed,
            id: newId,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            source: validatedCoordinates.normalizedSource ?? '',
            note: validatedNote.normalizedNote,
          ),
    );
  }

  /// Deletes label [labelId] under local-mutation suppression, collapses the card, and emits `labelDeletedNotice` without Undo.
  Future<ActionResult> deleteLabel(String labelId, {Locale? locale}) =>
      _deleteEntity(
        kind: EntityKind.label,
        entityId: labelId,
        locale: locale,
        persist: () =>
            ref.read(taskNotifierProvider.notifier).deleteLabel(labelId),
      );

  /// Deletes location [locationId] under local-mutation suppression, collapses the card, and emits `locationDeletedNotice` without Undo.
  Future<ActionResult> deleteLocation(String locationId, {Locale? locale}) =>
      _deleteEntity(
        kind: EntityKind.location,
        entityId: locationId,
        locale: locale,
        persist: () =>
            ref.read(taskNotifierProvider.notifier).deleteLocation(locationId),
      );

  /// Quick-creates a label named [rawName] with the next rotating preset color, expands and reveals it, and emits `labelSavedNotice`.
  Future<ActionResult> quickCreateLabel(
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
            .read(floatingNoticeProvider.notifier)
            .showNotice(nameError, tone: FloatingNoticeTone.danger);
      }
      return ActionValidationFailed(
        message: nameError,
        fieldErrors: <String, String>{'name': nameError},
      );
    }

    final colorHex =
        canonicalLabelPresetHexColors[board.labels.length %
            canonicalLabelPresetHexColors.length];
    final newId = generateLabelId(
      timestamp: _nowUtc(),
      existingIds: TaskScheduleHelper.collectAllUsedEntityIds(board),
    );
    return _commitCreatedEntity(
      kind: EntityKind.label,
      entityId: newId,
      localizations: localizations,
      closeDraft: false,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .addLabel(validatedName.trimmed, id: newId, color: colorHex),
    );
  }

  /// Quick-creates a location named [rawName] seeded from the active GPS fix (or `0.0, 0.0`) with `200m` radius, expands and reveals it, and emits `locationSavedNotice`.
  Future<ActionResult> quickCreateLocation(
    String rawName, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final board = _currentBoard();
    final validatedName = _validateLocationName(rawName, localizations);
    if (validatedName.error case final nameError?) {
      return ActionValidationFailed(
        message: nameError,
        fieldErrors: <String, String>{'name': nameError},
      );
    }

    if (board.locations.length >= maxTdfLocations) {
      final limitMessage = localizations.errorLocalFileTooLarge;
      ref
          .read(floatingNoticeProvider.notifier)
          .showNotice(limitMessage, tone: FloatingNoticeTone.danger);
      return ActionValidationFailed(
        message: limitMessage,
        fieldErrors: <String, String>{'limit': limitMessage},
      );
    }

    final seededCoordinates = _seedCoordinatesFromForegroundFix();
    final newId = generateLocationId(
      timestamp: _nowUtc(),
      existingIds: TaskScheduleHelper.collectAllUsedEntityIds(board),
    );
    return _commitCreatedEntity(
      kind: EntityKind.location,
      entityId: newId,
      localizations: localizations,
      closeDraft: false,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .addLocation(
            validatedName.trimmed,
            id: newId,
            latitude: seededCoordinates.latitude,
            longitude: seededCoordinates.longitude,
            radiusMeters: _defaultQuickCreateRadiusMeters,
            source: '',
          ),
    );
  }

  /// Resolves the active foreground GPS fix formatted to 6 decimal places, emitting `gpsAppliedNotice` when found.
  Future<({String latitudeText, String longitudeText})?>
  resolveCurrentGpsPosition({Locale? locale}) async {
    if (state.isResolvingLocation) {
      return null;
    }
    final localizations = _localizations(locale);
    final locationResolver = ref.read(locationSourceResolverProvider);
    final token = _operationToken;
    state = state.copyWith(isResolvingLocation: true);
    try {
      final coordinates = await locationResolver.resolveCurrentGpsPosition();
      if (!_isOperationActive(token) || coordinates == null) {
        return null;
      }
      final formattedLatitude = locationResolver.formatGpsCoordinate(
        coordinates.latitude,
      );
      final formattedLongitude = locationResolver.formatGpsCoordinate(
        coordinates.longitude,
      );
      ref
          .read(floatingNoticeProvider.notifier)
          .showNotice(localizations.gpsAppliedNotice);
      return (
        latitudeText: formattedLatitude,
        longitudeText: formattedLongitude,
      );
    } finally {
      if (_isOperationActive(token)) {
        state = state.copyWith(isResolvingLocation: false);
      }
    }
  }

  /// Resolves an address or Plus Code [rawSource] under [sourceType], returning [LocationSourceResolutionResult] directly.
  Future<LocationSourceResolutionResult> resolveLocationSource({
    required LocationSourceType sourceType,
    required String rawSource,
    Locale? locale,
  }) async {
    if (sourceType == LocationSourceType.gps) {
      return const LocationSourceNotNeeded();
    }
    final localizations = _localizations(locale);
    final sourceValidation = TaskScheduleHelper.validateLocationSource(
      sourceType: sourceType,
      rawSource: rawSource,
      localizations: localizations,
    );
    if (sourceValidation.error != null) {
      return LocationSourceResolutionError(
        sourceType == LocationSourceType.plusCode
            ? localizations.locationResolveErrorInvalidPlusCode
            : localizations.locationResolveErrorNotFound,
      );
    }
    if (state.isResolvingLocation) {
      return LocationSourceResolutionError(
        localizations.locationResolveErrorNotFound,
      );
    }

    final locationResolver = ref.read(locationSourceResolverProvider);
    final token = _operationToken;
    state = state.copyWith(isResolvingLocation: true);
    try {
      final result = await locationResolver.resolveSource(
        sourceType: sourceType,
        rawSource: rawSource,
        locale: locale,
      );
      if (!_isOperationActive(token)) {
        return LocationSourceResolutionError(
          localizations.locationResolveErrorNotFound,
        );
      }
      if (result is LocationSourceResolved) {
        ref
            .read(floatingNoticeProvider.notifier)
            .showNotice(localizations.locationResolvedNotice);
      }
      return result;
    } on Exception {
      if (AppLogger.shouldLog(LogLevel.warn)) {
        AppLogger.event(
          LogLevel.warn,
          LogTag.ui,
          'ui.location_source.resolve_failed',
          fields: <String, Object?>{'source_type': sourceType.name},
        );
      }
      return LocationSourceResolutionError(
        localizations.locationResolveErrorNotFound,
      );
    } finally {
      if (_isOperationActive(token)) {
        state = state.copyWith(isResolvingLocation: false);
      }
    }
  }

  /// Validates and saves [rawColorHex] onto label [labelId] (clearing color when blank).
  Future<ActionResult> saveLabelColor(
    String labelId,
    String rawColorHex, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final validatedColor = TaskScheduleHelper.validateOptionalColor(
      rawColorHex,
      localizations,
    );
    if (validatedColor.error case final colorError?) {
      return ActionValidationFailed(
        message: colorError,
        fieldErrors: <String, String>{'color': colorError},
      );
    }
    final normalizedHex = validatedColor.normalizedHex;
    return _saveEntitySection(
      kind: EntityKind.label,
      entityId: labelId,
      sectionName: LabelSectionKind.color.name,
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
  Future<ActionResult> saveLabelConditions(
    String labelId,
    ConditionDraft draft, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final validated = TaskScheduleHelper.compileConditionDraft(
      draft: draft,
      board: _currentBoard(),
      isTask: false,
      localizations: localizations,
    );
    if (validated.error case final conditionsError?) {
      return ActionValidationFailed(
        message: conditionsError,
        fieldErrors: <String, String>{'conditions': conditionsError},
      );
    }
    return _saveEntitySection(
      kind: EntityKind.label,
      entityId: labelId,
      sectionName: LabelSectionKind.conditions.name,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLabel(labelId, conditions: validated.conditions),
    );
  }

  /// Validates and saves reference [links] (`<= 20`) onto label [labelId].
  Future<ActionResult> saveLabelLinks(
    String labelId,
    List<TaskLink> links, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final validated = TaskScheduleHelper.validateLinksList(
      links: links,
      localizations: localizations,
      isLabel: true,
    );
    if (validated.error case final linksError?) {
      return ActionValidationFailed(
        message: linksError,
        fieldErrors: <String, String>{'links': linksError},
      );
    }
    return _saveEntitySection(
      kind: EntityKind.label,
      entityId: labelId,
      sectionName: LabelSectionKind.links.name,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLabel(labelId, links: validated.links),
    );
  }

  /// Validates and saves an updated name [rawName] onto label [labelId].
  Future<ActionResult> saveLabelName(
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
      return ActionValidationFailed(
        message: nameError,
        fieldErrors: <String, String>{'name': nameError},
      );
    }
    return _saveEntitySection(
      kind: EntityKind.label,
      entityId: labelId,
      sectionName: LabelSectionKind.title.name,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLabel(labelId, name: validatedName.trimmed),
    );
  }

  /// Validates and saves [rawNote] (`<= 2000` scalars) onto label [labelId], clearing when blank.
  Future<ActionResult> saveLabelNote(
    String labelId,
    String rawNote, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final validated = _validateOptionalNote(rawNote, localizations);
    if (validated.error case final noteError?) {
      return ActionValidationFailed(
        message: noteError,
        fieldErrors: <String, String>{'note': noteError},
      );
    }
    final normalizedNote = validated.normalizedNote;
    return _saveEntitySection(
      kind: EntityKind.label,
      entityId: labelId,
      sectionName: LabelSectionKind.note.name,
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
  Future<ActionResult> saveLocationCoordinates(
    String locationId, {
    required LocationSourceType sourceType,
    required String rawSource,
    required String rawLatitude,
    required String rawLongitude,
    required String rawRadius,
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final fieldErrors = <String, String>{};
    final validatedCoordinates = _validateLocationCoordinates(
      sourceType: sourceType,
      rawSource: rawSource,
      rawLatitude: rawLatitude,
      rawLongitude: rawLongitude,
      rawRadius: rawRadius,
      localizations: localizations,
      fieldErrors: fieldErrors,
    );
    if (fieldErrors.isNotEmpty) {
      return ActionValidationFailed(
        message: fieldErrors.values.first,
        fieldErrors: fieldErrors,
      );
    }
    final latitude = validatedCoordinates.latitude;
    final longitude = validatedCoordinates.longitude;
    final radiusMeters = validatedCoordinates.radiusMeters;
    if (latitude == null || longitude == null || radiusMeters == null) {
      return ActionValidationFailed(
        message: localizations.locationCoordinatesErrorInvalid,
      );
    }
    final normalizedSource = validatedCoordinates.normalizedSource;
    return _saveEntitySection(
      kind: EntityKind.location,
      entityId: locationId,
      sectionName: LocationSectionKind.coordinates.name,
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
  Future<ActionResult> saveLocationName(
    String locationId,
    String rawName, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final validatedName = _validateLocationName(rawName, localizations);
    if (validatedName.error case final nameError?) {
      return ActionValidationFailed(
        message: nameError,
        fieldErrors: <String, String>{'name': nameError},
      );
    }
    return _saveEntitySection(
      kind: EntityKind.location,
      entityId: locationId,
      sectionName: LocationSectionKind.title.name,
      locale: locale,
      persist: () => ref
          .read(taskNotifierProvider.notifier)
          .updateLocation(locationId, name: validatedName.trimmed),
    );
  }

  /// Validates and saves [rawNote] (`<= 2000` scalars) onto location [locationId], clearing when blank.
  Future<ActionResult> saveLocationNote(
    String locationId,
    String rawNote, {
    Locale? locale,
  }) async {
    final localizations = _localizations(locale);
    final validated = _validateOptionalNote(rawNote, localizations);
    if (validated.error case final noteError?) {
      return ActionValidationFailed(
        message: noteError,
        fieldErrors: <String, String>{'note': noteError},
      );
    }
    final normalizedNote = validated.normalizedNote;
    return _saveEntitySection(
      kind: EntityKind.location,
      entityId: locationId,
      sectionName: LocationSectionKind.note.name,
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
  Future<ActionResult> setLabelScoped(
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
      action: (token) async {
        final committed = await ref
            .read(taskNotifierProvider.notifier)
            .updateLabel(labelId, isScoped: isScoped);
        if (!_isOperationActive(token)) {
          return ActionSucceeded(
            entityId: labelId,
            noticeMessage: localizations.labelSavedNotice,
          );
        }
        if (!committed) {
          return _buildUncommittedError(localizations: localizations);
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
            .read(floatingNoticeProvider.notifier)
            .showNotice(localizations.labelSavedNotice);
        return ActionSucceeded(
          entityId: labelId,
          noticeMessage: localizations.labelSavedNotice,
        );
      },
    );
  }

  /// Builds a sanitized [ActionPersistFailed] outcome and logs telemetry after a rolled-back [TaskNotifier] mutation.
  ActionPersistFailed _buildUncommittedError({
    required AppLocalizations localizations,
    String? inlineEntityKind,
    String? inlineEntityId,
    String? inlineSection,
  }) {
    final syncState = ref.read(syncStateProvider);
    _logPersistenceFailure(
      inlineEntityKind: inlineEntityKind,
      inlineEntityId: inlineEntityId,
      inlineSection: inlineSection,
      errorKind: syncState.hasOpenConflict ? 'conflict' : 'error',
    );
    final message = syncState.errorMessage;
    return ActionPersistFailed(
      message: message != null && message.trim().isNotEmpty
          ? AppLogger.sanitize(message)
          : localizations.syncStatusError,
    );
  }

  /// Persists a newly validated label or location identified by [entityId], optionally closing the active draft, expanding the card, and showing its saved notice.
  Future<ActionResult> _commitCreatedEntity({
    required EntityKind kind,
    required String entityId,
    required AppLocalizations localizations,
    required bool closeDraft,
    required Future<bool> Function() persist,
  }) {
    final noticeMessage = _savedNoticeForKind(kind, localizations);
    return _runBusyMutation(
      localizations: localizations,
      action: (token) async {
        final committed = await persist();
        if (!_isOperationActive(token)) {
          return ActionSucceeded(
            entityId: entityId,
            noticeMessage: noticeMessage,
          );
        }
        if (!committed) {
          return _buildUncommittedError(localizations: localizations);
        }
        final shellNotifier = ref.read(shellProvider.notifier);
        if (closeDraft) {
          shellNotifier.cancelDraft();
          UiTelemetry.logEntityDraftCommitted(kind.name);
        }
        shellNotifier.expandEntity(EntityRef(kind: kind, id: entityId));
        ref.read(floatingNoticeProvider.notifier).showNotice(noticeMessage);
        return ActionSucceeded(
          entityId: entityId,
          noticeMessage: noticeMessage,
        );
      },
    );
  }

  /// Returns the currently loaded [TaskBoard] or an empty board before initialization completes.
  TaskBoard _currentBoard() =>
      ref.read(taskNotifierProvider).asData?.value ?? TaskBoard.empty();

  /// Deletes a label or location under local-mutation suppression, collapses the card, and emits its deletion notice.
  Future<ActionResult> _deleteEntity({
    required EntityKind kind,
    required String entityId,
    required Locale? locale,
    required Future<bool> Function() persist,
  }) {
    final localizations = _localizations(locale);
    final noticeMessage = kind == EntityKind.label
        ? localizations.labelDeletedNotice
        : localizations.locationDeletedNotice;
    final target = EntityRef(kind: kind, id: entityId);
    return _runBusyMutation(
      localizations: localizations,
      action: (token) async {
        final committed = await ref
            .read(shellProvider.notifier)
            .runLocalEntityMutation(target, persist);
        if (!_isOperationActive(token)) {
          return ActionSucceeded(
            entityId: entityId,
            noticeMessage: noticeMessage,
          );
        }
        if (!committed) {
          return _buildUncommittedError(localizations: localizations);
        }
        ref.read(shellProvider.notifier).collapseEntity();
        ref.read(floatingNoticeProvider.notifier).showNotice(noticeMessage);
        return ActionSucceeded(
          entityId: entityId,
          noticeMessage: noticeMessage,
        );
      },
    );
  }

  /// Returns `true` when the label or location with [entityId] exists on the active board.
  bool _entityExists(EntityKind kind, String entityId) {
    final board = _currentBoard();
    return switch (kind) {
      EntityKind.label => board.findLabel(entityId) != null,
      EntityKind.location => board.findLocation(entityId) != null,
      EntityKind.task => board.findTask(entityId) != null,
    };
  }

  /// Closes any active inline edit and returns a localized missing-entity validation error.
  ActionValidationFailed _handleMissingEntity(AppLocalizations localizations) {
    ref.read(shellProvider.notifier).closeInlineEdit();
    return ActionValidationFailed(
      message: localizations.entityRemovedExternallyNotice,
    );
  }

  /// Resets transient busy and geocoding flags and invalidates stale tokens on actual workspace switch while ignoring transient `AsyncLoading`.
  void _handleWorkspaceIdChanged(
    String? previousWorkspaceId,
    String? nextWorkspaceId,
  ) {
    if (nextWorkspaceId == null) {
      return;
    }
    final switchedWorkspace =
        _activeWorkspaceId != null && _activeWorkspaceId != nextWorkspaceId;
    _activeWorkspaceId = nextWorkspaceId;
    if (switchedWorkspace) {
      _operationToken++;
      state = const EntityActionsState();
    }
  }

  /// Returns `true` when this notifier is still mounted and [token] belongs to the active workspace session.
  bool _isOperationActive(int token) => ref.mounted && _operationToken == token;

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
        'ui.entity.persist_failed',
        fields: <String, Object?>{'kind': errorKind},
      );
    }
  }

  /// Returns the current UTC timestamp from [clockProvider].
  DateTime _nowUtc() => ref.read(clockProvider)().toUtc();

  /// Executes [action] under a serialized `isBusy` guard and maps persistence exceptions into sanitized [ActionPersistFailed] outcomes.
  Future<ActionResult> _runBusyMutation({
    required AppLocalizations localizations,
    required Future<ActionResult> Function(int token) action,
    String? inlineEntityKind,
    String? inlineEntityId,
    String? inlineSection,
  }) async {
    if (state.isBusy) {
      return ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final token = _operationToken;
    state = state.copyWith(isBusy: true);
    try {
      return await action(token);
    } on TdfException catch (error) {
      _logPersistenceFailure(
        inlineEntityKind: inlineEntityKind,
        inlineEntityId: inlineEntityId,
        inlineSection: inlineSection,
        errorKind: error.kind.name,
      );
      return ActionPersistFailed(
        message: SyncErrorFormatter.mapTdfExceptionMessage(
          error.kind,
          localizations,
        ),
      );
    } on Exception {
      _logPersistenceFailure(
        inlineEntityKind: inlineEntityKind,
        inlineEntityId: inlineEntityId,
        inlineSection: inlineSection,
        errorKind: 'exception',
      );
      return ActionPersistFailed(
        message: localizations.errorSaveLocalFileFailed(
          localizations.fileReadStatusUnreadable,
        ),
      );
    } finally {
      if (_isOperationActive(token)) {
        state = state.copyWith(isBusy: false);
      }
    }
  }

  /// Resolves the localized save notice message for [kind].
  String _savedNoticeForKind(EntityKind kind, AppLocalizations localizations) =>
      switch (kind) {
        EntityKind.label => localizations.labelSavedNotice,
        EntityKind.location => localizations.locationSavedNotice,
        EntityKind.task => localizations.noticeTaskSaved,
      };

  /// Persists a single inline section update on a label or location, closing the inline editor and emitting telemetry and notice.
  Future<ActionResult> _saveEntitySection({
    required EntityKind kind,
    required String entityId,
    required String sectionName,
    required Locale? locale,
    required Future<bool> Function() persist,
  }) async {
    final localizations = _localizations(locale);
    if (!_entityExists(kind, entityId)) {
      return _handleMissingEntity(localizations);
    }
    final noticeMessage = _savedNoticeForKind(kind, localizations);
    return _runBusyMutation(
      localizations: localizations,
      inlineEntityKind: kind.name,
      inlineEntityId: entityId,
      inlineSection: sectionName,
      action: (token) async {
        final committed = await persist();
        if (!_isOperationActive(token)) {
          return ActionSucceeded(
            entityId: entityId,
            noticeMessage: noticeMessage,
          );
        }
        if (!committed) {
          return _buildUncommittedError(
            localizations: localizations,
            inlineEntityKind: kind.name,
            inlineEntityId: entityId,
            inlineSection: sectionName,
          );
        }
        ref.read(shellProvider.notifier).closeInlineEdit();
        UiTelemetry.logInlineEditSaved(
          kind: kind.name,
          entityId: entityId,
          section: sectionName,
        );
        ref.read(floatingNoticeProvider.notifier).showNotice(noticeMessage);
        return ActionSucceeded(
          entityId: entityId,
          noticeMessage: noticeMessage,
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
    final locationResolver = ref.read(locationSourceResolverProvider);
    if (!locationResolver.isValidCoordinates(rawLatitude, rawLongitude)) {
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

/// Immutable operational status state of [EntityActionsNotifier].
@immutable
class EntityActionsState {
  /// Creates an [EntityActionsState].
  const EntityActionsState({
    this.isBusy = false,
    this.isResolvingLocation = false,
  });

  /// Whether an entity create, inline save, or delete mutation is currently in flight.
  final bool isBusy;

  /// Whether a GPS refresh or address/Plus Code forward-geocoding lookup is currently in flight.
  final bool isResolvingLocation;

  /// Returns a copy of this [EntityActionsState] with updated fields.
  EntityActionsState copyWith({bool? isBusy, bool? isResolvingLocation}) {
    return EntityActionsState(
      isBusy: isBusy ?? this.isBusy,
      isResolvingLocation: isResolvingLocation ?? this.isResolvingLocation,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EntityActionsState &&
        other.isBusy == isBusy &&
        other.isResolvingLocation == isResolvingLocation;
  }

  @override
  int get hashCode => Object.hash(isBusy, isResolvingLocation);
}

/// Immutable domain-typed input payload submitted from an uncommitted Label Draft Card.
@immutable
class LabelDraftInput {
  /// Creates a [LabelDraftInput].
  LabelDraftInput({
    required this.name,
    this.colorHex = '',
    this.isScoped = false,
    this.note = '',
    Iterable<TaskLink> links = const <TaskLink>[],
    ConditionDraft? conditions,
  }) : links = List<TaskLink>.unmodifiable(links),
       conditions = conditions ?? ConditionDraft();

  /// Optional `#RRGGBB` hexadecimal color text, or empty when unset.
  final String colorHex;

  /// Inherited activation conditions draft.
  final ConditionDraft conditions;

  /// Whether this label acts as a Scoped Queue (`label <id> scoped {`).
  final bool isScoped;

  /// Unmodifiable list of reference links (`0..20`).
  final List<TaskLink> links;

  /// Raw label display name (`1..500` Unicode scalar values).
  final String name;

  /// Raw optional multi-line label note (`<= 2000` Unicode scalar values).
  final String note;

  /// Returns a copy of this [LabelDraftInput] with updated fields.
  LabelDraftInput copyWith({
    String? name,
    String? colorHex,
    bool? isScoped,
    String? note,
    Iterable<TaskLink>? links,
    ConditionDraft? conditions,
  }) {
    return LabelDraftInput(
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      isScoped: isScoped ?? this.isScoped,
      note: note ?? this.note,
      links: links ?? this.links,
      conditions: conditions ?? this.conditions,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LabelDraftInput &&
        other.name == name &&
        other.colorHex == colorHex &&
        other.isScoped == isScoped &&
        other.note == note &&
        listEquals(other.links, links) &&
        other.conditions == conditions;
  }

  @override
  int get hashCode => Object.hash(
    name,
    colorHex,
    isScoped,
    note,
    Object.hashAll(links),
    conditions,
  );
}

/// Immutable domain-typed input payload submitted from an uncommitted Location Draft Card.
@immutable
class LocationDraftInput {
  /// Creates a [LocationDraftInput].
  const LocationDraftInput({
    required this.name,
    this.sourceType = LocationSourceType.gps,
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
  final LocationSourceType sourceType;

  /// Returns a copy of this [LocationDraftInput] with updated fields.
  LocationDraftInput copyWith({
    String? name,
    LocationSourceType? sourceType,
    String? rawSource,
    String? rawLatitude,
    String? rawLongitude,
    String? rawRadius,
    String? note,
  }) {
    return LocationDraftInput(
      name: name ?? this.name,
      sourceType: sourceType ?? this.sourceType,
      rawSource: rawSource ?? this.rawSource,
      rawLatitude: rawLatitude ?? this.rawLatitude,
      rawLongitude: rawLongitude ?? this.rawLongitude,
      rawRadius: rawRadius ?? this.rawRadius,
      note: note ?? this.note,
    );
  }

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

/// Coordinates manual synchronization, foreground location refresh, and conflict or recovery resolution actions.
class SyncActionsNotifier extends Notifier<SyncActionsState> {
  String? _activeWorkspaceId;
  int _operationToken = 0;

  @override
  SyncActionsState build() {
    _operationToken = 0;
    _activeWorkspaceId = ref.read(activeWorkspaceProvider).asData?.value.id;
    ref.listen<String?>(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
      _handleWorkspaceIdChanged,
    );
    return const SyncActionsState();
  }

  /// Applies `TDF-DEL-003` deletion conflict choices, returns to Tasks, and announces completion.
  Future<ActionResult> applyDeletionConflictResolutions({
    required Map<String, TdfDeletionResolution> taskDecisions,
    required Map<String, TdfDeletionResolution> labelDecisions,
    required Map<String, TdfDeletionResolution> locationDecisions,
    Locale? locale,
  }) => _applyResolutions(
    locale: locale,
    taskCount: taskDecisions.length,
    labelCount: labelDecisions.length,
    locationCount: locationDecisions.length,
    successEvent: 'sync.conflict_resolved',
    failureEvent: 'sync.conflict_resolve_failed',
    noticeBuilder: (localizations) => localizations.conflictResolvedNotice,
    resolve: () => ref
        .read(taskNotifierProvider.notifier)
        .resolveDeletionConflicts(
          taskResolutions: taskDecisions,
          labelResolutions: labelDecisions,
          locationResolutions: locationDecisions,
        ),
  );

  /// Applies `TDF-REC-002` generation recovery choices, returns to Tasks, and announces completion.
  Future<ActionResult> applyRecoveryResolutions({
    required Map<String, TdfRecoveryResolution> taskDecisions,
    required Map<String, TdfRecoveryResolution> labelDecisions,
    required Map<String, TdfRecoveryResolution> locationDecisions,
    Locale? locale,
  }) => _applyResolutions(
    locale: locale,
    taskCount: taskDecisions.length,
    labelCount: labelDecisions.length,
    locationCount: locationDecisions.length,
    successEvent: 'sync.recovery_resolved',
    failureEvent: 'sync.recovery_resolve_failed',
    noticeBuilder: (localizations) => localizations.recoveryResolvedNotice,
    resolve: () => ref
        .read(taskNotifierProvider.notifier)
        .resolveRecovery(
          taskResolutions: taskDecisions,
          labelResolutions: labelDecisions,
          locationResolutions: locationDecisions,
        ),
  );

  /// Triggers an immediate foreground location refresh via [locationStateProvider].
  Future<ActionResult> refreshLocation() async {
    final localizations = _resolveLocalizations(null);
    try {
      await ref.read(locationStateProvider.notifier).refreshLocation();
      return const ActionSucceeded();
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.ui,
        'ui.location.refresh_failed',
        error: error,
      );
      return ActionPersistFailed(
        message: SyncErrorFormatter.formatSyncError(error, localizations),
      );
    }
  }

  /// Synchronizes the active workspace or retries a failed initial board or workspace load.
  Future<ActionResult> syncNow({Locale? locale}) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final token = _operationToken;
    state = state.copyWith(isBusy: true);
    try {
      final currentWorkspaceState = ref.read(activeWorkspaceProvider);
      final currentTaskState = ref.read(taskNotifierProvider);
      if (currentWorkspaceState.hasError) {
        ref.invalidate(activeWorkspaceProvider);
        await ref.read(activeWorkspaceProvider.future);
        if (!_isOperationActive(token)) {
          return const ActionSucceeded();
        }
        if (ref.read(taskNotifierProvider).hasError &&
            !ref.read(taskNotifierProvider).hasValue) {
          ref.invalidate(taskNotifierProvider);
        }
        await ref.read(taskNotifierProvider.future);
      } else if (currentTaskState.hasError && !currentTaskState.hasValue) {
        ref.invalidate(taskNotifierProvider);
        await ref.read(taskNotifierProvider.future);
      } else {
        await ref.read(taskNotifierProvider.notifier).syncFromRemote();
      }
      if (!_isOperationActive(token)) {
        return const ActionSucceeded();
      }
      return _inspectPostSyncResult(localizations);
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.sync,
        'sync.sync_now_failed',
        error: error,
      );
      return ActionPersistFailed(
        message: SyncErrorFormatter.formatSyncError(error, localizations),
      );
    } finally {
      if (_isOperationActive(token)) {
        state = state.copyWith(isBusy: false);
      }
    }
  }

  /// Executes a guarded conflict or recovery resolution pass, logs telemetry, returns to Tasks, and announces completion.
  Future<ActionResult> _applyResolutions({
    required Locale? locale,
    required int taskCount,
    required int labelCount,
    required int locationCount,
    required String successEvent,
    required String failureEvent,
    required String Function(AppLocalizations localizations) noticeBuilder,
    required Future<TaskBoard> Function() resolve,
  }) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final token = _operationToken;
    state = state.copyWith(isBusy: true);
    try {
      await resolve();
      if (!_isOperationActive(token)) {
        return const ActionSucceeded();
      }
      AppLogger.event(
        LogLevel.info,
        LogTag.sync,
        successEvent,
        fields: <String, Object?>{
          'tasks': taskCount,
          'labels': labelCount,
          'locations': locationCount,
        },
      );
      ref.read(shellProvider.notifier).openView(ShellView.tasks);
      final noticeMessage = noticeBuilder(localizations);
      ref
          .read(floatingNoticeProvider.notifier)
          .showNotice(noticeMessage, tone: FloatingNoticeTone.success);
      return ActionSucceeded(noticeMessage: noticeMessage);
    } on Object catch (error) {
      AppLogger.event(LogLevel.warn, LogTag.sync, failureEvent, error: error);
      return ActionPersistFailed(
        message: SyncErrorFormatter.formatSyncError(
          error,
          localizations,
          isSave: true,
        ),
      );
    } finally {
      if (_isOperationActive(token)) {
        state = state.copyWith(isBusy: false);
      }
    }
  }

  /// Resets transient busy state and invalidates stale tokens when switching workspaces while ignoring transient `AsyncLoading`.
  void _handleWorkspaceIdChanged(
    String? previousWorkspaceId,
    String? nextWorkspaceId,
  ) {
    if (nextWorkspaceId == null) {
      return;
    }
    final switchedWorkspace =
        _activeWorkspaceId != null && _activeWorkspaceId != nextWorkspaceId;
    _activeWorkspaceId = nextWorkspaceId;
    if (switchedWorkspace) {
      _operationToken++;
      state = const SyncActionsState();
    }
  }

  /// Evaluates [syncStateProvider] and [taskNotifierProvider] after a non-throwing sync pass.
  ActionResult _inspectPostSyncResult(AppLocalizations localizations) {
    final latestSyncState = ref.read(syncStateProvider);
    if (latestSyncState.syncOutcome case final outcome?) {
      return ActionPersistFailed(
        message: SyncErrorFormatter.formatSyncOutcomeMessage(
          outcome,
          localizations,
        ),
      );
    }
    if (latestSyncState.fileReadReport case final fileReadReport?
        when fileReadReport.hasFailure) {
      final formatted = localizations.formatStorageFileReadMessage(
        fileReadReport,
      );
      if (formatted.isNotEmpty) {
        return ActionPersistFailed(message: formatted);
      }
    }
    final errorMessage = latestSyncState.errorMessage;
    if (errorMessage != null && errorMessage.trim().isNotEmpty) {
      return ActionPersistFailed(message: AppLogger.sanitize(errorMessage));
    }
    final latestTaskState = ref.read(taskNotifierProvider);
    if (latestTaskState.hasError) {
      final error = latestTaskState.error;
      return ActionPersistFailed(
        message: error != null
            ? SyncErrorFormatter.formatSyncError(error, localizations)
            : localizations.syncStatusError,
      );
    }
    return const ActionSucceeded();
  }

  /// Returns `true` when this notifier is still mounted and [token] belongs to the active workspace session.
  bool _isOperationActive(int token) => ref.mounted && _operationToken == token;

  /// Resolves [AppLocalizations] from an explicit [locale] override or [appLocaleProvider].
  AppLocalizations _resolveLocalizations(Locale? locale) =>
      lookupAppLocalizations(locale ?? ref.read(appLocaleProvider));
}

/// Immutable transient busy state for [SyncActionsNotifier].
@immutable
class SyncActionsState {
  /// Creates a [SyncActionsState].
  const SyncActionsState({this.isBusy = false});

  /// Whether a manual sync, conflict resolution, or recovery submission is in flight.
  final bool isBusy;

  /// Returns a copy of this [SyncActionsState] with updated fields.
  SyncActionsState copyWith({bool? isBusy}) {
    return SyncActionsState(isBusy: isBusy ?? this.isBusy);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncActionsState && other.isBusy == isBusy;
  }

  @override
  int get hashCode => isBusy.hashCode;
}

/// Coordinates workspace creation, switching, renaming, and deletion mutations.
class WorkspaceActionsNotifier extends Notifier<WorkspaceActionsState> {
  @override
  WorkspaceActionsState build() => const WorkspaceActionsState();

  /// Creates a workspace named [rawName], optionally activating it and emitting a localized switch notice.
  Future<ActionResult> createWorkspace(
    String rawName, {
    bool activate = true,
    Locale? locale,
  }) {
    return _runGuardedMutation(
      operation: 'create',
      locale: locale,
      action: (fallbackLocale) async {
        final created = await ref
            .read(activeWorkspaceProvider.notifier)
            .createWorkspace(rawName, activate: activate);
        if (!activate) {
          return ActionSucceeded(entityId: created.id);
        }
        final localizations = _resolveLocalizations(locale, fallbackLocale);
        final noticeMessage = localizations.workspaceSwitchedNotice(
          created.name,
        );
        if (ref.mounted) {
          ref.read(floatingNoticeProvider.notifier).showNotice(noticeMessage);
        }
        return ActionSucceeded(
          entityId: created.id,
          noticeMessage: noticeMessage,
        );
      },
    );
  }

  /// Deletes the workspace identified by [workspaceId] and maps domain errors to localized results.
  Future<ActionResult> deleteWorkspace(String workspaceId, {Locale? locale}) {
    return _runGuardedMutation(
      operation: 'delete',
      locale: locale,
      action: (_) async {
        final activeAfterDelete = await ref
            .read(activeWorkspaceProvider.notifier)
            .deleteWorkspace(workspaceId);
        return ActionSucceeded(entityId: activeAfterDelete.id);
      },
    );
  }

  /// Renames the workspace identified by [workspaceId] to [rawName].
  Future<ActionResult> renameWorkspace(
    String workspaceId,
    String rawName, {
    Locale? locale,
  }) {
    return _runGuardedMutation(
      operation: 'rename',
      locale: locale,
      action: (_) async {
        final renamed = await ref
            .read(activeWorkspaceProvider.notifier)
            .renameWorkspace(workspaceId, rawName);
        return ActionSucceeded(entityId: renamed.id);
      },
    );
  }

  /// Switches the active workspace to [workspaceId] and emits a localized switch toast when changed.
  Future<ActionResult> switchWorkspace(String workspaceId, {Locale? locale}) {
    return _runGuardedMutation(
      operation: 'switch',
      locale: locale,
      action: (fallbackLocale) async {
        final previousId = ref.read(activeWorkspaceProvider).asData?.value.id;
        final nextWorkspace = await ref
            .read(activeWorkspaceProvider.notifier)
            .switchWorkspace(workspaceId);
        if (previousId == nextWorkspace.id) {
          return ActionSucceeded(entityId: nextWorkspace.id);
        }
        final localizations = _resolveLocalizations(locale, fallbackLocale);
        final noticeMessage = localizations.workspaceSwitchedNotice(
          nextWorkspace.name,
        );
        if (ref.mounted) {
          ref.read(floatingNoticeProvider.notifier).showNotice(noticeMessage);
        }
        return ActionSucceeded(
          entityId: nextWorkspace.id,
          noticeMessage: noticeMessage,
        );
      },
    );
  }

  /// Resolves [AppLocalizations] from an explicit [locale], live [appLocaleProvider], or [fallbackLocale].
  AppLocalizations _resolveLocalizations(
    Locale? locale,
    Locale fallbackLocale,
  ) {
    final Locale effectiveLocale =
        locale ?? (ref.mounted ? ref.read(appLocaleProvider) : fallbackLocale);
    return lookupAppLocalizations(effectiveLocale);
  }

  /// Runs [action] under the [WorkspaceActionsState.isBusy] guard and maps thrown failures.
  Future<ActionResult> _runGuardedMutation({
    required String operation,
    required Locale? locale,
    required Future<ActionSucceeded> Function(Locale fallbackLocale) action,
  }) async {
    if (state.isBusy) {
      final Locale fallbackLocale = locale ?? ref.read(appLocaleProvider);
      final localizations = _resolveLocalizations(locale, fallbackLocale);
      return ActionValidationFailed(message: localizations.syncStatusSyncing);
    }
    final Locale fallbackLocale = locale ?? ref.read(appLocaleProvider);
    state = const WorkspaceActionsState(isBusy: true);
    try {
      return await action(fallbackLocale);
    } on WorkspaceException catch (error) {
      _logWorkspaceActionFailed(
        level: LogLevel.warn,
        operation: operation,
        kind: error.kind.name,
      );
      final localizations = _resolveLocalizations(locale, fallbackLocale);
      return _mapWorkspaceException(error, localizations);
    } on Exception {
      _logWorkspaceActionFailed(
        level: LogLevel.error,
        operation: operation,
        kind: 'unexpected',
      );
      final localizations = _resolveLocalizations(locale, fallbackLocale);
      return ActionPersistFailed(
        message: localizations.errorSettingsSaveFailed,
      );
    } finally {
      if (ref.mounted) {
        state = const WorkspaceActionsState();
      }
    }
  }
}

/// Immutable transient execution state for [WorkspaceActionsNotifier].
@immutable
class WorkspaceActionsState {
  /// Creates a [WorkspaceActionsState].
  const WorkspaceActionsState({this.isBusy = false});

  /// Whether a workspace mutation is currently executing.
  final bool isBusy;

  /// Returns a copy of this [WorkspaceActionsState] with updated fields.
  WorkspaceActionsState copyWith({bool? isBusy}) =>
      WorkspaceActionsState(isBusy: isBusy ?? this.isBusy);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorkspaceActionsState && other.isBusy == isBusy;
  }

  @override
  int get hashCode => isBusy.hashCode;
}

/// Emits a redacted diagnostic event when a workspace mutation fails.
void _logWorkspaceActionFailed({
  required LogLevel level,
  required String operation,
  required String kind,
}) {
  if (!AppLogger.shouldLog(level)) {
    return;
  }
  AppLogger.event(
    level,
    LogTag.ui,
    'ui.workspace_action_failed',
    fields: <String, Object?>{'operation': operation, 'kind': kind},
  );
}

/// Maps [error] exhaustively to [ActionValidationFailed] or [ActionPersistFailed].
ActionResult _mapWorkspaceException(
  WorkspaceException error,
  AppLocalizations localizations,
) {
  final message = localizations.localizeWorkspaceError(error);
  return switch (error.kind) {
    WorkspaceErrorKind.emptyName ||
    WorkspaceErrorKind.duplicateName ||
    WorkspaceErrorKind.duplicateFilePath ||
    WorkspaceErrorKind.invalidFilePath ||
    WorkspaceErrorKind.workspaceNotFound ||
    WorkspaceErrorKind.cannotDeleteLastWorkspace ||
    WorkspaceErrorKind.maxWorkspacesExceeded => ActionValidationFailed(
      message: message,
    ),
    WorkspaceErrorKind.corruptSettingsPayload ||
    WorkspaceErrorKind.unsupportedSettingsSchemaVersion ||
    WorkspaceErrorKind.credentialStorageUnavailable ||
    WorkspaceErrorKind.settingsPersistenceFailed => ActionPersistFailed(
      message: message,
    ),
  };
}

/// Validates a label name against single-line `<text>` bounds and case-insensitive uniqueness on [board].
({String trimmed, String? error, bool isDuplicate}) _validateLabelName({
  required String rawName,
  required TaskBoard board,
  required String? excludingLabelId,
  required AppLocalizations localizations,
}) {
  final validatedText = TaskScheduleHelper.validateSingleLineText(
    rawText: rawName,
    emptyError: localizations.labelNameErrorEmpty,
    invalidError: localizations.labelNameErrorEmpty,
    tooLongError: localizations.labelNameErrorEmpty,
  );
  if (validatedText.error case final textError?) {
    return (trimmed: '', error: textError, isDuplicate: false);
  }
  if (board.hasDuplicateLabelName(
    validatedText.trimmed,
    excludingLabelId: excludingLabelId,
  )) {
    return (
      trimmed: '',
      error: localizations.labelNameErrorDuplicate,
      isDuplicate: true,
    );
  }
  return (trimmed: validatedText.trimmed, error: null, isDuplicate: false);
}

/// Validates location coordinates, geofence radius, and source metadata, recording any failures into [fieldErrors].
({
  double? latitude,
  double? longitude,
  double? radiusMeters,
  String? normalizedSource,
})
_validateLocationCoordinates({
  required LocationSourceType sourceType,
  required String rawSource,
  required String rawLatitude,
  required String rawLongitude,
  required String rawRadius,
  required AppLocalizations localizations,
  required Map<String, String> fieldErrors,
}) {
  final validatedCoordinates = TaskScheduleHelper.parseCoordinates(
    rawLatitude: rawLatitude,
    rawLongitude: rawLongitude,
    localizations: localizations,
  );
  if (validatedCoordinates.error case final coordinatesError?) {
    fieldErrors['coordinates'] = coordinatesError;
  }
  final radiusMeters = TaskScheduleHelper.parseRadiusMeters(rawRadius);
  if (radiusMeters == null) {
    fieldErrors['radius'] = localizations.locationRadiusErrorInvalid;
  }
  final validatedSource = TaskScheduleHelper.validateLocationSource(
    sourceType: sourceType,
    rawSource: rawSource,
    localizations: localizations,
  );
  if (validatedSource.error case final sourceError?) {
    fieldErrors['source'] = sourceError;
  }
  return (
    latitude: validatedCoordinates.latitude,
    longitude: validatedCoordinates.longitude,
    radiusMeters: radiusMeters,
    normalizedSource: validatedSource.normalizedSource,
  );
}

/// Validates a location display name against single-line `<text>` bounds.
({String trimmed, String? error}) _validateLocationName(
  String rawName,
  AppLocalizations localizations,
) => TaskScheduleHelper.validateSingleLineText(
  rawText: rawName,
  emptyError: localizations.locationNameErrorEmpty,
  invalidError: localizations.locationNameErrorEmpty,
  tooLongError: localizations.locationNameErrorEmpty,
);

/// Normalizes and validates an optional multi-line `<note>` string against `maxTdfNoteLength` (`2000`) and control-char rules.
({String? normalizedNote, String? error}) _validateOptionalNote(
  String rawNote,
  AppLocalizations localizations,
) {
  final normalizedNote = TaskScheduleHelper.normalizeSchedulingNote(rawNote);
  final noteError = TaskScheduleHelper.validateSchedulingNote(
    normalizedNote,
    localizations,
  );
  if (noteError != null) {
    return (normalizedNote: null, error: noteError);
  }
  return (normalizedNote: normalizedNote, error: null);
}
