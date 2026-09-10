/// Canonical YouTube watch URL for a video id.
String youtubeWatchUrl(String videoId) =>
    'https://www.youtube.com/watch?v=$videoId';

/// Where a song came from / how it is stored.
///
/// - [youtube]: a YouTube result with no local file (search / preview only).
/// - [downloaded]: downloaded by FreeVibe; has an owned local file.
/// - [device]: discovered from the device's own music collection; the local
///   URI/path references the user's original file (never copied into app
///   storage, never deleted by FreeVibe).
enum SongSource { youtube, downloaded, device }

SongSource _sourceFromName(Object? value) {
  if (value is SongSource) return value;
  return SongSource.values.firstWhere(
    (s) => s.name == value,
    orElse: () => SongSource.youtube,
  );
}

class Song {
  /// Primary key. The YouTube video id for YouTube/downloaded songs; a stable
  /// synthetic id for device-only songs.
  final String id;

  /// YouTube video id when the song originates from YouTube. Null for
  /// device-only songs.
  final String? videoId;

  final String title;
  final String author;
  final String duration;
  final String thumbnailUrl;

  /// Absolute local file path (FreeVibe downloads) or an Android
  /// content:// URI / absolute path for device songs. Null = not local.
  final String? localPath;

  /// Canonical YouTube watch URL. Derived from [videoId]/[id] when not
  /// persisted.
  final String? youtubeUrl;

  /// Epoch milliseconds when the song was added to the library/playlist.
  final int? createdAt;

  /// Epoch milliseconds at download time (persisted for new downloads).
  final int? downloadedAt;

  final SongSource source;

  const Song({
    required this.id,
    this.videoId,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnailUrl,
    this.localPath,
    this.youtubeUrl,
    this.createdAt,
    this.downloadedAt,
    this.source = SongSource.youtube,
  });

  String get canonicalYoutubeUrl =>
      youtubeUrl ?? (videoId != null ? youtubeWatchUrl(videoId!) : '');

  /// A normalized identity used for de-duplication. Falls back to the primary
  /// key (YouTube video id) when no local uri/path is available.
  String get localIdentity => normalizeLocalIdentity(localPath) ?? id;

  Song copyWith({
    String? videoId,
    String? title,
    String? author,
    String? localPath,
    String? youtubeUrl,
    int? createdAt,
    int? downloadedAt,
    SongSource? source,
  }) {
    return Song(
      id: id,
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      author: author ?? this.author,
      duration: duration,
      thumbnailUrl: thumbnailUrl,
      localPath: localPath ?? this.localPath,
      youtubeUrl: youtubeUrl ?? this.youtubeUrl,
      createdAt: createdAt ?? this.createdAt,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'videoId': videoId,
      'title': title,
      'author': author,
      'duration': duration,
      'thumbnailUrl': thumbnailUrl,
      'localPath': localPath,
      'youtubeUrl': youtubeUrl,
      'createdAt': createdAt,
      'downloadedAt': downloadedAt,
      'source': source.name,
    };
  }

  factory Song.fromMap(Map<String, dynamic> map) {
    return Song(
      id: map['id'] as String,
      videoId: map['videoId'] as String?,
      title: map['title'] as String,
      author: map['author'] as String,
      duration: map['duration'] as String,
      thumbnailUrl: map['thumbnailUrl'] as String,
      localPath: map['localPath'] as String?,
      youtubeUrl: map['youtubeUrl'] as String?,
      createdAt: map['createdAt'] as int?,
      downloadedAt: map['downloadedAt'] as int?,
      source: _sourceFromName(map['source']),
    );
  }
}

/// Normalizes a local uri/path for identity comparison.
///
/// - `content://` URIs are kept as-is (scheme + last encoded segment).
/// - Absolute file paths are canonicalized (resolves `..` segments) on the
///   current platform.
/// Returns null when [value] is blank.
String? normalizeLocalIdentity(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null) {
    return null;
  }
  if (uri.scheme == 'content') {
    final segments = uri.pathSegments;
    return 'content://${uri.authority}/${segments.isEmpty ? uri.path : segments.last}';
  }
  return value.replaceAll('\\', '/');
}