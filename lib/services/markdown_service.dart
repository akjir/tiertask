import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/task_tier.dart';

/// Dependency-free, line-by-line Markdown parser and serializer for TierTask (`tiertask.md` / `t2.md`).
class MarkdownService {
  const MarkdownService();

  static final RegExp _completedWithDatePattern = RegExp(
    r'^-\s*\[[xX]\]\s*(\d{4}-\d{2}-\d{2})\s+(.*)$',
  );

  static final RegExp _completedWithoutDatePattern = RegExp(
    r'^-\s*\[[xX]\]\s*(.*)$',
  );

  static final RegExp _incompleteTaskPattern = RegExp(
    r'^-\s*\[\s?\]\s*(.*)$',
  );

  /// Parses a raw Markdown string into an immutable [TaskBoard] instance.
  ///
  /// Preserves task order within each of the 6 German H1 sections and gracefully
  /// handles empty sections, CRLF line endings, or trailing whitespace.
  TaskBoard parse(String markdown) {
    final buckets = <TaskTier, List<TaskItem>>{
      for (final tier in TaskTier.values) tier: <TaskItem>[],
    };

    TaskTier? currentTier;
    final lines = markdown.split('\n');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      if (line.startsWith('#')) {
        // Match H1 heading (`# Fokus`, `# Bereit`, etc.)
        final headingText = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
        currentTier = TaskTier.fromHeading(headingText);
        continue;
      }

      if (currentTier == null || !line.startsWith('-')) {
        continue;
      }

      final parsedTask = _parseTaskLine(line, currentTier);
      if (parsedTask != null) {
        buckets[currentTier]!.add(parsedTask);
      }
    }

    return TaskBoard(
      fokus: buckets[TaskTier.fokus]!,
      bereit: buckets[TaskTier.bereit]!,
      irgendwann: buckets[TaskTier.irgendwann]!,
      blockiert: buckets[TaskTier.blockiert]!,
      geplant: buckets[TaskTier.geplant]!,
      erledigt: buckets[TaskTier.erledigt]!,
    );
  }

  TaskItem? _parseTaskLine(String line, TaskTier tier) {
    final completedWithDateMatch = _completedWithDatePattern.firstMatch(line);
    if (completedWithDateMatch != null) {
      final rawDate = completedWithDateMatch.group(1)!;
      final title = completedWithDateMatch.group(2)!.trim();
      if (title.isEmpty) return null;

      DateTime? parsedDate;
      try {
        final d = DateTime.parse(rawDate);
        parsedDate = DateTime.utc(d.year, d.month, d.day);
      } catch (_) {
        parsedDate = null;
      }

      return TaskItem(
        title: title,
        isCompleted: true,
        completedAt: parsedDate,
      );
    }

    final completedNoDateMatch = _completedWithoutDatePattern.firstMatch(line);
    if (completedNoDateMatch != null) {
      final title = completedNoDateMatch.group(1)!.trim();
      if (title.isEmpty) return null;
      return TaskItem(
        title: title,
        isCompleted: true,
      );
    }

    final incompleteMatch = _incompleteTaskPattern.firstMatch(line);
    if (incompleteMatch != null) {
      final title = incompleteMatch.group(1)!.trim();
      if (title.isEmpty) return null;
      return TaskItem(
        title: title,
        isCompleted: tier == TaskTier.erledigt,
      );
    }

    // Fallback for plain bullet lines (`- Task title`) edited manually
    if (line.startsWith('- ')) {
      final title = line.substring(2).trim();
      if (title.isEmpty) return null;
      return TaskItem(
        title: title,
        isCompleted: tier == TaskTier.erledigt,
      );
    }

    return null;
  }

  /// Serializes an immutable [TaskBoard] into the canonical 6-section Markdown format.
  String serialize(TaskBoard board) {
    final buffer = StringBuffer();
    const tiers = TaskTier.values;

    for (var i = 0; i < tiers.length; i++) {
      final tier = tiers[i];
      buffer.writeln(tier.markdownHeading);

      final tasks = board.tasksForTier(tier);
      for (final task in tasks) {
        buffer.writeln(
          task.toMarkdownLine(inErledigt: tier == TaskTier.erledigt),
        );
      }

      if (i < tiers.length - 1) {
        buffer.writeln();
      }
    }

    return buffer.toString();
  }
}
