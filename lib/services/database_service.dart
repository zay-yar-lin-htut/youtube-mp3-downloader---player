import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/song.dart';
import 'library_storage.dart';

class DatabaseService implements LibraryStorage {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('playlist.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 6,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
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
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await _createHistoryTable(db);
    await _createPlaylistTables(db);
  }

  Future<void> _createHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS download_history (
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
        source TEXT
      )
    ''');
  }

  Future<void> _createPlaylistTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS custom_playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlist_songs (
        playlistId TEXT NOT NULL,
        songId TEXT NOT NULL,
        position INTEGER NOT NULL,
        addedAt INTEGER NOT NULL,
        PRIMARY KEY (playlistId, songId)
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE playlist ADD COLUMN youtubeUrl TEXT');
      await db.execute('ALTER TABLE playlist ADD COLUMN downloadedAt INTEGER');
    }
    if (oldVersion < 4) {
      await _createHistoryTable(db);
      // Backfill history from library records that already carry a timestamp.
      await db.execute('''
        INSERT INTO download_history (
          id, title, author, duration, thumbnailUrl,
          localPath, youtubeUrl, downloadedAt
        )
        SELECT id, title, author, duration, thumbnailUrl,
          localPath, youtubeUrl, downloadedAt
        FROM playlist
        WHERE downloadedAt IS NOT NULL
      ''');
    }
    if (oldVersion < 5) {
      // v5: playlist can now hold device music too, and every row records
      // where it came from. Existing rows are all FreeVibe downloads.
      await db.execute('ALTER TABLE playlist ADD COLUMN videoId TEXT');
      await db.execute(
        "ALTER TABLE playlist ADD COLUMN source TEXT NOT NULL DEFAULT 'downloaded'",
      );
      await db.execute('ALTER TABLE playlist ADD COLUMN createdAt INTEGER');
      await db.execute(
        'UPDATE playlist SET videoId = id WHERE videoId IS NULL',
      );
      await db.execute(
        'UPDATE playlist SET createdAt = downloadedAt '
        'WHERE createdAt IS NULL AND downloadedAt IS NOT NULL',
      );
      // Keep the history table schema compatible for inserts/roundtrips.
      await db.execute('ALTER TABLE download_history ADD COLUMN videoId TEXT');
      await db.execute('ALTER TABLE download_history ADD COLUMN source TEXT');
      await db.execute(
        'ALTER TABLE download_history ADD COLUMN createdAt INTEGER',
      );
      await db.execute(
        'UPDATE download_history SET videoId = id WHERE videoId IS NULL',
      );
    }
    if (oldVersion < 6) {
      // v6: custom playlists (multi-membership, no file duplication).
      await _createPlaylistTables(db);
    }
  }

  Future<void> setSetting(String key, String value) async {
    final db = await instance.database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await instance.database;
    final result = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (result.isEmpty) {
      return null;
    }
    return result.first['value'] as String?;
  }

  @override
  Future<void> insertSong(Song song) async {
    final db = await instance.database;
    await db.insert(
      'playlist',
      song.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<Song>> getPlaylist() async {
    final db = await instance.database;
    final result = await db.query('playlist');
    return result.map((map) => Song.fromMap(map)).toList();
  }

  @override
  Future<void> updateSong(Song song) async {
    final db = await instance.database;
    await db.update(
      'playlist',
      song.toMap(),
      where: 'id = ?',
      whereArgs: [song.id],
    );
  }

  @override
  Future<void> deleteSong(String id) async {
    final db = await instance.database;
    await db.delete('playlist', where: 'id = ?', whereArgs: [id]);
    await db.delete(
      'playlist_songs',
      where: 'songId = ?',
      whereArgs: [id],
    );
  }

  /// Records a completed download in the history log. The library/playlist
  /// table and the audio file on disk are intentionally left untouched here.
  Future<void> insertHistory(Song song) async {
    final db = await instance.database;
    await db.insert(
      'download_history',
      song.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Downloaded songs, newest first.
  Future<List<Song>> getDownloadHistory() async {
    final db = await instance.database;
    final result = await db.query(
      'download_history',
      orderBy: 'downloadedAt DESC',
    );
    return result.map((map) => Song.fromMap(map)).toList();
  }

  /// Deletes ALL download-history records. Audio files on disk and the
  /// library/playlist rows stay intact.
  Future<void> clearDownloadHistory() async {
    final db = await instance.database;
    await db.delete('download_history');
  }

  /// Renames a downloaded song everywhere it is referenced: the library row
  /// and the history log. Both keep the same id so playlist membership stays
  /// intact. The audio file itself is handled by the caller.
  Future<void> updateDownloadHistoryMetadata(
    String songId,
    String title,
    String localPath,
  ) async {
    final db = await instance.database;
    await db.update(
      'download_history',
      {'title': title, 'localPath': localPath},
      where: 'id = ?',
      whereArgs: [songId],
    );
  }

  /// Test seam: point the singleton at a closed in-memory/ffi database.
  /// Must be paired with `close()` from within the calling test.
  @visibleForTesting
  static void debugSetDatabase(Database? db) {
    _database = db;
  }
}
