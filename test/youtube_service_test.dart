import 'package:flutter_test/flutter_test.dart';
import 'package:http_parser/http_parser.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'package:yt_local_music/services/youtube_service.dart';

AudioOnlyStreamInfo _stream({
  required int tag,
  required String container,
  required int bitsPerSecond,
}) {
  return AudioOnlyStreamInfo(
    VideoId('dQw4w9WgXcQ'),
    tag,
    Uri.parse('https://example.com/stream$tag'),
    StreamContainer.parse(container),
    FileSize(1024),
    Bitrate(bitsPerSecond),
    container == 'mp4' ? 'mp4a.40.2' : 'opus',
    'audio only',
    const [],
    MediaType('audio', 'mp4'),
    null,
  );
}

void main() {
  final service = YouTubeService();

  group('selectBestAudioStream', () {
    test('prefers m4a (mp4 container) over higher-bitrate webm', () {
      final webmHigh = _stream(tag: 1, container: 'webm', bitsPerSecond: 200);
      final m4aLower = _stream(tag: 2, container: 'mp4', bitsPerSecond: 100);

      final result = service.selectBestAudioStream([webmHigh, m4aLower]);
      expect(result.container.name, 'mp4');
      expect(result.tag, 2);
    });

    test('picks highest bitrate among m4a streams', () {
      final m4aLow = _stream(tag: 1, container: 'mp4', bitsPerSecond: 50);
      final m4aHigh = _stream(tag: 2, container: 'mp4', bitsPerSecond: 250);

      final result = service.selectBestAudioStream([m4aLow, m4aHigh]);
      expect(result.container.name, 'mp4');
      expect(result.tag, 2);
    });

    test('falls back to webm when no m4a exists', () {
      final webm = _stream(tag: 5, container: 'webm', bitsPerSecond: 160);

      final result = service.selectBestAudioStream([webm]);
      expect(result.container.name, 'webm');
      expect(result.tag, 5);
    });
  });
}
