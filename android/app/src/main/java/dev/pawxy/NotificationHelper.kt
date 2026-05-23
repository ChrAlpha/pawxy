package dev.pawxy

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

class NotificationHelper(private val context: Context) {
    init {
        createChannel()
    }

    fun build(listen: String, wakeLockEnabled: Boolean): Notification {
        val text = if (wakeLockEnabled) {
            "HTTP + SOCKS5 on $listen · wake lock on"
        } else {
            "HTTP + SOCKS5 on $listen"
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        return builder
            .setContentTitle("Pawxy running")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_pawxy)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Pawxy",
            NotificationManager.IMPORTANCE_LOW
        )
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "pawxy"
        const val NOTIFICATION_ID = 1
    }
}
