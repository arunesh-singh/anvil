package com.arunesh.anvil

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Ongoing-notification service that exists purely to keep this process in the
 * foreground importance bucket while Anvil runs a long on-device job.
 *
 * It runs no work of its own: the job lives in the Flutter isolate (and the
 * native threads the engines spawn), which the OS would otherwise freeze or
 * reclaim once the user switches apps. `dataSync` is the applicable
 * foreground-service type for local processing; Android 15+ caps such
 * services at ~6 h/day, far beyond any single Anvil job.
 */
class KeepAliveService : Service() {
    companion object {
        const val ACTION_START = "com.arunesh.anvil.KEEP_ALIVE"
        const val EXTRA_LABEL = "label"

        private const val CHANNEL_ID = "anvil_jobs"
        private const val NOTIFICATION_ID = 1201
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val label = intent?.getStringExtra(EXTRA_LABEL) ?: "Working…"
        val notification = buildNotification(label)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // The job is owned by the Dart side: a restarted service would hold a
        // notification over work that no longer exists.
        return START_NOT_STICKY
    }

    private fun buildNotification(label: String): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Running tasks",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shown while Anvil finishes a task in the background."
                    setShowBadge(false)
                },
            )
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Anvil")
            .setContentText(label)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }
}
