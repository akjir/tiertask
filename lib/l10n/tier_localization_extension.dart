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

import '../models/task_tier.dart';
import 'app_localizations.dart';

/// Maps [TaskTier] values (`1` through `6`) to localized display names,
/// uppercase section headings, and empty-state hints from [AppLocalizations].
extension TierLocalizationExtension on AppLocalizations {
  /// Returns the localized empty-state hint for [tier] on single-tier tabs.
  String tierEmptyHint(TaskTier tier) {
    return switch (tier) {
      TaskTier.focus => emptyFocusHint,
      TaskTier.ready => emptyReadyHint,
      TaskTier.planned => emptyPlannedHint,
      TaskTier.blocked => emptyBlockedHint,
      TaskTier.someday => emptySomedayHint,
      TaskTier.completed => emptyCompletedHint,
    };
  }

  /// Returns the localized display name for [tier] without the `# [n]` prefix.
  String tierName(TaskTier tier) {
    return switch (tier) {
      TaskTier.focus => tier1Name,
      TaskTier.ready => tier2Name,
      TaskTier.planned => tier3Name,
      TaskTier.blocked => tier4Name,
      TaskTier.someday => tier5Name,
      TaskTier.completed => tier6Name,
    };
  }

  /// Returns the localized uppercase section heading for [tier].
  String tierSectionTitle(TaskTier tier) {
    return switch (tier) {
      TaskTier.focus => sectionFocusTasks,
      TaskTier.ready => sectionReadyTasks,
      TaskTier.planned => sectionPlannedTasks,
      TaskTier.blocked => sectionBlockedTasks,
      TaskTier.someday => sectionSomedayTasks,
      TaskTier.completed => sectionCompletedTasks,
    };
  }
}
