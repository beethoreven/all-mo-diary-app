import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:allmodiary/services/drive_store.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// 測試用的假雲端硬碟:App 專用區與使用者看得到的資料夾都放在記憶體裡。
class FakeCloud implements CloudStore {
  final Map<String, FakeEntry> files = {};
  var _next = 0;
  bool offline = false;

  /// 下載永遠不回應(模擬網路卡住)。
  bool hangDownloads = false;

  void _check() {
    if (offline) throw const CloudError('network', '無法連上 Google 雲端硬碟，請確認網路後再試');
  }

  String _id() => 'f${_next++}';

  @override
  Future<List<CloudFile>> listAppData(String namePrefix) async {
    _check();
    return [
      for (final e in files.entries)
        if (e.value.appData && e.value.name.startsWith(namePrefix)) e.value.toCloud(e.key),
    ];
  }

  @override
  Future<Uint8List> readAppData(String fileId) async {
    _check();
    final e = files[fileId];
    if (e == null) throw const CloudError('not_found', 'not found');
    return Uint8List.fromList(e.bytes);
  }

  @override
  Future<CloudFile> createAppData(String name, Uint8List bytes, {Map<String, String> props = const {}}) async {
    _check();
    final id = _id();
    files[id] = FakeEntry(name, bytes, Map.of(props), appData: true);
    return files[id]!.toCloud(id);
  }

  @override
  Future<CloudFile> updateAppData(String fileId, Uint8List bytes, {Map<String, String> props = const {}}) async {
    _check();
    final e = files[fileId];
    if (e == null) throw const CloudError('not_found', 'not found');
    e.bytes = bytes;
    e.props.addAll(props);
    return e.toCloud(fileId);
  }

  @override
  Future<String> folder(List<String> path) async {
    _check();
    return 'folder:${path.join('/')}';
  }

  @override
  Future<CloudFile> upload(String folderId, String name, Stream<List<int>> data, int length, String mime) async {
    _check();
    final bytes = <int>[];
    await for (final chunk in data) {
      bytes.addAll(chunk);
    }
    final id = _id();
    files[id] = FakeEntry(name, bytes, {}, appData: false, folder: folderId);
    return files[id]!.toCloud(id);
  }

  @override
  Future<void> downloadToFile(String fileId, File target) async {
    _check();
    if (hangDownloads) await Completer<void>().future;
    final e = files[fileId];
    if (e == null) throw const CloudError('not_found', 'not found');
    await target.writeAsBytes(e.bytes);
  }

  @override
  Future<CloudFile?> metadata(String fileId) async {
    _check();
    final e = files[fileId];
    return e?.toCloud(fileId);
  }

  @override
  Future<CloudFile?> findByName(String folderId, String name) async {
    _check();
    for (final e in files.entries) {
      if (!e.value.appData && e.value.folder == folderId && e.value.name == name) return e.value.toCloud(e.key);
    }
    return null;
  }

  @override
  Future<void> delete(String fileId) async {
    _check();
    files.remove(fileId);
  }
}

class FakeEntry {
  FakeEntry(this.name, this.bytes, this.props, {required this.appData, this.folder});

  final String name;
  List<int> bytes;
  final Map<String, String> props;
  final bool appData;
  final String? folder;

  CloudFile toCloud(String id) => CloudFile(id: id, name: name, size: bytes.length, props: Map.of(props));
}

/// 測試用的假 Google 登入：不會自動登入，Drive 權限直接給。
class FakeGoogle extends GoogleSignInPlatform with MockPlatformInterfaceMixin {
  @override
  Future<void> init(InitParameters params) async {}

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(AttemptLightweightAuthenticationParameters p) =>
      Future.value(null);

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) => throw UnimplementedError();

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
          ClientAuthorizationTokensForScopesParameters params) async =>
      const ClientAuthorizationTokenData(accessToken: 'drive');

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
          ServerAuthorizationTokensForScopesParameters params) async =>
      null;

  @override
  Future<void> clearAuthorizationToken(ClearAuthorizationTokenParams params) async {}

  @override
  Future<void> signOut(SignOutParams params) async {}

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}
