import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          _SleepTimerButton(controller: controller),
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
    final source = controller.currentSource;
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
                            if (source != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              _sourceChip(source, context),
                            ],
                            if (controller.playbackContextName != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              _contextChip(controller.playbackContextName!),
                            ],
                            const SizedBox(height: AppSpacing.xs),
                            _sourceUrlRow(context),
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

  Widget _sourceChip(PlaybackSource source, BuildContext context) {
    final (label, icon, color) = switch (source) {
      PlaybackSource.local => (
          'Downloaded file',
          Icons.offline_pin_rounded,
          AppColors.success,
        ),
      PlaybackSource.device => (
          'On device',
          Icons.smartphone_rounded,
          AppColors.tertiary,
        ),
      PlaybackSource.preview => (
          'Preview stream',
          Icons.cloud_rounded,
          AppColors.textSecondary,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _contextChip(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.queue_music_rounded, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            'From: $name',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// The REAL source: the canonical YouTube watch URL (never a fabricated or
  /// temporary stream URL). Truncated for display, copyable in full.
  Widget _sourceUrlRow(BuildContext context) {
    final url = song.canonicalYoutubeUrl;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.link_rounded, size: 13, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () {
            Clipboard.setData(ClipboardData(text: url));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Source URL copied')),
            );
          },
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(
              Icons.copy_rounded,
              size: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
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

class _SleepTimerButton extends StatelessWidget {
  const _SleepTimerButton({required this.controller});
  final MusicPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return IconButton(
          tooltip: 'Sleep timer',
          icon: Icon(
            Icons.bedtime_rounded,
            color: controller.hasSleepTimer
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
          onPressed: () => _showTimerSheet(context),
        );
      },
    );
  }

  void _showTimerSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.lg),
        ),
      ),
      builder: (sheetContext) {
        final remaining = controller.sleepTimerRemaining;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'Sleep timer',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (remaining != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      _formatDuration(remaining),
                      style: AppTypography.caption,
                    ),
                  ),
                if (controller.hasSleepTimer)
                  TextButton(
                    onPressed: () {
                      controller.cancelSleepTimer();
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text(
                      'Cancel timer',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                _timerRow(sheetContext, '15 minutes', const Duration(minutes: 15)),
                _timerRow(sheetContext, '30 minutes', const Duration(minutes: 30)),
                _timerRow(sheetContext, '45 minutes', const Duration(minutes: 45)),
                _timerRow(sheetContext, '60 minutes', const Duration(minutes: 60)),
                _timerRow(sheetContext, '90 minutes', const Duration(minutes: 90)),
                ListTile(
                  dense: true,
                  title: const Text(
                    'Custom minutes…',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  leading: const Icon(Icons.schedule_rounded,
                      color: AppColors.textSecondary),
                  onTap: () => _openCustomMinutes(sheetContext),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openCustomMinutes(BuildContext sheetContext) {
    showDialog<int>(
      context: sheetContext,
      builder: (_) => const _MinutePickerDialog(),
    ).then((minutes) {
      if (minutes == null) return;
      if (!sheetContext.mounted) return;
      controller.startSleepTimer(Duration(minutes: minutes));
      Navigator.of(sheetContext).pop();
    });
  }

  Widget _timerRow(BuildContext context, String label, Duration duration) {
    return ListTile(
      dense: true,
      title: Text(
        label,
        style: const TextStyle(color: AppColors.textPrimary),
      ),
      leading: const Icon(Icons.bedtime_rounded, color: AppColors.textSecondary),
      onTap: () {
        controller.startSleepTimer(duration);
        Navigator.of(context).pop();
      },
    );
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '0:00';
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    if (mins >= 60) {
      final hrs = mins ~/ 60;
      final remainMins = mins % 60;
      return '${hrs}h ${remainMins}m';
    }
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}

class _MinutePickerDialog extends StatefulWidget {
  const _MinutePickerDialog();

  @override
  State<_MinutePickerDialog> createState() => _MinutePickerDialogState();
}

class _MinutePickerDialogState extends State<_MinutePickerDialog> {
  final TextEditingController _minutesInput = TextEditingController();

  @override
  void dispose() {
    _minutesInput.dispose();
    super.dispose();
  }

  void _submit() {
    final minutes = int.tryParse(_minutesInput.text.trim());
    if (minutes == null || minutes <= 0 || minutes > 24 * 60) return;
    Navigator.of(context).pop(minutes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text(
        'Sleep timer',
        style: TextStyle(color: AppColors.textPrimary),
      ),
      content: TextField(
        controller: _minutesInput,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Minutes',
          labelStyle: TextStyle(color: AppColors.textSecondary),
          hintText: 'e.g. 25',
          hintStyle: TextStyle(color: AppColors.textMuted),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.textMuted),
          ),
        ),
        style: const TextStyle(color: AppColors.textPrimary),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child:
              const Text('Start', style: TextStyle(color: AppColors.primary)),
        ),
      ],
    );
  }
}