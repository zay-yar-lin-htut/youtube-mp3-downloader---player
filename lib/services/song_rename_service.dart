import 'dart:io';

import '../models/song.dart';
import '../services/database_service.dart';
import '../services/library_storage.dart';

/// Outcome of a rename attempt: either the updated [Song] with its new
/// title + path, or a user-facing [error] message (storage/file untouched).
class SongRenameResult {
  const SongRenameResult.ok(this.song) : error = null;
  const SongRenameResult.failure(this.error) : song = null;

  final Song? song;
  final String? error;

  bool get ok => song != null;
}

/// Renames a *downloaded* song: validates the new name, renames the owned
/// audio file on disk and only then updates the library + history rows. The
/// stable song id (== and therefore playlist memberships) never changes.
///
/// Device songs and YouTube-only results are deliberately refused (there is no
/// owned file FreeVibe may touch).
class SongRenameService {
  SongRenameService({
    LibraryStorage? storage,
    Future<void> Function(Song song)? onHistoryUpdate,
  })  : _storage = storage ?? DatabaseService.instance,
        _onHistoryUpdate = onHistoryUpdate ??
            ((song) => DatabaseService.instance.updateDownloadHistoryMetadata(
                  song.id,
                  song.title,
                  song.localPath!,
                ));

  final LibraryStorage _storage;
  final Future<void> Function(Song song) _onHistoryUpdate;

  /// Returns a user-facing message when [raw] is unusable as a filename stem.
  String? validateNewName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return 'Name cannot be empty';
    if (name.length > 120) return 'Name is too long';
    if (name == '.' || name == '..') return 'Name is invalid';
    if (RegExp(r'[\\/:*?"<>|\u0000]').hasMatch(name)) {
      return 'Name contains invalid characters';
    }
    return null;
  }

  /// Splits the file name into `(stem, extension)` where the extension keeps
  /// its leading dot. `foo.m4a` -> `('foo', '.m4a')`.
  static (String, String) splitFileName(String pathOrUri) {
    final fileName =
        pathOrUri.split(RegExp(r'[\\/]')).last.replaceAll('?', '');
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) return (fileName, '');
    return (fileName.substring(0, dot), fileName.substring(dot));
  }

  /// Whether FreeVibe owns the file behind [song] and may rename it.
  bool canRename(Song song) {
    final path = song.localPath;
    if (song.source != SongSource.downloaded || path == null) return false;
    final uri = Uri.tryParse(path);
    if (uri != null &&
        (uri.scheme == 'content' || uri.scheme == 'http' || uri.scheme == 'https')) {
      return false;
    }
    return true;
  }

  Future<SongRenameResult> rename(Song song, String rawName) async {
    final name = rawName.trim();
    final validation = validateNewName(name);
    if (validation != null) return SongRenameResult.failure(validation);
    if (!canRename(song)) {
      return const SongRenameResult.failure(
        'This song cannot be renamed: FreeVibe does not own its file.',
      );
    }

    final path = song.localPath!;
    final sep = _lastSeparatorIndex(path);
    if (sep < 0) {
      return const SongRenameResult.failure(
        'The audio file path is invalid.',
      );
    }
    final dir = path.substring(0, sep + 1);
    final (_, ext) = splitFileName(path);

    final newPath = '$dir$name$ext';
    if (newPath == path) {
      // Same name: nothing to do, already consistent.
      return SongRenameResult.ok(song);
    }

    final file = File(path);
    if (!await file.exists()) {
      return const SongRenameResult.failure(
        'The audio file was not found on disk.',
      );
    }
    if (await File(newPath).exists()) {
      return SongRenameResult.failure(
        'A file named "$name$ext" already exists. '
        'Choose a different name.',
      );
    }

    try {
      await file.rename(newPath);
    } catch (_) {
      return const SongRenameResult.failure(
        'The file could not be renamed. Try a different name.',
      );
    }

    final updated = song.copyWith(title: name, localPath: newPath);
    try {
      await _storage.updateSong(updated);
      await _onHistoryUpdate(updated);
    } catch (_) {
      // DB persistence is best-effort: the file is already renamed and the
      // in-memory library will reconcile on the next repository load.
    }
    return SongRenameResult.ok(updated);
  }

  int _lastSeparatorIndex(String path) {
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf(r'\');
    return slash > backslash ? slash : backslash;
  }
}