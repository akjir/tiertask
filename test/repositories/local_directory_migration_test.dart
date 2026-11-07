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

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalFileRepository Path Helpers & Native Picker Channel', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tiertask_dir_helpers_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolves directory path, extracts file name, and combines directory and file name for relative and absolute paths', () {
      final relativeRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'tasks.tdf'),
        baseDirectoryPath: tempDir.path,
      );
      expect(
        relativeRepo.extractFileName(),
        equals('tasks.tdf'),
        reason: 'extractFileName must return tasks.tdf for relative path',
      );
      expect(
        relativeRepo.resolveDirectoryPath(),
        equals(tempDir.path),
        reason: 'resolveDirectoryPath must return baseDirectoryPath',
      );

      final customSubdir =
          '${tempDir.path}${Platform.pathSeparator}custom_folder';
      final combined = LocalFileRepository.combineDirectoryAndFileName(
        customSubdir,
        'work.tdf',
      );
      expect(
        combined,
        equals('$customSubdir${Platform.pathSeparator}work.tdf'),
        reason: 'combineDirectoryAndFileName must join directory and file name',
      );

      final absoluteRepo = LocalFileRepository(
        config: WebDavConfig(localFilePath: combined),
        baseDirectoryPath: '${tempDir.path}${Platform.pathSeparator}ignored',
      );
      expect(
        absoluteRepo.resolveFilePath(),
        equals(combined),
        reason: 'Explicit absolute localFilePath must not prepend baseDirectoryPath',
      );
      expect(
        absoluteRepo.resolveDirectoryPath(),
        equals(customSubdir),
        reason: 'resolveDirectoryPath must return parent of absolute path',
      );
      expect(
        absoluteRepo.extractFileName(),
        equals('work.tdf'),
        reason: 'extractFileName must return trailing file name',
      );
    });

    test('pickDirectory invokes native directory_picker MethodChannel and returns selected path or null on cancel', () async {
      MethodCall? recordedCall;
      String? mockResponse = '/home/stefan/SelectedTasks';

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            LocalFileRepository.directoryPickerChannel,
            (call) async {
              recordedCall = call;
              return mockResponse;
            },
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              LocalFileRepository.directoryPickerChannel,
              null,
            );
      });

      final repo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'tasks.tdf'),
        baseDirectoryPath: tempDir.path,
      );

      final selected = await repo.pickDirectory(initialDirectory: tempDir.path);
      expect(
        selected,
        equals('/home/stefan/SelectedTasks'),
        reason: 'pickDirectory must return trimmed native directory path',
      );
      expect(
        recordedCall?.method,
        equals('pickDirectory'),
        reason: 'MethodChannel method name must be pickDirectory',
      );

      mockResponse = null;
      final cancelled = await repo.pickDirectory();
      expect(
        cancelled,
        isNull,
        reason: 'pickDirectory must return null when dialog is cancelled',
      );
    });

    test('ensureTdfExtension, isValidSingleFileName, pickTdfFile, listTdfFileNamesInDirectory, and initializeIfMissing handle local file selection and creation', () async {
      expect(
        LocalFileRepository.ensureTdfExtension('board'),
        equals('board.tdf'),
        reason: 'Missing .tdf extension must be appended',
      );
      expect(
        LocalFileRepository.ensureTdfExtension('board.tdf'),
        equals('board.tdf'),
        reason: 'Existing .tdf extension must be preserved',
      );
      expect(
        LocalFileRepository.ensureTdfExtension('board.TDF'),
        equals('board.TDF'),
        reason: 'Case-insensitive .TDF extension must be preserved',
      );

      expect(
        LocalFileRepository.isValidSingleFileName('tasks'),
        isTrue,
        reason: 'Alphanumeric base name must be valid',
      );
      expect(
        LocalFileRepository.isValidSingleFileName('my_tasks-2.tdf'),
        isTrue,
        reason: 'Full .tdf file name without separators must be valid',
      );
      for (final invalid in <String>[
        '',
        '   ',
        '.',
        '..',
        '.tdf',
        'sub/tasks.tdf',
        r'sub\tasks.tdf',
        'bad\x00name.tdf',
      ]) {
        expect(
          LocalFileRepository.isValidSingleFileName(invalid),
          isFalse,
          reason: 'Invalid single file name "$invalid" must be rejected',
        );
      }

      MethodCall? recordedCall;
      String? mockFileResponse = '${tempDir.path}/custom_board';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            LocalFileRepository.directoryPickerChannel,
            (call) async {
              recordedCall = call;
              return mockFileResponse;
            },
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              LocalFileRepository.directoryPickerChannel,
              null,
            );
      });

      final repo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'tasks.tdf'),
        baseDirectoryPath: tempDir.path,
      );

      final pickedFile = await repo.pickTdfFile(
        initialDirectory: tempDir.path,
        currentFileName: 'tasks.tdf',
      );
      expect(
        pickedFile,
        equals('${tempDir.path}/custom_board.tdf'),
        reason: 'pickTdfFile must append .tdf when missing',
      );
      expect(
        recordedCall?.method,
        equals('pickFile'),
        reason: 'MethodChannel method name must be pickFile',
      );

      mockFileResponse = null;
      expect(
        await repo.pickTdfFile(),
        isNull,
        reason: 'pickTdfFile must return null when cancelled',
      );

      final newRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'newly_created.tdf'),
        baseDirectoryPath: tempDir.path,
      );
      await newRepo.initializeIfMissing();
      final createdPath =
          '${tempDir.path}${Platform.pathSeparator}newly_created.tdf';
      expect(
        File(createdPath).existsSync(),
        isTrue,
        reason: 'initializeIfMissing must create a new .tdf file when missing',
      );
      expect(
        File(createdPath).readAsStringSync(),
        startsWith('tdf '),
        reason: 'Created .tdf file must contain canonical header',
      );

      File('${tempDir.path}${Platform.pathSeparator}alpha.tdf')
          .writeAsStringSync('tdf 0.5.1\n', flush: true);
      File('${tempDir.path}${Platform.pathSeparator}ignore.txt')
          .writeAsStringSync('not tdf', flush: true);
      expect(
        repo.listTdfFileNamesInDirectory(),
        equals(<String>['alpha.tdf', 'newly_created.tdf']),
        reason: 'listTdfFileNamesInDirectory must return sorted .tdf file names only',
      );
    });
  });

  group('LocalFileRepository Safe Non-Destructive File Move & Error Reasons', () {
    late Directory sourceDir;
    late Directory targetDir;

    setUp(() async {
      sourceDir = await Directory.systemTemp.createTemp('tiertask_move_src_');
      targetDir = await Directory.systemTemp.createTemp('tiertask_move_dst_');
    });

    tearDown(() async {
      if (await sourceDir.exists()) {
        await sourceDir.delete(recursive: true);
      }
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
    });

    test('moves existing .tdf file to new directory, removes old file, and preserves content', () async {
      final sourcePath = '${sourceDir.path}${Platform.pathSeparator}tasks.tdf';
      final targetPath = '${targetDir.path}${Platform.pathSeparator}tasks.tdf';
      const content =
          'tdf 0.3.0\ntask t001 {\n    name "Move Me"\n    created 2026-11-01 08:00\n    queued 2026-11-01 08:00\n}\n';
      await File(sourcePath).writeAsString(content, flush: true);

      final sourceRepo = LocalFileRepository(
        config: WebDavConfig(
          localFilePath: sourcePath,
          language: AppLanguage.english,
        ),
      );
      final targetRepo = LocalFileRepository(
        config: WebDavConfig(
          localFilePath: targetPath,
          language: AppLanguage.english,
        ),
      );

      await sourceRepo.moveTdfFile(targetRepo);

      expect(
        await File(sourcePath).exists(),
        isFalse,
        reason: 'Source .tdf file must be removed after successful move',
      );
      expect(
        await File(targetPath).exists(),
        isTrue,
        reason: 'Target .tdf file must exist after successful move',
      );
      expect(
        await File(targetPath).readAsString(),
        equals(content),
        reason: 'Moved .tdf file must preserve exact content',
      );
    });

    test('rejects move when a regular file, directory, or symbolic link already exists at target path without overwriting', () async {
      final sourcePath = '${sourceDir.path}${Platform.pathSeparator}tasks.tdf';
      const sourceContent = 'tdf 0.3.0\n# original source\n';
      await File(sourcePath).writeAsString(sourceContent, flush: true);

      final sourceRepo = LocalFileRepository(
        config: WebDavConfig(
          localFilePath: sourcePath,
          language: AppLanguage.english,
        ),
      );

      final existingFileTarget =
          '${targetDir.path}${Platform.pathSeparator}existing_file.tdf';
      await File(existingFileTarget)
          .writeAsString('existing target content', flush: true);

      await expectLater(
        () => sourceRepo.moveTdfFile(
          LocalFileRepository(
            config: WebDavConfig(
              localFilePath: existingFileTarget,
              language: AppLanguage.english,
            ),
          ),
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('A file already exists at the target path'),
          ),
        ),
        reason: 'Existing target file must be rejected without overwriting',
      );
      expect(
        await File(existingFileTarget).readAsString(),
        equals('existing target content'),
        reason: 'Existing target file content must remain untouched',
      );
      expect(
        await File(sourcePath).readAsString(),
        equals(sourceContent),
        reason: 'Source file must remain untouched on failed move',
      );

      final existingDirTarget =
          '${targetDir.path}${Platform.pathSeparator}existing_dir.tdf';
      await Directory(existingDirTarget).create();

      await expectLater(
        () => sourceRepo.moveTdfFile(
          LocalFileRepository(
            config: WebDavConfig(
              localFilePath: existingDirTarget,
              language: AppLanguage.english,
            ),
          ),
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains(
              'A directory with this name already exists at the target path',
            ),
          ),
        ),
        reason: 'Existing target directory must be rejected',
      );

      final symlinkTarget =
          '${targetDir.path}${Platform.pathSeparator}symlink_tasks.tdf';
      await Link(symlinkTarget)
          .create('${targetDir.path}${Platform.pathSeparator}dangling_target');

      await expectLater(
        () => sourceRepo.moveTdfFile(
          LocalFileRepository(
            config: WebDavConfig(
              localFilePath: symlinkTarget,
              language: AppLanguage.english,
            ),
          ),
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('A symbolic link already exists at the target path'),
          ),
        ),
        reason: 'Existing symbolic link (including dangling symlink) at target path must be rejected',
      );
      expect(
        await FileSystemEntity.type(symlinkTarget, followLinks: false),
        equals(FileSystemEntityType.link),
        reason: 'Existing symbolic link must not be deleted or overwritten',
      );
    });

    test('rejects move when source is a symlink or directory, or when target directory is missing or not a directory', () async {
      final symlinkSource =
          '${sourceDir.path}${Platform.pathSeparator}link_source.tdf';
      final realFile = '${sourceDir.path}${Platform.pathSeparator}real.tdf';
      await File(realFile).writeAsString('tdf 0.3.0\n', flush: true);
      await Link(symlinkSource).create(realFile);

      final targetPath = '${targetDir.path}${Platform.pathSeparator}tasks.tdf';
      final targetRepo = LocalFileRepository(
        config: WebDavConfig(
          localFilePath: targetPath,
          language: AppLanguage.english,
        ),
      );

      await expectLater(
        () => LocalFileRepository(
          config: WebDavConfig(
            localFilePath: symlinkSource,
            language: AppLanguage.english,
          ),
        ).moveTdfFile(targetRepo),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('The source path is a symbolic link'),
          ),
        ),
        reason: 'Source symbolic link must not be moved',
      );

      final dirSource =
          '${sourceDir.path}${Platform.pathSeparator}dir_source.tdf';
      await Directory(dirSource).create();
      await expectLater(
        () => LocalFileRepository(
          config: WebDavConfig(
            localFilePath: dirSource,
            language: AppLanguage.english,
          ),
        ).moveTdfFile(targetRepo),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('The source path is a directory'),
          ),
        ),
        reason: 'Source directory must not be moved as a TDF file',
      );

      final validSourceRepo = LocalFileRepository(
        config: WebDavConfig(
          localFilePath: realFile,
          language: AppLanguage.english,
        ),
      );
      final missingDirTarget =
          '${targetDir.path}${Platform.pathSeparator}missing_folder${Platform.pathSeparator}tasks.tdf';
      await expectLater(
        () => validSourceRepo.moveTdfFile(
          LocalFileRepository(
            config: WebDavConfig(
              localFilePath: missingDirTarget,
              language: AppLanguage.english,
            ),
          ),
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('The target directory does not exist'),
          ),
        ),
        reason:
            'Missing target directory must not be force-created during move',
      );

      final fileAsDir = '${targetDir.path}${Platform.pathSeparator}not_a_dir';
      await File(fileAsDir).writeAsString('file', flush: true);
      final underFileTarget = '$fileAsDir${Platform.pathSeparator}tasks.tdf';
      await expectLater(
        () => validSourceRepo.moveTdfFile(
          LocalFileRepository(
            config: WebDavConfig(
              localFilePath: underFileTarget,
              language: AppLanguage.english,
            ),
          ),
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('The selected target path is not a directory'),
          ),
        ),
        reason: 'Target parent path that is a file must report not a directory',
      );
    });

    test('maps OS error codes across Linux and Windows for permission denied, read-only FS, disk full, locked file, and path length', () {
      final repo = LocalFileRepository(
        config: const WebDavConfig(
          localFilePath: 'tasks.tdf',
          language: AppLanguage.english,
        ),
        baseDirectoryPath: sourceDir.path,
      );

      for (final (code, message, expectedSubstring) in <(int, String, String)>[
        (13, 'Permission denied', 'Permission denied'),
        (1, 'Operation not permitted', 'Permission denied'),
        (5, 'Access is denied.', 'Permission denied'),
        (1314, 'Privilege not held', 'Permission denied'),
        (30, 'Read-only file system', 'read-only'),
        (19, 'The media is write protected.', 'read-only'),
        (28, 'No space left on device', 'Not enough free disk space'),
        (122, 'Disk quota exceeded', 'Not enough free disk space'),
        (
          112,
          'There is not enough space on the disk.',
          'Not enough free disk space',
        ),
        (39, 'The disk is full.', 'Not enough free disk space'),
        (16, 'Device or resource busy', 'locked or in use'),
        (26, 'Text file busy', 'locked or in use'),
        (32, 'Sharing violation', 'locked or in use'),
        (33, 'Lock violation', 'locked or in use'),
        (17, 'File exists', 'A file already exists'),
        (80, 'The file exists.', 'A file already exists'),
        (
          183,
          'Cannot create a file when that file already exists.',
          'A file already exists',
        ),
        (21, 'Is a directory', 'A directory with this name already exists'),
        (20, 'Not a directory', 'not a directory'),
        (267, 'The directory name is invalid.', 'not a directory'),
        (2, 'No such file or directory', 'does not exist'),
        (3, 'The system cannot find the path specified.', 'does not exist'),
        (36, 'File name too long', 'too long'),
        (206, 'The filename or extension is too long.', 'too long'),
        (999, 'Custom hardware I/O fault', 'Custom hardware I/O fault'),
      ]) {
        final fsException = FileSystemException(
          'Move failed',
          '/target/tasks.tdf',
          OSError(message, code),
        );
        final mapped = repo.mapMoveFileSystemException(
          fsException,
          fallbackPath: '/target/tasks.tdf',
        );
        expect(
          mapped.message,
          contains(expectedSubstring),
          reason:
              'OS error code $code ("$message") must map to "$expectedSubstring"',
        );
      }
    });

    test('WebDavConfigNotifier.changeLocalFileLocation moves file on success and keeps previous directory unchanged on failure', () async {
      final initialFilePath =
          '${sourceDir.path}${Platform.pathSeparator}tasks.tdf';
      await File(initialFilePath).writeAsString(
        'tdf 0.3.0\ntask t001 {\n    name "Keep Safe"\n    created 2026-11-01 08:00\n    queued 2026-11-01 08:00\n}\n',
        flush: true,
      );

      final settingsRepository = InMemorySettingsRepository(
        WebDavConfig(
          localFilePath: initialFilePath,
          storageMode: StorageMode.local,
          language: AppLanguage.english,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(webDavConfigProvider.future);

      final conflictPath =
          '${targetDir.path}${Platform.pathSeparator}tasks.tdf';
      await File(conflictPath).writeAsString('do not overwrite', flush: true);

      await expectLater(
        () => container
            .read(webDavConfigProvider.notifier)
            .changeLocalFileLocation(
              WebDavConfig(
                localFilePath: conflictPath,
                storageMode: StorageMode.local,
                language: AppLanguage.english,
              ),
            ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('A file already exists at the target path'),
          ),
        ),
        reason: 'changeLocalFileLocation must throw LocalFileException when target file already exists',
      );

      final configAfterFailedMove = await container.read(
        webDavConfigProvider.future,
      );
      expect(
        configAfterFailedMove.localFilePath,
        equals(initialFilePath),
        reason: 'Failed directory move must leave persisted localFilePath unchanged',
      );
      expect(
        await File(initialFilePath).exists(),
        isTrue,
        reason: 'Original file must remain in place after failed move',
      );

      await File(conflictPath).delete();

      await container
          .read(webDavConfigProvider.notifier)
          .changeLocalFileLocation(
            WebDavConfig(
              localFilePath: conflictPath,
              storageMode: StorageMode.local,
              language: AppLanguage.english,
            ),
          );

      final configAfterSuccess = await container.read(
        webDavConfigProvider.future,
      );
      expect(
        configAfterSuccess.localFilePath,
        equals(conflictPath),
        reason: 'Successful directory move must update persisted localFilePath',
      );
      expect(
        await File(initialFilePath).exists(),
        isFalse,
        reason: 'Original file must be removed after successful move',
      );
      expect(
        await File(conflictPath).exists(),
        isTrue,
        reason: 'File must exist at new target path after successful move',
      );

      await container
          .read(activeWorkspaceProvider.notifier)
          .createWorkspace(
            'Second Workspace',
            config: WebDavConfig(
              localFilePath:
                  '${sourceDir.path}${Platform.pathSeparator}second.tdf',
              filePath: 'second.tdf',
            ),
          );

      await expectLater(
        () => container
            .read(webDavConfigProvider.notifier)
            .changeLocalFileLocation(
              WebDavConfig(
                localFilePath:
                    '${sourceDir.path}${Platform.pathSeparator}second.tdf',
                storageMode: StorageMode.local,
                language: AppLanguage.english,
              ),
            ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('Another workspace already uses this TDF file path'),
          ),
        ),
        reason: 'Colliding with another workspace localFilePath must be rejected before moving',
      );
      expect(
        await File(conflictPath).exists(),
        isTrue,
        reason: 'File must stay untouched when workspace path validation fails',
      );
    });

    test('rejects directory change with permission denied when target directory lacks write permission even if source file does not exist yet', () async {
      if (!Platform.isLinux) {
        return;
      }
      final idResult = await Process.run('id', const <String>['-u']);
      if (idResult.stdout.toString().trim() == '0') {
        return;
      }

      final readOnlyDir =
          '${targetDir.path}${Platform.pathSeparator}readonly_dir';
      await Directory(readOnlyDir).create();
      await Process.run('chmod', <String>['0500', readOnlyDir]);
      addTearDown(() async {
        await Process.run('chmod', <String>['0700', readOnlyDir]);
      });

      final nonExistentSourceRepo = LocalFileRepository(
        config: WebDavConfig(
          localFilePath:
              '${sourceDir.path}${Platform.pathSeparator}not_created_yet.tdf',
          language: AppLanguage.english,
        ),
      );
      final readOnlyTargetRepo = LocalFileRepository(
        config: WebDavConfig(
          localFilePath:
              '$readOnlyDir${Platform.pathSeparator}not_created_yet.tdf',
          language: AppLanguage.english,
        ),
      );

      await expectLater(
        () => nonExistentSourceRepo.moveTdfFile(readOnlyTargetRepo),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('Permission denied'),
          ),
        ),
        reason: 'Unwritable target directory must be rejected with Permission denied even when source file was not created yet',
      );
    });

    test('TaskNotifier.selectLocalFile switches to an existing .tdf file or initializes a new .tdf file without moving or deleting the previous file', () async {
      final firstPath = '${sourceDir.path}${Platform.pathSeparator}first.tdf';
      final existingSecondPath =
          '${sourceDir.path}${Platform.pathSeparator}second.tdf';
      final newThirdPath =
          '${sourceDir.path}${Platform.pathSeparator}third.tdf';

      await File(firstPath).writeAsString(
        'tdf 0.5.1\n\nqueue {\n    modified 2026-11-01 08:00:00\n    task 000001OkD2\n}\n\ntask 000001OkD2 {\n    name "First File Task"\n    created 2026-11-01 08:00:00\n    modified 2026-11-01 08:00:00\n}\n',
        flush: true,
      );
      await File(existingSecondPath).writeAsString(
        'tdf 0.5.1\n\nqueue {\n    modified 2026-11-01 09:00:00\n    task 000002OkD2\n}\n\ntask 000002OkD2 {\n    name "Second File Task"\n    created 2026-11-01 09:00:00\n    modified 2026-11-01 09:00:00\n}\n',
        flush: true,
      );

      final settingsRepository = InMemorySettingsRepository(
        WebDavConfig(
          localFilePath: firstPath,
          storageMode: StorageMode.local,
          language: AppLanguage.english,
        ),
      );
      final container = ProviderContainer(
        retry: (retryCount, error) => null,
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1, 10)),
        ],
      );
      addTearDown(container.dispose);

      final initialBoard = await container.read(taskNotifierProvider.future);
      expect(
        initialBoard.allTasks.map((task) => task.title),
        equals(<String>['First File Task']),
      );

      await container
          .read(taskNotifierProvider.notifier)
          .selectLocalFile(
            WebDavConfig(
              localFilePath: existingSecondPath,
              storageMode: StorageMode.local,
              language: AppLanguage.english,
            ),
          );

      final secondBoard = await container.read(taskNotifierProvider.future);
      expect(
        secondBoard.allTasks.map((task) => task.title),
        equals(<String>['Second File Task']),
        reason: 'Selecting an existing .tdf file must load its tasks into the board',
      );
      expect(
        await File(firstPath).exists(),
        isTrue,
        reason: 'Selecting another file must leave the previous .tdf file on disk untouched',
      );

      await container
          .read(taskNotifierProvider.notifier)
          .selectLocalFile(
            WebDavConfig(
              localFilePath: newThirdPath,
              storageMode: StorageMode.local,
              language: AppLanguage.english,
            ),
          );

      final thirdBoard = await container.read(taskNotifierProvider.future);
      expect(
        thirdBoard.allTasks,
        isEmpty,
        reason:
            'Selecting a new non-existent .tdf file must load an empty board',
      );
      expect(
        await File(newThirdPath).exists(),
        isTrue,
        reason:
            'Selecting a new non-existent .tdf file must initialize it on disk',
      );
      expect(
        await File(existingSecondPath).exists(),
        isTrue,
        reason: 'Previous .tdf file must remain untouched on disk',
      );
    });
  });
}
