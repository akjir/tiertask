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

import '../l10n/app_localizations.dart';
import '../l10n/storage_file_read_localization_extension.dart';
import '../l10n/tier_localization_extension.dart';
import '../models/storage_file_read_status.dart';
import '../models/task_tier.dart';
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';
import 'shell_models.dart';

const List<String> canonicalLabelPresetHexColors = <String>[
  '#2196F3',
  '#4CAF50',
  '#FF9100',
  '#E91E63',
  '#9C27B0',
  '#00BCD4',
  '#EB06FF',
  '#00E5FF',
];

/// Semantic icon key for collapsed entity card badges mapped inside `lib/ui/`.
enum CardBadgeIconKey {
  /// Tier indicator icon (Search view).
  tierFocus,

  /// Tier indicator icon (Ready).
  tierReady,

  /// Tier indicator icon (Planned).
  tierPlanned,

  /// Tier indicator icon (Blocked).
  tierBlocked,

  /// Tier indicator icon (Someday).
  tierSomeday,

  /// Tier indicator icon (Completed).
  tierCompleted,

  /// Due or overdue deadline indicator.
  due,

  /// Manual or automatic deadline priority indicator.
  priority,

  /// Suspended indicator.
  suspended,

  /// Prerequisite blocker indicator.
  blockedBy,

  /// Activation conditions indicator.
  conditions,

  /// Standard subtasks progress indicator.
  subtasks,

  /// Auto-finish subtasks progress indicator.
  subtasksAutoFinish,

  /// Recurrence interval indicator.
  repeat,

  /// Note indicator.
  note,

  /// Reference links indicator.
  links,

  /// History journal indicator.
  history,
}

/// Top-level banner category distinguishing interactive actions.
enum ShellBannerKind {
  /// WebDAV enabled but unconfigured (`Configure`).
  unconfiguredWebDav,

  /// General sync error or generation rollback (`Retry` + `Settings`).
  syncError,

  /// Partial file-read failure where one storage target remained readable.
  partialFileRead,

  /// Unresolved `TDF-DEL-003` deletion conflict (`Resolve conflict`).
  deletionConflict,

  /// Unresolved `TDF-REC-002` generation recovery (`Open recovery`).
  recoveryRequired,
}

/// Immutable pill badge rendered in a collapsed entity metadata strip.
@immutable
class CardBadgeViewModel {
  /// Creates a [CardBadgeViewModel].
  const CardBadgeViewModel({
    required this.label,
    required this.tone,
    required this.iconKey,
  });

  /// Semantic icon identifier resolved by `lib/ui/ui_icon_mapper.dart`.
  final CardBadgeIconKey iconKey;

  /// Localized badge text.
  final String label;

  /// Visual severity tone.
  final BadgeTone tone;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CardBadgeViewModel &&
        other.label == label &&
        other.tone == tone &&
        other.iconKey == iconKey;
  }

  @override
  int get hashCode => Object.hash(label, tone, iconKey);
}

/// Immutable model-free representation of activation condition editor state.
@immutable
class ConditionDraftViewModel {
  /// Creates a [ConditionDraftViewModel].
  ConditionDraftViewModel({
    this.ignoreAllLabelConditions = false,
    this.daysMode = ConditionDimensionMode.inherit,
    Iterable<int> selectedWeekdays = const <int>[],
    this.timesMode = ConditionDimensionMode.inherit,
    Iterable<TimeWindowDraftViewModel> timeWindows =
        const <TimeWindowDraftViewModel>[],
    this.locationsMode = ConditionDimensionMode.inherit,
    Iterable<String> selectedLocationIds = const <String>[],
  }) : selectedWeekdays = List<int>.unmodifiable(selectedWeekdays),
       timeWindows = List<TimeWindowDraftViewModel>.unmodifiable(timeWindows),
       selectedLocationIds = List<String>.unmodifiable(selectedLocationIds);

  /// Day dimension mode (`inherit`, `any`, or `custom`).
  final ConditionDimensionMode daysMode;

  /// Whether `condition any` ignores all inherited label conditions.
  final bool ignoreAllLabelConditions;

  /// Location dimension mode (`inherit`, `any`, or `custom`).
  final ConditionDimensionMode locationsMode;

  /// Selected referenced location identifiers.
  final List<String> selectedLocationIds;

  /// Selected ISO weekdays (`1..7`, Monday to Sunday).
  final List<int> selectedWeekdays;

  /// Time dimension mode (`inherit`, `any`, or `custom`).
  final ConditionDimensionMode timesMode;

  /// Configured `HH:MM`..`HH:MM` daily time windows.
  final List<TimeWindowDraftViewModel> timeWindows;

  /// Returns a copy of this [ConditionDraftViewModel] with updated fields.
  ConditionDraftViewModel copyWith({
    bool? ignoreAllLabelConditions,
    ConditionDimensionMode? daysMode,
    Iterable<int>? selectedWeekdays,
    ConditionDimensionMode? timesMode,
    Iterable<TimeWindowDraftViewModel>? timeWindows,
    ConditionDimensionMode? locationsMode,
    Iterable<String>? selectedLocationIds,
  }) {
    return ConditionDraftViewModel(
      ignoreAllLabelConditions:
          ignoreAllLabelConditions ?? this.ignoreAllLabelConditions,
      daysMode: daysMode ?? this.daysMode,
      selectedWeekdays: selectedWeekdays ?? this.selectedWeekdays,
      timesMode: timesMode ?? this.timesMode,
      timeWindows: timeWindows ?? this.timeWindows,
      locationsMode: locationsMode ?? this.locationsMode,
      selectedLocationIds: selectedLocationIds ?? this.selectedLocationIds,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConditionDraftViewModel &&
        other.ignoreAllLabelConditions == ignoreAllLabelConditions &&
        other.daysMode == daysMode &&
        listEquals(other.selectedWeekdays, selectedWeekdays) &&
        other.timesMode == timesMode &&
        listEquals(other.timeWindows, timeWindows) &&
        other.locationsMode == locationsMode &&
        listEquals(other.selectedLocationIds, selectedLocationIds);
  }

  @override
  int get hashCode => Object.hash(
    ignoreAllLabelConditions,
    daysMode,
    Object.hashAll(selectedWeekdays),
    timesMode,
    Object.hashAll(timeWindows),
    locationsMode,
    Object.hashAll(selectedLocationIds),
  );
}

/// Immutable read-only condition summary token with optional clickable location navigation target.
@immutable
class ConditionSummaryChipViewModel {
  /// Creates a [ConditionSummaryChipViewModel].
  const ConditionSummaryChipViewModel({
    required this.label,
    this.locationId,
    this.isInherited = false,
  });

  /// Whether this rule is inherited from an assigned label.
  final bool isInherited;

  /// Localized human-readable condition summary.
  final String label;

  /// Optional location identifier when tapping navigates to the Locations manager.
  final String? locationId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConditionSummaryChipViewModel &&
        other.label == label &&
        other.locationId == locationId &&
        other.isInherited == isInherited;
  }

  @override
  int get hashCode => Object.hash(label, locationId, isInherited);
}

/// Immutable assigned label chip displayed on collapsed or expanded task cards.
@immutable
class EntityLabelChipViewModel {
  /// Creates an [EntityLabelChipViewModel].
  const EntityLabelChipViewModel({
    required this.id,
    required this.name,
    required this.isScoped,
    this.colorValue,
  });

  /// Optional ARGB color integer parsed from `#RRGGBB`.
  final int? colorValue;

  /// Canonical label identifier.
  final String id;

  /// Whether this label scopes its tasks into a dedicated queue.
  final bool isScoped;

  /// Label display name.
  final String name;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EntityLabelChipViewModel &&
        other.id == id &&
        other.name == name &&
        other.colorValue == colorValue &&
        other.isScoped == isScoped;
  }

  @override
  int get hashCode => Object.hash(id, name, colorValue, isScoped);
}

/// Immutable reference link item displayed inside Task and Label cards.
@immutable
class EntityLinkViewModel {
  /// Creates an [EntityLinkViewModel].
  const EntityLinkViewModel({required this.title, required this.uri});

  /// Display title of the reference link.
  final String title;

  /// Validated URI launched through `LinkActionController`.
  final String uri;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EntityLinkViewModel &&
        other.title == title &&
        other.uri == uri;
  }

  @override
  int get hashCode => Object.hash(title, uri);
}

/// Immutable per-target file readability diagnostic line.
@immutable
class FileReadDiagnosticLineViewModel {
  /// Creates a [FileReadDiagnosticLineViewModel].
  const FileReadDiagnosticLineViewModel({
    required this.targetLabel,
    required this.statusText,
    required this.isReadable,
  });

  /// Whether this target was read cleanly.
  final bool isReadable;

  /// Localized readability status or detailed format error text.
  final String statusText;

  /// Localized target label (`Local file` or `Remote file`).
  final String targetLabel;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileReadDiagnosticLineViewModel &&
        other.targetLabel == targetLabel &&
        other.statusText == statusText &&
        other.isReadable == isReadable;
  }

  @override
  int get hashCode => Object.hash(targetLabel, statusText, isReadable);
}

/// Immutable full-screen or banner file-read diagnostic report.
@immutable
class FileReadReportViewModel {
  /// Creates a [FileReadReportViewModel].
  FileReadReportViewModel({
    required this.title,
    required this.summary,
    required Iterable<FileReadDiagnosticLineViewModel> lines,
  }) : lines = List<FileReadDiagnosticLineViewModel>.unmodifiable(lines);

  /// Per-target diagnostic rows.
  final List<FileReadDiagnosticLineViewModel> lines;

  /// Localized summary explaining which target(s) failed.
  final String summary;

  /// Localized heading (`File Read Error`).
  final String title;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileReadReportViewModel &&
        other.title == title &&
        other.summary == summary &&
        listEquals(other.lines, lines);
  }

  @override
  int get hashCode => Object.hash(title, summary, Object.hashAll(lines));
}

/// Immutable option row supplied to the Searchable Label Picker (`U-COMP-005`).
@immutable
class LabelPickerOptionViewModel {
  /// Creates a [LabelPickerOptionViewModel].
  const LabelPickerOptionViewModel({
    required this.id,
    required this.name,
    required this.isScoped,
    required this.openCount,
    this.colorValue,
  });

  /// Optional parsed ARGB color integer.
  final int? colorValue;

  /// Canonical label identifier.
  final String id;

  /// Whether this label is a Scoped Queue.
  final bool isScoped;

  /// Label display name.
  final String name;

  /// Open task count referencing this label.
  final int openCount;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LabelPickerOptionViewModel &&
        other.id == id &&
        other.name == name &&
        other.colorValue == colorValue &&
        other.isScoped == isScoped &&
        other.openCount == openCount;
  }

  @override
  int get hashCode => Object.hash(id, name, colorValue, isScoped, openCount);
}

/// Immutable lightweight location reference option for condition pickers.
@immutable
class LocationOptionViewModel {
  /// Creates a [LocationOptionViewModel].
  const LocationOptionViewModel({
    required this.id,
    required this.name,
    required this.coordinatesSummary,
  });

  /// Formatted coordinate and radius preview string.
  final String coordinatesSummary;

  /// Canonical location identifier.
  final String id;

  /// Location display name.
  final String name;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationOptionViewModel &&
        other.id == id &&
        other.name == name &&
        other.coordinatesSummary == coordinatesSummary;
  }

  @override
  int get hashCode => Object.hash(id, name, coordinatesSummary);
}

/// Immutable operational status banner displayed at the top of Tasks view (`U-UX-007`).
@immutable
class ShellBannerViewModel {
  /// Creates a [ShellBannerViewModel].
  ShellBannerViewModel({
    required this.kind,
    required this.tone,
    required this.message,
    required this.dismissible,
    this.primaryActionLabel,
    this.secondaryActionLabel,
    Iterable<FileReadDiagnosticLineViewModel> diagnosticLines =
        const <FileReadDiagnosticLineViewModel>[],
  }) : diagnosticLines = List<FileReadDiagnosticLineViewModel>.unmodifiable(
         diagnosticLines,
       );

  /// Optional structured per-target diagnostic lines for partial file-read errors.
  final List<FileReadDiagnosticLineViewModel> diagnosticLines;

  /// Whether the user may dismiss this banner.
  final bool dismissible;

  /// Operational banner category.
  final ShellBannerKind kind;

  /// Localized banner body text.
  final String message;

  /// Optional primary banner button label.
  final String? primaryActionLabel;

  /// Optional secondary banner button label.
  final String? secondaryActionLabel;

  /// Visual severity tone.
  final BannerTone tone;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ShellBannerViewModel &&
        other.kind == kind &&
        other.tone == tone &&
        other.message == message &&
        other.dismissible == dismissible &&
        other.primaryActionLabel == primaryActionLabel &&
        other.secondaryActionLabel == secondaryActionLabel &&
        listEquals(other.diagnosticLines, diagnosticLines);
  }

  @override
  int get hashCode => Object.hash(
    kind,
    tone,
    message,
    dismissible,
    primaryActionLabel,
    secondaryActionLabel,
    Object.hashAll(diagnosticLines),
  );
}

/// Immutable daily time-window draft pair (`HH:MM`..`HH:MM`).
@immutable
class TimeWindowDraftViewModel {
  /// Creates a [TimeWindowDraftViewModel].
  const TimeWindowDraftViewModel({required this.start, required this.end});

  /// Inclusive end time token (`HH:MM`).
  final String end;

  /// Inclusive start time token (`HH:MM`).
  final String start;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TimeWindowDraftViewModel &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);
}

/// Stateless formatting and projection helpers shared across domain view-model builders.
class ViewModelFormatters {
  /// Prevents instantiation of [ViewModelFormatters].
  const ViewModelFormatters._();

  /// Builds the [ConditionDraftViewModel] representing [rules] on a task or label.
  static ConditionDraftViewModel buildConditionDraft(
    List<TaskCondition> rules, {
    required bool isTask,
  }) {
    final ignoreAll =
        isTask &&
        rules.any((condition) => condition is GlobalResetTaskCondition);
    final weekdays = <int>[];
    final timeWindows = <TimeWindowDraftViewModel>[];
    final locationIds = <String>[];
    var dayAny = false;
    var timeAny = false;
    var locationAny = false;

    for (final rule in rules) {
      switch (rule) {
        case GlobalResetTaskCondition():
          break;
        case GroupResetTaskCondition(:final targetGroup):
          if (targetGroup == ConditionGroup.day) dayAny = true;
          if (targetGroup == ConditionGroup.time) timeAny = true;
          if (targetGroup == ConditionGroup.location) locationAny = true;
        case DayTaskCondition():
          for (final day in rule.weekdays) {
            if (!weekdays.contains(day)) {
              weekdays.add(day);
            }
          }
        case TimeWindowTaskCondition(:final startToken, :final endToken):
          timeWindows.add(
            TimeWindowDraftViewModel(start: startToken, end: endToken),
          );
        case LocationTaskCondition():
          for (final id in rule.locationIds) {
            if (!locationIds.contains(id)) {
              locationIds.add(id);
            }
          }
      }
    }
    weekdays.sort();

    ConditionDimensionMode resolveMode(bool hasRules, bool hasAny) {
      if (hasRules) return ConditionDimensionMode.custom;
      if (isTask && hasAny) return ConditionDimensionMode.any;
      return isTask
          ? ConditionDimensionMode.inherit
          : ConditionDimensionMode.custom;
    }

    return ConditionDraftViewModel(
      ignoreAllLabelConditions: ignoreAll,
      daysMode: resolveMode(weekdays.isNotEmpty, dayAny),
      selectedWeekdays: weekdays,
      timesMode: resolveMode(timeWindows.isNotEmpty, timeAny),
      timeWindows: timeWindows,
      locationsMode: resolveMode(locationIds.isNotEmpty, locationAny),
      selectedLocationIds: locationIds,
    );
  }

  /// Builds read-only condition summary chips for [rules] plus optional inherited label rules.
  static List<ConditionSummaryChipViewModel> buildConditionSummaryChips({
    required List<TaskCondition> ownRules,
    required List<TaskCondition> inheritedRules,
    required Map<String, TdfLocation> locationsById,
    required AppLocalizations localizations,
  }) {
    final chips = <ConditionSummaryChipViewModel>[];
    final hasGlobalReset = ownRules.any(
      (condition) => condition is GlobalResetTaskCondition,
    );
    if (hasGlobalReset) {
      chips.add(
        ConditionSummaryChipViewModel(
          label: localizations.conditionGlobalAnyLabel,
        ),
      );
    }
    _appendRuleSummaryChips(
      rules: ownRules,
      isInherited: false,
      locationsById: locationsById,
      localizations: localizations,
      target: chips,
    );
    if (!hasGlobalReset && inheritedRules.isNotEmpty) {
      _appendRuleSummaryChips(
        rules: inheritedRules,
        isInherited: true,
        locationsById: locationsById,
        localizations: localizations,
        target: chips,
      );
    }
    return chips;
  }

  /// Formats 4-decimal coordinate and radius summary (`47.1204, 8.5173 · 250m`).
  static String formatCoordinatesSummary(TdfLocation location) {
    final lat = location.latitude.toStringAsFixed(4);
    final lon = location.longitude.toStringAsFixed(4);
    return '$lat, $lon · ${formatRadiusMeters(location.radius)}';
  }

  /// Formats per-target lines from a [StorageFileReadReport].
  static List<FileReadDiagnosticLineViewModel> formatFileReadDiagnosticLines(
    StorageFileReadReport report,
    AppLocalizations localizations,
  ) {
    return <FileReadDiagnosticLineViewModel>[
      for (final entry in report.activeEntries)
        FileReadDiagnosticLineViewModel(
          targetLabel: localizations.storageFileTargetLabel(entry.target),
          statusText: localizations.storageFileReadEntryText(entry),
          isReadable: entry.isReadable,
        ),
    ];
  }

  /// Formats [radiusMeters] compactly as meters or kilometers.
  static String formatRadiusMeters(double radiusMeters) {
    if (radiusMeters >= 1000.0 && radiusMeters % 1000.0 == 0.0) {
      return '${(radiusMeters / 1000.0).toInt()}km';
    }
    if (radiusMeters >= 1000.0) {
      return '${TdfLocation.formatRoundedDouble(radiusMeters / 1000.0, 2)}km';
    }
    return '${TdfLocation.formatRoundedDouble(radiusMeters, 2)}m';
  }

  /// Parses an optional `#RRGGBB` string into a 32-bit ARGB integer.
  static int? parseLabelColorValue(String? hex) => TdfColor.tryParseArgb(hex);

  /// Returns the localized tier name for [tier].
  static String tierName(ShellTier tier, AppLocalizations localizations) =>
      localizations.tierName(toTaskTier(tier));

  /// Returns the soft WIP limit for [tier] (`3` for Focus, `5` for Ready, else `null`).
  static int? tierWipLimit(ShellTier tier) {
    return switch (tier) {
      ShellTier.focus => 3,
      ShellTier.ready => 5,
      ShellTier.planned ||
      ShellTier.blocked ||
      ShellTier.someday ||
      ShellTier.completed => null,
    };
  }

  /// Maps presentation [ShellTier] to domain [TaskTier].
  static TaskTier toTaskTier(ShellTier tier) {
    return switch (tier) {
      ShellTier.focus => TaskTier.focus,
      ShellTier.ready => TaskTier.ready,
      ShellTier.planned => TaskTier.planned,
      ShellTier.blocked => TaskTier.blocked,
      ShellTier.someday => TaskTier.someday,
      ShellTier.completed => TaskTier.completed,
    };
  }
}

/// Appends localized summary chips for each rule in [rules].
void _appendRuleSummaryChips({
  required List<TaskCondition> rules,
  required bool isInherited,
  required Map<String, TdfLocation> locationsById,
  required AppLocalizations localizations,
  required List<ConditionSummaryChipViewModel> target,
}) {
  final dayNames = <String>[
    localizations.weekdayMon,
    localizations.weekdayTue,
    localizations.weekdayWed,
    localizations.weekdayThu,
    localizations.weekdayFri,
    localizations.weekdaySat,
    localizations.weekdaySun,
  ];
  for (final rule in rules) {
    switch (rule) {
      case GlobalResetTaskCondition():
        break;
      case GroupResetTaskCondition(:final targetGroup):
        final label = switch (targetGroup) {
          ConditionGroup.day => localizations.conditionDayAnyLabel,
          ConditionGroup.time => localizations.conditionTimeAnyLabel,
          ConditionGroup.location => localizations.conditionLocationAnyLabel,
        };
        target.add(
          ConditionSummaryChipViewModel(label: label, isInherited: isInherited),
        );
      case DayTaskCondition(:final weekdays):
        final formatted = weekdays
            .where((day) => day >= 1 && day <= 7)
            .map((day) => dayNames[day - 1])
            .join(', ');
        if (formatted.isNotEmpty) {
          target.add(
            ConditionSummaryChipViewModel(
              label: formatted,
              isInherited: isInherited,
            ),
          );
        }
      case TimeWindowTaskCondition(:final startToken, :final endToken):
        target.add(
          ConditionSummaryChipViewModel(
            label: '$startToken - $endToken',
            isInherited: isInherited,
          ),
        );
      case LocationTaskCondition(:final locationIds):
        for (final locationId in locationIds) {
          final location = locationsById[locationId];
          target.add(
            ConditionSummaryChipViewModel(
              label: location?.name ?? locationId,
              locationId: location != null ? locationId : null,
              isInherited: isInherited,
            ),
          );
        }
    }
  }
}
