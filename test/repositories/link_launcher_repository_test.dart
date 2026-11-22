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

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/repositories/link_launcher_repository.dart';
import 'package:tiertask/services/app_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlatformLinkLauncherRepository & FakeLinkLauncherRepository', () {
    String? lastLaunchedUri;
    var channelResult = true;
    var shouldThrowPlatformException = false;

    setUp(() {
      lastLaunchedUri = null;
      channelResult = true;
      shouldThrowPlatformException = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PlatformLinkLauncherRepository.linkLauncherChannel,
            (call) async {
              if (call.method == 'openLink') {
                if (shouldThrowPlatformException) {
                  throw PlatformException(
                    code: 'LAUNCH_FAILED',
                    message: 'No application registered for URI',
                  );
                }
                final arguments = call.arguments;
                if (arguments is Map<Object?, Object?>) {
                  final rawUri = arguments['uri'];
                  if (rawUri is String) {
                    lastLaunchedUri = rawUri;
                  }
                }
                return channelResult;
              }
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PlatformLinkLauncherRepository.linkLauncherChannel,
            null,
          );
    });

    test('dispatches valid URI to native method channel', () async {
      const repository = PlatformLinkLauncherRepository();
      await repository.openLink('  https://example.com/docs?v=1  ');
      expect(
        lastLaunchedUri,
        equals('https://example.com/docs?v=1'),
        reason: 'Trimmed valid URI must be sent to native openLink channel',
      );
    });

    test('rejects invalid schemes, control characters, and overlong URIs before calling platform channel', () async {
      const repository = PlatformLinkLauncherRepository();
      final overlongUri = 'https://example.com/${'a' * TaskLink.maxUriLength}';

      for (final invalidUri in [
        '',
        '   ',
        'example.com/no-scheme',
        '123://bad-scheme',
        'https://example.com/bad\nchar',
        'https://example.com/bad\x00null',
        overlongUri,
      ]) {
        await expectLater(
          () => repository.openLink(invalidUri),
          throwsA(isA<LinkLaunchException>()),
          reason: 'Invalid URI "$invalidUri" must throw LinkLaunchException',
        );
      }
      expect(
        lastLaunchedUri,
        isNull,
        reason: 'Invalid URIs must never reach the native platform channel',
      );
    });

    test('throws LinkLaunchException when native channel returns false or throws PlatformException', () async {
      const repository = PlatformLinkLauncherRepository();
      channelResult = false;
      await expectLater(
        () => repository.openLink('https://example.com'),
        throwsA(isA<LinkLaunchException>()),
        reason: 'Channel returning false must throw LinkLaunchException',
      );

      channelResult = true;
      shouldThrowPlatformException = true;
      await expectLater(
        () => repository.openLink('https://example.com'),
        throwsA(
          isA<LinkLaunchException>().having(
            (error) => error.cause,
            'cause',
            isA<PlatformException>(),
          ),
        ),
        reason: 'PlatformException must be wrapped in LinkLaunchException preserving cause',
      );
    });

    test('FakeLinkLauncherRepository records launched URIs and supports failure simulation', () async {
      final fake = FakeLinkLauncherRepository();
      await fake.openLink('mailto:ops@example.com');
      expect(fake.launchedUris, equals(['mailto:ops@example.com']));

      fake.shouldThrow = true;
      await expectLater(
        () => fake.openLink('https://example.com'),
        throwsA(isA<LinkLaunchException>()),
      );
    });

    test('isLaunchableUri permits valid RFC 3986 custom schemes and rejects blocked schemes, backslashes, and Unicode BiDi controls', () async {
      const allowedUris = <String>[
        'https://example.com/path?q=1#top',
        '  http://localhost:8080/board  ',
        'HTTPS://EXAMPLE.COM/UPPER',
        'mailto:ops@example.com',
        'tel:+49123456789',
        'geo:48.137154,11.576124',
        'obsidian://open?vault=Notes&file=Task',
        'notion://www.notion.so/page-id',
        'vscode://file/home/user/project/main.dart',
        'custom+scheme-1.0://resource/item',
      ];

      const platformRepo = PlatformLinkLauncherRepository();
      final fakeRepo = FakeLinkLauncherRepository();

      for (final uri in allowedUris) {
        expect(
          LinkLauncherRepository.isLaunchableUri(uri),
          isTrue,
          reason: 'Allowed URI "$uri" must pass isLaunchableUri',
        );
        await platformRepo.openLink(uri);
        expect(
          lastLaunchedUri,
          equals(uri.trim()),
          reason: 'Allowed URI "$uri" must reach native channel',
        );
        await fakeRepo.openLink(uri);
      }
      expect(
        fakeRepo.launchedUris,
        equals(allowedUris.map((uri) => uri.trim()).toList()),
      );

      lastLaunchedUri = null;
      fakeRepo.launchedUris.clear();

      const blockedSchemes = <String>[
        'javascript',
        'vbscript',
        'jscript',
        'livescript',
        'data',
        'blob',
        'about',
        'view-source',
        'file',
        'smb',
        'cifs',
        'nfs',
        'jar',
        'shell',
        'cmd',
        'powershell',
        'wscript',
        'cscript',
        'ms-msdt',
        'search-ms',
        'ms-appinstaller',
        'mhtml',
        'its',
        'mk',
        'hcp',
        'res',
        'intent',
        'content',
      ];
      expect(
        blockedSchemes.length,
        equals(28),
        reason: 'Policy must cover all 28 blocked dangerous schemes',
      );

      for (final scheme in blockedSchemes) {
        for (final variant in <String>[
          '$scheme://host/payload',
          '${scheme.toUpperCase()}:payload',
          '${scheme[0].toUpperCase()}${scheme.substring(1)}://mixed',
        ]) {
          expect(
            LinkLauncherRepository.isLaunchableUri(variant),
            isFalse,
            reason: 'Blocked scheme URI "$variant" must be rejected',
          );
          await expectLater(
            () => platformRepo.openLink(variant),
            throwsA(isA<LinkLaunchException>()),
            reason: 'PlatformLinkLauncherRepository must reject "$variant"',
          );
          await expectLater(
            () => fakeRepo.openLink(variant),
            throwsA(isA<LinkLaunchException>()),
            reason: 'FakeLinkLauncherRepository must reject "$variant"',
          );
        }
      }

      const maliciousUris = <String>[
        r'https://example.com\evil',
        r'obsidian://open?file=a\b',
        'https://example.com/\u200Eleft',
        'https://example.com/\u200Fright',
        'https://example.com/\u202Alre',
        'https://example.com/\u202Brle',
        'https://example.com/\u202Cpdf',
        'https://example.com/\u202Dlro',
        'https://example.com/\u202Etxt.exe',
        'https://example.com/\u2066lri',
        'https://example.com/\u2067rli',
        'https://example.com/\u2068fsi',
        'https://example.com/\u2069pdi',
        '\nhttps://example.com/leading-lf',
        'https://example.com/trailing-cr\r',
        'https://example.com/c1\u0085nel',
        'https:',
      ];

      for (final uri in maliciousUris) {
        expect(
          LinkLauncherRepository.isLaunchableUri(uri),
          isFalse,
          reason: 'Malicious URI "$uri" must fail isLaunchableUri',
        );
        await expectLater(
          () => platformRepo.openLink(uri),
          throwsA(isA<LinkLaunchException>()),
          reason:
              'PlatformLinkLauncherRepository must reject malicious URI "$uri"',
        );
        await expectLater(
          () => fakeRepo.openLink(uri),
          throwsA(isA<LinkLaunchException>()),
          reason: 'FakeLinkLauncherRepository must reject malicious URI "$uri"',
        );
      }

      expect(
        lastLaunchedUri,
        isNull,
        reason: 'Blocked and malicious URIs must never reach platform channel',
      );
      expect(
        fakeRepo.launchedUris,
        isEmpty,
        reason: 'Blocked and malicious URIs must never be recorded by FakeLinkLauncherRepository',
      );
    });

    test('rejects single-character schemes (Windows drive paths), Arabic Letter Mark, and Unicode line/paragraph separators', () async {
      const platformRepo = PlatformLinkLauncherRepository();
      final fakeRepo = FakeLinkLauncherRepository();

      const rejectedUris = <String>[
        'C:/Windows/System32/calc.exe',
        'c:payload.bat',
        'D:/Users/Alice/secret.txt',
        'a:opaque',
        'https://example.com/\u061Calm',
        'https://example.com/\u2028line-sep',
        'https://example.com/\u2029para-sep',
      ];

      for (final uri in rejectedUris) {
        expect(
          LinkLauncherRepository.isLaunchableUri(uri),
          isFalse,
          reason: 'URI "$uri" must fail isLaunchableUri',
        );
        await expectLater(
          () => platformRepo.openLink(uri),
          throwsA(isA<LinkLaunchException>()),
          reason: 'PlatformLinkLauncherRepository must reject "$uri"',
        );
        await expectLater(
          () => fakeRepo.openLink(uri),
          throwsA(isA<LinkLaunchException>()),
          reason: 'FakeLinkLauncherRepository must reject "$uri"',
        );
      }

      expect(lastLaunchedUri, isNull);
      expect(fakeRepo.launchedUris, isEmpty);
    });

    test('logs only validated RFC 3986 schemes and masks malformed prefixes with <invalid> in AppLogger', () async {
      AppLogger.resetForTesting();
      AppLogger.setEnabled(true, persistToDisk: false);
      addTearDown(AppLogger.resetForTesting);

      const repository = PlatformLinkLauncherRepository();

      const malformedWithSensitivePrefix = <String>[
        'secret bank note: 12345',
        '/home/alice/private:secret',
        '//internal-host.corp:8443/path',
        '123bad://host/item',
        'C:/Windows/System32/calc.exe',
        'bad_token_prefix:value',
        'bad\nsecret_prefix:value',
      ];
      final overlongPrefix = '${'a' * 80}:${'b' * TaskLink.maxUriLength}';

      for (final uri in <String>[
        ...malformedWithSensitivePrefix,
        overlongPrefix,
      ]) {
        await expectLater(
          () => repository.openLink(uri),
          throwsA(isA<LinkLaunchException>()),
          reason: 'Malformed URI "$uri" must be rejected',
        );
      }

      final logAfterMalformed = AppLogger.fullLogText;
      expect(
        logAfterMalformed,
        contains('scheme=<invalid>'),
        reason: 'Malformed URI prefixes must be logged as scheme=<invalid>',
      );
      for (final leakedFragment in const <String>[
        'secret bank note',
        '/home/alice/private',
        'internal-host.corp',
        '123bad',
        'bad_token_prefix',
        'secret_prefix',
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ]) {
        expect(
          logAfterMalformed,
          isNot(contains(leakedFragment)),
          reason:
              'Unvalidated URI prefix "$leakedFragment" must never leak into AppLogger',
        );
      }

      // A blocked URI with syntactically valid RFC 3986 scheme still logs the normalized scheme only.
      AppLogger.resetForTesting();
      AppLogger.setEnabled(true, persistToDisk: false);
      await expectLater(
        () => repository.openLink('JavaScript:alert("secret-payload")'),
        throwsA(isA<LinkLaunchException>()),
      );
      final blockedLog = AppLogger.fullLogText;
      expect(blockedLog, contains('scheme=javascript'));
      expect(blockedLog, isNot(contains('secret-payload')));
    });
  });
}
