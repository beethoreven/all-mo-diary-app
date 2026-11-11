import 'package:flutter/material.dart';

import '../theme.dart';

/// A short message at the bottom of the screen.
void toast(BuildContext context, String message, {Duration duration = const Duration(seconds: 2)}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: duration));
}

/// A yes/no question. Returns true only when [confirm] is pressed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String message,
  String confirm = '確定',
  String cancel = '取消',
  bool danger = false,
}) async {
  final c = context.colors;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancel)),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// A list of choices: tapping one picks it, tapping outside closes without a change (spec §8).
Future<T?> showChoices<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required T? selected,
  required String Function(T) label,
}) {
  final initialIndex = selected == null ? 0 : items.indexOf(selected as T).clamp(0, items.length - 1);
  return showDialog<T>(
    context: context,
    builder: (ctx) {
      final c = ctx.colors;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(title, style: Theme.of(ctx).textTheme.titleSmall),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  // Open with the current choice in view.
                  controller: ScrollController(initialScrollOffset: (initialIndex - 2).clamp(0, items.length) * 48.0),
                  itemCount: items.length,
                  itemExtent: 48,
                  itemBuilder: (_, i) {
                    final on = items[i] == selected;
                    return InkWell(
                      onTap: () => Navigator.pop(ctx, items[i]),
                      child: Container(
                        color: on ? c.accentSoft : null,
                        alignment: Alignment.center,
                        child: Text(label(items[i]), style: weight(Theme.of(ctx).textTheme.bodyLarge!, on ? 600 : 400)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

/// The capsule button that opens a choice list (year, month, day…), as in mama-fufood.
class PickerButton extends StatelessWidget {
  const PickerButton({super.key, required this.text, required this.onTap, this.enabled = true, this.compact = false});

  final String text;
  final VoidCallback onTap;
  final bool enabled;

  /// Smaller text and padding, for rows of several capsules that should fit on one line.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: enabled ? c.surface2 : c.surface2.withValues(alpha: 0.4),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 48, minWidth: compact ? 48 : 64),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    style: weight(
                      Theme.of(context).textTheme.bodyLarge!
                          .copyWith(color: enabled ? c.text : c.muted, fontSize: compact ? 14 : null),
                      500,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 2 : 4),
                Icon(Icons.expand_more_rounded, size: compact ? 16 : 18, color: enabled ? c.text2 : c.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Year / month / day capsules. [allowAnyMonth]: the month and day may be "不指定" (the filter tab).
class YearMonthDayPickers extends StatelessWidget {
  const YearMonthDayPickers({
    super.key,
    required this.year,
    required this.month,
    required this.day,
    required this.onChanged,
    this.allowAnyMonth = false,
    this.yearMin = 2020,
    this.yearMax = 2080,
  });

  final int year;
  final int? month;
  final int? day;
  final void Function(int year, int? month, int? day) onChanged;
  final bool allowAnyMonth;
  final int yearMin;
  final int yearMax;

  @override
  Widget build(BuildContext context) {
    final days = month == null ? 31 : DateTime.utc(year, month! + 1, 0).day;
    // Keep the chosen day when the month changes, pulled back to the month's last day if needed.
    int? fitDay(int y, int? m, int? d) => m == null || d == null ? null : d.clamp(1, DateTime.utc(y, m + 1, 0).day);
    // One line: compact capsules, and on a very narrow screen (or with large system text) the row
    // shrinks as a whole rather than wrapping the day onto a second line.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          PickerButton(
            compact: true,
            text: '$year 年',
            onTap: () async {
              final y = await showChoices<int>(
                context,
                title: '年',
                items: [for (var y = yearMin; y <= yearMax; y++) y],
                selected: year,
                label: (y) => '$y 年',
              );
              if (y != null) onChanged(y, month, fitDay(y, month, day));
            },
          ),
          PickerButton(
            compact: true,
            text: month == null ? '月：不指定' : '$month 月',
            onTap: () async {
              final m = await showChoices<int>(
                context,
                title: '月',
                items: [if (allowAnyMonth) 0, for (var m = 1; m <= 12; m++) m],
                selected: month ?? 0,
                label: (m) => m == 0 ? '不指定' : '$m 月',
              );
              if (m == null) return;
              final mm = m == 0 ? null : m;
              onChanged(year, mm, mm == null ? null : fitDay(year, mm, day));
            },
          ),
          PickerButton(
            compact: true,
            enabled: month != null,
            text: day == null ? '日：不指定' : '$day 日',
            onTap: () async {
              final d = await showChoices<int>(
                context,
                title: '日',
                items: [if (allowAnyMonth) 0, for (var d = 1; d <= days; d++) d],
                selected: day ?? 0,
                label: (d) => d == 0 ? '不指定' : '$d 日',
              );
              if (d != null) onChanged(year, month, d == 0 ? null : d);
            },
          ),
        ],
      ),
    );
  }
}

/// The centred, clearly-not-a-button "沒有結果" (spec §4, §5).
class NoResults extends StatelessWidget {
  const NoResults({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Text(
        '沒有結果',
        style: weight(Theme.of(context).textTheme.titleMedium!.copyWith(color: c.muted, fontSize: 18), 500),
      ),
    );
  }
}

/// A card with the standard padding (as mama-fufood).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(12)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: padding, child: child));
}
