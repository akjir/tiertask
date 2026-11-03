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

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';

void main() {
  final fixedDate = DateTime.utc(2026, 11, 1, 12, 0);

  group('AppLanguage & Locale Resolution', () {
    test(
      'resolves English as default and honors German or System locale settings',
      () {
        expect(
          AppLanguage.system.resolveLocale(const Locale('de', 'DE')),
          equals(const Locale('de')),
        );
        expect(
          AppLanguage.system.resolveLocale(const Locale('en', 'US')),
          equals(const Locale('en')),
        );
        expect(
          AppLanguage.system.resolveLocale(const Locale('fr', 'FR')),
          equals(const Locale('en')),
        );
        expect(
          AppLanguage.system.resolveLocale(null),
          equals(const Locale('en')),
        );
        expect(
          AppLanguage.english.resolveLocale(const Locale('de', 'DE')),
          equals(const Locale('en')),
        );
        expect(
          AppLanguage.german.resolveLocale(const Locale('en', 'US')),
          equals(const Locale('de')),
        );
        expect(AppLanguage.fromId(2), equals(AppLanguage.german));
        expect(AppLanguage.fromId(1), equals(AppLanguage.english));
        expect(AppLanguage.fromId(0), equals(AppLanguage.system));
        expect(AppLanguage.fromId(99), equals(AppLanguage.system));
      },
    );
  });

  group('Riverpod TaskNotifier & Native WebDavRepository (TDF)', () {
    late HttpServer server;
    String remoteTdfStore = '';
    String? lastAuthHeader;
    int putCount = 0;

    setUp(() async {
      remoteTdfStore = '''
tdf 0.2.0

task f1 {
    name "Remote Focus 1"
    created 2026-11-01 08:00
    queued 2026-11-01 08:00
}
task f2 {
    name "Remote Focus 2"
    created 2026-11-01 08:05
    queued 2026-11-01 08:05
}
task f3 {
    name "Remote Focus 3"
    created 2026-11-01 08:10
    queued 2026-11-01 08:10
}
task r1 {
    name "Remote Ready 1"
    created 2026-11-01 08:15
    queued 2026-11-01 08:15
}
task b1 {
    name "Remote Backlog 1"
    created 2026-11-01 08:20
    queued 2026-11-01 08:20
}
''';
      lastAuthHeader = null;
      putCount = 0;

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        lastAuthHeader = request.headers.value(HttpHeaders.authorizationHeader);
        if (request.method == 'GET') {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(remoteTdfStore);
          await request.response.close();
        } else if (request.method == 'PUT') {
          putCount++;
          remoteTdfStore = await utf8.decoder.bind(request).join();
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
        } else {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
        }
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('fetches TDF via HTTP GET with Basic Auth, derives tiers, and syncs mutations via HTTP PUT', () async {
      final config = WebDavConfig(
        serverUrl: 'http://${server.address.host}:${server.port}',
        username: 'stefan',
        password: 'secret-app-password',
        filePath: 'tiertask.tdf',
        language: AppLanguage.english,
      );

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(config),
          ),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(container.dispose);

      final initialBoard = await container.read(taskNotifierProvider.future);

      final expectedAuth =
          'Basic ${base64Encode(utf8.encode('stefan:secret-app-password'))}';
      expect(lastAuthHeader, equals(expectedAuth));

      expect(initialBoard.focus.length, equals(3));
      expect(
        initialBoard.ready.map((task) => task.title),
        equals(['Remote Ready 1', 'Remote Backlog 1']),
      );
      expect(initialBoard.planned, isEmpty);

      final firstFocusId = initialBoard.focus.first.id;
      await container
          .read(taskNotifierProvider.notifier)
          .completeTask(firstFocusId);

      final updatedBoard = container.read(taskNotifierProvider).value!;
      expect(
        updatedBoard.focus.map((task) => task.title),
        equals(['Remote Focus 2', 'Remote Focus 3', 'Remote Ready 1']),
      );
      expect(
        updatedBoard.ready.map((task) => task.title),
        equals(['Remote Backlog 1']),
      );
      expect(updatedBoard.completed.first.title, equals('Remote Focus 1'));

      expect(putCount, greaterThanOrEqualTo(1));
      expect(remoteTdfStore, contains('tdf 0.3.0'));
      expect(remoteTdfStore, contains('task f1 {'));
      expect(remoteTdfStore, contains('finished 2026-11-01 12:00'));
    });
  });

  group('Localization ARB Metadata & Key Parity', () {
    test('every message key in app_en.arb defines @key metadata with a non-empty description and matches app_de.arb keys', () {
      final enRaw = File('lib/l10n/app_en.arb').readAsStringSync();
      final deRaw = File('lib/l10n/app_de.arb').readAsStringSync();
      final enDecoded = jsonDecode(enRaw);
      final deDecoded = jsonDecode(deRaw);

      expect(enDecoded, isA<Map<String, Object?>>());
      expect(deDecoded, isA<Map<String, Object?>>());
      if (enDecoded is! Map<String, Object?> ||
          deDecoded is! Map<String, Object?>) {
        return;
      }

      final enMessageKeys = <String>[
        for (final key in enDecoded.keys)
          if (!key.startsWith('@')) key,
      ];
      final deMessageKeys = <String>[
        for (final key in deDecoded.keys)
          if (!key.startsWith('@')) key,
      ];

      expect(enMessageKeys, contains('sectionReadyTasks'));
      expect(enMessageKeys, contains('sectionLabels'));
      expect(enMessageKeys, contains('drawerLabels'));
      expect(enMessageKeys, contains('emptyLabelsHint'));
      expect(enMessageKeys, isNot(contains('sectionCategories')));
      expect(enMessageKeys, isNot(contains('sectionLocations')));
      expect(enMessageKeys, isNot(contains('moveTaskTitle')));
      expect(enMessageKeys, isNot(contains('menuMoveTo')));
      expect(enMessageKeys, isNot(contains('openTaskCountSectionTitle')));
      expect(enMessageKeys, isNot(contains('openTaskCountSectionDescription')));
      expect(enMessageKeys, isNot(contains('openTaskCountOff')));
      expect(enMessageKeys, isNot(contains('openTaskCountOn')));
      expect(enMessageKeys, isNot(contains('taskCountLabel')));
      expect(deMessageKeys, equals(enMessageKeys));

      for (final key in enMessageKeys) {
        _expectArbKeyMetadata(enDecoded, key);
      }
    });

    test('Linux, Windows, and Android platform runners and manifests display TierTask as the taskbar and window title', () {
      final linuxRunner = File('linux/runner/my_application.cc')
          .readAsStringSync();
      expect(
        linuxRunner,
        contains('gtk_header_bar_set_title(header_bar, "TierTask");'),
      );
      expect(
        linuxRunner,
        contains('gtk_window_set_title(window, "TierTask");'),
      );
      expect(linuxRunner, contains('g_set_application_name("TierTask");'));

      final windowsMain = File('windows/runner/main.cpp').readAsStringSync();
      expect(windowsMain, contains('window.Create(L"TierTask", origin, size)'));

      final windowsResource = File('windows/runner/Runner.rc')
          .readAsStringSync();
      expect(
        windowsResource,
        contains('VALUE "FileDescription", "TierTask" "\\0"'),
      );

      final androidManifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(androidManifest, contains('android:label="TierTask"'));
    });
  });

  group('AppThemeMode, StorageMode & WebDavConfig Resolution', () {
    test('resolves AppThemeMode and StorageMode binary IDs with system and local tasks.tdf defaults', () {
      expect(AppThemeMode.fromId(1), equals(AppThemeMode.light));
      expect(AppThemeMode.fromId(2), equals(AppThemeMode.dark));
      expect(AppThemeMode.fromId(0), equals(AppThemeMode.system));
      expect(AppThemeMode.fromId(99), equals(AppThemeMode.system));

      expect(StorageMode.fromId(0), equals(StorageMode.local));
      expect(StorageMode.fromId(1), equals(StorageMode.webdav));
      expect(StorageMode.fromId(2), equals(StorageMode.both));
      expect(StorageMode.fromId(99), equals(StorageMode.local));

      const defaultConfig = WebDavConfig();
      expect(defaultConfig.themeMode, equals(AppThemeMode.system));
      expect(defaultConfig.storageMode, equals(StorageMode.local));
      expect(
        defaultConfig.localFilePath,
        equals('tasks.tdf'),
        reason: 'Default localFilePath must be tasks.tdf',
      );
      expect(
        defaultConfig.filePath,
        equals('tasks.tdf'),
        reason: 'Default remote filePath must be tasks.tdf',
      );
      expect(defaultConfig.isConfigured, isTrue);
    });
  });

  group('LocalFileRepository & Persistent Local TDF Storage', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tiertask_local_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('reads and writes local .tdf files and rejects traversal or oversized payloads', () async {
      const config = WebDavConfig(
        localFilePath: 'custom_tasks.tdf',
        storageMode: StorageMode.local,
      );
      final repository = LocalFileRepository(
        config: config,
        baseDirectoryPath: tempDir.path,
        maxFileBytes: 256,
      );

      expect(
        await repository.loadTdf(),
        isEmpty,
        reason: 'Missing local TDF file must return empty string',
      );

      const sampleTdf =
          'tdf 0.2.0\ntask t001 {\n  name "Local Task"\n  created 2026-11-01 08:00\n  queued 2026-11-01 08:00\n}\n';
      await repository.saveTdf(sampleTdf);
      final loaded = await repository.loadTdf();
      expect(loaded, contains('name "Local Task"'));

      final traversalRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: '../escape.tdf'),
        baseDirectoryPath: tempDir.path,
      );
      await expectLater(
        traversalRepo.loadTdf,
        throwsA(isA<LocalFileException>()),
        reason: 'Relative parent traversal (..) must be rejected',
      );

      final nullByteRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'bad\x00file.tdf'),
        baseDirectoryPath: tempDir.path,
      );
      await expectLater(
        nullByteRepo.saveTdf('content'),
        throwsA(isA<LocalFileException>()),
        reason: 'Null bytes in local file name must be rejected',
      );

      await expectLater(
        repository.saveTdf('A' * 300),
        throwsA(isA<LocalFileException>()),
        reason: 'Content exceeding maxFileBytes must be rejected before write',
      );
    });

    test('persists and reloads TDF tasks across container restarts in StorageMode.local and StorageMode.both', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      var remoteTdf = '';
      var remotePutCount = 0;
      server.listen((HttpRequest request) async {
        if (request.method == 'GET') {
          request.response.statusCode = remoteTdf.isEmpty
              ? HttpStatus.notFound
              : HttpStatus.ok;
          request.response.write(remoteTdf);
          await request.response.close();
        } else if (request.method == 'PUT') {
          remotePutCount++;
          remoteTdf = await utf8.decoder.bind(request).join();
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
        }
      });

      const localOnlyConfig = WebDavConfig(
        localFilePath: 'local_only.tdf',
        storageMode: StorageMode.local,
        language: AppLanguage.english,
      );

      final localContainer = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(localOnlyConfig),
          ),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(localContainer.dispose);

      await localContainer.read(taskNotifierProvider.future);
      await localContainer
          .read(taskNotifierProvider.notifier)
          .addTask(
            'Persistent Local Task',
            isPriority: true,
            subtasks: const [SubtaskItem(title: 'First step')],
          );

      final localFile = File('${tempDir.path}/local_only.tdf');
      expect(
        await localFile.exists(),
        isTrue,
        reason: 'Local mode must persist local_only.tdf on disk',
      );
      final savedDiskContent = await localFile.readAsString();
      expect(savedDiskContent, contains('tdf 0.3.0'));
      expect(savedDiskContent, contains('name "Persistent Local Task"'));
      expect(savedDiskContent, contains('step false "First step"'));
      expect(remotePutCount, equals(0));

      final restartedContainer = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(localOnlyConfig),
          ),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(restartedContainer.dispose);

      final reloadedBoard = await restartedContainer.read(
        taskNotifierProvider.future,
      );
      expect(
        reloadedBoard.focus.map((task) => task.title),
        equals(['Persistent Local Task']),
        reason: 'Reloaded container must restore task from local .tdf file',
      );
      expect(
        reloadedBoard.focus.first.subtasks.single.title,
        equals('First step'),
      );

      final bothConfig = WebDavConfig(
        serverUrl: 'http://${server.address.host}:${server.port}',
        username: 'stefan',
        password: 'secret',
        filePath: 'remote_both.tdf',
        localFilePath: 'both_mode.tdf',
        storageMode: StorageMode.both,
        language: AppLanguage.english,
      );

      final bothContainer = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(bothConfig),
          ),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(bothContainer.dispose);

      await bothContainer.read(taskNotifierProvider.future);
      await bothContainer
          .read(taskNotifierProvider.notifier)
          .addTask('Dual Synced TDF Task');

      final bothFile = File('${tempDir.path}/both_mode.tdf');
      expect(await bothFile.exists(), isTrue);
      expect(
        await bothFile.readAsString(),
        contains('name "Dual Synced TDF Task"'),
      );
      expect(remoteTdf, contains('name "Dual Synced TDF Task"'));
      expect(remotePutCount, greaterThanOrEqualTo(1));
    });
  });
}

/// Verifies that [arbMap] defines an `@<key>` metadata map with a non-empty description.
void _expectArbKeyMetadata(Map<String, Object?> arbMap, String key) {
  final metadataKey = '@$key';
  final metadata = arbMap[metadataKey];
  expect(
    metadata,
    isA<Map<String, Object?>>(),
    reason:
        'The message with key "$key" must have $metadataKey metadata defined',
  );
  if (metadata is! Map<String, Object?>) {
    return;
  }

  final description = metadata['description'];
  expect(
    description,
    isA<String>(),
    reason: 'Metadata $metadataKey must define a description string',
  );
  if (description is String) {
    expect(
      description.trim(),
      isNotEmpty,
      reason: 'Metadata $metadataKey description must not be empty',
    );
  }
}
