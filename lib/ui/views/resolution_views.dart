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
import 'package:tiertask_ui/tiertask_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../presentation/app_shell_controller.dart';
import '../../presentation/floating_notice_controller.dart';
import '../../presentation/shell_models.dart';
import '../../presentation/sync_controller.dart';

/// Resolution view listing pending `TDF-DEL-003` deletion conflicts across tasks, labels, and locations.
class DeletionConflictView extends ConsumerWidget {
  /// Creates a [DeletionConflictView].
  const DeletionConflictView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final viewModel = ref.watch(conflictResolutionViewModelProvider);
    final decisions = ref.watch(conflictDecisionsProvider);
    final notifier = ref.read(conflictDecisionsProvider.notifier);

    return _ResolutionScaffoldBody(
      title: viewModel.title,
      subtitle: viewModel.subtitle,
      entryCount: viewModel.entries.length,
      onBack: () => ref
          .read(appShellControllerProvider.notifier)
          .openView(ShellView.tasks),
      itemBuilder: (context, index) {
        final entry = viewModel.entries[index];
        final decisionKey = resolutionDecisionKey(entry.kind, entry.id);
        final selected =
            decisions[decisionKey] ?? ConflictDecisionChoice.keepEdit;
        return _ResolutionEntryCard<ConflictDecisionChoice>(
          key: ValueKey<String>('conflict_card_${entry.kind.name}_${entry.id}'),
          entry: entry,
          value: selected,
          segments: <UiSegment<ConflictDecisionChoice>>[
            UiSegment<ConflictDecisionChoice>(
              value: ConflictDecisionChoice.keepEdit,
              label: localizations.conflictKeepEditOption,
            ),
            UiSegment<ConflictDecisionChoice>(
              value: ConflictDecisionChoice.confirmDelete,
              label: localizations.conflictConfirmDeleteOption,
            ),
          ],
          onChanged: (choice) =>
              notifier.selectDecision(entry.kind, entry.id, choice),
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
    final viewModel = ref.watch(recoveryResolutionViewModelProvider);
    final decisions = ref.watch(recoveryDecisionsProvider);
    final notifier = ref.read(recoveryDecisionsProvider.notifier);

    return _ResolutionScaffoldBody(
      title: viewModel.title,
      subtitle: viewModel.subtitle,
      entryCount: viewModel.entries.length,
      onBack: () => ref
          .read(appShellControllerProvider.notifier)
          .openView(ShellView.tasks),
      itemBuilder: (context, index) {
        final entry = viewModel.entries[index];
        final decisionKey = resolutionDecisionKey(entry.kind, entry.id);
        final selected =
            decisions[decisionKey] ?? RecoveryDecisionChoice.recoverAsNew;
        return _ResolutionEntryCard<RecoveryDecisionChoice>(
          key: ValueKey<String>('recovery_card_${entry.kind.name}_${entry.id}'),
          entry: entry,
          value: selected,
          segments: <UiSegment<RecoveryDecisionChoice>>[
            UiSegment<RecoveryDecisionChoice>(
              value: RecoveryDecisionChoice.recoverAsNew,
              label: localizations.recoveryAsNewOption,
            ),
            UiSegment<RecoveryDecisionChoice>(
              value: RecoveryDecisionChoice.discardLocal,
              label: localizations.recoveryDiscardLocalOption,
            ),
          ],
          onChanged: (choice) =>
              notifier.selectDecision(entry.kind, entry.id, choice),
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
      syncControllerProvider.select((syncState) => syncState.isBusy),
    );
    final hasEntries = isRecovery
        ? ref.watch(
            recoveryResolutionViewModelProvider.select(
              (model) => model.hasItems,
            ),
          )
        : ref.watch(
            conflictResolutionViewModelProvider.select(
              (model) => model.hasConflicts,
            ),
          );

    return _ResolutionActionButtons(
      isRecovery: isRecovery,
      isBusy: isBusy,
      hasEntries: hasEntries,
      onCancel: () => ref
          .read(appShellControllerProvider.notifier)
          .openView(ShellView.tasks),
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

/// Flat `UiCard.standard` displaying one conflicted or ambiguous entity with its 2-way decision control.
class _ResolutionEntryCard<T> extends StatelessWidget {
  /// Creates a [_ResolutionEntryCard].
  const _ResolutionEntryCard({
    super.key,
    required this.entry,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  /// Conflicted or ambiguous entity view model.
  final ResolutionEntryViewModel entry;

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

  /// Conflicted or ambiguous entity view model.
  final ResolutionEntryViewModel entry;

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

/// Partitions deletion conflict choices by entity kind and submits them via [SyncController].
Future<void> _applyConflictResolutions(
  BuildContext context,
  WidgetRef ref, {
  required Locale locale,
}) async {
  final viewModel = ref.read(conflictResolutionViewModelProvider);
  final decisions = ref.read(conflictDecisionsProvider);
  final taskDecisions = <String, ConflictDecisionChoice>{};
  final labelDecisions = <String, ConflictDecisionChoice>{};
  final locationDecisions = <String, ConflictDecisionChoice>{};

  for (final entry in viewModel.entries) {
    final choice =
        decisions[resolutionDecisionKey(entry.kind, entry.id)] ??
        ConflictDecisionChoice.keepEdit;
    switch (entry.kind) {
      case EntityKind.task:
        taskDecisions[entry.id] = choice;
      case EntityKind.label:
        labelDecisions[entry.id] = choice;
      case EntityKind.location:
        locationDecisions[entry.id] = choice;
    }
  }

  final result = await ref
      .read(syncControllerProvider.notifier)
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

/// Partitions generation recovery choices by entity kind and submits them via [SyncController].
Future<void> _applyRecoveryResolutions(
  BuildContext context,
  WidgetRef ref, {
  required Locale locale,
}) async {
  final viewModel = ref.read(recoveryResolutionViewModelProvider);
  final decisions = ref.read(recoveryDecisionsProvider);
  final taskDecisions = <String, RecoveryDecisionChoice>{};
  final labelDecisions = <String, RecoveryDecisionChoice>{};
  final locationDecisions = <String, RecoveryDecisionChoice>{};

  for (final entry in viewModel.entries) {
    final choice =
        decisions[resolutionDecisionKey(entry.kind, entry.id)] ??
        RecoveryDecisionChoice.recoverAsNew;
    switch (entry.kind) {
      case EntityKind.task:
        taskDecisions[entry.id] = choice;
      case EntityKind.label:
        labelDecisions[entry.id] = choice;
      case EntityKind.location:
        locationDecisions[entry.id] = choice;
    }
  }

  final result = await ref
      .read(syncControllerProvider.notifier)
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

/// Emits a danger floating notice when [result] indicates validation or persistence failure.
void _reportResolutionFailure(WidgetRef ref, ActionResult result) {
  switch (result) {
    case ActionSucceeded():
      return;
    case ActionValidationFailed(:final message):
    case ActionPersistFailed(:final message):
      ref
          .read(floatingNoticeControllerProvider.notifier)
          .showNotice(message, tone: NoticeTone.danger);
  }
}
