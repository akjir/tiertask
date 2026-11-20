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

import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/storage_file_read_localization_extension.dart';
import '../../models/storage_file_read_status.dart';

/// Compact per-file readability status content rendered inside error banners.
class FileReadStatusBannerContent extends StatelessWidget {
  /// Creates a [FileReadStatusBannerContent] for [report].
  const FileReadStatusBannerContent({
    super.key,
    required this.report,
    required this.foregroundColor,
  });

  /// Foreground text and icon color matching the enclosing error container.
  final Color foregroundColor;

  /// Structured readability report for the active local and/or remote files.
  final StorageFileReadReport report;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final summary = switch (report.failureScope) {
      final scope? => localizations.storageFileReadSummary(scope),
      null => null,
    };
    return Column(
      key: const ValueKey('file_read_banner_content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (summary != null)
          Text(
            summary,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: foregroundColor,
            ),
          ),
        for (final entry in report.activeEntries) ...[
          const SizedBox(height: 4),
          _FileReadStatusBannerRow(
            entry: entry,
            foregroundColor: foregroundColor,
          ),
        ],
      ],
    );
  }
}

/// Full-width Material 3 card presenting per-file local and/or remote readability status on error screens.
class FileReadStatusCard extends StatelessWidget {
  /// Creates a [FileReadStatusCard] for [report].
  const FileReadStatusCard({super.key, required this.report});

  /// Structured readability report for the active local and/or remote files.
  final StorageFileReadReport report;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final summary = switch (report.failureScope) {
      final scope? => localizations.storageFileReadSummary(scope),
      null => null,
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (summary != null) ...[
            Text(
              summary,
              key: const ValueKey('file_read_status_summary'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 14),
          ],
          _FileReadStatusCardContainer(entries: report.activeEntries),
        ],
      ),
    );
  }
}

/// Compact pill badge indicating whether a storage file is `OK` or unreadable.
class _FileReadStatusBadge extends StatelessWidget {
  /// Creates a [_FileReadStatusBadge].
  const _FileReadStatusBadge({required this.isReadable});

  /// Whether the associated storage file is readable and intact.
  final bool isReadable;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isReadable
        ? colorScheme.primaryContainer
        : colorScheme.errorContainer;
    final foregroundColor = isReadable
        ? colorScheme.onPrimaryContainer
        : colorScheme.onErrorContainer;
    final label = isReadable
        ? localizations.fileReadStatusOk
        : localizations.fileReadStatusUnreadable;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: foregroundColor,
        ),
      ),
    );
  }
}

/// Single compact status line inside [FileReadStatusBannerContent].
class _FileReadStatusBannerRow extends StatelessWidget {
  /// Creates a [_FileReadStatusBannerRow].
  const _FileReadStatusBannerRow({
    required this.entry,
    required this.foregroundColor,
  });

  /// Target file readability status to display.
  final StorageFileReadStatus entry;

  /// Foreground text and icon color matching the enclosing error container.
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final icon = entry.isReadable
        ? Icons.check_circle_outline_rounded
        : Icons.error_outline_rounded;
    return Row(
      key: ValueKey('file_read_banner_row_${entry.target.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1.5),
          child: Icon(icon, size: 15, color: foregroundColor),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            localizations.formatStorageFileReadLine(entry),
            style: TextStyle(fontSize: 12.5, color: foregroundColor),
          ),
        ),
      ],
    );
  }
}

/// Bordered surface container listing active [_FileReadStatusCardRow] entries.
class _FileReadStatusCardContainer extends StatelessWidget {
  /// Creates a [_FileReadStatusCardContainer].
  const _FileReadStatusCardContainer({required this.entries});

  /// Active target statuses rendered inside the card.
  final List<StorageFileReadStatus> entries;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('file_read_status_card'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colorScheme.outlineVariant),
            _FileReadStatusCardRow(entry: entries[i]),
          ],
        ],
      ),
    );
  }
}

/// Single target status row inside [_FileReadStatusCardContainer].
class _FileReadStatusCardRow extends StatelessWidget {
  /// Creates a [_FileReadStatusCardRow].
  const _FileReadStatusCardRow({required this.entry});

  /// Target file readability status to display.
  final StorageFileReadStatus entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = entry.isReadable
        ? Icons.check_circle_outline_rounded
        : Icons.error_outline_rounded;
    final iconColor = entry.isReadable
        ? colorScheme.primary
        : colorScheme.error;
    return Padding(
      key: ValueKey('file_read_status_row_${entry.target.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(child: _FileReadStatusRowDetails(entry: entry)),
        ],
      ),
    );
  }
}

/// Target label, status badge, and optional failure reason column inside [_FileReadStatusCardRow].
class _FileReadStatusRowDetails extends StatelessWidget {
  /// Creates a [_FileReadStatusRowDetails].
  const _FileReadStatusRowDetails({required this.entry});

  /// Target file readability status to display.
  final StorageFileReadStatus entry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final reason = localizations.storageFileReadEntryReason(entry);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              localizations.storageFileTargetLabel(entry.target),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            _FileReadStatusBadge(isReadable: entry.isReadable),
          ],
        ),
        if (reason != null) ...[
          const SizedBox(height: 4),
          Text(
            reason,
            style: TextStyle(
              fontSize: 12.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
