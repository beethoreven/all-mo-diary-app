import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/log.dart';
import '../core/time.dart';
import '../data/database.dart';
import '../data/store.dart';
import '../domain/diary.dart';
import 'drive_store.dart';
import 'export_crypto.dart';
import 'export_keys.dart';
import 'sync_engine.dart';

class ExportProblem implements Exception {
  const ExportProblem(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What an import found and did.
class ImportResult {
  const ImportResult(
      {required this.added, required this.replaced, required this.kept, required this.images, required this.videos});

  final int added;
  final int replaced;

  /// Days where the phone already had a diary and the phone's was kept.
  final int kept;
  final int images;
  final int videos;
}

/// How to handle days that already have a diary on the phone.
enum ImportConflict { keepPhone, useImported }

/// Export and import:
///
/// - One file holds every diary on the phone, the user name, the images and the videos, **encrypted as a whole**
///   (export_crypto.dart). It goes to the user's own Drive folder 「全心日記」. The key lives in the
///   app's hidden Drive area (export_keys.dart); we never see it, so only the same Google account can
///   import the file.
/// - The file name has no personal information (a leaked file wouldn't reveal a name).
/// - The file inside is a zip: `data.json` + `images/<id>.jpg` + `videos/<id>.mp4`.
class ExportService {
  ExportService({required this.store, required this.sync, required this.appVersion, required this.cloud});

  final Store store;
  final SyncEngine sync;
  final String Function() appVersion;
  final CloudStore Function({required bool interactive}) cloud;

  static const folder = ['全心日記'];
  /// 2: diaries may hold videos (`videos/` in the zip). An app that only knows 1 refuses the file and
  /// asks for an update, instead of importing diaries whose videos it would drop.
  static const formatVersion = 2;

  /// What export or import is doing now (null when neither runs), for the page to show. Kept here,
  /// not in the page: the work goes on after the page is left, and a page opened again must show it
  /// and not start a second run over the same scratch folder.
  final ValueNotifier<String?> step = ValueNotifier(null);

  /// Starts an export or import (app-wide, one at a time). false when one is already running.
  bool begin(String label) {
    if (step.value != null) return false;
    step.value = label;
    return true;
  }

  void update(String label) {
    if (step.value != null) step.value = label;
  }

  void end() => step.value = null;

  static String fileName(DateTime local) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '全心日記_匯出_${local.year}${two(local.month)}${two(local.day)}_'
        '${two(local.hour)}${two(local.minute)}${two(local.second)}.amd';
  }

  Future<Map<String, Object?>> buildData() async {
    final settings = await store.allSettings();
    final rows = (await store.allDiaryRows()).where((r) => !r.deleted).toList()..sort((a, b) => a.day.compareTo(b.day));
    return {
      'format_version': formatVersion,
      'user_name': settings[Keys.userName],
      'diaries': [
        for (final r in rows)
          {'id': r.id, 'day': r.day, 'title': r.title, 'body': r.body, 'created_at': r.createdAt, 'updated_at': r.updatedAt},
      ],
    };
  }

  /// Exports to the user's Drive. Returns the file name. [tmpDir] is a scratch folder.
  Future<String> export(Directory tmpDir) async {
    final drive = cloud(interactive: true);
    final key = await ExportKeys(drive).getOrCreate();
    final data = await buildData();
    await tmpDir.create(recursive: true);
    final zipFile = File(p.join(tmpDir.path, 'export.zip'));
    final encoder = ZipFileEncoder()..create(zipFile.path);
    try {
      final json = utf8.encode(jsonEncode(data));
      encoder.addArchiveFile(ArchiveFile('data.json', json.length, json));
      final images = <String>{}, videos = <String>{};
      for (final d in data['diaries']! as List) {
        final body = (d as Map)['body'] as String;
        images.addAll(DiaryBody.imageIds(body));
        videos.addAll(DiaryBody.videoIds(body));
      }
      for (final id in images) {
        final file = await sync.resolveImage(id);
        if (file == null) {
          throw const ExportProblem('有圖片只在雲端、現在下載不到，請確認網路後再試');
        }
        await encoder.addFile(file, 'images/$id.jpg');
      }
      for (final id in videos) {
        final file = await sync.resolveVideo(id);
        if (file == null) {
          throw const ExportProblem('有影片只在雲端、現在下載不到，請確認網路後再試');
        }
        // Stored, not compressed again: an MP4 is already compressed, and deflating tens of
        // megabytes per video would only make the export slower.
        await encoder.addFile(file, 'videos/$id.mp4', ZipFileEncoder.store);
      }
    } finally {
      await encoder.close();
    }
    final name = fileName(TimeRules.now().toLocal());
    final out = File(p.join(tmpDir.path, name));
    final header = AmdHeader(
      formatVersion: formatVersion,
      appVersion: appVersion(),
      exportedAt: DateTime.now().toUtc().toIso8601String(),
      keyId: key.id,
      noncePrefix: base64.encode(AmdCrypto.randomBytes(8)),
    );
    await AmdCrypto.encryptFile(plain: zipFile, out: out, header: header, key: key.bytes);
    await zipFile.delete();
    final folderId = await drive.folder(folder);
    await drive.upload(folderId, name, out.openRead(), await out.length(), 'application/octet-stream');
    await out.delete();
    AppLog.info('export.done', {'diaries': (data['diaries']! as List).length});
    return name;
  }

  /// Reads an export file. Returns the parsed data and the folders holding its images and videos.
  Future<({Map<String, Object?> data, Directory images, Directory videos})> open(File file, Directory tmpDir) async {
    final parsed = await AmdCrypto.readHeader(file);
    if (parsed == null) throw const ExportProblem('這不是全心日記的匯出檔');
    final (header, _) = parsed;
    if (header.formatVersion > formatVersion) throw const ExportProblem('這個檔案是新版 App 匯出的，請先更新 App');
    final key = await ExportKeys(cloud(interactive: true)).find(header.keyId);
    if (key == null) throw const ExportProblem('這個檔案是用另一個 Google 帳號匯出的，請改用匯出時的帳號登入');
    await tmpDir.create(recursive: true);
    final zipFile = File(p.join(tmpDir.path, 'import.zip'));
    try {
      await AmdCrypto.decryptFile(amd: file, out: zipFile, key: key.bytes);
    } on AmdCorrupted {
      throw const ExportProblem('檔案損壞或被修改過，無法匯入');
    }
    final imagesDir = Directory(p.join(tmpDir.path, 'images'));
    final videosDir = Directory(p.join(tmpDir.path, 'videos'));
    await imagesDir.create(recursive: true);
    await videosDir.create(recursive: true);
    Map<String, Object?>? data;
    final input = InputFileStream(zipFile.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final entry in archive) {
        if (!entry.isFile || entry.name.contains('..')) continue;
        if (entry.name == 'data.json') {
          data = (jsonDecode(utf8.decode(entry.content as List<int>)) as Map).cast<String, Object?>();
        } else if (entry.name.startsWith('images/') && entry.name.endsWith('.jpg')) {
          await File(p.join(imagesDir.path, p.basename(entry.name))).writeAsBytes(entry.content as List<int>);
        } else if (entry.name.startsWith('videos/') && entry.name.endsWith('.mp4')) {
          // Straight to a file: a video is tens of megabytes.
          final out = OutputFileStream(p.join(videosDir.path, p.basename(entry.name)));
          try {
            entry.writeContent(out);
          } finally {
            await out.close();
          }
        }
      }
    } finally {
      await input.close();
    }
    await zipFile.delete();
    if (data == null || data['format_version'] is! int || data['diaries'] is! List) {
      throw const ExportProblem('檔案內容不完整，無法匯入');
    }
    return (data: data, images: imagesDir, videos: videosDir);
  }

  /// Days in [data] where the phone already has a different diary.
  Future<List<Day>> conflicts(Map<String, Object?> data) async {
    final out = <Day>[];
    for (final d in (data['diaries']! as List).cast<Map>()) {
      final day = Day.parse(d['day'] as String);
      final mine = await store.diaryOn(day);
      if (mine != null && mine.id != d['id']) out.add(day);
    }
    return out;
  }

  /// Merges the imported diaries. Same diary (same id): the newer change wins. A different diary on a
  /// day that has one: [conflict] decides. Imported diaries upload with the next sync.
  Future<ImportResult> apply(Map<String, Object?> data, Directory images, Directory videos, ImportConflict conflict) async {
    var added = 0, replaced = 0, kept = 0, imageCount = 0, videoCount = 0;
    for (final d in (data['diaries']! as List).cast<Map>()) {
      final id = d['id'], dayText = d['day'], updated = d['updated_at'];
      if (id is! String || dayText is! String || updated is! int) continue;
      final body = d['body'] is String ? d['body'] as String : DiaryBody.empty;
      final row = DiaryRow(
        id: id,
        day: dayText,
        title: d['title'] is String ? d['title'] as String : '',
        body: body,
        bodyPlain: DiaryBody.plainText(body),
        createdAt: d['created_at'] is int ? d['created_at'] as int : updated,
        updatedAt: updated,
        deleted: false,
        dirty: true,
      );
      final mineSameId = await store.byId(id);
      if (mineSameId != null) {
        if (mineSameId.updatedAt >= updated) continue;
      }
      final onDay = await store.diaryOn(Day.parse(dayText));
      final replacing = onDay != null && onDay.id != id;
      if (replacing && conflict == ImportConflict.keepPhone) {
        kept++;
        continue;
      }
      for (final imageId in DiaryBody.imageIds(body)) {
        if (await _bringIn(imageId, MediaKind.image, images)) imageCount++;
      }
      for (final videoId in DiaryBody.videoIds(body)) {
        if (await _bringIn(videoId, MediaKind.video, videos)) videoCount++;
      }
      // Replacing is one step: the phone's diary is never deleted without the imported one taking its day.
      await store.db.transaction(() async {
        if (replacing) await store.tombstone(onDay.id);
        await store.db.into(store.db.diaries).insertOnConflictUpdate(row);
      });
      replacing ? replaced++ : added++;
    }
    // Images and videos of replaced diaries are no longer used.
    if (replaced > 0) await store.cleanupMedia();
    final name = data['user_name'];
    if (name is String && name.trim().isNotEmpty && await store.getSetting(Keys.userName) == null) {
      await store.setSetting(Keys.userName, name);
    }
    AppLog.info('import.done',
        {'added': added, 'replaced': replaced, 'kept': kept, 'images': imageCount, 'videos': videoCount});
    return ImportResult(added: added, replaced: replaced, kept: kept, images: imageCount, videos: videoCount);
  }

  /// Copies one image or video of an export onto the phone, unless the phone (or its cloud) already
  /// has it. true when it was copied.
  Future<bool> _bringIn(String id, MediaKind kind, Directory from) async {
    final src = File(p.join(from.path, '$id.${kind.ext}'));
    final dst = store.mediaFile(id, kind);
    if (!await src.exists() || await dst.exists() || await store.mediaRow(id) != null) return false;
    await dst.parent.create(recursive: true);
    // Under a temporary name until complete: a half-copied file at the real name would be shown
    // (and uploaded) as if it were whole.
    final tmp = File('${dst.path}.part');
    await src.copy(tmp.path);
    await tmp.rename(dst.path);
    await store.addMedia(id, kind);
    return true;
  }
}
