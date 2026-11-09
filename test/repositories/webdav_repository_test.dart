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
        } else if (request.method == 'DELETE') {
          if (remoteFiles.remove(path) != null) {
            request.response.statusCode = HttpStatus.noContent;
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
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
      expect(remoteFiles[remotePath], equals('tdf 0.6.0\n'));
      expect(remoteFiles.containsKey('$remotePath.bak'), isFalse);

      // First wipe with createBackup: true writes .bak.
      remoteFiles[remotePath] = 'tdf 0.6.0\n# state 1\n';
      await repository.wipeTdf(createBackup: true);
      expect(remoteFiles['$remotePath.bak'], equals('tdf 0.6.0\n# state 1\n'));
      expect(remoteFiles[remotePath], equals('tdf 0.6.0\n'));

      // Second wipe with createBackup: true writes .bak.001 without overwriting .bak.
      remoteFiles[remotePath] = 'tdf 0.6.0\n# state 2\n';
      await repository.wipeTdf(createBackup: true);
      expect(
        remoteFiles['$remotePath.bak.001'],
        equals('tdf 0.6.0\n# state 2\n'),
      );
      expect(remoteFiles['$remotePath.bak'], equals('tdf 0.6.0\n# state 1\n'));
      expect(remoteFiles[remotePath], equals('tdf 0.6.0\n'));
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
        'ftp://cloud.example.com',
        'file:///etc/passwd',
        'https://user:pass@cloud.example.com',
        'https://cloud.example.com/dav?query=1',
        'https://cloud.example.com/dav#fragment',
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

      for (final invalidFilePath in <String>[
        '../tasks.tdf',
        'sub/../../etc/passwd',
        './tasks.tdf',
        r'folder\tasks.tdf',
        'tasks\x00.tdf',
      ]) {
        final invalidPathConfig = WebDavConfig(
          serverUrl: 'https://cloud.example.com',
          username: 'stefan',
          password: secret,
          filePath: invalidFilePath,
        );
        expect(
          invalidPathConfig.resolveEndpointUri(),
          isNull,
          reason: 'Unsafe remote filePath "$invalidFilePath" must resolve null',
        );
      }

      final activeConfig = WebDavConfig(
        serverUrl: 'http://${server.address.host}:${server.port}',
        username: 'stefan',
        password: secret,
        filePath: 'logged.tdf',
        language: AppLanguage.english,
      );
      expect(
        activeConfig.toString(),
        isNot(contains(secret)),
        reason: 'WebDavConfig.toString() must redact password',
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
        contains('[INFO ] [STORAGE  ] webdav.put |'),
        reason: 'WebDavRepository.saveTdf must emit [STORAGE] webdav.put entry',
      );
      expect(
        fullLog,
        contains('[INFO ] [STORAGE  ] webdav.get |'),
        reason:
            'WebDavRepository.fetchTdf must emit [STORAGE] webdav.get entry',
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

      final linesBeforeSaveLog = AppLogger.lines.length;
      const logFileName = 'tiertask_2026-11-03_linux_tasks.log';
      await repository.saveLog(logFileName);
      expect(
        remoteFiles['/remote.php/dav/files/stefan/$logFileName'],
        isNotEmpty,
        reason: 'saveLog must upload diagnostic log to sibling WebDAV path',
      );
      expect(
        AppLogger.lines.length,
        equals(linesBeforeSaveLog),
        reason: 'Successful saveLog must not append post-snapshot log entries that re-dirty the log',
      );

      forcedPutStatus = HttpStatus.internalServerError;
      await expectLater(
        () => repository.saveLog(logFileName),
        throwsA(isA<WebDavException>()),
      );
      expect(
        AppLogger.fullLogText,
        contains('[ERROR] [STORAGE  ] webdav.log_put |'),
        reason: 'Failed saveLog must record webdav.log_put error after request',
      );

      await repository.deleteLog(logFileName);
      expect(
        remoteFiles.containsKey('/remote.php/dav/files/stefan/$logFileName'),
        isFalse,
        reason: 'deleteLog must remove remote log file via HTTP DELETE',
      );
      await repository.deleteLog(logFileName);
      expect(
        AppLogger.fullLogText,
        contains('[INFO ] [STORAGE  ] webdav.log_delete |'),
        reason: 'deleteLog must record webdav.log_delete entry',
      );

      final boundedRepo = WebDavRepository(
        config: activeConfig,
        maxFileBytes: 64,
      );
      remoteFiles['/remote.php/dav/files/stefan/logged.tdf'] = 'a' * 64;
      expect(
        (await boundedRepo.fetchTdf()).length,
        equals(64),
        reason: 'Payload at exact maxFileBytes boundary must succeed',
      );
      remoteFiles['/remote.php/dav/files/stefan/logged.tdf'] = 'a' * 65;
      await expectLater(
        boundedRepo.fetchTdf,
        throwsA(isA<WebDavException>()),
        reason:
            'Payload exceeding maxFileBytes (N+1) must throw WebDavException',
      );
    });

    test('caches ETag and Last-Modified headers, evaluates 304 Not Modified on GET, and sends If-Match on PUT with 412 cache invalidation', () async {
      final etagServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => etagServer.close(force: true));

      var serverContent = 'tdf 0.6.0\n# v1\n';
      String? serverEtag = '"etag-v1"';
      String? serverLastModified = 'Mon, 09 Nov 2026 22:00:00 GMT';
      String? receivedIfNoneMatch;
      String? receivedIfModifiedSince;
      String? receivedIfMatch;
      var get200Count = 0;
      var get304Count = 0;

      etagServer.listen((HttpRequest request) async {
        receivedIfNoneMatch = request.headers.value(
          HttpHeaders.ifNoneMatchHeader,
        );
        receivedIfModifiedSince = request.headers.value(
          HttpHeaders.ifModifiedSinceHeader,
        );
        receivedIfMatch = request.headers.value(HttpHeaders.ifMatchHeader);

        if (request.method == 'GET') {
          final etagMatched =
              serverEtag != null && receivedIfNoneMatch == serverEtag;
          final lastModMatched =
              serverEtag == null &&
              serverLastModified != null &&
              receivedIfModifiedSince == serverLastModified;
          if (etagMatched || lastModMatched) {
            get304Count++;
            request.response.statusCode = HttpStatus.notModified;
            if (serverEtag != null) {
              request.response.headers.set(HttpHeaders.etagHeader, serverEtag!);
            }
            if (serverLastModified != null) {
              request.response.headers.set(
                HttpHeaders.lastModifiedHeader,
                serverLastModified!,
              );
            }
            await request.response.close();
            return;
          }
          get200Count++;
          request.response.statusCode = HttpStatus.ok;
          if (serverEtag != null) {
            request.response.headers.set(HttpHeaders.etagHeader, serverEtag!);
          }
          if (serverLastModified != null) {
            request.response.headers.set(
              HttpHeaders.lastModifiedHeader,
              serverLastModified!,
            );
          }
          request.response.write(serverContent);
          await request.response.close();
          return;
        }

        if (request.method == 'PUT') {
          final body = await utf8.decoder.bind(request).join();
          if (receivedIfMatch != null && receivedIfMatch != serverEtag) {
            request.response.statusCode = HttpStatus.preconditionFailed;
            await request.response.close();
            return;
          }
          serverContent = body;
          if (serverEtag != null && !serverEtag!.startsWith('W/')) {
            serverEtag = '"etag-v2"';
            request.response.headers.set(HttpHeaders.etagHeader, serverEtag!);
          }
          serverLastModified = 'Mon, 09 Nov 2026 22:05:00 GMT';
          request.response.headers.set(
            HttpHeaders.lastModifiedHeader,
            serverLastModified!,
          );
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
        }
      });

      expect(WebDavRepository.isStrongEtag('"etag-v1"'), isTrue);
      expect(WebDavRepository.isStrongEtag('W/"weak-etag"'), isFalse);
      expect(WebDavRepository.isStrongEtag('w/"weak-etag"'), isFalse);
      expect(WebDavRepository.isStrongEtag(''), isFalse);
      expect(WebDavRepository.isStrongEtag(null), isFalse);

      final config = WebDavConfig(
        serverUrl: 'http://${etagServer.address.host}:${etagServer.port}',
        username: 'stefan',
        password: 'secret',
        filePath: 'tasks.tdf',
        language: AppLanguage.english,
      );
      final repository = WebDavRepository(config: config);

      // 1. Initial GET returns 200 OK and caches ETag and Last-Modified.
      final firstBody = await repository.fetchTdf();
      expect(firstBody, equals('tdf 0.6.0\n# v1\n'));
      expect(repository.lastFetchWasNotModified, isFalse);
      expect(repository.cachedEtag, equals('"etag-v1"'));
      expect(
        repository.cachedLastModified,
        equals('Mon, 09 Nov 2026 22:00:00 GMT'),
      );
      expect(get200Count, equals(1));
      expect(get304Count, equals(0));

      // 2. Second GET sends If-None-Match and If-Modified-Since, receives 304 Not Modified, and returns cached content.
      final secondBody = await repository.fetchTdf();
      expect(secondBody, equals('tdf 0.6.0\n# v1\n'));
      expect(repository.lastFetchWasNotModified, isTrue);
      expect(receivedIfNoneMatch, equals('"etag-v1"'));
      expect(receivedIfModifiedSince, equals('Mon, 09 Nov 2026 22:00:00 GMT'));
      expect(get200Count, equals(1));
      expect(get304Count, equals(1));

      // 3. PUT sends If-Match: "etag-v1" and updates cachedEtag to "etag-v2".
      await repository.saveTdf('tdf 0.6.0\n# v2\n');
      expect(receivedIfMatch, equals('"etag-v1"'));
      expect(repository.cachedEtag, equals('"etag-v2"'));
      expect(
        repository.cachedLastModified,
        equals('Mon, 09 Nov 2026 22:05:00 GMT'),
      );

      // 4. Subsequent GET uses "etag-v2" from PUT response and receives 304 Not Modified without redownloading.
      final thirdBody = await repository.fetchTdf();
      expect(thirdBody, equals('tdf 0.6.0\n# v2\n'));
      expect(repository.lastFetchWasNotModified, isTrue);
      expect(receivedIfNoneMatch, equals('"etag-v2"'));
      expect(get200Count, equals(1));
      expect(get304Count, equals(2));

      // 5. Simulate concurrent external modification on server ("etag-v3"); PUT with stale "etag-v2" throws 412 and clears cached ETag.
      serverContent = 'tdf 0.6.0\n# v3-external\n';
      serverEtag = '"etag-v3"';
      await expectLater(
        () => repository.saveTdf('tdf 0.6.0\n# v2-local-conflict\n'),
        throwsA(
          isA<WebDavException>().having(
            (e) => e.statusCode,
            'statusCode',
            equals(HttpStatus.preconditionFailed),
          ),
        ),
      );
      expect(
        repository.cachedEtag,
        isNull,
        reason: 'HTTP 412 must invalidate stale cached ETag',
      );

      // 6. Next GET after 412 fetches unconditionally (200 OK) and obtains "etag-v3".
      final fourthBody = await repository.fetchTdf();
      expect(fourthBody, equals('tdf 0.6.0\n# v3-external\n'));
      expect(repository.lastFetchWasNotModified, isFalse);
      expect(repository.cachedEtag, equals('"etag-v3"'));
      expect(get200Count, equals(2));

      // 7. Weak ETag sends If-None-Match on GET, but omits If-Match on PUT.
      serverEtag = 'W/"weak-v4"';
      serverContent = 'tdf 0.6.0\n# v4-weak\n';
      repository.clearCache();
      await repository.fetchTdf();
      expect(repository.cachedEtag, equals('W/"weak-v4"'));
      await repository.fetchTdf();
      expect(repository.lastFetchWasNotModified, isTrue);
      expect(receivedIfNoneMatch, equals('W/"weak-v4"'));
      await repository.saveTdf('tdf 0.6.0\n# v5\n');
      expect(
        receivedIfMatch,
        isNull,
        reason: 'Weak ETag must not be sent in If-Match header on PUT',
      );

      // 8. Server with only Last-Modified (no ETag) evaluates 304 via If-Modified-Since.
      serverEtag = null;
      serverLastModified = 'Mon, 09 Nov 2026 22:10:00 GMT';
      serverContent = 'tdf 0.6.0\n# v6-lastmod-only\n';
      repository.clearCache();
      repository.seedCacheIfEmpty(
        etag: null,
        lastModified: 'Mon, 09 Nov 2026 22:10:00 GMT',
        content: 'tdf 0.6.0\n# v6-lastmod-only\n',
      );
      final seededBody = await repository.fetchTdf();
      expect(seededBody, equals('tdf 0.6.0\n# v6-lastmod-only\n'));
      expect(repository.lastFetchWasNotModified, isTrue);
      expect(receivedIfModifiedSince, equals('Mon, 09 Nov 2026 22:10:00 GMT'));
    });
  });
}
