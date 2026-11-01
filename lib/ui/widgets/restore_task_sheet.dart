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

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/tier_localization_extension.dart';
import '../../models/task_item.dart';
import '../../models/task_tier.dart';
import 'tier_page_indicator.dart';

/// Modal bottom sheet body for selecting a target active tier (`1` through `5`).
class _RestoreTaskSheetBody extends StatelessWidget {
  /// Creates a [_RestoreTaskSheetBody] widget.
  const _RestoreTaskSheetBody({required this.task, required this.title});

  /// Task being restored or moved.
  final TaskItem task;

  /// Sheet header title.
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              localizations.selectTargetTierSubtitle(task.title),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final tier in TaskTier.activeTiers)
              _TierOptionTile(tier: tier),
          ],
        ),
      ),
    );
  }
}

/// Single selectable tier row inside [_RestoreTaskSheetBody].
class _TierOptionTile extends StatelessWidget {
  /// Creates a [_TierOptionTile] for [tier].
  const _TierOptionTile({required this.tier});

  /// Target tier option.
  final TaskTier tier;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(TierPageIndicator.iconForTier(tier)),
      title: Text(
        localizations.tierName(tier),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(localizations.tierDescription(tier)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).pop(tier),
    );
  }
}

/// Prompts the user via a Material 3 modal bottom sheet to select the target
/// active tier (`1` through `5`) when restoring or moving [task].
Future<TaskTier?> showRestoreTaskSheet(
  BuildContext context, {
  required TaskItem task,
  String? title,
}) {
  final effectiveTitle = title ?? AppLocalizations.of(context).restoreTaskTitle;
  return showModalBottomSheet<TaskTier>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _RestoreTaskSheetBody(task: task, title: effectiveTitle),
  );
}
