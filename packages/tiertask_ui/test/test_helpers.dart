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

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

/// Pumps [child] inside a [MaterialApp] themed with [tokens] at [surfaceSize].
Future<void> pumpUiWidget(
  WidgetTester tester,
  Widget child, {
  UiThemeTokens? tokens,
  Size surfaceSize = const Size(1280, 800),
  bool wrapInScaffold = true,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = surfaceSize;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final activeTokens = tokens ?? UiThemePresets.calm.light;
  await tester.pumpWidget(
    MaterialApp(
      theme: activeTokens.toThemeData(),
      home: wrapInScaffold ? Scaffold(body: child) : child,
    ),
  );
  await tester.pump();
}
