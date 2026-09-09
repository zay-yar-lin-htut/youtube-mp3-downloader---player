import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// Thumbnail with graceful fallback to a gradient + note glyph.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.imageUrl,
    this.size,
    this.radius = AppRadius.md,
  });

  final String imageUrl;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final widget = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Builder(
        builder: (context) {
          if (imageUrl.isEmpty) {
            return _fallback(context);
          }
          return Image.network(
            imageUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) {
                return child;
              }
              return _fallback(context);
            },
            errorBuilder: (context, error, stackTrace) => _fallback(context),
          );
        },
      ),
    );

    if (size == null) {
      return widget;
    }
    return SizedBox(width: size, height: size, child: widget);
  }

  Widget _fallback(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.artworkFallback,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: AppColors.textMuted,
        size: (size ?? 40) * 0.45,
      ),
    );
  }
}