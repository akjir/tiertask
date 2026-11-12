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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/webdav_config.dart';
import '../../providers/config_providers.dart';
import '../../repositories/local_file_repository.dart';
import 'local_tdf_file_dialogs.dart';
import 'settings_preference_cards.dart';

/// Horizontal row of four local TDF file action buttons (`Select`, `Move`, `Rename`, `Delete`).
class LocalStorageActionsRow extends StatelessWidget {
  /// Creates a [LocalStorageActionsRow].
  const LocalStorageActionsRow({
    super.key,
    this.onSelectLocalFile,
    this.onMoveLocalFile,
    this.onRenameLocalFile,
    this.onWipeLocalFile,
  });

  /// Optional callback to move the existing local `.tdf` file to another folder.
  final VoidCallback? onMoveLocalFile;

  /// Optional callback to rename the local `.tdf` file inside its current folder.
  final VoidCallback? onRenameLocalFile;

  /// Optional callback to select an existing `.tdf` file or create a new one.
  final VoidCallback? onSelectLocalFile;

  /// Optional callback to open the confirmation dialog and wipe the local `.tdf` file.
  final VoidCallback? onWipeLocalFile;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      spacing: 8,
      children: [
        _buildExpandedButton(
          const ValueKey('settings_select_local_button'),
          Icons.file_open_outlined,
          localizations.actionSelectLocalFile,
          onSelectLocalFile,
        ),
        _buildExpandedButton(
          const ValueKey('settings_move_local_button'),
          Icons.drive_file_move_outlined,
          localizations.actionMoveLocalFile,
          onMoveLocalFile,
        ),
        _buildExpandedButton(
          const ValueKey('settings_rename_local_button'),
          Icons.drive_file_rename_outline,
          localizations.actionRenameLocalFile,
          onRenameLocalFile,
        ),
        Expanded(
          child: WipeStorageButton(
            buttonKey: const ValueKey('settings_wipe_local_button'),
            compact: true,
            label: localizations.actionDelete,
            onPressed: onWipeLocalFile,
          ),
        ),
      ],
    );
  }

  /// Builds an [Expanded] compact outlined button with [buttonKey], [icon], [label], and [onPressed].
  Widget _buildExpandedButton(
    Key buttonKey,
    IconData icon,
    String label,
    VoidCallback? onPressed,
  ) {
    return Expanded(
      child: OutlinedButton.icon(
        key: buttonKey,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// Card for previewing the resolved local `.tdf` file path and managing the file via four side-by-side actions.
class LocalStorageSection extends StatelessWidget {
  /// Creates a [LocalStorageSection].
  const LocalStorageSection({
    super.key,
    required this.resolvedLocalPath,
    this.onSelectLocalFile,
    this.onMoveLocalFile,
    this.onRenameLocalFile,
    this.onWipeLocalFile,
  });

  /// Pattern matching POSIX (`/`) or Windows (`\`) path separators.
  static final RegExp _pathSeparatorPattern = RegExp(r'[/\\]');

  /// Optional callback to move the local `.tdf` file into another directory.
  final VoidCallback? onMoveLocalFile;

  /// Optional callback to rename the local `.tdf` file in the current directory.
  final VoidCallback? onRenameLocalFile;

  /// Optional callback to select an existing `.tdf` file or create a new one.
  final VoidCallback? onSelectLocalFile;

  /// Optional callback to open the confirmation dialog and wipe the local `.tdf` file.
  final VoidCallback? onWipeLocalFile;

  /// Resolved local filesystem path preview, or `null` if invalid.
  final String? resolvedLocalPath;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final previewPath = resolvedLocalPath;

    return SettingsSectionCard(
      icon: Icons.folder_outlined,
      title: localizations.localSectionTitle,
      description: localizations.localSectionDescription,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          if (previewPath != null)
            ResolvedPathPreview(
              label: localizations.resolvedLocalPathLabel,
              value: previewPath,
            ),
          LocalStorageActionsRow(
            onSelectLocalFile: onSelectLocalFile,
            onMoveLocalFile: onMoveLocalFile,
            onRenameLocalFile: onRenameLocalFile,
            onWipeLocalFile: onWipeLocalFile,
          ),
        ],
      ),
    );
  }

  /// Prompts the user to select, move (`moveDirectory: true`), or rename (`renameOnly: true`) a local `.tdf` file.
  static Future<String?> pickLocalFilePath(
    BuildContext context,
    WidgetRef ref,
    WebDavConfig config, {
    bool moveDirectory = false,
    bool renameOnly = false,
  }) async {
    final baseDirectoryPath = ref.read(localStorageDirectoryPathProvider);
    final repository = LocalFileRepository(
      config: config,
      baseDirectoryPath: baseDirectoryPath,
    );
    final currentDirectory = repository.tryResolveDirectoryPath();
    final currentName = repository.extractFileName();
    if (moveDirectory) {
      final selectedDirectory = await ref.read(directoryPickerProvider)(
        initialDirectory: currentDirectory,
      );
      if (selectedDirectory == null ||
          selectedDirectory.trim().isEmpty ||
          selectedDirectory == currentDirectory) {
        return null;
      }
      return LocalFileRepository.combineDirectoryAndFileName(
        selectedDirectory,
        currentName,
      );
    }
    if (!renameOnly && ref.read(supportsDirectoryPickerProvider)) {
      return ref.read(filePickerProvider)(
        initialDirectory: currentDirectory,
        currentFileName: currentName,
      );
    }
    final chosenName = renameOnly
        ? await showRenameLocalTdfDialog(context, currentFileName: currentName)
        : await showSelectLocalTdfDialog(
            context,
            currentFileName: currentName,
            existingFileNames: ref
                .read(localFileRepositoryProvider)
                .listTdfFileNamesInDirectory(),
          );
    if (chosenName == null ||
        chosenName.trim().isEmpty ||
        (renameOnly && chosenName == currentName)) {
      return null;
    }
    final hasDirectory =
        _pathSeparatorPattern.hasMatch(config.localFilePath) ||
        baseDirectoryPath != null;
    return (hasDirectory && currentDirectory != null)
        ? LocalFileRepository.combineDirectoryAndFileName(
            currentDirectory,
            chosenName,
          )
        : chosenName;
  }
}

/// Monospace preview box displaying a resolved local file path or WebDAV endpoint URI.
class ResolvedPathPreview extends StatelessWidget {
  /// Creates a [ResolvedPathPreview].
  const ResolvedPathPreview({
    super.key,
    required this.label,
    required this.value,
  });

  /// Descriptive header label above the resolved path or URI.
  final String label;

  /// Resolved path or URI string.
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
        spacing: 4,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          SelectableText(
            value,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

/// Destructive outlined button for wiping the local or remote TDF file in settings.
class WipeStorageButton extends StatelessWidget {
  /// Creates a [WipeStorageButton].
  const WipeStorageButton({
    super.key,
    required this.buttonKey,
    required this.label,
    required this.onPressed,
    this.compact = false,
  });

  /// Widget key for the button.
  final Key buttonKey;

  /// Whether to use compact horizontal padding for side-by-side button rows.
  final bool compact;

  /// Localized button label.
  final String label;

  /// Callback invoked when pressed, or `null` when disabled.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      key: buttonKey,
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.error,
        side: BorderSide(color: colorScheme.error),
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 10)
            : null,
      ),
      onPressed: onPressed,
      icon: Icon(Icons.delete_sweep_outlined, size: compact ? 18 : null),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
