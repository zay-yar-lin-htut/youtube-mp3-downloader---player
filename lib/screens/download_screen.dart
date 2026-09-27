import 'package:flutter/material.dart';
import '../models/song.dart';
import '../player/time_format.dart';
import '../services/download_manager.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/song_tile.dart';
import '../widgets/song_info_dialog.dart';

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
      final songs = await DatabaseService.instance.getDownloadHistory();
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

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear download history'),
        content: const Text(
          'This clears the download records only.\n\n'
          'Your downloaded audio files and your library are NOT deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Clear',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await DatabaseService.instance.clearDownloadHistory();
    DownloadManager.instance.notifyHistoryChanged();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('History cleared')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: ListenableBuilder(
        listenable: DownloadManager.instance,
        builder: (context, _) {
          final activeTasks = DownloadManager.instance.activeDownloads.values
              .where((task) => !task.isCompleted)
              .toList();
          final failed = DownloadManager.instance.failedDownloads.entries
              .toList();

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
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Text('History', style: AppTypography.screenHeading),
                  ],
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
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textMuted,
                        ),
                        tooltip: 'Dismiss',
                        onPressed: () =>
                            DownloadManager.instance.removeFailure(entry.key),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Text(
                        'History (${_history.length})',
                        style: AppTypography.playlistUbuntu,
                      ),
                      const Spacer(),
                      if (_history.isNotEmpty)
                        TextButton(
                          onPressed: _confirmClearHistory,
                          child: const Text(
                            'Clear history',
                            style: TextStyle(color: AppColors.error),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 56,
                            color: AppColors.textMuted,
                          ),
                          SizedBox(height: AppSpacing.md),
                          Text('No history', style: AppTypography.caption),
                          SizedBox(height: AppSpacing.xs),
                          Text(
                            'Completed downloads appear here with timestamps',
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._history.map(
                    (song) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: SongTile(
                        song: song,
                        subtitle: 'Downloaded',
                        timestamp: song.downloadedAt == null
                            ? null
                            : formatDownloaded(song.downloadedAt!),
                        onTap: () => SongInfoDialog.show(context, song),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
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
    final percent = task.progress == null
        ? '—'
        : '${(task.progress! * 100).toStringAsFixed(0)}%';
    final total = task.totalBytes;
    final remaining = total == null
        ? null
        : (total - task.downloadedBytes).clamp(0, total);
    final detail = [
      if (task.speedBytesPerSecond != null)
        '${_formatBytes(task.speedBytesPerSecond!.round())}/s',
      total == null
          ? '${_formatBytes(task.downloadedBytes)} · total unknown'
          : '${_formatBytes(task.downloadedBytes)} / ${_formatBytes(total)}',
      if (remaining != null) '${_formatBytes(remaining)} remaining',
      if (task.eta != null) '${_formatEta(task.eta!)} remaining',
    ].join(' · ');
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
                  '${_statusLabel(task.status)} · $percent',
                  style: AppTypography.caption,
                ),
                const SizedBox(height: 3),
                Text(detail, style: AppTypography.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _statusLabel(DownloadStatus status) => switch (status) {
  DownloadStatus.waiting => 'Waiting',
  DownloadStatus.downloading => 'Downloading',
  DownloadStatus.completed => 'Completed',
  DownloadStatus.failed => 'Failed',
  DownloadStatus.paused => 'Paused',
  DownloadStatus.cancelled => 'Cancelled',
};

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unit]}';
}

String _formatEta(Duration duration) {
  if (duration.inHours > 0) {
    return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
  }
  if (duration.inMinutes > 0) {
    return '${duration.inMinutes} min';
  }
  return '${duration.inSeconds} sec';
}
