import '../core/time.dart';

/// A month as 4–6 weeks of 7 cells, starting on Monday or Sunday; cells outside the month are null.
/// (Same layout as mama-fufood.)
List<List<Day?>> monthGrid(int year, int month, {required bool weekStartsMonday}) {
  final first = Day(year, month, 1);
  final lead = weekStartsMonday ? first.weekday - 1 : first.weekday % 7;
  final cells = <Day?>[
    for (var i = 0; i < lead; i++) null,
    for (var d = 1; d <= Day.daysInMonth(year, month); d++) Day(year, month, d),
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return [for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7)];
}

List<String> weekdayLabels({required bool weekStartsMonday}) =>
    weekStartsMonday ? const ['一', '二', '三', '四', '五', '六', '日'] : const ['日', '一', '二', '三', '四', '五', '六'];
