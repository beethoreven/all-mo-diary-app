import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/time.dart';
import '../../domain/search.dart';
import '../../state/providers.dart';
import '../list/diary_list.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Tab 2: list diaries in a range. Year is required; month defaults to 「不指定」;
/// day can only be picked after a month.
class FilterTab extends ConsumerStatefulWidget {
  const FilterTab({super.key});

  @override
  ConsumerState<FilterTab> createState() => _FilterTabState();
}

class _FilterTabState extends ConsumerState<FilterTab> {
  late DayFilter _filter = DayFilter(year: TimeRules.today().year.clamp(Limits.yearMin, Limits.yearMax));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(prefixDiariesProvider(_filter.prefix));
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: c.surface,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: YearMonthDayPickers(
          year: _filter.year,
          month: _filter.month,
          day: _filter.day,
          allowAnyMonth: true,
          yearMin: Limits.yearMin,
          yearMax: Limits.yearMax,
          onChanged: (y, m, d) => setState(() => _filter = DayFilter(year: y, month: m, day: d)),
        ),
      ),
      Expanded(
        child: async.hasError
            ? Center(child: Text('讀取日記失敗，請重新開啟 App', style: TextStyle(color: c.danger)))
            : !async.hasValue
                ? const Center(child: CircularProgressIndicator())
                : DiaryList(diaries: async.value!),
      ),
    ]);
  }
}
