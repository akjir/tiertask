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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'models/webdav_config.dart';
import 'providers/task_providers.dart';
import 'services/app_logger.dart';
import 'ui/home_screen.dart';

/// Root Material 3 application widget for TierTask.
class TierTaskApp extends ConsumerStatefulWidget {
  /// Creates the root [TierTaskApp] widget.
  const TierTaskApp({super.key});

  @override
  ConsumerState<TierTaskApp> createState() => _TierTaskAppState();
}

class _TierTaskAppState extends ConsumerState<TierTaskApp> {
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: AppLogger.handleAppLifecycleState,
      onExitRequested: () async {
        AppLogger.handleAppLifecycleState(AppLifecycleState.detached);
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(diagnosticsEnabledProvider);
    final locale = ref.watch(appLocaleProvider);
    final appThemeMode = ref.watch(appThemeModeProvider);
    final appThemeSet = ref.watch(appThemeProvider);

    return MaterialApp(
      title: 'TierTask',
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      themeMode: _toFlutterThemeMode(appThemeMode),
      theme: appThemeSet.light.toThemeData(),
      darkTheme: appThemeSet.dark.toThemeData(),
      home: const HomeScreen(),
    );
  }

  /// Maps [AppThemeMode] to Flutter's [ThemeMode].
  ThemeMode _toFlutterThemeMode(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };
  }
}

/// Entry point for the TierTask application.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerGlobalErrorHandlers();
  runApp(const ProviderScope(child: TierTaskApp()));
}

/// Registers global framework and isolate crash handlers for [AppLogger].
void registerGlobalErrorHandlers() {
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.crash(details.exception, details.stack ?? StackTrace.current);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
    AppLogger.crash(error, stackTrace);
    return true;
  };
}
