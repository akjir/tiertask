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
import '../../presentation/app_shell_controller.dart';
import '../../presentation/log_viewer_controller.dart';
import '../../presentation/settings_v2_controller.dart';
import '../../presentation/ui_v2_shell_models.dart';
import '../dialogs/app_modals.dart';
import '../ui_v2_icon_mapper.dart';

/// Pinned bottom action dock decoupled outside [SettingsView]'s scroll region (`U-LAYOUT-005`, `U-UX-006`).
class SettingsActionDock extends ConsumerWidget {
  /// Creates a [SettingsActionDock].
  const SettingsActionDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = UiThemeTokens.of(context);
    final dockState = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (
          canTestConnectionAndSync: model.canTestConnectionAndSync,
          isBusy: model.isBusy,
          isWebDavDirty: model.isWebDavDirty,
          storageMode: model.storageMode,
        ),
      ),
    );
    final usesWebDav = _usesWebDavStorage(dockState.storageMode);

    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: tokens.spacing.space2,
        runSpacing: tokens.spacing.space2,
        children: <Widget>[
          _SettingsDockUnsavedBadge(isVisible: dockState.isWebDavDirty),
          _SettingsDockButtons(
            canSave: !dockState.isBusy && usesWebDav,
            canTestConnectionAndSync: dockState.canTestConnectionAndSync,
            isDirty: dockState.isWebDavDirty,
            isSaving: dockState.isBusy && dockState.isWebDavDirty,
            isTestingSync:
                dockState.isBusy && !dockState.isWebDavDirty && usesWebDav,
            onSave: () => _handleSave(context, ref),
            onTestAndSync: () => _handleTestAndSync(context, ref),
          ),
        ],
      ),
    );
  }

  /// Validates and persists the WebDAV draft via [SettingsV2Controller.saveWebDavDraft].
  void _handleSave(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsV2ControllerProvider.notifier)
          .saveWebDavDraft(locale: locale),
    );
  }

  /// Validates and tests WebDAV synchronization via [SettingsV2Controller.testConnectionAndSync].
  void _handleTestAndSync(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsV2ControllerProvider.notifier)
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
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (isBusy: model.isBusy, themeMode: model.themeMode),
      ),
    );

    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_appearance_card'),
      icon: Icons.brightness_6_outlined,
      title: localizations.themeSectionTitle,
      description: localizations.themeSectionDescription,
      child: UiSegmentedControl<ShellThemeMode>(
        key: const ValueKey<String>('settings_theme_mode_control'),
        value: slice.themeMode,
        enabled: !slice.isBusy,
        semanticLabel: localizations.themeSectionTitle,
        segments: _themeModeSegments(localizations),
        onChanged: (next) => _commitThemeMode(context, ref, next),
      ),
    );
  }

  /// Commits a theme mode change immediately via [SettingsV2Controller.setThemeMode].
  void _commitThemeMode(
    BuildContext context,
    WidgetRef ref,
    ShellThemeMode next,
  ) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsV2ControllerProvider.notifier)
          .setThemeMode(next, locale: locale),
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
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (isBusy: model.isBusy, themePalette: model.themePalette),
      ),
    );

    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_palette_card'),
      icon: Icons.palette_outlined,
      title: localizations.themePaletteSectionTitle,
      description: localizations.themePaletteSectionDescription,
      child: UiSegmentedControl<AppThemePresetKey>(
        key: const ValueKey<String>('settings_theme_palette_control'),
        value: slice.themePalette,
        enabled: !slice.isBusy,
        semanticLabel: localizations.themePaletteSectionTitle,
        segments: _themePaletteSegments(localizations),
        onChanged: (next) => _commitPalette(context, ref, next),
      ),
    );
  }

  /// Commits a palette change immediately via [SettingsV2Controller.setThemePalette].
  void _commitPalette(
    BuildContext context,
    WidgetRef ref,
    AppThemePresetKey next,
  ) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsV2ControllerProvider.notifier)
          .setThemePalette(next, locale: locale),
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
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (dueLeadWindow: model.dueLeadWindow, isBusy: model.isBusy),
      ),
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
        selectValue: slice.dueLeadWindow.name,
        selectOptions: _dueLeadOptions(localizations),
        enabled: !slice.isBusy,
        onSelectChanged: (raw) => _commitDueLead(context, ref, raw),
      ),
    );
  }

  /// Parses [raw] into a [ShellDueLeadOption] and commits via [SettingsV2Controller.setDueLeadWindow].
  void _commitDueLead(BuildContext context, WidgetRef ref, String raw) {
    final parsed = _parseDueLeadOption(raw);
    if (parsed == null) {
      return;
    }
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsV2ControllerProvider.notifier)
          .setDueLeadWindow(parsed, locale: locale),
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
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (
          diagnosticsEnabled: model.diagnosticsEnabled,
          isBusy: model.isBusy,
        ),
      ),
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
            value: slice.diagnosticsEnabled,
            enabled: !slice.isBusy,
            onChanged: (enabled) => _commitDiagnostics(context, ref, enabled),
          ),
          if (slice.diagnosticsEnabled) ...<Widget>[
            SizedBox(height: tokens.spacing.space3),
            const _DiagnosticsDetailsPanel(),
          ],
        ],
      ),
    );
  }

  /// Commits diagnostic logging opt-in state via [SettingsV2Controller.setDiagnosticsEnabled].
  void _commitDiagnostics(BuildContext context, WidgetRef ref, bool enabled) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsV2ControllerProvider.notifier)
          .setDiagnosticsEnabled(enabled, locale: locale),
    );
  }
}

/// Conditional diagnostic level, storage, and viewer trigger controls inside [_DiagnosticsCard].
class _DiagnosticsDetailsPanel extends ConsumerWidget {
  /// Creates a [_DiagnosticsDetailsPanel].
  const _DiagnosticsDetailsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (
          activeLogFileName: model.activeLogFileName,
          isBusy: model.isBusy,
          logLevel: model.logLevel,
          logStorageMode: model.logStorageMode,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UiField(
          key: const ValueKey<String>('settings_log_level_select'),
          kind: UiFieldKind.select,
          label: localizations.logLevelLabel,
          selectValue: slice.logLevel.name,
          selectOptions: _logLevelOptions(localizations),
          enabled: !slice.isBusy,
          onSelectChanged: (raw) => _commitLogLevel(context, ref, raw),
        ),
        SizedBox(height: tokens.spacing.space3),
        UiField(
          key: const ValueKey<String>('settings_log_storage_select'),
          kind: UiFieldKind.select,
          label: localizations.logStorageLabel,
          selectValue: slice.logStorageMode.name,
          selectOptions: _logStorageOptions(localizations),
          enabled: !slice.isBusy,
          onSelectChanged: (raw) => _commitLogStorageMode(context, ref, raw),
        ),
        SizedBox(height: tokens.spacing.space3),
        _DiagnosticsLogFooter(activeLogFileName: slice.activeLogFileName),
      ],
    );
  }

  /// Parses [raw] into a [DiagnosticLogLevel] and commits via [SettingsV2Controller.setLogLevel].
  void _commitLogLevel(BuildContext context, WidgetRef ref, String raw) {
    final parsed = _parseDiagnosticLogLevel(raw);
    if (parsed == null) {
      return;
    }
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsV2ControllerProvider.notifier)
          .setLogLevel(parsed, locale: locale),
    );
  }

  /// Parses [raw] into a [ShellStorageMode] and commits via [SettingsV2Controller.setLogStorageMode].
  void _commitLogStorageMode(BuildContext context, WidgetRef ref, String raw) {
    final parsed = _parseStorageMode(raw);
    if (parsed == null) {
      return;
    }
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsV2ControllerProvider.notifier)
          .setLogStorageMode(parsed, locale: locale),
    );
  }
}

/// Active diagnostic log filename readout and viewer trigger button inside [_DiagnosticsDetailsPanel].
class _DiagnosticsLogFooter extends ConsumerWidget {
  /// Creates a [_DiagnosticsLogFooter].
  const _DiagnosticsLogFooter({required this.activeLogFileName});

  /// Active dated diagnostic log filename.
  final String activeLogFileName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

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
            onPressed: () => ref
                .read(appShellControllerProvider.notifier)
                .openView(ShellView.logs),
          ),
        ),
      ],
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
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) =>
            (isBusy: model.isBusy, locationEnabled: model.locationEnabled),
      ),
    );

    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_location_card'),
      icon: Icons.my_location_rounded,
      title: localizations.locationSectionTitle,
      description: localizations.locationSectionDescription,
      child: UiSegmentedControl<bool>(
        key: const ValueKey<String>('settings_location_control'),
        value: slice.locationEnabled,
        enabled: !slice.isBusy,
        semanticLabel: localizations.locationSectionTitle,
        segments: _locationSegments(localizations),
        onChanged: (next) => _commitLocationEnabled(context, ref, next),
      ),
    );
  }

  /// Commits foreground location state immediately via [SettingsV2Controller.setLocationEnabled].
  void _commitLocationEnabled(BuildContext context, WidgetRef ref, bool next) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsV2ControllerProvider.notifier)
          .setLocationEnabled(next, locale: locale),
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
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (isBusy: model.isBusy, language: model.language),
      ),
    );

    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_language_card'),
      icon: Icons.language_rounded,
      title: localizations.languageSectionTitle,
      description: localizations.languageSectionDescription,
      child: UiSegmentedControl<ShellLanguageOption>(
        key: const ValueKey<String>('settings_language_control'),
        value: slice.language,
        enabled: !slice.isBusy,
        semanticLabel: localizations.languageSectionTitle,
        segments: _languageSegments(localizations),
        onChanged: (next) => _commitLanguage(context, ref, next),
      ),
    );
  }

  /// Commits display language immediately via [SettingsV2Controller.setLanguage].
  void _commitLanguage(
    BuildContext context,
    WidgetRef ref,
    ShellLanguageOption next,
  ) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsV2ControllerProvider.notifier)
          .setLanguage(next, locale: locale),
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
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (
          isBusy: model.isBusy,
          supportsNativeDirectoryPicker: model.supportsNativeDirectoryPicker,
        ),
      ),
    );
    return _LocalActionButton(
      buttonKey: const ValueKey<String>('settings_move_local_button'),
      label: localizations.actionMoveLocalFile,
      icon: Icons.drive_file_move_outlined,
      tooltip: slice.supportsNativeDirectoryPicker
          ? null
          : localizations.settingsMoveDesktopOnlyTooltip,
      onPressed: (slice.supportsNativeDirectoryPicker && !slice.isBusy)
          ? () => _handleMove(context, ref)
          : null,
    );
  }

  /// Moves the active local `.tdf` file via [SettingsV2Controller.moveLocalDirectory].
  void _handleMove(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsV2ControllerProvider.notifier)
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
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (isBusy: model.isBusy, localFileName: model.localFileName),
      ),
    );
    return _LocalActionButton(
      buttonKey: const ValueKey<String>('settings_rename_local_button'),
      label: localizations.actionRenameLocalFile,
      icon: Icons.drive_file_rename_outline,
      onPressed: slice.isBusy
          ? null
          : () => unawaited(
              showRenameLocalFileModal(
                context,
                currentFileName: slice.localFileName,
              ),
            ),
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
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (
          isBusy: model.isBusy,
          supportsNativeDirectoryPicker: model.supportsNativeDirectoryPicker,
        ),
      ),
    );
    return _LocalActionButton(
      buttonKey: const ValueKey<String>('settings_select_local_button'),
      label: localizations.actionSelectLocalFile,
      icon: Icons.file_open_outlined,
      onPressed: slice.isBusy
          ? null
          : () => _handleSelect(
              context,
              ref,
              supportsNativePicker: slice.supportsNativeDirectoryPicker,
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
            .read(settingsV2ControllerProvider.notifier)
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
class _LocalStorageCardBody extends ConsumerWidget {
  /// Creates a [_LocalStorageCardBody].
  const _LocalStorageCardBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final gap = UiThemeTokens.of(context).spacing.space3;
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (
          isBusy: model.isBusy,
          localWatchEnabled: model.localWatchEnabled,
          resolvedLocalPath: model.resolvedLocalPath,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UiField(
          key: const ValueKey<String>('settings_resolved_local_path_field'),
          kind: UiFieldKind.readOnlyDisplay,
          label: localizations.resolvedLocalPathLabel,
          displayValue: slice.resolvedLocalPath,
        ),
        SizedBox(height: gap),
        const _LocalActionsGrid(),
        SizedBox(height: gap),
        UiToggleRow(
          key: const ValueKey<String>('settings_local_watch_toggle'),
          label: localizations.localWatchLabel,
          description: localizations.localWatchDescription,
          value: slice.localWatchEnabled,
          enabled: !slice.isBusy,
          onChanged: (enabled) => _commitLocalWatch(context, ref, enabled),
        ),
      ],
    );
  }

  /// Commits external file watching preference via [SettingsV2Controller.setLocalWatchEnabled].
  void _commitLocalWatch(BuildContext context, WidgetRef ref, bool enabled) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsV2ControllerProvider.notifier)
          .setLocalWatchEnabled(enabled, locale: locale),
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
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (
          isBusy: model.isBusy,
          localFileBaseName: model.localFileBaseName,
          localFileName: model.localFileName,
        ),
      ),
    );
    return _LocalActionButton(
      buttonKey: const ValueKey<String>('settings_wipe_local_button'),
      label: localizations.actionDelete,
      semanticLabel: localizations.actionWipeLocalFile,
      icon: Icons.delete_outline_rounded,
      variant: UiButtonVariant.danger,
      onPressed: slice.isBusy
          ? null
          : () => unawaited(
              showWipeTdfModal(
                context,
                isRemote: false,
                fileName: slice.localFileName,
                baseName: slice.localFileBaseName,
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
    required this.workspaceName,
    required this.statusBanner,
    required this.storageMode,
    required this.serverUrlController,
    required this.usernameController,
    required this.passwordController,
    required this.filePathController,
    required this.onBack,
    required this.onDismissBanner,
  });

  /// Controller bound to the WebDAV remote file path input.
  final TextEditingController filePathController;

  /// Callback returning to the primary Tasks view.
  final VoidCallback onBack;

  /// Callback dismissing [statusBanner].
  final VoidCallback onDismissBanner;

  /// Controller bound to the WebDAV password input.
  final TextEditingController passwordController;

  /// Controller bound to the WebDAV server URL input.
  final TextEditingController serverUrlController;

  /// Active top status banner, or `null` when hidden.
  final SettingsStatusBannerViewModel? statusBanner;

  /// Active workspace persistence storage mode.
  final ShellStorageMode storageMode;

  /// Controller bound to the WebDAV username input.
  final TextEditingController usernameController;

  /// Display name of the currently active workspace.
  final String workspaceName;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UiPageHeader(
          backLabel: localizations.actionBackToTasks,
          onBack: onBack,
          title: localizations.settingsTitle,
          subtitle: localizations.settingsWorkspaceSubtitle(workspaceName),
        ),
        if (statusBanner case final banner?)
          _SettingsStatusBannerSection(
            banner: banner,
            onDismiss: onDismissBanner,
          ),
        SizedBox(height: tokens.spacing.space4),
        const _SettingsPreferenceGrid(),
        if (_usesLocalStorage(storageMode)) ...<Widget>[
          SizedBox(height: tokens.spacing.sectionGridGap),
          const _LocalStorageCard(),
        ],
        if (_usesWebDavStorage(storageMode)) ...<Widget>[
          SizedBox(height: tokens.spacing.sectionGridGap),
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

/// Top-spaced status banner section rendered inside [_SettingsScrollContent].
class _SettingsStatusBannerSection extends StatelessWidget {
  /// Creates a [_SettingsStatusBannerSection].
  const _SettingsStatusBannerSection({
    required this.banner,
    required this.onDismiss,
  });

  /// Active settings status banner projection.
  final SettingsStatusBannerViewModel banner;

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
        tone: UiV2IconMapper.bannerTone(banner.tone),
        message: banner.message,
        dismissTooltip: localizations.actionDismiss,
        onDismiss: onDismiss,
      ),
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
    final initial = ref.read(settingsV2ControllerProvider);
    _serverUrlController = TextEditingController(text: initial.webDavServerUrl);
    _usernameController = TextEditingController(text: initial.webDavUsername);
    _passwordController = TextEditingController(text: initial.webDavPassword);
    _filePathController = TextEditingController(text: initial.webDavFilePath);
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
    ref.listen<SettingsV2ViewModel>(
      settingsV2ControllerProvider,
      _handleViewModelChanged,
    );
    final tokens = UiThemeTokens.of(context);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);
    final shellSlice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (
          statusBanner: model.statusBanner,
          storageMode: model.storageMode,
          workspaceName: model.workspaceName,
        ),
      ),
    );

    return SingleChildScrollView(
      key: const ValueKey<String>('settings_scroll_view'),
      controller: widget.scrollController,
      padding: tokens.spacing.mainContentPadding(viewport),
      child: _SettingsScrollContent(
        workspaceName: shellSlice.workspaceName,
        statusBanner: shellSlice.statusBanner,
        storageMode: shellSlice.storageMode,
        serverUrlController: _serverUrlController,
        usernameController: _usernameController,
        passwordController: _passwordController,
        filePathController: _filePathController,
        onBack: _handleBack,
        onDismissBanner: _handleDismissBanner,
      ),
    );
  }

  /// Navigates back to the primary Tasks view via [AppShellController.openView].
  void _handleBack() {
    ref.read(appShellControllerProvider.notifier).openView(ShellView.tasks);
  }

  /// Dismisses the currently visible top status banner.
  void _handleDismissBanner() {
    ref.read(settingsV2ControllerProvider.notifier).dismissStatusBanner();
  }

  /// Synchronizes the four WebDAV controllers when external state resets or updates draft values.
  void _handleViewModelChanged(
    SettingsV2ViewModel? previous,
    SettingsV2ViewModel next,
  ) {
    _syncController(_serverUrlController, next.webDavServerUrl);
    _syncController(_usernameController, next.webDavUsername);
    _syncController(_passwordController, next.webDavPassword);
    _syncController(_filePathController, next.webDavFilePath);
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
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (isBusy: model.isBusy, storageMode: model.storageMode),
      ),
    );

    return _SettingsAutoSavedCard(
      cardKey: const ValueKey<String>('settings_storage_mode_card'),
      icon: Icons.layers_outlined,
      title: localizations.storageModeSectionTitle,
      description: localizations.storageModeSectionDescription,
      child: UiSegmentedControl<ShellStorageMode>(
        key: const ValueKey<String>('settings_storage_mode_control'),
        value: slice.storageMode,
        enabled: !slice.isBusy,
        semanticLabel: localizations.storageModeSectionTitle,
        segments: _storageModeSegments(localizations),
        onChanged: (next) => _commitStorageMode(context, ref, next),
      ),
    );
  }

  /// Commits storage mode immediately via [SettingsV2Controller.setStorageMode].
  void _commitStorageMode(
    BuildContext context,
    WidgetRef ref,
    ShellStorageMode next,
  ) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsV2ControllerProvider.notifier)
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
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (isBusy: model.isBusy, timeZoneMode: model.timeZoneMode),
      ),
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
          UiSegmentedControl<ShellTimeZoneMode>(
            key: const ValueKey<String>('settings_timezone_mode_control'),
            value: slice.timeZoneMode,
            enabled: !slice.isBusy,
            semanticLabel: localizations.timeZoneSectionTitle,
            segments: _timeZoneModeSegments(localizations),
            onChanged: (next) => _commitTimeZoneMode(context, ref, next),
          ),
          if (slice.timeZoneMode == ShellTimeZoneMode.manual) ...<Widget>[
            SizedBox(height: tokens.spacing.space3),
            const _TimeZoneOffsetSelect(),
          ],
        ],
      ),
    );
  }

  /// Commits time zone mode immediately via [SettingsV2Controller.setTimeZoneMode].
  void _commitTimeZoneMode(
    BuildContext context,
    WidgetRef ref,
    ShellTimeZoneMode next,
  ) {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsV2ControllerProvider.notifier)
          .setTimeZoneMode(next, locale: locale),
    );
  }
}

/// Conditional 37-offset UTC select dropdown shown inside [_TimeZoneCard] in manual mode.
class _TimeZoneOffsetSelect extends ConsumerWidget {
  /// Creates a [_TimeZoneOffsetSelect].
  const _TimeZoneOffsetSelect();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (
          isBusy: model.isBusy,
          manualOffsetMinutes: model.manualTimeZoneOffsetMinutes,
          supportedUtcOffsets: model.supportedUtcOffsets,
        ),
      ),
    );

    return UiField(
      key: const ValueKey<String>('settings_timezone_offset_select'),
      kind: UiFieldKind.select,
      label: localizations.timeZoneOffsetLabel,
      selectValue: '${slice.manualOffsetMinutes}',
      selectOptions: _utcOffsetOptions(slice.supportedUtcOffsets),
      enabled: !slice.isBusy,
      onSelectChanged: (raw) => _commitUtcOffset(context, ref, raw),
    );
  }

  /// Parses [raw] offset minutes and commits immediately via [SettingsV2Controller.setManualTimeZoneOffsetMinutes].
  void _commitUtcOffset(BuildContext context, WidgetRef ref, String raw) {
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      return;
    }
    final locale = Localizations.localeOf(context);
    unawaited(
      ref
          .read(settingsV2ControllerProvider.notifier)
          .setManualTimeZoneOffsetMinutes(parsed, locale: locale),
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
      settingsV2ControllerProvider.select(
        (model) => (filePathError: model.filePathError, isBusy: model.isBusy),
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
          .read(settingsV2ControllerProvider.notifier)
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
      settingsV2ControllerProvider.select(
        (model) => (isBusy: model.isBusy, passwordError: model.passwordError),
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
          .read(settingsV2ControllerProvider.notifier)
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
      settingsV2ControllerProvider.select(
        (model) => model.resolvedWebDavEndpoint,
      ),
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
      settingsV2ControllerProvider.select(
        (model) => (isBusy: model.isBusy, serverUrlError: model.serverUrlError),
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
          .read(settingsV2ControllerProvider.notifier)
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
      settingsV2ControllerProvider.select((model) => model.isWebDavDirty),
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
      settingsV2ControllerProvider.select(
        (model) => (isBusy: model.isBusy, usernameError: model.usernameError),
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
          .read(settingsV2ControllerProvider.notifier)
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
    final slice = ref.watch(
      settingsV2ControllerProvider.select(
        (model) => (
          isBusy: model.isBusy,
          isWebDavConfigured: model.isWebDavConfigured,
          remoteFileBaseName: model.remoteFileBaseName,
          webDavFilePath: model.webDavFilePath,
        ),
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: UiButton(
        key: const ValueKey<String>('settings_wipe_remote_button'),
        label: localizations.actionWipeRemoteFile,
        leadingIcon: Icons.delete_outline_rounded,
        variant: UiButtonVariant.danger,
        density: UiButtonDensity.compact,
        onPressed: (slice.isWebDavConfigured && !slice.isBusy)
            ? () => _openWipeModal(
                context,
                filePath: slice.webDavFilePath,
                baseName: slice.remoteFileBaseName,
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

/// Maps [option] exhaustively to its localized deadline lead-window display label.
String _dueLeadLabel(
  ShellDueLeadOption option,
  AppLocalizations localizations,
) {
  return switch (option) {
    ShellDueLeadOption.off => localizations.dueLeadWindowOff,
    ShellDueLeadOption.atDue => localizations.dueLeadWindowAtDue,
    ShellDueLeadOption.hours12 => localizations.dueLeadWindow12Hours,
    ShellDueLeadOption.hours24 => localizations.dueLeadWindow24Hours,
    ShellDueLeadOption.hours48 => localizations.dueLeadWindow48Hours,
    ShellDueLeadOption.days7 => localizations.dueLeadWindow7Days,
  };
}

/// Builds localized select options for every [ShellDueLeadOption].
List<UiSelectOption> _dueLeadOptions(AppLocalizations localizations) {
  return <UiSelectOption>[
    for (final option in ShellDueLeadOption.values)
      UiSelectOption(
        value: option.name,
        label: _dueLeadLabel(option, localizations),
      ),
  ];
}

/// Builds segmented options for [ShellLanguageOption].
List<UiSegment<ShellLanguageOption>> _languageSegments(
  AppLocalizations localizations,
) {
  return <UiSegment<ShellLanguageOption>>[
    UiSegment<ShellLanguageOption>(
      value: ShellLanguageOption.system,
      label: localizations.languageSystem,
    ),
    UiSegment<ShellLanguageOption>(
      value: ShellLanguageOption.english,
      label: localizations.languageEnglish,
    ),
    UiSegment<ShellLanguageOption>(
      value: ShellLanguageOption.german,
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
String _logLevelLabel(
  DiagnosticLogLevel level,
  AppLocalizations localizations,
) {
  return switch (level) {
    DiagnosticLogLevel.debug => localizations.logLevelDebug,
    DiagnosticLogLevel.info => localizations.logLevelInfo,
    DiagnosticLogLevel.warn => localizations.logLevelWarn,
    DiagnosticLogLevel.error => localizations.logLevelError,
    DiagnosticLogLevel.crash => level.label,
  };
}

/// Builds localized select options for every [DiagnosticLogLevel].
List<UiSelectOption> _logLevelOptions(AppLocalizations localizations) {
  return <UiSelectOption>[
    for (final level in DiagnosticLogLevel.values)
      UiSelectOption(
        value: level.name,
        label: _logLevelLabel(level, localizations),
      ),
  ];
}

/// Maps [mode] exhaustively to its localized diagnostic log storage label.
String _logStorageLabel(ShellStorageMode mode, AppLocalizations localizations) {
  return switch (mode) {
    ShellStorageMode.local => localizations.logStorageLocal,
    ShellStorageMode.webdav => localizations.logStorageWebDav,
    ShellStorageMode.both => localizations.logStorageBoth,
  };
}

/// Builds localized select options for diagnostic log storage modes.
List<UiSelectOption> _logStorageOptions(AppLocalizations localizations) {
  return <UiSelectOption>[
    for (final mode in ShellStorageMode.values)
      UiSelectOption(
        value: mode.name,
        label: _logStorageLabel(mode, localizations),
      ),
  ];
}

/// Parses [raw] into a [DiagnosticLogLevel], returning `null` if unknown.
DiagnosticLogLevel? _parseDiagnosticLogLevel(String raw) {
  for (final level in DiagnosticLogLevel.values) {
    if (level.name == raw) {
      return level;
    }
  }
  return null;
}

/// Parses [raw] into a [ShellDueLeadOption], returning `null` if unknown.
ShellDueLeadOption? _parseDueLeadOption(String raw) {
  for (final option in ShellDueLeadOption.values) {
    if (option.name == raw) {
      return option;
    }
  }
  return null;
}

/// Parses [raw] into a [ShellStorageMode], returning `null` if unknown.
ShellStorageMode? _parseStorageMode(String raw) {
  for (final mode in ShellStorageMode.values) {
    if (mode.name == raw) {
      return mode;
    }
  }
  return null;
}

/// Builds segmented options for [ShellStorageMode].
List<UiSegment<ShellStorageMode>> _storageModeSegments(
  AppLocalizations localizations,
) {
  return <UiSegment<ShellStorageMode>>[
    UiSegment<ShellStorageMode>(
      value: ShellStorageMode.local,
      label: localizations.storageModeLocal,
    ),
    UiSegment<ShellStorageMode>(
      value: ShellStorageMode.webdav,
      label: localizations.storageModeWebDav,
    ),
    UiSegment<ShellStorageMode>(
      value: ShellStorageMode.both,
      label: localizations.storageModeBoth,
    ),
  ];
}

/// Builds segmented options for [ShellThemeMode].
List<UiSegment<ShellThemeMode>> _themeModeSegments(
  AppLocalizations localizations,
) {
  return <UiSegment<ShellThemeMode>>[
    UiSegment<ShellThemeMode>(
      value: ShellThemeMode.system,
      label: localizations.themeSystem,
    ),
    UiSegment<ShellThemeMode>(
      value: ShellThemeMode.light,
      label: localizations.themeLight,
    ),
    UiSegment<ShellThemeMode>(
      value: ShellThemeMode.dark,
      label: localizations.themeDark,
    ),
  ];
}

/// Builds segmented options for [AppThemePresetKey].
List<UiSegment<AppThemePresetKey>> _themePaletteSegments(
  AppLocalizations localizations,
) {
  return <UiSegment<AppThemePresetKey>>[
    UiSegment<AppThemePresetKey>(
      value: AppThemePresetKey.calm,
      label: localizations.themePaletteCalm,
    ),
    UiSegment<AppThemePresetKey>(
      value: AppThemePresetKey.plumUmber,
      label: localizations.themePalettePlumUmber,
    ),
  ];
}

/// Builds segmented options for [ShellTimeZoneMode].
List<UiSegment<ShellTimeZoneMode>> _timeZoneModeSegments(
  AppLocalizations localizations,
) {
  return <UiSegment<ShellTimeZoneMode>>[
    UiSegment<ShellTimeZoneMode>(
      value: ShellTimeZoneMode.automatic,
      label: localizations.timeZoneModeAutomatic,
    ),
    UiSegment<ShellTimeZoneMode>(
      value: ShellTimeZoneMode.manual,
      label: localizations.timeZoneModeManual,
    ),
  ];
}

/// Returns `true` when [mode] persists tasks in a local `.tdf` file.
bool _usesLocalStorage(ShellStorageMode mode) {
  return switch (mode) {
    ShellStorageMode.local || ShellStorageMode.both => true,
    ShellStorageMode.webdav => false,
  };
}

/// Returns `true` when [mode] synchronizes tasks with a WebDAV server.
bool _usesWebDavStorage(ShellStorageMode mode) {
  return switch (mode) {
    ShellStorageMode.webdav || ShellStorageMode.both => true,
    ShellStorageMode.local => false,
  };
}

/// Maps all 37 [offsets] into [UiSelectOption] entries keyed by signed offset minutes.
List<UiSelectOption> _utcOffsetOptions(List<UtcOffsetOptionViewModel> offsets) {
  return <UiSelectOption>[
    for (final offset in offsets)
      UiSelectOption(value: '${offset.offsetMinutes}', label: offset.label),
  ];
}
