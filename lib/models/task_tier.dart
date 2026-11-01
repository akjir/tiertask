/// Represents the six strictly ordered priority/status tiers in TierTask (T2).
enum TaskTier {
  fokus(
    heading: 'Fokus',
    softLimit: 3,
    isAutoPullTarget: true,
    isStatic: false,
    description: 'Aktive Top-Priorität (Soft-Limit: 3)',
  ),
  bereit(
    heading: 'Bereit',
    softLimit: 5,
    isAutoPullTarget: true,
    isStatic: false,
    description: 'Startklar für Fokus (Soft-Limit: 5)',
  ),
  irgendwann(
    heading: 'Irgendwann',
    softLimit: null,
    isAutoPullTarget: false,
    isStatic: true,
    description: 'Ideenspeicher ohne automatisches Nachrücken',
  ),
  blockiert(
    heading: 'Blockiert',
    softLimit: null,
    isAutoPullTarget: false,
    isStatic: true,
    description: 'Wartet auf externe Ereignisse oder Dritte',
  ),
  geplant(
    heading: 'Geplant',
    softLimit: null,
    isAutoPullTarget: false,
    isStatic: false,
    description: 'Aktives Backlog (rückt automatisch in Bereit nach)',
  ),
  erledigt(
    heading: 'Erledigt',
    softLimit: null,
    isAutoPullTarget: false,
    isStatic: true,
    description: 'Abgeschlossene Aufgaben (30 Tage Aufbewahrung)',
  );

  const TaskTier({
    required this.heading,
    required this.softLimit,
    required this.isAutoPullTarget,
    required this.isStatic,
    required this.description,
  });

  /// Exact German H1 heading name without the leading `# `.
  final String heading;

  /// Soft WIP limit (3 for Fokus, 5 for Bereit, null for others).
  final int? softLimit;

  /// Whether this tier automatically pulls tasks from lower active tiers.
  final bool isAutoPullTarget;

  /// Whether this tier is static (excluded from automatic pull operations).
  final bool isStatic;

  /// Short German description for the UI.
  final String description;

  /// Full Markdown H1 line (`# <heading>`).
  String get markdownHeading => '# $heading';

  /// Active (non-completed) tiers where tasks can be added or restored.
  static const List<TaskTier> activeTiers = [
    TaskTier.fokus,
    TaskTier.bereit,
    TaskTier.geplant,
    TaskTier.blockiert,
    TaskTier.irgendwann,
  ];

  /// Resolves a [TaskTier] from a raw H1 heading name (case-sensitive match
  /// first, with case-insensitive fallback).
  static TaskTier? fromHeading(String rawHeading) {
    final cleaned = rawHeading.trim();
    for (final tier in TaskTier.values) {
      if (tier.heading == cleaned) {
        return tier;
      }
    }
    for (final tier in TaskTier.values) {
      if (tier.heading.toLowerCase() == cleaned.toLowerCase()) {
        return tier;
      }
    }
    return null;
  }
}
