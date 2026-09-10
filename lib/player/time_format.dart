String formatDuration(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) {
    return '$h:$mm:$ss';
  }
  return '$mm:$ss';
}

String formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Formats an epoch-milliseconds timestamp as e.g. "Sep 9, 2026, 6:21 PM".
String formatDownloaded(int epochMs) {
  final t = DateTime.fromMillisecondsSinceEpoch(epochMs);
  var hour = t.hour % 12;
  if (hour == 0) {
    hour = 12;
  }
  final minute = t.minute.toString().padLeft(2, '0');
  final ampm = t.hour >= 12 ? 'PM' : 'AM';
  return '${_months[t.month - 1]} ${t.day}, ${t.year}, $hour:$minute $ampm';
}