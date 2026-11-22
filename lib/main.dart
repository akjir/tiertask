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
    if (ref.watch(supportsLocalFileWatchProvider)) {
      ref.watch(localFileWatcherProvider);
    }
    return child;
  }
}

/// State for [TierTaskApp] managing application lifecycle log flushing, cached themes, and Material routing.
class _TierTaskAppState extends ConsumerState<TierTaskApp> {
  static final Map<AppThemePalette, ({ThemeData light, ThemeData dark})>
  _cachedThemes =
      Map<AppThemePalette, ({ThemeData light, ThemeData dark})>.unmodifiable(
        <AppThemePalette, ({ThemeData light, ThemeData dark})>{
          for (final palette in AppThemePalette.values)
            palette: _buildThemePair(UiDomainMappers.themePreset(palette)),
        },
      );

  Future<void>? _inFlightRemoteLogFlush;
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _handleLifecycleStateChange,
      onExitRequested: _handleExitRequested,
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

  /// Builds the cached light and dark [ThemeData] pair for [preset].
  static ({ThemeData light, ThemeData dark}) _buildThemePair(
    UiThemePreset preset,
  ) => (light: preset.light.toThemeData(), dark: preset.dark.toThemeData());

  /// Attempts a deduplicated best-effort WebDAV log upload during backgrounding or shutdown.
  Future<void> _flushRemoteLogQuietly() {
    if (_inFlightRemoteLogFlush case final pending?) {
      return pending;
    }
    final operation = _runRemoteLogFlush();
    _inFlightRemoteLogFlush = operation;
    return operation;
  }

  /// Drains pending workspace persistence before flushing [AppLogger] and approving exit.
  Future<AppExitResponse> _handleExitRequested() async {
    if (mounted) {
      try {
        await ref.read(workspaceUnloadCoordinatorProvider).runBeforeUnload();
      } on Object catch (error) {
        AppLogger.event(
          LogLevel.warn,
          LogTag.lifecycle,
          'lifecycle.exit_flush_failed',
          error: error,
        );
      }
    }
    AppLogger.handleAppLifecycleState(AppLifecycleState.detached);
    return AppExitResponse.exit;
  }

  /// Records lifecycle state transitions and flushes WebDAV logs on backgrounding or exit.
  void _handleLifecycleStateChange(AppLifecycleState state) {
    AppLogger.handleAppLifecycleState(state);
    final shouldFlushRemoteLog = switch (state) {
      AppLifecycleState.paused ||
      AppLifecycleState.hidden ||
      AppLifecycleState.detached => true,
      AppLifecycleState.inactive || AppLifecycleState.resumed => false,
    };
    if (shouldFlushRemoteLog) {
      unawaited(_flushRemoteLogQuietly());
    }
  }

  /// Returns cached light and dark [ThemeData] instances for [palette].
  ({ThemeData light, ThemeData dark}) _resolveCachedThemes(
    AppThemePalette palette,
  ) {
    return _cachedThemes[palette] ??
        _buildThemePair(UiDomainMappers.themePreset(palette));
  }

  /// Executes a single best-effort WebDAV log upload and clears [_inFlightRemoteLogFlush].
  Future<void> _runRemoteLogFlush() async {
    try {
      if (!mounted) {
        return;
      }
      await ref.read(webDavConfigProvider.notifier).syncLogToWebDavNow();
    } on Object {
      // Ignore background flush errors during lifecycle transitions.
    } finally {
      _inFlightRemoteLogFlush = null;
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
