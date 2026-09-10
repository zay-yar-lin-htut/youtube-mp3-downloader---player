import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/custom_playlist.dart';
import '../models/song.dart';
import '../player/music_player_controller.dart';
import '../services/database_service.dart';
import '../services/device_music_service.dart';
import '../services/download_manager.dart';
import '../services/custom_playlist_service.dart';
import '../services/playlist_repository.dart';
import '../services/song_rename_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/song_tile.dart';
import '../widgets/song_info_dialog.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Which built-in set of songs the detail view is showing.
enum PlaylistSystemView { all, downloaded, onDevice }

/// Sort order for any song list.
enum PlaylistSort { recentlyAdded, title, artist, duration }

// ---------------------------------------------------------------------------
// Root screen: System views + My Playlists
// ---------------------------------------------------------------------------

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({
    super.key,
    required this.playerController,
    this.repository,
  });

  final MusicPlayerController playerController;

  /// Injectable for tests; defaults to the SQLite + MediaStore repository.
  final PlaylistRepository? repository;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late final PlaylistRepository _repository;
  late final CustomPlaylistService _playlists;

  /// Total song counts for the system views, populated from a fresh snapshot.
  int _allCount = 0;
  int _downloadedCount = 0;
  int _onDeviceCount = 0;
  bool _isLoading = true;

  List<CustomPlaylist> _customPlaylists = [];
  int _lastHistoryRevision = -1;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ??
        (Platform.isAndroid
            ? PlaylistRepository(device: OnDeviceDeviceMusicService())
            : PlaylistRepository());
    _playlists = CustomPlaylistService();
    _load();
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
    _load();
  }

  Future<void> _load() async {
    PlaylistSnapshot snapshot;
    try {
      snapshot = await _repository.load(rescanDevice: false);
    } catch (e) {
      debugPrint('[Playlist] failed to load: $e');
      snapshot = const PlaylistSnapshot(
        songs: [],
        permission: DevicePermissionState.unknown,
        scanned: false,
        removedMissingDownloads: [],
      );
    }
    var customs = <CustomPlaylist>[];
    try {
      customs = await _playlists.listAll();
    } catch (e) {
      debugPrint('[Playlist] custom playlists unavailable: $e');
    }
    if (!mounted) return;

    if (snapshot.removedMissingDownloads.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Removed ${snapshot.removedMissingDownloads.length} '
            'download(s) whose file was missing',
          ),
        ),
      );
    }
    setState(() {
      _allCount = snapshot.songs.length;
      _downloadedCount =
          snapshot.songs.where((s) => s.source == SongSource.downloaded).length;
      _onDeviceCount =
          snapshot.songs.where((s) => s.source == SongSource.device).length;
      _customPlaylists = customs;
      _isLoading = false;
    });
  }

  void _openDetail({PlaylistSystemView? systemView, String? playlistId, String? playlistName}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(
          playerController: widget.playerController,
          repository: widget.repository ?? _repository,
          systemView: systemView,
          playlistId: playlistId,
          playlistName: playlistName ?? '',
        ),
      ),
    ).then((_) => _load());
  }

  Future<void> _showNewPlaylistDialog() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _NewPlaylistDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    final error = _playlists.validateName(name);
    if (error != null) {
      _showSnack(error);
      return;
    }
    final playlist = await _playlists.create(name);
    if (!mounted) return;
    _showSnack('Created "${playlist.name}"');
    await _load();
    _openDetail(playlistId: playlist.id, playlistName: playlist.name);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm,
        ),
        children: [
          Text('Playlists', style: AppTypography.screenHeading),
          const SizedBox(height: AppSpacing.lg),

          // ── System views ──────────────────────────────────────────
          _ViewTile(
            icon: Icons.library_music_outlined,
            label: 'All',
            count: _allCount,
            onTap: () => _openDetail(systemView: PlaylistSystemView.all),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ViewTile(
            icon: Icons.download_outlined,
            label: 'Downloaded',
            count: _downloadedCount,
            onTap: () => _openDetail(systemView: PlaylistSystemView.downloaded),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ViewTile(
            icon: Icons.smartphone_rounded,
            label: 'On device',
            count: _onDeviceCount,
            onTap: () => _openDetail(systemView: PlaylistSystemView.onDevice),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Custom playlists ──────────────────────────────────────
          if (_customPlaylists.isNotEmpty) ...[
            Text('My Playlists', style: AppTypography.caption),
            const SizedBox(height: AppSpacing.sm),
            ..._customPlaylists.map((pl) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: _CustomPlaylistTile(
                    playlist: pl,
                    onTap: () => _openDetail(
                      playlistId: pl.id,
                      playlistName: pl.name,
                    ),
                    onRename: () => _renamePlaylist(pl),
                    onDelete: () => _deletePlaylist(pl),
                  ),
                )),
            const SizedBox(height: AppSpacing.xs),
          ],

          // ── New playlist button ───────────────────────────────────
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: AppColors.primary),
            title: const Text(
              'New playlist',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            onTap: _showNewPlaylistDialog,
          ),
        ],
      ),
    );
  }

  Future<void> _renamePlaylist(CustomPlaylist pl) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenamePlaylistDialog(initialName: pl.name),
    );
    if (name == null || name.trim().isEmpty || name == pl.name) return;
    final error = _playlists.validateName(name);
    if (error != null) {
      _showSnack(error);
      return;
    }
    await _playlists.rename(pl.id, name);
    await _load();
  }

  Future<void> _deletePlaylist(CustomPlaylist pl) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete playlist'),
        content: Text(
          'Delete "${pl.name}"?\n'
          'Songs in your library will NOT be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _playlists.delete(pl.id);
    await _load();
  }
}

// ---------------------------------------------------------------------------
// Detail screen (system view OR custom playlist)
// ---------------------------------------------------------------------------

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.playerController,
    required this.repository,
    this.systemView,
    this.playlistId,
    this.playlistName = '',
  });

  final MusicPlayerController playerController;
  final PlaylistRepository repository;
  final PlaylistSystemView? systemView;
  final String? playlistId;
  final String playlistName;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen>
    with WidgetsBindingObserver {
  late final CustomPlaylistService _playlists;
  late final SongRenameService _renameService;

  PlaylistSort _sort = PlaylistSort.recentlyAdded;
  DevicePermissionState _permission = DevicePermissionState.unknown;
  bool _isLoading = true;
  int _lastHistoryRevision = -1;
  late PlaylistSystemView _currentSystemView;

  // System-view mode data
  List<Song> _allSongs = [];

  // Custom-playlist mode data
  List<Song> _playlistSongs = [];
  String _playlistName = '';

  bool get _isSystemView => widget.systemView != null;

  PlaylistSystemView get _systemView => _currentSystemView;

  List<Song> get _rawSongs =>
      _isSystemView ? _allSongs : _playlistSongs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentSystemView = widget.systemView ?? PlaylistSystemView.all;
    _playlists = CustomPlaylistService();
    _renameService = SongRenameService();
    _playlistName = widget.playlistName;
    _load();
    DownloadManager.instance.addListener(_onDownloadChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DownloadManager.instance.removeListener(_onDownloadChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check the media permission and rescan when returning from the OS
    // settings app (e.g. after permanently-denied -> grant), without needing
    // an app restart.
    if (state == AppLifecycleState.resumed &&
        _isSystemView &&
        _permission != DevicePermissionState.granted) {
      _load();
    }
  }

  void _onDownloadChanged() {
    final revision = DownloadManager.historyRevision;
    if (revision == _lastHistoryRevision) return;
    _lastHistoryRevision = revision;
    _load();
  }

  Future<void> _load() async {
    if (_isSystemView) {
      PlaylistSnapshot snapshot;
      try {
        snapshot = await widget.repository.load(
          rescanDevice: _systemView == PlaylistSystemView.onDevice,
        );
      } catch (e) {
        snapshot = const PlaylistSnapshot(
          songs: [],
          permission: DevicePermissionState.unknown,
          scanned: false,
          removedMissingDownloads: [],
        );
      }
      if (!mounted) return;
      setState(() {
        _allSongs = snapshot.songs;
        _permission = snapshot.permission;
        _isLoading = false;
      });
    } else {
      final songs = await _playlists.songsFor(widget.playlistId!);
      final pl = await _playlists.find(widget.playlistId!);
      if (!mounted) return;
      setState(() {
        _playlistSongs = songs;
        _playlistName = pl?.name ?? _playlistName;
        _isLoading = false;
      });
    }
  }

  void _switchSystemView(PlaylistSystemView view) {
    if (_systemView == view) return;
    setState(() {
      _currentSystemView = view;
      _isLoading = true;
    });
    _load();
  }

  Future<void> _requestDevicePermission() async {
    final state = await widget.repository.requestPermission();
    if (!mounted) return;
    setState(() => _permission = state);
    if (state == DevicePermissionState.granted) await _load();
  }

  List<Song> _visibleSongs() {
    final filtered = _isSystemView
        ? switch (_systemView) {
            PlaylistSystemView.all => _rawSongs,
            PlaylistSystemView.downloaded =>
              _rawSongs.where((s) => s.source == SongSource.downloaded).toList(),
            PlaylistSystemView.onDevice =>
              _rawSongs.where((s) => s.source == SongSource.device).toList(),
          }
        : List.of(_rawSongs);

    final list = List<Song>.of(filtered);
    switch (_sort) {
      case PlaylistSort.recentlyAdded:
        list.sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
      case PlaylistSort.title:
        list.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case PlaylistSort.artist:
        list.sort(
            (a, b) => a.author.toLowerCase().compareTo(b.author.toLowerCase()));
      case PlaylistSort.duration:
        list.sort(
            (a, b) => _durationSeconds(a).compareTo(_durationSeconds(b)));
    }
    return list;
  }

  int _durationSeconds(Song song) {
    final parts = song.duration.split(':').reversed.toList();
    if (parts.isEmpty) return 0;
    var seconds = 0;
    var multiplier = 1;
    for (final part in parts) {
      seconds += (int.tryParse(part) ?? 0) * multiplier;
      multiplier *= 60;
    }
    return seconds;
  }

  String get _appBarTitle {
    if (!_isSystemView) return _playlistName;
    return switch (_systemView) {
      PlaylistSystemView.all => 'All',
      PlaylistSystemView.downloaded => 'Downloaded',
      PlaylistSystemView.onDevice => 'On device',
    };
  }

  void _playSong(Song song) {
    final visible = _visibleSongs();
    final index = visible.indexWhere((s) => s.id == song.id);
    widget.playerController.playSongList(
      visible,
      index: index < 0 ? 0 : index,
      contextName: _appBarTitle,
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _renameSong(Song song) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameSongDialog(initialTitle: song.title),
    );
    if (name == null || name.trim().isEmpty || name == song.title) return;
    final result = await _renameService.rename(song, name);
    if (!mounted) return;
    if (result.ok) {
      _showSnack('Renamed to "${result.song!.title}"');
      widget.playerController.updateSong(result.song!);
      await _load();
    } else {
      _showSnack(result.error ?? 'Rename failed');
    }
  }

  Future<void> _removeSongFromCustomPlaylist(Song song) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from playlist'),
        content: Text(
          'Remove "${song.title}" from "$_playlistName"?\n'
          'The song will stay in your library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _playlists.removeSong(widget.playlistId!, song.id);
    await _load();
  }

  Future<void> _confirmDeleteDownload(Song song) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Download'),
        content: Text(
          'Remove "${song.title}" from your device?\n'
          'The downloaded file will also be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final wasPlaying =
        widget.playerController.currentSong?.id == song.id;
    await widget.playerController.handleSongDeleted(song.id);
    try {
      if (song.localPath != null) {
        final file = File(song.localPath!);
        if (await file.exists()) await file.delete();
      }
      await DatabaseService.instance.deleteSong(song.id);
      DownloadManager.instance.notifyHistoryChanged();
    } catch (e) {
      _showSnack('Failed to delete file: $e');
      return;
    }
    _showSnack(wasPlaying ? 'Deleted and stopped playback' : 'Deleted');
    await _load();
  }

  Future<void> _confirmRemoveDevice(Song song) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from Playlist'),
        content: Text(
          'Remove "${song.title}" from your playlist?\n'
          'Your original device file will NOT be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.playerController.handleSongDeleted(song.id);
    await DatabaseService.instance.deleteSong(song.id);
    DownloadManager.instance.notifyHistoryChanged();
    _showSnack('Removed from playlist');
    await _load();
  }

  Future<void> _shareAudioFile(Song song) async {
    final path = song.localPath;
    if (path == null) {
      _showSnack('This song has no local audio file to share');
      return;
    }
    try {
      final file = File(path);
      if (!await file.exists()) {
        _showSnack('The audio file is missing on disk');
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          subject: '${song.title} - ${song.author}',
          title: 'Share "${song.title}"',
        ),
      );
    } catch (e) {
      debugPrint('[Playlist] share audio failed: $e');
      _showSnack('Could not share the audio file');
    }
  }

  void _showFilePath(Song song) {
    final path = song.localPath;
    if (path == null) {
      _showSnack('This song has no local file');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('File path'),
        content: SelectableText(path, style: AppTypography.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: path));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Path copied to clipboard')),
              );
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  void _showAddToPlaylist(Song song) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => _AddToPlaylistSheet(
        song: song,
        playlists: _playlists,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(_appBarTitle, style: AppTypography.appBarTitle),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_appBarTitle, style: AppTypography.appBarTitle),
        actions: [
          if (_isSystemView) ...[
            PopupMenuButton<PlaylistSystemView>(
              tooltip: 'Filter',
              color: AppColors.surfaceElevated,
              icon: const Icon(
                  Icons.filter_list, color: AppColors.textSecondary),
              onSelected: _switchSystemView,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: PlaylistSystemView.all,
                  child: Text('All music'),
                ),
                PopupMenuItem(
                  value: PlaylistSystemView.downloaded,
                  child: Text('Downloaded'),
                ),
                PopupMenuItem(
                  value: PlaylistSystemView.onDevice,
                  child: Text('On device'),
                ),
              ],
            ),
            PopupMenuButton<PlaylistSort>(
              tooltip: 'Sort',
              color: AppColors.surfaceElevated,
              icon: const Icon(Icons.sort_rounded, color: AppColors.textSecondary),
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: PlaylistSort.recentlyAdded,
                    child: Text('Recently added')),
                PopupMenuItem(value: PlaylistSort.title, child: Text('Title')),
                PopupMenuItem(value: PlaylistSort.artist, child: Text('Artist')),
                PopupMenuItem(
                    value: PlaylistSort.duration, child: Text('Duration')),
              ],
            ),
          ]
          else
            PopupMenuButton<String>(
              tooltip: 'Sort',
              color: AppColors.surfaceElevated,
              icon: const Icon(Icons.sort_rounded, color: AppColors.textSecondary),
              onSelected: (v) {
                switch (v) {
                  case 'sort_added':
                    setState(() => _sort = PlaylistSort.recentlyAdded);
                  case 'sort_title':
                    setState(() => _sort = PlaylistSort.title);
                  case 'sort_artist':
                    setState(() => _sort = PlaylistSort.artist);
                  case 'sort_duration':
                    setState(() => _sort = PlaylistSort.duration);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'sort_added', child: Text('Recently added')),
                PopupMenuItem(value: 'sort_title', child: Text('Title')),
                PopupMenuItem(value: 'sort_artist', child: Text('Artist')),
                PopupMenuItem(value: 'sort_duration', child: Text('Duration')),
              ],
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.playerController,
        builder: (context, _) {
          final currentId = widget.playerController.currentSong?.id;
          final visible = _visibleSongs();

          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm,
              ),
              children: [
                // Count header
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: AppSpacing.sm,
                    top: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${visible.length} ${visible.length == 1 ? 'song' : 'songs'}',
                        style: AppTypography.playlistUbuntu,
                      ),
                    ],
                  ),
                ),

                // Permission pane (system views only)
                if (_isSystemView &&
                    _systemView == PlaylistSystemView.onDevice &&
                    _permission != DevicePermissionState.granted)
                  _DevicePermissionPane(
                    permission: _permission,
                    onAllowAccess: _requestDevicePermission,
                    onOpenSettings: () =>
                        widget.repository.openAppSettings(),
                  )
                else if (visible.isEmpty)
                  _EmptyPane(filter: _systemView)
                else
                  ...visible.map((song) {
                    final isActive = song.id == currentId;
                    final isDownload =
                        song.source == SongSource.downloaded;
                    final isDevice =
                        song.source == SongSource.device;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: SongTile(
                        song: song,
                        isActive: isActive,
                        badge: isDownload
                            ? 'Downloaded'
                            : isDevice
                                ? 'On device'
                                : null,
                        onTap: () => _playSong(song),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: isActive &&
                                      widget.playerController.isPlaying
                                  ? 'Pause'
                                  : 'Play',
                              icon: Icon(
                                isActive &&
                                        widget.playerController.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: AppColors.textPrimary,
                              ),
                              onPressed: () => _playSong(song),
                            ),
                            _SongMenu(
                              song: song,
                              onPlay: () => _playSong(song),
                              onAddToPlaylist: () =>
                                  _showAddToPlaylist(song),
                              onRename: isDownload
                                  ? () => _renameSong(song)
                                  : null,
                              onInfo: () =>
                                  SongInfoDialog.show(context, song),
                              onShowPath: () => _showFilePath(song),
                              onShareFile: () => _shareAudioFile(song),
                              onDeleteDownload: _isSystemView && isDownload
                                  ? () => _confirmDeleteDownload(song)
                                  : null,
                              onRemoveDevice: _isSystemView && isDevice
                                  ? () => _confirmRemoveDevice(song)
                                  : null,
                              onRemoveFromPlaylist: !_isSystemView
                                  ? () => _removeSongFromCustomPlaylist(
                                      song)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _ViewTile extends StatelessWidget {
  const _ViewTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(label, style: AppTypography.body),
              ),
              Text('$count', style: AppTypography.caption),
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomPlaylistTile extends StatelessWidget {
  const _CustomPlaylistTile({
    required this.playlist,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final CustomPlaylist playlist;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        onLongPress: () => _showMenu(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.queue_music_rounded,
                size: 22,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body,
                ),
              ),
              Text('${playlist.songCount}', style: AppTypography.caption),
              const SizedBox(width: AppSpacing.xs),
              PopupMenuButton<String>(
                tooltip: 'More',
                color: AppColors.surfaceElevated,
                icon: const Icon(Icons.more_vert,
                    color: AppColors.textSecondary, size: 20),
                onSelected: (v) {
                  if (v == 'rename') onRename();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete',
                        style: TextStyle(color: AppColors.error)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                onRename();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: AppColors.error),
              title: const Text('Delete',
                  style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SongMenu extends StatelessWidget {
  const _SongMenu({
    required this.song,
    required this.onPlay,
    required this.onAddToPlaylist,
    required this.onRename,
    required this.onInfo,
    required this.onShowPath,
    required this.onShareFile,
    this.onDeleteDownload,
    this.onRemoveDevice,
    this.onRemoveFromPlaylist,
  });

  final Song song;
  final VoidCallback onPlay;
  final VoidCallback onAddToPlaylist;
  final VoidCallback? onRename;
  final VoidCallback onInfo;
  final VoidCallback onShowPath;
  final VoidCallback onShareFile;
  final VoidCallback? onDeleteDownload;
  final VoidCallback? onRemoveDevice;
  final VoidCallback? onRemoveFromPlaylist;

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
          case 'add_to_playlist':
            onAddToPlaylist();
          case 'rename':
            onRename?.call();
          case 'info':
            onInfo();
          case 'path':
            onShowPath();
          case 'share':
            onShareFile();
          case 'delete_download':
            onDeleteDownload?.call();
          case 'remove_device':
            onRemoveDevice?.call();
          case 'remove_playlist':
            onRemoveFromPlaylist?.call();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'play', child: Text('Play')),
        const PopupMenuItem(
          value: 'add_to_playlist',
          child: Text('Add to playlist'),
        ),
        if (onRename != null)
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'info', child: Text('File Information')),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'path',
          child: Row(
            children: [
              Icon(Icons.folder_open_rounded,
                  size: 18, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Text('Show/Copy File Path'),
            ],
          ),
        ),
        const PopupMenuItem(value: 'share', child: Text('Share file')),
        if (onDeleteDownload != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'delete_download',
            child: Text('Delete Download',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
        if (onRemoveDevice != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'remove_device',
            child: Text('Remove from Playlist',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
        if (onRemoveFromPlaylist != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'remove_playlist',
            child: Text('Remove from playlist',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty / permission panes
// ---------------------------------------------------------------------------

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({required this.filter});

  final PlaylistSystemView filter;

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = switch (filter) {
      PlaylistSystemView.all => (
          Icons.library_music_outlined,
          'No music yet',
          'Download songs from Search, or let FreeVibe see music on your device',
        ),
      PlaylistSystemView.downloaded => (
          Icons.download_outlined,
          'No downloaded songs',
          'Download a song from Search and it will appear here',
        ),
      PlaylistSystemView.onDevice => (
          Icons.music_note_outlined,
          'No device music found',
          'FreeVibe could not find audio in your device collection',
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: AppTypography.caption),
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class _DevicePermissionPane extends StatelessWidget {
  const _DevicePermissionPane({
    required this.permission,
    required this.onAllowAccess,
    required this.onOpenSettings,
  });

  final DevicePermissionState permission;
  final VoidCallback onAllowAccess;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final denied = permission == DevicePermissionState.denied;
    final permanent =
        permission == DevicePermissionState.permanentlyDenied;
    final title = denied
        ? 'Device music access denied'
        : permanent
            ? 'Device music access is permanently off'
            : 'Device music access needed';
    final subtitle = denied
        ? 'Allow FreeVibe to read your media library to find songs stored on this device.'
        : permanent
            ? 'Open settings and enable media permission for FreeVibe to find device music.'
            : 'Allow FreeVibe to read your media library to see music stored on this device.';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.perm_media_rounded,
                size: 56, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: AppTypography.caption),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: AppTypography.caption,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (!permanent)
              FilledButton.tonal(
                onPressed: onAllowAccess,
                child: const Text('Allow access'),
              ),
            if (denied || permanent) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                  onPressed: onOpenSettings,
                  child: const Text('Open Settings')),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add-to-playlist bottom sheet
// ---------------------------------------------------------------------------

class _AddToPlaylistSheet extends StatefulWidget {
  const _AddToPlaylistSheet({
    required this.song,
    required this.playlists,
  });

  final Song song;
  final CustomPlaylistService playlists;

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  List<CustomPlaylist> _allPlaylists = [];
  Set<String> _containedIn = {};
  bool _isLoading = true;
  String _newName = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await widget.playlists.listAll();
    final contained =
        await widget.playlists.playlistsContainingSong(widget.song.id);
    if (!mounted) return;
    setState(() {
      _allPlaylists = all;
      _containedIn = contained;
      _isLoading = false;
    });
  }

  Future<void> _toggle(CustomPlaylist pl) async {
    if (_containedIn.contains(pl.id)) {
      await widget.playlists.removeSong(pl.id, widget.song.id);
    } else {
      await widget.playlists.addSong(pl.id, widget.song.id);
    }
    final all = await widget.playlists.listAll();
    final contained =
        await widget.playlists.playlistsContainingSong(widget.song.id);
    if (!mounted) return;
    setState(() {
      _allPlaylists = all;
      _containedIn = contained;
    });
  }

  Future<void> _createAndAdd() async {
    final error = widget.playlists.validateName(_newName);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (FocusScope.of(context).hasPrimaryFocus) {
      FocusScope.of(context).unfocus();
    }
    final pl = await widget.playlists.create(_newName);
    await widget.playlists.addSong(pl.id, widget.song.id);
    _newName = '';
    final all = await widget.playlists.listAll();
    final contained =
        await widget.playlists.playlistsContainingSong(widget.song.id);
    if (!mounted) return;
    setState(() {
      _allPlaylists = all;
      _containedIn = contained;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollController) {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Add to playlist',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              // Create new row
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'New playlist name',
                          hintStyle:
                              const TextStyle(color: AppColors.textMuted),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceMuted,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                        onChanged: (v) => _newName = v,
                        onSubmitted: (_) => _createAndAdd(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      icon: const Icon(Icons.add_circle,
                          color: AppColors.primary),
                      onPressed: _createAndAdd,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _allPlaylists.length,
                  itemBuilder: (_, i) {
                    final pl = _allPlaylists[i];
                    final checked = _containedIn.contains(pl.id);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (_) => _toggle(pl),
                      title: Text(
                        pl.name,
                        style:
                            const TextStyle(color: AppColors.textPrimary),
                      ),
                      subtitle: Text(
                        '${pl.songCount} ${pl.songCount == 1 ? 'song' : 'songs'}',
                        style: AppTypography.caption,
                      ),
                      activeColor: AppColors.primary,
                      checkColor: Colors.white,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

class _NewPlaylistDialog extends StatefulWidget {
  @override
  State<_NewPlaylistDialog> createState() => _NewPlaylistDialogState();
}

class _NewPlaylistDialogState extends State<_NewPlaylistDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New playlist'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: const InputDecoration(
          hintText: 'Playlist name',
          hintStyle: TextStyle(color: AppColors.textMuted),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }

  void _submit() {
    Navigator.pop(context, _controller.text);
  }
}

class _RenamePlaylistDialog extends StatefulWidget {
  const _RenamePlaylistDialog({required this.initialName});
  final String initialName;

  @override
  State<_RenamePlaylistDialog> createState() => _RenamePlaylistDialogState();
}

class _RenamePlaylistDialogState extends State<_RenamePlaylistDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename playlist'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: const InputDecoration(hintText: 'New name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Rename'),
        ),
      ],
    );
  }

  void _submit() => Navigator.pop(context, _controller.text);
}

class _RenameSongDialog extends StatefulWidget {
  const _RenameSongDialog({required this.initialTitle});
  final String initialTitle;

  @override
  State<_RenameSongDialog> createState() => _RenameSongDialogState();
}

class _RenameSongDialogState extends State<_RenameSongDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename song'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Song name',
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The file extension will be preserved automatically.',
            style: AppTypography.caption,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Rename'),
        ),
      ],
    );
  }

  void _submit() {
    final validation = SongRenameService().validateNewName(_controller.text);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    Navigator.pop(context, _controller.text);
  }
}
