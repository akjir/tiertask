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
import 'package:tiertask/models/tdf_file_path.dart';
import 'package:tiertask/models/webdav_config.dart';

void main() {
  group('TdfFilePath.ensureTdfExtension', () {
    test('returns default filename for empty or whitespace input', () {
      expect(
        TdfFilePath.ensureTdfExtension(''),
        equals(WebDavConfig.defaultFileName),
      );
      expect(
        TdfFilePath.ensureTdfExtension('   \t '),
        equals(WebDavConfig.defaultFileName),
      );
    });

    test(
      'preserves valid .tdf suffix case-insensitively and appends otherwise',
      () {
        const cases = <(String, String)>[
          ('work', 'work.tdf'),
          ('  work  ', 'work.tdf'),
          ('work.tdf', 'work.tdf'),
          ('WORK.TDF', 'WORK.TDF'),
          ('.tdf', '.tdf.tdf'),
          ('my.archive.2026', 'my.archive.2026.tdf'),
          ('my.archive.2026.tdf', 'my.archive.2026.tdf'),
        ];
        for (final (input, expected) in cases) {
          expect(
            TdfFilePath.ensureTdfExtension(input),
            equals(expected),
            reason: 'ensureTdfExtension($input) should return $expected',
          );
        }
      },
    );
  });

  group('TdfFilePath path extraction and normalization', () {
    test(
      'extractFileNameFromPath handles POSIX, Windows, mixed, and empty paths',
      () {
        const cases = <(String, String)>[
          ('', WebDavConfig.defaultFileName),
          ('   ', WebDavConfig.defaultFileName),
          ('///', WebDavConfig.defaultFileName),
          (r'\\\', WebDavConfig.defaultFileName),
          ('tasks.tdf', 'tasks.tdf'),
          ('/home/user/work.tdf', 'work.tdf'),
          ('/home/user/work.tdf///', 'work.tdf'),
          (r'C:\Users\Alice\notes.tdf', 'notes.tdf'),
          (r'C:/Users\Alice//nested\board.TDF', 'board.TDF'),
        ];
        for (final (input, expected) in cases) {
          expect(
            TdfFilePath.extractFileNameFromPath(input),
            equals(expected),
            reason: 'extractFileNameFromPath($input) should return $expected',
          );
        }
      },
    );

    test('extractFileBaseName strips case-insensitive .tdf suffix only when length > 4', () {
      const cases = <(String, String)>[
        ('/dir/work.tdf', 'work'),
        (r'C:\dir\WORK.TDF', 'WORK'),
        ('/dir/.tdf', '.tdf'),
        ('/dir/notes.txt', 'notes.txt'),
        ('a.tdf', 'a'),
      ];
      for (final (input, expected) in cases) {
        expect(
          TdfFilePath.extractFileBaseName(input),
          equals(expected),
          reason: 'extractFileBaseName($input) should return $expected',
        );
      }
    });

    test(
      'extractDirectoryFromPath preserves POSIX and Windows drive roots',
      () {
        const cases = <(String, String)>[
          ('', ''),
          ('tasks.tdf', ''),
          ('/tasks.tdf', '/'),
          ('/home/user/tasks.tdf', '/home/user'),
          ('/home/user/tasks.tdf/', '/home/user'),
          (r'C:\tasks.tdf', r'C:\'),
          ('C:/tasks.tdf', 'C:/'),
          (r'C:\Users\Alice\tasks.tdf', r'C:\Users\Alice'),
          (r'C:\Users/Alice\tasks.tdf', r'C:\Users/Alice'),
        ];
        for (final (input, expected) in cases) {
          expect(
            TdfFilePath.extractDirectoryFromPath(input),
            equals(expected),
            reason: 'extractDirectoryFromPath($input) should return $expected',
          );
        }
      },
    );

    test(
      'trimTrailingSeparators strips trailing slashes while preserving roots',
      () {
        const cases = <(String, String)>[
          ('', ''),
          ('/', '/'),
          ('////', '/'),
          (r'C:\', r'C:\'),
          (r'C:\\\\', r'C:\'),
          ('C:///', 'C:/'),
          ('/home/user///', '/home/user'),
          (r'C:\Users\Alice\\/', r'C:\Users\Alice'),
        ];
        for (final (input, expected) in cases) {
          expect(
            TdfFilePath.trimTrailingSeparators(input),
            equals(expected),
            reason: 'trimTrailingSeparators($input) should return $expected',
          );
        }
      },
    );

    test(
      'isAbsolutePath distinguishes POSIX, Windows drives, and relative paths',
      () {
        const cases = <(String, bool)>[
          ('/home/user/tasks.tdf', true),
          ('/', true),
          (r'C:\tasks.tdf', true),
          ('d:/tasks.tdf', true),
          ('tasks.tdf', false),
          ('subdir/tasks.tdf', false),
          ('C:relative.tdf', false),
          ('', false),
        ];
        for (final (input, expected) in cases) {
          expect(
            TdfFilePath.isAbsolutePath(input),
            equals(expected),
            reason: 'isAbsolutePath($input) should be $expected',
          );
        }
      },
    );

    test('combineDirectoryAndFileName normalizes roots, separators, and nested filenames', () {
      expect(
        TdfFilePath.combineDirectoryAndFileName('', 'work.tdf', separator: '/'),
        equals('work.tdf'),
      );
      expect(
        TdfFilePath.combineDirectoryAndFileName(
          '/',
          'work.tdf',
          separator: '/',
        ),
        equals('/work.tdf'),
      );
      expect(
        TdfFilePath.combineDirectoryAndFileName(
          '/home/user///',
          '/ignored/path/work.tdf',
          separator: '/',
        ),
        equals('/home/user/work.tdf'),
      );
      expect(
        TdfFilePath.combineDirectoryAndFileName(
          r'C:\',
          'work.tdf',
          separator: r'\',
        ),
        equals(r'C:\work.tdf'),
      );
      expect(
        TdfFilePath.combineDirectoryAndFileName(
          r'C:\Users\Alice\\',
          r'nested\work.tdf',
          separator: r'\',
        ),
        equals(r'C:\Users\Alice\work.tdf'),
      );
      expect(
        TdfFilePath.combineDirectoryAndFileName(
          'C:/Users/Alice/',
          'work.tdf',
          separator: '/',
        ),
        equals('C:/Users/Alice/work.tdf'),
      );
    });
  });

  group('TdfFilePath.isValidSingleFileName', () {
    test('accepts safe single filenames and rejects traversal, separators, and control/BiDi chars', () {
      const validNames = <String>[
        'tasks.tdf',
        'work',
        'project-2026_v1.tdf',
        'Übersicht.tdf',
        '  trimmed.tdf  ',
      ];
      for (final candidate in validNames) {
        expect(
          TdfFilePath.isValidSingleFileName(candidate),
          isTrue,
          reason: 'Expected valid filename: $candidate',
        );
      }

      const invalidNames = <String>[
        '',
        '   ',
        '.',
        '..',
        '.tdf',
        '.TDF',
        'a/b.tdf',
        r'a\b.tdf',
        'C:tasks.tdf',
        'bad\x00name.tdf',
        'bad\nname.tdf',
        'bad\x1Fname.tdf',
        'bad\x7Fname.tdf',
        'bad\u0085name.tdf',
        'bad\u202Ename.tdf',
        'bad\u2066name.tdf',
      ];
      for (final candidate in invalidNames) {
        expect(
          TdfFilePath.isValidSingleFileName(candidate),
          isFalse,
          reason: 'Expected invalid filename: $candidate',
        );
      }
    });
  });
}
