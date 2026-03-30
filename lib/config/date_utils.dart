/// Utilidades de fecha con zona horaria del tenant.
/// Usa el timezone configurado en el tenant (ej: America/Bogota = UTC-5).
class AppDateUtils {
  static Duration _offset = const Duration(hours: -5); // Default: Bogota
  static String _timezone = 'America/Bogota';

  /// Configure timezone from tenant settings.
  /// Call this after login or when tenant data loads.
  static void configure(String timezone) {
    _timezone = timezone;
    _offset = _getOffset(timezone);
  }

  static String get timezone => _timezone;

  /// Convert UTC DateTime to tenant local time
  static DateTime toLocal(DateTime utcDate) {
    return utcDate.toUtc().add(_offset);
  }

  /// Format a DateTime (assumed UTC from server) to tenant local string
  static String format(DateTime? date, {bool includeTime = true}) {
    if (date == null) return '-';
    final local = toLocal(date);
    final d = '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}';
    if (!includeTime) return d;
    return '$d ${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  /// Format date only
  static String formatDate(DateTime? date) => format(date, includeTime: false);

  /// Format time only
  static String formatTime(DateTime? date) {
    if (date == null) return '-';
    final local = toLocal(date);
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  /// Get UTC offset for common Colombian/Latin American timezones
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
