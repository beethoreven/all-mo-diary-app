/// Dates: every date is a Gregorian calendar day in Taiwan time (Asia/Taipei),
/// shown as 2026/11/10（二）. A diary belongs to a day, not to a moment, so it stores no time zone.
library;

/// A calendar day without a time zone.
class Day implements Comparable<Day> {
  const Day(this.year, this.month, this.day);

  factory Day.of(DateTime dt) => Day(dt.year, dt.month, dt.day);

  /// Parses the stored form, 2026-11-10.
  factory Day.parse(String text) {
    final parts = text.split('-').map(int.parse).toList();
    return Day(parts[0], parts[1], parts[2]);
  }

  final int year;
  final int month;
  final int day;

  /// Midnight UTC of this day, only for date arithmetic.
  DateTime get asUtc => DateTime.utc(year, month, day);

  Day addDays(int days) => Day.of(asUtc.add(Duration(days: days)));

  /// 1 = Monday … 7 = Sunday.
  int get weekday => asUtc.weekday;

  static int daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

  /// The stored form, 2026-11-10 (sorts correctly as text).
  @override
  String toString() => '${_pad(year, 4)}-${_pad(month, 2)}-${_pad(day, 2)}';

  /// The displayed form, 2026/11/10（二）.
  String get label => '${_pad(year, 4)}/${_pad(month, 2)}/${_pad(day, 2)}（${weekdayName(weekday)}）';

  static String weekdayName(int weekday) => const ['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

  static String _pad(int v, int width) => v.toString().padLeft(width, '0');

  @override
  int compareTo(Day other) => asUtc.compareTo(other.asUtc);

  @override
  bool operator ==(Object other) => other is Day && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

abstract final class TimeRules {
  static const taipeiOffset = Duration(hours: 8);

  /// Now. Tests replace it.
  static DateTime Function() now = DateTime.now;

  /// Today in Taiwan, whatever time zone the phone is set to.
  static Day today() => Day.of(now().toUtc().add(taipeiOffset));

  /// Milliseconds since the epoch, UTC. Used for created/updated stamps.
  static int nowMs() => now().toUtc().millisecondsSinceEpoch;
}
