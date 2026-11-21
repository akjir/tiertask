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
import '../models/task_board.dart';
import '../models/tdf_metadata.dart';
import '../providers/config_providers.dart';
import '../providers/task_providers.dart';
import '../services/app_logger.dart';

/// Provides [LabelEditorController] for label validation, CRUD mutations, and redacted telemetry.
final labelEditorControllerProvider = Provider<LabelEditorController>(
  LabelEditorController.new,
);

/// Categorizes field validation failures in the label editor.
enum LabelValidationErrorKind {
  /// Label name is empty or whitespace-only.
  emptyName,

  /// Another label already uses the same name (case-insensitive).
  duplicateName,

  /// Entered hexadecimal color string is not a valid `#RRGGBB` value.
  invalidColor,
}

/// Immutable validation result returned by [LabelEditorController.validateLabel].
@immutable
class LabelValidationResult {
  /// Creates a [LabelValidationResult].
  const LabelValidationResult({
    this.errorKind,
    this.errorMessage,
    this.normalizedColor,
    this.trimmedName,
  });

  /// Validation error category, or `null` when valid.
  final LabelValidationErrorKind? errorKind;

  /// Localized inline error text, or `null` when valid.
  final String? errorMessage;

  /// Normalized uppercase `#RRGGBB` color string, or `null` when cleared or invalid.
  final String? normalizedColor;

  /// Trimmed valid label name, or `null` when validation failed.
  final String? trimmedName;

  /// Whether validation succeeded.
  bool get isValid => errorKind == null && trimmedName != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LabelValidationResult &&
        other.errorKind == errorKind &&
        other.errorMessage == errorMessage &&
        other.normalizedColor == normalizedColor &&
        other.trimmedName == trimmedName;
  }

  @override
  int get hashCode =>
      Object.hash(errorKind, errorMessage, normalizedColor, trimmedName);
}

/// Presentation controller owning label validation, CRUD delegation, and redacted `ui.label_editor.save` telemetry.
class LabelEditorController {
  /// Creates a [LabelEditorController] backed by [_ref].
  const LabelEditorController(this._ref);

  final Ref _ref;

  /// Creates a new label from [rawName], ignoring empty or whitespace-only inputs.
  Future<void> addLabel(String rawName) async {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _ref.read(taskNotifierProvider.notifier).addLabel(trimmed);
  }

  /// Deletes the label identified by [labelId].
  Future<void> deleteLabel(String labelId) =>
      _ref.read(taskNotifierProvider.notifier).deleteLabel(labelId);

  /// Emits redacted save telemetry and persists updated fields onto [labelId].
  Future<void> saveLabel({
    required String labelId,
    required String name,
    required String? normalizedColor,
    required bool clearColor,
    required String? note,
    required bool isScoped,
    required List<TaskLink> links,
    required List<TaskCondition> conditions,
  }) async {
    if (AppLogger.shouldLog(LogLevel.info)) {
      AppLogger.event(
        LogLevel.info,
        LogTag.ui,
        'ui.label_editor.save',
        fields: <String, Object?>{
          'id': labelId,
          'links': links.length,
          'scoped': isScoped,
        },
      );
    }
    await _ref
        .read(taskNotifierProvider.notifier)
        .updateLabel(
          labelId,
          name: name,
          color: normalizedColor,
          clearColor: clearColor,
          note: note,
          clearNote: note == null,
          isScoped: isScoped,
          links: List<TaskLink>.unmodifiable(links),
          conditions: conditions,
        );
  }

  /// Validates [rawName] and [rawColor] against [board], excluding [labelId] from duplicate checks.
  LabelValidationResult validateLabel({
    required TaskBoard board,
    required String labelId,
    required String rawName,
    required String rawColor,
    Locale? locale,
  }) {
    final localizations = lookupAppLocalizations(
      locale ?? _ref.read(appLocaleProvider),
    );
    final trimmedName = rawName.trim();
    if (trimmedName.isEmpty) {
      return LabelValidationResult(
        errorKind: LabelValidationErrorKind.emptyName,
        errorMessage: localizations.labelNameErrorEmpty,
      );
    }
    if (board.hasDuplicateLabelName(trimmedName, excludingLabelId: labelId)) {
      return LabelValidationResult(
        errorKind: LabelValidationErrorKind.duplicateName,
        errorMessage: localizations.labelNameErrorDuplicate,
      );
    }
    final trimmedColor = rawColor.trim();
    final normalizedColor = TdfColor.normalizeHex(trimmedColor);
    if (trimmedColor.isNotEmpty && normalizedColor == null) {
      return LabelValidationResult(
        errorKind: LabelValidationErrorKind.invalidColor,
        errorMessage: localizations.labelColorErrorInvalid,
      );
    }
    return LabelValidationResult(
      trimmedName: trimmedName,
      normalizedColor: normalizedColor,
    );
  }
}
