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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/location_state.dart';
import '../../providers/entity_actions_provider.dart';
import '../../providers/location_providers.dart';
import '../../providers/shell_providers.dart';
import '../../providers/ui_telemetry.dart';
import '../components/ui_dialog_frame.dart';
import '../primitives/ui_banner.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../primitives/ui_pill.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';
import '../ui_domain_mappers.dart';

/// Labeled inset well rendering one selectable location metadata attribute.
class _LocationDetailWell extends StatelessWidget {
  /// Creates a [_LocationDetailWell].
  const _LocationDetailWell({
    super.key,
    required this.label,
    required this.value,
    this.isMonospace = false,
  });

  /// Whether [value] renders in monospace typography (e.g. 6dp GPS coordinates).
  final bool isMonospace;

  /// Muted field caption above [value].
  final String label;

  /// Selectable display text inside the well.
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final valueStyle = isMonospace
        ? UiTypographyTokens.mono(
            tokens.typography.monoSmall.copyWith(color: colors.ink),
          )
        : tokens.typography.control.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w600,
          );

    return UiCard.inset(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: tokens.typography.meta.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 4.0),
          SelectableText(value, style: valueStyle),
        ],
      ),
    );
  }
}

/// Readout list inside [_LocationStatusModalBody] displaying populated place, coordinate, and source wells.
class _LocationMetadataWells extends StatelessWidget {
  /// Creates a [_LocationMetadataWells].
  const _LocationMetadataWells({required this.locationState});

  /// Current foreground domain location state.
  final LocationState locationState;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final metadata = _resolveMetadata(localizations);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (metadata.place.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12.0),
          _LocationDetailWell(
            key: const ValueKey<String>('location_status_place'),
            label: localizations.locationPlaceLabel,
            value: metadata.place,
          ),
        ],
        if (metadata.coordinates.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8.0),
          _LocationDetailWell(
            key: const ValueKey<String>('location_status_coordinates'),
            label: localizations.locationCoordinatesLabel,
            value: metadata.coordinates,
            isMonospace: true,
          ),
        ],
        if (metadata.source.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8.0),
          _LocationDetailWell(
            key: const ValueKey<String>('location_status_source'),
            label: localizations.locationSourceLabel,
            value: metadata.source,
          ),
        ],
      ],
    );
  }

  /// Resolves formatted place, 6dp coordinates, and source captions from [locationState].
  ({String coordinates, String place, String source}) _resolveMetadata(
    AppLocalizations localizations,
  ) {
    return (
      coordinates: UiDomainMappers.formatLocationCoordinates6dp(
        locationState.fix,
      ),
      place: UiDomainMappers.resolveLocationPlaceLabel(
        locationState,
        localizations,
      ),
      source: UiDomainMappers.locationSourceLabel(
        locationState.fix?.source,
        localizations,
      ),
    );
  }
}

/// Centered modal presenting live foreground location status, place, 6dp coordinates, and refresh control.
class _LocationStatusModal extends ConsumerStatefulWidget {
  /// Creates a [_LocationStatusModal].
  const _LocationStatusModal({required this.onClose});

  /// Callback closing this modal route.
  final VoidCallback onClose;

  @override
  ConsumerState<_LocationStatusModal> createState() =>
      _LocationStatusModalState();
}

/// Body layout for [_LocationStatusModal].
class _LocationStatusModalBody extends StatelessWidget {
  /// Creates a [_LocationStatusModalBody].
  const _LocationStatusModalBody({
    required this.locationState,
    required this.errorMessage,
    required this.onDismissError,
  });

  /// Optional transient refresh error message.
  final String? errorMessage;

  /// Current foreground domain location state.
  final LocationState locationState;

  /// Callback dismissing [errorMessage].
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: UiPill(
            key: const ValueKey<String>('location_status_pill'),
            label: UiDomainMappers.locationStatusLabel(
              locationState.status,
              localizations,
            ),
            icon: UiDomainMappers.locationIcon(locationState.status),
            tone: _locationStatusPillTone(locationState.status),
          ),
        ),
        _LocationMetadataWells(locationState: locationState),
        if (errorMessage case final message?) ...<Widget>[
          const SizedBox(height: 10.0),
          UiBanner(
            variant: UiBannerVariant.status,
            tone: UiBannerTone.danger,
            message: message,
            dismissTooltip: localizations.actionDismiss,
            onDismiss: onDismissError,
          ),
        ],
      ],
    );
  }
}

/// Footer row for [_LocationStatusModal] pairing `Refresh` and `Close`.
class _LocationStatusModalFooter extends StatelessWidget {
  /// Creates a [_LocationStatusModalFooter].
  const _LocationStatusModalFooter({
    required this.isRefreshing,
    required this.isBusy,
    required this.onRefresh,
    required this.onClose,
  });

  /// Whether a sync or refresh action is currently executing.
  final bool isBusy;

  /// Whether foreground location lookup is currently active.
  final bool isRefreshing;

  /// Callback closing the modal.
  final VoidCallback onClose;

  /// Callback triggering immediate location refresh.
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      alignment: WrapAlignment.end,
      children: <Widget>[
        UiButton(
          key: const ValueKey<String>('location_status_refresh_button'),
          label: localizations.actionRefresh,
          leadingIcon: Icons.refresh_rounded,
          density: UiButtonDensity.compact,
          isLoading: isRefreshing,
          onPressed: (isRefreshing || isBusy) ? null : onRefresh,
        ),
        UiButton(
          key: const ValueKey<String>('location_status_close_button'),
          label: localizations.actionClose,
          variant: UiButtonVariant.primary,
          density: UiButtonDensity.compact,
          onPressed: onClose,
        ),
      ],
    );
  }
}

/// State managing foreground location refresh invocation and error reporting inside [_LocationStatusModal].
class _LocationStatusModalState extends ConsumerState<_LocationStatusModal> {
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isLocationEnabled = ref.watch(locationEnabledProvider);
    final rawLocationState = ref.watch(locationStateProvider);
    final locationState = isLocationEnabled
        ? rawLocationState
        : const LocationState.disabled();
    final isBusy = ref.watch(
      syncActionsProvider.select((state) => state.isBusy),
    );

    return UiDialogFrame(
      key: const ValueKey<String>('location_status_modal'),
      title: localizations.locationDialogTitle,
      closeTooltip: localizations.actionClose,
      onClose: widget.onClose,
      body: _LocationStatusModalBody(
        locationState: locationState,
        errorMessage: _errorMessage,
        onDismissError: _clearError,
      ),
      footer: _LocationStatusModalFooter(
        isRefreshing: locationState.status == LocationStatus.searching,
        isBusy: isBusy,
        onRefresh: _triggerRefresh,
        onClose: widget.onClose,
      ),
    );
  }

  /// Clears any displayed refresh error banner.
  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  /// Triggers an immediate location refresh through [SyncActionsNotifier].
  Future<void> _handleRefresh() async {
    _clearError();
    final result = await ref
        .read(syncActionsProvider.notifier)
        .refreshLocation();
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        break;
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        if (message.isNotEmpty) {
          setState(() => _errorMessage = message);
        }
    }
  }

  /// Dispatches async location refresh from synchronous button callbacks.
  void _triggerRefresh() {
    unawaited(_handleRefresh());
  }
}

/// Presents the foreground location status modal showing status pill, place, 6dp GPS coordinates, source, and refresh action.
Future<void> showLocationStatusModal(BuildContext context) {
  UiTelemetry.logDialogOpened('location_status');
  final localizations = AppLocalizations.of(context);
  return UiDialogFrame.showModal<void>(
    context: context,
    barrierLabel: localizations.locationDialogTitle,
    builder: (modalContext) => _LocationStatusModal(
      onClose: () => Navigator.of(modalContext).maybePop(),
    ),
  );
}

/// Maps domain [LocationStatus] exhaustively to its semantic [UiPillTone].
UiPillTone _locationStatusPillTone(LocationStatus status) {
  return switch (status) {
    LocationStatus.found => UiPillTone.success,
    LocationStatus.searching => UiPillTone.soft,
    LocationStatus.disabled || LocationStatus.unavailable => UiPillTone.neutral,
  };
}
