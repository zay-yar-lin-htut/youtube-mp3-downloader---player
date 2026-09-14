import 'dart:convert';

/// Installed application version read from platform/package metadata.
class AppVersion {
  const AppVersion({required this.versionName, required this.versionCode});

  final String versionName;
  final int versionCode;
}

/// Latest release information published by the Vercel Update API.
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
    required this.forceUpdate,
  });

  final String version;
  final int versionCode;
  final String downloadUrl;
  final bool forceUpdate;

  /// Strictly parses the Vercel Update API response.
  ///
  /// Returns `null` when the payload is malformed so the caller can treat the
  /// update check as failed instead of crashing. Fields the app cannot trust
  /// are validated here:
  ///
  /// * [version] must be a non-empty string.
  /// * [versionCode] must be an integer greater than zero.
  /// * [downloadUrl] must be a well-formed `https://` URL.
  /// * [forceUpdate] must be a boolean.
  ///
  /// The body may be a JSON object or an errors-ish object; anything else is
  /// rejected.
  static AppUpdate? tryParse(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final version = decoded['version'];
    final versionCode = decoded['versionCode'];
    final downloadUrl = decoded['downloadUrl'];
    final forceUpdate = decoded['forceUpdate'];

    if (version is! String || version.trim().isEmpty) return null;
    if (versionCode is! int || versionCode <= 0) return null;
    if (downloadUrl is! String || !_isHttpsUrl(downloadUrl)) return null;
    if (forceUpdate is! bool) return null;

    return AppUpdate(
      version: version.trim(),
      versionCode: versionCode,
      downloadUrl: downloadUrl,
      forceUpdate: forceUpdate,
    );
  }

  static bool _isHttpsUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.isAbsolute && uri.scheme == 'https';
  }
}

/// Compares the installed [installedCode] against the server [serverCode].
///
/// versionCode is the primary comparison on Android; plain string comparison
/// of version names like `"1.10.0" > "1.9.0"` is unreliable and is never used.
bool isUpdateAvailable({required int installedCode, required int serverCode}) {
  return serverCode > installedCode;
}