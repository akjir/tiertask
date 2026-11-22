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
import 'dart:typed_data' show BytesBuilder;
import 'dart:ui';

import '../l10n/app_localizations.dart';
import '../models/webdav_config.dart';
import '../services/app_logger.dart';
import '../services/tdf_service.dart';
import 'local_file_repository.dart';

/// Custom domain exception thrown when WebDAV HTTP operations fail.
class WebDavException implements Exception {
  /// Creates a [WebDavException] with a localized [message], optional [statusCode], and optional [cause].
  const WebDavException(this.message, {this.statusCode, this.cause});

  /// Underlying network, TLS, or transport exception cause when available.
  final Object? cause;

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
      AppLogger.registerSecret(config.password);
    }
  }

  static const int _maxDrainBytes = 65536;
  static const int _maxRedirects = 5;

  /// Active WebDAV connection and language configuration.
  final WebDavConfig config;

  /// Maximum allowed remote response or payload byte size (1 MiB default).
  final int maxFileBytes;

  /// Timeout applied to connection, request, and response operations.
  final Duration timeout;

  String? _cachedContent;
  String? _cachedEtag;
  bool? _cachedExists;
  String? _cachedLastModified;
  Uri? _cachedUri;
  HttpClient? _client;
  final HttpClient Function() _clientFactory;
  bool _lastFetchNotModified = false;

  /// Cached HTTP `ETag` response header from the most recent `.tdf` synchronization.
  String? get cachedEtag => _cachedEtag;

  /// Tri-state existence cache for the active `.tdf` URI (`null` unknown, `false` after `404`, `true` after `2xx`/`304`/seed).
  bool? get cachedExists => _cachedExists;

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

  /// Clears cached HTTP `ETag`, `Last-Modified`, existence, and `.tdf` content state.
  void clearCache() {
    _cachedUri = null;
    _cachedExists = null;
    _cachedEtag = null;
    _cachedLastModified = null;
    _cachedContent = null;
    _lastFetchNotModified = false;
  }

  /// Closes the pooled [HttpClient] and releases underlying socket connections.
  void close({bool force = false}) {
    final active = _client;
    _client = null;
    active?.close(force: force);
  }

  /// Deletes the remote diagnostic log file [logFileName] via HTTP DELETE, ignoring `404`.
  Future<void> deleteLog(String logFileName) async {
    final localizations = _localizations;
    final uri = _requireLogUri(logFileName, localizations);
    final stopwatch = Stopwatch()..start();
    final deadline = DateTime.now().add(timeout);
    final client = _acquireClient();

    try {
      final request = await client
          .deleteUrl(uri)
          .timeout(_remainingTimeout(deadline));
      final response = await _sendConfiguredRequest(request, client, deadline, (
        opened,
      ) {
        opened.followRedirects = false;
        opened.headers.set(HttpHeaders.authorizationHeader, _basicAuthHeader);
      });
      await _drainResponseSafely(response, deadline, client);
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
      AppLogger.event(
        LogLevel.warn,
        LogTag.storage,
        'webdav.log_delete',
        fields: <String, Object?>{
          'uri': uri.toString(),
          'status': status,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
    } on TimeoutException catch (error) {
      _resetPooledClient(client);
      AppLogger.event(
        LogLevel.warn,
        LogTag.storage,
        'webdav.log_delete',
        fields: <String, Object?>{'uri': uri.toString(), 'reason': 'timeout'},
        error: error,
      );
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.storage,
        'webdav.log_delete',
        fields: <String, Object?>{'uri': uri.toString()},
        error: error,
      );
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
    if (content == null ||
        normalizedContent == null ||
        normalizedContent.isEmpty ||
        _exceedsMaxUtf8Bytes(content)) {
      return;
    }
    final normalizedEtag = _normalizeHeaderValue(etag);
    final normalizedLastModified = _normalizeHeaderValue(lastModified);
    if (normalizedEtag == null && normalizedLastModified == null) return;
    _cachedUri = uri;
    _cachedExists = true;
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
    await _putToUri(uri, emptyContent, localizations);
    AppLogger.event(
      LogLevel.info,
      LogTag.storage,
      'webdav.wipe',
      fields: <String, Object?>{'uri': uri.toString(), 'backup': createBackup},
    );
  }

  /// Aborts an unclosed [request] and force-resets [client] so sockets never leak after pre-close exceptions.
  void _abortRequestSafely(HttpClientRequest request, HttpClient client) {
    try {
      request.abort();
    } on Object {
      // Ignore abort errors on already-closed or stubbed requests.
    }
    _resetPooledClient(client);
  }

  /// Returns the lazily initialized pooled [HttpClient] configured with [timeout].
  HttpClient _acquireClient() {
    if (_client case final existing?) {
      return existing;
    }
    final created = _clientFactory()..connectionTimeout = timeout;
    _client = created;
    return created;
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

  /// Attaches `If-Match` or `If-None-Match: *` to [request] according to tri-state [_cachedExists] (`TDF-PUB-003`).
  ({String? ifMatch, String? ifNoneMatch}) _applyConditionalPutHeaders(
    HttpClientRequest request,
    Uri uri,
  ) {
    if (_cachedUri != uri) {
      return (ifMatch: null, ifNoneMatch: null);
    }
    if (_cachedExists == true) {
      if (_cachedEtag case final etag? when isStrongEtag(etag)) {
        request.headers.set(HttpHeaders.ifMatchHeader, etag);
        return (ifMatch: etag, ifNoneMatch: null);
      }
      return (ifMatch: null, ifNoneMatch: null);
    }
    if (_cachedExists == false) {
      request.headers.set(HttpHeaders.ifNoneMatchHeader, '*');
      return (ifMatch: null, ifNoneMatch: '*');
    }
    return (ifMatch: null, ifNoneMatch: null);
  }

  /// Returns a safe structured failure summary for unexpected transport errors without leaking raw exception text.
  static String _describeUnexpectedError(Object error) {
    return switch (error) {
      HttpException _ => 'HTTP protocol error',
      FormatException _ => 'Invalid response format',
      TlsException _ => 'TLS connection error',
      IOException _ => 'Network I/O error',
      _ => 'Unexpected transport error',
    };
  }

  /// Drains up to [_maxDrainBytes] from [response] within [deadline] so keep-alive sockets return cleanly to the pool.
  Future<void> _drainResponseSafely(
    HttpClientResponse response,
    DateTime deadline,
    HttpClient client,
  ) async {
    if (response.contentLength > _maxDrainBytes) {
      _resetPooledClient(client);
      return;
    }
    final iterator = StreamIterator<List<int>>(response);
    var completedNormally = false;
    var drainedBytes = 0;
    try {
      while (await iterator.moveNext().timeout(_remainingTimeout(deadline))) {
        drainedBytes += iterator.current.length;
        if (drainedBytes > _maxDrainBytes) {
          _resetPooledClient(client);
          return;
        }
      }
      completedNormally = true;
    } finally {
      if (!completedNormally) {
        unawaited(iterator.cancel());
      }
    }
  }

  /// Returns `true` when UTF-8 encoding [payload] would exceed [maxFileBytes] without allocating an encoded buffer.
  bool _exceedsMaxUtf8Bytes(String payload) {
    if (maxFileBytes < 0 || payload.length > maxFileBytes) {
      return true;
    }
    var byteCount = 0;
    var index = 0;
    while (index < payload.length) {
      final unit = payload.codeUnitAt(index);
      if (unit <= 0x7F) {
        byteCount += 1;
        index += 1;
      } else if (unit <= 0x7FF) {
        byteCount += 2;
        index += 1;
      } else if (_isHighSurrogate(unit) &&
          index + 1 < payload.length &&
          _isLowSurrogate(payload.codeUnitAt(index + 1))) {
        byteCount += 4;
        index += 2;
      } else {
        byteCount += 3;
        index += 1;
      }
      if (byteCount > maxFileBytes) {
        return true;
      }
    }
    return false;
  }

  /// Executes one redirectable `GET` or `HEAD` hop using a freshly acquired pooled client,
  /// returning either the terminal response or the validated next redirect [Uri].
  Future<({HttpClient client, Uri? nextUri, HttpClientResponse? response})>
  _executeRedirectHop({
    required Uri initialUri,
    required Uri currentUri,
    required String method,
    required int hop,
    required bool sendAuth,
    required bool useConditionalCache,
    required DateTime deadline,
    required AppLocalizations localizations,
  }) async {
    final client = _acquireClient();
    final request = method == 'GET'
        ? await client.getUrl(currentUri).timeout(_remainingTimeout(deadline))
        : await client
              .openUrl(method, currentUri)
              .timeout(_remainingTimeout(deadline));
    final response = await _sendConfiguredRequest(request, client, deadline, (
      opened,
    ) {
      opened.followRedirects = false;
      if (sendAuth) {
        opened.headers.set(HttpHeaders.authorizationHeader, _basicAuthHeader);
      }
      if (method == 'GET') {
        opened.headers.set(HttpHeaders.acceptHeader, 'text/plain, */*');
      }
      if (method == 'GET' && useConditionalCache && hop == 0) {
        _applyConditionalGetHeaders(opened, initialUri);
      }
    });
    if (!_isRedirectStatus(response.statusCode)) {
      return (client: client, nextUri: null, response: response);
    }
    await _drainResponseSafely(response, deadline, client);
    if (hop == _maxRedirects) {
      throw WebDavException(
        localizations.errorLoadMarkdownFailed,
        statusCode: response.statusCode,
      );
    }
    final nextUri = _resolveRedirectUri(
      currentUri: currentUri,
      locationHeader: response.headers.value(HttpHeaders.locationHeader),
      statusCode: response.statusCode,
      localizations: localizations,
    );
    return (client: client, nextUri: nextUri, response: null);
  }

  /// Executes a `GET` or `HEAD` request with explicit bounded redirects, HTTPS downgrade defense, and cross-origin credential stripping.
  Future<({HttpClient client, HttpClientResponse response})>
  _executeRedirectableRequest({
    required Uri initialUri,
    required String method,
    required DateTime deadline,
    required AppLocalizations localizations,
    required bool useConditionalCache,
  }) async {
    var currentUri = initialUri;
    var sendAuth = true;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final step = await _executeRedirectHop(
        initialUri: initialUri,
        currentUri: currentUri,
        method: method,
        hop: hop,
        sendAuth: sendAuth,
        useConditionalCache: useConditionalCache,
        deadline: deadline,
        localizations: localizations,
      );
      if (step.response case final finalResponse?) {
        return (client: step.client, response: finalResponse);
      }
      final nextUri = step.nextUri;
      if (nextUri == null) {
        break;
      }
      sendAuth = sendAuth && _isSameOrigin(initialUri, nextUri);
      currentUri = nextUri;
    }
    throw WebDavException(localizations.errorLoadMarkdownFailed);
  }

  /// Executes an HTTP GET against [uri] and returns whether the resource exists along with its decoded body.
  Future<({bool exists, String content})> _getFromUri(
    Uri uri,
    AppLocalizations localizations, {
    bool useConditionalCache = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final deadline = DateTime.now().add(timeout);
    if (useConditionalCache) {
      _lastFetchNotModified = false;
    }

    try {
      final (:client, :response) = await _executeRedirectableRequest(
        initialUri: uri,
        method: 'GET',
        deadline: deadline,
        localizations: localizations,
        useConditionalCache: useConditionalCache,
      );
      return await _handleGetResponse(
        response,
        uri,
        localizations,
        stopwatch,
        deadline: deadline,
        client: client,
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
        localizations.errorNetworkUnreachable(
          AppLogger.sanitize(error.message),
        ),
        cause: error,
      );
    } on TimeoutException catch (error) {
      _resetCurrentPooledClient();
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
      throw WebDavException(localizations.errorTimeoutLoad, cause: error);
    } on HandshakeException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'webdav.get',
        fields: <String, Object?>{'uri': uri.toString(), 'reason': 'tls'},
        error: error.message,
      );
      throw WebDavException(
        localizations.errorTlsLoad(AppLogger.sanitize(error.message)),
        cause: error,
      );
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'webdav.get',
        fields: <String, Object?>{'uri': uri.toString()},
        error: error,
      );
      throw WebDavException(
        localizations.errorUnexpectedLoad(_describeUnexpectedError(error)),
        cause: error,
      );
    }
  }

  /// Processes the [response] from an HTTP GET request, evaluating `304 Not Modified`, `2xx`, and `404` states.
  Future<({bool exists, String content})> _handleGetResponse(
    HttpClientResponse response,
    Uri uri,
    AppLocalizations localizations,
    Stopwatch stopwatch, {
    required DateTime deadline,
    required HttpClient client,
    required bool useConditionalCache,
  }) async {
    final status = response.statusCode;
    if (status == HttpStatus.notModified && useConditionalCache) {
      if (_cachedContent case final cachedBody? when _cachedUri == uri) {
        await _drainResponseSafely(response, deadline, client);
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

    if (status >= 200 && status < 300) {
      final body = await _readBoundedUtf8Body(
        response,
        localizations,
        deadline: deadline,
        client: client,
      );
      if (useConditionalCache) {
        _updateConditionalCache(uri, body.content, response.headers);
      }
      AppLogger.event(
        LogLevel.info,
        LogTag.storage,
        'webdav.get',
        fields: <String, Object?>{
          'uri': uri.toString(),
          'status': status,
          'bytes': body.byteLength,
          if (useConditionalCache && _cachedEtag != null) 'etag': _cachedEtag,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return (exists: true, content: body.content);
    }

    await _drainResponseSafely(response, deadline, client);
    if (status == HttpStatus.notFound) {
      if (useConditionalCache) {
        clearCache();
        _cachedUri = uri;
        _cachedExists = false;
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
    String? ifMatch,
    String? ifNoneMatch,
  }) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      if (useConditionalCache) {
        _cachedUri = uri;
        _cachedExists = true;
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
            'ifMatch': ?ifMatch,
            'ifNoneMatch': ?ifNoneMatch,
            if (useConditionalCache && _cachedEtag != null) 'etag': _cachedEtag,
            'elapsed_ms': stopwatch.elapsedMilliseconds,
          },
        );
      }
      return;
    }
    if (status == HttpStatus.preconditionFailed && useConditionalCache) {
      _cachedExists = null;
      _cachedEtag = null;
      _cachedLastModified = null;
      _cachedContent = null;
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

  /// Probes whether [uri] exists on the WebDAV server using a lightweight HTTP `HEAD` request.
  Future<bool> _headExists(Uri uri, AppLocalizations localizations) async {
    final deadline = DateTime.now().add(timeout);
    try {
      final (:client, :response) = await _executeRedirectableRequest(
        initialUri: uri,
        method: 'HEAD',
        deadline: deadline,
        localizations: localizations,
        useConditionalCache: false,
      );
      await _drainResponseSafely(response, deadline, client);
      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        return true;
      }
      if (status == HttpStatus.notFound) {
        return false;
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
    } on WebDavException {
      rethrow;
    } on SocketException catch (error) {
      throw WebDavException(
        localizations.errorNetworkUnreachable(
          AppLogger.sanitize(error.message),
        ),
        cause: error,
      );
    } on TimeoutException catch (error) {
      _resetCurrentPooledClient();
      throw WebDavException(localizations.errorTimeoutLoad, cause: error);
    } on HandshakeException catch (error) {
      throw WebDavException(
        localizations.errorTlsLoad(AppLogger.sanitize(error.message)),
        cause: error,
      );
    } on Object catch (error) {
      throw WebDavException(
        localizations.errorUnexpectedLoad(_describeUnexpectedError(error)),
        cause: error,
      );
    }
  }

  /// Returns `true` when UTF-16 [codeUnit] is a leading high surrogate (`0xD800..0xDBFF`).
  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  /// Returns `true` when UTF-16 [codeUnit] is a trailing low surrogate (`0xDC00..0xDFFF`).
  static bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

  /// Returns `true` when [statusCode] is an HTTP redirect status (`301`, `302`, `303`, `307`, `308`).
  static bool _isRedirectStatus(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;

  /// Returns `true` when [first] and [second] share the same scheme, host, and effective port.
  static bool _isSameOrigin(Uri first, Uri second) =>
      first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
      first.host.toLowerCase() == second.host.toLowerCase() &&
      first.port == second.port;

  /// Trims [rawValue] and returns `null` when absent, empty, or containing control (`0x00..0x1F`, `0x7F..0x9F`) or non-ISO-8859-1 (`> 0xFF`) characters.
  static String? _normalizeHeaderValue(String? rawValue) {
    if (rawValue == null) return null;
    for (var i = 0; i < rawValue.length; i++) {
      final code = rawValue.codeUnitAt(i);
      if (code <= 0x1F || (code >= 0x7F && code <= 0x9F) || code > 0xFF) {
        return null;
      }
    }
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
    if (_exceedsMaxUtf8Bytes(payload)) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        eventName,
        fields: <String, Object?>{'uri': uri.toString(), 'reason': 'oversized'},
      );
      throw WebDavException(localizations.errorLocalFileTooLarge);
    }
    final stopwatch = Stopwatch()..start();
    final deadline = DateTime.now().add(timeout);
    final client = _acquireClient();
    String? sentIfMatch;
    String? sentIfNoneMatch;

    try {
      final bytes = utf8.encode(payload);
      final request = await client
          .putUrl(uri)
          .timeout(_remainingTimeout(deadline));
      final response = await _sendConfiguredRequest(request, client, deadline, (
        opened,
      ) {
        opened.followRedirects = false;
        opened.headers.set(HttpHeaders.authorizationHeader, _basicAuthHeader);
        opened.headers.set(
          HttpHeaders.contentTypeHeader,
          'text/plain; charset=utf-8',
        );
        if (useConditionalCache) {
          final preconditions = _applyConditionalPutHeaders(opened, uri);
          sentIfMatch = preconditions.ifMatch;
          sentIfNoneMatch = preconditions.ifNoneMatch;
        }
        opened.contentLength = bytes.length;
        opened.add(bytes);
      });
      await _drainResponseSafely(response, deadline, client);
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
        ifMatch: sentIfMatch,
        ifNoneMatch: sentIfNoneMatch,
      );
    } on WebDavException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        eventName,
        fields: <String, Object?>{
          'uri': uri.toString(),
          'status': error.statusCode,
          'ifMatch': ?sentIfMatch,
          'ifNoneMatch': ?sentIfNoneMatch,
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
      throw WebDavException(
        localizations.errorNetworkSave(AppLogger.sanitize(error.message)),
        cause: error,
      );
    } on TimeoutException catch (error) {
      _resetPooledClient(client);
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
      throw WebDavException(localizations.errorTimeoutSave, cause: error);
    } on HandshakeException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        eventName,
        fields: <String, Object?>{'uri': uri.toString(), 'reason': 'tls'},
        error: error.message,
      );
      throw WebDavException(
        localizations.errorTlsSave(AppLogger.sanitize(error.message)),
        cause: error,
      );
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        eventName,
        fields: <String, Object?>{'uri': uri.toString()},
        error: error,
      );
      throw WebDavException(
        localizations.errorUnexpectedSave(_describeUnexpectedError(error)),
        cause: error,
      );
    }
  }

  /// Reads at most [maxFileBytes] from [response] within [deadline] using [BytesBuilder] and decodes UTF-8.
  Future<({String content, int byteLength})> _readBoundedUtf8Body(
    HttpClientResponse response,
    AppLocalizations localizations, {
    required DateTime deadline,
    required HttpClient client,
  }) async {
    if (response.contentLength > maxFileBytes) {
      _resetPooledClient(client);
      throw WebDavException(localizations.errorLocalFileTooLarge);
    }
    final iterator = StreamIterator<List<int>>(response);
    final builder = BytesBuilder(copy: false);
    var completedNormally = false;
    try {
      while (await iterator.moveNext().timeout(_remainingTimeout(deadline))) {
        final chunk = iterator.current;
        if (builder.length + chunk.length > maxFileBytes) {
          _resetPooledClient(client);
          throw WebDavException(localizations.errorLocalFileTooLarge);
        }
        builder.add(chunk);
      }
      completedNormally = true;
      final bytes = builder.takeBytes();
      return (content: utf8.decode(bytes), byteLength: bytes.length);
    } finally {
      if (!completedNormally) {
        unawaited(iterator.cancel());
      }
    }
  }

  /// Computes remaining wall-clock budget before [deadline], throwing [TimeoutException] when exhausted.
  Duration _remainingTimeout(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException('HTTP request deadline exceeded', timeout);
    }
    return remaining;
  }

  /// Validates and returns the resolved WebDAV log [Uri] for [logFileName].
  Uri _requireLogUri(String logFileName, AppLocalizations localizations) {
    if (!config.isWebDavConfigured) {
      throw WebDavException(localizations.errorWebDavNotConfigured);
    }
    try {
      return config.resolveLogEndpointUri(logFileName);
    } on FormatException catch (error) {
      throw WebDavException(localizations.errorInvalidServerUrl, cause: error);
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

  /// Force-closes the currently pooled [HttpClient], if one is active.
  void _resetCurrentPooledClient() {
    if (_client case final active?) {
      _resetPooledClient(active);
    }
  }

  /// Force-closes [client] and clears [_client] so subsequent calls create a fresh connection pool.
  void _resetPooledClient(HttpClient client) {
    if (identical(_client, client)) {
      _client = null;
    }
    client.close(force: true);
  }

  /// Resolves the first available `<uri>.bak` or `<uri>.bak.NNN` URI on the WebDAV server via HTTP `HEAD`.
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
      final exists = await _headExists(candidateUri, localizations);
      if (!exists) {
        return candidateUri;
      }
    }
    throw WebDavException(localizations.errorSaveMarkdownFailed);
  }

  /// Resolves and validates a redirect [locationHeader] relative to [currentUri], rejecting HTTPS-to-HTTP downgrades.
  Uri _resolveRedirectUri({
    required Uri currentUri,
    required String? locationHeader,
    required int statusCode,
    required AppLocalizations localizations,
  }) {
    final trimmed = locationHeader?.trim() ?? '';
    if (trimmed.isEmpty) {
      throw WebDavException(
        localizations.errorLoadMarkdownFailed,
        statusCode: statusCode,
      );
    }
    final Uri nextUri;
    try {
      nextUri = currentUri.resolve(trimmed);
    } on FormatException catch (error) {
      throw WebDavException(
        localizations.errorLoadMarkdownFailed,
        statusCode: statusCode,
        cause: error,
      );
    }
    final scheme = nextUri.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') ||
        nextUri.host.isEmpty ||
        nextUri.userInfo.isNotEmpty) {
      throw WebDavException(
        localizations.errorLoadMarkdownFailed,
        statusCode: statusCode,
      );
    }
    if (currentUri.scheme.toLowerCase() == 'https' && scheme != 'https') {
      AppLogger.event(
        LogLevel.warn,
        LogTag.storage,
        'webdav.redirect_blocked',
        fields: <String, Object?>{'reason': 'cleartext_downgrade'},
      );
      throw WebDavException(
        localizations.errorTlsLoad('Refused insecure HTTPS-to-HTTP redirect'),
      );
    }
    return nextUri;
  }

  /// Configures and closes [request] within [deadline], aborting [request] and resetting [client] if an error occurs before closing.
  Future<HttpClientResponse> _sendConfiguredRequest(
    HttpClientRequest request,
    HttpClient client,
    DateTime deadline,
    void Function(HttpClientRequest request) configure,
  ) async {
    var requestClosed = false;
    try {
      configure(request);
      final closeTimeout = _remainingTimeout(deadline);
      requestClosed = true;
      return await request.close().timeout(closeTimeout);
    } on Object {
      if (!requestClosed) {
        _abortRequestSafely(request, client);
      }
      rethrow;
    }
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
    _cachedExists = true;
    _cachedContent = content;
    _cachedEtag =
        nextEtag ??
        (preserveExistingValidators && sameUri ? _cachedEtag : null);
    _cachedLastModified =
        nextLastModified ??
        (preserveExistingValidators && sameUri ? _cachedLastModified : null);
  }
}
