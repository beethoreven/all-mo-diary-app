import '../core/text.dart';
import 'diary.dart';

/// Where to look.
enum SearchScope {
  all('全部'),
  title('標題'),
  body('內文');

  const SearchScope(this.label);

  final String label;
}

/// Diaries whose title and/or body contain [query], oldest first.
///
/// - The query's ends are trimmed; spaces in the middle must match exactly.
/// - English letters match regardless of case.
/// - Returns null when the query is empty after trimming (the screen asks for text instead).
List<Diary>? searchDiaries(Iterable<Diary> diaries, String query, SearchScope scope) {
  final q = TextRules.clean(query).toLowerCase();
  if (q.isEmpty) return null;
  bool hit(String text) => text.toLowerCase().contains(q);
  final found = [
    for (final d in diaries)
      if (switch (scope) {
        SearchScope.title => hit(d.title),
        SearchScope.body => hit(d.bodyPlain),
        SearchScope.all => hit(d.title) || hit(d.bodyPlain),
      })
        d,
  ]..sort((a, b) => a.day.compareTo(b.day));
  return found;
}

/// The filter tab's range: a whole year, a month, or one day.
class DayFilter {
  const DayFilter({required this.year, this.month, this.day}) : assert(day == null || month != null);

  final int year;
  final int? month;
  final int? day;

  /// The stored-day prefix that matches this range: '2026-', '2026-11-', '2026-11-10'.
  String get prefix {
    final y = year.toString().padLeft(4, '0');
    if (month == null) return '$y-';
    final m = month!.toString().padLeft(2, '0');
    if (day == null) return '$y-$m-';
    return '$y-$m-${day!.toString().padLeft(2, '0')}';
  }
}
