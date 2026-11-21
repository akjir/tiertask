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
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import 'l10n/app_localizations.dart';
import 'presentation/shell_chrome_view_models.dart';
import 'providers/config_providers.dart';
import 'providers/local_file_watch_providers.dart';
import 'providers/workspace_providers.dart';
import 'services/app_logger.dart';
import 'ui/tier_task_shell_screen.dart';
import 'ui/ui_icon_mapper.dart';

/// Root Material 3 application widget for TierTask.
class TierTaskApp extends ConsumerStatefulWidget {
  /// Creates the root [TierTaskApp] widget.
  const TierTaskApp({super.key});

  @override
  ConsumerState<TierTaskApp> createState() => _TierTaskAppState();
}

/// State for [TierTaskApp] managing application lifecycle log flushing and Material routing.
class _TierTaskAppState extends ConsumerState<TierTaskApp> {
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _handleLifecycleStateChange,
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
    ref.watch(localFileWatcherProvider);
    final themeState = ref.watch(shellThemeStateProvider);
    final preset = UiThemePresets.byId(themeState.presetId);
    final buildProfile = ref.watch(appBuildProfileProvider);

    return MaterialApp(
      title: buildProfile.formatWindowTitle('TierTask'),
      onGenerateTitle: (context) =>
          buildProfile.formatWindowTitle(AppLocalizations.of(context).appTitle),
      debugShowCheckedModeBanner: false,
      locale: themeState.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      themeMode: UiIconMapper.flutterThemeMode(themeState.themeMode),
      theme: preset.light.toThemeData(),
      darkTheme: preset.dark.toThemeData(),
      home: const TierTaskShellScreen(),
    );
  }

  /// Attempts a best-effort WebDAV log upload when backgrounding the application.
  Future<void> _flushRemoteLogQuietly() async {
    try {
      await ref.read(webDavConfigProvider.notifier).syncLogToWebDavNow();
    } on Object {
      // Ignore background flush errors during lifecycle transitions.
    }
  }

  /// Records lifecycle state transitions and flushes WebDAV logs on backgrounding.
  void _handleLifecycleStateChange(AppLifecycleState state) {
    AppLogger.handleAppLifecycleState(state);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_flushRemoteLogQuietly());
    }
  }
}

/// Entry point for the TierTask application.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerGlobalErrorHandlers();
  runApp(
    const ProviderScope(retry: disableProviderRetry, child: TierTaskApp()),
  );
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
