package com.example.accessible_media_recorder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val SERVICE_CHANNEL = "acc_rec/foreground_service"
    private val SCREEN_CHANNEL = "acc_rec/screen_events"
    private var screenChannel: MethodChannel? = null
    private var screenReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SERVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val intent = Intent(this, RecordingForegroundService::class.java)
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, RecordingForegroundService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        screenChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_ON -> screenChannel?.invokeMethod("screenOn", null)
                    Intent.ACTION_SCREEN_OFF -> screenChannel?.invokeMethod("screenOff", null)
                }
            }
        }
        registerReceiver(screenReceiver, filter)
    }

    override fun onDestroy() {
        screenReceiver?.let { unregisterReceiver(it) }
        screenReceiver = null
        super.onDestroy()
    }
}
