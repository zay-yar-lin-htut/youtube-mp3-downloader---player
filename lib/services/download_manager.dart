import 'package:flutter/foundation.dart';
import 'dart:math' as math;

enum DownloadStatus {
  waiting,
  downloading,
  completed,
  failed,
  paused,
  cancelled,
}

class DownloadTask {
  final String id;
  final String title;

  /// Progress between 0.0 and 1.0. Null means the total size is unknown,
  /// so the UI should render an indeterminate progress bar.
  final double? progress;
  final bool isCompleted;
  final DownloadStatus status;
  final int downloadedBytes;
  final int? totalBytes;
  final double? speedBytesPerSecond;
  final Duration? eta;

  const DownloadTask({
    required this.id,
    required this.title,
    this.progress,
    this.isCompleted = false,
    this.status = DownloadStatus.downloading,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.speedBytesPerSecond,
    this.eta,
  });

  DownloadTask copyWith({
    double? progress,
    bool? isCompleted,
    DownloadStatus? status,
    int? downloadedBytes,
    int? totalBytes,
    double? speedBytesPerSecond,
    Duration? eta,
  }) {
    return DownloadTask(
      id: id,
      title: title,
      progress: progress ?? this.progress,
      isCompleted: isCompleted ?? this.isCompleted,
      status: status ?? this.status,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
      eta: eta ?? this.eta,
    );
  }
}

class DownloadManager extends ChangeNotifier {
  DownloadManager._();

  static final DownloadManager instance = DownloadManager._();

  /// Bumped on structural changes (a download completing, a failure being
  /// recorded/dismissed, a row inserted/deleted by UI code) so listening
  /// screens can reload the DB list. Progress ticks deliberately do NOT bump
  /// it, keeping history reloads cheap.
  static int _historyRevision = 0;
  static int get historyRevision => _historyRevision;

  final Map<String, DownloadTask> activeDownloads = {};
  final Map<String, List<_ProgressSample>> _samples = {};

  /// Songs whose download failed, keyed by song id. Pure UI bookkeeping on top
  /// of the (untouched) download engine.
  final Map<String, String> failedDownloads = {};

  Future<void> updateProgress(
    String id,
    String title,
    double? progress, {
    int downloadedBytes = 0,
    int? totalBytes,
  }) async {
    debugPrint(
      '[DownloadManager] updateProgress id=$id '
      'progress=${progress?.toStringAsFixed(3) ?? "null"}',
    );
    final now = DateTime.now();
    final samples = _samples.putIfAbsent(id, () => <_ProgressSample>[]);
    samples.add(_ProgressSample(now, downloadedBytes));
    samples.removeWhere((sample) => now.difference(sample.at).inSeconds > 3);
    double? speed;
    if (samples.length >= 2) {
      final first = samples.first;
      final seconds = now.difference(first.at).inMilliseconds / 1000;
      if (seconds > 0) {
        speed = math.max(0, downloadedBytes - first.bytes) / seconds;
      }
    }
    final remaining = totalBytes == null
        ? null
        : math.max(0, totalBytes - downloadedBytes);
    final eta = speed != null && speed > 0 && remaining != null
        ? Duration(seconds: (remaining / speed).ceil())
        : null;
    activeDownloads[id] = DownloadTask(
      id: id,
      title: title,
      progress: progress?.clamp(0.0, 1.0),
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      speedBytesPerSecond: speed,
      eta: eta,
      status: DownloadStatus.downloading,
    );
    notifyListeners();
  }

  Future<void> markCompleted(String id) async {
    final task = activeDownloads[id];
    if (task == null) return;
    activeDownloads[id] = task.copyWith(
      progress: 1.0,
      isCompleted: true,
      status: DownloadStatus.completed,
    );
    failedDownloads.remove(id);
    _historyRevision++;
    notifyListeners();
  }

  void recordFailure(String id, String title) {
    debugPrint('[DownloadManager] recordFailure id=$id title=$title');
    activeDownloads.remove(id);
    _samples.remove(id);
    failedDownloads[id] = title;
    _historyRevision++;
    notifyListeners();
  }

  void removeFailure(String id) {
    failedDownloads.remove(id);
    _historyRevision++;
    notifyListeners();
  }

  void remove(String id) {
    activeDownloads.remove(id);
    _samples.remove(id);
    _historyRevision++;
    notifyListeners();
  }

  /// Tells listening screens the underlying DB list may have changed (e.g. a
  /// playlist row was inserted or deleted by the app layer, which happens
  /// strictly AFTER the downloader signals completion). Screens reload on any
  /// revision bump that is not a progress tick.
  void notifyHistoryChanged() {
    _historyRevision++;
    notifyListeners();
  }
}

class _ProgressSample {
  const _ProgressSample(this.at, this.bytes);

  final DateTime at;
  final int bytes;
}
