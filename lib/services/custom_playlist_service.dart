import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../models/custom_playlist.dart';
import '../models/song.dart';
import 'database_service.dart';

/// Persists user-created playlists and their song membership in SQLite.
///
/// Playlists contain references (by stable `song.id`), never file copies, and
/// a song may belong to any number of playlists. Ordering within a playlist
/// follows insertion order.
class CustomPlaylistService {
  CustomPlaylistService({DatabaseService? storage, DateTime Function()? clock})
      : _storage = storage ?? DatabaseService.instance,
        _clock = clock ?? DateTime.now;

  static int _nonce = 0;
  final DatabaseService _storage;
  final DateTime Function() _clock;

  String _newId() {
    _nonce++;
    final rand = Random();
    final n = DateTime.now().millisecondsSinceEpoch;
    final suffix =
        '${rand.nextInt(0xFFFFFF).toRadixString(16)}${_nonce.toRadixString(16)}';
    return 'pl_${n.toRadixString(16)}_$suffix';
  }

  /// Returns a user-facing validation message, or `null` when valid.
  String? validateName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return 'Playlist name cannot be empty';
    if (name.length > 80) return 'Playlist name is too long';
    if (name == '.') return 'Playlist name is invalid';
    return null;
  }

  Future<Database> get _db => _storage.database;

  Future<List<CustomPlaylist>> listAll() async {
    final db = await _db;
    final counts = await db.rawQuery('''
      SELECT playlistId, COUNT(*) AS count
      FROM playlist_songs
      GROUP BY playlistId
    ''');
    final countByPlaylist = <String, int>{
      for (final row in counts) row['playlistId'] as String: row['count'] as int,
    };
    final rows = await db.query(
      'custom_playlists',
      orderBy: 'createdAt ASC',
    );
    return [
      for (final row in rows)
        CustomPlaylist.fromMap(row).copyWith(
          songCount: countByPlaylist[row['id'] as String] ?? 0,
        ),
    ];
  }

  Future<CustomPlaylist?> find(String id) async {
    final db = await _db;
    final rows = await db.query(
      'custom_playlists',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final count = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM playlist_songs WHERE playlistId = ?',
      [id],
    );
    return CustomPlaylist.fromMap(rows.first).copyWith(
      songCount: count.first['count'] as int,
    );
  }

  Future<CustomPlaylist> create(String rawName) async {
    final name = rawName.trim();
    final error = validateName(name);
    if (error != null) throw ArgumentError(error);
    final now = _clock().millisecondsSinceEpoch;
    final playlist = CustomPlaylist(
      id: _newId(),
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    final db = await _db;
    await db.insert('custom_playlists', {
      'id': playlist.id,
      'name': playlist.name,
      'createdAt': playlist.createdAt,
      'updatedAt': playlist.updatedAt,
    });
    return playlist;
  }

  Future<CustomPlaylist> rename(String id, String rawName) async {
    final name = rawName.trim();
    final error = validateName(name);
    if (error != null) throw ArgumentError(error);
    final db = await _db;
    await db.update(
      'custom_playlists',
      {'name': name, 'updatedAt': _clock().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
    final result = await find(id);
    if (result == null) throw StateError('Playlist no longer exists');
    return result;
  }

  /// Deletes the playlist and all of its memberships. Songs and files are
  /// never touched.
  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete('playlist_songs', where: 'playlistId = ?', whereArgs: [id]);
    await db.delete('custom_playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Song>> songsFor(String playlistId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT p.*
      FROM playlist_songs ps
      JOIN playlist p ON p.id = ps.songId
      WHERE ps.playlistId = ?
      ORDER BY ps.position ASC, ps.addedAt ASC
    ''', [playlistId]);
    return rows.map((map) => Song.fromMap(map)).toList();
  }

  /// Adds [songId] to the playlist at the end, unless it is already there.
  Future<bool> addSong(String playlistId, String songId) async {
    final db = await _db;
    final exists = await db.query(
      'playlist_songs',
      where: 'playlistId = ? AND songId = ?',
      whereArgs: [playlistId, songId],
      limit: 1,
    );
    if (exists.isNotEmpty) return false;
    final position = await db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) AS maxPos '
      'FROM playlist_songs WHERE playlistId = ?',
      [playlistId],
    );
    await db.insert('playlist_songs', {
      'playlistId': playlistId,
      'songId': songId,
      'position': (position.first['maxPos'] as int) + 1,
      'addedAt': _clock().millisecondsSinceEpoch,
    });
    await db.update(
      'custom_playlists',
      {'updatedAt': _clock().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
    return true;
  }

  Future<void> removeSong(String playlistId, String songId) async {
    final db = await _db;
    await db.delete(
      'playlist_songs',
      where: 'playlistId = ? AND songId = ?',
      whereArgs: [playlistId, songId],
    );
  }

  /// Playlist ids that contain [songId].
  Future<Set<String>> playlistsContainingSong(String songId) async {
    final db = await _db;
    final rows = await db.query(
      'playlist_songs',
      columns: ['playlistId'],
      where: 'songId = ?',
      whereArgs: [songId],
    );
    return {for (final row in rows) row['playlistId'] as String};
  }
}