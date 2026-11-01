import 'package:flutter/material.dart';

import '../../models/task_item.dart';
import '../../models/task_tier.dart';

/// Prompts the user via a Material 3 modal bottom sheet to select the target
/// category (`Fokus`, `Bereit`, `Geplant`, `Blockiert`, or `Irgendwann`) when
/// restoring a completed task from `# Erledigt` or moving a task.
Future<TaskTier?> showRestoreTaskSheet(
  BuildContext context, {
  required TaskItem task,
  String title = 'Aufgabe wiederherstellen',
  String subtitle = 'Zielkategorie auswählen:',
}) {
  return showModalBottomSheet<TaskTier>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
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
                '„${task.title}“ – $subtitle',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final tier in TaskTier.activeTiers)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(_iconForTier(tier)),
                  title: Text(
                    '# ${tier.heading}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(tier.description),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(sheetContext).pop(tier),
                ),
            ],
          ),
        ),
      );
    },
  );
}

IconData _iconForTier(TaskTier tier) {
  switch (tier) {
    case TaskTier.fokus:
      return Icons.bolt_rounded;
    case TaskTier.bereit:
      return Icons.playlist_play_rounded;
    case TaskTier.geplant:
      return Icons.list_alt_rounded;
    case TaskTier.blockiert:
      return Icons.block_rounded;
    case TaskTier.irgendwann:
      return Icons.lightbulb_outline_rounded;
    case TaskTier.erledigt:
      return Icons.check_circle_outline_rounded;
  }
}
