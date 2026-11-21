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
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/location_state.dart';
import '../models/task_board.dart';
import '../models/tdf_error.dart';
import '../models/webdav_config.dart';
import '../providers/config_providers.dart';
import '../providers/location_providers.dart';
import '../providers/task_providers.dart';
import '../repositories/app_version_repository.dart';

/// Provides the formatted [AppVersionViewModel] for drawer and about footers.
final appVersionViewModelProvider = Provider<AppVersionViewModel>(
  (ref) => AppVersionViewModel.fromRawVersion(
    ref.watch(appVersionProvider).asData?.value ??
        AppVersionRepository.defaultFullVersion,
  ),
);

/// Evaluates the live [TaskBoard] against clock, boundary ticks, location fix, lead window, and [activeLabelId].
final evaluatedBoardProvider = Provider.autoDispose
    .family<AsyncValue<TaskBoard>, String?>((ref, activeLabelId) {
      ref.watch(boundaryTickProvider);
      final boardAsync = ref.watch(taskNotifierProvider);
      final activeFix = ref.watch(
        locationStateProvider.select(
          (state) => state.status == LocationStatus.found ? state.fix : null,
        ),
      );
      final evaluationConfig = ref.watch(
        webDavConfigProvider.select((asyncConfiguration) {
          final config =
              asyncConfiguration.asData?.value ?? const WebDavConfig();
          return (
            dueLeadWindow: config.dueLeadWindow,
            manualTimeZoneOffsetMinutes: config.manualTimeZoneOffsetMinutes,
            timeZoneMode: config.timeZoneMode,
          );
        }),
      );
      final clock = ref.watch(clockProvider);
      return boardAsync.whenData((board) {
        final evaluationTime = clock().toUtc();
        final timeZoneConfig = WebDavConfig(
          timeZoneMode: evaluationConfig.timeZoneMode,
          manualTimeZoneOffsetMinutes:
              evaluationConfig.manualTimeZoneOffsetMinutes,
          dueLeadWindow: evaluationConfig.dueLeadWindow,
        );
        return board.evaluateForContext(
          activeLabelId: activeLabelId,
          currentLatitude: activeFix?.latitude,
          currentLongitude: activeFix?.longitude,
          evaluationTime: evaluationTime,
          localEvaluationTime: timeZoneConfig.toLocalWallClock(evaluationTime),
          dueLeadWindow: evaluationConfig.dueLeadWindow.duration,
        );
      });
    });

/// Provides [TdfPreviewController] for exporting the current board into raw `.tdf` preview text.
final tdfPreviewControllerProvider = Provider<TdfPreviewController>(
  TdfPreviewController.new,
);

/// Sealed result returned by [TdfPreviewController.serializeBoard].
sealed class TdfPreviewResult {
  /// Creates a [TdfPreviewResult].
  const TdfPreviewResult();
}

/// Result returned when `.tdf` preview serialization exceeds format limits.
@immutable
final class TdfPreviewLimitExceeded extends TdfPreviewResult {
  /// Creates a [TdfPreviewLimitExceeded] result with [localizedMessage].
  const TdfPreviewLimitExceeded(this.localizedMessage);

  /// Localized fallback message explaining that the serialized file exceeds bounds.
  final String localizedMessage;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TdfPreviewLimitExceeded &&
        other.localizedMessage == localizedMessage;
  }

  @override
  int get hashCode => localizedMessage.hashCode;
}

/// Result returned when `.tdf` preview serialization succeeds.
@immutable
final class TdfPreviewSuccess extends TdfPreviewResult {
  /// Creates a [TdfPreviewSuccess] result carrying [content].
  const TdfPreviewSuccess(this.content);

  /// Serialized canonical `.tdf` document text.
  final String content;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TdfPreviewSuccess && other.content == content;
  }

  @override
  int get hashCode => content.hashCode;
}

/// Immutable split presentation view of the SemVer 2.0.0 application version and build metadata.
@immutable
class AppVersionViewModel {
  /// Creates an [AppVersionViewModel] with [versionLabel] and [buildSuffix].
  const AppVersionViewModel({
    required this.versionLabel,
    required this.buildSuffix,
  });

  /// Splits [rawVersion] (`v0.4.0+<build>`) into `Version 0.4.0` and `+<build>`.
  factory AppVersionViewModel.fromRawVersion(String rawVersion) {
    final trimmed = rawVersion.trim();
    final versionText = (trimmed.startsWith('v') || trimmed.startsWith('V'))
        ? trimmed.substring(1)
        : trimmed;
    final plusIndex = versionText.indexOf('+');
    if (plusIndex < 0) {
      return AppVersionViewModel(
        versionLabel: 'Version $versionText',
        buildSuffix: '',
      );
    }
    return AppVersionViewModel(
      versionLabel: 'Version ${versionText.substring(0, plusIndex)}',
      buildSuffix: versionText.substring(plusIndex),
    );
  }

  /// Build metadata suffix starting with `'+'`, or empty when absent.
  final String buildSuffix;

  /// Human-readable version prefix (e.g., `'Version 0.4.0'`).
  final String versionLabel;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppVersionViewModel &&
        other.versionLabel == versionLabel &&
        other.buildSuffix == buildSuffix;
  }

  @override
  int get hashCode => Object.hash(versionLabel, buildSuffix);
}

/// Serializes a [TaskBoard] into `.tdf` preview text while shielding UI widgets from [TdfException].
class TdfPreviewController {
  /// Creates a [TdfPreviewController] backed by [_ref].
  const TdfPreviewController(this._ref);

  final Ref _ref;

  /// Serializes [board] to `.tdf` text or returns a localized [TdfPreviewLimitExceeded] fallback.
  TdfPreviewResult serializeBoard(TaskBoard board, {Locale? locale}) {
    try {
      return TdfPreviewSuccess(_ref.read(tdfServiceProvider).serialize(board));
    } on TdfException {
      final localizations = lookupAppLocalizations(
        locale ?? _ref.read(appLocaleProvider),
      );
      return TdfPreviewLimitExceeded(localizations.errorLocalFileTooLarge);
    }
  }
}
