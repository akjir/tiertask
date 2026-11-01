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

/// Represents the six strictly ordered priority and status tiers (`1` to `6`) in TierTask.
enum TaskTier {
  /// Tier 1: Active top-priority focus tasks (soft limit: 3).
  focus,

  /// Tier 2: Tasks ready to pull into Focus (soft limit: 5).
  ready,

  /// Tier 3: Active backlog feeding Ready automatically.
  planned,

  /// Tier 4: Static tier for tasks blocked by prerequisites, deferral, or conditions.
  blocked,

  /// Tier 5: Static tier for unscheduled ideas without a `queued` timestamp.
  someday,

  /// Tier 6: Static archive of completed tasks retained for 30 days.
  completed,
}
