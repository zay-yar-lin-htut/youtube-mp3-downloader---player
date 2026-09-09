import 'package:flutter/material.dart';
import '../models/song.dart';
import '../player/music_player_controller.dart';
import '../services/youtube_service.dart';
import '../services/database_service.dart';
import '../services/download_manager.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/song_tile.dart';
import '../widgets/song_info_dialog.dart';

class SearchScreen extends StatefulWidget {
  final YouTubeService youtubeService;
  final MusicPlayerController playerController;

  const SearchScreen({
    super.key,
    required this.youtubeService,
    required this.playerController,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  List<Song> _results = [];
  bool _isLoading = false;
  final Set<String> _previewingIds = {};
  final Set<String> _downloadingIds = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _results = [];
    });

    try {
      final results = await widget.youtubeService.searchVideos(query);
      if (mounted) {
        setState(() {
          _results = results;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _previewSong(Song song) async {
    setState(() => _previewingIds.add(song.id));
    await widget.playerController.playPreview(song);
    if (mounted) {
      setState(() => _previewingIds.remove(song.id));
    }
  }

  Future<void> _downloadSong(Song song) async {
    debugPrint('[Search] Download requested id=${song.id} title=${song.title}');
    setState(() => _downloadingIds.add(song.id));
    try {
      final localPath = await widget.youtubeService.downloadAudio(song);
      debugPrint('[Search] downloadAudio returned localPath=$localPath');
      final savedSong = song.copyWith(localPath: localPath);
      await DatabaseService.instance.insertSong(savedSong);
      DownloadManager.instance.removeFailure(song.id);
      DownloadManager.instance.notifyHistoryChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Downloaded successfully')),
        );
      }
    } catch (e) {
      DownloadManager.instance.recordFailure(song.id, song.title);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _downloadingIds.remove(song.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search YouTube music…',
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: _results.isEmpty
                ? (_isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.library_music_outlined,
                          size: 56,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const Text(
                          'Search for music on YouTube',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  )
                )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final song = _results[index];
                      final isPreviewing = _previewingIds.contains(song.id);
                      final isDownloading = _downloadingIds.contains(song.id);
                      final task = DownloadManager.instance.activeDownloads[song.id];
                      final hasProgress = task != null && task.progress != null;
                      return SongTile(
                        song: song,
                        onTap: () => _previewSong(song),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'More',
                              icon: const Icon(
                                Icons.more_vert,
                                color: AppColors.textSecondary,
                              ),
                              onPressed: () => SongInfoDialog.show(context, song),
                            ),
                            IconButton(
                              tooltip: 'Preview',
                              icon: isPreviewing
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.play_circle_outline),
                              onPressed: isPreviewing ? null : () => _previewSong(song),
                            ),
                            IconButton(
                              tooltip: 'Download',
                              icon: isDownloading
                                  ? (hasProgress
                                      ? Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: CircularProgressIndicator(
                                            value: task.progress,
                                            strokeWidth: 3,
                                          ),
                                        )
                                      : const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ))
                                  : const Icon(Icons.download_rounded),
                              onPressed:
                                  isDownloading ? null : () => _downloadSong(song),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}