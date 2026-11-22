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

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_board.dart';
import '../../models/tdf_sync_metadata.dart';
import '../../providers/entity_actions_provider.dart';
import '../../providers/floating_notice_providers.dart';
import '../../providers/shell_providers.dart';
import '../../providers/sync_providers.dart';
import '../../providers/task_providers.dart';
import '../layout/ui_page_header.dart';
import '../primitives/ui_banner.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../primitives/ui_pill.dart';
import '../primitives/ui_segmented_control.dart';
import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';

/// Resolution view listing pending `TDF-DEL-003` deletion conflicts across tasks, labels, and locations.
class DeletionConflictView extends ConsumerWidget {
  /// Creates a [DeletionConflictView].
  const DeletionConflictView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    // Keep auto-disposed decision state alive for this view without rebuilding the list on per-card changes.
    ref.listen<bool>(conflictDecisionsProvider.select((_) => true), (_, _) {});
    final outcome = ref.watch(
      syncStateProvider.select((syncState) => syncState.syncOutcome),
    );
    final board = ref.watch(
      taskNotifierProvider.select((boardAsync) => boardAsync.asData?.value),
    );
    final entries = _buildConflictEntries(
      outcome: outcome,
      board: board,
      localizations: localizations,
    );

    return _ResolutionScaffoldBody(
      title: localizations.conflictResolutionTitle,
      subtitle: localizations.conflictResolutionSubtitle,
      entryCount: entries.length,
      onBack: () => ref.read(shellProvider.notifier).openView(ShellView.tasks),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _ConflictEntryCard(
          key: ValueKey<String>('conflict_card_${entry.kind.name}_${entry.id}'),
          entry: entry,
        );
      },
    );
  }
}

/// Resolution view listing pending `TDF-REC-002` generation recovery items across tasks, labels, and locations.
class GenerationRecoveryView extends ConsumerWidget {
  /// Creates a [GenerationRecoveryView].
  const GenerationRecoveryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    // Keep auto-disposed decision state alive for this view without rebuilding the list on per-card changes.
    ref.listen<bool>(recoveryDecisionsProvider.select((_) => true), (_, _) {});
    final outcome = ref.watch(
      syncStateProvider.select((syncState) => syncState.syncOutcome),
    );
    final board = ref.watch(
      taskNotifierProvider.select((boardAsync) => boardAsync.asData?.value),
    );
    final entries = _buildRecoveryEntries(
      outcome: outcome,
      board: board,
      localizations: localizations,
    );

    return _ResolutionScaffoldBody(
      title: localizations.recoveryResolutionTitle,
      subtitle: localizations.recoveryResolutionSubtitle,
      entryCount: entries.length,
      onBack: () => ref.read(shellProvider.notifier).openView(ShellView.tasks),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _RecoveryEntryCard(
          key: ValueKey<String>('recovery_card_${entry.kind.name}_${entry.id}'),
          entry: entry,
        );
      },
    );
  }
}

/// Pinned bottom dock footer hosting `Cancel` and primary `Apply & Sync` actions
/// decoupled outside the resolution scroll region (`U-LAYOUT-005`).
class ResolutionActionDock extends ConsumerWidget {
  /// Creates a [ResolutionActionDock].
  const ResolutionActionDock({super.key, required this.isRecovery});

  /// Selects generation recovery (`true`) vs deletion conflict (`false`) submission.
  final bool isRecovery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBusy = ref.watch(
      syncActionsProvider.select((syncActions) => syncActions.isBusy),
    );
    final hasEntries = ref.watch(
      syncStateProvider.select(
        (syncState) => _hasResolutionEntries(
          syncState.syncOutcome,
          isRecovery: isRecovery,
        ),
      ),
    );

    return _ResolutionActionButtons(
      isRecovery: isRecovery,
      isBusy: isBusy,
      hasEntries: hasEntries,
      onCancel: () =>
          ref.read(shellProvider.notifier).openView(ShellView.tasks),
      onApply: () => _handleApply(context, ref),
    );
  }

  /// Dispatches the selected conflict or recovery decisions asynchronously.
  void _handleApply(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    unawaited(
      isRecovery
          ? _applyRecoveryResolutions(context, ref, locale: locale)
          : _applyConflictResolutions(context, ref, locale: locale),
    );
  }
}

/// Scoped `TDF-DEL-003` deletion conflict card watching only its own [conflictDecisionsProvider] entry.
class _ConflictEntryCard extends ConsumerWidget {
  /// Creates a [_ConflictEntryCard].
  const _ConflictEntryCard({super.key, required this.entry});

  /// Conflicted entity metadata rendered on this card.
  final _ResolutionEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final decisionKey = resolutionDecisionKey(entry.kind.name, entry.id);
    final selected = ref.watch(
      conflictDecisionsProvider.select(
        (decisions) => decisions[decisionKey] ?? TdfDeletionResolution.undelete,
      ),
    );

    return _ResolutionEntryCard<TdfDeletionResolution>(
      entry: entry,
      value: selected,
      segments: <UiSegment<TdfDeletionResolution>>[
        UiSegment<TdfDeletionResolution>(
          value: TdfDeletionResolution.undelete,
          label: localizations.conflictKeepEditOption,
        ),
        UiSegment<TdfDeletionResolution>(
          value: TdfDeletionResolution.delete,
          label: localizations.conflictConfirmDeleteOption,
        ),
      ],
      onChanged: (choice) => ref
          .read(conflictDecisionsProvider.notifier)
          .selectDecision(decisionKey, choice),
    );
  }
}

/// Scoped `TDF-REC-002` generation recovery card watching only its own [recoveryDecisionsProvider] entry.
class _RecoveryEntryCard extends ConsumerWidget {
  /// Creates a [_RecoveryEntryCard].
  const _RecoveryEntryCard({super.key, required this.entry});

  /// Ambiguous entity metadata rendered on this card.
  final _ResolutionEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final decisionKey = resolutionDecisionKey(entry.kind.name, entry.id);
    final selected = ref.watch(
      recoveryDecisionsProvider.select(
        (decisions) =>
            decisions[decisionKey] ?? TdfRecoveryResolution.recoverAsNew,
      ),
    );

    return _ResolutionEntryCard<TdfRecoveryResolution>(
      entry: entry,
      value: selected,
      segments: <UiSegment<TdfRecoveryResolution>>[
        UiSegment<TdfRecoveryResolution>(
          value: TdfRecoveryResolution.recoverAsNew,
          label: localizations.recoveryAsNewOption,
        ),
        UiSegment<TdfRecoveryResolution>(
          value: TdfRecoveryResolution.discard,
          label: localizations.recoveryDiscardLocalOption,
        ),
      ],
      onChanged: (choice) => ref
          .read(recoveryDecisionsProvider.notifier)
          .selectDecision(decisionKey, choice),
    );
  }
}

/// Right-aligned `Cancel` and primary `Apply & Sync` buttons inside [ResolutionActionDock].
class _ResolutionActionButtons extends StatelessWidget {
  /// Creates a [_ResolutionActionButtons].
  const _ResolutionActionButtons({
    required this.isRecovery,
    required this.isBusy,
    required this.hasEntries,
    required this.onCancel,
    required this.onApply,
  });

  /// Whether pending resolution entries exist to submit.
  final bool hasEntries;

  /// Whether a sync or resolution write is currently executing.
  final bool isBusy;

  /// Selects generation recovery (`true`) vs deletion conflict (`false`) label.
  final bool isRecovery;

  /// Callback applying selected resolution choices.
  final VoidCallback onApply;

  /// Callback returning to the primary Tasks view.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8.0,
        runSpacing: 8.0,
        children: <Widget>[
          UiButton(
            key: const ValueKey<String>('resolution_cancel_button'),
            label: localizations.actionCancel,
            onPressed: onCancel,
          ),
          UiButton(
            key: const ValueKey<String>('resolution_apply_button'),
            label: isRecovery
                ? localizations.recoveryApplyAndSyncAction
                : localizations.conflictApplyAndSyncAction,
            variant: UiButtonVariant.primary,
            leadingIcon: isBusy ? Icons.sync_rounded : null,
            isLoading: isBusy,
            onPressed: (!hasEntries || isBusy) ? null : onApply,
          ),
        ],
      ),
    );
  }
}

/// Immutable display entry for one conflicted or ambiguous task, label, or location.
@immutable
class _ResolutionEntry {
  /// Creates a [_ResolutionEntry].
  const _ResolutionEntry({
    required this.kind,
    required this.kindBadgeLabel,
    required this.id,
    required this.title,
    required this.detail,
  });

  /// Localized conflict or recovery explanation shown on the card.
  final String detail;

  /// Canonical entity identifier.
  final String id;

  /// Entity domain kind (`task`, `label`, or `location`).
  final EntityKind kind;

  /// Localized uppercase badge label for [kind].
  final String kindBadgeLabel;

  /// Resolved display title from the loaded board, or [id] when absent.
  final String title;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ResolutionEntry &&
        other.kind == kind &&
        other.kindBadgeLabel == kindBadgeLabel &&
        other.id == id &&
        other.title == title &&
        other.detail == detail;
  }

  @override
  int get hashCode => Object.hash(kind, kindBadgeLabel, id, title, detail);
}

/// Flat `UiCard.standard` displaying one conflicted or ambiguous entity with its 2-way decision control.
class _ResolutionEntryCard<T> extends StatelessWidget {
  /// Creates a [_ResolutionEntryCard].
  const _ResolutionEntryCard({
    required this.entry,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  /// Conflicted or ambiguous entity display entry.
  final _ResolutionEntry entry;

  /// Callback invoked when the user switches the segmented decision.
  final ValueChanged<T> onChanged;

  /// Two-way resolution options presented in [UiSegmentedControl].
  final List<UiSegment<T>> segments;

  /// Currently selected resolution decision.
  final T value;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);

    return UiCard.standard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ResolutionEntryHeader(entry: entry),
          SizedBox(height: tokens.spacing.space2),
          Text(
            entry.detail,
            style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
          ),
          SizedBox(height: tokens.spacing.space3),
          UiSegmentedControl<T>(
            segments: segments,
            value: value,
            onChanged: onChanged,
            semanticLabel: entry.title,
          ),
        ],
      ),
    );
  }
}

/// Entity badge and card title header row inside [_ResolutionEntryCard].
class _ResolutionEntryHeader extends StatelessWidget {
  /// Creates a [_ResolutionEntryHeader].
  const _ResolutionEntryHeader({required this.entry});

  /// Conflicted or ambiguous entity display entry.
  final _ResolutionEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);

    return Wrap(
      spacing: 8.0,
      runSpacing: 6.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        UiPill(
          label: '${entry.kindBadgeLabel} · ${entry.id}',
          tone: UiPillTone.warning,
          isMono: true,
        ),
        Text(
          entry.title,
          style: tokens.typography.cardTitle.copyWith(color: tokens.colors.ink),
        ),
      ],
    );
  }
}

/// Empty-state banner or lazy vertical list of pending resolution entry cards.
class _ResolutionEntryList extends StatelessWidget {
  /// Creates a [_ResolutionEntryList].
  const _ResolutionEntryList({
    required this.entryCount,
    required this.emptyMessage,
    required this.itemBuilder,
  });

  /// Localized message displayed when [entryCount] is zero.
  final String emptyMessage;

  /// Total number of pending items rendered in the list.
  final int entryCount;

  /// Lazy card builder invoked for each pending entry index.
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (entryCount == 0) {
      return UiBanner(
        variant: UiBannerVariant.emptyState,
        message: emptyMessage,
      );
    }
    final spacing = UiThemeTokens.of(context).spacing.space3;
    return ListView.builder(
      itemCount: entryCount,
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.only(
          bottom: index + 1 < entryCount ? spacing : 0.0,
        ),
        child: itemBuilder(context, index),
      ),
    );
  }
}

/// Shared padded layout with [UiPageHeader] and lazy `ListView.builder` for resolution views.
class _ResolutionScaffoldBody extends StatelessWidget {
  /// Creates a [_ResolutionScaffoldBody].
  const _ResolutionScaffoldBody({
    required this.title,
    required this.subtitle,
    required this.entryCount,
    required this.onBack,
    required this.itemBuilder,
  });

  /// Total number of pending items rendered in the header count pill and list.
  final int entryCount;

  /// Lazy card builder invoked for each pending entry index.
  final IndexedWidgetBuilder itemBuilder;

  /// Back navigation callback returning to Tasks.
  final VoidCallback onBack;

  /// Localized explanatory subtitle.
  final String subtitle;

  /// Localized view heading.
  final String title;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);

    return Padding(
      padding: tokens.spacing.mainContentPadding(viewport),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          UiPageHeader(
            backLabel: localizations.actionBackToTasks,
            onBack: onBack,
            title: title,
            subtitle: subtitle,
            countLabel: '$entryCount',
          ),
          SizedBox(height: tokens.spacing.space4),
          Expanded(
            child: _ResolutionEntryList(
              entryCount: entryCount,
              emptyMessage: subtitle,
              itemBuilder: itemBuilder,
            ),
          ),
        ],
      ),
    );
  }
}

/// Partitions deletion conflict choices by entity kind and submits them via [SyncActionsNotifier].
Future<void> _applyConflictResolutions(
  BuildContext context,
  WidgetRef ref, {
  required Locale locale,
}) async {
  final outcome = ref.read(syncStateProvider).syncOutcome;
  if (outcome == null || outcome.kind != TdfSyncOutcomeKind.deletionConflict) {
    return;
  }
  final decisions = ref.read(conflictDecisionsProvider);
  final taskDecisions = <String, TdfDeletionResolution>{
    for (final id in outcome.conflictedTaskIds)
      id:
          decisions[resolutionDecisionKey(EntityKind.task.name, id)] ??
          TdfDeletionResolution.undelete,
  };
  final labelDecisions = <String, TdfDeletionResolution>{
    for (final id in outcome.conflictedLabelIds)
      id:
          decisions[resolutionDecisionKey(EntityKind.label.name, id)] ??
          TdfDeletionResolution.undelete,
  };
  final locationDecisions = <String, TdfDeletionResolution>{
    for (final id in outcome.conflictedLocationIds)
      id:
          decisions[resolutionDecisionKey(EntityKind.location.name, id)] ??
          TdfDeletionResolution.undelete,
  };

  final result = await ref
      .read(syncActionsProvider.notifier)
      .applyDeletionConflictResolutions(
        taskDecisions: taskDecisions,
        labelDecisions: labelDecisions,
        locationDecisions: locationDecisions,
        locale: locale,
      );
  if (!context.mounted) {
    return;
  }
  _reportResolutionFailure(ref, result);
}

/// Partitions generation recovery choices by entity kind and submits them via [SyncActionsNotifier].
Future<void> _applyRecoveryResolutions(
  BuildContext context,
  WidgetRef ref, {
  required Locale locale,
}) async {
  final outcome = ref.read(syncStateProvider).syncOutcome;
  if (outcome == null || outcome.kind != TdfSyncOutcomeKind.recoveryRequired) {
    return;
  }
  final decisions = ref.read(recoveryDecisionsProvider);
  final taskDecisions = <String, TdfRecoveryResolution>{
    for (final id in outcome.ambiguousTaskIds)
      id:
          decisions[resolutionDecisionKey(EntityKind.task.name, id)] ??
          TdfRecoveryResolution.recoverAsNew,
  };
  final labelDecisions = <String, TdfRecoveryResolution>{
    for (final id in outcome.ambiguousLabelIds)
      id:
          decisions[resolutionDecisionKey(EntityKind.label.name, id)] ??
          TdfRecoveryResolution.recoverAsNew,
  };
  final locationDecisions = <String, TdfRecoveryResolution>{
    for (final id in outcome.ambiguousLocationIds)
      id:
          decisions[resolutionDecisionKey(EntityKind.location.name, id)] ??
          TdfRecoveryResolution.recoverAsNew,
  };

  final result = await ref
      .read(syncActionsProvider.notifier)
      .applyRecoveryResolutions(
        taskDecisions: taskDecisions,
        labelDecisions: labelDecisions,
        locationDecisions: locationDecisions,
        locale: locale,
      );
  if (!context.mounted) {
    return;
  }
  _reportResolutionFailure(ref, result);
}

/// Builds pending `TDF-DEL-003` deletion conflict display entries from [outcome] and [board].
List<_ResolutionEntry> _buildConflictEntries({
  required TdfSyncOutcomeException? outcome,
  required TaskBoard? board,
  required AppLocalizations localizations,
}) {
  if (outcome == null || outcome.kind != TdfSyncOutcomeKind.deletionConflict) {
    return const <_ResolutionEntry>[];
  }
  return _buildResolutionEntries(
    taskIds: outcome.conflictedTaskIds,
    labelIds: outcome.conflictedLabelIds,
    locationIds: outcome.conflictedLocationIds,
    board: board,
    localizations: localizations,
    detail: localizations.syncConflictDeletionBanner,
  );
}

/// Builds pending `TDF-REC-002` generation recovery display entries from [outcome] and [board].
List<_ResolutionEntry> _buildRecoveryEntries({
  required TdfSyncOutcomeException? outcome,
  required TaskBoard? board,
  required AppLocalizations localizations,
}) {
  if (outcome == null || outcome.kind != TdfSyncOutcomeKind.recoveryRequired) {
    return const <_ResolutionEntry>[];
  }
  return _buildResolutionEntries(
    taskIds: outcome.ambiguousTaskIds,
    labelIds: outcome.ambiguousLabelIds,
    locationIds: outcome.ambiguousLocationIds,
    board: board,
    localizations: localizations,
    detail: localizations.syncConflictRecoveryBanner,
  );
}

/// Builds ordered [_ResolutionEntry] items across tasks, labels, and locations.
List<_ResolutionEntry> _buildResolutionEntries({
  required Iterable<String> taskIds,
  required Iterable<String> labelIds,
  required Iterable<String> locationIds,
  required TaskBoard? board,
  required AppLocalizations localizations,
  required String detail,
}) {
  final entries = <_ResolutionEntry>[];
  for (final taskId in taskIds) {
    entries.add(
      _ResolutionEntry(
        kind: EntityKind.task,
        kindBadgeLabel: localizations.entityKindTaskBadge,
        id: taskId,
        title: _resolveDisplayTitle(
          board?.findTask(taskId)?.title,
          fallbackId: taskId,
        ),
        detail: detail,
      ),
    );
  }
  for (final labelId in labelIds) {
    entries.add(
      _ResolutionEntry(
        kind: EntityKind.label,
        kindBadgeLabel: localizations.entityKindLabelBadge,
        id: labelId,
        title: _resolveDisplayTitle(
          board?.findLabel(labelId)?.name,
          fallbackId: labelId,
        ),
        detail: detail,
      ),
    );
  }
  for (final locationId in locationIds) {
    entries.add(
      _ResolutionEntry(
        kind: EntityKind.location,
        kindBadgeLabel: localizations.entityKindLocationBadge,
        id: locationId,
        title: _resolveDisplayTitle(
          board?.findLocation(locationId)?.name,
          fallbackId: locationId,
        ),
        detail: detail,
      ),
    );
  }
  return entries;
}

/// Returns `true` when [outcome] contains at least one pending entry for the active resolution mode.
bool _hasResolutionEntries(
  TdfSyncOutcomeException? outcome, {
  required bool isRecovery,
}) {
  if (outcome == null) {
    return false;
  }
  if (isRecovery) {
    return outcome.kind == TdfSyncOutcomeKind.recoveryRequired &&
        (outcome.ambiguousTaskIds.isNotEmpty ||
            outcome.ambiguousLabelIds.isNotEmpty ||
            outcome.ambiguousLocationIds.isNotEmpty);
  }
  return outcome.kind == TdfSyncOutcomeKind.deletionConflict &&
      (outcome.conflictedTaskIds.isNotEmpty ||
          outcome.conflictedLabelIds.isNotEmpty ||
          outcome.conflictedLocationIds.isNotEmpty);
}

/// Emits a danger floating notice when [result] indicates validation or persistence failure.
void _reportResolutionFailure(WidgetRef ref, ActionResult result) {
  switch (result) {
    case ActionSucceeded():
      return;
    case ActionValidationFailed(:final message):
    case ActionPersistFailed(:final message):
      ref
          .read(floatingNoticeProvider.notifier)
          .showNotice(message, tone: FloatingNoticeTone.danger);
  }
}

/// Returns [candidate] when non-empty, otherwise falls back to [fallbackId].
String _resolveDisplayTitle(String? candidate, {required String fallbackId}) {
  if (candidate != null && candidate.trim().isNotEmpty) {
    return candidate;
  }
  return fallbackId;
}
