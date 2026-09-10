import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../models/song.dart';
import '../player/time_format.dart';

/// Method channel served by MainActivity to read the real Android API level
/// (`Build.VERSION.SDK_INT`). dart:io's `Platform.operatingSystemVersion`
/// returns a kernel-style string on Android and must not be parsed for this.
const MethodChannel _platformChannel =
    MethodChannel('com.example.yt_local_music/platform');

/// Result of checking / requesting the runtime media permission.
enum DevicePermissionState {
  unknown,
  granted,
  denied,
  permanentlyDenied,
  restricted,
}

/// Thrown when a scan is requested without the media permission.
class DevicePermissionException implements Exception {
  const DevicePermissionException(this.state);

  final DevicePermissionState state;

  @override
  String toString() => 'DevicePermissionException: $state';
}

/// Abstraction over Android device-music discovery so app logic and tests do
/// not depend on platform channels.
abstract class DeviceMusicService {
  Future<DevicePermissionState> checkPermission();

  Future<DevicePermissionState> requestPermission();

  /// Returns true when the OS app-settings page could be opened.
  Future<bool> openAppSettings();

  /// Returns device-owned audio tracks as [Song]s with [SongSource.device].
  /// Throws [DevicePermissionException] when the permission is not granted.
  Future<List<Song>> scanDevice();
}

/// Real implementation using MediaStore (`on_audio_query`) with
/// `permission_handler` for permission states.
///
/// Only the minimum permission for the installed Android version is requested:
/// `READ_MEDIA_AUDIO` on API 33+, `READ_EXTERNAL_STORAGE` on older versions.
class OnDeviceDeviceMusicService extends DeviceMusicService {
  OnDeviceDeviceMusicService({OnAudioQuery? query, int? androidSdkInt})
      : _query = query ?? OnAudioQuery(),
        _injectedSdkInt = androidSdkInt;

  final OnAudioQuery _query;
  final int? _injectedSdkInt;

  int? _resolvedSdkInt;

  /// Maps the Android API level to the permission_handler permission whose
  /// manifest name is declared in AndroidManifest.xml:
  /// `READ_MEDIA_AUDIO` (Permission.audio) on Android 13+ / API 33+,
  /// `READ_EXTERNAL_STORAGE` (Permission.storage) on older versions.
  @visibleForTesting
  static ph.Permission permissionForApiLevel(int apiLevel) =>
      apiLevel >= 33 ? ph.Permission.audio : ph.Permission.storage;

  /// Resolves the permission object for the running device.
  @visibleForTesting
  Future<ph.Permission> permissionForSdk() async {
    final sdk = await _androidApiLevel();
    return permissionForApiLevel(sdk);
  }

  Future<int> _androidApiLevel() async {
    if (_resolvedSdkInt != null) {
      return _resolvedSdkInt!;
    }
    if (_injectedSdkInt != null) {
      return _resolvedSdkInt = _injectedSdkInt;
    }
    if (kIsWeb || !Platform.isAndroid) {
      // Non-Android: permission_handler's audio permission is a no-op default.
      return _resolvedSdkInt = 33;
    }
    try {
      final value = await _platformChannel.invokeMethod<int>('androidSdkInt');
      return _resolvedSdkInt = value ?? 0;
    } catch (e) {
      debugPrint('[DeviceMusicService] androidSdkInt fetch failed: $e');
      return _resolvedSdkInt = 0;
    }
  }

  @override
  Future<DevicePermissionState> checkPermission() async {
    if (kIsWeb) {
      return DevicePermissionState.restricted;
    }
    try {
      return _mapStatus(await (await permissionForSdk()).status);
    } catch (e) {
      debugPrint('[DeviceMusicService] permission status check failed: $e');
      return DevicePermissionState.unknown;
    }
  }

  @override
  Future<DevicePermissionState> requestPermission() async {
    if (kIsWeb) {
      return DevicePermissionState.restricted;
    }
    try {
      final status = await (await permissionForSdk()).request();
      if (status.isPermanentlyDenied) {
        return DevicePermissionState.permanentlyDenied;
      }
      return _mapStatus(status);
    } catch (e) {
      debugPrint('[DeviceMusicService] permission request failed: $e');
      return DevicePermissionState.unknown;
    }
  }

  DevicePermissionState _mapStatus(ph.PermissionStatus status) {
    if (status.isGranted) {
      return DevicePermissionState.granted;
    }
    if (status.isPermanentlyDenied) {
      return DevicePermissionState.permanentlyDenied;
    }
    if (status.isRestricted) {
      return DevicePermissionState.restricted;
    }
    return DevicePermissionState.denied;
  }

  @override
  Future<bool> openAppSettings() => ph.openAppSettings();

  @override
  Future<List<Song>> scanDevice() async {
    final state = await checkPermission();
    if (state != DevicePermissionState.granted) {
      throw DevicePermissionException(state);
    }

    var models = <SongModel>[];
    try {
      models = await _query.querySongs(
        uriType: UriType.EXTERNAL,
      );
    } catch (e) {
      debugPrint('[DeviceMusicService] querySongs failed: $e');
      return const [];
    }

    // Stable id derived from the physical identity, so restarting the app
    // yields the same playlist ids (persisted rows stay usable).
    final seen = <String>{};
    final songs = <Song>[];
    for (final model in models) {
      if (model.isRingtone == true ||
        model.isNotification == true ||
        model.isAlarm == true) {
        continue;
      }
      final identity = _identityFor(model);
      if (!seen.add(identity)) {
        continue;
      }
      songs.add(_toSong(model));
    }
    return songs;
  }

  String _identityFor(SongModel model) {
    final data = model.data.trim();
    if (data.isNotEmpty && !data.startsWith('//')) {
      return 'file:$data';
    }
    if (data.isNotEmpty) {
      return 'file:$data';
    }
    final uri = _contentUri(model.id);
    if (uri != null) {
      return uri;
    }
    return 'meta:${model.title}|${model.artist ?? ''}|${model.duration ?? 0}';
  }

  String? _contentUri(int id) {
    if (id <= 0) {
      return null;
    }
    return 'content://media/external/audio/media/$id';
  }

  Song _toSong(SongModel model) {
    final idUri = _contentUri(model.id);
    final title = model.displayNameWOExt.trim().isNotEmpty
        ? model.displayNameWOExt.trim()
        : model.title.trim();
    final author = (model.artist == null || model.artist!.trim().isEmpty)
        ? 'Unknown Artist'
        : model.artist!.trim();
    final durationMs = (model.duration ?? 0).clamp(0, 1 << 30);
    final identity = _identityFor(model);
    final digest = md5.convert(identity.codeUnits);
    return Song(
      id: 'd_$digest',
      videoId: null,
      title: title,
      author: author,
      duration: formatDuration(Duration(milliseconds: durationMs)),
      thumbnailUrl: '',
      localPath: idUri ?? (model.data.isNotEmpty ? model.data : null),
      source: SongSource.device,
    );
  }
}