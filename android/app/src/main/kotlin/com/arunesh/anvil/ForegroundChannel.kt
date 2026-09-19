package com.arunesh.anvil

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Handles the `anvil/foreground` platform channel: `start {label}` / `stop`.
 *
 * Starting a foreground service is what keeps a long on-device job (LLM turn,
 * ffmpeg transcode, model download) running after the user switches apps —
 * without it the process is frozen when cached and killed early under memory
 * pressure. The service holds no work itself; the work stays in the Flutter
 * isolate and its native threads.
 */
object ForegroundChannel {
    const val NAME = "anvil/foreground"

    private const val NOTIFICATION_PERMISSION_REQUEST = 4711

    fun register(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val label = call.argument<String>("label") ?: "Working…"
                    requestNotificationPermission(activity)
                    start(activity, label)
                    result.success(null)
                }
                "stop" -> {
                    stop(activity)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun start(context: Context, label: String) {
        val intent = Intent(context, KeepAliveService::class.java).apply {
            action = KeepAliveService.ACTION_START
            putExtra(KeepAliveService.EXTRA_LABEL, label)
        }
        context.startForegroundService(intent)
    }

    private fun stop(context: Context) {
        context.stopService(Intent(context, KeepAliveService::class.java))
    }

    /**
     * Android 13+ hides an FGS notification without POST_NOTIFICATIONS. The
     * service still runs when the user declines — the ask is so the ongoing
     * "Anvil is working" notification is visible, not a precondition.
     */
    private fun requestNotificationPermission(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) return
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }
}
