import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yt_local_music/models/song.dart';
import 'package:yt_local_music/services/custom_playlist_service.dart';
import 'package:yt_local_music/services/database_service.dart';

Song _song(String id) => Song(
      id: id,
      videoId: id,
      title: 'Song $id',
      author: 'Artist',
      duration: '3:00',
      thumbnailUrl: '',
      source: SongSource.downloaded,
    );

/// Mirrors the v6 schema so the service can run against a real in-memory DB.
Future<Database> _openInMemory() {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE playlist (
            id TEXT PRIMARY KEY,
            videoId TEXT,
            title TEXT NOT NULL,
            author TEXT NOT NULL,
            duration TEXT NOT NULL,
            thumbnailUrl TEXT NOT NULL,
            localPath TEXT,
            youtubeUrl TEXT,
            createdAt INTEGER,
            downloadedAt INTEGER,
            source TEXT NOT NULL DEFAULT 'downloaded'
          )
        ''');
        await db.execute('''
          CREATE TABLE custom_playlists (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE playlist_songs (
            playlistId TEXT NOT NULL,
            songId TEXT NOT NULL,
            position INTEGER NOT NULL,
            addedAt INTEGER NOT NULL,
            PRIMARY KEY (playlistId, songId)
          )
        ''');
      },
    ),
  );
}

void main() {
  late Database db;
  late CustomPlaylistService service;

  setUp(() async {
    db = await _openInMemory();
    DatabaseService.debugSetDatabase(db);
    service = CustomPlaylistService();
  });

  tearDown(() async {
    DatabaseService.debugSetDatabase(null);
    await db.close();
  });

  Future<void> insertLibrary(List<String> ids) async {
    for (final id in ids) {
      await DatabaseService.instance.insertSong(_song(id));
    }
  }

  group('CustomPlaylistService create/list', () {
    test('creates and lists playlists', () async {
      final pl = await service.create('Workout');
      expect(pl.name, 'Workout');
      expect(pl.songCount, 0);

      final all = await service.listAll();
      expect(all, hasLength(1));
      expect(all.single.name, 'Workout');
    });

    test('trims names and rejects invalid ones', () async {
      final pl = await service.create('  Road trip  ');
      expect(pl.name, 'Road trip');
      expect(service.validateName('Abc'), isNull);
      expect(service.validateName('   '), isNotNull);
      expect(service.validateName(''), isNotNull);
      await expectLater(
        service.create('   '),
        throwsArgumentError,
      );
    });
  });

  group('CustomPlaylistService membership', () {
    test('addSong appends and songsFor returns insertion order', () async {
      await insertLibrary(['a', 'b', 'c']);
      final pl = await service.create('Trips');
      expect(await service.addSong(pl.id, 'a'), isTrue);
      expect(await service.addSong(pl.id, 'b'), isTrue);
      expect(await service.addSong(pl.id, 'c'), isTrue);

      final songs = await service.songsFor(pl.id);
      expect(songs.map((s) => s.id).toList(), ['a', 'b', 'c']);

      final found = await service.find(pl.id);
      expect(found!.songCount, 3);
    });

    test('addSong is idempotent (no duplicate membership)', () async {
      await insertLibrary(['a']);
      final pl = await service.create('DU');
      expect(await service.addSong(pl.id, 'a'), isTrue);
      expect(await service.addSong(pl.id, 'a'), isFalse);
      expect(await service.addSong(pl.id, 'a'), isFalse);
      expect((await service.songsFor(pl.id)), hasLength(1));
    });

    test('a song can live in several playlists without duplication', () async {
      await insertLibrary(['a']);
      final p1 = await service.create('One');
      final p2 = await service.create('Two');
      await service.addSong(p1.id, 'a');
      await service.addSong(p2.id, 'a');
      expect((await service.playlistsContainingSong('a')), {p1.id, p2.id});
    });

    test('removeSong detaches membership only from that playlist', () async {
      await insertLibrary(['a']);
      final p1 = await service.create('One');
      final p2 = await service.create('Two');
      await service.addSong(p1.id, 'a');
      await service.addSong(p2.id, 'a');

      await service.removeSong(p1.id, 'a');
      expect(await service.songsFor(p1.id), isEmpty);
      expect((await service.songsFor(p2.id)).single.id, 'a');
    });
  });

  group('CustomPlaylistService playlist lifecycle', () {
    test('rename updates the name and bumps updatedAt', () async {
      final pl = await service.create('Old');
      final renamed = await service.rename(pl.id, 'New Name');
      expect(renamed.name, 'New Name');
      expect((await service.find(pl.id))!.name, 'New Name');
    });

    test('delete removes the playlist and its memberships only', () async {
      await insertLibrary(['a', 'b']);
      final pl = await service.create('Gone');
      await service.addSong(pl.id, 'a');
      // A song that lives elsewhere stays behind.
      await service.addSong(pl.id, 'b');

      await service.delete(pl.id);
      expect(await service.find(pl.id), isNull);
      expect(await service.listAll(), isEmpty);
      // Membership for the deleted playlist is gone.
      expect(await service.playlistsContainingSong('a'), isEmpty);
      expect((await service.songsFor(pl.id)), isEmpty);
    });
  });

  group('CustomPlaylistService rename validation', () {
    test('rejects empty and over-long names', () async {
      final pl = await service.create('Keep');
      expect(
        () => service.rename(pl.id, '  '),
        throwsArgumentError,
      );
      expect(
        () => service.rename(pl.id, 'x' * 81),
        throwsArgumentError,
      );
      expect((await service.find(pl.id))!.name, 'Keep');
    });
  });
}