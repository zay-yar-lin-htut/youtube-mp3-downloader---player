import 'package:flutter_test/flutter_test.dart';
import 'package:yt_local_music/player/time_format.dart';

void main() {
  group('formatDownloaded', () {
    test('formats a known timestamp as "Sep 9, 2026, 6:21 PM"', () {
      final epoch = DateTime(2026, 9, 9, 18, 21).millisecondsSinceEpoch;
      expect(formatDownloaded(epoch), 'Sep 9, 2026, 6:21 PM');
    });

    test('uses 12-hour time with leading-zero minutes', () {
      final epoch = DateTime(2026, 1, 5, 9, 5).millisecondsSinceEpoch;
      expect(formatDownloaded(epoch), 'Jan 5, 2026, 9:05 AM');
    });

    test('midnight and noon map to 12 on the 12-hour clock', () {
      final midnight = DateTime(2025, 12, 31, 0, 0).millisecondsSinceEpoch;
      expect(formatDownloaded(midnight), 'Dec 31, 2025, 12:00 AM');

      final noon = DateTime(2025, 6, 1, 12, 30).millisecondsSinceEpoch;
      expect(formatDownloaded(noon), 'Jun 1, 2025, 12:30 PM');
    });
  });
}