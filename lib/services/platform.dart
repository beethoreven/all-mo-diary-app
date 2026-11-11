import 'package:flutter/services.dart';

/// App 自己的原生程式(android/app/src/main/kotlin/.../DiagnosticsChannel.kt)。
///
/// 只取除錯需要的那幾項:機型與系統、螢幕、儲存空間、電量、省電與電池最佳化、
/// 網路類型、上次結束原因。**不取** IMEI、序號、廣告 ID、位置、其他 App 清單。
class PlatformInfo {
  PlatformInfo._();

  static const _channel = MethodChannel('tw.com.tutorarthur.allmodiary/diagnostics');

  /// files 以外、不會被 Android 自動備份的資料夾(診斷記錄、待送的意見回饋、安裝 ID)。
  static Future<String> noBackupDir() async => (await _channel.invokeMethod<String>('noBackupDir'))!;

  static Future<Map<String, Object?>> device() async =>
      (await _channel.invokeMapMethod<String, Object?>('device')) ?? const {};

  static Future<Map<String, Object?>> state() async =>
      (await _channel.invokeMapMethod<String, Object?>('state')) ?? const {};

  /// 上次結束的原因(Android 11 起的 ApplicationExitInfo),最多幾筆,含追蹤資料摘要。
  static Future<List<Map<String, Object?>>> exitReasons() async {
    final list = await _channel.invokeListMethod<Object?>('exitReasons') ?? const [];
    return [for (final e in list) (e as Map).cast<String, Object?>()];
  }

  /// 原生層當機時寫下的檔案(下次開啟時讀出來,讀完刪掉)。
  static Future<String?> takeNativeCrash() => _channel.invokeMethod<String>('takeNativeCrash');

  /// 只讀我們自己、Flutter、Android 當機這幾個標籤的最後幾行 logcat。
  static Future<String> logcat(int lines) async =>
      await _channel.invokeMethod<String>('logcat', {'lines': lines}) ?? '';

  /// debug 版才有的除錯工具:故意讓原生層當機、故意卡住主執行緒(無回應)。release 版裡沒有。
  static Future<void> debugCrashNative() => _channel.invokeMethod('debugCrashNative');

  static Future<void> debugHangMainThread() => _channel.invokeMethod('debugHangMainThread');
}
