import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/webdav_config.dart';

/// Custom exception thrown when WebDAV HTTP operations fail.
class WebDavException implements Exception {
  const WebDavException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode != null ? '$message (HTTP $statusCode)' : message;
}

/// Native WebDAV client repository using `HttpClient` from `dart:io` and
/// Basic Authentication (`base64Encode(utf8.encode('$username:$password'))`).
class WebDavRepository {
  WebDavRepository({
    required this.config,
    HttpClient Function()? clientFactory,
    this.timeout = const Duration(seconds: 15),
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final WebDavConfig config;
  final HttpClient Function() _clientFactory;
  final Duration timeout;

  /// Builds the HTTP Basic Authentication header value.
  String get _basicAuthHeader {
    final username = config.username.trim();
    final password = config.password;
    final token = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $token';
  }

  Uri _requireUri() {
    if (!config.isConfigured) {
      throw const WebDavException(
        'WebDAV ist noch nicht konfiguriert. Bitte Nextcloud-Zugangsdaten in den Einstellungen hinterlegen.',
      );
    }
    final uri = config.resolveEndpointUri();
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const WebDavException('Ungültige Nextcloud-Server-URL.');
    }
    return uri;
  }

  /// Fetches the remote Markdown file (`tiertask.md` / `t2.md`) via HTTP GET.
  ///
  /// If the remote file does not exist yet (`HTTP 404`), returns an empty string
  /// so a fresh board can be initialized and created on first save.
  Future<String> fetchMarkdown() async {
    final uri = _requireUri();
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
      final body = await response.transform(utf8.decoder).join().timeout(timeout);

      if (status >= 200 && status < 300) {
        return body;
      }
      if (status == HttpStatus.notFound) {
        // File does not exist on server yet; return empty content to initialize.
        return '';
      }
      if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
        throw WebDavException(
          'Authentifizierung fehlgeschlagen. Bitte Benutzername und App-Passwort prüfen.',
          statusCode: status,
        );
      }
      throw WebDavException(
        'Fehler beim Laden der Markdown-Datei vom Server.',
        statusCode: status,
      );
    } on WebDavException {
      rethrow;
    } on SocketException catch (e) {
      throw WebDavException('Netzwerkfehler: Server nicht erreichbar (${e.message}).');
    } on TimeoutException {
      throw const WebDavException('Zeitüberschreitung bei der Verbindung zum Nextcloud-Server.');
    } on HandshakeException catch (e) {
      throw WebDavException('TLS/SSL-Verbindungsfehler: ${e.message}');
    } catch (e) {
      throw WebDavException('Unerwarteter WebDAV-Fehler beim Laden: $e');
    } finally {
      client.close(force: false);
    }
  }

  /// Overwrites the remote Markdown file on the Nextcloud server via HTTP PUT.
  Future<void> saveMarkdown(String markdownContent) async {
    final uri = _requireUri();
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
      // Drain response stream to free socket resources
      await response.drain<void>().timeout(timeout);

      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        return;
      }
      if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
        throw WebDavException(
          'Authentifizierung beim Speichern fehlgeschlagen. Bitte App-Passwort prüfen.',
          statusCode: status,
        );
      }
      throw WebDavException(
        'Fehler beim Speichern der Markdown-Datei auf dem Server.',
        statusCode: status,
      );
    } on WebDavException {
      rethrow;
    } on SocketException catch (e) {
      throw WebDavException('Netzwerkfehler beim Speichern (${e.message}).');
    } on TimeoutException {
      throw const WebDavException('Zeitüberschreitung beim Speichern auf Nextcloud.');
    } on HandshakeException catch (e) {
      throw WebDavException('TLS/SSL-Fehler beim Speichern: ${e.message}');
    } catch (e) {
      throw WebDavException('Unerwarteter WebDAV-Fehler beim Speichern: $e');
    } finally {
      client.close(force: false);
    }
  }
}
