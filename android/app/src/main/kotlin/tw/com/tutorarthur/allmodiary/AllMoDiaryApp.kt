package tw.com.tutorarthur.allmodiary

import android.app.Application
import android.util.Log
import java.io.File

/**
 * 原生層的當機捕捉:未捕捉的例外發生的當下,把堆疊寫進不會被備份的
 * 資料夾,下次開 App 時由 Dart 讀出來(DiagnosticsChannel.takeNativeCrash)放進記錄檔。
 * 寫完交回系統原本的處理方式(照常結束 App)。
 */
class AllMoDiaryApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val text = "time=${System.currentTimeMillis()} thread=${thread.name}\n" + Log.getStackTraceString(error)
                File(noBackupFilesDir, CRASH_FILE).writeText(text.take(MAX_CRASH_CHARS))
            } catch (_: Throwable) {
            }
            previous?.uncaughtException(thread, error)
        }
    }

    companion object {
        const val CRASH_FILE = "native_crash.txt"
        const val MAX_CRASH_CHARS = 512 * 1024
    }
}
