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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/task_tier.dart';
import '../models/webdav_config.dart';
import 'config_providers.dart';
import 'floating_notice_providers.dart';
import 'sync_providers.dart';
import 'task_providers.dart';
import 'ui_telemetry.dart';
import 'workspace_providers.dart';

/// Provides the live search text inside the Searchable Label Picker without rebuilding unrelated shell chrome.
final labelPickerQueryProvider = NotifierProvider<TextQueryNotifier, String>(
  TextQueryNotifier.new,
);

/// Provides the live Global Search query string decoupled from [shellProvider] chrome rebuilds.
final searchQueryProvider = NotifierProvider<TextQueryNotifier, String>(
  TextQueryNotifier.new,
);

/// Provides centralized shell navigation, filtering, expansion, draft, and unwind state.
final shellProvider = NotifierProvider<ShellNotifier, ShellState>(
  ShellNotifier.new,
);

/// Provides the live inline sidebar Labels filter query decoupled from [shellProvider].
final sidebarLabelsFilterQueryProvider =
    NotifierProvider<TextQueryNotifier, String>(TextQueryNotifier.new);

/// Provides the live inline sidebar Locations filter query decoupled from [shellProvider].
final sidebarLocationsFilterQueryProvider =
    NotifierProvider<TextQueryNotifier, String>(TextQueryNotifier.new);

/// Kind of uncommitted draft card currently open at the top of a view.
enum EntityDraftKind {
  /// Uncommitted task draft card.
  task,

  /// Uncommitted label draft card.
  label,

  /// Uncommitted location draft card.
  location,
}

/// Unified entity type participating in single-expand card coordination.
enum EntityKind {
  /// Task card inside Tasks or Global Search view.
  task,

  /// Label card inside Labels manager view.
  label,

  /// Location card inside Locations manager view.
  location,
}

/// Editable section identifiers on an expanded Label card.
enum LabelSectionKind {
  /// Inline label name editor.
  title,

  /// Inline label note editor.
  note,

  /// Inline label reference links editor.
  links,

  /// Inline label color selector.
  color,

  /// Inline inherited activation conditions editor.
  conditions,
}

/// Editable section identifiers on an expanded Location card.
enum LocationSectionKind {
  /// Inline location name editor.
  title,

  /// Inline location note editor.
  note,

  /// Inline coordinates, source, and radius editor.
  coordinates,
}

/// Resolution outcome for a keyboard `Escape` or Android system Back request.
enum ShellDismissOutcome {
  /// Dismissed an active in-shell layer; keep the application open.
  handled,

  /// Clean `tasks` root state reached; permit OS back navigation or exit.
  allowSystemPop,
}

/// Top-level route views hosted inside the adaptive shell.
enum ShellView {
  /// Primary six-tier task board and Global Search view.
  tasks,

  /// Expandable Labels manager view.
  labels,

  /// Expandable Locations manager view.
  locations,

  /// Dual-persistence workspace Settings view.
  settings,

  /// Full-height Diagnostic Log viewer.
  logs,

  /// Full-height canonical Raw `TDF 0.8.0` preview view.
  rawTdf,

  /// `TDF-DEL-003` Deletion Conflict resolution view.
  conflict,

  /// `TDF-REC-002` Generation Recovery resolution view.
  recovery,
}

/// Chrome synchronization indicator state.
enum SyncStatusKind {
  /// Workspace persists locally only.
  localOnly,

  /// Workspace synchronized cleanly.
  synced,

  /// Synchronization request currently in flight.
  syncing,

  /// Deletion conflict or generation recovery pending.
  conflict,

  /// Synchronization error or file read error active.
  error,
}

/// Editable section identifiers on an expanded Task card.
enum TaskSectionKind {
  /// Inline task title editor.
  title,

  /// Inline task note editor.
  note,

  /// Inline task reference links editor.
  links,

  /// Inline task subtasks and auto-finish editor.
  subtasks,

  /// Inline or modal searchable label picker.
  labels,

  /// Inline due date, auto-prioritize, and deadline note editor.
  due,

  /// Inline recurrence interval and preparation lead editor.
  repeat,

  /// Inline suspension mode, timestamp, and deferral note editor.
  suspended,

  /// Inline prerequisite picker editor.
  prerequisites,

  /// Inline activation conditions editor.
  conditions,
}

/// Sealed outcome returned by domain action coordinators.
sealed class ActionResult {
  /// Creates an [ActionResult].
  const ActionResult();
}

/// Outcome returned when repository persistence rejects a mutation.
@immutable
final class ActionPersistFailed extends ActionResult {
  /// Creates an [ActionPersistFailed] result carrying [message].
  const ActionPersistFailed({required this.message});

  /// Sanitized localized persistence error message.
  final String message;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ActionPersistFailed && other.message == message;
  }

  @override
  int get hashCode => message.hashCode;
}

/// Outcome returned when a mutation commits cleanly.
@immutable
final class ActionSucceeded extends ActionResult {
  /// Creates an [ActionSucceeded] result.
  const ActionSucceeded({this.entityId, this.noticeMessage});

  /// Optional identifier of the created or mutated entity.
  final String? entityId;

  /// Optional localized confirmation message emitted by the coordinator.
  final String? noticeMessage;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ActionSucceeded &&
        other.entityId == entityId &&
        other.noticeMessage == noticeMessage;
  }

  @override
  int get hashCode => Object.hash(entityId, noticeMessage);
}

/// Outcome returned when client-side validation rejects a draft or inline edit.
@immutable
final class ActionValidationFailed extends ActionResult {
  /// Creates an [ActionValidationFailed] result.
  ActionValidationFailed({
    required this.message,
    Map<String, String> fieldErrors = const <String, String>{},
  }) : fieldErrors = Map<String, String>.unmodifiable(fieldErrors);

  /// Optional per-field localized error map keyed by logical field name.
  final Map<String, String> fieldErrors;

  /// Primary localized validation error message.
  final String message;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ActionValidationFailed &&
        other.message == message &&
        mapEquals(other.fieldErrors, fieldErrors);
  }

  @override
  int get hashCode => Object.hash(
    message,
    Object.hashAll(
      fieldErrors.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}

/// Immutable identifier referencing one expandable entity card in the shell.
@immutable
class EntityRef {
  /// Creates an [EntityRef].
  const EntityRef({required this.kind, required this.id});

  /// Canonical entity identifier.
  final String id;

  /// Entity domain kind.
  final EntityKind kind;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EntityRef && other.kind == kind && other.id == id;
  }

  @override
  int get hashCode => Object.hash(kind, id);
}

/// Immutable identifier targeting the single currently open inline section editor.
@immutable
class InlineEditTarget {
  /// Creates an [InlineEditTarget].
  const InlineEditTarget({required this.entity, required this.sectionKey});

  /// Creates an [InlineEditTarget] for a label section.
  factory InlineEditTarget.label(String labelId, LabelSectionKind section) =>
      InlineEditTarget(
        entity: EntityRef(kind: EntityKind.label, id: labelId),
        sectionKey: section.name,
      );

  /// Creates an [InlineEditTarget] for a location section.
  factory InlineEditTarget.location(
    String locationId,
    LocationSectionKind section,
  ) => InlineEditTarget(
    entity: EntityRef(kind: EntityKind.location, id: locationId),
    sectionKey: section.name,
  );

  /// Creates an [InlineEditTarget] for a task section.
  factory InlineEditTarget.task(String taskId, TaskSectionKind section) =>
      InlineEditTarget(
        entity: EntityRef(kind: EntityKind.task, id: taskId),
        sectionKey: section.name,
      );

  /// Owning entity card reference.
  final EntityRef entity;

  /// Canonical section key name matching the owning entity's section enum.
  final String sectionKey;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InlineEditTarget &&
        other.entity == entity &&
        other.sectionKey == sectionKey;
  }

  @override
  int get hashCode => Object.hash(entity, sectionKey);
}

/// Saved task or search context restored when clicking Back from Labels or Locations manager (`U-UX-002`).
@immutable
class ReturnContext {
  /// Creates a [ReturnContext].
  const ReturnContext({
    required this.view,
    required this.tier,
    required this.labelId,
    required this.searchOpen,
    required this.searchQuery,
    required this.expandedEntity,
  });

  /// Expanded entity card that originated the navigation, if any.
  final EntityRef? expandedEntity;

  /// Active label filter identifier when leaving the Tasks/Search view.
  final String? labelId;

  /// Whether Global Search was open when leaving the Tasks view.
  final bool searchOpen;

  /// Active search query when leaving the Tasks view.
  final String searchQuery;

  /// Active domain task tier when leaving the Tasks view.
  final TaskTier tier;

  /// Originating shell view (always `ShellView.tasks`).
  final ShellView view;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReturnContext &&
        other.view == view &&
        other.tier == tier &&
        other.labelId == labelId &&
        other.searchOpen == searchOpen &&
        other.searchQuery == searchQuery &&
        other.expandedEntity == expandedEntity;
  }

  @override
  int get hashCode =>
      Object.hash(view, tier, labelId, searchOpen, searchQuery, expandedEntity);
}

/// Coordinates adaptive shell routes, `returnContext`, single-expand cards, inline editing,
/// external board reconciliation, and unified desktop `Escape` / Android `PopScope` unwinding.
class ShellNotifier extends Notifier<ShellState> {
  String? _activeWorkspaceId;
  TaskBoard? _lastSeenBoard;
  final Set<EntityRef> _suppressedLocalMutations = <EntityRef>{};

  @override
  ShellState build() {
    _suppressedLocalMutations.clear();
    _activeWorkspaceId = ref.read(activeWorkspaceProvider).asData?.value.id;
    _lastSeenBoard = ref.read(taskNotifierProvider).asData?.value;

    ref.listen<String?>(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
      _handleWorkspaceIdChanged,
    );

    ref.listen<AsyncValue<TaskBoard>>(taskNotifierProvider, (previous, next) {
      final board = next.asData?.value;
      if (board == null) {
        return;
      }
      final baselineBoard = previous?.asData?.value ?? _lastSeenBoard;
      _lastSeenBoard = board;
      _reconcileBoardUpdate(baselineBoard, board);
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

    return ShellState();
  }

  /// Cancels any open uncommitted entity draft card.
  void cancelDraft() {
    final kind = state.activeDraft;
    if (kind == null) {
      return;
    }
    UiTelemetry.logEntityDraftCancelled(kind.name);
    ref.read(labelPickerQueryProvider.notifier).clear();
    state = state.copyWith(
      clearActiveDraft: true,
      draftSeedTitle: '',
      draftSeedPlacement: QuickAddMode.standard,
      draftSeedLabelIds: const <String>[],
      labelPickerOpen: false,
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
    ref.read(labelPickerQueryProvider.notifier).clear();
    state = state.copyWith(clearActiveInlineEdit: true, labelPickerOpen: false);
  }

  /// Closes Global Search and clears [searchQueryProvider].
  void closeSearch() {
    final hasQuery = ref.read(searchQueryProvider).isNotEmpty;
    if (!state.searchOpen && !hasQuery) {
      return;
    }
    ref.read(searchQueryProvider.notifier).clear();
    state = state.copyWith(searchOpen: false);
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
    ref.read(labelPickerQueryProvider.notifier).clear();
    state = state.copyWith(
      clearExpandedEntity: true,
      clearActiveInlineEdit: true,
      clearActiveDeleteConfirm: true,
      labelPickerOpen: false,
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
    ref.read(labelPickerQueryProvider.notifier).clear();
    state = state.copyWith(
      expandedEntity: entity,
      clearActiveInlineEdit: true,
      clearActiveDeleteConfirm: true,
      labelPickerOpen: false,
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
    ref.read(searchQueryProvider.notifier).setQuery(saved.searchQuery);
    ref.read(labelPickerQueryProvider.notifier).clear();
    state = state.copyWith(
      view: saved.view,
      activeTier: saved.tier,
      activeLabelId: saved.labelId,
      clearActiveLabelId: saved.labelId == null,
      searchOpen: saved.searchOpen,
      expandedEntity: saved.expandedEntity,
      clearExpandedEntity: saved.expandedEntity == null,
      revealEntityRequest: saved.expandedEntity,
      clearRevealEntityRequest: saved.expandedEntity == null,
      clearReturnContext: true,
      clearActiveInlineEdit: true,
      clearActiveDeleteConfirm: true,
      clearActiveDraft: true,
      labelPickerOpen: false,
      compactDrawerOpen: false,
    );
  }

  /// Opens an uncommitted entity draft card of [kind] at the top of the current view (`U-CARD-006`).
  void openDraft(
    EntityDraftKind kind, {
    String seedTitle = '',
    QuickAddMode seedPlacement = QuickAddMode.standard,
    List<String> seedLabelIds = const <String>[],
  }) {
    UiTelemetry.logEntityDraftOpened(kind.name);
    ref.read(labelPickerQueryProvider.notifier).clear();
    state = state.copyWith(
      activeDraft: kind,
      draftSeedTitle: seedTitle,
      draftSeedPlacement: seedPlacement,
      draftSeedLabelIds: seedLabelIds,
      clearExpandedEntity: true,
      clearActiveInlineEdit: true,
      clearActiveDeleteConfirm: true,
      labelPickerOpen: false,
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
            searchQuery: ref.read(searchQueryProvider),
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
    ref.read(labelPickerQueryProvider.notifier).clear();
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
    ref.read(labelPickerQueryProvider.notifier).clear();
    state = state.copyWith(
      expandedEntity: target.entity,
      activeInlineEdit: target,
      clearActiveDeleteConfirm: true,
      labelPickerOpen: target.sectionKey == TaskSectionKind.labels.name,
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
    ref.read(searchQueryProvider.notifier).clear();
    ref.read(labelPickerQueryProvider.notifier).clear();
    state = state.copyWith(
      view: view,
      clearReturnContext: true,
      clearExpandedEntity: true,
      clearActiveInlineEdit: true,
      clearActiveDeleteConfirm: true,
      clearActiveDraft: true,
      searchOpen: false,
      labelPickerOpen: false,
      compactDrawerOpen: false,
      compactComposerOpen: false,
    );
  }

  /// Opens the inline delete confirmation for [entity].
  void requestInlineDelete(EntityRef entity) {
    ref.read(labelPickerQueryProvider.notifier).clear();
    state = state.copyWith(
      expandedEntity: entity,
      activeDeleteConfirm: entity,
      clearActiveInlineEdit: true,
      labelPickerOpen: false,
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
    ref.read(labelPickerQueryProvider.notifier).clear();
    state = state.copyWith(
      view: ShellView.tasks,
      activeLabelId: labelId,
      clearActiveLabelId: labelId == null,
      clearReturnContext: true,
      clearExpandedEntity: shouldCollapseExpanded,
      clearActiveInlineEdit: shouldCollapseExpanded,
      clearActiveDeleteConfirm: shouldCollapseExpanded,
      labelPickerOpen: false,
      compactDrawerOpen: false,
    );
  }

  /// Selects domain task [tier] on the Tasks view and clears transient editing state.
  void selectTier(TaskTier tier) {
    final previousView = state.view;
    if (previousView != ShellView.tasks) {
      UiTelemetry.logViewChanged(
        from: previousView.name,
        to: ShellView.tasks.name,
        viaReturnContext: false,
      );
    }
    ref.read(searchQueryProvider.notifier).clear();
    ref.read(labelPickerQueryProvider.notifier).clear();
    state = state.copyWith(
      view: ShellView.tasks,
      activeTier: tier,
      searchOpen: false,
      clearReturnContext: true,
      clearExpandedEntity: true,
      clearActiveInlineEdit: true,
      clearActiveDeleteConfirm: true,
      clearActiveDraft: true,
      labelPickerOpen: false,
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
    ref.read(sidebarLabelsFilterQueryProvider.notifier).clear();
    ref.read(sidebarLocationsFilterQueryProvider.notifier).clear();
    state = state.copyWith(
      compactDrawerOpen: false,
      sidebarLabelsFilterOpen: false,
      sidebarLocationsFilterOpen: false,
    );
  }

  /// Opens or closes the inline or popover label picker.
  void setLabelPickerOpen(bool open) {
    if (!open) {
      ref.read(labelPickerQueryProvider.notifier).clear();
    }
    state = state.copyWith(labelPickerOpen: open);
  }

  /// Steps the active tier by [delta] (`-1` or `+1`) clamped to `0..5` (`ArrowLeft`/`ArrowRight`).
  void stepTier(int delta) {
    if (state.view != ShellView.tasks || state.searchOpen) {
      return;
    }
    final nextIndex = (state.activeTier.index + delta).clamp(
      0,
      TaskTier.values.length - 1,
    );
    final nextTier = TaskTier.values[nextIndex];
    if (nextTier == state.activeTier) {
      return;
    }
    ref.read(labelPickerQueryProvider.notifier).clear();
    state = state.copyWith(
      activeTier: nextTier,
      clearExpandedEntity: true,
      clearActiveInlineEdit: true,
      clearActiveDeleteConfirm: true,
      labelPickerOpen: false,
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
    if (nextCollapsed) {
      ref.read(sidebarLabelsFilterQueryProvider.notifier).clear();
    }
    state = state.copyWith(
      sidebarLabelsCollapsed: nextCollapsed,
      sidebarLabelsFilterOpen: nextCollapsed
          ? false
          : state.sidebarLabelsFilterOpen,
    );
  }

  /// Toggles the sidebar Labels inline filter, auto-expanding the section when opening (`U-UX-001`).
  void toggleSidebarLabelsFilter() {
    final nextOpen = !state.sidebarLabelsFilterOpen;
    if (!nextOpen) {
      ref.read(sidebarLabelsFilterQueryProvider.notifier).clear();
    }
    state = state.copyWith(
      sidebarLabelsCollapsed: nextOpen ? false : state.sidebarLabelsCollapsed,
      sidebarLabelsFilterOpen: nextOpen,
    );
  }

  /// Toggles collapse state of the sidebar Locations section, clearing filter when collapsing (`U-UX-001`).
  void toggleSidebarLocationsCollapsed() {
    final nextCollapsed = !state.sidebarLocationsCollapsed;
    if (nextCollapsed) {
      ref.read(sidebarLocationsFilterQueryProvider.notifier).clear();
    }
    state = state.copyWith(
      sidebarLocationsCollapsed: nextCollapsed,
      sidebarLocationsFilterOpen: nextCollapsed
          ? false
          : state.sidebarLocationsFilterOpen,
    );
  }

  /// Toggles the sidebar Locations inline filter, auto-expanding the section when opening (`U-UX-001`).
  void toggleSidebarLocationsFilter() {
    final nextOpen = !state.sidebarLocationsFilterOpen;
    if (!nextOpen) {
      ref.read(sidebarLocationsFilterQueryProvider.notifier).clear();
    }
    state = state.copyWith(
      sidebarLocationsCollapsed: nextOpen
          ? false
          : state.sidebarLocationsCollapsed,
      sidebarLocationsFilterOpen: nextOpen,
    );
  }

  /// Returns `true` when [entity] exists on [board].
  bool _entityExistsOnBoard(TaskBoard board, EntityRef entity) {
    return switch (entity.kind) {
      EntityKind.task => board.findTask(entity.id) != null,
      EntityKind.label => board.findLabel(entity.id) != null,
      EntityKind.location => board.findLocation(entity.id) != null,
    };
  }

  /// Resets transient navigation, expansion, draft, and text-query state when switching workspaces.
  void _handleWorkspaceIdChanged(
    String? previousWorkspaceId,
    String? nextWorkspaceId,
  ) {
    if (nextWorkspaceId == null) {
      return;
    }
    final switchedWorkspace =
        _activeWorkspaceId != null && _activeWorkspaceId != nextWorkspaceId;
    _activeWorkspaceId = nextWorkspaceId;
    if (!switchedWorkspace) {
      return;
    }
    _suppressedLocalMutations.clear();
    _lastSeenBoard = null;
    ref.read(searchQueryProvider.notifier).clear();
    ref.read(labelPickerQueryProvider.notifier).clear();
    ref.read(sidebarLabelsFilterQueryProvider.notifier).clear();
    ref.read(sidebarLocationsFilterQueryProvider.notifier).clear();
    state = ShellState();
  }

  /// Reconciles active filter, expanded card, and active inline edit against external board updates.
  void _reconcileBoardUpdate(TaskBoard? previousBoard, TaskBoard nextBoard) {
    final currentLabelId = state.activeLabelId;
    if (currentLabelId != null &&
        !nextBoard.labels.any((label) => label.id == currentLabelId)) {
      final shouldCollapse = !state.searchOpen;
      ref.read(labelPickerQueryProvider.notifier).clear();
      state = state.copyWith(
        clearActiveLabelId: true,
        clearExpandedEntity: shouldCollapse,
        clearActiveInlineEdit: shouldCollapse,
        clearActiveDeleteConfirm: shouldCollapse,
        labelPickerOpen: false,
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
      ref.read(labelPickerQueryProvider.notifier).clear();
      state = state.copyWith(
        clearExpandedEntity: true,
        clearActiveInlineEdit: true,
        clearActiveDeleteConfirm: true,
        labelPickerOpen: false,
      );
      final localizations = lookupAppLocalizations(ref.read(appLocaleProvider));
      ref
          .read(floatingNoticeProvider.notifier)
          .showNotice(
            localizations.entityRemovedExternallyNotice,
            tone: FloatingNoticeTone.warning,
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
        previousTask != null &&
        !previousTask.isCompleted;
    if (!transitionedToCompleted) {
      return;
    }
    ref.read(labelPickerQueryProvider.notifier).clear();
    state = state.copyWith(clearActiveInlineEdit: true, labelPickerOpen: false);
    final localizations = lookupAppLocalizations(ref.read(appLocaleProvider));
    ref
        .read(floatingNoticeProvider.notifier)
        .showNotice(
          localizations.taskCompletedExternallyNotice,
          tone: FloatingNoticeTone.warning,
        );
  }

  /// Unwinds one in-shell layer in exact priority order, returning its diagnostic name or `null`.
  String? _unwindInShellLayer() {
    if (state.compactDrawerOpen) {
      setCompactDrawerOpen(false);
      return 'compact_drawer';
    }
    if (state.labelPickerOpen &&
        ref.read(labelPickerQueryProvider).isNotEmpty) {
      ref.read(labelPickerQueryProvider.notifier).clear();
      return 'label_picker_query';
    }
    if (state.sidebarLabelsFilterOpen || state.sidebarLocationsFilterOpen) {
      ref.read(sidebarLabelsFilterQueryProvider.notifier).clear();
      ref.read(sidebarLocationsFilterQueryProvider.notifier).clear();
      state = state.copyWith(
        sidebarLabelsFilterOpen: false,
        sidebarLocationsFilterOpen: false,
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

/// Immutable transient navigation, filtering, expansion, draft, and inline-edit state of the adaptive shell.
@immutable
class ShellState {
  /// Creates a [ShellState].
  ShellState({
    this.view = ShellView.tasks,
    this.activeTier = TaskTier.focus,
    this.activeLabelId,
    this.searchOpen = false,
    this.returnContext,
    this.expandedEntity,
    this.activeInlineEdit,
    this.activeDeleteConfirm,
    this.activeDraft,
    this.draftSeedTitle = '',
    this.draftSeedPlacement = QuickAddMode.standard,
    Iterable<String> draftSeedLabelIds = const <String>[],
    this.labelPickerOpen = false,
    this.sidebarLabelsCollapsed = false,
    this.sidebarLabelsFilterOpen = false,
    this.sidebarLocationsCollapsed = false,
    this.sidebarLocationsFilterOpen = false,
    this.compactDrawerOpen = false,
    this.compactComposerOpen = false,
    this.syncErrorBannerDismissed = false,
    this.fileReadBannerDismissed = false,
    this.revealEntityRequest,
  }) : draftSeedLabelIds = List<String>.unmodifiable(draftSeedLabelIds);

  /// Entity currently showing an inline `Keep` / `Yes, delete` confirmation, if any.
  final EntityRef? activeDeleteConfirm;

  /// Currently open uncommitted entity draft card kind, if any.
  final EntityDraftKind? activeDraft;

  /// Currently open single-section inline editor target, if any.
  final InlineEditTarget? activeInlineEdit;

  /// Active sidebar label filter identifier, or `null` for `All Tasks`.
  final String? activeLabelId;

  /// Currently selected domain task tier (`0..5`).
  final TaskTier activeTier;

  /// Whether the compact mobile Quick-Add form is currently expanded.
  final bool compactComposerOpen;

  /// Whether the compact slide-over navigation drawer is currently open.
  final bool compactDrawerOpen;

  /// Initial label identifiers seeded into an open Task Draft Card.
  final List<String> draftSeedLabelIds;

  /// Initial placement seeded into an open Task Draft Card.
  final QuickAddMode draftSeedPlacement;

  /// Initial title or name seeded into an open entity Draft Card.
  final String draftSeedTitle;

  /// Single currently expanded entity card across Tasks, Labels, and Locations.
  final EntityRef? expandedEntity;

  /// Whether the dismissible partial file-read status banner is currently hidden.
  final bool fileReadBannerDismissed;

  /// Whether an inline or popover Searchable Label Picker is currently open.
  final bool labelPickerOpen;

  /// Saved context for back-navigation from Labels or Locations manager.
  final ReturnContext? returnContext;

  /// One-shot entity reveal request instructing the view to scroll the card into view.
  final EntityRef? revealEntityRequest;

  /// Whether Global Search mode is active on the Tasks view.
  final bool searchOpen;

  /// Whether the sidebar Labels section is collapsed.
  final bool sidebarLabelsCollapsed;

  /// Whether the inline sidebar Labels filter input is open.
  final bool sidebarLabelsFilterOpen;

  /// Whether the sidebar Locations section is collapsed.
  final bool sidebarLocationsCollapsed;

  /// Whether the inline sidebar Locations filter input is open.
  final bool sidebarLocationsFilterOpen;

  /// Whether the dismissible sync error status banner is currently hidden.
  final bool syncErrorBannerDismissed;

  /// Active top-level shell route view.
  final ShellView view;

  /// Returns a copy of this [ShellState] with updated fields.
  ShellState copyWith({
    ShellView? view,
    TaskTier? activeTier,
    String? activeLabelId,
    bool clearActiveLabelId = false,
    bool? searchOpen,
    ReturnContext? returnContext,
    bool clearReturnContext = false,
    EntityRef? expandedEntity,
    bool clearExpandedEntity = false,
    InlineEditTarget? activeInlineEdit,
    bool clearActiveInlineEdit = false,
    EntityRef? activeDeleteConfirm,
    bool clearActiveDeleteConfirm = false,
    EntityDraftKind? activeDraft,
    bool clearActiveDraft = false,
    String? draftSeedTitle,
    QuickAddMode? draftSeedPlacement,
    Iterable<String>? draftSeedLabelIds,
    bool? labelPickerOpen,
    bool? sidebarLabelsCollapsed,
    bool? sidebarLabelsFilterOpen,
    bool? sidebarLocationsCollapsed,
    bool? sidebarLocationsFilterOpen,
    bool? compactDrawerOpen,
    bool? compactComposerOpen,
    bool? syncErrorBannerDismissed,
    bool? fileReadBannerDismissed,
    EntityRef? revealEntityRequest,
    bool clearRevealEntityRequest = false,
  }) {
    return ShellState(
      view: view ?? this.view,
      activeTier: activeTier ?? this.activeTier,
      activeLabelId: clearActiveLabelId
          ? null
          : (activeLabelId ?? this.activeLabelId),
      searchOpen: searchOpen ?? this.searchOpen,
      returnContext: clearReturnContext
          ? null
          : (returnContext ?? this.returnContext),
      expandedEntity: clearExpandedEntity
          ? null
          : (expandedEntity ?? this.expandedEntity),
      activeInlineEdit: clearActiveInlineEdit
          ? null
          : (activeInlineEdit ?? this.activeInlineEdit),
      activeDeleteConfirm: clearActiveDeleteConfirm
          ? null
          : (activeDeleteConfirm ?? this.activeDeleteConfirm),
      activeDraft: clearActiveDraft ? null : (activeDraft ?? this.activeDraft),
      draftSeedTitle: draftSeedTitle ?? this.draftSeedTitle,
      draftSeedPlacement: draftSeedPlacement ?? this.draftSeedPlacement,
      draftSeedLabelIds: draftSeedLabelIds ?? this.draftSeedLabelIds,
      labelPickerOpen: labelPickerOpen ?? this.labelPickerOpen,
      sidebarLabelsCollapsed:
          sidebarLabelsCollapsed ?? this.sidebarLabelsCollapsed,
      sidebarLabelsFilterOpen:
          sidebarLabelsFilterOpen ?? this.sidebarLabelsFilterOpen,
      sidebarLocationsCollapsed:
          sidebarLocationsCollapsed ?? this.sidebarLocationsCollapsed,
      sidebarLocationsFilterOpen:
          sidebarLocationsFilterOpen ?? this.sidebarLocationsFilterOpen,
      compactDrawerOpen: compactDrawerOpen ?? this.compactDrawerOpen,
      compactComposerOpen: compactComposerOpen ?? this.compactComposerOpen,
      syncErrorBannerDismissed:
          syncErrorBannerDismissed ?? this.syncErrorBannerDismissed,
      fileReadBannerDismissed:
          fileReadBannerDismissed ?? this.fileReadBannerDismissed,
      revealEntityRequest: clearRevealEntityRequest
          ? null
          : (revealEntityRequest ?? this.revealEntityRequest),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ShellState &&
        other.view == view &&
        other.activeTier == activeTier &&
        other.activeLabelId == activeLabelId &&
        other.searchOpen == searchOpen &&
        other.returnContext == returnContext &&
        other.expandedEntity == expandedEntity &&
        other.activeInlineEdit == activeInlineEdit &&
        other.activeDeleteConfirm == activeDeleteConfirm &&
        other.activeDraft == activeDraft &&
        other.draftSeedTitle == draftSeedTitle &&
        other.draftSeedPlacement == draftSeedPlacement &&
        listEquals(other.draftSeedLabelIds, draftSeedLabelIds) &&
        other.labelPickerOpen == labelPickerOpen &&
        other.sidebarLabelsCollapsed == sidebarLabelsCollapsed &&
        other.sidebarLabelsFilterOpen == sidebarLabelsFilterOpen &&
        other.sidebarLocationsCollapsed == sidebarLocationsCollapsed &&
        other.sidebarLocationsFilterOpen == sidebarLocationsFilterOpen &&
        other.compactDrawerOpen == compactDrawerOpen &&
        other.compactComposerOpen == compactComposerOpen &&
        other.syncErrorBannerDismissed == syncErrorBannerDismissed &&
        other.fileReadBannerDismissed == fileReadBannerDismissed &&
        other.revealEntityRequest == revealEntityRequest;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    view,
    activeTier,
    activeLabelId,
    searchOpen,
    returnContext,
    expandedEntity,
    activeInlineEdit,
    activeDeleteConfirm,
    activeDraft,
    draftSeedTitle,
    draftSeedPlacement,
    Object.hashAll(draftSeedLabelIds),
    labelPickerOpen,
    sidebarLabelsCollapsed,
    sidebarLabelsFilterOpen,
    sidebarLocationsCollapsed,
    sidebarLocationsFilterOpen,
    compactDrawerOpen,
    compactComposerOpen,
    syncErrorBannerDismissed,
    fileReadBannerDismissed,
    revealEntityRequest,
  ]);
}

/// Lightweight notifier holding a single high-frequency text filter or search query.
class TextQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  /// Resets the query string to empty.
  void clear() {
    if (state.isNotEmpty) {
      state = '';
    }
  }

  /// Replaces the query string with [query].
  void setQuery(String query) {
    if (state != query) {
      state = query;
    }
  }
}

/// Maps [storageMode] and [syncState] into the top-bar [SyncStatusKind].
SyncStatusKind resolveSyncStatusKind({
  required StorageMode storageMode,
  required SyncState syncState,
}) {
  if (syncState.isSyncing) {
    return SyncStatusKind.syncing;
  }
  if (syncState.hasOpenConflict || syncState.syncOutcome != null) {
    return SyncStatusKind.conflict;
  }
  if (syncState.errorMessage != null ||
      (syncState.fileReadReport?.hasFailure ?? false)) {
    return SyncStatusKind.error;
  }
  if (storageMode == StorageMode.local) {
    return SyncStatusKind.localOnly;
  }
  return SyncStatusKind.synced;
}
