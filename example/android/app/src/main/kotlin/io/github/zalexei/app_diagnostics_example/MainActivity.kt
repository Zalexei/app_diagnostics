package io.github.zalexei.app_diagnostics_example

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Crash lab: kills the process on purpose so the next launch can show the
 * ApplicationExitInfo record. Work is posted to the main looper so the
 * exception escapes the method channel and reaches the default handler.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app_diagnostics_example/crash_lab")
            .setMethodCallHandler { call, result ->
                val main = Handler(Looper.getMainLooper())
                when (call.method) {
                    // Blocks the main thread; the next touch makes the system declare an ANR.
                    "anr" -> main.postDelayed({ Thread.sleep(60_000) }, 300)
                    "oom" -> main.postDelayed({
                        val hog = ArrayList<ByteArray>()
                        while (true) hog.add(ByteArray(16 shl 20))
                    }, 300)
                    "javaCrash" -> main.postDelayed({
                        throw IllegalStateException("crash_lab: Java crash on purpose")
                    }, 300)
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                }
                result.success(null)
            }
    }
}
