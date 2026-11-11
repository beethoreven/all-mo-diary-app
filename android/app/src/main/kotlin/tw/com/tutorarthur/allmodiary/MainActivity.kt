package tw.com.tutorarthur.allmodiary

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DiagnosticsChannel(applicationContext).register(flutterEngine.dartExecutor.binaryMessenger)
    }
}
