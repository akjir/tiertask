/// Immutable representation of a single task item in TierTask.
class TaskItem {
  TaskItem({
    String? id,
    required this.title,
    this.isCompleted = false,
    this.completedAt,
  }) : id = id ?? _nextId();

  static int _idCounter = 0;

  static String _nextId() {
    _idCounter++;
    return 'task_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  /// Internal runtime identifier (never persisted to the Markdown file).
  final String id;

  /// Plain-text task description.
  final String title;

  /// Whether the task is marked as completed (`[x]`).
  final bool isCompleted;

  /// Completion date (`YYYY-MM-DD`) when located in `# Erledigt`.
  final DateTime? completedAt;

  /// Creates an active (incomplete) task with no completion timestamp.
  TaskItem toActive() {
    return TaskItem(
      id: id,
      title: title,
      isCompleted: false,
      completedAt: null,
    );
  }

  /// Creates a completed task stamped with [completionDate] (normalized to UTC date).
  TaskItem toCompleted(DateTime completionDate) {
    final normalized = DateTime.utc(
      completionDate.year,
      completionDate.month,
      completionDate.day,
    );
    return TaskItem(
      id: id,
      title: title,
      isCompleted: true,
      completedAt: normalized,
    );
  }

  TaskItem copyWith({
    String? id,
    String? title,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }

  /// Formats [date] as an ISO-8601 date string (`YYYY-MM-DD`).
  static String formatIsoDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Serializes this task into a single Markdown list item line.
  String toMarkdownLine({required bool inErledigt}) {
    final cleanTitle = title.trim();
    if (inErledigt || isCompleted) {
      if (completedAt != null) {
        return '- [x] ${formatIsoDate(completedAt!)} $cleanTitle';
      }
      return '- [x] $cleanTitle';
    }
    return '- [ ] $cleanTitle';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskItem &&
        other.id == id &&
        other.title == title &&
        other.isCompleted == isCompleted &&
        _sameDate(other.completedAt, completedAt);
  }

  static bool _sameDate(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  int get hashCode => Object.hash(
        id,
        title,
        isCompleted,
        completedAt?.year,
        completedAt?.month,
        completedAt?.day,
      );

  @override
  String toString() => toMarkdownLine(inErledigt: isCompleted);
}
