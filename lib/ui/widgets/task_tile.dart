import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/task_item.dart';
import '../../models/task_tier.dart';
import '../../providers/task_providers.dart';
import 'restore_task_sheet.dart';

/// Material 3 task card / list tile with tier-appropriate quick actions.
class TaskTile extends ConsumerWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.tier,
    this.isProminent = false,
  });

  final TaskItem task;
  final TaskTier tier;
  final bool isProminent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final notifier = ref.read(taskNotifierProvider.notifier);
    final isDone = tier == TaskTier.erledigt;

    return Card(
      elevation: isProminent ? 2 : 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isProminent
          ? colorScheme.primaryContainer.withValues(alpha: 0.45)
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isProminent
              ? colorScheme.primary.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: isProminent ? 6 : 2,
        ),
        child: Row(
          children: [
            Checkbox(
              value: isDone,
              onChanged: (_) async {
                if (isDone) {
                  final targetTier = await showRestoreTaskSheet(
                    context,
                    task: task,
                  );
                  if (targetTier != null) {
                    await notifier.restoreTask(task.id, targetTier);
                  }
                } else {
                  await notifier.completeTask(task.id);
                }
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    task.title,
                    style:
                        (isProminent
                                ? theme.textTheme.titleMedium
                                : theme.textTheme.bodyLarge)
                            ?.copyWith(
                              fontWeight: isProminent
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              decoration: isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: isDone
                                  ? colorScheme.onSurfaceVariant
                                  : colorScheme.onSurface,
                            ),
                  ),
                  if (isDone && task.completedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Erledigt am ${TaskItem.formatIsoDate(task.completedAt!)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Direct Downgrade & Quick-Block actions for # Fokus and # Bereit
            if (tier == TaskTier.fokus || tier == TaskTier.bereit) ...[
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tier == TaskTier.fokus
                    ? 'Herabstufen nach # Bereit'
                    : 'Herabstufen nach # Geplant',
                icon: const Icon(Icons.arrow_downward_rounded, size: 20),
                onPressed: () => notifier.downgradeTask(task.id),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Sofort nach # Blockiert verschieben',
                icon: Icon(
                  Icons.block_rounded,
                  size: 20,
                  color: colorScheme.error,
                ),
                onPressed: () => notifier.blockTask(task.id),
              ),
            ],
            // Quick promote action for static tiers (# Blockiert / # Irgendwann)
            if (tier == TaskTier.blockiert || tier == TaskTier.irgendwann)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'In # Geplant einreihen',
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                onPressed: () => notifier.moveTask(task.id, TaskTier.geplant),
              ),
            PopupMenuButton<_TaskMenuAction>(
              tooltip: 'Weitere Aktionen',
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onSelected: (action) async {
                switch (action) {
                  case _TaskMenuAction.move:
                    final selectedTier = await showRestoreTaskSheet(
                      context,
                      task: task,
                      title: 'Aufgabe verschieben',
                      subtitle: 'Zielkategorie auswählen:',
                    );
                    if (selectedTier != null) {
                      await notifier.moveTask(task.id, selectedTier);
                    }
                    break;
                  case _TaskMenuAction.edit:
                    await _showEditDialog(context, notifier, task);
                    break;
                  case _TaskMenuAction.delete:
                    await notifier.deleteTask(task.id);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _TaskMenuAction.move,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.swap_vert_rounded),
                    title: Text('Verschieben nach…'),
                  ),
                ),
                const PopupMenuItem(
                  value: _TaskMenuAction.edit,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Text bearbeiten'),
                  ),
                ),
                const PopupMenuItem(
                  value: _TaskMenuAction.delete,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline_rounded),
                    title: Text('Löschen'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(
    BuildContext context,
    TaskNotifier notifier,
    TaskItem task,
  ) async {
    final controller = TextEditingController(text: task.title);
    final updatedTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aufgabe bearbeiten'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Aufgabentext',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (updatedTitle != null && updatedTitle.trim().isNotEmpty) {
      await notifier.editTaskTitle(task.id, updatedTitle);
    }
  }
}

enum _TaskMenuAction { move, edit, delete }
