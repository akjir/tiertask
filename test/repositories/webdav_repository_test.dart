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
    final getPaths = <String>[];
    final headPaths = <String>[];

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
      getPaths.clear();
      headPaths.clear();
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
          getPaths.add(path);
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
        } else if (request.method == 'HEAD') {
          headPaths.add(path);
          if (forcedGetStatus != HttpStatus.ok) {
            request.response.statusCode = forcedGetStatus;
            await request.response.close();
            return;
          }
          request.response.statusCode = remoteFiles.containsKey(path)
              ? HttpStatus.ok
              : HttpStatus.notFound;
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
          'tdf 0.8.0\n\nqueue {\n    modified 2026-11-01 08:00:00\n    task 000001OkD2\n}\n\ntask 000001OkD2 {\n    name "Remote Focus 1"\n    created 2026-11-01 08:00:00\n    modified 2026-11-01 08:00:00\n}\n';
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
          () => repository.saveTdf('tdf 0.8.0\n'),
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
        () => repository.saveTdf('tdf 0.8.0\n'),
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
        () => repository.saveTdf('tdf 0.8.0\n'),
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
        () => unreachableRepo.saveTdf('tdf 0.8.0\n'),
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
      expect(remoteFiles[remotePath], equals('tdf 0.8.0\n'));
      expect(remoteFiles.containsKey('$remotePath.bak'), isFalse);

      // First wipe with createBackup: true writes .bak.
      remoteFiles[remotePath] = 'tdf 0.8.0\n# state 1\n';
      await repository.wipeTdf(createBackup: true);
      expect(remoteFiles['$remotePath.bak'], equals('tdf 0.8.0\n# state 1\n'));
      expect(remoteFiles[remotePath], equals('tdf 0.8.0\n'));

      // Second wipe with createBackup: true writes .bak.001 without overwriting .bak.
      getPaths.clear();
      headPaths.clear();
      remoteFiles[remotePath] = 'tdf 0.8.0\n# state 2\n';
      await repository.wipeTdf(createBackup: true);
      expect(
        remoteFiles['$remotePath.bak.001'],
        equals('tdf 0.8.0\n# state 2\n'),
      );
      expect(remoteFiles['$remotePath.bak'], equals('tdf 0.8.0\n# state 1\n'));
      expect(remoteFiles[remotePath], equals('tdf 0.8.0\n'));
      expect(
        headPaths,
        equals(<String>['$remotePath.bak', '$remotePath.bak.001']),
        reason: 'Remote backup slot probing must use lightweight HTTP HEAD requests',
      );
      expect(
        getPaths,
        equals(<String>[remotePath]),
        reason: 'Backup slot probing must never download .bak files via GET',
      );
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
        () => unconfiguredRepo.saveTdf('tdf 0.8.0\n'),
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
        'file:/etc/passwd',
        'http:/cloud.example.com',
        'https://user:pass@cloud.example.com',
        'user:pass@cloud.example.com',
        'https://cloud.example.com/dav?query=1',
        'https://cloud.example.com/dav#fragment',
        'https://cloud.example.com/../secret',
        r'https://cloud.example.com\dav',
        'starknet .one',
      ]) {
        final invalidConfig = WebDavConfig(
          serverUrl: invalidServerUrl,
          username: 'stefan',
          password: secret,
        );
        expect(
          invalidConfig.resolveEndpointUri(),
          isNull,
          reason: 'Malformed serverUrl "$invalidServerUrl" must resolve null',
        );
      }

      expect(
        const WebDavConfig(
          serverUrl: 'starknet.one',
          username: 'stefan',
          password: secret,
        ).resolveEndpointUri()?.toString(),
        equals('https://starknet.one/remote.php/dav/files/stefan/tasks.tdf'),
        reason: 'Scheme-less serverUrl must resolve with implicit https://',
      );

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
      await repository.saveTdf('tdf 0.8.0\n');
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

      var serverContent = 'tdf 0.8.0\n# v1\n';
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
          final currentEtag = serverEtag;
          final currentLastModified = serverLastModified;
          final etagMatched =
              currentEtag != null && receivedIfNoneMatch == currentEtag;
          final lastModMatched =
              currentEtag == null &&
              currentLastModified != null &&
              receivedIfModifiedSince == currentLastModified;
          if (etagMatched || lastModMatched) {
            get304Count++;
            request.response.statusCode = HttpStatus.notModified;
            if (currentEtag != null) {
              request.response.headers.set(HttpHeaders.etagHeader, currentEtag);
            }
            if (currentLastModified != null) {
              request.response.headers.set(
                HttpHeaders.lastModifiedHeader,
                currentLastModified,
              );
            }
            await request.response.close();
            return;
          }
          get200Count++;
          request.response.statusCode = HttpStatus.ok;
          if (currentEtag != null) {
            request.response.headers.set(HttpHeaders.etagHeader, currentEtag);
          }
          if (currentLastModified != null) {
            request.response.headers.set(
              HttpHeaders.lastModifiedHeader,
              currentLastModified,
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
          if (serverEtag case final activeEtag?
              when !activeEtag.startsWith('W/')) {
            const nextEtag = '"etag-v2"';
            serverEtag = nextEtag;
            request.response.headers.set(HttpHeaders.etagHeader, nextEtag);
          }
          const nextLastModified = 'Mon, 09 Nov 2026 22:05:00 GMT';
          serverLastModified = nextLastModified;
          request.response.headers.set(
            HttpHeaders.lastModifiedHeader,
            nextLastModified,
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
        language: AppLanguage.english,
      );
      final repository = WebDavRepository(config: config);

      // 1. Initial GET returns 200 OK and caches ETag and Last-Modified.
      final firstBody = await repository.fetchTdf();
      expect(firstBody, equals('tdf 0.8.0\n# v1\n'));
      expect(repository.lastFetchWasNotModified, isFalse);
      expect(repository.cachedExists, isTrue);
      expect(repository.cachedEtag, equals('"etag-v1"'));
      expect(
        repository.cachedLastModified,
        equals('Mon, 09 Nov 2026 22:00:00 GMT'),
      );
      expect(get200Count, equals(1));
      expect(get304Count, equals(0));

      // 2. Second GET sends If-None-Match and If-Modified-Since, receives 304 Not Modified, and returns cached content.
      final secondBody = await repository.fetchTdf();
      expect(secondBody, equals('tdf 0.8.0\n# v1\n'));
      expect(repository.lastFetchWasNotModified, isTrue);
      expect(receivedIfNoneMatch, equals('"etag-v1"'));
      expect(receivedIfModifiedSince, equals('Mon, 09 Nov 2026 22:00:00 GMT'));
      expect(get200Count, equals(1));
      expect(get304Count, equals(1));

      // 3. PUT sends If-Match: "etag-v1" and updates cachedEtag to "etag-v2".
      await repository.saveTdf('tdf 0.8.0\n# v2\n');
      expect(receivedIfMatch, equals('"etag-v1"'));
      expect(repository.cachedExists, isTrue);
      expect(repository.cachedEtag, equals('"etag-v2"'));
      expect(
        repository.cachedLastModified,
        equals('Mon, 09 Nov 2026 22:05:00 GMT'),
      );

      // 4. Subsequent GET uses "etag-v2" from PUT response and receives 304 Not Modified without redownloading.
      final thirdBody = await repository.fetchTdf();
      expect(thirdBody, equals('tdf 0.8.0\n# v2\n'));
      expect(repository.lastFetchWasNotModified, isTrue);
      expect(receivedIfNoneMatch, equals('"etag-v2"'));
      expect(get200Count, equals(1));
      expect(get304Count, equals(2));

      // 5. Simulate concurrent external modification on server ("etag-v3"); PUT with stale "etag-v2" throws 412 and clears cached ETag + cachedExists.
      serverContent = 'tdf 0.8.0\n# v3-external\n';
      serverEtag = '"etag-v3"';
      await expectLater(
        () => repository.saveTdf('tdf 0.8.0\n# v2-local-conflict\n'),
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
      expect(
        repository.cachedLastModified,
        isNull,
        reason: 'HTTP 412 must invalidate stale cached Last-Modified',
      );
      expect(
        repository.cachedExists,
        isNull,
        reason: 'HTTP 412 must reset cachedExists to null',
      );

      // 6. Next GET after 412 fetches unconditionally (200 OK) and obtains "etag-v3".
      final fourthBody = await repository.fetchTdf();
      expect(fourthBody, equals('tdf 0.8.0\n# v3-external\n'));
      expect(repository.lastFetchWasNotModified, isFalse);
      expect(repository.cachedExists, isTrue);
      expect(repository.cachedEtag, equals('"etag-v3"'));
      expect(get200Count, equals(2));

      // 7. Weak ETag sends If-None-Match on GET, but omits If-Match on PUT.
      serverEtag = 'W/"weak-v4"';
      serverContent = 'tdf 0.8.0\n# v4-weak\n';
      repository.clearCache();
      expect(repository.cachedExists, isNull);
      await repository.fetchTdf();
      expect(repository.cachedEtag, equals('W/"weak-v4"'));
      await repository.fetchTdf();
      expect(repository.lastFetchWasNotModified, isTrue);
      expect(receivedIfNoneMatch, equals('W/"weak-v4"'));
      await repository.saveTdf('tdf 0.8.0\n# v5\n');
      expect(
        receivedIfMatch,
        isNull,
        reason: 'Weak ETag must not be sent in If-Match header on PUT',
      );

      // 8. Server with only Last-Modified (no ETag) evaluates 304 via If-Modified-Since.
      serverEtag = null;
      serverLastModified = 'Mon, 09 Nov 2026 22:10:00 GMT';
      serverContent = 'tdf 0.8.0\n# v6-lastmod-only\n';
      repository.clearCache();
      expect(repository.cachedExists, isNull);
      repository.seedCacheIfEmpty(
        lastModified: 'Mon, 09 Nov 2026 22:10:00 GMT',
        content: 'tdf 0.8.0\n# v6-lastmod-only\n',
      );
      expect(
        repository.cachedExists,
        isTrue,
        reason: 'seedCacheIfEmpty must mark cachedExists as true',
      );
      final seededBody = await repository.fetchTdf();
      expect(seededBody, equals('tdf 0.8.0\n# v6-lastmod-only\n'));
      expect(repository.lastFetchWasNotModified, isTrue);
      expect(receivedIfModifiedSince, equals('Mon, 09 Nov 2026 22:10:00 GMT'));
    });

    test('enforces tri-state cachedExists transitions for fresh PUT, 404 -> If-None-Match: *, ETag-less 201/204 creation (DECISION-15), strong ETag creation, 412, clearCache, and wipeTdf', () async {
      AppLogger.setEnabled(true, persistToDisk: false);
      final casServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => casServer.close(force: true));

      var fileExistsOnServer = false;
      var serverBody = '';
      String? responsePutEtag;
      var responsePutStatus = HttpStatus.created;
      var rejectPutWith412 = false;
      String? lastPutIfMatch;
      String? lastPutIfNoneMatch;

      casServer.listen((HttpRequest request) async {
        if (request.method == 'GET') {
          if (!fileExistsOnServer) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.statusCode = HttpStatus.ok;
            if (responsePutEtag case final etag?) {
              request.response.headers.set(HttpHeaders.etagHeader, etag);
            }
            request.response.write(serverBody);
          }
          await request.response.close();
          return;
        }
        if (request.method == 'PUT') {
          lastPutIfMatch = request.headers.value(HttpHeaders.ifMatchHeader);
          lastPutIfNoneMatch = request.headers.value(
            HttpHeaders.ifNoneMatchHeader,
          );
          final body = await utf8.decoder.bind(request).join();
          if (rejectPutWith412) {
            request.response.statusCode = HttpStatus.preconditionFailed;
            await request.response.close();
            return;
          }
          fileExistsOnServer = true;
          serverBody = body;
          request.response.statusCode = responsePutStatus;
          if (responsePutEtag case final etag?) {
            request.response.headers.set(HttpHeaders.etagHeader, etag);
          }
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
      });

      final config = WebDavConfig(
        serverUrl: 'http://${casServer.address.host}:${casServer.port}',
        username: 'stefan',
        password: 'secret',
        filePath: 'tri_state.tdf',
        language: AppLanguage.english,
      );

      // 1. Fresh WebDavRepository (cachedExists == null) sends NEITHER If-Match NOR If-None-Match.
      final freshRepo = WebDavRepository(config: config);
      expect(freshRepo.cachedExists, isNull);
      responsePutStatus = HttpStatus.noContent;
      responsePutEtag = null;
      await freshRepo.saveTdf('tdf 0.8.0\n# fresh\n');
      expect(
        lastPutIfMatch,
        isNull,
        reason: 'Fresh repo (cachedExists == null) must omit If-Match',
      );
      expect(
        lastPutIfNoneMatch,
        isNull,
        reason: 'Fresh repo (cachedExists == null) must omit If-None-Match',
      );
      expect(freshRepo.cachedExists, isTrue);

      // 2. 404 Not Found sets cachedExists == false; subsequent PUT sends If-None-Match: *.
      //    When 201 Created / 204 No Content omits an ETag header, cachedExists transitions
      //    immediately to true so a second saveTdf does NOT send If-None-Match: * (DECISION-15).
      fileExistsOnServer = false;
      freshRepo.clearCache();
      expect(freshRepo.cachedExists, isNull);

      expect(await freshRepo.fetchTdf(), isEmpty);
      expect(
        freshRepo.cachedExists,
        isFalse,
        reason: 'GET 404 must set cachedExists to false',
      );

      responsePutStatus = HttpStatus.created;
      responsePutEtag = null;
      await freshRepo.saveTdf('tdf 0.8.0\n# created-no-etag\n');
      expect(
        lastPutIfNoneMatch,
        equals('*'),
        reason: 'Initial PUT after 404 must send If-None-Match: *',
      );
      expect(lastPutIfMatch, isNull);
      expect(
        freshRepo.cachedExists,
        isTrue,
        reason: '201 Created without ETag must still transition cachedExists to true',
      );
      expect(freshRepo.cachedEtag, isNull);
      expect(AppLogger.fullLogText, contains('ifNoneMatch=*'));

      responsePutStatus = HttpStatus.noContent;
      await freshRepo.saveTdf('tdf 0.8.0\n# second-put-no-etag\n');
      expect(
        lastPutIfNoneMatch,
        isNull,
        reason: 'Second PUT after ETag-less creation must NOT resend If-None-Match: *',
      );
      expect(lastPutIfMatch, isNull);
      expect(freshRepo.cachedExists, isTrue);

      // 3. 404 -> saveTdf returning 201 Created WITH strong ETag "v1" transitions cachedExists to true
      //    and second saveTdf sends If-Match: "v1" without If-None-Match.
      fileExistsOnServer = false;
      freshRepo.clearCache();
      expect(await freshRepo.fetchTdf(), isEmpty);
      expect(freshRepo.cachedExists, isFalse);

      responsePutStatus = HttpStatus.created;
      responsePutEtag = '"v1"';
      await freshRepo.saveTdf('tdf 0.8.0\n# created-with-v1\n');
      expect(lastPutIfNoneMatch, equals('*'));
      expect(lastPutIfMatch, isNull);
      expect(freshRepo.cachedExists, isTrue);
      expect(freshRepo.cachedEtag, equals('"v1"'));

      responsePutStatus = HttpStatus.noContent;
      responsePutEtag = '"v2"';
      await freshRepo.saveTdf('tdf 0.8.0\n# updated-from-v1\n');
      expect(
        lastPutIfMatch,
        equals('"v1"'),
        reason:
            'Second PUT after strong ETag creation must send If-Match: "v1"',
      );
      expect(
        lastPutIfNoneMatch,
        isNull,
        reason: 'PUT when cachedExists == true must omit If-None-Match',
      );
      expect(freshRepo.cachedEtag, equals('"v2"'));
      expect(AppLogger.fullLogText, contains(r'ifMatch="\"v1\""'));

      // 4. HTTP 412 Precondition Failed resets cachedExists to null alongside cachedEtag and cachedLastModified.
      rejectPutWith412 = true;
      await expectLater(
        () => freshRepo.saveTdf('tdf 0.8.0\n# conflict\n'),
        throwsA(
          isA<WebDavException>().having(
            (e) => e.isPreconditionFailed,
            'isPreconditionFailed',
            isTrue,
          ),
        ),
      );
      expect(freshRepo.cachedExists, isNull);
      expect(freshRepo.cachedEtag, isNull);
      expect(freshRepo.cachedLastModified, isNull);

      // 5. seedCacheIfEmpty sets cachedExists to true, and wipeTdf resets cachedExists to null.
      rejectPutWith412 = false;
      freshRepo.seedCacheIfEmpty(
        etag: '"seeded"',
        content: 'tdf 0.8.0\n# seeded\n',
      );
      expect(freshRepo.cachedExists, isTrue);
      expect(freshRepo.cachedEtag, equals('"seeded"'));

      responsePutEtag = null;
      await freshRepo.wipeTdf();
      expect(
        freshRepo.cachedExists,
        isNull,
        reason: 'wipeTdf must reset cachedExists to null',
      );
      expect(freshRepo.cachedEtag, isNull);
      expect(freshRepo.cachedLastModified, isNull);
    });

    test('preserves multi-workspace secret redaction, attaches exception cause without leaking raw error text, and logs WARN on deleteLog HTTP 500', () async {
      AppLogger.setEnabled(true, persistToDisk: false);

      const firstSecret = 'FirstWorkspaceSecret#111';
      const secondSecret = 'SecondWorkspaceSecret#222';
      final firstRepo = WebDavRepository(
        config: WebDavConfig(
          serverUrl: 'http://${server.address.host}:${server.port}',
          username: 'alice',
          password: firstSecret,
          filePath: 'one.tdf',
          language: AppLanguage.english,
        ),
      );
      final secondRepo = WebDavRepository(
        config: WebDavConfig(
          serverUrl: 'http://${server.address.host}:${server.port}',
          username: 'bob',
          password: secondSecret,
          filePath: 'two.tdf',
          language: AppLanguage.english,
        ),
      );
      expect(firstRepo.config.password, equals(firstSecret));
      expect(secondRepo.config.password, equals(secondSecret));

      final sanitized = AppLogger.sanitize(
        'leak check: $firstSecret and $secondSecret',
      );
      expect(
        sanitized,
        isNot(contains(firstSecret)),
        reason: 'Constructing a second WebDavRepository must keep first workspace password redacted',
      );
      expect(
        sanitized,
        isNot(contains(secondSecret)),
        reason: 'Second WebDavRepository password must also be redacted',
      );

      // Verify WebDavException exposes cause on SocketException and TimeoutException.
      final deadServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = deadServer.port;
      await deadServer.close(force: true);
      final unreachableRepo = WebDavRepository(
        config: WebDavConfig(
          serverUrl: 'http://127.0.0.1:$deadPort',
          username: 'alice',
          password: firstSecret,
          filePath: 'one.tdf',
          language: AppLanguage.english,
        ),
      );
      await expectLater(
        unreachableRepo.fetchTdf,
        throwsA(
          isA<WebDavException>().having(
            (e) => e.cause,
            'cause',
            isA<SocketException>(),
          ),
        ),
        reason: 'SocketException must be preserved as WebDavException.cause',
      );

      // Verify malformed HTTP response produces sanitized message without leaking raw exception text, while preserving cause.
      final malformedServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(malformedServer.close);
      malformedServer.listen((socket) {
        socket.write('INVALID_HTTP_GARBAGE_TOKEN_98765\r\n\r\n');
        socket.destroy();
      });
      final malformedRepo = WebDavRepository(
        config: WebDavConfig(
          serverUrl:
              'http://${malformedServer.address.host}:${malformedServer.port}',
          username: 'alice',
          password: firstSecret,
          filePath: 'broken.tdf',
          language: AppLanguage.english,
        ),
      );
      await expectLater(
        malformedRepo.fetchTdf,
        throwsA(
          isA<WebDavException>()
              .having((e) => e.cause, 'cause', isNotNull)
              .having(
                (e) => e.message,
                'message',
                allOf(
                  isNot(contains('HttpException')),
                  isNot(contains('INVALID_HTTP_GARBAGE_TOKEN_98765')),
                ),
              ),
        ),
        reason: 'Unexpected GET failure must preserve cause and avoid raw error.toString() in user message',
      );
      await expectLater(
        () => malformedRepo.saveTdf('tdf 0.8.0\n'),
        throwsA(
          isA<WebDavException>()
              .having((e) => e.cause, 'cause', isNotNull)
              .having(
                (e) => e.message,
                'message',
                allOf(
                  isNot(contains('HttpException')),
                  isNot(contains('INVALID_HTTP_GARBAGE_TOKEN_98765')),
                ),
              ),
        ),
        reason: 'Unexpected PUT failure must preserve cause and avoid raw error.toString() in user message',
      );

      // Verify deleteLog stays best-effort on HTTP 500 and emits a structured WARN event with status=500.
      final errorDeleteServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => errorDeleteServer.close(force: true));
      errorDeleteServer.listen((request) async {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      });
      final deleteLogRepo = WebDavRepository(
        config: WebDavConfig(
          serverUrl:
              'http://${errorDeleteServer.address.host}:${errorDeleteServer.port}',
          username: 'alice',
          password: firstSecret,
          language: AppLanguage.english,
        ),
      );
      await deleteLogRepo.deleteLog('tiertask_2026-11-03_linux_tasks.log');
      expect(
        AppLogger.fullLogText,
        contains('[WARN ] [STORAGE  ] webdav.log_delete |'),
        reason: 'deleteLog HTTP 500 must emit a WARN diagnostic event',
      );
      expect(
        AppLogger.fullLogText,
        contains('status=500'),
        reason: 'deleteLog HTTP 500 WARN event must include structured status=500 field',
      );
    });

    test('pools HttpClient across healthy requests, resets on timeout or oversized abort, supports close(), and logs UTF-8 byte counts on GET', () async {
      AppLogger.setEnabled(true, persistToDisk: false);
      const remotePath = '/remote.php/dav/files/stefan/pooled.tdf';
      const utf8Payload = 'tdf 0.8.0\n# Ümlaut 🚀\n';
      final expectedUtf8Bytes = utf8.encode(utf8Payload).length;
      expect(expectedUtf8Bytes, greaterThan(utf8Payload.length));
      remoteFiles[remotePath] = utf8Payload;

      var clientCreateCount = 0;
      final config = WebDavConfig(
        serverUrl: 'http://${server.address.host}:${server.port}',
        username: 'stefan',
        password: 'secret',
        filePath: 'pooled.tdf',
        language: AppLanguage.english,
      );
      final repository = WebDavRepository(
        config: config,
        maxFileBytes: 64,
        timeout: const Duration(milliseconds: 100),
        clientFactory: () {
          clientCreateCount++;
          return HttpClient();
        },
      );
      addTearDown(() => repository.close(force: true));

      // Multiple healthy operations reuse one pooled HttpClient.
      expect(await repository.fetchTdf(), equals(utf8Payload));
      expect(
        AppLogger.fullLogText,
        contains('bytes=$expectedUtf8Bytes'),
        reason:
            'GET log must record UTF-8 byte count rather than UTF-16 length',
      );
      await repository.saveTdf(utf8Payload);
      forcedGetStatus = HttpStatus.internalServerError;
      await expectLater(repository.fetchTdf, throwsA(isA<WebDavException>()));
      forcedGetStatus = HttpStatus.ok;
      await repository.deleteLog('tiertask_2026-11-03_linux_tasks.log');
      expect(
        clientCreateCount,
        equals(1),
        reason: 'Healthy requests and drained error responses must reuse one pooled HttpClient',
      );

      // Explicit close() releases the pool so the next request creates a new client.
      repository.close();
      expect(await repository.fetchTdf(), equals(utf8Payload));
      expect(clientCreateCount, equals(2));

      // Oversized response resets the pooled client so subsequent valid calls recover cleanly.
      remoteFiles[remotePath] = 'x' * 80;
      await expectLater(repository.fetchTdf, throwsA(isA<WebDavException>()));
      remoteFiles[remotePath] = utf8Payload;
      expect(await repository.fetchTdf(), equals(utf8Payload));
      expect(
        clientCreateCount,
        equals(3),
        reason: 'Oversized abort must reset the pooled HttpClient',
      );

      // Timeout resets the pooled client cleanly.
      responseDelay = const Duration(milliseconds: 220);
      await expectLater(repository.fetchTdf, throwsA(isA<WebDavException>()));
      responseDelay = Duration.zero;
      expect(await repository.fetchTdf(), equals(utf8Payload));
      expect(
        clientCreateCount,
        equals(4),
        reason: 'Timeout must tear down stalled client and recreate pool on next call',
      );
    });

    test('enforces single overall wall-clock deadline against Slowloris trickles and handles redirects safely', () async {
      // 1. Slowloris trickle server: sends 1 byte every 35ms (less than timeout=110ms per chunk, but total > 110ms).
      final slowServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => slowServer.close(force: true));
      slowServer.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.bufferOutput = false;
        try {
          for (var i = 0; i < 20; i++) {
            request.response.add(const <int>[0x61]);
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 35));
          }
          await request.response.close();
        } on Object {
          // Client aborted stalled connection as expected.
        }
      });

      final slowRepo = WebDavRepository(
        config: WebDavConfig(
          serverUrl: 'http://${slowServer.address.host}:${slowServer.port}',
          username: 'stefan',
          password: 'secret',
          filePath: 'slow.tdf',
          language: AppLanguage.english,
        ),
        timeout: const Duration(milliseconds: 110),
      );
      addTearDown(() => slowRepo.close(force: true));
      final watch = Stopwatch()..start();
      await expectLater(
        slowRepo.fetchTdf,
        throwsA(
          isA<WebDavException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
        reason: 'Slowloris trickle must be aborted by single overall wall-clock deadline',
      );
      expect(
        watch.elapsedMilliseconds,
        lessThan(450),
        reason: 'Slowloris abort must not wait for all 20 chunks (700ms+)',
      );

      // 2. Redirects: same-origin keeps Authorization, cross-origin strips Authorization, >5 hops rejected.
      final targetServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => targetServer.close(force: true));
      String? crossOriginReceivedAuth;
      targetServer.listen((HttpRequest request) async {
        crossOriginReceivedAuth = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        request.response.statusCode = HttpStatus.ok;
        request.response.write('tdf 0.8.0\n# cross-origin\n');
        await request.response.close();
      });

      final redirectServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => redirectServer.close(force: true));
      String? sameOriginTargetAuth;
      redirectServer.listen((HttpRequest request) async {
        final path = request.uri.path;
        if (path.endsWith('/same.tdf')) {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '/same-target.tdf',
          );
          await request.response.close();
          return;
        }
        if (path == '/same-target.tdf') {
          sameOriginTargetAuth = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          request.response.statusCode = HttpStatus.ok;
          request.response.write('tdf 0.8.0\n# same-origin\n');
          await request.response.close();
          return;
        }
        if (path.endsWith('/cross.tdf')) {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            'http://${targetServer.address.host}:${targetServer.port}/final.tdf',
          );
          await request.response.close();
          return;
        }
        if (path.endsWith('/loop.tdf') || path.startsWith('/hop-')) {
          final currentHop = path.startsWith('/hop-')
              ? int.parse(path.substring(5))
              : 0;
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '/hop-${currentHop + 1}',
          );
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final sameOriginRepo = WebDavRepository(
        config: WebDavConfig(
          serverUrl:
              'http://${redirectServer.address.host}:${redirectServer.port}',
          username: 'stefan',
          password: 'secret',
          filePath: 'same.tdf',
          language: AppLanguage.english,
        ),
      );
      addTearDown(() => sameOriginRepo.close(force: true));
      expect(
        await sameOriginRepo.fetchTdf(),
        equals('tdf 0.8.0\n# same-origin\n'),
      );
      expect(
        sameOriginTargetAuth,
        startsWith('Basic '),
        reason: 'Same-origin redirect must preserve Basic Authorization header',
      );

      final crossOriginRepo = WebDavRepository(
        config: WebDavConfig(
          serverUrl:
              'http://${redirectServer.address.host}:${redirectServer.port}',
          username: 'stefan',
          password: 'secret',
          filePath: 'cross.tdf',
          language: AppLanguage.english,
        ),
      );
      addTearDown(() => crossOriginRepo.close(force: true));
      expect(
        await crossOriginRepo.fetchTdf(),
        equals('tdf 0.8.0\n# cross-origin\n'),
      );
      expect(
        crossOriginReceivedAuth,
        isNull,
        reason: 'Cross-origin redirect must strip Authorization header',
      );

      final loopRepo = WebDavRepository(
        config: WebDavConfig(
          serverUrl:
              'http://${redirectServer.address.host}:${redirectServer.port}',
          username: 'stefan',
          password: 'secret',
          filePath: 'loop.tdf',
          language: AppLanguage.english,
        ),
      );
      addTearDown(() => loopRepo.close(force: true));
      await expectLater(
        loopRepo.fetchTdf,
        throwsA(isA<WebDavException>()),
        reason: 'Redirect chains exceeding 5 hops must be rejected',
      );

      // 3. HTTPS -> HTTP cleartext downgrade redirect must be rejected before touching HTTP host.
      final visitedUris = <Uri>[];
      var sawFollowRedirectsFalse = false;
      final downgradeRepo = WebDavRepository(
        config: const WebDavConfig(
          serverUrl: 'https://secure.example.com',
          username: 'stefan',
          password: 'secret',
          language: AppLanguage.english,
        ),
        clientFactory: () => _RedirectDowngradeStubHttpClient(
          onRequest: (uri, followRedirects) {
            visitedUris.add(uri);
            sawFollowRedirectsFalse = !followRedirects;
          },
          redirectLocation: 'http://insecure.example.com/tasks.tdf',
        ),
      );
      addTearDown(() => downgradeRepo.close(force: true));
      await expectLater(
        downgradeRepo.fetchTdf,
        throwsA(isA<WebDavException>()),
        reason: 'HTTPS-to-HTTP cleartext redirect downgrade must be rejected',
      );
      expect(
        sawFollowRedirectsFalse,
        isTrue,
        reason: 'GET requests must disable automatic followRedirects',
      );
      expect(
        visitedUris,
        hasLength(1),
        reason: 'Client must never issue an HTTP request after rejecting downgrade redirect',
      );
    });

    test('re-acquires fresh pooled HttpClient after oversized redirect body triggers pool reset', () async {
      final bigRedirectServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => bigRedirectServer.close(force: true));

      bigRedirectServer.listen((HttpRequest request) async {
        if (request.uri.path.endsWith('/big-redirect.tdf')) {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '/final-after-big-redirect.tdf',
          );
          // Body > 64 KiB (_maxDrainBytes) forces _drainResponseSafely to close the pooled client.
          request.response.write('X' * 70000);
          await request.response.close();
          return;
        }
        if (request.uri.path == '/final-after-big-redirect.tdf') {
          request.response.statusCode = HttpStatus.ok;
          request.response.write('tdf 0.8.0\n# recovered-hop\n');
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      var clientCreateCount = 0;
      final repository = WebDavRepository(
        config: WebDavConfig(
          serverUrl:
              'http://${bigRedirectServer.address.host}:${bigRedirectServer.port}',
          username: 'stefan',
          password: 'secret',
          filePath: 'big-redirect.tdf',
          language: AppLanguage.english,
        ),
        clientFactory: () {
          clientCreateCount++;
          return HttpClient();
        },
      );
      addTearDown(() => repository.close(force: true));

      final body = await repository.fetchTdf();
      expect(
        body,
        equals('tdf 0.8.0\n# recovered-hop\n'),
        reason: 'Redirect hop after pool reset must succeed with a fresh HttpClient',
      );
      expect(
        clientCreateCount,
        equals(2),
        reason: 'Oversized redirect body must reset pool and acquire a second HttpClient for hop 1',
      );
    });

    test('rejects poisoned header values in _normalizeHeaderValue and aborts unclosed requests on pre-close exceptions', () async {
      const poisonedValues = <String>[
        '"etag"\r\nX-Injected: 1',
        '"etag"\n',
        '\r"etag"',
        '"etag\x00null"',
        '"etag\tcontrol"',
        '"etag\x7Fdel"',
        '"etag\u0085nel"',
        '"etag\u009Fc1"',
        '"etag\u0100non-latin1"',
        '"etag🚀"',
      ];

      for (final poisoned in poisonedValues) {
        expect(
          WebDavRepository.isStrongEtag(poisoned),
          isFalse,
          reason: 'Poisoned ETag "$poisoned" must be rejected by isStrongEtag',
        );
      }

      final seededRepo = WebDavRepository(
        config: WebDavConfig(
          serverUrl: 'http://${server.address.host}:${server.port}',
          username: 'stefan',
          password: 'secret',
          filePath: 'poison.tdf',
          language: AppLanguage.english,
        ),
      );
      for (final poisoned in poisonedValues) {
        seededRepo.seedCacheIfEmpty(
          etag: poisoned,
          lastModified: poisoned,
          content: 'tdf 0.8.0\n',
        );
        expect(
          seededRepo.cachedEtag,
          isNull,
          reason: 'seedCacheIfEmpty must drop poisoned ETag "$poisoned"',
        );
        expect(
          seededRepo.cachedLastModified,
          isNull,
          reason:
              'seedCacheIfEmpty must drop poisoned Last-Modified "$poisoned"',
        );
      }

      // Exception raised between openUrl/putUrl and request.close() must abort request and force-close client.
      var abortedCount = 0;
      var clientForceClosedCount = 0;
      final abortRepo = WebDavRepository(
        config: const WebDavConfig(
          serverUrl: 'https://secure.example.com',
          username: 'stefan',
          password: 'secret',
          language: AppLanguage.english,
        ),
        clientFactory: () => _ThrowingHeaderStubHttpClient(
          onAbort: () => abortedCount++,
          onForceClose: () => clientForceClosedCount++,
        ),
      );

      await expectLater(abortRepo.fetchTdf, throwsA(isA<WebDavException>()));
      expect(
        abortedCount,
        equals(1),
        reason: 'GET error before request.close() must abort the open request',
      );
      expect(
        clientForceClosedCount,
        equals(1),
        reason: 'GET error before request.close() must reset the pooled client',
      );

      await expectLater(
        () => abortRepo.saveTdf('tdf 0.8.0\n'),
        throwsA(isA<WebDavException>()),
      );
      expect(
        abortedCount,
        equals(2),
        reason: 'PUT error before request.close() must abort the open request',
      );
      expect(
        clientForceClosedCount,
        equals(2),
        reason: 'PUT error before request.close() must reset the pooled client',
      );
    });

    test('enforces maxFileBytes on saveTdf BEFORE encoding, sending PUT, or updating conditional cache', () async {
      const remotePath = '/remote.php/dav/files/stefan/bounded_put.tdf';
      final repository = WebDavRepository(
        config: WebDavConfig(
          serverUrl: 'http://${server.address.host}:${server.port}',
          username: 'stefan',
          password: 'secret',
          filePath: 'bounded_put.tdf',
          language: AppLanguage.english,
        ),
        maxFileBytes: 64,
      );
      addTearDown(() => repository.close(force: true));

      // Exact 64 ASCII bytes and exact 64 UTF-8 bytes (16 x 4-byte scalar) succeed.
      final exactAscii = 'a' * 64;
      await repository.saveTdf(exactAscii);
      expect(putCount, equals(1));
      expect(remoteFiles[remotePath], equals(exactAscii));

      final exactEmoji = '🚀' * 16;
      expect(utf8.encode(exactEmoji).length, equals(64));
      await repository.saveTdf(exactEmoji);
      expect(putCount, equals(2));

      // 65 ASCII bytes, 66 UTF-8 bytes ('€' * 22 -> length 22 <= 64), and 68 UTF-8 bytes ('🚀' * 17) must fail BEFORE HTTP PUT.
      putCount = 0;
      for (final oversized in <String>['a' * 65, '€' * 22, '🚀' * 17]) {
        await expectLater(
          () => repository.saveTdf(oversized),
          throwsA(
            isA<WebDavException>().having(
              (error) => error.message,
              'message',
              contains('maximum allowed size'),
            ),
          ),
          reason:
              'Oversized PUT payload (${utf8.encode(oversized).length} bytes) must throw before sending',
        );
      }
      expect(
        putCount,
        equals(0),
        reason: 'Oversized saveTdf must never issue an HTTP PUT request',
      );
      expect(
        remoteFiles[remotePath],
        equals(exactEmoji),
        reason: 'Oversized saveTdf must leave remote file and cache untouched',
      );
    });
  });
}

class _ThrowingHeaderStubHttpClient implements HttpClient {
  _ThrowingHeaderStubHttpClient({
    required this.onAbort,
    required this.onForceClose,
  });

  final void Function() onAbort;
  final void Function() onForceClose;

  @override
  Duration? connectionTimeout;

  @override
  void close({bool force = false}) {
    if (force) {
      onForceClose();
    }
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _ThrowingHeaderStubRequest(uri: url, onAbort: onAbort);

  @override
  Future<HttpClientRequest> putUrl(Uri url) async =>
      _ThrowingHeaderStubRequest(uri: url, onAbort: onAbort);

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _ThrowingHeaderStubRequest implements HttpClientRequest {
  _ThrowingHeaderStubRequest({required this.uri, required this.onAbort});

  @override
  bool followRedirects = true;

  @override
  final HttpHeaders headers = _ThrowingHttpHeaders();

  final void Function() onAbort;

  @override
  final Uri uri;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    onAbort();
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _ThrowingHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    throw const FormatException('Simulated header failure before close');
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _RedirectDowngradeStubHttpClient implements HttpClient {
  _RedirectDowngradeStubHttpClient({
    required this.onRequest,
    required this.redirectLocation,
  });

  final void Function(Uri uri, bool followRedirects) onRequest;
  final String redirectLocation;

  @override
  Duration? connectionTimeout;

  @override
  void close({bool force = false}) {}

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _StubHttpClientRequest(
      uri: url,
      onClose: (followRedirects) => onRequest(url, followRedirects),
      redirectLocation: redirectLocation,
    );
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _StubHttpClientRequest implements HttpClientRequest {
  _StubHttpClientRequest({
    required this.uri,
    required this.onClose,
    required this.redirectLocation,
  });

  @override
  bool followRedirects = true;

  @override
  final HttpHeaders headers = _StubHttpHeaders();

  final void Function(bool followRedirects) onClose;
  final String redirectLocation;

  @override
  final Uri uri;

  @override
  Future<HttpClientResponse> close() async {
    onClose(followRedirects);
    return _StubRedirectHttpClientResponse(redirectLocation);
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _StubRedirectHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _StubRedirectHttpClientResponse(String location)
    : headers = _StubHttpHeaders(
        initial: <String, String>{HttpHeaders.locationHeader: location},
      );

  @override
  final HttpHeaders headers;

  @override
  int get contentLength => 0;

  @override
  bool get isRedirect => true;

  @override
  int get statusCode => HttpStatus.found;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => const Stream<List<int>>.empty().listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _StubHttpHeaders implements HttpHeaders {
  _StubHttpHeaders({Map<String, String>? initial})
    : _values = <String, String>{
        if (initial != null)
          for (final entry in initial.entries)
            entry.key.toLowerCase(): entry.value,
      };

  final Map<String, String> _values;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) => _values[name.toLowerCase()];

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
