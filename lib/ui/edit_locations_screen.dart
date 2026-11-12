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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../models/location_state.dart';
import '../models/task_board.dart';
import '../models/tdf_location.dart';
import '../providers/location_providers.dart';
import '../providers/task_providers.dart';
import '../services/app_logger.dart';
import '../services/plus_code_service.dart';
import 'app_theme.dart';
import 'widgets/clearable_text_field.dart';
import 'widgets/task_editor_sections.dart';

/// Dedicated panel screen for editing all properties of an existing TDF `location` block (`name`, `coordinates`, `source`, and `note`).
class EditLocationScreen extends ConsumerStatefulWidget {
  /// Creates an [EditLocationScreen].
  const EditLocationScreen({super.key, required this.location});

  /// Location block to edit.
  final TdfLocation location;

  @override
  ConsumerState<EditLocationScreen> createState() => _EditLocationScreenState();
}

/// Overview screen for creating, deleting, and opening the editor panel for locations while displaying open task counts in alphabetical order.
class EditLocationsScreen extends ConsumerStatefulWidget {
  /// Creates an [EditLocationsScreen] widget.
  const EditLocationsScreen({super.key, this.autofocusCreate = false});

  /// Whether the create-location text field should request focus automatically when opened.
  final bool autofocusCreate;

  @override
  ConsumerState<EditLocationsScreen> createState() =>
      _EditLocationsScreenState();
}

/// Text field inside [_CreateLocationRow] for entering a new location name.
class _CreateLocationInputField extends StatelessWidget {
  /// Creates a [_CreateLocationInputField].
  const _CreateLocationInputField({
    required this.autofocus,
    required this.controller,
    required this.onClear,
    required this.onSubmit,
  });

  /// Whether the text field requests focus automatically.
  final bool autofocus;

  /// Controller for the new location name input.
  final TextEditingController controller;

  /// Callback invoked when the clear button is pressed.
  final VoidCallback onClear;

  /// Callback invoked when the new location is submitted.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return ClearableTextField(
      fieldKey: const ValueKey('create_location_input'),
      controller: controller,
      autofocus: autofocus,
      cursorColor: colorScheme.primary,
      style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
      textInputAction: TextInputAction.done,
      onCleared: onClear,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        filled: false,
        hintText: localizations.createNewLocation,
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: true,
      ),
    );
  }
}

/// Top row inside [EditLocationsScreen] for creating a new location.
class _CreateLocationRow extends StatelessWidget {
  /// Creates a [_CreateLocationRow].
  const _CreateLocationRow({
    required this.autofocus,
    required this.controller,
    required this.hasText,
    required this.onClear,
    required this.onSubmit,
  });

  /// Whether the text field requests focus automatically.
  final bool autofocus;

  /// Controller for the new location name input.
  final TextEditingController controller;

  /// Whether the input field currently contains non-whitespace text.
  final bool hasText;

  /// Callback invoked when the leading clear or add icon is pressed.
  final VoidCallback onClear;

  /// Callback invoked when the new location is submitted.
  final VoidCallback onSubmit;

  /// Leading icon reflecting whether the input currently contains text.
  IconData get _leadingIcon =>
      hasText ? Icons.close_rounded : Icons.add_rounded;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('create_location_clear_button'),
            tooltip: hasText
                ? localizations.actionCancel
                : localizations.actionAdd,
            icon: Icon(_leadingIcon, color: colorScheme.onSurfaceVariant),
            onPressed: hasText ? onClear : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CreateLocationInputField(
              autofocus: autofocus,
              controller: controller,
              onClear: onClear,
              onSubmit: onSubmit,
            ),
          ),
          IconButton(
            key: const ValueKey('create_location_submit_button'),
            tooltip: localizations.actionAdd,
            icon: Icon(
              Icons.check_rounded,
              color: _submitIconColor(colorScheme),
            ),
            onPressed: hasText ? onSubmit : null,
          ),
        ],
      ),
    );
  }

  /// Returns the color for the submit check icon based on [hasText].
  Color _submitIconColor(ColorScheme colorScheme) =>
      hasText ? colorScheme.primary : colorScheme.onSurfaceVariant;
}

/// Settings-style card column inside [EditLocationScreen] for editing location details and coordinates.
class _EditLocationFormColumn extends StatelessWidget {
  /// Creates an [_EditLocationFormColumn].
  const _EditLocationFormColumn({
    required this.coordinatesErrorMessage,
    required this.isResolving,
    required this.latitudeController,
    required this.longitudeController,
    required this.nameController,
    required this.nameErrorMessage,
    required this.noteController,
    required this.onResolveSource,
    required this.onSourceTypeChanged,
    required this.onSubmit,
    required this.onUseCurrentGps,
    required this.radiusController,
    required this.sourceController,
    required this.sourceType,
  });

  /// Validation error message for coordinates, radius, or source resolution.
  final String? coordinatesErrorMessage;

  /// Whether an asynchronous source resolution request is currently in flight.
  final bool isResolving;

  /// Controller for latitude input.
  final TextEditingController latitudeController;

  /// Controller for longitude input.
  final TextEditingController longitudeController;

  /// Controller for location name input.
  final TextEditingController nameController;

  /// Validation error message for the location name field.
  final String? nameErrorMessage;

  /// Controller for location note input.
  final TextEditingController noteController;

  /// Callback invoked when the `Resolve` button is tapped.
  final VoidCallback onResolveSource;

  /// Callback invoked when the source type dropdown changes.
  final ValueChanged<LocationSourceType?> onSourceTypeChanged;

  /// Callback invoked when the location editor form is submitted.
  final VoidCallback onSubmit;

  /// Callback invoked when the `Use Current GPS Position` button is tapped.
  final VoidCallback onUseCurrentGps;

  /// Controller for radius input.
  final TextEditingController radiusController;

  /// Controller for source input.
  final TextEditingController sourceController;

  /// Currently selected [LocationSourceType].
  final LocationSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TaskEditorDetailsCard(
          sectionTitle: localizations.locationDetailsSectionTitle,
          titleLabel: localizations.locationNameLabel,
          titleController: nameController,
          noteController: noteController,
          errorMessage: nameErrorMessage,
          onSubmit: onSubmit,
        ),
        const SizedBox(height: 10),
        _LocationCoordinatesCard(
          errorMessage: coordinatesErrorMessage,
          isResolving: isResolving,
          latitudeController: latitudeController,
          longitudeController: longitudeController,
          onResolveSource: onResolveSource,
          onSourceTypeChanged: onSourceTypeChanged,
          onUseCurrentGps: onUseCurrentGps,
          radiusController: radiusController,
          sourceController: sourceController,
          sourceType: sourceType,
        ),
      ],
    );
  }
}

/// Scaffold layout for [EditLocationScreen] wrapping the scrollable form column and bottom action bar.
class _EditLocationScaffold extends StatelessWidget {
  /// Creates an [_EditLocationScaffold].
  const _EditLocationScaffold({required this.formChild, required this.onSave});

  /// Scrollable form content displayed above the action row.
  final Widget formChild;

  /// Callback invoked when the Save button is pressed.
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('edit_location_screen'),
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: Text(localizations.editLocationTitle)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: formChild,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TaskEditorActionsRow(
                onCancel: () => Navigator.of(context).pop(),
                onSave: onSave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// State for [EditLocationScreen].
class _EditLocationScreenState extends ConsumerState<EditLocationScreen> {
  String? _coordinatesErrorMessage;
  bool _isResolving = false;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  late final TextEditingController _nameController;
  String? _nameErrorMessage;
  late final TextEditingController _noteController;
  late final TextEditingController _radiusController;
  int _resolveGeneration = 0;
  String? _resolvedSourceText;
  LocationSourceType? _resolvedSourceType;
  late final TextEditingController _sourceController;
  late LocationSourceType _sourceType;

  /// Whether the current source text has already been resolved into coordinates for [_sourceType].
  bool get _isSourceResolved =>
      _sourceType == LocationSourceType.gps ||
      (_resolvedSourceType == _sourceType &&
          _resolvedSourceText == _sourceController.text.trim() &&
          (_resolvedSourceText?.isNotEmpty ?? false));

  @override
  void initState() {
    super.initState();
    final location = widget.location;
    _sourceType = PlusCodeService.classifySource(location.source);
    final initialSourceText = _sourceType == LocationSourceType.gps
        ? ''
        : (location.source?.trim() ?? '');
    if (_sourceType != LocationSourceType.gps && initialSourceText.isNotEmpty) {
      _resolvedSourceType = _sourceType;
      _resolvedSourceText = initialSourceText;
    }
    _nameController = TextEditingController(text: location.name);
    _noteController = TextEditingController(text: location.note ?? '');
    _latitudeController = TextEditingController(text: location.latitudeText);
    _longitudeController = TextEditingController(text: location.longitudeText);
    _radiusController = TextEditingController(text: location.radiusText);
    _sourceController = TextEditingController(text: initialSourceText);
    _nameController.addListener(_handleNameChanged);
    _latitudeController.addListener(_handleCoordinatesChanged);
    _longitudeController.addListener(_handleCoordinatesChanged);
    _radiusController.addListener(_handleCoordinatesChanged);
    _sourceController.addListener(_handleSourceTextChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_handleNameChanged);
    _latitudeController.removeListener(_handleCoordinatesChanged);
    _longitudeController.removeListener(_handleCoordinatesChanged);
    _radiusController.removeListener(_handleCoordinatesChanged);
    _sourceController.removeListener(_handleSourceTextChanged);
    _nameController.dispose();
    _noteController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _EditLocationScaffold(
      onSave: _submit,
      formChild: _EditLocationFormColumn(
        coordinatesErrorMessage: _coordinatesErrorMessage,
        isResolving: _isResolving,
        latitudeController: _latitudeController,
        longitudeController: _longitudeController,
        nameController: _nameController,
        nameErrorMessage: _nameErrorMessage,
        noteController: _noteController,
        onResolveSource: _resolveSource,
        onSourceTypeChanged: _handleSourceTypeChanged,
        onSubmit: _submit,
        onUseCurrentGps: _useCurrentGpsPosition,
        radiusController: _radiusController,
        sourceController: _sourceController,
        sourceType: _sourceType,
      ),
    );
  }

  /// Rounds [value] to at most 6 decimal places and formats it canonically.
  static String _formatGpsCoordinate(double value) =>
      TdfLocation.formatRoundedDouble(value, 6);

  /// Checks whether [latitude] and [longitude] are finite WGS-84 coordinates.
  static bool _isValidCoordinates(double latitude, double longitude) =>
      !latitude.isNaN &&
      !latitude.isInfinite &&
      latitude >= -90.0 &&
      latitude <= 90.0 &&
      !longitude.isNaN &&
      !longitude.isInfinite &&
      longitude >= -180.0 &&
      longitude <= 180.0;

  /// Checks whether [radius] is a valid TDF location radius in meters (`0 < radius <= 100000`).
  static bool _isValidRadius(double radius) =>
      !radius.isNaN && !radius.isInfinite && radius > 0.0 && radius <= 100000.0;

  /// Parses a radius input string (`150`, `150m`, or `0.5km`) into meters rounded to at most 2 decimal places.
  static double? _parseRadiusInput(String rawRadius) {
    final trimmed = rawRadius.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    var numericPart = trimmed;
    var multiplier = 1.0;
    if (trimmed.endsWith('km')) {
      numericPart = trimmed.substring(0, trimmed.length - 2).trim();
      multiplier = 1000.0;
    } else if (trimmed.endsWith('m')) {
      numericPart = trimmed.substring(0, trimmed.length - 1).trim();
    }
    final numeric = double.tryParse(numericPart);
    if (numeric == null || numeric.isNaN || numeric.isInfinite) {
      return null;
    }
    final meters = numeric * multiplier;
    if (meters.isNaN || meters.isInfinite) {
      return null;
    }
    final roundedMeters = double.tryParse(
      TdfLocation.formatRoundedDouble(meters, 2),
    );
    return roundedMeters != null && _isValidRadius(roundedMeters)
        ? roundedMeters
        : null;
  }

  /// Decodes a full Plus Code and applies its center coordinates and formatted source string.
  bool _applyFullPlusCode(String fullCode, String? localitySuffix) {
    final area = PlusCodeService.decode(fullCode);
    if (area == null) {
      setState(() {
        _coordinatesErrorMessage = AppLocalizations.of(context)
            .locationResolveErrorInvalidPlusCode;
      });
      return false;
    }
    final formattedSource = PlusCodeService.truncateToMaxTextLength(
      localitySuffix == null || localitySuffix.isEmpty
          ? fullCode
          : '$fullCode $localitySuffix',
    );
    _applyResolvedCoordinates(
      latitude: area.latitudeCenter,
      longitude: area.longitudeCenter,
      normalizedSource: formattedSource,
      sourceType: LocationSourceType.plusCode,
    );
    return true;
  }

  /// Recovers the full Plus Code nearest to [reference] for [shortCode] and applies its coordinates.
  bool _applyRecoveredShortPlusCode({
    required String shortCode,
    required String localityQuery,
    required GeocodingCandidate reference,
  }) {
    final fullCode = PlusCodeService.recoverNearest(
      shortCode,
      reference.latitude,
      reference.longitude,
    );
    final area = fullCode == null ? null : PlusCodeService.decode(fullCode);
    if (area == null) {
      setState(() {
        _coordinatesErrorMessage = AppLocalizations.of(context)
            .locationResolveErrorInvalidPlusCode;
      });
      return false;
    }
    final formattedSource = PlusCodeService.truncateToMaxTextLength(
      '$shortCode $localityQuery',
    );
    _applyResolvedCoordinates(
      latitude: area.latitudeCenter,
      longitude: area.longitudeCenter,
      normalizedSource: formattedSource,
      sourceType: LocationSourceType.plusCode,
    );
    return true;
  }

  /// Applies resolved [latitude], [longitude], and [normalizedSource] to the editor controllers and state.
  void _applyResolvedCoordinates({
    required double latitude,
    required double longitude,
    required String normalizedSource,
    required LocationSourceType sourceType,
  }) {
    setState(() {
      _latitudeController.text = _formatGpsCoordinate(latitude);
      _longitudeController.text = _formatGpsCoordinate(longitude);
      _sourceController.text = normalizedSource;
      _resolvedSourceType = sourceType;
      _resolvedSourceText = normalizedSource;
      _coordinatesErrorMessage = null;
    });
  }

  /// Clears any coordinate validation error when coordinate inputs change.
  void _handleCoordinatesChanged() {
    if (_coordinatesErrorMessage == null) {
      return;
    }
    setState(() {
      _coordinatesErrorMessage = null;
    });
  }

  /// Clears any name validation error when [_nameController] changes.
  void _handleNameChanged() {
    if (_nameErrorMessage == null) {
      return;
    }
    setState(() {
      _nameErrorMessage = null;
    });
  }

  /// Clears any coordinate or source validation error when [_sourceController] changes.
  void _handleSourceTextChanged() {
    if (_coordinatesErrorMessage == null) {
      return;
    }
    setState(() {
      _coordinatesErrorMessage = null;
    });
  }

  /// Updates [_sourceType], cancels any in-flight resolution, and clears the source text when switching to GPS mode.
  void _handleSourceTypeChanged(LocationSourceType? nextType) {
    if (nextType == null || nextType == _sourceType) {
      return;
    }
    setState(() {
      _resolveGeneration++;
      _isResolving = false;
      _sourceType = nextType;
      _coordinatesErrorMessage = null;
      if (nextType == LocationSourceType.gps) {
        _sourceController.clear();
      }
    });
  }

  /// Resolves an address query via forward geocoding and disambiguates multiple candidates.
  Future<bool> _resolveAddressInput(
    String trimmedSource,
    int generation,
  ) async {
    setState(() {
      _isResolving = true;
      _coordinatesErrorMessage = null;
    });
    try {
      final candidates = await ref
          .read(locationRepositoryProvider)
          .searchLocations(trimmedSource);
      if (!mounted || generation != _resolveGeneration) {
        return false;
      }
      final selected = await _selectGeocodingCandidate(candidates, generation);
      if (selected == null || !mounted || generation != _resolveGeneration) {
        return false;
      }
      _applyResolvedCoordinates(
        latitude: selected.latitude,
        longitude: selected.longitude,
        normalizedSource: selected.displayName,
        sourceType: LocationSourceType.address,
      );
      return true;
    } finally {
      if (mounted && generation == _resolveGeneration) {
        setState(() {
          _isResolving = false;
        });
      }
    }
  }

  /// Resolves a full or short Google Plus Code into WGS-84 coordinates.
  Future<bool> _resolvePlusCodeInput(
    String trimmedSource,
    int generation,
  ) async {
    switch (PlusCodeService.parseInput(trimmedSource)) {
      case InvalidPlusCodeInput():
        setState(() {
          _coordinatesErrorMessage = AppLocalizations.of(context)
              .locationResolveErrorInvalidPlusCode;
        });
        return false;
      case FullPlusCodeInput(:final fullCode, :final localitySuffix):
        return _applyFullPlusCode(fullCode, localitySuffix);
      case ShortPlusCodeInput(:final localityQuery, :final shortCode):
        return _resolveShortPlusCode(
          shortCode: shortCode,
          localityQuery: localityQuery,
          generation: generation,
        );
    }
  }

  /// Resolves a [shortCode] by geocoding [localityQuery] and recovering the nearest full Plus Code.
  Future<bool> _resolveShortPlusCode({
    required String shortCode,
    required String localityQuery,
    required int generation,
  }) async {
    setState(() {
      _isResolving = true;
      _coordinatesErrorMessage = null;
    });
    try {
      final candidates = await ref
          .read(locationRepositoryProvider)
          .searchLocations(localityQuery);
      if (!mounted || generation != _resolveGeneration) {
        return false;
      }
      final selected = await _selectGeocodingCandidate(candidates, generation);
      if (selected == null || !mounted || generation != _resolveGeneration) {
        return false;
      }
      return _applyRecoveredShortPlusCode(
        shortCode: shortCode,
        localityQuery: localityQuery,
        reference: selected,
      );
    } finally {
      if (mounted && generation == _resolveGeneration) {
        setState(() {
          _isResolving = false;
        });
      }
    }
  }

  /// Resolves the current source input according to [_sourceType].
  Future<bool> _resolveSource() async {
    if (_sourceType == LocationSourceType.gps) {
      return true;
    }
    if (_isResolving) {
      return false;
    }
    final localizations = AppLocalizations.of(context);
    final trimmedSource = _sourceController.text.trim();
    if (trimmedSource.isEmpty ||
        trimmedSource.length > PlusCodeService.maxInputLength) {
      setState(() {
        _coordinatesErrorMessage = _sourceType == LocationSourceType.plusCode
            ? localizations.locationResolveErrorInvalidPlusCode
            : localizations.locationResolveErrorNotFound;
      });
      return false;
    }
    final generation = ++_resolveGeneration;
    return switch (_sourceType) {
      LocationSourceType.gps => Future<bool>.value(true),
      LocationSourceType.address => _resolveAddressInput(
        trimmedSource,
        generation,
      ),
      LocationSourceType.plusCode => _resolvePlusCodeInput(
        trimmedSource,
        generation,
      ),
    };
  }

  /// Returns a single [GeocodingCandidate] directly or prompts the user when multiple candidates exist.
  Future<GeocodingCandidate?> _selectGeocodingCandidate(
    List<GeocodingCandidate> candidates,
    int generation,
  ) async {
    if (candidates.isEmpty) {
      setState(() {
        _coordinatesErrorMessage = AppLocalizations.of(context)
            .locationResolveErrorNotFound;
      });
      return null;
    }
    if (candidates.length == 1) {
      return candidates.first;
    }
    final selected = await showDialog<GeocodingCandidate>(
      context: context,
      builder: (_) => _LocationCandidateDialog(candidates: candidates),
    );
    if (!mounted || generation != _resolveGeneration) {
      return null;
    }
    return selected;
  }

  /// Validates the location inputs and persists the updated [TdfLocation].
  Future<void> _submit() async {
    final trimmedName = _nameController.text.trim();
    if (trimmedName.isEmpty) {
      setState(() {
        _nameErrorMessage = AppLocalizations.of(context).locationNameErrorEmpty;
      });
      return;
    }
    if (!_isSourceResolved && (!await _resolveSource() || !mounted)) {
      return;
    }
    final validated = _validateCoordinatesAndRadius();
    if (validated == null) {
      return;
    }
    final trimmedNote = _noteController.text.trim();
    final trimmedSource = _sourceType == LocationSourceType.gps
        ? ''
        : _sourceController.text.trim();
    await ref
        .read(taskNotifierProvider.notifier)
        .updateLocation(
          widget.location.id,
          name: trimmedName,
          latitude: validated.latitude,
          longitude: validated.longitude,
          radiusMeters: validated.radiusMeters,
          source: trimmedSource.isEmpty ? null : trimmedSource,
          clearSource: trimmedSource.isEmpty,
          note: trimmedNote.isEmpty ? null : trimmedNote,
          clearNote: trimmedNote.isEmpty,
        );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Populates latitude and longitude from the current GPS fix rounded to at most 6 decimal places.
  Future<void> _useCurrentGpsPosition() async {
    var fix = ref.read(locationStateProvider).fix;
    if (fix == null || !fix.hasCoordinates) {
      await ref.read(locationStateProvider.notifier).refreshLocation();
      if (!mounted) {
        return;
      }
      fix = ref.read(locationStateProvider).fix;
    }
    final latitude = fix?.latitude;
    final longitude = fix?.longitude;
    if (latitude == null || longitude == null) {
      return;
    }
    setState(() {
      _latitudeController.text = _formatGpsCoordinate(latitude);
      _longitudeController.text = _formatGpsCoordinate(longitude);
      _coordinatesErrorMessage = null;
    });
  }

  /// Validates latitude, longitude, and radius inputs, setting [_coordinatesErrorMessage] when invalid.
  ({double latitude, double longitude, double radiusMeters})?
  _validateCoordinatesAndRadius() {
    final localizations = AppLocalizations.of(context);
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    if (latitude == null ||
        longitude == null ||
        !_isValidCoordinates(latitude, longitude)) {
      setState(() {
        _coordinatesErrorMessage =
            localizations.locationCoordinatesErrorInvalid;
      });
      return null;
    }
    final radiusMeters = _parseRadiusInput(_radiusController.text);
    if (radiusMeters == null) {
      setState(() {
        _coordinatesErrorMessage = localizations.locationRadiusErrorInvalid;
      });
      return null;
    }
    return (
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
  }
}

/// Body list inside [EditLocationsScreen] rendering either [_EmptyLocationsView] or the sorted location rows.
class _EditLocationsList extends StatelessWidget {
  /// Creates an [_EditLocationsList].
  const _EditLocationsList({
    required this.board,
    required this.onDeleteLocation,
    required this.sortedLocations,
  });

  /// Current task board snapshot used to compute open task counts.
  final TaskBoard board;

  /// Callback invoked to delete a location by ID.
  final ValueChanged<String> onDeleteLocation;

  /// Locations sorted alphabetically by name.
  final List<TdfLocation> sortedLocations;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (sortedLocations.isEmpty) {
      return _EmptyLocationsView(message: localizations.emptyLocationsHint);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sortedLocations.length,
      itemBuilder: (context, index) {
        final location = sortedLocations[index];
        return _EditableLocationRow(
          key: ValueKey('edit_location_row_${location.id}'),
          location: location,
          openTaskCount: board.openTaskCountForLocation(location.id),
          onDelete: () => onDeleteLocation(location.id),
          onEdit: () => openEditLocationScreen(context, location: location),
        );
      },
    );
  }
}

/// State for [EditLocationsScreen].
class _EditLocationsScreenState extends ConsumerState<EditLocationsScreen> {
  final TextEditingController _createController = TextEditingController();
  bool _hasCreateText = false;

  @override
  void initState() {
    super.initState();
    _createController.addListener(_handleCreateInputChanged);
  }

  @override
  void dispose() {
    _createController.removeListener(_handleCreateInputChanged);
    _createController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final board =
        ref.watch(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      key: const ValueKey('edit_locations_screen'),
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: Text(localizations.editLocationsTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: theme.cardColor,
              child: _CreateLocationRow(
                autofocus: widget.autofocusCreate,
                controller: _createController,
                hasText: _hasCreateText,
                onClear: _clearCreateInput,
                onSubmit: _submitCreateLocation,
              ),
            ),
            Divider(height: 1, color: theme.scaffoldBackgroundColor),
            Expanded(
              child: _EditLocationsList(
                board: board,
                onDeleteLocation: _deleteLocation,
                sortedLocations: board.sortedLocations,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Clears the create-location input field.
  void _clearCreateInput() {
    _createController.clear();
  }

  /// Deletes the location with [locationId].
  Future<void> _deleteLocation(String locationId) async {
    await ref.read(taskNotifierProvider.notifier).deleteLocation(locationId);
  }

  /// Rebuilds when the create-location text transitions between empty and non-empty.
  void _handleCreateInputChanged() {
    final hasText = _createController.text.trim().isNotEmpty;
    if (hasText != _hasCreateText) {
      setState(() {
        _hasCreateText = hasText;
      });
    }
  }

  /// Creates a new location from [_createController] and clears the input field.
  Future<void> _submitCreateLocation() async {
    final trimmed = _createController.text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _createController.clear();
    final fix = ref.read(locationStateProvider).fix;
    final rawLatitude = fix != null && fix.hasCoordinates ? fix.latitude : null;
    final rawLongitude = fix != null && fix.hasCoordinates
        ? fix.longitude
        : null;
    final latitude = rawLatitude != null
        ? (double.tryParse(TdfLocation.formatRoundedDouble(rawLatitude, 6)) ??
              0.0)
        : 0.0;
    final longitude = rawLongitude != null
        ? (double.tryParse(TdfLocation.formatRoundedDouble(rawLongitude, 6)) ??
              0.0)
        : 0.0;
    await ref
        .read(taskNotifierProvider.notifier)
        .addLocation(
          trimmed,
          latitude: latitude,
          longitude: longitude,
          radiusMeters: 100.0,
        );
  }
}

/// Single existing location row inside [EditLocationsScreen] with quick delete button, icon, title, open task count badge, and edit button.
class _EditableLocationRow extends StatelessWidget {
  /// Creates an [_EditableLocationRow].
  const _EditableLocationRow({
    super.key,
    required this.location,
    required this.openTaskCount,
    required this.onDelete,
    required this.onEdit,
  });

  /// Location displayed by this row.
  final TdfLocation location;

  /// Callback invoked when the delete icon button is tapped.
  final VoidCallback onDelete;

  /// Callback invoked when the edit icon button is tapped.
  final VoidCallback onEdit;

  /// Number of open tasks referencing [location].
  final int openTaskCount;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mutedColor = colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                key: ValueKey('delete_location_button_${location.id}'),
                tooltip: localizations.tooltipDeleteLocation,
                icon: Icon(Icons.delete_outline_rounded, color: mutedColor),
                onPressed: onDelete,
              ),
              Icon(Icons.place_outlined, color: mutedColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(location.name, style: _titleStyle(colorScheme)),
              ),
              const SizedBox(width: 8),
              _EditableLocationTrailing(
                locationId: location.id,
                onEdit: onEdit,
                openTaskCount: openTaskCount,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Returns the text style for the location name.
  TextStyle _titleStyle(ColorScheme colorScheme) => TextStyle(
    color: colorScheme.onSurface,
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );
}

/// Open-task count badge and edit button at the trailing end of [_EditableLocationRow].
class _EditableLocationTrailing extends StatelessWidget {
  /// Creates an [_EditableLocationTrailing].
  const _EditableLocationTrailing({
    required this.locationId,
    required this.onEdit,
    required this.openTaskCount,
  });

  /// Identifier of the location row.
  final String locationId;

  /// Callback invoked when the edit button is tapped.
  final VoidCallback onEdit;

  /// Number of open tasks referencing the location.
  final int openTaskCount;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Badge.count(
          key: ValueKey('edit_location_badge_$locationId'),
          count: openTaskCount,
        ),
        const SizedBox(width: 4),
        IconButton(
          key: ValueKey('edit_location_button_$locationId'),
          tooltip: localizations.tooltipEditLocation,
          icon: Icon(Icons.edit_outlined, color: mutedColor),
          onPressed: onEdit,
        ),
      ],
    );
  }
}

/// Empty-state message shown in [EditLocationsScreen] when no locations exist.
class _EmptyLocationsView extends StatelessWidget {
  /// Creates an [_EmptyLocationsView].
  const _EmptyLocationsView({required this.message});

  /// Localized empty-state message text.
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15),
        ),
      ),
    );
  }
}

/// Action buttons row inside [_LocationCoordinatesCard] for triggering GPS lookup or source resolution.
class _LocationActionButtonsRow extends StatelessWidget {
  /// Creates a [_LocationActionButtonsRow].
  const _LocationActionButtonsRow({
    required this.isGpsMode,
    required this.isResolving,
    required this.onResolveSource,
    required this.onUseCurrentGps,
  });

  /// Whether [LocationSourceType.gps] is currently active.
  final bool isGpsMode;

  /// Whether an asynchronous source resolution request is currently in flight.
  final bool isResolving;

  /// Callback invoked when the `Resolve` button is tapped.
  final VoidCallback onResolveSource;

  /// Callback invoked when the `Use Current GPS Position` button is tapped.
  final VoidCallback onUseCurrentGps;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('location_editor_use_gps_button'),
          onPressed: isGpsMode && !isResolving ? onUseCurrentGps : null,
          icon: const Icon(Icons.gps_fixed_rounded, size: 16),
          label: Text(localizations.locationUseCurrentGpsButton),
        ),
        OutlinedButton.icon(
          key: const ValueKey('location_editor_resolve_button'),
          onPressed: !isGpsMode && !isResolving ? onResolveSource : null,
          icon: const Icon(Icons.travel_explore_rounded, size: 16),
          label: Text(localizations.locationResolveButton),
        ),
      ],
    );
  }
}

/// Modal dialog allowing the user to disambiguate between multiple [GeocodingCandidate] matches.
class _LocationCandidateDialog extends StatelessWidget {
  /// Creates a [_LocationCandidateDialog].
  const _LocationCandidateDialog({required this.candidates});

  /// Forward-geocoding candidates to display.
  final List<GeocodingCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('location_candidate_dialog'),
      title: Text(localizations.locationSelectCandidateTitle),
      content: SizedBox(
        width: 420,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: candidates.length,
          itemBuilder: (context, index) {
            final candidate = candidates[index];
            return ListTile(
              key: ValueKey('location_candidate_item_$index'),
              leading: const Icon(Icons.place_outlined),
              title: Text(candidate.displayName),
              subtitle: Text(candidate.formattedCoordinates),
              onTap: () => Navigator.of(context).pop(candidate),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.actionCancel),
        ),
      ],
    );
  }
}

/// Validation error message text displayed at the bottom of [_LocationCoordinatesCard].
class _LocationCoordinateErrorText extends StatelessWidget {
  /// Creates a [_LocationCoordinateErrorText].
  const _LocationCoordinateErrorText({required this.message});

  /// Error message to display.
  final String message;

  @override
  Widget build(BuildContext context) {
    final appTheme = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        message,
        style: TextStyle(color: appTheme.errorColor, fontSize: 12),
      ),
    );
  }
}

/// Styled clearable text field inside [_LocationCoordinatesCard] for coordinate, radius, or source input.
class _LocationCoordinateField extends StatelessWidget {
  /// Creates a [_LocationCoordinateField].
  const _LocationCoordinateField({
    required this.controller,
    this.enabled = true,
    required this.fieldKey,
    this.hintText,
    required this.labelText,
    this.onSubmitted,
    this.readOnly = false,
  });

  /// Controller for the text field.
  final TextEditingController controller;

  /// Whether the text field is enabled.
  final bool enabled;

  /// Key identifying the underlying [TextField].
  final Key fieldKey;

  /// Optional placeholder hint text.
  final String? hintText;

  /// Field label text.
  final String labelText;

  /// Optional callback invoked when the field is submitted.
  final ValueChanged<String>? onSubmitted;

  /// Whether the text field is read-only.
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final appTheme = AppTheme.of(context);
    final textColor = enabled && !readOnly
        ? appTheme.primaryTextColor
        : appTheme.mutedTextColor;
    return ClearableTextField(
      fieldKey: fieldKey,
      controller: controller,
      enabled: enabled,
      readOnly: readOnly,
      onSubmitted: onSubmitted,
      clearIconColor: appTheme.mutedTextColor,
      clearIconSize: 16,
      cursorColor: appTheme.tertiaryAccent,
      style: TextStyle(color: textColor, fontSize: 13),
      decoration: _buildDecoration(appTheme),
    );
  }

  /// Creates the [InputDecoration] for this coordinate, radius, or source input field.
  InputDecoration _buildDecoration(AppTheme appTheme) {
    final borderRadius = BorderRadius.circular(12);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: appTheme.mutedTextColor.withValues(alpha: 0.35),
      ),
    );
    final captionStyle = TextStyle(
      color: appTheme.mutedTextColor,
      fontSize: 12,
    );
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      labelStyle: captionStyle,
      hintStyle: captionStyle,
      isDense: true,
      filled: true,
      fillColor: appTheme.canvasColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: defaultBorder,
      enabledBorder: defaultBorder,
      disabledBorder: defaultBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: appTheme.tertiaryAccent, width: 1.5),
      ),
    );
  }
}

/// Card inside [EditLocationScreen] for editing latitude, longitude, radius, source type, and source resolution.
class _LocationCoordinatesCard extends StatelessWidget {
  /// Creates a [_LocationCoordinatesCard].
  const _LocationCoordinatesCard({
    required this.errorMessage,
    required this.isResolving,
    required this.latitudeController,
    required this.longitudeController,
    required this.onResolveSource,
    required this.onSourceTypeChanged,
    required this.onUseCurrentGps,
    required this.radiusController,
    required this.sourceController,
    required this.sourceType,
  });

  /// Validation error message for coordinates, radius, or source resolution, or `null` when valid.
  final String? errorMessage;

  /// Whether an asynchronous source resolution operation is currently in flight.
  final bool isResolving;

  /// Controller for latitude input.
  final TextEditingController latitudeController;

  /// Controller for longitude input.
  final TextEditingController longitudeController;

  /// Callback invoked when the `Resolve` button is tapped.
  final VoidCallback onResolveSource;

  /// Callback invoked when the source type dropdown value changes.
  final ValueChanged<LocationSourceType?> onSourceTypeChanged;

  /// Callback invoked when the `Use Current GPS Position` button is tapped.
  final VoidCallback onUseCurrentGps;

  /// Controller for radius input.
  final TextEditingController radiusController;

  /// Controller for source input.
  final TextEditingController sourceController;

  /// Currently selected [LocationSourceType].
  final LocationSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isGpsMode = sourceType == LocationSourceType.gps;
    return TaskEditorSectionCard(
      cardKey: const ValueKey('location_editor_coordinates_card'),
      icon: Icons.my_location_rounded,
      title: localizations.locationCoordinatesSectionTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LocationSourceControlsRow(
            isResolving: isResolving,
            onResolveSource: onResolveSource,
            onSourceTypeChanged: onSourceTypeChanged,
            radiusController: radiusController,
            sourceController: sourceController,
            sourceType: sourceType,
          ),
          const SizedBox(height: 8),
          _LocationLatitudeLongitudeRow(
            latitudeController: latitudeController,
            longitudeController: longitudeController,
            readOnly: !isGpsMode,
          ),
          const SizedBox(height: 8),
          _LocationActionButtonsRow(
            isGpsMode: isGpsMode,
            isResolving: isResolving,
            onResolveSource: onResolveSource,
            onUseCurrentGps: onUseCurrentGps,
          ),
          if (errorMessage case final message?)
            _LocationCoordinateErrorText(message: message),
        ],
      ),
    );
  }
}

/// Side-by-side latitude and longitude input fields inside [_LocationCoordinatesCard].
class _LocationLatitudeLongitudeRow extends StatelessWidget {
  /// Creates a [_LocationLatitudeLongitudeRow].
  const _LocationLatitudeLongitudeRow({
    required this.latitudeController,
    required this.longitudeController,
    required this.readOnly,
  });

  /// Controller for latitude input.
  final TextEditingController latitudeController;

  /// Controller for longitude input.
  final TextEditingController longitudeController;

  /// Whether the coordinate fields are read-only.
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _LocationCoordinateField(
            fieldKey: const ValueKey('location_editor_lat_input'),
            controller: latitudeController,
            labelText: localizations.locationLatitudeLabel,
            readOnly: readOnly,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _LocationCoordinateField(
            fieldKey: const ValueKey('location_editor_lon_input'),
            controller: longitudeController,
            labelText: localizations.locationLongitudeLabel,
            readOnly: readOnly,
          ),
        ),
      ],
    );
  }
}

/// Source type dropdown, radius field, and source input field inside [_LocationCoordinatesCard].
class _LocationSourceControlsRow extends StatelessWidget {
  /// Creates a [_LocationSourceControlsRow].
  const _LocationSourceControlsRow({
    required this.isResolving,
    required this.onResolveSource,
    required this.onSourceTypeChanged,
    required this.radiusController,
    required this.sourceController,
    required this.sourceType,
  });

  /// Whether an asynchronous source resolution request is currently in flight.
  final bool isResolving;

  /// Callback invoked when the user submits the source field.
  final VoidCallback onResolveSource;

  /// Callback invoked when the dropdown selection changes.
  final ValueChanged<LocationSourceType?> onSourceTypeChanged;

  /// Controller for the radius input field.
  final TextEditingController radiusController;

  /// Controller for the source input field.
  final TextEditingController sourceController;

  /// Currently selected [LocationSourceType].
  final LocationSourceType sourceType;

  /// Whether the source text field is currently interactive.
  bool get _isEditableSource =>
      sourceType != LocationSourceType.gps && !isResolving;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _LocationSourceTypeDropdown(
                isResolving: isResolving,
                onSourceTypeChanged: onSourceTypeChanged,
                sourceType: sourceType,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _LocationCoordinateField(
                fieldKey: const ValueKey('location_editor_radius_input'),
                controller: radiusController,
                labelText: localizations.locationRadiusLabel,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _LocationCoordinateField(
          fieldKey: const ValueKey('location_editor_source_input'),
          controller: sourceController,
          labelText: _sourceFieldLabel(localizations),
          hintText: _sourceFieldHint(localizations),
          enabled: _isEditableSource,
          onSubmitted: _isEditableSource ? (_) => onResolveSource() : null,
        ),
      ],
    );
  }

  /// Returns the localized hint for the source text field based on [sourceType].
  String? _sourceFieldHint(AppLocalizations localizations) {
    return switch (sourceType) {
      LocationSourceType.gps => null,
      LocationSourceType.address => localizations.locationSourceAddressHint,
      LocationSourceType.plusCode => localizations.locationSourcePlusCodeHint,
    };
  }

  /// Returns the localized label for the source text field based on [sourceType].
  String _sourceFieldLabel(AppLocalizations localizations) {
    return switch (sourceType) {
      LocationSourceType.gps => localizations.locationSourceTypeGps,
      LocationSourceType.address => localizations.locationSourceTypeAddress,
      LocationSourceType.plusCode => localizations.locationSourceTypePlusCode,
    };
  }
}

/// Dropdown field inside [_LocationSourceControlsRow] for selecting [LocationSourceType].
class _LocationSourceTypeDropdown extends StatelessWidget {
  /// Creates a [_LocationSourceTypeDropdown].
  const _LocationSourceTypeDropdown({
    required this.isResolving,
    required this.onSourceTypeChanged,
    required this.sourceType,
  });

  /// Whether an asynchronous source resolution request is currently in flight.
  final bool isResolving;

  /// Callback invoked when the dropdown selection changes.
  final ValueChanged<LocationSourceType?> onSourceTypeChanged;

  /// Currently selected [LocationSourceType].
  final LocationSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return DropdownButtonFormField<LocationSourceType>(
      key: const ValueKey('location_editor_source_type_dropdown'),
      initialValue: sourceType,
      isExpanded: true,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 13),
      dropdownColor: appTheme.cardColor,
      decoration: _buildDecoration(appTheme, localizations),
      items: [
        DropdownMenuItem(
          value: LocationSourceType.gps,
          child: Text(localizations.locationSourceTypeGps),
        ),
        DropdownMenuItem(
          value: LocationSourceType.address,
          child: Text(localizations.locationSourceTypeAddress),
        ),
        DropdownMenuItem(
          value: LocationSourceType.plusCode,
          child: Text(localizations.locationSourceTypePlusCode),
        ),
      ],
      onChanged: isResolving ? null : onSourceTypeChanged,
    );
  }

  /// Creates the [InputDecoration] for the source type dropdown field.
  InputDecoration _buildDecoration(
    AppTheme appTheme,
    AppLocalizations localizations,
  ) {
    final borderRadius = BorderRadius.circular(12);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: appTheme.mutedTextColor.withValues(alpha: 0.35),
      ),
    );
    return InputDecoration(
      labelText: localizations.locationSourceTypeLabel,
      labelStyle: TextStyle(color: appTheme.mutedTextColor, fontSize: 12),
      isDense: true,
      filled: true,
      fillColor: appTheme.canvasColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: defaultBorder,
      enabledBorder: defaultBorder,
      disabledBorder: defaultBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: appTheme.tertiaryAccent, width: 1.5),
      ),
    );
  }
}

/// Pushes [EditLocationScreen] onto the navigation stack to edit [location].
Future<void> openEditLocationScreen(
  BuildContext context, {
  required TdfLocation location,
}) {
  AppLogger.info(
    LogTag.ui,
    'Opened EditLocationScreen location=${location.id}',
  );
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => EditLocationScreen(location: location),
    ),
  );
}
