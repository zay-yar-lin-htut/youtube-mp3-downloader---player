import 'package:flutter/material.dart';

import '../player/time_format.dart';
import '../services/update_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Runs a non-blocking update check and, when a newer version is published,
/// prompts the user with either an optional or a forced update dialog.
Future<void> runUpdateFlowIfNeeded(
  BuildContext context, {
  required UpdateService service,
}) async {
  final check = await service.checkForUpdate();
  if (!context.mounted || check == null || !check.available) {
    return;
  }
  await showUpdateDialog(context, service: service, check: check);
}

/// Shows the update prompt for an already-resolved [UpdateCheck].
Future<void> showUpdateDialog(
  BuildContext context, {
  required UpdateService service,
  required UpdateCheck check,
}) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: !check.server.forceUpdate,
    builder: (_) => UpdateFlowDialog(service: service, check: check),
  );
}

enum _UpdateStage { prompt, downloading, done, failed }

/// Full update flow inside one dialog: prompt -> download -> installer.
class UpdateFlowDialog extends StatefulWidget {
  const UpdateFlowDialog({
    super.key,
    required this.service,
    required this.check,
  });

  final UpdateService service;
  final UpdateCheck check;

  @override
  State<UpdateFlowDialog> createState() => _UpdateFlowDialogState();
}

class _UpdateFlowDialogState extends State<UpdateFlowDialog> {
  _UpdateStage _stage = _UpdateStage.prompt;
  int _receivedBytes = 0;
  int? _totalBytes;
  String _errorMessage = '';

  bool get _force => widget.check.server.forceUpdate;

  Future<void> _start() async {
    setState(() {
      _stage = _UpdateStage.downloading;
      _receivedBytes = 0;
      _totalBytes = null;
      _errorMessage = '';
    });
    final download = await widget.service.downloadUpdate(
      widget.check.server.downloadUrl,
      onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          _receivedBytes = received;
          _totalBytes = total;
        });
      },
    );
    if (!mounted) return;
    if (download == null) {
      setState(() {
        _stage = _UpdateStage.failed;
        _errorMessage = 'The download could not be completed. '
            'Please check your connection and try again.';
      });
      return;
    }
    final launched = await widget.service.launchInstaller(download.filePath);
    if (!mounted) return;
    setState(() {
      _stage = launched ? _UpdateStage.done : _UpdateStage.failed;
      _errorMessage = launched
          ? ''
          : 'The APK was downloaded, but the installer could not be opened. '
              'Try again, or grant "Install unknown apps" permission first.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage != _UpdateStage.downloading && !_force,
      child: AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(_title()),
        content: _content(),
        actions: _actions(),
      ),
    );
  }

  String _title() {
    switch (_stage) {
      case _UpdateStage.prompt:
        return 'Update available';
      case _UpdateStage.downloading:
        return 'Downloading update';
      case _UpdateStage.done:
        return 'Ready to install';
      case _UpdateStage.failed:
        return 'Update failed';
    }
  }

  Widget? _content() {
    switch (_stage) {
      case _UpdateStage.prompt:
        final server = widget.check.server;
        return Text(
          'FreeVibe ${server.version} (build ${server.versionCode}) is here. '
          '${_force ? 'This update is required to keep listening.' : 'Install it now or later.'}',
          style: AppTypography.bodyMuted,
        );
      case _UpdateStage.downloading:
        final received = _receivedBytes;
        final total = _totalBytes;
        final percent = (total == null || total <= 0)
            ? null
            : ((received / total) * 100).clamp(0, 100).toDouble();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 6,
                backgroundColor: AppColors.surfaceMuted,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              total == null
                  ? formatBytes(received)
                  : '${formatBytes(received)} / ${formatBytes(total)}',
              style: AppTypography.caption,
            ),
          ],
        );
      case _UpdateStage.done:
        return const Text(
          'The installer should open automatically. If prompted, allow '
          '"Install unknown apps" for FreeVibe, then confirm the update.',
          style: AppTypography.bodyMuted,
        );
      case _UpdateStage.failed:
        return Text(
          _errorMessage.isEmpty
              ? 'Something went wrong. Please try again.'
              : _errorMessage,
          style: AppTypography.bodyMuted,
        );
    }
  }

  List<Widget> _actions() {
    switch (_stage) {
      case _UpdateStage.prompt:
        return [
          if (!_force)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          FilledButton(
            onPressed: _start,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Update'),
          ),
        ];
      case _UpdateStage.downloading:
        return const [];
      case _UpdateStage.done:
        return [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Close'),
          ),
        ];
      case _UpdateStage.failed:
        return [
          if (!_force)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          FilledButton(
            onPressed: _start,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Try again'),
          ),
        ];
    }
  }
}