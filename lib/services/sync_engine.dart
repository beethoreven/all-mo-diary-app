import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/log.dart';
import '../core/time.dart';
import '../data/database.dart';
import '../data/store.dart';
import '../domain/diary.dart';
import 'auth_service.dart';
import 'drive_store.dart';

abstract final class SyncKeys {
  /// 「日記與雲端同步」 (spec §8): '1' when on.
  static const diaries = 'sync_diaries';

  /// 「圖片存到雲端」: '1' when on.
  static const images = 'sync_images';

  /// The Google account (sub) the cloud data belongs to.
  static const account = 'sync_account';
  static const lastOk = 'sync_last_ok';
  static const lastError = 'sync_last_error';

  /// When the user name was last changed on this phone (ms), to compare with the cloud copy.
  static const profileUpdatedAt = 'profile_updated_at';
}

enum SyncState { idle, running, ok, error }

/// Thrown when turning a cloud switch on or off can't proceed; the message is for the user.
class SyncProblem implements Exception {
  const SyncProblem(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cloud backup (spec §8). Two switches, as in mama-fufood:
///
/// - **日記與雲端同步**: every diary is one file in the app's hidden Drive area (`drive.appdata`),
///   `amd_diary_<id>.json`, with appProperties u (last change, ms), d (deleted) and day, so a
///   listing alone tells what changed. The user name is `amd_profile.json`. Text and formatting stay
///   on the phone too (spec §8: the phone keeps a full copy).
/// - **圖片存到雲端**: images go to the visible folder 「全心日記/圖片」 as `<id>.jpg`; once the cloud
///   copy's MD5 matches, the phone's copy is deleted and later downloads to the cache on demand.
///
/// Rules carried from mama-fufood: deleting leaves a tombstone so another phone can't bring a diary
/// back; nothing on the phone is deleted unless the cloud step it depends on verifiably succeeded.
/// Two phones editing the same diary at once is out of scope for now (spec §8): the newer change wins.
class SyncEngine extends ChangeNotifier {
  SyncEngine({required this.store, required this.auth, required CloudStore Function({required bool interactive}) cloud})
      : _cloud = cloud; // ignore: prefer_initializing_formals

  final Store store;
  final AuthService auth;
  final CloudStore Function({required bool interactive}) _cloud;

  static const _diaryPrefix = 'amd_diary_';
  static const _profileName = 'amd_profile.json';
  static const imageFolder = ['全心日記', '圖片'];

  SyncState state = SyncState.idle;
  String? lastError;
  bool _again = false;
  DateTime? _lastRun;
  Timer? _retry;
  int _retries = 0;
  DateTime _retryWindow = DateTime.now();

  /// A sync pass or a switch change holds the engine; only one at a time. ★ A switch change must not
  /// overlap a pass: turning images off brings the phone copies back while a pass (started by
  /// returning to the app, the retry timer or saving a diary) would free them again, leaving the
  /// switch off with images only in the cloud (known-issue-check #48).
  bool _held = false;
  Completer<void>? _released;

  Future<void> _hold() async {
    while (_held) {
      await (_released ??= Completer<void>()).future;
    }
    _held = true;
  }

  void _release() {
    _held = false;
    final waiting = _released;
    _released = null;
    waiting?.complete();
  }

  /// Runs a switch change while holding the engine. The screen shows 「正在同步」 meanwhile, so the
  /// switches and 「現在同步」 stay disabled even on a settings page opened again.
  Future<void> _switching(Future<void> Function() change) async {
    await _hold();
    final before = state;
    state = SyncState.running;
    notifyListeners();
    try {
      await change();
    } finally {
      if (state == SyncState.running) state = before == SyncState.running ? SyncState.idle : before;
      _release();
      notifyListeners();
    }
  }

  Future<bool> _on(String key) async => await store.getSetting(key) == '1';

  Future<bool> get diariesOn => _on(SyncKeys.diaries);

  Future<bool> get imagesOn => _on(SyncKeys.images);

  // ── Switches ───────────────────────────────────────────────

  /// Turns 「日記與雲端同步」 on or off. Turning on asks for Drive access (a user tap) and binds the
  /// cloud data to the signed-in account; every diary on the phone is then uploaded once.
  Future<void> setDiariesOn(bool on) async {
    if (!on) {
      await store.setSetting(SyncKeys.diaries, null);
      AppLog.info('sync.diaries_off');
      notifyListeners();
      return;
    }
    await _switching(() async {
      await _bindAccount();
      await store.markAllDirty();
      await store.setSetting(SyncKeys.diaries, '1');
      AppLog.info('sync.diaries_on');
    });
    _again = false; // the pass below covers anything asked for meanwhile
    await syncNow(interactive: true);
  }

  /// Turns 「圖片存到雲端」 on or off. Turning off first downloads every cloud-only image back to the
  /// phone; it only switches off once all of them are back (otherwise they'd be unreachable).
  Future<void> setImagesOn(bool on) async {
    if (on) {
      await _switching(() async {
        await _bindAccount();
        await store.setSetting(SyncKeys.images, '1');
        AppLog.info('sync.images_on');
      });
      _again = false;
      await syncNow(interactive: true);
      return;
    }
    try {
      await _switching(() async {
        final cloud = _cloud(interactive: true);
        for (final row in await store.images()) {
          if (row.hasLocal) continue;
          await _bringBack(cloud, row);
          await store.setImageLocal(row.id, true);
        }
        await store.setSetting(SyncKeys.images, null);
        AppLog.info('sync.images_off');
      });
    } finally {
      // A pass asked for while switching (e.g. a diary saved meanwhile) runs now.
      if (_again) {
        _again = false;
        unawaited(syncNow());
      }
    }
  }

  /// Puts a cloud-only image back on the phone. Written to a temporary file and renamed only when
  /// complete: a half-downloaded file at the real path would be shown (and exported) instead of the
  /// cloud copy (known-issue-check #47).
  Future<void> _bringBack(CloudStore cloud, ImageRow row) async {
    final target = store.imageFile(row.id);
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.part');
    try {
      final cached = store.cachedImageFile(row.id);
      if (await cached.exists()) {
        await cached.copy(tmp.path);
      } else {
        final fileId = row.cloudFileId;
        if (fileId == null) throw const SyncProblem('有圖片找不到雲端的那一份，請稍後再試');
        await cloud.downloadToFile(fileId, tmp);
      }
      await tmp.rename(target.path);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }

  Future<void> _bindAccount() async {
    final user = auth.user;
    if (user == null) throw const SyncProblem('請先用 Google 帳號登入');
    // Asks for Drive access now, while the user is looking (never from a background sync).
    try {
      await auth.driveAccessToken(interactive: true);
    } on DriveNotAuthorized {
      throw const SyncProblem('需要雲端硬碟的權限才能開啟');
    }
    final previous = await store.getSetting(SyncKeys.account);
    if (previous != null && previous != user.sub && (await store.images()).any((r) => !r.hasLocal)) {
      throw const SyncProblem('有圖片只存在另一個 Google 帳號的雲端硬碟。請先登入原本的帳號，關閉「圖片存到雲端」把圖片下載回手機。');
    }
    // Another account's Drive: forget where images were stored there; they upload again.
    if (previous != user.sub) await store.forgetImageCloud();
    await store.setSetting(SyncKeys.account, user.sub);
  }

  // ── Running ────────────────────────────────────────────────

  /// On opening the app or returning to it: at most once a minute.
  Future<void> maybeSync() async {
    final last = _lastRun;
    if (last != null && DateTime.now().difference(last) < Timing.syncMinInterval) return;
    await syncNow();
  }

  /// One sync pass. Never shows a Google screen unless [interactive] (a user tap).
  Future<void> syncNow({bool interactive = false}) async {
    // Taken before the first await, so two callers can't both start a pass.
    if (_held) {
      _again = true;
      return;
    }
    _held = true;
    try {
      final diaries = await diariesOn, images = await imagesOn;
      if (!diaries && !images) return;
      final user = auth.user;
      if (user == null) return;
      if (await store.getSetting(SyncKeys.account) != user.sub) {
        _fail('目前登入的帳號跟雲端同步的帳號不同。請換回原本的帳號，或把雲端同步關掉再打開，改用這個帳號。');
        return;
      }
      state = SyncState.running;
      _lastRun = DateTime.now();
      notifyListeners();
      try {
        final cloud = _cloud(interactive: interactive);
        if (diaries) await _syncDiaries(cloud);
        if (images) await _syncImages(cloud);
        state = SyncState.ok;
        lastError = null;
        _retries = 0;
        await store.setSetting(SyncKeys.lastOk, '${DateTime.now().millisecondsSinceEpoch}');
        await store.setSetting(SyncKeys.lastError, null);
        AppLog.info('sync.ok');
      } on DriveNotAuthorized {
        _fail('需要雲端硬碟的權限，請到 App 設定按「現在同步」');
      } on NotSignedIn {
        _fail('請先用 Google 帳號登入');
      } on CloudError catch (e) {
        _fail(e.message);
        _scheduleRetry();
      } catch (e, st) {
        AppLog.error('sync.error', e, st);
        _fail('同步沒有成功，稍後會自動重試');
        _scheduleRetry();
      } finally {
        if (state == SyncState.running) state = SyncState.error;
      }
    } finally {
      _release();
      notifyListeners();
    }
    if (_again) {
      _again = false;
      await syncNow();
    }
  }

  void _fail(String message) {
    state = SyncState.error;
    lastError = message;
    unawaited(store.setSetting(SyncKeys.lastError, message));
    AppLog.warn('sync.failed');
    notifyListeners();
  }

  /// Every 5 minutes after a failure, at most 10 times per half day, while the app is open.
  void _scheduleRetry() {
    if (DateTime.now().difference(_retryWindow) > const Duration(hours: 12)) {
      _retryWindow = DateTime.now();
      _retries = 0;
    }
    if (_retries >= Timing.syncRetriesPerHalfDay || (_retry?.isActive ?? false)) return;
    _retries++;
    _retry = Timer(Timing.syncRetryInterval, () => unawaited(syncNow()));
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  // ── Diaries ────────────────────────────────────────────────

  static Map<String, Object?> _encode(DiaryRow r) => {
        'v': 1,
        'id': r.id,
        'day': r.day,
        'title': r.title,
        'body': r.body,
        'created_at': r.createdAt,
        'updated_at': r.updatedAt,
        'deleted': r.deleted,
      };

  static DiaryRow? _decode(Map<String, Object?> m) {
    if (m['v'] != 1 || m['id'] is! String || m['day'] is! String || m['updated_at'] is! int) return null;
    final body = m['body'] is String ? m['body'] as String : DiaryBody.empty;
    return DiaryRow(
      id: m['id'] as String,
      day: m['day'] as String,
      title: m['title'] is String ? m['title'] as String : '',
      body: body,
      bodyPlain: DiaryBody.plainText(body),
      createdAt: m['created_at'] is int ? m['created_at'] as int : m['updated_at'] as int,
      updatedAt: m['updated_at'] as int,
      deleted: m['deleted'] == true,
      dirty: false,
    );
  }

  static Map<String, String> _props(DiaryRow r) => {'u': '${r.updatedAt}', 'd': r.deleted ? '1' : '0', 'day': r.day};

  Future<void> _syncDiaries(CloudStore cloud) async {
    final files = await cloud.listAppData('amd_');
    final cloudDiaries = <String, CloudFile>{};
    CloudFile? profile;
    for (final f in files) {
      if (f.name == _profileName) profile = f;
      if (f.name.startsWith(_diaryPrefix) && f.name.endsWith('.json')) {
        cloudDiaries[f.name.substring(_diaryPrefix.length, f.name.length - 5)] = f;
      }
    }
    final local = {for (final r in await store.allDiaryRows()) r.id: r};
    var down = 0, up = 0, skipped = 0;

    // Cloud → phone: anything newer in the cloud than here.
    for (final e in cloudDiaries.entries) {
      final cloudU = int.tryParse(e.value.props['u'] ?? '') ?? 0;
      final mine = local[e.key];
      if (mine != null && mine.updatedAt >= cloudU) continue;
      final raw = await cloud.readAppData(e.value.id);
      final remote = _decode((jsonDecode(utf8.decode(raw)) as Map).cast<String, Object?>());
      if (remote == null) continue;
      if (await store.applyRemote(remote)) {
        down++;
        local[remote.id] = remote;
      } else {
        skipped++;
        AppLog.warn('sync.day_taken');
      }
    }

    // Phone → cloud: changed here and newer than the cloud copy.
    for (final r in local.values.where((r) => r.dirty)) {
      final existing = cloudDiaries[r.id];
      final cloudU = int.tryParse(existing?.props['u'] ?? '') ?? -1;
      if (cloudU > r.updatedAt) continue;
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(_encode(r))));
      if (existing == null) {
        await cloud.createAppData('$_diaryPrefix${r.id}.json', bytes, props: _props(r));
      } else {
        await cloud.updateAppData(existing.id, bytes, props: _props(r));
      }
      await store.markClean(r.id, r.updatedAt);
      up++;
    }
    await _syncProfile(cloud, profile);
    AppLog.info('sync.diaries', {'down': down, 'up': up, 'skipped': skipped});
  }

  /// The user name (spec §1.1: synced with the diaries). The newer change wins.
  Future<void> _syncProfile(CloudStore cloud, CloudFile? profile) async {
    final name = await store.getSetting(Keys.userName);
    final mineAt = int.tryParse(await store.getSetting(SyncKeys.profileUpdatedAt) ?? '') ?? 0;
    final cloudAt = int.tryParse(profile?.props['u'] ?? '') ?? -1;
    if (profile != null && cloudAt > mineAt) {
      final m = (jsonDecode(utf8.decode(await cloud.readAppData(profile.id))) as Map).cast<String, Object?>();
      final cloudName = m['user_name'];
      if (cloudName is String && cloudName.trim().isNotEmpty) {
        await store.setSetting(Keys.userName, cloudName);
        await store.setSetting(SyncKeys.profileUpdatedAt, '$cloudAt');
      }
    } else if (name != null && (profile == null || cloudAt < mineAt)) {
      final at = mineAt == 0 ? TimeRules.nowMs() : mineAt;
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode({'v': 1, 'user_name': name})));
      if (profile == null) {
        await cloud.createAppData(_profileName, bytes, props: {'u': '$at'});
      } else {
        await cloud.updateAppData(profile.id, bytes, props: {'u': '$at'});
      }
      await store.setSetting(SyncKeys.profileUpdatedAt, '$at');
    }
  }

  // ── Images ─────────────────────────────────────────────────

  Future<void> _syncImages(CloudStore cloud) async {
    await store.adoptImageFiles();
    final folder = await cloud.folder(imageFolder);
    final used = await store.usedImageIds();
    var uploaded = 0, removed = 0;
    for (final row in await store.images()) {
      final inDiary = used.diaries.contains(row.id);
      final inDraft = used.drafts.contains(row.id);
      if (row.cloudFileId == null && row.hasLocal && inDiary) {
        await _upload(cloud, folder, row);
        uploaded++;
      } else if (row.cloudFileId != null && row.hasLocal && inDiary && !inDraft) {
        // Already in the cloud (e.g. switched off and on again): just free the phone's copy.
        await _freeLocal(row.id, row.cloudMd5);
      } else if (row.cloudFileId != null && !inDiary && !inDraft) {
        // No diary uses it any more: remove the cloud copy, then the row.
        await cloud.delete(row.cloudFileId!);
        await store.cachedImageFile(row.id).delete().catchError((_) => File(''));
        if (!row.hasLocal || !await store.imageFile(row.id).exists()) await store.deleteImageRow(row.id);
        removed++;
      }
    }
    AppLog.info('sync.images', {'up': uploaded, 'removed': removed});
  }

  Future<void> _upload(CloudStore cloud, String folder, ImageRow row) async {
    final file = store.imageFile(row.id);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final md5Local = md5.convert(bytes).toString();
    final uploaded = await cloud.upload(folder, '${row.id}.jpg', Stream.value(bytes), bytes.length, 'image/jpeg');
    if (uploaded.md5 != null && uploaded.md5 != md5Local) {
      // Corrupted on the way: remove the bad copy, keep ours, try again next time.
      AppLog.warn('sync.image_md5_mismatch');
      await cloud.delete(uploaded.id);
      return;
    }
    await store.setImageCloud(row.id, fileId: uploaded.id, md5: md5Local);
    await _freeLocal(row.id, md5Local);
  }

  /// Deletes the phone's copy only when it matches what's in the cloud.
  Future<void> _freeLocal(String id, String? cloudMd5) async {
    final file = store.imageFile(id);
    if (!await file.exists()) return store.setImageLocal(id, false);
    final mine = md5.convert(await file.readAsBytes()).toString();
    if (cloudMd5 == null || mine != cloudMd5) return;
    // Keep a cached copy so the image still shows right away on this phone.
    final cached = store.cachedImageFile(id);
    await cached.parent.create(recursive: true);
    await file.copy(cached.path);
    await file.delete();
    await store.setImageLocal(id, false);
  }

  // ── Showing images ─────────────────────────────────────────

  final Map<String, Future<File?>> _resolving = {};

  /// The file to show for an image: the phone's copy, the cache, or a fresh download from the cloud.
  /// null when it's only in the cloud and can't be fetched now (offline, signed out, timed out).
  Future<File?> resolveImage(String id) async {
    final local = store.imageFile(id);
    if (await local.exists()) return local;
    final cached = store.cachedImageFile(id);
    if (await cached.exists()) return cached;
    // One download per image at a time. ★ Block body: an arrow returning map.remove(id) would return
    // the stored future itself, and the future would wait on itself forever (known-issue-check #39).
    return _resolving.putIfAbsent(id, () => _download(id).whenComplete(() {
          _resolving.remove(id);
        }));
  }

  Future<File?> _download(String id) async {
    if (auth.user == null) return null;
    try {
      final cloud = _cloud(interactive: false);
      final row = await store.image(id);
      var fileId = row?.cloudFileId;
      if (fileId == null) {
        // Uploaded by another phone: find it by name in the folder. Only looks the folder up: showing
        // a diary must never create 「全心日記/圖片」 in the user's Drive.
        final folder = await cloud.findFolder(imageFolder);
        fileId = folder == null ? null : (await cloud.findByName(folder, '$id.jpg'))?.id;
      }
      if (fileId == null) return null;
      final target = store.cachedImageFile(id);
      await target.parent.create(recursive: true);
      // A temporary file of its own per attempt: on timeout the download is abandoned but keeps
      // writing, and with a shared name it would write into the next attempt's file — after that
      // one was renamed, into the cached image itself (known-issue-check #47).
      final tmp = File('${target.path}.${Store.newId()}.part');
      try {
        await cloud.downloadToFile(fileId, tmp).timeout(ImageSpec.loadTimeout);
        await tmp.rename(target.path);
      } finally {
        if (await tmp.exists()) await tmp.delete();
      }
      return target;
    } catch (e) {
      AppLog.warn('sync.image_download_failed', {'type': e.runtimeType.toString()});
      return null;
    }
  }
}
