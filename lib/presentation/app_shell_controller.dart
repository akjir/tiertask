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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/task_board.dart';
import '../models/task_item.dart';
import '../providers/config_providers.dart';
import '../providers/sync_providers.dart';
import '../providers/task_providers.dart';
import '../providers/workspace_providers.dart';
import 'floating_notice_controller.dart';
import 'ui_telemetry.dart';
import 'ui_v2_shell_models.dart';

/// Provides centralized shell navigation, filtering, expansion, draft, and unwind state for `lib/ui_v2/`.
final appShellControllerProvider =
    NotifierProvider<AppShellController, AppShellState>(AppShellController.new);

/// Coordinates adaptive shell routes, `returnContext`, single-expand cards, inline editing,
/// external board reconciliation, and unified desktop `Escape` / Android `PopScope` unwinding.
class AppShellController extends Notifier<AppShellState> {
  final Set<EntityRef> _suppressedLocalMutations = <EntityRef>{};

  @override
  AppShellState build() {
    ref.watch(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
    );
    _suppressedLocalMutations.clear();

    ref.listen<AsyncValue<TaskBoard>>(taskNotifierProvider, (previous, next) {
      final board = next.asData?.value;
      if (board == null) {
        return;
      }
      _reconcileBoardUpdate(previous?.asData?.value, board);
    });

    ref.listen<SyncState>(syncStateProvider, (previous, next) {
      if (next.errorMessage != previous?.errorMessage &&
          next.errorMessage != null) {
        state = state.copyWith(syncErrorBannerDismissed: false);
      }
      if (next.fileReadReport != previous?.fileReadReport &&
          next.fileReadReport != null) {
        state = state.copyWith(fileReadBannerDismissed: false);
      }
    });

    return AppShellState();
  }

  /// Cancels any open uncommitted entity draft card.
  void cancelDraft() {
    final kind = state.activeDraft;
    if (kind == null) {
      return;
    }
    UiTelemetry.logEntityDraftCancelled(kind.name);
    state = state.copyWith(
      clearActiveDraft: true,
      draftSeedTitle: '',
      draftSeedPlacement: TaskPlacementOption.queue,
      draftSeedLabelIds: const <String>[],
      labelPickerOpen: false,
      labelPickerQuery: '',
    );
  }

  /// Cancels any open inline delete confirmation.
  void cancelInlineDelete() {
    if (state.activeDeleteConfirm == null) {
      return;
    }
    state = state.copyWith(clearActiveDeleteConfirm: true);
  }

  /// Clears a one-shot entity reveal scroll request after the UI scrolls to the card.
  void clearRevealRequest() {
    if (state.revealEntityRequest == null) {
      return;
    }
    state = state.copyWith(clearRevealEntityRequest: true);
  }

  /// Closes the active inline section editor without committing.
  void closeInlineEdit() {
    if (state.activeInlineEdit == null) {
      return;
    }
    state = state.copyWith(
      clearActiveInlineEdit: true,
      labelPickerOpen: false,
      labelPickerQuery: '',
    );
  }

  /// Closes Global Search and clears its query.
  void closeSearch() {
    if (!state.searchOpen && state.searchQuery.isEmpty) {
      return;
    }
    state = state.copyWith(searchOpen: false, searchQuery: '');
  }

  /// Collapses the expanded entity card and clears dependent inline states.
  void collapseEntity() {
    if (state.expandedEntity == null &&
        state.activeInlineEdit == null &&
        state.activeDeleteConfirm == null) {
      return;
    }
    if (state.expandedEntity case final current?) {
      if (current.kind == EntityKind.task) {
        UiTelemetry.logTaskDetailsToggled(
          taskId: current.id,
          isExpanded: false,
        );
      }
    }
    state = state.copyWith(
      clearExpandedEntity: true,
      clearActiveInlineEdit: true,
      clearActiveDeleteConfirm: true,
      labelPickerOpen: false,
      labelPickerQuery: '',
    );
  }

  /// Dismisses the partial file-read status banner until a new report arrives.
  void dismissFileReadBanner() {
    state = state.copyWith(fileReadBannerDismissed: true);
  }

  /// Dismisses the sync error status banner until a new sync error arrives.
  void dismissSyncErrorBanner() {
    state = state.copyWith(syncErrorBannerDismissed: true);
  }

  /// Expands [entity] under strict single-expand coordination (`U-CARD-001`).
  void expandEntity(EntityRef entity, {bool reveal = true}) {
    if (entity.kind == EntityKind.task) {
      UiTelemetry.logTaskDetailsToggled(taskId: entity.id, isExpanded: true);
    }
    state = state.copyWith(
      expandedEntity: entity,
      clearActiveInlineEdit: true,
      clearActiveDeleteConfirm: true,
      labelPickerOpen: false,
      labelPickerQuery: '',
      revealEntityRequest: reveal ? entity : null,
      clearRevealEntityRequest: !reveal,
    );
  }

  /// Unwinds the highest-priority active desktop `Escape` layer (`U-A11Y-002`).
  ShellDismissOutcome handleEscape() {
    final layer = _unwindInShellLayer();
    if (layer != null) {
      UiTelemetry.logEscapeUnwound(layer);
      return ShellDismissOutcome.handled;
    }
    return ShellDismissOutcome.allowSystemPop;
  }

  /// Unwinds in-shell layers, `returnContext`, and secondary views for Android `PopScope`.
  ShellDismissOutcome handleSystemBack() {
    final layer = _unwindInShellLayer();
    if (layer != null) {
      UiTelemetry.logPopScopeUnwound(layer);
      return ShellDismissOutcome.handled;
    }
    if (state.returnContext != null) {
      navigateBackFromReturnContext();
      UiTelemetry.logPopScopeUnwound('return_context');
      return ShellDismissOutcome.handled;
    }
    if (state.view != ShellView.tasks) {
      openView(ShellView.tasks);
      UiTelemetry.logPopScopeUnwound('secondary_view');
      return ShellDismissOutcome.handled;
    }
    return ShellDismissOutcome.allowSystemPop;
  }

  /// Restores the saved [ReturnContext] back to Tasks or Global Search (`U-UX-002`).
  void navigateBackFromReturnContext() {
    final saved = state.returnContext;
    if (saved == null) {
      openView(ShellView.tasks);
      return;
    }
    final previousView = state.view;
    UiTelemetry.logViewChanged(
      from: previousView.name,
      to: saved.view.name,
      viaReturnContext: true,
    );
    state = state.copyWith(
      view: saved.view,
      activeTier: saved.tier,
      activeLabelId: saved.labelId,
      clearActiveLabelId: saved.labelId == null,
      searchOpen: saved.searchOpen,
      searchQuery: saved.searchQuery,
      expandedEntity: saved.expandedEntity,
      clearExpandedEntity: saved.expandedEntity == null,
      revealEntityRequest: saved.expandedEntity,
      clearRevealEntityRequest: saved.expandedEntity == null,
      clearReturnContext: true,
      clearActiveInlineEdit: true,
      clearActiveDeleteConfirm: true,
      clearActiveDraft: true,
      labelPickerOpen: false,
      labelPickerQuery: '',
      compactDrawerOpen: false,
    );
  }

  /// Opens an uncommitted entity draft card of [kind] at the top of the current view (`U-CARD-006`).
  void openDraft(
    EntityDraftKind kind, {
    String seedTitle = '',
    TaskPlacementOption seedPlacement = TaskPlacementOption.queue,
    List<String> seedLabelIds = const <String>[],
  }) {
    UiTelemetry.logEntityDraftOpened(kind.name);
    state = state.copyWith(
      activeDraft: kind,
      draftSeedTitle: seedTitle,
      draftSeedPlacement: seedPlacement,
      draftSeedLabelIds: seedLabelIds,
      clearExpandedEntity: true,
      clearActiveInlineEdit: true,
      clearActiveDeleteConfirm: true,
      labelPickerOpen: false,
      labelPickerQuery: '',
      compactComposerOpen: false,
    );
  }

  /// Opens [entity] inside its manager view (`labels` or `locations`), optionally recording `returnContext`.
  void openEntityInManager(
    EntityRef entity, {
    required bool preserveReturnContext,
  }) {
    final targetView = switch (entity.kind) {
      EntityKind.task => ShellView.tasks,
      EntityKind.label => ShellView.labels,
      EntityKind.location => ShellView.locations,
    };
    final shouldSaveContext =
        preserveReturnContext &&
        state.view == ShellView.tasks &&
        targetView != ShellView.tasks;
    final nextReturnContext = shouldSaveContext
        ? ReturnContext(
            view: state.view,
            tier: state.activeTier,
            labelId: state.activeLabelId,
            searchOpen: state.searchOpen,
            searchQuery: state.searchQuery,
            expandedEntity: state.expandedEntity,
          )
        : null;
    if (state.view != targetView) {
      UiTelemetry.logViewChanged(
        from: state.view.name,
        to: targetView.name,
        viaReturnContext: false,
      );
    }
    if (entity.kind == EntityKind.label) {
      UiTelemetry.logLabelHubOpened(entity.id);
    }
    state = state.copyWith(
      view: targetView,
      returnContext: nextReturnContext,
      clearReturnContext: !shouldSaveContext,
      expandedEntity: entity,
      revealEntityRequest: entity,
      clearActiveInlineEdit: true,
      clearActiveDeleteConfirm: true,
      clearActiveDraft: true,
      searchOpen: false,
      labelPickerOpen: false,
      labelPickerQuery: '',
      compactDrawerOpen: false,
    );
  }

  /// Opens the single active inline section editor targeting [target].
  void openInlineEdit(InlineEditTarget target) {
    UiTelemetry.logInlineEditOpened(
      kind: target.entity.kind.name,
      entityId: target.entity.id,
      section: target.sectionKey,
    );
    state = state.copyWith(
      expandedEntity: target.entity,
      activeInlineEdit: target,
      clearActiveDeleteConfirm: true,
      labelPickerOpen: target.sectionKey == TaskSectionKind.labels.name,
      labelPickerQuery: '',
    );
  }

  /// Opens Global Search on the Tasks view and closes any active draft card.
  void openSearch() {
    final previousView = state.view;
    if (previousView != ShellView.tasks) {
      UiTelemetry.logViewChanged(
        from: previousView.name,
        to: ShellView.tasks.name,
        viaReturnContext: false,
      );
    }
    state = state.copyWith(
      view: ShellView.tasks,
      searchOpen: true,
      clearActiveDraft: true,
      clearReturnContext: true,
      compactDrawerOpen: false,
      compactComposerOpen: false,
    );
  }

  /// Navigates directly to top-level [view] via chrome or sidebar, clearing `returnContext`.
  void openView(ShellView view) {
    final previousView = state.view;
    if (previousView != view) {
      UiTelemetry.logViewChanged(
        from: previousView.name,
        to: view.name,
        viaReturnContext: false,
      );
      if (view == ShellView.conflict || view == ShellView.recovery) {
        UiTelemetry.logConflictViewOpened(view.name);
      }
    }
    state = state.copyWith(
      view: view,
      clearReturnContext: true,
      clearExpandedEntity: true,
      clearActiveInlineEdit: true,
      clearActiveDeleteConfirm: true,
      clearActiveDraft: true,
      searchOpen: false,
      searchQuery: '',
      labelPickerOpen: false,
      labelPickerQuery: '',
      compactDrawerOpen: false,
      compactComposerOpen: false,
    );
  }

  /// Opens the inline delete confirmation for [entity].
  void requestInlineDelete(EntityRef entity) {
    state = state.copyWith(
      expandedEntity: entity,
      activeDeleteConfirm: entity,
      clearActiveInlineEdit: true,
      labelPickerOpen: false,
      labelPickerQuery: '',
    );
  }

  /// Wraps a local entity mutation on [target] so the board listener suppresses external-change notices.
  Future<T> runLocalEntityMutation<T>(
    EntityRef target,
    Future<T> Function() action,
  ) async {
    _suppressedLocalMutations.add(target);
    try {
      return await action();
    } finally {
      _suppressedLocalMutations.remove(target);
    }
  }

  /// Selects [labelId] (or clears filter when `null`), applying `U-LAYOUT-004` filter-clear side effects.
  void selectLabelFilter(String? labelId) {
    final previousView = state.view;
    if (previousView != ShellView.tasks) {
      UiTelemetry.logViewChanged(
        from: previousView.name,
        to: ShellView.tasks.name,
        viaReturnContext: false,
      );
    }
    final shouldCollapseExpanded = labelId == null && !state.searchOpen;
    state = state.copyWith(
      view: ShellView.tasks,
      activeLabelId: labelId,
      clearActiveLabelId: labelId == null,
      clearReturnContext: true,
      clearExpandedEntity: shouldCollapseExpanded,
      clearActiveInlineEdit: shouldCollapseExpanded,
      clearActiveDeleteConfirm: shouldCollapseExpanded,
      labelPickerOpen: false,
      labelPickerQuery: '',
      compactDrawerOpen: false,
    );
  }

  /// Selects task tier [tier] on the Tasks view and clears transient editing state.
  void selectTier(ShellTier tier) {
    final previousView = state.view;
    if (previousView != ShellView.tasks) {
      UiTelemetry.logViewChanged(
        from: previousView.name,
        to: ShellView.tasks.name,
        viaReturnContext: false,
      );
    }
    state = state.copyWith(
      view: ShellView.tasks,
      activeTier: tier,
      searchOpen: false,
      searchQuery: '',
      clearReturnContext: true,
      clearExpandedEntity: true,
      clearActiveInlineEdit: true,
      clearActiveDeleteConfirm: true,
      clearActiveDraft: true,
      labelPickerOpen: false,
      labelPickerQuery: '',
      compactDrawerOpen: false,
    );
  }

  /// Sets whether the compact mobile Quick-Add form is expanded.
  void setCompactComposerOpen(bool open) {
    state = state.copyWith(compactComposerOpen: open);
  }

  /// Opens or closes the compact slide-over navigation drawer.
  void setCompactDrawerOpen(bool open) {
    if (open) {
      state = state.copyWith(compactDrawerOpen: true);
      return;
    }
    state = state.copyWith(
      compactDrawerOpen: false,
      sidebarLabelsFilterOpen: false,
      sidebarLabelsFilterQuery: '',
      sidebarLocationsFilterOpen: false,
      sidebarLocationsFilterQuery: '',
    );
  }

  /// Opens or closes the inline/popover label picker.
  void setLabelPickerOpen(bool open) {
    state = state.copyWith(
      labelPickerOpen: open,
      labelPickerQuery: open ? state.labelPickerQuery : '',
    );
  }

  /// Updates the active query inside the Searchable Label Picker.
  void setLabelPickerQuery(String query) {
    state = state.copyWith(labelPickerQuery: query);
  }

  /// Updates the inline sidebar Labels filter query.
  void setSidebarLabelsFilterQuery(String query) {
    state = state.copyWith(sidebarLabelsFilterQuery: query);
  }

  /// Updates the inline sidebar Locations filter query.
  void setSidebarLocationsFilterQuery(String query) {
    state = state.copyWith(sidebarLocationsFilterQuery: query);
  }

  /// Steps the active tier by [delta] (`-1` or `+1`) clamped to `0..5` (`ArrowLeft`/`ArrowRight`).
  void stepTier(int delta) {
    if (state.view != ShellView.tasks || state.searchOpen) {
      return;
    }
    final nextIndex = (state.activeTier.index + delta).clamp(
      0,
      ShellTier.values.length - 1,
    );
    final nextTier = ShellTier.values[nextIndex];
    if (nextTier == state.activeTier) {
      return;
    }
    state = state.copyWith(
      activeTier: nextTier,
      clearExpandedEntity: true,
      clearActiveInlineEdit: true,
      clearActiveDeleteConfirm: true,
      labelPickerOpen: false,
      labelPickerQuery: '',
    );
  }

  /// Toggles expansion of [entity] under strict single-expand coordination.
  void toggleExpandEntity(EntityRef entity) {
    if (state.expandedEntity == entity) {
      collapseEntity();
      return;
    }
    expandEntity(entity);
  }

  /// Toggles collapse state of the sidebar Labels section, clearing filter when collapsing (`U-UX-001`).
  void toggleSidebarLabelsCollapsed() {
    final nextCollapsed = !state.sidebarLabelsCollapsed;
    state = state.copyWith(
      sidebarLabelsCollapsed: nextCollapsed,
      sidebarLabelsFilterOpen: nextCollapsed
          ? false
          : state.sidebarLabelsFilterOpen,
      sidebarLabelsFilterQuery: nextCollapsed
          ? ''
          : state.sidebarLabelsFilterQuery,
    );
  }

  /// Toggles the sidebar Labels inline filter, auto-expanding the section when opening (`U-UX-001`).
  void toggleSidebarLabelsFilter() {
    final nextOpen = !state.sidebarLabelsFilterOpen;
    state = state.copyWith(
      sidebarLabelsCollapsed: nextOpen ? false : state.sidebarLabelsCollapsed,
      sidebarLabelsFilterOpen: nextOpen,
      sidebarLabelsFilterQuery: nextOpen ? state.sidebarLabelsFilterQuery : '',
    );
  }

  /// Toggles collapse state of the sidebar Locations section, clearing filter when collapsing (`U-UX-001`).
  void toggleSidebarLocationsCollapsed() {
    final nextCollapsed = !state.sidebarLocationsCollapsed;
    state = state.copyWith(
      sidebarLocationsCollapsed: nextCollapsed,
      sidebarLocationsFilterOpen: nextCollapsed
          ? false
          : state.sidebarLocationsFilterOpen,
      sidebarLocationsFilterQuery: nextCollapsed
          ? ''
          : state.sidebarLocationsFilterQuery,
    );
  }

  /// Toggles the sidebar Locations inline filter, auto-expanding the section when opening (`U-UX-001`).
  void toggleSidebarLocationsFilter() {
    final nextOpen = !state.sidebarLocationsFilterOpen;
    state = state.copyWith(
      sidebarLocationsCollapsed: nextOpen
          ? false
          : state.sidebarLocationsCollapsed,
      sidebarLocationsFilterOpen: nextOpen,
      sidebarLocationsFilterQuery: nextOpen
          ? state.sidebarLocationsFilterQuery
          : '',
    );
  }

  /// Updates the Global Search query string.
  void updateSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Returns `true` when [entity] exists on [board].
  bool _entityExistsOnBoard(TaskBoard board, EntityRef entity) {
    return switch (entity.kind) {
      EntityKind.task => board.findTask(entity.id) != null,
      EntityKind.label => board.findLabel(entity.id) != null,
      EntityKind.location => board.findLocation(entity.id) != null,
    };
  }

  /// Reconciles active filter, expanded card, and active inline edit against external board updates.
  void _reconcileBoardUpdate(TaskBoard? previousBoard, TaskBoard nextBoard) {
    final currentLabelId = state.activeLabelId;
    if (currentLabelId != null &&
        !nextBoard.labels.any((label) => label.id == currentLabelId)) {
      final shouldCollapse = !state.searchOpen;
      state = state.copyWith(
        clearActiveLabelId: true,
        clearExpandedEntity: shouldCollapse,
        clearActiveInlineEdit: shouldCollapse,
        clearActiveDeleteConfirm: shouldCollapse,
        labelPickerOpen: false,
        labelPickerQuery: '',
        compactDrawerOpen: false,
      );
    }

    final trackedEntity =
        state.activeInlineEdit?.entity ?? state.expandedEntity;
    if (trackedEntity == null ||
        _suppressedLocalMutations.contains(trackedEntity)) {
      return;
    }

    if (!_entityExistsOnBoard(nextBoard, trackedEntity)) {
      state = state.copyWith(
        clearExpandedEntity: true,
        clearActiveInlineEdit: true,
        clearActiveDeleteConfirm: true,
        labelPickerOpen: false,
        labelPickerQuery: '',
      );
      final localizations = lookupAppLocalizations(ref.read(appLocaleProvider));
      ref
          .read(floatingNoticeControllerProvider.notifier)
          .showNotice(
            localizations.entityRemovedExternallyNotice,
            tone: NoticeTone.warning,
          );
      return;
    }

    final activeEdit = state.activeInlineEdit;
    if (activeEdit == null ||
        activeEdit.entity.kind != EntityKind.task ||
        activeEdit.sectionKey == 'history') {
      return;
    }
    final TaskItem? previousTask = previousBoard?.findTask(
      activeEdit.entity.id,
    );
    final TaskItem? nextTask = nextBoard.findTask(activeEdit.entity.id);
    final transitionedToCompleted =
        nextTask != null &&
        nextTask.isCompleted &&
        (previousTask == null || !previousTask.isCompleted);
    if (!transitionedToCompleted) {
      return;
    }
    state = state.copyWith(
      clearActiveInlineEdit: true,
      labelPickerOpen: false,
      labelPickerQuery: '',
    );
    final localizations = lookupAppLocalizations(ref.read(appLocaleProvider));
    ref
        .read(floatingNoticeControllerProvider.notifier)
        .showNotice(
          localizations.taskCompletedExternallyNotice,
          tone: NoticeTone.warning,
        );
  }

  /// Unwinds one in-shell layer in exact priority order, returning its diagnostic name or `null`.
  String? _unwindInShellLayer() {
    if (state.compactDrawerOpen) {
      setCompactDrawerOpen(false);
      return 'compact_drawer';
    }
    if (state.labelPickerOpen && state.labelPickerQuery.isNotEmpty) {
      setLabelPickerQuery('');
      return 'label_picker_query';
    }
    if (state.sidebarLabelsFilterOpen || state.sidebarLocationsFilterOpen) {
      state = state.copyWith(
        sidebarLabelsFilterOpen: false,
        sidebarLabelsFilterQuery: '',
        sidebarLocationsFilterOpen: false,
        sidebarLocationsFilterQuery: '',
      );
      return 'sidebar_filter';
    }
    if (state.labelPickerOpen) {
      setLabelPickerOpen(false);
      return 'label_picker';
    }
    if (state.activeDraft != null) {
      cancelDraft();
      return 'entity_draft';
    }
    if (state.searchOpen) {
      closeSearch();
      return 'global_search';
    }
    if (state.activeInlineEdit != null) {
      closeInlineEdit();
      return 'inline_edit';
    }
    if (state.activeDeleteConfirm != null) {
      cancelInlineDelete();
      return 'delete_confirm';
    }
    if (state.expandedEntity != null) {
      collapseEntity();
      return 'expanded_entity';
    }
    return null;
  }
}
