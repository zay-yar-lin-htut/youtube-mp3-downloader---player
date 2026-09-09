import 'package:flutter/material.dart';

/// Centralized color palette for the app.
///
/// Dark-first visual language: near-black charcoal surfaces with a vivid
/// violet -> magenta music accent. All widgets should pull from these tokens
/// instead of hard-coding `Colors.*`.
abstract final class AppColors {
  static const background = Color(0xFF0D0D12);
  static const surface = Color(0xFF14141B);
  static const surfaceElevated = Color(0xFF1C1C26);
  static const surfaceMuted = Color(0xFF232330);
  static const surfaceOverlay = Color(0xFF2A2A38);

  static const primary = Color(0xFF8B5CF6);
  static const primaryDim = Color(0xFF6D4ACB);
  static const secondary = Color(0xFFEC4899);
  static const tertiary = Color(0xFF22D3EE);

  static const textPrimary = Color(0xFFF4F4F8);
  static const textSecondary = Color(0xFFA3A3B0);
  static const textMuted = Color(0xFF72727F);

  static const divider = Color(0xFF272732);
  static const error = Color(0xFFFF6B6B);
  static const success = Color(0xFF3DDC97);
  static const scrim = Color(0xB30D0D12);

  static LinearGradient get accentGradient => const LinearGradient(
        colors: [primary, secondary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static const _artworkGradient = LinearGradient(
    colors: [surfaceMuted, surface],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get artworkFallback => _artworkGradient;
}