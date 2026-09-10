import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/song.dart';
import '../player/time_format.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Shows technical details for a song (path, size, duration) with a copy
/// button for the local path.
class SongInfoDialog extends StatelessWidget {
  const SongInfoDialog({super.key, required this.song});

  final Song song;

  static Future<void> show(BuildContext context, Song song) {
    return showDialog(context: context, builder: (_) => SongInfoDialog(song: song));
  }

  @override
  Widget build(BuildContext context) {
    final path = song.localPath;
    final size = _localSizeText();
    return AlertDialog(
      title: const Text('Track Info'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (path != null) ..._localRows(context, path, size)
          else ..._previewRows(context),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  List<Widget> _localRows(BuildContext context, String path, String size) {
    return [
      _row('Title', song.title),
      const SizedBox(height: AppSpacing.sm),
      _row('Artist', song.author),
      const SizedBox(height: AppSpacing.sm),
      _row('Duration', song.duration),
      const SizedBox(height: AppSpacing.sm),
      _row('File name', _fileName(path)),
      const SizedBox(height: AppSpacing.sm),
      _row('Format', _fileFormat(path)),
      const SizedBox(height: AppSpacing.sm),
      _row('Size', size),
      const SizedBox(height: AppSpacing.sm),
      if (song.downloadedAt != null) ...[
        _row('Downloaded', _formatDate(song.downloadedAt!)),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (song.source == SongSource.device) ...[
        _row('Source', 'On device'),
        const SizedBox(height: AppSpacing.sm),
      ] else if (song.canonicalYoutubeUrl.isNotEmpty) ...[
        _urlRow(context, 'Source')
      ] else ...[
        _row('Source', 'YouTube (URL not stored)'),
        const SizedBox(height: AppSpacing.sm),
      ],
      const SizedBox(height: AppSpacing.xs),
      _pathRow(context),
    ];
  }

  List<Widget> _previewRows(BuildContext context) {
    return [
      _row('Title', song.title),
      const SizedBox(height: AppSpacing.sm),
      _row('Artist', song.author),
      const SizedBox(height: AppSpacing.sm),
      _row('Duration', song.duration),
      const SizedBox(height: AppSpacing.sm),
      if (song.canonicalYoutubeUrl.isNotEmpty) ...[
        _urlRow(context, 'Source')
      ] else ...[
        const _InfoRow(
          label: 'Source',
          value: 'Preview only (not downloaded)',
        ),
      ],
    ];
  }

  Widget _pathRow(BuildContext context) {
    return _InfoRow(
      label: 'Local path',
      value: song.localPath!,
      trailing: IconButton(
        tooltip: 'Copy path',
        icon: const Icon(Icons.copy, size: 18, color: AppColors.textSecondary),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: song.localPath!));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Path copied to clipboard')),
          );
        },
      ),
    );
  }

  Widget _urlRow(BuildContext context, String label) {
    return _InfoRow(
      label: label,
      value: song.canonicalYoutubeUrl,
      trailing: IconButton(
        tooltip: 'Copy URL',
        icon: const Icon(Icons.copy, size: 18, color: AppColors.textSecondary),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: song.canonicalYoutubeUrl));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('URL copied to clipboard')),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) => _InfoRow(label: label, value: value);

  String _fileName(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.isEmpty ? path : name;
  }

  String _fileFormat(String path) {
    final dot = path.lastIndexOf('.');
    if (dot <= 0 || dot == path.length - 1) return 'unknown';
    return path.substring(dot + 1).toUpperCase();
  }

  String _formatDate(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  String _localSizeText() {
    final path = song.localPath;
    if (path == null) {
      return 'n/a';
    }
    try {
      final file = File(path);
      final exists = file.existsSync();
      if (!exists) {
        return 'missing on disk';
      }
      return formatBytes(file.lengthSync());
    } catch (_) {
      return 'unavailable';
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(label, style: AppTypography.caption),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: AppTypography.body.copyWith(color: AppColors.textPrimary),
          ),
        ),
        ?trailing,
      ],
    );
  }
}