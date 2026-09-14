import '../services/database_service.dart';

/// Persists per-song playback positions ("resume points") so a song can be
/// continued from where it was left off when it is played again.
///
/// The real implementation lives in the existing `app_settings` key/value
/// table — NO SQLite schema change was required. Each song maps to a
/// `resume_<songId>` key holding its last position in milliseconds.
abstract class ResumeStore {
  Future<void> save(String songId, Duration position);

  Future<Duration?> load(String songId);

  Future<void> clear(String songId);

  /// All saved resume positions, keyed by song id.
  Future<Map<String, Duration>> loadAll();
}

class DatabaseResumeStore implements ResumeStore {
  DatabaseResumeStore({DatabaseService? db})
      : _db = db ?? DatabaseService.instance;

  final DatabaseService _db;

  static const String resumePrefix = 'resume_';

  @override
  Future<void> save(String songId, Duration position) async {
    if (position <= Duration.zero) {
      return;
    }
    await _db.setSetting('$resumePrefix$songId', '${position.inMilliseconds}');
  }

  @override
  Future<Duration?> load(String songId) async {
    final raw = await _db.getSetting('$resumePrefix$songId');
    if (raw == null) {
      return null;
    }
    final ms = int.tryParse(raw) ?? 0;
    if (ms <= 0) {
      return null;
    }
    return Duration(milliseconds: ms);
  }

  @override
  Future<void> clear(String songId) async {
    await _db.deleteSetting('$resumePrefix$songId');
  }

  @override
  Future<Map<String, Duration>> loadAll() async {
    final all = await _db.getAllSettings();
    final result = <String, Duration>{};
    for (final entry in all.entries) {
      if (!entry.key.startsWith(resumePrefix)) {
        continue;
      }
      final songId = entry.key.substring(resumePrefix.length);
      final ms = int.tryParse(entry.value) ?? 0;
      if (songId.isNotEmpty && ms > 0) {
        result[songId] = Duration(milliseconds: ms);
      }
    }
    return result;
  }
}