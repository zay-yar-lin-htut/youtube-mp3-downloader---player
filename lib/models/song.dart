class Song {
  final String id;
  final String title;
  final String author;
  final String duration;
  final String thumbnailUrl;
  final String? localPath;

  const Song({
    required this.id,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnailUrl,
    this.localPath,
  });

  Song copyWith({String? localPath}) {
    return Song(
      id: id,
      title: title,
      author: author,
      duration: duration,
      thumbnailUrl: thumbnailUrl,
      localPath: localPath ?? this.localPath,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'duration': duration,
      'thumbnailUrl': thumbnailUrl,
      'localPath': localPath,
    };
  }

  factory Song.fromMap(Map<String, dynamic> map) {
    return Song(
      id: map['id'] as String,
      title: map['title'] as String,
      author: map['author'] as String,
      duration: map['duration'] as String,
      thumbnailUrl: map['thumbnailUrl'] as String,
      localPath: map['localPath'] as String?,
    );
  }
}
