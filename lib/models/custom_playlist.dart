/// A user-created playlist stored in SQLite. Membership lives in a separate
/// table keyed by the stable `song.id`, so songs can belong to many playlists
/// without duplicating any files.
class CustomPlaylist {
  const CustomPlaylist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.songCount = 0,
  });

  final String id;
  final String name;
  final int createdAt;
  final int updatedAt;
  final int songCount;

  CustomPlaylist copyWith({String? name, int? updatedAt, int? songCount}) {
    return CustomPlaylist(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      songCount: songCount ?? this.songCount,
    );
  }

  factory CustomPlaylist.fromMap(Map<String, Object?> map) {
    return CustomPlaylist(
      id: map['id'] as String,
      name: map['name'] as String,
      createdAt: map['createdAt'] as int,
      updatedAt: map['updatedAt'] as int,
    );
  }
}