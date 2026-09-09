import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yt_local_music/main.dart';
import 'package:yt_local_music/models/song.dart';
import 'package:yt_local_music/player/music_player_controller.dart';

import 'fakes/fake_audio_engine.dart';

Song _song(String id, {String? path}) => Song(
      id: id,
      title: 'Song $id',
      author: 'Artist',
      duration: '3:21',
      thumbnailUrl: '',
      localPath: path ?? '/tmp/$id.m4a',
    );

Widget _app(MusicPlayerController controller) {
  return MyApp(controller: controller);
}

void main() {
  testWidgets('App renders search, downloads and playlist navigation',
      (tester) async {
    final controller = MusicPlayerController(engine: FakeAudioEngine());
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Search'), findsWidgets);

    // Mini player is hidden while nothing is playing.
    expect(find.text('Song a'), findsNothing);

    await tester.tap(find.text('Playlist'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing downloaded yet'), findsOneWidget);
    // Back to Search.
    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);


  });

  testWidgets('Playing a song shows the mini player and opens Now Playing',
      (tester) async {
    final controller = MusicPlayerController(engine: FakeAudioEngine());
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
    await tester.pumpAndSettle();

    // Mini player surfaces the current track.
    expect(find.text('Song a'), findsOneWidget);

    // Tapping the mini player opens the full-screen page.
    await tester.tap(find.text('Song a'));
    await tester.pumpAndSettle();
    expect(find.text('Now Playing'), findsOneWidget);
    expect(find.text('Song a'), findsWidgets);

    // Collapse back.
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Now Playing'), findsNothing);

    await controller.stopAndClear();
    await tester.pumpAndSettle();
    expect(find.text('Song a'), findsNothing);


  });

  testWidgets('Auto-advances to next track as engine completes',
      (tester) async {
    final engine = FakeAudioEngine();
    final controller = MusicPlayerController(engine: engine);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    await controller.playLocalList([
      _song('a', path: '/tmp/a.m4a'),
      _song('b', path: '/tmp/b.m4a'),
    ]);
    await tester.pumpAndSettle();

    // move to next track through the engine completing
    engine.complete();
    await tester.pumpAndSettle();
    expect(controller.currentSong!.id, 'b');
    expect(find.text('Song b'), findsWidgets);


  });
}
