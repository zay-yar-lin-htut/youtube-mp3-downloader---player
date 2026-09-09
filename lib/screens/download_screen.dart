import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/download_manager.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/song_tile.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  List<Song> _history = [];
  bool _isLoading = true;
  int _lastHistoryRevision = -1;

  @override
  void initState() {
    super.initState();
    _loadHistory();
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
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final songs = await DatabaseService.instance.getPlaylist();
      if (mounted) {
        setState(() => _history = songs);
      }
    } catch (_) {
      // Ignore; non-fatal for the downloads overview.
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadManager.instance,
      builder: (context, _) {
        final activeTasks = DownloadManager.instance.activeDownloads.values
            .where((task) => !task.isCompleted)
            .toList();
        final failed = DownloadManager.instance.failedDownloads.entries.toList();

        if (_isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        return RefreshIndicator(
          onRefresh: _loadHistory,
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
                child: Text('Downloads', style: AppTypography.screenHeading),
              ),
              if (activeTasks.isNotEmpty) ...[
                _SectionLabel('Downloading'),
                const SizedBox(height: AppSpacing.xs),
                ...activeTasks.map((task) {
                  return _ActiveDownloadCard(task: task);
                }),
                const SizedBox(height: AppSpacing.xl),
              ],
              if (failed.isNotEmpty) ...[
                _SectionLabel('Failed'),
                const SizedBox(height: AppSpacing.xs),
                ...failed.map(
                  (entry) => ListTile(
                    leading: const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.error,
                    ),
                    title: Text(
                      entry.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.songTitleSmall,
                    ),
                    subtitle: const Text(
                      'Download failed — try again from Search',
                      style: AppTypography.songSubtitle,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textMuted),
                      tooltip: 'Dismiss',
                      onPressed: () =>
                          DownloadManager.instance.removeFailure(entry.key),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
              _SectionLabel('Downloaded (${_history.length})'),
              const SizedBox(height: AppSpacing.xs),
              if (_history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Center(
                    child: Text(
                      'No downloads yet',
                      style: AppTypography.caption,
                    ),
                  ),
                )
              else
                ..._history.map(
                  (song) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: SongTile(song: song),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTypography.playlistUbuntu);
  }
}

class _ActiveDownloadCard extends StatelessWidget {
  const _ActiveDownloadCard({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.downloading_rounded, color: AppColors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.songTitleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  backgroundColor: AppColors.surfaceMuted,
                  color: AppColors.primary,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  task.progress == null
                      ? 'Downloading…'
                      : '${(task.progress! * 100).toStringAsFixed(0)}%',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}