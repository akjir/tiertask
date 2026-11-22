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

import '../../l10n/app_localizations.dart';
import '../../models/location_state.dart';
import '../../providers/ui_telemetry.dart';
import '../components/ui_dialog_frame.dart';
import '../components/ui_searchable_picker.dart';
import '../primitives/ui_button.dart';

/// Centered modal listing ranked forward-geocoding candidates for user disambiguation.
class _GeocodingCandidatesModal extends StatelessWidget {
  /// Creates a [_GeocodingCandidatesModal].
  const _GeocodingCandidatesModal({
    required this.candidates,
    required this.onSelect,
    required this.onClose,
  });

  /// Ranked domain geocoding candidates to list.
  final List<GeocodingCandidate> candidates;

  /// Callback dismissing the modal without selection.
  final VoidCallback onClose;

  /// Callback returning the chosen [GeocodingCandidate].
  final ValueChanged<GeocodingCandidate> onSelect;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiDialogFrame(
      key: const ValueKey<String>('geocoding_candidates_modal'),
      title: localizations.locationSelectCandidateTitle,
      closeTooltip: localizations.actionClose,
      onClose: onClose,
      body: UiSearchablePicker<GeocodingCandidate>(
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
        density: UiButtonDensity.compact,
        onPressed: onClose,
      ),
    );
  }

  /// Maps domain [GeocodingCandidate] entries to single-select picker rows.
  List<UiPickerOption<GeocodingCandidate>> _buildCandidateOptions() {
    return <UiPickerOption<GeocodingCandidate>>[
      for (var i = 0; i < candidates.length; i++)
        UiPickerOption<GeocodingCandidate>(
          id: '$i',
          value: candidates[i],
          label: candidates[i].displayName,
          subtitle: candidates[i].formattedCoordinates,
          icon: Icons.location_on_outlined,
        ),
    ];
  }
}

/// Presents the forward-geocoding candidate disambiguation modal and returns the chosen [GeocodingCandidate], or `null`.
Future<GeocodingCandidate?> showGeocodingCandidatesModal(
  BuildContext context, {
  required List<GeocodingCandidate> candidates,
}) {
  UiTelemetry.logDialogOpened('geocoding_candidates');
  final localizations = AppLocalizations.of(context);
  return UiDialogFrame.showModal<GeocodingCandidate>(
    context: context,
    barrierLabel: localizations.locationSelectCandidateTitle,
    builder: (modalContext) => _GeocodingCandidatesModal(
      candidates: candidates,
      onSelect: (candidate) =>
          Navigator.of(modalContext).pop<GeocodingCandidate>(candidate),
      onClose: () => Navigator.of(modalContext).maybePop(),
    ),
  );
}
