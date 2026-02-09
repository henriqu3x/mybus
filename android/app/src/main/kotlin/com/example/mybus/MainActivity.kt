package com.example.mybus

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "foreground_location"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val intent = Intent(this, LocationForegroundService::class.java)
                    startForegroundService(intent)
                    result.success(null)
                }

                "stopService" -> {
                    val intent = Intent(this, LocationForegroundService::class.java)
                    stopService(intent)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }
}