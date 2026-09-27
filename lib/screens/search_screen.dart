import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../models/song.dart';
import '../player/music_player_controller.dart';
import '../services/youtube_service.dart';
import '../services/database_service.dart';
import '../services/download_manager.dart';
import '../services/search_suggestion_service.dart';
import '../services/update_service.dart';
import '../services/youtube_url.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/song_tile.dart';
import '../widgets/song_info_dialog.dart';
import '../widgets/search_field.dart';
import '../widgets/network_required_dialog.dart';
import 'search_overlay.dart';
import 'update_dialog.dart';

class SearchScreen extends StatefulWidget {
  final YouTubeService youtubeService;
  final MusicPlayerController playerController;

  /// Optional update engine. When provided it both gates Internet-dependent
  /// actions (search/preview/download) via [UpdateService.hasInternetConnection]
  /// and lazily triggers the app-update check after a successful online
  /// search. When null the network gate is skipped.
  final UpdateService? updateService;

  const SearchScreen({
    super.key,
    required this.youtubeService,
    required this.playerController,
    this.updateService,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  late final RecentSearchStore _recents;

  // Search results + pagination.
  List<Song> _results = [];
  VideoSearchPage? _page;
  bool _hasMore = false;
  String? _activeQuery;
  int _requestGeneration = 0;
  bool _isInitialLoading = false;
  bool _isResolvingUrl = false;
  String? _initialError;
  bool _isLoadingMore = false;
  String? _loadMoreError;

  bool _disposed = false;
  final Map<String, Song> _downloadedById = {};
  int _lastDownloadRevision = -1;

  @override
  void initState() {
    super.initState();
    _recents = RecentSearchStore.db();
    _loadDownloadedSongs();
    DownloadManager.instance.addListener(_onDownloadStateChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    DownloadManager.instance.removeListener(_onDownloadStateChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onDownloadStateChanged() {
    final revision = DownloadManager.historyRevision;
    if (revision == _lastDownloadRevision) return;
    _lastDownloadRevision = revision;
    _loadDownloadedSongs();
  }

  Future<void> _loadDownloadedSongs() async {
    try {
      final library = await DatabaseService.instance.getPlaylist();
      final history = await DatabaseService.instance.getDownloadHistory();
      final all = [...library, ...history];
      final downloaded = <String, Song>{};
      for (final song in all) {
        if (song.source != SongSource.downloaded || song.localPath == null) {
          continue;
        }
        final exists = await File(song.localPath!).exists();
        if (!exists) continue;
        downloaded[song.id] = song;
        if (song.videoId != null) downloaded[song.videoId!] = song;
      }
      if (mounted) {
        setState(
          () => _downloadedById
            ..clear()
            ..addAll(downloaded),
        );
      }
    } catch (_) {
      // Search remains usable when the local store is unavailable.
    }
  }

  Future<void> _openSearchOverlay() async {
    final query = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close search',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) => SearchOverlay(
        initialQuery: _controller.text,
        fetchSuggestions: widget.youtubeService.getSearchSuggestions,
        recents: _recents,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
    if (query == null || query.isEmpty || _disposed || !mounted) {
      return;
    }
    _submitSearch(query);
  }

  Future<void> _submitSearch([String? fixedQuery]) async {
    final query = (fixedQuery ?? _controller.text).trim();
    if (query.isEmpty) {
      return;
    }
    final online = await _ensureOnlineForAction(networkRequiredSearchMessage);
    if (!online || _disposed || !mounted) {
      return;
    }
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);

    final videoId = extractYouTubeVideoId(query);
    if (videoId == null) {
      await _recents.add(query);
      if (_disposed) {
        return;
      }
    }

    _activeQuery = query;
    final generation = ++_requestGeneration;
    setState(() {
      _results = const [];
      _page = null;
      _hasMore = false;
      _isInitialLoading = true;
      _isResolvingUrl = videoId != null;
      _initialError = null;
      _loadMoreError = null;
      _isLoadingMore = false;
    });

    try {
      if (videoId != null) {
        final song = await widget.youtubeService.getVideo(videoId);
        if (mounted && generation == _requestGeneration) {
          setState(() {
            _results = [song];
            _isInitialLoading = false;
            _isResolvingUrl = false;
          });
          unawaited(_loadDownloadedSongs());
        }
      } else {
        final page = await widget.youtubeService.searchVideos(query);
        if (mounted && generation == _requestGeneration) {
          setState(() {
            _results = List.of(page.songs);
            _page = page;
            _hasMore = true;
            _isInitialLoading = false;
          });
          unawaited(_loadDownloadedSongs());
        }
      }
    } catch (e) {
      debugPrint('[Search] search failed for "$query": $e');
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _isInitialLoading = false;
          _isResolvingUrl = false;
          _initialError = "Couldn't load search results.\nPlease try again.";
        });
      }
    }
    unawaited(_maybeCheckForUpdate());
  }

  /// Runs the app-update check in the background after an online action.
  /// Search results must never wait for the update API, and every update
  /// failure (offline, 4xx/5xx, timeout, malformed payload) is silently
  /// ignored by the update engine itself.
  Future<void> _maybeCheckForUpdate() {
    final service = widget.updateService;
    if (service == null) {
      return Future.value();
    }
    return runUpdateFlowIfNeeded(context, service: service);
  }

  /// Gates an Internet-dependent action. When the device is offline a styled
  /// "No Internet Connection" dialog is shown (operation-specific [message])
  /// and the action is aborted. Returns true when online (or when no update
  /// engine is configured, e.g. in tests that inject none).
  Future<bool> _ensureOnlineForAction(String message) async {
    final service = widget.updateService;
    if (service == null) {
      return true;
    }
    final online = await service.hasInternetConnection();
    if (!online && mounted) {
      await showNetworkRequiredDialog(context, message: message);
    }
    return online;
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isInitialLoading) {
      return;
    }
    final page = _page;
    final generation = _requestGeneration;
    if (page == null) {
      return;
    }
    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });
    try {
      final next = await widget.youtubeService.nextSearchPage(page);
      if (mounted && generation == _requestGeneration) {
        setState(() {
          if (next == null) {
            _hasMore = false;
          } else {
            _results = [..._results, ...next.songs];
            _page = next;
          }
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('[Search] pagination failed: $e');
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _isLoadingMore = false;
          _loadMoreError = "Couldn't load more results.";
        });
      }
    }
  }

  Future<void> _previewSong(Song song) async {
    final online = await _ensureOnlineForAction(networkRequiredPreviewMessage);
    if (!online || _disposed || !mounted) {
      return;
    }
    widget.playerController.playPreview(song);
  }

  Future<void> _downloadSong(Song song) async {
    final online = await _ensureOnlineForAction(networkRequiredDownloadMessage);
    if (!online || _disposed || !mounted) {
      return;
    }
    debugPrint('[Search] Download requested id=${song.id} title=${song.title}');
    await DownloadManager.instance.updateProgress(song.id, song.title, null);
    try {
      final localPath = await widget.youtubeService.downloadAudio(song);
      debugPrint('[Search] downloadAudio returned localPath=$localPath');
      final savedSong = song.copyWith(
        videoId: song.videoId ?? song.id,
        localPath: localPath,
        downloadedAt: DateTime.now().millisecondsSinceEpoch,
        source: SongSource.downloaded,
      );
      await DatabaseService.instance.insertSong(savedSong);
      await DatabaseService.instance.insertHistory(savedSong);
      if (mounted) {
        setState(() {
          _downloadedById[savedSong.id] = savedSong;
          if (savedSong.videoId != null) {
            _downloadedById[savedSong.videoId!] = savedSong;
          }
        });
      }
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
        final message = switch (e) {
          DownloadRateLimitedException() ||
          DownloadUnavailableException() => '$e',
          _ => 'Download failed: $e',
        };
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
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
          SearchLauncherBar(
            key: const Key('search_launcher'),
            controller: _controller,
            isLoading: _isInitialLoading || _isResolvingUrl,
            onTap: _openSearchOverlay,
            onSearchPressed: _openSearchOverlay,
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.playerController,
              builder: (context, _) => _buildResultsArea(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsArea(BuildContext context) {
    if (_isInitialLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            Text(
              _isResolvingUrl
                  ? 'Resolving YouTube video…'
                  : 'Loading search results…',
              style: AppTypography.caption,
            ),
          ],
        ),
      );
    }

    if (_initialError != null) {
      return _MessagePane(
        icon: Icons.cloud_off_rounded,
        title: _initialError!,
        actionLabel: 'Retry',
        onAction: () => _submitSearch(),
      );
    }

    if (_results.isEmpty) {
      return _activeQuery == null
          ? const _MessagePane(
              icon: Icons.library_music_outlined,
              title: 'Search for music on YouTube',
            )
          : _MessagePane(
              icon: Icons.search_off_rounded,
              title: 'No results found for "$_activeQuery"',
              actionLabel: 'Try again',
              onAction: () => _submitSearch(),
            );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 400) {
          _loadMore();
        }
        return false;
      },
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _results.length + 1,
        itemBuilder: (context, index) {
          if (index == _results.length) {
            return _buildFooter(context);
          }
          final song = _results[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: SongTile(
              song: song,
              onTap: () => _previewSong(song),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'More',
                    visualDensity: kSongActionDensity,
                    padding: kSongActionPadding,
                    constraints: kSongActionConstraints,
                    icon: const Icon(
                      Icons.more_vert,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => SongInfoDialog.show(context, song),
                  ),
                  _PreviewButton(
                    song: song,
                    controller: widget.playerController,
                    onPreview: () => _previewSong(song),
                  ),
                  _DownloadButton(
                    song: song,
                    onDownload: _downloadSong,
                    isDownloaded:
                        _downloadedById.containsKey(song.id) ||
                        (song.videoId != null &&
                            _downloadedById.containsKey(song.videoId)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    if (_loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          children: [
            Text(_loadMoreError!, style: AppTypography.caption),
            TextButton(
              onPressed: () {
                setState(() {
                  _loadMoreError = null;
                  _hasMore = true;
                });
                _loadMore();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: Text('End of results', style: AppTypography.caption),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Preview button reflecting exactly one active preview: spinner while THIS
/// song resolves/loads, play/pause while THIS song is the current track.
class _PreviewButton extends StatelessWidget {
  const _PreviewButton({
    required this.song,
    required this.controller,
    required this.onPreview,
  });

  final Song song;
  final MusicPlayerController controller;

  /// Runs an Internet-gated preview start (a current-track toggle pause is a
  /// local playback control and never goes through this callback).
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final isLoading = controller.previewLoadingSongId == song.id;
    final isCurrent = controller.currentSong?.id == song.id;
    final playing = controller.isPlaying && isCurrent;
    return IconButton(
      tooltip: isLoading ? 'Loading preview…' : 'Preview',
      visualDensity: kSongActionDensity,
      padding: kSongActionPadding,
      constraints: kSongActionConstraints,
      icon: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              playing ? Icons.pause_circle_outline : Icons.play_circle_outline,
              color: isCurrent ? AppColors.primary : AppColors.textSecondary,
            ),
      onPressed: isLoading
          ? null
          : isCurrent
          ? controller.togglePause
          : onPreview,
    );
  }
}

/// Download button that surfaces REAL byte progress from the downloader.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({
    required this.song,
    required this.onDownload,
    required this.isDownloaded,
  });

  final Song song;
  final ValueChanged<Song> onDownload;
  final bool isDownloaded;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadManager.instance,
      builder: (context, _) {
        final task = DownloadManager.instance.activeDownloads[song.id];
        if (isDownloaded && (task == null || task.isCompleted)) {
          return const Tooltip(
            message: 'Downloaded',
            child: Padding(
              padding: EdgeInsets.all(9),
              child: Icon(
                Icons.check_circle_rounded,
                size: 22,
                color: AppColors.success,
              ),
            ),
          );
        }
        if (task == null) {
          return IconButton(
            tooltip: 'Download',
            visualDensity: kSongActionDensity,
            padding: kSongActionPadding,
            constraints: kSongActionConstraints,
            icon: const Icon(Icons.download_rounded),
            onPressed: () => onDownload(song),
          );
        }
        if (task.isCompleted) {
          return const Padding(
            padding: EdgeInsets.all(9),
            child: Icon(
              Icons.check_circle_outline_rounded,
              size: 22,
              color: AppColors.success,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(9),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              value: task.progress,
              strokeWidth: 2.5,
            ),
          ),
        );
      },
    );
  }
}

class _MessagePane extends StatelessWidget {
  const _MessagePane({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
