import 'package:flutter/material.dart';
import '../player/music_player_controller.dart';
import '../player/player_queue.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'artwork.dart';

/// Bottom sheet listing the playback queue (active order). Supports jumping to
/// a track, removing a track, and clearing the rest of the queue.
class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key, required this.controller});

  final MusicPlayerController controller;

  static Future<void> show(BuildContext context, MusicPlayerController controller) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => QueueSheet(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.queue,
      builder: (context, _) {
        final order = controller.queue.activeOrder;
        final currentId = controller.currentSong?.id;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Text(
                        order.isEmpty ? 'Queue' : 'Now Playing (${order.length})',
                        style: AppTypography.screenHeading,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Clear queued tracks',
                        icon: const Icon(Icons.playlist_remove, color: AppColors.textSecondary),
                        onPressed: order.isEmpty || controller.queue.cursor == order.length - 1
                            ? null
                            : controller.queue.clearUpcoming,
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close, color: AppColors.textSecondary),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: order.isEmpty
                      ? const Center(
                          child: Text(
                            'Queue is empty',
                            style: AppTypography.caption,
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: order.length,
                          itemBuilder: (context, index) {
                            final entry = order[index];
                            final song = entry.song;
                            final isCurrent = song.id == currentId;
                            return ListTile(
                              onTap: () {
                                Navigator.of(context).pop();
                                controller.playAtActiveIndex(index);
                              },
                              leading: Stack(
                                children: [
                                  Artwork(imageUrl: song.thumbnailUrl, size: 44),
                                  if (isCurrent)
                                    Positioned.fill(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: AppColors.scrim,
                                          borderRadius: BorderRadius.circular(AppRadius.sm),
                                        ),
                                        child: const Icon(
                                          Icons.equalizer_rounded,
                                          size: 22,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              title: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: isCurrent
                                    ? const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      )
                                    : AppTypography.songTitleSmall,
                              ),
                              subtitle: Text(
                                '${song.author} · ${_sourceLabel(entry.source)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.songSubtitle,
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, color: AppColors.textMuted),
                                tooltip: 'Remove from queue',
                                onPressed: () => controller.removeAtActiveIndex(index),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _sourceLabel(PlaybackSource source) =>
      source == PlaybackSource.local ? 'local file' : 'preview';
}