---
id: TEP-005
title: Selectable Location Source Resolution, Offline Open Location Code Decoding, and Forward Geocoding Disambiguation
status: review
type: feature
created: 2026-11-08
updated: 2026-11-09
---

# TEP-005: Selectable Location Source Resolution, Offline Open Location Code Decoding, and Forward Geocoding Disambiguation

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal enhances the location editor (`EditLocationScreen` in `lib/ui/edit_locations_screen.dart`) to support structured source selection via a three-option dropdown (`LocationSourceType`: `gps`, `address`, `plusCode`), mode-dependent field locking (disabling the source text field and enabling direct coordinate input when `gps` is selected; locking `latitude` and `longitude` as read-only and enabling the source text field and a `Resolve` button when `address` or `plusCode` is selected), pure offline Open Location Code (Google Plus Code) decoding and nearest-locality recovery (`PlusCodeService` in `lib/services/plus_code_service.dart`), bounded OpenStreetMap Nominatim forward geocoding (`LocationRepository.searchLocations` in `lib/repositories/location_repository.dart`), and a modal candidate selection dialog when an address or short Plus Code locality resolves to multiple matches.

### 1.2 Motivation
In the current `EditLocationScreen` implementation (`lib/ui/edit_locations_screen.dart`), `location.source` is an unstructured free-text input field next to `radius`, and users must manually type decimal WGS-84 `latitude` and `longitude` values or copy their current hardware GPS position:
1. **No Address or Plus Code Resolution:** Although `spec/TDF_SPEC_0.6.0.md` Section 4.3 defines `location.source` as an optional human- or tool-readable street address (`"Bahnhofstraße 1, 99084 Erfurt"`) or Open Location Code / Google Plus Code (`"9F2PXXH7+F4"`), the UI offers no mechanism to resolve an entered address or Plus Code into WGS-84 coordinates.
2. **Inconsistent Coordinate Editing State:** Users can simultaneously enter an arbitrary `source` string and unrelated manual `latitude`/`longitude` coordinates without visual separation between direct GPS coordinate entry and source-derived coordinates.
3. **Ambiguous Address Queries:** Street addresses or city names frequently match multiple geographic locations (for example, `"Hauptbahnhof"` or `"Bahnhofstraße 1"`), requiring an explicit user disambiguation step when forward geocoding returns more than one candidate.

### 1.3 Goals & Non-Goals
* **Goals:**
  1. Add a `LocationSourceType` dropdown (`gps`, `address`, `plusCode`) to `EditLocationScreen` that deterministically governs input field state:
     - When `LocationSourceType.gps` is active, disable the source text field, allow direct editing of `latitude` and `longitude`, and enable the `Use Current GPS Position` button.
     - When `LocationSourceType.address` or `LocationSourceType.plusCode` is active, lock `latitude` and `longitude` as read-only (`readOnly: true`, clear button suppressed), enable the source text field, and enable the `Resolve` button.
  2. Implement a pure, zero-I/O Open Location Code service (`PlusCodeService` in `lib/services/plus_code_service.dart`) supporting full Plus Code offline decoding (`8` prefix digits before `+`, preserving optional locality suffixes), short Plus Code extraction with locality query (`4` or `6` prefix digits before `+` paired with a locality name), and `recoverNearest` coordinate reconstruction per the Apache-2.0 Open Location Code specification.
  3. Extend `LocationRepository` (`PlatformLocationRepository` and `FakeLocationRepository` in `lib/repositories/location_repository.dart`) with bounded forward geocoding (`searchLocations(String query)`) against OpenStreetMap Nominatim (`GET /search?format=jsonv2&addressdetails=1&limit=5&q=<query>`), enforcing single-line `<text>` normalization and rate-limit hygiene.
  4. Present a modal candidate disambiguation dialog in `EditLocationScreen` whenever `searchLocations` returns `2..5` candidates, updating the read-only `latitude` and `longitude` fields (and setting the resolved address in `Address` mode) upon selection.
  5. Preserve full compliance with `spec/TDF_SPEC_0.6.0.md` Section 4.3, keeping `location.source` strictly passive during parsing, migration, synchronization, and 6-tier evaluation, and redacting queries, addresses, and coordinates from diagnostic logs.
* **Non-Goals:**
  1. **What3words Integration:** What3words does not offer a public unauthenticated API and removed coordinate conversion from its free plan (requiring a registered API key and a paid monthly subscription, while its algorithm is proprietary and patented). What3words is therefore excluded from the dropdown.
  2. **Automatic Background Geocoding:** In accordance with `spec/TDF_SPEC_0.6.0.md` Section 4.3 (Normative SSRF & Passive-Metadata Security Rule), TDF parsers, migrators, reconcilers, and 6-tier evaluators never invoke geocoding services automatically; resolution occurs exclusively on explicit user interaction in `EditLocationScreen`.
  3. **Changes to `.tdf` File Grammar:** The TDF `0.6.0` `location` block schema (`name`, `note`, `source`, `coordinates`, `radius`, `modified`) in `spec/TDF_SPEC_0.6.0.md` Section 4.3 remains unchanged.

### 1.4 Description

#### 1.4.1 Source Type Classification, Dropdown Behavior & Derived Resolution State
When `EditLocationScreen` opens for an existing `TdfLocation`, `PlusCodeService.classifySource(location.source)` determines the initial `LocationSourceType`:
1. **`LocationSourceType.gps`:** Selected when `location.source` is `null`, empty/whitespace, `'gps'`, or `'manual'` (case-insensitive). The source text controller is initialized to `''` and disabled (`enabled: false`). The `latitude` and `longitude` text fields are editable (`readOnly: false`). Tapping `Use Current GPS Position` populates `latitude` and `longitude` without writing `'gps'` into `_sourceController.text`. When saved in `gps` mode (or when a new location is created in `EditLocationsScreen._submitCreateLocation`), `source` is omitted (`source: null`, `clearSource: true`).
2. **`LocationSourceType.plusCode`:** Selected when `location.source` parses as a valid full Plus Code (for example, `"9F2PXXH7+F4"` or `"9F2PXXH7+F4 Erfurt"`) or a valid short Plus Code with locality (for example, `"XXH7+F4 Erfurt"` or `"Erfurt, XXH7+F4"`). The source text field is enabled (`enabled: true`), and `latitude` and `longitude` are read-only (`readOnly: true`).
3. **`LocationSourceType.address`:** Selected for any other non-empty `location.source` string (for example, `"Bahnhofstraße 1, 99084 Erfurt"`). The source text field is enabled (`enabled: true`), and `latitude` and `longitude` are read-only (`readOnly: true`).

Resolution state in `EditLocationScreen` is derived deterministically from two tracked anchors (`LocationSourceType? _resolvedSourceType` and `String? _resolvedSourceText`):
```dart
bool get _isSourceResolved =>
    _sourceType == LocationSourceType.gps ||
    (_resolvedSourceType == _sourceType &&
        _resolvedSourceText == _sourceController.text.trim() &&
        (_resolvedSourceText?.isNotEmpty ?? false));
```
* When opening `EditLocationScreen` for an existing location whose initial `_sourceType` is `address` or `plusCode`, `_resolvedSourceType` is initialized to `_sourceType` and `_resolvedSourceText` is initialized to `_sourceController.text.trim()`.
* Whenever the user edits `_sourceController.text` or switches `_sourceType` between `address` and `plusCode`, `_isSourceResolved` automatically evaluates to `false` (unless the text and mode match the last resolved anchor) until `_resolveSource()` succeeds and updates `_resolvedSourceType` and `_resolvedSourceText` to the normalized value.
* Switching to `LocationSourceType.gps` disables the source text field, makes `latitude` and `longitude` editable, increments `_resolveGeneration` to cancel any in-flight resolution, and clears any source resolution error.

#### 1.4.2 Resolution Flows (`Resolve` Button, In-Flight Locking & Save Guard)
While a resolution operation is active (`_isResolving == true`), `location_editor_source_type_dropdown`, `location_editor_source_input`, and `location_editor_resolve_button` are disabled (`enabled: false` / `onPressed: null`) to prevent concurrent duplicate requests and conflicting mode switches. An incrementing `int _resolveGeneration` counter guards every asynchronous gap (`await searchLocations` and `await showDialog`): if `!mounted || currentGeneration != _resolveGeneration`, the stale continuation exits immediately without mutating controllers or state.

1. **Address Mode (`LocationSourceType.address`):**
   - Clicking `Resolve` (or pressing Enter in the source text field) trims the source text. If empty or exceeding `PlatformLocationRepository.maxSearchQueryLength` (`500` characters), an inline validation error (`locationResolveErrorNotFound`) is displayed.
   - Otherwise, `EditLocationScreen` increments `_resolveGeneration`, sets `_isResolving = true`, and awaits `ref.read(locationRepositoryProvider).searchLocations(trimmedSource)`:
     - **0 candidates:** Displays `locationResolveErrorNotFound`.
     - **1 candidate:** Populates `_latController` and `_lonController` with `TdfLocation.formatRoundedDouble(candidate.latitude, 6)` and `TdfLocation.formatRoundedDouble(candidate.longitude, 6)`, updates `_sourceController.text` to the already single-line normalized and `maxTdfTextLength`-bounded `candidate.displayName`, and records `_resolvedSourceType = LocationSourceType.address` and `_resolvedSourceText = candidate.displayName`.
     - **2..5 candidates:** Opens the modal candidate selection dialog (`_LocationCandidateDialog`) displaying each candidate's `displayName` and 6-decimal `formattedCoordinates` (`lat, lon`). If the user selects a candidate, populates `_latController`, `_lonController`, and `_sourceController.text` with `candidate.displayName` and records `_resolvedSourceType = LocationSourceType.address` and `_resolvedSourceText = candidate.displayName`. If the user dismisses the dialog without selecting a candidate, `_resolvedSourceType` and `_resolvedSourceText` remain unchanged (`_isSourceResolved` remains `false`).
2. **Google Plus Code Mode (`LocationSourceType.plusCode`):**
   - Clicking `Resolve` parses the input via `PlusCodeService.parseInput(trimmedSource)`:
     - **`InvalidPlusCodeInput`:** Displays `locationResolveErrorInvalidPlusCode`.
     - **`FullPlusCodeInput(fullCode, localitySuffix)`:** Decodes `fullCode` purely offline via `PlusCodeService.decode(fullCode)` without network I/O, populates `_latController` and `_lonController` with the decoded center coordinates rounded to at most 6 decimal places, normalizes `_sourceController.text` to `PlusCodeService.truncateToMaxTextLength(localitySuffix == null || localitySuffix.isEmpty ? fullCode : '$fullCode $localitySuffix')` so human-readable locality context is preserved, and updates `_resolvedSourceType = LocationSourceType.plusCode` and `_resolvedSourceText = _sourceController.text`.
     - **`ShortPlusCodeInput(shortCode, localityQuery)`:** Increments `_resolveGeneration`, sets `_isResolving = true`, and calls `searchLocations(localityQuery)` to resolve the reference locality:
       - **0 candidates:** Displays `locationResolveErrorNotFound`.
       - **1 candidate (or user-selected candidate from `_LocationCandidateDialog` when 2..5 candidates match):** Recovers the full Plus Code via `PlusCodeService.recoverNearest(shortCode, candidate.latitude, candidate.longitude)`, decodes its center coordinates, populates `_latController` and `_lonController` rounded to at most 6 decimal places, normalizes `_sourceController.text` to `PlusCodeService.truncateToMaxTextLength('$shortCode $localityQuery')` (preserving the concise user-entered locality name rather than overwriting it with a verbose multi-part Nominatim address string), and records `_resolvedSourceType = LocationSourceType.plusCode` and `_resolvedSourceText = _sourceController.text`.
3. **Save Guard on Unresolved Source:**
   - When the user clicks `Save` in `Address` or `Plus Code` mode while `_isSourceResolved` is `false`, `_submit()` automatically invokes `_resolveSource()` first. If `_resolveSource()` succeeds (`_isSourceResolved == true`), `_submit()` validates `name`, `latitude`, `longitude`, and `radius` and persists the updated `TdfLocation`; otherwise, persistence is aborted and the error message remains visible.

### 1.5 Alternatives
1. **Including What3words with User-Configured API Key in Settings:** Rejected because What3words no longer allows coordinate conversion on its free tier, requiring every user to purchase a commercial subscription and manage a secret API key in settings for a proprietary format.
2. **Third-Party `open_location_code` Pub Package:** Rejected under `P-STDLIB-FIRST` (`AGENTS.md` Section 1). The Open Location Code specification is a compact base-20 and $4 \times 5$ grid mathematical algorithm that can be implemented cleanly in pure Dart (`lib/services/plus_code_service.dart`) with zero external dependencies and full static analysis compliance.
3. **Automatic Debounced Geocoding on Every Keystroke:** Rejected to respect OpenStreetMap Nominatim usage policy (maximum 1 request per second, no bulk autocomplete keystroke polling) and avoid unnecessary network traffic; explicit resolution via the `Resolve` button (guarded by UI button disabling while `_isResolving == true` and repository-level rate-limit hygiene) is deterministic and user-controlled.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules

| Layer | File | Change Type | Responsibility |
| :--- | :--- | :--- | :--- |
| Models (`Rank 1`) | `lib/models/location_state.dart` | Modify | Add `LocationSourceType` enum (`gps`, `address`, `plusCode`) and immutable `GeocodingCandidate` value class with 6-decimal `formattedCoordinates`. |
| Localization (`Rank 2`) | `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | Modify | Add English and German localization keys for source type dropdown labels, input hints, `Resolve` button, candidate selection dialog, and validation errors. |
| Services (`Rank 3`) | `lib/services/plus_code_service.dart` | New | Stateless, zero-I/O Open Location Code (Google Plus Code) validator, parser (`PlusCodeInput`), encoder, decoder (`PlusCodeArea`), nearest-reference recovery (`recoverNearest`), Unicode scalar text truncation, and `TdfLocation.source` classifier. |
| Repositories (`Rank 4`) | `lib/repositories/location_repository.dart` | Modify | Add `searchLocations(String query)` to `LocationRepository`, `PlatformLocationRepository` (Nominatim `/search?format=jsonv2` with rate-limit guard and single-line `<text>` sanitization), and `FakeLocationRepository`. |
| UI (`Rank 6`) | `lib/ui/widgets/clearable_text_field.dart` | Modify | Add `enabled` (`bool`, default `true`) and `readOnly` (`bool`, default `false`) parameters, hiding the clear suffix button when `!enabled || readOnly`. |
| UI (`Rank 6`) | `lib/ui/edit_locations_screen.dart` | Modify | Add source type dropdown, read-only coordinate locking, `Resolve` button, in-flight control locking, `_LocationCandidateDialog`, and save-time resolution guard in `EditLocationScreen`; omit redundant `'manual'`/`'gps'` source strings when creating new locations in `EditLocationsScreen`. |
| Tests | `test/models/location_state_test.dart`, `test/services/plus_code_service_test.dart`, `test/repositories/location_repository_test.dart`, `test/ui/edit_locations_screen_test.dart` | Modify / New | Unit and widget test suites covering all new models, OLC decoding/recovery vectors, repository forward geocoding bounds/sanitization/cooldowns, and UI source resolution flows. |

### 2.2 TDF Schema, Localization & State Changes

#### 2.2.1 TDF `0.6.0` Schema Impact
No grammar or semantic changes to `spec/TDF_SPEC_0.6.0.md` are required. `spec/TDF_SPEC_0.6.0.md` Section 4.3 already specifies `source "<text>"` (`0..1`, `1..MAX_TEXT_LENGTH` Unicode scalar values, single-line without `\n`, `\r`, or `\t`) for street addresses and Open Location Codes / Google Plus Codes, and mandates that `coordinates <lat> <lon>` have at most 6 fractional decimal digits.

#### 2.2.2 Localization Keys (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`)

| Key | English (`app_en.arb`) | German (`app_de.arb`) |
| :--- | :--- | :--- |
| `locationSourceTypeLabel` | `"Source Type"` | `"Quellentyp"` |
| `locationSourceTypeGps` | `"GPS Coordinates"` | `"GPS-Koordinaten"` |
| `locationSourceTypeAddress` | `"Address"` | `"Adresse"` |
| `locationSourceTypePlusCode` | `"Google Plus Code"` | `"Google Plus Code"` |
| `locationSourceAddressHint` | `"Street, postal code, city"` | `"Straße, PLZ, Ort"` |
| `locationSourcePlusCodeHint` | `"e.g. 9F2PXXH7+F4 or XXH7+F4 Erfurt"` | `"z. B. 9F2PXXH7+F4 oder XXH7+F4 Erfurt"` |
| `locationResolveButton` | `"Resolve"` | `"Auflösen"` |
| `locationSelectCandidateTitle` | `"Select Location"` | `"Ort auswählen"` |
| `locationResolveErrorNotFound` | `"Could not resolve address or Plus Code."` | `"Adresse oder Plus Code konnte nicht aufgelöst werden."` |
| `locationResolveErrorInvalidPlusCode` | `"Enter a valid Plus Code (e.g. 9F2PXXH7+F4 or XXH7+F4 Erfurt)."` | `"Gültigen Plus Code eingeben (z. B. 9F2PXXH7+F4 oder XXH7+F4 Erfurt)."` |

### 2.3 Implementation Details

#### 2.3.1 Domain Models (`lib/models/location_state.dart`)
* `enum LocationSourceType { gps, address, plusCode }`
* `@immutable class GeocodingCandidate`:
  - Fields (alphabetical per `P-CLASS-COHESION`): `final String displayName`, `final double latitude`, `final double longitude`.
  - Computed getter:
    ```dart
    String get formattedCoordinates =>
        '${TdfLocation.formatRoundedDouble(latitude, 6)}, ${TdfLocation.formatRoundedDouble(longitude, 6)}';
    ```
    (Uses `TdfLocation.formatRoundedDouble` from `tdf_location.dart` at Layer Rank 1 so coordinates shown in `_LocationCandidateDialog` match the exact 6-decimal values written into `_latController` and `_lonController`.)
  - Value equality (`operator ==`, `hashCode`) and `toString()`.

#### 2.3.2 Open Location Code Service (`lib/services/plus_code_service.dart`)
* Sealed input hierarchy `sealed class PlusCodeInput`:
  - `final class FullPlusCodeInput extends PlusCodeInput` with fields (alphabetical per `P-CLASS-COHESION`): `final String fullCode` and `final String? localitySuffix` (optional trimmed, single-line locality text when the user enters e.g. `"9F2PXXH7+F4 Erfurt"` or `"Erfurt, 9F2PXXH7+F4"`).
  - `final class ShortPlusCodeInput extends PlusCodeInput` with fields (alphabetical per `P-CLASS-COHESION`): `final String localityQuery` and `final String shortCode`.
  - `final class InvalidPlusCodeInput extends PlusCodeInput` (`const InvalidPlusCodeInput()`).
* `@immutable class PlusCodeArea`:
  - Fields (alphabetical per `P-CLASS-COHESION`): `final double latitudeHi`, `final double latitudeLo`, `final double longitudeHi`, `final double longitudeLo`.
  - Getters: `double get latitudeCenter => ((latitudeLo + latitudeHi) / 2.0).clamp(-90.0, 90.0);`, `double get longitudeCenter => ((longitudeLo + longitudeHi) / 2.0).clamp(-180.0, 180.0);`.
* `final class PlusCodeService`:
  - Private constructor `const PlusCodeService._();`.
  - Constants:
    - `static const String alphabet = '23456789CFGHJMPQRVWX';`
    - `static const int gridCodeLength = 5;`
    - `static const int maxDigitCount = 15;`
    - `static const int maxInputLength = 500;`
    - `static const int pairCodeLength = 10;`
    - `static const int separatorPosition = 8;`
  - Methods:
    - `static LocationSourceType classifySource(String? rawSource)`: Returns `LocationSourceType.gps` when `rawSource` is `null`, empty after trimming, or ASCII case-insensitively equal to `'gps'` or `'manual'`; returns `LocationSourceType.plusCode` when `parseInput(rawSource)` is `FullPlusCodeInput` or `ShortPlusCodeInput`; otherwise returns `LocationSourceType.address`.
    - `static PlusCodeArea? decode(String fullCode)`: Validates that `fullCode` is a full Open Location Code (`isFullCode(fullCode)`), strips `+` and `0` padding, decodes up to `10` pair digits in base `20` and up to `5` refinement digits in the $4 \times 5$ grid, and returns `PlusCodeArea`.
    - `static String encode(double latitude, double longitude, {int codeLength = pairCodeLength})`: Encodes WGS-84 coordinates into a full Open Location Code of length `codeLength` (`10..15` digits, or even `2..8` padded with `0`).
    - `static bool isFullCode(String code)` and `static bool isShortCode(String code)`: Single-pass character-code validation without regular expressions inside loops (`P-ZERO-ALLOC`, `P-ZERO-COPY`).
    - `static String normalizeSingleLineText(String rawText, {int maxScalarValues = maxTdfTextLength})`: Replaces any `\r`, `\n`, or `\t` with an ASCII space (`0x20`), collapses consecutive ASCII spaces, trims leading/trailing ASCII whitespace, and truncates to at most `maxScalarValues` Unicode scalar values (`runes`) without splitting UTF-16 surrogate pairs.
    - `static PlusCodeInput parseInput(String rawInput)`: Enforces `rawInput.length <= maxInputLength` (`P-BOUND-ALLOC`), normalizes single-line whitespace, splits tokens around whitespace/commas to locate a candidate token containing `'+'`, and returns:
      - `FullPlusCodeInput(fullCode: normalizedCode, localitySuffix: remainingLocality)` when the code token is a valid full code (`localitySuffix` is `null` if no remaining locality tokens exist, or the normalized single-line locality string otherwise),
      - `ShortPlusCodeInput(shortCode: normalizedCode, localityQuery: remainingLocality)` when the code token is a valid short code with `4` or `6` prefix digits before `+` and the remaining tokens form a non-empty locality query, or
      - `InvalidPlusCodeInput()` otherwise.
    - `static String? recoverNearest(String shortCode, double referenceLatitude, double referenceLongitude)`: Reconstructs a full Open Location Code from a valid `shortCode` and reference coordinates using the official Open Location Code grid-step boundary adjustment.
    - `static String truncateToMaxTextLength(String text)`: Convenience wrapper around `normalizeSingleLineText(text, maxScalarValues: maxTdfTextLength)`.

#### 2.3.3 Repository Forward Geocoding (`lib/repositories/location_repository.dart`)
* Add `Future<List<GeocodingCandidate>> searchLocations(String query);` to `LocationRepository`.
* In `PlatformLocationRepository`:
  - Add constructor parameters:
    - `Uri Function(String query)? searchGeocodeUriBuilder` defaulting to `_defaultSearchGeocodeUri`.
    - `Duration minSearchInterval = defaultMinSearchInterval` (where `static const Duration defaultMinSearchInterval = Duration(seconds: 1);` enforces the OpenStreetMap Nominatim 1 req/s rate limit and can be set to `Duration.zero` or controlled via the injected `clock` in unit tests).
  - Default URI builder:
    ```dart
    static Uri _defaultSearchGeocodeUri(String query) {
      return Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        <String, String>{
          'format': 'jsonv2',
          'addressdetails': '1',
          'limit': '$maxGeocodingCandidates',
          'q': query,
        },
      );
    }
    ```
  - Constants: `static const int maxGeocodingCandidates = 5;` and `static const int maxSearchQueryLength = 500;`.
  - Rate-limit & single-flight state: Track `DateTime? _lastSearchAt;` and `bool _searchInFlight = false;`. If `_searchInFlight` is `true` or (`minSearchInterval > Duration.zero` and `_lastSearchAt` is within `minSearchInterval` of `_clock()`), `searchLocations` waits for the remaining cooldown interval (or rejects concurrent overlapping invocations) before issuing the HTTP request.
  - Helper `Future<List<Object?>?> _fetchJsonList(Uri uri)` performing a bounded HTTP GET (`connectionTimeout`, `maxResponseBytes = 65536`, `User-Agent: TierTask/1.0`) and decoding a JSON `List<Object?>`.
  - Helper `static List<GeocodingCandidate> _parseSearchCandidates(List<Object?>? jsonList)` iterating flatly over `jsonList`, stopping once `candidates.length >= maxGeocodingCandidates` (`P-BOUND-ALLOC`, `P-NO-NESTED-LOOPS`), extracting `lat`, `lon`, and `display_name` (or `name`), normalizing `displayName` via `PlusCodeService.normalizeSingleLineText(rawDisplayName, maxScalarValues: maxTdfTextLength)` (replacing `\r`, `\n`, `\t` with `0x20`, collapsing consecutive spaces, trimming, and truncating to at most `500` Unicode scalar values without slicing surrogate pairs), and skipping any candidate whose sanitized `displayName` is empty.
  - Diagnostic logging (`AGENTS.md` Section 6 & `spec/TDF_SPEC_0.6.0.md` Section 4.3): Emit `AppLogger.event(LogLevel.info, LogTag.storage, 'location.search', fields: <String, Object?>{'results': candidates.length, 'elapsed_ms': stopwatch.elapsedMilliseconds});` without logging `query`, `displayName`, or coordinates.
* In `FakeLocationRepository`:
  - Add `List<GeocodingCandidate> searchResults = const <GeocodingCandidate>[];`, `int searchCallCount = 0;`, and `String? lastSearchQuery;` to support deterministic unit and widget tests.

#### 2.3.4 UI Enhancements (`lib/ui/widgets/clearable_text_field.dart` & `lib/ui/edit_locations_screen.dart`)
* In `ClearableTextField`:
  - Add `this.enabled = true` and `this.readOnly = false` constructor parameters and fields, forwarding them to `TextField` and `TextFormField`.
  - Update `_shouldShowClearButton` to require `widget.enabled && !widget.readOnly && (_effectiveFocusNode.hasFocus || (widget.showClearWhenUnfocused && widget.controller.text.isNotEmpty))`.
* In `EditLocationScreen` (`lib/ui/edit_locations_screen.dart`):
  - State fields:
    - `late LocationSourceType _sourceType;`
    - `LocationSourceType? _resolvedSourceType;`
    - `String? _resolvedSourceText;`
    - `bool _isResolving = false;`
    - `int _resolveGeneration = 0;`
    - Computed getter:
      ```dart
      bool get _isSourceResolved =>
          _sourceType == LocationSourceType.gps ||
          (_resolvedSourceType == _sourceType &&
              _resolvedSourceText == _sourceController.text.trim() &&
              (_resolvedSourceText?.isNotEmpty ?? false));
      ```
  - Control locking during active resolution: While `_isResolving` is `true`, disable `location_editor_source_type_dropdown`, `location_editor_source_input`, and `location_editor_resolve_button`. After every `await` in `_resolveSource()` (`searchLocations` and `showDialog`), check `if (!mounted || currentGeneration != _resolveGeneration) return false;` before mutating controllers or state.
  - Widget keys:
    - `ValueKey('location_editor_source_type_dropdown')` for the `DropdownButtonFormField<LocationSourceType>`.
    - `ValueKey('location_editor_source_input')` for the source `ClearableTextField`.
    - `ValueKey('location_editor_resolve_button')` for the `Resolve` `OutlinedButton.icon`.
    - `ValueKey('location_editor_use_gps_button')` for the `Use Current GPS Position` `OutlinedButton.icon`.
    - `ValueKey('location_candidate_dialog')` and `ValueKey('location_candidate_item_$index')` inside `_LocationCandidateDialog`.
  - Keep all `build()` methods under 40 lines (`P-FLATTEN-BUILD`) and indentation $\le 3$ levels (`P-FLAT-CONTROL-FLOW`) by extracting dedicated private `StatelessWidget` classes (`_LocationSourceControlsRow`, `_LocationActionButtonsRow`, `_LocationCandidateDialog`).

### 2.4 Testing Strategy
1. **`test/services/plus_code_service_test.dart` (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`, `M-DELIM-INJECT-TESTS`):**
   - Exhaustive `PlusCodeInput` branch tests (`FullPlusCodeInput` with and without `localitySuffix`, `ShortPlusCodeInput`, `InvalidPlusCodeInput`) and `LocationSourceType` classification (`null`, `''`, `'gps'`, `'manual'`, full Plus Codes with/without locality, short Plus Codes, street addresses).
   - Standard Open Location Code round-trip and decoding accuracy vectors (`9F2PXXH7+F4` in Erfurt, `849VCWC8+R9` in Mountain View, `8FVC9G8F+6W` in Zurich, 11-character grid refinement codes, and `0`-padded codes).
   - `recoverNearest` tests across grid cell boundaries, negative/Southern/Western hemispheres, and antimeridian clamping.
   - Single-line text normalization and Unicode scalar (`runes`) truncation tests (replacing `\r`, `\n`, `\t`, collapsing spaces, and truncating at 500 scalar values without breaking astral-plane surrogate pairs).
   - Boundary and injection tests: `maxInputLength` (`500` vs `501` chars), malformed separators (`++`, missing `+`, invalid base-20 characters `A`, `E`, `I`, `O`, `U`, `1`, `0` after `+`), and control characters.
2. **`test/models/location_state_test.dart` (`M-EXHAUSTIVE-STATE-TESTS`):**
   - Verify `GeocodingCandidate` value equality, `hashCode`, 6-decimal `formattedCoordinates` matching `TdfLocation.formatRoundedDouble`, `toString()`, and `LocationSourceType.values`.
3. **`test/repositories/location_repository_test.dart` (`M-IO-TESTS`, `M-EXTREME-BOUND-TESTS`, `M-URI-PATH-EDGE-TESTS`):**
   - Loopback `HttpServer` tests (`HttpOverrides.global = null` in `setUp`) for `PlatformLocationRepository.searchLocations`:
     - Single and multi-result JSON array parsing.
     - Single-line normalization of `display_name` containing `\r\n\t`, multiple spaces, astral-plane Unicode characters exceeding 500 scalar values, and skipping empty sanitized names.
     - Enforcing `maxGeocodingCandidates = 5` cap when server returns $> 5$ items.
     - Enforcing `maxSearchQueryLength = 500`, rejecting empty/whitespace queries without network requests, and verifying the rate-limit / single-flight guard.
     - Handling HTTP 500 errors, malformed JSON objects, and oversized responses (`> maxResponseBytes`).
     - `FakeLocationRepository.searchLocations` tracking `searchCallCount` and `lastSearchQuery`.
4. **`test/ui/edit_locations_screen_test.dart` (`M-EXHAUSTIVE-STATE-TESTS`, `M-IO-TESTS`):**
   - Verify `GPS` mode disables `location_editor_source_input`, keeps `location_editor_lat_input` and `location_editor_lon_input` editable, and populates 6-decimal coordinates via `location_editor_use_gps_button` without writing `'gps'` into `location_editor_source_input`.
   - Verify switching to `Google Plus Code` locks `lat`/`lon` as `readOnly`, enables `location_editor_source_input`, resolves full Plus Codes (`9F2PXXH7+F4` and `9F2PXXH7+F4 Erfurt` preserving the locality suffix) offline via `location_editor_resolve_button`, and resolves short Plus Codes (`XXH7+F4 Erfurt`) preserving `'XXH7+F4 Erfurt'` in the source input.
   - Verify switching to `Address` resolves a single match immediately, opens `location_candidate_dialog` when multiple candidates are returned, applies the selected candidate's 6-decimal coordinates and `displayName`, and tracks `_isSourceResolved` across subsequent text/mode edits and in-flight state locks.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [x] Run `python3 .agents/scripts/tiertask_dev.py verify --fast` to confirm a clean baseline.
- [x] Add English and German localization keys to `lib/l10n/app_en.arb` and `lib/l10n/app_de.arb` via `tiertask_dev.py l10n --set`.
- [x] Write failing unit tests in `test/models/location_state_test.dart`, `test/services/plus_code_service_test.dart`, and `test/repositories/location_repository_test.dart`, and failing widget tests in `test/ui/edit_locations_screen_test.dart` (TDD Red Phase — `P-TDD-FIRST`).
- [x] Implement `LocationSourceType` and `GeocodingCandidate` in `lib/models/location_state.dart`, `PlusCodeService` in `lib/services/plus_code_service.dart`, `searchLocations` in `lib/repositories/location_repository.dart`, `enabled`/`readOnly` support in `lib/ui/widgets/clearable_text_field.dart`, and the source resolution workflow in `lib/ui/edit_locations_screen.dart` (TDD Green & Refactor Phase).
- [x] Run `python3 .agents/scripts/tiertask_dev.py arch --sync-tree --set lib/services/plus_code_service.dart "Stateless Open Location Code (Google Plus Code) parser, decoder, encoder, and nearest-locality recovery service."` and synchronize `ARCHITECTURE.md` and `README.md` per **`update-documentation`**.
- [x] Update `CHANGELOG.md` under `## [Unreleased]` per **`changelog-updater`**.
- [x] Run `python3 .agents/scripts/tiertask_dev.py verify --full --fix`.
- [x] Set `status: review` in `tep-005-location-source-resolution.md` and `BOARD.md` and request user approval.

### 3.2 Work Log & Decisions
* **2026-11-08:** Created `TEP-005` in `planned` status following internet research on What3words API restrictions, OpenStreetMap Nominatim forward geocoding, and offline Open Location Code decoding.
* **2026-11-08:** Updated `TEP-005` with 6 technical refinements: optional `localitySuffix` preservation on `FullPlusCodeInput`, single-line `<text>` normalization and 500-rune truncation for `GeocodingCandidate.displayName`, 6-decimal `GeocodingCandidate.formattedCoordinates` alignment, anchor-derived `_isSourceResolved` tracking, `_resolveGeneration` async cancellation and in-flight control locking, and Nominatim rate-limit guard plus short Plus Code source string preservation.
* **2026-11-09:** Implemented `TEP-005` via Red-Green-Refactor TDD across `lib/models/location_state.dart`, `lib/services/plus_code_service.dart`, `lib/repositories/location_repository.dart`, `lib/ui/widgets/clearable_text_field.dart`, `lib/ui/edit_locations_screen.dart`, and `lib/l10n/app_*.arb`.

### 3.3 Delivered Artifacts
*(Complete upon approval)*
