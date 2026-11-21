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

import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../presentation/entity_controller.dart';
import '../../presentation/ui_telemetry.dart';

/// Centered modal listing ranked forward-geocoding candidates for user disambiguation.
class _GeocodingCandidatesModal extends StatelessWidget {
  /// Creates a [_GeocodingCandidatesModal].
  const _GeocodingCandidatesModal({
    required this.candidates,
    required this.onSelect,
    required this.onClose,
  });

  /// Ranked geocoding candidate projections to list.
  final List<GeocodingCandidateViewModel> candidates;

  /// Callback dismissing the modal without selection.
  final VoidCallback onClose;

  /// Callback returning the chosen candidate index.
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiDialogFrame(
      key: const ValueKey<String>('geocoding_candidates_modal'),
      title: localizations.locationSelectCandidateTitle,
      size: UiDialogSize.medium,
      closeTooltip: localizations.actionClose,
      onClose: onClose,
      body: UiSearchablePicker<int>(
        key: const ValueKey<String>('geocoding_candidates_picker'),
        options: _buildCandidateOptions(),
        selectedIds: const <String>{},
        selectionMode: UiPickerSelectionMode.single,
        showSearch: false,
        showSelectedChips: false,
        emptyText: localizations.locationResolveErrorNotFound,
        onToggleOption: (option) => onSelect(option.value),
        onRequestClose: onClose,
      ),
      footer: UiButton(
        key: const ValueKey<String>('geocoding_candidates_cancel_button'),
        label: localizations.actionCancel,
        variant: UiButtonVariant.secondary,
        density: UiButtonDensity.compact,
        onPressed: onClose,
      ),
    );
  }

  /// Maps geocoding candidate projections to single-select picker rows.
  List<UiPickerOption<int>> _buildCandidateOptions() {
    return <UiPickerOption<int>>[
      for (final candidate in candidates)
        UiPickerOption<int>(
          id: '${candidate.index}',
          value: candidate.index,
          label: candidate.displayName,
          subtitle: candidate.coordinatesSummary,
          icon: Icons.location_on_outlined,
        ),
    ];
  }
}

/// Presents the forward-geocoding candidate disambiguation modal and returns the chosen candidate index, or `null`.
Future<int?> showGeocodingCandidatesModal(
  BuildContext context, {
  required List<GeocodingCandidateViewModel> candidates,
}) {
  UiTelemetry.logDialogOpened('geocoding_candidates');
  final localizations = AppLocalizations.of(context);
  return UiDialogFrame.showModal<int>(
    context: context,
    barrierLabel: localizations.locationSelectCandidateTitle,
    builder: (modalContext) => _GeocodingCandidatesModal(
      candidates: candidates,
      onSelect: (index) => Navigator.of(modalContext).pop<int>(index),
      onClose: () => Navigator.of(modalContext).maybePop(),
    ),
  );
}
