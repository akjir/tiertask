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
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';

/// Fake [LocalFileRepository] returning an in-memory `.tdf` document for widget tests.
class FakeLocalFileRepository extends LocalFileRepository {
  /// Creates a [FakeLocalFileRepository].
  FakeLocalFileRepository({required super.config, required this.initialTdf});

  /// Initial `.tdf` content returned by [loadTdf] before any mutations are saved.
  String initialTdf;

  @override
  Future<String> loadTdf() async => initialTdf;

  @override
  Future<void> saveTdf(String tdfContent) async {
    initialTdf = tdfContent;
  }
}

/// Fake [WebDavRepository] for deterministic widget tests of connection status banners.
class FakeWebDavRepository extends WebDavRepository {
  /// Creates a [FakeWebDavRepository].
  FakeWebDavRepository({required super.config, required this.shouldFail});

  /// Callback returning whether WebDAV operations should throw a [WebDavException].
  final bool Function() shouldFail;

  @override
  Future<String> fetchTdf() async {
    if (shouldFail()) {
      throw const WebDavException(
        'Authentication failed. Please check username and app password.',
        statusCode: 401,
      );
    }
    return '';
  }

  @override
  Future<void> saveTdf(String tdfContent) async {
    if (shouldFail()) {
      throw const WebDavException(
        'Authentication failed while saving. Please check app password.',
        statusCode: 401,
      );
    }
  }
}

/// Opens the top-left navigation drawer and navigates to SettingsScreen.
Future<void> openSettingsFromMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
}
