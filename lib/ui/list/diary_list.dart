import 'package:flutter/material.dart';

import '../../domain/diary.dart';
import '../editor/diary_page.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// The result list shared by the filter and search tabs: date and title, oldest
/// first; tapping a row opens that day's diary. Empty → "沒有結果".
class DiaryList extends StatelessWidget {
  const DiaryList({super.key, required this.diaries});

  final List<Diary> diaries;

  @override
  Widget build(BuildContext context) {
    if (diaries.isEmpty) return const NoResults();
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: diaries.length,
      separatorBuilder: (_, _) => Divider(height: 1, indent: 16, endIndent: 16, color: c.border),
      itemBuilder: (context, i) {
        final d = diaries[i];
        return ListTile(
          title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: weight(t.bodyLarge!, 500)),
          subtitle: Text(d.day.label, style: t.bodySmall),
          trailing: Icon(Icons.chevron_right_rounded, color: c.muted),
          onTap: () => openDiary(context, day: d.day, diaryId: d.id),
        );
      },
    );
  }
}
