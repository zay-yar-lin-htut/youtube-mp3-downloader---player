import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/song.dart';

/// Playback entry — wraps a [Song] and remembers its media source.
enum PlaybackSource { local, preview }

@immutable
class QueueEntry {
  const QueueEntry({required this.song, required this.source});

  final Song song;
  final PlaybackSource source;

  @override
  bool operator ==(Object other) =>
      other is QueueEntry &&
      other.song.id == song.id &&
      other.source == source;

  @override
  int get hashCode => Object.hash(song.id, source);
}

/// Pure Dart queue + shuffle/repeat bookkeeping. Kept free of just_audio so it
/// is fully unit-testable.
class PlayerQueue extends ChangeNotifier {
  final List<QueueEntry> _entries = [];
  final math.Random _random;

  /// Playback index inside [_active].
  int _cursor = -1;

  /// The order actually played. Equals [_entries] while shuffle is off;
  /// otherwise a shuffled permutation of it (current track pinned at index 0).
  List<QueueEntry> _active = [];

  bool _shuffleEnabled = false;

  PlayerQueue({math.Random? random}) : _random = random ?? math.Random();

  List<QueueEntry> get entries => List.unmodifiable(_entries);

  List<QueueEntry> get activeOrder => List.unmodifiable(_active);

  bool get isShuffleEnabled => _shuffleEnabled;

  bool get isEmpty => _entries.isEmpty;

  int get length => _entries.length;

  int get cursor => _cursor;

  QueueEntry? get currentEntry =>
      (_cursor >= 0 && _cursor < _active.length) ? _active[_cursor] : null;

  Song? get currentSong => currentEntry?.song;

  QueueEntry entryAt(int index) => _entries[index];

  int indexOfSong(String songId) => _entries.indexWhere((e) => e.song.id == songId);

  /// Rebuilds the queue from scratch; [playIndex] selects the active-order
  /// index that plays first (defaults to 0). When shuffle is enabled the
  /// tapped entry is pinned to the front of the shuffled pool so the user's
  /// tap target always plays first.
  void resetForPlayback(List<QueueEntry> entries, {int? playIndex}) {
    _entries
      ..clear()
      ..addAll(entries);
    if (_shuffleEnabled) {
      final pinIndex = (playIndex ?? 0).clamp(0, _entries.isEmpty ? -1 : _entries.length - 1);
      final pinned = pinIndex >= 0 ? _entries[pinIndex] : null;
      final pool = List<QueueEntry>.of(_entries);
      if (pinned != null) {
        pool.removeWhere((e) => e.song.id == pinned.song.id);
      }
      pool.shuffle(_random);
      _active = pinned == null ? pool : [pinned, ...pool];
      _cursor = 0;
    } else {
      _rebuildActive();
      _cursor = (playIndex ?? 0).clamp(0, _active.isEmpty ? -1 : _active.length - 1);
    }
    notifyListeners();
  }

  /// Moves [entry] to the front of the community and plays it now.
  void insertAndPlay(QueueEntry entry) {
    final existing = _entries.indexWhere((e) => e.song.id == entry.song.id);
    if (existing >= 0) {
      _entries.removeAt(existing);
    }
    _entries.insert(0, entry);
    _rebuildActive();
    _cursor = _active.indexWhere((e) => e.song.id == entry.song.id);
    notifyListeners();
  }

  /// Appends to the canonical list and places it right after the current track
  /// in the active (played) order.
  void addToQueue(QueueEntry entry) {
    if (_entries.any((e) => e.song.id == entry.song.id)) {
      return;
    }
    _entries.add(entry);
    _insertInActiveAfterCursor(entry);
    notifyListeners();
  }

  void _insertInActiveAfterCursor(QueueEntry entry) {
    if (_active.isEmpty) {
      _active.add(entry);
      return;
    }
    if (!_shuffleEnabled) {
      _active.add(entry);
      return;
    }
    final insertPoint = _cursor + 1;
    _active.insert(insertPoint.clamp(0, _active.length), entry);
  }

  /// Removes every occurrence of [songId] (used by delete flows).
  /// Returns whether the removed entry was the currently playing one.
  bool removeSong(String songId) {
    final wasCurrent = currentSong?.id == songId;
    _entries.removeWhere((e) => e.song.id == songId);
    _active.removeWhere((e) => e.song.id == songId);
    if (_active.isEmpty) {
      _cursor = -1;
    } else if (_cursor >= _active.length) {
      _cursor = _active.length - 1;
    }
    notifyListeners();
    return wasCurrent;
  }

  /// Removes the entry at the given *active-order* index (queue sheet UI).
  QueueEntry? removeAtActiveIndex(int index) {
    if (index < 0 || index >= _active.length) {
      return null;
    }
    final removed = _active.removeAt(index);
    _entries.removeWhere((e) => e.song.id == removed.song.id);
    if (_active.isEmpty) {
      _cursor = -1;
    } else if (_cursor > index) {
      _cursor -= 1;
    } else if (_cursor == index) {
      _cursor = _cursor.clamp(0, _active.length - 1);
    }
    notifyListeners();
    return removed;
  }

  /// Empties the queue entirely.
  void removeAll() {
    _entries.clear();
    _active.clear();
    _cursor = -1;
    notifyListeners();
  }

  /// Drops everything after the current track from the playback order.
  void clearUpcoming() {
    if (_active.isEmpty || _cursor < 0 || _cursor >= _active.length - 1) {
      notifyListeners();
      return;
    }
    final droppedIds = _active.sublist(_cursor + 1).map((e) => e.song.id).toSet();
    _active.removeRange(_cursor + 1, _active.length);
    _entries.removeWhere((e) => droppedIds.contains(e.song.id));
    notifyListeners();
  }

  QueueEntry? peekNext({bool wrapAtEnd = false}) {
    if (_active.isEmpty) {
      return null;
    }
    final nextIndex = _cursor + 1;
    if (nextIndex < _active.length) {
      return _active[nextIndex];
    }
    return wrapAtEnd ? _active[0] : null;
  }

  QueueEntry? peekPrevious() {
    if (_active.isEmpty) {
      return null;
    }
    final prevIndex = _cursor - 1;
    if (prevIndex >= 0) {
      return _active[prevIndex];
    }
    return _active.last;
  }

  void advance() {
    if (_active.isEmpty) {
      return;
    }
    final nextIndex = _cursor + 1;
    _cursor = (nextIndex < _active.length) ? nextIndex : 0;
    notifyListeners();
  }

  void goToActiveIndex(int index) {
    if (index < 0 || index >= _active.length) {
      return;
    }
    _cursor = index;
    notifyListeners();
  }

  void enableShuffle() {
    if (_shuffleEnabled) {
      return;
    }
    _shuffleEnabled = true;
    _rebuildActive();
    notifyListeners();
  }

  void disableShuffle() {
    if (!_shuffleEnabled) {
      return;
    }
    final currentId = currentSong?.id;
    _shuffleEnabled = false;
    _active = List.of(_entries);
    if (currentId != null && _active.isNotEmpty) {
      _cursor = _active.indexWhere((e) => e.song.id == currentId);
    } else {
      _cursor = _active.isEmpty ? -1 : _cursor.clamp(0, _active.length - 1);
    }
    notifyListeners();
  }

  void _rebuildActive() {
    if (_entries.isEmpty) {
      _active = [];
      _cursor = -1;
      return;
    }
    if (!_shuffleEnabled) {
      _active = List.of(_entries);
      return;
    }
    QueueEntry? current = (_cursor >= 0 && _cursor < _active.length)
        ? _active[_cursor]
        : null;
    final pool = List<QueueEntry>.of(_entries);
    if (current != null) {
      pool.removeWhere((e) => e.song.id == current.song.id);
      pool.shuffle(_random);
      _active = [current, ...pool];
    } else {
      pool.shuffle(_random);
      _active = pool;
    }
    _cursor = 0;
  }
}