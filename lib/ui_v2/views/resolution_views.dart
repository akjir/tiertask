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
import '../../presentation/sync_v2_controller.dart';
import '../../presentation/ui_v2_shell_models.dart';

/// Provides per-entity `TDF-DEL-003` deletion conflict decisions shared between
/// [DeletionConflictView] and [ResolutionActionDock].
final conflictDecisionsProvider =
    NotifierProvider<
      ConflictDecisionsNotifier,
      Map<String, ConflictDecisionChoice>
    >(ConflictDecisionsNotifier.new);

/// Provides per-entity `TDF-REC-002` generation recovery decisions shared between
/// [GenerationRecoveryView] and [ResolutionActionDock].
final recoveryDecisionsProvider =
    NotifierProvider<
      RecoveryDecisionsNotifier,
      Map<String, RecoveryDecisionChoice>
    >(RecoveryDecisionsNotifier.new);

/// Manages per-entity deletion conflict choices defaulting every item to [ConflictDecisionChoice.keepEdit] (`U-UX-007`).
class ConflictDecisionsNotifier
    extends Notifier<Map<String, ConflictDecisionChoice>> {
  @override
  Map<String, ConflictDecisionChoice> build() {
    final viewModel = ref.watch(conflictResolutionViewModelProvider);
    return Map<String, ConflictDecisionChoice>.unmodifiable(
      <String, ConflictDecisionChoice>{
        for (final entry in viewModel.entries)
          resolutionDecisionKey(entry.kind, entry.id):
              ConflictDecisionChoice.keepEdit,
      },
    );
  }

  /// Updates the resolution [choice] for the entity identified by [kind] and [id].
  void selectDecision(
    EntityKind kind,
    String id,
    ConflictDecisionChoice choice,
  ) {
    final key = resolutionDecisionKey(kind, id);
    if (state[key] == choice) {
      return;
    }
    state = Map<String, ConflictDecisionChoice>.unmodifiable(
      <String, ConflictDecisionChoice>{...state, key: choice},
    );
  }
}

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

/// Manages per-entity generation recovery choices defaulting every item to [RecoveryDecisionChoice.recoverAsNew] (`U-UX-007`).
class RecoveryDecisionsNotifier
    extends Notifier<Map<String, RecoveryDecisionChoice>> {
  @override
  Map<String, RecoveryDecisionChoice> build() {
    final viewModel = ref.watch(recoveryResolutionViewModelProvider);
    return Map<String, RecoveryDecisionChoice>.unmodifiable(
      <String, RecoveryDecisionChoice>{
        for (final entry in viewModel.entries)
          resolutionDecisionKey(entry.kind, entry.id):
              RecoveryDecisionChoice.recoverAsNew,
      },
    );
  }

  /// Updates the recovery [choice] for the entity identified by [kind] and [id].
  void selectDecision(
    EntityKind kind,
    String id,
    RecoveryDecisionChoice choice,
  ) {
    final key = resolutionDecisionKey(kind, id);
    if (state[key] == choice) {
      return;
    }
    state = Map<String, RecoveryDecisionChoice>.unmodifiable(
      <String, RecoveryDecisionChoice>{...state, key: choice},
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
    final localizations = AppLocalizations.of(context);
    final isBusy = ref.watch(
      syncV2ControllerProvider.select((syncState) => syncState.isBusy),
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
            onPressed: () => ref
                .read(appShellControllerProvider.notifier)
                .openView(ShellView.tasks),
          ),
          UiButton(
            key: const ValueKey<String>('resolution_apply_button'),
            label: isRecovery
                ? localizations.recoveryApplyAndSyncAction
                : localizations.conflictApplyAndSyncAction,
            variant: UiButtonVariant.primary,
            leadingIcon: isBusy ? Icons.sync_rounded : null,
            isLoading: isBusy,
            onPressed: (!hasEntries || isBusy)
                ? null
                : () => _handleApply(context, ref),
          ),
        ],
      ),
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
    final colors = tokens.colors;

    return UiCard.standard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(
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
                style: tokens.typography.cardTitle.copyWith(color: colors.ink),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.space2),
          Text(
            entry.detail,
            style: tokens.typography.meta.copyWith(color: colors.muted),
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
            child: entryCount == 0
                ? UiBanner(
                    variant: UiBannerVariant.emptyState,
                    message: subtitle,
                  )
                : ListView.builder(
                    itemCount: entryCount,
                    itemBuilder: (context, index) => Padding(
                      padding: EdgeInsets.only(
                        bottom: index + 1 < entryCount
                            ? tokens.spacing.space3
                            : 0.0,
                      ),
                      child: itemBuilder(context, index),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Builds a namespace-safe map key combining entity [kind] and canonical [id].
String resolutionDecisionKey(EntityKind kind, String id) => '${kind.name}:$id';

/// Partitions deletion conflict choices by entity kind and submits them via [SyncV2Controller].
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
      .read(syncV2ControllerProvider.notifier)
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

/// Partitions generation recovery choices by entity kind and submits them via [SyncV2Controller].
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
      .read(syncV2ControllerProvider.notifier)
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
void _reportResolutionFailure(WidgetRef ref, V2ActionResult result) {
  switch (result) {
    case V2ActionSucceeded():
      return;
    case V2ActionValidationFailed(:final message):
    case V2ActionPersistFailed(:final message):
      ref
          .read(floatingNoticeControllerProvider.notifier)
          .showNotice(message, tone: NoticeTone.danger);
  }
}
