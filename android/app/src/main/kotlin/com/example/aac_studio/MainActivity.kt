package com.example.aac_studio

import android.app.ActivityManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // "Lock the app on the screen": Android screen pinning, started and
    // stopped from Settings > Caregiver (lib/engine/app_lock.dart).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aac_studio/app_lock")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            startLockTask()
                            result.success(true)
                        }
                        "stop" -> {
                            stopLockTask()
                            result.success(true)
                        }
                        "active" -> {
                            val manager =
                                getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                            result.success(
                                manager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
                            )
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.success(false)
                }
            }
    }
}
