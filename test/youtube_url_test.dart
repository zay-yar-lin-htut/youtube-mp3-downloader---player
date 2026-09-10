import 'package:flutter_test/flutter_test.dart';
import 'package:yt_local_music/services/youtube_url.dart';

void main() {
  group('extractYouTubeVideoId', () {
    const id = 'dQw4w9WgXcQ';

    test('watch URLs with query params', () {
      expect(extractYouTubeVideoId('https://www.youtube.com/watch?v=$id'), id);
      expect(
        extractYouTubeVideoId('https://youtube.com/watch?v=$id&t=30s'),
        id,
      );
      expect(
        extractYouTubeVideoId(
          'https://www.youtube.com/watch?feature=share&v=$id&list=abc',
        ),
        id,
      );
    });

    test('short youtu.be links', () {
      expect(extractYouTubeVideoId('https://youtu.be/$id'), id);
      expect(extractYouTubeVideoId('https://youtu.be/$id?t=42'), id);
    });

    test('shorts and embed URLs', () {
      expect(
        extractYouTubeVideoId('https://youtube.com/shorts/$id'),
        id,
      );
      expect(
        extractYouTubeVideoId('https://www.youtube.com/embed/$id'),
        id,
      );
    });

    test('music.youtube.com hosts are recognized too', () {
      expect(
        extractYouTubeVideoId('https://music.youtube.com/watch?v=$id'),
        id,
      );
      expect(
        extractYouTubeVideoId('https://music.youtube.com/shorts/$id'),
        id,
      );
    });

    test('scheme-omitted watch URLs are handled', () {
      expect(
        extractYouTubeVideoId('www.youtube.com/watch?v=$id'),
        id,
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        extractYouTubeVideoId('  https://youtu.be/$id  '),
        id,
      );
    });

    test('rejects arbitrary text, query keywords and malformed ids', () {
      expect(extractYouTubeVideoId('dQw4w9WgXcQ'), isNull);
      expect(extractYouTubeVideoId('coldplay paradise'), isNull);
      expect(extractYouTubeVideoId('short'), isNull);
      expect(extractYouTubeVideoId('https://example.com/watch?v=$id'), isNull);
      expect(extractYouTubeVideoId('https://youtu.be/too-short'), isNull);
      expect(extractYouTubeVideoId('https://youtu.be/not!valid!id!'), isNull);
      expect(extractYouTubeVideoId(''), isNull);
    });
  });

  group('isYouTubeUrl', () {
    test('true for real YouTube URLs, false for keywords', () {
      expect(
        isYouTubeUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        isTrue,
      );
      expect(isYouTubeUrl('some song name'), isFalse);
    });
  });
}