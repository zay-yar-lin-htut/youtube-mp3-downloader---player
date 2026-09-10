import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'database_service.dart';

/// Debounced, latest-query-wins YouTube search suggestions.
///
/// Kept separate from the search-results pipeline so a stale suggestion never
/// interferes with an active search. The fetcher is injected so pure Dart
/// tests can drive it with a stub instead of YouTubeService.
class SearchSuggestionService {
  SearchSuggestionService({
    required Future<List<String>> Function(String query) fetchSuggestions,
    this.debounce = const Duration(milliseconds: 350),
  }) : _fetch = fetchSuggestions;

  final Future<List<String>> Function(String query) _fetch;
  final Duration debounce;

  Timer? _timer;
  int _generation = 0;

  /// Schedules a (debounced) suggestion fetch for [query]. When it completes
  /// [onResult] is called with the newest result, unless a newer request (or
  /// [cancel]) invalidated it. Empty results are reported as an empty list.
  void requestSuggestions(String query, ValueChanged<List<String>> onResult) {
    final trimmed = query.trim();
    _timer?.cancel();
    final generation = ++_generation;
    if (trimmed.isEmpty) {
      return;
    }
    _timer = Timer(debounce, () async {
      try {
        final suggestions = await _fetch(trimmed);
        if (generation == _generation) {
          onResult(suggestions);
        }
      } catch (_) {
        if (generation == _generation) {
          onResult(const []);
        }
      }
    });
  }

  /// Invalidates any pending or in-flight suggestion request.
  void cancel() {
    _timer?.cancel();
    _generation++;
  }

  void dispose() {
    _timer?.cancel();
    _generation++;
  }
}

/// Small, persisted history of recent search queries (deduplicated, capped,
/// most-recent first). Persistence is injected so unit tests can run without
/// sqflite.
class RecentSearchStore {
  RecentSearchStore({
    this.load,
    this.save,
    this.maxEntries = 8,
  });

  /// [SearchSuggestionService]-independent storage bound to app settings.
  factory RecentSearchStore.db() => RecentSearchStore(
        load: () async {
          final raw = await DatabaseService.instance.getSetting(
            'recent_searches',
          );
          if (raw == null) {
            return const <String>[];
          }
          try {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              return decoded.map((e) => e.toString()).toList();
            }
          } catch (_) {}
          return const <String>[];
        },
        save: (items) => DatabaseService.instance.setSetting(
          'recent_searches',
          jsonEncode(items),
        ),
      );

  final Future<List<String>?> Function()? load;
  final Future<void> Function(List<String> items)? save;
  final int maxEntries;

  List<String> _items = const [];
  bool _loaded = false;

  /// Most-recent-first recent queries, newest at index 0.
  List<String> get items => List.unmodifiable(_items);

  Future<void> ensureLoaded() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    try {
      final stored = await load?.call();
      if (stored != null) {
        _items = stored.take(maxEntries).toList();
      }
    } catch (_) {
      _items = const [];
    }
  }

  Future<void> add(String query) async {
    await ensureLoaded();
    final q = query.trim();
    if (q.isEmpty) {
      return;
    }
    _items = [q, ..._items.where((e) => e != q)];
    if (_items.length > maxEntries) {
      _items = _items.sublist(0, maxEntries);
    }
    await _persist();
  }

  Future<void> remove(String query) async {
    await ensureLoaded();
    _items = _items.where((e) => e != query).toList();
    await _persist();
  }

  Future<void> clear() async {
    _items = const [];
    await _persist();
  }

  Future<void> _persist() async {
    try {
      await save?.call(_items);
    } catch (_) {}
  }
}