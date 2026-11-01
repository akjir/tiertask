/// Immutable configuration for connecting to a Nextcloud WebDAV endpoint.
class WebDavConfig {
  const WebDavConfig({
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.filePath = 'tiertask.md',
  });

  /// Nextcloud base URL (e.g. `https://cloud.example.com`) or full WebDAV URL.
  final String serverUrl;

  /// Nextcloud username.
  final String username;

  /// Nextcloud password or App-Password.
  final String password;

  /// Remote Markdown file name or relative path (e.g. `tiertask.md` or `t2.md`).
  final String filePath;

  bool get isConfigured =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  WebDavConfig copyWith({
    String? serverUrl,
    String? username,
    String? password,
    String? filePath,
  }) {
    return WebDavConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      filePath: filePath ?? this.filePath,
    );
  }

  /// Resolves the full WebDAV endpoint [Uri] for the target Markdown file.
  ///
  /// Supports:
  /// 1. Direct full URLs ending in `.md` (e.g., `https://cloud.example.com/remote.php/dav/files/user/tiertask.md`)
  /// 2. WebDAV base URLs containing `/remote.php/dav` or `/remote.php/webdav`
  /// 3. Standard Nextcloud server URLs (e.g., `https://cloud.example.com`), automatically
  ///    building `/remote.php/dav/files/<username>/<filePath>`.
  Uri? resolveEndpointUri() {
    var rawUrl = serverUrl.trim();
    if (rawUrl.isEmpty) return null;

    if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
      rawUrl = 'https://$rawUrl';
    }

    // Remove trailing slashes
    while (rawUrl.endsWith('/')) {
      rawUrl = rawUrl.substring(0, rawUrl.length - 1);
    }

    final cleanFile = filePath.trim().isEmpty
        ? 'tiertask.md'
        : filePath.trim().replaceFirst(RegExp(r'^/+'), '');

    // Encode each path segment of cleanFile while preserving '/'
    final encodedFileSegments = cleanFile
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');

    String fullUrl;
    if (rawUrl.toLowerCase().endsWith('.md')) {
      fullUrl = rawUrl;
    } else if (rawUrl.contains('/remote.php/dav/files/') ||
        rawUrl.contains('/remote.php/webdav')) {
      fullUrl = '$rawUrl/$encodedFileSegments';
    } else {
      final cleanUser = username.trim();
      if (cleanUser.isEmpty) {
        fullUrl = '$rawUrl/remote.php/webdav/$encodedFileSegments';
      } else {
        fullUrl =
            '$rawUrl/remote.php/dav/files/${Uri.encodeComponent(cleanUser)}/$encodedFileSegments';
      }
    }

    return Uri.tryParse(fullUrl);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WebDavConfig &&
        other.serverUrl == serverUrl &&
        other.username == username &&
        other.password == password &&
        other.filePath == filePath;
  }

  @override
  int get hashCode => Object.hash(serverUrl, username, password, filePath);
}
