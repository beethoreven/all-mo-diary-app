package tw.com.tutorarthur.allmodiary

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 給意見回饋用的除錯資訊。只取需要的那幾項;不取 IMEI、序號、
 * 廣告 ID、位置、其他 App 清單。
 */
class DiagnosticsChannel(private val context: Context) {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "tw.com.tutorarthur.allmodiary/diagnostics").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "noBackupDir" -> result.success(context.noBackupFilesDir.absolutePath)
                    "device" -> result.success(device())
                    "state" -> result.success(state())
                    "exitReasons" -> result.success(exitReasons())
                    "takeNativeCrash" -> result.success(takeNativeCrash())
                    "logcat" -> result.success(logcat(call.argument<Int>("lines") ?: 500))
                    "debugCrashNative" -> {
                        result.success(null)
                        if (BuildConfig.DEBUG) Handler(Looper.getMainLooper()).post { throw RuntimeException("debug native crash") }
                    }
                    "debugHangMainThread" -> {
                        result.success(null)
                        if (BuildConfig.DEBUG) Handler(Looper.getMainLooper()).post { Thread.sleep(20_000) }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                result.error("diagnostics_failed", e.javaClass.simpleName, null)
            }
        }
    }

    private fun device(): Map<String, Any?> = mapOf(
        "manufacturer" to Build.MANUFACTURER,
        "brand" to Build.BRAND,
        "model" to Build.MODEL,
        "release" to Build.VERSION.RELEASE,
        "sdk" to Build.VERSION.SDK_INT,
        "build" to Build.DISPLAY,
    )

    private fun state(): Map<String, Any?> {
        val stat = StatFs(context.filesDir.path)
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val plugged = battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork)
        val network = when {
            caps == null -> "none"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "other"
        }
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mem = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        return mapOf(
            "storage_free_mb" to stat.availableBytes / (1024 * 1024),
            "storage_total_mb" to stat.totalBytes / (1024 * 1024),
            "battery_percent" to if (level >= 0 && scale > 0) level * 100 / scale else null,
            "charging" to (plugged != 0),
            "power_save" to power.isPowerSaveMode,
            "battery_optimized" to !power.isIgnoringBatteryOptimizations(context.packageName),
            "data_saver" to (cm.restrictBackgroundStatus == ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED),
            "network" to network,
            "memory_available_mb" to mem.availMem / (1024 * 1024),
            "low_memory" to mem.lowMemory,
        )
    }

    /** 上次結束的原因(Android 11 起)。無回應的追蹤資料 Android 11 起、原生當機的 Android 12 起。 */
    private fun exitReasons(): List<Map<String, Any?>> {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val abnormal = setOf(
            ApplicationExitInfo.REASON_CRASH,
            ApplicationExitInfo.REASON_CRASH_NATIVE,
            ApplicationExitInfo.REASON_ANR,
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE,
        )
        return am.getHistoricalProcessExitReasons(context.packageName, 0, 5).map { info ->
            val trace: String? = try {
                info.traceInputStream?.use { stream ->
                    val bytes = stream.readBytes().take(MAX_TRACE).toByteArray()
                    if (info.reason == ApplicationExitInfo.REASON_ANR) String(bytes)
                    else "base64:" + Base64.encodeToString(bytes.take(MAX_NATIVE_TRACE).toByteArray(), Base64.NO_WRAP)
                }
            } catch (_: Throwable) {
                null
            }
            mapOf(
                "timestamp" to info.timestamp,
                "reason" to reasonName(info.reason),
                "status" to info.status,
                "importance" to info.importance,
                "abnormal" to (info.reason in abnormal),
                "trace" to trace,
            )
        }
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_ANR -> "anr"
        ApplicationExitInfo.REASON_CRASH -> "crash"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "crash_native"
        ApplicationExitInfo.REASON_EXIT_SELF -> "exit_self"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "init_failure"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "low_memory"
        ApplicationExitInfo.REASON_SIGNALED -> "signaled"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "user_requested"
        ApplicationExitInfo.REASON_USER_STOPPED -> "user_stopped"
        ApplicationExitInfo.REASON_OTHER -> "other"
        else -> "code_$reason"
    }

    private fun takeNativeCrash(): String? {
        val f = File(context.noBackupFilesDir, DiaryApp.CRASH_FILE)
        if (!f.exists()) return null
        val text = f.readText()
        f.delete()
        return text
    }

    /** 只取我們自己、Flutter、Android 當機這幾個標籤的最後幾行(App 只讀得到自己的記錄)。 */
    private fun logcat(lines: Int): String {
        val process = ProcessBuilder(
            "logcat", "-d", "-t", lines.coerceIn(1, 500).toString(), "-v", "threadtime",
            "flutter:V", "MamaFufood:V", "AndroidRuntime:E", "DEBUG:V", "*:S",
        ).redirectErrorStream(true).start()
        val out = process.inputStream.bufferedReader().use { it.readText() }
        process.waitFor()
        return out.takeLast(MAX_LOGCAT_CHARS)
    }

    companion object {
        const val MAX_TRACE = 512 * 1024
        const val MAX_NATIVE_TRACE = 96 * 1024
        const val MAX_LOGCAT_CHARS = 200 * 1024
    }
}
