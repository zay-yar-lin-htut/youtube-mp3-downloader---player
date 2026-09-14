import 'package:flutter/material.dart';
import '../models/song.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'artwork.dart';

/// Shared, styled song row used across Search / Playlist / Downloads.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.subtitle,
    this.durationLabel,
    this.badge,
    this.resumeLabel,
    this.timestamp,
    this.trailing,
    this.isActive = false,
  });

  final Song song;
  final VoidCallback? onTap;
  final String? subtitle;

  /// Small pill label (e.g. "Downloaded" / "On device" / "YouTube").
  final String? badge;

  /// Resume hint (e.g. "Continue · 1:37") shown while not active.
  final String? resumeLabel;

  /// Right-aligned song length; defaults to [song.duration].
  final String? durationLabel;

  /// Compact meta line below the artist (e.g. a download timestamp).
  final String? timestamp;

  final Widget? trailing;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Artwork(imageUrl: song.thumbnailUrl, size: 48),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.songTitle,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isActive ? 'Now playing' : subtitleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: isActive
                              ? const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w500,
                                )
                              : AppTypography.songSubtitle,
                        ),
                      ),
                      if (durationLabel != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          durationLabel!,
                          style: AppTypography.songDuration,
                        ),
                      ],
                      if (resumeLabel != null && !isActive) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          resumeLabel!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                      if (badge != null && !isActive) ...[
                        const SizedBox(width: AppSpacing.sm),
                        _SourceBadge(label: badge!),
                      ],
                    ],
                  ),
                  if (timestamp != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      timestamp!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.songTimestamp,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }

  String get subtitleText => subtitle ?? song.author;
}

/// Compact sizing for song-row action buttons: keeps adjacent actions close
/// together while retaining a comfortable touch target.
const BoxConstraints kSongActionConstraints =
    BoxConstraints(minWidth: 40, minHeight: 40);
const VisualDensity kSongActionDensity = VisualDensity.compact;
const EdgeInsets kSongActionPadding = EdgeInsets.zero;

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = switch (label) {
      'Downloaded' => AppColors.success,
      'On device' => AppColors.tertiary,
      _ => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}