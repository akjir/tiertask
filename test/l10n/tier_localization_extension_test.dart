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

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/l10n/tier_localization_extension.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/task_tier.dart';

void main() {
  final locales = <Locale>[const Locale('en'), const Locale('de')];

  group('TierLocalizationExtension', () {
    test('tierName maps every TaskTier exhaustively in en and de', () {
      for (final locale in locales) {
        final localizations = lookupAppLocalizations(locale);
        final expectedNames = <TaskTier, String>{
          TaskTier.focus: localizations.tier1Name,
          TaskTier.ready: localizations.tier2Name,
          TaskTier.planned: localizations.tier3Name,
          TaskTier.blocked: localizations.tier4Name,
          TaskTier.someday: localizations.tier5Name,
          TaskTier.completed: localizations.tier6Name,
        };

        for (final tier in TaskTier.values) {
          final localized = localizations.tierName(tier);
          expect(
            localized,
            equals(expectedNames[tier]),
            reason: 'tierName mismatch for $tier in ${locale.languageCode}',
          );
          expect(
            localized.trim(),
            isNotEmpty,
            reason: 'tierName must be non-empty for $tier in $locale',
          );
        }
      }
    });

    test('tierEmptyHint maps every TaskTier exhaustively in en and de', () {
      for (final locale in locales) {
        final localizations = lookupAppLocalizations(locale);
        final expectedHints = <TaskTier, String>{
          TaskTier.focus: localizations.emptyFocusHint,
          TaskTier.ready: localizations.emptyReadyHint,
          TaskTier.planned: localizations.emptyPlannedHint,
          TaskTier.blocked: localizations.emptyBlockedHint,
          TaskTier.someday: localizations.emptySomedayHint,
          TaskTier.completed: localizations.emptyCompletedHint,
        };

        for (final tier in TaskTier.values) {
          final localized = localizations.tierEmptyHint(tier);
          expect(
            localized,
            equals(expectedHints[tier]),
            reason:
                'tierEmptyHint mismatch for $tier in ${locale.languageCode}',
          );
          expect(
            localized.trim(),
            isNotEmpty,
            reason: 'tierEmptyHint must be non-empty for $tier in $locale',
          );
        }
      }
    });

    test('localizeWorkspaceError maps every WorkspaceErrorKind exhaustively in en and de', () {
      for (final locale in locales) {
        final localizations = lookupAppLocalizations(locale);
        const customMessage = 'Workspace custom-id does not exist';
        final expectedMessages = <WorkspaceErrorKind, String>{
          WorkspaceErrorKind.emptyName: localizations.errorWorkspaceNameEmpty,
          WorkspaceErrorKind.duplicateName:
              localizations.errorWorkspaceNameDuplicate,
          WorkspaceErrorKind.duplicateFilePath:
              localizations.errorDuplicateWorkspaceFilePath,
          WorkspaceErrorKind.invalidFilePath:
              localizations.errorInvalidLocalFilePath,
          WorkspaceErrorKind.workspaceNotFound: customMessage,
          WorkspaceErrorKind.cannotDeleteLastWorkspace:
              localizations.errorWorkspaceCannotDeleteLast,
          WorkspaceErrorKind.maxWorkspacesExceeded:
              localizations.errorWorkspaceMaxExceeded,
          WorkspaceErrorKind.corruptSettingsPayload:
              localizations.errorSettingsCorrupt,
          WorkspaceErrorKind.unsupportedSettingsSchemaVersion:
              localizations.errorSettingsUnsupportedVersion,
          WorkspaceErrorKind.credentialStorageUnavailable:
              localizations.errorSettingsCredentialStorageUnavailable,
          WorkspaceErrorKind.settingsPersistenceFailed:
              localizations.errorSettingsSaveFailed,
        };

        for (final kind in WorkspaceErrorKind.values) {
          final exception = WorkspaceException(kind, customMessage);
          final localized = localizations.localizeWorkspaceError(exception);
          expect(
            localized,
            equals(expectedMessages[kind]),
            reason:
                'localizeWorkspaceError mismatch for $kind in ${locale.languageCode}',
          );
          expect(
            localized.trim(),
            isNotEmpty,
            reason:
                'localizeWorkspaceError must be non-empty for $kind in $locale',
          );
        }
      }
    });
  });
}
