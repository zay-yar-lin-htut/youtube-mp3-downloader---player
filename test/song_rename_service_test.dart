import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yt_local_music/models/song.dart';
import 'package:yt_local_music/services/library_storage.dart';
import 'package:yt_local_music/services/song_rename_service.dart';

class _FakeStorage implements LibraryStorage {
  final List<Song> songs = [];
  final List<String> warnings = [];

  @override
  Future<List<Song>> getPlaylist() async => List.of(songs);

  @override
  Future<void> insertSong(Song song) async {
    songs.removeWhere((s) => s.id == song.id);
    songs.add(song);
  }

  @override
  Future<void> updateSong(Song song) async {
    final i = songs.indexWhere((s) => s.id == song.id);
    if (i >= 0) {
      songs[i] = song;
    } else {
      warnings.add('update for missing id ${song.id}');
    }
  }

  @override
  Future<void> deleteSong(String id) async {
    songs.removeWhere((s) => s.id == id);
  }
}

Song _download(String id, String path, {String title = 'Old Name'}) => Song(
      id: id,
      videoId: id,
      title: title,
      author: 'Artist',
      duration: '3:00',
      thumbnailUrl: '',
      localPath: path,
      source: SongSource.downloaded,
    );

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fv_rename_test');
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  String writeFile(String name, [int bytes = 16]) {
    final f = File('${temp.path}/$name');
    f.writeAsBytesSync(List.filled(bytes, 7));
    return f.path;
  }

  group('SongRenameService validation', () {
    test('accepts a plain name', () {
      expect(SongRenameService().validateNewName('My Song'), isNull);
    });

    test('rejects empty and whitespace-only names', () {
      expect(SongRenameService().validateNewName('   '), isNotNull);
      expect(SongRenameService().validateNewName(''), isNotNull);
    });

    test('rejects names with path separators and illegal characters', () {
      final service = SongRenameService();
      expect(service.validateNewName('a/b'), isNotNull);
      expect(service.validateNewName(r'a\b'), isNotNull);
      expect(service.validateNewName('a:b'), isNotNull);
      expect(service.validateNewName('a*b'), isNotNull);
      expect(service.validateNewName('a?b'), isNotNull);
    });

    test('rejects "." and ".."', () {
      final service = SongRenameService();
      expect(service.validateNewName('.'), isNotNull);
      expect(service.validateNewName('..'), isNotNull);
    });

    test('rejects names longer than 120 chars', () {
      expect(
        SongRenameService().validateNewName('x' * 121),
        isNotNull,
      );
    });
  });

  group('SongRenameService splitFileName', () {
    test('keeps the extension with its dot', () {
      expect(SongRenameService.splitFileName('/a/b/my song.m4a').$1, 'my song');
      expect(SongRenameService.splitFileName('/a/b/my song.m4a').$2, '.m4a');
      expect(SongRenameService.splitFileName('plain.mp3').$2, '.mp3');
    });

    test('handles files without an extension', () {
      expect(SongRenameService.splitFileName('song').$2, '');
    });
  });

  group('SongRenameService canRename', () {
    test('only downloaded songs with a real file path', () {
      final realPath = writeFile('real.m4a');
      final service = SongRenameService();
      expect(service.canRename(_download('a', realPath)), isTrue);

      final device = Song(
        id: 'd_1',
        title: 't',
        author: 'a',
        duration: '1:00',
        thumbnailUrl: '',
        localPath: 'content://media/external/audio/media/1',
        source: SongSource.device,
      );
      expect(service.canRename(device), isFalse);

      final httpSong = _download('b', 'https://cdn/x.m4a');
      expect(service.canRename(httpSong), isFalse);

      final youtubeOnly = Song(
        id: 'yt',
        title: 't',
        author: 'a',
        duration: '1:00',
        thumbnailUrl: '',
      );
      expect(service.canRename(youtubeOnly), isFalse);
    });
  });

  group('SongRenameService rename', () {
    test('renames the file, preserves extension and persists the new song',
        () async {
      final path = writeFile('Old Name.m4a', 100);
      final storage = _FakeStorage()..songs.add(_download('a', path));
      final history = <String>[];
      final service = SongRenameService(
        storage: storage,
        onHistoryUpdate: (song) async {
          history.add('${song.id}:${song.title}:${song.localPath}');
        },
      );

      final result = await service.rename(storage.songs.single, 'New Name');

      expect(result.ok, isTrue);
      final updated = result.song!;
      expect(updated.title, 'New Name');
      expect(updated.localPath, '${temp.path}/New Name.m4a');
      expect(updated.id, 'a', reason: 'id drives playlist membership');
      expect(await File('${temp.path}/New Name.m4a').exists(), isTrue);
      expect(await File(path).exists(), isFalse);
      expect(storage.songs.single.title, 'New Name');
      expect(history, ['a:New Name:${temp.path}/New Name.m4a']);
    });

    test('no-op when the name equals the current file stem', () async {
      final path = writeFile('Old Name.m4a');
      final storage = _FakeStorage()..songs.add(_download('a', path));
      final service = SongRenameService(storage: storage);

      final result = await service.rename(storage.songs.single, 'Old Name');
      expect(result.ok, isTrue);
      expect(result.song!.title, 'Old Name');
      expect(await File(path).exists(), isTrue);
    });

    test('refuses to overwrite an existing target file', () async {
      final path = writeFile('A.m4a');
      writeFile('B.m4a', 32);
      final storage = _FakeStorage()..songs.add(_download('a', path));
      final service = SongRenameService(storage: storage);

      final result = await service.rename(storage.songs.single, 'B');
      expect(result.ok, isFalse);
      expect(result.error, contains('already exists'));
      expect(await File(path).exists(), isTrue);
      expect(storage.songs.single.title, 'Old Name');
    });

    test('missing file yields a friendly failure without DB changes', () async {
      final storage = _FakeStorage()
        ..songs.add(_download('a', '${temp.path}/gone.m4a'));
      final service = SongRenameService(storage: storage);

      final result = await service.rename(storage.songs.single, 'Whatever');
      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
      expect(storage.songs.single.title, 'Old Name');
    });

    test('device songs are refused', () async {
      final device = Song(
        id: 'd_1',
        title: 't',
        author: 'a',
        duration: '1:00',
        thumbnailUrl: '',
        localPath: 'content://media/external/audio/media/1',
        source: SongSource.device,
      );
      final service = SongRenameService(storage: _FakeStorage());
      final result = await service.rename(device, 'New');
      expect(result.ok, isFalse);
      expect(result.error, contains('cannot be renamed'));
    });
  });
}