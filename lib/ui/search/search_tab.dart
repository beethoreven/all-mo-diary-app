import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/text.dart';
import '../../domain/diary.dart';
import '../../domain/search.dart';
import '../../state/providers.dart';
import '../list/diary_list.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Tab 3: search. Scope menu (全部／標題／內文), a one-line text box, and a magnifier
/// that runs the search; nothing happens while typing.
class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab> {
  final _text = TextEditingController();
  SearchScope _scope = SearchScope.all;

  /// The search that was last run; null before the first one.
  ({String query, SearchScope scope})? _ran;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _run() {
    if (TextRules.clean(_text.text).isEmpty) {
      toast(context, '請輸入要搜尋的文字');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _ran = (query: _text.text, scope: _scope));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ran = _ran;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: c.surface,
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(children: [
          PickerButton(
            text: _scope.label,
            onTap: () async {
              final s = await showChoices<SearchScope>(context,
                  title: '搜尋範圍', items: SearchScope.values, selected: _scope, label: (s) => s.label);
              if (s != null) setState(() => _scope = s);
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _text,
              maxLines: 1,
              maxLength: Limits.searchMaxChars,
              inputFormatters: [TextRules.blockControl],
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              decoration: const InputDecoration(hintText: '搜尋文字', counterText: ''),
            ),
          ),
          IconButton(tooltip: '搜尋', onPressed: _run, icon: const Icon(Icons.search_rounded)),
        ]),
      ),
      Expanded(child: ran == null ? const SizedBox.shrink() : _Results(query: ran.query, scope: ran.scope)),
    ]);
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.scope});

  final String query;
  final SearchScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allDiariesProvider);
    if (!async.hasValue) return const Center(child: CircularProgressIndicator());
    final found = searchDiaries(async.value!, query, scope) ?? const <Diary>[];
    return DiaryList(diaries: found);
  }
}
