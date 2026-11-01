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
import '../../models/tdf_metadata.dart';
import '../../providers/task_providers.dart';
import 'color_wheel_picker.dart';

const Color _defaultCategoryColor = Color(0xFFEB06FF);
const Color _defaultLocationColor = Color(0xFF00E5FF);

/// Modal panel for viewing, creating, and deleting TDF categories or locations.
class ContextManagementSheet extends ConsumerStatefulWidget {
  /// Creates a [ContextManagementSheet] for the specified [kind].
  const ContextManagementSheet({super.key, required this.kind});

  /// Panel domain kind (`categories` or `locations`).
  final ContextPanelKind kind;

  @override
  ConsumerState<ContextManagementSheet> createState() =>
      _ContextManagementSheetState();
}

/// Identifies whether [ContextManagementSheet] manages categories or locations.
enum ContextPanelKind {
  /// Manages TDF `category` blocks.
  categories,

  /// Manages TDF `location` blocks.
  locations,
}

/// Color selection section pairing [ColorWheelPicker] with a direct hexadecimal input field.
class _ColorSelectionRow extends StatelessWidget {
  /// Creates a [_ColorSelectionRow].
  const _ColorSelectionRow({
    required this.hexController,
    required this.selectedColor,
    required this.onHexChanged,
    required this.onWheelColorChanged,
  });

  /// Controller for the direct hexadecimal color input field.
  final TextEditingController hexController;

  /// Callback invoked when the user edits the hexadecimal text field.
  final ValueChanged<String> onHexChanged;

  /// Callback invoked when the user selects a color on the color wheel.
  final ValueChanged<Color> onWheelColorChanged;

  /// Active color rendered on the wheel and preview swatch.
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ColorWheelPicker(
          key: const ValueKey('color_wheel_picker'),
          selectedColor: selectedColor,
          onColorChanged: onWheelColorChanged,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    key: const ValueKey('color_preview_indicator'),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: selectedColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white54, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('color_hex_input'),
                      controller: hexController,
                      onChanged: onHexChanged,
                      decoration: InputDecoration(
                        labelText: localizations.colorHexLabel,
                        hintText: '#4CAF50',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Form card for creating a new category or location with name, color wheel, and hex input.
class _ContextCreationForm extends StatelessWidget {
  /// Creates a [_ContextCreationForm].
  const _ContextCreationForm({
    required this.canSubmit,
    required this.hexController,
    required this.kind,
    required this.nameController,
    required this.selectedColor,
    required this.onHexChanged,
    required this.onSubmit,
    required this.onWheelColorChanged,
  });

  /// Whether the name and hex color inputs are valid for submission.
  final bool canSubmit;

  /// Text controller for the direct hex color input.
  final TextEditingController hexController;

  /// Active panel kind (`categories` or `locations`).
  final ContextPanelKind kind;

  /// Text controller for the display name input.
  final TextEditingController nameController;

  /// Callback invoked when the hex input text changes.
  final ValueChanged<String> onHexChanged;

  /// Callback invoked when the Add button is pressed.
  final VoidCallback onSubmit;

  /// Callback invoked when the color wheel selection changes.
  final ValueChanged<Color> onWheelColorChanged;

  /// Currently selected color.
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isCategories = kind == ContextPanelKind.categories;
    final inputKey = ValueKey(
      isCategories ? 'category_name_input' : 'location_name_input',
    );
    final buttonKey = ValueKey(
      isCategories ? 'add_category_button' : 'add_location_button',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: inputKey,
                controller: nameController,
                onSubmitted: (_) {
                  if (canSubmit) {
                    onSubmit();
                  }
                },
                decoration: InputDecoration(
                  hintText: isCategories
                      ? localizations.categoryNameHint
                      : localizations.locationNameHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: buttonKey,
              onPressed: canSubmit ? onSubmit : null,
              icon: const Icon(Icons.add_rounded),
              label: Text(localizations.actionAdd),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ColorSelectionRow(
          hexController: hexController,
          selectedColor: selectedColor,
          onHexChanged: onHexChanged,
          onWheelColorChanged: onWheelColorChanged,
        ),
      ],
    );
  }
}

/// Immutable display row model for a category or location entry inside [ContextManagementSheet].
@immutable
class _ContextEntryViewData {
  /// Creates a [_ContextEntryViewData].
  const _ContextEntryViewData({
    required this.id,
    required this.name,
    required this.color,
    this.hexLabel,
  });

  /// Resolved display color for the swatch.
  final Color color;

  /// Optional raw `#RRGGBB` string.
  final String? hexLabel;

  /// Unique TDF entity `<id>`.
  final String id;

  /// Human-readable display name.
  final String name;
}

/// Single list tile displaying a created category or location with its color swatch and delete action.
class _ContextItemTile extends StatelessWidget {
  /// Creates a [_ContextItemTile].
  const _ContextItemTile({
    super.key,
    required this.entry,
    required this.kind,
    required this.onDelete,
  });

  /// Entry data to render.
  final _ContextEntryViewData entry;

  /// Panel domain kind (`categories` or `locations`).
  final ContextPanelKind kind;

  /// Callback invoked when the delete button is pressed.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isCategories = kind == ContextPanelKind.categories;
    final prefix = isCategories ? 'category' : 'location';
    final hexText = entry.hexLabel;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        key: ValueKey('${prefix}_swatch_${entry.id}'),
        width: 24,
        height: 24,
        decoration: BoxDecoration(color: entry.color, shape: BoxShape.circle),
      ),
      title: Text(entry.name),
      subtitle: hexText != null ? Text(hexText) : null,
      trailing: IconButton(
        key: ValueKey('delete_${prefix}_${entry.id}'),
        tooltip: isCategories
            ? localizations.tooltipDeleteCategory
            : localizations.tooltipDeleteLocation,
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: onDelete,
      ),
    );
  }
}

/// Virtualized list of existing categories or locations inside [ContextManagementSheet].
class _ContextItemsList extends StatelessWidget {
  /// Creates a [_ContextItemsList].
  const _ContextItemsList({
    required this.entries,
    required this.kind,
    required this.onDelete,
  });

  /// Entries to display.
  final List<_ContextEntryViewData> entries;

  /// Panel domain kind (`categories` or `locations`).
  final ContextPanelKind kind;

  /// Callback invoked with the entry ID when delete is pressed.
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isCategories = kind == ContextPanelKind.categories;

    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          isCategories
              ? localizations.emptyCategoriesHint
              : localizations.emptyLocationsHint,
        ),
      );
    }

    final prefix = isCategories ? 'category' : 'location';
    return Flexible(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _ContextItemTile(
            key: ValueKey('${prefix}_item_${entry.id}'),
            entry: entry,
            kind: kind,
            onDelete: () => onDelete(entry.id),
          );
        },
      ),
    );
  }
}

/// State for [ContextManagementSheet].
class _ContextManagementSheetState
    extends ConsumerState<ContextManagementSheet> {
  late final TextEditingController _hexController;
  final TextEditingController _nameController = TextEditingController();
  late Color _selectedColor;

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty &&
      TdfColor.normalizeHex(_hexController.text) != null;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.kind == ContextPanelKind.categories
        ? _defaultCategoryColor
        : _defaultLocationColor;
    _hexController = TextEditingController(
      text: TdfColor.formatArgb(_selectedColor.toARGB32()),
    );
    _nameController.addListener(_handleInputChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_handleInputChanged);
    _nameController.dispose();
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final entries = _watchEntries();
    final title = widget.kind == ContextPanelKind.categories
        ? localizations.drawerCategories
        : localizations.drawerLocations;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _ContextCreationForm(
                canSubmit: _canSubmit,
                hexController: _hexController,
                kind: widget.kind,
                nameController: _nameController,
                selectedColor: _selectedColor,
                onHexChanged: _handleHexChanged,
                onSubmit: _submit,
                onWheelColorChanged: _handleWheelColorChanged,
              ),
              const Divider(height: 24),
              _ContextItemsList(
                entries: entries,
                kind: widget.kind,
                onDelete: _deleteEntry,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Deletes the category or location with [id].
  Future<void> _deleteEntry(String id) async {
    final notifier = ref.read(taskNotifierProvider.notifier);
    if (widget.kind == ContextPanelKind.categories) {
      await notifier.deleteCategory(id);
    } else {
      await notifier.deleteLocation(id);
    }
  }

  /// Updates [_selectedColor] when a valid 6-digit hex code is typed into [_hexController].
  void _handleHexChanged(String rawHex) {
    final parsedArgb = TdfColor.tryParseArgb(rawHex);
    setState(() {
      if (parsedArgb != null) {
        _selectedColor = Color(parsedArgb);
      }
    });
  }

  /// Rebuilds the form state when the name input changes.
  void _handleInputChanged() {
    setState(() {});
  }

  /// Updates [_selectedColor] and [_hexController] when the color wheel changes.
  void _handleWheelColorChanged(Color color) {
    final formattedHex = TdfColor.formatArgb(color.toARGB32());
    setState(() {
      _selectedColor = color;
      _hexController.value = TextEditingValue(
        text: formattedHex,
        selection: TextSelection.collapsed(offset: formattedHex.length),
      );
    });
  }

  /// Resolves a display [Color] from [rawHex] or falls back to [fallback].
  static Color _resolveColor(String? rawHex, Color fallback) {
    final argb = TdfColor.tryParseArgb(rawHex);
    return argb != null ? Color(argb) : fallback;
  }

  /// Creates the new category or location and resets the name input.
  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final normalizedHex = TdfColor.normalizeHex(_hexController.text);
    if (name.isEmpty || normalizedHex == null) {
      return;
    }
    _nameController.clear();
    final notifier = ref.read(taskNotifierProvider.notifier);
    if (widget.kind == ContextPanelKind.categories) {
      await notifier.addCategory(name, color: normalizedHex);
    } else {
      await notifier.addLocation(name, color: normalizedHex);
    }
  }

  /// Watches and maps the active categories or locations list from [taskNotifierProvider].
  List<_ContextEntryViewData> _watchEntries() {
    if (widget.kind == ContextPanelKind.categories) {
      final categories = ref.watch(
        taskNotifierProvider.select(
          (boardAsync) =>
              boardAsync.asData?.value.categories ?? const <TdfCategory>[],
        ),
      );
      return [
        for (final category in categories)
          _ContextEntryViewData(
            id: category.id,
            name: category.name,
            color: _resolveColor(category.color, _defaultCategoryColor),
            hexLabel: category.color,
          ),
      ];
    }

    final locations = ref.watch(
      taskNotifierProvider.select(
        (boardAsync) =>
            boardAsync.asData?.value.locations ?? const <TdfLocation>[],
      ),
    );
    return [
      for (final location in locations)
        _ContextEntryViewData(
          id: location.id,
          name: location.name,
          color: _resolveColor(location.color, _defaultLocationColor),
          hexLabel: location.color,
        ),
    ];
  }
}
