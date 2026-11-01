import 'task_item.dart';
import 'task_tier.dart';

/// Immutable domain model representing the entire TierTask board across all 6 tiers.
class TaskBoard {
  TaskBoard({
    List<TaskItem> fokus = const [],
    List<TaskItem> bereit = const [],
    List<TaskItem> irgendwann = const [],
    List<TaskItem> blockiert = const [],
    List<TaskItem> geplant = const [],
    List<TaskItem> erledigt = const [],
  })  : fokus = List<TaskItem>.unmodifiable(fokus),
        bereit = List<TaskItem>.unmodifiable(bereit),
        irgendwann = List<TaskItem>.unmodifiable(irgendwann),
        blockiert = List<TaskItem>.unmodifiable(blockiert),
        geplant = List<TaskItem>.unmodifiable(geplant),
        erledigt = List<TaskItem>.unmodifiable(erledigt);

  factory TaskBoard.empty() => TaskBoard();

  static const int fokusSoftLimit = 3;
  static const int bereitSoftLimit = 5;
  static const int erledigtRetentionDays = 30;

  final List<TaskItem> fokus;
  final List<TaskItem> bereit;
  final List<TaskItem> irgendwann;
  final List<TaskItem> blockiert;
  final List<TaskItem> geplant;
  final List<TaskItem> erledigt;

  /// Returns the task list for a given [tier].
  List<TaskItem> tasksForTier(TaskTier tier) {
    switch (tier) {
      case TaskTier.fokus:
        return fokus;
      case TaskTier.bereit:
        return bereit;
      case TaskTier.irgendwann:
        return irgendwann;
      case TaskTier.blockiert:
        return blockiert;
      case TaskTier.geplant:
        return geplant;
      case TaskTier.erledigt:
        return erledigt;
    }
  }

  /// Finds which [TaskTier] currently contains [taskId], or `null` if not found.
  TaskTier? findTierOfTask(String taskId) {
    for (final tier in TaskTier.values) {
      final list = tasksForTier(tier);
      if (list.any((t) => t.id == taskId)) {
        return tier;
      }
    }
    return null;
  }

  /// Finds the [TaskItem] with [taskId], or `null` if not found.
  TaskItem? findTask(String taskId) {
    for (final tier in TaskTier.values) {
      for (final task in tasksForTier(tier)) {
        if (task.id == taskId) {
          return task;
        }
      }
    }
    return null;
  }

  TaskBoard copyWith({
    List<TaskItem>? fokus,
    List<TaskItem>? bereit,
    List<TaskItem>? irgendwann,
    List<TaskItem>? blockiert,
    List<TaskItem>? geplant,
    List<TaskItem>? erledigt,
  }) {
    return TaskBoard(
      fokus: fokus ?? this.fokus,
      bereit: bereit ?? this.bereit,
      irgendwann: irgendwann ?? this.irgendwann,
      blockiert: blockiert ?? this.blockiert,
      geplant: geplant ?? this.geplant,
      erledigt: erledigt ?? this.erledigt,
    );
  }

  /// Executes the Auto-Pull Cascade (Soft WIP Limits):
  /// - Step 1 (Fill Fokus): `while (fokus.length < 3 && bereit.isNotEmpty)`
  ///   Removes top task from `# Bereit` and appends to `# Fokus`.
  /// - Step 2 (Fill Bereit): `while (bereit.length < 5 && geplant.isNotEmpty)`
  ///   Removes top task from `# Geplant` and appends to `# Bereit`.
  /// - Repeats if `# Fokus` is still below 3 and `# Bereit` received tasks from `# Geplant`.
  /// - Never force-moves excess items downward if a category is manually overfilled.
  /// - `# Irgendwann` and `# Blockiert` never participate in automatic pull operations.
  TaskBoard applyAutoPull() {
    final nextFokus = List<TaskItem>.from(fokus);
    final nextBereit = List<TaskItem>.from(bereit);
    final nextGeplant = List<TaskItem>.from(geplant);

    bool changed = true;
    while (changed) {
      changed = false;

      // Step 1 (Fill Fokus): while (fokus.length < 3 && bereit.isNotEmpty)
      while (nextFokus.length < fokusSoftLimit && nextBereit.isNotEmpty) {
        final pulled = nextBereit.removeAt(0).toActive();
        nextFokus.add(pulled);
        changed = true;
      }

      // Step 2 (Fill Bereit): while (bereit.length < 5 && geplant.isNotEmpty)
      while (nextBereit.length < bereitSoftLimit && nextGeplant.isNotEmpty) {
        final pulled = nextGeplant.removeAt(0).toActive();
        nextBereit.add(pulled);
        changed = true;
      }
    }

    return copyWith(
      fokus: nextFokus,
      bereit: nextBereit,
      geplant: nextGeplant,
    );
  }

  /// 30-Day Pruning: Iterates through all items in `# Erledigt`.
  /// If `currentDate.difference(taskDate).inDays > 30`, permanently deletes the item.
  TaskBoard pruneCompletedTasks({DateTime? currentDate}) {
    final now = currentDate ?? DateTime.now();
    final normalizedNow = DateTime.utc(now.year, now.month, now.day);

    final retained = erledigt.where((task) {
      final completedDate = task.completedAt;
      if (completedDate == null) {
        return true;
      }
      final normalizedTaskDate = DateTime.utc(
        completedDate.year,
        completedDate.month,
        completedDate.day,
      );
      return normalizedNow.difference(normalizedTaskDate).inDays <=
          erledigtRetentionDays;
    }).toList();

    return copyWith(erledigt: retained);
  }

  /// Adds a new task to [targetTier] (defaulting to `# Geplant`),
  /// prunes expired completed tasks, and runs the Auto-Pull Cascade.
  TaskBoard addTask(
    String title, {
    TaskTier targetTier = TaskTier.geplant,
    DateTime? currentDate,
    String? id,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return this;

    final now = currentDate ?? DateTime.now();
    final isDoneTier = targetTier == TaskTier.erledigt;
    final newTask = isDoneTier
        ? TaskItem(id: id, title: trimmed).toCompleted(now)
        : TaskItem(id: id, title: trimmed, isCompleted: false);

    TaskBoard updated;
    switch (targetTier) {
      case TaskTier.fokus:
        updated = copyWith(fokus: [...fokus, newTask]);
        break;
      case TaskTier.bereit:
        updated = copyWith(bereit: [...bereit, newTask]);
        break;
      case TaskTier.irgendwann:
        updated = copyWith(irgendwann: [...irgendwann, newTask]);
        break;
      case TaskTier.blockiert:
        updated = copyWith(blockiert: [...blockiert, newTask]);
        break;
      case TaskTier.geplant:
        updated = copyWith(geplant: [...geplant, newTask]);
        break;
      case TaskTier.erledigt:
        updated = copyWith(erledigt: [newTask, ...erledigt]);
        break;
    }

    return updated.pruneCompletedTasks(currentDate: now).applyAutoPull();
  }

  /// Marks an active task as done:
  /// 1. Changes prefix from `- [ ] ` to `- [x] YYYY-MM-DD ` and inserts at top of `# Erledigt`.
  /// 2. Prunes items in `# Erledigt` older than 30 days.
  /// 3. Triggers the Auto-Pull Cascade to refill `# Fokus` and `# Bereit`.
  TaskBoard completeTask(String taskId, {DateTime? currentDate}) {
    final now = currentDate ?? DateTime.now();
    final sourceTier = findTierOfTask(taskId);
    if (sourceTier == null || sourceTier == TaskTier.erledigt) {
      return this;
    }

    final task = findTask(taskId)!;
    final completedTask = task.toCompleted(now);

    final updated = _removeTaskFromTier(taskId, sourceTier).copyWith(
      erledigt: [completedTask, ...erledigt],
    );

    return updated.pruneCompletedTasks(currentDate: now).applyAutoPull();
  }

  /// Restores a completed task from `# Erledigt` into [targetTier]:
  /// 1. Strips `[x]` and the `YYYY-MM-DD` timestamp (reverting to `- [ ] `).
  /// 2. Appends to the selected [targetTier].
  /// 3. Prunes expired tasks and runs the Auto-Pull Cascade.
  TaskBoard restoreTask(
    String taskId,
    TaskTier targetTier, {
    DateTime? currentDate,
  }) {
    if (targetTier == TaskTier.erledigt) return this;
    final sourceTier = findTierOfTask(taskId);
    if (sourceTier != TaskTier.erledigt) return this;

    final now = currentDate ?? DateTime.now();
    final task = findTask(taskId)!;
    final restoredTask = task.toActive();

    final withoutTask = _removeTaskFromTier(taskId, TaskTier.erledigt);
    final withRestored = withoutTask._appendTaskToTier(
      restoredTask,
      targetTier,
    );

    return withRestored.pruneCompletedTasks(currentDate: now).applyAutoPull();
  }

  /// Downgrades a task one active tier down while preventing the Ping-Pong Bug:
  /// - From `# Fokus` to `# Bereit`:
  ///   First pulls the top task from `# Bereit` into `# Fokus` (if applicable),
  ///   then appends the downgraded task to the end of `# Bereit` (and refills `# Bereit` from `# Geplant`).
  /// - From `# Bereit` to `# Geplant`:
  ///   First pulls the next candidate from the top of `# Geplant` into `# Bereit` (if applicable),
  ///   and then inserts the downgraded task at the end of `# Geplant`.
  TaskBoard downgradeTask(String taskId, {DateTime? currentDate}) {
    final now = currentDate ?? DateTime.now();
    final sourceTier = findTierOfTask(taskId);
    if (sourceTier == null) return this;

    if (sourceTier == TaskTier.fokus) {
      final task = findTask(taskId)!.toActive();
      final nextFokus = fokus.where((t) => t.id != taskId).toList();
      final nextBereit = List<TaskItem>.from(bereit);
      final nextGeplant = List<TaskItem>.from(geplant);

      // Step 1: Pull top task(s) from # Bereit (or # Geplant if # Bereit runs out)
      // into # Fokus BEFORE appending the downgraded task to # Bereit.
      while (nextFokus.length < fokusSoftLimit &&
          (nextBereit.isNotEmpty || nextGeplant.isNotEmpty)) {
        if (nextBereit.isNotEmpty) {
          nextFokus.add(nextBereit.removeAt(0).toActive());
        } else if (nextGeplant.isNotEmpty) {
          nextFokus.add(nextGeplant.removeAt(0).toActive());
        }
      }

      // Step 2: Append downgraded task to the end of # Bereit.
      nextBereit.add(task);

      // Step 3: Refill # Bereit from # Geplant if below soft limit.
      while (nextBereit.length < bereitSoftLimit && nextGeplant.isNotEmpty) {
        nextBereit.add(nextGeplant.removeAt(0).toActive());
      }

      return copyWith(
        fokus: nextFokus,
        bereit: nextBereit,
        geplant: nextGeplant,
      ).pruneCompletedTasks(currentDate: now);
    }

    if (sourceTier == TaskTier.bereit) {
      final task = findTask(taskId)!.toActive();
      final nextFokus = List<TaskItem>.from(fokus);
      final nextBereit = bereit.where((t) => t.id != taskId).toList();
      final nextGeplant = List<TaskItem>.from(geplant);

      // Step 1: Pull next candidate(s) from the top of # Geplant into # Bereit
      // BEFORE inserting the downgraded task into # Geplant.
      while (nextBereit.length < bereitSoftLimit && nextGeplant.isNotEmpty) {
        nextBereit.add(nextGeplant.removeAt(0).toActive());
      }

      // Also ensure # Fokus is filled from existing candidates if below limit.
      while (nextFokus.length < fokusSoftLimit && nextBereit.isNotEmpty) {
        nextFokus.add(nextBereit.removeAt(0).toActive());
        while (nextBereit.length < bereitSoftLimit && nextGeplant.isNotEmpty) {
          nextBereit.add(nextGeplant.removeAt(0).toActive());
        }
      }

      // Step 2: Insert downgraded task at the end of # Geplant.
      nextGeplant.add(task);

      return copyWith(
        fokus: nextFokus,
        bereit: nextBereit,
        geplant: nextGeplant,
      ).pruneCompletedTasks(currentDate: now);
    }

    return this;
  }

  /// Quick-Block Action: Moves an active task immediately to `# Blockiert`
  /// and triggers the Auto-Pull Cascade afterward to fill the vacated slot.
  TaskBoard blockTask(String taskId, {DateTime? currentDate}) {
    return moveTask(taskId, TaskTier.blockiert, currentDate: currentDate);
  }

  /// Moves a task to any [targetTier], respecting anti-ping-pong rules when moving downward
  /// and triggering the Auto-Pull Cascade when slots open or tasks enter active queues.
  TaskBoard moveTask(
    String taskId,
    TaskTier targetTier, {
    DateTime? currentDate,
  }) {
    final now = currentDate ?? DateTime.now();
    final sourceTier = findTierOfTask(taskId);
    if (sourceTier == null || sourceTier == targetTier) {
      return this;
    }

    if (targetTier == TaskTier.erledigt) {
      return completeTask(taskId, currentDate: now);
    }

    if (sourceTier == TaskTier.erledigt) {
      return restoreTask(taskId, targetTier, currentDate: now);
    }

    // Use anti-ping-pong downgrade when moving one step down the active pull chain.
    if (sourceTier == TaskTier.fokus && targetTier == TaskTier.bereit) {
      return downgradeTask(taskId, currentDate: now);
    }
    if (sourceTier == TaskTier.bereit && targetTier == TaskTier.geplant) {
      return downgradeTask(taskId, currentDate: now);
    }

    // If moving directly from # Fokus to # Geplant, pull existing tasks up first
    // before appending the moved task to the end of # Geplant.
    if (sourceTier == TaskTier.fokus && targetTier == TaskTier.geplant) {
      final task = findTask(taskId)!.toActive();
      final afterRemovalAndPull =
          _removeTaskFromTier(taskId, TaskTier.fokus).applyAutoPull();
      return afterRemovalAndPull
          ._appendTaskToTier(task, TaskTier.geplant)
          .pruneCompletedTasks(currentDate: now);
    }

    final task = findTask(taskId)!.toActive();
    final withoutTask = _removeTaskFromTier(taskId, sourceTier);

    // If moving from # Fokus or # Bereit to a static tier (# Blockiert / # Irgendwann),
    // or promoting from any tier up into # Fokus / # Bereit / # Geplant:
    return withoutTask
        ._appendTaskToTier(task, targetTier)
        .pruneCompletedTasks(currentDate: now)
        .applyAutoPull();
  }

  /// Updates the title of an existing task.
  TaskBoard editTaskTitle(String taskId, String newTitle) {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return this;
    final tier = findTierOfTask(taskId);
    if (tier == null) return this;

    List<TaskItem> updateList(List<TaskItem> list) {
      return list
          .map((t) => t.id == taskId ? t.copyWith(title: trimmed) : t)
          .toList();
    }

    switch (tier) {
      case TaskTier.fokus:
        return copyWith(fokus: updateList(fokus));
      case TaskTier.bereit:
        return copyWith(bereit: updateList(bereit));
      case TaskTier.irgendwann:
        return copyWith(irgendwann: updateList(irgendwann));
      case TaskTier.blockiert:
        return copyWith(blockiert: updateList(blockiert));
      case TaskTier.geplant:
        return copyWith(geplant: updateList(geplant));
      case TaskTier.erledigt:
        return copyWith(erledigt: updateList(erledigt));
    }
  }

  /// Permanently deletes a task and runs Auto-Pull Cascade if an active slot opened.
  TaskBoard deleteTask(String taskId, {DateTime? currentDate}) {
    final now = currentDate ?? DateTime.now();
    final tier = findTierOfTask(taskId);
    if (tier == null) return this;

    return _removeTaskFromTier(taskId, tier)
        .pruneCompletedTasks(currentDate: now)
        .applyAutoPull();
  }

  TaskBoard _removeTaskFromTier(String taskId, TaskTier tier) {
    List<TaskItem> filterOut(List<TaskItem> list) =>
        list.where((t) => t.id != taskId).toList();

    switch (tier) {
      case TaskTier.fokus:
        return copyWith(fokus: filterOut(fokus));
      case TaskTier.bereit:
        return copyWith(bereit: filterOut(bereit));
      case TaskTier.irgendwann:
        return copyWith(irgendwann: filterOut(irgendwann));
      case TaskTier.blockiert:
        return copyWith(blockiert: filterOut(blockiert));
      case TaskTier.geplant:
        return copyWith(geplant: filterOut(geplant));
      case TaskTier.erledigt:
        return copyWith(erledigt: filterOut(erledigt));
    }
  }

  TaskBoard _appendTaskToTier(TaskItem task, TaskTier tier) {
    switch (tier) {
      case TaskTier.fokus:
        return copyWith(fokus: [...fokus, task]);
      case TaskTier.bereit:
        return copyWith(bereit: [...bereit, task]);
      case TaskTier.irgendwann:
        return copyWith(irgendwann: [...irgendwann, task]);
      case TaskTier.blockiert:
        return copyWith(blockiert: [...blockiert, task]);
      case TaskTier.geplant:
        return copyWith(geplant: [...geplant, task]);
      case TaskTier.erledigt:
        return copyWith(erledigt: [task, ...erledigt]);
    }
  }
}
