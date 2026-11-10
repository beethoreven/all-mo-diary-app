import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/time.dart';
import '../../domain/calendar.dart';
import '../../domain/diary.dart';
import '../../state/providers.dart';
import '../editor/diary_page.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Tab 1: the calendar (spec §3). Month header, swipe left/right to change month (as mama-fufood).
/// A day with a diary shows a blue dot and 「日記」; tapping an empty day opens a new diary,
/// tapping a day with a diary opens it for viewing.
class CalendarTab extends ConsumerStatefulWidget {
  const CalendarTab({super.key});

  @override
  ConsumerState<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends ConsumerState<CalendarTab> with SingleTickerProviderStateMixin {
  late int _year;
  late int _month;

  /// How far the month is dragged (pixels): positive shows the previous month, negative the next.
  late final AnimationController _offset = AnimationController.unbounded(vsync: this);
  double _width = 1;

  @override
  void initState() {
    super.initState();
    final today = TimeRules.today();
    _year = today.year.clamp(Limits.yearMin, Limits.yearMax);
    _month = today.month;
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  bool get _atStart => _year == Limits.yearMin && _month == 1;

  bool get _atEnd => _year == Limits.yearMax && _month == 12;

  (int, int) _neighbor(int delta) {
    final m = DateTime.utc(_year, _month + delta);
    return (m.year, m.month);
  }

  Future<void> _shift(int delta) async {
    if ((delta < 0 && _atStart) || (delta > 0 && _atEnd) || _offset.isAnimating) return;
    await _offset.animateTo(-delta * _width, duration: Timing.monthSlide, curve: Curves.easeOutCubic);
    if (!mounted) return;
    final (year, month) = _neighbor(delta);
    setState(() {
      _year = year;
      _month = month;
    });
    _offset.value = 0;
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_offset.isAnimating) return;
    var next = _offset.value + d.delta.dx;
    if ((next > 0 && _atStart) || (next < 0 && _atEnd)) next = (next * 0.15).clamp(-24.0, 24.0);
    _offset.value = next.clamp(-_width, _width);
  }

  void _dragEnd() {
    if (_offset.isAnimating) return;
    final threshold = _width * Timing.monthSwipeFraction;
    if (_offset.value <= -threshold && !_atEnd) {
      _shift(1);
    } else if (_offset.value >= threshold && !_atStart) {
      _shift(-1);
    } else {
      _offset.animateTo(0, duration: Timing.monthSlide, curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = settingsOf(ref);
    final c = context.colors;
    Widget grid(int year, int month) => _MonthGrid(
      key: ValueKey('$year-$month'),
      year: year,
      month: month,
      weekStartsMonday: settings.weekStartsMonday,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return GestureDetector(
          onHorizontalDragUpdate: _dragUpdate,
          onHorizontalDragEnd: (_) => _dragEnd(),
          onHorizontalDragCancel: _dragEnd,
          child: Column(
            children: [
              _header(context),
              Container(
                color: c.surface,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    for (final w in weekdayLabels(weekStartsMonday: settings.weekStartsMonday))
                      Expanded(
                        child: Center(child: Text(w, style: Theme.of(context).textTheme.labelSmall)),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ClipRect(
                  child: AnimatedBuilder(
                    animation: _offset,
                    builder: (context, _) {
                      final dx = _offset.value;
                      final neighbor = dx < 0 && !_atEnd
                          ? _neighbor(1)
                          : dx > 0 && !_atStart
                          ? _neighbor(-1)
                          : null;
                      return Stack(
                        children: [
                          if (neighbor != null)
                            Positioned.fill(
                              child: Transform.translate(
                                offset: Offset(dx < 0 ? dx + _width : dx - _width, 0),
                                child: grid(neighbor.$1, neighbor.$2),
                              ),
                            ),
                          Positioned.fill(
                            child: Transform.translate(offset: Offset(dx, 0), child: grid(_year, _month)),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: '上個月',
            onPressed: _atStart ? null : () => _shift(-1),
            icon: Icon(Icons.chevron_left_rounded, color: _atStart ? c.muted.withValues(alpha: 0.4) : c.text),
          ),
          // Flexible: on a narrow screen or with large system text the capsules shrink (text ends in …)
          // instead of overflowing.
          Flexible(
            child: PickerButton(
              text: '$_year 年',
              onTap: () async {
                final y = await showChoices<int>(
                  context,
                  title: '年',
                  items: [for (var y = Limits.yearMin; y <= Limits.yearMax; y++) y],
                  selected: _year,
                  label: (y) => '$y 年',
                );
                if (y != null) setState(() => _year = y);
              },
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: PickerButton(
              text: '$_month 月',
              onTap: () async {
                final m = await showChoices<int>(
                  context,
                  title: '月',
                  items: [for (var m = 1; m <= 12; m++) m],
                  selected: _month,
                  label: (m) => '$m 月',
                );
                if (m != null) setState(() => _month = m);
              },
            ),
          ),
          IconButton(
            tooltip: '下個月',
            onPressed: _atEnd ? null : () => _shift(1),
            icon: Icon(Icons.chevron_right_rounded, color: _atEnd ? c.muted.withValues(alpha: 0.4) : c.text),
          ),
        ],
      ),
    );
  }
}

class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({super.key, required this.year, required this.month, required this.weekStartsMonday});

  final int year;
  final int month;
  final bool weekStartsMonday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diaries = ref.watch(monthDiariesProvider((year, month))).value ?? const <Diary>[];
    final byDay = {for (final d in diaries) d.day: d};
    final today = TimeRules.today();
    final c = context.colors;
    return Container(
      color: c.bg,
      child: Column(
        children: [
          for (final week in monthGrid(year, month, weekStartsMonday: weekStartsMonday))
            Expanded(
              child: Row(
                children: [
                  for (final day in week)
                    Expanded(
                      child: day == null
                          ? Container(
                              decoration: BoxDecoration(border: Border.all(color: c.border, width: 0.25)),
                            )
                          : _DayCell(
                              day: day,
                              today: day == today,
                              diary: byDay[day],
                              onTap: () => openDiary(context, day: day, diaryId: byDay[day]?.id),
                            ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.today, required this.diary, required this.onTap});

  final Day day;
  final bool today;
  final Diary? diary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '${day.label}${diary == null ? '，沒有日記' : '，有日記'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: c.border, width: 0.25)),
          padding: const EdgeInsets.fromLTRB(1, 3, 1, 2),
          child: Column(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: today ? BoxDecoration(color: c.todayBg, shape: BoxShape.circle) : null,
                child: Text(
                  '${day.day}',
                  style: weight(
                    t.bodySmall!.copyWith(fontSize: 12, color: today ? c.todayText : c.text2),
                    today ? 700 : 400,
                  ),
                ),
              ),
              if (diary != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    // Shrinks instead of overflowing on small screens or large system font sizes.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(color: c.diaryDot, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 3),
                          Text('日記', style: t.labelSmall!.copyWith(fontSize: 11, color: c.text)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
