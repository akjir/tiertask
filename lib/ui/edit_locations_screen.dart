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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/task_board.dart';
import '../models/tdf_location.dart';
import '../providers/location_providers.dart';
import '../providers/task_providers.dart';
import '../services/app_logger.dart';
import 'app_theme.dart';
import 'widgets/clearable_text_field.dart';
import 'widgets/task_editor_sections.dart';

/// Dedicated panel screen for editing all properties of an existing TDF `location` block (`name`, `coordinates`, and `note`).
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
            icon: Icon(
              hasText ? Icons.close_rounded : Icons.add_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            onPressed: hasText ? onClear : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClearableTextField(
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
            ),
          ),
          IconButton(
            key: const ValueKey('create_location_submit_button'),
            tooltip: localizations.actionAdd,
            icon: Icon(
              Icons.check_rounded,
              color: hasText
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            onPressed: hasText ? onSubmit : null,
          ),
        ],
      ),
    );
  }
}

/// State for [EditLocationScreen].
class _EditLocationScreenState extends ConsumerState<EditLocationScreen> {
  String? _coordinatesErrorMessage;
  late final TextEditingController _latController;
  late final TextEditingController _lonController;
  late final TextEditingController _nameController;
  String? _nameErrorMessage;
  late final TextEditingController _noteController;
  late final TextEditingController _radiusController;
  late final TextEditingController _sourceController;

  @override
  void initState() {
    super.initState();
    final location = widget.location;
    _nameController = TextEditingController(text: location.name);
    _noteController = TextEditingController(text: location.note ?? '');
    _latController = TextEditingController(text: location.latitudeText);
    _lonController = TextEditingController(text: location.longitudeText);
    _radiusController = TextEditingController(text: location.radiusText);
    _sourceController = TextEditingController(text: location.source ?? '');
    _nameController.addListener(_handleNameChanged);
    _latController.addListener(_handleCoordinatesChanged);
    _lonController.addListener(_handleCoordinatesChanged);
    _radiusController.addListener(_handleCoordinatesChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_handleNameChanged);
    _latController.removeListener(_handleCoordinatesChanged);
    _lonController.removeListener(_handleCoordinatesChanged);
    _radiusController.removeListener(_handleCoordinatesChanged);
    _nameController.dispose();
    _noteController.dispose();
    _latController.dispose();
    _lonController.dispose();
    _radiusController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

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
                child: _buildFormColumn(localizations),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TaskEditorActionsRow(
                onCancel: () => Navigator.of(context).pop(),
                onSave: _submit,
              ),
            ),
          ],
        ),
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

  /// Parses a radius input string (`150`, `150m`, or `0.5km`) into meters.
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
    if (numeric == null) {
      return null;
    }
    final meters = numeric * multiplier;
    return _isValidRadius(meters) ? meters : null;
  }

  /// Builds the Settings-style card column inside [EditLocationScreen].
  Widget _buildFormColumn(AppLocalizations localizations) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TaskEditorDetailsCard(
          sectionTitle: localizations.locationDetailsSectionTitle,
          titleLabel: localizations.locationNameLabel,
          titleController: _nameController,
          noteController: _noteController,
          errorMessage: _nameErrorMessage,
          onSubmit: _submit,
        ),
        const SizedBox(height: 10),
        _LocationCoordinatesCard(
          latController: _latController,
          lonController: _lonController,
          radiusController: _radiusController,
          sourceController: _sourceController,
          errorMessage: _coordinatesErrorMessage,
          onUseCurrentGps: _useCurrentGpsPosition,
        ),
      ],
    );
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

  /// Validates the location inputs and persists the updated [TdfLocation].
  Future<void> _submit() async {
    final localizations = AppLocalizations.of(context);
    final trimmedName = _nameController.text.trim();
    if (trimmedName.isEmpty) {
      setState(() {
        _nameErrorMessage = localizations.locationNameErrorEmpty;
      });
      return;
    }

    final latitude = double.tryParse(_latController.text.trim());
    final longitude = double.tryParse(_lonController.text.trim());
    if (latitude == null ||
        longitude == null ||
        !_isValidCoordinates(latitude, longitude)) {
      setState(() {
        _coordinatesErrorMessage =
            localizations.locationCoordinatesErrorInvalid;
      });
      return;
    }

    final radiusMeters = _parseRadiusInput(_radiusController.text);
    if (radiusMeters == null) {
      setState(() {
        _coordinatesErrorMessage = localizations.locationRadiusErrorInvalid;
      });
      return;
    }

    final trimmedNote = _noteController.text.trim();
    final trimmedSource = _sourceController.text.trim();
    await ref
        .read(taskNotifierProvider.notifier)
        .updateLocation(
          widget.location.id,
          name: trimmedName,
          latitude: latitude,
          longitude: longitude,
          radiusMeters: radiusMeters,
          source: trimmedSource.isEmpty ? null : trimmedSource,
          clearSource: trimmedSource.isEmpty,
          note: trimmedNote.isEmpty ? null : trimmedNote,
          clearNote: trimmedNote.isEmpty,
        );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
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
    final lat = fix?.latitude;
    final lon = fix?.longitude;
    if (lat == null || lon == null) {
      return;
    }
    setState(() {
      _latController.text = _formatGpsCoordinate(lat);
      _lonController.text = _formatGpsCoordinate(lon);
      if (_sourceController.text.trim().isEmpty ||
          _sourceController.text.trim() == 'manual') {
        _sourceController.text = 'gps';
      }
      _coordinatesErrorMessage = null;
    });
  }
}

/// State for [EditLocationsScreen].
class _EditLocationsScreenState extends ConsumerState<EditLocationsScreen> {
  final TextEditingController _createController = TextEditingController();

  /// Whether the create-location input field currently contains non-whitespace text.
  bool get _hasCreateText => _createController.text.trim().isNotEmpty;

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
    final sortedLocations = board.sortedLocations;

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
              child: sortedLocations.isEmpty
                  ? _EmptyLocationsView(
                      message: localizations.emptyLocationsHint,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: sortedLocations.length,
                      itemBuilder: (context, index) {
                        final location = sortedLocations[index];
                        return _EditableLocationRow(
                          key: ValueKey('edit_location_row_${location.id}'),
                          location: location,
                          openTaskCount: board.openTaskCountForLocation(
                            location.id,
                          ),
                          onDelete: () => _deleteLocation(location.id),
                          onEdit: () => openEditLocationScreen(
                            context,
                            location: location,
                          ),
                        );
                      },
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

  /// Rebuilds when the create-location text changes.
  void _handleCreateInputChanged() {
    setState(() {});
  }

  /// Creates a new location from [_createController] and clears the input field.
  Future<void> _submitCreateLocation() async {
    final trimmed = _createController.text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _createController.clear();
    final fix = ref.read(locationStateProvider).fix;
    final rawLat = fix?.latitude;
    final rawLon = fix?.longitude;
    final hasGps = rawLat != null && rawLon != null;
    final latitude = hasGps ? double.parse(rawLat.toStringAsFixed(6)) : 0.0;
    final longitude = hasGps ? double.parse(rawLon.toStringAsFixed(6)) : 0.0;
    await ref
        .read(taskNotifierProvider.notifier)
        .addLocation(
          trimmed,
          latitude: latitude,
          longitude: longitude,
          radiusMeters: 100.0,
          source: hasGps ? 'gps' : 'manual',
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
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed: onDelete,
              ),
              Icon(
                Icons.place_outlined,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  location.name,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Badge.count(
                key: ValueKey('edit_location_badge_${location.id}'),
                count: openTaskCount,
              ),
              const SizedBox(width: 4),
              IconButton(
                key: ValueKey('edit_location_button_${location.id}'),
                tooltip: localizations.tooltipEditLocation,
                icon: Icon(
                  Icons.edit_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed: onEdit,
              ),
            ],
          ),
        ),
      ),
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

/// Card inside [EditLocationScreen] for editing latitude, longitude, radius, source, and populating from current GPS position.
class _LocationCoordinatesCard extends StatelessWidget {
  /// Creates a [_LocationCoordinatesCard].
  const _LocationCoordinatesCard({
    required this.errorMessage,
    required this.latController,
    required this.lonController,
    required this.radiusController,
    required this.sourceController,
    required this.onUseCurrentGps,
  });

  /// Validation error message for coordinates or radius, or `null` when valid.
  final String? errorMessage;

  /// Controller for latitude input.
  final TextEditingController latController;

  /// Controller for longitude input.
  final TextEditingController lonController;

  /// Callback invoked when the "Use Current GPS Position" button is tapped.
  final VoidCallback onUseCurrentGps;

  /// Controller for radius input.
  final TextEditingController radiusController;

  /// Controller for optional source token input.
  final TextEditingController sourceController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return TaskEditorSectionCard(
      cardKey: const ValueKey('location_editor_coordinates_card'),
      icon: Icons.my_location_rounded,
      title: localizations.locationCoordinatesSectionTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildCoordinateField(
                  appTheme: appTheme,
                  fieldKey: const ValueKey('location_editor_lat_input'),
                  controller: latController,
                  labelText: localizations.locationLatitudeLabel,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCoordinateField(
                  appTheme: appTheme,
                  fieldKey: const ValueKey('location_editor_lon_input'),
                  controller: lonController,
                  labelText: localizations.locationLongitudeLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildCoordinateField(
                  appTheme: appTheme,
                  fieldKey: const ValueKey('location_editor_radius_input'),
                  controller: radiusController,
                  labelText: localizations.locationRadiusLabel,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCoordinateField(
                  appTheme: appTheme,
                  fieldKey: const ValueKey('location_editor_source_input'),
                  controller: sourceController,
                  labelText: 'Source',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('location_editor_use_gps_button'),
              onPressed: onUseCurrentGps,
              icon: const Icon(Icons.gps_fixed_rounded, size: 16),
              label: Text(localizations.locationUseCurrentGpsButton),
            ),
          ),
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                errorMessage ?? '',
                style: TextStyle(color: appTheme.errorColor, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  /// Builds a single coordinate or radius input field.
  static Widget _buildCoordinateField({
    required AppTheme appTheme,
    required Key fieldKey,
    required TextEditingController controller,
    required String labelText,
  }) {
    final borderRadius = BorderRadius.circular(12);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: appTheme.mutedTextColor.withValues(alpha: 0.35),
      ),
    );
    return ClearableTextField(
      fieldKey: fieldKey,
      controller: controller,
      clearIconColor: appTheme.mutedTextColor,
      clearIconSize: 16,
      cursorColor: appTheme.tertiaryAccent,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 13),
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(color: appTheme.mutedTextColor, fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: appTheme.canvasColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: appTheme.tertiaryAccent, width: 1.5),
        ),
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
