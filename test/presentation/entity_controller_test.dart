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
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/app_shell_controller.dart';
import 'package:tiertask/presentation/entity_controller.dart';
import 'package:tiertask/presentation/floating_notice_controller.dart';
import 'package:tiertask/presentation/shell_models.dart';
import 'package:tiertask/presentation/view_model_primitives.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/location_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/tdf_service.dart';

import '../ui/test_helpers.dart';

class _ControlledLocationNotifier extends LocationNotifier {
  _ControlledLocationNotifier(this._initialState, {this.refreshedFix});

  final LocationState _initialState;
  final LocationFix? refreshedFix;
  int refreshCalls = 0;

  @override
  LocationState build() => _initialState;

  @override
  Future<void> refreshLocation() async {
    refreshCalls++;
    if (refreshedFix case final fix?) {
      state = LocationState(
        status: LocationStatus.found,
        fix: fix,
        updatedAt: DateTime.utc(2026, 11, 21, 12),
      );
    }
  }
}

class _DelayedLocationRepository extends FakeLocationRepository {
  Completer<List<GeocodingCandidate>>? nextSearchCompleter;

  @override
  Future<List<GeocodingCandidate>> searchLocations(String query) {
    if (nextSearchCompleter case final completer?) {
      nextSearchCompleter = null;
      return completer.future;
    }
    return super.searchLocations(query);
  }
}

class _BlockingTaskNotifier extends TaskNotifier {
  _BlockingTaskNotifier(this._initialBoard);

  final TaskBoard _initialBoard;
  Completer<void>? nextMutationCompleter;
  Object? nextError;

  @override
  Future<TaskBoard> build() async => _initialBoard;

  @override
  Future<void> addLabel(
    String name, {
    String? color,
    String? id,
    String? note,
    bool isScoped = false,
    Iterable<TaskLink>? links,
    List<TaskCondition> conditions = const <TaskCondition>[],
    DateTime? currentDate,
  }) async {
    await _awaitGate();
  }

  @override
  Future<void> updateLabel(
    String labelId, {
    String? name,
    String? color,
    bool clearColor = false,
    String? note,
    bool clearNote = false,
    bool? isScoped,
    Iterable<TaskLink>? links,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
  }) async {
    await _awaitGate();
  }

  Future<void> _awaitGate() async {
    if (nextMutationCompleter case final completer?) {
      nextMutationCompleter = null;
      await completer.future;
    }
    if (nextError case final error?) {
      nextError = null;
      throw error;
    }
  }
}

void main() {
  const baseTdf = '''tdf 0.8.0

label work000001 {
  name "Work"
  color "#2196F3"
  modified 2026-11-01 08:00:00
}

location loc0000001 {
  name "Office"
  coordinates 52.52 13.405
  radius 150
  modified 2026-11-01 08:00:00
}
''';

  setUp(() {
    AppLogger.resetForTesting(clock: () => DateTime.utc(2026, 11, 21, 12));
  });

  tearDown(() {
    AppLogger.resetForTesting();
  });

  ({
    ProviderContainer container,
    FakeLocalFileRepository localRepository,
    _DelayedLocationRepository locationRepository,
    _ControlledLocationNotifier locationNotifier,
  })
  createHarness({
    String initialTdf = baseTdf,
    LocationState locationState = const LocationState.unavailable(),
    LocationFix? refreshedFix,
    WebDavConfig config = const WebDavConfig(language: AppLanguage.english),
  }) {
    final settingsRepository = InMemorySettingsRepository(config);
    final localRepository = FakeLocalFileRepository(
      config: config,
      initialTdf: initialTdf,
    );
    final locationRepository = _DelayedLocationRepository();
    final locationNotifier = _ControlledLocationNotifier(
      locationState,
      refreshedFix: refreshedFix,
    );
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepository),
        localFileRepositoryProvider.overrideWith((ref) => localRepository),
        locationRepositoryProvider.overrideWithValue(locationRepository),
        locationStateProvider.overrideWith(() => locationNotifier),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 21, 12)),
      ],
    );
    return (
      container: container,
      localRepository: localRepository,
      locationRepository: locationRepository,
      locationNotifier: locationNotifier,
    );
  }

  group('EntityController immutable value types', () {
    test('supports value equality, hashCode, and copyWith on public types', () {
      const stateA = EntityControllerState();
      final stateB = stateA.copyWith(isBusy: true, isResolvingLocation: true);
      expect(stateA, equals(const EntityControllerState()));
      expect(stateA.hashCode, equals(const EntityControllerState().hashCode));
      expect(stateB.isBusy, isTrue);
      expect(stateB.isResolvingLocation, isTrue);
      expect(stateB, isNot(equals(stateA)));

      final labelDraftA = LabelDraftInput(
        name: 'Focus',
        colorHex: '#2196F3',
        isScoped: true,
        note: 'Details',
        links: const <EntityLinkViewModel>[
          EntityLinkViewModel(title: 'Docs', uri: 'https://example.com'),
        ],
        conditionDraft: ConditionDraftViewModel(
          daysMode: ConditionDimensionMode.custom,
          selectedWeekdays: const <int>[1, 2],
        ),
      );
      final labelDraftB = LabelDraftInput(
        name: 'Focus',
        colorHex: '#2196F3',
        isScoped: true,
        note: 'Details',
        links: const <EntityLinkViewModel>[
          EntityLinkViewModel(title: 'Docs', uri: 'https://example.com'),
        ],
        conditionDraft: ConditionDraftViewModel(
          daysMode: ConditionDimensionMode.custom,
          selectedWeekdays: const <int>[1, 2],
        ),
      );
      expect(labelDraftA, equals(labelDraftB));
      expect(labelDraftA.hashCode, equals(labelDraftB.hashCode));
      expect(() => labelDraftA.links.clear(), throwsUnsupportedError);

      const locationDraftA = LocationDraftInput(
        name: 'Home',
        sourceType: ShellLocationSourceType.address,
        rawSource: 'Berlin',
        rawLatitude: '52.52',
        rawLongitude: '13.405',
        rawRadius: '250m',
        note: 'Entrance',
      );
      const locationDraftB = LocationDraftInput(
        name: 'Home',
        sourceType: ShellLocationSourceType.address,
        rawSource: 'Berlin',
        rawLatitude: '52.52',
        rawLongitude: '13.405',
        rawRadius: '250m',
        note: 'Entrance',
      );
      expect(locationDraftA, equals(locationDraftB));
      expect(locationDraftA.hashCode, equals(locationDraftB.hashCode));

      const candidate = GeocodingCandidateViewModel(
        index: 0,
        displayName: 'Berlin',
        latitude: 52.52,
        longitude: 13.405,
        coordinatesSummary: '52.52, 13.405',
      );
      final disambiguationA = LocationSourceUiNeedsDisambiguation(
        candidates: const <GeocodingCandidateViewModel>[candidate],
        sourceType: ShellLocationSourceType.address,
      );
      final disambiguationB = LocationSourceUiNeedsDisambiguation(
        candidates: const <GeocodingCandidateViewModel>[candidate],
        sourceType: ShellLocationSourceType.address,
      );
      expect(disambiguationA, equals(disambiguationB));
      expect(disambiguationA.hashCode, equals(disambiguationB.hashCode));
      expect(() => disambiguationA.candidates.clear(), throwsUnsupportedError);

      const resolvedA = LocationSourceUiResolved(
        latitudeText: '52.52',
        longitudeText: '13.405',
        normalizedSource: 'Berlin',
        sourceType: ShellLocationSourceType.address,
      );
      expect(
        resolvedA,
        equals(
          const LocationSourceUiResolved(
            latitudeText: '52.52',
            longitudeText: '13.405',
            normalizedSource: 'Berlin',
            sourceType: ShellLocationSourceType.address,
          ),
        ),
      );
      expect(
        const LocationSourceUiError(message: 'Err'),
        equals(const LocationSourceUiError(message: 'Err')),
      );
    });
  });

  group('EntityController Labels', () {
    test('quickCreateLabel rotates through all 8 preset colors, auto-expands & reveals, and emits labelSavedNotice', () async {
      final harness = createHarness(initialTdf: 'tdf 0.8.0\n');
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);
      final en = lookupAppLocalizations(const Locale('en'));

      final controller = harness.container.read(
        entityControllerProvider.notifier,
      );
      for (var i = 0; i < canonicalLabelPresetHexColors.length + 1; i++) {
        final result = await controller.quickCreateLabel('Label $i');
        expect(
          result,
          isA<ActionSucceeded>(),
          reason: 'Expected label $i quick-create to succeed',
        );
        final succeeded = result as ActionSucceeded;
        expect(succeeded.entityId, isNotNull);
        expect(succeeded.noticeMessage, equals(en.labelSavedNotice));

        final board = harness.container.read(taskNotifierProvider).requireValue;
        final created = board.findLabel(succeeded.entityId ?? '');
        expect(created, isNotNull);
        final expectedColor =
            canonicalLabelPresetHexColors[i %
                canonicalLabelPresetHexColors.length];
        expect(
          created?.color,
          equals(expectedColor),
          reason: 'Rotating preset color mismatch at index $i',
        );

        final shellState = harness.container.read(appShellControllerProvider);
        final expectedRef = EntityRef(
          kind: EntityKind.label,
          id: succeeded.entityId ?? '',
        );
        expect(shellState.expandedEntity, equals(expectedRef));
        expect(shellState.revealEntityRequest, equals(expectedRef));

        final notice = harness.container.read(floatingNoticeControllerProvider);
        expect(notice?.message, equals(en.labelSavedNotice));
      }
    });

    test('quickCreateLabel rejects empty, case-insensitive duplicates, >500 scalars, control chars, and unpaired surrogates', () async {
      final harness = createHarness();
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);
      final en = lookupAppLocalizations(const Locale('en'));
      final controller = harness.container.read(
        entityControllerProvider.notifier,
      );

      final empty = await controller.quickCreateLabel('   ');
      expect(empty, isA<ActionValidationFailed>());
      expect(
        (empty as ActionValidationFailed).message,
        equals(en.labelNameErrorEmpty),
      );

      final duplicate = await controller.quickCreateLabel('  wOrK  ');
      expect(duplicate, isA<ActionValidationFailed>());
      expect(
        (duplicate as ActionValidationFailed).message,
        equals(en.labelNameErrorDuplicate),
      );
      final duplicateNotice = harness.container.read(
        floatingNoticeControllerProvider,
      );
      expect(duplicateNotice?.tone, equals(NoticeTone.danger));
      expect(duplicateNotice?.message, equals(en.labelNameErrorDuplicate));

      // Exact 500 astral Unicode scalars (1000 UTF-16 code units) must succeed.
      final maxScalarsName = '\u{10000}' * maxTdfTextLength;
      final atLimit = await controller.quickCreateLabel(maxScalarsName);
      expect(
        atLimit,
        isA<ActionSucceeded>(),
        reason: '500 Unicode scalars must be accepted',
      );

      // 501 Unicode scalars must fail.
      final overLimit = await controller.quickCreateLabel(
        'a' * (maxTdfTextLength + 1),
      );
      expect(
        overLimit,
        isA<ActionValidationFailed>(),
        reason: '501 Unicode scalars must be rejected',
      );

      // Control chars and unpaired surrogate must fail.
      for (final bad in <String>[
        'Line1\nLine2',
        'Tab\tName',
        'Null\x00Byte',
        'Del\x7FChar',
        'Surrogate\uD800Bad',
      ]) {
        final rejected = await controller.quickCreateLabel(bad);
        expect(
          rejected,
          isA<ActionValidationFailed>(),
          reason: 'Control/surrogate input "$bad" must be rejected',
        );
      }
    });

    test('createLabelDraft persists full payload, closes draft, logs redacted telemetry, and auto-expands', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.info,
        persistToDisk: false,
      );
      final harness = createHarness();
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);
      final en = lookupAppLocalizations(const Locale('en'));

      final shell = harness.container.read(appShellControllerProvider.notifier);
      shell.openDraft(EntityDraftKind.label, seedTitle: 'Private');

      final controller = harness.container.read(
        entityControllerProvider.notifier,
      );
      final result = await controller.createLabelDraft(
        LabelDraftInput(
          name: '  Deep Work  ',
          colorHex: '#4caf50',
          isScoped: true,
          note: 'Line 1\r\nSecret Line 2',
          links: const <EntityLinkViewModel>[
            EntityLinkViewModel(
              title: 'Spec Docs',
              uri: 'https://secret.example.com/path',
            ),
          ],
          conditionDraft: ConditionDraftViewModel(
            daysMode: ConditionDimensionMode.custom,
            selectedWeekdays: const <int>[1, 3, 5],
            timesMode: ConditionDimensionMode.custom,
            timeWindows: const <TimeWindowDraftViewModel>[
              TimeWindowDraftViewModel(start: '09:00', end: '17:00'),
            ],
            locationsMode: ConditionDimensionMode.custom,
            selectedLocationIds: const <String>['loc0000001'],
          ),
        ),
      );

      expect(result, isA<ActionSucceeded>());
      final succeeded = result as ActionSucceeded;
      final labelId = succeeded.entityId ?? '';
      expect(labelId, isNotEmpty);

      final board = harness.container.read(taskNotifierProvider).requireValue;
      final created = board.findLabel(labelId);
      expect(created, isNotNull);
      expect(created?.name, equals('Deep Work'));
      expect(created?.color, equals('#4CAF50'));
      expect(created?.isScoped, isTrue);
      expect(created?.note, equals('Line 1\nSecret Line 2'));
      expect(created?.links, hasLength(1));
      expect(created?.links.first.title, equals('Spec Docs'));
      expect(
        created?.links.first.uri,
        equals('https://secret.example.com/path'),
      );
      expect(created?.conditions, hasLength(3));

      final shellState = harness.container.read(appShellControllerProvider);
      expect(shellState.activeDraft, isNull);
      expect(
        shellState.expandedEntity,
        equals(EntityRef(kind: EntityKind.label, id: labelId)),
      );
      expect(
        shellState.revealEntityRequest,
        equals(EntityRef(kind: EntityKind.label, id: labelId)),
      );
      expect(
        harness.container.read(floatingNoticeControllerProvider)?.message,
        equals(en.labelSavedNotice),
      );

      final logText = AppLogger.fullLogText;
      expect(logText, contains('ui.entity_draft_committed | kind=label'));
      expect(logText, isNot(contains('Secret Line 2')));
      expect(logText, isNot(contains('secret.example.com')));
    });

    test('createLabelDraft enforces color, note, link, and condition bounds', () async {
      final harness = createHarness();
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);
      final en = lookupAppLocalizations(const Locale('en'));
      final controller = harness.container.read(
        entityControllerProvider.notifier,
      );

      // Invalid hex color.
      final badColor = await controller.createLabelDraft(
        LabelDraftInput(name: 'BadColor', colorHex: '#12345'),
      );
      expect(badColor, isA<ActionValidationFailed>());
      expect(
        (badColor as ActionValidationFailed).fieldErrors['color'],
        equals(en.labelColorErrorInvalid),
      );

      // Note exceeding 2000 scalars and note with disallowed control char.
      final longNote = await controller.createLabelDraft(
        LabelDraftInput(name: 'LongNote', note: 'n' * (maxTdfNoteLength + 1)),
      );
      expect(longNote, isA<ActionValidationFailed>());
      expect(
        (longNote as ActionValidationFailed).fieldErrors['note'],
        equals(en.schedulingNoteErrorTooLong),
      );

      final badNoteChar = await controller.createLabelDraft(
        LabelDraftInput(name: 'BadNote', note: 'Bad\x07Bell'),
      );
      expect(badNoteChar, isA<ActionValidationFailed>());
      expect(
        (badNoteChar as ActionValidationFailed).fieldErrors['note'],
        equals(en.schedulingNoteErrorInvalid),
      );

      // 21 links exceeds maxTdfLinksPerLabel (20).
      final tooManyLinks = List<EntityLinkViewModel>.generate(
        maxTdfLinksPerLabel + 1,
        (i) => EntityLinkViewModel(
          title: 'Link $i',
          uri: 'https://example.com/$i',
        ),
      );
      final linkOverflow = await controller.createLabelDraft(
        LabelDraftInput(name: 'ManyLinks', links: tooManyLinks),
      );
      expect(linkOverflow, isA<ActionValidationFailed>());
      expect(
        (linkOverflow as ActionValidationFailed).fieldErrors['links'],
        equals(en.labelLinkErrorMaxExceeded),
      );

      // Disallowed URI schemes & malformed links.
      for (final badLink in const <EntityLinkViewModel>[
        EntityLinkViewModel(title: 'XSS', uri: 'javascript:alert(1)'),
        EntityLinkViewModel(title: 'Data', uri: 'data:text/html,hi'),
        EntityLinkViewModel(title: 'NoScheme', uri: 'example.com'),
        EntityLinkViewModel(title: '   ', uri: 'https://example.com'),
      ]) {
        final rejected = await controller.createLabelDraft(
          LabelDraftInput(
            name: 'BadLink',
            links: <EntityLinkViewModel>[badLink],
          ),
        );
        expect(
          rejected,
          isA<ActionValidationFailed>(),
          reason: 'Expected invalid link ${badLink.uri} to fail',
        );
        expect(
          (rejected as ActionValidationFailed).fieldErrors['links'],
          equals(en.linkErrorInvalid),
        );
      }

      // Invalid time window (start == end) and unknown location reference.
      final equalTime = await controller.createLabelDraft(
        LabelDraftInput(
          name: 'EqualTime',
          conditionDraft: ConditionDraftViewModel(
            timesMode: ConditionDimensionMode.custom,
            timeWindows: const <TimeWindowDraftViewModel>[
              TimeWindowDraftViewModel(start: '10:00', end: '10:00'),
            ],
          ),
        ),
      );
      expect(equalTime, isA<ActionValidationFailed>());
      expect(
        (equalTime as ActionValidationFailed).fieldErrors['conditions'],
        equals(en.conditionTimeErrorInvalid),
      );

      final unknownLocation = await controller.createLabelDraft(
        LabelDraftInput(
          name: 'UnknownLoc',
          conditionDraft: ConditionDraftViewModel(
            locationsMode: ConditionDimensionMode.custom,
            selectedLocationIds: const <String>['missing001'],
          ),
        ),
      );
      expect(unknownLocation, isA<ActionValidationFailed>());
      expect(
        (unknownLocation as ActionValidationFailed).fieldErrors['conditions'],
        equals(en.conditionLocationErrorInvalid),
      );

      // Exceeding maxTdfLocationRefsPerEntity (63) fails before deduplication.
      final tooManyLocationRefs = await controller.createLabelDraft(
        LabelDraftInput(
          name: 'TooManyLocRefs',
          conditionDraft: ConditionDraftViewModel(
            locationsMode: ConditionDimensionMode.custom,
            selectedLocationIds: List<String>.filled(
              maxTdfLocationRefsPerEntity + 1,
              'loc0000001',
            ),
          ),
        ),
      );
      expect(tooManyLocationRefs, isA<ActionValidationFailed>());
      expect(
        (tooManyLocationRefs as ActionValidationFailed)
            .fieldErrors['conditions'],
        equals(en.conditionLocationErrorInvalid),
      );

      // Invalid weekday out of 1..7 rejected.
      final invalidWeekday = await controller.createLabelDraft(
        LabelDraftInput(
          name: 'BadWeekday',
          conditionDraft: ConditionDraftViewModel(
            daysMode: ConditionDimensionMode.custom,
            selectedWeekdays: const <int>[0, 8],
          ),
        ),
      );
      expect(invalidWeekday, isA<ActionValidationFailed>());

      // Exact 20 links and 2000-scalar note succeed.
      final exactLinks = List<EntityLinkViewModel>.generate(
        maxTdfLinksPerLabel,
        (i) => EntityLinkViewModel(
          title: 'Link $i',
          uri: 'https://example.com/$i',
        ),
      );
      final exactValid = await controller.createLabelDraft(
        LabelDraftInput(
          name: 'ExactBounds',
          note: 'n' * maxTdfNoteLength,
          links: exactLinks,
        ),
      );
      expect(exactValid, isA<ActionSucceeded>());
    });

    test('inline label saves, live Board Scope toggle, clear actions, and deleteLabel without Undo', () async {
      final harness = createHarness();
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);
      final en = lookupAppLocalizations(const Locale('en'));

      final controller = harness.container.read(
        entityControllerProvider.notifier,
      );
      final shell = harness.container.read(appShellControllerProvider.notifier);

      // Add second label to verify duplicate check excludes self.
      await controller.quickCreateLabel('Personal');

      // Self case-change succeeds; colliding with Personal fails.
      shell.openInlineEdit(
        InlineEditTarget.label('work000001', LabelSectionKind.title),
      );
      expect(
        await controller.saveLabelName('work000001', 'personal'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await controller.saveLabelName('work000001', 'WORK'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container.read(appShellControllerProvider).activeInlineEdit,
        isNull,
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.name,
        equals('WORK'),
      );

      // Note save and clear.
      shell.openInlineEdit(
        InlineEditTarget.label('work000001', LabelSectionKind.note),
      );
      expect(
        await controller.saveLabelNote('work000001', 'Scope guidelines'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.note,
        equals('Scope guidelines'),
      );
      expect(
        await controller.clearLabelNote('work000001'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.note,
        isNull,
      );

      // Links save.
      expect(
        await controller.saveLabelLinks(
          'work000001',
          const <EntityLinkViewModel>[
            EntityLinkViewModel(title: 'Wiki', uri: 'https://wiki.example'),
          ],
        ),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.links,
        hasLength(1),
      );

      // Color save and clear.
      expect(
        await controller.saveLabelColor('work000001', 'bad'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await controller.saveLabelColor('work000001', 'ff9100'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.color,
        equals('#FF9100'),
      );
      expect(
        await controller.clearLabelColor('work000001'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.color,
        isNull,
      );

      // Live Board Scope toggle persists immediately.
      expect(
        await controller.setLabelScoped('work000001', true),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.isScoped,
        isTrue,
      );
      expect(
        await controller.setLabelScoped('work000001', false),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.isScoped,
        isFalse,
      );

      // Conditions save and clear.
      expect(
        await controller.saveLabelConditions(
          'work000001',
          ConditionDraftViewModel(
            daysMode: ConditionDimensionMode.custom,
            selectedWeekdays: const <int>[1, 2],
            locationsMode: ConditionDimensionMode.custom,
            selectedLocationIds: const <String>['loc0000001'],
          ),
        ),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.conditions,
        hasLength(2),
      );
      expect(
        await controller.clearLabelConditions('work000001'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.conditions,
        isEmpty,
      );

      // Delete label wraps in runLocalEntityMutation, collapses, clears delete confirm, no Undo.
      const labelRef = EntityRef(kind: EntityKind.label, id: 'work000001');
      shell.expandEntity(labelRef);
      shell.requestInlineDelete(labelRef);
      final deleted = await controller.deleteLabel('work000001');
      expect(deleted, isA<ActionSucceeded>());
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001'),
        isNull,
      );
      final shellAfter = harness.container.read(appShellControllerProvider);
      expect(shellAfter.expandedEntity, isNull);
      expect(shellAfter.activeDeleteConfirm, isNull);
      final notice = harness.container.read(floatingNoticeControllerProvider);
      expect(notice?.message, equals(en.labelDeletedNotice));
      expect(notice?.hasUndoAction, isFalse);
      expect(harness.container.read(taskUndoStateProvider).canUndo, isFalse);
    });
  });

  group('EntityController Locations', () {
    test('quickCreateLocation seeds foreground GPS fix rounded to 6dp with 200m default radius or falls back to 0, 0', () async {
      final gpsHarness = createHarness(
        initialTdf: 'tdf 0.8.0\n',
        locationState: const LocationState.found(
          fix: LocationFix(latitude: 52.5200089, longitude: 13.4049541),
        ),
      );
      addTearDown(gpsHarness.container.dispose);
      await gpsHarness.container.read(taskNotifierProvider.future);
      final en = lookupAppLocalizations(const Locale('en'));

      final gpsController = gpsHarness.container.read(
        entityControllerProvider.notifier,
      );
      final gpsResult = await gpsController.quickCreateLocation('  Home  ');
      expect(gpsResult, isA<ActionSucceeded>());
      final gpsId = (gpsResult as ActionSucceeded).entityId ?? '';
      final createdWithGps = gpsHarness.container
          .read(taskNotifierProvider)
          .requireValue
          .findLocation(gpsId);
      expect(createdWithGps?.name, equals('Home'));
      expect(createdWithGps?.latitude, equals(52.520009));
      expect(createdWithGps?.longitude, equals(13.404954));
      expect(createdWithGps?.radius, equals(200.0));
      expect(
        gpsHarness.container.read(appShellControllerProvider).expandedEntity,
        equals(EntityRef(kind: EntityKind.location, id: gpsId)),
      );
      expect(
        gpsHarness.container.read(floatingNoticeControllerProvider)?.message,
        equals(en.locationSavedNotice),
      );

      // Fallback when no GPS fix is available.
      final noFixHarness = createHarness(initialTdf: 'tdf 0.8.0\n');
      addTearDown(noFixHarness.container.dispose);
      await noFixHarness.container.read(taskNotifierProvider.future);

      final noFixController = noFixHarness.container.read(
        entityControllerProvider.notifier,
      );
      final noFixResult = await noFixController.quickCreateLocation('Fallback');
      expect(noFixResult, isA<ActionSucceeded>());
      final noFixId = (noFixResult as ActionSucceeded).entityId ?? '';
      final createdFallback = noFixHarness.container
          .read(taskNotifierProvider)
          .requireValue
          .findLocation(noFixId);
      expect(createdFallback?.latitude, equals(0.0));
      expect(createdFallback?.longitude, equals(0.0));
      expect(createdFallback?.radius, equals(200.0));
    });

    test('createLocationDraft parses radius bounds (0.01m..100km, m/km, comma/dot), coordinates, source, note, and closes draft', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.info,
        persistToDisk: false,
      );
      final harness = createHarness(initialTdf: 'tdf 0.8.0\n');
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);
      final en = lookupAppLocalizations(const Locale('en'));

      final controller = harness.container.read(
        entityControllerProvider.notifier,
      );
      final shell = harness.container.read(appShellControllerProvider.notifier);

      // Valid radius cases (dot, comma, m, km, extremes 0.01m and 100km).
      final radiusCases = <({String input, double expectedMeters})>[
        (input: '0.01m', expectedMeters: 0.01),
        (input: '0,01m', expectedMeters: 0.01),
        (input: '0.00001km', expectedMeters: 0.01),
        (input: '250', expectedMeters: 250.0),
        (input: '1,5km', expectedMeters: 1500.0),
        (input: '1.25 KM', expectedMeters: 1250.0),
        (input: '100000m', expectedMeters: 100000.0),
        (input: '100km', expectedMeters: 100000.0),
        (input: '100,0km', expectedMeters: 100000.0),
      ];
      for (var i = 0; i < radiusCases.length; i++) {
        final testCase = radiusCases[i];
        shell.openDraft(EntityDraftKind.location);
        final result = await controller.createLocationDraft(
          LocationDraftInput(
            name: 'Place $i',
            sourceType: ShellLocationSourceType.address,
            rawSource: 'Alexanderplatz, Berlin',
            rawLatitude: '52,521918',
            rawLongitude: '13,413215',
            rawRadius: testCase.input,
            note: 'Floor 2\r\nSecret entry code',
          ),
        );
        expect(
          result,
          isA<ActionSucceeded>(),
          reason: 'Expected radius "${testCase.input}" to succeed',
        );
        final createdId = (result as ActionSucceeded).entityId ?? '';
        final location = harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLocation(createdId);
        expect(
          location?.radius,
          equals(testCase.expectedMeters),
          reason: 'Radius mismatch for "${testCase.input}"',
        );
        expect(location?.latitude, equals(52.521918));
        expect(location?.longitude, equals(13.413215));
        expect(location?.source, equals('Alexanderplatz, Berlin'));
        expect(location?.note, equals('Floor 2\nSecret entry code'));
        expect(
          harness.container.read(appShellControllerProvider).activeDraft,
          isNull,
        );
      }

      final logText = AppLogger.fullLogText;
      expect(logText, contains('ui.entity_draft_committed | kind=location'));
      expect(logText, isNot(contains('Secret entry code')));
      expect(logText, isNot(contains('Alexanderplatz')));
      expect(logText, isNot(contains('52.521918')));

      // Invalid radii rejected.
      for (final badRadius in const <String>[
        '',
        '0',
        '0.009m',
        '0,004m',
        '-10m',
        '100.01km',
        '100,01km',
        '100001',
        '1,2.3m',
        'NaN',
        '100m\n',
      ]) {
        final rejected = await controller.createLocationDraft(
          LocationDraftInput(
            name: 'BadRadius',
            rawLatitude: '52.52',
            rawLongitude: '13.405',
            rawRadius: badRadius,
          ),
        );
        expect(
          rejected,
          isA<ActionValidationFailed>(),
          reason: 'Expected radius "$badRadius" to be rejected',
        );
        expect(
          (rejected as ActionValidationFailed).fieldErrors['radius'],
          equals(en.locationRadiusErrorInvalid),
        );
      }

      // Invalid coordinates rejected.
      for (final badCoordinates in const <({String lat, String lon})>[
        (lat: '90.01', lon: '0'),
        (lat: '-90.01', lon: '0'),
        (lat: '0', lon: '180.01'),
        (lat: '0', lon: '-180.01'),
        (lat: 'NaN', lon: '0'),
        (lat: '', lon: '13.4'),
      ]) {
        final rejected = await controller.createLocationDraft(
          LocationDraftInput(
            name: 'BadCoordinates',
            rawLatitude: badCoordinates.lat,
            rawLongitude: badCoordinates.lon,
            rawRadius: '100m',
          ),
        );
        expect(
          rejected,
          isA<ActionValidationFailed>(),
          reason:
              'Expected coordinates (${badCoordinates.lat}, ${badCoordinates.lon}) to fail',
        );
        expect(
          (rejected as ActionValidationFailed).fieldErrors['coordinates'],
          equals(en.locationCoordinatesErrorInvalid),
        );
      }

      // Control chars or >500 scalars in non-GPS source rejected.
      final controlSource = await controller.createLocationDraft(
        const LocationDraftInput(
          name: 'BadSource',
          sourceType: ShellLocationSourceType.address,
          rawSource: 'Berlin\x00Null',
          rawLatitude: '52.52',
          rawLongitude: '13.405',
          rawRadius: '100m',
        ),
      );
      expect(controlSource, isA<ActionValidationFailed>());
      expect(
        (controlSource as ActionValidationFailed).fieldErrors['source'],
        equals(en.locationSourceErrorEmpty),
      );

      final overlongSource = await controller.createLocationDraft(
        LocationDraftInput(
          name: 'LongSource',
          sourceType: ShellLocationSourceType.address,
          rawSource: 's' * (maxTdfTextLength + 1),
          rawLatitude: '52.52',
          rawLongitude: '13.405',
          rawRadius: '100m',
        ),
      );
      expect(overlongSource, isA<ActionValidationFailed>());
      expect(
        (overlongSource as ActionValidationFailed).fieldErrors['source'],
        equals(en.locationSourceErrorEmpty),
      );
    });

    test('enforces maxTdfLocations = 200 bound in quickCreateLocation and createLocationDraft', () async {
      final buffer = StringBuffer('tdf 0.8.0\n');
      for (var i = 0; i < maxTdfLocations - 1; i++) {
        final idSuffix = i.toString().padLeft(6, '0');
        buffer.writeln('''
location locA$idSuffix {
  name "Loc $i"
  coordinates 52.52 13.405
  radius 100
  modified 2026-11-01 08:00:00
}''');
      }
      final harness = createHarness(initialTdf: buffer.toString());
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);
      final controller = harness.container.read(
        entityControllerProvider.notifier,
      );

      // 200th location succeeds.
      final atLimit = await controller.quickCreateLocation('Location 200');
      expect(
        atLimit,
        isA<ActionSucceeded>(),
        reason: '200th location must succeed',
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .locations
            .length,
        equals(maxTdfLocations),
      );

      // 201st location fails in both quickCreateLocation and createLocationDraft.
      final quickOverflow = await controller.quickCreateLocation(
        'Location 201',
      );
      expect(quickOverflow, isA<ActionValidationFailed>());
      expect(
        harness.container.read(floatingNoticeControllerProvider)?.tone,
        equals(NoticeTone.danger),
      );

      final draftOverflow = await controller.createLocationDraft(
        const LocationDraftInput(
          name: 'Draft 201',
          rawLatitude: '52.52',
          rawLongitude: '13.405',
          rawRadius: '100m',
        ),
      );
      expect(draftOverflow, isA<ActionValidationFailed>());
    });

    test('inline location saves (name, note, coordinates/source) and deleteLocation without Undo', () async {
      final harness = createHarness();
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);
      final en = lookupAppLocalizations(const Locale('en'));

      final controller = harness.container.read(
        entityControllerProvider.notifier,
      );
      final shell = harness.container.read(appShellControllerProvider.notifier);

      // Name save.
      shell.openInlineEdit(
        InlineEditTarget.location('loc0000001', LocationSectionKind.title),
      );
      expect(
        await controller.saveLocationName('loc0000001', 'HQ Berlin'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLocation('loc0000001')
            ?.name,
        equals('HQ Berlin'),
      );
      expect(
        harness.container.read(appShellControllerProvider).activeInlineEdit,
        isNull,
      );

      // Note save and clear.
      expect(
        await controller.saveLocationNote('loc0000001', 'North wing'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLocation('loc0000001')
            ?.note,
        equals('North wing'),
      );
      expect(
        await controller.clearLocationNote('loc0000001'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLocation('loc0000001')
            ?.note,
        isNull,
      );

      // Coordinates & source update, then switching to GPS clears source.
      expect(
        await controller.saveLocationCoordinates(
          'loc0000001',
          sourceType: ShellLocationSourceType.plusCode,
          rawSource: '9F4MG9X5+XX Berlin',
          rawLatitude: '52.549938',
          rawLongitude: '13.359938',
          rawRadius: '0,5km',
        ),
        isA<ActionSucceeded>(),
      );
      var updated = harness.container
          .read(taskNotifierProvider)
          .requireValue
          .findLocation('loc0000001');
      expect(updated?.source, equals('9F4MG9X5+XX Berlin'));
      expect(updated?.radius, equals(500.0));

      expect(
        await controller.saveLocationCoordinates(
          'loc0000001',
          sourceType: ShellLocationSourceType.gps,
          rawSource: 'ignored in gps mode',
          rawLatitude: '52.52',
          rawLongitude: '13.405',
          rawRadius: '100m',
        ),
        isA<ActionSucceeded>(),
      );
      updated = harness.container
          .read(taskNotifierProvider)
          .requireValue
          .findLocation('loc0000001');
      expect(updated?.source, isNull);
      expect(updated?.radius, equals(100.0));

      // Delete location collapses card, clears delete confirm, no Undo.
      const locationRef = EntityRef(
        kind: EntityKind.location,
        id: 'loc0000001',
      );
      shell.expandEntity(locationRef);
      shell.requestInlineDelete(locationRef);
      expect(
        await controller.deleteLocation('loc0000001'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLocation('loc0000001'),
        isNull,
      );
      final shellAfter = harness.container.read(appShellControllerProvider);
      expect(shellAfter.expandedEntity, isNull);
      expect(shellAfter.activeDeleteConfirm, isNull);
      final notice = harness.container.read(floatingNoticeControllerProvider);
      expect(notice?.message, equals(en.locationDeletedNotice));
      expect(notice?.hasUndoAction, isFalse);

      // Editing missing label or location returns validation failure cleanly.
      expect(
        await controller.saveLabelName('missing001', 'Name'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await controller.setLabelScoped('missing001', true),
        isA<ActionValidationFailed>(),
      );
      expect(
        await controller.saveLocationName('missing001', 'Place'),
        isA<ActionValidationFailed>(),
      );
    });
  });

  group('EntityController GPS, Address & Plus Code resolution', () {
    test('resolveCurrentGpsPosition refreshes missing fix, formats 6dp, and emits gpsAppliedNotice', () async {
      final harness = createHarness(
        locationState: const LocationState.unavailable(),
        refreshedFix: const LocationFix(
          latitude: 52.5200089,
          longitude: 13.4049541,
        ),
      );
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);
      final en = lookupAppLocalizations(const Locale('en'));

      final controller = harness.container.read(
        entityControllerProvider.notifier,
      );
      final resolved = await controller.resolveCurrentGpsPosition();
      expect(resolved, isNotNull);
      expect(resolved?.latitudeText, equals('52.520009'));
      expect(resolved?.longitudeText, equals('13.404954'));
      expect(harness.locationNotifier.refreshCalls, equals(1));
      expect(
        harness.container.read(floatingNoticeControllerProvider)?.message,
        equals(en.gpsAppliedNotice),
      );

      // Unavailable GPS returns null without emitting gpsAppliedNotice.
      final unavailableHarness = createHarness(
        locationState: const LocationState.unavailable(),
      );
      addTearDown(unavailableHarness.container.dispose);
      await unavailableHarness.container.read(taskNotifierProvider.future);
      final unavailableController = unavailableHarness.container.read(
        entityControllerProvider.notifier,
      );
      expect(await unavailableController.resolveCurrentGpsPosition(), isNull);
      expect(
        unavailableHarness.container.read(floatingNoticeControllerProvider),
        isNull,
      );
    });

    test('resolveLocationSource handles full Plus Code, single/multi address, short Plus Code disambiguation, and tracks isResolvingLocation', () async {
      final harness = createHarness();
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);
      final en = lookupAppLocalizations(const Locale('en'));

      final controller = harness.container.read(
        entityControllerProvider.notifier,
      );

      // Full Plus Code resolves offline without calling geocoder.
      final fullPlus = await controller.resolveLocationSource(
        sourceType: ShellLocationSourceType.plusCode,
        rawSource: '9F4MG9X5+XX Berlin',
      );
      expect(fullPlus, isA<LocationSourceUiResolved>());
      final resolvedPlus = fullPlus as LocationSourceUiResolved;
      expect(resolvedPlus.sourceType, equals(ShellLocationSourceType.plusCode));
      expect(resolvedPlus.normalizedSource, equals('9F4MG9X5+XX Berlin'));
      expect(
        harness.container.read(floatingNoticeControllerProvider)?.message,
        equals(en.locationResolvedNotice),
      );

      // Control char injection rejected upfront.
      final controlInjected = await controller.resolveLocationSource(
        sourceType: ShellLocationSourceType.address,
        rawSource: 'Berlin\nInjected',
      );
      expect(controlInjected, isA<LocationSourceUiError>());

      // Multi-candidate address resolution tracks isResolvingLocation while in-flight.
      final completer = Completer<List<GeocodingCandidate>>();
      harness.locationRepository.nextSearchCompleter = completer;

      final future = controller.resolveLocationSource(
        sourceType: ShellLocationSourceType.address,
        rawSource: 'Springfield',
      );
      expect(
        harness.container.read(entityControllerProvider).isResolvingLocation,
        isTrue,
      );

      completer.complete(const <GeocodingCandidate>[
        GeocodingCandidate(
          displayName: 'Springfield, IL',
          latitude: 39.7817,
          longitude: -89.6501,
        ),
        GeocodingCandidate(
          displayName: 'Springfield, OR',
          latitude: 44.0462,
          longitude: -123.0220,
        ),
      ]);
      final multiAddress = await future;
      expect(
        harness.container.read(entityControllerProvider).isResolvingLocation,
        isFalse,
      );
      expect(multiAddress, isA<LocationSourceUiNeedsDisambiguation>());
      final disambiguation =
          multiAddress as LocationSourceUiNeedsDisambiguation;
      expect(disambiguation.candidates, hasLength(2));
      expect(disambiguation.candidates[0].index, equals(0));
      expect(
        disambiguation.candidates[1].displayName,
        equals('Springfield, OR'),
      );

      // Out-of-bounds candidate index returns error without clearing cache.
      expect(
        controller.applyDisambiguatedCandidate(
          candidateIndex: 99,
          sourceType: ShellLocationSourceType.address,
        ),
        isA<LocationSourceUiError>(),
      );

      // Valid candidate index resolves cleanly and clears cache afterward.
      final appliedAddress = controller.applyDisambiguatedCandidate(
        candidateIndex: 1,
        sourceType: ShellLocationSourceType.address,
      );
      expect(appliedAddress, isA<LocationSourceUiResolved>());
      expect(
        (appliedAddress as LocationSourceUiResolved).normalizedSource,
        equals('Springfield, OR'),
      );
      expect(
        controller.applyDisambiguatedCandidate(
          candidateIndex: 1,
          sourceType: ShellLocationSourceType.address,
        ),
        isA<LocationSourceUiError>(),
        reason: 'Cached candidates must clear after successful selection',
      );

      // GPS source mode and empty address matches return LocationSourceUiError.
      expect(
        await controller.resolveLocationSource(
          sourceType: ShellLocationSourceType.gps,
          rawSource: 'Berlin',
        ),
        isA<LocationSourceUiError>(),
      );
      harness.locationRepository.searchResults = const <GeocodingCandidate>[];
      expect(
        await controller.resolveLocationSource(
          sourceType: ShellLocationSourceType.address,
          rawSource: 'Nowhere',
        ),
        isA<LocationSourceUiError>(),
      );

      // Single address match resolves directly without disambiguation.
      harness.locationRepository.searchResults = const <GeocodingCandidate>[
        GeocodingCandidate(
          displayName: 'Munich, Germany',
          latitude: 48.1351,
          longitude: 11.5820,
        ),
      ];
      final singleAddress = await controller.resolveLocationSource(
        sourceType: ShellLocationSourceType.address,
        rawSource: 'Munich',
      );
      expect(singleAddress, isA<LocationSourceUiResolved>());
      expect(
        (singleAddress as LocationSourceUiResolved).normalizedSource,
        equals('Munich, Germany'),
      );

      // Short Plus Code with multiple locality matches resolves via applyDisambiguatedCandidate.
      harness.locationRepository.searchResults = const <GeocodingCandidate>[
        GeocodingCandidate(
          displayName: 'Springfield, IL',
          latitude: 39.7817,
          longitude: -89.6501,
        ),
        GeocodingCandidate(
          displayName: 'Springfield, OR',
          latitude: 44.0462,
          longitude: -123.0220,
        ),
      ];
      final shortPlus = await controller.resolveLocationSource(
        sourceType: ShellLocationSourceType.plusCode,
        rawSource: 'G9X5+XX Springfield',
      );
      expect(shortPlus, isA<LocationSourceUiNeedsDisambiguation>());
      final shortDisambiguation =
          shortPlus as LocationSourceUiNeedsDisambiguation;
      expect(shortDisambiguation.shortPlusCode, equals('G9X5+XX'));

      final appliedShort = controller.applyDisambiguatedCandidate(
        candidateIndex: 0,
        sourceType: ShellLocationSourceType.plusCode,
        shortPlusCode: shortDisambiguation.shortPlusCode,
      );
      expect(appliedShort, isA<LocationSourceUiResolved>());
      expect(
        (appliedShort as LocationSourceUiResolved).normalizedSource,
        equals('G9X5+XX Springfield'),
      );
    });
  });

  group('EntityController delimiter round-trip, busy guard & errors', () {
    test('round-trips quotes, backslashes, braces, and # comments cleanly through TDF 0.8.0 persistence', () async {
      final harness = createHarness(initialTdf: 'tdf 0.8.0\n');
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);
      final controller = harness.container.read(
        entityControllerProvider.notifier,
      );

      const labelName = r'Work "Q1" {urgent} #core \ team';
      const labelNote = 'Line 1 #comment\n"quoted" \\ {braces}';
      const locationName = r'Cafe "Alpha" {North} #2 \ Patio';
      const locationSource = r'123 "Main" St {Unit 4} #back \ Entrance';

      final labelResult = await controller.createLabelDraft(
        LabelDraftInput(
          name: labelName,
          note: labelNote,
          links: const <EntityLinkViewModel>[
            EntityLinkViewModel(
              title: r'Doc "1" {spec} #top \ link',
              uri: 'https://example.com/a?x=1#frag',
            ),
          ],
        ),
      );
      expect(labelResult, isA<ActionSucceeded>());

      final locationResult = await controller.createLocationDraft(
        const LocationDraftInput(
          name: locationName,
          sourceType: ShellLocationSourceType.address,
          rawSource: locationSource,
          rawLatitude: '52.52',
          rawLongitude: '13.405',
          rawRadius: '150m',
          note: labelNote,
        ),
      );
      expect(locationResult, isA<ActionSucceeded>());

      final parsed = const TdfService().parse(
        harness.localRepository.initialTdf,
      );
      expect(parsed.labels.single.name, equals(labelName));
      expect(parsed.labels.single.note, equals(labelNote));
      expect(
        parsed.labels.single.links.single.title,
        equals(r'Doc "1" {spec} #top \ link'),
      );
      expect(parsed.locations.single.name, equals(locationName));
      expect(parsed.locations.single.source, equals(locationSource));
      expect(parsed.locations.single.note, equals(labelNote));
    });

    test('serializes mid-flight mutations via isBusy and surfaces sanitized ActionPersistFailed on error', () async {
      final initialBoard = TaskBoard.empty().addLabel(
        'Work',
        id: 'work000001',
        currentDate: DateTime.utc(2026, 11, 21),
      );
      final blockingNotifier = _BlockingTaskNotifier(initialBoard);
      final container = ProviderContainer(
        overrides: [
          taskNotifierProvider.overrideWith(() => blockingNotifier),
          appLocaleProvider.overrideWithValue(const Locale('de')),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 21, 12)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);
      final de = lookupAppLocalizations(const Locale('de'));

      final controller = container.read(entityControllerProvider.notifier);
      final completer = Completer<void>();
      blockingNotifier.nextMutationCompleter = completer;

      final firstFuture = controller.quickCreateLabel('Queued');
      expect(container.read(entityControllerProvider).isBusy, isTrue);

      // Overlapping call rejected immediately while busy.
      final overlapping = await controller.quickCreateLabel('Concurrent');
      expect(overlapping, isA<ActionPersistFailed>());

      completer.complete();
      expect(await firstFuture, isA<ActionSucceeded>());
      expect(container.read(entityControllerProvider).isBusy, isFalse);

      // Persistence exception returns sanitized localized ActionPersistFailed without leaking raw text.
      blockingNotifier.nextError = Exception('SENSITIVE_SECRET_TOKEN_XYZ');
      final failed = await controller.saveLabelName(
        'work000001',
        'Renamed',
        locale: const Locale('de'),
      );
      expect(failed, isA<ActionPersistFailed>());
      final persistFailure = failed as ActionPersistFailed;
      expect(
        persistFailure.message,
        isNot(contains('SENSITIVE_SECRET_TOKEN_XYZ')),
      );
      expect(persistFailure.message, isNotEmpty);

      // TdfException persistence error maps to specific localized error string.
      blockingNotifier.nextError = const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: 'raw internal detail',
      );
      final tdfFailed = await controller.saveLabelName(
        'work000001',
        'Renamed',
        locale: const Locale('de'),
      );
      expect(tdfFailed, isA<ActionPersistFailed>());
      expect(
        (tdfFailed as ActionPersistFailed).message,
        equals(de.errorLocalFileTooLarge),
      );

      // German locale validation message check.
      final germanEmpty = await controller.quickCreateLabel(
        '   ',
        locale: const Locale('de'),
      );
      expect(germanEmpty, isA<ActionValidationFailed>());
      expect(
        (germanEmpty as ActionValidationFailed).message,
        equals(de.labelNameErrorEmpty),
      );
    });
  });
}
