import 'package:flutter/material.dart';
import '../models/song.dart';
import '../player/music_player_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../screens/now_playing_screen.dart';
import 'artwork.dart';

/// Floating compact player above the navigation bar. Hides itself when the
/// queue is empty. Tap opens the full Now Playing view.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.controller,
    this.onOpenNowPlaying,
  });

  final MusicPlayerController controller;
  final VoidCallback? onOpenNowPlaying;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final song = controller.currentSong;
        if (song == null) {
          return const SizedBox.shrink();
        }
        return _MiniPlayerView(
          controller: controller,
          song: song,
          onTap: onOpenNowPlaying ??
              () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => NowPlayingScreen(controller: controller),
                    ),
                  ),
        );
      },
    );
  }
}

class _MiniPlayerView extends StatelessWidget {
  const _MiniPlayerView({
    required this.controller,
    required this.song,
    required this.onTap,
  });

  final MusicPlayerController controller;
  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: controller.positionNotifier,
      builder: (context, position, _) {
        final total = controller.durationNotifier.value;
        final fraction = total.inMilliseconds == 0
            ? 0.0
            : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
        return Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.sm,
                right: AppSpacing.xs,
                bottom: AppSpacing.xs,
                top: AppSpacing.xs,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 3,
                      backgroundColor: AppColors.surfaceMuted,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Artwork(
                        imageUrl: song.thumbnailUrl,
                        size: 42,
                        radius: AppRadius.sm,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.songTitleSmall,
                            ),
                            Text(
                              song.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.songSubtitle,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        iconSize: 26,
                        icon: Icon(
                          controller.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: AppColors.textPrimary,
                        ),
                        onPressed: controller.togglePause,
                      ),
                      IconButton(
                        iconSize: 26,
                        icon: const Icon(
                          Icons.skip_next_rounded,
                          color: AppColors.textPrimary,
                        ),
                        onPressed: controller.next,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}