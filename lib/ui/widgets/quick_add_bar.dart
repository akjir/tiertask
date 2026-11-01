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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/tier_localization_extension.dart';
import '../../models/task_tier.dart';
import '../../providers/task_providers.dart';

/// Bottom Quick-Add input bar with tier selection chips (`1` through `5`).
///
/// Defaults to Tier 3 (`# [3] Planned`) when no tier chip is explicitly selected,
/// automatically cascading new tasks upward into Tier 2 or Tier 1 when slots are open.
class QuickAddBar extends ConsumerStatefulWidget {
  /// Creates a [QuickAddBar] widget.
  const QuickAddBar({super.key});

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

/// State for [QuickAddBar].
class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  final TextEditingController _controller = TextEditingController();
  TaskTier? _explicitSelectedTier;

  TaskTier get _effectiveTier => _explicitSelectedTier ?? TaskTier.planned;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 8,
      color: colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TierSelectionChipRow(
                effectiveTier: _effectiveTier,
                explicitSelectedTier: _explicitSelectedTier,
                onTierSelected: _handleTierSelected,
              ),
              const SizedBox(height: 6),
              _QuickAddInputRow(
                controller: _controller,
                effectiveTier: _effectiveTier,
                onSubmit: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Updates the explicitly selected target tier.
  void _handleTierSelected(TaskTier tier, bool selected) {
    setState(() {
      _explicitSelectedTier = selected ? tier : null;
    });
  }

  /// Submits the entered task title to [TaskNotifier.addTask].
  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    final targetTier = _effectiveTier;
    _controller.clear();

    await ref
        .read(taskNotifierProvider.notifier)
        .addTask(text, targetTier: targetTier);
  }
}

/// Text input field and submit button row inside [QuickAddBar].
class _QuickAddInputRow extends StatelessWidget {
  /// Creates a [_QuickAddInputRow].
  const _QuickAddInputRow({
    required this.controller,
    required this.effectiveTier,
    required this.onSubmit,
  });

  /// Text controller for the task title input.
  final TextEditingController controller;

  /// Currently active target tier.
  final TaskTier effectiveTier;

  /// Callback invoked when the user submits the task.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);
    final heading = localizations.tierMarkdownHeading(effectiveTier);

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              hintText: localizations.quickAddHint(heading),
              isDense: true,
              filled: true,
              fillColor: colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: onSubmit,
          icon: const Icon(Icons.add_rounded),
          label: Text(localizations.actionAdd),
        ),
      ],
    );
  }
}

/// Horizontal scrollable row of tier selection chips for [QuickAddBar].
class _TierSelectionChipRow extends StatelessWidget {
  /// Creates a [_TierSelectionChipRow].
  const _TierSelectionChipRow({
    required this.effectiveTier,
    required this.explicitSelectedTier,
    required this.onTierSelected,
  });

  /// Effective target tier.
  final TaskTier effectiveTier;

  /// Explicitly chosen tier, or `null` when using the default Tier 3 (`planned`).
  final TaskTier? explicitSelectedTier;

  /// Callback invoked when a chip is toggled.
  final void Function(TaskTier tier, bool selected) onTierSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tier in TaskTier.activeTiers)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(_chipLabel(localizations, tier)),
                selected: effectiveTier == tier,
                visualDensity: VisualDensity.compact,
                onSelected: (selected) => onTierSelected(tier, selected),
              ),
            ),
        ],
      ),
    );
  }

  /// Formats the localized label for [tier] chip.
  String _chipLabel(AppLocalizations localizations, TaskTier tier) {
    final heading = localizations.tierMarkdownHeading(tier);
    if (tier == TaskTier.planned && explicitSelectedTier == null) {
      return localizations.defaultTierChipLabel(heading);
    }
    return heading;
  }
}
