import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Message shown when a YouTube search cannot start because the device is
/// offline.
const String networkRequiredSearchMessage =
    'Internet connection is required to search YouTube.\n'
    'Please connect to Wi-Fi or mobile data and try again.';

/// Message shown when a YouTube preview cannot start because the device is
/// offline.
const String networkRequiredPreviewMessage =
    'Internet connection is required for preview.\n'
    'Please connect to Wi-Fi or mobile data and try again.';

/// Message shown when a YouTube download cannot start because the device is
/// offline.
const String networkRequiredDownloadMessage =
    'Internet connection is required to download from YouTube.\n'
    'Please connect to Wi-Fi or mobile data and try again.';

/// Blocks an Internet-dependent action (search, preview, download) with a
/// single styled "No Internet Connection" dialog. [message] describes the
/// operation that could not be started.
Future<void> showNetworkRequiredDialog(
  BuildContext context, {
  required String message,
}) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => NetworkRequiredDialog(message: message),
  );
}

/// Reusable "No Internet Connection" alert used to gate every
/// Internet-dependent action.
class NetworkRequiredDialog extends StatelessWidget {
  const NetworkRequiredDialog({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      icon: const Icon(
        Icons.wifi_off_rounded,
        size: 40,
        color: AppColors.textMuted,
      ),
      title: const Text('No Internet Connection'),
      content: Text(message, style: AppTypography.bodyMuted),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}