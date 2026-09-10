import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_local_music/services/search_suggestion_service.dart';

void main() {
  group('SearchSuggestionService', () {
    test('debounces rapid typing into a single fetch of the latest query',
        () {
      fakeAsync((async) {
        final fetches = <String>[];
        final results = <List<String>>[];
        final service = SearchSuggestionService(
          debounce: const Duration(milliseconds: 350),
          fetchSuggestions: (q) async {
            fetches.add(q);
            return [q];
          },
        );

        service.requestSuggestions('coldp', results.add);
        async.elapse(const Duration(milliseconds: 100));
        service.requestSuggestions('coldpla', results.add);
        async.elapse(const Duration(milliseconds: 100));
        service.requestSuggestions('coldplay', results.add);
        async.elapse(const Duration(milliseconds: 350));

        expect(fetches, ['coldplay']);
        expect(results, [
          ['coldplay'],
        ]);
      });
    });

    test('latest request wins when two fetches overlap in flight', () {
      fakeAsync((async) {
        final completers = <String, Completer<List<String>>>{};
        final service = SearchSuggestionService(
          debounce: const Duration(milliseconds: 50),
          fetchSuggestions: (q) {
            final c = Completer<List<String>>();
            completers[q] = c;
            return c.future;
          },
        );
        final results = <List<String>>[];

        service.requestSuggestions('query one', results.add);
        async.elapse(const Duration(milliseconds: 50));
        service.requestSuggestions('query two', results.add);
        async.elapse(const Duration(milliseconds: 50));

        // The newer request completes first; its result is delivered.
        completers['query two']!.complete(const ['two-a', 'two-b']);
        async.flushMicrotasks();
        expect(results, const [
          ['two-a', 'two-b'],
        ]);

        // The stale request then completes — it must be dropped.
        completers['query one']!.complete(const ['one']);
        async.flushMicrotasks();
        expect(results, const [
          ['two-a', 'two-b'],
        ]);
      });
    });

    test('stale result is dropped even when it finishes before a newer fetch starts', () {
      fakeAsync((async) {
        final completers = <String, Completer<List<String>>>{};
        final service = SearchSuggestionService(
          debounce: const Duration(milliseconds: 50),
          fetchSuggestions: (q) {
            final c = Completer<List<String>>();
            completers[q] = c;
            return c.future;
          },
        );
        final results = <List<String>>[];

        service.requestSuggestions('a', results.add);
        async.elapse(const Duration(milliseconds: 50));
        // Newer request supersedes 'a' before 'a' has resolved.
        service.requestSuggestions('b', results.add);
        async.elapse(const Duration(milliseconds: 50));

        completers['a']!.complete(const ['stale']);
        async.flushMicrotasks();
        expect(results, isEmpty);

        completers['b']!.complete(const ['fresh']);
        async.flushMicrotasks();
        expect(results, const [
          ['fresh'],
        ]);
      });
    });

    test('cancel() suppresses pending and in-flight results', () {
      fakeAsync((async) {
        final fetches = <String>[];
        final results = <List<String>>[];
        final completers = <String, Completer<List<String>>>{};
        final service = SearchSuggestionService(
          debounce: const Duration(milliseconds: 50),
          fetchSuggestions: (q) {
            fetches.add(q);
            final c = Completer<List<String>>();
            completers[q] = c;
            return c.future;
          },
        );

        // Pending:
        service.requestSuggestions('pending', results.add);
        async.elapse(const Duration(milliseconds: 20));
        service.cancel();
        async.elapse(const Duration(milliseconds: 100));
        expect(fetches, isEmpty);

        // In-flight:
        service.requestSuggestions('inflight', results.add);
        async.elapse(const Duration(milliseconds: 50));
        service.cancel();
        completers['inflight']!.complete(const ['late']);
        async.flushMicrotasks();
        expect(results, isEmpty);
      });
    });

    test('fetch failures surface as empty suggestions', () {
      fakeAsync((async) {
        final results = <List<String>>[];
        final service = SearchSuggestionService(
          debounce: const Duration(milliseconds: 20),
          fetchSuggestions: (_) async => throw Exception('network'),
        );
        service.requestSuggestions('song', results.add);
        async.elapse(const Duration(milliseconds: 20));
        async.flushMicrotasks();
        expect(results, const [<String>[]]);
      });
    });

    test('empty or whitespace-only queries never fetch', () {
      fakeAsync((async) {
        var fetches = 0;
        final service = SearchSuggestionService(
          debounce: const Duration(milliseconds: 20),
          fetchSuggestions: (_) async {
            fetches++;
            return const [];
          },
        );
        service.requestSuggestions('   ', (_) {});
        service.requestSuggestions('', (_) {});
        async.elapse(const Duration(milliseconds: 100));
        expect(fetches, 0);
      });
    });
  });

  group('RecentSearchStore', () {
    test('dedupes, caps, keeps most-recent-first and persists', () async {
      final saved = <List<String>>[];
      final store = RecentSearchStore(
        maxEntries: 3,
        save: (items) async => saved.add(items),
      );

      await store.add('coldplay');
      await store.add('ed sheeran');
      await store.add('coldplay'); // moves to front, no duplicate
      expect(store.items, ['coldplay', 'ed sheeran']);
      expect(saved.last, ['coldplay', 'ed sheeran']);

      await store.add('radiohead');
      await store.add('nirvana'); // exceeds cap -> oldest dropped
      expect(store.items, ['nirvana', 'radiohead', 'coldplay']);
      expect(saved.last, ['nirvana', 'radiohead', 'coldplay']);
    });

    test('loads persisted entries on first use', () async {
      final saved = <List<String>>[];
      final store = RecentSearchStore(
        load: () async => const ['old x', 'old y'],
        save: (items) async => saved.add(items),
      );

      await store.ensureLoaded();
      expect(store.items, ['old x', 'old y']);

      await store.add('new z');
      expect(store.items, ['new z', 'old x', 'old y']);
      expect(saved.last, ['new z', 'old x', 'old y']);
    });

    test('remove and clear persist their changes', () async {
      final saved = <List<String>>[];
      final store = RecentSearchStore(
        load: () async => const ['a', 'b', 'c'],
        save: (items) async => saved.add(items),
      );

      await store.remove('b');
      expect(store.items, ['a', 'c']);
      expect(saved.last, ['a', 'c']);

      await store.clear();
      expect(store.items, isEmpty);
      expect(saved.last, isEmpty);
    });

    test('survives a failing loader', () async {
      final store = RecentSearchStore(load: () async => throw Exception('db'));
      await store.ensureLoaded();
      expect(store.items, isEmpty);
    });
  });
}