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

/// Parses a "m:ss", "mm:ss" or "h:mm:ss" clock string into a [Duration].
/// Returns [Duration.zero] when the string cannot be parsed.
Duration parseClockDuration(String value) {
  final parts = value.trim().split(':');
  if (parts.length < 2 || parts.length > 3) {
    return Duration.zero;
  }
  final numbers = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part.trim());
    if (n == null || n < 0) {
      return Duration.zero;
    }
    numbers.add(n);
  }
  final seconds = numbers.last;
  final minutes = numbers[numbers.length - 2];
  final hours = numbers.length == 3 ? numbers.first : 0;
  return Duration(hours: hours, minutes: minutes, seconds: seconds);
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