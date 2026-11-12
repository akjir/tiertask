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
import '../../models/webdav_config.dart';
import '../../services/app_logger.dart';
import 'log_viewer_dialog.dart';

/// Card for configuring opt-in diagnostic logging, minimum log level, and log storage mode.
class DiagnosticsSelectionCard extends StatelessWidget {
  /// Creates a [DiagnosticsSelectionCard].
  const DiagnosticsSelectionCard({
    super.key,
    required this.diagnosticsEnabled,
    required this.selectedLogLevel,
    required this.selectedLogStorageMode,
    required this.onDiagnosticsEnabledChanged,
    required this.onLogLevelChanged,
    required this.onLogStorageModeChanged,
  });

  /// Whether opt-in diagnostic logging is currently enabled.
  final bool diagnosticsEnabled;

  /// Callback invoked when the user toggles the diagnostic logging switch.
  final ValueChanged<bool> onDiagnosticsEnabledChanged;

  /// Callback invoked when the user selects a new minimum [LogLevel].
  final ValueChanged<LogLevel> onLogLevelChanged;

  /// Callback invoked when the user selects a new log [StorageMode].
  final ValueChanged<StorageMode> onLogStorageModeChanged;

  /// Currently selected minimum [LogLevel].
  final LogLevel selectedLogLevel;

  /// Currently selected log [StorageMode].
  final StorageMode selectedLogStorageMode;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SettingsSectionCard(
      icon: Icons.bug_report_outlined,
      title: localizations.diagnosticsSectionTitle,
      description: localizations.diagnosticsSectionDescription,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Switch(
            key: const ValueKey('settings_diagnostics_switch'),
            value: diagnosticsEnabled,
            onChanged: onDiagnosticsEnabledChanged,
          ),
          if (diagnosticsEnabled) ...[
            const SizedBox(height: 8),
            _DiagnosticsDetailsPanel(
              selectedLogLevel: selectedLogLevel,
              selectedLogStorageMode: selectedLogStorageMode,
              onLogLevelChanged: onLogLevelChanged,
              onLogStorageModeChanged: onLogStorageModeChanged,
            ),
          ],
        ],
      ),
    );
  }
}

/// Card for choosing the application display language (`System`, `English`, or `Deutsch`).
class LanguageSelectionCard extends StatelessWidget {
  /// Creates a [LanguageSelectionCard].
  const LanguageSelectionCard({
    super.key,
    required this.selectedLanguage,
    required this.onLanguageChanged,
  });

  /// Callback invoked when the user selects a new [AppLanguage].
  final ValueChanged<AppLanguage> onLanguageChanged;

  /// Currently selected [AppLanguage].
  final AppLanguage selectedLanguage;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SettingsSectionCard(
      icon: Icons.language_rounded,
      title: localizations.languageSectionTitle,
      description: localizations.languageSectionDescription,
      child: _PreferenceSegmentedButton<AppLanguage>(
        selectedValue: selectedLanguage,
        onChanged: onLanguageChanged,
        segments: [
          ButtonSegment(
            value: AppLanguage.system,
            label: Text(localizations.languageSystem),
          ),
          ButtonSegment(
            value: AppLanguage.english,
            label: Text(localizations.languageEnglish),
          ),
          ButtonSegment(
            value: AppLanguage.german,
            label: Text(localizations.languageGerman),
          ),
        ],
      ),
    );
  }
}

/// Card for enabling or disabling foreground location determination.
class LocationSelectionCard extends StatelessWidget {
  /// Creates a [LocationSelectionCard].
  const LocationSelectionCard({
    super.key,
    required this.locationEnabled,
    required this.onLocationEnabledChanged,
  });

  /// Whether foreground location determination is currently enabled.
  final bool locationEnabled;

  /// Callback invoked when the user toggles location determination.
  final ValueChanged<bool> onLocationEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SettingsSectionCard(
      icon: Icons.location_on_outlined,
      title: localizations.locationSectionTitle,
      description: localizations.locationSectionDescription,
      child: _PreferenceSegmentedButton<bool>(
        buttonKey: const ValueKey('settings_location_segmented_button'),
        selectedValue: locationEnabled,
        onChanged: onLocationEnabledChanged,
        segments: [
          ButtonSegment<bool>(
            value: false,
            label: Text(localizations.locationOff),
          ),
          ButtonSegment<bool>(
            value: true,
            label: Text(localizations.locationOn),
          ),
        ],
      ),
    );
  }
}

/// Groups the language, theme, color palette, time zone, location, diagnostics, and storage mode preference cards.
class SettingsPreferenceCards extends StatelessWidget {
  /// Creates [SettingsPreferenceCards].
  const SettingsPreferenceCards({
    super.key,
    required this.config,
    required this.onPreferenceChanged,
  });

  /// Current [WebDavConfig] holding the selected preference states.
  final WebDavConfig config;

  /// Callback invoked when any preference card selection changes.
  final ValueChanged<WebDavConfig> onPreferenceChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        LanguageSelectionCard(
          selectedLanguage: config.language,
          onLanguageChanged: (value) =>
              onPreferenceChanged(config.copyWith(language: value)),
        ),
        ThemeSelectionCard(
          selectedThemeMode: config.themeMode,
          onThemeModeChanged: (value) =>
              onPreferenceChanged(config.copyWith(themeMode: value)),
        ),
        ThemePaletteSelectionCard(
          selectedThemePalette: config.themePalette,
          onThemePaletteChanged: (value) =>
              onPreferenceChanged(config.copyWith(themePalette: value)),
        ),
        TimeZoneSelectionCard(
          selectedTimeZoneMode: config.timeZoneMode,
          manualOffsetMinutes: config.manualTimeZoneOffsetMinutes,
          onTimeZoneModeChanged: (value) =>
              onPreferenceChanged(config.copyWith(timeZoneMode: value)),
          onManualOffsetChanged: (value) => onPreferenceChanged(
            config.copyWith(manualTimeZoneOffsetMinutes: value),
          ),
        ),
        LocationSelectionCard(
          locationEnabled: config.locationEnabled,
          onLocationEnabledChanged: (value) =>
              onPreferenceChanged(config.copyWith(locationEnabled: value)),
        ),
        DiagnosticsSelectionCard(
          diagnosticsEnabled: config.diagnosticsEnabled,
          selectedLogLevel: config.logLevel,
          selectedLogStorageMode: config.logStorageMode,
          onDiagnosticsEnabledChanged: (value) =>
              onPreferenceChanged(config.copyWith(diagnosticsEnabled: value)),
          onLogLevelChanged: (value) =>
              onPreferenceChanged(config.copyWith(logLevel: value)),
          onLogStorageModeChanged: (value) =>
              onPreferenceChanged(config.copyWith(logStorageMode: value)),
        ),
        StorageModeSelectionCard(
          selectedStorageMode: config.storageMode,
          onStorageModeChanged: (value) =>
              onPreferenceChanged(config.copyWith(storageMode: value)),
        ),
      ],
    );
  }
}

/// Shared Material 3 card container with an icon, title, description, and body [child].
class SettingsSectionCard extends StatelessWidget {
  /// Creates a [SettingsSectionCard].
  const SettingsSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  /// Interactive content below the description.
  final Widget child;

  /// Section subtitle description.
  final String description;

  /// Leading header icon.
  final IconData icon;

  /// Section title text.
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      color: theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// Card for choosing the TDF storage mode (`Local`, `WebDAV`, or `Both`).
class StorageModeSelectionCard extends StatelessWidget {
  /// Creates a [StorageModeSelectionCard].
  const StorageModeSelectionCard({
    super.key,
    required this.selectedStorageMode,
    required this.onStorageModeChanged,
  });

  /// Callback invoked when the user selects a new [StorageMode].
  final ValueChanged<StorageMode> onStorageModeChanged;

  /// Currently selected [StorageMode].
  final StorageMode selectedStorageMode;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SettingsSectionCard(
      icon: Icons.storage_rounded,
      title: localizations.storageModeSectionTitle,
      description: localizations.storageModeSectionDescription,
      child: _PreferenceSegmentedButton<StorageMode>(
        selectedValue: selectedStorageMode,
        onChanged: onStorageModeChanged,
        segments: [
          ButtonSegment(
            value: StorageMode.local,
            label: Text(localizations.storageModeLocal),
          ),
          ButtonSegment(
            value: StorageMode.webdav,
            label: Text(localizations.storageModeWebDav),
          ),
          ButtonSegment(
            value: StorageMode.both,
            label: Text(localizations.storageModeBoth),
          ),
        ],
      ),
    );
  }
}

/// Card for choosing the Material 3 color palette (`Slate` or `Navy`).
class ThemePaletteSelectionCard extends StatelessWidget {
  /// Creates a [ThemePaletteSelectionCard].
  const ThemePaletteSelectionCard({
    super.key,
    required this.selectedThemePalette,
    required this.onThemePaletteChanged,
  });

  /// Callback invoked when the user selects a new [AppThemePalette].
  final ValueChanged<AppThemePalette> onThemePaletteChanged;

  /// Currently selected [AppThemePalette].
  final AppThemePalette selectedThemePalette;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SettingsSectionCard(
      icon: Icons.palette_outlined,
      title: localizations.themePaletteSectionTitle,
      description: localizations.themePaletteSectionDescription,
      child: _PreferenceSegmentedButton<AppThemePalette>(
        selectedValue: selectedThemePalette,
        onChanged: onThemePaletteChanged,
        segments: [
          ButtonSegment(
            value: AppThemePalette.slate,
            label: Text(localizations.themePaletteSlate),
          ),
          ButtonSegment(
            value: AppThemePalette.navy,
            label: Text(localizations.themePaletteNavy),
          ),
        ],
      ),
    );
  }
}

/// Card for choosing the application color theme (`System`, `Light`, or `Dark`).
class ThemeSelectionCard extends StatelessWidget {
  /// Creates a [ThemeSelectionCard].
  const ThemeSelectionCard({
    super.key,
    required this.selectedThemeMode,
    required this.onThemeModeChanged,
  });

  /// Callback invoked when the user selects a new [AppThemeMode].
  final ValueChanged<AppThemeMode> onThemeModeChanged;

  /// Currently selected [AppThemeMode].
  final AppThemeMode selectedThemeMode;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SettingsSectionCard(
      icon: Icons.brightness_6_outlined,
      title: localizations.themeSectionTitle,
      description: localizations.themeSectionDescription,
      child: _PreferenceSegmentedButton<AppThemeMode>(
        selectedValue: selectedThemeMode,
        onChanged: onThemeModeChanged,
        segments: [
          ButtonSegment(
            value: AppThemeMode.system,
            label: Text(localizations.themeSystem),
          ),
          ButtonSegment(
            value: AppThemeMode.light,
            label: Text(localizations.themeLight),
          ),
          ButtonSegment(
            value: AppThemeMode.dark,
            label: Text(localizations.themeDark),
          ),
        ],
      ),
    );
  }
}

/// Card for choosing whether the local time zone is detected automatically or configured manually.
class TimeZoneSelectionCard extends StatelessWidget {
  /// Creates a [TimeZoneSelectionCard].
  const TimeZoneSelectionCard({
    super.key,
    required this.selectedTimeZoneMode,
    required this.manualOffsetMinutes,
    required this.onTimeZoneModeChanged,
    required this.onManualOffsetChanged,
  });

  /// Currently selected manual UTC offset in minutes.
  final int manualOffsetMinutes;

  /// Callback invoked when the user selects a manual UTC offset.
  final ValueChanged<int> onManualOffsetChanged;

  /// Callback invoked when the user selects a new [AppTimeZoneMode].
  final ValueChanged<AppTimeZoneMode> onTimeZoneModeChanged;

  /// Currently selected [AppTimeZoneMode].
  final AppTimeZoneMode selectedTimeZoneMode;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final effectiveOffset =
        WebDavConfig.supportedUtcOffsetMinutes.contains(manualOffsetMinutes)
        ? manualOffsetMinutes
        : 0;

    return SettingsSectionCard(
      icon: Icons.schedule_rounded,
      title: localizations.timeZoneSectionTitle,
      description: localizations.timeZoneSectionDescription,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PreferenceSegmentedButton<AppTimeZoneMode>(
            selectedValue: selectedTimeZoneMode,
            onChanged: onTimeZoneModeChanged,
            segments: [
              ButtonSegment(
                value: AppTimeZoneMode.automatic,
                label: Text(localizations.timeZoneModeAutomatic),
              ),
              ButtonSegment(
                value: AppTimeZoneMode.manual,
                label: Text(localizations.timeZoneModeManual),
              ),
            ],
          ),
          if (selectedTimeZoneMode == AppTimeZoneMode.manual) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: effectiveOffset,
              decoration: InputDecoration(
                labelText: localizations.timeZoneOffsetLabel,
                prefixIcon: const Icon(Icons.public_rounded),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final offset in WebDavConfig.supportedUtcOffsetMinutes)
                  DropdownMenuItem<int>(
                    value: offset,
                    child: Text(WebDavConfig.formatUtcOffset(offset)),
                  ),
              ],
              onChanged: (selected) {
                if (selected != null) {
                  onManualOffsetChanged(selected);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Expanded controls for log level, log storage mode, and opening [LogViewerDialog].
class _DiagnosticsDetailsPanel extends StatelessWidget {
  const _DiagnosticsDetailsPanel({
    required this.selectedLogLevel,
    required this.selectedLogStorageMode,
    required this.onLogLevelChanged,
    required this.onLogStorageModeChanged,
  });

  final ValueChanged<LogLevel> onLogLevelChanged;
  final ValueChanged<StorageMode> onLogStorageModeChanged;
  final LogLevel selectedLogLevel;
  final StorageMode selectedLogStorageMode;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(localizations.logLevelLabel, style: labelStyle),
        _LogLevelSelector(
          selectedLogLevel: selectedLogLevel,
          onLogLevelChanged: onLogLevelChanged,
        ),
        Text(localizations.logStorageLabel, style: labelStyle),
        _LogStorageModeSelector(
          selectedLogStorageMode: selectedLogStorageMode,
          onLogStorageModeChanged: onLogStorageModeChanged,
        ),
        const _DiagnosticsLogFileRow(),
      ],
    );
  }
}

/// Displays the resolved log filename and a button to open [LogViewerDialog].
class _DiagnosticsLogFileRow extends StatelessWidget {
  const _DiagnosticsLogFileRow();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Text(localizations.logMetadataFile(AppLogger.activeLogFileName)),
        OutlinedButton.icon(
          key: const ValueKey('settings_open_log_viewer_button'),
          onPressed: () => showLogViewerDialog(context),
          icon: const Icon(Icons.article_outlined, size: 18),
          label: Text(localizations.diagnosticLogTitle),
        ),
      ],
    );
  }
}

/// Segmented selector for minimum [LogLevel].
class _LogLevelSelector extends StatelessWidget {
  const _LogLevelSelector({
    required this.selectedLogLevel,
    required this.onLogLevelChanged,
  });

  final ValueChanged<LogLevel> onLogLevelChanged;
  final LogLevel selectedLogLevel;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _PreferenceSegmentedButton<LogLevel>(
      buttonKey: const ValueKey('settings_log_level_segmented'),
      selectedValue: selectedLogLevel,
      onChanged: onLogLevelChanged,
      segments: [
        ButtonSegment<LogLevel>(
          value: LogLevel.debug,
          label: Text(localizations.logLevelDebug),
        ),
        ButtonSegment<LogLevel>(
          value: LogLevel.info,
          label: Text(localizations.logLevelInfo),
        ),
        ButtonSegment<LogLevel>(
          value: LogLevel.warn,
          label: Text(localizations.logLevelWarn),
        ),
        ButtonSegment<LogLevel>(
          value: LogLevel.error,
          label: Text(localizations.logLevelError),
        ),
      ],
    );
  }
}

/// Segmented selector for diagnostic log [StorageMode].
class _LogStorageModeSelector extends StatelessWidget {
  const _LogStorageModeSelector({
    required this.selectedLogStorageMode,
    required this.onLogStorageModeChanged,
  });

  final ValueChanged<StorageMode> onLogStorageModeChanged;
  final StorageMode selectedLogStorageMode;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _PreferenceSegmentedButton<StorageMode>(
      buttonKey: const ValueKey('settings_log_storage_segmented'),
      selectedValue: selectedLogStorageMode,
      onChanged: onLogStorageModeChanged,
      segments: [
        ButtonSegment<StorageMode>(
          value: StorageMode.local,
          label: Text(localizations.logStorageLocal),
        ),
        ButtonSegment<StorageMode>(
          value: StorageMode.webdav,
          label: Text(localizations.logStorageWebDav),
        ),
        ButtonSegment<StorageMode>(
          value: StorageMode.both,
          label: Text(localizations.logStorageBoth),
        ),
      ],
    );
  }
}

/// Full-width single-select [SegmentedButton] used inside settings preference cards.
class _PreferenceSegmentedButton<T> extends StatelessWidget {
  /// Creates a [_PreferenceSegmentedButton].
  const _PreferenceSegmentedButton({
    this.buttonKey,
    required this.segments,
    required this.selectedValue,
    required this.onChanged,
  });

  /// Optional widget key for the underlying [SegmentedButton].
  final Key? buttonKey;

  /// Callback invoked when the user selects a segment.
  final ValueChanged<T> onChanged;

  /// Segments rendered inside the button.
  final List<ButtonSegment<T>> segments;

  /// Currently selected value.
  final T selectedValue;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        key: buttonKey,
        segments: segments,
        selected: <T>{selectedValue},
        onSelectionChanged: (selection) {
          if (selection.isNotEmpty) {
            onChanged(selection.first);
          }
        },
      ),
    );
  }
}
