import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/song.dart';
import 'database_service.dart';
import 'device_music_service.dart';
import 'library_storage.dart';

/// A normalized snapshot of the full playlist (see [PlaylistRepository]).
class PlaylistSnapshot {
  const PlaylistSnapshot({
    required this.songs,
    required this.permission,
    required this.scanned,
    required this.removedMissingDownloads,
  });

  /// Fully normalized playlist (deduplicated), newest-first.
  final List<Song> songs;

  final DevicePermissionState permission;

  /// Whether a device scan was attempted in this load.
  final bool scanned;

  /// Ids of FreeVibe-download rows whose file was gone (cleaned up).
  final List<String> removedMissingDownloads;

  PlaylistSnapshot copyWith({
    List<Song>? songs,
    DevicePermissionState? permission,
    bool? scanned,
    List<String>? removedMissingDownloads,
  }) {
    return PlaylistSnapshot(
      songs: songs ?? this.songs,
      permission: permission ?? this.permission,
      scanned: scanned ?? this.scanned,
      removedMissingDownloads:
          removedMissingDownloads ?? this.removedMissingDownloads,
    );
  }

  List<Song> get downloaded =>
      songs.where((s) => s.source == SongSource.downloaded).toList();

  List<Song> get onDevice =>
      songs.where((s) => s.source == SongSource.device).toList();
}

/// Builds the Playlist view from the SQLite library + a cached device scan.
///
/// Responsibilities:
/// - a song is only [SongSource.downloaded] when the record exists AND its
///   local file actually exists (stale/empty rows are cleaned up),
/// - device rows are reconciled against the latest scan (missing media is
///   dropped, newly discovered media is persisted for restart survival),
/// - the same physical file is never shown twice.
///
/// Device scans are cached per session; [load] with `rescanDevice: true` is
/// the only way to force a fresh scan, so widget rebuilds never re-query
/// MediaStore.
class PlaylistRepository {
  PlaylistRepository({
    LibraryStorage? storage,
    this.device,
  }) : storage = storage ?? DatabaseService.instance;

  final LibraryStorage storage;
  final DeviceMusicService? device;

  List<Song>? _cachedDeviceScan;
  bool _scanTimedOut = false;
  bool _lastScanOk = false;

  bool get hasDeviceService => device != null && !kIsWeb;

  /// Requests the device-media permission through the [DeviceMusicService].
  /// Never throws; non-usable services resolve to [DevicePermissionState.denied].
  Future<DevicePermissionState> requestPermission() async {
    if (!hasDeviceService) return DevicePermissionState.denied;
    try {
      return await device!.requestPermission();
    } catch (e) {
      debugPrint('[PlaylistRepository] requestPermission failed: $e');
      return DevicePermissionState.denied;
    }
  }

  /// Opens the Android app settings screen so the user can grant media
  /// access. Swallows errors so permission flows never crash.
  Future<void> openAppSettings() async {
    if (!hasDeviceService) return;
    try {
      await device!.openAppSettings();
    } catch (e) {
      debugPrint('[PlaylistRepository] openAppSettings failed: $e');
    }
  }

  Future<PlaylistSnapshot> load({bool rescanDevice = false}) async {
    final removedMissing = <String>[];

    var permission = DevicePermissionState.unknown;
    var scanned = false;
    List<Song> deviceSongs = const [];

    if (hasDeviceService) {
      permission = await device!.checkPermission();
      if (rescanDevice && permission == DevicePermissionState.granted) {
        _scrubScan();
      }
      if (permission == DevicePermissionState.granted) {
        deviceSongs = await _scan();
        scanned = true;
      }
    }

    final rows = await storage.getPlaylist();

    final downloads = <Song>[];
    final persistedDevice = <Song>[];
    for (final row in rows) {
      if (row.source == SongSource.device) {
        persistedDevice.add(row);
      } else if (row.source == SongSource.downloaded) {
        if (_downloadFileOk(row.localPath)) {
          downloads.add(row);
        } else {
          removedMissing.add(row.id);
          await storage.deleteSong(row.id);
        }
      }
    }

    final mergedDevice = _lastScanOk
        ? await _reconcileDevice(deviceSongs, persistedDevice)
        : persistedDevice;
    final noDupDevice = _dedupeAgainstDownloaded(downloads, mergedDevice);

    return PlaylistSnapshot(
      songs: [...downloads, ...noDupDevice],
      permission: permission,
      scanned: scanned,
      removedMissingDownloads: removedMissing,
    );
  }

  Future<List<Song>> _scan() async {
    if (_scanTimedOut) {
      return _cachedDeviceScan ?? const [];
    }
    try {
      final scan = await device!.scanDevice();
      _cachedDeviceScan = scan;
      _lastScanOk = true;
      return scan;
    } catch (e) {
      debugPrint('[PlaylistRepository] device scan failed: $e');
      _scanTimedOut = true;
      _lastScanOk = false;
      return _cachedDeviceScan ?? const [];
    }
  }

  void _scrubScan() {
    _scanTimedOut = false;
    _lastScanOk = false;
    _cachedDeviceScan = null;
  }

  bool _downloadFileOk(String? path) {
    if (path == null || path.isEmpty) {
      return false;
    }
    final uri = Uri.tryParse(path);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return false;
    }
    try {
      final file = File(path);
      return file.existsSync() && file.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  Future<List<Song>> _reconcileDevice(
    List<Song> scanned,
    List<Song> persisted,
  ) async {
    final result = <Song>[];

    if (!hasDeviceService) {
      return const [];
    }

    final scanByIdentity = <String, Song>{};
    for (final s in scanned) {
      scanByIdentity[s.localIdentity] = s;
    }

    final seen = <String>{};
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final row in persisted) {
      final scan = scanByIdentity[row.localIdentity];
      if (scan == null) {
        // The original device file is no longer indexed: drop the row.
        await storage.deleteSong(row.id);
        continue;
      }
      final updated = scan.copyWith(createdAt: row.createdAt);
      result.add(updated);
      seen.add(row.localIdentity);
    }

    for (final scan in scanned) {
      if (seen.contains(scan.localIdentity)) {
        continue;
      }
      final persistedAgain = scan.copyWith(createdAt: now);
      await storage.insertSong(persistedAgain);
      result.add(persistedAgain);
      seen.add(scan.localIdentity);
    }

    return result;
  }

  /// A physical file must appear once: if a FreeVibe download already owns the
  /// same local identity, the device copy is not shown separately.
  List<Song> _dedupeAgainstDownloaded(
    List<Song> downloads,
    List<Song> deviceSongs,
  ) {
    if (deviceSongs.isEmpty) {
      return deviceSongs;
    }
    final ownedPaths = <String>{};
    for (final d in downloads) {
      final identity = normalizeLocalIdentity(d.localPath);
      if (identity != null) {
        ownedPaths.add(identity);
      }
      if (d.id.isNotEmpty) {
        ownedPaths.add('video:${d.id}');
      }
    }
    return deviceSongs
        .where((s) => !ownedPaths.contains(s.localIdentity))
        .toList();
  }
}