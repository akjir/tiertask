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

/// Modal dialog and compact bottom-sheet presenters for TierTask UI v2 (`U-COMP-004`, `U-UX-005`, `U-A11Y-003`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../presentation/board_v2_view_models.dart';
import '../../presentation/entity_v2_controller.dart';
import '../../presentation/settings_v2_controller.dart';
import '../../presentation/sync_v2_controller.dart';
import '../../presentation/ui_telemetry.dart';
import '../../presentation/ui_v2_shell_models.dart';
import '../../presentation/workspace_v2_controller.dart';
import '../ui_v2_icon_mapper.dart';

/// Scope filter identifier showing all labels inside the compact label picker sheet.
const String _labelScopeAll = 'all';

/// Scope filter identifier showing only global context labels inside the compact label picker sheet.
const String _labelScopeGlobal = 'global';

/// Scope filter identifier showing only scoped queue labels inside the compact label picker sheet.
const String _labelScopeScoped = 'scoped';

/// Maximum Unicode scalar length for searchable label creation (`maxTdfTextLength`).
const int _maxLabelNameLength = 500;

/// Maximum character length for workspace display names.
const int _maxWorkspaceNameLength = 128;

/// Stateful body hosted inside the compact mobile label picker bottom sheet (`U-A11Y-003`).
class _CompactLabelPickerSheetBody extends StatefulWidget {
  /// Creates a [_CompactLabelPickerSheetBody].
  const _CompactLabelPickerSheetBody({
    required this.initialLabels,
    required this.hasBothScopedAndGlobal,
    required this.initialSelectedIds,
    required this.onToggleLabel,
    required this.onCreateAndAssign,
    required this.onOpenLabelInfo,
    required this.onRequestClose,
  });

  /// Whether conditional `All` / `Scoped` / `Global` filter pills are shown.
  final bool hasBothScopedAndGlobal;

  /// Initial label options supplied when opening the sheet.
  final List<LabelPickerOptionViewModel> initialLabels;

  /// Initial set of selected label identifiers.
  final Set<String> initialSelectedIds;

  /// Callback creating and assigning a new label by name.
  final ValueChanged<String> onCreateAndAssign;

  /// Callback navigating to the label manager card for a label identifier.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback closing the active bottom sheet route.
  final VoidCallback onRequestClose;

  /// Callback toggling selection of an existing label identifier.
  final ValueChanged<String> onToggleLabel;

  @override
  State<_CompactLabelPickerSheetBody> createState() =>
      _CompactLabelPickerSheetBodyState();
}

/// Manages local live selection, scope filtering, and inline label creation inside [_CompactLabelPickerSheetBody].
class _CompactLabelPickerSheetBodyState
    extends State<_CompactLabelPickerSheetBody> {
  String _activeScopeId = _labelScopeAll;
  late List<LabelPickerOptionViewModel> _labels;
  String _query = '';
  late Set<String> _selectedIds;
  final Set<String> _syntheticIds = <String>{};

  @override
  void initState() {
    super.initState();
    _labels = List<LabelPickerOptionViewModel>.of(widget.initialLabels);
    _selectedIds = Set<String>.of(widget.initialSelectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final hasDuplicate = _hasLabelNamed(_labels, _query.trim());

    return UiSearchablePicker<String>(
      key: const ValueKey<String>('compact_label_picker'),
      options: _buildOptions(localizations, tokens),
      selectedIds: _selectedIds,
      selectionMode: UiPickerSelectionMode.multiple,
      isCompactSheet: true,
      autoFocusSearch: false,
      searchMaxLength: _maxLabelNameLength,
      query: _query,
      onQueryChanged: _handleQueryChanged,
      searchPlaceholder: localizations.labelPickerSearchPlaceholder,
      searchClearTooltip: localizations.tooltipClearSearch,
      scopeFilters: _buildScopeFilters(localizations),
      activeScopeId: _activeScopeId,
      onScopeChanged: _handleScopeChanged,
      emptyText: _labels.isEmpty
          ? localizations.labelPickerEmptyHint
          : localizations.labelPickerNoMatches,
      infoTooltip: localizations.openLabelInManagerTooltip,
      onToggleOption: _handleToggleOption,
      onOptionInfo: _handleOptionInfo,
      removeChipTooltip: (option) =>
          localizations.labelPickerRemoveTooltip(option.label),
      inlineCreateLabel: (trimmed) =>
          localizations.labelPickerCreateAndAssign(trimmed),
      onInlineCreate: hasDuplicate ? null : _handleInlineCreate,
      onRequestClose: widget.onRequestClose,
    );
  }

  /// Builds picker option rows filtered by [_activeScopeId].
  List<UiPickerOption<String>> _buildOptions(
    AppLocalizations localizations,
    UiThemeTokens tokens,
  ) {
    final options = <UiPickerOption<String>>[];
    for (final label in _labels) {
      if (_activeScopeId == _labelScopeScoped && !label.isScoped) {
        continue;
      }
      if (_activeScopeId == _labelScopeGlobal && label.isScoped) {
        continue;
      }
      final colorDot = switch (label.colorValue) {
        final value? => Color(value),
        null => tokens.colors.accent,
      };
      options.add(
        UiPickerOption<String>(
          id: label.id,
          value: label.id,
          label: label.name,
          colorDot: colorDot,
          badgeLabel: label.isScoped ? localizations.scopedQueueLabel : null,
          countLabel: localizations.openTasksCountPill('${label.openCount}'),
          hasInfoAction: !_syntheticIds.contains(label.id),
        ),
      );
    }
    return options;
  }

  /// Builds conditional `All`, `Scoped`, and `Global` filter pills when both scopes exist.
  List<UiPickerScopeFilter> _buildScopeFilters(AppLocalizations localizations) {
    if (!widget.hasBothScopedAndGlobal) {
      return const <UiPickerScopeFilter>[];
    }
    var scopedCount = 0;
    for (final label in _labels) {
      if (label.isScoped) {
        scopedCount++;
      }
    }
    final globalCount = _labels.length - scopedCount;
    return <UiPickerScopeFilter>[
      UiPickerScopeFilter(
        id: _labelScopeAll,
        label: localizations.labelPickerFilterAll('${_labels.length}'),
      ),
      UiPickerScopeFilter(
        id: _labelScopeScoped,
        label: localizations.labelPickerFilterScoped('$scopedCount'),
      ),
      UiPickerScopeFilter(
        id: _labelScopeGlobal,
        label: localizations.labelPickerFilterGlobal('$globalCount'),
      ),
    ];
  }

  /// Invokes inline label creation and reflects the new selection optimistically inside the sheet.
  void _handleInlineCreate(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    widget.onCreateAndAssign(trimmed);
    final syntheticId = '_created_${_syntheticIds.length}';
    final createdOption = LabelPickerOptionViewModel(
      id: syntheticId,
      name: trimmed,
      isScoped: false,
      openCount: 0,
    );
    setState(() {
      _syntheticIds.add(syntheticId);
      _labels = <LabelPickerOptionViewModel>[..._labels, createdOption]
        ..sort(
          (first, second) =>
              first.name.toLowerCase().compareTo(second.name.toLowerCase()),
        );
      _selectedIds = <String>{..._selectedIds, syntheticId};
      _query = '';
      if (_activeScopeId == _labelScopeScoped) {
        _activeScopeId = _labelScopeAll;
      }
    });
  }

  /// Closes the bottom sheet and notifies the caller to inspect [option] in Labels manager.
  void _handleOptionInfo(UiPickerOption<String> option) {
    widget.onOpenLabelInfo(option.value);
    widget.onRequestClose();
  }

  /// Updates the controlled search query inside the sheet.
  void _handleQueryChanged(String nextQuery) {
    setState(() => _query = nextQuery);
  }

  /// Switches the active scope filter pill.
  void _handleScopeChanged(String nextScopeId) {
    setState(() => _activeScopeId = nextScopeId);
  }

  /// Toggles local selection state and forwards existing label IDs to the caller.
  void _handleToggleOption(UiPickerOption<String> option) {
    final nextSelected = Set<String>.of(_selectedIds);
    if (!nextSelected.add(option.id)) {
      nextSelected.remove(option.id);
    }
    setState(() => _selectedIds = nextSelected);
    if (!_syntheticIds.contains(option.id)) {
      widget.onToggleLabel(option.value);
    }
  }
}

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
            icon: UiV2IconMapper.locationIcon(viewModel.statusKind),
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
    final syncState = ref.watch(syncV2ControllerProvider);

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

  /// Triggers an immediate location refresh through [SyncV2Controller].
  Future<void> _handleRefresh() async {
    _clearError();
    final result = await ref
        .read(syncV2ControllerProvider.notifier)
        .refreshLocation();
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        break;
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        if (message.isNotEmpty) {
          setState(() => _errorMessage = message);
        }
    }
  }
}

/// Shared right-aligned `Cancel` + primary/danger action footer for confirmation modals.
class _ModalActionFooter extends StatelessWidget {
  /// Creates a [_ModalActionFooter].
  const _ModalActionFooter({
    required this.cancelKey,
    required this.confirmKey,
    required this.confirmLabel,
    required this.confirmVariant,
    required this.isBusy,
    required this.onCancel,
    required this.onConfirm,
  });

  /// Stable key for the cancel button.
  final Key cancelKey;

  /// Stable key for the confirm button.
  final Key confirmKey;

  /// Localized label for the confirm button.
  final String confirmLabel;

  /// Visual button variant (`primary` or `danger`).
  final UiButtonVariant confirmVariant;

  /// Whether an asynchronous action is currently in flight.
  final bool isBusy;

  /// Cancel callback.
  final VoidCallback onCancel;

  /// Confirm callback, or `null` when confirmation is disabled.
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      alignment: WrapAlignment.end,
      children: <Widget>[
        UiButton(
          key: cancelKey,
          label: localizations.actionCancel,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          onPressed: isBusy ? null : onCancel,
        ),
        KeyedSubtree(
          key: ValueKey<bool>(isBusy),
          child: UiButton(
            key: confirmKey,
            label: confirmLabel,
            variant: confirmVariant,
            density: UiButtonDensity.compact,
            isLoading: isBusy,
            onPressed: isBusy ? null : onConfirm,
          ),
        ),
      ],
    );
  }
}

/// Body input field for [_RenameLocalFileModal].
class _RenameLocalFileBody extends StatelessWidget {
  /// Creates a [_RenameLocalFileBody].
  const _RenameLocalFileBody({
    required this.controller,
    required this.currentFileName,
    required this.isBusy,
    required this.errorText,
    required this.onChanged,
    required this.onSubmitted,
  });

  /// Pre-filled controller for the target filename.
  final TextEditingController controller;

  /// Current filename displayed as placeholder hint.
  final String currentFileName;

  /// Optional live or persisted error text.
  final String? errorText;

  /// Whether rename persistence is currently executing.
  final bool isBusy;

  /// Callback notified on input changes.
  final ValueChanged<String> onChanged;

  /// Callback submitting rename on `Enter`.
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiField(
      key: const ValueKey<String>('rename_local_file_input'),
      label: localizations.localFileNameInputLabel,
      hintText: currentFileName,
      controller: controller,
      autofocus: true,
      isMonospace: true,
      showClearButton: true,
      clearTooltip: localizations.tooltipClearInput,
      enabled: !isBusy,
      errorText: errorText,
      textInputAction: TextInputAction.done,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

/// Centered modal for renaming the active local `.tdf` file within its current directory.
class _RenameLocalFileModal extends ConsumerStatefulWidget {
  /// Creates a [_RenameLocalFileModal].
  const _RenameLocalFileModal({
    required this.currentFileName,
    required this.onClose,
  });

  /// Current local `.tdf` filename shown in the dialog subtitle.
  final String currentFileName;

  /// Callback closing the modal route.
  final VoidCallback onClose;

  @override
  ConsumerState<_RenameLocalFileModal> createState() =>
      _RenameLocalFileModalState();
}

/// State owning the pre-filled filename controller and validation readout for [_RenameLocalFileModal].
class _RenameLocalFileModalState extends ConsumerState<_RenameLocalFileModal> {
  late final TextEditingController _controller;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _stripTdfExtension(widget.currentFileName),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isBusy = ref.watch(
      settingsV2ControllerProvider.select((state) => state.isBusy),
    );

    return UiDialogFrame(
      key: const ValueKey<String>('rename_local_file_modal'),
      title: localizations.renameLocalDialogTitle,
      subtitle: localizations.renameLocalDialogDescription(
        widget.currentFileName,
      ),
      size: UiDialogSize.small,
      closeTooltip: localizations.actionClose,
      onClose: widget.onClose,
      body: _RenameLocalFileBody(
        controller: _controller,
        currentFileName: widget.currentFileName,
        isBusy: isBusy,
        errorText: _resolveErrorText(localizations),
        onChanged: _handleInputChanged,
        onSubmitted: (_) async {
          await _handleSubmit();
        },
      ),
      footer: _ModalActionFooter(
        cancelKey: const ValueKey<String>('rename_local_file_cancel_button'),
        confirmKey: const ValueKey<String>('rename_local_file_confirm_button'),
        confirmLabel: localizations.actionRenameLocalFile,
        confirmVariant: UiButtonVariant.primary,
        isBusy: isBusy,
        onCancel: widget.onClose,
        onConfirm: () async {
          await _handleSubmit();
        },
      ),
    );
  }

  /// Clears submission errors and refreshes inline validation when input text changes.
  void _handleInputChanged(String _) {
    setState(() => _submitError = null);
  }

  /// Commits the rename via [SettingsV2Controller.renameLocalFile] and closes on success.
  Future<void> _handleSubmit() async {
    final result = await ref
        .read(settingsV2ControllerProvider.notifier)
        .renameLocalFile(_controller.text);
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        widget.onClose();
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        setState(() => _submitError = message);
    }
  }

  /// Resolves live client validation or persistence error text.
  String? _resolveErrorText(AppLocalizations localizations) {
    final raw = _controller.text;
    if (raw.isNotEmpty && !_isValidLocalFileName(raw)) {
      return localizations.localFileNameErrorInvalid;
    }
    return _submitError;
  }
}

/// Body pairing the existing `.tdf` file picker with the manual new-filename field inside [_SelectLocalFileModal].
class _SelectLocalFileBody extends StatelessWidget {
  /// Creates a [_SelectLocalFileBody].
  const _SelectLocalFileBody({
    required this.options,
    required this.selectedIds,
    required this.fileNameController,
    required this.isBusy,
    required this.errorText,
    required this.onPickExisting,
    required this.onInputChanged,
    required this.onSubmitted,
    required this.onRequestClose,
  });

  /// Optional live or persisted validation error text.
  final String? errorText;

  /// Controller for the chosen or newly entered filename.
  final TextEditingController fileNameController;

  /// Whether file selection is currently executing.
  final bool isBusy;

  /// Callback notified on manual filename changes.
  final ValueChanged<String> onInputChanged;

  /// Callback populating the field from a picked file row.
  final ValueChanged<UiPickerOption<String>> onPickExisting;

  /// Callback closing the modal on second `Escape` from search.
  final VoidCallback onRequestClose;

  /// Callback committing selection on `Enter`.
  final ValueChanged<String> onSubmitted;

  /// Monospace file picker rows.
  final List<UiPickerOption<String>> options;

  /// Currently highlighted file identifier set.
  final Set<String> selectedIds;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiSearchablePicker<String>(
          key: const ValueKey<String>('select_local_file_picker'),
          options: options,
          selectedIds: selectedIds,
          selectionMode: UiPickerSelectionMode.single,
          showSelectedChips: false,
          searchPlaceholder: localizations.localFilePathHint,
          searchClearTooltip: localizations.tooltipClearSearch,
          emptyText: localizations.selectLocalDialogDescription,
          onToggleOption: onPickExisting,
          onRequestClose: onRequestClose,
        ),
        const SizedBox(height: 12.0),
        UiField(
          key: const ValueKey<String>('select_local_file_input'),
          label: localizations.localFileNameInputLabel,
          hintText: localizations.localFilePathHint,
          controller: fileNameController,
          isMonospace: true,
          showClearButton: true,
          clearTooltip: localizations.tooltipClearInput,
          enabled: !isBusy,
          errorText: errorText,
          textInputAction: TextInputAction.done,
          onChanged: onInputChanged,
          onSubmitted: onSubmitted,
        ),
      ],
    );
  }
}

/// Centered modal allowing selection of an existing local `.tdf` file or entry of a new `.tdf` filename.
class _SelectLocalFileModal extends ConsumerStatefulWidget {
  /// Creates a [_SelectLocalFileModal].
  const _SelectLocalFileModal({required this.onClose});

  /// Callback closing the modal route.
  final VoidCallback onClose;

  @override
  ConsumerState<_SelectLocalFileModal> createState() =>
      _SelectLocalFileModalState();
}

/// State owning discovered `.tdf` filenames, manual input controller, and submit validation for [_SelectLocalFileModal].
class _SelectLocalFileModalState extends ConsumerState<_SelectLocalFileModal> {
  late final List<String> _existingFileNames;
  late final TextEditingController _fileNameController;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    final settingsNotifier = ref.read(settingsV2ControllerProvider.notifier);
    final currentFileName = ref
        .read(settingsV2ControllerProvider)
        .localFileName;
    _existingFileNames = settingsNotifier.listLocalTdfFileNames();
    _fileNameController = TextEditingController(text: currentFileName);
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isBusy = ref.watch(
      settingsV2ControllerProvider.select((state) => state.isBusy),
    );
    final selectedName = _normalizeTdfFileName(_fileNameController.text);

    return UiDialogFrame(
      key: const ValueKey<String>('select_local_file_modal'),
      title: localizations.selectLocalDialogTitle,
      subtitle: localizations.selectLocalDialogDescription,
      size: UiDialogSize.medium,
      closeTooltip: localizations.actionClose,
      onClose: widget.onClose,
      body: _SelectLocalFileBody(
        options: _buildFileOptions(),
        selectedIds: selectedName.isEmpty
            ? const <String>{}
            : <String>{selectedName},
        fileNameController: _fileNameController,
        isBusy: isBusy,
        errorText: _resolveErrorText(localizations),
        onPickExisting: _handlePickExisting,
        onInputChanged: _handleInputChanged,
        onSubmitted: _triggerSubmitFromInput,
        onRequestClose: widget.onClose,
      ),
      footer: _ModalActionFooter(
        cancelKey: const ValueKey<String>('select_local_file_cancel_button'),
        confirmKey: const ValueKey<String>('select_local_file_confirm_button'),
        confirmLabel: localizations.actionSelectLocalFile,
        confirmVariant: UiButtonVariant.primary,
        isBusy: isBusy,
        onCancel: widget.onClose,
        onConfirm: _triggerSubmit,
      ),
    );
  }

  /// Maps discovered local `.tdf` filenames into monospace picker options.
  List<UiPickerOption<String>> _buildFileOptions() {
    return <UiPickerOption<String>>[
      for (final fileName in _existingFileNames)
        UiPickerOption<String>(
          id: fileName,
          value: fileName,
          label: fileName,
          icon: Icons.description_outlined,
          isMonospace: true,
        ),
    ];
  }

  /// Clears stale submission error and updates selection highlight on manual text input.
  void _handleInputChanged(String _) {
    setState(() => _submitError = null);
  }

  /// Populates the filename field when an existing `.tdf` option is selected.
  void _handlePickExisting(UiPickerOption<String> option) {
    setState(() {
      _submitError = null;
      _fileNameController.value = TextEditingValue(
        text: option.value,
        selection: TextSelection.collapsed(offset: option.value.length),
      );
    });
  }

  /// Submits the chosen `.tdf` filename via [SettingsV2Controller.selectLocalFile].
  Future<void> _handleSubmit() async {
    final result = await ref
        .read(settingsV2ControllerProvider.notifier)
        .selectLocalFile(chosenFileName: _fileNameController.text);
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        widget.onClose();
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        setState(() => _submitError = message);
    }
  }

  /// Resolves live client validation or controller error text.
  String? _resolveErrorText(AppLocalizations localizations) {
    final raw = _fileNameController.text;
    if (raw.isNotEmpty && !_isValidLocalFileName(raw)) {
      return localizations.localFileNameErrorInvalid;
    }
    return _submitError;
  }

  /// Dispatches async local file selection from synchronous callbacks.
  void _triggerSubmit() {
    _handleSubmit();
  }

  /// Dispatches async local file selection from text submission callbacks.
  void _triggerSubmitFromInput(String _) {
    _handleSubmit();
  }
}

/// Centered destructive confirmation modal enforcing the `U-UX-005` typed-filename guard before wiping a `.tdf` file.
class _WipeTdfModal extends ConsumerStatefulWidget {
  /// Creates a [_WipeTdfModal].
  const _WipeTdfModal({
    required this.isRemote,
    required this.fileName,
    required this.baseName,
    required this.onClose,
  });

  /// Required filename without `.tdf` extension unlocking the danger button.
  final String baseName;

  /// Full display `.tdf` filename shown in the modal description.
  final String fileName;

  /// Whether the wipe targets the remote WebDAV file (`true`) or local file (`false`).
  final bool isRemote;

  /// Callback closing this modal route.
  final VoidCallback onClose;

  @override
  ConsumerState<_WipeTdfModal> createState() => _WipeTdfModalState();
}

/// Body pairing the typed-filename confirmation field and default-checked `.bak` toggle inside [_WipeTdfModal].
class _WipeTdfModalBody extends StatelessWidget {
  /// Creates a [_WipeTdfModalBody].
  const _WipeTdfModalBody({
    required this.baseName,
    required this.confirmController,
    required this.createBackup,
    required this.isBusy,
    required this.errorMessage,
    required this.onInputChanged,
    required this.onSubmitted,
    required this.onBackupChanged,
  });

  /// Expected filename without `.tdf` shown as field hint.
  final String baseName;

  /// Controller for typed-filename confirmation input.
  final TextEditingController confirmController;

  /// Whether `.bak` backup creation is currently checked.
  final bool createBackup;

  /// Optional persistence error text.
  final String? errorMessage;

  /// Whether wipe persistence is currently executing.
  final bool isBusy;

  /// Callback toggling backup creation.
  final ValueChanged<bool> onBackupChanged;

  /// Callback notified on confirmation input changes.
  final ValueChanged<String> onInputChanged;

  /// Callback invoked when user submits via `Enter`.
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiField(
          key: const ValueKey<String>('wipe_tdf_confirm_input'),
          label: localizations.wipeConfirmInputLabel,
          hintText: baseName,
          controller: confirmController,
          autofocus: true,
          isMonospace: true,
          showClearButton: true,
          clearTooltip: localizations.tooltipClearInput,
          enabled: !isBusy,
          errorText: errorMessage,
          textInputAction: TextInputAction.done,
          onChanged: onInputChanged,
          onSubmitted: onSubmitted,
        ),
        const SizedBox(height: 12.0),
        UiToggleRow(
          key: const ValueKey<String>('wipe_tdf_backup_toggle'),
          label: localizations.wipeCreateBackupLabel,
          value: createBackup,
          enabled: !isBusy,
          onChanged: onBackupChanged,
        ),
      ],
    );
  }
}

/// State owning typed confirmation text, default-checked backup toggle, and error reporting for [_WipeTdfModal].
class _WipeTdfModalState extends ConsumerState<_WipeTdfModal> {
  final TextEditingController _confirmController = TextEditingController();
  bool _createBackup = true;
  String? _errorMessage;

  /// Whether trimmed user input exactly matches [widget.baseName].
  bool get _isConfirmEnabled =>
      _confirmController.text.trim() == widget.baseName;

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isBusy = ref.watch(
      settingsV2ControllerProvider.select((state) => state.isBusy),
    );
    return UiDialogFrame(
      key: ValueKey<String>(
        widget.isRemote ? 'wipe_remote_tdf_modal' : 'wipe_local_tdf_modal',
      ),
      title: _resolveTitle(localizations),
      subtitle: _resolveSubtitle(localizations),
      size: UiDialogSize.small,
      closeTooltip: localizations.actionClose,
      onClose: widget.onClose,
      body: _WipeTdfModalBody(
        baseName: widget.baseName,
        confirmController: _confirmController,
        createBackup: _createBackup,
        isBusy: isBusy,
        errorMessage: _errorMessage,
        onInputChanged: _handleInputChanged,
        onSubmitted: (_) => _triggerConfirmIfReady(isBusy: isBusy),
        onBackupChanged: _handleBackupChanged,
      ),
      footer: _ModalActionFooter(
        cancelKey: const ValueKey<String>('wipe_tdf_cancel_button'),
        confirmKey: const ValueKey<String>('wipe_tdf_confirm_button'),
        confirmLabel: localizations.actionWipeConfirm,
        confirmVariant: UiButtonVariant.danger,
        isBusy: isBusy,
        onCancel: widget.onClose,
        onConfirm: _isConfirmEnabled ? _triggerConfirm : null,
      ),
    );
  }

  /// Toggles `.bak` backup creation before wiping.
  void _handleBackupChanged(bool nextValue) {
    setState(() => _createBackup = nextValue);
  }

  /// Commits local or remote `.tdf` wipe through [SettingsV2Controller] and closes on success.
  Future<void> _handleConfirm() async {
    if (!_isConfirmEnabled) {
      return;
    }
    final notifier = ref.read(settingsV2ControllerProvider.notifier);
    final result = widget.isRemote
        ? await notifier.wipeRemoteFile(createBackup: _createBackup)
        : await notifier.wipeLocalFile(createBackup: _createBackup);
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        widget.onClose();
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        setState(() => _errorMessage = message);
    }
  }

  /// Re-evaluates the typed-filename guard whenever the input changes.
  void _handleInputChanged(String _) {
    setState(() => _errorMessage = null);
  }

  /// Resolves the localized subtitle for local or remote `.tdf` wipe confirmation.
  String _resolveSubtitle(AppLocalizations localizations) {
    return widget.isRemote
        ? localizations.wipeRemoteDialogDescription(
            widget.fileName,
            widget.baseName,
          )
        : localizations.wipeLocalDialogDescription(
            widget.fileName,
            widget.baseName,
          );
  }

  /// Resolves the localized heading for local or remote `.tdf` wipe confirmation.
  String _resolveTitle(AppLocalizations localizations) {
    return widget.isRemote
        ? localizations.wipeRemoteDialogTitle
        : localizations.wipeLocalDialogTitle;
  }

  /// Dispatches async wipe confirmation from synchronous button callbacks.
  void _triggerConfirm() {
    _handleConfirm();
  }

  /// Dispatches async wipe confirmation on `Enter` when the guard passes and idle.
  void _triggerConfirmIfReady({required bool isBusy}) {
    if (_isConfirmEnabled && !isBusy) {
      _handleConfirm();
    }
  }
}

/// Input and submit row inside [_WorkspaceCreateSection].
class _WorkspaceCreateRow extends StatelessWidget {
  /// Creates a [_WorkspaceCreateRow].
  const _WorkspaceCreateRow({
    required this.controller,
    required this.canCreateMore,
    required this.canSubmit,
    required this.isBusy,
    required this.onChanged,
    required this.onSubmit,
  });

  /// Whether another workspace may still be created.
  final bool canCreateMore;

  /// Whether submit button is enabled.
  final bool canSubmit;

  /// Controller for the new workspace name.
  final TextEditingController controller;

  /// Whether a workspace mutation is executing.
  final bool isBusy;

  /// Callback notified on input changes.
  final ValueChanged<String> onChanged;

  /// Callback submitting workspace creation.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: UiField(
            key: const ValueKey<String>('workspace_create_field'),
            controller: controller,
            hintText: localizations.createWorkspaceHint,
            maxLength: _maxWorkspaceNameLength,
            enabled: canCreateMore && !isBusy,
            showClearButton: true,
            clearTooltip: localizations.tooltipClearInput,
            helperText: canCreateMore
                ? null
                : localizations.errorWorkspaceMaxExceeded,
            textInputAction: TextInputAction.done,
            onChanged: onChanged,
            onSubmitted: _handleSubmitted,
          ),
        ),
        const SizedBox(width: 8.0),
        KeyedSubtree(
          key: ValueKey<bool>(isBusy),
          child: UiButton(
            key: const ValueKey<String>('workspace_create_button'),
            label: localizations.actionAdd,
            leadingIcon: Icons.add_rounded,
            variant: UiButtonVariant.primary,
            density: UiButtonDensity.standard,
            tooltip: localizations.tooltipCreateWorkspace,
            isLoading: isBusy,
            onPressed: canSubmit ? onSubmit : null,
          ),
        ),
      ],
    );
  }

  /// Submits creation on `Enter` when workspace capacity allows and no mutation is active.
  void _handleSubmitted(String _) {
    if (canCreateMore && !isBusy) {
      onSubmit();
    }
  }
}

/// Bottom create-workspace form displaying the input, live suggested `.tdf` caption, and primary create button.
class _WorkspaceCreateSection extends StatelessWidget {
  /// Creates a [_WorkspaceCreateSection].
  const _WorkspaceCreateSection({
    required this.controller,
    required this.canCreateMore,
    required this.isBusy,
    required this.suggestedFileName,
    required this.onChanged,
    required this.onSubmit,
  });

  /// Whether another workspace can still be created within `maxWorkspaces`.
  final bool canCreateMore;

  /// Controller for the new workspace name input.
  final TextEditingController controller;

  /// Whether a workspace mutation is currently executing.
  final bool isBusy;

  /// Callback invoked when input text changes.
  final ValueChanged<String> onChanged;

  /// Callback invoked when submitting creation via button or `Enter`.
  final VoidCallback onSubmit;

  /// Suggested lowercase `.tdf` filename derived from current text.
  final String suggestedFileName;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final hasInput = controller.text.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _WorkspaceCreateRow(
          controller: controller,
          canCreateMore: canCreateMore,
          canSubmit: canCreateMore && !isBusy && hasInput,
          isBusy: isBusy,
          onChanged: onChanged,
          onSubmit: onSubmit,
        ),
        if (canCreateMore && hasInput) ...<Widget>[
          const SizedBox(height: 6.0),
          Text(
            localizations.workspaceSuggestedFileLabel(suggestedFileName),
            key: const ValueKey<String>('workspace_suggested_file'),
            style: UiTypographyTokens.mono(
              tokens.typography.monoSmall.copyWith(color: tokens.colors.muted),
            ),
          ),
        ],
      ],
    );
  }
}

/// Inline confirmation banner rendered below a workspace card while confirming deletion.
class _WorkspaceDeleteConfirmBar extends StatelessWidget {
  /// Creates a [_WorkspaceDeleteConfirmBar].
  const _WorkspaceDeleteConfirmBar({
    required this.row,
    required this.isBusy,
    required this.onCancel,
    required this.onConfirm,
  });

  /// Whether a workspace mutation is executing.
  final bool isBusy;

  /// Callback cancelling delete confirmation.
  final VoidCallback onCancel;

  /// Callback confirming deletion.
  final VoidCallback onConfirm;

  /// Workspace row being confirmed for deletion.
  final WorkspaceRowViewModel row;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: UiBanner(
        key: ValueKey<String>('workspace_delete_confirm_${row.id}'),
        variant: UiBannerVariant.inlineConfirm,
        message: localizations.deleteWorkspaceConfirmMessage(row.name),
        cancelLabel: localizations.actionCancel,
        onCancel: isBusy ? null : onCancel,
        confirmLabel: localizations.actionDelete,
        onConfirm: isBusy ? null : onConfirm,
      ),
    );
  }
}

/// Optional inline error banner rendered above the workspace creation form.
class _WorkspaceErrorSlot extends StatelessWidget {
  /// Creates a [_WorkspaceErrorSlot].
  const _WorkspaceErrorSlot({
    required this.errorMessage,
    required this.onDismiss,
  });

  /// Optional localized error message.
  final String? errorMessage;

  /// Callback dismissing the banner.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final message = errorMessage;
    if (message == null) {
      return const SizedBox.shrink();
    }
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10.0),
      child: UiBanner(
        key: const ValueKey<String>('workspace_error_banner'),
        variant: UiBannerVariant.status,
        tone: UiBannerTone.danger,
        message: message,
        dismissTooltip: localizations.actionDismiss,
        onDismiss: onDismiss,
      ),
    );
  }
}

/// Inline rename input row replacing the standard workspace row header while editing.
class _WorkspaceInlineRenameRow extends StatelessWidget {
  /// Creates a [_WorkspaceInlineRenameRow].
  const _WorkspaceInlineRenameRow({
    required this.workspaceId,
    required this.controller,
    required this.isBusy,
    required this.onChanged,
    required this.onCancel,
    required this.onSave,
  });

  /// Controller pre-filled with the workspace display name.
  final TextEditingController controller;

  /// Whether a workspace mutation is currently executing.
  final bool isBusy;

  /// Callback cancelling inline rename.
  final VoidCallback onCancel;

  /// Callback notified when rename text changes.
  final ValueChanged<String> onChanged;

  /// Callback committing inline rename.
  final VoidCallback onSave;

  /// Identifier of the workspace being renamed.
  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: UiField(
            key: ValueKey<String>('workspace_rename_field_$workspaceId'),
            controller: controller,
            autofocus: true,
            maxLength: _maxWorkspaceNameLength,
            enabled: !isBusy,
            showClearButton: true,
            clearTooltip: localizations.tooltipClearInput,
            textInputAction: TextInputAction.done,
            onChanged: onChanged,
            onSubmitted: (_) => onSave(),
          ),
        ),
        const SizedBox(width: 8.0),
        _ModalActionFooter(
          cancelKey: ValueKey<String>('workspace_rename_cancel_$workspaceId'),
          confirmKey: ValueKey<String>('workspace_rename_save_$workspaceId'),
          confirmLabel: localizations.actionSave,
          confirmVariant: UiButtonVariant.primary,
          isBusy: isBusy,
          onCancel: onCancel,
          onConfirm: onSave,
        ),
      ],
    );
  }
}

/// Lazy vertical list of workspace cards rendered inside [_WorkspaceModalBody].
class _WorkspaceListSection extends StatelessWidget {
  /// Creates a [_WorkspaceListSection].
  const _WorkspaceListSection({
    required this.workspaces,
    required this.isBusy,
    required this.renamingWorkspaceId,
    required this.pendingDeleteWorkspaceId,
    required this.renameController,
    required this.onSelectWorkspace,
    required this.onStartRename,
    required this.onCancelRename,
    required this.onSaveRename,
    required this.onRenameChanged,
    required this.onRequestDelete,
    required this.onCancelDelete,
    required this.onConfirmDelete,
  });

  /// Whether a workspace mutation is currently executing.
  final bool isBusy;

  /// Callback dismissing an active inline delete confirmation.
  final VoidCallback onCancelDelete;

  /// Callback cancelling inline rename mode.
  final VoidCallback onCancelRename;

  /// Callback confirming deletion of a workspace identifier.
  final ValueChanged<String> onConfirmDelete;

  /// Callback notified when inline rename input changes.
  final ValueChanged<String> onRenameChanged;

  /// Callback opening inline delete confirmation for a workspace identifier.
  final ValueChanged<String> onRequestDelete;

  /// Callback committing inline rename for a workspace identifier.
  final ValueChanged<String> onSaveRename;

  /// Callback switching active workspace to an inactive workspace identifier.
  final ValueChanged<String> onSelectWorkspace;

  /// Callback entering inline rename mode for a workspace row.
  final ValueChanged<WorkspaceRowViewModel> onStartRename;

  /// Identifier of the workspace currently showing inline delete confirmation, if any.
  final String? pendingDeleteWorkspaceId;

  /// Controller for the active inline rename input.
  final TextEditingController renameController;

  /// Identifier of the workspace currently being renamed inline, if any.
  final String? renamingWorkspaceId;

  /// Ordered persisted workspace rows.
  final List<WorkspaceRowViewModel> workspaces;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: workspaces.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8.0),
      itemBuilder: (context, index) {
        final row = workspaces[index];
        return _WorkspaceModalRowCard(
          key: ValueKey<String>('workspace_card_${row.id}'),
          row: row,
          isBusy: isBusy,
          isRenaming: renamingWorkspaceId == row.id,
          isConfirmingDelete: pendingDeleteWorkspaceId == row.id,
          renameController: renameController,
          onSelect: () => onSelectWorkspace(row.id),
          onStartRename: () => onStartRename(row),
          onCancelRename: onCancelRename,
          onSaveRename: () => onSaveRename(row.id),
          onRenameChanged: onRenameChanged,
          onRequestDelete: () => onRequestDelete(row.id),
          onCancelDelete: onCancelDelete,
          onConfirmDelete: () => onConfirmDelete(row.id),
        );
      },
    );
  }
}

/// Scrollable body content of [_WorkspacesModal] composing workspace cards, error readout, and bottom create form.
class _WorkspaceModalBody extends StatelessWidget {
  /// Creates a [_WorkspaceModalBody].
  const _WorkspaceModalBody({
    required this.viewModel,
    required this.isBusy,
    required this.renamingWorkspaceId,
    required this.pendingDeleteWorkspaceId,
    required this.errorMessage,
    required this.createController,
    required this.renameController,
    required this.suggestedFileName,
    required this.onSelectWorkspace,
    required this.onStartRename,
    required this.onCancelRename,
    required this.onSaveRename,
    required this.onRenameChanged,
    required this.onRequestDelete,
    required this.onCancelDelete,
    required this.onConfirmDelete,
    required this.onCreateChanged,
    required this.onCreateSubmit,
    required this.onDismissError,
  });

  /// Controller for the bottom create-workspace input.
  final TextEditingController createController;

  /// Optional inline validation or persistence error message.
  final String? errorMessage;

  /// Whether a workspace mutation is currently executing.
  final bool isBusy;

  /// Callback dismissing an active inline delete confirmation.
  final VoidCallback onCancelDelete;

  /// Callback cancelling inline rename mode.
  final VoidCallback onCancelRename;

  /// Callback confirming deletion of a workspace identifier.
  final ValueChanged<String> onConfirmDelete;

  /// Callback notified when create input changes.
  final ValueChanged<String> onCreateChanged;

  /// Callback submitting new workspace creation.
  final VoidCallback onCreateSubmit;

  /// Callback dismissing [errorMessage].
  final VoidCallback onDismissError;

  /// Callback notified when inline rename input changes.
  final ValueChanged<String> onRenameChanged;

  /// Callback opening inline delete confirmation for a workspace identifier.
  final ValueChanged<String> onRequestDelete;

  /// Callback committing inline rename for a workspace identifier.
  final ValueChanged<String> onSaveRename;

  /// Callback switching active workspace to an inactive workspace identifier.
  final ValueChanged<String> onSelectWorkspace;

  /// Callback entering inline rename mode for a workspace row.
  final ValueChanged<WorkspaceRowViewModel> onStartRename;

  /// Identifier of the workspace currently showing inline delete confirmation, if any.
  final String? pendingDeleteWorkspaceId;

  /// Controller for the active inline rename input.
  final TextEditingController renameController;

  /// Identifier of the workspace currently being renamed inline, if any.
  final String? renamingWorkspaceId;

  /// Live suggested `.tdf` filename for [createController].
  final String suggestedFileName;

  /// Workspace list projection from [workspacesViewModelProvider].
  final WorkspacesViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (viewModel.isLoading) {
      return UiBanner(
        variant: UiBannerVariant.loadingState,
        message: localizations.loadingBoardSubtitle,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _WorkspaceListSection(
          workspaces: viewModel.workspaces,
          isBusy: isBusy,
          renamingWorkspaceId: renamingWorkspaceId,
          pendingDeleteWorkspaceId: pendingDeleteWorkspaceId,
          renameController: renameController,
          onSelectWorkspace: onSelectWorkspace,
          onStartRename: onStartRename,
          onCancelRename: onCancelRename,
          onSaveRename: onSaveRename,
          onRenameChanged: onRenameChanged,
          onRequestDelete: onRequestDelete,
          onCancelDelete: onCancelDelete,
          onConfirmDelete: onConfirmDelete,
        ),
        _WorkspaceErrorSlot(
          errorMessage: errorMessage,
          onDismiss: onDismissError,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12.0),
          child: Divider(height: 1.0),
        ),
        _WorkspaceCreateSection(
          controller: createController,
          canCreateMore: viewModel.canCreateMore,
          isBusy: isBusy,
          suggestedFileName: suggestedFileName,
          onChanged: onCreateChanged,
          onSubmit: onCreateSubmit,
        ),
      ],
    );
  }
}

/// Workspace entry card supporting switch tap, inline rename, and inline delete confirmation.
class _WorkspaceModalRowCard extends StatelessWidget {
  /// Creates a [_WorkspaceModalRowCard].
  const _WorkspaceModalRowCard({
    super.key,
    required this.row,
    required this.isBusy,
    required this.isRenaming,
    required this.isConfirmingDelete,
    required this.renameController,
    required this.onSelect,
    required this.onStartRename,
    required this.onCancelRename,
    required this.onSaveRename,
    required this.onRenameChanged,
    required this.onRequestDelete,
    required this.onCancelDelete,
    required this.onConfirmDelete,
  });

  /// Whether any workspace mutation is currently executing.
  final bool isBusy;

  /// Whether inline delete confirmation is open for this card.
  final bool isConfirmingDelete;

  /// Whether inline rename mode is open for this card.
  final bool isRenaming;

  /// Callback cancelling delete confirmation.
  final VoidCallback onCancelDelete;

  /// Callback cancelling inline rename.
  final VoidCallback onCancelRename;

  /// Callback confirming deletion of [row].
  final VoidCallback onConfirmDelete;

  /// Callback notified when rename input changes.
  final ValueChanged<String> onRenameChanged;

  /// Callback opening inline delete confirmation.
  final VoidCallback onRequestDelete;

  /// Callback saving inline rename.
  final VoidCallback onSaveRename;

  /// Callback switching to [row] when inactive.
  final VoidCallback onSelect;

  /// Callback opening inline rename mode.
  final VoidCallback onStartRename;

  /// Text controller used when [isRenaming] is true.
  final TextEditingController renameController;

  /// Workspace row projection.
  final WorkspaceRowViewModel row;

  @override
  Widget build(BuildContext context) {
    return UiCard.standard(
      isHighlighted: row.isActive,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (isRenaming)
            _WorkspaceInlineRenameRow(
              workspaceId: row.id,
              controller: renameController,
              isBusy: isBusy,
              onChanged: onRenameChanged,
              onCancel: onCancelRename,
              onSave: onSaveRename,
            )
          else
            _WorkspaceRowMainContent(
              row: row,
              isBusy: isBusy,
              onSelect: onSelect,
              onStartRename: onStartRename,
              onRequestDelete: onRequestDelete,
            ),
          if (isConfirmingDelete && row.canDelete)
            _WorkspaceDeleteConfirmBar(
              row: row,
              isBusy: isBusy,
              onCancel: onCancelDelete,
              onConfirm: onConfirmDelete,
            ),
        ],
      ),
    );
  }
}

/// Workspace title, active badge, and monospace `.tdf` filename column inside [_WorkspaceRowIdentity].
class _WorkspaceRowDetails extends StatelessWidget {
  /// Creates a [_WorkspaceRowDetails].
  const _WorkspaceRowDetails({required this.row});

  /// Workspace row projection.
  final WorkspaceRowViewModel row;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              row.name,
              style: tokens.typography.control.copyWith(
                color: colors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (row.isActive)
              UiPill(
                label: localizations.workspaceActiveBadge,
                variant: UiPillVariant.badge,
                tone: UiPillTone.accent,
              ),
          ],
        ),
        const SizedBox(height: 2.0),
        Text(
          row.localFileName,
          style: UiTypographyTokens.mono(
            tokens.typography.monoSmall.copyWith(color: colors.muted),
          ),
        ),
      ],
    );
  }
}

/// Workspace icon, display name, active badge, and monospace `.tdf` filename inside [_WorkspaceRowMainContent].
class _WorkspaceRowIdentity extends StatelessWidget {
  /// Creates a [_WorkspaceRowIdentity].
  const _WorkspaceRowIdentity({required this.row});

  /// Workspace row projection.
  final WorkspaceRowViewModel row;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Icon(
            row.isActive
                ? Icons.check_circle_outline_rounded
                : Icons.workspaces_outlined,
            size: tokens.spacing.iconSm,
            color: row.isActive ? colors.accent : colors.muted,
          ),
        ),
        const SizedBox(width: 10.0),
        Expanded(child: _WorkspaceRowDetails(row: row)),
      ],
    );
  }
}

/// Primary workspace row display pairing clickable workspace identity with Rename and Delete icon actions.
class _WorkspaceRowMainContent extends StatelessWidget {
  /// Creates a [_WorkspaceRowMainContent].
  const _WorkspaceRowMainContent({
    required this.row,
    required this.isBusy,
    required this.onSelect,
    required this.onStartRename,
    required this.onRequestDelete,
  });

  /// Whether a workspace mutation is currently executing.
  final bool isBusy;

  /// Callback opening inline delete confirmation.
  final VoidCallback onRequestDelete;

  /// Callback switching to [row] when inactive.
  final VoidCallback onSelect;

  /// Callback opening inline rename mode.
  final VoidCallback onStartRename;

  /// Workspace row projection.
  final WorkspaceRowViewModel row;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: _WorkspaceSelectableArea(
            row: row,
            canSwitch: !row.isActive && !isBusy,
            onSelect: onSelect,
          ),
        ),
        const SizedBox(width: 8.0),
        UiButton(
          key: ValueKey<String>('workspace_rename_button_${row.id}'),
          leadingIcon: Icons.edit_outlined,
          variant: UiButtonVariant.icon,
          density: UiButtonDensity.compact,
          tooltip: localizations.tooltipRenameWorkspace,
          onPressed: isBusy ? null : onStartRename,
        ),
        const SizedBox(width: 2.0),
        UiButton(
          key: ValueKey<String>('workspace_delete_button_${row.id}'),
          leadingIcon: Icons.delete_outline_rounded,
          variant: UiButtonVariant.icon,
          density: UiButtonDensity.compact,
          isDangerHover: true,
          tooltip: localizations.tooltipDeleteWorkspace,
          onPressed: (row.canDelete && !isBusy) ? onRequestDelete : null,
        ),
      ],
    );
  }
}

/// Interactive wrapper enabling pointer and keyboard activation only for inactive workspace rows.
class _WorkspaceSelectableArea extends StatelessWidget {
  /// Creates a [_WorkspaceSelectableArea].
  const _WorkspaceSelectableArea({
    required this.row,
    required this.canSwitch,
    required this.onSelect,
  });

  /// Whether tapping or activating this area switches workspaces.
  final bool canSwitch;

  /// Switch callback.
  final VoidCallback onSelect;

  /// Workspace row projection.
  final WorkspaceRowViewModel row;

  @override
  Widget build(BuildContext context) {
    final identity = _WorkspaceRowIdentity(row: row);
    if (!canSwitch) {
      return KeyedSubtree(
        key: ValueKey<String>('workspace_select_${row.id}'),
        child: identity,
      );
    }
    return Semantics(
      button: true,
      label: row.name,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onSelect();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              onSelect();
              return null;
            },
          ),
        },
        child: GestureDetector(
          key: ValueKey<String>('workspace_select_${row.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: onSelect,
          child: identity,
        ),
      ),
    );
  }
}

/// Centered modal managing isolated workspaces (switch, create, inline rename, and inline delete).
class _WorkspacesModal extends ConsumerStatefulWidget {
  /// Creates a [_WorkspacesModal].
  const _WorkspacesModal({required this.onClose});

  /// Callback closing this modal route.
  final VoidCallback onClose;

  @override
  ConsumerState<_WorkspacesModal> createState() => _WorkspacesModalState();
}

/// State managing inline rename, inline delete confirmation, creation input, and error readout for [_WorkspacesModal].
class _WorkspacesModalState extends ConsumerState<_WorkspacesModal> {
  final TextEditingController _createController = TextEditingController();
  String? _errorMessage;
  String? _pendingDeleteWorkspaceId;
  final TextEditingController _renameController = TextEditingController();
  String? _renamingWorkspaceId;

  @override
  void dispose() {
    _createController.dispose();
    _renameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final viewModel = ref.watch(workspacesViewModelProvider);
    final controllerState = ref.watch(workspaceV2ControllerProvider);
    final suggestedFileName = ref
        .read(workspaceV2ControllerProvider.notifier)
        .suggestWorkspaceFileName(_createController.text);

    return UiDialogFrame(
      key: const ValueKey<String>('workspaces_modal'),
      title: localizations.workspacesDialogTitle,
      subtitle: localizations.workspacesDialogDescription,
      size: UiDialogSize.large,
      closeTooltip: localizations.actionClose,
      onClose: widget.onClose,
      body: _WorkspaceModalBody(
        viewModel: viewModel,
        isBusy: controllerState.isBusy,
        renamingWorkspaceId: _renamingWorkspaceId,
        pendingDeleteWorkspaceId: _pendingDeleteWorkspaceId,
        errorMessage: _errorMessage,
        createController: _createController,
        renameController: _renameController,
        suggestedFileName: suggestedFileName,
        onSelectWorkspace: _triggerSwitchWorkspace,
        onStartRename: _handleStartRename,
        onCancelRename: _handleCancelRename,
        onSaveRename: _triggerSaveRename,
        onRenameChanged: _handleRenameInputChanged,
        onRequestDelete: _handleRequestDelete,
        onCancelDelete: _handleCancelDelete,
        onConfirmDelete: _triggerConfirmDelete,
        onCreateChanged: _handleCreateInputChanged,
        onCreateSubmit: _triggerCreateWorkspace,
        onDismissError: _clearError,
      ),
    );
  }

  /// Dismisses any visible workspace error banner.
  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  /// Cancels an active inline delete confirmation bar.
  void _handleCancelDelete() {
    setState(() => _pendingDeleteWorkspaceId = null);
  }

  /// Exits inline rename mode without saving.
  void _handleCancelRename() {
    setState(() {
      _renamingWorkspaceId = null;
      _renameController.clear();
    });
  }

  /// Deletes [workspaceId] via [WorkspaceV2Controller] and clears confirmation on success.
  Future<void> _handleConfirmDelete(String workspaceId) async {
    _clearError();
    final result = await ref
        .read(workspaceV2ControllerProvider.notifier)
        .deleteWorkspace(workspaceId);
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        setState(() {
          _pendingDeleteWorkspaceId = null;
          if (_renamingWorkspaceId == workspaceId) {
            _renamingWorkspaceId = null;
            _renameController.clear();
          }
        });
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        _showError(message);
    }
  }

  /// Updates live `.tdf` filename suggestion and clears errors when create text changes.
  void _handleCreateInputChanged(String _) {
    setState(() => _errorMessage = null);
  }

  /// Creates and activates a workspace from [_createController], closing the modal on success.
  Future<void> _handleCreateWorkspace() async {
    _clearError();
    final result = await ref
        .read(workspaceV2ControllerProvider.notifier)
        .createWorkspace(_createController.text, activate: true);
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        widget.onClose();
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        _showError(message);
    }
  }

  /// Clears errors when inline rename text changes.
  void _handleRenameInputChanged(String _) {
    _clearError();
  }

  /// Opens inline delete confirmation for [workspaceId].
  void _handleRequestDelete(String workspaceId) {
    setState(() {
      _renamingWorkspaceId = null;
      _pendingDeleteWorkspaceId = workspaceId;
      _errorMessage = null;
    });
  }

  /// Saves inline rename for [workspaceId] via [WorkspaceV2Controller].
  Future<void> _handleSaveRename(String workspaceId) async {
    _clearError();
    final result = await ref
        .read(workspaceV2ControllerProvider.notifier)
        .renameWorkspace(workspaceId, _renameController.text);
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        setState(() {
          _renamingWorkspaceId = null;
          _renameController.clear();
        });
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        _showError(message);
    }
  }

  /// Opens inline rename mode pre-filled with [row.name].
  void _handleStartRename(WorkspaceRowViewModel row) {
    setState(() {
      _pendingDeleteWorkspaceId = null;
      _errorMessage = null;
      _renamingWorkspaceId = row.id;
      _renameController.value = TextEditingValue(
        text: row.name,
        selection: TextSelection.collapsed(offset: row.name.length),
      );
    });
  }

  /// Switches the active workspace to [workspaceId] and closes the modal on success.
  Future<void> _handleSwitchWorkspace(String workspaceId) async {
    _clearError();
    final result = await ref
        .read(workspaceV2ControllerProvider.notifier)
        .switchWorkspace(workspaceId);
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        widget.onClose();
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        _showError(message);
    }
  }

  /// Displays non-empty validation or persistence error messages inline.
  void _showError(String message) {
    if (message.isNotEmpty) {
      setState(() => _errorMessage = message);
    }
  }

  /// Dispatches async deletion for [workspaceId] from synchronous callbacks.
  void _triggerConfirmDelete(String workspaceId) {
    _handleConfirmDelete(workspaceId);
  }

  /// Dispatches async creation from synchronous callbacks.
  void _triggerCreateWorkspace() {
    _handleCreateWorkspace();
  }

  /// Dispatches async rename save for [workspaceId] from synchronous callbacks.
  void _triggerSaveRename(String workspaceId) {
    _handleSaveRename(workspaceId);
  }

  /// Dispatches async workspace switch for [workspaceId] from synchronous callbacks.
  void _triggerSwitchWorkspace(String workspaceId) {
    _handleSwitchWorkspace(workspaceId);
  }
}

/// Presents the focus-trapped compact mobile label picker bottom sheet without search auto-focus (`U-A11Y-003`).
Future<void> showCompactLabelPickerSheet(
  BuildContext context, {
  required String title,
  required List<LabelPickerOptionViewModel> allLabels,
  required bool hasBothScopedAndGlobal,
  required Set<String> selectedIds,
  required ValueChanged<String> onToggleLabel,
  required ValueChanged<String> onCreateAndAssign,
  required ValueChanged<String> onOpenLabelInfo,
}) {
  UiTelemetry.logDialogOpened('label_picker_sheet');
  final localizations = AppLocalizations.of(context);
  return UiDialogFrame.showBottomSheet<void>(
    context: context,
    title: title,
    icon: Icons.label_outline_rounded,
    countLabel: '${selectedIds.length}',
    doneLabel: localizations.actionDone,
    barrierLabel: title,
    builder: (modalContext) => _CompactLabelPickerSheetBody(
      initialLabels: allLabels,
      hasBothScopedAndGlobal: hasBothScopedAndGlobal,
      initialSelectedIds: selectedIds,
      onToggleLabel: onToggleLabel,
      onCreateAndAssign: onCreateAndAssign,
      onOpenLabelInfo: onOpenLabelInfo,
      onRequestClose: () => Navigator.of(modalContext).maybePop(),
    ),
  );
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

/// Presents the local `.tdf` file rename modal pre-filled with [currentFileName].
Future<void> showRenameLocalFileModal(
  BuildContext context, {
  required String currentFileName,
}) {
  UiTelemetry.logDialogOpened('rename_local_file');
  final localizations = AppLocalizations.of(context);
  return UiDialogFrame.showModal<void>(
    context: context,
    barrierLabel: localizations.renameLocalDialogTitle,
    builder: (modalContext) => _RenameLocalFileModal(
      currentFileName: currentFileName,
      onClose: () => Navigator.of(modalContext).maybePop(),
    ),
  );
}

/// Presents the local `.tdf` file selection modal combining discovered files and new filename input.
Future<void> showSelectLocalFileModal(BuildContext context) {
  UiTelemetry.logDialogOpened('select_local_file');
  final localizations = AppLocalizations.of(context);
  return UiDialogFrame.showModal<void>(
    context: context,
    barrierLabel: localizations.selectLocalDialogTitle,
    builder: (modalContext) => _SelectLocalFileModal(
      onClose: () => Navigator.of(modalContext).maybePop(),
    ),
  );
}

/// Presents the typed-filename destructive confirmation modal for wiping a local or remote `.tdf` file (`U-UX-005`).
Future<void> showWipeTdfModal(
  BuildContext context, {
  required bool isRemote,
  required String fileName,
  required String baseName,
}) {
  UiTelemetry.logDialogOpened(isRemote ? 'wipe_remote_tdf' : 'wipe_local_tdf');
  final localizations = AppLocalizations.of(context);
  return UiDialogFrame.showModal<void>(
    context: context,
    barrierLabel: isRemote
        ? localizations.wipeRemoteDialogTitle
        : localizations.wipeLocalDialogTitle,
    builder: (modalContext) => _WipeTdfModal(
      isRemote: isRemote,
      fileName: fileName,
      baseName: baseName,
      onClose: () => Navigator.of(modalContext).maybePop(),
    ),
  );
}

/// Presents the isolated workspaces manager modal supporting switching, creation, inline rename, and inline deletion.
Future<void> showWorkspacesModal(BuildContext context) {
  UiTelemetry.logDialogOpened('workspaces');
  final localizations = AppLocalizations.of(context);
  return UiDialogFrame.showModal<void>(
    context: context,
    barrierLabel: localizations.workspacesDialogTitle,
    builder: (modalContext) =>
        _WorkspacesModal(onClose: () => Navigator.of(modalContext).maybePop()),
  );
}

/// Returns `true` when [value] contains ASCII control characters (`0x00..0x1F`) or `DEL` (`0x7F`).
bool _containsControlCharacters(String value) {
  for (var i = 0; i < value.length; i++) {
    final codeUnit = value.codeUnitAt(i);
    if (codeUnit < 0x20 || codeUnit == 0x7F) {
      return true;
    }
  }
  return false;
}

/// Returns `true` when any option in [labels] matches [trimmedName] case-insensitively.
bool _hasLabelNamed(
  List<LabelPickerOptionViewModel> labels,
  String trimmedName,
) {
  if (trimmedName.isEmpty) {
    return false;
  }
  final normalized = trimmedName.toLowerCase();
  for (final label in labels) {
    if (label.name.trim().toLowerCase() == normalized) {
      return true;
    }
  }
  return false;
}

/// Validates that [rawValue] is a safe single local `.tdf` filename without path separators, `..`, or control characters.
bool _isValidLocalFileName(String rawValue) {
  if (_containsControlCharacters(rawValue)) {
    return false;
  }
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty ||
      trimmed == '.' ||
      trimmed == '..' ||
      trimmed.contains('/') ||
      trimmed.contains(r'\') ||
      trimmed.contains('..')) {
    return false;
  }
  return _stripTdfExtension(trimmed).isNotEmpty;
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

/// Normalizes a trimmed filename by appending `.tdf` when absent so picker selection highlights consistently.
String _normalizeTdfFileName(String rawValue) {
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (trimmed.toLowerCase().endsWith('.tdf')) {
    return trimmed;
  }
  return '$trimmed.tdf';
}

/// Removes a trailing `.tdf` extension case-insensitively when present.
String _stripTdfExtension(String fileName) {
  final trimmed = fileName.trim();
  if (trimmed.length >= 4 && trimmed.toLowerCase().endsWith('.tdf')) {
    return trimmed.substring(0, trimmed.length - 4);
  }
  return trimmed;
}
