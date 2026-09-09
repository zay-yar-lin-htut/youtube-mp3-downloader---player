import 'package:flutter/foundation.dart';

class DownloadTask {
  final String id;
  final String title;

  /// Progress between 0.0 and 1.0. Null means the total size is unknown,
  /// so the UI should render an indeterminate progress bar.
  final double? progress;
  final bool isCompleted;

  const DownloadTask({
    required this.id,
    required this.title,
    this.progress,
    this.isCompleted = false,
  });

  DownloadTask copyWith({
    double? progress,
    bool? isCompleted,
  }) {
    return DownloadTask(
      id: id,
      title: title,
      progress: progress ?? this.progress,
      isCompleted: isCompleted ?? this.isCompleted,
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

  /// Songs whose download failed, keyed by song id. Pure UI bookkeeping on top
  /// of the (untouched) download engine.
  final Map<String, String> failedDownloads = {};

  Future<void> updateProgress(String id, String title, double? progress) async {
    debugPrint('[DownloadManager] updateProgress id=$id '
        'progress=${progress?.toStringAsFixed(3) ?? "null"}');
    activeDownloads[id] = DownloadTask(
      id: id,
      title: title,
      progress: progress?.clamp(0.0, 1.0),
    );
    notifyListeners();
  }

  Future<void> markCompleted(String id) async {
    final task = activeDownloads[id];
    if (task == null) return;
    activeDownloads[id] = task.copyWith(
      progress: 1.0,
      isCompleted: true,
    );
    failedDownloads.remove(id);
    _historyRevision++;
    notifyListeners();
  }

  void recordFailure(String id, String title) {
    debugPrint('[DownloadManager] recordFailure id=$id title=$title');
    activeDownloads.remove(id);
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