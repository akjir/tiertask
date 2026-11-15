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

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tdf_location.dart';
import '../../models/tdf_metadata.dart';
import '../../providers/config_providers.dart';
import '../../providers/task_providers.dart';
import '../../repositories/link_launcher_repository.dart';
import '../../services/app_logger.dart';
import '../edit_labels_screen.dart';

/// Modal Context Hub dialog displaying a label's color, scope, note, links, and conditions.
class LabelHubDialog extends ConsumerStatefulWidget {
  /// Creates a [LabelHubDialog] for [labelId].
  const LabelHubDialog({super.key, required this.labelId});

  /// Identifier of the label displayed in this dialog.
  final String labelId;

  @override
  ConsumerState<LabelHubDialog> createState() => _LabelHubDialogState();
}

/// Scrollable content sections inside [LabelHubDialog].
class _LabelHubBody extends StatelessWidget {
  /// Creates a [_LabelHubBody].
  const _LabelHubBody({required this.label, required this.locations});

  /// Live label snapshot to render.
  final TdfLabel label;

  /// Board locations used to resolve location condition names.
  final List<TdfLocation> locations;

  @override
  Widget build(BuildContext context) {
    final note = label.note;
    final hasNote = note != null && note.isNotEmpty;
    final hasLinks = label.links.isNotEmpty;
    final hasConditions = label.conditions.isNotEmpty;
    if (!hasNote && !hasLinks && !hasConditions) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: const _LabelHubEmptyCard(),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440, maxHeight: 460),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasNote) _LabelHubNoteSection(labelId: label.id, note: note),
            if (hasNote && (hasLinks || hasConditions))
              const SizedBox(height: 10),
            if (hasLinks) _LabelHubLinksSection(links: label.links),
            if (hasLinks && hasConditions) const SizedBox(height: 10),
            if (hasConditions)
              _LabelHubConditionsSection(
                conditions: label.conditions,
                locations: locations,
              ),
          ],
        ),
      ),
    );
  }
}

/// Activation conditions summary card inside [LabelHubDialog].
class _LabelHubConditionsSection extends StatelessWidget {
  /// Creates a [_LabelHubConditionsSection].
  const _LabelHubConditionsSection({
    required this.conditions,
    required this.locations,
  });

  /// Active label conditions to summarize.
  final List<TaskCondition> conditions;

  /// Board locations used to resolve location condition names.
  final List<TdfLocation> locations;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    return _LabelHubSectionCard(
      cardKey: const ValueKey('label_hub_conditions_section'),
      icon: Icons.tune_rounded,
      title: localizations.taskConditionsSectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < conditions.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
              child: Text(
                formatConditionSummary(conditions[i], locations, localizations),
                style: textStyle,
              ),
            ),
        ],
      ),
    );
  }
}

/// State for [LabelHubDialog].
class _LabelHubDialogState extends ConsumerState<LabelHubDialog> {
  bool _didScheduleClose = false;

  @override
  Widget build(BuildContext context) {
    final hasBoard = ref.watch(
      taskNotifierProvider.select((asyncBoard) => asyncBoard.hasValue),
    );
    final label = ref.watch(
      taskNotifierProvider.select(
        (asyncBoard) => asyncBoard.asData?.value.findLabel(widget.labelId),
      ),
    );
    final locations = ref.watch(
      taskNotifierProvider.select(
        (asyncBoard) =>
            asyncBoard.asData?.value.locations ?? const <TdfLocation>[],
      ),
    );
    if (!hasBoard || label == null) {
      _scheduleAutoClose();
      return const SizedBox.shrink();
    }
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('label_hub_dialog'),
      title: _LabelHubHeader(label: label),
      content: _LabelHubBody(label: label, locations: locations),
      actions: [
        TextButton(
          key: const ValueKey('label_hub_edit_button'),
          onPressed: () => openEditLabelScreen(context, label: label),
          child: Text(localizations.actionEdit),
        ),
        FilledButton.tonal(
          key: const ValueKey('label_hub_close_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.actionClose),
        ),
      ],
    );
  }

  /// Schedules a single post-frame route removal when the watched label disappears.
  void _scheduleAutoClose() {
    if (_didScheduleClose) {
      return;
    }
    _didScheduleClose = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) {
        return;
      }
      final navigator = Navigator.of(context);
      if (route.isCurrent) {
        if (navigator.canPop()) {
          navigator.pop();
        }
        return;
      }
      navigator.removeRoute(route);
    });
  }
}

/// Empty-state card displayed when a label has no note, links, or conditions.
class _LabelHubEmptyCard extends StatelessWidget {
  /// Creates a [_LabelHubEmptyCard].
  const _LabelHubEmptyCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      key: const ValueKey('label_hub_empty_hint'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        AppLocalizations.of(context).labelHubEmptyHint,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Header block inside [LabelHubDialog] showing dialog title, color swatch, name, and scoped badge.
class _LabelHubHeader extends StatelessWidget {
  /// Creates a [_LabelHubHeader].
  const _LabelHubHeader({required this.label});

  /// Live label displayed in the header.
  final TdfLabel label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppLocalizations.of(context).labelHubDialogTitle,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        _LabelHubTitleRow(label: label),
      ],
    );
  }
}

/// Single clickable reference link row inside [_LabelHubLinksSection].
class _LabelHubLinkRow extends ConsumerWidget {
  /// Creates a [_LabelHubLinkRow].
  const _LabelHubLinkRow({required this.index, required this.link});

  /// Zero-based declaration index of [link].
  final int index;

  /// Reference link to display and launch.
  final TaskLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);
    void launch() => _openLabelResourceLink(
      context,
      ref.read(linkLauncherRepositoryProvider),
      link.uri,
    );
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('label_hub_link_item_$index'),
        borderRadius: BorderRadius.circular(8),
        onTap: launch,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.link_rounded, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: _LabelHubLinkTexts(link: link)),
              IconButton(
                key: ValueKey('label_hub_open_link_$index'),
                visualDensity: VisualDensity.compact,
                tooltip: localizations.tooltipOpenLink,
                icon: Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                onPressed: launch,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Title and URI text stack inside [_LabelHubLinkRow].
class _LabelHubLinkTexts extends StatelessWidget {
  /// Creates [_LabelHubLinkTexts].
  const _LabelHubLinkTexts({required this.link});

  /// Link item whose title and URI are rendered.
  final TaskLink link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          link.title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          link.uri,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Reference links card inside [LabelHubDialog].
class _LabelHubLinksSection extends StatelessWidget {
  /// Creates a [_LabelHubLinksSection].
  const _LabelHubLinksSection({required this.links});

  /// Reference links in canonical declaration order.
  final List<TaskLink> links;

  @override
  Widget build(BuildContext context) {
    return _LabelHubSectionCard(
      cardKey: const ValueKey('label_hub_links_section'),
      icon: Icons.link_rounded,
      title: AppLocalizations.of(context).linksSectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < links.length; i++)
            _LabelHubLinkRow(index: i, link: links[i]),
        ],
      ),
    );
  }
}

/// Selectable note card with clipboard copy action inside [LabelHubDialog].
class _LabelHubNoteSection extends StatelessWidget {
  /// Creates a [_LabelHubNoteSection].
  const _LabelHubNoteSection({required this.labelId, required this.note});

  /// Identifier of the label owning [note].
  final String labelId;

  /// Multi-line note body.
  final String note;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return _LabelHubSectionCard(
      cardKey: const ValueKey('label_hub_note_section'),
      icon: Icons.notes_rounded,
      title: localizations.taskNoteLabel,
      trailing: IconButton(
        key: const ValueKey('label_hub_copy_note_button'),
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        tooltip: localizations.tooltipCopyNote,
        icon: Icon(
          Icons.content_copy_rounded,
          size: 16,
          color: colorScheme.onSurfaceVariant,
        ),
        onPressed: () =>
            _copyLabelNoteToClipboard(context, labelId: labelId, note: note),
      ),
      child: SelectableText(
        note,
        key: const ValueKey('label_hub_note_text'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

/// Compact pill badge indicating that a label carries the `scoped` flag.
class _LabelHubScopedBadge extends StatelessWidget {
  /// Creates a [_LabelHubScopedBadge].
  const _LabelHubScopedBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      key: const ValueKey('label_hub_scoped_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: 14,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context).labelScopedSwitchTitle,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared surface card container for sections inside [LabelHubDialog].
class _LabelHubSectionCard extends StatelessWidget {
  /// Creates a [_LabelHubSectionCard].
  const _LabelHubSectionCard({
    required this.cardKey,
    required this.child,
    required this.icon,
    required this.title,
    this.trailing,
  });

  /// Deterministic widget key for the card container.
  final Key cardKey;

  /// Section body content.
  final Widget child;

  /// Leading section icon.
  final IconData icon;

  /// Localized section heading.
  final String title;

  /// Optional trailing action widget in the header row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      key: cardKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// Title row inside [_LabelHubHeader] displaying the color swatch, label name, and optional scoped badge.
class _LabelHubTitleRow extends StatelessWidget {
  /// Creates a [_LabelHubTitleRow].
  const _LabelHubTitleRow({required this.label});

  /// Live label displayed in the title row.
  final TdfLabel label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeColor = _resolveHubLabelColor(
      label.color,
      theme.colorScheme.primary,
    );
    return Row(
      children: [
        Container(
          key: const ValueKey('label_hub_color_badge'),
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (label.isScoped) ...[
          const SizedBox(width: 8),
          const _LabelHubScopedBadge(),
        ],
      ],
    );
  }
}

/// Formats [condition] into a localized single-line summary using [locations] and [localizations].
String formatConditionSummary(
  TaskCondition condition,
  Iterable<TdfLocation> locations,
  AppLocalizations localizations,
) {
  return switch (condition) {
    DayTaskCondition() => _formatDaySummary(condition, localizations),
    GlobalResetTaskCondition() => localizations.conditionGlobalAnyLabel,
    GroupResetTaskCondition() => _formatGroupResetSummary(
      condition.targetGroup,
      localizations,
    ),
    LocationTaskCondition() => _formatLocationSummary(condition, locations),
    TimeWindowTaskCondition() =>
      '${condition.startToken} - ${condition.endToken}',
  };
}

/// Opens [LabelHubDialog] as a modal overlay for [labelId].
Future<void> showLabelHubDialog(
  BuildContext context, {
  required String labelId,
}) {
  if (AppLogger.shouldLog(LogLevel.info)) {
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'ui.label_hub.open',
      fields: <String, Object?>{'id': labelId},
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => LabelHubDialog(labelId: labelId),
  );
}

/// Copies [note] to the system clipboard and displays a confirmation [SnackBar].
Future<void> _copyLabelNoteToClipboard(
  BuildContext context, {
  required String labelId,
  required String note,
}) async {
  if (AppLogger.shouldLog(LogLevel.info)) {
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'label.note.copied',
      fields: <String, Object?>{'id': labelId, 'length': note.length},
    );
  }
  final message = AppLocalizations.of(context).noteCopiedSnackBar;
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: note));
  if (!context.mounted) {
    return;
  }
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Looks up the display name for [locationId] in [locations], or returns [locationId] when unresolved.
String _findLocationName(Iterable<TdfLocation> locations, String locationId) {
  for (final location in locations) {
    if (location.id == locationId) {
      return location.name;
    }
  }
  return locationId;
}

/// Formats a [DayTaskCondition] as a comma-separated list of localized short weekday names.
String _formatDaySummary(
  DayTaskCondition condition,
  AppLocalizations localizations,
) {
  final names = <String>[
    for (final weekday in condition.weekdays)
      _formatWeekdayName(weekday, localizations),
  ];
  return names.join(', ');
}

/// Formats a [ConditionGroup] reset rule into its localized summary label.
String _formatGroupResetSummary(
  ConditionGroup group,
  AppLocalizations localizations,
) {
  return switch (group) {
    ConditionGroup.day => localizations.conditionDayAnyLabel,
    ConditionGroup.time => localizations.conditionTimeAnyLabel,
    ConditionGroup.location => localizations.conditionLocationAnyLabel,
  };
}

/// Formats a [LocationTaskCondition] using resolved [locations] names or legacy coordinates.
String _formatLocationSummary(
  LocationTaskCondition condition,
  Iterable<TdfLocation> locations,
) {
  if (condition.locationIds.isEmpty) {
    return '${condition.latitudeText}, ${condition.longitudeText} (${condition.radiusText}m)';
  }
  final names = <String>[
    for (final locationId in condition.locationIds)
      _findLocationName(locations, locationId),
  ];
  return names.join(', ');
}

/// Resolves the localized short weekday name for an ISO-8601 [weekday] (`1..7`).
String _formatWeekdayName(int weekday, AppLocalizations localizations) {
  return switch (weekday) {
    DateTime.monday => localizations.weekdayMon,
    DateTime.tuesday => localizations.weekdayTue,
    DateTime.wednesday => localizations.weekdayWed,
    DateTime.thursday => localizations.weekdayThu,
    DateTime.friday => localizations.weekdayFri,
    DateTime.saturday => localizations.weekdaySat,
    _ => localizations.weekdaySun,
  };
}

/// Launches [uri] via [repository] and displays an error [SnackBar] when launching fails.
Future<void> _openLabelResourceLink(
  BuildContext context,
  LinkLauncherRepository repository,
  String uri,
) async {
  final errorText = AppLocalizations.of(context).errorOpenLinkFailed;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await repository.openLink(uri);
  } on LinkLaunchException {
    if (!context.mounted) {
      return;
    }
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(errorText)));
  }
}

/// Resolves the `#RRGGBB` color of [rawHex] or returns [fallback].
Color _resolveHubLabelColor(String? rawHex, Color fallback) {
  final parsed = TdfColor.tryParseArgb(rawHex);
  return parsed != null ? Color(parsed) : fallback;
}
