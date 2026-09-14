import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Centralized text styles. Dark app: keep body text bright, allow muted for
/// secondary/meta lines.
abstract final class AppTypography {
  static const TextStyle appBarTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMuted = TextStyle(
    fontSize: 14,
    color: AppColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: AppColors.textSecondary,
  );

  static const TextStyle songTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle songTitleSmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const TextStyle songSubtitle = TextStyle(
    fontSize: 12,
    color: AppColors.textSecondary,
  );

  /// Right-aligned song length (e.g. "3:42") on the meta line.
  static const TextStyle songDuration = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  /// Compact download timestamp under the meta line (e.g. "Sep 9, 2026").
  static const TextStyle songTimestamp = TextStyle(
    fontSize: 11,
    color: AppColors.textMuted,
  );

  static const TextStyle playlistUbuntu = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  static const TextStyle screenHeading = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
}