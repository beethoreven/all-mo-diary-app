import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as gauth;
import 'package:http/io_client.dart';

import '../core/log.dart';
import 'auth_service.dart';

/// 雲端檔案的基本資料。
class CloudFile {
  const CloudFile({required this.id, required this.name, this.size, this.md5, this.props = const {}});

  final String id;
  final String name;
  final int? size;
  final String? md5;

  /// 檔案的 appProperties(同步用:不必下載內容就知道紀錄的版本)。
  final Map<String, String> props;
}

class CloudError implements Exception {
  const CloudError(this.kind, this.message);

  /// network / unauthorized / not_found / storage_full / other
  final String kind;
  final String message;

  bool get isStorageFull => kind == 'storage_full';

  @override
  String toString() => message;
}

/// 雲端硬碟的操作,包成介面方便測試(測試用 test/services/fake_cloud.dart)。
///
/// - App 專用區(`drive.appdata`,使用者看不到):紀錄同步、匯出檔的金鑰。
/// - 使用者看得到的「全心日記」資料夾(`drive.file`):匯出檔、雲端的圖片
///   (照片放這裡:手機遺失時照片還看得到)。
abstract class CloudStore {
  Future<List<CloudFile>> listAppData(String namePrefix);

  Future<Uint8List> readAppData(String fileId);

  Future<CloudFile> createAppData(String name, Uint8List bytes, {Map<String, String> props = const {}});

  Future<CloudFile> updateAppData(String fileId, Uint8List bytes, {Map<String, String> props = const {}});

  /// 使用者看得到的資料夾(沒有就建立),例如 ['全心日記', '圖片']。
  Future<String> folder(List<String> path);

  /// 只找、不建立:沒有這個資料夾就回 null(顯示日記時不能在使用者的雲端硬碟建資料夾)。
  Future<String?> findFolder(List<String> path);

  Future<CloudFile> upload(String folderId, String name, Stream<List<int>> data, int length, String mime);

  /// 下載到檔案(邊收邊寫,匯出檔可能有幾百 MB,不能整份放進記憶體)。
  /// [onProgress]:已收到的位元組數與總數(雲端沒有回報大小時總數是 null)。
  Future<void> downloadToFile(String fileId, File target, {void Function(int received, int? total)? onProgress});

  Future<CloudFile?> metadata(String fileId);

  /// 在使用者看得到的資料夾裡用檔名找檔案(另一支手機上傳的照片)。
  Future<CloudFile?> findByName(String folderId, String name);

  Future<void> delete(String fileId);
}

class GoogleDriveStore implements CloudStore {
  GoogleDriveStore(this.auth, {required this.interactive});

  final AuthService auth;

  /// true:使用者按了按鈕,沒有權限時可以跳出授權畫面。
  final bool interactive;

  static const _fields = 'id,name,size,md5Checksum,appProperties';
  final Map<String, String> _folderCache = {};

  /// 一般操作(列表、讀寫小檔)的時間上限;上傳、下載大檔另外給長一點
  /// (同步一次只跑一個,一個沒有上限的請求卡住,之後的同步就全部排在它後面)。
  static const _normalTimeout = Duration(seconds: 60);
  static const _transferTimeout = Duration(minutes: 30);

  Future<T> _call<T>(Future<T> Function(drive.DriveApi api) action,
      {bool retried = false, Duration timeout = _normalTimeout}) async {
    // 不跳授權畫面時,拿權杖也要有時間上限(系統沒有回應時不要讓呼叫的人一直等);
    // 要跳畫面時是等使用者操作,不設上限。
    final tokenRequest = auth.driveAccessToken(interactive: interactive);
    final token = interactive ? await tokenRequest : await tokenRequest.timeout(_normalTimeout);
    final client = gauth.authenticatedClient(
      IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 20)),
      gauth.AccessCredentials(
        gauth.AccessToken('Bearer', token, DateTime.now().toUtc().add(const Duration(minutes: 50))),
        null,
        DriveScopes.all,
      ),
      closeUnderlyingClient: true,
    );
    try {
      return await action(drive.DriveApi(client)).timeout(timeout);
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 401 && !retried) {
        await auth.dropDriveToken(token);
        return _call(action, retried: true, timeout: timeout);
      }
      final reason = e.errors.isNotEmpty ? e.errors.first.reason : null;
      AppLog.warn('drive.error', {'status': e.status, 'reason': reason});
      if (e.status == 404) throw const CloudError('not_found', '雲端硬碟上找不到這個檔案');
      if (reason == 'storageQuotaExceeded') throw const CloudError('storage_full', '你的 Google 雲端硬碟空間不足');
      if (e.status == 401 || e.status == 403) throw const CloudError('unauthorized', '雲端硬碟的權限不足，請重新登入');
      throw CloudError('other', '雲端硬碟回應錯誤（${e.status}）');
    } on CloudError {
      rethrow;
    } on NotSignedIn {
      rethrow;
    } on DriveNotAuthorized {
      rethrow;
    } catch (e) {
      AppLog.warn('drive.network_error', {'type': e.runtimeType.toString()});
      throw const CloudError('network', '無法連上 Google 雲端硬碟，請確認網路後再試');
    } finally {
      client.close();
    }
  }

  static CloudFile _file(drive.File f) => CloudFile(
        id: f.id!,
        name: f.name ?? '',
        size: f.size == null ? null : int.tryParse(f.size!),
        md5: f.md5Checksum,
        props: {
          for (final e in (f.appProperties ?? const <String, String?>{}).entries)
            if (e.value != null) e.key: e.value!,
        },
      );

  @override
  Future<List<CloudFile>> listAppData(String namePrefix) => _call((api) async {
        final out = <CloudFile>[];
        String? page;
        do {
          final list = await api.files.list(
            spaces: 'appDataFolder',
            q: "name contains '${namePrefix.replaceAll("'", "\\'")}' and trashed = false",
            pageSize: 1000,
            pageToken: page,
            $fields: 'nextPageToken,files($_fields)',
          );
          // 「contains」是前綴比對(Drive 的規則),這裡再確認一次。
          out.addAll([for (final f in list.files ?? const <drive.File>[]) if ((f.name ?? '').startsWith(namePrefix)) _file(f)]);
          page = list.nextPageToken;
        } while (page != null);
        return out;
      });

  @override
  Future<Uint8List> readAppData(String fileId) => _call((api) async {
        final media = await api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
        final builder = BytesBuilder(copy: false);
        await for (final chunk in media.stream) {
          builder.add(chunk);
        }
        return builder.takeBytes();
      });

  @override
  Future<CloudFile> createAppData(String name, Uint8List bytes, {Map<String, String> props = const {}}) =>
      _call((api) async => _file(await api.files.create(
            drive.File(name: name, parents: ['appDataFolder'], appProperties: props),
            uploadMedia: drive.Media(Stream.value(bytes), bytes.length, contentType: 'application/json'),
            $fields: _fields,
          )));

  @override
  Future<CloudFile> updateAppData(String fileId, Uint8List bytes, {Map<String, String> props = const {}}) =>
      _call((api) async => _file(await api.files.update(
            drive.File(appProperties: props),
            fileId,
            uploadMedia: drive.Media(Stream.value(bytes), bytes.length, contentType: 'application/json'),
            $fields: _fields,
          )));

  /// Folder lookups and creations run one at a time in this app: an export (「全心日記」) and the
  /// first image upload (「全心日記/圖片」) at the same moment would otherwise both create 「全心日記」.
  static Future<void> _folderQueue = Future.value();

  @override
  Future<String> folder(List<String> path) async => (await _folder(path, create: true))!;

  @override
  Future<String?> findFolder(List<String> path) => _folder(path, create: false);

  Future<String?> _folder(List<String> path, {required bool create}) {
    final run = _folderQueue.then((_) => _resolveFolder(path, create: create));
    _folderQueue = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<String?> _resolveFolder(List<String> path, {required bool create}) async {
    final key = path.join('/');
    final cached = _folderCache[key];
    if (cached != null) return cached;
    String? parent = 'root';
    for (final name in path) {
      final under = parent!;
      parent = await _call<String?>((api) async {
        final escaped = name.replaceAll("'", "\\'");
        final found = await api.files.list(
          q: "mimeType = 'application/vnd.google-apps.folder' and name = '$escaped' and '$under' in parents and trashed = false",
          $fields: 'files(id)',
          pageSize: 10,
        );
        final existing = found.files ?? const <drive.File>[];
        if (existing.isNotEmpty) return existing.first.id!;
        if (!create) return null;
        final created = await api.files.create(
          drive.File(name: name, mimeType: 'application/vnd.google-apps.folder', parents: [under]),
          $fields: 'id',
        );
        return created.id!;
      });
      if (parent == null) return null;
    }
    _folderCache[key] = parent!;
    return parent;
  }

  @override
  Future<CloudFile> upload(String folderId, String name, Stream<List<int>> data, int length, String mime) =>
      _call((api) async => _file(await api.files.create(
            drive.File(name: name, parents: [folderId]),
            uploadMedia: drive.Media(data, length, contentType: mime),
            uploadOptions: length > 5 * 1024 * 1024 ? drive.ResumableUploadOptions() : drive.UploadOptions.defaultOptions,
            $fields: _fields,
          )), timeout: _transferTimeout);

  @override
  Future<void> downloadToFile(String fileId, File target, {void Function(int received, int? total)? onProgress}) =>
      _call((api) async {
        final media = await api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
        final sink = target.openWrite();
        var received = 0;
        try {
          await sink.addStream(onProgress == null
              ? media.stream
              : media.stream.map((chunk) {
                  received += chunk.length;
                  onProgress(received, media.length);
                  return chunk;
                }));
        } finally {
          await sink.close();
        }
      }, timeout: _transferTimeout);

  @override
  Future<CloudFile?> metadata(String fileId) async {
    try {
      return await _call((api) async => _file(await api.files.get(fileId, $fields: _fields) as drive.File));
    } on CloudError catch (e) {
      if (e.kind == 'not_found') return null;
      rethrow;
    }
  }

  @override
  Future<CloudFile?> findByName(String folderId, String name) => _call((api) async {
        final escaped = name.replaceAll("'", "\\'");
        final found = await api.files.list(
          q: "name = '$escaped' and '$folderId' in parents and trashed = false",
          $fields: 'files($_fields)',
          pageSize: 5,
        );
        final files = found.files ?? const <drive.File>[];
        return files.isEmpty ? null : _file(files.first);
      });

  @override
  Future<void> delete(String fileId) async {
    try {
      await _call((api) => api.files.delete(fileId));
    } on CloudError catch (e) {
      if (e.kind != 'not_found') rethrow; // 已經不在了,就是我們要的結果
    }
  }
}
