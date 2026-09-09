import 'dart:io';
import 'package:flutter/material.dart';
import '../models/song.dart';
import '../player/music_player_controller.dart';
import '../player/player_queue.dart';
import '../services/database_service.dart';
import '../services/download_manager.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/song_tile.dart';
import '../widgets/song_info_dialog.dart';

class PlaylistScreen extends StatefulWidget {
  final MusicPlayerController playerController;

  const PlaylistScreen({
    super.key,
    required this.playerController,
  });

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  List<Song> _songs = [];
  bool _isLoading = true;
  int _lastHistoryRevision = -1;

  @override
  void initState() {
    super.initState();
    _loadPlaylist();
    DownloadManager.instance.addListener(_onDownloadChanged);
  }

  @override
  void dispose() {
    DownloadManager.instance.removeListener(_onDownloadChanged);
    super.dispose();
  }

  void _onDownloadChanged() {
    final revision = DownloadManager.historyRevision;
    if (revision == _lastHistoryRevision) return;
    _lastHistoryRevision = revision;
    _loadPlaylist();
  }

  Future<void> _loadPlaylist() async {
    try {
      final songs = await DatabaseService.instance.getPlaylist();
      final (kept, removed) = await _validateFiles(songs);
      if (removed.isNotEmpty) {
        debugPrint('[Playlist] removed ${removed.length} stale entries: $removed');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Removed ${removed.length} song(s) with missing files',
              ),
            ),
          );
        }
      }
      if (mounted) {
        setState(() {
          _songs = kept;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[Playlist] failed to load playlist: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Drops entries whose local file is gone/empty (or path is blank) and
  /// cleans up any stale rows + empty files.
  Future<(List<Song>, List<String>)> _validateFiles(List<Song> songs) async {
    final kept = <Song>[];
    final removedIds = <String>[];
    for (final song in songs) {
      final path = song.localPath;
      if (path == null || path.isEmpty) {
        removedIds.add(song.id);
        await DatabaseService.instance.deleteSong(song.id);
        continue;
      }
      final parsed = Uri.tryParse(path);
      if (parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https')) {
        // Remote URL stored where a local path was expected.
        removedIds.add(song.id);
        await DatabaseService.instance.deleteSong(song.id);
        continue;
      }
      try {
        final file = File(path);
        if (!await file.exists()) {
          removedIds.add(song.id);
          await DatabaseService.instance.deleteSong(song.id);
          continue;
        }
        if (await file.length() == 0) {
          removedIds.add(song.id);
          await DatabaseService.instance.deleteSong(song.id);
          if (await file.exists()) {
            await file.delete();
          }
          continue;
        }
      } catch (_) {
        removedIds.add(song.id);
        await DatabaseService.instance.deleteSong(song.id);
        continue;
      }
      kept.add(song);
    }
    return (kept, removedIds);
  }

  void _playSong(Song song) {
    debugPrint('[Playlist] Play tapped for id=${song.id} '
        'localPath=${song.localPath}');
    final index = _songs.indexWhere((s) => s.id == song.id);
    widget.playerController.playLocalList(
      _songs,
      index: index < 0 ? 0 : index,
    );
  }

  void _addToQueue(Song song) {
    widget.playerController.addToQueue(song, source: PlaybackSource.local);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${song.title}" added to queue')),
    );
  }

  Future<void> _confirmDelete(Song song) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Song'),
        content: Text('Remove "${song.title}" from your device?\n'
            'The downloaded file will also be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final wasPlaying = widget.playerController.currentSong?.id == song.id;
    await widget.playerController.handleSongDeleted(song.id);

    try {
      if (song.localPath != null) {
        final file = File(song.localPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      await DatabaseService.instance.deleteSong(song.id);
      DownloadManager.instance.notifyHistoryChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete file: $e')),
        );
      }
    }

    if (mounted) {
      setState(() {
        _songs.removeWhere((s) => s.id == song.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasPlaying
                ? 'Deleted and stopped playback'
                : 'Deleted "${song.title}"',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListenableBuilder(
      listenable: widget.playerController,
      builder: (context, _) {
        final currentId = widget.playerController.currentSong?.id;
        if (_songs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.library_music_outlined,
                  size: 56,
                  color: AppColors.textMuted,
                ),
                SizedBox(height: AppSpacing.md),
                Text(
                  'Nothing downloaded yet',
                  style: AppTypography.caption,
                ),
                SizedBox(height: AppSpacing.xs),
                Text(
                  'Download songs from Search and they will appear here',
                  style: AppTypography.caption,
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _loadPlaylist,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  children: [
                    Text(
                      'My Library',
                      style: AppTypography.screenHeading,
                    ),
                    const Spacer(),
                    Text(
                      '${_songs.length} songs',
                      style: AppTypography.playlistUbuntu,
                    ),
                  ],
                ),
              ),
              ..._songs.map((song) {
                final isActive = song.id == currentId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: SongTile(
                    song: song,
                    isActive: isActive,
                    onTap: () => _playSong(song),
                    trailing: _TrailingMenu(
                      onPlay: () => _playSong(song),
                      onAddQueue: () => _addToQueue(song),
                      onInfo: () => SongInfoDialog.show(context, song),
                      onDelete: () => _confirmDelete(song),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _TrailingMenu extends StatelessWidget {
  const _TrailingMenu({
    required this.onPlay,
    required this.onAddQueue,
    required this.onInfo,
    required this.onDelete,
  });

  final VoidCallback onPlay;
  final VoidCallback onAddQueue;
  final VoidCallback onInfo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      color: AppColors.surfaceElevated,
      icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
      onSelected: (value) {
        switch (value) {
          case 'play':
            onPlay();
          case 'queue':
            onAddQueue();
          case 'info':
            onInfo();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'play', child: Text('Play')),
        PopupMenuItem(value: 'queue', child: Text('Add to queue')),
        PopupMenuItem(value: 'info', child: Text('File info')),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: AppColors.error)),
        ),
      ],
    );
  }
}