import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/text.dart';
import '../../core/time.dart';
import '../../data/database.dart';
import '../../data/store.dart';
import '../../domain/diary.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'body_editor.dart';
import 'toolbar.dart';

/// Opens the diary screen over everything, bottom bar included (spec §6, §7).
/// [diaryId] null → a new diary for [day]; otherwise that diary, for viewing.
/// [resume] continues an unsaved draft found at start-up.
Future<void> openDiary(BuildContext context, {required Day day, String? diaryId, DraftRow? resume}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => DiaryPage(day: day, diaryId: diaryId, resume: resume),
    ));

enum _Mode { create, view, edit }

class DiaryPage extends ConsumerStatefulWidget {
  const DiaryPage({super.key, required this.day, this.diaryId, this.resume});

  final Day day;
  final String? diaryId;
  final DraftRow? resume;

  @override
  ConsumerState<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends ConsumerState<DiaryPage> with WidgetsBindingObserver {
  late final Store _store = ref.read(storeProvider);
  final _title = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  QuillController? _body;
  Timer? _draftTimer;

  _Mode _mode = _Mode.create;
  Diary? _saved;
  late Day _day = widget.day;
  bool _loading = true;
  bool _busy = false;

  /// A save is in flight. Draft writes stop meanwhile: a draft written after the save's
  /// transaction deleted it would be offered again as "unsaved" next launch.
  bool _saving = false;

  /// What the content was when editing started; "changed" compares against this.
  String _baseTitle = '';
  String _baseBody = DiaryBody.empty;
  late Day _baseDay = widget.day;
  String? _lastDraftSig;

  bool get _editing => _mode != _Mode.view;

  String get _draftKey => _mode == _Mode.edit ? Store.editDraftKey(_saved!.id) : Store.newDraftKey(_day);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftTimer?.cancel();
    _body?.dispose();
    _title.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app (home button, a phone call): write the draft now rather than in 3 seconds.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) _writeDraft();
  }

  Future<void> _load() async {
    final resume = widget.resume;
    final id = widget.diaryId ?? resume?.diaryId;
    if (id != null) {
      final diary = await _store.byId(id);
      if (!mounted) return;
      if (diary == null) {
        Navigator.pop(context);
        toast(context, '這篇日記已經不存在了');
        return;
      }
      _saved = diary;
      if (resume != null) {
        _enter(_Mode.edit, title: resume.title, body: resume.body, day: Day.parse(resume.day));
      } else {
        _enter(_Mode.view, title: diary.title, body: diary.body, day: diary.day);
      }
    } else if (resume != null) {
      _enter(_Mode.create, title: resume.title, body: resume.body, day: Day.parse(resume.day));
    } else {
      _enter(_Mode.create, title: '', body: DiaryBody.empty, day: widget.day);
      await _offerDraft(Store.newDraftKey(widget.day));
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Switches mode and loads content. In create/edit the baseline is the saved diary (or empty).
  void _enter(_Mode mode, {required String title, required String body, required Day day}) {
    _body?.dispose();
    _mode = mode;
    _day = day;
    _title.text = title;
    _body = controllerFor(body, readOnly: mode == _Mode.view);
    _baseTitle = _saved?.title ?? '';
    _baseBody = _saved?.body ?? DiaryBody.empty;
    _baseDay = _saved?.day ?? widget.day;
    _lastDraftSig = null;
    _draftTimer?.cancel();
    if (mode != _Mode.view) _draftTimer = Timer.periodic(Timing.draftSaveInterval, (_) => _writeDraft());
    if (mounted) setState(() {});
  }

  /// Asks to continue an unsaved draft for this diary, if there is one.
  Future<void> _offerDraft(String key) async {
    final draft = await _store.draft(key);
    if (draft == null || !mounted) return;
    final resume = await confirmDialog(context,
        message: '要接著寫上次沒儲存的內容嗎？', confirm: '接著寫', cancel: '不要');
    if (!mounted) return;
    if (resume) {
      _enter(_mode, title: draft.title, body: draft.body, day: Day.parse(draft.day));
    } else {
      await _store.deleteDraft(key);
    }
  }

  // ── State of the content ────────────────────────────────────

  String get _bodyNow => _body == null ? DiaryBody.empty : bodyOf(_body!);

  /// New diary: anything written. Edit: anything different from the saved diary.
  bool get _hasUnsaved {
    if (!_editing || _body == null) return false;
    if (_mode == _Mode.create) {
      return TextRules.clean(_title.text).isNotEmpty || DiaryBody.hasContent(_bodyNow);
    }
    return _title.text != _baseTitle || _bodyNow != _baseBody || _day != _baseDay;
  }

  Future<void> _writeDraft() async {
    if (!_editing || _body == null || _saving) return;
    final key = _draftKey;
    final body = _bodyNow;
    final sig = '$_day|${_title.text}|$body';
    if (sig == _lastDraftSig) return;
    _lastDraftSig = sig;
    if (_hasUnsaved) {
      await _store.saveDraft(key: key, diaryId: _saved?.id, day: _day, title: _title.text, body: body);
    } else {
      await _store.deleteDraft(key);
    }
  }

  // ── Buttons ─────────────────────────────────────────────────

  Future<void> _save() async {
    if (_busy) return;
    if (TextRules.clean(_title.text).isEmpty) {
      toast(context, '請輸入標題');
      return;
    }
    setState(() => _busy = true);
    _saving = true;
    try {
      final saved = await _store.save(
        DiaryInput(id: _saved?.id, day: _day, title: _title.text, body: _bodyNow),
        draftKey: _draftKey,
      );
      if (!mounted) return;
      _saved = saved;
      _enter(_Mode.view, title: saved.title, body: saved.body, day: saved.day);
      toast(context, '已儲存');
    } on InputProblem catch (e) {
      if (mounted) toast(context, e.message);
    } catch (_) {
      // Any other failure (e.g. the database): say so; the writing stays on screen and in the draft.
      if (mounted) toast(context, '儲存沒有成功，請再試一次');
    } finally {
      // Every exit clears the flags, so a failed save never leaves autosave switched off
      // (the draft timer itself keeps running while still editing).
      _saving = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 『取消』 and the system back gesture while writing.
  Future<void> _cancel() async {
    if (_hasUnsaved) {
      final discard = await confirmDialog(context,
          message: _mode == _Mode.create ? '要放棄這篇還沒儲存的日記嗎？' : '要放棄這次的修改嗎？', confirm: '放棄', cancel: '繼續寫');
      if (!discard || !mounted) return;
    }
    _draftTimer?.cancel();
    await _store.deleteDraft(_draftKey);
    if (!mounted) return;
    if (_mode == _Mode.edit) {
      _enter(_Mode.view, title: _saved!.title, body: _saved!.body, day: _saved!.day);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _startEdit() async {
    final saved = _saved!;
    _enter(_Mode.edit, title: saved.title, body: saved.body, day: saved.day);
    await _offerDraft(Store.editDraftKey(saved.id));
  }

  Future<void> _delete() async {
    final first = await confirmDialog(context, message: '確定要刪除這篇日記嗎？', confirm: '刪除', danger: true);
    if (!first || !mounted) return;
    final typed = await showDialog<bool>(context: context, builder: (_) => const _TypeToDeleteDialog());
    if (typed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await _store.delete(_saved!.id);
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(content: Text('日記已刪除')));
  }

  Future<void> _changeDay(int year, int? month, int? day) async {
    if (month == null || day == null) return;
    final next = Day(year, month, day);
    if (next == _day) return;
    final other = await _store.diaryOn(next);
    if (!mounted) return;
    if (other != null && other.id != _saved?.id) {
      toast(context, '這天已經有日記了');
      return;
    }
    setState(() => _day = next);
  }

  Future<void> _addImage() async {
    final body = _body;
    if (body == null || _busy) return;
    final mq = MediaQuery.of(context);
    final screen = Size(mq.size.width * mq.devicePixelRatio, mq.size.height * mq.devicePixelRatio);
    final at = body.selection;
    setState(() => _busy = true);
    try {
      final image = await ref.read(imageServiceProvider).pick(screen);
      if (image == null || !mounted) return;
      final start = at.isValid ? at.start : body.document.length - 1;
      final length = at.isValid ? at.end - at.start : 0;
      body.replaceText(start, length, CustomBlockEmbed(DiaryBody.imageType, image.encode()),
          TextSelection.collapsed(offset: start + 1));
    } catch (_) {
      if (mounted) toast(context, '加入圖片沒有成功，請再試一次');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Layout ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final body = _body;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_editing) {
          _cancel();
        } else {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: c.surface,
        body: SafeArea(
          child: _loading || body == null
              ? const Center(child: CircularProgressIndicator())
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _dateRow(context),
                  if (_editing) DiaryToolbar(controller: body, onAddImage: _addImage),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: _editing
                        ? TextField(
                            controller: _title,
                            maxLines: 1,
                            maxLength: Limits.titleMaxChars,
                            inputFormatters: [TextRules.blockControl],
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => _focus.requestFocus(),
                            style: weight(t.titleMedium!, 600),
                            decoration: const InputDecoration(hintText: '標題', counterText: ''),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(_title.text, style: weight(t.titleMedium!.copyWith(fontSize: 18), 600)),
                          ),
                  ),
                  Expanded(child: BodyEditor(controller: body, store: _store, focusNode: _focus, scroll: _scroll)),
                ]),
        ),
        // In the bottom bar slot (not the body) so toasts float above the buttons instead of covering them.
        bottomNavigationBar: _loading || body == null ? null : SafeArea(top: false, child: _buttons(context)),
      ),
    );
  }

  Widget _dateRow(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: _mode == _Mode.edit
          ? YearMonthDayPickers(
              year: _day.year,
              month: _day.month,
              day: _day.day,
              yearMin: Limits.yearMin,
              yearMax: Limits.yearMax,
              onChanged: _changeDay,
            )
          : Text(_day.label, textAlign: TextAlign.center, style: weight(t.titleSmall!.copyWith(color: c.text2), 500)),
    );
  }

  Widget _buttons(BuildContext context) {
    final c = context.colors;
    final buttons = _editing
        ? [
            Expanded(child: OutlinedButton(onPressed: _busy ? null : _cancel, child: const Text('取消'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(onPressed: _busy ? null : _save, child: const Text('儲存'))),
          ]
        : [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('返回'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(onPressed: _startEdit, child: const Text('編輯'))),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: c.danger, side: BorderSide(color: c.danger)),
                onPressed: _delete,
                child: const Text('刪除'),
              ),
            ),
          ];
    return Container(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(children: buttons),
    );
  }
}

/// The second delete step: type 「刪除日記」 to really delete (spec §7).
class _TypeToDeleteDialog extends StatefulWidget {
  const _TypeToDeleteDialog();

  static const phrase = '刪除日記';

  @override
  State<_TypeToDeleteDialog> createState() => _TypeToDeleteDialogState();
}

class _TypeToDeleteDialogState extends State<_TypeToDeleteDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ok = _text.text.trim() == _TypeToDeleteDialog.phrase;
    return AlertDialog(
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('刪除後無法復原。\n請輸入「${_TypeToDeleteDialog.phrase}」四個字確認。'),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          autofocus: true,
          maxLines: 1,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: _TypeToDeleteDialog.phrase),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: Colors.white),
          onPressed: ok ? () => Navigator.pop(context, true) : null,
          child: const Text('刪除'),
        ),
      ],
    );
  }
}
