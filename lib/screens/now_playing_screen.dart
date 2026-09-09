import 'package:flutter/material.dart';
import '../models/song.dart';
import '../player/audio_engine.dart';
import '../player/music_player_controller.dart';
import '../player/player_queue.dart';
import '../player/time_format.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/artwork.dart';
import '../widgets/queue_sheet.dart';

/// Full-screen playback page opened from the mini player.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key, required this.controller});

  final MusicPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          tooltip: 'Collapse',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Now Playing', style: AppTypography.appBarTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music_rounded),
            tooltip: 'Queue',
            onPressed: () => QueueSheet.show(context, controller),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final song = controller.currentSong;
          if (song == null) {
            return const Center(
              child: Text('Nothing is playing', style: AppTypography.caption),
            );
          }
          return _NowPlayingBody(controller: controller, song: song);
        },
      ),
    );
  }
}

class _NowPlayingBody extends StatelessWidget {
  const _NowPlayingBody({required this.controller, required this.song});

  final MusicPlayerController controller;
  final Song song;

  @override
  Widget build(BuildContext context) {
    final isLocal = controller.currentSource == PlaybackSource.local;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Artwork(imageUrl: song.thumbnailUrl, size: 280),
                      const SizedBox(height: AppSpacing.xxxl),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                        child: Column(
                          children: [
                            Text(
                              song.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              song.author,
                              style: AppTypography.songSubtitle,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _sourceChip(isLocal, context),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _SeekArea(controller: controller),
          _Controls(controller: controller),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _sourceChip(bool isLocal, BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLocal ? Icons.offline_pin_rounded : Icons.cloud_rounded,
            size: 14,
            color: isLocal ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            isLocal ? 'Local file' : 'Preview stream',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SeekArea extends StatelessWidget {
  const _SeekArea({required this.controller});

  final MusicPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: controller.positionNotifier,
      builder: (context, position, _) {
        return ValueListenableBuilder<Duration>(
          valueListenable: controller.durationNotifier,
          builder: (context, duration, _) {
            final max = duration.inMilliseconds > 0
                ? duration.inMilliseconds.toDouble()
                : 1.0;
            final value = position.inMilliseconds
                .clamp(0, duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds)
                .toDouble();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: AppColors.surfaceMuted,
                      thumbColor: AppColors.primary,
                    ),
                    child: Slider(
                      value: value.clamp(0.0, max),
                      max: max,
                      onChanged: (v) => controller.seekTo(
                        Duration(milliseconds: v.round()),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          formatDuration(position),
                          style: AppTypography.caption,
                        ),
                        Text(
                          formatDuration(duration),
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final MusicPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          iconSize: 22,
          tooltip: 'Shuffle',
          onPressed: controller.toggleShuffle,
          icon: Icon(
            Icons.shuffle_rounded,
            color: controller.queue.isShuffleEnabled
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
        ),
        IconButton(
          iconSize: 34,
          tooltip: 'Previous',
          onPressed: controller.previous,
          icon: const Icon(Icons.skip_previous_rounded, color: AppColors.textPrimary),
        ),
        ValueListenableBuilder(
          valueListenable: controller.engine.stage,
          builder: (context, stage, _) {
            final playing = stage == EngineStage.playing;
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.accentGradient,
              ),
              child: IconButton(
                iconSize: 40,
                tooltip: playing ? 'Pause' : 'Play',
                onPressed: controller.togglePause,
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
              ),
            );
          },
        ),
        IconButton(
          iconSize: 34,
          tooltip: 'Next',
          onPressed: controller.next,
          icon: const Icon(Icons.skip_next_rounded, color: AppColors.textPrimary),
        ),
        IconButton(
          iconSize: 22,
          tooltip: 'Repeat',
          onPressed: controller.cycleRepeat,
          icon: Icon(
            controller.repeatMode == RepeatStyle.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            color: controller.repeatMode == RepeatStyle.off
                ? AppColors.textSecondary
                : AppColors.primary,
          ),
        ),
      ],
    );
  }
}