/// Utilidades de fecha con zona horaria del tenant.
class AppDateUtils {
  static Duration _offset = const Duration(hours: -5);
  static String _timezone = 'America/Bogota';

  static void configure(String timezone) {
    _timezone = timezone;
    _offset = _getOffset(timezone);
  }

  static String get timezone => _timezone;

  /// Convert a server DateTime (UTC) to tenant local time
  static DateTime toLocal(DateTime date) {
    // Server always sends UTC timestamps
    // If the DateTime was parsed without 'Z', it might be treated as local
    // Force it to UTC first, then apply offset
    final utc = date.isUtc ? date : DateTime.utc(
      date.year, date.month, date.day,
      date.hour, date.minute, date.second, date.millisecond,
    );
    return utc.add(_offset);
  }

  /// Format a DateTime from server to tenant local string
  static String format(DateTime? date, {bool includeTime = true}) {
    if (date == null) return '-';
    final local = toLocal(date);
    final d = '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}';
    if (!includeTime) return d;
    final h = local.hour;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : h > 12 ? h - 12 : h;
    return '$d $h12:$m $ampm';
  }

  static String formatDate(DateTime? date) => format(date, includeTime: false);

  static String formatTime(DateTime? date) {
    if (date == null) return '-';
    final local = toLocal(date);
    final h = local.hour;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : h > 12 ? h - 12 : h;
    return '$h12:$m $ampm';
  }

  static Duration _getOffset(String tz) {
    final offsets = {
      'America/Bogota': const Duration(hours: -5),
      'America/Lima': const Duration(hours: -5),
      'America/Guayaquil': const Duration(hours: -5),
      'America/Mexico_City': const Duration(hours: -6),
      'America/Santiago': const Duration(hours: -4),
      'America/Buenos_Aires': const Duration(hours: -3),
      'America/Sao_Paulo': const Duration(hours: -3),
      'America/Caracas': const Duration(hours: -4),
      'America/Panama': const Duration(hours: -5),
      'America/New_York': const Duration(hours: -5),
      'UTC': Duration.zero,
    };
    return offsets[tz] ?? const Duration(hours: -5);
  }
}
