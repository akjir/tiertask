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

import '../../l10n/app_localizations.dart';
import '../../models/location_state.dart';
import '../../providers/location_providers.dart';

/// Popup dialog displaying the current foreground location determination status, place name, and GPS coordinates.
class LocationStatusDialog extends ConsumerWidget {
  /// Creates a [LocationStatusDialog].
  const LocationStatusDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final locationState = ref.watch(locationStateProvider);
    final isSearching = locationState.status == LocationStatus.searching;
    final fix = locationState.fix;

    return AlertDialog(
      title: Text(localizations.locationDialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LocationStatusBanner(status: locationState.status),
            if (locationState.status == LocationStatus.found &&
                fix != null) ...[
              const SizedBox(height: 12),
              _LocationDetailBox(
                label: localizations.locationPlaceLabel,
                value: fix.placeName ?? localizations.locationPlaceUnknown,
              ),
              if (fix.formattedCoordinates case final coordinates?) ...[
                const SizedBox(height: 8),
                _LocationDetailBox(
                  label: localizations.locationCoordinatesLabel,
                  value: coordinates,
                  monospace: true,
                ),
              ],
              if (fix.source case final source?) ...[
                const SizedBox(height: 8),
                _LocationDetailBox(
                  label: localizations.locationSourceLabel,
                  value: _resolveSourceText(localizations, source),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('location_dialog_refresh_button'),
          onPressed: isSearching
              ? null
              : () =>
                    ref.read(locationStateProvider.notifier).refreshLocation(),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(localizations.actionRefresh),
        ),
        FilledButton(
          key: const ValueKey('location_dialog_close_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.actionClose),
        ),
      ],
    );
  }

  /// Resolves the localized display label for [source].
  static String _resolveSourceText(
    AppLocalizations localizations,
    LocationSource source,
  ) {
    return switch (source) {
      LocationSource.gps => localizations.locationSourceGps,
      LocationSource.system => localizations.locationSourceSystem,
      LocationSource.internet => localizations.locationSourceInternet,
    };
  }
}

/// Top bar icon button shown to the right of the search button when foreground location determination is enabled.
class TopBarLocationButton extends ConsumerWidget {
  /// Creates a [TopBarLocationButton].
  const TopBarLocationButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationEnabled = ref.watch(locationEnabledProvider);
    if (!locationEnabled) {
      return const SizedBox.shrink();
    }
    final status = ref.watch(
      locationStateProvider.select((state) => state.status),
    );
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final iconData = _resolveIcon(status);
    final iconColor = status == LocationStatus.found
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return IconButton(
      key: const ValueKey('top_bar_location_button'),
      tooltip: localizations.tooltipLocationStatus,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          iconData,
          key: ValueKey<LocationStatus>(status),
          color: iconColor,
          size: 24,
        ),
      ),
      onPressed: () => showLocationStatusDialog(context),
    );
  }

  /// Maps [status] to the corresponding Material location icon.
  static IconData _resolveIcon(LocationStatus status) {
    return switch (status) {
      LocationStatus.disabled => Icons.location_disabled_rounded,
      LocationStatus.searching => Icons.location_searching_rounded,
      LocationStatus.found => Icons.location_on_rounded,
      LocationStatus.unavailable => Icons.location_disabled_rounded,
    };
  }
}

/// Labeled container box inside [LocationStatusDialog] displaying the resolved place name or GPS coordinates.
class _LocationDetailBox extends StatelessWidget {
  /// Creates a [_LocationDetailBox].
  const _LocationDetailBox({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  /// Header label above the value.
  final String label;

  /// Whether [value] should be rendered in a monospace font.
  final bool monospace;

  /// Text value displayed inside the box.
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: monospace
                ? theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')
                : theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Status row inside [LocationStatusDialog] indicating whether location is searching, found, or unavailable.
class _LocationStatusBanner extends StatelessWidget {
  /// Creates a [_LocationStatusBanner].
  const _LocationStatusBanner({required this.status});

  /// Current [LocationStatus].
  final LocationStatus status;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final statusText = _resolveStatusText(localizations, status);
    final isFound = status == LocationStatus.found;
    final isSearching = status == LocationStatus.searching;

    return Row(
      children: [
        if (isSearching)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(
            isFound
                ? Icons.location_on_rounded
                : Icons.location_disabled_rounded,
            color: isFound ? colorScheme.primary : colorScheme.onSurfaceVariant,
            size: 22,
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            statusText,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  /// Resolves the localized status description for [status].
  static String _resolveStatusText(
    AppLocalizations localizations,
    LocationStatus status,
  ) {
    return switch (status) {
      LocationStatus.disabled => localizations.locationStatusUnavailable,
      LocationStatus.searching => localizations.locationStatusSearching,
      LocationStatus.found => localizations.locationStatusFound,
      LocationStatus.unavailable => localizations.locationStatusUnavailable,
    };
  }
}

/// Opens [LocationStatusDialog] as a modal dialog.
Future<void> showLocationStatusDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const LocationStatusDialog(),
  );
}
