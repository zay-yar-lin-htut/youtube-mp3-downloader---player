/// Detection + validation helpers for YouTube URLs.
library;

final RegExp _bareId = RegExp(r'^[A-Za-z0-9_-]{11}$');

final RegExp _youtuBe = RegExp(
  r'^(?:https?://)?(?:www\.)?youtu\.be/([A-Za-z0-9_-]{11})(?:[?&#].*)?$',
);
final RegExp _watch = RegExp(
  r'^(?:https?://)?(?:www\.|music\.)?youtube\.com/watch\?(?:[^#\s]*)v=([A-Za-z0-9_-]{11})(?:&.*)?$',
);
final RegExp _shorts = RegExp(
  r'^(?:https?://)?(?:www\.|music\.)?youtube\.com/shorts/([A-Za-z0-9_-]{11})(?:[?&#].*)?$',
);
final RegExp _embed = RegExp(
  r'^(?:https?://)?(?:www\.|music\.)?youtube\.com/embed/([A-Za-z0-9_-]{11})(?:[?&#].*)?$',
);

/// Returns the 11-character YouTube video id embedded in [input], or null when
/// [input] is not a recognizable, valid YouTube URL. Arbitrary text is never
/// treated as a video id.
String? extractYouTubeVideoId(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return null;
  }
  for (final pattern in [_watch, _youtuBe, _shorts, _embed]) {
    final match = pattern.firstMatch(text);
    final id = match?.group(1);
    if (id != null && _bareId.hasMatch(id)) {
      return id;
    }
  }
  return null;
}

/// Whether [input] looks like a YouTube URL (rather than a keyword query).
bool isYouTubeUrl(String input) => extractYouTubeVideoId(input) != null;