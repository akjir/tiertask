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

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/services/app_logger.dart';

void main() {
  group('WebDavRepository HTTP GET, PUT, Backup Rotation & Auth', () {
    late HttpServer server;
    late Directory tempDir;
    final remoteFiles = <String, String>{};
    String? lastAuthHeader;
    String? lastAcceptHeader;
    String? lastContentTypeHeader;
    var forcedGetStatus = HttpStatus.ok;
    var forcedPutStatus = HttpStatus.noContent;
    var responseDelay = Duration.zero;
    var putCount = 0;

    setUp(() async {
      HttpOverrides.global = null;
      tempDir = await Directory.systemTemp.createTemp('tiertask_webdav_test_');
      remoteFiles.clear();
      lastAuthHeader = null;
      lastAcceptHeader = null;
      lastContentTypeHeader = null;
      forcedGetStatus = HttpStatus.ok;
      forcedPutStatus = HttpStatus.noContent;
      responseDelay = Duration.zero;
      putCount = 0;
      AppLogger.resetForTesting(sink: const LocalFileLogSink());

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        lastAuthHeader = request.headers.value(HttpHeaders.authorizationHeader);
        lastAcceptHeader = request.headers.value(HttpHeaders.acceptHeader);
        lastContentTypeHeader = request.headers.value(
          HttpHeaders.contentTypeHeader,
        );
        if (responseDelay > Duration.zero) {
          await Future<void>.delayed(responseDelay);
        }
        final path = request.uri.path;
        if (request.method == 'GET') {
          if (forcedGetStatus != HttpStatus.ok) {
            request.response.statusCode = forcedGetStatus;
            await request.response.close();
            return;
          }
          if (remoteFiles.containsKey(path)) {
            request.response.statusCode = HttpStatus.ok;
            request.response.write(remoteFiles[path]);
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        } else if (request.method == 'PUT') {
          putCount++;
          final body = await utf8.decoder.bind(request).join();
          if (forcedPutStatus >= 200 && forcedPutStatus < 300) {
            remoteFiles[path] = body;
          }
          request.response.statusCode = forcedPutStatus;
          await request.response.close();
        } else {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
        }
      });
    });

    tearDown(() async {
      AppLogger.resetForTesting();
      await server.close(force: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('fetches TDF via HTTP GET with Basic Auth, returns empty string on 404, and saves TDF via HTTP PUT (200/201/204)', () async {
      const remotePath = '/remote.php/dav/files/stefan/tiertask.tdf';
      final config = WebDavConfig(
        serverUrl: 'http://${server.address.host}:${server.port}',
        username: 'stefan',
        password: 'secret-app-password',
        filePath: 'tiertask.tdf',
        language: AppLanguage.english,
      );
      final repository = WebDavRepository(config: config);

      expect(
        await repository.fetchTdf(),
        isEmpty,
        reason: 'HTTP 404 must return empty string so a new board can init',
      );
      final expectedAuth =
          'Basic ${base64Encode(utf8.encode('stefan:secret-app-password'))}';
      expect(lastAuthHeader, equals(expectedAuth));
      expect(lastAcceptHeader, contains('text/plain'));

      const sampleTdf =
          'tdf 0.5.1\n\nqueue {\n    modified 2026-11-01 08:00:00\n    task 000001OkD2\n}\n\ntask 000001OkD2 {\n    name "Remote Focus 1"\n    created 2026-11-01 08:00:00\n    modified 2026-11-01 08:00:00\n}\n';
      for (final successStatus in <int>[
        HttpStatus.ok,
        HttpStatus.created,
        HttpStatus.noContent,
      ]) {
        forcedPutStatus = successStatus;
        await repository.saveTdf(sampleTdf);
      }
      expect(putCount, equals(3));
      expect(lastContentTypeHeader, contains('text/plain'));
      expect(remoteFiles[remotePath], equals(sampleTdf));

      final fetched = await repository.fetchTdf();
      expect(fetched, equals(sampleTdf));
    });

    test('maps HTTP 401, 403, 500, timeouts, and socket failures to WebDavException without leaking credentials', () async {
      const secretPassword = 'UltraSecretPassword!99';
      final config = WebDavConfig(
        serverUrl: 'http://${server.address.host}:${server.port}',
        username: 'stefan',
        password: secretPassword,
        filePath: 'tiertask.tdf',
        language: AppLanguage.english,
      );
      final repository = WebDavRepository(
        config: config,
        timeout: const Duration(milliseconds: 80),
      );

      for (final authStatus in <int>[
        HttpStatus.unauthorized,
        HttpStatus.forbidden,
      ]) {
        forcedGetStatus = authStatus;
        await expectLater(
          repository.fetchTdf,
          throwsA(
            isA<WebDavException>()
                .having((e) => e.statusCode, 'statusCode', equals(authStatus))
                .having(
                  (e) => e.toString(),
                  'toString',
                  allOf(
                    contains('HTTP $authStatus'),
                    isNot(contains(secretPassword)),
                  ),
                ),
          ),
        );

        forcedPutStatus = authStatus;
        await expectLater(
          () => repository.saveTdf('tdf 0.5.1\n'),
          throwsA(
            isA<WebDavException>()
                .having((e) => e.statusCode, 'statusCode', equals(authStatus))
                .having(
                  (e) => e.toString(),
                  'toString',
                  isNot(contains(secretPassword)),
                ),
          ),
        );
      }

      forcedGetStatus = HttpStatus.internalServerError;
      await expectLater(
        repository.fetchTdf,
        throwsA(
          isA<WebDavException>().having(
            (e) => e.statusCode,
            'statusCode',
            equals(HttpStatus.internalServerError),
          ),
        ),
      );

      forcedPutStatus = HttpStatus.internalServerError;
      await expectLater(
        () => repository.saveTdf('tdf 0.5.1\n'),
        throwsA(
          isA<WebDavException>().having(
            (e) => e.statusCode,
            'statusCode',
            equals(HttpStatus.internalServerError),
          ),
        ),
      );

      forcedGetStatus = HttpStatus.ok;
      forcedPutStatus = HttpStatus.noContent;
      responseDelay = const Duration(milliseconds: 250);
      await expectLater(
        repository.fetchTdf,
        throwsA(
          isA<WebDavException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      await expectLater(
        () => repository.saveTdf('tdf 0.5.1\n'),
        throwsA(
          isA<WebDavException>().having(
            (e) => e.message,
            'message',
            contains('Timed out'),
          ),
        ),
      );

      responseDelay = Duration.zero;
      final deadServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = deadServer.port;
      await deadServer.close(force: true);

      final unreachableRepo = WebDavRepository(
        config: config.copyWith(serverUrl: 'http://127.0.0.1:$deadPort'),
      );
      await expectLater(
        unreachableRepo.fetchTdf,
        throwsA(isA<WebDavException>()),
      );
      await expectLater(
        () => unreachableRepo.saveTdf('tdf 0.5.1\n'),
        throwsA(isA<WebDavException>()),
      );
    });

    test('wipeTdf resets remote file and rotates .bak and .bak.001+ remote backups when createBackup is true', () async {
      const remotePath = '/remote.php/dav/files/stefan/remote_wipe.tdf';
      final config = WebDavConfig(
        serverUrl: 'http://${server.address.host}:${server.port}',
        username: 'stefan',
        password: 'secret',
        filePath: 'remote_wipe.tdf',
        language: AppLanguage.english,
      );
      final repository = WebDavRepository(config: config);

      // Wiping a non-existent remote file initializes it without creating .bak.
      await repository.wipeTdf(createBackup: true);
      expect(remoteFiles[remotePath], equals('tdf 0.5.1\n'));
      expect(remoteFiles.containsKey('$remotePath.bak'), isFalse);

      // First wipe with createBackup: true writes .bak.
      remoteFiles[remotePath] = 'tdf 0.5.1\n# state 1\n';
      await repository.wipeTdf(createBackup: true);
      expect(remoteFiles['$remotePath.bak'], equals('tdf 0.5.1\n# state 1\n'));
      expect(remoteFiles[remotePath], equals('tdf 0.5.1\n'));

      // Second wipe with createBackup: true writes .bak.001 without overwriting .bak.
      remoteFiles[remotePath] = 'tdf 0.5.1\n# state 2\n';
      await repository.wipeTdf(createBackup: true);
      expect(
        remoteFiles['$remotePath.bak.001'],
        equals('tdf 0.5.1\n# state 2\n'),
      );
      expect(remoteFiles['$remotePath.bak'], equals('tdf 0.5.1\n# state 1\n'));
      expect(remoteFiles[remotePath], equals('tdf 0.5.1\n'));
    });

    test('validates WebDAV configuration and endpoint URIs and emits sanitized [STORAGE] logs to AppLogger', () async {
      final logFilePath =
          '${tempDir.path}${Platform.pathSeparator}tiertask.log';
      const secret = 'WebDavSecretPass#2026';
      AppLogger.setEnabled(
        true,
        sink: const LocalFileLogSink(),
        logFilePath: logFilePath,
      );

      final unconfiguredRepo = WebDavRepository(
        config: const WebDavConfig(
          storageMode: StorageMode.webdav,
          language: AppLanguage.english,
        ),
      );
      await expectLater(
        unconfiguredRepo.fetchTdf,
        throwsA(isA<WebDavException>()),
      );
      await expectLater(
        () => unconfiguredRepo.saveTdf('tdf 0.5.1\n'),
        throwsA(isA<WebDavException>()),
      );

      for (final invalidServerUrl in <String>[
        '',
        '   ',
        'http://',
        'https://',
        '://missing-host',
      ]) {
        final invalidConfig = WebDavConfig(
          serverUrl: invalidServerUrl,
          username: 'stefan',
          password: secret,
          filePath: 'tasks.tdf',
        );
        expect(
          invalidConfig.resolveEndpointUri(),
          isNull,
          reason: 'Malformed serverUrl "$invalidServerUrl" must resolve null',
        );
      }

      final activeConfig = WebDavConfig(
        serverUrl: 'http://${server.address.host}:${server.port}',
        username: 'stefan',
        password: secret,
        filePath: 'logged.tdf',
        language: AppLanguage.english,
      );
      final repository = WebDavRepository(config: activeConfig);
      await repository.saveTdf('tdf 0.5.1\n');
      await repository.fetchTdf();

      AppLogger.error(
        LogTag.storage,
        'Diagnostic check with $secret and Authorization: Basic c3RlZmFuOnNlY3JldA==',
      );

      final fullLog = AppLogger.fullLogText;
      expect(
        fullLog,
        contains('[INFO] [STORAGE] WebDavRepository.saveTdf PUT'),
        reason: 'WebDavRepository.saveTdf must emit [STORAGE] log entry',
      );
      expect(
        fullLog,
        contains('[INFO] [STORAGE] WebDavRepository.fetchTdf GET'),
        reason: 'WebDavRepository.fetchTdf must emit [STORAGE] log entry',
      );
      expect(
        fullLog,
        isNot(contains(secret)),
        reason: 'WebDAV password must never appear in AppLogger output',
      );
      expect(
        fullLog,
        isNot(contains('c3RlZmFuOnNlY3JldA==')),
        reason: 'Base64 Basic Auth token must be redacted in AppLogger',
      );
    });
  });
}
