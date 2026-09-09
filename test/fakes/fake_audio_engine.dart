import 'package:flutter/foundation.dart';
import 'package:yt_local_music/player/audio_engine.dart';

/// In-memory [AudioEngine] for widget/unit tests. Simulates loading, playback
/// and completed events without any platform channels.
class FakeAudioEngine implements AudioEngine {
  FakeAudioEngine();

  final _stage = ValueNotifier<EngineStage>(EngineStage.idle);
  final _position = ValueNotifier<Duration>(Duration.zero);
  final _duration = ValueNotifier<Duration>(Duration.zero);

  final List<String> loadedSources = [];
  bool failNextLoad = false;
  Object? loadError;

  @override
  ValueListenable<EngineStage> get stage => _stage;

  @override
  ValueListenable<Duration> get position => _position;

  @override
  ValueListenable<Duration> get duration => _duration;

  EngineStage get currentStage => _stage.value;

  bool get isPlaying => _stage.value == EngineStage.playing;

  @override
  bool get hasLoadedSource => loadedSources.isNotEmpty;

  @override
  Future<void> loadRemote(String url) async {
    if (failNextLoad || loadError != null) {
      throw loadError ?? StateError('load failed');
    }
    loadedSources.add(url);
    _duration.value = const Duration(seconds: 210);
    _position.value = Duration.zero;
    _stage.value = EngineStage.playing;
  }

  @override
  Future<void> loadLocal(String filePath) async {
    if (failNextLoad || loadError != null) {
      throw loadError ?? StateError('load failed');
    }
    loadedSources.add('file:$filePath');
    _duration.value = const Duration(seconds: 210);
    _position.value = Duration.zero;
    _stage.value = EngineStage.playing;
  }

  @override
  Future<void> play() async {
    _stage.value = EngineStage.playing;
  }

  @override
  Future<void> pause() async {
    _stage.value = EngineStage.paused;
  }

  @override
  Future<void> stop() async {
    _stage.value = EngineStage.idle;
    _position.value = Duration.zero;
  }

  @override
  Future<void> seekTo(Duration position) async {
    _position.value = position;
  }

  /// Simulates reaching the end of the current source.
  void complete() {
    _stage.value = EngineStage.completed;
  }

  @override
  Future<void> dispose() async {
    _stage.dispose();
    _position.dispose();
    _duration.dispose();
  }
}