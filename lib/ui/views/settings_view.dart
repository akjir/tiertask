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
import '../../models/app_workspace.dart';
import '../../models/tdf_file_path.dart';
import '../../models/webdav_config.dart';
import '../../providers/config_providers.dart';
import '../../providers/log_viewer_providers.dart';
import '../../providers/settings_draft_providers.dart';
import '../../providers/shell_providers.dart';
import '../../providers/workspace_providers.dart';
import '../../services/app_logger.dart';
import '../dialogs/local_file_modals.dart';
import '../dialogs/wipe_tdf_modal.dart';
import '../layout/ui_page_header.dart';
import '../layout/ui_responsive_grid.dart';
import '../primitives/ui_banner.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../primitives/ui_field.dart';
import '../primitives/ui_pill.dart';
import '../primitives/ui_segmented_control.dart';
import '../primitives/ui_toggle_row.dart';
import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';
import '../ui_domain_mappers.dart';

/// Identifies one of the four local `.tdf` file management action buttons in [_LocalActionsGrid].
enum _LocalStorageActionKind {
  /// Selects an existing or new local `.tdf` file via native picker or in-app modal.
  select,

  /// Moves the active local `.tdf` file to another directory (desktop-only).
  move,

  /// Renames the active local `.tdf` file.
  rename,

  /// Destructively wipes the active local `.tdf` file via typed-filename confirmation.
  wipe,
}

/// Identifies one of the four auto-saved segmented preference cards in [_SettingsPreferenceGrid].
enum _SegmentedPreferenceKind {
  /// Display language preference (`System` / `English` / `Deutsch`).
  language,

  /// Color brightness preference (`System` / `Light` / `Dark`).
  appearance,

  /// Design-system color palette preference (`Calm` / `Plum Umber`).
  colorPalette,

  /// Foreground location determination toggle (`Off` / `On`).
  foregroundLocation,
}

/// Identifies one of the four WebDAV credential and remote path draft fields.
enum _WebDavFieldKind {
  /// WebDAV base server URL.
  serverUrl,

  /// WebDAV authentication username.
  username,

  /// WebDAV authentication password.
  password,

  /// Relative remote `.tdf` file path.
  filePath,
}

/// Pinned bottom dock footer hosting conditional `Unsaved changes` pill, `Save`,
/// and `Test Connection / Sync Now` buttons decoupled outside the Settings scroll region (`U-LAYOUT-006`, `U-UX-006`).
class SettingsActionDock extends ConsumerWidget {
  /// Creates a [SettingsActionDock].
  const SettingsActionDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = UiThemeTokens.of(context).spacing.space2;
    final usesWebDav = _watchConfigSlice<bool>(
      ref,
      (config) => config.storageMode.usesWebDav,
      fallback: false,
    );
    final draft = ref.watch(settingsDraftProvider.select(_selectDockDraft));
    final canAct = usesWebDav && !draft.isBusy;

    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: spacing,
        runSpacing: spacing,
        children: <Widget>[
          _SettingsDockUnsavedBadge(isVisible: draft.isDirty),
          _SettingsDockButtons(
            canSave: canAct,
            canTestConnectionAndSync: canAct,
            isDirty: draft.isDirty,
            isSaving: draft.isSavingWebDav,
            isTestingSync: draft.isTestingConnection,
            onSave: () => _handleSave(context, ref),
            onTestAndSync: () => _handleTestAndSync(context, ref),
          ),
        ],
      ),
    );
  }

  /// Validates and persists the WebDAV draft via [SettingsDraftNotifier.saveWebDavDraft].
  void _handleSave(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref.read(settingsDraftProvider.notifier).saveWebDavDraft(locale: locale),
    );
  }

  /// Validates and tests WebDAV synchronization via [SettingsDraftNotifier.testConnectionAndSync].
  void _handleTestAndSync(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsDraftProvider.notifier)
          .testConnectionAndSync(locale: locale),
    );
  }
}

/// Dual-persistence workspace Settings view with auto-saved preference cards, capability-gated
/// Local TDF management, and explicit WebDAV draft synchronization (`U-LAYOUT-006`, `U-UX-006`).
class SettingsView extends ConsumerStatefulWidget {
  /// Creates a [SettingsView].
  const SettingsView({super.key, this.scrollController});

  /// Optional caller-owned scroll controller preserving scroll offset across state updates.
  final ScrollController? scrollController;

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

/// Granular auto-saved dropdown selector watching one narrow [WebDavConfig] slice.
class _ConfigSelectField<T extends Object> extends ConsumerWidget {
  /// Creates a [_ConfigSelectField].
  const _ConfigSelectField({
    required this.fieldKey,
    required this.label,
    required this.select,
    required this.fallback,
    required this.formatValue,
    required this.options,
    required this.parseValue,
    required this.onCommit,
  });

  /// Fallback value used while workspace configuration loads.
  final T fallback;

  /// Stable key assigned to the underlying [UiField].
  final Key fieldKey;

  /// Converts the selected [T] value into the matching option string value.
  final String Function(T value) formatValue;

  /// Localized visible field label.
  final String label;

  /// Persists the parsed selection through [WebDavConfigNotifier].
  final Future<void> Function(WebDavConfigNotifier notifier, T value) onCommit;

  /// Selectable dropdown options.
  final List<UiSelectOption> options;

  /// Safely parses a selected option string back into [T].
  final T? Function(String raw) parseValue;

  /// Narrow [WebDavConfig] selector preserving rebuild isolation.
  final T Function(WebDavConfig config) select;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentValue = _watchConfigSlice<T>(ref, select, fallback: fallback);

    return UiField(
      key: fieldKey,
      kind: UiFieldKind.select,
      label: label,
      selectValue: formatValue(currentValue),
      selectOptions: options,
      onSelectChanged: (raw) {
        final parsed = parseValue(raw);
        if (parsed != null) {
          _saveConfigPreference(
            context,
            ref,
            (notifier) => onCommit(notifier, parsed),
          );
        }
      },
    );
  }
}

/// Auto-saved per-workspace deadline lead-window prioritization card.
class _DeadlinePrioritizationCard extends StatelessWidget {
  /// Creates a [_DeadlinePrioritizationCard].
  const _DeadlinePrioritizationCard();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_due_lead_card'),
      icon: Icons.bolt_outlined,
      title: localizations.dueLeadWindowSectionTitle,
      description: localizations.dueLeadWindowSectionDescription,
      child: _ConfigSelectField<DueLeadWindow>(
        fieldKey: const ValueKey<String>('settings_due_lead_select'),
        label: localizations.dueLeadWindowLabel,
        select: (config) => config.dueLeadWindow,
        fallback: DueLeadWindow.hours24,
        formatValue: (window) => window.name,
        options: _dueLeadOptions(localizations),
        parseValue: (raw) => _parseEnumByName(raw, DueLeadWindow.values),
        onCommit: (notifier, value) => notifier.updateDueLeadWindow(value),
      ),
    );
  }
}

/// Auto-saved diagnostic logging card with checkbox toggle and conditional log controls.
class _DiagnosticsCard extends ConsumerWidget {
  /// Creates a [_DiagnosticsCard].
  const _DiagnosticsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final diagnosticsEnabled = _watchConfigSlice<bool>(
      ref,
      (config) => config.diagnosticsEnabled,
      fallback: false,
    );

    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_diagnostics_card'),
      icon: Icons.bug_report_outlined,
      title: localizations.diagnosticLogTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          UiToggleRow(
            key: const ValueKey<String>('settings_diagnostics_toggle'),
            label: localizations.diagnosticsSectionTitle,
            description: localizations.diagnosticsSectionDescription,
            value: diagnosticsEnabled,
            onChanged: (enabled) => _saveConfigPreference(
              context,
              ref,
              (notifier) => notifier.updateDiagnosticsEnabled(enabled),
            ),
          ),
          if (diagnosticsEnabled) ...<Widget>[
            SizedBox(height: tokens.spacing.space3),
            const _DiagnosticsDetailsPanel(),
          ],
        ],
      ),
    );
  }
}

/// Conditional diagnostic level, storage, and viewer trigger controls inside [_DiagnosticsCard].
class _DiagnosticsDetailsPanel extends StatelessWidget {
  /// Creates a [_DiagnosticsDetailsPanel].
  const _DiagnosticsDetailsPanel();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final spacing = UiThemeTokens.of(context).spacing.space3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ConfigSelectField<LogLevel>(
          fieldKey: const ValueKey<String>('settings_log_level_select'),
          label: localizations.logLevelLabel,
          select: (config) => config.logLevel,
          fallback: LogLevel.info,
          formatValue: (level) => level.name,
          options: _logLevelOptions(localizations),
          parseValue: (raw) =>
              _parseEnumByName(raw, configurableDiagnosticLogLevels),
          onCommit: (notifier, value) => notifier.updateLogLevel(value),
        ),
        SizedBox(height: spacing),
        _ConfigSelectField<StorageMode>(
          fieldKey: const ValueKey<String>('settings_log_storage_select'),
          label: localizations.logStorageLabel,
          select: (config) => config.logStorageMode,
          fallback: StorageMode.local,
          formatValue: (mode) => mode.name,
          options: _logStorageOptions(localizations),
          parseValue: (raw) => _parseEnumByName(raw, StorageMode.values),
          onCommit: (notifier, value) => notifier.updateLogStorageMode(value),
        ),
        SizedBox(height: spacing),
        const _DiagnosticsLogFooter(),
      ],
    );
  }
}

/// Active diagnostic log filename readout and viewer trigger button inside [_DiagnosticsDetailsPanel].
class _DiagnosticsLogFooter extends ConsumerWidget {
  /// Creates a [_DiagnosticsLogFooter].
  const _DiagnosticsLogFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final activeLogFileName = ref.watch(activeLogFileNameProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (activeLogFileName.isNotEmpty) ...<Widget>[
          Text(
            localizations.logMetadataFile(activeLogFileName),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UiTypographyTokens.mono(
              tokens.typography.monoSmall.copyWith(color: tokens.colors.muted),
            ),
          ),
          SizedBox(height: tokens.spacing.space2),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: UiButton(
            key: const ValueKey<String>('settings_open_log_viewer_button'),
            label: localizations.diagnosticLogButton,
            leadingIcon: Icons.bug_report_outlined,
            density: UiButtonDensity.compact,
            onPressed: () =>
                ref.read(shellProvider.notifier).openView(ShellView.logs),
          ),
        ),
      ],
    );
  }
}

/// Responsive 4-column (`2x2` compact) action button grid for local `.tdf` file management.
class _LocalActionsGrid extends StatelessWidget {
  /// Creates a [_LocalActionsGrid].
  const _LocalActionsGrid();

  @override
  Widget build(BuildContext context) {
    final gap = UiThemeTokens.of(context).spacing.space2;

    return UiResponsiveGrid(
      key: const ValueKey<String>('settings_local_actions_grid'),
      preset: UiGridPreset.fourActionCompactTwo,
      spacing: gap,
      runSpacing: gap,
      children: const <Widget>[
        _LocalStorageActionButton(kind: _LocalStorageActionKind.select),
        _LocalStorageActionButton(kind: _LocalStorageActionKind.move),
        _LocalStorageActionButton(kind: _LocalStorageActionKind.rename),
        _LocalStorageActionButton(kind: _LocalStorageActionKind.wipe),
      ],
    );
  }
}

/// Read-only resolved local `.tdf` path preview inside [_LocalStorageCard].
class _LocalResolvedPathField extends ConsumerWidget {
  /// Creates a [_LocalResolvedPathField].
  const _LocalResolvedPathField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final resolvedLocalPath = ref.watch(
      settingsDraftProvider.select(
        (draft) => draft.resolvedLocalPathPreview ?? '',
      ),
    );

    return UiField(
      key: const ValueKey<String>('settings_resolved_local_path_field'),
      kind: UiFieldKind.readOnlyDisplay,
      label: localizations.resolvedLocalPathLabel,
      displayValue: resolvedLocalPath,
    );
  }
}

/// Parameterized local `.tdf` file action button watching only the slices required by [kind] (`U-UX-006`).
class _LocalStorageActionButton extends ConsumerWidget {
  /// Creates a [_LocalStorageActionButton].
  const _LocalStorageActionButton({required this.kind});

  /// Specific local storage action rendered by this cell.
  final _LocalStorageActionKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final isBusy = ref.watch(
      settingsDraftProvider.select((draft) => draft.isBusy),
    );
    final supportsPicker = _watchSupportsPicker(ref);
    final localFilePath = _watchLocalFilePath(ref);
    final spec = _localActionSpec(
      kind,
      localizations: localizations,
      isBusy: isBusy,
      supportsDirectoryPicker: supportsPicker,
    );

    return UiButton(
      key: spec.buttonKey,
      label: spec.label,
      semanticLabel: spec.semanticLabel,
      leadingIcon: spec.icon,
      variant: spec.variant,
      density: UiButtonDensity.compact,
      isFullWidth: true,
      tooltip: spec.tooltip,
      onPressed: spec.enabled
          ? () => _dispatchLocalStorageAction(
              context,
              ref,
              kind: kind,
              supportsDirectoryPicker: supportsPicker,
              localFilePath: localFilePath,
            )
          : null,
    );
  }

  /// Watches [WebDavConfig.localFilePath] only for actions that need the active filename.
  String _watchLocalFilePath(WidgetRef ref) {
    final needsPath =
        kind == _LocalStorageActionKind.rename ||
        kind == _LocalStorageActionKind.wipe;
    if (!needsPath) {
      return WebDavConfig.defaultFileName;
    }
    return _watchConfigSlice<String>(
      ref,
      (config) => config.localFilePath,
      fallback: WebDavConfig.defaultFileName,
    );
  }

  /// Watches [supportsDirectoryPickerProvider] only for capability-gated picker actions.
  bool _watchSupportsPicker(WidgetRef ref) {
    final needsCapability =
        kind == _LocalStorageActionKind.select ||
        kind == _LocalStorageActionKind.move;
    return needsCapability && ref.watch(supportsDirectoryPickerProvider);
  }
}

/// Full-width auto-saved Local TDF File card with resolved path, capability-gated actions, and desktop file watch toggle.
class _LocalStorageCard extends ConsumerWidget {
  /// Creates a [_LocalStorageCard].
  const _LocalStorageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final gap = UiThemeTokens.of(context).spacing.space3;
    final supportsLocalFileWatch = ref.watch(supportsLocalFileWatchProvider);

    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_local_card'),
      icon: Icons.folder_outlined,
      title: localizations.localSectionTitle,
      description: localizations.localSectionDescription,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const _LocalResolvedPathField(),
          SizedBox(height: gap),
          const _LocalActionsGrid(),
          if (supportsLocalFileWatch) ...<Widget>[
            SizedBox(height: gap),
            const _LocalWatchToggle(),
          ],
        ],
      ),
    );
  }
}

/// Auto-saved external local file watching checkbox row inside [_LocalStorageCard].
class _LocalWatchToggle extends ConsumerWidget {
  /// Creates a [_LocalWatchToggle].
  const _LocalWatchToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final localWatchEnabled = _watchConfigSlice<bool>(
      ref,
      (config) => config.localWatchEnabled,
      fallback: true,
    );
    final isStorageOperationBusy = ref.watch(
      settingsDraftProvider.select((draft) => draft.isStorageOperationBusy),
    );

    return UiToggleRow(
      key: const ValueKey<String>('settings_local_watch_toggle'),
      label: localizations.localWatchLabel,
      description: localizations.localWatchDescription,
      value: localWatchEnabled,
      enabled: !isStorageOperationBusy,
      onChanged: (enabled) => _saveConfigPreference(
        context,
        ref,
        (notifier) => notifier.updateLocalWatchEnabled(enabled),
      ),
    );
  }
}

/// Granular auto-saved segmented preference card watching one narrow [WebDavConfig] slice.
class _SegmentedPreferenceCard<T extends Object> extends ConsumerWidget {
  /// Creates a [_SegmentedPreferenceCard].
  const _SegmentedPreferenceCard({required this.spec});

  /// Static card metadata, config slice selector, segments, and commit mutation.
  final _SegmentedPreferenceSpec<T> spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentValue = _watchConfigSlice<T>(
      ref,
      spec.select,
      fallback: spec.fallback,
    );

    return _SettingsAutoSavedCard(
      cardKey: spec.cardKey,
      icon: spec.icon,
      title: spec.title,
      description: spec.description,
      child: UiSegmentedControl<T>(
        key: spec.controlKey,
        value: currentValue,
        semanticLabel: spec.title,
        segments: spec.segments,
        onChanged: (next) => _saveConfigPreference(
          context,
          ref,
          (notifier) => spec.onCommit(notifier, next),
        ),
      ),
    );
  }
}

/// Dispatches one of the four simple segmented preference cards to [_SegmentedPreferenceCard].
class _SegmentedPreferenceCardSlot extends StatelessWidget {
  /// Creates a [_SegmentedPreferenceCardSlot].
  const _SegmentedPreferenceCardSlot({required this.kind});

  /// Preference card variant rendered by this slot.
  final _SegmentedPreferenceKind kind;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return switch (kind) {
      _SegmentedPreferenceKind.language =>
        _SegmentedPreferenceCard<AppLanguage>(
          spec: _languageCardSpec(localizations),
        ),
      _SegmentedPreferenceKind.appearance =>
        _SegmentedPreferenceCard<AppThemeMode>(
          spec: _appearanceCardSpec(localizations),
        ),
      _SegmentedPreferenceKind.colorPalette =>
        _SegmentedPreferenceCard<AppThemePalette>(
          spec: _colorPaletteCardSpec(localizations),
        ),
      _SegmentedPreferenceKind.foregroundLocation =>
        _SegmentedPreferenceCard<bool>(spec: _locationCardSpec(localizations)),
    };
  }
}

/// Shared flat `UiCard.standard` shell for auto-saved Settings cards carrying the `Auto-saved` pill badge.
class _SettingsAutoSavedCard extends StatelessWidget {
  /// Creates a [_SettingsAutoSavedCard].
  const _SettingsAutoSavedCard({
    required this.cardKey,
    required this.icon,
    required this.title,
    required this.child,
    this.description,
  });

  /// Stable key attached to the outer [UiCard].
  final Key cardKey;

  /// Interactive preference control body.
  final Widget child;

  /// Optional muted explanatory paragraph above [child].
  final String? description;

  /// Leading outline header icon.
  final IconData icon;

  /// Localized card heading title.
  final String title;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiCard.standard(
      key: cardKey,
      headerIcon: icon,
      headerTitle: title,
      headerBadge: UiPill(label: localizations.settingsAutoSavedBadge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (description case final copy?) ...<Widget>[
            Text(
              copy,
              style: tokens.typography.meta.copyWith(
                color: tokens.colors.muted,
              ),
            ),
            SizedBox(height: tokens.spacing.space3),
          ],
          child,
        ],
      ),
    );
  }
}

/// Right-aligned button cluster inside [SettingsActionDock] swapping primary emphasis on dirty state.
class _SettingsDockButtons extends StatelessWidget {
  /// Creates a [_SettingsDockButtons].
  const _SettingsDockButtons({
    required this.canSave,
    required this.canTestConnectionAndSync,
    required this.isDirty,
    required this.isSaving,
    required this.isTestingSync,
    required this.onSave,
    required this.onTestAndSync,
  });

  /// Whether the `Save` button is enabled.
  final bool canSave;

  /// Whether the `Test Connection / Sync Now` button is enabled.
  final bool canTestConnectionAndSync;

  /// Whether transient WebDAV edits are uncommitted (`U-UX-006`).
  final bool isDirty;

  /// Whether `Save` is currently executing.
  final bool isSaving;

  /// Whether `Test Connection / Sync Now` is currently executing.
  final bool isTestingSync;

  /// Callback saving the WebDAV draft.
  final VoidCallback onSave;

  /// Callback testing connection and synchronizing with WebDAV.
  final VoidCallback onTestAndSync;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: tokens.spacing.space2,
      runSpacing: tokens.spacing.space2,
      children: <Widget>[
        UiButton(
          key: const ValueKey<String>('settings_dock_save_button'),
          label: localizations.actionSave,
          variant: isDirty
              ? UiButtonVariant.primary
              : UiButtonVariant.secondary,
          leadingIcon: isSaving ? Icons.sync_rounded : null,
          isLoading: isSaving,
          onPressed: canSave ? onSave : null,
        ),
        UiButton(
          key: const ValueKey<String>('settings_dock_test_sync_button'),
          label: localizations.actionTestConnectionAndSync,
          leadingIcon: Icons.sync_rounded,
          variant: isDirty
              ? UiButtonVariant.secondary
              : UiButtonVariant.primary,
          isLoading: isTestingSync,
          onPressed: canTestConnectionAndSync ? onTestAndSync : null,
        ),
      ],
    );
  }
}

/// Conditional warning pill rendered on the left side of [SettingsActionDock] when WebDAV is dirty.
class _SettingsDockUnsavedBadge extends StatelessWidget {
  /// Creates a [_SettingsDockUnsavedBadge].
  const _SettingsDockUnsavedBadge({required this.isVisible});

  /// Whether the unsaved-changes badge is shown.
  final bool isVisible;

  @override
  Widget build(BuildContext context) {
    if (!isVisible) {
      return const SizedBox.shrink();
    }
    return UiPill(
      key: const ValueKey<String>('settings_dock_unsaved_badge'),
      label: AppLocalizations.of(context).settingsUnsavedChangesBadge,
      tone: UiPillTone.warning,
    );
  }
}

/// Workspace-scoped page header watching only the active workspace display name.
class _SettingsHeader extends ConsumerWidget {
  /// Creates a [_SettingsHeader].
  const _SettingsHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final workspaceName = ref.watch(
      activeWorkspaceProvider.select(
        (workspace) => workspace.asData?.value.name ?? AppWorkspace.defaultName,
      ),
    );

    return UiPageHeader(
      backLabel: localizations.actionBackToTasks,
      onBack: () => ref.read(shellProvider.notifier).openView(ShellView.tasks),
      title: localizations.settingsTitle,
      subtitle: localizations.settingsWorkspaceSubtitle(workspaceName),
    );
  }
}

/// Responsive 2-column (`> 820px`) grid of all 8 auto-saved Settings preference cards (`U-LAYOUT-006`).
class _SettingsPreferenceGrid extends StatelessWidget {
  /// Creates a [_SettingsPreferenceGrid].
  const _SettingsPreferenceGrid();

  @override
  Widget build(BuildContext context) {
    return const UiResponsiveGrid(
      key: ValueKey<String>('settings_preferences_grid'),
      preset: UiGridPreset.twoColumnMediumCollapse,
      children: <Widget>[
        _SegmentedPreferenceCardSlot(kind: _SegmentedPreferenceKind.language),
        _SegmentedPreferenceCardSlot(kind: _SegmentedPreferenceKind.appearance),
        _SegmentedPreferenceCardSlot(
          kind: _SegmentedPreferenceKind.colorPalette,
        ),
        _TimeZoneCard(),
        _DeadlinePrioritizationCard(),
        _SegmentedPreferenceCardSlot(
          kind: _SegmentedPreferenceKind.foregroundLocation,
        ),
        _DiagnosticsCard(),
        _StorageModeCard(),
      ],
    );
  }
}

/// Scrollable column body assembling header, optional status banner, preference grid, and storage cards.
class _SettingsScrollContent extends StatelessWidget {
  /// Creates a [_SettingsScrollContent].
  const _SettingsScrollContent({required this.webDavControllers});

  /// Bundle owning the four WebDAV text controllers.
  final _WebDavFieldControllers webDavControllers;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _SettingsHeader(),
        const _SettingsStatusBannerHost(),
        SizedBox(height: tokens.spacing.space4),
        const _SettingsPreferenceGrid(),
        _SettingsStorageSections(webDavControllers: webDavControllers),
      ],
    );
  }
}

/// Scoped status banner host watching only [SettingsDraftState.statusBanner].
class _SettingsStatusBannerHost extends ConsumerWidget {
  /// Creates a [_SettingsStatusBannerHost].
  const _SettingsStatusBannerHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusBanner = ref.watch(
      settingsDraftProvider.select((draft) => draft.statusBanner),
    );
    if (statusBanner == null) {
      return const SizedBox.shrink();
    }
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.space3),
      child: UiBanner(
        key: const ValueKey<String>('settings_status_banner'),
        variant: UiBannerVariant.status,
        tone: UiDomainMappers.settingsBannerTone(statusBanner.tone),
        message: statusBanner.message,
        dismissTooltip: localizations.actionDismiss,
        onDismiss: () =>
            ref.read(settingsDraftProvider.notifier).dismissStatusBanner(),
      ),
    );
  }
}

/// Conditional Local and WebDAV storage section host watching only [WebDavConfig.storageMode].
class _SettingsStorageSections extends ConsumerWidget {
  /// Creates a [_SettingsStorageSections].
  const _SettingsStorageSections({required this.webDavControllers});

  /// Bundle owning the four WebDAV text controllers.
  final _WebDavFieldControllers webDavControllers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gap = UiThemeTokens.of(context).spacing.sectionGridGap;
    final storageMode = _watchConfigSlice<StorageMode>(
      ref,
      (config) => config.storageMode,
      fallback: StorageMode.local,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (storageMode.usesLocal) ...<Widget>[
          SizedBox(height: gap),
          const _LocalStorageCard(),
        ],
        if (storageMode.usesWebDav) ...<Widget>[
          SizedBox(height: gap),
          _WebDavStorageCard(controllers: webDavControllers),
        ],
      ],
    );
  }
}

/// Manages WebDAV [TextEditingController] lifecycles and external draft sync for [SettingsView].
class _SettingsViewState extends ConsumerState<SettingsView> {
  late final _WebDavFieldControllers _webDavControllers;

  @override
  void initState() {
    super.initState();
    _webDavControllers = _WebDavFieldControllers.fromDraft(
      ref.read(settingsDraftProvider),
    );
  }

  @override
  void dispose() {
    _webDavControllers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<_WebDavDraftTextSlice>(
      settingsDraftProvider.select(
        (draft) => (
          filePath: draft.filePath,
          password: draft.password,
          serverUrl: draft.serverUrl,
          username: draft.username,
        ),
      ),
      (_, next) => _webDavControllers.syncFrom(next),
    );
    final tokens = UiThemeTokens.of(context);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);

    return SingleChildScrollView(
      key: const ValueKey<String>('settings_scroll_view'),
      controller: widget.scrollController,
      padding: tokens.spacing.mainContentPadding(viewport),
      child: _SettingsScrollContent(webDavControllers: _webDavControllers),
    );
  }
}

/// Auto-saved task persistence storage mode card (`Local` / `WebDAV` / `Both`).
class _StorageModeCard extends ConsumerWidget {
  /// Creates a [_StorageModeCard].
  const _StorageModeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final storageMode = _watchConfigSlice<StorageMode>(
      ref,
      (config) => config.storageMode,
      fallback: StorageMode.local,
    );
    final isBusy = ref.watch(
      settingsDraftProvider.select((draft) => draft.isBusy),
    );

    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_storage_mode_card'),
      icon: Icons.layers_outlined,
      title: localizations.storageModeSectionTitle,
      description: localizations.storageModeSectionDescription,
      child: UiSegmentedControl<StorageMode>(
        key: const ValueKey<String>('settings_storage_mode_control'),
        value: storageMode,
        enabled: !isBusy,
        semanticLabel: localizations.storageModeSectionTitle,
        segments: _storageModeSegments(localizations),
        onChanged: (next) => _commitStorageMode(context, ref, next),
      ),
    );
  }

  /// Commits storage mode immediately via [SettingsDraftNotifier.setStorageMode].
  void _commitStorageMode(
    BuildContext context,
    WidgetRef ref,
    StorageMode next,
  ) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsDraftProvider.notifier)
          .setStorageMode(next, locale: locale),
    );
  }
}

/// Auto-saved time zone card with `Automatic`/`Manual` segmented control and conditional 37-offset select.
class _TimeZoneCard extends ConsumerWidget {
  /// Creates a [_TimeZoneCard].
  const _TimeZoneCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final timeZoneMode = _watchConfigSlice<AppTimeZoneMode>(
      ref,
      (config) => config.timeZoneMode,
      fallback: AppTimeZoneMode.automatic,
    );

    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_timezone_card'),
      icon: Icons.schedule_rounded,
      title: localizations.timeZoneSectionTitle,
      description: localizations.timeZoneSectionDescription,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          UiSegmentedControl<AppTimeZoneMode>(
            key: const ValueKey<String>('settings_timezone_mode_control'),
            value: timeZoneMode,
            semanticLabel: localizations.timeZoneSectionTitle,
            segments: _timeZoneModeSegments(localizations),
            onChanged: (next) => _saveConfigPreference(
              context,
              ref,
              (notifier) => notifier.updateTimeZoneMode(next),
            ),
          ),
          if (timeZoneMode == AppTimeZoneMode.manual) ...<Widget>[
            SizedBox(height: tokens.spacing.space3),
            const _TimeZoneOffsetSelect(),
          ],
        ],
      ),
    );
  }
}

/// Conditional 37-offset UTC select dropdown shown inside [_TimeZoneCard] in manual mode.
class _TimeZoneOffsetSelect extends StatelessWidget {
  /// Creates a [_TimeZoneOffsetSelect].
  const _TimeZoneOffsetSelect();

  /// Cached immutable list of all 37 selectable UTC offset dropdown options.
  static final List<UiSelectOption> _utcOffsetOptions =
      List<UiSelectOption>.unmodifiable(<UiSelectOption>[
        for (final offsetMinutes in WebDavConfig.supportedUtcOffsetMinutes)
          UiSelectOption(
            value: '$offsetMinutes',
            label: WebDavConfig.formatUtcOffset(offsetMinutes),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _ConfigSelectField<int>(
      fieldKey: const ValueKey<String>('settings_timezone_offset_select'),
      label: localizations.timeZoneOffsetLabel,
      select: (config) => config.manualTimeZoneOffsetMinutes,
      fallback: 0,
      formatValue: (minutes) => '$minutes',
      options: _utcOffsetOptions,
      parseValue: int.tryParse,
      onCommit: (notifier, value) =>
          notifier.updateManualTimeZoneOffsetMinutes(value),
    );
  }
}

/// Parameterized WebDAV draft text input watching only `(isBusy, fieldError)` for its [kind].
class _WebDavDraftTextField extends ConsumerWidget {
  /// Creates a [_WebDavDraftTextField].
  const _WebDavDraftTextField({required this.kind, required this.controller});

  /// Text controller bound to this WebDAV draft field.
  final TextEditingController controller;

  /// Specific WebDAV field rendered by this widget.
  final _WebDavFieldKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final slice = ref.watch(
      settingsDraftProvider.select(
        (draft) =>
            (isBusy: draft.isBusy, error: _selectWebDavFieldError(draft, kind)),
      ),
    );
    final spec = _webDavFieldSpec(kind, localizations);

    return UiField(
      key: spec.key,
      kind: spec.fieldKind,
      label: spec.label,
      hintText: spec.hintText,
      controller: controller,
      isMonospace: spec.isMonospace,
      keyboardType: spec.keyboardType,
      enabled: !slice.isBusy,
      showPasswordTooltip: spec.showPasswordTooltip,
      hidePasswordTooltip: spec.hidePasswordTooltip,
      errorText: slice.error,
      onChanged: (value) => _updateWebDavField(ref, kind, value),
    );
  }
}

/// Owns the four WebDAV text controllers and synchronizes external draft resets without resetting active carets.
class _WebDavFieldControllers {
  /// Creates a [_WebDavFieldControllers] seeded from [draft].
  _WebDavFieldControllers.fromDraft(SettingsDraftState draft)
    : serverUrl = TextEditingController(text: draft.serverUrl),
      username = TextEditingController(text: draft.username),
      password = TextEditingController(text: draft.password),
      filePath = TextEditingController(text: draft.filePath);

  /// Controller bound to the remote `.tdf` file path input.
  final TextEditingController filePath;

  /// Controller bound to the WebDAV password input.
  final TextEditingController password;

  /// Controller bound to the WebDAV server URL input.
  final TextEditingController serverUrl;

  /// Controller bound to the WebDAV username input.
  final TextEditingController username;

  /// Returns the controller bound to WebDAV draft field [kind].
  TextEditingController controllerFor(_WebDavFieldKind kind) {
    return switch (kind) {
      _WebDavFieldKind.serverUrl => serverUrl,
      _WebDavFieldKind.username => username,
      _WebDavFieldKind.password => password,
      _WebDavFieldKind.filePath => filePath,
    };
  }

  /// Disposes all four WebDAV text controllers.
  void dispose() {
    filePath.dispose();
    password.dispose();
    serverUrl.dispose();
    username.dispose();
  }

  /// Synchronizes all four controllers against updated [slice] text values.
  void syncFrom(_WebDavDraftTextSlice slice) {
    _syncController(serverUrl, slice.serverUrl);
    _syncController(username, slice.username);
    _syncController(password, slice.password);
    _syncController(filePath, slice.filePath);
  }

  /// Updates [controller] only when its text differs from [expectedText].
  void _syncController(TextEditingController controller, String expectedText) {
    if (controller.text == expectedText) {
      return;
    }
    controller.value = TextEditingValue(
      text: expectedText,
      selection: TextSelection.collapsed(offset: expectedText.length),
    );
  }
}

/// Live resolved WebDAV endpoint preview readout inside [_WebDavStorageCardBody].
class _WebDavResolvedEndpointField extends ConsumerWidget {
  /// Creates a [_WebDavResolvedEndpointField].
  const _WebDavResolvedEndpointField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final resolvedEndpoint = ref.watch(
      settingsDraftProvider.select((draft) => draft.endpointPreview),
    );

    return UiField(
      key: const ValueKey<String>('settings_resolved_endpoint_field'),
      kind: UiFieldKind.readOnlyDisplay,
      label: localizations.resolvedEndpointLabel,
      displayValue: resolvedEndpoint,
    );
  }
}

/// Full-width WebDAV Synchronization card with conditional `Unsaved changes` pill, fields, endpoint readout, and Wipe button.
class _WebDavStorageCard extends ConsumerWidget {
  /// Creates a [_WebDavStorageCard].
  const _WebDavStorageCard({required this.controllers});

  /// Bundle owning the four WebDAV text controllers.
  final _WebDavFieldControllers controllers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final isWebDavDirty = ref.watch(
      settingsDraftProvider.select((draft) => draft.isDirty),
    );

    return UiCard.standard(
      key: const ValueKey<String>('settings_webdav_card'),
      headerIcon: Icons.cloud_sync_outlined,
      headerTitle: localizations.webdavSectionTitle,
      headerBadge: isWebDavDirty
          ? UiPill(
              key: const ValueKey<String>('settings_webdav_unsaved_badge'),
              label: localizations.settingsUnsavedChangesBadge,
              tone: UiPillTone.warning,
            )
          : null,
      child: _WebDavStorageCardBody(controllers: controllers),
    );
  }
}

/// Body layout inside [_WebDavStorageCard] hosting description, field grid, endpoint preview, and remote wipe trigger.
class _WebDavStorageCardBody extends StatelessWidget {
  /// Creates a [_WebDavStorageCardBody].
  const _WebDavStorageCardBody({required this.controllers});

  /// Bundle owning the four WebDAV text controllers.
  final _WebDavFieldControllers controllers;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final gap = tokens.spacing.space3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          localizations.webdavSectionDescription,
          style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
        ),
        SizedBox(height: gap),
        UiResponsiveGrid(
          key: const ValueKey<String>('settings_webdav_fields_grid'),
          preset: UiGridPreset.twoColumnCompactCollapse,
          children: <Widget>[
            for (final kind in _WebDavFieldKind.values)
              _WebDavDraftTextField(
                kind: kind,
                controller: controllers.controllerFor(kind),
              ),
          ],
        ),
        SizedBox(height: gap),
        const _WebDavResolvedEndpointField(),
        SizedBox(height: gap),
        const _WebDavWipeFooter(),
      ],
    );
  }
}

/// Danger remote wipe button row at the bottom of [_WebDavStorageCardBody].
class _WebDavWipeFooter extends ConsumerWidget {
  /// Creates a [_WebDavWipeFooter].
  const _WebDavWipeFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final isWebDavConfigured = _watchConfigSlice<bool>(
      ref,
      (config) => config.isWebDavConfigured,
      fallback: false,
    );
    final draftSlice = ref.watch(
      settingsDraftProvider.select(
        (draft) => (filePath: draft.filePath, isBusy: draft.isBusy),
      ),
    );
    final effectiveDraftPath = draftSlice.filePath.trim().isEmpty
        ? WebDavConfig.defaultFileName
        : draftSlice.filePath.trim();
    final remoteFileBaseName = TdfFilePath.extractFileBaseName(
      effectiveDraftPath,
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: UiButton(
        key: const ValueKey<String>('settings_wipe_remote_button'),
        label: localizations.actionWipeRemoteFile,
        leadingIcon: Icons.delete_outline_rounded,
        variant: UiButtonVariant.danger,
        density: UiButtonDensity.compact,
        onPressed: (isWebDavConfigured && !draftSlice.isBusy)
            ? () => _openWipeModal(
                context,
                filePath: draftSlice.filePath,
                baseName: remoteFileBaseName,
              )
            : null,
      ),
    );
  }

  /// Opens the typed-filename destructive wipe modal for the remote WebDAV `.tdf` file.
  void _openWipeModal(
    BuildContext context, {
    required String filePath,
    required String baseName,
  }) {
    final effectiveFileName = filePath.trim().isEmpty
        ? '$baseName.tdf'
        : filePath.trim();
    unawaited(
      showWipeTdfModal(
        context,
        isRemote: true,
        fileName: effectiveFileName,
        baseName: baseName,
      ),
    );
  }
}

/// Metadata descriptor for one local storage action button in [_LocalStorageActionButton].
typedef _LocalActionSpec = ({
  Key buttonKey,
  String label,
  String? semanticLabel,
  IconData icon,
  UiButtonVariant variant,
  String? tooltip,
  bool enabled,
});

/// Metadata descriptor for one segmented preference card rendered by [_SegmentedPreferenceCard].
typedef _SegmentedPreferenceSpec<T extends Object> = ({
  Key cardKey,
  Key controlKey,
  IconData icon,
  String title,
  String description,
  T Function(WebDavConfig config) select,
  T fallback,
  List<UiSegment<T>> segments,
  Future<void> Function(WebDavConfigNotifier notifier, T value) onCommit,
});

/// Narrow record of dock-relevant flags projected from [SettingsDraftState].
typedef _SettingsDockDraftSlice = ({
  bool isBusy,
  bool isDirty,
  bool isSavingWebDav,
  bool isTestingConnection,
});

/// Narrow record of the four transient WebDAV text draft fields observed for controller synchronization.
typedef _WebDavDraftTextSlice = ({
  String filePath,
  String password,
  String serverUrl,
  String username,
});

/// Metadata descriptor for one WebDAV draft input rendered by [_WebDavDraftTextField].
typedef _WebDavFieldSpec = ({
  Key key,
  UiFieldKind fieldKind,
  String label,
  String? hintText,
  bool isMonospace,
  TextInputType? keyboardType,
  String? showPasswordTooltip,
  String? hidePasswordTooltip,
});

/// Builds the metadata descriptor for the auto-saved Appearance preference card.
_SegmentedPreferenceSpec<AppThemeMode> _appearanceCardSpec(
  AppLocalizations localizations,
) {
  return (
    cardKey: const ValueKey<String>('settings_appearance_card'),
    controlKey: const ValueKey<String>('settings_theme_mode_control'),
    icon: Icons.brightness_6_outlined,
    title: localizations.themeSectionTitle,
    description: localizations.themeSectionDescription,
    select: (config) => config.themeMode,
    fallback: AppThemeMode.system,
    segments: _themeModeSegments(localizations),
    onCommit: (notifier, next) => notifier.updateThemeMode(next),
  );
}

/// Builds the metadata descriptor for the auto-saved Color Palette preference card.
_SegmentedPreferenceSpec<AppThemePalette> _colorPaletteCardSpec(
  AppLocalizations localizations,
) {
  return (
    cardKey: const ValueKey<String>('settings_palette_card'),
    controlKey: const ValueKey<String>('settings_theme_palette_control'),
    icon: Icons.palette_outlined,
    title: localizations.themePaletteSectionTitle,
    description: localizations.themePaletteSectionDescription,
    select: (config) => config.themePalette,
    fallback: AppThemePalette.calm,
    segments: _themePaletteSegments(localizations),
    onCommit: (notifier, next) => notifier.updateThemePalette(next),
  );
}

/// Dispatches the selected local storage file action from [_LocalStorageActionButton].
void _dispatchLocalStorageAction(
  BuildContext context,
  WidgetRef ref, {
  required _LocalStorageActionKind kind,
  required bool supportsDirectoryPicker,
  required String localFilePath,
}) {
  final locale = Localizations.localeOf(context);
  switch (kind) {
    case _LocalStorageActionKind.select:
      if (supportsDirectoryPicker) {
        unawaited(
          ref
              .read(settingsDraftProvider.notifier)
              .selectLocalFile(locale: locale),
        );
      } else {
        unawaited(showSelectLocalFileModal(context));
      }
    case _LocalStorageActionKind.move:
      unawaited(
        ref
            .read(settingsDraftProvider.notifier)
            .moveLocalDirectory(locale: locale),
      );
    case _LocalStorageActionKind.rename:
      unawaited(
        showRenameLocalFileModal(
          context,
          currentFileName: TdfFilePath.extractFileNameFromPath(localFilePath),
        ),
      );
    case _LocalStorageActionKind.wipe:
      unawaited(
        showWipeTdfModal(
          context,
          isRemote: false,
          fileName: TdfFilePath.extractFileNameFromPath(localFilePath),
          baseName: TdfFilePath.extractFileBaseName(localFilePath),
        ),
      );
  }
}

/// Maps [window] exhaustively to its localized deadline lead-window display label.
String _dueLeadLabel(DueLeadWindow window, AppLocalizations localizations) {
  return switch (window) {
    DueLeadWindow.off => localizations.dueLeadWindowOff,
    DueLeadWindow.atDue => localizations.dueLeadWindowAtDue,
    DueLeadWindow.hours12 => localizations.dueLeadWindow12Hours,
    DueLeadWindow.hours24 => localizations.dueLeadWindow24Hours,
    DueLeadWindow.hours48 => localizations.dueLeadWindow48Hours,
    DueLeadWindow.days7 => localizations.dueLeadWindow7Days,
  };
}

/// Builds localized select options for every [DueLeadWindow].
List<UiSelectOption> _dueLeadOptions(AppLocalizations localizations) {
  return <UiSelectOption>[
    for (final window in DueLeadWindow.values)
      UiSelectOption(
        value: window.name,
        label: _dueLeadLabel(window, localizations),
      ),
  ];
}

/// Builds the metadata descriptor for the auto-saved Language preference card.
_SegmentedPreferenceSpec<AppLanguage> _languageCardSpec(
  AppLocalizations localizations,
) {
  return (
    cardKey: const ValueKey<String>('settings_language_card'),
    controlKey: const ValueKey<String>('settings_language_control'),
    icon: Icons.language_rounded,
    title: localizations.languageSectionTitle,
    description: localizations.languageSectionDescription,
    select: (config) => config.language,
    fallback: AppLanguage.system,
    segments: _languageSegments(localizations),
    onCommit: (notifier, next) => notifier.updateLanguage(next),
  );
}

/// Builds segmented options for [AppLanguage].
List<UiSegment<AppLanguage>> _languageSegments(AppLocalizations localizations) {
  return <UiSegment<AppLanguage>>[
    UiSegment<AppLanguage>(
      value: AppLanguage.system,
      label: localizations.languageSystem,
    ),
    UiSegment<AppLanguage>(
      value: AppLanguage.english,
      label: localizations.languageEnglish,
    ),
    UiSegment<AppLanguage>(
      value: AppLanguage.german,
      label: localizations.languageGerman,
    ),
  ];
}

/// Resolves deterministic key, copy, icon, variant, and enabled gating for [kind].
_LocalActionSpec _localActionSpec(
  _LocalStorageActionKind kind, {
  required AppLocalizations localizations,
  required bool isBusy,
  required bool supportsDirectoryPicker,
}) {
  return switch (kind) {
    _LocalStorageActionKind.select => (
      buttonKey: const ValueKey<String>('settings_select_local_button'),
      label: localizations.actionSelectLocalFile,
      semanticLabel: null,
      icon: Icons.file_open_outlined,
      variant: UiButtonVariant.secondary,
      tooltip: null,
      enabled: !isBusy,
    ),
    _LocalStorageActionKind.move => (
      buttonKey: const ValueKey<String>('settings_move_local_button'),
      label: localizations.actionMoveLocalFile,
      semanticLabel: null,
      icon: Icons.drive_file_move_outlined,
      variant: UiButtonVariant.secondary,
      tooltip: supportsDirectoryPicker
          ? null
          : localizations.settingsMoveDesktopOnlyTooltip,
      enabled: supportsDirectoryPicker && !isBusy,
    ),
    _LocalStorageActionKind.rename => (
      buttonKey: const ValueKey<String>('settings_rename_local_button'),
      label: localizations.actionRenameLocalFile,
      semanticLabel: null,
      icon: Icons.drive_file_rename_outline,
      variant: UiButtonVariant.secondary,
      tooltip: null,
      enabled: !isBusy,
    ),
    _LocalStorageActionKind.wipe => (
      buttonKey: const ValueKey<String>('settings_wipe_local_button'),
      label: localizations.actionDelete,
      semanticLabel: localizations.actionWipeLocalFile,
      icon: Icons.delete_outline_rounded,
      variant: UiButtonVariant.danger,
      tooltip: null,
      enabled: !isBusy,
    ),
  };
}

/// Builds the metadata descriptor for the auto-saved Foreground Location card.
_SegmentedPreferenceSpec<bool> _locationCardSpec(
  AppLocalizations localizations,
) {
  return (
    cardKey: const ValueKey<String>('settings_location_card'),
    controlKey: const ValueKey<String>('settings_location_control'),
    icon: Icons.my_location_rounded,
    title: localizations.locationSectionTitle,
    description: localizations.locationSectionDescription,
    select: (config) => config.locationEnabled,
    fallback: false,
    segments: _locationSegments(localizations),
    onCommit: (notifier, next) => notifier.updateLocationEnabled(next),
  );
}

/// Builds 2-way segmented options for foreground location determination (`Off` / `On`).
List<UiSegment<bool>> _locationSegments(AppLocalizations localizations) {
  return <UiSegment<bool>>[
    UiSegment<bool>(value: false, label: localizations.locationOff),
    UiSegment<bool>(value: true, label: localizations.locationOn),
  ];
}

/// Maps [level] exhaustively to its localized diagnostic minimum-level label.
String _logLevelLabel(LogLevel level, AppLocalizations localizations) {
  return switch (level) {
    LogLevel.debug => localizations.logLevelDebug,
    LogLevel.info => localizations.logLevelInfo,
    LogLevel.warn => localizations.logLevelWarn,
    LogLevel.error => localizations.logLevelError,
    LogLevel.crash => level.label,
  };
}

/// Builds localized select options for every configurable [LogLevel].
List<UiSelectOption> _logLevelOptions(AppLocalizations localizations) {
  return <UiSelectOption>[
    for (final level in configurableDiagnosticLogLevels)
      UiSelectOption(
        value: level.name,
        label: _logLevelLabel(level, localizations),
      ),
  ];
}

/// Maps [mode] exhaustively to its localized diagnostic log storage label.
String _logStorageLabel(StorageMode mode, AppLocalizations localizations) {
  return switch (mode) {
    StorageMode.local => localizations.logStorageLocal,
    StorageMode.webdav => localizations.logStorageWebDav,
    StorageMode.both => localizations.logStorageBoth,
  };
}

/// Builds localized select options for diagnostic log storage modes.
List<UiSelectOption> _logStorageOptions(AppLocalizations localizations) {
  return <UiSelectOption>[
    for (final mode in StorageMode.values)
      UiSelectOption(
        value: mode.name,
        label: _logStorageLabel(mode, localizations),
      ),
  ];
}

/// Parses [raw] into the matching enum value in [values], returning `null` if unknown.
T? _parseEnumByName<T extends Enum>(String raw, Iterable<T> values) {
  for (final value in values) {
    if (value.name == raw) {
      return value;
    }
  }
  return null;
}

/// Commits an immediate auto-saved preference [mutation] via [SettingsDraftNotifier.savePreference].
void _saveConfigPreference(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(WebDavConfigNotifier notifier) mutation,
) {
  final locale = Localizations.localeOf(context);
  unawaited(
    ref
        .read(settingsDraftProvider.notifier)
        .savePreference(mutation, locale: locale),
  );
}

/// Projects dock-relevant dirty and busy flags from [state] for [SettingsActionDock].
_SettingsDockDraftSlice _selectDockDraft(SettingsDraftState state) {
  return (
    isBusy: state.isBusy,
    isDirty: state.isDirty,
    isSavingWebDav: state.isSavingWebDav,
    isTestingConnection: state.isTestingConnection,
  );
}

/// Projects the inline validation error for WebDAV [kind] from [draft].
String? _selectWebDavFieldError(
  SettingsDraftState draft,
  _WebDavFieldKind kind,
) {
  return switch (kind) {
    _WebDavFieldKind.serverUrl => draft.serverUrlError,
    _WebDavFieldKind.username => draft.usernameError,
    _WebDavFieldKind.password => draft.passwordError,
    _WebDavFieldKind.filePath => draft.filePathError,
  };
}

/// Builds segmented options for [StorageMode].
List<UiSegment<StorageMode>> _storageModeSegments(
  AppLocalizations localizations,
) {
  return <UiSegment<StorageMode>>[
    UiSegment<StorageMode>(
      value: StorageMode.local,
      label: localizations.storageModeLocal,
    ),
    UiSegment<StorageMode>(
      value: StorageMode.webdav,
      label: localizations.storageModeWebDav,
    ),
    UiSegment<StorageMode>(
      value: StorageMode.both,
      label: localizations.storageModeBoth,
    ),
  ];
}

/// Builds segmented options for [AppThemeMode].
List<UiSegment<AppThemeMode>> _themeModeSegments(
  AppLocalizations localizations,
) {
  return <UiSegment<AppThemeMode>>[
    UiSegment<AppThemeMode>(
      value: AppThemeMode.system,
      label: localizations.themeSystem,
    ),
    UiSegment<AppThemeMode>(
      value: AppThemeMode.light,
      label: localizations.themeLight,
    ),
    UiSegment<AppThemeMode>(
      value: AppThemeMode.dark,
      label: localizations.themeDark,
    ),
  ];
}

/// Builds segmented options for [AppThemePalette].
List<UiSegment<AppThemePalette>> _themePaletteSegments(
  AppLocalizations localizations,
) {
  return <UiSegment<AppThemePalette>>[
    UiSegment<AppThemePalette>(
      value: AppThemePalette.calm,
      label: localizations.themePaletteCalm,
    ),
    UiSegment<AppThemePalette>(
      value: AppThemePalette.plumUmber,
      label: localizations.themePalettePlumUmber,
    ),
  ];
}

/// Builds segmented options for [AppTimeZoneMode].
List<UiSegment<AppTimeZoneMode>> _timeZoneModeSegments(
  AppLocalizations localizations,
) {
  return <UiSegment<AppTimeZoneMode>>[
    UiSegment<AppTimeZoneMode>(
      value: AppTimeZoneMode.automatic,
      label: localizations.timeZoneModeAutomatic,
    ),
    UiSegment<AppTimeZoneMode>(
      value: AppTimeZoneMode.manual,
      label: localizations.timeZoneModeManual,
    ),
  ];
}

/// Updates the matching WebDAV draft field [kind] with [value] on [settingsDraftProvider].
void _updateWebDavField(WidgetRef ref, _WebDavFieldKind kind, String value) {
  final notifier = ref.read(settingsDraftProvider.notifier);
  switch (kind) {
    case _WebDavFieldKind.serverUrl:
      notifier.updateWebDavDraft(serverUrl: value);
    case _WebDavFieldKind.username:
      notifier.updateWebDavDraft(username: value);
    case _WebDavFieldKind.password:
      notifier.updateWebDavDraft(password: value);
    case _WebDavFieldKind.filePath:
      notifier.updateWebDavDraft(filePath: value);
  }
}

/// Watches a single narrow field from [webDavConfigProvider], falling back to
/// [activeWorkspaceProvider] or [fallback] while initial configuration loads.
T _watchConfigSlice<T extends Object>(
  WidgetRef ref,
  T Function(WebDavConfig config) select, {
  required T fallback,
}) {
  final fromConfig = ref.watch(
    webDavConfigProvider.select((asyncConfig) {
      if (asyncConfig.asData?.value case final config?) {
        return select(config);
      }
      return null;
    }),
  );
  if (fromConfig != null) {
    return fromConfig;
  }
  return ref.watch(
        activeWorkspaceProvider.select((asyncWorkspace) {
          if (asyncWorkspace.asData?.value.config case final config?) {
            return select(config);
          }
          return null;
        }),
      ) ??
      fallback;
}

/// Resolves deterministic key, field kind, copy, and input attributes for WebDAV [kind].
_WebDavFieldSpec _webDavFieldSpec(
  _WebDavFieldKind kind,
  AppLocalizations localizations,
) {
  return switch (kind) {
    _WebDavFieldKind.serverUrl => (
      key: const ValueKey<String>('settings_webdav_server_url_field'),
      fieldKind: UiFieldKind.text,
      label: localizations.serverUrlLabel,
      hintText: 'https://cloud.example.com',
      isMonospace: true,
      keyboardType: TextInputType.url,
      showPasswordTooltip: null,
      hidePasswordTooltip: null,
    ),
    _WebDavFieldKind.username => (
      key: const ValueKey<String>('settings_webdav_username_field'),
      fieldKind: UiFieldKind.text,
      label: localizations.usernameLabel,
      hintText: 'example-user',
      isMonospace: false,
      keyboardType: null,
      showPasswordTooltip: null,
      hidePasswordTooltip: null,
    ),
    _WebDavFieldKind.password => (
      key: const ValueKey<String>('settings_webdav_password_field'),
      fieldKind: UiFieldKind.password,
      label: localizations.passwordLabel,
      hintText: null,
      isMonospace: false,
      keyboardType: null,
      showPasswordTooltip: localizations.tooltipShowPassword,
      hidePasswordTooltip: localizations.tooltipHidePassword,
    ),
    _WebDavFieldKind.filePath => (
      key: const ValueKey<String>('settings_webdav_file_path_field'),
      fieldKind: UiFieldKind.text,
      label: localizations.filePathLabel,
      hintText: localizations.filePathHint,
      isMonospace: true,
      keyboardType: null,
      showPasswordTooltip: null,
      hidePasswordTooltip: null,
    ),
  };
}
