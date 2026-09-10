import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yt_local_music/models/song.dart';
import 'package:yt_local_music/services/device_music_service.dart';
import 'package:yt_local_music/services/library_storage.dart';
import 'package:yt_local_music/services/playlist_repository.dart';

class FakeStorage implements LibraryStorage {
  List<Song> songs = [];
  final List<String> deleted = [];

  @override
  Future<List<Song>> getPlaylist() async => List.of(songs);

  @override
  Future<void> insertSong(Song song) async {
    final i = songs.indexWhere((s) => s.id == song.id);
    if (i >= 0) {
      songs[i] = song;
    } else {
      songs.add(song);
    }
  }

  @override
  Future<void> updateSong(Song song) async {
    final i = songs.indexWhere((s) => s.id == song.id);
    if (i >= 0) songs[i] = song;
  }

  @override
  Future<void> deleteSong(String id) async {
    songs.removeWhere((s) => s.id == id);
    deleted.add(id);
  }
}

class FakeDeviceMusicService implements DeviceMusicService {
  FakeDeviceMusicService({required this.permission, List<Song>? scan})
      : scan = scan ?? const [];

  DevicePermissionState permission;
  List<Song> scan;
  int scanCalls = 0;
  bool failScan = false;

  @override
  Future<DevicePermissionState> checkPermission() async => permission;

  @override
  Future<DevicePermissionState> requestPermission() async => permission;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<List<Song>> scanDevice() async {
    scanCalls++;
    if (failScan) {
      throw const DevicePermissionException(DevicePermissionState.denied);
    }
    return List.of(scan);
  }
}

Song _download(String id, {String? path, int? createdAt}) => Song(
      id: id,
      videoId: id,
      title: 'Downloaded $id',
      author: 'Artist',
      duration: '3:00',
      thumbnailUrl: '',
      localPath: path,
      createdAt: createdAt ?? 100,
      downloadedAt: createdAt ?? 100,
      source: SongSource.downloaded,
    );

Song _deviceSong(String id,
        {required String path, int? createdAt, String videoId = ''}) =>
    Song(
      id: id,
      videoId: videoId.isEmpty ? null : videoId,
      title: 'Device $id',
      author: 'Collection',
      duration: '4:00',
      thumbnailUrl: '',
      localPath: path,
      createdAt: createdAt,
      source: SongSource.device,
    );

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fv_playlist_test');
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  String writeFile(String name, [int bytes = 1]) {
    final f = File('${temp.path}/$name');
    f.writeAsBytesSync(List.filled(bytes, 7));
    return f.path;
  }

  group('PlaylistRepository classification', () {
    test('a download is Downloaded only when its file exists', () async {
      final realPath = writeFile('real.m4a', 100);
      final missingPath = '${temp.path}/gone.m4a';
      final storage = FakeStorage()..songs = [
        _download('real', path: realPath),
        _download('gone', path: missingPath),
      ];
      final repo = PlaylistRepository(storage: storage, device: null);

      final snapshot = await repo.load();

      expect(snapshot.songs.single.id, 'real');
      expect(snapshot.songs.single.source, SongSource.downloaded);
      expect(storage.deleted, contains('gone'));
      expect(snapshot.removedMissingDownloads, ['gone']);
    });

    test('an http(s) localPath is never treated as a downloaded file', () async {
      final storage = FakeStorage()
        ..songs.add(_download('fake', path: 'https://cdn/invalid.m4a'));
      final repo = PlaylistRepository(storage: storage, device: null);
      final snapshot = await repo.load();
      expect(snapshot.songs, isEmpty);
      expect(storage.deleted, contains('fake'));
    });

    test('device-only songs are On device and never Downloaded', () async {
      final storage = FakeStorage()
        ..songs.add(_deviceSong(
          'd_1',
          path: 'content://media/external/audio/media/1',
        ));
      final device = FakeDeviceMusicService(
        permission: DevicePermissionState.granted,
        scan: [
          _deviceSong('d_1', path: 'content://media/external/audio/media/1'),
        ],
      );
      final repo = PlaylistRepository(storage: storage, device: device);

      final snapshot = await repo.load();

      expect(snapshot.songs.single.source, SongSource.device);
      expect(snapshot.downloaded, isEmpty);
      expect(snapshot.onDevice.single.id, 'd_1');
    });

    test('same physical file owned by a download is not shown as device too',
        () async {
      final realPath = writeFile('shared.m4a', 50);
      final storage = FakeStorage()
        ..songs.add(_download('dl', path: realPath));
      final device = FakeDeviceMusicService(
        permission: DevicePermissionState.granted,
        scan: [
          _deviceSong('d_1', path: 'content://media/external/audio/media/1'),
          _deviceSong('d_2', path: realPath),
        ],
      );
      final repo = PlaylistRepository(storage: storage, device: device);

      final snapshot = await repo.load();

      expect(snapshot.downloaded.single.id, 'dl');
      expect(snapshot.onDevice.single.id, 'd_1');
      expect(snapshot.songs.length, 2);
    });

    test('device rows are persisted for restart survival and stale ones dropped',
        () async {
      final storage = FakeStorage()
        ..songs.add(_deviceSong(
          'd_keep',
          path: 'content://media/external/audio/media/5',
          createdAt: 500,
        ))
        ..songs.add(_deviceSong(
          'd_stale',
          path: 'content://media/external/audio/media/OLD',
        ));
      final device = FakeDeviceMusicService(
        permission: DevicePermissionState.granted,
        scan: [
          _deviceSong('d_keep', path: 'content://media/external/audio/media/5'),
          _deviceSong('d_new', path: 'content://media/external/audio/media/9'),
        ],
      );
      final repo = PlaylistRepository(storage: storage, device: device);

      final snapshot = await repo.load();

      final kept = snapshot.onDevice.singleWhere((s) => s.id == 'd_keep');
      expect(kept.createdAt, 500, reason: 'must not reset the added date');
      final newlyAdded = snapshot.onDevice.singleWhere((s) => s.id == 'd_new');
      expect(newlyAdded.createdAt, isNotNull);
      expect(storage.deleted, contains('d_stale'));
      expect(storage.songs.map((s) => s.id), contains('d_new'));
      expect(snapshot.scanned, isTrue);
    });

    test('a denied permission neither scans nor drops persisted rows', () async {
      final storage = FakeStorage()
        ..songs.add(_deviceSong(
          'd_keep',
          path: 'content://media/external/audio/media/5',
        ));
      final device = FakeDeviceMusicService(permission: DevicePermissionState.denied);
      final repo = PlaylistRepository(storage: storage, device: device);

      final snapshot = await repo.load();

      expect(device.scanCalls, 0);
      expect(snapshot.permission, DevicePermissionState.denied);
      expect(snapshot.scanned, isFalse);
      expect(snapshot.onDevice.single.id, 'd_keep',
          reason: 'revoking permission must not wipe the library');
      expect(storage.deleted, isEmpty);
    });

    test('a failed scan keeps persisted device rows (no data loss)', () async {
      final storage = FakeStorage()
        ..songs.add(_deviceSong(
          'd_keep',
          path: 'content://media/external/audio/media/5',
        ));
      final device = FakeDeviceMusicService(
        permission: DevicePermissionState.granted,
      )..failScan = true;
      final repo = PlaylistRepository(storage: storage, device: device);

      final snapshot = await repo.load();
      expect(snapshot.onDevice.single.id, 'd_keep');
      expect(storage.deleted, isEmpty);
    });

    test('a fresh download record (from search) becomes a Downloaded entry',
        () async {
      final realPath = writeFile('dl.m4a', 100);
      final storage = FakeStorage()
        ..songs.add(_download('id-1', path: realPath));
      final repo = PlaylistRepository(storage: storage, device: null);

      final snapshot = await repo.load();
      expect(snapshot.downloaded.single.id, 'id-1');
      expect(snapshot.downloaded.single.videoId, 'id-1');
    });
  });

  group('PlaylistRepository deduplication', () {
    test('dedup uses normalized local identity across separators', () async {
      final realPath = writeFile('multi.m4a', 40);
      final storage = FakeStorage()
        ..songs.add(_download('dl', path: realPath));
      final device = FakeDeviceMusicService(
        permission: DevicePermissionState.granted,
        scan: [
          _deviceSong('d_backslash', path: realPath.replaceAll('\\', '/')),
        ],
      );
      final repo = PlaylistRepository(storage: storage, device: device);

      final snapshot = await repo.load();
      expect(snapshot.downloaded.single.id, 'dl');
      expect(snapshot.onDevice, isEmpty);
      expect(snapshot.songs.length, 1);
    });
  });

  group('PlaylistRepository permission helpers', () {
    test('requestPermission and openAppSettings route through the device',
        () async {
      final device = FakeDeviceMusicService(permission: DevicePermissionState.granted);
      final repo = PlaylistRepository(storage: FakeStorage(), device: device);
      expect(await repo.requestPermission(), DevicePermissionState.granted);
      await repo.openAppSettings();
    });

    test('without a device service there is no device music', () async {
      final repo = PlaylistRepository(storage: FakeStorage());
      final snapshot = await repo.load();
      expect(snapshot.permission, DevicePermissionState.unknown);
      expect(snapshot.onDevice, isEmpty);
    });
  });
}