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

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/l10n/tier_localization_extension.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/floating_notice_providers.dart';
import 'package:tiertask/providers/settings_draft_providers.dart';
import 'package:tiertask/providers/shell_providers.dart';
import 'package:tiertask/providers/task_schedule_helper.dart';
import 'package:tiertask/ui/primitives/ui_banner.dart';
import 'package:tiertask/ui/primitives/ui_button.dart';
import 'package:tiertask/ui/primitives/ui_pill.dart';
import 'package:tiertask/ui/tokens/ui_theme_tokens.dart';
import 'package:tiertask/ui/ui_domain_mappers.dart';

void main() {
  final englishLocalizations = lookupAppLocalizations(const Locale('en'));
  final germanLocalizations = lookupAppLocalizations(const Locale('de'));
  final fixedNowUtc = DateTime.utc(2026, 11, 10, 12); // Tuesday
  final fixedLocalNow = DateTime(2026, 11, 10, 12); // Tuesday
  const utcConfig = WebDavConfig(
    language: AppLanguage.english,
    timeZoneMode: AppTimeZoneMode.manual,
  );

  group('TaskCardBadge', () {
    test('supports value equality and hashCode', () {
      const first = TaskCardBadge(
        label: 'Priority',
        tone: UiPillTone.accent,
        icon: Icons.bolt_outlined,
      );
      const identicalCopy = TaskCardBadge(
        label: 'Priority',
        tone: UiPillTone.accent,
        icon: Icons.bolt_outlined,
      );
      const differentLabel = TaskCardBadge(
        label: 'Auto-priority',
        tone: UiPillTone.accent,
        icon: Icons.bolt_outlined,
      );
      const differentTone = TaskCardBadge(
        label: 'Priority',
        tone: UiPillTone.warning,
        icon: Icons.bolt_outlined,
      );
      const differentIcon = TaskCardBadge(
        label: 'Priority',
        tone: UiPillTone.accent,
        icon: Icons.tune_rounded,
      );

      expect(first, equals(identicalCopy));
      expect(first.hashCode, equals(identicalCopy.hashCode));
      expect(first, isNot(equals(differentLabel)));
      expect(first, isNot(equals(differentTone)));
      expect(first, isNot(equals(differentIcon)));
    });
  });

  group('UiDomainMappers enum & scalar mappers', () {
    test('maps every AppThemeMode and AppThemePalette exhaustively', () {
      for (final mode in AppThemeMode.values) {
        expect(
          UiDomainMappers.flutterThemeMode(mode),
          isA<ThemeMode>(),
          reason: 'Every AppThemeMode must map to a Flutter ThemeMode',
        );
      }
      expect(
        UiDomainMappers.flutterThemeMode(AppThemeMode.system),
        equals(ThemeMode.system),
      );
      expect(
        UiDomainMappers.flutterThemeMode(AppThemeMode.light),
        equals(ThemeMode.light),
      );
      expect(
        UiDomainMappers.flutterThemeMode(AppThemeMode.dark),
        equals(ThemeMode.dark),
      );

      for (final palette in AppThemePalette.values) {
        final preset = UiDomainMappers.themePreset(palette);
        expect(
          preset.id,
          equals(palette.jsonValue),
          reason: 'UiThemePreset.id must match AppThemePalette.jsonValue',
        );
      }
      expect(
        UiDomainMappers.themePreset(AppThemePalette.calm),
        equals(UiThemePresets.calm),
      );
      expect(
        UiDomainMappers.themePreset(AppThemePalette.plumUmber),
        equals(UiThemePresets.plumUmber),
      );
    });

    test('maps every TaskTier exhaustively for icon, subtitle, and empty hint in en and de', () {
      final expectedIcons = <TaskTier, IconData>{
        TaskTier.focus: Icons.bolt_outlined,
        TaskTier.ready: Icons.format_list_numbered_rounded,
        TaskTier.planned: Icons.calendar_today_outlined,
        TaskTier.blocked: Icons.block_outlined,
        TaskTier.someday: Icons.lightbulb_outline_rounded,
        TaskTier.completed: Icons.check_circle_outline_rounded,
      };
      for (final tier in TaskTier.values) {
        expect(
          UiDomainMappers.tierIcon(tier),
          equals(expectedIcons[tier]),
          reason: 'TaskTier.$tier must resolve its canonical outline icon',
        );
        expect(
          UiDomainMappers.tierEmptyHint(tier, englishLocalizations),
          equals(englishLocalizations.tierEmptyHint(tier)),
          reason: 'TaskTier.$tier English empty hint must match l10n',
        );
        expect(
          UiDomainMappers.tierEmptyHint(tier, germanLocalizations),
          equals(germanLocalizations.tierEmptyHint(tier)),
          reason: 'TaskTier.$tier German empty hint must match l10n',
        );
        expect(
          UiDomainMappers.tierSubtitle(tier, englishLocalizations),
          isNotEmpty,
          reason: 'TaskTier.$tier English subtitle must be non-empty',
        );
        expect(
          UiDomainMappers.tierSubtitle(tier, germanLocalizations),
          isNotEmpty,
          reason: 'TaskTier.$tier German subtitle must be non-empty',
        );
      }

      expect(
        UiDomainMappers.tierSubtitle(TaskTier.focus, englishLocalizations),
        equals(englishLocalizations.tierFocusSubtitle),
      );
      expect(
        UiDomainMappers.tierSubtitle(TaskTier.ready, englishLocalizations),
        equals(englishLocalizations.tierReadySubtitle),
      );
      expect(
        UiDomainMappers.tierSubtitle(TaskTier.planned, englishLocalizations),
        equals(englishLocalizations.tierPlannedSubtitle),
      );
      expect(
        UiDomainMappers.tierSubtitle(TaskTier.blocked, englishLocalizations),
        equals(englishLocalizations.tierBlockedSubtitle),
      );
      expect(
        UiDomainMappers.tierSubtitle(TaskTier.someday, englishLocalizations),
        equals(englishLocalizations.tierSomedaySubtitle),
      );
      expect(
        UiDomainMappers.tierSubtitle(TaskTier.completed, englishLocalizations),
        equals(englishLocalizations.tierCompletedSubtitle),
      );
    });

    test('maps every LocationStatus, LocationSource, coordinates, and place label exhaustively', () {
      for (final status in LocationStatus.values) {
        expect(
          UiDomainMappers.locationIcon(status),
          isA<IconData>(),
          reason: 'Every LocationStatus must map to an IconData',
        );
        expect(
          UiDomainMappers.locationButtonTone(status),
          isA<UiButtonTone>(),
          reason: 'Every LocationStatus must map to a UiButtonTone',
        );
        expect(
          UiDomainMappers.locationStatusLabel(status, englishLocalizations),
          isNotEmpty,
          reason: 'Every LocationStatus must map to a localized label',
        );
      }

      expect(
        UiDomainMappers.locationButtonTone(LocationStatus.found),
        equals(UiButtonTone.accent),
        reason: 'Active GPS fix must tint chrome location button in accent',
      );
      expect(
        UiDomainMappers.locationButtonTone(LocationStatus.searching),
        equals(UiButtonTone.neutral),
      );
      expect(
        UiDomainMappers.locationButtonTone(LocationStatus.unavailable),
        equals(UiButtonTone.neutral),
      );
      expect(
        UiDomainMappers.locationButtonTone(LocationStatus.disabled),
        equals(UiButtonTone.neutral),
      );

      expect(
        UiDomainMappers.locationIcon(LocationStatus.found),
        equals(Icons.my_location_rounded),
      );
      expect(
        UiDomainMappers.locationIcon(LocationStatus.searching),
        equals(Icons.refresh_rounded),
      );
      expect(
        UiDomainMappers.locationIcon(LocationStatus.unavailable),
        equals(Icons.location_disabled_rounded),
      );
      expect(
        UiDomainMappers.locationIcon(LocationStatus.disabled),
        equals(Icons.location_disabled_rounded),
      );

      expect(
        UiDomainMappers.locationStatusLabel(
          LocationStatus.found,
          englishLocalizations,
        ),
        equals(englishLocalizations.locationStatusFound),
      );
      expect(
        UiDomainMappers.locationStatusLabel(
          LocationStatus.searching,
          englishLocalizations,
        ),
        equals(englishLocalizations.locationStatusSearching),
      );
      expect(
        UiDomainMappers.locationStatusLabel(
          LocationStatus.unavailable,
          englishLocalizations,
        ),
        equals(englishLocalizations.locationStatusUnavailable),
      );
      expect(
        UiDomainMappers.locationStatusLabel(
          LocationStatus.disabled,
          englishLocalizations,
        ),
        equals(englishLocalizations.locationStatusUnavailable),
      );

      for (final source in LocationSource.values) {
        expect(
          UiDomainMappers.locationSourceLabel(source, englishLocalizations),
          isNotEmpty,
          reason: 'Every LocationSource must map to a localized label',
        );
      }
      expect(
        UiDomainMappers.locationSourceLabel(
          LocationSource.gps,
          englishLocalizations,
        ),
        equals(englishLocalizations.locationSourceGps),
      );
      expect(
        UiDomainMappers.locationSourceLabel(
          LocationSource.system,
          englishLocalizations,
        ),
        equals(englishLocalizations.locationSourceSystem),
      );
      expect(
        UiDomainMappers.locationSourceLabel(
          LocationSource.internet,
          englishLocalizations,
        ),
        equals(englishLocalizations.locationSourceInternet),
      );
      expect(
        UiDomainMappers.locationSourceLabel(null, englishLocalizations),
        isEmpty,
      );

      expect(UiDomainMappers.formatLocationCoordinates6dp(null), isEmpty);
      expect(
        UiDomainMappers.formatLocationCoordinates6dp(
          const LocationFix(placeName: 'No Coords'),
        ),
        isEmpty,
      );
      expect(
        UiDomainMappers.formatLocationCoordinates6dp(
          const LocationFix(latitude: 50.9787, longitude: 11.03283),
        ),
        equals('50.978700, 11.032830'),
      );
      expect(
        UiDomainMappers.formatLocationCoordinates6dp(
          const LocationFix(latitude: -0.0, longitude: -0.0),
        ),
        equals('0.000000, 0.000000'),
        reason: 'Negative zero coordinates must normalize to positive zero',
      );

      expect(
        UiDomainMappers.resolveLocationPlaceLabel(
          const LocationState.found(
            fix: LocationFix(
              latitude: 50.9787,
              longitude: 11.03283,
              placeName: '  Erfurt  ',
            ),
          ),
          englishLocalizations,
        ),
        equals('Erfurt'),
      );
      expect(
        UiDomainMappers.resolveLocationPlaceLabel(
          const LocationState.found(
            fix: LocationFix(
              latitude: 50.9787,
              longitude: 11.03283,
              placeName: '   ',
            ),
          ),
          englishLocalizations,
        ),
        equals(englishLocalizations.locationPlaceUnknown),
      );
      expect(
        UiDomainMappers.resolveLocationPlaceLabel(
          const LocationState(status: LocationStatus.found),
          englishLocalizations,
        ),
        equals(englishLocalizations.locationPlaceUnknown),
      );
      expect(
        UiDomainMappers.resolveLocationPlaceLabel(
          const LocationState.unavailable(),
          englishLocalizations,
        ),
        isEmpty,
      );
      expect(
        UiDomainMappers.resolveLocationPlaceLabel(
          const LocationState.disabled(),
          englishLocalizations,
        ),
        isEmpty,
      );
    });

    test('maps every SyncStatusKind, FloatingNoticeTone, and SettingsBannerTone exhaustively', () {
      for (final status in SyncStatusKind.values) {
        expect(
          UiDomainMappers.syncIcon(status),
          isA<IconData>(),
          reason: 'Every SyncStatusKind must map to an IconData',
        );
        expect(
          UiDomainMappers.syncButtonTone(status),
          isA<UiButtonTone>(),
          reason: 'Every SyncStatusKind must map to a UiButtonTone',
        );
        expect(
          UiDomainMappers.syncStatusLabel(status, englishLocalizations),
          isNotEmpty,
          reason: 'Every SyncStatusKind must map to a localized label',
        );
      }

      expect(
        UiDomainMappers.syncIcon(SyncStatusKind.localOnly),
        equals(Icons.folder_outlined),
      );
      expect(
        UiDomainMappers.syncIcon(SyncStatusKind.synced),
        equals(Icons.cloud_done_outlined),
      );
      expect(
        UiDomainMappers.syncIcon(SyncStatusKind.syncing),
        equals(Icons.refresh_rounded),
      );
      expect(
        UiDomainMappers.syncIcon(SyncStatusKind.conflict),
        equals(Icons.warning_amber_rounded),
      );
      expect(
        UiDomainMappers.syncIcon(SyncStatusKind.error),
        equals(Icons.cloud_off_outlined),
      );

      expect(
        UiDomainMappers.syncButtonTone(SyncStatusKind.localOnly),
        equals(UiButtonTone.muted),
      );
      expect(
        UiDomainMappers.syncButtonTone(SyncStatusKind.synced),
        equals(UiButtonTone.muted),
      );
      expect(
        UiDomainMappers.syncButtonTone(SyncStatusKind.syncing),
        equals(UiButtonTone.muted),
      );
      expect(
        UiDomainMappers.syncButtonTone(SyncStatusKind.conflict),
        equals(UiButtonTone.warning),
      );
      expect(
        UiDomainMappers.syncButtonTone(SyncStatusKind.error),
        equals(UiButtonTone.danger),
      );

      expect(
        UiDomainMappers.syncStatusLabel(
          SyncStatusKind.localOnly,
          englishLocalizations,
        ),
        equals(englishLocalizations.syncStatusLocalOnly),
      );
      expect(
        UiDomainMappers.syncStatusLabel(
          SyncStatusKind.synced,
          englishLocalizations,
        ),
        equals(englishLocalizations.syncStatusSynced),
      );
      expect(
        UiDomainMappers.syncStatusLabel(
          SyncStatusKind.syncing,
          englishLocalizations,
        ),
        equals(englishLocalizations.syncStatusSyncing),
      );
      expect(
        UiDomainMappers.syncStatusLabel(
          SyncStatusKind.conflict,
          englishLocalizations,
        ),
        equals(englishLocalizations.syncStatusConflict),
      );
      expect(
        UiDomainMappers.syncStatusLabel(
          SyncStatusKind.error,
          englishLocalizations,
        ),
        equals(englishLocalizations.syncStatusError),
      );

      for (final tone in FloatingNoticeTone.values) {
        expect(
          UiDomainMappers.noticeTone(tone),
          isA<UiBannerTone>(),
          reason: 'Every FloatingNoticeTone must map to a UiBannerTone',
        );
      }
      expect(
        UiDomainMappers.noticeTone(FloatingNoticeTone.neutral),
        equals(UiBannerTone.neutral),
      );
      expect(
        UiDomainMappers.noticeTone(FloatingNoticeTone.accent),
        equals(UiBannerTone.neutral),
      );
      expect(
        UiDomainMappers.noticeTone(FloatingNoticeTone.warning),
        equals(UiBannerTone.warning),
      );
      expect(
        UiDomainMappers.noticeTone(FloatingNoticeTone.danger),
        equals(UiBannerTone.danger),
      );
      expect(
        UiDomainMappers.noticeTone(FloatingNoticeTone.success),
        equals(UiBannerTone.success),
      );

      for (final tone in SettingsBannerTone.values) {
        expect(
          UiDomainMappers.settingsBannerTone(tone),
          isA<UiBannerTone>(),
          reason: 'Every SettingsBannerTone must map to a UiBannerTone',
        );
      }
      expect(
        UiDomainMappers.settingsBannerTone(SettingsBannerTone.warning),
        equals(UiBannerTone.warning),
      );
      expect(
        UiDomainMappers.settingsBannerTone(SettingsBannerTone.danger),
        equals(UiBannerTone.danger),
      );
      expect(
        UiDomainMappers.settingsBannerTone(SettingsBannerTone.success),
        equals(UiBannerTone.success),
      );
    });
  });

  group('UiDomainMappers.buildTaskCollapsedBadges', () {
    ({
      List<TaskCardBadge> primary,
      List<TaskCardBadge> visibleSecondary,
      int overflowCount,
    })
    buildBadges(
      TaskItem task, {
      TaskTier tier = TaskTier.ready,
      bool isSearchMode = false,
      String? activeLabelId,
      Map<String, TdfLabel> labelsById = const <String, TdfLabel>{},
      Map<String, TdfLocation> locationsById = const <String, TdfLocation>{},
      Map<String, TaskItem> tasksById = const <String, TaskItem>{},
      WebDavConfig config = utcConfig,
      LocationFix? activeFix,
      AppLocalizations? localizations,
    }) {
      return UiDomainMappers.buildTaskCollapsedBadges(
        task: task,
        tier: tier,
        isSearchMode: isSearchMode,
        activeLabelId: activeLabelId,
        labelsById: labelsById,
        locationsById: locationsById,
        tasksById: tasksById,
        config: config,
        nowUtc: fixedNowUtc,
        localNow: fixedLocalNow,
        activeFix: activeFix,
        localizations: localizations ?? englishLocalizations,
      );
    }

    test('prepends soft tier badge only when isSearchMode is true', () {
      final task = TaskItem(
        id: 'task000001',
        title: 'Plain task',
        createdAt: fixedNowUtc,
      );

      final normalResult = buildBadges(task, tier: TaskTier.focus);
      expect(normalResult.primary, isEmpty);
      expect(normalResult.visibleSecondary, isEmpty);
      expect(normalResult.overflowCount, equals(0));

      for (final tier in TaskTier.values) {
        final searchResult = buildBadges(task, tier: tier, isSearchMode: true);
        expect(
          searchResult.primary,
          equals(<TaskCardBadge>[
            TaskCardBadge(
              label: englishLocalizations.tierName(tier),
              tone: UiPillTone.soft,
              icon: UiDomainMappers.tierIcon(tier),
            ),
          ]),
          reason: 'Search mode must prepend tier badge for TaskTier.$tier',
        );
      }
    });

    test('formats due, overdue, lead window, passive due, someday, completed, and priority vs auto-priority badges', () {
      final overdueAt = fixedNowUtc.subtract(const Duration(hours: 2));
      final exactDueAt = fixedNowUtc;
      final withinLeadAt = fixedNowUtc.add(const Duration(hours: 6));
      final futureAt = fixedNowUtc.add(const Duration(days: 5));

      // Active overdue task with explicit priority.
      final overdueResult = buildBadges(
        TaskItem(
          id: 'task000002',
          title: 'Overdue priority',
          isPriority: true,
          dueAt: overdueAt,
          createdAt: fixedNowUtc,
        ),
      );
      expect(
        overdueResult.primary,
        equals(<TaskCardBadge>[
          TaskCardBadge(
            label: englishLocalizations.badgeOverduePrefix(
              TaskScheduleHelper.formatLocalTimestamp(overdueAt, utcConfig),
            ),
            tone: UiPillTone.danger,
            icon: Icons.calendar_today_outlined,
          ),
        ]),
      );
      expect(
        overdueResult.visibleSecondary,
        equals(<TaskCardBadge>[
          TaskCardBadge(
            label: englishLocalizations.quickAddPriority,
            tone: UiPillTone.accent,
            icon: Icons.bolt_outlined,
          ),
        ]),
        reason: 'Explicit priority must take precedence over auto-priority',
      );

      // Exact boundary dueAt == nowUtc counts as overdue.
      final exactBoundaryResult = buildBadges(
        TaskItem(
          id: 'task000003',
          title: 'Due now',
          dueAt: exactDueAt,
          createdAt: fixedNowUtc,
        ),
      );
      expect(
        exactBoundaryResult.primary.single.tone,
        equals(UiPillTone.danger),
      );

      // Active task within lead window without explicit priority -> warning due + auto-priority.
      final leadResult = buildBadges(
        TaskItem(
          id: 'task000004',
          title: 'Upcoming deadline',
          dueAt: withinLeadAt,
          createdAt: fixedNowUtc,
        ),
      );
      expect(
        leadResult.primary,
        equals(<TaskCardBadge>[
          TaskCardBadge(
            label: englishLocalizations.pillDuePrefix(
              TaskScheduleHelper.formatLocalTimestamp(withinLeadAt, utcConfig),
            ),
            tone: UiPillTone.warning,
            icon: Icons.calendar_today_outlined,
          ),
        ]),
      );
      expect(
        leadResult.visibleSecondary,
        equals(<TaskCardBadge>[
          TaskCardBadge(
            label: englishLocalizations.badgeAutoPriority,
            tone: UiPillTone.warning,
            icon: Icons.bolt_outlined,
          ),
        ]),
      );

      // Passive due inside lead window stays neutral and does not auto-prioritize.
      final passiveLeadResult = buildBadges(
        TaskItem(
          id: 'task000005',
          title: 'Passive due',
          dueAt: withinLeadAt,
          isDuePassive: true,
          createdAt: fixedNowUtc,
        ),
      );
      expect(passiveLeadResult.primary.single.tone, equals(UiPillTone.neutral));
      expect(passiveLeadResult.visibleSecondary, isEmpty);

      // Someday task inside lead window keeps warning due badge but suppresses auto-priority.
      final somedayLeadResult = buildBadges(
        TaskItem(
          id: 'task000006',
          title: 'Someday deadline',
          dueAt: withinLeadAt,
          createdAt: fixedNowUtc,
        ),
        tier: TaskTier.someday,
      );
      expect(somedayLeadResult.primary.single.tone, equals(UiPillTone.warning));
      expect(somedayLeadResult.visibleSecondary, isEmpty);

      // Distant future due stays neutral with no priority badge.
      final futureResult = buildBadges(
        TaskItem(
          id: 'task000007',
          title: 'Later deadline',
          dueAt: futureAt,
          createdAt: fixedNowUtc,
        ),
      );
      expect(futureResult.primary.single.tone, equals(UiPillTone.neutral));
      expect(futureResult.visibleSecondary, isEmpty);

      // Completed task with past due and priority flag renders neutral due and omits priority.
      final completedResult = buildBadges(
        TaskItem(
          id: 'task000008',
          title: 'Finished task',
          isCompleted: true,
          isPriority: true,
          dueAt: overdueAt,
          completedAt: fixedNowUtc,
          createdAt: fixedNowUtc,
        ),
        tier: TaskTier.completed,
      );
      expect(
        completedResult.primary,
        equals(<TaskCardBadge>[
          TaskCardBadge(
            label: englishLocalizations.pillDuePrefix(
              TaskScheduleHelper.formatLocalTimestamp(overdueAt, utcConfig),
            ),
            tone: UiPillTone.neutral,
            icon: Icons.calendar_today_outlined,
          ),
        ]),
      );
      expect(completedResult.visibleSecondary, isEmpty);
    });

    test('renders suspended forever, suspended until, and omits expired suspension', () {
      final futureSuspendedAt = fixedNowUtc.add(const Duration(days: 2));
      final pastSuspendedAt = fixedNowUtc.subtract(const Duration(hours: 1));

      final foreverResult = buildBadges(
        TaskItem(
          id: 'task000009',
          title: 'Paused indefinitely',
          isSuspendedForever: true,
          createdAt: fixedNowUtc,
        ),
        tier: TaskTier.blocked,
      );
      expect(
        foreverResult.visibleSecondary,
        equals(<TaskCardBadge>[
          TaskCardBadge(
            label: englishLocalizations.badgeSuspendedForever,
            tone: UiPillTone.warning,
            icon: Icons.pause_circle_outline_rounded,
          ),
        ]),
      );

      final untilResult = buildBadges(
        TaskItem(
          id: 'task000010',
          title: 'Paused until date',
          suspendedAt: futureSuspendedAt,
          createdAt: fixedNowUtc,
        ),
        tier: TaskTier.blocked,
      );
      expect(
        untilResult.visibleSecondary,
        equals(<TaskCardBadge>[
          TaskCardBadge(
            label: englishLocalizations.badgeSuspendedUntil(
              TaskScheduleHelper.formatLocalTimestamp(
                futureSuspendedAt,
                utcConfig,
              ),
            ),
            tone: UiPillTone.warning,
            icon: Icons.pause_circle_outline_rounded,
          ),
        ]),
      );

      final expiredResult = buildBadges(
        TaskItem(
          id: 'task000011',
          title: 'Expired suspension',
          suspendedAt: pastSuspendedAt,
          createdAt: fixedNowUtc,
        ),
      );
      expect(expiredResult.visibleSecondary, isEmpty);
    });

    test(
      'renders blockedBy progress only when prerequisites are unsatisfied',
      () {
        final donePrerequisite = TaskItem(
          id: 'prereq0001',
          title: 'Done prerequisite',
          isCompleted: true,
          completions: 2,
          createdAt: fixedNowUtc,
        );
        final openPrerequisite = TaskItem(
          id: 'prereq0002',
          title: 'Open prerequisite',
          completions: 1,
          createdAt: fixedNowUtc,
        );
        final tasksById = <String, TaskItem>{
          donePrerequisite.id: donePrerequisite,
          openPrerequisite.id: openPrerequisite,
        };

        final partialResult = buildBadges(
          TaskItem(
            id: 'task000012',
            title: 'Partially blocked',
            dependencies: const <TdfTaskDependency>[
              TdfTaskDependency(taskId: 'prereq0001', requiredCompletion: 2),
              TdfTaskDependency(taskId: 'prereq0002', requiredCompletion: 2),
              TdfTaskDependency(taskId: 'missing001'),
            ],
            createdAt: fixedNowUtc,
          ),
          tier: TaskTier.blocked,
          tasksById: tasksById,
        );
        expect(
          partialResult.visibleSecondary,
          equals(<TaskCardBadge>[
            TaskCardBadge(
              label: englishLocalizations.badgeBlockedByProgress('1', '3'),
              tone: UiPillTone.warning,
              icon: Icons.lock_outline_rounded,
            ),
          ]),
        );

        final satisfiedResult = buildBadges(
          TaskItem(
            id: 'task000013',
            title: 'All prerequisites met',
            dependencies: const <TdfTaskDependency>[
              TdfTaskDependency(taskId: 'prereq0001', requiredCompletion: 2),
              TdfTaskDependency(taskId: 'prereq0002'),
            ],
            createdAt: fixedNowUtc,
          ),
          tasksById: tasksById,
        );
        expect(satisfiedResult.visibleSecondary, isEmpty);
      },
    );

    test('evaluates own and label-inherited conditions into neutral (satisfied) vs warning (unsatisfied)', () {
      const office = TdfLocation(
        id: 'loc0000001',
        name: 'Office',
        latitude: 50.9787,
        longitude: 11.03283,
        radius: 200.0,
      );
      final locationsById = <String, TdfLocation>{office.id: office};

      // Tuesday (fixedLocalNow.weekday == 2) matches -> neutral.
      final ownSatisfied = buildBadges(
        TaskItem(
          id: 'task000014',
          title: 'Tuesday task',
          conditions: <TaskCondition>[
            DayTaskCondition.fromWeekdays(const <int>[DateTime.tuesday]),
          ],
          createdAt: fixedNowUtc,
        ),
      );
      expect(
        ownSatisfied.visibleSecondary,
        equals(<TaskCardBadge>[
          TaskCardBadge(
            label: englishLocalizations.tooltipIndicatorConditions,
            tone: UiPillTone.neutral,
            icon: Icons.tune_rounded,
          ),
        ]),
      );

      // Monday only does not match Tuesday -> warning.
      final ownUnsatisfied = buildBadges(
        TaskItem(
          id: 'task000015',
          title: 'Monday task',
          conditions: <TaskCondition>[
            DayTaskCondition.fromWeekdays(const <int>[DateTime.monday]),
          ],
          createdAt: fixedNowUtc,
        ),
        tier: TaskTier.blocked,
      );
      expect(
        ownUnsatisfied.visibleSecondary,
        equals(<TaskCardBadge>[
          TaskCardBadge(
            label: englishLocalizations.tooltipIndicatorConditions,
            tone: UiPillTone.warning,
            icon: Icons.tune_rounded,
          ),
        ]),
      );

      // Label-inherited location condition: inside geofence -> neutral, far away -> warning.
      final officeLabel = TdfLabel(
        id: 'lbl0000001',
        name: 'Office Work',
        conditions: <TaskCondition>[
          LocationTaskCondition.fromIds(const <String>['loc0000001']),
        ],
      );
      final labelsById = <String, TdfLabel>{officeLabel.id: officeLabel};
      final inheritedTask = TaskItem(
        id: 'task000016',
        title: 'Inherited location task',
        labelIds: const <String>['lbl0000001'],
        createdAt: fixedNowUtc,
      );

      final insideGeofence = buildBadges(
        inheritedTask,
        labelsById: labelsById,
        locationsById: locationsById,
        activeFix: const LocationFix(latitude: 50.9787, longitude: 11.03283),
      );
      expect(
        insideGeofence.visibleSecondary.single.tone,
        equals(UiPillTone.neutral),
      );

      final outsideGeofence = buildBadges(
        inheritedTask,
        tier: TaskTier.blocked,
        labelsById: labelsById,
        locationsById: locationsById,
        activeFix: const LocationFix(latitude: 52.52, longitude: 13.405),
      );
      expect(
        outsideGeofence.visibleSecondary.single.tone,
        equals(UiPillTone.warning),
      );
    });

    test('renders subtasks (normal vs auto-finish), repeat, note, singular/plural links, and history badges', () {
      const repeatRule = TaskRepeatRule(count: 2, unit: RepeatUnit.weeks);

      final normalSubtasksAndRepeat = buildBadges(
        TaskItem(
          id: 'task000017',
          title: 'Steps and repeat',
          subtasks: const <SubtaskItem>[
            SubtaskItem(title: 'Step 1', isCompleted: true),
            SubtaskItem(title: 'Step 2'),
          ],
          repeatRule: repeatRule,
          note: '   ',
          createdAt: fixedNowUtc,
        ),
      );
      expect(
        normalSubtasksAndRepeat.visibleSecondary,
        equals(<TaskCardBadge>[
          TaskCardBadge(
            label: englishLocalizations.badgeStepsProgress('1', '2'),
            tone: UiPillTone.neutral,
            icon: Icons.checklist_rounded,
          ),
          TaskCardBadge(
            label: TaskScheduleHelper.formatRepeatPhrase(
              repeatRule,
              englishLocalizations,
            ),
            tone: UiPillTone.neutral,
            icon: Icons.repeat_rounded,
          ),
        ]),
        reason: 'Blank whitespace note must not emit a Note badge',
      );

      final autoFinishNoteAndSingleLink = buildBadges(
        TaskItem(
          id: 'task000018',
          title: 'Auto-finish steps',
          subtasksAutoFinish: true,
          subtasks: const <SubtaskItem>[SubtaskItem(title: 'Only step')],
          note: 'Important details',
          links: const <TaskLink>[
            TaskLink(title: 'Docs', uri: 'https://example.com'),
          ],
          createdAt: fixedNowUtc,
        ),
      );
      expect(
        autoFinishNoteAndSingleLink.visibleSecondary,
        equals(<TaskCardBadge>[
          TaskCardBadge(
            label: englishLocalizations.badgeStepsProgress('0', '1'),
            tone: UiPillTone.neutral,
            icon: Icons.check_box_outlined,
          ),
          TaskCardBadge(
            label: englishLocalizations.tooltipIndicatorNote,
            tone: UiPillTone.neutral,
            icon: Icons.description_outlined,
          ),
          TaskCardBadge(
            label: englishLocalizations.badgeLinkSingular,
            tone: UiPillTone.neutral,
            icon: Icons.link_rounded,
          ),
        ]),
      );
      expect(autoFinishNoteAndSingleLink.overflowCount, equals(0));

      final pluralLinksAndHistory = buildBadges(
        TaskItem(
          id: 'task000019',
          title: 'Links and history',
          links: const <TaskLink>[
            TaskLink(title: 'One', uri: 'https://one.example'),
            TaskLink(title: 'Two', uri: 'https://two.example'),
          ],
          history: <TaskHistoryEntry>[
            TaskHistoryEntry(
              timestampUtc: fixedNowUtc.subtract(const Duration(days: 2)),
              text: 'First event',
            ),
            TaskHistoryEntry(
              timestampUtc: fixedNowUtc.subtract(const Duration(days: 1)),
              text: 'Second event',
            ),
          ],
          createdAt: fixedNowUtc,
        ),
      );
      expect(
        pluralLinksAndHistory.visibleSecondary,
        equals(<TaskCardBadge>[
          TaskCardBadge(
            label: englishLocalizations.taskInfoLinksCount('2'),
            tone: UiPillTone.neutral,
            icon: Icons.link_rounded,
          ),
          TaskCardBadge(
            label: englishLocalizations.badgeHistoryCount('2'),
            tone: UiPillTone.neutral,
            icon: Icons.history_rounded,
          ),
        ]),
      );
    });

    test('caps visibleSecondary at 3 in strict U-CARD-005 priority order and reports overflowCount', () {
      final crowdedTask = TaskItem(
        id: 'task000020',
        title: 'Everything enabled',
        isPriority: true,
        isSuspendedForever: true,
        dueAt: fixedNowUtc.subtract(const Duration(hours: 1)),
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'missing001'),
        ],
        conditions: <TaskCondition>[
          DayTaskCondition.fromWeekdays(const <int>[DateTime.monday]),
        ],
        subtasks: const <SubtaskItem>[SubtaskItem(title: 'Step')],
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.days),
        note: 'Has note',
        links: const <TaskLink>[
          TaskLink(title: 'Ref', uri: 'https://example.com'),
        ],
        history: <TaskHistoryEntry>[
          TaskHistoryEntry(timestampUtc: fixedNowUtc, text: 'Logged'),
        ],
        createdAt: fixedNowUtc,
      );

      final result = buildBadges(
        crowdedTask,
        tier: TaskTier.blocked,
        isSearchMode: true,
      );

      expect(
        result.primary,
        hasLength(2),
        reason: 'Search mode + dueAt must produce 2 primary badges',
      );
      expect(result.visibleSecondary, hasLength(3));
      expect(
        result.overflowCount,
        equals(6),
        reason: '9 total secondary badges minus 3 visible leaves +6 overflow',
      );
      expect(
        result.visibleSecondary,
        equals(<TaskCardBadge>[
          TaskCardBadge(
            label: englishLocalizations.quickAddPriority,
            tone: UiPillTone.accent,
            icon: Icons.bolt_outlined,
          ),
          TaskCardBadge(
            label: englishLocalizations.badgeSuspendedForever,
            tone: UiPillTone.warning,
            icon: Icons.pause_circle_outline_rounded,
          ),
          TaskCardBadge(
            label: englishLocalizations.badgeBlockedByProgress('0', '1'),
            tone: UiPillTone.warning,
            icon: Icons.lock_outline_rounded,
          ),
        ]),
      );
    });
  });
}
