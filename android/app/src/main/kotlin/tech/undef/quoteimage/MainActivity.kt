package tech.undef.quoteimage

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import org.brotli.dec.BrotliInputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "tech.undef.quoteimage/brotli",
        ).setMethodCallHandler { call, result ->
            if (call.method != "decompress") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val input = call.arguments as? ByteArray
            if (input == null) {
                result.error("invalid_input", "Brotli input must be bytes", null)
                return@setMethodCallHandler
            }
            Thread {
                try {
                    val output = BrotliInputStream(ByteArrayInputStream(input)).use {
                        it.readBytes()
                    }
                    runOnUiThread { result.success(output) }
                } catch (error: Exception) {
                    runOnUiThread {
                        result.error("brotli_error", error.message, null)
                    }
                }
            }.start()
        }
    }
}
