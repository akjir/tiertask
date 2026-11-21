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
import 'package:tiertask_ui/tiertask_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../presentation/shell_models.dart';
import '../../presentation/sync_controller.dart';
import '../../presentation/ui_telemetry.dart';
import '../ui_icon_mapper.dart';

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
  const _LocationMetadataWells({required this.viewModel});

  /// Current foreground location projection.
  final LocationStatusViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (viewModel.placeLabel.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12.0),
          _LocationDetailWell(
            key: const ValueKey<String>('location_status_place'),
            label: localizations.locationPlaceLabel,
            value: viewModel.placeLabel,
          ),
        ],
        if (viewModel.coordinatesText.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8.0),
          _LocationDetailWell(
            key: const ValueKey<String>('location_status_coordinates'),
            label: localizations.locationCoordinatesLabel,
            value: viewModel.coordinatesText,
            isMonospace: true,
          ),
        ],
        if (viewModel.sourceLabel.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8.0),
          _LocationDetailWell(
            key: const ValueKey<String>('location_status_source'),
            label: localizations.locationSourceLabel,
            value: viewModel.sourceLabel,
          ),
        ],
      ],
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
    required this.viewModel,
    required this.errorMessage,
    required this.onDismissError,
  });

  /// Optional transient refresh error message.
  final String? errorMessage;

  /// Callback dismissing [errorMessage].
  final VoidCallback onDismissError;

  /// Current location status projection.
  final LocationStatusViewModel viewModel;

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
            label: viewModel.statusLabel,
            icon: UiIconMapper.locationIcon(viewModel.statusKind),
            variant: UiPillVariant.badge,
            tone: _locationStatusPillTone(viewModel.statusKind),
          ),
        ),
        _LocationMetadataWells(viewModel: viewModel),
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
        KeyedSubtree(
          key: ValueKey<bool>(isRefreshing),
          child: UiButton(
            key: const ValueKey<String>('location_status_refresh_button'),
            label: localizations.actionRefresh,
            leadingIcon: Icons.refresh_rounded,
            variant: UiButtonVariant.secondary,
            density: UiButtonDensity.compact,
            isLoading: isRefreshing,
            onPressed: (isRefreshing || isBusy) ? null : onRefresh,
          ),
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
    final viewModel = ref.watch(locationStatusViewModelProvider);
    final syncState = ref.watch(syncControllerProvider);

    return UiDialogFrame(
      key: const ValueKey<String>('location_status_modal'),
      title: localizations.locationDialogTitle,
      size: UiDialogSize.medium,
      closeTooltip: localizations.actionClose,
      onClose: widget.onClose,
      body: _LocationStatusModalBody(
        viewModel: viewModel,
        errorMessage: _errorMessage,
        onDismissError: _clearError,
      ),
      footer: _LocationStatusModalFooter(
        isRefreshing: viewModel.isRefreshing,
        isBusy: syncState.isBusy,
        onRefresh: () async {
          await _handleRefresh();
        },
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

  /// Triggers an immediate location refresh through [SyncController].
  Future<void> _handleRefresh() async {
    _clearError();
    final result = await ref
        .read(syncControllerProvider.notifier)
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

/// Maps [ShellLocationStatusKind] exhaustively to its semantic [UiPillTone].
UiPillTone _locationStatusPillTone(ShellLocationStatusKind statusKind) {
  return switch (statusKind) {
    ShellLocationStatusKind.found => UiPillTone.success,
    ShellLocationStatusKind.searching => UiPillTone.soft,
    ShellLocationStatusKind.disabled ||
    ShellLocationStatusKind.unavailable => UiPillTone.neutral,
  };
}
