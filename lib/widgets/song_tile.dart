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
    this.trailing,
    this.isActive = false,
  });

  final Song song;
  final VoidCallback? onTap;
  final String? subtitle;
  final Widget? trailing;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final subtitleText = subtitle ?? '${song.author} · ${song.duration}';
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
                  if (isActive) const SizedBox(height: 2),
                  Text(
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
}