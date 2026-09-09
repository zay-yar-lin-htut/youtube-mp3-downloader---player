import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_local_music/models/song.dart';
import 'package:yt_local_music/player/player_queue.dart';

Song _song(String id) => Song(
      id: id,
      title: 'Title $id',
      author: 'Author',
      duration: '3:00',
      thumbnailUrl: '',
    );

QueueEntry _entry(String id, {PlaybackSource source = PlaybackSource.local}) =>
    QueueEntry(song: _song(id), source: source);

void main() {
  group('PlayerQueue', () {
    test('resetForPlayback sets first entry as current', () {
      final q = PlayerQueue();
      q.resetForPlayback([_entry('a'), _entry('b')]);
      expect(q.length, 2);
      expect(q.currentSong!.id, 'a');
      expect(q.cursor, 0);
    });

    test('insertAndPlay moves an existing song to front without duplicating', () {
      final q = PlayerQueue();
      q.resetForPlayback([_entry('a'), _entry('b'), _entry('c')]);
      q.advance(); // -> b
      q.insertAndPlay(_entry('b'));
      expect(q.entries.length, 3);
      expect(q.currentSong!.id, 'b');
      expect(q.cursor, 0);
    });

    test('next/previous move through active order', () {
      final q = PlayerQueue();
      q.resetForPlayback([_entry('a'), _entry('b'), _entry('c')]);
      expect(q.peekNext()!.song.id, 'b');
      q.advance();
      expect(q.currentSong!.id, 'b');
      q.advance();
      expect(q.currentSong!.id, 'c');
      expect(q.peekNext(wrapAtEnd: false), isNull);
      expect(q.peekNext(wrapAtEnd: true)!.song.id, 'a');
      expect(q.peekPrevious()!.song.id, 'b');
    });

    test('addToQueue appends to the end and skips duplicates', () {
      final q = PlayerQueue();
      q.resetForPlayback([_entry('a'), _entry('b')]);
      q.addToQueue(_entry('c', source: PlaybackSource.preview));
      expect(q.entries.length, 3);
      expect(q.activeOrder.last.song.id, 'c');
      expect(q.entries.map((e) => e.song.id), ['a', 'b', 'c']);
      q.addToQueue(_entry('a'));
      expect(q.entries.length, 3); // duplicate skipped
    });

    test('removeSong returns whether it removed the current track', () {
      final q = PlayerQueue();
      q.resetForPlayback([_entry('a'), _entry('b')]);
      final wasCurrent = q.removeSong('a');
      expect(wasCurrent, isTrue);
      expect(q.currentSong!.id, 'b');
      expect(q.removeSong('x'), isFalse);
    });

    test('removeAtActiveIndex slides cursor before removing', () {
      final q = PlayerQueue();
      q.resetForPlayback([_entry('a'), _entry('b'), _entry('c')]);
      q.advance(); // b (cursor 1)
      q.removeAtActiveIndex(0); // remove a
      expect(q.currentSong!.id, 'b');
      expect(q.cursor, 0);
    });

    test('clearUpcoming drops tracks after current from both structures', () {
      final q = PlayerQueue();
      q.resetForPlayback([_entry('a'), _entry('b'), _entry('c')]);
      q.clearUpcoming();
      expect(q.entries.map((e) => e.song.id), ['a']);
      expect(q.activeOrder.map((e) => e.song.id), ['a']);
    });

    test('enableShuffle pins current first and permutes the rest', () {
      final q = PlayerQueue(random: Random(7));
      q.resetForPlayback([_entry('a'), _entry('b'), _entry('c'), _entry('d')]);
      q.advance(); // b
      q.enableShuffle();
      expect(q.isShuffleEnabled, isTrue);
      expect(q.currentSong!.id, 'b');
      final ids = q.activeOrder.map((e) => e.song.id).toList();
      expect(ids.length, 4);
      expect(ids.first, 'b');
      expect(ids.sublist(1).toSet(), {'a', 'c', 'd'});
    });

    test('resetForPlayback with shuffle pins the tapped entry first', () {
      final q = PlayerQueue(random: Random(7));
      q.enableShuffle();
      q.resetForPlayback(
        [_entry('a'), _entry('b'), _entry('c'), _entry('d')],
        playIndex: 2,
      );
      expect(q.isShuffleEnabled, isTrue);
      expect(q.currentSong!.id, 'c', reason: 'tap target must play first');
      expect(q.cursor, 0);
      final ids = q.activeOrder.map((e) => e.song.id).toList();
      expect(ids.first, 'c');
      expect(ids.sublist(1).toSet(), {'a', 'b', 'd'});
    });

    test('disableShuffle restores canonical order and keeps position', () {
      final q = PlayerQueue(random: Random(7));
      q.resetForPlayback([_entry('a'), _entry('b'), _entry('c')]);
      q.advance(); // b
      q.enableShuffle();
      expect(q.activeOrder.map((e) => e.song.id),
          isNot(equals(['a', 'b', 'c'])));
      q.disableShuffle();
      expect(q.isShuffleEnabled, isFalse);
      expect(q.activeOrder.map((e) => e.song.id), ['a', 'b', 'c']);
      expect(q.currentSong!.id, 'b');
    });

    test('removeAll empties everything', () {
      final q = PlayerQueue();
      q.resetForPlayback([_entry('a')]);
      q.removeAll();
      expect(q.length, 0);
      expect(q.currentSong, isNull);
      expect(q.cursor, -1);
    });
  });
}