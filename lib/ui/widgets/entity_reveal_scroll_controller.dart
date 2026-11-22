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

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../providers/shell_providers.dart';

/// Estimated vertical extent per collapsed entity card used to pre-scroll offscreen reveals.
const double _estimatedRevealCardExtent = 84.0;

/// Maximum bounded pre-scroll refinement passes when locating variable-height offscreen cards.
const int _maxRevealScrollAttempts = 6;

/// Duration used for smooth `Scrollable.ensureVisible` and draft scroll-to-top reveals (`U-LAYOUT-007`).
const Duration _revealScrollDuration = Duration(milliseconds: 220);

/// Reusable scroll-controller ownership, deferred disposal, card reveal key cache,
/// and bounded offscreen pre-scroll reveal logic shared by `TasksView`, `LabelsView`, and `LocationsView`.
mixin EntityRevealScrollMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  final Map<String, GlobalKey> _ownedCardKeys = <String, GlobalKey>{};
  final List<ScrollController> _pendingDisposals = <ScrollController>[];

  bool _isDisposalScheduled = false;
  bool _isKeyPruneScheduled = false;
  ScrollController? _ownedScrollController;
  String? _pendingRevealEntityId;
  int _revealRequestToken = 0;

  /// Effective scroll controller shared with the view's primary [CustomScrollView].
  ScrollController get effectiveScrollController {
    if (externalScrollController case final external?) {
      return external;
    }
    return _ownedScrollController ??= ScrollController();
  }

  /// Optional caller-owned scroll controller passed into the view widget.
  ScrollController? get externalScrollController;

  /// Whether any internally owned reveal card [GlobalKey]s are currently cached.
  bool get hasOwnedCardKeys => _ownedCardKeys.isNotEmpty;

  /// Viewport alignment (`0.0..1.0`) applied to `Scrollable.ensureVisible`.
  double get revealAlignment => 0.15;

  /// Optional caller-supplied key builder overriding owned reveal card keys.
  GlobalKey Function(String entityId)? get revealCardKeyBuilder => null;

  /// Draft kind whose opening triggers smooth scroll-to-top (`U-CARD-006`).
  EntityDraftKind get revealDraftKind;

  /// Entity kind matched against [ShellState.revealEntityRequest].
  EntityKind get revealEntityKind;

  /// Returns ordered identifiers for entities currently rendered in the lazy list.
  List<String> collectVisibleEntityIds();

  /// Disposes any owned fallback scroll controller and flushes queued deferred disposals.
  void disposeRevealScroll() {
    _flushPendingDisposals();
    _ownedScrollController?.dispose();
  }

  /// Defers disposal of an owned fallback scroll controller when a caller supplies [externalScrollController].
  void handleScrollControllerSwap(ScrollController? previousExternal) {
    if (previousExternal != externalScrollController &&
        externalScrollController != null) {
      if (_ownedScrollController case final previousOwned?) {
        _ownedScrollController = null;
        _enqueueDisposal(previousOwned);
      }
    }
  }

  /// Schedules any initial pending reveal request already set in [shellProvider] at mount time.
  void initRevealScroll() {
    scheduleRevealEntity(ref.read(shellProvider).revealEntityRequest);
  }

  /// Removes cached card [GlobalKey]s for entity identifiers absent from [activeIds].
  void pruneOwnedCardKeys(Iterable<String> activeIds) {
    if (revealCardKeyBuilder != null || _ownedCardKeys.isEmpty) {
      return;
    }
    final activeSet = activeIds is Set<String>
        ? activeIds
        : Set<String>.of(activeIds);
    _ownedCardKeys.removeWhere((id, _) => !activeSet.contains(id));
  }

  /// Registers [shellProvider] listeners for smooth entity reveal and draft scroll-to-top.
  void registerRevealShellListeners() {
    ref.listen<EntityRef?>(
      shellProvider.select((shell) => shell.revealEntityRequest),
      _handleRevealEntityRequested,
    );
    ref.listen<EntityDraftKind?>(
      shellProvider.select((shell) => shell.activeDraft),
      _handleActiveDraftChanged,
    );
  }

  /// Resolves a stable [GlobalKey] mapped to [entityId] for smooth reveal scrolling.
  GlobalKey resolveRevealCardKey(String entityId) {
    if (revealCardKeyBuilder case final builder?) {
      return builder(entityId);
    }
    return _ownedCardKeys.putIfAbsent(entityId, GlobalKey.new);
  }

  /// Schedules one coalesced post-frame prune of stale owned reveal card keys.
  void schedulePruneOwnedCardKeys() {
    if (revealCardKeyBuilder != null ||
        _ownedCardKeys.isEmpty ||
        _isKeyPruneScheduled) {
      return;
    }
    _isKeyPruneScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pruneOwnedCardKeysPostFrame();
    });
  }

  /// Schedules a post-frame bounded reveal scroll when [request] targets [revealEntityKind].
  void scheduleRevealEntity(EntityRef? request) {
    if (request == null ||
        request.kind != revealEntityKind ||
        _pendingRevealEntityId == request.id) {
      return;
    }
    _pendingRevealEntityId = request.id;
    final token = ++_revealRequestToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_performRevealEntity(request.id, token: token, attempt: 0));
    });
  }

  /// Smoothly scrolls the primary list back to offset `0.0` when opening a Draft Card (`U-CARD-006`).
  void scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final controller = effectiveScrollController;
      if (!controller.hasClients || controller.offset == 0.0) {
        return;
      }
      unawaited(
        controller.animateTo(
          0.0,
          duration: _revealScrollDuration,
          curve: Curves.easeOut,
        ),
      );
    });
  }

  /// Computes the next bounded pre-scroll offset targeting [targetIndex] inside [controller].
  double _computeNextRevealOffset({
    required ScrollController controller,
    required List<String> visibleIds,
    required int targetIndex,
    required int attempt,
  }) {
    final maxScrollExtent = controller.position.maxScrollExtent;
    if (attempt == 0) {
      return (targetIndex * _estimatedRevealCardExtent).clamp(
        0.0,
        maxScrollExtent,
      );
    }
    final bounds = _findMaterializedIndexBounds(visibleIds);
    final step = controller.position.viewportDimension * 0.85;
    if (bounds != null && bounds.minIndex > targetIndex) {
      return (controller.offset - step).clamp(0.0, maxScrollExtent);
    }
    if (bounds != null && bounds.maxIndex < targetIndex) {
      return (controller.offset + step).clamp(0.0, maxScrollExtent);
    }
    return (targetIndex * _estimatedRevealCardExtent).clamp(
      0.0,
      maxScrollExtent,
    );
  }

  /// Queues a replaced internal [controller] for post-frame disposal after the scroll view detaches.
  void _enqueueDisposal(ScrollController controller) {
    _pendingDisposals.add(controller);
    if (_isDisposalScheduled) {
      return;
    }
    _isDisposalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushPendingDisposals();
    });
  }

  /// Finds the lowest and highest indices in [visibleIds] currently mounted in the sliver viewport.
  ({int minIndex, int maxIndex})? _findMaterializedIndexBounds(
    List<String> visibleIds,
  ) {
    int? minIndex;
    int? maxIndex;
    for (var i = 0; i < visibleIds.length; i++) {
      final hasContext =
          resolveRevealCardKey(visibleIds[i]).currentContext != null;
      if (!hasContext) {
        continue;
      }
      minIndex ??= i;
      maxIndex = i;
    }
    if (minIndex == null || maxIndex == null) {
      return null;
    }
    return (minIndex: minIndex, maxIndex: maxIndex);
  }

  /// Clears local pending reveal tracking and the one-shot shell reveal request.
  void _finishRevealRequest() {
    _pendingRevealEntityId = null;
    ref.read(shellProvider.notifier).clearRevealRequest();
  }

  /// Disposes all queued internal scroll controllers after the frame or during unmount.
  void _flushPendingDisposals() {
    _isDisposalScheduled = false;
    if (_pendingDisposals.isEmpty) {
      return;
    }
    final controllers = List<ScrollController>.of(_pendingDisposals);
    _pendingDisposals.clear();
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  /// Scrolls the list to top when the matching Draft Card transitions from closed to open.
  void _handleActiveDraftChanged(
    EntityDraftKind? previous,
    EntityDraftKind? next,
  ) {
    if (next == revealDraftKind && previous != revealDraftKind) {
      scrollToTop();
    }
  }

  /// Schedules reveal scrolling when [shellProvider] requests focusing a matching entity card.
  void _handleRevealEntityRequested(EntityRef? previous, EntityRef? next) {
    scheduleRevealEntity(next);
  }

  /// Executes `Scrollable.ensureVisible` for [entityId], pre-scrolling offscreen lazy sliver items first.
  Future<void> _performRevealEntity(
    String entityId, {
    required int token,
    required int attempt,
  }) async {
    if (!mounted || token != _revealRequestToken) {
      return;
    }
    final cardContext = resolveRevealCardKey(entityId).currentContext;
    if (cardContext != null) {
      _finishRevealRequest();
      await Scrollable.ensureVisible(
        cardContext,
        duration: _revealScrollDuration,
        curve: Curves.easeOut,
        alignment: revealAlignment,
      );
      return;
    }

    final visibleIds = collectVisibleEntityIds();
    final targetIndex = visibleIds.indexOf(entityId);
    final controller = effectiveScrollController;
    if (targetIndex < 0 ||
        !controller.hasClients ||
        attempt >= _maxRevealScrollAttempts) {
      _finishRevealRequest();
      return;
    }

    final nextOffset = _computeNextRevealOffset(
      controller: controller,
      visibleIds: visibleIds,
      targetIndex: targetIndex,
      attempt: attempt,
    );
    if (attempt > 0 && (nextOffset - controller.offset).abs() < 1.0) {
      _finishRevealRequest();
      return;
    }
    controller.jumpTo(nextOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _performRevealEntity(entityId, token: token, attempt: attempt + 1),
      );
    });
  }

  /// Prunes stale owned card [GlobalKey]s post-frame outside widget `build()`.
  void _pruneOwnedCardKeysPostFrame() {
    _isKeyPruneScheduled = false;
    if (!mounted) {
      return;
    }
    pruneOwnedCardKeys(collectVisibleEntityIds());
  }
}
