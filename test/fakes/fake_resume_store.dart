import 'package:yt_local_music/services/resume_store.dart';

/// In-memory [ResumeStore] for unit/widget tests.
class FakeResumeStore implements ResumeStore {
  final Map<String, Duration> data = {};

  @override
  Future<void> save(String songId, Duration position) async {
    data[songId] = position;
  }

  @override
  Future<Duration?> load(String songId) async => data[songId];

  @override
  Future<void> clear(String songId) async {
    data.remove(songId);
  }

  @override
  Future<Map<String, Duration>> loadAll() async => Map.of(data);
}