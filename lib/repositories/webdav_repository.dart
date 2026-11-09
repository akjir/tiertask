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
import 'dart:ui';

import '../l10n/app_localizations.dart';
import '../models/webdav_config.dart';
import '../services/app_logger.dart';
import '../services/tdf_service.dart';
import 'local_file_repository.dart';

/// Custom domain exception thrown when WebDAV HTTP operations fail.
class WebDavException implements Exception {
  /// Creates a [WebDavException] with a localized [message] and optional [statusCode].
  const WebDavException(this.message, {this.statusCode});

  /// Human-readable error message.
  final String message;

  /// Optional HTTP status code returned by the WebDAV server.
  final int? statusCode;

  /// Whether this exception represents an `HTTP 412 Precondition Failed` response.
  bool get isPreconditionFailed => statusCode == HttpStatus.preconditionFailed;

  @override
  String toString() =>
      statusCode != null ? '$message (HTTP $statusCode)' : message;
}

/// Native WebDAV client repository using [HttpClient] from `dart:io` and Basic Authentication.
class WebDavRepository {
  /// Creates a [WebDavRepository] for [config].
  WebDavRepository({
    required this.config,
    HttpClient Function()? clientFactory,
    this.maxFileBytes = LocalFileRepository.defaultMaxFileBytes,
    this.timeout = const Duration(seconds: 15),
  }) : _clientFactory = clientFactory ?? HttpClient.new {
    if (config.password.isNotEmpty) {
      AppLogger.setSecretToRedact(config.password);
    }
  }

  /// Active WebDAV connection and language configuration.
  final WebDavConfig config;

  /// Maximum allowed remote response or payload byte size (1 MiB default).
  final int maxFileBytes;

  /// Timeout applied to connection, request, and response operations.
  final Duration timeout;

  String? _cachedContent;
  String? _cachedEtag;
  String? _cachedLastModified;
  Uri? _cachedUri;
  final HttpClient Function() _clientFactory;
  bool _lastFetchNotModified = false;

  /// Cached HTTP `ETag` response header from the most recent `.tdf` synchronization.
  String? get cachedEtag => _cachedEtag;

  /// Cached HTTP `Last-Modified` response header from the most recent `.tdf` synchronization.
  String? get cachedLastModified => _cachedLastModified;

  /// Whether the most recent [fetchTdf] call received `HTTP 304 Not Modified`.
  bool get lastFetchWasNotModified => _lastFetchNotModified;

  /// Builds the HTTP Basic Authentication header value.
  String get _basicAuthHeader {
    final username = config.username.trim();
    final password = config.password;
    final token = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $token';
  }

  /// Resolves the active [AppLocalizations] instance for error messages.
  AppLocalizations get _localizations {
    final locale = config.language.resolveLocale(
      PlatformDispatcher.instance.locale,
    );
    return lookupAppLocalizations(locale);
  }

  /// Clears cached HTTP `ETag`, `Last-Modified`, and `.tdf` content state.
  void clearCache() {
    _cachedUri = null;
    _cachedEtag = null;
    _cachedLastModified = null;
    _cachedContent = null;
    _lastFetchNotModified = false;
  }

  /// Deletes the remote diagnostic log file [logFileName] via HTTP DELETE, ignoring `404`.
  Future<void> deleteLog(String logFileName) async {
    final localizations = _localizations;
    final uri = _requireLogUri(logFileName, localizations);
    final stopwatch = Stopwatch()..start();
    final client = _clientFactory();
    client.connectionTimeout = timeout;

    try {
      final request = await client.deleteUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.authorizationHeader, _basicAuthHeader);
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      final status = response.statusCode;
      if ((status >= 200 && status < 300) || status == HttpStatus.notFound) {
        AppLogger.event(
          LogLevel.info,
          LogTag.storage,
          'webdav.log_delete',
          fields: <String, Object?>{
            'uri': uri.toString(),
            'status': status,
            'elapsed_ms': stopwatch.elapsedMilliseconds,
          },
        );
        return;
      }
      throw WebDavException(
        localizations.errorSaveMarkdownFailed,
        statusCode: status,
      );
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.storage,
        'webdav.log_delete',
        fields: <String, Object?>{'uri': uri.toString()},
        error: error,
      );
    } finally {
      client.close(force: false);
    }
  }

  /// Fetches the remote TDF file (`tiertask.tdf`) via HTTP GET.
  ///
  /// Sends `If-None-Match` and/or `If-Modified-Since` when cached validators and
  /// content exist for the active URI, returning the cached content on `HTTP 304`.
  /// Returns an empty string when the remote file does not exist (`HTTP 404`)
  /// so a new 6-tier board can be initialized on first save.
  Future<String> fetchTdf() async {
    final localizations = _localizations;
    final uri = _requireUri(localizations);
    final result = await _getFromUri(
      uri,
      localizations,
      useConditionalCache: true,
    );
    return result.content;
  }

  /// Returns `true` when [etag] is a non-empty strong HTTP entity tag (not prefixed with `W/` or `w/`).
  static bool isStrongEtag(String? etag) {
    final normalized = _normalizeHeaderValue(etag);
    if (normalized == null) return false;
    return !normalized.startsWith('W/') && !normalized.startsWith('w/');
  }

  /// Uploads the diagnostic log snapshot for [logFileName] to WebDAV via HTTP PUT.
  ///
  /// Does not append post-snapshot log entries on HTTP `2xx` success so that
  /// debounced log uploads do not re-dirty [AppLogger.revision].
  Future<void> saveLog(String logFileName, [String? logContent]) async {
    final localizations = _localizations;
    final uri = _requireLogUri(logFileName, localizations);
    final snapshot = logContent ?? '${AppLogger.fullLogText}\n';
    await _putToUri(
      uri,
      snapshot,
      localizations,
      eventName: 'webdav.log_put',
      logOnSuccess: false,
    );
  }

  /// Overwrites the remote TDF file on the WebDAV server via HTTP PUT.
  Future<void> saveTdf(String tdfContent) async {
    final localizations = _localizations;
    final uri = _requireUri(localizations);
    await _putToUri(uri, tdfContent, localizations, useConditionalCache: true);
  }

  /// Seeds the conditional validator cache for the resolved `.tdf` URI when not already populated.
  void seedCacheIfEmpty({String? etag, String? lastModified, String? content}) {
    final uri = config.resolveEndpointUri();
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return;
    if (_cachedUri == uri && _cachedContent != null) return;
    final normalizedContent = content?.trim();
    if (normalizedContent == null || normalizedContent.isEmpty) return;
    final normalizedEtag = _normalizeHeaderValue(etag);
    final normalizedLastModified = _normalizeHeaderValue(lastModified);
    if (normalizedEtag == null && normalizedLastModified == null) return;
    _cachedUri = uri;
    _cachedContent = content;
    _cachedEtag = normalizedEtag;
    _cachedLastModified = normalizedLastModified;
  }

  /// Empties and re-initializes the remote `.tdf` file on the WebDAV server, optionally creating a `.bak` or `.bak.001`+ backup first if the file exists.
  Future<void> wipeTdf({bool createBackup = false}) async {
    final localizations = _localizations;
    final uri = _requireUri(localizations);
    const emptyContent = 'tdf ${TdfService.supportedVersion}\n';

    if (createBackup) {
      final current = await _getFromUri(uri, localizations);
      if (current.exists) {
        final backupUri = await _resolveNextRemoteBackupUri(uri, localizations);
        await _putToUri(backupUri, current.content, localizations);
        AppLogger.event(
          LogLevel.info,
          LogTag.storage,
          'webdav.wipe',
          fields: <String, Object?>{'backup_uri': backupUri.toString()},
        );
      }
    }
    clearCache();
    await _putToUri(
      uri,
      emptyContent,
      localizations,
      useConditionalCache: true,
    );
    AppLogger.event(
      LogLevel.info,
      LogTag.storage,
      'webdav.wipe',
      fields: <String, Object?>{'uri': uri.toString(), 'backup': createBackup},
    );
  }

  /// Attaches `If-None-Match` and `If-Modified-Since` headers to [request] when cached `.tdf` content exists for [uri].
  void _applyConditionalGetHeaders(HttpClientRequest request, Uri uri) {
    if (_cachedUri != uri) return;
    final cachedBody = _cachedContent;
    if (cachedBody == null || cachedBody.isEmpty) return;
    if (_cachedEtag case final etag?) {
      request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
    }
    if (_cachedLastModified case final lastModified?) {
      request.headers.set(HttpHeaders.ifModifiedSinceHeader, lastModified);
    }
  }

  /// Attaches `If-Match` to [request] when a strong cached `ETag` exists for [uri].
  void _applyConditionalPutHeaders(HttpClientRequest request, Uri uri) {
    if (_cachedUri != uri) return;
    if (_cachedEtag case final etag? when isStrongEtag(etag)) {
      request.headers.set(HttpHeaders.ifMatchHeader, etag);
    }
  }

  /// Executes an HTTP GET against [uri] and returns whether the resource exists along with its decoded body.
  Future<({bool exists, String content})> _getFromUri(
    Uri uri,
    AppLocalizations localizations, {
    bool useConditionalCache = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final client = _clientFactory();
    client.connectionTimeout = timeout;
    if (useConditionalCache) {
      _lastFetchNotModified = false;
    }

    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.authorizationHeader, _basicAuthHeader);
      request.headers.set(HttpHeaders.acceptHeader, 'text/plain, */*');
      if (useConditionalCache) {
        _applyConditionalGetHeaders(request, uri);
      }

      final response = await request.close().timeout(timeout);
      return await _handleGetResponse(
        response,
        uri,
        localizations,
        stopwatch,
        useConditionalCache: useConditionalCache,
      );
    } on WebDavException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'webdav.get',
        fields: <String, Object?>{
          'uri': uri.toString(),
          'status': error.statusCode,
        },
        error: error,
      );
      rethrow;
    } on SocketException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'webdav.get',
        fields: <String, Object?>{'uri': uri.toString(), 'reason': 'socket'},
        error: error.message,
      );
      throw WebDavException(
        localizations.errorNetworkUnreachable(error.message),
      );
    } on TimeoutException {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'webdav.get',
        fields: <String, Object?>{
          'uri': uri.toString(),
          'reason': 'timeout',
          'timeout_ms': timeout.inMilliseconds,
        },
      );
      throw WebDavException(localizations.errorTimeoutLoad);
    } on HandshakeException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'webdav.get',
        fields: <String, Object?>{'uri': uri.toString(), 'reason': 'tls'},
        error: error.message,
      );
      throw WebDavException(localizations.errorTlsLoad(error.message));
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'webdav.get',
        fields: <String, Object?>{'uri': uri.toString()},
        error: error,
      );
      throw WebDavException(
        localizations.errorUnexpectedLoad(error.toString()),
      );
    } finally {
      client.close(force: false);
    }
  }

  /// Processes the [response] from an HTTP GET request, evaluating `304 Not Modified`, `2xx`, and `404` states.
  Future<({bool exists, String content})> _handleGetResponse(
    HttpClientResponse response,
    Uri uri,
    AppLocalizations localizations,
    Stopwatch stopwatch, {
    required bool useConditionalCache,
  }) async {
    final status = response.statusCode;
    if (status == HttpStatus.notModified && useConditionalCache) {
      if (_cachedContent case final cachedBody? when _cachedUri == uri) {
        await response.drain<void>().timeout(timeout);
        _updateConditionalCache(
          uri,
          cachedBody,
          response.headers,
          preserveExistingValidators: true,
        );
        _lastFetchNotModified = true;
        AppLogger.event(
          LogLevel.info,
          LogTag.storage,
          'webdav.get',
          fields: <String, Object?>{
            'uri': uri.toString(),
            'status': HttpStatus.notModified,
            'not_modified': true,
            'etag': _cachedEtag,
            'elapsed_ms': stopwatch.elapsedMilliseconds,
          },
        );
        return (exists: true, content: cachedBody);
      }
    }

    final body = await _readBoundedUtf8Body(response, localizations);
    if (status >= 200 && status < 300) {
      if (useConditionalCache) {
        _updateConditionalCache(uri, body, response.headers);
      }
      AppLogger.event(
        LogLevel.info,
        LogTag.storage,
        'webdav.get',
        fields: <String, Object?>{
          'uri': uri.toString(),
          'status': status,
          'bytes': body.length,
          if (useConditionalCache && _cachedEtag != null) 'etag': _cachedEtag,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return (exists: true, content: body);
    }
    if (status == HttpStatus.notFound) {
      if (useConditionalCache) {
        clearCache();
      }
      AppLogger.event(
        LogLevel.info,
        LogTag.storage,
        'webdav.get',
        fields: <String, Object?>{
          'uri': uri.toString(),
          'status': HttpStatus.notFound,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return (exists: false, content: '');
    }
    if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
      throw WebDavException(
        localizations.errorAuthFailedLoad,
        statusCode: status,
      );
    }
    throw WebDavException(
      localizations.errorLoadMarkdownFailed,
      statusCode: status,
    );
  }

  /// Evaluates the status code and headers of an HTTP PUT [response].
  void _handlePutResponse(
    HttpClientResponse response,
    Uri uri,
    String payload,
    int byteLength,
    AppLocalizations localizations,
    Stopwatch stopwatch, {
    required String eventName,
    required bool logOnSuccess,
    required bool useConditionalCache,
  }) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      if (useConditionalCache) {
        _cachedUri = uri;
        _cachedContent = payload;
        _cachedEtag = _normalizeHeaderValue(
          response.headers.value(HttpHeaders.etagHeader),
        );
        _cachedLastModified = _normalizeHeaderValue(
          response.headers.value(HttpHeaders.lastModifiedHeader),
        );
        _lastFetchNotModified = false;
      }
      if (logOnSuccess) {
        AppLogger.event(
          LogLevel.info,
          LogTag.storage,
          eventName,
          fields: <String, Object?>{
            'uri': uri.toString(),
            'status': status,
            'bytes': byteLength,
            if (useConditionalCache && _cachedEtag != null) 'etag': _cachedEtag,
            'elapsed_ms': stopwatch.elapsedMilliseconds,
          },
        );
      }
      return;
    }
    if (status == HttpStatus.preconditionFailed && useConditionalCache) {
      _cachedEtag = null;
      _cachedLastModified = null;
    }
    if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
      throw WebDavException(
        localizations.errorAuthFailedSave,
        statusCode: status,
      );
    }
    throw WebDavException(
      localizations.errorSaveMarkdownFailed,
      statusCode: status,
    );
  }

  /// Trims [rawValue] and returns `null` when absent or empty.
  static String? _normalizeHeaderValue(String? rawValue) {
    if (rawValue == null) return null;
    final trimmed = rawValue.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Executes an HTTP PUT sending [payload] to [uri].
  Future<void> _putToUri(
    Uri uri,
    String payload,
    AppLocalizations localizations, {
    String eventName = 'webdav.put',
    bool logOnSuccess = true,
    bool useConditionalCache = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final client = _clientFactory();
    client.connectionTimeout = timeout;

    try {
      final request = await client.putUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.authorizationHeader, _basicAuthHeader);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/plain; charset=utf-8',
      );
      if (useConditionalCache) {
        _applyConditionalPutHeaders(request, uri);
      }

      final bytes = utf8.encode(payload);
      request.contentLength = bytes.length;
      request.add(bytes);

      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      _handlePutResponse(
        response,
        uri,
        payload,
        bytes.length,
        localizations,
        stopwatch,
        eventName: eventName,
        logOnSuccess: logOnSuccess,
        useConditionalCache: useConditionalCache,
      );
    } on WebDavException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        eventName,
        fields: <String, Object?>{
          'uri': uri.toString(),
          'status': error.statusCode,
        },
        error: error,
      );
      rethrow;
    } on SocketException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        eventName,
        fields: <String, Object?>{'uri': uri.toString(), 'reason': 'socket'},
        error: error.message,
      );
      throw WebDavException(localizations.errorNetworkSave(error.message));
    } on TimeoutException {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        eventName,
        fields: <String, Object?>{
          'uri': uri.toString(),
          'reason': 'timeout',
          'timeout_ms': timeout.inMilliseconds,
        },
      );
      throw WebDavException(localizations.errorTimeoutSave);
    } on HandshakeException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        eventName,
        fields: <String, Object?>{'uri': uri.toString(), 'reason': 'tls'},
        error: error.message,
      );
      throw WebDavException(localizations.errorTlsSave(error.message));
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        eventName,
        fields: <String, Object?>{'uri': uri.toString()},
        error: error,
      );
      throw WebDavException(
        localizations.errorUnexpectedSave(error.toString()),
      );
    } finally {
      client.close(force: false);
    }
  }

  /// Reads at most [maxFileBytes] from [response] and decodes it as UTF-8, throwing [WebDavException] if oversized.
  Future<String> _readBoundedUtf8Body(
    HttpClientResponse response,
    AppLocalizations localizations,
  ) async {
    if (response.contentLength > maxFileBytes) {
      throw WebDavException(localizations.errorLocalFileTooLarge);
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      if (bytes.length + chunk.length > maxFileBytes) {
        throw WebDavException(localizations.errorLocalFileTooLarge);
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  /// Validates and returns the resolved WebDAV log [Uri] for [logFileName].
  Uri _requireLogUri(String logFileName, AppLocalizations localizations) {
    if (!config.isWebDavConfigured) {
      throw WebDavException(localizations.errorWebDavNotConfigured);
    }
    try {
      return config.resolveLogEndpointUri(logFileName);
    } on FormatException {
      throw WebDavException(localizations.errorInvalidServerUrl);
    }
  }

  /// Validates and returns the resolved WebDAV [Uri] or throws a [WebDavException].
  Uri _requireUri(AppLocalizations localizations) {
    if (!config.isWebDavConfigured) {
      throw WebDavException(localizations.errorWebDavNotConfigured);
    }
    final uri = config.resolveEndpointUri();
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw WebDavException(localizations.errorInvalidServerUrl);
    }
    return uri;
  }

  /// Resolves the first available `<uri>.bak` or `<uri>.bak.NNN` URI on the WebDAV server.
  Future<Uri> _resolveNextRemoteBackupUri(
    Uri baseUri,
    AppLocalizations localizations,
  ) async {
    for (
      var attempt = 0;
      attempt <= LocalFileRepository.maxBackupSuffix;
      attempt++
    ) {
      final candidatePath = LocalFileRepository.formatBackupPath(
        baseUri.path,
        attempt,
      );
      final candidateUri = baseUri.replace(path: candidatePath);
      final existing = await _getFromUri(candidateUri, localizations);
      if (!existing.exists) {
        return candidateUri;
      }
    }
    throw WebDavException(localizations.errorSaveMarkdownFailed);
  }

  /// Updates the conditional validator cache for [uri] from [content] and response [headers].
  void _updateConditionalCache(
    Uri uri,
    String content,
    HttpHeaders headers, {
    bool preserveExistingValidators = false,
  }) {
    final sameUri = _cachedUri == uri;
    final nextEtag = _normalizeHeaderValue(
      headers.value(HttpHeaders.etagHeader),
    );
    final nextLastModified = _normalizeHeaderValue(
      headers.value(HttpHeaders.lastModifiedHeader),
    );
    _cachedUri = uri;
    _cachedContent = content;
    _cachedEtag =
        nextEtag ??
        (preserveExistingValidators && sameUri ? _cachedEtag : null);
    _cachedLastModified =
        nextLastModified ??
        (preserveExistingValidators && sameUri ? _cachedLastModified : null);
  }
}
