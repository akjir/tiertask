import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/task_tier.dart';
import '../../providers/task_providers.dart';

/// Bottom Quick-Add input bar with category selection chips.
///
/// Defaults to `# Geplant` when no category chip is explicitly selected,
/// automatically cascading new tasks upward into `# Bereit` or `# Fokus`
/// whenever those tiers are below their soft WIP limits.
class QuickAddBar extends ConsumerStatefulWidget {
  const QuickAddBar({super.key});

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  final TextEditingController _controller = TextEditingController();
  TaskTier? _explicitSelectedTier;

  TaskTier get _effectiveTier => _explicitSelectedTier ?? TaskTier.geplant;

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final targetTier = _effectiveTier;
    _controller.clear();

    await ref
        .read(taskNotifierProvider.notifier)
        .addTask(text, targetTier: targetTier);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final tier in TaskTier.activeTiers)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            tier == TaskTier.geplant &&
                                    _explicitSelectedTier == null
                                ? '# ${tier.heading} (Standard)'
                                : '# ${tier.heading}',
                          ),
                          selected: _effectiveTier == tier,
                          visualDensity: VisualDensity.compact,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _explicitSelectedTier = tier;
                              } else {
                                _explicitSelectedTier = null;
                              }
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText:
                            'Neue Aufgabe in # ${_effectiveTier.heading} hinzufügen…',
                        isDense: true,
                        filled: true,
                        fillColor: colorScheme.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Hinzufügen'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
