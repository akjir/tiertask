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
import '../../models/app_workspace.dart';
import '../../models/task_board.dart';
import '../../models/tdf_location.dart';
import '../../models/tdf_metadata.dart';
import '../../providers/config_providers.dart';
import '../../repositories/app_version_repository.dart';
import '../edit_locations_screen.dart';
import 'app_logo.dart';
import 'log_viewer_dialog.dart';
import 'workspace_dialog.dart';

/// Left-side navigation drawer for workspace switching, labels, locations, and settings.
class HomeDrawer extends StatelessWidget {
  /// Creates a [HomeDrawer].
  const HomeDrawer({
    super.key,
    required this.activeLabelId,
    required this.activeWorkspace,
    required this.board,
    required this.onManageWorkspaces,
    required this.onOpenEditLabels,
    required this.onOpenSettings,
    required this.onSelectLabel,
    required this.onSyncRemote,
    this.onOpenEditLocations,
  });

  final String? activeLabelId;
  final AppWorkspace activeWorkspace;
  final TaskBoard board;
  final VoidCallback onManageWorkspaces;
  final ValueChanged<bool> onOpenEditLabels;
  final ValueChanged<bool>? onOpenEditLocations;
  final VoidCallback onOpenSettings;
  final ValueChanged<String?> onSelectLabel;
  final VoidCallback onSyncRemote;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _DrawerHeader(
                    workspace: activeWorkspace,
                    onManageWorkspaces: onManageWorkspaces,
                  ),
                  _DrawerLabelsSection(
                    activeLabelId: activeLabelId,
                    board: board,
                    onOpenEditLabels: onOpenEditLabels,
                    onSelectLabel: onSelectLabel,
                  ),
                  _DrawerLocationsSection(
                    board: board,
                    onOpenEditLocations: onOpenEditLocations,
                  ),
                  _DrawerFooterSection(
                    board: board,
                    enableLogging: activeWorkspace.config.enableLogging,
                    onOpenSettings: onOpenSettings,
                    onSyncRemote: onSyncRemote,
                  ),
                ],
              ),
            ),
            const _DrawerVersionFooter(),
          ],
        ),
      ),
    );
  }
}

/// Action tile inside [HomeDrawer] that closes the drawer before [onAction].
class _DrawerActionTile extends StatelessWidget {
  /// Creates a [_DrawerActionTile].
  const _DrawerActionTile({
    required this.icon,
    required this.title,
    required this.onAction,
    this.tileKey,
  });

  final IconData icon;
  final VoidCallback onAction;
  final Key? tileKey;
  final String title;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: tileKey,
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.of(context).pop();
        onAction();
      },
    );
  }
}

/// Footer actions inside [HomeDrawer] for sync, preview, logs, and settings.
class _DrawerFooterSection extends StatelessWidget {
  /// Creates a [_DrawerFooterSection].
  const _DrawerFooterSection({
    required this.board,
    required this.enableLogging,
    required this.onOpenSettings,
    required this.onSyncRemote,
  });

  final TaskBoard board;
  final bool enableLogging;
  final VoidCallback onOpenSettings;
  final VoidCallback onSyncRemote;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DrawerActionTile(
          icon: Icons.sync_rounded,
          title: localizations.tooltipSyncWebDav,
          onAction: onSyncRemote,
        ),
        _DrawerActionTile(
          icon: Icons.code_rounded,
          title: localizations.tooltipMarkdownPreview,
          onAction: () => showTdfMarkdownDialog(context, board: board),
        ),
        if (enableLogging)
          _DrawerActionTile(
            tileKey: const ValueKey('drawer_diagnostic_log_tile'),
            icon: Icons.bug_report_outlined,
            title: localizations.diagnosticLogButton,
            onAction: () => showLogViewerDialog(context),
          ),
        _DrawerActionTile(
          icon: Icons.settings_outlined,
          title: localizations.tooltipSettings,
          onAction: onOpenSettings,
        ),
      ],
    );
  }
}

/// Header block inside [HomeDrawer] displaying [AppLogo] and [DrawerWorkspaceCard].
class _DrawerHeader extends StatelessWidget {
  /// Creates a [_DrawerHeader].
  const _DrawerHeader({
    required this.workspace,
    required this.onManageWorkspaces,
  });

  final VoidCallback onManageWorkspaces;
  final AppWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.headlineSmall
        ?.copyWith(fontWeight: FontWeight.bold);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              const AppLogo(size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).appTitle,
                  style: titleStyle,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: DrawerWorkspaceCard(
            workspace: workspace,
            onTap: () {
              Navigator.of(context).pop();
              onManageWorkspaces();
            },
          ),
        ),
      ],
    );
  }
}

/// Google Keep style label row inside [HomeDrawer] with task count badge.
class _DrawerLabelTile extends StatelessWidget {
  /// Creates a [_DrawerLabelTile].
  const _DrawerLabelTile({
    super.key,
    required this.count,
    required this.isSelected,
    required this.label,
    required this.onTap,
  });

  final int count;
  final bool isSelected;
  final TdfLabel label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final leadingColor = isSelected
        ? colorScheme.onSecondaryContainer
        : _resolveColor(label.color);
    final weight = isSelected ? FontWeight.w600 : FontWeight.normal;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        dense: true,
        selected: isSelected,
        selectedColor: colorScheme.onSecondaryContainer,
        selectedTileColor: colorScheme.secondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        visualDensity: const VisualDensity(vertical: -2),
        leading: Icon(Icons.label_outline_rounded, color: leadingColor),
        title: Text(label.name, style: TextStyle(fontWeight: weight)),
        trailing: _DrawerLabelTrailing(count: count, label: label),
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
      ),
    );
  }

  /// Resolves an optional `#RRGGBB` color string or returns `null`.
  static Color? _resolveColor(String? rawHex) =>
      switch (TdfColor.tryParseArgb(rawHex)) {
        final argb? => Color(argb),
        null => null,
      };
}

/// Trailing row inside [_DrawerLabelTile] displaying the optional scoped indicator and task count badge.
class _DrawerLabelTrailing extends StatelessWidget {
  /// Creates a [_DrawerLabelTrailing].
  const _DrawerLabelTrailing({required this.count, required this.label});

  /// Open task count for [label].
  final int count;

  /// Label rendered by the parent drawer tile.
  final TdfLabel label;

  @override
  Widget build(BuildContext context) {
    final badge = Badge.count(
      key: ValueKey('drawer_label_badge_${label.id}'),
      count: count,
    );
    if (!label.isScoped) {
      return badge;
    }
    final color = Theme.of(context).colorScheme.onSurfaceVariant
        .withValues(alpha: 0.55);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: AppLocalizations.of(context).labelScopedSwitchTitle,
          child: Icon(
            Icons.visibility_off_outlined,
            key: ValueKey('drawer_label_scoped_indicator_${label.id}'),
            size: 16,
            color: color,
          ),
        ),
        const SizedBox(width: 6),
        badge,
      ],
    );
  }
}

/// Labels section inside [HomeDrawer] rendering sorted label filter tiles.
class _DrawerLabelsSection extends StatelessWidget {
  /// Creates a [_DrawerLabelsSection].
  const _DrawerLabelsSection({
    required this.activeLabelId,
    required this.board,
    required this.onOpenEditLabels,
    required this.onSelectLabel,
  });

  final String? activeLabelId;
  final TaskBoard board;
  final ValueChanged<bool> onOpenEditLabels;
  final ValueChanged<String?> onSelectLabel;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 8),
        _DrawerSectionHeader(
          title: localizations.drawerLabels,
          editButtonKey: const ValueKey('drawer_edit_labels_button'),
          onEdit: () => onOpenEditLabels(false),
        ),
        for (final label in board.sortedLabels)
          _DrawerLabelTile(
            key: ValueKey('drawer_label_tile_${label.id}'),
            count: board.openTaskCountForLabel(label.id),
            isSelected: activeLabelId == label.id,
            label: label,
            onTap: () =>
                onSelectLabel(activeLabelId == label.id ? null : label.id),
          ),
        _DrawerActionTile(
          tileKey: const ValueKey('drawer_create_label_tile'),
          icon: Icons.add_rounded,
          title: localizations.createNewLabel,
          onAction: () => onOpenEditLabels(true),
        ),
        const Divider(height: 8),
      ],
    );
  }
}

/// Location row inside [HomeDrawer] with open task count badge.
class _DrawerLocationTile extends StatelessWidget {
  /// Creates a [_DrawerLocationTile].
  const _DrawerLocationTile({
    super.key,
    required this.count,
    required this.location,
    required this.onTap,
  });

  final int count;
  final TdfLocation location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        visualDensity: const VisualDensity(vertical: -2),
        leading: const Icon(Icons.place_outlined),
        title: Text(location.name),
        trailing: Badge.count(
          key: ValueKey('drawer_location_badge_${location.id}'),
          count: count,
        ),
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
      ),
    );
  }
}

/// Locations section inside [HomeDrawer] rendering sorted location tiles below [_DrawerLabelsSection].
class _DrawerLocationsSection extends StatelessWidget {
  /// Creates a [_DrawerLocationsSection].
  const _DrawerLocationsSection({
    required this.board,
    required this.onOpenEditLocations,
  });

  final TaskBoard board;
  final ValueChanged<bool>? onOpenEditLocations;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DrawerSectionHeader(
          title: localizations.drawerLocations,
          editButtonKey: const ValueKey('drawer_edit_locations_button'),
          onEdit: () => _openLocationsOverview(context, autofocusCreate: false),
        ),
        for (final location in board.sortedLocations)
          _DrawerLocationTile(
            key: ValueKey('drawer_location_tile_${location.id}'),
            count: board.openTaskCountForLocation(location.id),
            location: location,
            onTap: () => openEditLocationScreen(context, location: location),
          ),
        _DrawerActionTile(
          tileKey: const ValueKey('drawer_create_location_tile'),
          icon: Icons.add_location_alt_outlined,
          title: localizations.createNewLocation,
          onAction: () =>
              _openLocationsOverview(context, autofocusCreate: true),
        ),
        const Divider(height: 8),
      ],
    );
  }

  /// Invokes [onOpenEditLocations] or pushes [EditLocationsScreen] directly.
  void _openLocationsOverview(
    BuildContext context, {
    required bool autofocusCreate,
  }) {
    if (onOpenEditLocations case final callback?) {
      callback(autofocusCreate);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditLocationsScreen(autofocusCreate: autofocusCreate),
      ),
    );
  }
}

/// Section header row inside [HomeDrawer] displaying [title] and `Edit`.
class _DrawerSectionHeader extends StatelessWidget {
  /// Creates a [_DrawerSectionHeader].
  const _DrawerSectionHeader({
    required this.editButtonKey,
    required this.title,
    required this.onEdit,
  });

  final Key editButtonKey;
  final VoidCallback onEdit;
  final String title;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final labelStyle = Theme.of(context).textTheme.labelLarge
        ?.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: labelStyle),
          TextButton(
            key: editButtonKey,
            onPressed: () {
              Navigator.of(context).pop();
              onEdit();
            },
            child: Text(localizations.actionEdit),
          ),
        ],
      ),
    );
  }
}

/// Muted SemVer 2.0.0 version and Git build metadata footer in [HomeDrawer].
class _DrawerVersionFooter extends ConsumerWidget {
  /// Creates a [_DrawerVersionFooter].
  const _DrawerVersionFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawVersion =
        ref.watch(appVersionProvider).asData?.value ??
        AppVersionRepository.defaultFullVersion;
    final parts = _splitVersionParts(rawVersion);
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.onSurfaceVariant;
    final versionColor =
        Color.lerp(baseColor, theme.cardColor, 0.18) ?? baseColor;
    final buildColor =
        Color.lerp(versionColor, Colors.black, 0.32) ?? versionColor;
    final baseStyle = theme.textTheme.labelSmall?.copyWith(
      fontFamily: 'monospace',
      fontSize: 11.5,
      letterSpacing: 0.3,
    );
    return Padding(
      key: const ValueKey('drawer_version_footer'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: parts.versionLabel,
              style: baseStyle?.copyWith(color: versionColor),
            ),
            if (parts.buildSuffix.isNotEmpty)
              TextSpan(
                text: parts.buildSuffix,
                style: baseStyle?.copyWith(color: buildColor),
              ),
          ],
        ),
        key: const ValueKey('drawer_version_text'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Splits [rawVersion] (`v0.1.0+<build>`) into `Version 0.1.0` and `+<build>`.
  static ({String versionLabel, String buildSuffix}) _splitVersionParts(
    String rawVersion,
  ) {
    final trimmed = rawVersion.trim();
    final versionText = (trimmed.startsWith('v') || trimmed.startsWith('V'))
        ? trimmed.substring(1)
        : trimmed;
    final plusIndex = versionText.indexOf('+');
    return plusIndex < 0
        ? (versionLabel: 'Version $versionText', buildSuffix: '')
        : (
            versionLabel: 'Version ${versionText.substring(0, plusIndex)}',
            buildSuffix: versionText.substring(plusIndex),
          );
  }
}

/// Dialog displaying the serialized `.tdf` text of the current task board.
class _TdfMarkdownDialog extends ConsumerWidget {
  /// Creates a [_TdfMarkdownDialog].
  const _TdfMarkdownDialog({required this.board});

  final TaskBoard board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(localizations.markdownPreviewTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(
            ref.read(tdfServiceProvider).serialize(board),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.actionClose),
        ),
      ],
    );
  }
}

/// Displays a dialog containing the serialized `.tdf` representation of [board].
Future<void> showTdfMarkdownDialog(
  BuildContext context, {
  required TaskBoard board,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _TdfMarkdownDialog(board: board),
  );
}
