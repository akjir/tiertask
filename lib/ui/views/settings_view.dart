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

/// Auto-saved color brightness preference card (`System` / `Light` / `Dark`).
class _AppearanceCard extends ConsumerWidget {
  /// Creates an [_AppearanceCard].
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final themeMode = _watchConfigSlice<AppThemeMode>(
      ref,
      (config) => config.themeMode,
      fallback: AppThemeMode.system,
    );

    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_appearance_card'),
      icon: Icons.brightness_6_outlined,
      title: localizations.themeSectionTitle,
      description: localizations.themeSectionDescription,
      child: UiSegmentedControl<AppThemeMode>(
        key: const ValueKey<String>('settings_theme_mode_control'),
        value: themeMode,
        semanticLabel: localizations.themeSectionTitle,
        segments: _themeModeSegments(localizations),
        onChanged: (next) => _commitThemeMode(context, ref, next),
      ),
    );
  }

  /// Commits a theme mode change immediately via [SettingsDraftNotifier.savePreference].
  void _commitThemeMode(
    BuildContext context,
    WidgetRef ref,
    AppThemeMode next,
  ) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsDraftProvider.notifier)
          .savePreference(
            (notifier) => notifier.updateThemeMode(next),
            locale: locale,
          ),
    );
  }
}

/// Auto-saved design-system color palette preference card (`Calm` / `Plum Umber`).
class _ColorPaletteCard extends ConsumerWidget {
  /// Creates a [_ColorPaletteCard].
  const _ColorPaletteCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final themePalette = _watchConfigSlice<AppThemePalette>(
      ref,
      (config) => config.themePalette,
      fallback: AppThemePalette.calm,
    );

    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_palette_card'),
      icon: Icons.palette_outlined,
      title: localizations.themePaletteSectionTitle,
      description: localizations.themePaletteSectionDescription,
      child: UiSegmentedControl<AppThemePalette>(
        key: const ValueKey<String>('settings_theme_palette_control'),
        value: themePalette,
        semanticLabel: localizations.themePaletteSectionTitle,
        segments: _themePaletteSegments(localizations),
        onChanged: (next) => _commitPalette(context, ref, next),
      ),
    );
  }

  /// Commits a palette change immediately via [SettingsDraftNotifier.savePreference].
  void _commitPalette(
    BuildContext context,
    WidgetRef ref,
    AppThemePalette next,
  ) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsDraftProvider.notifier)
          .savePreference(
            (notifier) => notifier.updateThemePalette(next),
            locale: locale,
          ),
    );
  }
}

/// Auto-saved per-workspace deadline lead-window prioritization card.
class _DeadlinePrioritizationCard extends ConsumerWidget {
  /// Creates a [_DeadlinePrioritizationCard].
  const _DeadlinePrioritizationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final dueLeadWindow = _watchConfigSlice<DueLeadWindow>(
      ref,
      (config) => config.dueLeadWindow,
      fallback: DueLeadWindow.hours24,
    );

    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_due_lead_card'),
      icon: Icons.bolt_outlined,
      title: localizations.dueLeadWindowSectionTitle,
      description: localizations.dueLeadWindowSectionDescription,
      child: UiField(
        key: const ValueKey<String>('settings_due_lead_select'),
        kind: UiFieldKind.select,
        label: localizations.dueLeadWindowLabel,
        selectValue: dueLeadWindow.name,
        selectOptions: _dueLeadOptions(localizations),
        onSelectChanged: (raw) => _commitDueLead(context, ref, raw),
      ),
    );
  }

  /// Parses [raw] into a [DueLeadWindow] and commits via [SettingsDraftNotifier.savePreference].
  void _commitDueLead(BuildContext context, WidgetRef ref, String raw) {
    final parsed = _parseDueLeadWindow(raw);
    if (parsed == null) {
      return;
    }
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsDraftProvider.notifier)
          .savePreference(
            (notifier) => notifier.updateDueLeadWindow(parsed),
            locale: locale,
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
            onChanged: (enabled) => _commitDiagnostics(context, ref, enabled),
          ),
          if (diagnosticsEnabled) ...<Widget>[
            SizedBox(height: tokens.spacing.space3),
            const _DiagnosticsDetailsPanel(),
          ],
        ],
      ),
    );
  }

  /// Commits diagnostic logging opt-in state via [SettingsDraftNotifier.savePreference].
  void _commitDiagnostics(BuildContext context, WidgetRef ref, bool enabled) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsDraftProvider.notifier)
          .savePreference(
            (notifier) => notifier.updateDiagnosticsEnabled(enabled),
            locale: locale,
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
    final tokens = UiThemeTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _DiagnosticsLogLevelSelect(),
        SizedBox(height: tokens.spacing.space3),
        const _DiagnosticsLogStorageSelect(),
        SizedBox(height: tokens.spacing.space3),
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

/// Diagnostic log verbosity selector inside [_DiagnosticsDetailsPanel].
class _DiagnosticsLogLevelSelect extends ConsumerWidget {
  /// Creates a [_DiagnosticsLogLevelSelect].
  const _DiagnosticsLogLevelSelect();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final logLevel = _watchConfigSlice<LogLevel>(
      ref,
      (config) => config.logLevel,
      fallback: LogLevel.info,
    );

    return UiField(
      key: const ValueKey<String>('settings_log_level_select'),
      kind: UiFieldKind.select,
      label: localizations.logLevelLabel,
      selectValue: logLevel.name,
      selectOptions: _logLevelOptions(localizations),
      onSelectChanged: (raw) => _commitLogLevel(context, ref, raw),
    );
  }

  /// Parses [raw] into a [LogLevel] and commits via [SettingsDraftNotifier.savePreference].
  void _commitLogLevel(BuildContext context, WidgetRef ref, String raw) {
    final parsed = _parseLogLevel(raw);
    if (parsed == null) {
      return;
    }
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsDraftProvider.notifier)
          .savePreference(
            (notifier) => notifier.updateLogLevel(parsed),
            locale: locale,
          ),
    );
  }
}

/// Diagnostic log storage destination selector inside [_DiagnosticsDetailsPanel].
class _DiagnosticsLogStorageSelect extends ConsumerWidget {
  /// Creates a [_DiagnosticsLogStorageSelect].
  const _DiagnosticsLogStorageSelect();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final logStorageMode = _watchConfigSlice<StorageMode>(
      ref,
      (config) => config.logStorageMode,
      fallback: StorageMode.local,
    );

    return UiField(
      key: const ValueKey<String>('settings_log_storage_select'),
      kind: UiFieldKind.select,
      label: localizations.logStorageLabel,
      selectValue: logStorageMode.name,
      selectOptions: _logStorageOptions(localizations),
      onSelectChanged: (raw) => _commitLogStorageMode(context, ref, raw),
    );
  }

  /// Parses [raw] into a [StorageMode] and commits via [SettingsDraftNotifier.savePreference].
  void _commitLogStorageMode(BuildContext context, WidgetRef ref, String raw) {
    final parsed = _parseStorageMode(raw);
    if (parsed == null) {
      return;
    }
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsDraftProvider.notifier)
          .savePreference(
            (notifier) => notifier.updateLogStorageMode(parsed),
            locale: locale,
          ),
    );
  }
}

/// Auto-saved foreground location determination card using a 2-way segmented control (`U-COMP-002`).
class _ForegroundLocationCard extends ConsumerWidget {
  /// Creates a [_ForegroundLocationCard].
  const _ForegroundLocationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final locationEnabled = _watchConfigSlice<bool>(
      ref,
      (config) => config.locationEnabled,
      fallback: false,
    );

    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_location_card'),
      icon: Icons.my_location_rounded,
      title: localizations.locationSectionTitle,
      description: localizations.locationSectionDescription,
      child: UiSegmentedControl<bool>(
        key: const ValueKey<String>('settings_location_control'),
        value: locationEnabled,
        semanticLabel: localizations.locationSectionTitle,
        segments: _locationSegments(localizations),
        onChanged: (next) => _commitLocationEnabled(context, ref, next),
      ),
    );
  }

  /// Commits foreground location state immediately via [SettingsDraftNotifier.savePreference].
  void _commitLocationEnabled(BuildContext context, WidgetRef ref, bool next) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsDraftProvider.notifier)
          .savePreference(
            (notifier) => notifier.updateLocationEnabled(next),
            locale: locale,
          ),
    );
  }
}

/// Auto-saved display language preference card (`System` / `English` / `Deutsch`).
class _LanguageCard extends ConsumerWidget {
  /// Creates a [_LanguageCard].
  const _LanguageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final language = _watchConfigSlice<AppLanguage>(
      ref,
      (config) => config.language,
      fallback: AppLanguage.system,
    );

    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_language_card'),
      icon: Icons.language_rounded,
      title: localizations.languageSectionTitle,
      description: localizations.languageSectionDescription,
      child: UiSegmentedControl<AppLanguage>(
        key: const ValueKey<String>('settings_language_control'),
        value: language,
        semanticLabel: localizations.languageSectionTitle,
        segments: _languageSegments(localizations),
        onChanged: (next) => _commitLanguage(context, ref, next),
      ),
    );
  }

  /// Commits display language immediately via [SettingsDraftNotifier.savePreference].
  void _commitLanguage(BuildContext context, WidgetRef ref, AppLanguage next) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsDraftProvider.notifier)
          .savePreference(
            (notifier) => notifier.updateLanguage(next),
            locale: locale,
          ),
    );
  }
}

/// Compact full-width action button cell inside [_LocalActionsGrid].
class _LocalActionButton extends StatelessWidget {
  /// Creates a [_LocalActionButton].
  const _LocalActionButton({
    required this.buttonKey,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.variant = UiButtonVariant.secondary,
    this.tooltip,
    this.semanticLabel,
  });

  /// Stable key assigned to the underlying [UiButton].
  final Key buttonKey;

  /// Leading outline icon glyph.
  final IconData icon;

  /// Localized visible action text.
  final String label;

  /// Tap callback, or `null` when disabled.
  final VoidCallback? onPressed;

  /// Optional accessible label overriding [label].
  final String? semanticLabel;

  /// Optional pointer tooltip explaining disabled desktop-only behavior.
  final String? tooltip;

  /// Visual button variant.
  final UiButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    return UiButton(
      key: buttonKey,
      label: label,
      semanticLabel: semanticLabel,
      leadingIcon: icon,
      variant: variant,
      density: UiButtonDensity.compact,
      isFullWidth: true,
      tooltip: tooltip,
      onPressed: onPressed,
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
        _LocalSelectActionButton(),
        _LocalMoveActionButton(),
        _LocalRenameActionButton(),
        _LocalWipeActionButton(),
      ],
    );
  }
}

/// Capability-gated `Move` action button displaying a desktop-only tooltip when unsupported (`U-UX-006`).
class _LocalMoveActionButton extends ConsumerWidget {
  /// Creates a [_LocalMoveActionButton].
  const _LocalMoveActionButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final supportsDirectoryPicker = ref.watch(supportsDirectoryPickerProvider);
    final isBusy = ref.watch(
      settingsDraftProvider.select((draft) => draft.isBusy),
    );

    return _LocalActionButton(
      buttonKey: const ValueKey<String>('settings_move_local_button'),
      label: localizations.actionMoveLocalFile,
      icon: Icons.drive_file_move_outlined,
      tooltip: supportsDirectoryPicker
          ? null
          : localizations.settingsMoveDesktopOnlyTooltip,
      onPressed: (supportsDirectoryPicker && !isBusy)
          ? () => _handleMove(context, ref)
          : null,
    );
  }

  /// Moves the active local `.tdf` file via [SettingsDraftNotifier.moveLocalDirectory].
  void _handleMove(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsDraftProvider.notifier)
          .moveLocalDirectory(locale: locale),
    );
  }
}

/// `Rename` action button opening [showRenameLocalFileModal] with the active filename.
class _LocalRenameActionButton extends ConsumerWidget {
  /// Creates a [_LocalRenameActionButton].
  const _LocalRenameActionButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final localFilePath = _watchConfigSlice<String>(
      ref,
      (config) => config.localFilePath,
      fallback: WebDavConfig.defaultFileName,
    );
    final isBusy = ref.watch(
      settingsDraftProvider.select((draft) => draft.isBusy),
    );
    final localFileName = TdfFilePath.extractFileNameFromPath(localFilePath);

    return _LocalActionButton(
      buttonKey: const ValueKey<String>('settings_rename_local_button'),
      label: localizations.actionRenameLocalFile,
      icon: Icons.drive_file_rename_outline,
      onPressed: isBusy
          ? null
          : () => unawaited(
              showRenameLocalFileModal(context, currentFileName: localFileName),
            ),
    );
  }
}

/// Read-only resolved local `.tdf` path preview inside [_LocalStorageCardBody].
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

/// Capability-gated `Select` action button invoking native file picker or in-app modal (`U-UX-006`).
class _LocalSelectActionButton extends ConsumerWidget {
  /// Creates a [_LocalSelectActionButton].
  const _LocalSelectActionButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final supportsDirectoryPicker = ref.watch(supportsDirectoryPickerProvider);
    final isBusy = ref.watch(
      settingsDraftProvider.select((draft) => draft.isBusy),
    );

    return _LocalActionButton(
      buttonKey: const ValueKey<String>('settings_select_local_button'),
      label: localizations.actionSelectLocalFile,
      icon: Icons.file_open_outlined,
      onPressed: isBusy
          ? null
          : () => _handleSelect(
              context,
              ref,
              supportsNativePicker: supportsDirectoryPicker,
            ),
    );
  }

  /// Invokes the native file picker when [supportsNativePicker] is true, or opens the in-app modal otherwise.
  void _handleSelect(
    BuildContext context,
    WidgetRef ref, {
    required bool supportsNativePicker,
  }) {
    if (supportsNativePicker) {
      final locale = Localizations.localeOf(context);
      unawaited(
        ref
            .read(settingsDraftProvider.notifier)
            .selectLocalFile(locale: locale),
      );
      return;
    }
    unawaited(showSelectLocalFileModal(context));
  }
}

/// Full-width auto-saved Local TDF File card with resolved path, capability-gated actions, and file watch toggle.
class _LocalStorageCard extends StatelessWidget {
  /// Creates a [_LocalStorageCard].
  const _LocalStorageCard();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_local_card'),
      icon: Icons.folder_outlined,
      title: localizations.localSectionTitle,
      description: localizations.localSectionDescription,
      child: const _LocalStorageCardBody(),
    );
  }
}

/// Body layout inside [_LocalStorageCard] pairing path readout, 4-action grid, and watch toggle.
class _LocalStorageCardBody extends StatelessWidget {
  /// Creates a [_LocalStorageCardBody].
  const _LocalStorageCardBody();

  @override
  Widget build(BuildContext context) {
    final gap = UiThemeTokens.of(context).spacing.space3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _LocalResolvedPathField(),
        SizedBox(height: gap),
        const _LocalActionsGrid(),
        SizedBox(height: gap),
        const _LocalWatchToggle(),
      ],
    );
  }
}

/// Auto-saved external local file watching checkbox row inside [_LocalStorageCardBody].
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
      onChanged: (enabled) => _commitLocalWatch(context, ref, enabled),
    );
  }

  /// Commits external file watching preference via [SettingsDraftNotifier.savePreference].
  void _commitLocalWatch(BuildContext context, WidgetRef ref, bool enabled) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsDraftProvider.notifier)
          .savePreference(
            (notifier) => notifier.updateLocalWatchEnabled(enabled),
            locale: locale,
          ),
    );
  }
}

/// Danger `Wipe` action button opening [showWipeTdfModal] for the active local `.tdf` file.
class _LocalWipeActionButton extends ConsumerWidget {
  /// Creates a [_LocalWipeActionButton].
  const _LocalWipeActionButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final localFilePath = _watchConfigSlice<String>(
      ref,
      (config) => config.localFilePath,
      fallback: WebDavConfig.defaultFileName,
    );
    final isBusy = ref.watch(
      settingsDraftProvider.select((draft) => draft.isBusy),
    );
    final localFileName = TdfFilePath.extractFileNameFromPath(localFilePath);
    final localFileBaseName = TdfFilePath.extractFileBaseName(localFilePath);

    return _LocalActionButton(
      buttonKey: const ValueKey<String>('settings_wipe_local_button'),
      label: localizations.actionDelete,
      semanticLabel: localizations.actionWipeLocalFile,
      icon: Icons.delete_outline_rounded,
      variant: UiButtonVariant.danger,
      onPressed: isBusy
          ? null
          : () => unawaited(
              showWipeTdfModal(
                context,
                isRemote: false,
                fileName: localFileName,
                baseName: localFileBaseName,
              ),
            ),
    );
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
        _LanguageCard(),
        _AppearanceCard(),
        _ColorPaletteCard(),
        _TimeZoneCard(),
        _DeadlinePrioritizationCard(),
        _ForegroundLocationCard(),
        _DiagnosticsCard(),
        _StorageModeCard(),
      ],
    );
  }
}

/// Scrollable column body assembling header, optional status banner, preference grid, and storage cards.
class _SettingsScrollContent extends StatelessWidget {
  /// Creates a [_SettingsScrollContent].
  const _SettingsScrollContent({
    required this.serverUrlController,
    required this.usernameController,
    required this.passwordController,
    required this.filePathController,
  });

  /// Controller bound to the WebDAV remote file path input.
  final TextEditingController filePathController;

  /// Controller bound to the WebDAV password input.
  final TextEditingController passwordController;

  /// Controller bound to the WebDAV server URL input.
  final TextEditingController serverUrlController;

  /// Controller bound to the WebDAV username input.
  final TextEditingController usernameController;

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
        _SettingsStorageSections(
          serverUrlController: serverUrlController,
          usernameController: usernameController,
          passwordController: passwordController,
          filePathController: filePathController,
        ),
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
    return _SettingsStatusBannerSection(
      banner: statusBanner,
      onDismiss: () =>
          ref.read(settingsDraftProvider.notifier).dismissStatusBanner(),
    );
  }
}

/// Top-spaced status banner section rendered inside [_SettingsStatusBannerHost].
class _SettingsStatusBannerSection extends StatelessWidget {
  /// Creates a [_SettingsStatusBannerSection].
  const _SettingsStatusBannerSection({
    required this.banner,
    required this.onDismiss,
  });

  /// Active settings status banner snapshot.
  final SettingsStatusBanner banner;

  /// Callback dismissing [banner].
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.space3),
      child: UiBanner(
        key: const ValueKey<String>('settings_status_banner'),
        variant: UiBannerVariant.status,
        tone: UiDomainMappers.settingsBannerTone(banner.tone),
        message: banner.message,
        dismissTooltip: localizations.actionDismiss,
        onDismiss: onDismiss,
      ),
    );
  }
}

/// Conditional Local and WebDAV storage section host watching only [WebDavConfig.storageMode].
class _SettingsStorageSections extends ConsumerWidget {
  /// Creates a [_SettingsStorageSections].
  const _SettingsStorageSections({
    required this.serverUrlController,
    required this.usernameController,
    required this.passwordController,
    required this.filePathController,
  });

  /// Controller bound to the WebDAV remote file path input.
  final TextEditingController filePathController;

  /// Controller bound to the WebDAV password input.
  final TextEditingController passwordController;

  /// Controller bound to the WebDAV server URL input.
  final TextEditingController serverUrlController;

  /// Controller bound to the WebDAV username input.
  final TextEditingController usernameController;

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
          _WebDavStorageCard(
            serverUrlController: serverUrlController,
            usernameController: usernameController,
            passwordController: passwordController,
            filePathController: filePathController,
          ),
        ],
      ],
    );
  }
}

/// Manages WebDAV [TextEditingController] lifecycles and external draft sync for [SettingsView].
class _SettingsViewState extends ConsumerState<SettingsView> {
  late final TextEditingController _filePathController;
  late final TextEditingController _passwordController;
  late final TextEditingController _serverUrlController;
  late final TextEditingController _usernameController;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(settingsDraftProvider);
    _serverUrlController = TextEditingController(text: initial.serverUrl);
    _usernameController = TextEditingController(text: initial.username);
    _passwordController = TextEditingController(text: initial.password);
    _filePathController = TextEditingController(text: initial.filePath);
  }

  @override
  void dispose() {
    _filePathController.dispose();
    _passwordController.dispose();
    _serverUrlController.dispose();
    _usernameController.dispose();
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
      _handleDraftTextChanged,
    );
    final tokens = UiThemeTokens.of(context);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);

    return SingleChildScrollView(
      key: const ValueKey<String>('settings_scroll_view'),
      controller: widget.scrollController,
      padding: tokens.spacing.mainContentPadding(viewport),
      child: _SettingsScrollContent(
        serverUrlController: _serverUrlController,
        usernameController: _usernameController,
        passwordController: _passwordController,
        filePathController: _filePathController,
      ),
    );
  }

  /// Synchronizes the four WebDAV controllers when external state resets or updates draft values.
  void _handleDraftTextChanged(
    _WebDavDraftTextSlice? previous,
    _WebDavDraftTextSlice next,
  ) {
    _syncController(_serverUrlController, next.serverUrl);
    _syncController(_usernameController, next.username);
    _syncController(_passwordController, next.password);
    _syncController(_filePathController, next.filePath);
  }

  /// Updates [controller] only when its text differs from [expectedText], preserving active caret edits.
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
            onChanged: (next) => _commitTimeZoneMode(context, ref, next),
          ),
          if (timeZoneMode == AppTimeZoneMode.manual) ...<Widget>[
            SizedBox(height: tokens.spacing.space3),
            const _TimeZoneOffsetSelect(),
          ],
        ],
      ),
    );
  }

  /// Commits time zone mode immediately via [SettingsDraftNotifier.savePreference].
  void _commitTimeZoneMode(
    BuildContext context,
    WidgetRef ref,
    AppTimeZoneMode next,
  ) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsDraftProvider.notifier)
          .savePreference(
            (notifier) => notifier.updateTimeZoneMode(next),
            locale: locale,
          ),
    );
  }
}

/// Conditional 37-offset UTC select dropdown shown inside [_TimeZoneCard] in manual mode.
class _TimeZoneOffsetSelect extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final manualOffsetMinutes = _watchConfigSlice<int>(
      ref,
      (config) => config.manualTimeZoneOffsetMinutes,
      fallback: 0,
    );

    return UiField(
      key: const ValueKey<String>('settings_timezone_offset_select'),
      kind: UiFieldKind.select,
      label: localizations.timeZoneOffsetLabel,
      selectValue: '$manualOffsetMinutes',
      selectOptions: _utcOffsetOptions,
      onSelectChanged: (raw) => _commitUtcOffset(context, ref, raw),
    );
  }

  /// Parses [raw] offset minutes and commits immediately via [SettingsDraftNotifier.savePreference].
  void _commitUtcOffset(BuildContext context, WidgetRef ref, String raw) {
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      return;
    }
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsDraftProvider.notifier)
          .savePreference(
            (notifier) => notifier.updateManualTimeZoneOffsetMinutes(parsed),
            locale: locale,
          ),
    );
  }
}

/// Responsive 2-column (`1` column compact) WebDAV credentials and remote file path field grid.
class _WebDavFieldsGrid extends StatelessWidget {
  /// Creates a [_WebDavFieldsGrid].
  const _WebDavFieldsGrid({
    required this.serverUrlController,
    required this.usernameController,
    required this.passwordController,
    required this.filePathController,
  });

  /// Controller bound to the remote `.tdf` file path input.
  final TextEditingController filePathController;

  /// Controller bound to the WebDAV password input.
  final TextEditingController passwordController;

  /// Controller bound to the WebDAV server URL input.
  final TextEditingController serverUrlController;

  /// Controller bound to the WebDAV username input.
  final TextEditingController usernameController;

  @override
  Widget build(BuildContext context) {
    return UiResponsiveGrid(
      key: const ValueKey<String>('settings_webdav_fields_grid'),
      preset: UiGridPreset.twoColumnCompactCollapse,
      children: <Widget>[
        _WebDavServerUrlField(controller: serverUrlController),
        _WebDavUsernameField(controller: usernameController),
        _WebDavPasswordField(controller: passwordController),
        _WebDavFilePathField(controller: filePathController),
      ],
    );
  }
}

/// Monospace remote `.tdf` file path field inside [_WebDavFieldsGrid].
class _WebDavFilePathField extends ConsumerWidget {
  /// Creates a [_WebDavFilePathField].
  const _WebDavFilePathField({required this.controller});

  /// Text controller bound to the remote file path.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final slice = ref.watch(
      settingsDraftProvider.select(
        (draft) => (filePathError: draft.filePathError, isBusy: draft.isBusy),
      ),
    );

    return UiField(
      key: const ValueKey<String>('settings_webdav_file_path_field'),
      label: localizations.filePathLabel,
      hintText: localizations.filePathHint,
      controller: controller,
      isMonospace: true,
      enabled: !slice.isBusy,
      errorText: slice.filePathError,
      onChanged: (value) => ref
          .read(settingsDraftProvider.notifier)
          .updateWebDavDraft(filePath: value),
    );
  }
}

/// Password input with visibility toggle inside [_WebDavFieldsGrid].
class _WebDavPasswordField extends ConsumerWidget {
  /// Creates a [_WebDavPasswordField].
  const _WebDavPasswordField({required this.controller});

  /// Text controller bound to the WebDAV password.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final slice = ref.watch(
      settingsDraftProvider.select(
        (draft) => (isBusy: draft.isBusy, passwordError: draft.passwordError),
      ),
    );

    return UiField(
      key: const ValueKey<String>('settings_webdav_password_field'),
      kind: UiFieldKind.password,
      label: localizations.passwordLabel,
      controller: controller,
      enabled: !slice.isBusy,
      showPasswordTooltip: localizations.tooltipShowPassword,
      hidePasswordTooltip: localizations.tooltipHidePassword,
      errorText: slice.passwordError,
      onChanged: (value) => ref
          .read(settingsDraftProvider.notifier)
          .updateWebDavDraft(password: value),
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

/// Monospace WebDAV server URL input inside [_WebDavFieldsGrid].
class _WebDavServerUrlField extends ConsumerWidget {
  /// Creates a [_WebDavServerUrlField].
  const _WebDavServerUrlField({required this.controller});

  /// Text controller bound to the WebDAV server URL.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final slice = ref.watch(
      settingsDraftProvider.select(
        (draft) => (isBusy: draft.isBusy, serverUrlError: draft.serverUrlError),
      ),
    );

    return UiField(
      key: const ValueKey<String>('settings_webdav_server_url_field'),
      label: localizations.serverUrlLabel,
      hintText: 'https://cloud.example.com',
      controller: controller,
      isMonospace: true,
      keyboardType: TextInputType.url,
      enabled: !slice.isBusy,
      errorText: slice.serverUrlError,
      onChanged: (value) => ref
          .read(settingsDraftProvider.notifier)
          .updateWebDavDraft(serverUrl: value),
    );
  }
}

/// Full-width WebDAV Synchronization card with conditional `Unsaved changes` pill, fields, endpoint readout, and Wipe button.
class _WebDavStorageCard extends ConsumerWidget {
  /// Creates a [_WebDavStorageCard].
  const _WebDavStorageCard({
    required this.serverUrlController,
    required this.usernameController,
    required this.passwordController,
    required this.filePathController,
  });

  /// Controller bound to the remote `.tdf` file path field.
  final TextEditingController filePathController;

  /// Controller bound to the WebDAV password field.
  final TextEditingController passwordController;

  /// Controller bound to the WebDAV server URL field.
  final TextEditingController serverUrlController;

  /// Controller bound to the WebDAV username field.
  final TextEditingController usernameController;

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
      child: _WebDavStorageCardBody(
        serverUrlController: serverUrlController,
        usernameController: usernameController,
        passwordController: passwordController,
        filePathController: filePathController,
      ),
    );
  }
}

/// Body layout inside [_WebDavStorageCard] hosting description, field grid, endpoint preview, and remote wipe trigger.
class _WebDavStorageCardBody extends StatelessWidget {
  /// Creates a [_WebDavStorageCardBody].
  const _WebDavStorageCardBody({
    required this.serverUrlController,
    required this.usernameController,
    required this.passwordController,
    required this.filePathController,
  });

  /// Controller bound to the remote `.tdf` file path field.
  final TextEditingController filePathController;

  /// Controller bound to the WebDAV password field.
  final TextEditingController passwordController;

  /// Controller bound to the WebDAV server URL field.
  final TextEditingController serverUrlController;

  /// Controller bound to the WebDAV username field.
  final TextEditingController usernameController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          localizations.webdavSectionDescription,
          style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
        ),
        SizedBox(height: tokens.spacing.space3),
        _WebDavFieldsGrid(
          serverUrlController: serverUrlController,
          usernameController: usernameController,
          passwordController: passwordController,
          filePathController: filePathController,
        ),
        SizedBox(height: tokens.spacing.space3),
        const _WebDavResolvedEndpointField(),
        SizedBox(height: tokens.spacing.space3),
        const _WebDavWipeFooter(),
      ],
    );
  }
}

/// WebDAV username input inside [_WebDavFieldsGrid].
class _WebDavUsernameField extends ConsumerWidget {
  /// Creates a [_WebDavUsernameField].
  const _WebDavUsernameField({required this.controller});

  /// Text controller bound to the WebDAV username.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final slice = ref.watch(
      settingsDraftProvider.select(
        (draft) => (isBusy: draft.isBusy, usernameError: draft.usernameError),
      ),
    );

    return UiField(
      key: const ValueKey<String>('settings_webdav_username_field'),
      label: localizations.usernameLabel,
      hintText: 'example-user',
      controller: controller,
      enabled: !slice.isBusy,
      errorText: slice.usernameError,
      onChanged: (value) => ref
          .read(settingsDraftProvider.notifier)
          .updateWebDavDraft(username: value),
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

/// Builds localized select options for every [LogLevel].
List<UiSelectOption> _logLevelOptions(AppLocalizations localizations) {
  return <UiSelectOption>[
    for (final level in LogLevel.values)
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

/// Parses [raw] into a [DueLeadWindow], returning `null` if unknown.
DueLeadWindow? _parseDueLeadWindow(String raw) {
  for (final window in DueLeadWindow.values) {
    if (window.name == raw) {
      return window;
    }
  }
  return null;
}

/// Parses [raw] into a [LogLevel], returning `null` if unknown.
LogLevel? _parseLogLevel(String raw) {
  for (final level in LogLevel.values) {
    if (level.name == raw) {
      return level;
    }
  }
  return null;
}

/// Parses [raw] into a [StorageMode], returning `null` if unknown.
StorageMode? _parseStorageMode(String raw) {
  for (final mode in StorageMode.values) {
    if (mode.name == raw) {
      return mode;
    }
  }
  return null;
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
