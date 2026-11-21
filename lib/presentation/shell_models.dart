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

import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Supported design-system color theme preset keys exposed to Rank 7 UI widgets.
enum AppThemePresetKey {
  /// Default WCAG AA verified Calm preset (`calm`).
  calm(presetId: 'calm'),

  /// Warm WCAG AA verified Plum Umber preset (`plum_umber`).
  plumUmber(presetId: 'plum_umber');

  /// Creates an [AppThemePresetKey].
  const AppThemePresetKey({required this.presetId});

  /// Canonical preset identifier matching `UiThemePresets.byId`.
  final String presetId;
}

/// Semantic visual tone for entity badges and chips.
enum BadgeTone {
  /// Neutral resting pill surface.
  neutral,

  /// Accent-tinted soft surface (e.g. Search Tier badge).
  soft,

  /// High-emphasis accent badge (e.g. manual Priority).
  accent,

  /// Amber warning badge (e.g. due lead window, auto-priority, blocked, suspended).
  warning,

  /// Crimson danger badge (e.g. overdue deadline).
  danger,

  /// Green success badge.
  success,
}

/// Semantic visual tone for top-level status banners.
enum BannerTone {
  /// Amber warning banner.
  warning,

  /// Crimson error banner.
  danger,

  /// Green confirmation banner.
  success,
}

/// Per-dimension override mode for task activation conditions.
enum ConditionDimensionMode {
  /// Inherit condition rules from assigned labels.
  inherit,

  /// Explicitly override label rules so this dimension always matches.
  any,

  /// Specify explicit custom rules on the task.
  custom,
}

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

/// Semantic visual tone for floating bottom notices and toasts.
enum NoticeTone {
  /// Default neutral informational toast.
  neutral,

  /// Accent-highlighted toast (e.g. Undo notice).
  accent,

  /// Amber warning toast (e.g. external removal or startup recovery).
  warning,

  /// Crimson danger toast (e.g. duplicate title or persistence error).
  danger,

  /// Green success toast.
  success,
}

/// Resolution outcome for a keyboard `Escape` or Android system Back request.
enum ShellDismissOutcome {
  /// Dismissed an active in-shell layer; keep the application open.
  handled,

  /// Clean `tasks` root state reached; permit OS back navigation / exit.
  allowSystemPop,
}

/// Model-free presentation enum mirroring per-workspace deadline lead windows.
enum ShellDueLeadOption {
  /// Disabled (`off`).
  off,

  /// Trigger at exact due instant (`0h`).
  atDue,

  /// 12 hours before due.
  hours12,

  /// 24 hours before due (default).
  hours24,

  /// 48 hours before due.
  hours48,

  /// 7 days before due.
  days7,
}

/// Model-free presentation enum mirroring display language choices.
enum ShellLanguageOption {
  /// Follow host operating system locale.
  system,

  /// Force English (`en`).
  english,

  /// Force German (`de`).
  german,
}

/// Model-free presentation enum mirroring foreground location status states.
enum ShellLocationStatusKind {
  /// Foreground location determination is turned off.
  disabled,

  /// Active location lookup is currently running.
  searching,

  /// Valid location fix is available.
  found,

  /// No location fix is currently available.
  unavailable,
}

/// Model-free presentation enum mirroring selectable location coordinate sources.
enum ShellLocationSourceType {
  /// Direct manual or current GPS latitude/longitude coordinates.
  gps,

  /// Forward-geocoded street address.
  address,

  /// Offline or geocoded Google Plus Code.
  plusCode,
}

/// Model-free presentation enum mirroring recurrence interval units.
enum ShellRepeatUnit {
  /// Daily recurrence unit.
  days,

  /// Weekly recurrence unit.
  weeks,

  /// Monthly recurrence unit.
  months,
}

/// Model-free presentation enum mirroring persistence storage targets.
enum ShellStorageMode {
  /// Local `.tdf` file only.
  local,

  /// Remote WebDAV `.tdf` file only.
  webdav,

  /// Both local and remote WebDAV `.tdf` files.
  both,
}

/// Chrome synchronization indicator state.
enum ShellSyncStatusKind {
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

/// Model-free presentation enum mirroring color brightness modes.
enum ShellThemeMode {
  /// Follow host operating system light/dark setting.
  system,

  /// Light appearance.
  light,

  /// Dark appearance.
  dark,
}

/// Model-free presentation enum mirroring the six dynamically derived task tiers.
enum ShellTier {
  /// Tier 0: Focus (`N / 3`).
  focus,

  /// Tier 1: Ready (`N / 5`).
  ready,

  /// Tier 2: Planned.
  planned,

  /// Tier 3: Blocked.
  blocked,

  /// Tier 4: Someday.
  someday,

  /// Tier 5: Completed.
  completed,
}

/// Model-free presentation enum mirroring time zone configuration modes.
enum ShellTimeZoneMode {
  /// Use host OS time zone automatically.
  automatic,

  /// Use a fixed manual UTC offset.
  manual,
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

/// Placement mode for active tasks in Quick-Add, Draft Cards, and live Placement switches.
enum TaskPlacementOption {
  /// Standard active queue placement.
  queue,

  /// Manual priority placement ahead of regular tasks.
  priority,

  /// Parked outside the active queue in Someday.
  someday,
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

/// Sealed outcome returned by model-free presentation mutation controllers.
sealed class ActionResult {
  /// Creates a [ActionResult].
  const ActionResult();
}

/// Outcome returned when a presentation mutation commits cleanly.
@immutable
final class ActionSucceeded extends ActionResult {
  /// Creates a [ActionSucceeded] result.
  const ActionSucceeded({this.entityId, this.noticeMessage});

  /// Optional identifier of the created or mutated entity.
  final String? entityId;

  /// Optional localized confirmation message emitted by the controller.
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
  /// Creates a [ActionValidationFailed] result.
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

/// Outcome returned when repository persistence rejects a mutation.
@immutable
final class ActionPersistFailed extends ActionResult {
  /// Creates a [ActionPersistFailed] result carrying [message].
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

  /// Creates an [InlineEditTarget] for a task section.
  factory InlineEditTarget.task(String taskId, TaskSectionKind section) =>
      InlineEditTarget(
        entity: EntityRef(kind: EntityKind.task, id: taskId),
        sectionKey: section.name,
      );

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

  /// Active task tier when leaving the Tasks view.
  final ShellTier tier;

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

/// Immutable theme and locale state exposed to `lib/main.dart` and `lib/ui/`.
@immutable
class ShellThemeState {
  /// Creates a [ShellThemeState].
  const ShellThemeState({
    required this.presetKey,
    required this.themeMode,
    required this.locale,
  });

  /// Resolved display [Locale] (`en` or `de`).
  final Locale locale;

  /// Selected design-system theme preset key.
  final AppThemePresetKey presetKey;

  /// Selected light/dark/system theme mode.
  final ShellThemeMode themeMode;

  /// Canonical preset identifier string (`'calm'` or `'plum_umber'`).
  String get presetId => presetKey.presetId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ShellThemeState &&
        other.presetKey == presetKey &&
        other.themeMode == themeMode &&
        other.locale == locale;
  }

  @override
  int get hashCode => Object.hash(presetKey, themeMode, locale);
}

/// Immutable model describing the active floating toast or Undo overlay (`U-UX-004`).
@immutable
class FloatingNoticeViewModel {
  /// Creates a [FloatingNoticeViewModel].
  const FloatingNoticeViewModel({
    required this.id,
    required this.message,
    required this.tone,
    this.actionLabel,
    this.undoSequence,
    this.shortcutHint,
    this.persistent = false,
    this.autoHideDuration,
  });

  /// Optional action button label (e.g. `Undo`).
  final String? actionLabel;

  /// Optional auto-hide duration (`8s` Undo / `5s` standard / `null` when persistent).
  final Duration? autoHideDuration;

  /// Monotonically increasing notice identifier for timer correlation.
  final int id;

  /// Localized message displayed inside the floating toast.
  final String message;

  /// Whether this notice remains visible until manually dismissed.
  final bool persistent;

  /// Optional desktop keyboard shortcut hint (e.g. `Ctrl+Z`).
  final String? shortcutHint;

  /// Visual severity tone of the floating toast.
  final NoticeTone tone;

  /// Optional session Undo sequence bound to the action button.
  final int? undoSequence;

  /// Whether this notice carries an actionable Undo callback.
  bool get hasUndoAction => undoSequence != null && actionLabel != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FloatingNoticeViewModel &&
        other.id == id &&
        other.message == message &&
        other.tone == tone &&
        other.actionLabel == actionLabel &&
        other.undoSequence == undoSequence &&
        other.shortcutHint == shortcutHint &&
        other.persistent == persistent &&
        other.autoHideDuration == autoHideDuration;
  }

  @override
  int get hashCode => Object.hash(
    id,
    message,
    tone,
    actionLabel,
    undoSequence,
    shortcutHint,
    persistent,
    autoHideDuration,
  );
}

/// Immutable transient navigation, filtering, expansion, draft, and inline-edit state of the adaptive shell.
@immutable
class AppShellState {
  /// Creates an [AppShellState].
  AppShellState({
    this.view = ShellView.tasks,
    this.activeTier = ShellTier.focus,
    this.activeLabelId,
    this.searchOpen = false,
    this.searchQuery = '',
    this.returnContext,
    this.expandedEntity,
    this.activeInlineEdit,
    this.activeDeleteConfirm,
    this.activeDraft,
    this.draftSeedTitle = '',
    this.draftSeedPlacement = TaskPlacementOption.queue,
    Iterable<String> draftSeedLabelIds = const <String>[],
    this.labelPickerOpen = false,
    this.labelPickerQuery = '',
    this.sidebarLabelsCollapsed = false,
    this.sidebarLabelsFilterOpen = false,
    this.sidebarLabelsFilterQuery = '',
    this.sidebarLocationsCollapsed = false,
    this.sidebarLocationsFilterOpen = false,
    this.sidebarLocationsFilterQuery = '',
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

  /// Currently selected task tier (`0..5`).
  final ShellTier activeTier;

  /// Whether the compact mobile Quick-Add form is currently expanded.
  final bool compactComposerOpen;

  /// Whether the compact slide-over navigation drawer is currently open.
  final bool compactDrawerOpen;

  /// Initial label identifiers seeded into an open Task Draft Card.
  final List<String> draftSeedLabelIds;

  /// Initial placement seeded into an open Task Draft Card.
  final TaskPlacementOption draftSeedPlacement;

  /// Initial title or name seeded into an open entity Draft Card.
  final String draftSeedTitle;

  /// Single currently expanded entity card across Tasks, Labels, and Locations.
  final EntityRef? expandedEntity;

  /// Whether the dismissible partial file-read status banner is currently hidden.
  final bool fileReadBannerDismissed;

  /// Whether an inline or popover Searchable Label Picker is currently open.
  final bool labelPickerOpen;

  /// Active query typed into the open Searchable Label Picker.
  final String labelPickerQuery;

  /// Saved context for back-navigation from Labels or Locations manager.
  final ReturnContext? returnContext;

  /// One-shot entity reveal request instructing the view to scroll the card into view.
  final EntityRef? revealEntityRequest;

  /// Whether Global Search mode is active on the Tasks view.
  final bool searchOpen;

  /// Active Global Search query string.
  final String searchQuery;

  /// Whether the sidebar Labels section is collapsed.
  final bool sidebarLabelsCollapsed;

  /// Whether the inline sidebar Labels filter input is open.
  final bool sidebarLabelsFilterOpen;

  /// Active query string in the sidebar Labels filter input.
  final String sidebarLabelsFilterQuery;

  /// Whether the sidebar Locations section is collapsed.
  final bool sidebarLocationsCollapsed;

  /// Whether the inline sidebar Locations filter input is open.
  final bool sidebarLocationsFilterOpen;

  /// Active query string in the sidebar Locations filter input.
  final String sidebarLocationsFilterQuery;

  /// Whether the dismissible sync error status banner is currently hidden.
  final bool syncErrorBannerDismissed;

  /// Active top-level shell route view.
  final ShellView view;

  /// Returns a copy of this [AppShellState] with updated fields.
  AppShellState copyWith({
    ShellView? view,
    ShellTier? activeTier,
    String? activeLabelId,
    bool clearActiveLabelId = false,
    bool? searchOpen,
    String? searchQuery,
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
    TaskPlacementOption? draftSeedPlacement,
    Iterable<String>? draftSeedLabelIds,
    bool? labelPickerOpen,
    String? labelPickerQuery,
    bool? sidebarLabelsCollapsed,
    bool? sidebarLabelsFilterOpen,
    String? sidebarLabelsFilterQuery,
    bool? sidebarLocationsCollapsed,
    bool? sidebarLocationsFilterOpen,
    String? sidebarLocationsFilterQuery,
    bool? compactDrawerOpen,
    bool? compactComposerOpen,
    bool? syncErrorBannerDismissed,
    bool? fileReadBannerDismissed,
    EntityRef? revealEntityRequest,
    bool clearRevealEntityRequest = false,
  }) {
    return AppShellState(
      view: view ?? this.view,
      activeTier: activeTier ?? this.activeTier,
      activeLabelId: clearActiveLabelId
          ? null
          : (activeLabelId ?? this.activeLabelId),
      searchOpen: searchOpen ?? this.searchOpen,
      searchQuery: searchQuery ?? this.searchQuery,
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
      labelPickerQuery: labelPickerQuery ?? this.labelPickerQuery,
      sidebarLabelsCollapsed:
          sidebarLabelsCollapsed ?? this.sidebarLabelsCollapsed,
      sidebarLabelsFilterOpen:
          sidebarLabelsFilterOpen ?? this.sidebarLabelsFilterOpen,
      sidebarLabelsFilterQuery:
          sidebarLabelsFilterQuery ?? this.sidebarLabelsFilterQuery,
      sidebarLocationsCollapsed:
          sidebarLocationsCollapsed ?? this.sidebarLocationsCollapsed,
      sidebarLocationsFilterOpen:
          sidebarLocationsFilterOpen ?? this.sidebarLocationsFilterOpen,
      sidebarLocationsFilterQuery:
          sidebarLocationsFilterQuery ?? this.sidebarLocationsFilterQuery,
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
    return other is AppShellState &&
        other.view == view &&
        other.activeTier == activeTier &&
        other.activeLabelId == activeLabelId &&
        other.searchOpen == searchOpen &&
        other.searchQuery == searchQuery &&
        other.returnContext == returnContext &&
        other.expandedEntity == expandedEntity &&
        other.activeInlineEdit == activeInlineEdit &&
        other.activeDeleteConfirm == activeDeleteConfirm &&
        other.activeDraft == activeDraft &&
        other.draftSeedTitle == draftSeedTitle &&
        other.draftSeedPlacement == draftSeedPlacement &&
        listEquals(other.draftSeedLabelIds, draftSeedLabelIds) &&
        other.labelPickerOpen == labelPickerOpen &&
        other.labelPickerQuery == labelPickerQuery &&
        other.sidebarLabelsCollapsed == sidebarLabelsCollapsed &&
        other.sidebarLabelsFilterOpen == sidebarLabelsFilterOpen &&
        other.sidebarLabelsFilterQuery == sidebarLabelsFilterQuery &&
        other.sidebarLocationsCollapsed == sidebarLocationsCollapsed &&
        other.sidebarLocationsFilterOpen == sidebarLocationsFilterOpen &&
        other.sidebarLocationsFilterQuery == sidebarLocationsFilterQuery &&
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
    searchQuery,
    returnContext,
    expandedEntity,
    activeInlineEdit,
    activeDeleteConfirm,
    activeDraft,
    draftSeedTitle,
    draftSeedPlacement,
    Object.hashAll(draftSeedLabelIds),
    labelPickerOpen,
    labelPickerQuery,
    sidebarLabelsCollapsed,
    sidebarLabelsFilterOpen,
    sidebarLabelsFilterQuery,
    sidebarLocationsCollapsed,
    sidebarLocationsFilterOpen,
    sidebarLocationsFilterQuery,
    compactDrawerOpen,
    compactComposerOpen,
    syncErrorBannerDismissed,
    fileReadBannerDismissed,
    revealEntityRequest,
  ]);
}
