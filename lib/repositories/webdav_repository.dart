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

/// Custom domain exception thrown when WebDAV HTTP operations fail.
class WebDavException implements Exception {
  /// Creates a [WebDavException] with a localized [message] and optional [statusCode].
  const WebDavException(this.message, {this.statusCode});

  /// Human-readable error message.
  final String message;

  /// Optional HTTP status code returned by the WebDAV server.
  final int? statusCode;

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
    this.timeout = const Duration(seconds: 15),
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  /// Active WebDAV connection and language configuration.
  final WebDavConfig config;

  /// Timeout applied to connection, request, and response operations.
  final Duration timeout;

  final HttpClient Function() _clientFactory;

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

  /// Fetches the remote Markdown file (`tiertask.md`) via HTTP GET.
  ///
  /// Returns an empty string when the remote file does not exist (`HTTP 404`)
  /// so a new 6-tier board can be initialized on first save.
  Future<String> fetchMarkdown() async {
    final localizations = _localizations;
    final uri = _requireUri(localizations);
    final client = _clientFactory();
    client.connectionTimeout = timeout;

    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.authorizationHeader, _basicAuthHeader);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/markdown, text/plain, */*',
      );

      final response = await request.close().timeout(timeout);
      final status = response.statusCode;
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);

      if (status >= 200 && status < 300) {
        return body;
      }
      if (status == HttpStatus.notFound) {
        return '';
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
        localizations.errorNetworkUnreachable(error.message),
      );
    } on TimeoutException {
      throw WebDavException(localizations.errorTimeoutLoad);
    } on HandshakeException catch (error) {
      throw WebDavException(localizations.errorTlsLoad(error.message));
    } on Object catch (error) {
      throw WebDavException(
        localizations.errorUnexpectedLoad(error.toString()),
      );
    } finally {
      client.close(force: false);
    }
  }

  /// Overwrites the remote Markdown file on the WebDAV server via HTTP PUT.
  Future<void> saveMarkdown(String markdownContent) async {
    final localizations = _localizations;
    final uri = _requireUri(localizations);
    final client = _clientFactory();
    client.connectionTimeout = timeout;

    try {
      final request = await client.putUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.authorizationHeader, _basicAuthHeader);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/markdown; charset=utf-8',
      );

      final bytes = utf8.encode(markdownContent);
      request.contentLength = bytes.length;
      request.add(bytes);

      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);

      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        return;
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
    } on WebDavException {
      rethrow;
    } on SocketException catch (error) {
      throw WebDavException(localizations.errorNetworkSave(error.message));
    } on TimeoutException {
      throw WebDavException(localizations.errorTimeoutSave);
    } on HandshakeException catch (error) {
      throw WebDavException(localizations.errorTlsSave(error.message));
    } on Object catch (error) {
      throw WebDavException(
        localizations.errorUnexpectedSave(error.toString()),
      );
    } finally {
      client.close(force: false);
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
}
