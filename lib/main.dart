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

import 'l10n/app_localizations.dart';
import 'models/webdav_config.dart';
import 'providers/config_providers.dart';
import 'providers/local_file_watch_providers.dart';
import 'providers/workspace_providers.dart';
import 'services/app_logger.dart';
import 'ui/tier_task_shell_screen.dart';
import 'ui/tokens/ui_theme_tokens.dart';
import 'ui/ui_domain_mappers.dart';

/// Root Material 3 application widget for TierTask.
class TierTaskApp extends ConsumerStatefulWidget {
  /// Creates the root [TierTaskApp] widget.
  const TierTaskApp({super.key});

  @override
  ConsumerState<TierTaskApp> createState() => _TierTaskAppState();
}

/// Keeps background diagnostic logging and local file-watching active without rebuilding [MaterialApp].
class _BackgroundServicesHost extends ConsumerWidget {
  /// Creates a [_BackgroundServicesHost] wrapping [child].
  const _BackgroundServicesHost({required this.child});

  /// Stable child subtree shielded from background service rebuilds.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(diagnosticsEnabledProvider);
    ref.watch(localFileWatcherProvider);
    return child;
  }
}

/// State for [TierTaskApp] managing application lifecycle log flushing, cached themes, and Material routing.
class _TierTaskAppState extends ConsumerState<TierTaskApp> {
  static final ThemeData _calmDarkTheme = UiThemePresets.calm.dark
      .toThemeData();
  static final ThemeData _calmLightTheme = UiThemePresets.calm.light
      .toThemeData();
  static final ThemeData _plumDarkTheme = UiThemePresets.plumUmber.dark
      .toThemeData();
  static final ThemeData _plumLightTheme = UiThemePresets.plumUmber.light
      .toThemeData();

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
    final palette = ref.watch(appThemePaletteProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final locale = ref.watch(appLocaleProvider);
    final buildProfile = ref.watch(appBuildProfileProvider);
    final themes = _resolveCachedThemes(palette);

    return MaterialApp(
      title: buildProfile.formatWindowTitle('TierTask'),
      onGenerateTitle: (context) =>
          buildProfile.formatWindowTitle(AppLocalizations.of(context).appTitle),
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      themeMode: UiDomainMappers.flutterThemeMode(themeMode),
      theme: themes.light,
      darkTheme: themes.dark,
      home: const _BackgroundServicesHost(child: TierTaskShellScreen()),
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

  /// Returns cached light and dark [ThemeData] instances for [palette].
  ({ThemeData light, ThemeData dark}) _resolveCachedThemes(
    AppThemePalette palette,
  ) {
    return switch (palette) {
      AppThemePalette.calm => (light: _calmLightTheme, dark: _calmDarkTheme),
      AppThemePalette.plumUmber => (
        light: _plumLightTheme,
        dark: _plumDarkTheme,
      ),
    };
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
