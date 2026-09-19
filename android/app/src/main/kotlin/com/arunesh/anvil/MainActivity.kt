package com.arunesh.anvil

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        ImageChannel.register(this, messenger)
        PdfChannel.register(this, messenger)
        ForegroundChannel.register(this, messenger)
    }
}
