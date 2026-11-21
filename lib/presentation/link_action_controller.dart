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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/config_providers.dart';
import '../repositories/link_launcher_repository.dart';

/// Provides the presentation-layer [LinkActionController] for launching task and label URIs.
final linkActionControllerProvider = Provider<LinkActionController>(
  (ref) => LinkActionController(ref.watch(linkLauncherRepositoryProvider)),
);

/// Exhaustive outcome returned by [LinkActionController.openLink].
enum LinkOpenOutcome {
  /// The operating system accepted the link launch request.
  opened,

  /// The URI was invalid or the operating system failed to launch it.
  failed,
}

/// Mediates external link launch requests between UI widgets and [LinkLauncherRepository].
class LinkActionController {
  /// Creates a [LinkActionController] backed by [_repository].
  const LinkActionController(this._repository);

  final LinkLauncherRepository _repository;

  /// Attempts to open [uri] and returns [LinkOpenOutcome.opened] or [LinkOpenOutcome.failed].
  Future<LinkOpenOutcome> openLink(String uri) async {
    try {
      await _repository.openLink(uri);
      return LinkOpenOutcome.opened;
    } on LinkLaunchException {
      return LinkOpenOutcome.failed;
    }
  }
}
