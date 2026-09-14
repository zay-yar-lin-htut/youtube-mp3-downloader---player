import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/update_config.dart';
import '../models/app_update.dart';

const Duration updateApiTimeout = Duration(seconds: 8);
const Duration updateConnectTimeout = Duration(seconds: 15);
const Duration updateReceiveTimeout = Duration(seconds: 30);

const String kUpdateApkPartFileName = 'freevibe_update.apk.part';
const String kUpdateApkFileName = 'freevibe_update.apk';

/// Reachability endpoint used to confirm a working Internet path rather than
/// just a connected network interface (Android convention: any HTTP response
/// counts as online).
const String kInternetReachabilityUrl =
    'https://connectivitycheck.gstatic.com/generate_204';

/// Reads the installed application version from platform metadata
/// (never hard-coded here).
typedef UpdateVersionLoader = Future<AppVersion> Function();

/// Returns true when connectivity reports the device has a network.
typedef UpdateConnectivityChecker = Future<bool> Function();

/// Launches the Android package installer for [apkPath]. True when the
/// install UI was handed off successfully (the user still decides).
typedef UpdateInstallLauncher = Future<bool> Function(String apkPath);

/// Outcome of a completed update check.
class UpdateCheck {
  const UpdateCheck({
    required this.installed,
    required this.server,
    required this.available,
  });

  final AppVersion installed;
  final AppUpdate server;
  final bool available;
}

/// Outcome of a completed APK download. Null download result means failure.
class ApkDownload {
  const ApkDownload({required this.filePath});

  final String filePath;
}

/// Network check + automatic update engine for FreeVibe.
///
/// Talks only to the Vercel Update API (see [updateApiUrl]); the app is never
/// coupled to GitHub Releases. Prefers versionCode for all comparisons.
class UpdateService {
  UpdateService({
    String? apiUrl,
    this.client,
    UpdateVersionLoader? versionLoader,
    UpdateConnectivityChecker? connectivityChecker,
    UpdateInstallLauncher? installLauncher,
    Future<Directory> Function()? cacheDirProvider,
    this.apiTimeout = updateApiTimeout,
    this.connectTimeout = updateConnectTimeout,
    this.receiveTimeout = updateReceiveTimeout,
  })  : apiUrl = apiUrl ?? updateApiUrl,
        _versionLoader = versionLoader ?? readInstalledVersion,
        _connectivityChecker = connectivityChecker ?? checkConnectivity,
        _installLauncher = installLauncher ?? openInstaller,
        _cacheDirProvider = cacheDirProvider ?? getApplicationCacheDirectory;

  /// Base URL of the Vercel Update API.
  final String apiUrl;

  /// Optional HTTP client override (used by tests). When null, a client is
  /// created per request and closed afterwards.
  final http.Client? client;

  /// Timeout for the version-check request.
  final Duration apiTimeout;

  /// Timeout for establishing the APK download connection.
  final Duration connectTimeout;

  /// Timeout between APK download chunks.
  final Duration receiveTimeout;

  final UpdateVersionLoader _versionLoader;
  final UpdateConnectivityChecker _connectivityChecker;
  final UpdateInstallLauncher _installLauncher;
  final Future<Directory> Function() _cacheDirProvider;

  bool _checkInProgress = false;
  bool _downloadInProgress = false;

  /// True while an update check is already running (duplicate protection).
  bool get checkInProgress => _checkInProgress;

  /// True while an APK download is already running (duplicate protection).
  bool get downloadInProgress => _downloadInProgress;

  /// Non-blocking update check.
  ///
  /// Returns null whenever the check cannot complete (no connectivity, API
  /// unreachable/timeout, non-200, malformed payload, or unknown installed
  /// version). Returns an [UpdateCheck] with [UpdateCheck.available] == false
  /// when the server version is not newer.
  Future<UpdateCheck?> checkForUpdate() async {
    if (_checkInProgress) return null;
    _checkInProgress = true;
    try {
      debugPrint('[Update] Starting update check');
      final online = await _runSafely(_connectivityChecker, fallback: false);
      if (online == false) {
        debugPrint('[Update] No network reported - skipping check');
        return null;
      }
      debugPrint('[Update] Querying $apiUrl');
      final httpClient = client ?? http.Client();
      try {
        final response = await httpClient
            .get(
              Uri.parse(apiUrl),
              headers: const {'Accept': 'application/json'},
            )
            .timeout(apiTimeout);
        if (response.statusCode != HttpStatus.ok) {
          debugPrint('[Update] API responded ${response.statusCode}');
          return null;
        }
        final server = AppUpdate.tryParse(response.body);
        if (server == null) {
          debugPrint('[Update] Malformed update payload - treating check as failed');
          return null;
        }
        final installed = await _runSafely(_versionLoader);
        if (installed == null) {
          debugPrint('[Update] Could not read installed version');
          return null;
        }
        final available = isUpdateAvailable(
          installedCode: installed.versionCode,
          serverCode: server.versionCode,
        );
        debugPrint(
          '[Update] installed ${installed.versionName} (${installed.versionCode}), '
          'server ${server.version} (${server.versionCode}), '
          '${available ? 'update available' : 'no update'}'
          '${server.forceUpdate ? ' (forced)' : ''}',
        );
        return UpdateCheck(
          installed: installed,
          server: server,
          available: available,
        );
      } finally {
        if (client == null) httpClient.close();
      }
    } catch (e) {
      debugPrint('[Update] Check failed: $e');
      return null;
    } finally {
      _checkInProgress = false;
    }
  }

  /// Downloads the APK to the app cache directory.
  ///
  /// Streams to `freevibe_update.apk.part` and atomically renames it to
  /// `freevibe_update.apk` on success. Any failure removes the `.part` file.
  /// [onProgress] reports `(receivedBytes, totalBytes?)`; [totalBytes] is
  /// null when Content-Length was not provided. Returns null on failure or
  /// when a download is already in progress.
  Future<ApkDownload?> downloadUpdate(
    String downloadUrl, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    if (_downloadInProgress) return null;
    _downloadInProgress = true;
    File? partFile;
    try {
      final dir = await _cacheDirProvider();
      await dir.create(recursive: true);
      partFile = File(p.join(dir.path, kUpdateApkPartFileName));
      final finalFile = File(p.join(dir.path, kUpdateApkFileName));
      debugPrint('[Update] Downloading $downloadUrl');
      final httpClient = client ?? http.Client();
      try {
        final request = http.Request('GET', Uri.parse(downloadUrl));
        final response = await httpClient
            .send(request)
            .timeout(connectTimeout);
        if (response.statusCode != HttpStatus.ok) {
          debugPrint('[Update] Download HTTP ${response.statusCode}');
          return null;
        }
        final total = response.contentLength;
        final sink = partFile.openWrite();
        var received = 0;
        try {
          await for (final chunk
              in response.stream.timeout(receiveTimeout)) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(received, total);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (received <= 0 || (total != null && received != total)) {
          debugPrint('[Update] Unusable download size $received/$total');
          return null;
        }
        if (finalFile.existsSync()) finalFile.deleteSync();
        await partFile.rename(finalFile.path);
        if (!finalFile.existsSync() || finalFile.lengthSync() <= 0) {
          debugPrint('[Update] Final APK missing/empty after rename');
          return null;
        }
        debugPrint(
          '[Update] Download complete (${finalFile.lengthSync()} bytes)',
        );
        return ApkDownload(filePath: finalFile.path);
      } finally {
        if (client == null) httpClient.close();
      }
    } catch (e) {
      debugPrint('[Update] Download failed: $e');
      return null;
    } finally {
      _downloadInProgress = false;
      try {
        if (partFile != null && partFile.existsSync()) {
          partFile.deleteSync();
        }
      } catch (e) {
        debugPrint('[Update] Could not clean up .part file: $e');
      }
    }
  }

  /// Hands the finished APK to the Android package installer.
  Future<bool> launchInstaller(String apkPath) => _installLauncher(apkPath);

  /// Confirms the device has a working Internet connection.
  ///
  /// Checks the connectivity plugin first (returns false immediately when it
  /// reports the device is offline). When the plugin claims online, verifies
  /// actual reachability with an HTTP GET to [kInternetReachabilityUrl]
  /// ([probeUrl] overrides this for tests). Only a 2xx response counts as
  /// online; any error, timeout, or non-2xx status does not. Never throws.
  Future<bool> hasInternetConnection({
    String? probeUrl,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final stateOnline = await _runSafely<bool>(
      _connectivityChecker,
      fallback: true,
    );
    if (stateOnline == false) {
      debugPrint('[Update] No connectivity - offline');
      return false;
    }
    final probe = probeUrl ?? kInternetReachabilityUrl;
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient.get(Uri.parse(probe)).timeout(timeout);
      final online =
          response.statusCode >= HttpStatus.ok &&
          response.statusCode < HttpStatus.multipleChoices;
      debugPrint('[Update] Reachability probe ${response.statusCode} '
          '-> ${online ? 'online' : 'offline'}');
      return online;
    } catch (e) {
      debugPrint('[Update] Reachability probe failed: $e');
      return false;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static Future<AppVersion> readInstalledVersion() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersion(
      versionName: info.version,
      versionCode: int.tryParse(info.buildNumber) ?? 0,
    );
  }

  static Future<bool> checkConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (e) {
      debugPrint('[Update] Connectivity probe failed: $e');
      return true;
    }
  }

  static Future<bool> openInstaller(String apkPath) async {
    try {
      final result = await OpenFilex.open(apkPath);
      final ok = result.type == ResultType.done;
      debugPrint('[Update] Installer ${ok ? 'started' : 'failed'}: ${result.message}');
      return ok;
    } catch (e) {
      debugPrint('[Update] Installer error: $e');
      return false;
    }
  }

  Future<T?> _runSafely<T>(Future<T> Function() action, {T? fallback}) async {
    try {
      return await action();
    } catch (e) {
      debugPrint('[Update] Sub-step failed: $e');
      return fallback;
    }
  }
}