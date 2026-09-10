import '../models/song.dart';

/// Minimal storage seam used by [PlaylistRepository]. The production
/// implementation is [DatabaseService]; tests inject an in-memory fake.
abstract class LibraryStorage {
  Future<List<Song>> getPlaylist();

  Future<void> insertSong(Song song);

  /// Replaces the stored row for [song]. Memberships (custom playlists) are
  /// keyed by the stable `song.id` and must be left untouched.
  Future<void> updateSong(Song song);

  Future<void> deleteSong(String id);
}